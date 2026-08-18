# App Store submission notes

## Version

- **Marketing version:** 2.4.0
- **Build:** 240
- **Bundle ID:** `FannypackInc.Pickems`
- **Apple ID:** 6785697079
- **ASO copy:** `docs/ASO.md` · upload via `fastlane/metadata/en-US/`

---

## What Apple rejected in 1.0 (build 2)

App Review attached crash logs from **2026-07-15** on iPhone OS 26.5.2. All incidents match the same failure:

| Field | Value |
|--|--|
| Exception | `EXC_BREAKPOINT` / `SIGTRAP` |
| Faulting path | `EnvironmentValues.subscript.getter` → `SheetBridge.present` |
| Timing | ~3–7s after launch while presenting a sheet |
| Likely UI | Groups → **Commissioner Settings** or **Join** (see review screenshot) |

Root cause: SwiftUI sheets reading `@Environment(AppState.self)` without a guaranteed environment (and empty `if let` sheet content). Fixed in 1.2.3 via `.pickemsEnvironment(appState)` on sheet roots and non-empty Commissioner Settings sheet content. Still required for any new sheets in 2.3.0.

## Work already shipped after 1.0 (through 1.2.4)

| Change | Status |
|--|--|
| Auth navigation / email-password / favorite team | Merged |
| Theme contrast + session tracing | Merged |
| TestFlight cold-launch Firebase / notifications crash → 1.2.2 | Merged |
| Sheet environment crash + Groups UX + account deletion | Merged (1.2.3 / 1.2.4) |
| Privacy Manifest, Privacy Policy + Terms, invite App Store URL | Merged |
| Watch app not embedded for iPhone App Store build | Remains for 2.3.0 |

## Fixes in 2.3.0 (this submission)

Feedback-driven release covering all eleven workstreams:

| Workstream | Fix |
|--|--|
| **AUTH** | Sign in with Apple is primary; email/password behind “Use email and password instead” |
| **GROUPS-NAV** | Group Picks, Build Slate / Make Picks / Live Picks, and Chat reachable from Groups |
| **NOMINATE-UX** | Already-nominated games greyed out in browse with nominator name; Top 25 + conference filters; spreads prominent |
| **DUP-GUARD** | Commissioner cannot add a game already on the slate or in nominations |
| **GROUP-PICKS** | Collapsible per-member sections (default open) with remaining-picks counts; spreads on rows |
| **ESPN-SLATE** | FBS-only scoreboard (`groups=80`); rank + conference decode; spreads hardened |
| **WEEK-NUM** | Preseason/widget copy uses Kickoff until Aug 29; first playable slate is Week 0 (Saturday openers), then Week 1 (Sep 3–7) |
| **CHAT** | Firestore group chat with report, block, delete-own, and terms (Guideline 1.2) |
| **ADMIN** | Super-user web admin (Hosting) for ops — not required for App Review path |
| **ASO** | Subtitle/keywords/description + pickems.app SEO landing; fastlane metadata |
| **RELEASE** | Marketing `2.3.0` / build `230` across app + extensions |

Watch app stays **not embedded** for this iPhone App Store build.

## App Review Information (paste into App Store Connect)

**Demo account (email/password):** create a dedicated reviewer account in Firebase Auth before submit, then fill:

```
Username: review@pickems.app   (or your seeded email)
Password: <set in Firebase>
```

**Notes for Review:**

> Pickems is a college football pick'em app for private leagues. Version 2.3.0 adds group chat and several UX fixes from TestFlight feedback.
>
> ### Guideline 1.2 — User-Generated Content (group chat)
> Chat messages are user-generated. We provide the required moderation controls:
> 1. **Report** — any member can report a message from the message context menu; reports are stored for review. Messages that accumulate reports are automatically soft-deleted.
> 2. **Block** — members can block another user; blocked users’ messages are filtered from their chat feed.
> 3. **Delete own** — authors can soft-delete their own messages; commissioners can remove messages.
> 4. **Terms of Use** — linked in-app (Profile and chat first-run notice). The notice states that reported messages are reviewed and accounts can be removed for abuse.
> Contact for content concerns: support via https://pickems.app (or the support URL in App Store Connect).
>
> ### How to review
> 1. Sign in with the demo account (or Sign in with Apple / Create Account). Apple Sign In is the primary button; email/password is optional under “Use email and password instead.”
> 2. Create a league or join with the invite code from Notes.
> 3. From Groups: open Group Picks, Build Slate / Make Picks, and Chat.
> 4. In Chat: send a message, open a message’s context menu to confirm Report / Block / Delete own.
> 5. Nominate a game — already-nominated games are greyed out. Spreads appear on browse, nominations, and picks.
> 6. Account deletion remains under Profile → Delete Account.
> 7. Sheets that present league flows forward AppState via `.pickemsEnvironment` (fix for the 1.0 crash).
>
> Privacy Policy: https://raw.githubusercontent.com/johnmfanning1-svg/Pickems/main/docs/privacy-policy.html
> Terms: https://raw.githubusercontent.com/johnmfanning1-svg/Pickems/main/docs/terms.html

**Invite code:** seed a stable public/private league and paste the 6-character code here before submit.

## Hosting legal pages

`AppConfig` currently points at raw GitHub URLs on `main` (HTTPS, publicly reachable). The marketing site at `web/` (pickems.app) links to the same Privacy/Terms URLs for now. A later pass can host branded `/privacy` and `/terms` on pickems.app and update `AppConfig`.

## Preflight checklist

- [ ] Seed App Review demo account + invite code in Connect notes
- [ ] Deploy Firestore indexes, then rules + storage, then functions (chat moderation paths)
- [ ] Confirm chat moderation: report, block, delete-own, terms notice
- [ ] Archive 2.3.0 (230) → TestFlight for PO acceptance, then App Store submit
- [ ] Confirm Sign in with Apple capability on the App ID
- [ ] Upload metadata via `fastlane metadata` (or paste from `fastlane/metadata/en-US/`)
- [ ] App Privacy questionnaire matches `PrivacyInfo.xcprivacy` / privacy policy
- [ ] Watch app remains not embedded
