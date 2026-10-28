#!/usr/bin/env bash
# Tests for the agent_force CLI.
af() { "$REPO/agent_force" "$@"; }

test_start_creates_leader() { cd "$AF_TMP"; af start >/dev/null; af_alive agent_01; assert_eq leader "$(af_meta_get agent_01 role)" "role"; }
test_start_twice_fails()    { cd "$AF_TMP"; af start >/dev/null; assert_fail af start; }
test_start_archives_old()   { cd "$AF_TMP"; af start >/dev/null; af stop >/dev/null; af start >/dev/null
                              assert_eq 1 "$(ls "$AF_HOME/archive" | wc -l | tr -d ' ')" "archived"; }
test_start_path_with_space(){ mkdir "$AF_TMP/a b"; cd "$AF_TMP/a b"; af start >/dev/null; assert_eq "$AF_TMP/a b" "$(af_meta_get agent_01 cwd)" "cwd"; }
test_stop_keeps_state()     { cd "$AF_TMP"; af start >/dev/null; af-spawn >/dev/null; af stop >/dev/null
                              ! af_alive agent_01; test -f "$AF_HOME/agents/agent_02/meta.json"; }
test_latest_resumes()       { cd "$AF_TMP"; af start >/dev/null; af-spawn >/dev/null; af-spawn >/dev/null; af-close 3 >/dev/null
                              id=$(af_meta_get agent_01 session_id); af stop >/dev/null; af start --latest >/dev/null
                              af_alive agent_01; af_alive agent_02; ! af_alive agent_03
                              assert_eq "$id" "$(af_meta_get agent_01 session_id)" "same id"
                              assert_contains "$(af_tmux capture-pane -p -t "$(af_pane agent_02)")" resume "resume mode"; }
test_latest_without_state() { assert_fail af start --latest; }
test_list()                 { cd "$AF_TMP"; af start >/dev/null; af-spawn >/dev/null; s=$(af list); assert_contains "$s" agent_01 l; assert_contains "$s" agent_02 w; }
test_connect_missing()      { assert_fail af connect 4; }
test_usage()                { assert_fail af; assert_fail af bogus; }
test_stop_without_server()  { assert_eq stopped "$(af stop)" "stop"; }
mkrepo() { git init -q "$1"; git -C "$1" commit -q --allow-empty -m init; }
test_restart_spawn_same_repo() { cd "$AF_TMP"; af start >/dev/null; mkrepo "$AF_TMP/repo"; (cd "$AF_TMP/repo" && af-spawn >/dev/null)
                              wt1=$(af_meta_get agent_02 worktree); af stop >/dev/null; af start >/dev/null
                              assert_eq agent_02 "$(cd "$AF_TMP/repo" && af-spawn)" "spawn after fresh start"
                              assert_eq "$wt1-2" "$(af_meta_get agent_02 worktree)" "path suffixed"
                              assert_eq "agent_force/agent_02-2" "$(af_meta_get agent_02 branch)" "branch suffixed"
                              assert_eq "agent_force/agent_02" "$(git -C "$wt1" branch --show-current)" "old worktree untouched"; }
test_start_names_killed()   { cd "$AF_TMP"; af start >/dev/null; af-spawn >/dev/null; af_tmux kill-session -t =agent_01
                              assert_contains "$(af start)" "agent_02" "names killed worker"; }
test_latest_interrupted()   { cd "$AF_TMP"; af start >/dev/null; af-spawn >/dev/null; af_status_set agent_02 working
                              af_meta_set agent_02 last_tag "(task agent_02-001)"; af_tmux kill-server; af start --latest >/dev/null
                              assert_eq interrupted "$(af_status_get agent_02)" "was working"
                              assert_contains "$(af-status)" interrupted "shown"; }
test_latest_keeps_outcome() { cd "$AF_TMP"; af start >/dev/null; af-spawn >/dev/null; af-spawn >/dev/null; af-spawn >/dev/null
                              af_status_set agent_02 done; af_status_set agent_03 failed; af_status_set agent_04 blocked
                              af stop >/dev/null; af start --latest >/dev/null
                              assert_eq done "$(af_status_get agent_02)" "done"; assert_eq failed "$(af_status_get agent_03)" "failed"
                              assert_eq blocked "$(af_status_get agent_04)" "blocked"; }
test_stop_saves_finished()  { cd "$AF_TMP"; af start >/dev/null; af-spawn >/dev/null; echo hi | af-send 2 >/dev/null; sleep 1
                              af stop >/dev/null; assert_eq done "$(af_status_get agent_02)" "checked before stop"
                              af start --latest >/dev/null; assert_eq done "$(af_status_get agent_02)" "not interrupted"; }
test_list_leader_dead()     { cd "$AF_TMP"; af start >/dev/null; af stop >/dev/null; assert_contains "$(af list)" dead "stopped leader"; }
test_latest_after_list()    { cd "$AF_TMP"; af start >/dev/null; af-spawn >/dev/null; af-spawn >/dev/null
                              af_status_set agent_02 done; af_status_set agent_03 working
                              af stop >/dev/null; af list >/dev/null; af list >/dev/null
                              assert_eq dead "$(af_status_get agent_02)" "shown dead after stop"
                              af start --latest >/dev/null
                              assert_eq done "$(af_status_get agent_02)" "done kept"
                              assert_eq interrupted "$(af_status_get agent_03)" "working kept"; }
test_latest_after_two_stops() { cd "$AF_TMP"; af start >/dev/null; af-spawn >/dev/null; af_status_set agent_02 blocked
                              af stop >/dev/null; af stop >/dev/null; af start --latest >/dev/null
                              assert_eq blocked "$(af_status_get agent_02)" "blocked kept"; }
