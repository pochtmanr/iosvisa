# iOS Authentication Setup

How to make every sign-in option in the iOS app actually work: **Sign in with Apple**,
**Google**, **email + password**, and **magic link**.

The app code is already complete — `SignInView`, `AppleSignInButton`, `GoogleSignInButton`,
`AuthService`, `AuthStore`, and `DeepLinkRouter` all handle these flows. What makes them work
is the **external configuration** below. Work through it once and all four methods light up.

| Setting | Value |
| --- | --- |
| Bundle ID | `com.visapilot.app` |
| Supabase project ref | `eujmomonscnlmwcbkbfy` |
| App deep-link scheme | `visapilot://auth/callback` |

This guide targets the **dev** environment (Supabase Site URL on localhost). See
[Production](#production-later) at the end for the extra prod steps.

---

## How each method authenticates (1-minute mental model)

- **Apple** and **Google** are fully **native**: the app obtains an Apple/Google ID token on
  device and hands it to Supabase via `signInWithIdToken`. Supabase only accepts the token if
  the token's audience (the client ID / bundle ID) is **registered in the provider's "Client
  IDs" field**. That registration is the whole job.
- **Email + password** and **magic link** go straight to Supabase Auth. The catch: any link
  Supabase emails (confirmation, magic link, password reset) must redirect back to
  `visapilot://auth/callback`, which only works if that URL is on the **redirect allow-list**.
  Otherwise the link bounces to the Site URL (localhost) — the bug you saw.

---

## 1. Google Cloud Console — create an iOS OAuth client

You currently have only a **Web** client. Native iOS needs its own client.

1. Go to **APIs & Services → Credentials**.
2. **Create Credentials → OAuth client ID**.
3. **Application type: iOS**.
4. **Bundle ID:** `com.visapilot.app`. (Leave App Store ID / Team ID blank until published.)
5. **Create**, then copy the **iOS client ID** — it looks like
   `1234567890-abc123.apps.googleusercontent.com`.
6. Derive the **reversed** form by swapping the two leading dot-segments:
   `com.googleusercontent.apps.1234567890-abc123`.

> iOS OAuth clients have **no client secret** — that's expected, don't go looking for one.

---

## 2. Supabase → Authentication → Providers → Google

1. Make sure Google is **Enabled** (it already is, for web).
2. In **Client IDs**, append the new **iOS client ID** after the existing Web client ID,
   separated by a comma:
   `<web-client-id>.apps.googleusercontent.com,<ios-client-id>.apps.googleusercontent.com`
3. Turn **ON** "Skip nonce check".
   *Why:* the GoogleSignIn SDK doesn't attach a nonce and the app's `signInWithGoogle` doesn't
   pass one, but Supabase verifies nonces by default — leaving this off makes Google sign-in
   fail.
4. **Save.**

---

## 3. Apple Developer — enable Sign in with Apple on the App ID

1. **developer.apple.com → Certificates, Identifiers & Profiles → Identifiers**.
2. Open the App ID `com.visapilot.app` (create it if it doesn't exist).
3. Enable the **Sign in with Apple** capability → **Save**.
4. From the **Membership** page, copy your **Team ID** (10 characters) for step 7.

> Native-only Apple sign-in needs **no** Services ID, signing key, or secret. Those are only
> for the web OAuth flow, which we don't use on iOS.

---

## 4. Supabase → Authentication → Providers → Apple

1. **Enable** the Apple provider.
2. In **Client IDs**, add the bundle ID: `com.visapilot.app`.
3. Leave the OAuth fields (**Services ID**, **Secret Key**) **blank**.
4. **Save.**

---

## 5. Supabase → Authentication → URL Configuration  *(fixes the localhost bounce)*

1. Under **Redirect URLs**, add both:
   - `visapilot://auth/callback`
   - `visapilot://**`  (covers password-reset and any future paths)
2. Leave **Site URL** as `http://localhost:3000` for dev.
3. **Save.**

This is what stops magic-link / confirmation / reset emails from opening localhost — now they
deep-link back into the app.

---

## 6. Supabase → Authentication → Providers → Email

- Confirm **Email** is enabled.
- For quick dev testing you can temporarily turn **OFF** "Confirm email" so password sign-up
  returns a session immediately. With it ON, a new account must confirm via the emailed link
  first (which now deep-links correctly thanks to step 5) — or just test sign-up using the
  magic-link option.

---

## 7. Local app config

Edit `ios/Config/Secrets.xcconfig` (git-ignored) and fill in the real values:

```
GOOGLE_IOS_CLIENT_ID = <ios-client-id>.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.<ios-client-id>
DEVELOPMENT_TEAM = <your-10-char-team-id>
```

Then regenerate the Xcode project (the URL scheme and Info.plist keys are injected from these):

```bash
cd ios
xcodegen generate
```

---

## 8. Build & test

```bash
cd ios
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme VisaPilot -destination 'generic/platform=iOS Simulator' build
```

Run the app and exercise each path:

| Method | Expected |
| --- | --- |
| Email + password | Sign up / sign in → onboarding or main tabs. |
| Magic link | Open the emailed link **on the device** → deep-links into the app and signs in (not localhost). |
| Google | "Continue with Google" now appears (it was hidden while the client ID was empty) → consent → signed in. |
| Apple | "Sign in with Apple" → Face ID / passcode → signed in. Test on a real device or a Simulator signed into an Apple ID. |

### If something fails, it isolates cleanly to one config step

| Symptom | Cause / fix |
| --- | --- |
| Google: "invalid audience" / token rejected | iOS client ID not in Supabase **Client IDs** (step 2). |
| Google: nonce error | "Skip nonce check" not enabled (step 2). |
| Google: consent screen hangs / never returns | Reversed-client-ID URL scheme missing or project not regenerated (`Secrets.xcconfig` + `xcodegen generate`). |
| Apple: sign-in error | Bundle ID not in Apple provider **Client IDs** (step 4) or capability not enabled on the App ID (step 3). |
| Magic link / reset opens localhost | `visapilot://auth/callback` not on the redirect allow-list (step 5). |
| Build: code-sign / "no team" error | `DEVELOPMENT_TEAM` not set in `Secrets.xcconfig` (step 7). |

---

## Production later

When moving beyond localhost:

- Serve `/.well-known/apple-app-site-association` on `visapilot.app` to enable universal links
  (the entitlements already declare `applinks:visapilot.app`). Not required for auth today —
  the custom `visapilot://` scheme handles all callbacks.
- Add the production redirect URL to Supabase **Redirect URLs** and set **Site URL** to the
  production domain.
- Add the production origin to the Google **Web** client's authorized origins (web app only).
