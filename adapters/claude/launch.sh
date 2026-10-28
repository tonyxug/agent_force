#!/usr/bin/env bash
# Claude adapter: launch.sh ROLE NAME SESSION_ID MODE -> prints the pane command.
# ROLE: leader | worker. MODE: new (--session-id) | resume (--resume).
# The role prompt is prompts/ROLE.md with {{NAME}} replaced by NAME.
set -euo pipefail
src="${BASH_SOURCE[0]}"
while [ -h "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"; src="$(readlink "$src")"
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
root="$(cd -P "$(dirname "$src")/../.." && pwd)"

if [ "$#" -ne 4 ]; then
  echo "usage: launch.sh ROLE NAME SESSION_ID MODE" >&2
  exit 2
fi
role="$1" name="$2" id="$3" mode="$4"

prompt_file="$root/prompts/$role.md"
[ -f "$prompt_file" ] || { echo "launch.sh: no prompt for role '$role'" >&2; exit 1; }
case "$mode" in
  new) id_flag=--session-id ;;
  resume) id_flag=--resume ;;
  *) echo "launch.sh: bad mode '$mode' (new|resume)" >&2; exit 2 ;;
esac

prompt="$(cat "$prompt_file")"
prompt="${prompt//\{\{NAME\}\}/$name}"

printf 'claude --dangerously-skip-permissions %s %q --append-system-prompt %q\n' \
  "$id_flag" "$id" "$prompt"
