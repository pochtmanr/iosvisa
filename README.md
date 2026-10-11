# VisaPassage iOS

A free native SwiftUI client for [VisaPassage](https://visapassage.com). It covers visa requirements by
passport, routes and checklists, the passport ranking, and the Visa Tracker. It reads the **same Supabase
backend** as the website (`../web`, project `eujmomonscnlmwcbkbfy`), under the same Row Level Security.

- Product plan and screens: [`../web/docs/product/IOS-APP.md`](../web/docs/product/IOS-APP.md)
- Session prompts and status: [`../web/prompts/IOS/ROADMAP.md`](../web/prompts/IOS/ROADMAP.md)
- Auth configuration: [`docs/AUTH-SETUP.md`](docs/AUTH-SETUP.md)

## Principles (locked 2026-10-11)

- **Free.** No subscriptions, paywall or StoreKit in v1.
- **Guest-first.** Every catalog screen works without an account. Only **My visas** asks you to sign in.
- **Feels like the web `/app`.** The same four tabs as the web phone tab bar (Home · Explore · My visas ·
  Settings), the same wording, and the same data rules (tracker stages, dense passport ranking).
- **en + ru.** UI strings live in `VisaPassage/Resources/Localizable.xcstrings`. Russian is written by
  hand, never by a script or a translation API, and copies `web/src/messages/ru/*.json` wherever the same
  string exists. Database prose goes through the `translations` jsonb via
  `Core/Localization/PickTranslation.swift`, a port of the web's `pick-translation.ts`.
- **Honest copy.** Never promise approval. Official decisions prevail.

## Stack

- SwiftUI, iOS 17+, MVVM with `@Observable`, `async/await`, Swift 6.
- [`supabase-swift`](https://github.com/supabase/supabase-swift) 2.x: Auth, plus PostgREST reads of the
  public catalog and the user's own rows.
- Auth: Sign in with Apple, Google, and email (password + magic link). The session lives in the Keychain.
- `Core/Cache/CatalogCache`: file-based JSON in Caches, keyed by query, with a 24h TTL and
  stale-while-revalidate. The app shows cached catalog data instantly, works offline, and refreshes in
  the background.
- XcodeGen. The `.xcodeproj` is **not** committed, so regenerate it from `project.yml`.

## Prerequisites

- macOS with **Xcode** installed. The build needs the iOS SDK; Command Line Tools alone are not enough.
- [XcodeGen](https://github.com/yonomi/XcodeGen): `brew install xcodegen`

## First-time setup

```bash
cd ios
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
# Fill in SUPABASE_ANON_KEY (public anon key, the same one the web bundle ships),
# GOOGLE_IOS_CLIENT_ID / GOOGLE_REVERSED_CLIENT_ID and DEVELOPMENT_TEAM.
xcodegen generate            # creates VisaPassage.xcodeproj
open VisaPassage.xcodeproj
```

`Config/Secrets.xcconfig` is git-ignored. Only the public anon key belongs there, **never** the
service-role key.

## Build and test

```bash
cd ios
xcodegen generate
xcodebuild -scheme VisaPassage -destination 'platform=iOS Simulator,name=iPhone 16' build test
```

If `xcode-select -p` points at Command Line Tools, prefix the command with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Without signing set up, add
`CODE_SIGNING_ALLOWED=NO`. If the simulator doesn't exist yet, create it with:
`xcrun simctl create "iPhone 16" com.apple.CoreSimulator.SimDeviceType.iPhone-16 <runtime-id>`
(get the runtime id from `xcrun simctl list runtimes`).

Tests:
- `VisaPassageTests`: pure logic, safe to run headless. It covers the cache, `pickTranslation`, the visa
  status reducer and eligibility fold, TopoJSON decoding and projection, the nonce, the passport preference
  (max four, legacy-key migration), the dense passport rank, Explore's status grouping and filters, and the
  rule-changes decoding.
- `VisaPassageUITests`: guest launch on the tab shell, ru tab labels, Explore's country catalog, and the
  first-launch welcome → passport picker → Home path.

Opening single `.swift` files outside the generated project shows false "No such module 'Supabase'"
errors. Always validate with `xcodebuild`.

## Project layout

```
ios/
  project.yml                  # XcodeGen spec, the source of truth for the project
  Config/                      # Base.xcconfig + Secrets.xcconfig(.example)
  VisaPassage/
    App/                       # @main, RootView, AuthStore, TabRouter, MainTabView, DeepLinkRouter
    DesignSystem/              # Palette/Theme/Typography/Layout + Components
    Core/
      Cache/                   # CatalogCache (file JSON, TTL, stale-while-revalidate)
      Config/                  # AppConfig (reads Info.plist)
      Localization/            # AppLocale + pickTranslation port
      Map/                     # TopoJSON decoder + Equal Earth projection
      Models/                  # Codable structs mirroring DB rows + enums
      Networking/              # APIClient for the web /api/* JSON routes
      Preferences/             # PassportPreference (up to four passports, on device)
      Repositories/            # PostgREST wrappers (countries, visas, cached requirements + ranking, profile)
      Supabase/                # shared SupabaseClient
    Features/                  # Welcome (+ passport picker), Home, Explore, Destinations, MyVisas, Settings, Auth
    Resources/                 # Geist fonts, asset catalog, world atlas, Localizable.xcstrings
  VisaPassageTests/
  VisaPassageUITests/
```

## Status

The session-by-session status lives in [`../web/prompts/IOS/ROADMAP.md`](../web/prompts/IOS/ROADMAP.md).
IOS-01 (foundation) delivered the rebrand, removed the marketplace-era features, and added the guest-first
tab shell, the catalog cache and the String Catalog. IOS-02 to IOS-07 build the screens, the tracker and
the release.

First launch shows a three-card welcome (`Features/Welcome/`) built from the landing's "How it works": the
landing photos, and SwiftUI ports of the passport folder, passport covers, stamps and status chips. It is
shown once (`welcome.completed` in `UserDefaults`; pass `-welcome.completed YES` to skip it in UI tests).
The welcome ends in "Pick your passport" (also reached by Skip): up to four passports, the first primary,
stored on the device under `passports.selected`. Home then shows that passport's rank, visa-free count and
mobility score (the `passport_strength` view with the web's dense rank), popular routes, and the latest
`policy_changes`. Explore colours the world map in the web hero map's palette, with status filter chips, a
bottom panel on tap, and a list grouped by status. Requirements, the ranking and the changes go through
`CatalogCache`, so Home and Explore work offline after the first load.

Debug launch arguments for screenshots: `-welcome.debugPage 2`, `-welcome.debugPicker YES`,
`-welcome.debugSignIn YES`, `-passports.selected UA`, `-debug.tab explore`, `-debug.exploreMode list`,
`-debug.exploreFocus TR`.

Sign-in everywhere is one floating card (`AuthSheet` via `.floatingSheet`, `DesignSystem/Components/FloatingSheet.swift`),
inset from the screen edges with corners concentric to the display's.

## Design system

Ported from the web `visapilot-design` skill:
- monochrome ink-on-paper neutrals, with saturated colour reserved for visa status;
- Geist and Geist Mono;
- hairline structure (1px borders, 24px cards, no resting shadow);
- SF Symbols as the line icons;
- the "official decisions prevail" disclaimer wherever advice is shown.

## History

This app started in 2026 as **VisaPilot** (bundle `com.visapilot.app`), the native client of the
agency-marketplace product. Its applications workflow, document vault and payments were removed in IOS-01,
when the app was rebuilt as the free VisaPassage catalog and tracker client. The old milestone prompts
(M0–M7) are in git history.
