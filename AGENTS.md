# AGENTS.md

## Cursor Cloud specific instructions

### What runs where
Pickems is a **SwiftUI iOS app** (`Pickems/`, `PickemsWatch/`, `PickemsWidget/`,
`Pickems.xcodeproj`) plus a **Firebase backend** (`firebase/`) and a static
marketing site (`web/`). The iOS/watchOS/widget targets require **Xcode/macOS and
cannot be built or run on this Linux VM** — only the Firebase backend, the React
admin portal, the rules tests, and the static site are runnable here. Treat the
Firebase side as the dev-environment scope on this VM.

### Node packages (all under `firebase/`)
Dependencies for the three Node packages are installed by the startup update
script (`npm install` in each). They are:
- `firebase/functions` — Cloud Functions (Node 20 engine, TypeScript). Build/lint
  commands are in its `package.json` (`build` = `tsc`, `lint` = `tsc --noEmit`).
- `firebase/admin` — React 18 + Vite 5 + Tailwind admin portal. Commands in its
  `package.json` (`dev`, `dev:emulators`, `build`, `typecheck`, `lint`); see
  `firebase/admin/README.md`.
- `firebase/tests` — Firestore security-rules unit tests (`vitest`); see
  `firebase/tests/README.md`.

### firebase-tools / emulators
`firebase-tools` is installed globally by the update script, so the `firebase`
command is on `PATH`. The Firestore emulator is a Java binary and the VM already
has a JRE (Java 21), so no extra install is needed.

Start the full suite from the `firebase/` directory:
`firebase emulators:start --only auth,firestore,functions,hosting --project pickems-fb`
(UI at `:4000`, auth `:9099`, firestore `:8080`, functions `:5001`, hosting `:5000`).
The three pubsub-scheduled functions (`deadlineReminders`, `lockAndScoreWeeks`,
`autoCloseSeasons`) are logged as "ignored" because the pubsub emulator is not
started — this is expected and harmless.

### Non-obvious caveats
- **Build functions before starting the functions emulator.** `firebase/functions`
  compiles to `lib/` (gitignored), and the emulator loads `lib/index.js`. The
  update script does not build (build steps are kept out of it), so run
  `npm --prefix firebase/functions run build` first, or use
  `npm --prefix firebase/functions run serve` (build + functions emulator). The
  Firestore **rules tests do not need the functions build** — they only use the
  Firestore emulator.
- **Rules tests** are run via the emulator, e.g. from `firebase/`:
  `firebase emulators:exec --only firestore --project pickems-fb "npm --prefix tests test"`.
- **Admin portal against emulators:** `npm --prefix firebase/admin run dev:emulators`
  (Vite on `:5173`). `firebase/admin/src/lib/firebase.ts` points auth/firestore/
  functions at local emulator ports when `VITE_USE_EMULATORS=true`. A local
  `firebase/admin/.env.local` (gitignored) can hold the non-secret Vite config;
  without it the build still works but the login screen shows a "Firebase config
  is missing" banner.
- **Admin login requires the `admin` custom claim.** In the emulator, create a
  user and set `{ admin: true }` via the Admin SDK (Firebase Admin SDK is already
  in `firebase/functions/node_modules`) with `FIREBASE_AUTH_EMULATOR_HOST` and
  `FIRESTORE_EMULATOR_HOST` set to the emulator ports. This mirrors the
  service-account bootstrap described in `firebase/README.md`. A user without the
  claim is signed straight back out with "This account is not authorized."
- Deploys (`scripts/deploy-firebase.sh`, `firebase deploy`) need real Firebase
  credentials (`FIREBASE_TOKEN` or `GOOGLE_APPLICATION_CREDENTIALS`) and target
  live project `pickems-fb`; do not run them from the cloud VM without credentials.
