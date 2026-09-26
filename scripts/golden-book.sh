#!/usr/bin/env bash
# The demo's golden book: a finished book (text, pictures, clips, pop-up layers, cover) kept on
# this Mac and put back on the iPhone Duo simulator before a demo, so the network-failure
# fallback is always there (ROADMAP Phase 9, §9 run-book). Books stay out of git (video).
#   scripts/golden-book.sh save [book-id]   copy a saved book (default: newest) to build/golden/
#   scripts/golden-book.sh restore          copy build/golden/ back into the app on the simulator
#   scripts/golden-book.sh show             list the books on the simulator and the golden copy
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="com.masterbrainy.pop"
DEVICE="${POP_SIM_DEVICE:-iPhone Duo}"
GOLDEN="$ROOT/build/golden"

device_id() {
  xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

books_dir() {
  local data
  data="$(xcrun simctl get_app_container "$(device_id)" "$BUNDLE_ID" data)"
  echo "$data/Library/Application Support/books"
}

title_of() {
  python3 -c 'import json,sys; b=json.load(open(sys.argv[1])); print(b.get("title") or "(untitled)", "·", b.get("status"), "·", len(b.get("pages",[])), "pages")' "$1/book.json"
}

save() {
  local books id
  books="$(books_dir)"
  id="${1:-$(ls -t "$books" | head -1)}"
  [ -f "$books/$id/book.json" ] || { echo "no saved book $id" >&2; exit 1; }
  rm -rf "$GOLDEN"
  mkdir -p "$GOLDEN"
  cp -R "$books/$id" "$GOLDEN/"
  echo "golden book saved: $id · $(title_of "$GOLDEN/$id") · $(du -sh "$GOLDEN/$id" | cut -f1)"
}

restore() {
  local books id
  id="$(ls "$GOLDEN" 2>/dev/null | head -1)"
  [ -n "$id" ] || { echo "no golden book in build/golden; run: $0 save" >&2; exit 1; }
  books="$(books_dir)"
  mkdir -p "$books"
  rm -rf "${books:?}/$id"
  cp -R "$GOLDEN/$id" "$books/"
  echo "golden book restored: $id · $(title_of "$books/$id")"
}

show() {
  local books
  books="$(books_dir)"
  echo "on the simulator:"
  for dir in "$books"/*/; do echo "  $(basename "$dir") · $(title_of "$dir")"; done
  echo "golden copy:"
  for dir in "$GOLDEN"/*/; do [ -d "$dir" ] && echo "  $(basename "$dir") · $(title_of "$dir")"; done
}

case "${1:-}" in
  save) shift; save "$@" ;;
  restore) restore ;;
  show) show ;;
  *) echo "usage: $0 save [book-id] | restore | show" >&2; exit 2 ;;
esac
