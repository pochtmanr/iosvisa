# Backend changes for iOS (additive — no user-data schema changes)

**First read `ios/prompts/00-shared-context.md`.** These are small, additive
changes to `web/` and the Supabase project so the native client can authenticate
and reach the few server-only routes. Do them in pieces as the milestones need
them (auth-provider parts before M1; order route before M5).

## Goal

Let iOS (1) sign in with Apple/Google/email and (2) call the owner-scoped
Next.js API routes with a Bearer JWT, without breaking the existing
cookie-based web auth.

## 1. Bearer-token auth helper (needed by M3, M5, M6)

The web API routes authenticate via `@supabase/ssr` cookies. Add a helper that
**also** accepts `Authorization: Bearer <jwt>`.

- Add `web/src/lib/auth/bearer.ts` (or extend `web/src/lib/auth/dal.ts`):
  `getUserFromRequest(req)` → returns the authenticated user by trying, in
  order: (a) the `Authorization: Bearer` token (build a Supabase client with the
  token and call `auth.getUser(token)`), then (b) the existing cookie session.
- Update these route handlers to use it (keep cookie behavior unchanged):
  - `web/src/app/api/applications/[id]/package/route.ts`
  - `web/src/app/api/applications/[id]/checklist/route.ts`
  - `web/src/app/api/documents/[id]/route.ts`
- **Verify:** existing web flows still work (cookie path), and a `curl` with a
  valid user JWT in the `Authorization` header returns that user's data; an
  invalid/expired token returns 401.

## 2. Order / checkout creation endpoint (needed by M5)

Web creates the Revolut order inside a checkout server action. Expose an HTTP
route callable with a Bearer token.

- Add `POST web/src/app/api/orders/route.ts`:
  - Auth via the bearer helper from step 1.
  - Body: `{ application_id: string }`.
  - Reuse the **existing** Revolut order-creation + `orders` insert logic
    (S10 — find it in the checkout server action / `web/src/lib/payments/` or
    similar; do not duplicate fee math, call the existing function).
  - Set the Revolut order `redirect_url` to the iOS deep link when the request
    is from the app (see step 4): `visapilot://checkout/return?order={orderId}`.
  - Return `{ checkout_url, order_id }`.
- **Verify:** with a valid JWT and a `ready` application, the route returns a
  Revolut `checkout_url`; the `orders` row is created `pending`.

## 3. Supabase Auth providers (needed by M1 Apple/Google)

In the Supabase dashboard (Auth → Providers / URL configuration):
- **Apple:** enable provider; add the app **bundle ID** `com.visapilot.app` to
  the allowed client IDs (native `signInWithIdToken` validates the audience).
  Register a Services ID + Sign-in-with-Apple key in the Apple Developer portal.
- **Google:** ensure the provider is enabled; add the **iOS OAuth client ID** to
  the allowed client IDs so `signInWithIdToken(provider: .google)` is accepted.
- **URL configuration:** add the app's redirect target
  `visapilot://auth/callback` and the universal-link
  `https://visapilot.app/auth/callback` to the allowed redirect URLs (for
  magic-link + OAuth fallback).
- Set **`emailRedirectTo`** for magic links to the universal link
  `https://visapilot.app/auth/callback`.

## 4. Universal Links / deep-link return (needed by M1 magic-link, M5 Revolut)

- Add `web/public/.well-known/apple-app-site-association` (served as JSON, no
  extension, `Content-Type: application/json`), with the app's
  `appID = <TEAMID>.com.visapilot.app` and `paths` covering
  `/auth/callback`, `/checkout/return`, `/applications/*`.
- Ensure Next.js serves it untouched (it's in `public/`, so it is).
- The matching app side (entitlement `applinks:visapilot.app`, URL scheme
  `visapilot`) is already configured in `ios/VisaPilot/VisaPilot.entitlements`
  and `Info.plist`.
- For the Revolut return, branch the redirect: web sessions keep the existing
  web return URL; iOS-originated orders use the `visapilot://checkout/return`
  scheme (pass a `client=ios` flag from the app's order request, or always use
  the universal link which both can handle).

## Definition of done
- Web build + existing auth unaffected (cookie path regression-tested).
- Bearer helper unit-tested (valid / invalid / expired token).
- `POST /api/orders` returns a checkout URL for a paid-eligible application.
- AASA file reachable at `https://visapilot.app/.well-known/apple-app-site-association`.
- Supabase providers/redirects configured (note what was set in the PR/commit).

> Apply DB/config via the Supabase MCP tools (`apply_migration` / dashboard) per
> the project's standing access. No user-data schema changes are required here.
