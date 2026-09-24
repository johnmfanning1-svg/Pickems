# Selection slate-limit fix (Core 4 OG / late joiners)

## Incident (production, verified)

- League: **Core 4 OG** (`groups/qb2aPmmAm1ZSWZnQVnNL`)
- Week: **2026-W4**
- Symptom: `week.slateSize` stayed at **9** after the roster grew to **4 members × `selectionsPerMember` 3 = expected 12**.
- Three members filled all 9 unique slots. **Jack (JBanda)** had personal slots left (0 noms, open deadline) but **Save** threw `PickError.nominationLimitReached` with copy that also blamed the Selection deadline.
- Browse footer still showed **"1 of 3 selected"** because `GameBrowseView` floored the limit with `max(..., 1)` even when remaining slate slots were 0.

Live data was already patched: W4 `slateSize` bumped to **12**. This change is the durable product/code fix.

## Root cause

1. **Stale `week.slateSize` after late join** — `reconcileSelectionWeekSnapshot` existed on `joinGroup` / `updateRules`, but the groups listener skipped week sync when membership grew while already observing the same week, so slate size often never expanded.
2. **Conflated errors** — `submitNominations` zeroed remaining slots for personal limit, slate full, *or* deadline, then always threw `nominationLimitReached`.
3. **Dead-end Select Games UX** — Browse/`PicksView` still offered a pick flow when the league slate had no room.

## What changed (this PR)

| Area | Change |
|------|--------|
| `PickService.submitNominations` / `PickError` | Distinct errors: personal Selection limit, league slate full, Selection deadline (`selectionClosed`). Re-read server `slateSize` and use `max(client, expected)` so a stale snapshot cannot falsely zero slots; self-heal by writing expanded `slateSize` when expected is larger. |
| `GameBrowseView` / `PicksView` / commissioner manage sheet | No usable Select Games flow when remaining slate slots are 0; removed `max(..., 1)` floor; clear slate-full copy. |
| `GroupService.reconcileSelectionWeekSnapshot` | Authoritative `memberCount`; expand on join / select / membership listener / week snapshot mismatch; **never shrink below** unique nomination+game count. |
| `SelectionSlateReconcile` + tests | Pure helpers for target/effective/remaining slate math. |

## Sunday ship steps

Do **not** merge or deploy Firebase from the agent. Ship when ready for App Store:

1. **Review & merge** this PR into `main` when approved.
2. **Build** a release candidate from `main` (Xcode archive).
3. **TestFlight**
   - Upload the build.
   - Smoke on a member-mode league during `.selection`:
     - Late join while slate is partially filled → `slateSize` expands to `members × selectionsPerMember`.
     - Member with personal slots left but slate full → no dead-end Select Games; sees slate-full messaging (not deadline copy).
     - Personal limit vs deadline still show their own errors.
4. **App Store**
   - Submit the same (or next) build after TestFlight sign-off.
   - No Hosting/Firebase Functions deploy required for this fix (client + week doc reconcile only). Live W4 data patch already applied.

## Follow-ups / risks

- `PickError.slateFull` copy is now member-slate oriented; commissioner “open week with empty games” still reuses that case (rare).
- Week-listener reconcile can write once when membership/rules disagree with `week.slateSize`; guarded to no-op when already aligned.
- XCTest/Swift Testing for this target is not runnable on the Linux agent box — run `SelectionSlateReconcileTests` (and related) in Xcode before ship.
