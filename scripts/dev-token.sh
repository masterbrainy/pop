#!/usr/bin/env bash
# Mints a short-lived Reactor token on this Mac and drops it into the simulator
# app's Documents/dev-reactor-token for Phase 0 probes. The API key never enters
# the app; the token is never printed. The app deletes the file after reading it.
#   scripts/dev-token.sh [seconds=900] [max_sessions=1]
set -euo pipefail
source "$(dirname "$0")/lib-env.sh"

seconds="${1:-900}"
max_sessions="${2:-1}"
model="${REACTOR_MODEL:-reactor/visko-orbis-stable}"

env_value REACTOR_API_KEY
key="$REPLY"
body="$(printf '{"expires_after":%d,"authorization_details":[{"type":"session","resources":{"models":{"match":["%s"]}},"constraints":{"max_sessions":%d}}]}' \
  "$seconds" "$model" "$max_sessions")"

reply="$(mktemp)"
trap 'rm -f "$reply"' EXIT
status="$(curl -sS -o "$reply" -w '%{http_code}' -X POST "https://api.reactor.inc/tokens" \
  -H @<(printf 'Reactor-API-Key: %s\nContent-Type: application/json\n' "$key") \
  --data "$body" --max-time 30)"
echo "tokens: HTTP $status"
[ "$status" = "200" ] || { echo "token request failed" >&2; exit 1; }

out="$(app_documents)/dev-reactor-token"
python3 - "$reply" "$out" <<'PY'
import json, os, sys
jwt = json.load(open(sys.argv[1])).get("jwt", "")
if not jwt:
    sys.exit("reply had no jwt")
with open(sys.argv[2], "w") as f:
    f.write(jwt)
os.chmod(sys.argv[2], 0o600)
PY
echo "token written to the app's Documents (valid ${seconds}s, max_sessions ${max_sessions})"
