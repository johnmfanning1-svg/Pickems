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
# Counts come from the .xcresult bundle (Swift Testing and XCTest alike),
# not from grepping test.log.
MIN_EXPECTED_TESTS="${MIN_EXPECTED_TESTS:-420}"
grep -iE "error:|Test case .* failed|\*\* TEST" "$OUT/logs/test.log" | tail -n 200 || true
summary="$OUT/logs/test-summary.json"
if ! xcrun xcresulttool get test-results summary --path "$OUT/TestResults.xcresult" --format json > "$summary" 2>"$OUT/logs/xcresulttool.err"; then
  echo "::error::Could not read test summary from TestResults.xcresult:"
  cat "$OUT/logs/xcresulttool.err" || true
  [ $rc -ne 0 ] || rc=1
else
  read -r total passed failed skipped expected_failures < <(python3 - "$summary" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("totalTestCount", 0), d.get("passedTests", 0), d.get("failedTests", 0),
      d.get("skippedTests", 0), d.get("expectedFailures", 0))
PY
)
  line="${total} total, ${passed} passed, ${failed} failed, ${skipped} skipped, ${expected_failures} expected failures"
  echo "Test results: ${line}"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "- iOS unit tests: ${line} (minimum expected ${MIN_EXPECTED_TESTS})" >> "$GITHUB_STEP_SUMMARY"
  fi
  if [ "${failed}" != "0" ]; then
    echo "Failed tests:"
    python3 - "$summary" <<'PY' || true
import json, sys
for f in json.load(open(sys.argv[1])).get("testFailures", []):
    print(f"  {f.get('testIdentifierString') or f.get('testName')}: {f.get('failureText', '')}")
PY
  fi
  if [ "${total}" -lt "${MIN_EXPECTED_TESTS}" ]; then
    echo "::error::Only ${total} tests ran; expected at least ${MIN_EXPECTED_TESTS}. Tests may have been skipped or dropped from the target."
    [ $rc -ne 0 ] || rc=1
  fi
fi
if [ $rc -ne 0 ]; then
  echo "::error::xcodebuild test failed (exit $rc). Last 150 log lines:"
  tail -n 150 "$OUT/logs/test.log"
fi
exit $rc
