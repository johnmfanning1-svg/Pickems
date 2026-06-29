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
6. Download `GoogleService-Info.plist` and replace the placeholder in `Pickems/Pickems/GoogleService-Info.plist`
7. Deploy backend:

```bash
cd firebase
npm install --prefix functions
npm run build --prefix functions
npx firebase-tools@latest deploy --only firestore:rules,functions
```

## Apple Setup

1. Enable **Sign in with Apple** capability for `FannypackInc.Pickems` in Apple Developer portal
2. Add push notification capability
3. Configure APNs key in Firebase Console → Project Settings → Cloud Messaging

## Project Structure

```
Pickems/Pickems/
├── App/              App entry, tab navigation
├── Core/             Models, services, scoring engine
├── DesignSystem/     Dark theme, red accents, components
├── Features/         Auth, Home, Groups, Picks, Profile
firebase/
├── firestore.rules
└── functions/        Slate lock, scoring, push reminders
```

## Commissioner Settings

Each group commissioner can configure:
- **Selection mode**: Commissioner selects games OR members nominate
- **Selections per member**: How many games each member nominates (member mode)
- **Slate size**: Total games per week
- **Deadline & tie-breaker** policies

## App Store

See [docs/APP_STORE.md](docs/APP_STORE.md) and [docs/privacy-policy.md](docs/privacy-policy.md).

## Cost

Designed for **$0/month** infrastructure at MVP scale using Firebase free tier.
