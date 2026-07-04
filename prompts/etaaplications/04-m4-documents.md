# M4 — Document vault

**First read `ios/prompts/00-shared-context.md` and `ios/README.md`.** Build on
M3 in `ios/`. Verify with `xcodebuild build` + `test`.

## Goal

A reusable document vault: upload files once (private Supabase Storage),
organize them by document kind, and attach them to application checklist items —
which feeds the M3 readiness gate.

## Scope

### 1. Models + repository
- `Core/Models/UserDocument.swift` mirroring `user_documents` (id, label,
  `kind`/`document_kind`, `storage_path`, `expires_on`, `status`, timestamps).
  Add `DocumentKind` referencing the `document_kinds` catalog.
- `Core/Repositories/DocumentRepository.swift`:
  - `list()` → user's `user_documents` (RLS).
  - `upload(data:filename:kind:label:expiresOn:)` → upload bytes to the private
    **`user-docs`** Storage bucket via `client.storage.from("user-docs")` at a
    user-scoped path (e.g. `{user_id}/{uuid}-{filename}`), then insert the
    `user_documents` row. Report progress.
  - `download(document:)` → signed URL or bytes for preview (via Storage, or
    `APIClient` GET `/api/documents/{id}` for the server path).
  - `delete(document:)` → remove the row + storage object.
  - `attach(documentId:toApplication:checklistItem:)` /
    `detach(...)` → however the web links docs to an application's checklist
    (match the web schema — confirm with `execute_sql`; it may be a join table
    or a field on the checklist row).

### 2. Vault UI
- `Features/Documents/DocumentsView.swift` — list/grid of documents grouped by
  kind, each a `Card` with label, kind, expiry chip (warn if expiring), and a
  menu (preview / replace / delete). Empty state with an upload CTA.
- Upload flow: a sheet using `PhotosPicker` (images) **and**
  `.fileImporter` (PDFs/files); pick a `DocumentKind` + label + optional expiry;
  show upload progress; handle large files gracefully.
- Preview via `QuickLook` (`QLPreviewController`) for images/PDFs.

### 3. Wire into the application workspace (M3)
- In `Documents` step of `ApplicationWorkspaceView`: for each checklist item,
  let the user **attach an existing vault document** (matching `kind`) or
  **upload a new one** (which lands in the vault and attaches). Update the
  ready/total progress and the readiness gate.

## Web parity references
- `web/src/app/(app)/app/documents/**`,
  `web/supabase/migrations/0037_*`/`0038_*` (S07 document vault, private bucket),
  `web/src/lib/**` vault/audit helpers, `web/src/app/api/documents/[id]/route.ts`.
- Confirm the `user-docs` bucket name, the storage-path convention, and the
  doc↔checklist link with `list_tables` / `execute_sql`.

## Tests
- Unit-test the storage-path builder and the kind↔checklist matching logic.

## Definition of done
- Build + tests green. A user can upload an image and a PDF to the vault
  (verify they appear in the **web** vault for the same account → confirms the
  bucket + RLS path), preview them, attach one to an application checklist item,
  and watch the M3 readiness gate update.
- Update `ios/README.md` M4 checkbox.
