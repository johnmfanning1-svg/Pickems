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
- Raise it while the new version is still `WAITING_FOR_REVIEW`, `PENDING_DEVELOPER_RELEASE`, or processing
- Overwrite the rest of `appConfig/live` (chat flags, announcements). Merge `minimumBuild` only
- Leave a typo string in the field and assume it blocks anyone — unreadable / non-positive values **fail open** (gate off)

---

## How the gate behaves

`ForceUpdatePolicy.requiresUpdate` is `currentBuild < minimumBuild` (`CFBundleVersion`). Equal builds are allowed.

`LiveAppConfigService` listens to `appConfig/live`. Signed-in users can be blocked **without** relaunching. `ForceUpdateView` cannot be dismissed.

Missing, `0`, negative, or unparsable `minimumBuild` → no gate. If the document is unreadable, the gate stays off.

---

## Safe value

Use the **App Store** binary’s build number (the `READY_FOR_DISTRIBUTION` iOS version’s attached build, e.g. `323` for `3.2.3`).

That is the maximum. You may set a **lower** already-shipped store build if you only need to cut off very old binaries.

```text
minimumBuild  ≤  App Store CFBundleVersion
```

If 3.2.3 is approved but not yet released (`AFTER_APPROVAL`), the live listing is still the previous version. Wait until that version is actually on the store, then raise the gate.

---

## 1. Confirm the ask and the store build

1. User asked to force-update / raise `minimumBuild`.
2. In App Store Connect (Chrome iris), confirm the target iOS version is `READY_FOR_DISTRIBUTION` and note its attached build number.
3. Read the current field before writing.

Portal: `/config` on the admin app. Agent: `firestore_get_document` on

`projects/pickems-fb/databases/(default)/documents/appConfig/live`

---

## 2. Set the field

**Human (preferred):** Admin portal → **App config** → `minimumBuild` → Publish. Confirm the warning. Blank clears the gate (`null`).

**Agent (only when asked):** `firestore_update_document` with `updateMask.fieldPaths: ["minimumBuild"]` so other flags are untouched. Integer string, e.g. `"323"`. Then read the document back.

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
