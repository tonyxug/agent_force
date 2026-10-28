#!/usr/bin/env bash
# Claude adapter: launch.sh command line and ready.sh on screens captured from
# Claude Code 2.1.312. The input line is "❯" + NO-BREAK SPACE at column 0.
CA="$REPO/adapters/claude"
NBSP=$(printf '\302\240')
RULE='────────────────────────────────────────'

screen_ready() {
  printf ' ▐▛███▛█   Claude Code v2.1.312\n%s\n❯%sTry "write a test for <filepath>"\n%s\n' "$RULE" "$NBSP" "$RULE"
  printf '  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents\n'
}
screen_trust() {
  printf '%s\n Accessing workspace:\n\n /tmp/x\n\n Quick safety check: Is this a project you created or one you trust?\n\n' "$RULE"
  printf ' ❯ No, exit\n   Yes, I trust this folder\n\n Enter to confirm · Esc to cancel\n'
}
screen_bypass() {
  printf '%s\n  WARNING: Claude Code running in Bypass Permissions mode\n\n' "$RULE"
  printf '  ❯ No, exit\n    Yes, I accept\n\n  Enter to confirm · Esc to cancel\n'
}

test_ready_input_box()      { screen_ready | "$CA/ready.sh"; }
test_ready_trust_dialog()   { assert_fail sh -c 'printf "%s\n" "$1" | "$2"' _ "$(screen_trust)" "$CA/ready.sh"; }
test_ready_bypass_dialog()  { assert_fail sh -c 'printf "%s\n" "$1" | "$2"' _ "$(screen_bypass)" "$CA/ready.sh"; }
test_ready_blank_screen()   { assert_fail sh -c 'printf "\n\n" | "$1"' _ "$CA/ready.sh"; }

test_parse_real_answer() {
  s=$(printf '  [agent_09: working] if you are not finished yet.      \n  (task agent_09-001)      \n⏺ OK          \n  [agent_09: done]        \n✻ Worked for 2s\n%s\n❯%s\n' "$RULE" "$NBSP")
  assert_eq "done 1" "$(printf '%s\n' "$s" | af-parse agent_09 "(task agent_09-001)")" "parse"
}

# Run the printed command in a shell with a fake claude that dumps its args.
run_launch() {
  mkdir -p "$AF_TMP/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$OUT"\n' >"$AF_TMP/bin/claude"
  chmod +x "$AF_TMP/bin/claude"
  cmd="$("$CA/launch.sh" "$@")"
  OUT="$AF_TMP/args" PATH="$AF_TMP/bin:$PATH" bash -c "$cmd"
}

test_launch_worker_new() {
  run_launch worker agent_05 id-123 new
  assert_eq "$(printf -- '--dangerously-skip-permissions\n--session-id\nid-123\n--append-system-prompt')" "$(head -4 "$AF_TMP/args")" "flags"
  assert_eq "$(sed 's/{{NAME}}/agent_05/g' "$REPO/prompts/worker.md")" "$(tail -n +5 "$AF_TMP/args")" "prompt"
}
test_launch_leader_resume() {
  run_launch leader agent_01 id-9 resume
  assert_eq "$(printf -- '--resume\nid-9')" "$(sed -n '2,3p' "$AF_TMP/args")" "flags"
  assert_eq "$(cat "$REPO/prompts/leader.md")" "$(tail -n +5 "$AF_TMP/args")" "prompt"
}
test_launch_bad_mode()   { assert_fail "$CA/launch.sh" worker agent_05 id x; }
test_launch_bad_role()   { assert_fail "$CA/launch.sh" nobody agent_05 id new; }
