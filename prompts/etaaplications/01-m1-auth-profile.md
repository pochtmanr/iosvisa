# M1 — Auth + profile vault

**First read `ios/prompts/00-shared-context.md` and `ios/README.md`.** Then
implement this milestone in `ios/`, building on the M0 foundation. Verify with
`xcodebuild build` and `test` (see shared context for commands). Work in small
steps; keep the build green.

## Goal

Real sign-in (Apple, Google, email password + magic link), session-driven
routing matching web's `/auth/resolve`, an onboarding wizard, and full
profile-vault CRUD. After this, a user can sign in, complete onboarding, and
manage their profile/passports/etc.

## Prerequisites
- For Apple/Google: the provider config from `08-backend-changes.md` (§3) and
  `GOOGLE_IOS_CLIENT_ID` in `Config/Secrets.xcconfig`. **Email + magic link need
  nothing extra — build that path first** and stub Apple/Google until creds land.

## Scope

### 1. Auth service + AuthStore wiring
- Add `Features/Auth/AuthService.swift` wrapping `SupabaseClientProvider.shared.auth`:
  - `signInWithApple(idToken:nonce:)` → `auth.signInWithIdToken(credentials:
    .init(provider: .apple, idToken:, nonce:))`.
  - `signInWithGoogle(idToken:accessToken:)` → `signInWithIdToken(provider:.google …)`.
  - `signUpEmail(email:password:)`, `signInEmail(email:password:)`,
    `sendMagicLink(email:)` (`auth.signInWithOTP(email:, redirectTo:
    visapilot://auth/callback)`), `resetPassword(email:)`.
  - `completeAuthCallback(url:)` → `auth.session(from: url)` /
    `exchangeCodeForSession` for magic-link/OAuth deep links.
- `AuthStore` already observes `authStateChanges` and loads the profile — keep
  that. Add an `errorMessage` surface for failed sign-in attempts.

### 2. Apple sign-in (native)
- `Features/Auth/AppleSignInButton.swift` using `SignInWithAppleButton`
  (AuthenticationServices). Generate a random nonce, SHA256 it for the request,
  pass the raw nonce to Supabase. Style the button to match the brand (black,
  Radius.md). Handle the credential → idToken → `AuthService.signInWithApple`.

### 3. Google sign-in (native SDK)
- `Features/Auth/GoogleSignInButton.swift` using `GoogleSignIn`
  (`GIDSignIn.sharedInstance.signIn(withPresenting:)`). Configure with
  `AppConfig.googleIOSClientID`. Pass the returned `idToken` (+ access token) to
  `AuthService.signInWithGoogle`. Get the presenting controller via a small
  `UIViewController` helper or `UIApplication` key window.

### 4. Email + magic link
- Rework `Features/Auth/SignInView.swift` (M0 placeholder) into the real screen:
  Apple + Google buttons, divider, email field, and a segmented "Password /
  Magic link" choice. Password mode shows a password field + sign-in/sign-up
  toggle + "forgot password". Magic-link mode sends the link and shows a "check
  your email" confirmation state. Wire deep-link return through
  `DeepLinkRouter.Route.authCallback` → `AuthService.completeAuthCallback`.

### 5. /auth/resolve parity
- Add `Core/Repositories/AccessRepository.swift`: `currentPortal()` queries
  `admin_users` (self) and `agency_members` (self) — mirrors
  `web/src/lib/auth/portals.ts`. For v1 iOS, **all roles route to the end-user
  app**, but if the account is agency/admin-only, show a small notice card
  ("Manage your agency/admin portal on the web") on the dashboard. Don't block.

### 6. Onboarding wizard (replaces the M0 placeholder)
- `Features/Onboarding/OnboardingFlow.swift` — multi-step, mirrors web S19
  (`web/src/app/(app)/app` onboarding + `goal` / `onboarding_completed_at`):
  1. **Goal** multi-select (`["travel","work_abroad","immigrate","study","invest"]`).
  2. **Identity** — legal first/last name, DOB (`DateField`), place of birth,
     gender, marital status (prefill from `profiles`).
  3. **Passport** — add a primary passport (citizenship, number, expiry).
- On finish: update `profiles` (set `goal`, identity fields,
  `onboarding_completed_at = now`), insert the passport, then
  `auth.markOnboardingComplete(updated)`. Allow "Skip for now" (sets
  `onboarding_completed_at` so the user reaches the app; they can fill the vault
  later).

### 7. Profile vault CRUD (the Profile tab)
- `Features/Profile/ProfileHomeView.swift` — sectioned list linking to:
  - **Personal** (`profiles` identity fields) — `ProfileDetailsView`.
  - **Contact** (`profiles.phone`, addresses) — `ProfileContactView`.
  - **Passports** (`passports`) — list + add/edit/delete (`PassportsView`,
    `PassportEditView`), `is_primary` toggle.
  - **Residencies** (`residencies`), **Family** (`family_members`),
    **Employment** (`employment_entries`), **Education** (`education_entries`),
    **Travel history** (`travel_entries`). Build these as a **reusable
    `VaultSectionView<Model>`** pattern (list + add/edit/delete) since they share
    shape — don't copy-paste seven times.
- Extend `Core/Models/` with the missing vault structs (`Residency`,
  `FamilyMember`, `EmploymentEntry`, `EducationEntry`, `TravelEntry`) and
  `Core/Repositories/VaultRepository.swift` with generic-ish CRUD per table.
- Add a `DateField` SwiftUI component (calendar entry) mirroring the web
  `DateField` used across the vault.

## Web parity references
- `web/src/app/(auth)/login/*`, `web/src/app/auth/callback/route.ts`,
  `web/src/app/auth/resolve/route.ts`, `web/src/lib/auth/portals.ts`,
  `web/src/components/auth/GoogleSignInButton.tsx`.
- Vault pages: `web/src/app/(app)/app/profile/**`, `.../passports`,
  `.../residencies`, `.../travel-history` and `web/supabase/migrations/0010_profile_vault.sql`.
- Confirm exact column names with `execute_sql` against the live project.

## Tests
- Add unit tests for the nonce hashing helper and any profile-completeness /
  prefill mapping logic (pure, headless-safe).

## Definition of done
- Build + tests green. Email + magic-link sign-in works end to end against the
  live Supabase project (verify on the simulator with a real test account).
  Apple/Google compile and work once provider creds are in place.
- New user → onboarding → reaches the dashboard; returning user skips onboarding.
- All seven vault sections do full CRUD under RLS; primary passport drives the
  default in later milestones.
- Update `ios/README.md` M1 checkbox.
