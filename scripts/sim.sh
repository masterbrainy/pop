#!/usr/bin/env bash
# Build Pop!, install it on the booted iPhone Duo simulator, and launch it.
#   scripts/sim.sh build            generate the project and build for the simulator
#   scripts/sim.sh run [args...]    build, install and launch (args go to the app, e.g. -probe hinge)
#   scripts/sim.sh shot <name>      screenshot both screens into build/shots/<name>-{outer,inner}.png
#   scripts/sim.sh log [seconds]    show the app's recent log lines
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="com.masterbrainy.pop"
DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Pop.app"
DEVICE="${POP_SIM_DEVICE:-iPhone Duo}"

device_id() {
  xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

build() {
  (cd "$ROOT" && xcodegen generate --quiet)
  xcodebuild -project "$ROOT/Pop.xcodeproj" -scheme Pop -configuration Debug \
    -destination "platform=iOS Simulator,id=$(device_id)" \
    -derivedDataPath "$DERIVED" build -quiet
}

run() {
  build
  local id; id="$(device_id)"
  xcrun simctl install "$id" "$APP"
  xcrun simctl terminate "$id" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$id" "$BUNDLE_ID" "$@"
}

shot() {
  local name="${1:?name}" id; id="$(device_id)"
  mkdir -p "$ROOT/build/shots"
  xcrun simctl io "$id" screenshot --display=1 "$ROOT/build/shots/$name-outer.png" >/dev/null
  xcrun simctl io "$id" screenshot --display=3 "$ROOT/build/shots/$name-inner.png" >/dev/null
  echo "$ROOT/build/shots/$name-outer.png"
  echo "$ROOT/build/shots/$name-inner.png"
}

log_recent() {
  local seconds="${1:-60}"
  xcrun simctl spawn "$(device_id)" log show --last "${seconds}s" --style compact \
    --predicate 'subsystem == "com.masterbrainy.pop"' | grep -v '^Timestamp' || true
}

case "${1:-}" in
  build) build ;;
  run) shift; run "$@" ;;
  shot) shift; shot "$@" ;;
  log) shift; log_recent "$@" ;;
  *) echo "usage: $0 build|run [args]|shot <name>|log [seconds]" >&2; exit 2 ;;
esac
