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

In `Pickems.xcodeproj/project.pbxproj`, replace the **current shipping** marketing version and build on Pickems, PickemsWidget, and PickemsWatch (Debug + Release). Convention: marketing `X.Y.Z` ↔ build `XYZ` (example: `3.2.3` / `323`).

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
