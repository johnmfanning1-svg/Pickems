#!/usr/bin/env bash
set -euo pipefail

# Deploy Firestore rules + Cloud Functions for Pickems.
# Auth options (first match wins):
#   1) FIREBASE_TOKEN env (from `firebase login:ci`)
#   2) GOOGLE_APPLICATION_CREDENTIALS service-account JSON
#   3) Existing `firebase login` session

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/firebase"

echo "Building functions…"
npm install --prefix functions
npm run build --prefix functions

ARGS=(deploy --only firestore:rules,functions --non-interactive --project pickems-fb)

if [[ -n "${FIREBASE_TOKEN:-}" ]]; then
  echo "Deploying with FIREBASE_TOKEN…"
  npx -y firebase-tools@latest "${ARGS[@]}" --token "$FIREBASE_TOKEN"
elif [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  echo "Deploying with GOOGLE_APPLICATION_CREDENTIALS…"
  npx -y firebase-tools@latest "${ARGS[@]}"
else
  echo "Deploying with local Firebase login session…"
  npx -y firebase-tools@latest "${ARGS[@]}"
fi

echo "Deploy complete."
