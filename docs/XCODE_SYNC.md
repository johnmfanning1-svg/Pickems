# Xcode Sync Guide

This repo is now structured for direct Xcode use. `main` contains the sharing module, a generated Xcode project, and integration hooks.

## Quick start (open in Xcode)

1. Clone or pull `main` on your Mac:
   ```bash
   git clone https://github.com/johnmfanning1-svg/Pickems.git
   cd Pickems
   ```
2. Open `Pickems.xcodeproj` in Xcode.
3. Select your **Development Team** in Signing & Capabilities for the Pickems target.
4. Set your X OAuth Client ID in `Pickems/Features/Sharing/Utilities/AppConfig.swift`.
5. Build and run on a device or simulator.

The included `RootView` is a demo tab bar for testing sharing. Replace it with your real app navigation when ready.

## If you already have a local Pickems Xcode project

Use the sync script to copy sharing into your existing project:

```bash
./scripts/sync-sharing-to-local.sh ~/Developer/Pickems
```

Then in Xcode:

### 1. Add files to target

Ensure these folders are in your app target’s **Compile Sources**:

```
Pickems/Features/Sharing/
Pickems/Features/SmackTalk/
```

### 2. Merge Info.plist entries

From `Pickems/Resources/InfoPlist-additions.xml`, add:

- URL scheme: `pickems` (OAuth callback `pickems://x-callback`)
- Query scheme: `twitter`

### 3. Bootstrap sharing and smack talk at app launch

In your `@main` app file:

```swift
@main
struct PickemsApp: App {
    var body: some Scene {
        WindowGroup {
            SmackTalkBootstrap {
                SharingBootstrap {
                    YourExistingRootView()
                }
            }
        }
    }
}
```

### 4. Wire standings views

Add share buttons where users see results:

```swift
ShareResultsButton(
    source: SharingIntegration.weeklySource(
        userId: currentUser.id,
        displayName: currentUser.name,
        week: week,
        season: season,
        leagueName: league.name,
        correctPicks: standing.correct,
        totalPicks: standing.total,
        rank: standing.rank,
        totalPlayers: league.memberCount,
        tiebreakerDelta: standing.tiebreakerDelta,
        isWeeklyWinner: standing.rank == 1
    )
)
```

Season:

```swift
ShareResultsButton(
    source: SharingIntegration.seasonSource(
        userId: currentUser.id,
        displayName: currentUser.name,
        season: season,
        leagueName: league.name,
        totalPoints: standing.points,
        weeklyWins: standing.weeklyWins,
        rank: standing.rank,
        totalPlayers: league.memberCount,
        bestWeek: standing.bestWeek,
        bestWeekRecord: standing.bestWeekRecord
    )
)
```

### 5. Invite friends

```swift
ShareAppButton(leagueName: league.name, label: "Invite Friends")
```

### 6. Auto-prompt after scoring locks

Inject `ResultsShareCoordinator` from the environment (provided by `SharingBootstrap`):

```swift
@EnvironmentObject private var shareCoordinator: ResultsShareCoordinator

// After weekly scoring finalizes
shareCoordinator.presentWeeklyShareIfEligible(weeklyResult)
```

### 7. Week-to-week smack talk

Add a chat entry point on weekly standings:

```swift
SmackTalkButton(
    context: SmackTalkIntegration.context(
        userId: currentUser.id,
        displayName: currentUser.name,
        leagueId: league.id,
        leagueName: league.name,
        season: season,
        week: week
    ),
    weeklyResult: weeklyResult
)
```

Post a system message when weekly scoring finalizes:

```swift
@EnvironmentObject private var smackTalkService: LocalSmackTalkService

try await smackTalkService.postSystemMessage(
    text: SmackTalkIntegration.systemMessage(for: weeklyResult),
    thread: SmackTalkIntegration.thread(
        leagueId: league.id,
        leagueName: league.name,
        season: season,
        week: week
    )
)
```

For production, replace `LocalSmackTalkService` with a backend implementation of `SmackTalkServing` (Firestore recommended).

## Regenerating the Xcode project

If you add new Swift files under `Pickems/`:

```bash
python3 scripts/generate_xcode_project.py
```

Or, if you use [XcodeGen](https://github.com/yonaskolb/XcodeGen) on your Mac:

```bash
brew install xcodegen
xcodegen generate
```

## Recommended git workflow

```bash
# On your Mac
cd ~/Developer/Pickems
git remote add github https://github.com/johnmfanning1-svg/Pickems.git   # if needed
git fetch github
git merge github/main
```

If your local project has diverged, merge `main` into your branch and resolve conflicts in `PickemsApp.swift` / `RootView` only — the sharing module under `Pickems/Features/Sharing/` should merge cleanly.

## Project layout

```
Pickems/
  App/
    PickemsApp.swift          # @main entry
    RootView.swift            # demo root (replace with your navigation)
  Features/
    Sharing/
      Integration/            # SharingBootstrap, SharingIntegration
      Models/
      Services/
      Views/
      Utilities/
    SmackTalk/
      Integration/            # SmackTalkBootstrap, SmackTalkIntegration
      Models/
      Services/
      Views/
      Utilities/
  Resources/
    Info.plist
    Assets.xcassets/
Pickems.xcodeproj/
PickemsTests/
scripts/
  generate_xcode_project.py
  sync-sharing-to-local.sh
```
