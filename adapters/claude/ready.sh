#!/usr/bin/env bash
# Claude adapter: exit 0 when the screen (stdin) shows the Claude Code input box.
# Ready = a line that starts with the prompt sign "❯" at column 0 and no
# first-run dialog on screen (dialogs show indented "❯ No, exit" and
# "Enter to confirm"). Read stdin into a variable: no grep -q on a pipe.
set -euo pipefail
screen="$(cat)"
case "$screen" in
  *"Enter to confirm"*) exit 1 ;;
esac
printf '%s\n' "$screen" | awk '/^❯/ { found = 1 } END { exit found ? 0 : 1 }'
