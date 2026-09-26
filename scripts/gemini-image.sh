#!/usr/bin/env bash
# Generates one picture with Gemini from this Mac (dev and probe use only; the app
# goes through the `art` Edge Function). Prints the HTTP status, size and time.
#   scripts/gemini-image.sh "<prompt>" <out.png> [aspect=16:9] [model=gemini-2.5-flash-image]
set -euo pipefail
source "$(dirname "$0")/lib-env.sh"

prompt="${1:?prompt}"
out="${2:?output path}"
aspect="${3:-16:9}"
model="${4:-gemini-2.5-flash-image}"

env_value GEMINI_API_KEY
key="$REPLY"

request="$(mktemp)"; reply="$(mktemp)"
trap 'rm -f "$request" "$reply"' EXIT
python3 - "$prompt" "$aspect" > "$request" <<'PY'
import json, sys
print(json.dumps({
    "contents": [{"parts": [{"text": sys.argv[1]}]}],
    "generationConfig": {"responseModalities": ["IMAGE"], "imageConfig": {"aspectRatio": sys.argv[2]}},
}))
PY

started=$(date +%s)
status="$(curl -sS -o "$reply" -w '%{http_code}' --max-time 120 -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent" \
  -H @<(printf 'x-goog-api-key: %s\nContent-Type: application/json\n' "$key") \
  --data-binary @"$request")"
echo "gemini ${model}: HTTP $status in $(( $(date +%s) - started ))s"
[ "$status" = "200" ] || { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("error",{}).get("message","")[:300])' "$reply" >&2; exit 1; }

python3 - "$reply" "$out" <<'PY'
import base64, json, sys
reply = json.load(open(sys.argv[1]))
for part in reply.get("candidates", [{}])[0].get("content", {}).get("parts", []):
    data = part.get("inlineData", {}).get("data")
    if data:
        open(sys.argv[2], "wb").write(base64.b64decode(data))
        break
else:
    sys.exit("no image in the reply: " + json.dumps(reply)[:300])
PY
sips -g pixelWidth -g pixelHeight "$out" | tail -2 | tr -s ' ' | tr '\n' ' '; echo
