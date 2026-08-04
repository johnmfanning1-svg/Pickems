# Pickems Admin Portal — Standard Operating Procedure

> **URL:** Deployed to Firebase Hosting at your project's default domain (e.g. `https://<project-id>.web.app`).  
> **Access:** Requires the `admin: true` Firebase Auth custom claim. Non-admins are signed out immediately on login.

---

## Table of Contents

1. [First-Time Setup](#1-first-time-setup)
2. [Signing In](#2-signing-in)
3. [Dashboard](#3-dashboard)
4. [Managing Groups](#4-managing-groups)
5. [Managing Members](#5-managing-members)
6. [Managing Weeks & Slates](#6-managing-weeks--slates)
7. [Editing Picks](#7-editing-picks)
8. [App Config (Feature Flags)](#8-app-config-feature-flags)
9. [Chat Moderation](#9-chat-moderation)
10. [Week Audit](#10-week-audit)
11. [Audit Log](#11-audit-log)
12. [Granting & Revoking Admin Access](#12-granting--revoking-admin-access)
13. [Deploying Changes](#13-deploying-changes)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. First-Time Setup

Before anyone can use the portal, the **first** admin must be bootstrapped from the command line (the portal's "Grant admin" UI requires an existing admin to call it).

### Prerequisites

- A Firebase service account JSON key (never commit this to the repo).
- Node.js 18+.

### Steps

```bash
# Point to your service account
export GOOGLE_APPLICATION_CREDENTIALS=~/secrets/pickems-sa.json

# Grant the admin claim to your account
node firebase/admin-tools/set-admin.mjs your-email@example.com

# To revoke later:
node firebase/admin-tools/set-admin.mjs your-email@example.com --revoke
```

The user must **sign out and back in** (or the client must call `getIdToken(true)`) for the claim to take effect. Revocations can take up to an hour to propagate to already-issued tokens.

### Deploy the portal & backend

```bash
cd firebase

# Deploy Firestore indexes (wait for "Enabled" status)
firebase deploy --only firestore:indexes

# Deploy security rules
firebase deploy --only firestore:rules

# Deploy Cloud Functions
firebase deploy --only functions

# Build and deploy the admin web app
cd admin && npm install && npm run build && cd ..
firebase deploy --only hosting
```

---

## 2. Signing In

1. Navigate to the portal URL.
2. Sign in with **email/password** or **Google**.
3. The portal forces an `getIdTokenResult(true)` call to pick up the latest custom claims.
4. If your account does **not** have the `admin: true` claim, you are immediately signed out with an error message.

---

## 3. Dashboard

**Route:** `/`

The dashboard shows live Firestore stats (not cached):

| Tile | What it shows |
|------|---------------|
| **Groups** | Total number of leagues |
| **Users** | Count from the `users` collection (single aggregation read) |
| **Public leagues** | Leagues with `isPublic == true` |
| **Weeks** | Total week docs across all groups (scans up to 100 groups) |

**Weeks by status** breaks down how many weeks are in each phase: `selection`, `picking`, `locked`, `scored`. Weeks with no status field are flagged — these are the docs most likely to cause support issues.

**Recent admin actions** shows the last 10 entries from the append-only audit log.

**Actions:**
- **Rescan weeks** — re-fetches the week status tally if you suspect it's stale.

---

## 4. Managing Groups

**Route:** `/groups`

A searchable table of every league. You can search by name, invite code, group ID, or commissioner ID.

### Group Detail (`/groups/:id`)

From the detail page you can:

| Action | What it does |
|--------|--------------|
| **Rename** | Changes the league name. Members see it immediately. |
| **Toggle Discover visibility** | Makes the league public or private. The `publicLeagues` index is updated by a Firestore trigger, not the portal. |
| **Edit invite code** | Changes or regenerates the invite code. Old links stop working. |
| **Edit league rules** | Adjusts selection mode, slate size, deadline policy, confidence picks, late pick penalty, and tie-breaker. Changing `slateSize` mid-week does **not** re-materialize an existing slate. |
| **Delete league** | Removes the group doc, invite reservation, and Discover entry. Subcollections (members, weeks, picks, chat) must be cleaned separately via the Firebase console or CLI: `firebase firestore:delete groups/<id> --recursive`. Requires typing the league name to confirm. |

---

## 5. Managing Members

**Route:** `/groups/:id/members`

Shows all member docs left-joined with the `memberIds` array on the group doc. Drift between the two is flagged:

- **"Ids in memberIds with no member doc"** — ghost entries that count toward totals but have no profile.
- **"Member docs missing from memberIds"** — members who can't see the league because rules gate reads on `memberIds`.

### Actions per member

| Action | What it does |
|--------|--------------|
| **Make commissioner** | Transfers the commissioner role. The previous commissioner becomes a regular member. |
| **Reset W-L** | Sets season record to 0-0. Standings don't update until the next rescore. |
| **Remove** | Deletes the member doc, career doc, and pick/submission docs across every week. Irreversible. |

### Adding a member

Enter a Firebase Auth UID in the "Add a member" card. If no `users/<uid>` profile exists, you'll get a warning but can proceed (the member appears as "Unknown").

---

## 6. Managing Weeks & Slates

**Route:** `/groups/:id/weeks`

Lists every week doc for the league, newest first. Each card shows:

- Current status and expected ID (flagged if misaligned with ESPN numbering)
- Nomination count, slate size, lock/score timestamps
- Pick deadline (editable)

### Actions per week

| Action | What it does |
|--------|--------------|
| **Change status** | Force a week to any status: `selection` → `picking` → `locked` → `scored`. Going backwards is allowed but flagged as dangerous — rescore afterwards. Moving `selection` → `picking` also materializes nominations into the slate. |
| **Set deadline** | Change or clear the pick deadline. Clear the field to remove it entirely. |
| **Re-materialize slate** | Rebuilds the `games` subcollection from nominations. Live scores on games that still exist are preserved; games whose nominations were removed disappear. |
| **Slate & spreads** | Expands an inline editor showing every game on the slate with its spread. You can edit spreads here. |
| **Delete week** | Removes the week doc only. Subcollections must be cleaned separately. Requires typing the week ID to confirm. |

---

## 7. Editing Picks

**Route:** `/groups/:id/weeks/:weekId/picks`

A spreadsheet-style grid with members down rows and slate games across columns.

### Reading the grid

- Each cell is a dropdown: away team, home team, or blank (no pick).
- After games go final, cells are color-coded: **green** for correct (covered the spread), **red** for incorrect.
- The spread is shown in the column header (e.g. `ALA -7`).
- Each member row shows their **submitted/open** status and pick count.

### Editing picks

1. Change any cell's dropdown to a different team.
2. Optionally set the **confidence game** dropdown (the double-weight pick).
3. Click **Save** on that member's row. A confirmation dialog shows how many picks you're writing.
4. Click **Reset** to discard unsaved edits for that member.

**Important:** The callable uses `set({ merge: true })`, so blanking a cell does **not** remove a pick — it keeps the previously stored team. To truly clear a pick, change it to the other team or use the Firebase console.

### Lock / Unlock

- **Lock** marks the member as submitted (their picks become visible to others).
- **Unlock** lets the member edit picks again, even after the deadline.

### Rescore

Click **Rescore week** in the page header. This recomputes results, awards, and standings from every scored week rather than incrementing, so running it twice is safe.

---

## 8. App Config (Feature Flags)

**Route:** `/config`

Edits the `appConfig/live` Firestore document, which every signed-in client reads at launch. Changes take effect on the next app launch — no App Store release required.

### Feature flags

| Flag | Purpose |
|------|---------|
| `chatEnabled` | Master kill switch for group chat. Turn this off if moderation slips (Guideline 1.2 fallback). |
| `top25FilterEnabled` | Enables Top 25 and conference filters in the game browse screen. |
| `minimumBuild` | Forces users below this build number to update. **Never** set this above the newest build actually available in TestFlight or the App Store. Leave blank for no minimum. |

### Marketing strings

| Field | Purpose |
|-------|---------|
| `announcementTitle` / `announcementBody` | In-app announcement banner. Blank clears it. |
| `maintenanceMessage` | When non-empty, the app typically shows a maintenance banner. |

### Other keys (raw JSON)

Merge arbitrary keys into `appConfig/live` without touching the typed fields above. There is no schema check — a typo here ships a flag the app never reads. Requires typing "live" to confirm.

---

## 9. Chat Moderation

**Route:** `/moderation`

Shows every chat message across all leagues that has at least one report, ordered by report count. This is the queue that App Store Guideline 1.2 assumes you're working.

### For each reported message you see:

- Report count and badge (3+ reports = danger badge)
- Author name, timestamp, week, and the message text
- Links to the league and member pages
- The Firestore document path

### Actions

| Action | What it does |
|--------|--------------|
| **Hide** | Sets `isDeleted: true`. The message stops rendering for members but stays in Firestore (evidence is preserved for App Review escalations). |
| **Restore** | Makes a hidden message visible again. Report count is unchanged, so it stays in this queue. |
| **Reporters** | Expands a list of who reported the message and their reasons. |
| **Delete** | Permanently removes the document. Prefer hiding — a soft delete keeps the evidence. The `reports` subcollection becomes orphaned. Requires typing "delete" to confirm. |

### Auto-moderation

Cloud Functions automatically soft-delete messages that reach 3 reports (`onReportCreated` increments `reportCount` and sets `isDeleted: true` at the threshold).

---

## 10. Week Audit

**Route:** `/audit/weeks`

Scans week docs across leagues to detect data integrity issues. This is the primary tool for diagnosing the "split week" problem where a fallback week ID that disagrees with ESPN creates a parallel week doc.

### Issue types

| Issue | Severity | Meaning |
|-------|----------|---------|
| `misalignedWeekId` | Danger | Doc ID doesn't match `{seasonYear}-W{weekNumber}`. Picks may be split across two docs. |
| `duplicateWeekNumber` | Danger | Two week docs claim the same season and week number. |
| `orphanWeek` | Neutral | No nominations, games, or picks. Safe to delete. |
| `gameNominationCountMismatch` | Warning | Materialized slate doesn't match nominations. Re-materialize to fix. |
| `missingSeasonOrWeekNumber` | Danger | Can't derive expected ID; app can't label the week. |

### Actions

- **Re-materialize** — available on any week with nominations.
- **Delete** — available on orphan weeks (requires typing the week ID).

### Merging a split week

There is no merge callable. To merge manually:

1. Open both week docs' picks grids.
2. Decide which doc is canonical (the one whose ID matches ESPN numbering).
3. Copy picks from the loser into the canonical doc using the picks grid.
4. Rescore the canonical week.
5. Delete the loser once its counts read 0.

**Run this audit before every TestFlight invite.**

---

## 11. Audit Log

**Route:** `/audit/log`

An append-only log of every admin action. Rules deny update and delete, so even an admin cannot rewrite history.

### Filtering

- **Action dropdown** — filter by specific action type (e.g. `adminRescoreWeek`, `adminDeleteGroup`).
- **Search** — client-side text search across actor email, UID, target path, and action name.

### Columns

| Column | Content |
|--------|---------|
| When | Timestamp and relative time |
| Action | The callable or portal operation name |
| Actor | Email and UID of the admin who performed it |
| Target | Firestore document path that was affected |
| Before / After | Snapshot of the document before and after the change (expandable for large payloads) |

---

## 12. Granting & Revoking Admin Access

### From the portal (Config page)

Scroll to the **Super-admin roles** card at the bottom of `/config`.

1. Enter the user's **email** or Firebase Auth **UID**.
2. Select **grant admin** or **revoke admin**.
3. Click **Apply**.

Granting gives the user commissioner-equivalent write access to **every** league plus access to this console. The blast radius is global — grant to as few accounts as possible.

Revocations land when the user's ID token next refreshes (up to an hour). For an immediate cutoff, also disable the account in Firebase Auth.

### From the command line (first admin only)

```bash
export GOOGLE_APPLICATION_CREDENTIALS=~/secrets/pickems-sa.json
node firebase/admin-tools/set-admin.mjs user@example.com          # grant
node firebase/admin-tools/set-admin.mjs user@example.com --revoke  # revoke
```

---

## 13. Deploying Changes

When you update the admin portal code or Firebase backend:

```bash
cd firebase

# 1. Deploy indexes first (they can take minutes to build)
firebase deploy --only firestore:indexes
# Wait for all indexes to show "Enabled" in the Firebase console

# 2. Deploy security rules
firebase deploy --only firestore:rules

# 3. Deploy Cloud Functions
firebase deploy --only functions

# 4. Build and deploy the web portal
cd admin && npm run build && cd ..
firebase deploy --only hosting
```

**Order matters:** deploy indexes before rules (rules may reference new indexes), and rules before functions (functions may write to paths the new rules protect).

---

## 14. Troubleshooting

### "Permission denied" errors

- **Most common cause:** Stale admin claim. Sign out, sign back in, and retry.
- If the error persists, verify the claim exists: check `Firebase Auth > Users > Custom Claims` in the Firebase console.

### Moderation page shows "query not authorized"

The collection-group query on `messages` requires the recursive-wildcard rule:

```
match /{path=**}/messages/{messageId} {
  allow read: if isSuperAdmin();
}
```

If this rule is missing, deploy updated `firestore.rules`.

### Moderation page shows "missing index"

Deploy the composite index:

```bash
firebase deploy --only firestore:indexes
```

Wait for the `(reportCount ASC, createdAt DESC)` collection-group index on `messages` to show "Enabled".

### Week status stuck / picks not visible

1. Go to `/groups/:id/weeks` and check the week's current status.
2. Use the status dropdown to force it to the correct phase.
3. If the slate is empty, click **Re-materialize slate**.
4. If standings are wrong, go to the picks page and click **Rescore week**.

### Member can't see the league

Check `/groups/:id/members`. If the member doc exists but the member is flagged as **"missing from memberIds"**, the `memberIds` array on the group doc needs to be repaired. Add the member again using the "Add a member" card (it writes both the member doc and the array entry).

### Callable returns "not deployed"

```bash
firebase deploy --only functions
```

Verify the function appears in `Firebase Console > Functions`.
