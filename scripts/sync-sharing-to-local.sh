#!/usr/bin/env bash
set -euo pipefail

# Copies the Sharing and SmackTalk features into an existing local Pickems Xcode project.
# Usage: ./scripts/sync-sharing-to-local.sh /path/to/your/Pickems

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/your/Pickems"
  exit 1
fi

DEST_ROOT="$1"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Syncing sharing module from $REPO_ROOT"
echo "Into local project at $DEST_ROOT"

mkdir -p "$DEST_ROOT/Pickems/Features"
rsync -av --delete \
  "$REPO_ROOT/Pickems/Features/Sharing/" \
  "$DEST_ROOT/Pickems/Features/Sharing/"

rsync -av --delete \
  "$REPO_ROOT/Pickems/Features/SmackTalk/" \
  "$DEST_ROOT/Pickems/Features/SmackTalk/"

mkdir -p "$DEST_ROOT/Pickems/App"
rsync -av \
  "$REPO_ROOT/Pickems/App/SharingBootstrap.swift" \
  "$DEST_ROOT/Pickems/App/" 2>/dev/null || true

rsync -av \
  "$REPO_ROOT/Pickems/Resources/InfoPlist-additions.xml" \
  "$DEST_ROOT/Pickems/Resources/" 2>/dev/null || mkdir -p "$DEST_ROOT/Pickems/Resources" && rsync -av "$REPO_ROOT/Pickems/Resources/InfoPlist-additions.xml" "$DEST_ROOT/Pickems/Resources/"

echo ""
echo "Next steps in Xcode:"
echo "1. Add Pickems/Features/Sharing and Pickems/Features/SmackTalk to your app target"
echo "2. Merge InfoPlist-additions.xml into your Info.plist"
echo "3. Wrap your app root with SmackTalkBootstrap { SharingBootstrap { YourRootView() } }"
echo "4. Add ShareResultsButton, SmackTalkButton, and ShareAppButton to standings/settings"
echo "5. Set AppConfig.xClientID and your Development Team"
