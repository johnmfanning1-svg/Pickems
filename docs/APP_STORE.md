# App Store Review SOP

Submit an **already-uploaded** TestFlight build for App Review. TestFlight first: [TESTFLIGHT.md](TESTFLIGHT.md). Agent entry point: `.cursor/skills/ship-ios/SKILL.md`.

ASO copy: [ASO.md](ASO.md) · `fastlane/metadata/en-US/`.

---

## Identity

| | |
|--|--|
| Bundle | `FannypackInc.Pickems` |
| Apple ID | `6785697079` |
| Team | `22A943P8SJ` |
| Copyright | `2026 Fannypack Inc.` (update year when needed) |
| Release type | `AFTER_APPROVAL` (manual release after Apple approves) |
| Connect UI | [iOS version deliverable](https://appstoreconnect.apple.com/apps/6785697079/distribution/ios/version/deliverable) |
| Encryption | `ITSAppUsesNonExemptEncryption` = false |

Demo account **email** (already in Connect): `review.pickems.appstore@gmail.com`. Copy the password from the previous version’s `appStoreReviewDetail` over iris. **Never commit it. Delete `/tmp` scripts that contain it when the submit is done.**

---

## Do not

- Submit unless the user explicitly asked for App Review / App Store submit
- Raise `appConfig/live.minimumBuild` unless they asked (see [MINIMUM_BUILD.md](MINIMUM_BUILD.md))
- Set `resetRatingsRequest` (do not reset ratings)
- Use Cursor’s browser for Connect (Apple login blocks it)
- Create a new version while another iOS version is `WAITING_FOR_REVIEW` or `IN_REVIEW` — cancel that review first
- Re-run production Week 0 migration, call ESPN with `week=0`, or auto-migrate on client launch

---

## Tooling: Google Chrome + iris

App Store Connect work is done in a **logged-in Google Chrome** tab via `osascript` `execute javascript`, `fetch(..., { credentials: 'include' })` against `https://appstoreconnect.apple.com/iris/v1/...`.

1. Confirm Chrome has a Connect tab (create/navigate if needed).
2. Write a short JS snippet to `/tmp`, execute it, then poll `window.__someFlag`.
3. After submit, `rm` any `/tmp` file that contains the demo password.

```applescript
osascript <<'AS'
set js to read POSIX file "/tmp/pickems-asc-state.js" as «class utf8»
tell application "Google Chrome"
  tell tab 1 of window 1
    execute javascript js
  end tell
end tell
AS
```

List tabs first if window/tab index is unknown.

---

## 1. Inspect live state

Query in parallel:

- `GET /iris/v1/apps/6785697079/appStoreVersions?filter[platform]=IOS&limit=8`
- `GET /iris/v1/reviewSubmissions?filter[app]=6785697079&filter[platform]=IOS&limit=10`
- `GET /iris/v1/builds?filter[app]=6785697079&filter[version]=NNN&limit=5` (the TestFlight build)

Need: build `NNN` `processingState` = `VALID`, `expired` = false.

### If another version is in review

`PATCH /iris/v1/reviewSubmissions/{id}` with `{ canceled: true }`. Poll until the submission is `COMPLETE` and the version is editable (`PREPARE_FOR_SUBMISSION` or similar — not `WAITING_FOR_REVIEW`). Then either rename that version to the new marketing string and attach the new build, or create a fresh version once the slot is free.

### If latest is `READY_FOR_DISTRIBUTION`

Create a new version (next section). Do not attach a build to a live `READY_FOR_DISTRIBUTION` version.

### If a `PREPARE_FOR_SUBMISSION` version already exists

Reuse it (patch version string if needed) instead of creating another.

---

## 2. Create version (when needed)

`POST /iris/v1/appStoreVersions`

```json
{
  "data": {
    "type": "appStoreVersions",
    "attributes": {
      "platform": "IOS",
      "versionString": "X.Y.Z",
      "copyright": "2026 Fannypack Inc.",
      "releaseType": "AFTER_APPROVAL"
    },
    "relationships": {
      "app": { "data": { "type": "apps", "id": "6785697079" } }
    }
  }
}
```

Then load:

- `GET .../appStoreVersions/{vid}/appStoreVersionLocalizations?limit=5` → localization id
- `GET .../appStoreVersions/{vid}/appStoreReviewDetail` → review detail id (and demo password to reuse)

Screenshots usually copy forward. Confirm at least iPhone 6.7" (and existing iPad set) remain.

---

## 3. Attach build + metadata

| Step | Call |
|--|--|
| Attach build | `PATCH .../appStoreVersions/{vid}/relationships/build` body `{ "data": { "type": "builds", "id": "<build uuid>" } }` |
| Release type | `PATCH .../appStoreVersions/{vid}` `releaseType: AFTER_APPROVAL` |
| What’s New | `PATCH .../appStoreVersionLocalizations/{loc}` |
| Review notes | `PATCH .../appStoreReviewDetails/{reviewId}` |

**What’s New:** start from `fastlane/metadata/en-US/release_notes.txt`. Drop TestFlight-only lines (“Thanks for helping us UAT…”). Close with “Thanks for playing with us.” Promotional text: `fastlane/metadata/en-US/promotional_text.txt`.

**Review notes:** version + build, short “what’s new”, Guideline 1.2 chat moderation (Report / Block / Delete own / Terms), HOW TO REVIEW for the new features, demo email, Privacy URL:

`https://raw.githubusercontent.com/johnmfanning1-svg/Pickems/main/docs/privacy-policy.html`

Keep `demoAccountRequired: true` and the existing demo email/password.

---

## 4. Submit

1. `POST /iris/v1/reviewSubmissions` — `{ platform: "IOS" }` related to app `6785697079`
2. `POST /iris/v1/reviewSubmissionItems` — relate that submission to the `appStoreVersion`
3. `PATCH /iris/v1/reviewSubmissions/{rsId}` — `{ submitted: true }`

Confirm:

- Review submission `state` = `WAITING_FOR_REVIEW`
- Version `appVersionState` = `WAITING_FOR_REVIEW`
- Included build `version` = the intended build number

Then delete `/tmp` JS that held credentials.

---

## 5. Tell the user

- Marketing version + build
- Waiting for Review
- Release is manual after approval (live store stays on the previous `READY_FOR_DISTRIBUTION` version)
- Link to the Connect deliverable page

Do not bump `minimumBuild` as part of submit (see [MINIMUM_BUILD.md](MINIMUM_BUILD.md)). Do not announce a store release until Apple approves and someone releases it.

---

## Fastlane metadata (copy, not binary)

```bash
bundle exec fastlane metadata
```

Use when ASO fields in `fastlane/metadata/en-US/` changed. Binary upload is [TESTFLIGHT.md](TESTFLIGHT.md), not this lane.

---

## Preflight (features that App Review cares about)

- [ ] Demo account still signs in (email/password behind “Use email and password instead”, or Sign in with Apple)
- [ ] Chat: Report, Block, Delete own, Terms linked (Guideline 1.2)
- [ ] Account deletion: Profile → Delete Account
- [ ] Privacy / Terms URLs load over HTTPS
- [ ] Sheets that present league flows still use `.pickemsEnvironment` (1.0 crash)
- [ ] Watch remains `SKIP_INSTALL`; do not change embedding as part of a routine ship

---

## Appendix: 1.0 rejection (keep)

App Review crash logs from **2026-07-15** on iPhone OS 26.5.2: `EXC_BREAKPOINT` / `SIGTRAP` in `EnvironmentValues.subscript.getter` → `SheetBridge.present`, ~3–7s after launch. Root cause: SwiftUI sheets reading `@Environment(AppState.self)` without a guaranteed environment. Fixed via `.pickemsEnvironment(appState)` on sheet roots. Still required for any new sheets.
