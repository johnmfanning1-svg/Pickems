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
4. Build the **Pickems** scheme (embeds widget; Watch is **not** embedded in 1.2.4 App Store builds — re-add Embed Watch Content when watchOS SDK is available)

### Build / UAT note

- Prefer the **Pickems** scheme (iPhone + **PickemsWidget**). Do **not** select **PickemsWatch** as the run destination or add it to the active scheme for iOS UAT — Watch embed objects in the project are orphaned / incomplete; building Watch can block an otherwise good iPhone + widget build.
- Widget empty App Group: Home Screen shows “Open Pickems” (no demo “Saturday Crew” standings). Placeholder/demo data is only for WidgetKit `placeholder` / `context.isPreview`.
- **Preseason:** before Week 0 (2026: Thu Aug 27 ET), the widget shows a countdown to the first day of college football. After Week 0 starts it shows **current-week** group standings (open the Home tab once so App Group data stays fresh).

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
