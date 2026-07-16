# App Store submission notes

## Version

- **Marketing version:** 1.2.3
- **Build:** 123
- **Bundle ID:** `FannypackInc.Pickems`
- **Apple ID:** 6785697079

## What Apple rejected in 1.0 (build 2)

App Review attached crash logs from **2026-07-15** on iPhone OS 26.5.2. All incidents match the same failure:

| Field | Value |
|--|--|
| Exception | `EXC_BREAKPOINT` / `SIGTRAP` |
| Faulting path | `EnvironmentValues.subscript.getter` → `SheetBridge.present` |
| Timing | ~3–7s after launch while presenting a sheet |
| Likely UI | Groups → **Commissioner Settings** or **Join** (see review screenshot) |

Root cause: SwiftUI sheets reading `@Environment(AppState.self)` without a guaranteed environment (and empty `if let` sheet content). Fixed in 1.2.3 via `.pickemsEnvironment(appState)` on sheet roots and non-empty Commissioner Settings sheet content.

## Work already shipped after 1.0 (before this pass)

| Change | Status |
|--|--|
| Auth navigation / email-password / favorite team (#6) | Merged |
| Theme contrast + session tracing (#7) | Merged |
| TestFlight cold-launch Firebase / notifications crash → 1.2.2 (#8) | Merged |

Those fixed launch/auth issues; they did **not** cover the sheet environment trap Apple hit.

## Fixes in 1.2.3 (this submission)

1. **Sheet environment crash** — forward `AppState` + theme into all major sheets; harden Commissioner Settings sheet
2. **Groups UX** — rename Join → “Join Another League”; Discover as full-width (clearer when already in a league)
3. **Account deletion (5.1.1(v))** — Profile → Delete Account; Firestore/Storage rules allow self-delete
4. **Privacy Manifest** — `PrivacyInfo.xcprivacy`
5. **Privacy Policy + Terms** — docs + in-app Profile links
6. **Invite copy** — remove “TestFlight coming soon”; real App Store URL
7. **Hide unfinished X Connect** until client ID is configured

## App Review Information (paste into App Store Connect)

**Demo account (email/password):** create a dedicated reviewer account in Firebase Auth before submit, then fill:

```
Username: review@pickems.app   (or your seeded email)
Password: <set in Firebase>
```

**Notes for Review:**

> Thank you for the crash logs from version 1.0 (build 2). Those crashes were EXC_BREAKPOINT failures when presenting Groups sheets (Commissioner Settings / Join) because AppState was missing from the sheet environment. Version 1.2.3 fixes that by always forwarding the environment into sheet content and avoiding empty sheet hierarchies.
>
> How to review:
> 1. Sign in with the demo account (or Sign in with Apple / Create Account).
> 2. Create a league or join with invite code from Notes.
> 3. On Groups, open Commissioner Settings — sheet should present without crashing.
> 4. Use “Join Another League” to open the join sheet safely.
> 5. Account deletion is available under Profile → Delete Account.
>
> Privacy Policy: https://raw.githubusercontent.com/johnmfanning1-svg/Pickems/cursor/app-store-approval-fixes-e1a6/docs/privacy-policy.html
> Terms: https://raw.githubusercontent.com/johnmfanning1-svg/Pickems/cursor/app-store-approval-fixes-e1a6/docs/terms.html

**Invite code:** seed a stable public/private league and paste the 6-character code here before submit.

## Hosting legal pages

`AppConfig` currently points at raw GitHub URLs on this branch (HTTPS, readable). For a nicer rendered page, enable GitHub Pages (Settings → Pages → Deploy from branch `main` / folder `/docs`) and switch `AppConfig.privacyPolicyURL` / `termsOfServiceURL` to `https://johnmfanning1-svg.github.io/Pickems/...`.

## Preflight checklist

- [ ] Seed App Review demo account + invite code in Connect notes
- [ ] Enable GitHub Pages (or update legal URLs)
- [ ] Deploy Firestore + Storage rules (`firebase deploy --only firestore:rules,storage`)
- [ ] Archive 1.2.3 (123) and submit
- [ ] Confirm Sign in with Apple capability on the App ID
- [ ] App Privacy questionnaire matches `PrivacyInfo.xcprivacy` / privacy policy
