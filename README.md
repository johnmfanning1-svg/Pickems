# Pickems

Custom iOS SwiftUI app for the Fannypack

## Features
- Live ESPN CFB game data & spreads
- Private league picks & standings
- Groups and live game info tracking
- **X (Twitter) and text message sharing** for weekly and end-of-year results
- **Invite friends** to Pickems via X or text

Built with SwiftUI + Xcode.

## Social Sharing

Users can brag about weekly and season results, and invite friends to Pickems, via **X** or **text message**.

### Results sharing

1. **Share on X** — Pre-filled tweet with brag copy (no API key required)
2. **Text Message** — Opens iMessage/SMS with pre-filled body and optional results card image
3. **More Sharing Options** — iOS share sheet for AirDrop, copy, etc.
4. **Post directly to X** — OAuth 2.0 PKCE + X API v2 (optional)

### App invite sharing

1. **Share App on X** — Pre-filled invite tweet with promo link and hashtags
2. **Text Invite** — Pre-filled SMS/iMessage invite with App Store link
3. **More Sharing Options** — Standard iOS share sheet

### Key files

| Area | Path |
|------|------|
| Share models | `Pickems/Models/ShareableResult.swift`, `ShareSource.swift`, `AppShareContent.swift` |
| Tweet / message copy | `Pickems/Services/ShareTextBuilder.swift`, `AppShareTextBuilder.swift` |
| Text messages | `Pickems/Services/MessageShareService.swift`, `Views/Share/MessageComposeView.swift` |
| X OAuth | `Pickems/Services/XAuthService.swift` |
| X posting | `Pickems/Services/XShareService.swift` |
| Results share flow | `Pickems/Views/Share/ShareResultsSheet.swift` |
| App invite flow | `Pickems/Views/Share/ShareAppSheet.swift`, `ShareAppButton.swift` |
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

Invite friends from settings or anywhere in the app:

```swift
ShareAppButton(leagueName: userLeagueName, label: "Invite Friends")
```

### Share tone

Users can pick **Auto**, **Humble Brag**, or **Full Dunk** before posting. Auto selects dunk copy for podium finishes and weekly wins.

### Message format

Weekly text example (no hashtags):

```
Week 7 Pickems 🏈
2nd of 12 in Fannypack • 8/10 correct • TB +3
Podium finish while the rest of the league is in shambles.
https://pickems.app
```

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
