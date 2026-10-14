# Widget & Live Activity Setup

There is no Apple Watch app. The unused PickemsWatch target was removed in #99 (it had not been embedded in any build since 1.2.4).

Targets are wired into `Pickems.xcodeproj`:

| Target | Bundle ID | Folder |
|--------|-----------|--------|
| PickemsWidget | `FannypackInc.Pickems.widget` | `PickemsWidget/` |

## App Group

All targets share:

`group.FannypackInc.Pickems`

Entitlements:

- `Pickems/Pickems.entitlements`
- `PickemsWidget/PickemsWidget.entitlements`

## First open in Xcode

1. Open `Pickems.xcodeproj`
2. Select **PickemsWidget** → Signing & Capabilities → choose Team `22A943P8SJ` (already set)
3. Confirm App Groups capability shows `group.FannypackInc.Pickems` for both targets
4. Build the **Pickems** scheme (embeds the widget)

### Build / UAT note

- Use the **Pickems** scheme (iPhone + **PickemsWidget**).
- Widget empty App Group: Home Screen shows “Open Pickems” (no demo “Saturday Crew” standings). Placeholder/demo data is only for WidgetKit `placeholder` / `context.isPreview`.
- **Preseason:** before season kickoff (2026: Sat Aug 29 ET), the widget shows a countdown to college football kickoff. The first playable slate is **Week 0** (the eight Saturday openers). After kickoff it shows **current-week** group standings (open the Home tab once so App Group data stays fresh).

## Live Activities

- `NSSupportsLiveActivities` is set in `Pickems/Info.plist`
- Attributes: `Pickems/Features/Live/LiveActivityController.swift` (app) and `PickemsWidget/PickemsLiveAttributes.swift` (extension)
- UI: `PickemsWidget/PickemsLiveActivityWidget.swift`

## Data flow

Main app → `WidgetSnapshotService.publish` → App Group `StandingsSnapshot` → Widget / Live Activity.
