# Force minimum build SOP

Raise `appConfig/live.minimumBuild` so older binaries show a full-screen **Update required** gate. The only exit is the public App Store listing (`https://apps.apple.com/app/id6785697079`).

Agent entry point: `.cursor/skills/ship-ios/SKILL.md`. Related: [TESTFLIGHT.md](TESTFLIGHT.md), [APP_STORE.md](APP_STORE.md), admin portal [ADMIN_PORTAL_SOP.md](ADMIN_PORTAL_SOP.md) §8.

---

## Identity

| | |
|--|--|
| Firebase project | `pickems-fb` |
| Document | `appConfig/live` |
| Field | `minimumBuild` (positive integer; blank / `null` / `0` = no gate) |
| Writes | Super-admin only (`firestore.rules`) |
| Reads | Any signed-in client (snapshot listener) |

---

## Do not

- Raise the gate unless the user **explicitly** asked to force a minimum build / force-update
- Set `minimumBuild` **above** the build currently downloadable on the **App Store**
- Treat a TestFlight-only build as a safe ceiling — the gate’s button does not open TestFlight
- Raise it while the new version is still `WAITING_FOR_REVIEW`, `PENDING_DEVELOPER_RELEASE` (**Apple Approved** is this state), or processing
- Treat “Apple approved the TestFlight build” as store-live. Release type is `AFTER_APPROVAL`; the public listing stays on the previous version until someone **releases** it
- Overwrite the rest of `appConfig/live` (chat flags, announcements). Merge `minimumBuild` only
- Leave a typo string in the field and assume it blocks anyone — unreadable / non-positive values **fail open** (gate off)

---

## How it is enforced (not a Cloud Function)

Nothing in `firebase/functions` reads `minimumBuild`. Callables, scheduled jobs, and Firestore rules do **not** reject old binaries. A blocked user can still hit the backend if they bypass the UI.

The gate is honor-system UI in the iOS app:

1. `AppState.configure()` starts `LiveAppConfigService`, which snapshot-listens to `appConfig/live`.
2. `ForceUpdatePolicy` compares this binary’s `CFBundleVersion` to `minimumBuild`. Block when `currentBuild < minimumBuild`. Equal builds pass.
3. `RootView` swaps the whole app for `ForceUpdateView` when `liveConfig.requiresUpdate` is true. That screen cannot be dismissed; the button opens `https://apps.apple.com/app/id6785697079`.
4. Join / favorite-team sheets in `PickemsApp` are also suppressed while the gate is on.

Missing, `0`, negative, or unparsable `minimumBuild` → no gate. If the document is unreadable, the gate stays **off** (fail open).

Binaries shipped **before** this client code existed will ignore the field entirely. There is no server-side backstop for those.

---

## Safe value

Use the **App Store** binary’s build number (the `READY_FOR_DISTRIBUTION` iOS version’s attached build, e.g. `323` for `3.2.3`).

That is the maximum. You may set a **lower** already-shipped store build if you only need to cut off very old binaries.

```text
minimumBuild  ≤  App Store CFBundleVersion
```

If a version is approved but not yet released (`AFTER_APPROVAL` / `PENDING_DEVELOPER_RELEASE`), the live listing is still the previous version. Wait until that version is actually on the store, then raise the gate.

The force-update button opens `https://apps.apple.com/app/id6785697079`. If `minimumBuild` is **above** what that URL installs, users are stuck on **Update required** with no TestFlight escape.

### Public store check (required; no Connect login)

```bash
python3 - <<'PY'
import json, urllib.request
with urllib.request.urlopen("https://itunes.apple.com/lookup?id=6785697079") as r:
    app = json.load(r)["results"][0]
print(app["version"], app["currentVersionReleaseDate"])
PY
```

`version` is the marketing string (`3.3.2`), not the build. Convention: `3.3.2` ↔ build `332`. Do not write `332` until this lookup prints `3.3.2`.

---

## Worked example: force 332 (3.3.2)

Use this after Apple approves TestFlight build `332` and the user asks to force-update onto it.

1. Confirm the ask: force-update / raise `minimumBuild` to **332**.
2. Run the public store check above.
   - Lookup still `3.2.3` (or anything other than `3.3.2`) → **stop**. Do not write Firestore. 332 is not downloadable from the App Store yet.
   - Lookup `3.3.2` → continue.
3. In App Store Connect, confirm the iOS version is `READY_FOR_DISTRIBUTION` and the attached build is `332`.
4. Read `appConfig/live.minimumBuild` (portal `/config`, or `firestore_get_document` on `projects/pickems-fb/databases/(default)/documents/appConfig/live`).
5. Set `minimumBuild` to `332` (portal Publish, or masked update below). Read it back.
6. Tell the user: anyone on `CFBundleVersion` **strictly below 332** sees **Update required** and is sent to the App Store. Build **332** and newer pass. TestFlight-only builds above 332 are unaffected; App Store users can only install what the listing serves.

---

## 1. Confirm the ask and the store build

1. User asked to force-update / raise `minimumBuild`.
2. Public store check (above) matches the intended marketing version.
3. In App Store Connect (Chrome iris), confirm the target iOS version is `READY_FOR_DISTRIBUTION` and note its attached build number.
4. Read the current field before writing.

Portal: `/config` on the admin app. Agent: `firestore_get_document` on

`projects/pickems-fb/databases/(default)/documents/appConfig/live`

---

## 2. Set the field

**Human (preferred):** Admin portal → **App config** → `minimumBuild` → Publish. Confirm the warning. Blank clears the gate (`null`).

**Agent (only when asked, and only after the public store check passes):** `firestore_update_document` with `updateMask.fieldPaths: ["minimumBuild"]` so other flags are untouched. Integer string, e.g. `"332"`. Then read the document back.

Do not use the portal’s raw-JSON merge for this field.

---

## 3. Lower or clear the gate

- Portal: clear the input and Publish (`null`)
- Agent: update `minimumBuild` to `null` or a lower integer, masked to that field only

Takes effect on the next snapshot for signed-in clients.

---

## 4. Tell the user

- Old value → new value
- Who is blocked: `CFBundleVersion` **strictly below** the new minimum
- Who is not: that build and newer, including the live App Store binary
- Reminder: TestFlight-only testers above the store build are fine; App Store users cannot install a TestFlight-only minimum
