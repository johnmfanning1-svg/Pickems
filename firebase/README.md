# Pickems Firebase

Deployable unit for Firestore rules, indexes, Cloud Functions, and the web admin
portal. Project: `pickems-fb`.

```
firebase/
  firebase.json            # functions + firestore + storage + hosting + emulators
  firestore.rules          # single-owner security rules
  firestore.indexes.json   # declaratively managed composite indexes — see below
  storage.rules
  functions/               # Cloud Functions (Node 20, TypeScript)
  admin/                   # web admin portal (Lane J) — dist/ is the hosting root
  admin-tools/             # local-only privileged scripts
  tests/                   # Firestore rules unit tests (release gate G0)
```

## Privilege model

Super-user is an Auth **custom claim**: `request.auth.token.admin == true`. Claims
ride in the ID token, cost zero reads, and no client write can grant them. There
is deliberately no `admins/{uid}` collection.

`isSuperAdmin()` is folded into `isCommissioner()`, which makes an admin
commissioner-equivalent in every group with one auditable change. Read
predicates that gate on `isGroupMember()` get an explicit `|| isSuperAdmin()`,
and the field-level allow-lists (`commissionerWeekFieldUpdate`,
`commissionerGameUpdate`) are bypassed for admins so the portal can repair
arbitrary fields. The claim check runs *before* the group `get()` so admin access
survives a missing or already-deleted group doc.

Bootstrap the first admin from a machine with a service-account key:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=~/secrets/pickems-sa.json
node firebase/admin-tools/set-admin.mjs john@pickems.app
```

After that, grants and revokes go through the `setAdminRole` callable. A claim
change is invisible until the token refreshes — call `getIdTokenResult(true)`.

## Composite indexes

`firebase.json` now has a `firestore.indexes` key, which means
`firebase deploy --only firestore` **manages indexes declaratively: any index
present in the console but absent from `firestore.indexes.json` is deleted.**

Provenance: `firebase firestore:indexes` against production returned
`{ "indexes": [], "fieldOverrides": [] }` at the time this file was written, and a
sweep of every `where` / `orderBy` in the iOS client and in `functions/src`
turned up only single-field queries (auto-indexed). So there was nothing to
preserve and this file is additive-only. **Re-run `firebase firestore:indexes`
before the first deploy** to confirm nobody added a console index in the interim.

| Index | Query it serves |
|--|--|
| `messages` (collection): `weekId` ASC, `createdAt` DESC | Lane E week-filtered chat feed |
| `messages` (collection group): `reportCount` ASC, `createdAt` DESC | Lane J `/moderation` queue across all groups |
| `adminAudit`: `action` ASC, `createdAt` DESC | Lane J `/audit/log` filtered by action |

Composite index builds are async and queries fail until the index reports
`Enabled`, so indexes deploy first.

## Callable admin functions

`functions/src/admin.ts`. Every one asserts the `admin` claim and appends an
`adminAudit` entry `{ actorUid, actorEmail, action, targetPath, before, after, createdAt }`.

| Function | Purpose |
|--|--|
| `setAdminRole` | grant/revoke the `admin` claim (self-revoke blocked) |
| `adminSetWeekStatus` | force a status transition, set `pickDeadline` |
| `adminRematerializeNominations` | re-derive `games` from `nominations`, preserving live scores |
| `adminUpsertPick` | write/repair a member's picks, set/clear `isLocked` |
| `adminRemoveMember` | drop a uid from `memberIds` and delete its member/pick/submission/career docs |
| `adminTransferCommissioner` | set `commissionerId` and fix both member roles |
| `adminAuditWeekIds` | Risk R1 tool — misaligned, duplicate, and orphan week docs |
| `adminRescoreWeek` | recompute a week and re-sum season records |

Scoring always routes through `functions/src/scoring.ts` (`scorePicks`,
`rankEntries`, `computeWeekAwards`) so the portal can never disagree with
`lockAndScoreWeeks`. `adminRescoreWeek` re-sums season totals from every scored
week instead of incrementing, which makes re-running it idempotent.

## Deploy order

Rules and indexes go out **before** the TestFlight build, or admin- and
chat-touched paths fail with permission-denied and read as product bugs.

```bash
cd firebase
firebase deploy --only firestore:indexes      # wait for Enabled in the console
firebase deploy --only firestore:rules,storage
firebase deploy --only functions
node admin-tools/set-admin.mjs <owner-email>
cd admin && npm ci && npm run build && cd ..
firebase deploy --only hosting
```

Rollback: redeploy `firestore.rules` from the previous git revision — rules are
versioned in the console and revert independently of the app build. Chat can be
killed without a build via `appConfig/live.chatEnabled = false`.
