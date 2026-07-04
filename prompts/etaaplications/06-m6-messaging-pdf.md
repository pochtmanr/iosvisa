# M6 — Messaging + PDF package

**First read `ios/prompts/00-shared-context.md` and `ios/README.md`.** Build on
M3 (and M5 for the paid gate) in `ios/`. Verify with `xcodebuild build` + `test`.

## Goal

Two post-payment features: a **Realtime case thread** per application (for
assisted cases with an agency), and the **PDF application package** (for
self-service), viewable in-app.

## Scope

### 1. Messaging
- `Core/Models/CaseMessage.swift` mirroring `case_messages` (id,
  application_id, author role user/agency/platform, kind
  text/file_request/file/system, body, created_at, read state).
- `Core/Repositories/MessageRepository.swift`:
  - `messages(applicationId:)` → ordered read (RLS scopes to the user's cases).
  - `send(applicationId:text:)` → PostgREST insert (allowed for the case owner
    under RLS). Do **not** call service-role RPCs; `markThreadRead` is
    service-role on web — for iOS, track unread client-side from `created_at`
    vs a locally stored last-read, or whatever RLS-safe field exists (confirm
    with `execute_sql`).
  - `subscribe(applicationId:)` → **Supabase Realtime** channel on
    `case_messages` filtered by `application_id`; yield inserts as an
    `AsyncStream` for the view model.
- `Features/Messages/CaseThreadView.swift` — chat UI (bubbles by author role,
  system events styled distinctly, file-request items), composer, auto-scroll,
  live updates via the subscription. Reachable from the workspace Tracking step
  and from a top-level **Inbox**.
- `Features/Messages/InboxView.swift` — list of threads (one per application
  with messages) with unread badges; a bell/badge on the tab.

### 2. PDF package
- `Core/Repositories/PackageRepository.swift`: `package(applicationId:)` →
  `APIClient` GET `/api/applications/{id}/package` (bearer) → `Data` (PDF). Gate
  on a paid order (or free-tier eligibility), matching web.
- `Features/Applications/PackageView.swift` — render the PDF with **PDFKit**
  (`PDFView`), with share/save (`UIActivityViewController`) and a download
  state. Surface it in the workspace Tracking step for self-service
  applications (`entry_type` drives self-vs-assisted, per web S09).

## Web parity references
- `web/src/app/(app)/app/messages/**`, `web/src/components/**` CaseThread/bell
  (S14), `web/src/app/api/applications/[id]/package/route.ts`,
  `web/src/app/(app)/app/applications/[id]/print/page.tsx`, `web/docs` S09/S14.
- Confirm `case_messages` columns + RLS (insert/select policies) and the
  unread mechanism with `list_tables` / `execute_sql`.

## Tests
- Unit-test the unread-count derivation and the author-role→bubble-style mapping.

## Definition of done
- Build + tests green. For an assisted application with a case, messages load,
  send, and **arrive live** in both directions vs the web (2-client check). For
  a self-service paid application, the PDF package fetches via bearer and renders
  in PDFKit, matching the web PDF.
- Update `ios/README.md` M6 checkbox.
