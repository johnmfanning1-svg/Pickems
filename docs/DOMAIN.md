# Pickems public URLs

**`pickems.app` is not ours.** Do not register it, point DNS at it, or publish it as a marketing, privacy, or App Store support URL. Use the free Firebase Hosting hostname until there are enough paying customers to justify a custom domain.

| Use | URL |
|--|--|
| App Store **Support URL** | `https://pickems-fb.web.app/support` |
| Support form (same page) | `https://pickems-fb.web.app/support` |
| Invite landing | `https://pickems-fb.web.app/join?code=` |
| Admin portal (not public marketing) | `https://pickems-fb.web.app/` |
| Privacy Policy (today) | `https://raw.githubusercontent.com/johnmfanning1-svg/Pickems/main/docs/privacy-policy.html` |
| Terms of Use (today) | `https://raw.githubusercontent.com/johnmfanning1-svg/Pickems/main/docs/terms.html` |

Firebase project: `pickems-fb`. Default Hosting site: `pickems-fb.web.app` / `pickems-fb.firebaseapp.com`.

`john@pickems.app` in admin-bootstrap examples is a Firebase Auth email, not proof we own the domain.

---

## Support page

Static HTML at `web/support.html`, copied into the Hosting bundle next to `/join` by `firebase/scripts/stage-hosting.sh`. Hosting rewrites `/support` → `/support.html` **before** the admin SPA catch-all (`**` → `/index.html`).

The form posts to [FormSubmit.co](https://formsubmit.co) (`https://formsubmit.co/johnmfanning1@gmail.com`). That is a free email-form backend: no paid SaaS, no Cloud Functions, no custom domain. Messages arrive in Gmail at `johnmfanning1@gmail.com`. The page also offers a `mailto:` fallback.

### One-time FormSubmit activation

FormSubmit does **not** deliver the first submission as a normal support email. It sends a confirmation to `johnmfanning1@gmail.com` (check spam). Click **Activate Form** / confirm the address once.

After that, every later submit from `/support` is forwarded to Gmail. No monthly fee on the free tier.

Do **not** write public contact mail into Firestore. An unauthenticated `supportMessages` create rule would be a spam/storage hole; skip it until there is an authenticated or Functions-backed path.

---

## What is in-repo vs App Store Connect

Already in this repo (source of truth for the next metadata upload):

- `fastlane/metadata/en-US/support_url.txt` → `https://pickems-fb.web.app/support`

Must be changed **manually in App Store Connect** (or by running `bundle exec fastlane metadata`) if the live listing still shows `pickems.app`:

1. [App Information](https://appstoreconnect.apple.com/apps/6785697079/distribution/info) → **Support URL** → `https://pickems-fb.web.app/support`
2. Leave **Marketing URL** empty unless we actually ship a public homepage we control (do not put `pickems.app` there).
3. Privacy URL can stay on the GitHub raw HTML until we host `docs/privacy-policy.html` on Firebase Hosting.

Connect work uses logged-in Chrome + iris — see [APP_STORE.md](APP_STORE.md). Cursor’s browser cannot complete Apple login.

Associated domains in `Pickems/Pickems.entitlements` still list `applinks:pickems.app` for historical Universal Links. That does **not** mean we own the domain. Do not configure DNS for it. Public support and ASO URLs stay on `pickems-fb.web.app`.

---

## Deploy Hosting

Documented path (from `firebase/`):

```bash
cd firebase
npx -y firebase-tools@latest deploy --only hosting --project pickems-fb
```

`firebase.json` `predeploy` runs `scripts/stage-hosting.sh`, which typechecks/builds the admin portal and copies `web/join.html`, `web/support.html`, AASA, `robots.txt`, and `sitemap.xml` into `admin/dist`.

Equivalent after a local admin build:

```bash
cd firebase/admin && npm ci && npm run build
cd .. && bash scripts/stage-hosting.sh
npx -y firebase-tools@latest deploy --only hosting --project pickems-fb
```

Preview channel (optional):

```bash
cd firebase
npx -y firebase-tools@latest hosting:channel:deploy support --project pickems-fb
```

Hosting deploy requires Firebase CLI login (`npx -y firebase-tools@latest login`) with access to `pickems-fb`.
