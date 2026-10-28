#!/usr/bin/env bash
mkrepo() { git init -q "$1"; git -C "$1" commit -q --allow-empty -m init; }
test_spawn_git_repo() {
  mkrepo "$AF_TMP/repo"; n=$(cd "$AF_TMP/repo" && af-spawn --worktree)
  assert_eq agent_02 "$n" "name"
  assert_eq idle "$(af_status_get agent_02)" "ready"
  assert_eq "agent_force/agent_02" "$(af_meta_get agent_02 branch)" "branch"
  wt=$(af_meta_get agent_02 worktree); assert_eq "$wt" "$(af_meta_get agent_02 cwd)" "cwd=worktree"
  assert_eq "agent_force/agent_02" "$(git -C "$wt" branch --show-current)" "wt branch"
  af_alive agent_02
}
test_spawn_second_worker()  { mkrepo "$AF_TMP/repo"; cd "$AF_TMP/repo"; af-spawn >/dev/null; assert_eq agent_03 "$(af-spawn)" "second"; }
test_spawn_branch_taken()   { mkrepo "$AF_TMP/repo"; git -C "$AF_TMP/repo" branch agent_force/agent_02; (cd "$AF_TMP/repo" && af-spawn --worktree >/dev/null)
                              assert_eq "agent_force/agent_02-2" "$(af_meta_get agent_02 branch)" "suffix"; }
test_spawn_non_git()        { mkdir "$AF_TMP/plain"; (cd "$AF_TMP/plain" && af-spawn >/dev/null)
                              assert_eq "$AF_TMP/plain" "$(af_meta_get agent_02 cwd)" "cwd"; assert_eq "" "$(af_meta_get agent_02 branch)" "no branch"; }
test_spawn_dir_flag()       { mkrepo "$AF_TMP/other"; af-spawn --worktree --dir "$AF_TMP/other" >/dev/null; assert_eq "$AF_TMP/other" "$(af_meta_get agent_02 repo)" "repo"; }
test_spawn_path_with_space(){ mkrepo "$AF_TMP/my repo"; (cd "$AF_TMP/my repo" && af-spawn --worktree >/dev/null); assert_eq idle "$(af_status_get agent_02)" "space"; }
test_spawn_ready_timeout()  { mkdir "$AF_TMP/p"; AF_READY_TIMEOUT=2 AF_ADAPTER_DIR="$AF_TMP/never" ; mkdir -p "$AF_TMP/never"
                              printf '#!/usr/bin/env bash\necho "sleep 100"\n' > "$AF_TMP/never/launch.sh"; printf '#!/usr/bin/env bash\nexit 1\n' > "$AF_TMP/never/ready.sh"; chmod +x "$AF_TMP/never/"*.sh
                              export AF_READY_TIMEOUT AF_ADAPTER_DIR; assert_fail af-spawn --dir "$AF_TMP/p"; assert_eq dead "$(af_status_get agent_02)" "dead"; }
test_spawn_missing_dir()    { assert_fail af-spawn --dir "$AF_TMP/nope"; }
test_spawn_meta()           { mkdir "$AF_TMP/plain"; (cd "$AF_TMP/plain" && af-spawn >/dev/null)
                              assert_eq fake_adapter "$(af_meta_get agent_02 type)" "type (adapter basename)"
                              assert_eq worker "$(af_meta_get agent_02 role)" "role"
                              assert_eq 0 "$(jq -r .tasks "$(af_dir agent_02)/meta.json")" "tasks"
                              assert_eq false "$(jq -r .closed "$(af_dir agent_02)/meta.json")" "closed"; }
test_spawn_history_limit()  { spawn_plain() { mkdir -p "$AF_TMP/plain"; af-spawn --dir "$AF_TMP/plain" >/dev/null; }; spawn_plain
                              assert_eq 100000 "$(af_tmux display -p -t "$(af_pane agent_02)" '#{history_limit}')" "pane history"
                              assert_eq 100000 "$(af_tmux show-options -gv history-limit)" "server default"; }
test_spawn_worktree_fail_cleans() { git init -q "$AF_TMP/empty"; assert_fail af-spawn --worktree --dir "$AF_TMP/empty"
                              test ! -e "$(af_dir agent_02)"; assert_eq 2 "$(af_next_number)" "number not burned"; }
test_spawn_ready_timeout_kills() { mkdir "$AF_TMP/p" "$AF_TMP/never"
                              printf '#!/usr/bin/env bash\necho "sleep 100"\n' > "$AF_TMP/never/launch.sh"; printf '#!/usr/bin/env bash\nexit 1\n' > "$AF_TMP/never/ready.sh"; chmod +x "$AF_TMP/never/"*.sh
                              AF_READY_TIMEOUT=2 AF_ADAPTER_DIR="$AF_TMP/never" assert_fail af-spawn --dir "$AF_TMP/p"
                              assert_fail af_alive agent_02; assert_eq dead "$(af_status_get agent_02)" "dead"; }
test_spawn_session_exits_fast() { mkdir "$AF_TMP/p" "$AF_TMP/quit"
                              printf '#!/usr/bin/env bash\necho "true"\n' > "$AF_TMP/quit/launch.sh"; printf '#!/usr/bin/env bash\nexit 1\n' > "$AF_TMP/quit/ready.sh"; chmod +x "$AF_TMP/quit/"*.sh
                              t0=$(date +%s); AF_READY_TIMEOUT=30 AF_ADAPTER_DIR="$AF_TMP/quit" assert_fail af-spawn --dir "$AF_TMP/p"; t1=$(date +%s)
                              [ $((t1 - t0)) -lt 10 ] || { echo "waited $((t1 - t0)) s" >&2; return 1; }
                              assert_eq dead "$(af_status_get agent_02)" "dead"; }
test_spawn_repo_no_worktree() { mkrepo "$AF_TMP/repo"; (cd "$AF_TMP/repo" && af-spawn >/dev/null)
                              assert_eq "$AF_TMP/repo" "$(af_meta_get agent_02 cwd)" "cwd is the repo"
                              assert_eq "" "$(af_meta_get agent_02 worktree)" "no worktree"; assert_eq "" "$(af_meta_get agent_02 branch)" "no branch"
                              assert_eq 1 "$(git -C "$AF_TMP/repo" worktree list | wc -l | tr -d ' ')" "git has no new worktree"; }
test_spawn_worktree_needs_repo() { mkdir "$AF_TMP/plain"; assert_fail af-spawn --worktree --dir "$AF_TMP/plain"
                              test ! -e "$(af_dir agent_02)"; }
