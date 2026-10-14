#!/usr/bin/env bash
# Runs the PickemsTests unit tests on an iPhone simulator. Used by the iOS
# tests PR workflow and as a gate in testflight.yml before archive/upload.
set -euo pipefail
PROJECT="${PROJECT:-Pickems.xcodeproj}"
SCHEME="${SCHEME:-Pickems}"
OUT="${RUNNER_TEMP:-/tmp}"
mkdir -p "$OUT/logs"
udid=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
best=None
for rt,devs in d.items():
    if "iOS" not in rt: continue
    v=tuple(int(x) for x in rt.rsplit("iOS-",1)[-1].split("-") if x.isdigit())
    for dev in devs:
        if dev["name"].startswith("iPhone") and (best is None or v>best[0]):
            best=(v,dev["udid"],dev["name"],rt)
if not best: sys.exit("no iPhone simulator")
print(best[1]); print(best[2],best[3],file=sys.stderr)')
echo "Using simulator $udid"
rm -rf "$OUT/TestResults.xcresult"
set +e
xcodebuild test \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination "id=$udid" \
  -only-testing:PickemsTests \
  -derivedDataPath "$OUT/TestDerivedData" \
  -resultBundlePath "$OUT/TestResults.xcresult" \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  > "$OUT/logs/test.log" 2>&1
rc=$?
set -e
grep -E "error:|Test Case .* (passed|failed)|Executed [0-9]+ test|\*\* TEST" "$OUT/logs/test.log" | grep -v "^$" | tail -n 2000 || true
if [ $rc -ne 0 ]; then
  echo "::error::xcodebuild test failed (exit $rc). Last 150 log lines:"
  tail -n 150 "$OUT/logs/test.log"
fi
exit $rc
