# VisaPilot iOS

Native SwiftUI client for VisaPilot. Mirrors the Next.js web app (`../web`) and
reuses the **same Supabase backend** (project `eujmomonscnlmwcbkbfy`): auth, the
passport-strength map / visa checker, the full eVisa/ETA application workflow,
document vault, messaging, billing, and the PDF package.

- **UI:** SwiftUI, iOS 17+, MVVM with `@Observable`, `async/await`.
- **Backend:** [`supabase-swift`](https://github.com/supabase/supabase-swift)
  (Auth, PostgREST, Storage, Realtime) directly against the existing project,
  gated by the same Row Level Security as the web client. A handful of
  server-only Next.js routes (PDF package, checklist, document download, order
  creation) are reached via a bearer-authenticated `APIClient`.
- **Auth (v1):** Sign in with Apple, Google, and email (password + magic link).
  Passkeys are deferred to v2 (Supabase needs a custom WebAuthn edge function).
- **Payments:** Revolut hosted checkout in `ASWebAuthenticationSession`
  (real-world service — no Apple IAP).

The project is generated from `project.yml` with **XcodeGen** — the
`.xcodeproj` is **not** committed (regenerate it instead).

## Prerequisites

- macOS with **Xcode 16+** installed (the build needs the iOS SDK; Command Line
  Tools alone are not enough).
- [XcodeGen](https://github.com/yonomi/XcodeGen): `brew install xcodegen`

## First-time setup

```bash
cd ios
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
# Edit Config/Secrets.xcconfig and fill in:
#   SUPABASE_ANON_KEY       (public anon key — same one the web bundle ships)
#   GOOGLE_IOS_CLIENT_ID    (iOS OAuth client from Google Cloud)
# SUPABASE_HOST is already set to the project host.

xcodegen generate          # creates VisaPilot.xcodeproj
open VisaPilot.xcodeproj    # Xcode resolves the SPM packages on first open
```

`Config/Secrets.xcconfig` is git-ignored. Only the public anon key belongs here
— **never** the service-role key.

## Build & test from the command line

If `xcode-select -p` points at Command Line Tools, target the full Xcode app
directly with `DEVELOPER_DIR` (no `sudo xcode-select` needed):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Build for the simulator
xcodebuild -project VisaPilot.xcodeproj -scheme VisaPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

# Run tests (unit + UI launch smoke)
xcodebuild -project VisaPilot.xcodeproj -scheme VisaPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

> **Editor note:** opening individual `.swift` files in a plain text editor (or
> a CLI SourceKit) before generating the project shows "No such module
> 'Supabase'" / "Cannot find 'Theme' in scope" errors. These are false
> positives — there is no module/SDK context without the generated project.
> The real `xcodebuild` compile (above) passes. Always validate via `xcodebuild`.

## Project layout

```
ios/
  project.yml                  # XcodeGen spec — source of truth for the project
  Config/                      # Base.xcconfig + Secrets.xcconfig(.example)
  VisaPilot/
    App/                       # @main, RootView gate, AuthStore, deep-link router
    DesignSystem/              # Palette/Theme/Typography/Layout + Components
    Core/
      Config/                  # AppConfig (reads Info.plist)
      Supabase/                # shared SupabaseClient
      Networking/              # APIClient (bearer auth to Next.js routes)
      Models/                  # Codable structs mirroring DB rows + enums
      Repositories/            # PostgREST/RPC wrappers per domain
    Features/                  # one folder per screen area
    Resources/                 # Geist fonts, asset catalog
  VisaPilotTests/              # pure-logic unit tests (headless-safe)
  VisaPilotUITests/            # launch smoke test
```

## Milestones

Implemented incrementally (see `../../.claude/plans/` for the full plan):

- **M0 — Foundation** ✅ design system, Supabase client, session wiring, app
  shell, deep-link router, build + tests green.
- **M1 — Auth + profile vault** ✅ Apple/Google/email/magic-link sign-in,
  session-driven routing (`/auth/resolve` parity as a non-blocking notice),
  three-step onboarding wizard, and full vault CRUD (Personal, Contact,
  Passports, Residencies, Family, Employment, Education, Travel history) via a
  reusable `VaultSectionView` + `DateField`/`CountryPicker`. *(Backend still
  needed for the social paths: enable the Apple provider, add
  `visapilot://auth/callback` to the Supabase redirect allowlist, and set
  `GOOGLE_IOS_CLIENT_ID` + its reversed-client-ID URL scheme. Email + magic
  link work with no extra config.)*
- **M2 — Discovery** ✅ a unified **Discover** tab with a Map / Browse toggle
  and shared passport selection: a real vector **passport-strength world map**
  (bundled `world-atlas-50m.json` TopoJSON, decoded + Equal-Earth-projected in
  pure Swift, shaded by best visa status across the selected passports, tap a
  country → detail), a searchable **destinations** gallery grouped by region,
  and a **destination detail** that resolves visa products for the primary
  passport (zone expansion + sparse eligibility-fold, mirroring web
  `loadDestinationVisaOptions`), grouped by purpose with eligibility/fees/
  processing, an online-vs-consular indicator, and a "Start application" hand-off
  to a stub M3 entry. Deep link `visapilot://visa-checker?passports=US,CA&to=DE`
  hydrates the selection and opens the destination. *(No backend change: all
  reads are public-catalog PostgREST + RLS. New unit tests cover the
  multi-passport status reducer, the eligibility fold, the TopoJSON decoder, and
  the projection.)*
- **M3 — Applications** ✅ the end-to-end pre-payment workflow: an
  **applications list** grouped by status bucket (Needs action / In progress /
  Complete) with pull-to-refresh and an empty-state CTA; a **new-application
  wizard** (from a discovery route, or cold: destination → passport → product)
  that seeds `applicant_details` from the profile vault and inserts a `draft`; a
  **step workspace** (Details → Documents → Review → Payment → Tracking) driven
  by a pure, unit-tested `ApplicationReadiness` gate — Details prefilled and
  confirmable, a document checklist (read straight from
  `visa_document_requirements`) with a ready/total bar + acknowledgment gate,
  the owner-allowed `draft`→`ready` transition unlocking payment (checkout is
  M5), and a Tracking timeline composed from `application_status_events` +
  honest future placeholders. The **dashboard** now shows featured active
  applications, a profile-completeness ring, a documents tile, and an explore
  CTA. *(No backend change: the checklist reads `visa_document_requirements`
  directly instead of the `/api/applications/{id}/checklist` route; all
  reads/writes stay within existing RLS — owner insert/update on
  `visa_applications`, read-only on `application_status_events`. New unit tests
  cover readiness + steps, the vault→`applicant_details` prefill, completeness,
  status→bucket grouping, and `applicant_details` round-trip.)*
- **M4 — Documents** — Storage upload/attach.
- **M5 — Payments** — Revolut hand-off + billing.
- **M6 — Messaging + PDF** — Realtime thread + PDFKit viewer.
- **M7 — Polish + ship** — states, a11y, TestFlight.

## Design system

Ported 1:1 from the web `visapilot-design` skill: monochrome ink-on-paper
neutrals, the seven status hues (saturated color reserved for visa-status
semantics only), Geist + Geist Mono (bundled from the repo's PDF font assets),
hairline structure (1px borders, 24px cards, no rest shadow), SF Symbols as the
line-icon substitute, and the "official decisions prevail" honesty disclaimer
wherever advice is shown.
```
