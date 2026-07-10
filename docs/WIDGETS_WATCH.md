# Widget, Live Activity & Watch Setup

Targets are wired into `Pickems.xcodeproj`:

| Target | Bundle ID | Folder |
|--------|-----------|--------|
| PickemsWidget | `FannypackInc.Pickems.widget` | `PickemsWidget/` |
| PickemsWatch | `FannypackInc.Pickems.watchkitapp` | `PickemsWatch/` |

## App Group

All targets share:

`group.FannypackInc.Pickems`

Entitlements:

- `Pickems/Pickems.entitlements`
- `PickemsWidget/PickemsWidget.entitlements`
- `PickemsWatch/PickemsWatch.entitlements`

## First open in Xcode

1. Open `Pickems.xcodeproj`
2. Select **PickemsWidget** and **PickemsWatch** → Signing & Capabilities → choose Team `22A943P8SJ` (already set)
3. Confirm App Groups capability shows `group.FannypackInc.Pickems` for all three targets
4. Build the **Pickems** scheme (embeds widget + watch)

## Live Activities

- `NSSupportsLiveActivities` is set in `Pickems/Info.plist`
- Attributes: `Pickems/Features/Live/LiveActivityController.swift` (app) and `PickemsWidget/PickemsLiveAttributes.swift` (extension)
- UI: `PickemsWidget/PickemsLiveActivityWidget.swift`

## Watch Info.plist requirements

Single-target watchOS apps **must** include:

```xml
<key>WKApplication</key>
<true/>
```

Also set `INFOPLIST_KEY_WKApplication = YES` on the PickemsWatch target. Missing this fails App Store validation and can break the embedded Watch bundle inside the iOS app.

## Data flow

Main app → `WidgetSnapshotService.publish` → App Group `StandingsSnapshot` → Widget / Watch / Live Activity.
