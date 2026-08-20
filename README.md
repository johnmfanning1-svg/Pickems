# Pickems

College football pick'em iOS app built with SwiftUI and Firebase.

## Requirements

- Xcode 16+
- Apple Developer Program ($99/yr)
- Firebase project on Blaze plan with **$5 budget cap** (see setup below)

## Firebase Setup

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com) named `pickems-prod`
2. Enable **Authentication** → **Sign in with Apple** and **Email/Password**
3. Create a Firestore database (production mode)
4. Upgrade to **Blaze** plan and set billing budget: $1 alert, $5 cap in Google Cloud Console
5. Register iOS app with bundle ID `FannypackInc.Pickems`
6. Download `GoogleService-Info.plist` and replace the placeholder in `Pickems/GoogleService-Info.plist`
7. Deploy backend:

```bash
cd firebase
npm install --prefix functions
npm run build --prefix functions
npx firebase-tools@latest deploy --only firestore:rules,functions
```

### Cloud Functions (included)

| Function | Role |
|----------|------|
| `onWeekStatusChange` | Materialize nominations → games; week scored push |
| `deadlineReminders` | FCM to members who haven't submitted |
| `lockAndScoreWeeks` | Lock at deadline, ESPN score sync, standings, game-final / lead-change push |
| `autoCloseSeasons` | Mid-January dynasty archive |
| `syncPublicLeagueIndex` | Discover index for public leagues |

## Apple Setup

1. Enable **Sign in with Apple** capability for `FannypackInc.Pickems`
2. Add push notification capability + App Group `group.FannypackInc.Pickems`
3. Configure APNs key in Firebase Console → Cloud Messaging
4. Add Widget / Watch targets once — see [docs/WIDGETS_WATCH.md](docs/WIDGETS_WATCH.md)

## Project Structure

```
Pickems/                 Main iOS app (SwiftUI)
PickemsWidget/           Widget + Live Activity sources
PickemsWatch/            watchOS glance sources
firebase/
  firestore.rules
  functions/             Slate lock, scoring, push, season close
```

## 2.0 Features

- Favorite-team theming
- Multi-season dynasty wall + career records
- Cover Moments, week awards, streak badges
- Confidence picks + late-pick policy (commissioner)
- Discover public leagues + rivalry head-to-head
- Home Screen widgets / Live Activities / Watch (sources + App Group)

## Debugging

Pickems logs structured events via `OSLog` (`AppLog` / `AppEvents`) and records non-fatals to **Firebase Crashlytics** when linked.

In Console.app, filter by subsystem `FannypackInc.Pickems` (or your bundle id) and categories such as `auth`, `onboarding`, `session`, `events`, `firestore`.

Useful event names:

| Event | When |
|-------|------|
| `auth.sign_in_failed` / `auth.sign_up_failed` | Email auth failure |
| `auth.apple_failed` | Sign in with Apple failure |
| `root.destination_changed` | Left/entered Sign In, Onboarding, or Home |
| `onboarding.join_failed` / `onboarding.create_failed` | League join/create failure |
| `auth.profile_sync_failed` | Firestore profile write/load issue |
| `groups.decode_dropped` | Group document could not be decoded |

Emails, passwords, and tokens are redacted from event metadata.

See [docs/DEBUGGING.md](docs/DEBUGGING.md) for Console.app filters and a healthy auth event trail.

## X MCP for Cursor (developers)

Hosted [X MCP](https://docs.x.com/tools/mcp) so Cursor can search X, read API docs, and prototype sharing features.

1. Copy `.env.example` to `.env` and set `CLIENT_ID` / `CLIENT_SECRET` from your X developer app
2. On that app, also register redirect URI `http://localhost:8080/callback` (for the MCP bridge; separate from the iOS `pickems://x-callback`)
3. Open **Cursor → Settings → MCP** — `xapi` and `x-docs` should appear from `.cursor/mcp.json`
4. On first `xapi` use, complete the browser OAuth login once; the bridge caches the token

`x-docs` needs no credentials. Use both together to look up endpoints and try API calls without leaving the editor.

## Commissioner Settings

- Selection mode, slate size, deadlines, tie-breakers
- Confidence pick, late picks, Discover listing
- Submission chase, close season

## App Store

See [docs/APP_STORE.md](docs/APP_STORE.md) and [docs/privacy-policy.md](docs/privacy-policy.md).

## Cost

Designed for low infrastructure cost at MVP scale using Firebase free/Blaze with a hard budget cap.
