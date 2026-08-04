# Firestore rules unit tests — release gate G0

`@firebase/rules-unit-testing` + `vitest`, run against the Firestore emulator.

## Requirements

The Firestore emulator is a Java binary, so a JRE 11+ must be on `PATH`:

```bash
java -version            # must succeed
brew install --cask temurin   # if it does not
```

## Run

```bash
cd firebase/tests && npm install
cd firebase && firebase emulators:exec --only firestore "npm --prefix tests test"
```

`emulators:exec` starts the emulator, exports `FIRESTORE_EMULATOR_HOST`, runs the
suite, and exits with the suite's status — which is what CI should gate on.

Against an already-running emulator:

```bash
cd firebase && firebase emulators:start --only firestore   # terminal 1
cd firebase/tests && npm test                              # terminal 2
```

## Coverage

The suite loads `../firestore.rules` directly, so it tests the file that
deploys. `afterEach` clears the emulator, and each case reseeds its own fixtures.

- **Chat** — non-member read denied, member and super-admin allowed; spoofed
  `userId`, empty text, and 501 characters rejected while 500 is accepted;
  client-forged `reportCount`, `isDeleted: true` on create, and a backdated
  `createdAt` all rejected; author may edit `text`, a non-author may change only
  `reactions` and cannot smuggle `text` or `reportCount` alongside it;
  commissioner soft-delete and admin hard-delete; reports only under the
  reporter's own uid.
- **`appConfig` / `adminAudit`** — any signed-in client reads `appConfig`, only an
  admin writes it; `adminAudit` is admin-read, admin-create, and append-only
  (update and delete denied even for an admin).
- **Super-admin blast radius** — an admin can write a group they are not a member
  of and list all groups; a signed-in non-admin non-member can do neither. This
  is the assertion that makes folding `isSuperAdmin()` into `isCommissioner()`
  safe to ship (Risk R2).
- **Regressions** — a member's own pick is readable pre-deadline and another
  member's is not, while an admin can read both (the portal's pick grid depends
  on it); the commissioner week field allow-list still rejects `slateSize`;
  submissions stay member-writable and picks stay unforgeable.
