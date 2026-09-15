#!/bin/bash
# Build the admin portal under /admin/ and copy public static files into dist/.
set -euo pipefail
cd "$(dirname "$0")/../admin"
./node_modules/.bin/tsc --noEmit
./node_modules/.bin/vite build
mkdir -p dist
# Drop leftover root-level SPA files from when admin owned public /.
find dist -maxdepth 1 -type f \( -name '*.js' -o -name '*.css' -o -name '*.map' \) -delete
rm -rf dist/assets
touch dist/.gitkeep
mkdir -p dist/.well-known dist/assets
# Marketing homepage owns public /. Vite emits the SPA at dist/admin/.
cp ../../web/index.html dist/index.html
cp ../../web/join.html dist/join.html
cp ../../web/support.html dist/support.html
cp ../../web/robots.txt dist/robots.txt
cp ../../web/sitemap.xml dist/sitemap.xml
cp ../../web/.well-known/apple-app-site-association dist/.well-known/apple-app-site-association
cp ../../web/apple-app-site-association dist/apple-app-site-association
cp ../../web/assets/logo.png dist/assets/logo.png
cp ../../web/assets/home.jpg dist/assets/home.jpg
cp ../../web/assets/select-games.jpg dist/assets/select-games.jpg
cp ../../web/assets/spread-pickems.jpg dist/assets/spread-pickems.jpg
cp ../../web/assets/leagues.jpg dist/assets/leagues.jpg
cp ../../web/assets/signin.jpg dist/assets/signin.jpg
