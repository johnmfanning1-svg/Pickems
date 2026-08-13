# Pickems ASO — App Store Optimization

**Release:** 3.0.2 (build 302)  
**Bundle:** `FannypackInc.Pickems` · **Apple ID:** `6785697079`  
**Locale:** en-US (primary)  
**Source of truth for Connect upload:** `fastlane/metadata/en-US/`

---

## Metadata (character counts)

| Field | Limit | Value | Count |
|--|--|--|--|
| Name | 30 | `CFB Pickems` | 11 |
| Subtitle | 30 | `College football pick'em` | 24 |
| Keywords | 100 | see below | 92 |
| Promotional text | 170 | see `fastlane/metadata/en-US/promotional_text.txt` | 129 |
| Description | 4000 | see `fastlane/metadata/en-US/description.txt` | ≤4000 |
| What's New | 4000 | see `fastlane/metadata/en-US/release_notes.txt` | ≤4000 |

**Keywords (exact string, no trailing comma):**

```
pickem,pick em,against the spread,ats,live scores,commissioner,bowl,fbs,ncaaf,league,playoff
```

92 / 100 characters. Do not repeat the app name (`CFB`, `Pickems`) or subtitle (`College football`, `pick'em`).

---

## Keyword rationale

| Term | Why |
|--|--|
| `pickem` / `pick em` | Primary category query; covers both spellings users type |
| Name + subtitle | Indexes `CFB`, `Pickems`, `college football`, `pick'em` |
| `against the spread` / `ats` | Differentiator vs straight win/loss pick'em apps |
| `live scores` | Scoreboard / Saturday intent from Home |
| `league` / `commissioner` | Private-league and organizer search |
| `bowl` / `playoff` | Postseason intent |
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

**Frame set (6 frames, same story on 6.9" and 6.5"):**

1. **Nominate the slate** — game browse with Top 25 / conference chips + spread on row  
2. **Pick against the spread** — picks screen with lines visible  
3. **Group standings** — weekly leaderboard / awards tease  
4. **Live Saturday** — live scores or Live Activity / widget  
5. **Your crew** — Groups hub (Build Slate / Group Picks / Chat)  
6. **Group chat** — chat thread (show report/block affordance in caption if space)

**Caption style:** short verb + outcome (“Nominate games. Build the slate.”). No keyword stuffing on overlays. Match app crimson accent (`#DC2626`) on dark background — same as in-app theme, not a purple marketing skin.

**Assets location (when captured):** keep under `fastlane/screenshots/en-US/` (not required for this scaffold commit).

---

## What changed this release (iterative ASO)

| Area | 2.3.0 change |
|--|--|
| Subtitle | Locked to `CFB pick'em with your crew` (26) — fits 30-char limit |
| Keywords | ATS / commissioner / bowl set at 90 chars |
| Description | Rewritten around nomination slate, ATS, standings, awards, widgets, chat |
| Promotional text | Seasonal / feature highlight (editable without a new binary) |
| What's New | Feedback-release notes covering AUTH → ASO workstreams |
| SEO | `web/` landing at pickems.app with OG, JSON-LD, sitemap, smart banner |
| Review risk | Chat moderation called out for Guideline 1.2 — see `docs/APP_STORE.md` |

**Next ASO pass ideas (post-2.3.0):** screenshot A/B on frame 1 (filters vs nomination), subtitle test (`ATS leagues for CFB` if chars allow after localization), add `en-GB` keyword set.

---

## Upload

```bash
# Metadata only (no binary)
bundle exec fastlane metadata

# TestFlight (when signing/certs ready)
bundle exec fastlane beta
```

See `fastlane/Fastfile` and `docs/APP_STORE.md`.
