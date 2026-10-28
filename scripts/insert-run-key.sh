#!/bin/bash
# Insert a game's run check key into a creator's zip before uploading it.
# Usage:  scripts/insert-run-key.sh path/to/game.zip            (key read from the clipboard)
#         scripts/insert-run-key.sh path/to/game.zip <key>      (key given directly)
# Writes  path/to/game-keyed.zip next to the original. The original zip is never changed.
set -u
ZIP="${1:-}"
if [ -z "$ZIP" ] || [ ! -f "$ZIP" ]; then echo "STOP: give the creator's zip, e.g.  scripts/insert-run-key.sh ~/Desktop/game.zip"; exit 1; fi
KEY="${2:-$(pbpaste 2>/dev/null)}"
KEY="$(printf '%s' "$KEY" | tr -d '[:space:]')"
if ! printf '%s' "$KEY" | grep -Eq '^[0-9a-f]{16,128}$'; then
  echo "STOP: no valid run key (got: ${KEY:0:20}...). In admin press Copy next to the game's Run check key, then run this again."; exit 1
fi
case "$ZIP" in *-keyed.zip) echo "STOP: this zip is already keyed. Use the creator's original zip."; exit 1;; esac
ABS="$(cd "$(dirname "$ZIP")" && pwd)/$(basename "$ZIP")"
OUT="${ABS%.zip}-keyed.zip"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
( cd "$T" && unzip -q "$ABS" ) || { echo "STOP: could not unzip $ZIP"; exit 1; }
FILES="$(cd "$T" && grep -rlI 'PASTE_KEY_HERE' . )"
if [ -z "$FILES" ]; then
  echo "STOP: no PASTE_KEY_HERE placeholder in this zip. Ask the creator for a build with  RUN_KEY = 'PASTE_KEY_HERE'  (or this zip already has a key in it)."; exit 1
fi
( cd "$T" && printf '%s\n' "$FILES" | while IFS= read -r f; do K="$KEY" perl -pi -e 's/PASTE_KEY_HERE/$ENV{K}/g' "$f"; done )
LEFT="$(cd "$T" && grep -rlI 'PASTE_KEY_HERE' . | wc -l | tr -d ' ')"
HAS="$(cd "$T" && grep -rlI "$KEY" . | wc -l | tr -d ' ')"
if [ "$LEFT" != "0" ] || [ "$HAS" = "0" ]; then echo "STOP: key swap did not complete (placeholders left: $LEFT). Nothing was written."; exit 1; fi
rm -f "$OUT"
( cd "$T" && zip -qr "$OUT" . ) || { echo "STOP: could not write $OUT"; exit 1; }
echo "OK: key ${KEY:0:6}…${KEY: -4} inserted into $HAS file(s)."
echo "Upload this file:  $OUT"
echo "Then in admin, make sure the Run check key field holds the same key and press Save key."
