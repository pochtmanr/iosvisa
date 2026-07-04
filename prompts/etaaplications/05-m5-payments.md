# M5 — Payments (Revolut)

**First read `ios/prompts/00-shared-context.md` and `ios/README.md`.** Build on
M3 in `ios/`. Verify with `xcodebuild build` + `test`.

## Goal

Take a `ready` application through checkout: fee breakdown + consent → Revolut
hosted checkout in an in-app browser → deep-link return → order state polled to
`paid` → application advances. Plus a billing/receipts list. **No Apple IAP** —
visa services are real-world services, so external payment is allowed.

## Prerequisites
- `POST /api/orders` (order creation) + the Revolut redirect deep link from
  `08-backend-changes.md` (§2, §4). The bearer-auth helper (§1).

## Scope

### 1. Models + repository
- `Core/Models/Order.swift` mirroring `orders` (id, application_id,
  `service_fee_cents`, `gov_fee_cents`, currency, `state`
  pending/paid/failed/refunded/cancelled, `revolut_order_id`, `paid_at`,
  `consent_data_sharing_at`, timestamps).
- `Core/Repositories/OrderRepository.swift`:
  - `createCheckout(applicationId:)` → `APIClient` POST `/api/orders` →
    `{ checkout_url, order_id }`.
  - `order(id:)` → read `orders` row (RLS) for polling.
  - `list()` → user's orders for billing.

### 2. Checkout flow
- `Features/Payments/CheckoutView.swift` — fee table (gov fee estimate +
  platform service fee, transparent breakdown), the **mandatory** terms
  acceptance, and **data-sharing consent** (mandatory only for assisted-tier;
  match web). CTA "Continue to payment" enabled when consents are checked.
- On CTA: `createCheckout` → open `checkout_url` in
  **`ASWebAuthenticationSession`** with callback scheme `visapilot`. On the
  deep-link return (`DeepLinkRouter.Route.checkoutReturn(orderID:)`), close the
  session and start polling `order(id:)` until `state == .paid` (or
  failed/cancelled), with a sensible timeout + manual "I've paid, refresh".
- On `paid`: refresh the application (status → `paid`) and route to the
  workspace **Tracking** step. On failure: clear error + retry.

### 3. Billing
- `Features/Payments/BillingView.swift` — list of orders (newest first) with
  amount, currency, state badge, date; tap → `Features/Payments/ReceiptView.swift`
  with the breakdown and the linked application. Add to the Profile/Settings
  area or as its own destination.

## Web parity references
- `web/src/app/(app)/app/applications/[id]/checkout/page.tsx`,
  `web/src/app/(app)/app/billing/**`, `web/src/app/api/webhooks/revolut/route.ts`,
  `web/docs/PAYMENTS.md`, `web/supabase/migrations/0039_*`/`0040_*`.
- Note: server-side Revolut **webhook** is the source of truth for `paid`; the
  app polls the `orders` row as the client signal. Don't try to confirm payment
  client-side.

## Tests
- Unit-test the fee-formatting (cents→currency) and the consent-gate logic
  (which consents are required for assisted vs self-service).

## Definition of done
- Build + tests green. With Revolut **sandbox** keys configured server-side, a
  `ready` application opens the hosted checkout, a sandbox payment returns via
  the deep link, the `orders` row flips to `paid` (via webhook), the app polls
  and advances the application, and the receipt shows in billing. (Mirror the
  web S10 sandbox E2E.)
- Update `ios/README.md` M5 checkbox.
