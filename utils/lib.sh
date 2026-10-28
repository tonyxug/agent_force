#!/usr/bin/env bash
# Shared helpers for agent_force. Source this file; do not run it.
set -euo pipefail

# Resolve this file's real path (symlink-safe, no readlink -f).
_af_src="${BASH_SOURCE[0]}"
while [ -h "$_af_src" ]; do
  _af_dir="$(cd -P "$(dirname "$_af_src")" && pwd)"
  _af_src="$(readlink "$_af_src")"
  case "$_af_src" in
    /*) ;;
    *) _af_src="$_af_dir/$_af_src" ;;
  esac
done
AF_ROOT="$(cd -P "$(dirname "$_af_src")/.." && pwd)"
unset _af_src _af_dir

AF_HOME="${AGENT_FORCE_HOME:-$HOME/.agent_force}"
AF_SOCKET="${AF_SOCKET:-agent_force}"
AF_ADAPTER_DIR="${AF_ADAPTER_DIR:-$AF_ROOT/adapters/claude}"
export AF_ROOT AF_HOME AF_SOCKET AF_ADAPTER_DIR

af_die() {
  printf 'agent_force: %s\n' "$*" >&2
  exit 1
}

af_tmux() {
  tmux -L "$AF_SOCKET" "$@"
}

# af_name INPUT -> agent_NN (01..99)
af_name() {
  local in="${1:-}" n
  n="${in#agent_}"
  case "$n" in
    ''|*[!0-9]*) af_die "bad agent name: '$in'" ;;
  esac
  n=$((10#$n))
  if [ "$n" -lt 1 ] || [ "$n" -gt 99 ]; then
    af_die "agent number out of range (1-99): '$in'"
  fi
  printf 'agent_%02d\n' "$n"
}

af_dir() {
  printf '%s/agents/%s\n' "$AF_HOME" "$1"
}

af_meta_get() {
  local f
  f="$(af_dir "$1")/meta.json"
  [ -f "$f" ] || return 0
  jq -r --arg k "$2" '.[$k] // empty' "$f"
}

# af_meta_set_json NAME KEY JSON
af_meta_set_json() {
  local d f tmp cur
  d="$(af_dir "$1")"
  f="$d/meta.json"
  mkdir -p "$d"
  cur='{}'
  [ -f "$f" ] && cur="$(cat "$f")"
  tmp="$(mktemp "$d/.meta.XXXXXX")"
  if ! printf '%s' "$cur" | jq --arg k "$2" --argjson v "$3" '.[$k] = $v' >"$tmp"; then
    rm -f "$tmp"
    af_die "cannot write meta for $1"
  fi
  mv "$tmp" "$f"
}

# af_meta_set NAME KEY VALUE (string value)
af_meta_set() {
  local json
  json="$(jq -n --arg v "$3" '$v')"
  af_meta_set_json "$1" "$2" "$json"
}

af_status_get() {
  local f
  f="$(af_dir "$1")/status"
  [ -f "$f" ] || return 0
  cat "$f"
}

af_status_set() {
  local d tmp
  d="$(af_dir "$1")"
  mkdir -p "$d"
  tmp="$(mktemp "$d/.status.XXXXXX")"
  printf '%s\n' "$2" >"$tmp"
  mv "$tmp" "$d/status"
}

# af_pane NAME -> tmux pane target for NAME (trailing colon is required).
af_pane() {
  printf '=%s:\n' "$1"
}

af_alive() {
  af_tmux has-session -t "=$1" >/dev/null 2>&1
}

# Next worker number: highest in agents/ + 1, minimum 2.
af_next_number() {
  local max=1 d b n
  if [ -d "$AF_HOME/agents" ]; then
    for d in "$AF_HOME"/agents/agent_*; do
      [ -e "$d" ] || continue
      b="${d##*/agent_}"
      case "$b" in
        ''|*[!0-9]*) continue ;;
      esac
      n=$((10#$b))
      [ "$n" -gt "$max" ] && max=$n
    done
  fi
  echo $((max + 1))
}

af_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  else
    af_die "no uuid source (need uuidgen)"
  fi
}

# af_wait_ready NAME: wait until the adapter's ready.sh accepts the pane.
# Success: status idle, return 0. Timeout (AF_READY_TIMEOUT, default 60 s): status dead, return 1.
af_wait_ready() {
  local name="$1" timeout="${AF_READY_TIMEOUT:-60}" start now screen
  start="$(date +%s)"
  while :; do
    screen="$(af_tmux capture-pane -p -t "=$name:" 2>/dev/null || true)"
    if printf '%s\n' "$screen" | "$AF_ADAPTER_DIR/ready.sh" >/dev/null 2>&1; then
      af_status_set "$name" idle
      return 0
    fi
    now="$(date +%s)"
    if [ $((now - start)) -ge "$timeout" ]; then
      af_status_set "$name" dead
      return 1
    fi
    sleep 0.5
  done
}

# af_check NAME: one check of a worker. Prints the resulting status word.
# Session gone (status not closed) -> dead. While status is working, parse the
# screen for last_tag; on done/failed/blocked save status, last_response.md, blocked_count.
af_check() {
  local name="$1" st tag screen res state count parse
  st="$(af_status_get "$name")"
  if [ "$st" = closed ]; then echo closed; return 0; fi
  if ! af_alive "$name"; then
    af_status_set "$name" dead
    echo dead
    return 0
  fi
  tag="$(af_meta_get "$name" last_tag)"
  if [ "$st" != working ] || [ -z "$tag" ]; then echo "$st"; return 0; fi
  parse="$AF_ROOT/utils/af-parse"
  screen="$(af_tmux capture-pane -p -J -S - -t "$(af_pane "$name")" 2>/dev/null || true)"
  res="$(printf '%s\n' "$screen" | "$parse" "$name" "$tag")"
  state="${res% *}"
  count="${res##* }"
  case "$state" in
    done|failed|blocked)
      printf '%s\n' "$screen" | "$parse" --body "$name" "$tag" >"$(af_dir "$name")/last_response.md"
      af_meta_set_json "$name" blocked_count "$count"
      af_status_set "$name" "$state"
      echo "$state"
      ;;
    *) echo "$st" ;;
  esac
}

# af_launch ROLE NAME CWD SESSION_ID MODE: start NAME's agent in a new tmux session.
af_launch() {
  local role="$1" name="$2" cwd="$3" id="$4" mode="$5" cmd
  cmd="$("$AF_ADAPTER_DIR/launch.sh" "$role" "$name" "$id" "$mode")"
  af_tmux new-session -d -s "$name" -c "$cwd" \
    -e "PATH=$AF_ROOT/utils:$PATH" -e "AF_AGENT=$name" -e "AF_HOME=$AF_HOME" \
    -e "AGENT_FORCE_HOME=$AF_HOME" -e "AF_SOCKET=$AF_SOCKET" \
    -e "AF_ADAPTER_DIR=$AF_ADAPTER_DIR" "$cmd"
}
