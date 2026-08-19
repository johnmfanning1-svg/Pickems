#!/bin/bash
# Build the admin portal and copy Universal Link files into dist/.
set -euo pipefail
cd "$(dirname "$0")/../admin"
./node_modules/.bin/tsc --noEmit
./node_modules/.bin/vite build
touch dist/.gitkeep
mkdir -p dist/.well-known
cp ../../web/.well-known/apple-app-site-association dist/.well-known/apple-app-site-association
cp ../../web/apple-app-site-association dist/apple-app-site-association
cp ../../web/join.html dist/join.html
