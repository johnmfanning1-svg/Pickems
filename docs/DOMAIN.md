# Domain ownership — read this before touching hostnames

**Last verified:** 15 September 2026

`pickems.app` is **not** a Fannypack / Pickems (this iOS app) domain. Do not treat it as ours in App Store metadata, associated domains, marketing HTML, DNS, or Cloudflare.

This repo started **26 June 2026**. The hostname was copied into entitlements and later into ASO copy as if we owned it. We never registered it, never received Namecheap or Cloudflare zone mail for it, and every Cloudflare login under `johnmfanning1@gmail.com` (Google, GitHub, Apple, and email/password after a reset) shows **no websites**.

---

## What we actually own

| Property | Owner / host | Notes |
|--|--|--|
| iOS app | Apple Team `22A943P8SJ` (Fannypack Inc.) | Bundle `FannypackInc.Pickems` |
| Backend | Firebase project `pickems-fb` | Auth, Firestore, Functions, Storage, FCM |
| Admin portal + AASA + `/join` | Firebase Hosting | `https://pickems-fb.web.app` and `https://pickems-fb.firebaseapp.com` |
| Privacy / terms | This GitHub repo | `docs/privacy-policy.html`, `docs/terms.html` (App Store privacy URL is the raw GitHub file) |
| Cloudflare account for `johnmfanning1@gmail.com` | Us, and **empty** | Email/password user. No zones, Workers, or Pages. Apple Sign In created a *second* empty user via Hide My Email. |

There is **no** production marketing hostname we control today besides the Firebase `*.web.app` defaults.

---

## What `pickems.app` actually is

| Fact | Detail |
|--|--|
| Registrar | Namecheap (IANA 1068), privacy WHOIS |
| Registered | **18 October 2024** (~20 months before this repo) |
| DNS | Cloudflare nameservers `adrian.ns.cloudflare.com` / `stan.ns.cloudflare.com` |
| Live origin | Laravel + Inertia + Discord OAuth, multi-tenant `{organisation}.pickems.app` |
| Product name on that site | “Pick'ems” (Discord application id `1297182629640142899`) |
| Our AASA / `/join` on that host | **404** — not this repo’s `web/` files |

That Cloudflare **zone** belongs to whatever account added the site in 2024. It is not the empty `johnmfanning1@gmail.com` Cloudflare user. Do not add `pickems.app` to our empty Cloudflare account while those nameservers already point at the other zone (pending/conflict, will not take over the site).

---

## How the mistake got into this repo

| Date | What happened |
|--|--|
| 18 Oct 2024 | Someone else registered `pickems.app` at Namecheap |
| 26 Jun 2026 | This repo’s first commit |
| 29 Jun 2026 | `applinks:pickems.app` added to `Pickems/Pickems.entitlements` |
| 29 Jul 2026 | App Store support URL, `web/` canonical URLs, and ASO copy assumed `https://pickems.app` |
| 18 Aug 2026 | Google/GitHub OAuth attempted against Cloudflare Dashboard; Cloudflare rejected social login because the Gmail user already existed as email/password |
| 15 Sep 2026 | Password reset on that Gmail Cloudflare user: dashboard still empty. Confirmed the zone is not on our account |

A hostname in entitlements or `support_url.txt` is not proof of ownership.

---

## Hard rules for this repo

1. **Do not** put a hostname in App Store support URL, associated domains, AASA, `web/` canonical/sitemap, or Universal Link parsers until we can log into the **registrar** and the **DNS host** for that exact name.
2. **Do not** point Cloudflare, Vercel, or Firebase Hosting at `pickems.app`.
3. **Do not** use `@pickems.app` as a real mailbox example for admin grants. Use an address we actually control (today: `johnmfanning1@gmail.com`). `review.pickems.appstore@gmail.com` is a Gmail address, not `@pickems.app`.
4. Before claiming a new domain, record in this file: registrar account email, registration date, nameservers, and which dashboard the zone appears in.
5. Firebase `*.web.app` / `*.firebaseapp.com` are the only Universal Link hosts we have verified we serve.

When we buy a domain we control, update this file first, then entitlements, AASA, `web/`, App Store support URL, and `DeepLinkRouter` together.

---

## Files that still mention `pickems.app` (stale assumptions)

These still say or imply the hostname is ours. Leave them until we have a replacement domain; do not “fix” them by pointing DNS at a name we do not own.

- `fastlane/metadata/en-US/support_url.txt` — App Store support URL (currently someone else’s site)
- `Pickems/Pickems.entitlements` — `applinks:pickems.app` (AASA on that host 404s; links do not open this app)
- `Pickems/Core/Utilities/DeepLinkRouter.swift`
- `web/index.html`, `web/robots.txt`, `web/sitemap.xml`
- `docs/ASO.md`, `docs/WEB_ARCHITECTURE_ASSESSMENT.md`, `docs/RELEASE_2_3_0_PLAN.md`

---

## Related docs

- Admin portal URL: [ADMIN_PORTAL_SOP.md](ADMIN_PORTAL_SOP.md)
- App Store submit: [APP_STORE.md](APP_STORE.md)
- Web architecture (Firebase-first; ignore any `pickems.app` DNS plan): [WEB_ARCHITECTURE_ASSESSMENT.md](WEB_ARCHITECTURE_ASSESSMENT.md)
