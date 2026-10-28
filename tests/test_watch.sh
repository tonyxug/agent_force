#!/usr/bin/env bash
spawn() { mkdir -p "$AF_TMP/p"; af-spawn --dir "$AF_TMP/p" >/dev/null; }
# wait_status NAME WORD [SECS]: poll af-status until the status shows WORD.
wait_status() {
  local i
  for i in $(seq 1 "${3:-10}"); do
    case "$(af-status)" in *"$1"*"$2"*) return 0 ;; esac
    sleep 1
  done
  return 1
}
test_watch_done()    { spawn; echo hi | af-send 2 >/dev/null; out=$(af-watch 2)
                       assert_eq "agent_02 done (task agent_02-001)" "$out" "watch"; assert_eq done "$(af_status_get agent_02)" "status"
                       assert_contains "$(cat "$AF_HOME/agents/agent_02/last_response.md")" "result: ok" "response"; }
test_watch_failed()  { spawn; echo PLEASE_FAIL  | af-send 2 >/dev/null; assert_contains "$(af-watch 2)" "failed" "failed"; }
test_watch_blocked() { spawn; echo PLEASE_BLOCK | af-send 2 >/dev/null; af-watch 2 >/dev/null
                       assert_eq blocked "$(af_status_get agent_02)" "blocked"; assert_contains "$(af-read 2)" "Question: which one?" "question"
                       assert_eq 1 "$(af_meta_get agent_02 blocked_count)" "blocked_count"; }
test_watch_ignores_working() { spawn; echo PLEASE_SLOW | af-send 2 >/dev/null; out=$(af-watch 2); assert_contains "$out" "done" "waited past working"; }
test_watch_dead_session()    { spawn; echo PLEASE_SLOW | af-send 2 >/dev/null; af_tmux kill-session -t agent_02
                               assert_eq "agent_02 dead" "$(af-watch 2)" "dead"; assert_eq dead "$(af_status_get agent_02)" "status"; }
test_watch_two_workers()     { spawn; spawn; echo a | af-send 2 >/dev/null; echo PLEASE_FAIL | af-send 3 >/dev/null
                               af-watch 2 >/dev/null; af-watch 3 >/dev/null
                               assert_eq done "$(af_status_get agent_02)" "w2"; assert_eq failed "$(af_status_get agent_03)" "w3 not mixed up"; }
test_watch_superseded()      { spawn; echo PLEASE_SLOW | af-send 2 >/dev/null
                               ( sleep 1; af_meta_set agent_02 last_tag "(task agent_02-999)" ) &
                               assert_eq "agent_02 superseded" "$(af-watch 2)" "superseded"; wait; }
test_watch_nothing_sent()    { spawn; assert_eq "agent_02 nothing to watch" "$(af-watch 2)" "nothing"; }
test_watch_unknown()         { assert_fail af-watch 7; assert_fail af-watch; }
test_read_nothing()          { spawn; assert_eq "" "$(af-read 2)" "empty"; }
test_read_after_dead()       { spawn; echo hi | af-send 2 >/dev/null; af-watch 2 >/dev/null; af_tmux kill-session -t agent_02
                               assert_contains "$(af-read 2)" "result: ok" "falls back to file"; }
test_status_lists()          { spawn; s=$(af-status); assert_contains "$s" "agent_02" "listed"; assert_contains "$s" "idle" "idle"; }
test_status_empty()          { assert_eq "" "$(af-status)" "no agents"; }
test_status_columns()        { spawn; echo "my title" | af-send 2 >/dev/null
                               line=$(af-status | head -n1)
                               assert_eq 6 "$(printf '%s' "$line" | awk -F'\t' '{print NF}')" "6 columns"
                               assert_contains "$line" "my title" "title"; assert_contains "$line" "worker" "role"; }
test_status_updates_working(){ spawn; echo hi | af-send 2 >/dev/null; wait_status agent_02 done || true; assert_contains "$(af-status)" "done" "status parses screen"
                               assert_eq done "$(af_status_get agent_02)" "saved"; }
test_status_dead()           { spawn; af_tmux kill-session -t agent_02; assert_contains "$(af-status)" "dead" "shows dead"
                               assert_eq dead "$(af_status_get agent_02)" "saved"; }
test_status_all_leader()     { spawn; af_meta_set agent_01 role leader; af_status_set agent_01 idle
                               assert_contains "$(af-status --all | head -n1)" "agent_01" "leader first"
                               case "$(af-status)" in *agent_01*) return 1 ;; esac; }
test_close()                 { spawn; af-close 2 >/dev/null; assert_eq closed "$(af_status_get agent_02)" "closed"
                               assert_fail af_alive agent_02; test -d "$(af_meta_get agent_02 cwd)"
                               assert_eq true "$(af_meta_get agent_02 closed)" "meta"
                               assert_eq "agent_02 closed" "$(af-close 2)" "idempotent"; assert_contains "$(af-status)" closed "shown closed"; }
test_close_unknown()         { assert_fail af-close 7; }
test_watch_ends_on_interrupted() { spawn; af_meta_set agent_02 last_tag "(task agent_02-001)"; af_status_set agent_02 interrupted
                               assert_eq "agent_02 interrupted (task agent_02-001)" "$(run_limited 5 af-watch 2)" "not polling forever"; }
test_watch_ends_on_idle()    { spawn; af_meta_set agent_02 last_tag "(task agent_02-001)"
                               assert_eq "agent_02 idle (task agent_02-001)" "$(run_limited 5 af-watch 2)" "idle is reported"; }
test_watch_lost_tag()        { spawn; af_meta_set agent_02 last_tag "(task agent_02-999)"; af_status_set agent_02 working
                               out=$(AF_LOST_POLLS=2 run_limited 10 af-watch 2)
                               assert_eq "agent_02 lost (task agent_02-999)" "$out" "lost"; assert_eq lost "$(af_status_get agent_02)" "status"; }
test_watch_tag_seen_not_lost() { spawn; echo PLEASE_SLOW | af-send 2 >/dev/null; out=$(AF_LOST_POLLS=1 af-watch 2)
                               assert_contains "$out" "done" "tag on screen is not lost"; }
test_status_all_leader_dead() { spawn; af_meta_set agent_01 role leader; af_status_set agent_01 idle
                               assert_contains "$(af-status --all | head -n1)" "dead" "stopped leader shows dead"; }
