# iOS authentication setup

This is the configuration that makes each sign-in option in the iOS app work: **Sign in with Apple**,
**Google**, **email + password** and **magic link**.

The app is guest-first. Every catalog screen works without an account, and sign-in is only needed for
**My visas** (trackers). Sign-in opens from the Settings tab or the My visas gate. The code is already
in place (`Features/Auth/*`, `App/AuthStore.swift`, `App/DeepLinkRouter.swift`). The steps below are external configuration only.

| Setting | Value |
| --- | --- |
| Bundle ID | `com.visapassage.app` |
| Apple team ID | `F7YY9U667A` |
| Supabase project ref | `eujmomonscnlmwcbkbfy` |
| App deep-link scheme | `visapassage://auth/callback` |
| Universal-link domain | `visapassage.com` (AASA file lands in IOS-06) |

## How each method authenticates

- **Apple** and **Google** are **native**. The app gets an ID token on the device and hands it to
  Supabase through `signInWithIdToken`. Supabase only accepts the token when its audience (the bundle ID
  or the iOS client ID) is listed in that provider's **Client IDs** field.
- **Email + password** and **magic link** go straight to Supabase Auth. Any link Supabase emails
  (confirmation, magic link, password reset) must redirect to `visapassage://auth/callback`. That only
  works when the URL is on the **redirect allow-list**. Without it, the link opens the Site URL instead.

## 1. Apple: done in IOS-00

All Apple setup is in **[`web/docs/apple-oauth-setup.md`](../../web/docs/apple-oauth-setup.md)** (IOS-00):
- the App ID `com.visapassage.app` with Sign in with Apple and Associated Domains;
- the Services ID `com.visapassage.web`, the key and the client secret for the website;
- the Supabase Apple provider.

For the iOS app, the only part that matters is that **`com.visapassage.app` is listed in the Supabase
Apple provider's Client IDs**. Native sign-in doesn't use the client secret. Until the bundle ID is listed,
Apple sign-in on iOS fails with a token/audience error.

## 2. Google Cloud: create an iOS OAuth client

1. **APIs & Services → Credentials → Create credentials → OAuth client ID**.
2. **Application type: iOS**. **Bundle ID: `com.visapassage.app`**. Leave App Store ID blank until the
   app is published, and set Team ID to `F7YY9U667A`.
3. **Create**, then copy the **iOS client ID** (`1234567890-abc123.apps.googleusercontent.com`).
4. Derive the **reversed** form by swapping the two leading dot-segments:
   `com.googleusercontent.apps.1234567890-abc123`.

iOS OAuth clients have **no client secret**. That's expected.

## 3. Supabase → Authentication → Providers → Google

1. Google stays **Enabled** (the website uses it).
2. In **Client IDs**, append the iOS client ID after the existing web client ID, comma-separated:
   `<web-client-id>.apps.googleusercontent.com,<ios-client-id>.apps.googleusercontent.com`
3. Turn **on** "Skip nonce check". The GoogleSignIn SDK doesn't attach a nonce, and Supabase rejects the
   token without one unless this is on.
4. **Save.**

## 4. Supabase → Authentication → URL Configuration

Under **Redirect URLs**, add:
- `visapassage://auth/callback`
- `visapassage://**` (covers password reset and future paths)

Leave **Site URL** as the website's production URL. With these entries, magic-link, confirmation and reset
emails opened on the phone come back into the app.

## 5. Supabase → Authentication → Providers → Email

Email is already enabled for the website. With "Confirm email" on, a new password account must confirm
through the emailed link first. That link deep-links into the app once step 4 is done.

## 6. Local app config

Fill in `ios/Config/Secrets.xcconfig` (git-ignored; copy it from `Secrets.xcconfig.example`):

```
SUPABASE_ANON_KEY = <public anon key>
GOOGLE_IOS_CLIENT_ID = <ios-client-id>.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.<ios-client-id>
DEVELOPMENT_TEAM = F7YY9U667A
```

The Google button stays hidden while `GOOGLE_IOS_CLIENT_ID` is empty.

## 7. Build and test

```bash
cd ios
xcodegen generate
xcodebuild -scheme VisaPassage -destination 'platform=iOS Simulator,name=iPhone 16' build test
```

Then run the app and try each path from **Settings → Sign in**:

| Method | Expected |
| --- | --- |
| Email + password | Sign up or sign in. Sign-in closes and Settings shows your account. |
| Magic link | Open the emailed link **on the device**. It opens the app and signs you in. |
| Google | "Continue with Google" appears, then the consent screen, then you're signed in. |
| Apple | "Sign in with Apple", then Face ID or passcode, then you're signed in. Use a real device or a simulator signed into an Apple ID. |

### Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Google: "invalid audience" / token rejected | The iOS client ID is missing from the Supabase Google **Client IDs** (step 3). |
| Google: nonce error | "Skip nonce check" is off (step 3). |
| Google: consent screen never returns | The reversed client ID is missing from `Secrets.xcconfig`, or the project wasn't regenerated. |
| Apple: sign-in error | `com.visapassage.app` is missing from the Supabase Apple **Client IDs**, or the capability is off on the App ID (step 1). |
| Magic link / reset opens the website | `visapassage://auth/callback` is not on the redirect allow-list (step 4). |
| Build: code-sign / "no team" error | `DEVELOPMENT_TEAM` is not set in `Secrets.xcconfig`. |

## Universal links (IOS-06)

The entitlements already declare `applinks:visapassage.com` and `webcredentials:visapassage.com`. IOS-06
serves `/.well-known/apple-app-site-association` from the website. Auth doesn't depend on it: the
`visapassage://` scheme handles every callback.
