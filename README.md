# Pickems

Custom iOS SwiftUI app for the Fannypack

## Features
- Live ESPN CFB game data & spreads
- Private league picks & standings
- Groups and live game info tracking
- **X (Twitter) sharing** for weekly and end-of-year results

Built with SwiftUI + Xcode.

## X / Twitter Social Sharing

Users can brag about weekly and season results on X to dunk on friends and drive traffic back to Pickems.

### Sharing options

1. **Open in X** — Uses `twitter.com/intent/tweet` with pre-filled brag text (no API key required)
2. **Share image + text** — Renders a branded results card and opens the iOS share sheet
3. **Post directly** — OAuth 2.0 PKCE + X API v2 for in-app posting (optional)

### Key files

| Area | Path |
|------|------|
| Share models | `Pickems/Models/ShareableResult.swift`, `ShareSource.swift` |
| Tweet copy | `Pickems/Services/ShareTextBuilder.swift` |
| X OAuth | `Pickems/Services/XAuthService.swift` |
| X posting | `Pickems/Services/XShareService.swift` |
| Share card UI | `Pickems/Views/Share/ResultsShareCard.swift` |
| Share flow | `Pickems/Views/Share/ShareResultsSheet.swift` |
| Weekly hook | `Pickems/Views/Standings/WeeklyStandingsView.swift` |
| Season hook | `Pickems/Views/Standings/SeasonStandingsView.swift` |
| Settings | `Pickems/Views/Settings/XConnectionSettingsView.swift` |

### Setup

1. Add the `Pickems/` source folder to your Xcode target.
2. Merge `Pickems/Resources/InfoPlist-additions.xml` into your app `Info.plist`:
   - URL scheme `pickems` for OAuth callback
   - `twitter` in `LSApplicationQueriesSchemes` for X app deep links
3. Create an app at [developer.x.com](https://developer.x.com) with OAuth 2.0 enabled.
4. Set your Client ID in `Pickems/Utilities/AppConfig.swift`.
5. Register callback URL: `pickems://x-callback`
6. Update `appPromoURL` and `appStoreURL` when your marketing links are live.

### Integration with standings

When your scoring service finalizes results, trigger the share flow:

```swift
// After weekly scoring locks
shareCoordinator.presentWeeklyShareIfEligible(weeklyResult)

// After season ends
shareCoordinator.presentSeasonShareIfEligible(seasonStanding)
```

Wire `ShareResultsButton` into your real standings views:

```swift
ShareResultsButton(source: .weekly(userWeeklyResult))
ShareResultsButton(source: .season(userSeasonStanding))
```

### Share tone

Users can pick **Auto**, **Humble Brag**, or **Full Dunk** before posting. Auto selects dunk copy for podium finishes and weekly wins.

### Tweet format

Weekly example:

```
Week 7 Pickems 🏈
2nd of 12 in Fannypack • 8/10 correct • TB +3
Podium finish while the rest of the league is in shambles.
https://pickems.app
#CFB #Pickems
```

Season example:

```
2025 Fannypack — Final Standings
🥈 2nd of 12 • 87 pts • 4 weekly wins • Best: Wk 5 (9/10)
Runner-up. The only person who beat the whole league all year? Me, almost.
https://pickems.app
#CFB #Pickems
```
