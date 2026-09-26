#!/usr/bin/env bash
# Admin janitor for the Reactor account (Brian's own, REVIEW R-23): lists open
# sessions, or kills them all. Uses the API key from .env through a header file;
# prints only session ids, states and HTTP statuses.
#   scripts/reactor-sessions.sh list
#   scripts/reactor-sessions.sh kill
set -euo pipefail
source "$(dirname "$0")/lib-env.sh"

env_value REACTOR_API_KEY
key="$REPLY"
api="https://api.reactor.inc"

get() {
  curl -sS --max-time 30 -H @<(printf 'Reactor-API-Key: %s\n' "$key") "$api$1"
}

open_sessions() {
  local account
  account="$(get /me | python3 -c 'import json,sys; print(json.load(sys.stdin).get("account_id",""))')"
  [ -n "$account" ] || { echo "/me returned no account_id" >&2; exit 1; }
  get "/accounts/$account/sessions" | python3 -c '
import json, sys
for s in json.load(sys.stdin).get("sessions", []):
    if not s.get("closed"):
        print(s.get("session_id", "?"), s.get("state", "?"), s.get("model", "?"))'
}

case "${1:-list}" in
  list)
    sessions="$(open_sessions)"
    echo "open sessions: $(printf '%s' "$sessions" | /usr/bin/grep -c . || true)"
    [ -z "$sessions" ] || printf '%s\n' "$sessions"
    ;;
  kill)
    open_sessions | while read -r id _; do
      status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 -X DELETE \
        -H @<(printf 'Reactor-API-Key: %s\n' "$key") "$api/sessions/$id")"
      echo "delete $id: HTTP $status"
    done
    ;;
  *) echo "usage: $0 list|kill" >&2; exit 2 ;;
esac
