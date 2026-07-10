# Widget, Live Activity & Watch Setup

Source for these targets lives in the repo. Add the Xcode targets once on a Mac, then keep the folders in sync.

## App Group

All targets must share:

`group.FannypackInc.Pickems`

Already listed in `Pickems/Pickems.entitlements`.

## 1. Widget Extension

1. Xcode → File → New → Target → **Widget Extension**
2. Product name: `PickemsWidget`
3. Include **Live Activity**
4. Replace generated sources with files under `/PickemsWidget/`
5. Add App Group capability matching the main app
6. Embed the extension in the Pickems app target

## 2. Watch App

1. Xcode → File → New → Target → **Watch App**
2. Product name: `PickemsWatch`
3. Replace sources with `/PickemsWatch/`
4. Enable the same App Group
5. Complications can read `PickemsAppGroup.load()` for rank / W–L

## 3. Live Activities

- `NSSupportsLiveActivities` is set in `Pickems/Info.plist`
- `LiveActivityController` starts/updates/ends activities when the week is locked / live
- Lock Screen + Dynamic Island UI is in `PickemsWidget/PickemsLiveActivityWidget.swift`

## Data flow

Main app → `WidgetSnapshotService.publish` → App Group `StandingsSnapshot` → Widget / Watch / Live Activity timelines.
