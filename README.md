# Pickems

College football pick'em iOS app built with SwiftUI and Firebase.

## Requirements

- Xcode 16+
- Apple Developer Program ($99/yr)
- Firebase project on Blaze plan with **$5 budget cap** (see setup below)

## Firebase Setup

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com) named `pickems-prod`
2. Enable **Authentication** → Sign in with Apple only (passwordless)
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

## Commissioner Settings

- Selection mode, slate size, deadlines, tie-breakers
- Confidence pick, late picks, Discover listing
- Submission chase, close season

## App Store

See [docs/APP_STORE.md](docs/APP_STORE.md) and [docs/privacy-policy.md](docs/privacy-policy.md).

## Cost

Designed for low infrastructure cost at MVP scale using Firebase free/Blaze with a hard budget cap.
