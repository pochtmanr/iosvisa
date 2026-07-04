# M3 — Applications core workflow

**First read `ios/prompts/00-shared-context.md` and `ios/README.md`.** Build on
M1 + M2 in `ios/`. Verify with `xcodebuild build` + `test`.

## Goal

The end-to-end application experience up to (but not including) payment: a list
grouped by status, a new-application wizard, and a step-driven workspace
(details → documents → review → tracking) with a readiness gate and a status
timeline. Also build the real dashboard.

## Scope

### 1. Models + repository
- `Core/Models/VisaApplication.swift` (id, user_id, product_id, passport_iso2,
  destination_iso2, status `ApplicationStatus`, `applicant_details` JSON,
  timestamps) and `ApplicationStatusEvent` (timeline rows from
  `application_status_events`).
- `Core/Repositories/ApplicationRepository.swift`:
  - `list()` → user's `visa_applications` (RLS-scoped), newest first.
  - `create(productId:passport:destination:)` → insert `draft`.
  - `update(id:applicantDetails:)`, `setStatus(...)` where the user is allowed
    (e.g. draft→ready). For server-mediated transitions, rely on the backend;
    don't call service-role RPCs.
  - `timeline(applicationId:)` → `application_status_events` ordered.
  - `checklist(applicationId:)` → via `APIClient` GET
    `/api/applications/{id}/checklist` (needs bearer change from `08`), OR read
    `visa_document_requirements` for the product directly if simpler — match
    web behavior.

### 2. Applications list
- `Features/Applications/ApplicationsListView.swift` — sectioned by
  `ApplicationStatus.Bucket` (Needs action / In progress / Complete), each row a
  `Card` with destination flag+name, `StatusBadge`, last-updated. Empty state →
  CTA to the visa checker. Pull-to-refresh.

### 3. New-application wizard
- `Features/Applications/NewApplicationFlow.swift` — entry either from a
  destination (prefilled passport+destination+product from M2) or cold:
  1. Pick destination (search countries).
  2. Pick passport (from vault).
  3. Pick visa type/product (resolved options from `VisaRepository`).
  Confirm → `create(...)` → open the workspace.

### 4. Step workspace
- `Features/Applications/ApplicationWorkspaceView.swift` — a step rail driven by
  a readiness model (mirror web's step-driven workspace + readiness gate, S08):
  - **Details** — `DetailsFormView`: applicant fields **prefilled from the
    profile vault** (legal name, DOB, place of birth, gender, passport
    number/expiry, phone, trip dates). Persist to `applicant_details`.
  - **Documents** — checklist of required/optional items with a ready/total
    progress bar. (Attaching real files is M4; here render the checklist and the
    gate.) Required items must be satisfied to reach "ready".
  - **Review** — read-only summary.
  - **Payment** — entry point (the actual checkout is M5; here show the CTA +
    fee preview, disabled until `ready`).
  - **Tracking** — visible after payment: status timeline from
    `application_status_events` + activity. For assisted cases, a messages entry
    (M6). For self-service, the package (M6).
- Readiness logic: a pure function `readiness(application:checklist:profile:)`
  returning per-step completion + the overall gate. Unit-test it.

### 5. Real dashboard (replace M0 placeholder)
- `Features/Dashboard/DashboardView.swift` — featured **active applications**,
  a **profile-completeness ring**, documents count, and an "explore
  destinations" CTA. Mirror web `/app` (S dashboard redesign): featured Active
  applications + completeness ring; no "next steps"/"expirations" widgets.

## Web parity references
- `web/src/app/(app)/app/applications/**` (list, new, `[id]` workspace, checklist),
  `web/src/app/(app)/app` dashboard, `web/docs/marketplace/CONTRACT.md` (status
  machine), `web/supabase/migrations/0048_*` (`ready` enum / readiness).

## Tests
- Unit-test `readiness(...)`, the status→bucket grouping (already partly
  covered), and the vault→`applicant_details` prefill mapping.

## Definition of done
- Build + tests green. A user can create an application from a destination,
  fill details (prefilled), see the document checklist + readiness gate, reach
  "ready", and view the tracking timeline — all against the live project under
  RLS.
- Dashboard reflects the user's real applications + completeness.
- Update `ios/README.md` M3 checkbox.
