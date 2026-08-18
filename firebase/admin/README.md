# Pickems web admin portal

Ops console for Pickems, deployed to Firebase Hosting at `https://pickems-fb.web.app`.
Vite 5 + React 18 + TypeScript + Tailwind 3 + React Router 6 + Firebase JS SDK 10
(modular).

> **The UI is not the security boundary.** Hosting is public and this bundle is
> readable by anyone who finds the URL. The `RequireAdmin` guard exists so a
> non-admin sees a clear rejection instead of a wall of permission errors — the
> actual gate is `isSuperAdmin()` in `../firestore.rules` and
> `requireSuperAdmin()` in `../functions/src/admin.ts`. Every screen here is
> written to still behave correctly if someone strips the guard out of the bundle.

## Setup

```bash
cd firebase/admin
npm ci                      # or npm install on a fresh clone
cp .env.example .env.local
```

Fill `.env.local` from the **web** app's config — not `GoogleService-Info.plist`,
which belongs to a different Firebase app with a different `appId` and API key:

```bash
firebase apps:sdkconfig WEB --project pickems-fb
```

| Key | Notes |
|--|--|
| `VITE_FIREBASE_API_KEY` | required |
| `VITE_FIREBASE_AUTH_DOMAIN` | `pickems-fb.firebaseapp.com` |
| `VITE_FIREBASE_PROJECT_ID` | `pickems-fb` |
| `VITE_FIREBASE_STORAGE_BUCKET` | `pickems-fb.firebasestorage.app` |
| `VITE_FIREBASE_MESSAGING_SENDER_ID` | required |
| `VITE_FIREBASE_APP_ID` | required |
| `VITE_USE_EMULATORS` | `true` points auth/firestore/functions at local emulators |
| `VITE_FUNCTIONS_REGION` | `us-central1` — must match the deployed callables |
| `VITE_ENVIRONMENT_LABEL` | shown in the header so prod is never mistaken for staging |

`.env.local` is gitignored. None of these values are secrets in the usual sense
(they ship in a public bundle), but they are environment-specific, so they stay
out of git. The build falls back to placeholders when they are absent, which is
why `npm run build` works on a clean checkout — a placeholder build renders a
"Firebase config is missing" banner on the login screen rather than crashing.

## Commands

| Command | What it does |
|--|--|
| `npm run dev` | Vite dev server on :5173 against **production** Firebase |
| `npm run dev:emulators` | same, but against the local emulator suite |
| `npm run build` | `tsc --noEmit` then `vite build` into `dist/` (release gate G3) |
| `npm run typecheck` | types only |
| `npm run lint` | eslint, zero warnings tolerated |
| `npm run preview` | serves the built `dist/` locally |

### Against emulators

```bash
cd firebase && firebase emulators:start          # auth 9099, firestore 8080, functions 5001
cd admin && npm run dev:emulators
```

The emulator Auth UI has no custom claims editor, so create a user in the
emulator and set the claim through the emulator's REST API, or run against
production with a real admin account. The header badge turns blue in emulator
mode and red in production.

## Auth gate

1. `signInWithEmailAndPassword` or a `GoogleAuthProvider` popup.
2. `getIdTokenResult(true)` — a **forced** refresh, because a claim granted
   moments ago is absent from the cached token.
3. `claims.admin !== true` → immediate `signOut()` and
   "This account is not authorized." No half-authenticated session is left behind.
4. `RequireAdmin` wraps every route except `/login`.
5. The claim is re-checked on `onIdTokenChanged`, which fires on the hourly token
   refresh — so a revoked admin loses access within the hour without anyone having
   to sign them out.

Grant the first admin from a machine with a service-account key (see
`../README.md`), then use `/config` → **Super-admin roles** for everyone after.

## Routes

| Route | Purpose | Backing |
|--|--|--|
| `/login` | email/password + Google, forced claim check | Auth |
| `/` | group/user counts, weeks by status, recent `adminAudit` | Firestore reads |
| `/groups` | searchable league list | `groups` |
| `/groups/:id` | rename, Discover visibility, `GroupRules`, invite code, delete | direct writes + `inviteCodes` |
| `/groups/:id/members` | add/remove, transfer commissioner, reset season W-L | `adminRemoveMember`, `adminTransferCommissioner` |
| `/groups/:id/weeks` | status transitions, `pickDeadline`, re-materialize, spreads, delete | `adminSetWeekStatus`, `adminRematerializeNominations` |
| `/groups/:id/weeks/:weekId/picks` | members × slate grid, edit picks, lock/unlock, rescore | `adminUpsertPick`, `adminRescoreWeek` |
| `/config` | `appConfig/live` flags + super-admin roles | `appConfig`, `setAdminRole` |
| `/audit/weeks` | Risk R1 tool — misaligned, duplicate, orphan weeks; 2026 Week 0 split | `adminAuditWeekIds`, `adminMigrateWeek0Split` |
| `/audit/log` | append-only admin action log | `adminAudit` |
| `/moderation` | messages with `reportCount > 0` | `messages` collection group + `reports` |

## Conventions

- **Every mutating action confirms first**, and the dialog names the target.
  Destructive ones (delete league, remove member, delete week, grant/revoke
  admin) require typing the target's name.
- **No optimistic updates.** Actions await the write; `onSnapshot` listeners
  report the result. A failed write never leaves the screen showing a change that
  did not happen.
- **Everything is audited.** Callables write their own `adminAudit` entry;
  direct Firestore writes from this bundle log through `src/lib/audit.ts`. Rules
  make `adminAudit` append-only even for admins.
- **`src/lib/types.ts` mirrors the iOS `Codable` models.** A field renamed in
  `Pickems/Core/Models/DomainModels.swift` must be renamed here too, or the app
  silently fails to decode a doc this portal "repaired".
- Ordering is done client-side, not with `orderBy`. A Firestore `orderBy` drops
  documents missing that field, and a doc with a missing field is exactly what an
  ops console exists to find.

## Deploy

```bash
cd firebase/admin && npm ci && npm run build
cd .. && firebase deploy --only hosting
```

Then sign in at `https://pickems-fb.web.app` and **confirm a non-admin account is
rejected** before handing the URL to anyone.

`hosting.public` is `admin/dist`, with `index.html` set to `no-store` and hashed
assets set to immutable — so a deploy is picked up on the next page load without
a stale-bundle window. `dist/` is gitignored except for a tracked `.gitkeep`,
which the `postbuild` script restores after Vite empties the directory.

## Known gaps

1. **`/moderation` needs one rules addition that this lane does not own.** A
   Firestore *collection group* query is not authorized by
   `match /groups/{groupId}/messages/{messageId}` — that requires a
   recursive-wildcard match. Until the rules owner (Lane F) adds the block below,
   `/moderation` shows an explanatory banner instead of the queue; nothing else in
   the console is affected.

   ```
   match /{path=**}/messages/{messageId} {
     allow read: if isSuperAdmin();
   }
   ```

   The COLLECTION_GROUP index it needs is already in `firestore.indexes.json`.

2. **Deletes do not recurse.** A client SDK delete removes one document. Deleting
   a league or a week therefore leaves subcollections behind — the confirm dialog
   says so and prints the `firebase firestore:delete --recursive` command to
   finish the job.

3. **Merging a split week is manual.** There is no merge callable, and inventing
   one in the client would risk double-counting picks. `/audit/weeks` identifies
   split weeks and documents the manual procedure: pick the doc whose id matches
   ESPN numbering, copy the other's picks in through the picks grid, rescore, then
   delete the loser.

4. **Members can only be added by uid.** Looking an account up by email needs the
   Admin SDK, which the browser does not have. Copy the uid from the Firebase Auth
   console or the `users` collection.

5. **Adding a member does not backfill history.** It creates the member doc and
   adds the uid to `memberIds`; it does not create pick docs for weeks already in
   progress.

6. **A pick can be changed but not cleared.** `adminUpsertPick` writes with
   `set({ merge: true })`, and Firestore deep-merges map fields, so a game omitted
   from the `picks` map keeps its stored value. The picks grid warns when cells
   were blanked. Removing a pick outright needs a `FieldValue.delete()` path in the
   callable (Lane F) or a manual edit in the Firebase console.
