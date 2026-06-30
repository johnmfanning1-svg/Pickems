# Pickems

Custom iOS SwiftUI app for the Fannypack

## Features
- Live ESPN CFB game data & spreads
- Private league picks & standings
- Groups and live game info tracking
- **X (Twitter) and text message sharing** for weekly and end-of-year results
- **Invite friends** to Pickems via X or text

Built with SwiftUI + Xcode.

## Open in Xcode

```bash
git clone https://github.com/johnmfanning1-svg/Pickems.git
cd Pickems
open Pickems.xcodeproj
```

1. Set your **Development Team** in Signing & Capabilities
2. Set X OAuth Client ID in `Pickems/Features/Sharing/Utilities/AppConfig.swift`
3. Build and run

Full integration steps for an existing local project: **[docs/XCODE_SYNC.md](docs/XCODE_SYNC.md)**

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

### Wire into your standings views

```swift
// App entry
SharingBootstrap {
    YourExistingRootView()
}

// Weekly results
ShareResultsButton(source: SharingIntegration.weeklySource(
    userId: user.id,
    displayName: user.name,
    week: 7,
    season: 2025,
    leagueName: "Fannypack",
    correctPicks: 8,
    totalPicks: 10,
    rank: 2,
    totalPlayers: 12,
    tiebreakerDelta: 3
))

// Season results
ShareResultsButton(source: SharingIntegration.seasonSource(
    userId: user.id,
    displayName: user.name,
    season: 2025,
    leagueName: "Fannypack",
    totalPoints: 87,
    weeklyWins: 4,
    rank: 2,
    totalPlayers: 12
))

// Invite friends
ShareAppButton(leagueName: "Fannypack", label: "Invite Friends")
```

### Key files

| Area | Path |
|------|------|
| Xcode entry | `Pickems/App/PickemsApp.swift` |
| Integration | `Pickems/Features/Sharing/Integration/` |
| Share models | `Pickems/Features/Sharing/Models/` |
| Services | `Pickems/Features/Sharing/Services/` |
| UI | `Pickems/Features/Sharing/Views/` |
| Xcode project | `Pickems.xcodeproj` |
| Sync guide | `docs/XCODE_SYNC.md` |

### Setup

1. Open `Pickems.xcodeproj` (or sync sharing into your existing project — see `docs/XCODE_SYNC.md`)
2. Merge `Pickems/Resources/InfoPlist-additions.xml` if using an existing Info.plist
3. Create an app at [developer.x.com](https://developer.x.com) with OAuth 2.0 enabled
4. Set Client ID in `AppConfig.swift` and register callback `pickems://x-callback`
5. Update `appPromoURL` and `appStoreURL` when live

### X MCP for Cursor (developers)

This repo includes [hosted X MCP](https://docs.x.com/tools/mcp) so Cursor can search X, read API docs, and prototype sharing features while you build.

1. Copy `.env.example` to `.env` and set `CLIENT_ID` / `CLIENT_SECRET` from your X developer app
2. On that app, also register redirect URI `http://localhost:8080/callback` (for the MCP bridge; separate from the iOS `pickems://x-callback`)
3. Open **Cursor → Settings → MCP** — `xapi` and `x-docs` should appear from `.cursor/mcp.json`
4. On first `xapi` use, complete the browser OAuth login once; the bridge caches the token

`x-docs` needs no credentials. Use both together to look up endpoints and try API calls without leaving the editor.

### Regenerate Xcode project after adding files

```bash
python3 scripts/generate_xcode_project.py
```

Or with XcodeGen: `xcodegen generate`
