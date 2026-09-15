# Pickems public URLs

**`pickems.app` is not ours.** Do not register it, point DNS at it, or publish it as a marketing, privacy, or App Store support URL. Use the free Firebase Hosting hostname until there are enough paying customers to justify a custom domain.

| Use | URL |
|--|--|
| App Store **Support URL** | `https://pickems-fb.web.app/support` |
| Support form (same page) | `https://pickems-fb.web.app/support` |
| Invite landing | `https://pickems-fb.web.app/join?code=` |
| Admin portal (not public marketing) | `https://pickems-fb.web.app/` |
| Admin support inbox (signed-in admins) | `https://pickems-fb.web.app/support-inbox` |
| Privacy Policy (today) | `https://raw.githubusercontent.com/johnmfanning1-svg/Pickems/main/docs/privacy-policy.html` |
| Terms of Use (today) | `https://raw.githubusercontent.com/johnmfanning1-svg/Pickems/main/docs/terms.html` |

Firebase project: `pickems-fb`. Default Hosting site: `pickems-fb.web.app` / `pickems-fb.firebaseapp.com`.

`john@pickems.app` in admin-bootstrap examples is a Firebase Auth email, not proof we own the domain.

---

## Support page

Static HTML at `web/support.html`, copied into the Hosting bundle next to `/join` by `firebase/scripts/stage-hosting.sh`. Hosting rewrites `/support` → `/support.html` **before** the admin SPA catch-all (`**` → `/index.html`).

**Do not put a personal mailbox, `mailto:`, or FormSubmit `/you@gmail.com` URL on this page.** The form POSTs to `/api/support`, which Hosting rewrites to the `submitSupport` Cloud Function. That function:

1. Validates the payload (honeypot, email, length, rate limit)
2. Writes `supportMessages/{id}` with the Admin SDK (no public create rule)
3. Forwards a copy by email if an inbox is configured **server-side**

The recipient is never shipped in HTML, git, or `appConfig/live` (that document is readable by every signed-in member). Configure it in one of these private places:

| Where | How |
|--|--|
| Admin portal | `/support-inbox` → **Forward copies to** (writes `adminConfig/support.inboxEmail`, admin-claim only) |
| Functions env | `SUPPORT_INBOX_EMAIL` in `firebase/functions/.env.pickems-fb` or Cloud Console (see `firebase/functions/.env.example`) |
| Web3Forms key | `SUPPORT_WEB3FORMS_ACCESS_KEY` — preferred mail path when set; the key is not an email address |

Env vars win over the Firestore inbox field. Web3Forms wins over FormSubmit. If no mail backend is configured, the form still succeeds: the row is in **Support inbox** in the portal.

Do **not** add an unauthenticated `supportMessages` create rule. That would be a spam/storage hole. Clients may read/delete only with `admin: true`; only `submitSupport` creates rows.

First FormSubmit delivery from a new inbox may send an activation mail to that inbox. Web3Forms does not need that step once the access key exists.

---

## What is in-repo vs App Store Connect

Already in this repo (source of truth for the next metadata upload):

- `fastlane/metadata/en-US/support_url.txt` → `https://pickems-fb.web.app/support`

Must be changed **manually in App Store Connect** (or by running `bundle exec fastlane metadata`) if the live listing still shows `pickems.app`:

1. [App Information](https://appstoreconnect.apple.com/apps/6785697079/distribution/info) → **Support URL** → `https://pickems-fb.web.app/support`
2. Leave **Marketing URL** empty unless we actually ship a public homepage we control (do not put `pickems.app` there).
3. Privacy URL can stay on the GitHub raw HTML until we host `docs/privacy-policy.html` on Firebase Hosting. That policy must link to `/support`, not a personal mailbox.

Connect work uses logged-in Chrome + iris — see [APP_STORE.md](APP_STORE.md). Cursor’s browser cannot complete Apple login.

Associated domains in `Pickems/Pickems.entitlements` still list `applinks:pickems.app` for historical Universal Links. That does **not** mean we own the domain. Do not configure DNS for it. Public support and ASO URLs stay on `pickems-fb.web.app`.

---

## Deploy Hosting + the support function

Documented path (from `firebase/`):

```bash
cd firebase
npx -y firebase-tools@latest deploy --only functions:submitSupport,hosting --project pickems-fb
```

`firebase.json` `predeploy` runs `scripts/stage-hosting.sh`, which typechecks/builds the admin portal and copies `web/join.html`, `web/support.html`, AASA, `robots.txt`, and `sitemap.xml` into `admin/dist`.

A full functions deploy (`deploy --only functions`) also ships `submitSupport`. Its env params default to empty strings, so missing inbox config does **not** block scoring-function deploys.

Equivalent after a local admin build:

```bash
cd firebase/admin && npm ci && npm run build
cd .. && bash scripts/stage-hosting.sh
npx -y firebase-tools@latest deploy --only functions:submitSupport,hosting --project pickems-fb
```

Preview channel (optional):

```bash
cd firebase
npx -y firebase-tools@latest hosting:channel:deploy support --project pickems-fb
```

Hosting deploy requires Firebase CLI login (`npx -y firebase-tools@latest login`) with access to `pickems-fb`.
