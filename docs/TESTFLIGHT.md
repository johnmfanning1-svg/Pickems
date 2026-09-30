# TestFlight SOP

Upload a new Pickems build for internal testers. **Do not** submit for App Review unless the user also asks for that.

Agent entry point: `.cursor/skills/ship-ios/SKILL.md`. App Review: [APP_STORE.md](APP_STORE.md).

---

## Identity

| | |
|--|--|
| Bundle | `FannypackInc.Pickems` |
| Apple ID | `6785697079` |
| Team | `22A943P8SJ` |
| Scheme | `Pickems` |
| Export options | `fastlane/ExportOptions-AppStore.plist` (`method: app-store-connect`, `destination: upload`, automatic signing) |

---

## Do not

- Submit the build for App Review
- Raise `appConfig/live.minimumBuild` (see [MINIMUM_BUILD.md](MINIMUM_BUILD.md))
- Change PickemsTests / PickemsUITests versions (leave `1.0`)
- Re-run the production Week 0 migration, call ESPN with `week=0`, or auto-migrate on client launch
- Push unless the user asked to push
- Treat Firebase dSYM upload warnings as a failed TestFlight upload (they are expected / non-blocking)

---

## 1. Confirm the ask

Typical phrasing: “bump TestFlight”, “new build”, “upload to TestFlight”. If they also want App Review, finish this SOP first, wait until they confirm the build looks good, then [APP_STORE.md](APP_STORE.md).

---

## 2. Bump shipping versions

In `Pickems.xcodeproj/project.pbxproj`, replace the **current shipping** marketing version and build on Pickems, PickemsWidget, and PickemsWatch (Debug + Release). Convention: marketing `X.Y.Z` ↔ build `XYZ` with no dropped digits (example: `3.2.3` / `323`, `3.3.11` / `3311`). Never increment the build as a bare integer (`339 → 340`) when the marketing patch rolls to two digits.

```text
CURRENT_PROJECT_VERSION = <old>;  →  CURRENT_PROJECT_VERSION = <new>;
MARKETING_VERSION = <old>;        →  MARKETING_VERSION = <new>;
```

`replace_all` of the old shipping values is safe because test targets stay at `1.0`, not the shipping build.

Update `fastlane/metadata/en-US/release_notes.txt` (What’s New / TestFlight notes). Keep bullets factual. A “Thanks for helping us UAT…” line is fine for TestFlight; App Review copy should drop it ([APP_STORE.md](APP_STORE.md)).

---

## 3. Commit (and push if asked)

Commit the bump + product changes with a message that states the version, e.g. `Ship 3.2.3 with See who's in on the Pickems tab.` Push only when the user asked.

---

## 4. Disk space

This machine fills `/tmp` with old DerivedData. Before archiving:

```bash
df -h /tmp
# If tight, remove stale archives/derived data (keep the current build’s archive if still needed):
rm -rf /tmp/PickemsDerived-*
```

Prefer Xcode’s existing Pickems DerivedData folder over a fresh `/tmp/PickemsDerived-*` so package resolution is reused:

`/Users/johnfanning/Library/Developer/Xcode/DerivedData/Pickems-gwvfqqvrkuvrizarqycfytzytpzl`

If that folder is gone, `xcodebuild` will create a new one; do not invent a path.

---

## 5. Archive Release

From the repo root. Replace `NNN` with the new build number.

```bash
mkdir -p /tmp/PickemsRelease
rm -rf /tmp/PickemsRelease/Pickems-NNN.xcarchive
xcodebuild -scheme Pickems -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/PickemsRelease/Pickems-NNN.xcarchive \
  -derivedDataPath /Users/johnfanning/Library/Developer/Xcode/DerivedData/Pickems-gwvfqqvrkuvrizarqycfytzytpzl \
  archive -allowProvisioningUpdates
```

Wait for `ARCHIVE SUCCEEDED`. Confirm the archive is the intended marketing + build:

```bash
plutil -p /tmp/PickemsRelease/Pickems-NNN.xcarchive/Info.plist | head -40
```

---

## 6. Export and upload

```bash
rm -rf /tmp/PickemsRelease/export-NNN
xcodebuild -exportArchive \
  -archivePath /tmp/PickemsRelease/Pickems-NNN.xcarchive \
  -exportPath /tmp/PickemsRelease/export-NNN \
  -exportOptionsPlist fastlane/ExportOptions-AppStore.plist \
  -allowProvisioningUpdates
```

Success looks like `EXPORT SUCCEEDED` and `Upload succeeded`. Firebase Crashlytics dSYM warnings do **not** mean the binary failed to reach TestFlight.

`fastlane beta` (`PILOT_IPA=...`) is an alternative if an IPA was already exported; the `xcodebuild` path above is the one that actually ships.

---

## 7. Tell the user

- Marketing version + build number
- That it is in TestFlight processing (usually valid within minutes)
- That it is **not** submitted for App Review unless they asked

Processing state can be checked later in App Store Connect (Chrome iris `builds?filter[version]=NNN`). Do not poll for “VALID” unless the next step is App Review.

---

## Tests (when changing code in the same ship)

Simulator: `platform=iOS Simulator,name=iPhone 17` (add `,OS=26.5` if multiple runtimes exist). If disk-full aborts a test run, clean `/tmp/PickemsDerived-tests` and retry.

```bash
xcodebuild test -scheme Pickems \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PickemsTests
```

---

## Automated via GitHub Actions

Workflow: [`.github/workflows/testflight.yml`](../.github/workflows/testflight.yml). It archives the **Pickems** scheme (Pickems + embedded PickemsWidget), signs with Xcode cloud-managed signing, exports an `.ipa`, and uploads it to TestFlight with `xcrun altool`. It does **not** submit for App Review, touch `appConfig/live.minimumBuild`, or commit anything back to the repo.

### Required secrets

Repository → Settings → Secrets and variables → Actions:

| Secret | Value |
|--|--|
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | Issuer ID (UUID shown above the key list in App Store Connect → Users and Access → Integrations) |
| `ASC_KEY_P8` | Full contents of `AuthKey_<KEY_ID>.p8`, raw PEM (`-----BEGIN PRIVATE KEY-----` …). Base64 of the file also works. |

The key must have the **Admin** role. Cloud-managed signing (`-allowProvisioningUpdates` with `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`) creates or fetches signing certificates and provisioning profiles for the app, widget, and watch bundle IDs, and Apple only allows that with an Admin key. With an App Manager or Developer key, archive/export fails with a signing or permission error. No certificates or profiles are stored as secrets.

The key file is written to `~/.appstoreconnect/private_keys/` on the runner only for the job and deleted in an `always()` step at the end, along with a temporary signing keychain. Key ID and issuer ID are scrubbed from the log files that are kept as artifacts.

### Build number

Marketing version comes from the repo unchanged (`MARKETING_VERSION` in `project.pbxproj`). The build number is set on the runner only, identically on Pickems, PickemsWidget, and PickemsWatch (Debug + Release; test targets stay at `1`):

- Default: `TESTFLIGHT_BUILD_BASE + github.run_number`, where the optional repository **variable** `TESTFLIGHT_BUILD_BASE` defaults to `10000` (first run = `10001`).
- Manual override: the `build_number` input on **Run workflow**.
- The job fails if the result is not a plain integer greater than the repo's current `CURRENT_PROJECT_VERSION`. It must be a plain integer because `ForceUpdatePolicy` parses `CFBundleVersion` with `Int()`.

Why `10000+` and not the Mac `XYZ` convention (§2): App Store Connect already has builds up to at least `3507`, and `minimumBuild` compares build numbers as integers, so a low CI build like `401` would be rejected as a duplicate/lower build or trip the force-update gate. CI builds therefore live above every `XYZ` build. Keep that in mind before raising `minimumBuild` to a CI build number: any later Mac-archived build using the `XYZ` convention would then be below the gate. Re-running a failed run reuses the same `run_number`, so if that attempt already uploaded, start a new run instead of re-running.

### Marketing version must be open in App Store Connect

The workflow uploads whatever `MARKETING_VERSION` the chosen ref has. App Store Connect rejects it if that version is not above the last **approved** App Store version, or if its train is closed (errors 90062 / 90186 / 90478). On 2026-09-30 `main` was still at `3.5.2` while `3.5.6` was approved and `3.5.7` was on TestFlight from an unmerged branch, so the first validation run signed and exported fine but the upload was rejected. Run it from a ref whose marketing version is above the approved App Store version (bump it the usual way, §2, and commit), not from a stale `main`.

### Signing certificates

Each run is a fresh runner, so `xcodebuild archive` creates a new **Apple Development: Created via API** certificate for the development-signed archive; the export then re-signs with **Cloud Managed Apple Distribution** and App Store profiles for `FannypackInc.Pickems` and `FannypackInc.Pickems.widget`. Revoke old "Created via API" development certificates in Certificates, Identifiers & Profiles from time to time so the team doesn't hit Apple's certificate limit.

### How to trigger

- **Manually:** GitHub → Actions → **TestFlight** → **Run workflow**, pick the branch, optionally set `build_number`, and optionally untick `upload` for a sign-and-export dry run. CLI: `gh workflow run testflight.yml --ref main` (add `-f build_number=10050` or `-f upload=false`).
- **Tag:** push a tag like `v3.5.8` (`git tag v3.5.8 && git push origin v3.5.8`). The tag is only a trigger; the marketing version still comes from `project.pbxproj`, and the job warns if they differ.
- It does **not** run on pushes to `main` or on pull requests.

Artifacts per run: the signed `.ipa` plus a dSYMs zip (30 days) and the resolve/archive/export/upload logs (14 days). TestFlight notes (`release_notes.txt`) are **not** pushed by this workflow; set What to Test in App Store Connect if needed.

### Runner and cost

Runs on `macos-26` with Xcode 26.6 selected via `xcode-select` (the project's iOS 26.5 deployment target needs the iOS 26.5 SDK). This repo is currently **public**, so GitHub-hosted macOS minutes are free. If the repo is ever made private, macOS minutes bill at **10x** the Linux rate against the plan's included minutes; one archive + upload is roughly 15–25 minutes.

### Watch target

The Pickems scheme does not embed PickemsWatch today (the `Embed Watch Content` phase exists but is not attached to the Pickems target; see [WIDGETS_WATCH.md](WIDGETS_WATCH.md)). The workflow still bumps its build number so all three stay in lockstep. If the watch app is embedded later, cloud signing will also need to provision `FannypackInc.Pickems.watchkitapp`, and the job's version check already inspects `Pickems.app/Watch/*.app`.
