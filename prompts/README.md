# VisaPilot iOS — build prompts

Paste-ready prompts to build the iOS app to **full parity**, one milestone at a
time. M0 (foundation) is already implemented and verified in `ios/`.

## How to use

1. Open a Claude Code session **in the repo root** (`/Users/roman/Developer/VisaApplication`).
2. Paste the contents of one `NN-*.md` file as your message (or say:
   "Execute `ios/prompts/01-m1-auth-profile.md`").
3. Each prompt tells Claude to first read `ios/prompts/00-shared-context.md` and
   `ios/README.md`, then implement that milestone and verify with `xcodebuild`.
4. Run them **in order** — later milestones build on earlier ones.

Each prompt is self-contained: goal, prerequisites, exact files to create,
data models, web-parity references, and a definition of done.

## Order

| File | Milestone | Needs first |
|------|-----------|-------------|
| `00-shared-context.md` | Shared context (read-only reference) | — |
| `08-backend-changes.md` | Web/Supabase additive changes (bearer auth, order route, AASA, Apple/Google providers) | do the auth-provider parts before M1; order route before M5 |
| `01-m1-auth-profile.md` | Auth (Apple/Google/email/magic-link) + onboarding + profile vault | Apple+Google provider config from `08` |
| `02-m2-discovery-map.md` | Passport-strength map + destinations | M1 |
| `03-m3-applications.md` | Applications list + new wizard + step workspace | M1, M2 |
| `04-m4-documents.md` | Document vault (Storage upload/attach) | M3 |
| `05-m5-payments.md` | Revolut checkout + billing | M3, order route from `08` |
| `06-m6-messaging-pdf.md` | Realtime case thread + PDF package | M3 |
| `07-m7-polish-ship.md` | States, a11y, App Store assets, TestFlight | all |

## What you (Roman) must provide out-of-band

These need an Apple Developer account / Google Cloud console and can't be done
in code:

- **Apple:** enable the Apple provider in Supabase Auth; create a Sign-in-with-
  Apple Services ID + key; set your **Team ID** in `ios/project.yml`.
- **Google:** create an **iOS OAuth client ID**; put it in
  `ios/Config/Secrets.xcconfig` (`GOOGLE_IOS_CLIENT_ID`).
- **Universal Links / Revolut return:** host the AASA file (see `08`).

The email + magic-link path and all data features need none of the above, so
M1's email flow and M2–M4/M6 can proceed before the Apple/Google config lands.
