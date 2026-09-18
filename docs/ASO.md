# Pickems ASO — App Store Optimization

**Release:** 3.5.6 (build 3506)  
**Bundle:** `FannypackInc.Pickems` · **Apple ID:** `6785697079`  
**Locale:** en-US (primary)  
**Source of truth for Connect upload:** `fastlane/metadata/en-US/`

---

## Metadata (character counts)

| Field | Limit | Value | Count |
|--|--|--|--|
| Name | 30 | `CFB Pickems` | 11 |
| Subtitle | 30 | `No gambling. CFB pick'em` | 24 |
| Keywords | 100 | see below | 96 |
| Promotional text | 170 | see `fastlane/metadata/en-US/promotional_text.txt` | 143 |
| Description | 4000 | see `fastlane/metadata/en-US/description.txt` | ≤4000 |
| What's New | 4000 | see `fastlane/metadata/en-US/release_notes.txt` | ≤4000 |

**Keywords (exact string, no trailing comma):**

```
pickem,pick em,against the spread,ats,straight up,live scores,commissioner,bowl,fbs,ncaaf,league
```

96 / 100 characters. Do not repeat the app name (`CFB`, `Pickems`) or subtitle (`No gambling`, `pick'em`).

---

## Keyword rationale

| Term | Why |
|--|--|
| `pickem` / `pick em` | Primary category query; covers both spellings users type |
| Name + subtitle | Indexes `CFB`, `Pickems`, `No gambling`, `pick'em` |
| `against the spread` / `ats` / `straight up` | Leagues are ATS or Straight Up |
| `live scores` | Scoreboard / Saturday intent from Home |
| `league` / `commissioner` | Private-league and organizer search |
| `bowl` | Postseason intent |
| `fbs` / `ncaaf` | Sport abbreviations people type instead of CFB |

**Lead description paragraph** stays under 170 characters so the store preview ends on a full sentence.

---

## Screenshot plan

Apple requires device-class screenshots for review. Prioritize:

| Priority | Size | Devices covered |
|--|--|--|
| Required | **6.9"** (1320×2868) | iPhone 16 Pro Max / 15 Pro Max class |
| Required | **6.5"** (1284×2778) | iPhone 11 Pro Max / 14 Plus class |
| Optional | 6.7" / iPad 13" | defer unless Connect warns |

**Frame set (6 frames, same story on 6.7"/6.9" and 6.5"):**

1. **Pick against the spread** — Pickems tab with live lines (`01-pickems-ats.png`)
2. **Nominate the slate** — Select Games, Top 25 / conference chips (`02-select-games.png`)
3. **Selections** — week chips, submit, real CFB slate (`03-selections.png`)
4. **League board** — everyoneʼs picks, covering / won / lost (`04-league-board.png`)
5. **Your league** — hub, leaderboard, invite (`05-leagues.png`)
6. **Saturday home** — news + this weekʼs matchups (`06-home.png`)

Connect stores the 1320×2868 set on `APP_IPHONE_67` (iris has no `APP_IPHONE_69` enum yet). 6.5" is the same six frames at 1284×2778. iPad 13" is unchanged. Skipped login, onboarding, and Scrimmage.

**Caption style:** short verb + outcome (“Nominate games. Build the slate.”). No keyword stuffing on overlays. Match app crimson accent (`#DC2626`) on dark background — same as in-app theme, not a purple marketing skin.

**Assets location (when captured):** keep under `fastlane/screenshots/en-US/` (not required for this scaffold commit).

---

## What changed this release (iterative ASO)

| Area | 3.5.5 change |
|--|--|
| Subtitle | `No gambling. CFB pick'em` |
| Description | Lead once with ad-free and No gambling, then ATS vs Straight Up |
| Promotional text | Same lead: ad-free, No gambling, then Against the Spread or Straight Up |
| Keywords | Added `straight up`; dropped `playoff` to stay at 96 / 100 |
| What's New | Switch ATS ↔ Straight Up while Selections are open; 0–0 new leagues; save remaining Selections; rank ties |

---

## Upload

```bash
# Metadata only (no binary)
bundle exec fastlane metadata

# TestFlight (when signing/certs ready)
bundle exec fastlane beta
```

See `fastlane/Fastfile` and `docs/APP_STORE.md`.
