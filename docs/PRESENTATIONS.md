# SwiftUI presentations

One presenter per level. A `Form` / `List` recycles rows. A `.sheet`, `.alert`, or
`.fullScreenCover` on a row or `Section` is torn down on the next Firestore tick,
and UIKit dismisses whatever that level is showing.

## Rules

1. One `.sheet(item:)` per screen, driven by an `Identifiable` route enum in
   `@State` on the screen root (outside `Form`, `List`, `ForEach`, and `if`).
   Children call `present` or flip a binding the parent owns.
2. Route ids are stored at tap time, never derived from live data.
   The route value carries everything the sheet renders (the carousel week,
   the deadline edit). Do not mirror that payload in a second `@State` or
   re-read `currentWeek` inside the sheet content. `sheet(item:)` can present
   before that sibling state is visible, and the sheet then shows an empty
   state ("No Active Week", 3.6.6). Keep `id` stable so a later week-field
   change does not dismiss the sheet.
3. Reusable components (`*Button`, `*Row`, `*Card`, `*Board`) do not own sheets.
   They set `HelpPresenter.modal`, injected by `pickemsEnvironment` → `presentsHelp()`.
4. Never bind one presentation to state shared by two mounted views.
5. Programmatic app-level prompts use `AppSheetPresentPolicy.ifIdle`.
6. `.task` and `.onAppear` go on the screen root, never on a `Section` or row.

## Why this keeps coming back

`a401352` (Aug 13) hoisted sheets off `CommissionerWeekAdminSections` after they
dismissed Settings. `fd7f19a` (Aug 31) added the single `AppSheet` host. Sep 14
put `rankDraft` back on that section, and #68 (`8862833`) added Selections, Slate,
and the league-type alert the same way. Each fix was local, so the bug returned.

## Do / don't

```swift
// Do: one route on the screen root
.sheet(item: $route) { (route: CommissionerSheet) in
    routeContent(route)
}

// Don't: .sheet / .alert / .task on a Section inside a Form
Section { /* rows */ }
    .sheet(item: $draft) { /* ... */ }
```

## Adding a case

- Settings: add a `CommissionerSheetRequest` case and a `CommissionerSheet` case
  (payload on the case, stable `id`), a `routeContent` branch, and a
  `CommissionerDeadlinePresentation.route` arm. Rows call `present` with the
  carousel week when the sheet needs one.
- Tab-root prompts: add an `AppSheet` case and a branch in `AppSheetHost`.
  Pass `.ifIdle` when the prompt must not replace an open sheet.
- Help or share from a button: add a `ScreenModal` case and a branch in
  `PresentsHelpModifier`. Buttons assign `helpPresenter?.modal`.

## Waiver

A reviewed fallback (no screen presenter, such as a preview) may keep a local sheet.
Put this on the modifier line: `// presentation-ok: fallback when no screen presenter`

`python3 scripts/check-presentations.py Pickems` enforces this. TestFlight CI runs it
before the archive and fails the job on the first violation.
