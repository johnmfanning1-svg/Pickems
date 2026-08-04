#!/usr/bin/env node
/**
 * One-time bootstrap for the super-admin custom claim.
 *
 * There is no way to grant the first admin from inside the app — `setAdminRole`
 * requires an existing admin. This script closes that loop with a service
 * account, and is the only privileged path that runs off a developer machine.
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS=~/secrets/pickems-sa.json
 *   node firebase/admin-tools/set-admin.mjs john@pickems.app
 *   node firebase/admin-tools/set-admin.mjs john@pickems.app --revoke
 *
 * Never move the service-account JSON into this repo. See Risk R2.
 */
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

const args = process.argv.slice(2);
const revoke = args.includes("--revoke");
const email = args.find((arg) => !arg.startsWith("--"));

if (!email) {
  console.error("Usage: node firebase/admin-tools/set-admin.mjs <email> [--revoke]");
  process.exit(1);
}

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && !process.env.FIREBASE_CONFIG) {
  console.error(
    "GOOGLE_APPLICATION_CREDENTIALS is not set.\n" +
      "  export GOOGLE_APPLICATION_CREDENTIALS=~/secrets/pickems-sa.json"
  );
  process.exit(1);
}

initializeApp({ credential: applicationDefault() });

try {
  const auth = getAuth();
  const user = await auth.getUserByEmail(email);
  const existingClaims = user.customClaims ?? {};
  const wasAdmin = existingClaims.admin === true;

  await auth.setCustomUserClaims(user.uid, { ...existingClaims, admin: !revoke });

  console.log(`${revoke ? "Revoked" : "Granted"} admin claim`);
  console.log(`  email: ${user.email}`);
  console.log(`  uid:   ${user.uid}`);
  console.log(`  was:   admin=${wasAdmin}`);
  console.log(`  now:   admin=${!revoke}`);
  console.log("");
  console.log(
    "Custom claims live in the ID token, so this is not visible yet. The user must\n" +
      "sign out and back in, or the client must call getIdToken(true) / getIdTokenResult(true).\n" +
      "A revoke can take up to an hour to propagate to an already-issued token."
  );
} catch (error) {
  if (error?.code === "auth/user-not-found") {
    console.error(`No Firebase Auth user with email ${email}. Have them sign in once first.`);
  } else {
    console.error(error?.message ?? error);
  }
  process.exit(1);
}
