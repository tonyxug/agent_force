#!/usr/bin/env bash
# Test helpers for agent_force. Sourced by tests/run.sh.

REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO

assert_eq() {
  if [ "$1" != "$2" ]; then
    printf 'assert_eq failed: %s\n  expected: [%s]\n  actual:   [%s]\n' "${3:-}" "$1" "$2" >&2
    return 1
  fi
}

assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  printf 'assert_contains failed: %s\n  needle:   [%s]\n  haystack: [%s]\n' "${3:-}" "$2" "$1" >&2
  return 1
}

# Passes when the command exits non-zero. Runs in a subshell so exit is safe.
assert_fail() {
  if ( "$@" ) >/dev/null 2>&1; then
    printf 'assert_fail failed: command succeeded: %s\n' "$*" >&2
    return 1
  fi
  return 0
}

af_test_setup() {
  AF_TMP="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/af_test.XXXXXX")" && pwd -P)"
  export AF_TMP
  export AGENT_FORCE_HOME="$AF_TMP/home"
  export AF_SOCKET="af_test_$$_$RANDOM"
  export AF_ADAPTER_DIR="$REPO/tests/fake_adapter"
  export AF_POLL_INTERVAL=1
  export PATH="$REPO/utils:$PATH"
  mkdir -p "$AGENT_FORCE_HOME"
  # shellcheck disable=SC1091
  . "$REPO/utils/lib.sh"
}

af_test_teardown() {
  if [ -n "${AF_SOCKET:-}" ]; then
    tmux -L "$AF_SOCKET" kill-server >/dev/null 2>&1 || true
  fi
  if [ -n "${AF_TMP:-}" ]; then
    rm -rf "$AF_TMP"
  fi
}

# run_limited SECS CMD...: run CMD, kill it after SECS. Prints its stdout.
# Returns 0 if CMD ended by itself, 1 if it was killed.
run_limited() {
  local secs="$1" out pid i rc=1
  shift
  out="$(mktemp "$AF_TMP/limited.XXXXXX")"
  "$@" >"$out" 2>/dev/null &
  pid=$!
  for i in $(seq 1 $((secs * 4))); do
    if ! kill -0 "$pid" 2>/dev/null; then rc=0; break; fi
    sleep 0.25
  done
  [ "$rc" -eq 0 ] || kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  cat "$out"
  return "$rc"
}
