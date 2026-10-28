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
