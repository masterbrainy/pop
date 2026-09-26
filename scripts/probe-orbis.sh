#!/usr/bin/env bash
# Probe 0.3a: animates one picture with Orbis inside the app on the Duo simulator.
# Builds and installs the app, copies the still and prompt into its Documents,
# mints a 15-minute dev token, launches the probe, follows its log, takes
# screenshots once video plays, and finally checks that no session is left open.
#   scripts/probe-orbis.sh <still.png|jpg> ["motion prompt"] [seconds of video=30]
set -euo pipefail
source "$(dirname "$0")/lib-env.sh"

still="${1:?still image}"
prompt="${2:-}"
seconds="${3:-30}"
id="$(sim_device_id)"
shots="$POP_ROOT/build/shots"
mkdir -p "$shots"

"$POP_ROOT/scripts/sim.sh" build
xcrun simctl install "$id" "$POP_ROOT/build/DerivedData/Build/Products/Debug-iphonesimulator/Pop.app"
xcrun simctl terminate "$id" com.masterbrainy.pop >/dev/null 2>&1 || true

docs="$(app_documents)"
sips -s format jpeg -s formatOptions 85 "$still" --out "$docs/probe-still.jpg" >/dev/null
if [ -n "$prompt" ]; then printf '%s' "$prompt" > "$docs/probe-prompt.txt"; else rm -f "$docs/probe-prompt.txt"; fi
rm -f "$docs/probe-orbis.log"
"$POP_ROOT/scripts/dev-token.sh" 900 1

xcrun simctl launch "$id" com.masterbrainy.pop -probe orbis -autorun YES -probeSeconds "$seconds" >/dev/null
log="$docs/probe-orbis.log"
deadline=$(( $(date +%s) + 600 ))
shown=0 shot=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  if [ -f "$log" ]; then
    total=$(wc -l < "$log")
    if [ "$total" -gt "$shown" ]; then
      sed -n "$((shown + 1)),${total}p" "$log" | /usr/bin/grep -v ' stats ' || true
      shown=$total
    fi
    if [ "$shot" = 0 ] && /usr/bin/grep -q 'first frame' "$log"; then
      sleep 4
      xcrun simctl io "$id" screenshot --display=1 "$shots/orbis-live-1.png" >/dev/null && echo "screenshot: $shots/orbis-live-1.png"
      sleep 8
      xcrun simctl io "$id" screenshot --display=1 "$shots/orbis-live-2.png" >/dev/null && echo "screenshot: $shots/orbis-live-2.png"
      shot=1
    fi
    /usr/bin/grep -q -E 'disconnected$|FAILED disconnect' "$log" && break
  fi
  sleep 2
done

echo "--- stats (last 3)"; /usr/bin/grep ' stats ' "$log" | tail -3 || true
"$POP_ROOT/scripts/reactor-sessions.sh" list
