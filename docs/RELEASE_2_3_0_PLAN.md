# Pickems 2.3.0 — Coordinated Feedback Release + Web Admin

**Release train:** `2.3.0` (build `230`) — currently `2.2.3` / `223` (`Pickems.xcodeproj/project.pbxproj:547`, `:531`)
**Bundle ID:** `FannypackInc.Pickems` · **Apple ID:** `6785697079`
**Validation target:** TestFlight, tested by PO in **Google Chrome** (App Store Connect web) — not the Cursor browser.

---

## 0. Ground truth established before planning

These were verified in the working tree, not assumed. They change how the lanes are cut.

| Finding | Impact |
|--|--|
| `Pickems/`, `PickemsWidget/`, `PickemsWatch/`, `PickemsTests/`, `PickemsUITests/` are `PBXFileSystemSynchronizedRootGroup` (`project.pbxproj:104–142`) | **New Swift files require no `.pbxproj` edit.** Parallel lanes can add files with zero merge conflict. `project.pbxproj` gets exactly one owner (the version-bump lane) for the whole release. |
| `firebase/firebase.json` has **no** `hosting` and **no** `indexes` block | Admin portal and chat both need it. This makes infra a blocking wave-0 lane, not a parallel one. |
| `firestore.rules` has no admin/super-user concept and no chat collection | Rules is a single-owner file. Feature lanes hand it snippets; they never edit it directly. |
| `CFBWeekSync.weekId` already emits `"{seasonYear}-W{weekNumber}"` from ESPN's `week.number` | **Existing Firestore week doc IDs are already ESPN-aligned.** Week numbering is a *copy* bug (widget), not a data migration. One real exception — see Risk R1. |
| `ESPNModels.swift` decodes no rank and no conference fields | Top-25 / conference filters need new decode fields first. Creates a hard B→C dependency. |
| `PickService.submitCommissionerGame` guards only `slateFull` (`PickService.swift:246–248`) | Duplicate-game guard genuinely missing on the commissioner path; `submitNomination` has one (`:140–143`). |
| `firebase-admin ^12.7.0` already a functions dependency | Custom-claims admin model needs no new backend dependency. |

---

## 1. Scope — 11 workstreams

1. **AUTH** — Apple-first sign-in
2. **GROUPS-NAV** — picks/slate reachable from Groups (pre- and post-kickoff)
3. **NOMINATE-UX** — grey out already-nominated games in-browse, show nominator
4. **DUP-GUARD** — commissioner duplicate-game guard
5. **GROUP-PICKS** — collapsible per-user sections + remaining-picks count
6. **ESPN-SLATE** — `groups=80` fix, conference + Top-25 filters, spreads everywhere
7. **WEEK-NUM** — align all copy to ESPN numbering (first slate = Week 1)
8. **CHAT** — Firestore-backed group chat + moderation (App Review 1.2 gate)
9. **ADMIN** — Firebase Hosting web admin, super-user gated
10. **ASO** — App Store metadata, fastlane `deliver`, pickems.app SEO
11. **RELEASE** — version bump, rules deploy, archive, TestFlight

---

## 2. Wave plan and lane ownership

Ownership rule: **one lane owns a file for the whole release.** A lane that needs a change in another lane's file requests it through an interface contract (§3), never by editing.

### Wave 0 — Infra (blocking, serial, must merge first)

**Lane F — Firebase infra.** Sole owner of `firebase/**` config for the release.

Owns:
- `firebase/firebase.json` — add `hosting` + `firestore.indexes`
- `firebase/firestore.rules` — admin predicate + chat rules + admin overrides
- `firebase/firestore.indexes.json` — **new**
- `firebase/functions/src/admin.ts` — **new** (callable admin fns)
- `firebase/functions/src/index.ts` — export lines only
- `firebase/tests/**` — **new** rules unit tests
- `firebase/admin-tools/set-admin.mjs` — **new** bootstrap script

Why blocking: Lanes E (chat) and J (admin web) both fail closed without rules, indexes, and hosting config. Everything else is independent of F.

### Wave 1 — Parallel, no cross-dependencies (6 lanes)

| Lane | Workstream | Files owned (exclusive) |
|--|--|--|
| **A** | AUTH | `Pickems/Features/Auth/SignInView.swift` |
| **B** | ESPN data layer | `Pickems/Core/Services/ESPNService.swift`, `Pickems/Core/Models/ESPNModels.swift`, `Pickems/Core/Models/ESPNConferenceCatalog.swift` *(new)* |
| **G** | GROUP-PICKS | `Pickems/Features/Picks/GroupPicksView.swift`, `Pickems/DesignSystem/PickResultRow.swift` |
| **H** | DUP-GUARD + nomination-list spreads | `Pickems/Core/Services/PickService.swift`, `Pickems/Features/Picks/PicksView.swift` |
| **I** | WEEK-NUM | `Pickems/Core/Utilities/CFBSeasonCalendar.swift`, `Pickems/Core/Utilities/CFBWeekSync.swift`, `PickemsWidget/CFBSeasonCalendar.swift`, `PickemsWidget/PickemsWidget.swift`, `docs/WIDGETS_WATCH.md` |
| **K** | ASO | `docs/APP_STORE.md`, `docs/ASO.md` *(new)*, `fastlane/**` *(new)*, `web/**` *(new)* |

### Wave 2 — Parallel, each depends on a wave-0/1 lane (4 lanes)

| Lane | Workstream | Depends on | Files owned (exclusive) |
|--|--|--|--|
| **C** | NOMINATE-UX + browse filters | **B** (needs `curatedRank`, conference fields, filter enum) | `Pickems/Features/Picks/GameBrowseView.swift` |
| **E** | CHAT | **F** (rules + index) | `Pickems/Features/Chat/**` *(new)*, `firebase/functions/src/chat.ts` *(new)* |
| **J** | ADMIN web | **F** (hosting + claims + rules) | `firebase/admin/**` *(new)* |
| **D** | GROUPS-NAV + chat entry point | **E** (needs `GroupChatEntryButton`) | `Pickems/Features/Groups/GroupsView.swift`, `Pickems/Features/Groups/GroupSlateView.swift` *(new)* |

### Wave 3 — Release (serial)

**Lane L — Release.** Sole owner of `Pickems.xcodeproj/project.pbxproj`. Runs only after A–K are merged and green.

---

## 3. Interface contracts (freeze these before Wave 1 starts)

Subagents must not invent these signatures. Lane B/E/G publish them; C/D/H consume them.

**C1 — `ESPNGame` additions (Lane B, consumed by C):**
```swift
// Pickems/Core/Models/ESPNModels.swift — added to struct ESPNGame
let homeCuratedRank: Int?      // nil when unranked; ESPN sends 99 for unranked → map to nil
let awayCuratedRank: Int?
let homeConferenceId: String?  // ESPN competitor.team.conferenceId
let awayConferenceId: String?

var isTop25: Bool { homeCuratedRank != nil || awayCuratedRank != nil }
```

**C2 — Conference filter model (Lane B, consumed by C):**
```swift
// Pickems/Core/Models/ESPNConferenceCatalog.swift  (new)
struct ESPNConference: Identifiable, Hashable { let id: String; let name: String; let shortName: String }

enum ESPNConferenceCatalog {
    /// FBS conference groups, ESPN group ids. Order = display order.
    static let fbs: [ESPNConference]           // SEC 8, Big Ten 5, Big 12 4, ACC 1, Pac-12 9, AAC 151, MWC 17, Sun Belt 37, MAC 15, C-USA 12, Ind 18
    static func conference(id: String?) -> ESPNConference?
}

enum GameSlateFilter: Hashable {
    case all, top25
    case conference(id: String)
}
```

**C3 — `GameBrowseView` init (Lane C, called by Lane H at `PicksView.swift:40`):**
```swift
GameBrowseView(
    games: [ESPNGame],
    nominatedEventIds: Set<String>,                 // grey out + disable
    nominatorNamesByEventId: [String: String],      // "Nominated by Dave"
    onSelect: (ESPNGame) -> Void
)
```
Lane H supplies both new arguments from `appState.pickService.nominations`. Lane C must give the two new parameters defaults (`[]`, `[:]`) so Lane C can merge before Lane H.

**C4 — Chat entry button (Lane E, placed by Lane D):**
```swift
// Pickems/Features/Chat/Views/GroupChatEntryButton.swift  (new, Lane E)
struct GroupChatEntryButton: View { let group: PickemGroup }   // self-contained: label, unread badge, NavigationLink
```

**C5 — `PickResultRow` (Lane G, used by G and D):**
```swift
PickResultRow(game: SlateGame, pickedTeamId: String?, showSpread: Bool = true)
```

**C6 — Slate screen reachable from Groups (Lane D, new file):**
```swift
GroupSlateView(group: PickemGroup, week: WeekSummary)   // pre-kickoff: build/edit slate; post-kickoff: live monitor
```

---

## 4. Workstream detail

### Lane A — AUTH: Apple primary, email secondary

`Pickems/Features/Auth/SignInView.swift`

Current order is brand header → `Picker` Sign In/Create (`:29–36`) → email form (`:38`) → primary button (`:40–48`) → divider (`:57`) → "Or continue with Apple" (`:59`) → Apple button (`:63–88`).

Target:
1. Brand header, then **`SignInWithAppleButton` immediately** — full width, `height 50`, `.signInWithAppleButtonStyle(.white)`, unchanged nonce/completion logic (do not touch `AuthService`).
2. Below it: `Button("Use email and password instead")` — `.font(.footnote)`, `PickemsColors.textSecondary`, toggles `@State private var showEmailAuth = false`.
3. Email path (mode `Picker`, `emailPasswordForm`, primary button, "Forgot password?") renders only when `showEmailAuth == true`, inside `.animation(.easeInOut(duration: 0.2), value: showEmailAuth)`.
4. Keep the `divider` only inside the expanded email block; drop the "Or continue with Apple" caption (Apple is now the lead, so the caption is wrong).
5. Preserve: error text block (`:90–96`), Privacy/Terms links (`:98–108`), `#if DEBUG` Admin button (`:110–117`), `.onChange(of: mode)` reset (`:123–127`), both sheets with `.pickemsEnvironment(appState)` (`:128–137`).
6. Accessibility: Apple button gets `.accessibilitySortPriority(2)`; the email disclosure gets `.accessibilityHint("Switch to email and password sign in")`.

Guardrail: `PickemsTests/AuthRoutingTests.swift` must stay green; do not change `AuthMode` cases (create-account flow still needs first/last/username validation at `:229–243`).

---

### Lane B — ESPN data layer: `groups=80`, rank, conference

`Pickems/Core/Services/ESPNService.swift`, `Pickems/Core/Models/ESPNModels.swift`

1. **The "99 games" root cause.** `fetchScoreboard` sends only `week` + `seasontype` (`ESPNService.swift:53–57`), so ESPN returns all divisions (FBS + FCS + D2/D3), which is why the browse list balloons. The Cloud Function already does this correctly (`firebase/functions/src/espn.ts:26`). Add `URLQueryItem(name: "groups", value: "80")` to `fetchScoreboard`, **and** to `currentWeek` (`:25`) so week metadata comes from the FBS scoreboard too. Add `URLQueryItem(name: "limit", value: "300")` — ESPN defaults to a smaller page and silently truncates busy Saturdays.
2. **Cache key must include the new dimension.** `cacheKey` (`:46`) becomes `"\(seasonType)-\(week)-fbs-\(live ? "live" : "browse")"` so pre-fix cached payloads can't be served post-fix within the 15-minute TTL.
3. **Decode rank + conference** in `ESPNScoreboardResponse` (`ESPNModels.swift:50–63`):
   - `ESPNCompetitor` gains `let curatedRank: ESPNCuratedRank?`; `struct ESPNCuratedRank: Decodable { let current: Int }`.
   - `ESPNTeam` gains `let conferenceId: String?`.
   - In `parseEvent` (`ESPNService.swift:156–195`), map `curatedRank.current == 99 → nil` (ESPN's unranked sentinel) and populate the four new `ESPNGame` fields per C1.
4. **New file** `ESPNConferenceCatalog.swift` per C2.
5. **Spread parsing hardening** (in scope, cheap, and it is why spreads look wrong on some rows): `parseSpreadTeamId` (`:205–209`) currently falls back to `homeId` whenever neither `favorite` flag is set, which mislabels the favorite. Change the fallback to derive from `odds.details` (e.g. `"BAMA -7.5"` → match abbreviation to home/away) and only then default to `homeId`. Keep the return type; do not change `ESPNGame.toSlateGame` (`:122–147`) — scoring depends on its sign convention.
6. Add `PickemsTests/ESPNServiceTests.swift`: fixture-based test that a `curatedRank.current == 99` decodes to `nil`, that a ranked matchup sets `isTop25`, and that the built URL contains `groups=80`.

Do **not** touch `GameBrowseView.swift` (Lane C) or `PicksView.swift` (Lane H).

---

### Lane C — NOMINATE-UX: fix duplicates in-browse + filters

`Pickems/Features/Picks/GameBrowseView.swift`

Today `PickError.duplicateGame` (`PickService.swift:142`) only fires *after* the user picks a game and tries to submit — a dead-end. And the browse list has only status filters (`GameBrowseFilter`, `:3–10`).

1. Adopt the C3 init. Compute `isNominated = nominatedEventIds.contains(game.espnEventId)`.
2. In the `List` (`:58–65`): when `isNominated`, apply `.opacity(0.45)`, `.disabled(true)`, and `.allowsHitTesting(false)` on the row button so the tap is impossible rather than failing.
3. In `GameBrowseRow` (`:150–247`) add `var isNominated: Bool = false` and `var nominatorName: String? = nil`. When nominated, render a trailing `StatusBadge(text: "Taken", color: PickemsColors.textSecondary)` and, under the matchup, `Text("Nominated by \(nominatorName)")` in `.caption2`. Accessibility: `.accessibilityLabel("\(away) at \(home), already nominated by \(nominatorName)")` and `.accessibilityRemoveTraits(.isButton)`.
4. **Make spreads prominent** (`:180–190`): move `spreadDisplayLabel` above `statusLabel`, bump to `.subheadline.weight(.bold)` in `theme.accent`, and render `Text("No line")` in `.caption2`/`textSecondary` when nil so a missing spread is explicit rather than blank.
5. **Two filter rows.** Keep the existing status `filterBar` (`:99–117`). Add a second horizontal chip row bound to `@State private var slateFilter: GameSlateFilter = .all`: `All`, `Top 25`, then `ESPNConferenceCatalog.fbs` chips. Extend `filteredGames` (`:26–36`) with `.filter { matchesSlateFilter($0) }`:
   - `.all` → true
   - `.top25` → `game.isTop25`
   - `.conference(id)` → `game.homeConferenceId == id || game.awayConferenceId == id`
6. Sort order in `filteredGames`: favorite team first (existing), then **Top-25 games**, then `kickoff`. Ranked games are what people want to nominate.
7. Toolbar count (`:85–89`) becomes `"\(filteredGames.count) of \(games.count)"` so the filter effect is legible.
8. Extend `emptyMessage` (`:119–129`) with slate-filter cases ("No Top 25 games this week.", "No SEC games this week.").

---

### Lane D — GROUPS-NAV: picks, slate, live, chat from Groups

`Pickems/Features/Groups/GroupsView.swift` + new `GroupSlateView.swift`

Today Groups has zero navigation into picks or the slate: `primaryActions` (`:230–254`) is only `InviteShareButton` + Members, and `manageSection` (`:258–373`) is Stats/Rivalry/Discover/Join/Create/Delete. `GroupPicksView` is only reachable from `PicksView.swift:337`.

1. **Replace `primaryActions` with a 2×2 `LazyVGrid`** (three buttons in one `HStack` is too cramped once Chat lands):
   - `GroupChatEntryButton(group: group)` (Lane E, per C4) — top-left, most discoverable
   - `NavigationLink { GroupPicksView() }` labelled **"Group Picks"**, `list.bullet.clipboard`
   - `NavigationLink { GroupSlateView(group: group, week: week) }` labelled by phase (below)
   - `NavigationLink { MemberListView() }` — Members (unchanged destination)
   - `InviteShareButton(group: group)` moves to a full-width row beneath the grid.
2. **Phase-aware slate entry.** Read `appState.groupService.currentWeek`. Render the slate button only when a week exists; label and destination by `week.status`:
   - `.selection` → **"Build Slate"** → `GroupSlateView` in build mode
   - `.picking` → **"Make Picks"** → `GroupSlateView` in picks mode
   - `.locked` / `.scored` → **"Live Picks"** → `GroupSlateView` in monitor mode
3. **Pre-kickoff current picks summary.** Above the grid, a `PickemsCard` "This Week" showing `week.displayLabel`, slate progress `\(week.nominationCount)/\(week.slateSize)`, and **submitted count** from `appState.pickService.submissions` (`x of \(group.memberCount) submitted`). Use `submissions`, not `allPicks` — `submissions` is the collection readable by all members before the deadline (`firestore.rules:159–168`), whereas `picks` is self-only until `picksVisibleToAll` (`:62–68`). Reading `allPicks` pre-deadline is exactly what produces the permission-denied noise handled at `PickService.swift:120–131`.
4. **`GroupSlateView`** (new, per C6) — a thin composition layer, not new business logic:
   - build mode: nomination list + `PrimaryButton("Nominate Game")` reusing `viewModel.loadESPNGames` / `showGameBrowse` from `PicksViewModel`
   - picks mode: `ForEach(appState.pickService.slateGames) { GamePickRow(...) }`
   - monitor mode: `LiveScoreboardSection` + `PickResultRow(game:pickedTeamId:showSpread: true)` per member, showing **spreads** (Lane G's C5)
   - Every mode shows the spread. Empty states via `ContentUnavailableView`.
5. **Crash guardrail (non-negotiable):** any new sheet root gets `.pickemsEnvironment(appState)`. This is the exact 1.0 App Review rejection (`docs/APP_STORE.md`, and the comment at `GroupsView.swift:57–59`). Prefer `NavigationLink` over `.sheet` for all new destinations.
6. `.task(id:)` for standings/picks loading stays in `LeaderboardView` (`:509–513`) — do not duplicate the loader.

---

### Lane E — CHAT: Firestore-backed group chat

**Do not ship `origin/cursor/smack-talk-group-chat-9c1a` as-is** — `LocalSmackTalkService.swift` is `UserDefaults`-only, so nobody sees anyone else's messages. Its `SmackTalkServing` protocol is a usable seam; port the views, replace the service.

#### Data model — one flat collection per group

```
groups/{groupId}/messages/{messageId}
```

Flat with an optional `weekId` field beats a `weeks/{weekId}/messages` subcollection here: one listener powers both the all-group feed and a week filter, and it keeps chat readable when a week doc doesn't exist yet.

```swift
// Pickems/Features/Chat/Models/ChatMessage.swift
struct ChatMessage: Codable, Identifiable, Equatable {
    var id: String
    var groupId: String
    var weekId: String?          // nil = league-wide
    var userId: String
    var displayName: String
    var avatarColorHex: String
    var text: String             // 1...500 chars, enforced in rules
    var createdAt: Date          // serverTimestamp on write
    var editedAt: Date?
    var isDeleted: Bool          // soft delete keeps thread order intact
    var reactions: [String: [String]]?   // emoji -> [uid]; v1 writes nil, rules already permit
    var reportCount: Int         // moderation signal, admin-visible
}
```

- Unread badge: add `lastReadChatAt: Date?` to the existing `groups/{groupId}/members/{memberId}` doc. **No rules change needed** — members may already update their own member doc (`firestore.rules:117`).
- Mute: `chatMuted: Bool` on the same member doc.
- Reports: `groups/{groupId}/messages/{messageId}/reports/{reporterUid}` — `{ reporterUid, reason, createdAt }`.

#### Composite index (required)

Week-filtered query `where weekId == x order by createdAt desc` needs a composite index. Lane F adds to `firestore.indexes.json`:
```json
{ "collectionGroup": "messages", "queryScope": "COLLECTION",
  "fields": [ { "fieldPath": "weekId", "order": "ASCENDING" },
              { "fieldPath": "createdAt", "order": "DESCENDING" } ] }
```

#### Rules block (Lane E authors, **Lane F merges**)

```
match /groups/{groupId}/messages/{messageId} {
  allow read: if isGroupMember(groupId) || isSuperAdmin();

  allow create: if isGroupMember(groupId)
    && request.resource.data.userId == request.auth.uid
    && request.resource.data.groupId == groupId
    && request.resource.data.text is string
    && request.resource.data.text.size() > 0
    && request.resource.data.text.size() <= 500
    && request.resource.data.isDeleted == false
    && request.resource.data.reportCount == 0
    && request.resource.data.createdAt == request.time;

  // Author edits own text / soft-deletes; any member may toggle reactions only.
  allow update: if isSuperAdmin()
    || (isGroupMember(groupId) && resource.data.userId == request.auth.uid
        && request.resource.data.diff(resource.data).affectedKeys()
             .hasOnly(['text', 'editedAt', 'isDeleted']))
    || (isGroupMember(groupId)
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['reactions']))
    || (isCommissioner(groupId)
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isDeleted']));

  allow delete: if isCommissioner(groupId) || isSuperAdmin();

  match /reports/{reporterUid} {
    allow read: if isCommissioner(groupId) || isSuperAdmin();
    allow create: if isGroupMember(groupId) && request.auth.uid == reporterUid;
    allow update, delete: if isSuperAdmin();
  }
}
```
`reportCount` is incremented by a Cloud Function, not the client — clients can't forge it because `create` pins it to `0` and `update` never lists it in an allowed key set.

#### iOS files (all new, auto-compiled via synchronized group)

```
Pickems/Features/Chat/Models/ChatMessage.swift
Pickems/Features/Chat/Services/ChatService.swift          // @Observable, addSnapshotListener, paginate 50
Pickems/Features/Chat/Views/GroupChatView.swift           // message list + composer
Pickems/Features/Chat/Views/ChatMessageRow.swift          // bubble, avatar, relative time, own-vs-other
Pickems/Features/Chat/Views/GroupChatEntryButton.swift    // contract C4
Pickems/Features/Chat/Views/ChatModerationSheet.swift     // report / block / delete-own
Pickems/Features/Chat/Utilities/ChatBlocklist.swift       // local blocked-uid set
```
- `ChatService` mirrors `PickService`'s listener lifecycle (`PickService.swift:19–47`): keep `ListenerRegistration`, remove on group switch. Register it on `AppState` alongside `pickService`.
- Query: `.order(by: "createdAt", descending: true).limit(to: 50)`, `startAfter` for older pages.
- Composer: 500-char cap enforced client-side with a live counter, trims whitespace, disabled while empty or sending, optimistic append.
- `FirestorePaths.swift` gets `static let messages = "messages"` — **coordinate with Lane H**, which owns nothing in that file; assign `FirestorePaths.swift` to Lane E.

#### Moderation — App Review Guideline 1.2 (blocking, see Risk R4)

Chat makes this a UGC app. Ship all four or expect rejection:
1. **Report** a message (writes the report doc) — in `ChatMessageRow` context menu
2. **Block** a user (local `ChatBlocklist` + filter in `ChatService`)
3. **Delete own** message (soft delete)
4. Terms link already exists (`AppConfig.termsOfServiceURL`) — add a first-run chat notice: "Be cool. Reported messages are reviewed and accounts can be removed."

#### Cloud Function (Lane E authors `chat.ts`, Lane F exports it)

`firebase/functions/src/chat.ts`:
- `onMessageCreated` (`onDocumentCreated("groups/{groupId}/messages/{messageId}")`) → `sendToUsers` (already in `notifications.ts`) to `memberIds` minus author minus anyone with `chatMuted == true`. Title = group name, body = `"{displayName}: {truncated text}"`, type `"chat_message"`.
- `onReportCreated` → `FieldValue.increment(1)` on `reportCount`; auto-set `isDeleted: true` at `reportCount >= 3`.

---

### Lane F — Firebase infra (Wave 0)

#### Privilege model: **Auth custom claims**, not a Firestore `admins` doc

Decision: super-user = `request.auth.token.admin == true`. Claims live in the ID token, cost zero reads, and cannot be self-granted by any client write. A Firestore `admins/{uid}` collection would add a `get()` to every admin-gated rule and is writable-by-rule-bug; claims are not.

`firestore.rules` additions:
```
function isSuperAdmin() {
  return isSignedIn() && request.auth.token.admin == true;
}
```
Then OR `isSuperAdmin()` into the write predicates for `groups`, `groups/*/members`, `groups/*/weeks`, `nominations`, `games`, `picks`, `submissions`, `standings`, `seasons`, `career`, `inviteCodes`, `publicLeagues`, plus the chat block from Lane E. Concretely, `isCommissioner(groupId)` at `firestore.rules:14–17` becomes:
```
function isCommissioner(groupId) {
  return isSignedIn()
    && (get(/databases/$(database)/documents/groups/$(groupId)).data.commissionerId == request.auth.uid
        || isSuperAdmin());
}
```
This single edit grants the admin portal commissioner-equivalent power everywhere with one auditable change, instead of 12 scattered ORs. Keep the field-level constraint helpers (`commissionerWeekFieldUpdate`, `commissionerGameUpdate`) but add an `|| isSuperAdmin()` bypass at their call sites so admins can repair arbitrary fields — that is the point of the portal.

Two new collections:
```
match /appConfig/{configId} {
  allow read: if isSignedIn();
  allow write: if isSuperAdmin();
}
match /adminAudit/{entryId} {
  allow read: if isSuperAdmin();
  allow create: if isSuperAdmin();
  allow update, delete: if false;      // append-only
}
```

#### `firebase.json`

```json
{
  "functions": [ /* unchanged */ ],
  "firestore": { "rules": "firestore.rules", "indexes": "firestore.indexes.json" },
  "storage": { "rules": "storage.rules" },
  "hosting": {
    "public": "admin/dist",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [ { "source": "**", "destination": "/index.html" } ],
    "headers": [
      { "source": "/index.html", "headers": [ { "key": "Cache-Control", "value": "no-store" } ] },
      { "source": "**/*.@(js|css)", "headers": [ { "key": "Cache-Control", "value": "public,max-age=31536000,immutable" } ] }
    ]
  }
}
```
`admin/` sits at `firebase/admin/` — inside the Firebase deployable unit, and critically **outside** every `PBXFileSystemSynchronizedRootGroup`, so `node_modules/` can never be swept into the Xcode target. Add to `.gitignore`: `firebase/admin/node_modules/`, `firebase/admin/dist/`, `firebase/admin/.env.local`.

#### Bootstrap + callable admin functions

`firebase/admin-tools/set-admin.mjs` — one-time, run locally:
```bash
export GOOGLE_APPLICATION_CREDENTIALS=~/secrets/pickems-sa.json
node firebase/admin-tools/set-admin.mjs john@pickems.app
```
Uses `admin.auth().getUserByEmail` → `setCustomUserClaims(uid, { admin: true })`. Prints a reminder that the user must sign out/in (or the app must call `getIdToken(true)`) before the claim is live.

`firebase/functions/src/admin.ts` (callable, each asserts `request.auth?.token.admin === true` and writes an `adminAudit` entry):
| Function | Purpose |
|--|--|
| `setAdminRole` | grant/revoke `admin` claim on another uid |
| `adminSetWeekStatus` | force `selection → picking → locked → scored`, set `pickDeadline` |
| `adminRematerializeNominations` | re-run `materializeNominations` for a week |
| `adminUpsertPick` | write/repair a member's `picks` map, set/clear `isLocked` |
| `adminRemoveMember` | remove uid from `memberIds` + delete member/pick/submission docs |
| `adminTransferCommissioner` | set `commissionerId` |
| `adminAuditWeekIds` | **Risk R1 tool** — report week docs where `id != "{seasonYear}-W{weekNumber}"`, plus duplicate/orphan weeks per group |
| `adminRescoreWeek` | recompute standings from current games/picks |

Reuse the existing `scoring.ts` helpers (`scorePicks`, `rankEntries`, `computeWeekAwards`) — do not fork scoring logic into the admin path, or the portal will silently disagree with `lockAndScoreWeeks`.

#### Rules unit tests (new, gate G0)

`firebase/tests/` with `@firebase/rules-unit-testing` + `vitest`, run against the emulator. Minimum cases:
- non-member cannot read `groups/{g}/messages`; member can
- member cannot create a message with `userId` ≠ own uid, 0 chars, or 501 chars
- member cannot forge `reportCount > 0` on create
- non-author cannot edit another's `text`; non-author **can** change only `reactions`
- non-admin cannot write `appConfig` or `adminAudit`; admin can create but not update `adminAudit`
- admin (claim `{admin:true}`) can update an arbitrary group they are not a member of
- existing regression: member's own pick readable pre-deadline, others' not (`firestore.rules:143–145`)

---

### Lane G — GROUP-PICKS: collapsible, default open, remaining count

`Pickems/Features/Picks/GroupPicksView.swift` (33 lines — full rewrite), `PickResultRow.swift`

Current: `Section(pick.displayName)` per user, not collapsible, no counts, and `submittedPicks` filters `allPicks.filter(\.isLocked)` (`:6–8`) so members who haven't submitted vanish entirely.

1. **Collapsible sections, default open.** Follow the established `manageExpanded` pattern (`GroupsView.swift:8`, `:258–290`): `@State private var collapsedUserIds: Set<String> = []` — collapse-by-exception keeps default-open without pre-seeding from async data. Header is a `Button` toggling inside `withAnimation(.easeInOut(duration: 0.2))`, with a `chevron.down` `.rotationEffect(.degrees(isCollapsed ? -90 : 0))`.
2. **Remaining-picks count** per member in the header: `"\(made)/\(total)"` where `total = appState.pickService.slateGames.count` and `made = pick.picks.keys.count`, plus `Text("\(total - made) left")` in `PickemsColors.warning` when non-zero. Section header also shows a `StatusBadge` "Submitted" / "In progress".
3. **Show everyone.** Drive the list from `appState.groupService.members`, left-joined to `allPicks`, so non-submitters render with an empty state instead of disappearing. Sort: submitted first, then `displayName`.
4. **Overall progress card** at top: `"\(submittedCount) of \(members.count) submitted"`.
5. **Spreads on every row** — pass `showSpread: true` (default) to `PickResultRow`.
6. `PickResultRow.swift`: add `var showSpread: Bool = true`; when true render `game.spreadLabel(for: game.spreadTeamId)` (`DomainModels.swift:124–129`) in `.caption.weight(.semibold)` / `theme.accent` beneath the matchup. Keep the existing `ScoringEngine.isPickCorrect` win/loss icon (`PickResultRow.swift:18–22`) untouched — scoring display is load-bearing.
7. Pre-deadline permission reality: `allPicks` is self-only until the deadline. Show "Picks hidden until the deadline" from `submissions` rather than surfacing a permission error; mirror the deferral already handled at `PickService.swift:120–131`.

---

### Lane H — DUP-GUARD + nomination-list spreads

`Pickems/Core/Services/PickService.swift`, `Pickems/Features/Picks/PicksView.swift`

1. **Commissioner duplicate guard.** `submitCommissionerGame` (`:240–265`) checks only `slateFull`. Add, before the write, mirroring `submitNomination`'s guard (`:140–143`):
```swift
guard !slateGames.contains(where: { $0.espnEventId == game.espnEventId }) else {
    throw PickError.duplicateGame
}
```
   Also guard the nomination set — a commissioner adding a game already nominated by a member creates a duplicate the moment `materializeNominationsIfNeeded` runs (`:187–216`), because it keys games by `espnEventId`:
```swift
guard !nominations.contains(where: { $0.espnEventId == game.espnEventId }) else {
    throw PickError.duplicateGame
}
```
2. **Defence in depth:** `materializeNominationsIfNeeded` writes with `.document(game.id)` where `id == espnEventId`, so duplicates collapse rather than double-write. Keep that; add a `AppLog.notice` when a collision is skipped so the admin portal has a trail.
3. **Wire C3 at the call site** (`PicksView.swift:40`):
```swift
GameBrowseView(
    games: viewModel.espnGames,
    nominatedEventIds: Set(appState.pickService.nominations.map(\.espnEventId)),
    nominatorNamesByEventId: Dictionary(
        appState.pickService.nominations.map { ($0.espnEventId, $0.submitterName) },
        uniquingKeysWith: { first, _ in first }
    )
) { game in /* existing closure unchanged */ }
```
4. **Spreads in the nominations list** (`PicksView.swift:179–197`): each nomination card currently shows only matchup + submitter. Add the line, using the same convention as `SlateGame.spreadLabel`:
```swift
Text("\(nom.spreadTeamAbbreviation) \(nom.spread < 0 ? "" : "-")\(abs(nom.spread).formatted(.number.precision(.fractionLength(1))))")
```
   `Nomination` (`DomainModels.swift:140–157`) has `spread` + `spreadTeamId` + both abbreviations, so resolve the favourite's abbreviation from `spreadTeamId` against `homeTeamId`/`awayTeamId`. Style `.caption.weight(.bold)` / `theme.accent`.
5. Keep `.pickemsEnvironment(appState)` on the `GameBrowseView` and `SpreadEditorSheet` sheets (`:40`, `:46`) — the 1.2.4 fix, per `docs/APP_STORE.md`.

---

### Lane I — WEEK-NUM: align copy to ESPN numbering

Data is already ESPN-aligned (`CFBWeekSync.weekId` → `"{year}-W{number}"`, ESPN `seasontype=2` never returns week 0). This lane is copy + the one genuine data hazard.

1. **Widget copy.** `PickemsWidget/PickemsWidget.swift` — replace every user-visible "Week 0" with kickoff language: `:199` and `:267` `"Until Week 0"` → `"Until Kickoff"`; `:222` `"Week 0"` → `"Kickoff"`; `:295` accessibility → `"… until college football kickoff"`; `:451` → `"… until college football kickoff on {day}."`; `:484` widget description → `"Kickoff countdown now; live group standings once the season starts."`
2. **Rename the API in both copies together** (they compile separately and must not drift): `weekZeroStart(forSeasonYear:)` → `seasonKickoff(forSeasonYear:)` and `nextWeekZeroStart(on:)` → `nextSeasonKickoff(on:)` in `Pickems/Core/Utilities/CFBSeasonCalendar.swift:6,32` **and** `PickemsWidget/CFBSeasonCalendar.swift:5,32`. Update the doc comments in all three `StandingsSnapshot.swift` copies' `:19` line (`Pickems/Shared/`, `PickemsWidget/`, `PickemsWatch/`) — comment-only, no behaviour change. Keep the August anchor dates (2026-08-27, 2025-08-23) as-is; they are correct kickoff dates, only the *name* was wrong.
3. **Fix the fallback estimator — the real hazard.** `CFBWeekSync.estimatedCFBWeek()` (`:14–21`) counts weeks from Aug 25 and clamps to `1...15`, and `fallbackWeekId()` uses it whenever the ESPN `currentWeek` call fails (`GroupService.swift:115–119`). A fallback that disagrees with ESPN's `week.number` **creates a second week doc for the same real week** (e.g. `2026-W3` alongside ESPN's `2026-W2`). Changes:
   - Anchor the estimator to `CFBSeasonCalendar.seasonKickoff(forSeasonYear:)` instead of a hardcoded Aug 25, so both files agree on the season start.
   - Prefer the **last known good** week over an estimate: persist the most recent successful `CFBWeekInfo` to `UserDefaults` in `ESPNService.currentWeek` and have `fallbackWeekId()` return that first, estimating only on a cold cache.
   - Log `AppEvents.failure` on every fallback so these are visible rather than silent.
4. **UI labels.** `WeekSummary.displayLabel` (`DomainModels.swift:88–90`) already renders `"Season 2026 | Week 3"` from ESPN's number — leave it. Audit remaining hardcoded week copy in `HomeView`/`PicksView` and route it all through `displayLabel`.
5. `docs/WIDGETS_WATCH.md:33` — rewrite the preseason paragraph in kickoff language and state explicitly that **the first playable slate is Week 1**.
6. Add `PickemsTests/CFBWeekSyncTests.swift`: `weekId(for:)` formatting; estimator returns `1` before kickoff and matches expected week at kickoff + 14 days; last-known-good wins over the estimate.

---

### Lane J — ADMIN: Firebase Hosting web admin

`firebase/admin/**` (new). Deploys to `https://<project>.web.app`.

#### Stack (defaults chosen, no options left open)

| Concern | Choice | Rationale |
|--|--|--|
| Build | **Vite 5 + React 18 + TypeScript** | fastest static build; Hosting wants a `dist/` |
| Routing | **React Router 6** (`createBrowserRouter`) | SPA rewrite already configured |
| Styling | **Tailwind CSS 3** | ops console; no design system needed |
| Firebase | **Firebase JS SDK 10 modular** (`auth`, `firestore`, `functions`) | tree-shaken, matches rules model |
| Data | `onSnapshot` in small custom hooks (`useGroups`, `useWeeks`, `usePicks`) | no extra state library for ~9 screens |
| Tables | plain semantic `<table>` | avoids a grid dependency for admin volume |
| Lint | `tsc --noEmit` + `eslint` | gate G3 |

Config via Vite env (`firebase/admin/.env.local`, gitignored), values from `firebase_get_sdk_config` for the web app — never reuse `GoogleService-Info.plist` values by hand.

#### Auth gate — defence in depth

1. `signInWithEmailAndPassword` **and** `GoogleAuthProvider` popup.
2. After sign-in: `await user.getIdTokenResult(true)` (force refresh — a freshly granted claim is absent from a cached token).
3. If `claims.admin !== true` → `signOut()` immediately and show "This account is not authorized." Do not leave a half-authenticated session.
4. `<RequireAdmin>` route guard wraps every route except `/login`.
5. **The UI is not the security boundary** — Hosting is public and the bundle is readable. Firestore rules (`isSuperAdmin()`) are the only real gate; every screen must still work correctly if someone strips the guard.
6. Re-check the claim on `onIdTokenChanged` so a revoked admin loses access within an hour without a manual sign-out.

#### Pages

| Route | Purpose | Backing |
|--|--|--|
| `/login` | email/password + Google, claim check | Auth |
| `/` | dashboard: group/user counts, weeks by status, recent `adminAudit` | Firestore reads |
| `/groups` | searchable group list (name, invite code, member count, `isPublic`) | `groups` |
| `/groups/:id` | rename, toggle `isPublic`, edit `GroupRules`, regenerate invite code, delete | direct writes + `inviteCodes` |
| `/groups/:id/members` | add/remove member, transfer commissioner, reset season W-L | `adminRemoveMember`, `adminTransferCommissioner` |
| `/groups/:id/weeks` | week list + status, force transition, set `pickDeadline`, re-materialize, edit spreads, delete week | `adminSetWeekStatus`, `adminRematerializeNominations` |
| `/groups/:id/weeks/:weekId/picks` | grid of members × slate games, edit a pick, unlock/relock, rescore | `adminUpsertPick`, `adminRescoreWeek` |
| `/config` | `appConfig/live` editor: feature flags (`chatEnabled`, `top25FilterEnabled`), `minimumBuild`, marketing strings | `appConfig` |
| `/audit/weeks` | **R1 tool** — misaligned/duplicate/orphan week docs with per-row merge/delete | `adminAuditWeekIds` |
| `/audit/log` | append-only admin action log | `adminAudit` |
| `/moderation` | messages with `reportCount > 0`, soft-delete / hard-delete / see reporters | `messages` + `reports` |

Every mutating action: confirm dialog naming the group, optimistic-free (await then refetch), and an `adminAudit` entry `{ actorUid, actorEmail, action, targetPath, before, after, createdAt }`.

`firebase/admin/README.md` documents install, `.env.local` keys, `npm run dev` against emulators, and `firebase deploy --only hosting`.

---

### Lane K — ASO: metadata, fastlane, SEO

1. **`fastlane/` scaffold** (new) — `deliver` metadata as files so copy is reviewable in git, plus an optional `pilot` lane. Structure:
```
fastlane/Appfile           # app_identifier FannypackInc.Pickems, apple_id 6785697079
fastlane/Deliverfile
fastlane/Fastfile          # lanes: metadata (deliver --skip_binary_upload), beta (pilot)
fastlane/metadata/en-US/{name,subtitle,keywords,description,promotional_text,release_notes,privacy_url,support_url}.txt
```
2. **Subtitle** (30 char max) — pick: `College football pick'em leagues` is 32, so ship **`CFB pick'em with your crew`** (26).
3. **Keywords** (100 chars, comma-separated, no spaces, no repeats of the app name or subtitle words):
   `pickem,pick em,college football,cfb,spread,against the spread,ats,league,commissioner,bowl`  (98 chars)
4. **Description** — rewrite around the differentiators that actually exist in the app: member game nomination (each member nominates, group builds the slate), picks against the spread, live scoring, weekly + season standings, dynasty/career records, awards (sharpshooter/heartbreaker/contrarian), widgets + Live Activities, group chat. Lead paragraph carries the searchable phrases naturally; no keyword stuffing.
5. **`docs/ASO.md`** (new) — keyword rationale, character counts, screenshot plan (6.9" + 6.5" required), and a "what changed this release" section for iterative ASO.
6. **`docs/APP_STORE.md`** — currently stale at 1.2.4/124. Update version block to 2.3.0/230, add a "Fixes in 2.3.0" table covering all 11 workstreams, and rewrite the App Review notes: **explicitly describe the chat moderation controls** (report, block, delete own, terms) since Guideline 1.2 is the highest rejection risk this release.
7. **pickems.app SEO** — `web/` (new) static landing page deployed to a second Hosting target: `<title>`, meta description, Open Graph + Twitter card, `application/ld+json` `SoftwareApplication` schema, canonical URL, `robots.txt`, `sitemap.xml`, and an App Store smart-banner meta tag. Also move Privacy/Terms here (they currently point at `raw.githubusercontent.com`, which is functional but reads as unprofessional and gives Apple a non-branded domain).
8. Zero code conflict — this lane touches no `.swift` file.

---

### Lane L — RELEASE (Wave 3)

Sole owner of `Pickems.xcodeproj/project.pbxproj`.

1. `MARKETING_VERSION` `2.2.3 → 2.3.0` and `CURRENT_PROJECT_VERSION` `223 → 230`, for **Debug and Release configs of all three shipping targets** — `Pickems` (`:547`, `:531`), `PickemsWidget`, `PickemsWatch`. Mismatched extension versions fail App Store validation.
2. Watch app stays **not embedded** for this build (`docs/APP_STORE.md`) — do not change embedding in a feedback release.
3. Discard the noise files in `git status` (`UserInterfaceState.xcuserstate`, `xcschememanagement.plist`); add both to `.gitignore` if not already covered.

---

## 5. Review and merge gates

Every lane's PR must pass G1–G4. Lane F additionally owns G0.

| Gate | Check | Command |
|--|--|--|
| **G0** | Firestore rules unit tests (Lane F + Lane E rules) | `cd firebase && npm --prefix tests test` against `firebase emulators:exec` |
| **G1** | iOS build + unit tests | `xcodebuild -scheme Pickems -destination 'platform=iOS Simulator,name=iPhone 16' clean build test` |
| **G2** | **Sheet-environment regression** — every new `.sheet` root has `.pickemsEnvironment(appState)` | extend `PickemsTests/LaunchSafetyTests.swift`; reviewer greps the diff for `\.sheet` |
| **G3** | Admin web typecheck + build | `cd firebase/admin && npx tsc --noEmit && npm run build` |
| **G4** | Bugbot review, zero unresolved high-severity | per PR |
| **G5** | Functions compile | `cd firebase/functions && npm run lint && npm run build` |

**Merge order (enforced):** `F` → (`A`,`B`,`G`,`H`,`I`,`K` in any order) → (`C`,`E`,`J`) → `D` → `L`.

`D` merges last among features because it is the only lane that consumes another lane's new symbol (`GroupChatEntryButton` from `E`, per C4). If `E` slips, `D` ships with the chat button omitted and everything else intact — that is the designed fallback, not a scramble.

Integration branch: cut `release/2.3.0` off `main`; every lane PRs into it. Squash-merge each lane, then one PR `release/2.3.0 → main` after G1–G5 pass on the integration branch.

---

## 6. Deploy and TestFlight sequence

**Order matters: rules before build.** A TestFlight build that exercises chat or admin-touched paths against un-deployed rules fails with permission-denied and reads as a product bug.

1. **Deploy Firestore indexes first** (composite index builds are async and queries fail until `Enabled`):
   `cd firebase && firebase deploy --only firestore:indexes` → confirm `messages` index is **Enabled** in console.
2. **Deploy rules + storage:** `firebase deploy --only firestore:rules,storage`
3. **Deploy functions:** `firebase deploy --only functions` (adds `admin.ts`, `chat.ts` exports)
4. **Grant the super-admin claim:** `node firebase/admin-tools/set-admin.mjs <owner-email>`
5. **Deploy admin web:** `cd firebase/admin && npm ci && npm run build && cd .. && firebase deploy --only hosting` → sign in at `https://<project>.web.app`, confirm a non-admin account is rejected.
6. **Seed `appConfig/live`** via the portal: `chatEnabled: true`, `minimumBuild: 230`.
7. **Version bump** (Lane L), commit, tag `v2.3.0-230`.
8. **Archive:** Xcode → *Product ▸ Archive*, scheme `Pickems`, destination *Any iOS Device (arm64)*, Release config. Manual archive for this release — no iOS CI exists and adding it inside a feedback release is unnecessary risk. `fastlane beta` is scaffolded (Lane K) for the *next* release.
9. **Validate then upload:** Organizer → *Validate App* (must pass clean; version-mismatch and missing-entitlement errors surface here) → *Distribute App ▸ App Store Connect ▸ Upload*.
10. **App Store Connect (owner's Chrome):** wait for processing, complete the **Export Compliance** prompt, add build `230` to the internal TestFlight group, fill "What to Test" (below).
11. **Confirm delivery:** build shows *Ready to Test*; installs on device via TestFlight.

**What to Test (paste into TestFlight):**
> 1. Sign in — Apple button is now first; "Use email and password instead" reveals the old form.
> 2. Groups — open Group Picks, Build Slate / Make Picks / Live Picks, and Chat directly from Groups.
> 3. Nominate a game — already-nominated games are greyed out and show who took them. Try Top 25 and conference filters; spreads show on every row.
> 4. Group Picks — tap a member's name to collapse/expand; check the "x left" counts.
> 5. Chat — send a message, confirm another member sees it, then try report / block / delete-own.
> 6. Home Screen widget — preseason copy says "Kickoff", never "Week 0".
> 7. Confirm the first playable slate is labelled **Week 1**.

**Rollback:** `firebase deploy --only firestore:rules` from the previous git revision of `firestore.rules` (rules are versioned in console and revertible independently of the build). Chat can be killed without a build via `appConfig/live.chatEnabled = false` — provided the iOS client honours the flag, which Lane E must implement.

---

## 7. Risks

**R1 — ESPN week alignment vs. existing Firestore docs (highest data risk).**
Week doc IDs are already `"{seasonYear}-W{espnWeekNumber}"`, so there is **no migration for correctly-created docs**. The exposure is `fallbackWeekId()` (`CFBWeekSync.swift:8–12`), used whenever the ESPN call fails (`GroupService.swift:115–119`): its `estimatedCFBWeek()` can disagree with ESPN and mint a *parallel* week doc for the same real week, splitting nominations and picks across two docs. Mitigations: last-known-good week preference (Lane I.3), `AppEvents.failure` logging on every fallback, and the `/audit/weeks` portal tool (Lane J) to detect and merge divergent docs. **Run the audit against production before the TestFlight invite** so the PO isn't the one who finds a split week.

**R2 — Admin privilege model.**
- Claims are baked into the ID token: a grant is invisible until refresh (force `getIdTokenResult(true)`), and a revoke persists up to an hour. Accept the hour, or add a `tokenRevokedAt` check for immediate cutoff.
- Folding `isSuperAdmin()` into `isCommissioner()` is a deliberately wide blast radius — a bug in the claim check becomes a global write. This is why G0 rules tests explicitly assert that a non-admin, non-member cannot write another group.
- The service-account JSON for `set-admin.mjs` must never enter the repo. `.gitignore` `*.json` under `firebase/admin-tools/` and keep the key outside the workspace.
- **`Pickems/Core/Utilities/DevAdminConfig.swift` has hardcoded credentials** (`pickems-admin`, `PickemsDev1`) and is in git history. It is `#if DEBUG`, so it does not ship — but rotate that Firebase Auth password now, and delete the file once the web portal replaces its purpose.

**R3 — Chat rules cost and correctness.**
`isGroupMember(groupId)` performs a `get()` on the group doc. Firestore evaluates rules per document on list queries but caches `get()` results within a request, so a 50-message page costs ~1 extra read, not 50 — acceptable, and consistent with every existing collection. Watch the 10-`get()`-per-request ceiling if chat rules are ever nested deeper. Also: `createdAt == request.time` is what makes ordering trustworthy; without it a client can backdate a message to the top of the thread.

**R4 — App Review Guideline 1.2 (UGC) — highest release risk.**
Shipping group chat converts Pickems into a user-generated-content app. Apple requires a content filter, a report mechanism, a block mechanism, and a published way to contact the developer. Missing any one is a documented rejection cause, and this app already has a rejection history. Lane E's moderation set is **not optional scope** — if it can't land, `chatEnabled: false` and hold chat for 2.3.1. Lane K must describe the controls in the review notes.

**R5 — `groups=80` changes the game universe.**
Adding the FBS filter *removes* FCS/D2 games that members could previously nominate. Any existing nomination or slate game referencing a non-FBS event still lives in Firestore and will no longer appear in browse — harmless for already-materialized games (they render from Firestore, not ESPN) but `lockAndScoreWeeks` scores from `fetchScoreboard()`, which the Cloud Function already restricts to `groups=80` (`espn.ts:26`). So non-FBS games were **already unscoreable server-side**; this change makes the client honest about it. Verify no active week has a non-FBS game before deploying, via the admin portal.

**R6 — Parallel-lane merge risk is low but not zero.**
Synchronized Xcode groups eliminate the usual `.pbxproj` conflict, and single-owner file assignment eliminates the rest. The two real coupling points are contract C3 (`GameBrowseView` init — mitigated by defaulting the new parameters) and C4 (`GroupChatEntryButton` — mitigated by Lane D merging last with a documented omit-the-button fallback).

**R7 — `firebase.json` currently has no `indexes` key.**
Adding it means `firebase deploy --only firestore` will start managing indexes declaratively. Any index created by hand in the console and absent from `firestore.indexes.json` **is deleted on deploy**. Before Lane F merges: run `firebase firestore:indexes > firebase/firestore.indexes.json` to capture existing production indexes, then add the `messages` index on top.

**R8 — Scope.**
Eleven workstreams plus a new web app plus a new backend surface in one release is a lot to validate in one TestFlight pass. The independent kill switches, in order of preference: chat behind `appConfig.chatEnabled`; the admin portal ships independently of the build (Hosting, not App Store) and can slip without touching the release; Lane K's `web/` landing page is fully decoupled. The iOS UX lanes (A, C, D, G, H, I) are the irreducible core of the feedback round.
