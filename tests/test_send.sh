#!/usr/bin/env bash
cap() { af_tmux capture-pane -p -J -S - -t "=$1:"; }
spawn() { mkdir -p "$AF_TMP/p"; af-spawn --dir "$AF_TMP/p" >/dev/null; }
test_send_basic() {
  spawn; out=$(echo "do thing" | af-send 2)
  assert_eq "agent_02 (task agent_02-001)" "$out" "out"
  assert_eq working "$(af_status_get agent_02)" "status"
  assert_contains "$(cat "$AF_HOME/agents/agent_02/tasks/001.md")" "[agent_02: blocked] if you need input" "instruction saved"
  assert_eq "do thing" "$(af_meta_get agent_02 last_task_title)" "title"
  sleep 2; assert_eq "done 1" "$(cap agent_02 | af-parse agent_02 '(task agent_02-001)')" "fake answered"
}
test_send_refuses_when_working() { spawn; echo a | af-send 2 >/dev/null; set +e; echo b | af-send 2 2>/dev/null; rc=$?; set -e; assert_eq 2 "$rc" "busy"; }
test_send_force()                { spawn; echo a | af-send 2 >/dev/null; echo b | af-send --force 2 >/dev/null; assert_eq 002 "$(af_meta_get agent_02 tasks)" "two tasks"; }
test_send_long_prompt_tag_visible() {
  spawn; for i in $(seq 1 200); do echo "line $i"; done > "$AF_TMP/long.txt"
  af-send 2 "$AF_TMP/long.txt" >/dev/null; sleep 2
  assert_eq "done 1" "$(cap agent_02 | af-parse agent_02 '(task agent_02-001)')" "long prompt"
}
test_send_unknown_agent() { assert_fail sh -c 'echo x | af-send 7'; }
test_send_empty_prompt()  { spawn; assert_fail sh -c 'echo "   " | af-send 2'; assert_eq idle "$(af_status_get agent_02)" "unchanged"; }
test_send_closed_agent()  { spawn; af_status_set agent_02 closed; assert_fail sh -c 'echo x | af-send 2'; }
test_send_blocked_answered_in_pane() {
  spawn; echo PLEASE_BLOCK | af-send 2 >/dev/null; sleep 2
  af_status_set agent_02 blocked; af_meta_set agent_02 blocked_count 1
  af_tmux send-keys -t "=agent_02:" -l "fine (task answer)"; af_tmux send-keys -t "=agent_02:" Enter; sleep 2
  set +e; echo answer | af-send 2 >/dev/null; rc=$?; set -e; assert_eq 3 "$rc" "answered directly"
}
test_send_blocked_not_answered() {
  spawn; echo PLEASE_BLOCK | af-send 2 >/dev/null; sleep 2
  af_status_set agent_02 blocked; af_meta_set agent_02 blocked_count 1
  out=$(echo answer | af-send 2); assert_eq "agent_02 (task agent_02-002)" "$out" "sent answer"
}
