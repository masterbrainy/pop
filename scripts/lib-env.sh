#!/usr/bin/env bash
# Shared helpers for dev scripts that call paid APIs from this Mac.
# Keys are read from supabase/functions/.env into shell variables only: they never
# appear on a command line (curl gets them through a header file) and are never printed.

POP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POP_ENV_FILE="$POP_ROOT/supabase/functions/.env"

# env_value NAME: prints nothing; sets REPLY to the value of NAME from .env, or fails.
env_value() {
  local name="$1" line
  line="$(/usr/bin/grep -E "^${name}=" "$POP_ENV_FILE" | head -1 || true)"
  REPLY="${line#*=}"
  REPLY="${REPLY%\"}"; REPLY="${REPLY#\"}"; REPLY="${REPLY%$'\r'}"
  if [ -z "$REPLY" ]; then
    echo "$name: EMPTY" >&2
    return 1
  fi
}

# sim_device_id: the booted (or first available) iPhone Duo simulator.
sim_device_id() {
  xcrun simctl list devices available | /usr/bin/grep -F "${POP_SIM_DEVICE:-iPhone Duo} (" | head -1 \
    | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

# app_documents: the Pop! app's Documents folder in the simulator (the app must be installed).
app_documents() {
  local container
  container="$(xcrun simctl get_app_container "$(sim_device_id)" com.masterbrainy.pop data)"
  mkdir -p "$container/Documents"
  printf '%s/Documents' "$container"
}
