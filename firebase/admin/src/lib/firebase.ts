import { initializeApp, type FirebaseOptions } from "firebase/app";
import { connectAuthEmulator, getAuth } from "firebase/auth";
import { connectFirestoreEmulator, getFirestore } from "firebase/firestore";
import { connectFunctionsEmulator, getFunctions } from "firebase/functions";

/**
 * Firebase wiring for the admin portal.
 *
 * Every value comes from Vite env vars so the bundle carries no project config
 * in git. The placeholders below exist purely so `npm run build` and a bare
 * `npm run dev` succeed without a `.env.local` — a placeholder build renders the
 * misconfiguration banner instead of throwing on module evaluation.
 *
 * These values are not secrets: Hosting serves this bundle publicly and anyone
 * can read them. Firestore rules (`isSuperAdmin()`) are the security boundary.
 */

const PLACEHOLDER = "__unset__";

function env(key: keyof ImportMetaEnv, fallback: string): string {
  const value = import.meta.env[key];
  return value != null && value !== "" ? value : fallback;
}

const firebaseConfig: FirebaseOptions = {
  apiKey: env("VITE_FIREBASE_API_KEY", PLACEHOLDER),
  authDomain: env("VITE_FIREBASE_AUTH_DOMAIN", "pickems-fb.firebaseapp.com"),
  projectId: env("VITE_FIREBASE_PROJECT_ID", "pickems-fb"),
  storageBucket: env("VITE_FIREBASE_STORAGE_BUCKET", "pickems-fb.firebasestorage.app"),
  messagingSenderId: env("VITE_FIREBASE_MESSAGING_SENDER_ID", PLACEHOLDER),
  appId: env("VITE_FIREBASE_APP_ID", PLACEHOLDER),
};

/** Which env vars are still placeholders — surfaced on the login screen. */
export const missingFirebaseConfigKeys: string[] = (
  [
    ["VITE_FIREBASE_API_KEY", firebaseConfig.apiKey],
    ["VITE_FIREBASE_MESSAGING_SENDER_ID", firebaseConfig.messagingSenderId],
    ["VITE_FIREBASE_APP_ID", firebaseConfig.appId],
  ] as const
)
  .filter(([, value]) => value === PLACEHOLDER)
  .map(([key]) => key);

export const isFirebaseConfigured = missingFirebaseConfigKeys.length === 0;

export const useEmulators = import.meta.env.VITE_USE_EMULATORS === "true";

/** v2 `onCall` deploys to us-central1 unless a region is declared. */
export const functionsRegion = env("VITE_FUNCTIONS_REGION", "us-central1");

export const environmentLabel = env(
  "VITE_ENVIRONMENT_LABEL",
  useEmulators ? "emulator" : "production",
);

export const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
export const functions = getFunctions(app, functionsRegion);

if (useEmulators) {
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  connectFirestoreEmulator(db, "127.0.0.1", 8080);
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
}
