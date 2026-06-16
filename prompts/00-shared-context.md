# Shared context — VisaPilot iOS

> **Every milestone prompt assumes this file.** Read it (and `ios/README.md`)
> before executing any `NN-*.md` prompt. It is the single source of truth for
> the backend, conventions, design system, and build commands.

## What we're building

A **native SwiftUI iOS app** in `ios/`, mirroring the Next.js web app in `web/`
with **full end-user parity**. It reuses the **same Supabase project**
(`eujmomonscnlmwcbkbfy`) — no new backend except a few small additive changes
(see `08-backend-changes.md`).

### Locked decisions
- **Scope:** full parity (auth, passport-strength map, destinations, full
  application workflow, document vault, payments, messaging, billing, PDF).
- **Auth:** Sign in with Apple + Google + email (password **and** magic link).
  **Passkeys are deferred to v2** (Supabase has no native WebAuthn).
- **Payments:** Revolut hosted checkout via `ASWebAuthenticationSession`
  (real-world service — **no Apple IAP**).
- **Repo:** monorepo — iOS lives in `ios/` next to `web/`.

## Architecture

Two backend channels:

1. **Direct to Supabase** (default for everything RLS-protected). The signed-in
   user's JWT authorizes PostgREST reads/writes, Storage, and Realtime. Use
   `SupabaseClientProvider.shared` through a **Repository** per domain. Mirror
   the web's read logic — it's plain PostgREST against the same tables.
2. **Next.js API routes** for server-only ops, via the bearer-auth `APIClient`:
   PDF package, per-application checklist, document download, order creation.
   (Needs the bearer-token backend change — `08-backend-changes.md`.)

**Layering:** `View` → `@Observable` view model → `Repository` → SDK/APIClient.
Views never touch the SDK directly. Models are `Codable` structs with
snake_case `CodingKeys`.

## Key backend facts (from the web app)

- **Project:** `eujmomonscnlmwcbkbfy.supabase.co`. RLS gates everything; the app
  only ever sees the signed-in user's rows. Public-read catalog tables need no
  auth.
- **Public-read tables:** `countries`, `visa_types`, `visa_products`,
  `visa_product_eligibility`, `visa_zones`, `visa_zone_members`,
  `country_visa_availability`, `visa_document_requirements`, `document_kinds`,
  `document_guides`, `visa_requirements` (bilateral passport→destination matrix).
- **Owner-only tables:** `profiles`, `passports`, `residencies`,
  `education_entries`, `employment_entries`, `family_members`, `travel_entries`,
  `background_declarations`, `visa_applications`, `user_documents`, `orders`,
  `order_events`, `held_visas` (permits the user holds).
- **Case/marketplace (read + limited write under RLS):** `case_messages`
  (Realtime), `application_status_events` (timeline), `case_offers`. The
  service-role RPCs (`dispatch_offers`, `claim_offer`, etc.) run server-side
  from cron/webhooks — **iOS never calls them**, it only observes the resulting
  status via Realtime/polling.
- **Eligibility logic to mirror:** `web/src/lib/visa-products.ts`
  → `loadDestinationVisaOptions(passportIso2, destinationIso2)` returns the
  resolved products (zone expansion via `visa_zone_members`, sparse overrides
  from `visa_product_eligibility`). Baseline regime is `visa_requirements`.
- **Status machine:** canonical `ApplicationStatus` (already modelled in
  `Core/Models/Enums.swift`). Legacy values map on decode.
- **Auth roles:** end-user (`traveler`) vs `agency_members` vs `admin_users`.
  Roles are **not** in the JWT — query the tables at runtime, like web's
  `/auth/resolve` (`web/src/app/auth/resolve/route.ts`,
  `web/src/lib/auth/portals.ts`). Agency/admin portals stay **web-only** for
  v1; iOS routes everyone to the end-user app.

### Web parity reference files (read-only, for matching behavior)
- `web/src/lib/visa-products.ts`, `web/src/lib/supabase/types.ts`
- `web/src/lib/auth/portals.ts`, `web/src/lib/auth/types.ts`, `web/src/lib/auth/dal.ts`
- `web/src/components/checker/CheckerFlow.tsx`, `web/src/app/visa-checker/page.tsx`
- `web/src/app/(app)/app/**` (all end-user screens)
- `web/docs/DATABASE.md`, `web/docs/PAYMENTS.md`, `web/docs/marketplace/CONTRACT.md`
- Supabase types on demand: `mcp__plugin_supabase_supabase__execute_sql` /
  `list_tables` (project `eujmomonscnlmwcbkbfy`). Do NOT trust `list_migrations`
  for raw-DDL migrations; verify schema with `execute_sql`.

## Design system (already ported — reuse it, don't reinvent)

Located in `ios/VisaPilot/DesignSystem/`. Ported 1:1 from the web
`visapilot-design` skill. **Use these; never hardcode colors/fonts.**
- `Theme.*` — neutral ink-on-paper spine (`Theme.ink`, `.inkMuted`, `.bg`,
  `.surface`, `.border`, …).
- `StatusHue` — the seven status hues (`.green .teal .blue .yellow .orange
  .red .purple`) with `.solid` / `.softBg` / `.softFg`. **Saturated color is
  reserved for visa-status semantics only.**
- `Typography` + `.typography(_:)` / `.typeRole(_:)` — Geist scale.
- `Spacing`, `Radius`, `Hairline` — 1px borders, 24px cards, no rest shadow.
- Components: `Card`, `PrimaryButton`, `SecondaryButton`, `StatusBadge`,
  `StatusDot`, `Eyebrow`, `AdvisoryDisclaimer`.
- **Copy honesty:** never promise approval — "eligible / may be eligible /
  requires review". Show `AdvisoryDisclaimer` wherever advice is given.
- Icons: **SF Symbols** (line, ~1.5 weight). Emoji only for flags
  (`Country.flag`).
- Motion: calm fade-ups + press-shrink (`PressShrinkStyle`). No bounces/loops.

## Conventions

- **iOS 17+**, Swift 6 **strict concurrency is ON**. Annotate `@MainActor` on
  view models; `Sendable` on models; use `nonisolated(unsafe)` for
  configure-once statics (e.g. formatters) — see `APIClient.swift`.
- Use `@Observable` (Observation framework), not `ObservableObject`.
- One folder per feature under `Features/`. Repositories under
  `Core/Repositories/`. Models under `Core/Models/`.
- Add new files under `VisaPilot/` — XcodeGen picks them up automatically on the
  next `xcodegen generate` (the `.xcodeproj` is git-ignored).
- Keep view models thin and testable; put pure logic in funcs covered by
  `VisaPilotTests` (headless-safe — no network).

## Build & verify (ALWAYS validate this way)

Full Xcode.app is installed but not selected — target it via `DEVELOPER_DIR`:

```bash
cd ios
xcodegen generate   # after adding/removing files
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Build
xcodebuild -project VisaPilot.xcodeproj -scheme VisaPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

# Test
xcodebuild -project VisaPilot.xcodeproj -scheme VisaPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

> **CLI SourceKit / editor diagnostics like "No such module 'Supabase'" or
> "Cannot find 'Theme' in scope" are FALSE POSITIVES** when viewing files
> without the generated project. Trust only `xcodebuild`. A milestone is "done"
> only when `xcodebuild build` AND `test` succeed.

## Definition of done (every milestone)
1. `xcodebuild build` succeeds (no errors).
2. `xcodebuild test` succeeds (existing tests stay green; add tests for new pure
   logic).
3. New screens use the design system, handle loading/empty/error states, and
   show the advisory disclaimer where advice is given.
4. No service-role key anywhere in the app; all data access stays within RLS.
5. Update `ios/README.md`'s milestone checklist and note any backend change that
   was required.
