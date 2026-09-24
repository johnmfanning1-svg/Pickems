# Paste this into Cursor on Sunday (ship day)

You are finishing **Selection slate-limit UX + late-joiner `slateSize` reconcile** for CFB Pickems (`johnmfanning1-svg/Pickems`, Firebase `pickems-fb`, bundle `FannypackInc.Pickems`).

## Mission
Ship the already-started fix so members cannot get a false “Selection limit or deadline” error when the real problem is a short week `slateSize` (or a full slate), and late joiners expand the week slate correctly.

**App Store build cannot wait on more product work — verify, TestFlight, then App Store.** Prefer local / Grok Bot / `gh`; do **not** burn Cursor Cloud Agent quota unless John says to.

## Incident (already mitigated in live data)
- League **Core 4 OG** `groups/qb2aPmmAm1ZSWZnQVnNL`, week `2026-W4`
- 4 members × `selectionsPerMember: 3` → expected slate **12**
- Week stayed at `slateSize: 9` (minted at 3 members); Fannypack/bbenson/Hayden filled 9/9
- **JBanda (Jack)** had 0 nominations; deadline still open; Save threw conflated `nominationLimitReached`
- Browse showed “1 of 3” via stale unique count + `max(..., 1)` floor
- **Ops fix already applied:** W4 `slateSize` bumped **9 → 12** (Jack confirmed working Wed Sep 23)
- Audit: only other short-slate multi-member league was idle **Alexas Pickems** W2/W3 at 3 vs expected 6 — John said **leave alone**

## Branch / code status (verify, don’t redo blindly)
- Branch: `fix/selection-slate-limit-ux`
- Commit message starts: `Fix Selection slate-limit UX and late-joiner slateSize reconcile`
- Key changes already intended:
  - `PickError.slateFull` separate from personal limit + deadline (`selectionClosed`)
  - Copy: personal limit / “league slate is full” / deadline — no conflated string
  - Gate Select Games / Browse when remaining slate slots are 0
  - Remove dead-end `max(..., 1)` when true remaining is 0
  - `SelectionSlateReconcile` + reconcile on join / select / membership / week mismatch
  - Never shrink `slateSize` below taken unique games
  - Save/browse remaining uses `max(week.slateSize, expectedSlateSize)`
  - Unit tests: `PickemsTests/SelectionSlateReconcileTests.swift`

## Sunday checklist
1. `git fetch` and confirm PR exists for `fix/selection-slate-limit-ux` → `main`. If missing, push + `gh pr create` (do **not** merge until checklist below is green).
2. Read the PR diff; if anything from Mission is missing, finish it on the same branch.
3. Run unit tests for SelectionSlateReconcile (Xcode on Mac / CI). Fix failures.
4. Merge PR when John says go (or after he reviews).
5. Cut **TestFlight** build from that `main` (coordinate with existing join-ticket / P0 ship order in `docs/` — join-ticket path should already be on main from PR #47; do **not** deploy undeployed P0 Firestore rules until TF with join path is what users run).
6. Smoke on device / TestFlight:
   - Member with personal slots left but slate full → clear slate-full message; no Select Games dead-end
   - Personal limit → personal-limit copy only
   - Past deadline → selectionClosed copy only
   - Late join during selection → week `slateSize` grows to `members × selectionsPerMember` (and never below taken)
7. App Store submit when TF smoke passes.
8. Optional ops: re-run short-slate audit (`status == selection`, `slateSize < expected`); only patch live weeks John approves.

## Hard constraints
- Do **not** deploy P0 Firestore rules until TestFlight with join-ticket client is live
- Do **not** launch Cloud Agents unless John tops up / asks
- Do **not** bump Alexas weeks unless he changes his mind
- Do **not** invent APIs — verify against repo
- Open/finish PR; merge only when asked or after explicit Sunday go

## Acceptance
- [ ] PR merged to `main` with distinct errors + slate-full gating + reconcile harden
- [ ] Tests green
- [ ] TestFlight build installed and smoke passed
- [ ] App Store build submitted (or ready in ASC)
- [ ] Core 4 remains healthy (Jack can select when slots remain)

## Reference
Full write-up: `SELECTION_SLATE_LIMIT_FIX.md` in this folder (and `docs/` once committed).
