# Selection slate-limit UX + late-joiner `slateSize` reconcile

**Ship window:** Sunday (App Store build). Live data for Core 4 already patched Wed Sep 23.
**Repo:** `johnmfanning1-svg/Pickems` · Firebase `pickems-fb` · iOS `FannypackInc.Pickems`
**Branch:** `fix/selection-slate-limit-ux`

## Problem
Member-mode weeks store `week.slateSize` derived as `members × selectionsPerMember` at mint time. If someone joins later and reconcile fails or never runs, the week can stay short. Other members can fill every slot. A member with **0 personal nominations** and an **open deadline** still sees Select Games, can pick (Browse limit floored / stale), then Save throws:

> You've reached your Selection limit or the Selection deadline has passed.

That string conflates personal limit, slate full, and deadline. Real cause for Jack (Core 4 OG W4): **slate full at wrong size (9 vs expected 12)**.

## Live mitigation (done)
| League | Week | Action |
| --- | --- | --- |
| Core 4 OG `qb2aPmmAm1ZSWZnQVnNL` | `2026-W4` | `slateSize` 9 → **12**; Jack confirmed Save works |
| Alexas Pickems `cKbju3nUMOZ19RkVDy4X` | W2/W3 short (3 vs 6) | **Left alone** (idle) per John |
| PPP, Bettors High, Jacks Spread, Seagulls, Apple Test, The Boys | current weeks | OK / N/A |

## Product fix (code — on branch)
1. **Distinct errors** (`PickService.PickError`): personal Selection limit · `slateFull` · `selectionClosed` (deadline).
2. **UX:** don’t offer a dead-end Select Games when remaining slate slots are 0; fix `GameBrowseView` `max(..., 1)` floor when remaining is 0.
3. **Reconcile:** expand `week.slateSize` to `rules.expectedSlateSize(memberCount)` during `.selection` on join / select / membership / mismatch; never shrink below unique taken games.
4. **Save/browse math:** use `max(week.slateSize, expected)` so a stale short client snapshot doesn’t falsely zero slots when expected is larger.

Files: `PickService.swift`, `GroupService.swift`, `SelectionSlateReconcile.swift`, `GameBrowseView.swift`, `PicksView.swift`, `PicksViewModel.swift`, `CommissionerManageSelectionsSheet.swift`, `SelectionSlateReconcileTests.swift`.

## Sunday ship order
1. Finish/verify PR → merge when approved  
2. TestFlight from `main`  
3. Smoke selection paths  
4. App Store  
5. Keep P0 Firestore rules deploy gated behind join-ticket TF (existing release rule)

## Cursor paste prompt
See `SELECTION_SLATE_LIMIT_SUNDAY_PROMPT.md` in this folder.
