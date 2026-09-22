# Shock Tweets v1

After a surprising college football final, Pickems writes an anonymized draft tweet to `shockTweets/{id}`. Nothing in this version logs into X or posts as @CFB_PICKEMS.

Firebase project: `pickems-fb`. Functions live in `firebase/functions`.

## What gets written

A scheduled function, `detectShockTweets`, and a manual callable, `runDetectShockTweets`, scan active weeks, aggregate picks for each final, and create one document per game per scoring mode.

Writes go through the Admin SDK. Client Firestore rules do not need a change, and this work does not deploy rules.

The draft never includes a user id, league id, league name, or commissioner name. The stat is a count of picks, so the same person in two leagues counts twice.

## Schedule

Cloud Scheduler cron, timezone `America/New_York`:

```text
*/20 12-23 * * 0,6
```

That fires every 20 minutes from noon through 11:40pm ET on Saturday (`6`) and Sunday (`0`). The function then keeps the run only when `isShockTweetWindow` is true:

| Day | Window (ET) | Ticks |
|---|---|---|
| Saturday | 3:00pm–11:59pm | 3:00pm, then every 20 minutes, through 11:40pm |
| Sunday | 12:00pm–12:59pm | 12:00pm, 12:20pm, 12:40pm |

Ticks outside those windows return immediately.

`lockAndScoreWeeks` still records finals about every 5 minutes. Shock detection waits until the slate game document's `updateTime` is at least **8 minutes** old, and ignores a final whose newest write is more than **12 hours** old. There is no `finalizedAt` field on the game. The 12-hour lookback is what lets Sunday midday still see a late Saturday final. A final that lands after the 11:40pm Saturday tick can age out before Sunday noon; the next Saturday window picks up new games.

The callable ignores this window so it can be run midweek.

## Thresholds

Constants in `SHOCK_TWEET_CONFIG` (`firebase/functions/src/shockTweets.ts`):

| Constant | Value | Meaning |
|---|---|---|
| `minPickCount` | 10 | Picks on that game, in one mode, across leagues |
| `dogPickPctMax` | 35 | Dog cover or straight-up dog win qualifies at this share or lower |
| `favoritePickPctMin` | 70 | Favorite fails to cover, or loses straight up, at this share or higher |
| `settleDelayMs` | 8 minutes | Ignore a final newer than this |
| `lookbackMs` | 12 hours | Ignore a final older than this |
| `maxTweetLength` | 280 | Drafts are clipped to this only after abbreviation fallback |

Percent thresholds use the raw ratio (`count / pickCount * 100`). The stored `homePickPct` / `awayPickPct` and the number in the draft are `Math.round` of that ratio, so 19/86 is **22%**.

When both heuristics match, the dog reason wins. That is the common case: a dog share of 30% is a favorite share of 70%. Favorite-fail is the path for a spread push, where the dog did not cover either.

A spread of 0 has no dog. Those finals are not drafted.

## Scoring mode

ATS and straight up are never combined into one percent.

- League mode is `groups/{groupId}.rules.pickMode` (`ats` or `straightUp`). Missing values resolve to `ats`.
- A week may override with `groups/{groupId}/weeks/{weekId}.pickMode`.
- `resolveWeekPickMode` decides the mode. Straight Up leagues stay Straight Up.
- Cover, win, and push all come from `coveredTeamId`. Pick counts use `pickedTeamId`. This module does not reimplement that math.

Document id: `{gameKey}_{mode}`.

`gameKey` is `espnEventId` when the slate game has one. Otherwise it is `{awayTeamId}@{homeTeamId}`. Cross-league totals only merge on that key, so a missing `espnEventId` will not join a slate that has one.

## Which games are read

For each group:

1. Weeks with `status` of `picking` or `locked` are read (season year at least last year, when `seasonYear` is set).
2. Weeks with `status` of `scored` are read only when `scoredAt` is inside the 12-hour lookback.
3. Each game must have `status === "final"` and numeric `homeScore` and `awayScore`.
4. Picks come from `groups/{groupId}/weeks/{weekId}/picks/{userId}` field `picks` (map of game id → team id). The game id is the slate game document id.
5. When `groups/{groupId}.memberIds` is non-empty, only those members count.

If leagues disagree on the score, the teams, the favorite, or who covered, the run writes nothing for that game and tries again next time. A later agreement can still create the draft. A pick'em (`spread === 0`) is ignored.

Stored `spread` and `spreadTeamId` come from the slate with the most picks in that mode.

## `shockTweets/{id}`

| Field | Notes |
|---|---|
| `id` | Same as the document id |
| `espnEventId` | Omitted when the slate has none |
| `gameKey` | Aggregation key |
| `homeTeamName`, `awayTeamName` | Display names, else abbreviations |
| `homeScore`, `awayScore` | Final score |
| `spread`, `spreadTeamId` | From the largest slate in this mode |
| `mode` | `ats` or `straightUp` |
| `pickCount`, `homePickCount`, `awayPickCount` | Picks on home or away only |
| `homePickPct`, `awayPickPct` | Integers 0–100, rounded |
| `coveredTeamId` | Team id, or `null` on a push |
| `winnerSide` | `home`, `away`, or `push` — the cover side for this mode |
| `shockReason` | `dog_cover_low_pct`, `dog_win_low_pct`, or `favorite_fail_high_pct` |
| `draftTweet` | ≤ 280 characters. Matchup, final score, one surprise, one stat with N |
| `status` | `pending`, `posted`, `skipped`, or `failed` |
| `skipReason` | `min_sample` when N is below 10. Omitted on `pending` |
| `createdAt`, `updatedAt` | Server timestamps |
| `postedAt`, `postedUrl` | Left unset. A later poster fills these |

`status: "pending"` is the post queue. `skipped` means the outcome was surprising but fewer than 10 picks backed it. The draft text is still stored. Do not post `skipped`.

Below the minimum, the document is `skipped`, not `pending`.

If a document already exists — `pending`, `posted`, `skipped`, or `failed` — a later run leaves it alone. Detection will not refresh the percent or flip `posted` back to `pending`.

### Draft shape

```text
FINAL: Kansas 31, Alabama 24. Only 22% of Pickems picks (19/86) took the dog — and they covered.
```

A straight-up dog win says "won". An ATS push where the favorite was heavily picked says "didn't cover". No links, no gambling call to action, and no invented counts.

## Callable

`runDetectShockTweets` takes an empty payload and returns:

```json
{
  "created": 1,
  "unchanged": 0,
  "pending": 1,
  "skipped": 0,
  "deferred": 0,
  "held": 0
}
```

`deferred` counts finals still inside the 8-minute settle window. `held` counts in-window finals whose leagues disagreed, or whose team names were missing. `unchanged` counts ids that already had a document.

The caller must be signed in with the Firebase Auth custom claim `admin: true` (the same claim as the admin portal). After a functions deploy, invoke it from the Firebase console or any callable client against `runDetectShockTweets` in `us-central1`. The callable runs the detector immediately. It does not post to X.

## Posting (out of scope)

A later pass can:

1. Read `shockTweets` where `status == "pending"`.
2. Post `draftTweet` as @CFB_PICKEMS. John handles 2FA if that is done in a browser.
3. On success, set `status` to `posted`, plus `postedAt` and `postedUrl`.
4. On failure, set `status` to `failed` and send John the draft to paste.

This repo does not automate X login or posting. No paid X API and no mobile measurement partner are part of v1.

## Deploy

Prefer a functions-only deploy of the new exports:

```bash
firebase deploy --only functions:detectShockTweets,functions:runDetectShockTweets
```

Do not deploy Firestore rules with this change. P0 rules stay undeployed until the join-ticket iOS build ships. Avoid the full Deploy Firebase workflow when it depends on `SUPPORT_*` secrets.

No new composite index is required. Week reads use the single-field `status` index.
