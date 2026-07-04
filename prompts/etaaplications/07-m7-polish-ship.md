# M7 — Polish + ship

**First read `ios/prompts/00-shared-context.md` and `ios/README.md`.** Final
pass over the whole app in `ios/`. Verify with `xcodebuild build` + `test`.

## Goal

Take the full-parity app from "works" to "shippable": consistent states,
accessibility, settings, notifications scaffolding, app identity, and a
TestFlight build.

## Scope

### 1. States & resilience
- Audit every screen for **loading / empty / error** states using the design
  system (skeletons or `ProgressView`, branded empty states with a CTA, inline
  error with retry). No silent failures — surface errors honestly.
- Centralize error presentation (a reusable `ErrorView` / banner). Handle
  offline + token-expiry → graceful re-auth.
- Confirm the `AdvisoryDisclaimer` appears on every advice-bearing screen.

### 2. Settings (real)
- `Features/Settings/SettingsView.swift` — notification preferences
  (`profiles.notify_*`), connected sign-in provider, app version, sign-out, and
  **delete account** (mirror web `/app/settings`). Delete account should call
  the appropriate server path (add one in `08` if needed) — never leave orphaned
  data.

### 3. Accessibility & polish
- Dynamic Type (the Geist roles should scale), VoiceOver labels on icons/controls
  and the map legend, sufficient contrast (the status hues already meet the
  web's contrast pairing), reduce-motion respect for the fade-ups, and full
  dark-mode pass (tokens already adapt — verify every screen).
- Haptics on key actions (submit, payment success). Keep motion calm.

### 4. Notifications (scaffolding — optional to fully wire)
- Add push-notification capability + registration scaffolding for case-message
  and status-change alerts. Full delivery needs an APNs + server piece; at
  minimum register for notifications and document the server hook needed. Don't
  fake it — if not wired end to end, say so in the README.

### 5. App identity & store readiness
- App icon (from `logo.svg` / `logo.png` in the repo root) into
  `Assets.xcassets/AppIcon.appiconset` (all required sizes). Launch screen
  using the brand. Set the real `DEVELOPMENT_TEAM` in `project.yml`.
- Privacy: `Info.plist` usage strings (Photos, Files, Camera if used). Fill the
  App Privacy "nutrition label" details (data collected: account, documents,
  payment via Revolut).
- App Store metadata draft (name, subtitle, description, keywords, screenshots
  from the simulator).

### 6. TestFlight
- Archive + upload an internal TestFlight build (needs the Apple Developer
  account / signing). Document the exact `xcodebuild archive` + `xcrun
  altool`/`notarytool` or Xcode Organizer steps in the README.

## Definition of done
- Build + tests green. Every screen has loading/empty/error states and passes a
  VoiceOver + Dynamic Type + dark-mode spot check.
- Settings (incl. delete account) works; notifications are either wired or
  clearly documented as pending with the server hook described.
- App icon + launch screen + privacy strings in place; a TestFlight build is
  uploaded (or the exact remaining signing steps are documented for Roman).
- Update `ios/README.md` — mark M7 done and summarize what's shipped + any
  follow-ups (e.g. passkeys v2).
