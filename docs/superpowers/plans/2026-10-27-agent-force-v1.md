# agent_force v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `agent_force` CLI and leader helper scripts so one Claude Code leader (`agent_01`) can spawn, drive, and watch Claude Code workers (`agent_02`, …) in tmux sessions on a private socket.

**Architecture:** Plain Bash scripts. `agent_force` (repo root) is the user CLI. `utils/af-*` are helpers the leader calls. `utils/lib.sh` holds shared functions. State lives in files under `$AGENT_FORCE_HOME`. Worker status comes only from parsing `tmux capture-pane` output for `[agent_NN: …]` markers. Everything agent-specific sits in an adapter folder (`adapters/claude/`); tests use a fake adapter that runs a small Bash "agent".

**Tech Stack:** Bash (3.2-compatible), tmux, git, jq, uuidgen. Tests: plain Bash test scripts, no test framework.

**Spec:** `docs/superpowers/specs/2026-10-27-agent-force-design.md`

**Status:** Done on branch `v1`. The build differs from this plan in places. See [As-built changes](#as-built-changes) at the end.

## Global Constraints

- Bash must run on macOS's `/bin/bash` 3.2: no associative arrays, no `mapfile`/`readarray`, no `${var,,}`, no `|&`. Shebang `#!/usr/bin/env bash`, `set -euo pipefail`.
- OS-agnostic: macOS and Linux. No OS notifications. Avoid GNU-only or BSD-only flags (`sed -i`, `date -d`, `readlink -f`); write portable helpers instead.
- Dependencies only: `tmux`, `git`, `claude`, `jq`, `uuidgen` (fallback `/proc/sys/kernel/random/uuid`).
- Agent names: `agent_NN`, two digits (`printf 'agent_%02d'`). Leader is always `agent_01`. Workers start at `agent_02`. tmux session name = agent name.
- tmux socket: `tmux -L "${AF_SOCKET:-agent_force}"`. Never touch the default tmux socket.
- State root: `${AGENT_FORCE_HOME:-$HOME/.agent_force}`.
- Status words: `starting | idle | working | done | failed | blocked | closed | dead`.
- Markers, alone on a line: `[agent_NN: done]`, `[agent_NN: failed]`, `[agent_NN: blocked]`, `[agent_NN: working]`.
- Task tag: `(task agent_NN-TTT)`, `TTT` = 3-digit task number per worker.
- Worker branch: `agent_force/agent_NN` (suffix `-2`, `-3`, … if taken). Never modify an existing branch.
- Both leader and workers launch with `claude --dangerously-skip-permissions`.
- Poll interval: `${AF_POLL_INTERVAL:-30}` seconds.
- Never auto-commit, merge, push, or delete a worktree. `stop` and `af-close` keep worktrees and state.
- Every script finds the repo root from its own real path (symlink-safe), exported as `AF_ROOT`.
- Adapter dir: `${AF_ADAPTER_DIR:-$AF_ROOT/adapters/claude}`.

## Review Focus

1. A long multi-line prompt (Claude Code shows it collapsed as `[Pasted text #1 +N lines]`) must still leave the task tag visible on screen, or no task ever finishes → Task 4 test `test_send_long_prompt_tag_visible`.
2. A task prompt that itself quotes a marker (`[agent_03: done]`) must not count as a finished task → Task 2 test `test_marker_inside_prompt_above_tag_ignored`.
3. A worker whose tmux session dies while a watch runs must end the watch with `dead`, not loop forever → Task 5 test `test_watch_dead_session`.
4. Paths with spaces (repo folder, leader folder) must work in spawn and start → Task 3 test `test_spawn_path_with_space`.
5. Worker number 10 and above, and user input `3`, `03`, `agent_03` all mean the same agent → Task 1 test `test_name_normalize`.

---

## File Structure

```
agent_force                  # user CLI: start [--latest] | stop | list | connect N
utils/
  lib.sh                     # shared: paths, names, tmux wrapper, meta/status I/O
  af-parse                   # pure: parse screen text → state, count, body
  af-spawn                   # create worker (worktree, tmux, launch, wait ready)
  af-send                    # send task/answer to worker
  af-watch                   # poll one worker until done/failed/blocked/dead
  af-read                    # print a worker's last response
  af-status                  # table of workers (+ leader with --all)
  af-close                   # close one worker, keep worktree
adapters/claude/
  launch.sh                  # print launch command for leader/worker
  ready.sh                   # exit 0 if screen (stdin) shows Claude ready
prompts/leader.md
prompts/worker.md
tests/
  run.sh                     # runs every tests/test_*.sh, prints summary
  helpers.sh                 # assert_eq, assert_contains, setup/teardown
  fake_adapter/launch.sh     # launches tests/fake_adapter/fake_agent.sh
  fake_adapter/ready.sh      # ready when screen contains "FAKE READY"
  fake_adapter/fake_agent.sh # line-reading fake agent that prints markers
  test_lib.sh  test_parse.sh  test_spawn.sh  test_send.sh
  test_watch.sh  test_cli.sh
README.md
```

---

### Task 1: Test harness and `utils/lib.sh`

**Files:**
- Create: `utils/lib.sh`, `tests/run.sh`, `tests/helpers.sh`, `tests/test_lib.sh`

**Interfaces:**
- Produces (`utils/lib.sh`, sourced by every script):
  - `AF_ROOT`, `AF_HOME`, `AF_SOCKET`, `AF_ADAPTER_DIR` exported on source.
  - `af_tmux ARGS…` → runs `tmux -L "$AF_SOCKET" ARGS…`.
  - `af_name INPUT` → prints `agent_NN`; accepts `3`, `03`, `agent_3`, `agent_03`; exit 1 with message on bad input.
  - `af_dir NAME` → prints `$AF_HOME/agents/NAME`.
  - `af_meta_get NAME KEY` → prints value or empty.
  - `af_meta_set NAME KEY VALUE` → writes `meta.json` atomically (jq to temp file, `mv`). String values; `closed` stored as JSON bool via `af_meta_set_json NAME KEY JSON`.
  - `af_status_get NAME` / `af_status_set NAME WORD`.
  - `af_alive NAME` → exit 0 if tmux session exists on the socket.
  - `af_next_number` → next worker number (highest in `agents/` + 1, min 2).
  - `af_uuid` → lowercase UUID.
  - `af_die MSG` → print `agent_force: MSG` to stderr, exit 1.
- Produces (`tests/helpers.sh`): `assert_eq EXPECTED ACTUAL MSG`, `assert_contains HAYSTACK NEEDLE MSG`, `assert_fail CMD…`, `af_test_setup` (temp `AGENT_FORCE_HOME`, unique `AF_SOCKET=af_test_$$_$RANDOM`, `AF_ADAPTER_DIR=$repo/tests/fake_adapter`, `AF_POLL_INTERVAL=1`, `PATH=$repo/utils:$PATH`), `af_test_teardown` (kill tmux server on that socket, remove temp dir). Each `test_*.sh` defines `test_*` functions; `run.sh` runs each in a subshell with setup/teardown and prints `PASS name` / `FAIL name`, exit 1 if any fail.

- [x] **Step 1: Write `tests/run.sh`, `tests/helpers.sh`, and failing `tests/test_lib.sh`**

```bash
test_name_normalize() {
  assert_eq agent_03 "$(af_name 3)" "3"
  assert_eq agent_03 "$(af_name 03)" "03"
  assert_eq agent_03 "$(af_name agent_03)" "agent_03"
  assert_eq agent_12 "$(af_name 12)" "12"
  assert_fail af_name foo
  assert_fail af_name 0
}
test_meta_roundtrip() {
  af_meta_set agent_02 branch "agent_force/agent_02"
  af_meta_set agent_02 cwd "/tmp/a b"
  assert_eq "agent_force/agent_02" "$(af_meta_get agent_02 branch)" "branch"
  assert_eq "/tmp/a b" "$(af_meta_get agent_02 cwd)" "space path"
  assert_eq "" "$(af_meta_get agent_02 missing)" "missing key"
}
test_status_roundtrip() { af_status_set agent_02 working; assert_eq working "$(af_status_get agent_02)" "status"; }
test_next_number() {
  assert_eq 2 "$(af_next_number)" "empty"
  mkdir -p "$AF_HOME/agents/agent_02" "$AF_HOME/agents/agent_09"
  assert_eq 10 "$(af_next_number)" "after 09"
}
test_uuid() { assert_contains "$(af_uuid)" "-" "uuid"; }
```

- [x] **Step 2: Run** `bash tests/run.sh` → Expected: every `test_lib` test FAIL (lib missing).
- [x] **Step 3: Implement `utils/lib.sh`** with the functions above. `AF_ROOT` = parent of the folder holding `lib.sh`, resolved through symlinks with a portable loop (`cd -P` + `readlink`), not `readlink -f`.
- [x] **Step 4: Run** `bash tests/run.sh` → Expected: all `test_lib` PASS.
- [x] **Step 5: Commit** `git add utils/lib.sh tests && git commit -m "feat: add lib.sh and test harness"`

---

### Task 2: Screen parser `utils/af-parse`

**Files:**
- Create: `utils/af-parse`, `tests/test_parse.sh`

**Interfaces:**
- Produces: `af-parse NAME TAG < screen` prints one line `STATE COUNT`.
  - `STATE` ∈ `notag | none | working | done | failed | blocked`. `notag` = no line contains `TAG`. `none` = tag found, no valid marker below it.
  - `COUNT` = number of valid markers below the last tag line.
- Produces: `af-parse --body NAME TAG < screen` prints lines strictly between the last tag line and the last valid marker below it (empty if none).
- Rules: a valid marker is a line matching, after removing leading whitespace and one optional leading `⏺` or `●` plus spaces, exactly `[NAME: (done|failed|blocked|working)]` with optional trailing spaces. Only lines below the **last** line containing `TAG` count. Last valid marker wins.

- [x] **Step 1: Write failing `tests/test_parse.sh`** (feed heredoc screens)

```bash
T="(task agent_03-002)"
test_notag()                      { assert_eq "notag 0" "$(printf 'hi\n' | af-parse agent_03 "$T")" ""; }
test_tag_no_marker()              { assert_eq "none 0" "$(printf 'x %s\nthinking\n' "$T" | af-parse agent_03 "$T")" ""; }
test_done_with_bullet()           { assert_eq "done 1" "$(printf '%s\n⏺ result\n⏺ [agent_03: done]\n' "$T" | af-parse agent_03 "$T")" ""; }
test_last_marker_wins()           { assert_eq "blocked 2" "$(printf '%s\n[agent_03: working]\nQ?\n  [agent_03: blocked]\n' "$T" | af-parse agent_03 "$T")" ""; }
test_marker_inside_prompt_above_tag_ignored() {
  s=$(printf 'write [agent_03: done] when done\n[agent_03: done]\n%s\nworking on it\n' "$T")
  assert_eq "none 0" "$(printf '%s\n' "$s" | af-parse agent_03 "$T")" ""
}
test_old_tag_ignored()            { s=$(printf '(task agent_03-001)\n[agent_03: done]\n%s\n' "$T"); assert_eq "none 0" "$(printf '%s\n' "$s" | af-parse agent_03 "$T")" ""; }
test_inline_marker_ignored()      { assert_eq "none 0" "$(printf '%s\nI will print [agent_03: done] later\n' "$T" | af-parse agent_03 "$T")" ""; }
test_other_agent_marker_ignored() { assert_eq "none 0" "$(printf '%s\n[agent_04: done]\n' "$T" | af-parse agent_03 "$T")" ""; }
test_body() {
  out=$(printf 'old\n> go %s\nline one\nline two\n[agent_03: done]\n> \n' "$T" | af-parse --body agent_03 "$T")
  assert_eq "$(printf 'line one\nline two')" "$out" "body"
}
```

- [x] **Step 2: Run** `bash tests/run.sh` → Expected: `test_parse` tests FAIL.
- [x] **Step 3: Implement `utils/af-parse`** with `awk` (fixed-string tag match via `index()`, not regex, since the tag holds `(`).
- [x] **Step 4: Run** `bash tests/run.sh` → Expected: all PASS.
- [x] **Step 5: Commit** `git commit -m "feat: add af-parse marker parser"`

---

### Task 3: Fake adapter and `utils/af-spawn`

**Files:**
- Create: `tests/fake_adapter/{launch.sh,ready.sh,fake_agent.sh}`, `utils/af-spawn`, `tests/test_spawn.sh`

**Interfaces:**
- Adapter contract (both `adapters/claude` and `tests/fake_adapter`):
  - `launch.sh ROLE NAME SESSION_ID MODE` → prints one shell command line to run in the tmux pane. `ROLE` ∈ `leader|worker`, `MODE` ∈ `new|resume`. Prompt file = `$AF_ROOT/prompts/$ROLE.md`.
  - `ready.sh < screen` → exit 0 when the agent is ready for input.
- Fake agent: prints `FAKE READY`, then reads stdin lines (strip `\e[200~`/`\e[201~`). Collects lines until a line contains `(task `. Then: if collected text contains `PLEASE_FAIL` print `[NAME: failed]`; `PLEASE_BLOCK` → print `Question: which one?` then `[NAME: blocked]`; `PLEASE_SLOW` → print `[NAME: working]`, sleep 3, then `slow ok` and `[NAME: done]`; else print `result: ok` and `[NAME: done]`. Name from `$AF_AGENT`.
- Produces: `af-spawn [--dir PATH]` → creates the next worker, prints its name (`agent_NN`) on stdout, exit 0. Default `PATH` = current folder.
  - In a git repo: `git -C PATH rev-parse --show-toplevel` → repo; worktree at `$AF_HOME/worktrees/<repo-basename>-<first 8 chars of cksum of repo path>/agent_NN`; `git worktree add -b BRANCH WT HEAD`. Branch `agent_force/agent_NN`, suffix `-2`, `-3`… if it exists.
  - Not a git repo: `cwd = PATH`, no worktree, empty `branch`/`worktree`.
  - meta keys: `name number type role cwd repo worktree branch session_id created closed last_tag tasks blocked_count`. `type=claude` (from adapter folder basename), `role=worker`, `tasks=0`, `closed=false`.
  - tmux: `af_tmux new-session -d -s NAME -c CWD -e AF_AGENT=NAME -e AF_HOME=… -e AF_SOCKET=… "<launch cmd>"`; status `starting`.
  - Wait: capture pane every 0.5 s, pipe to `ready.sh`; on success status `idle`; after `${AF_READY_TIMEOUT:-60}` s → status `dead`, `af_die "agent_NN did not become ready"`.

- [x] **Step 1: Write fake adapter and failing `tests/test_spawn.sh`**

```bash
mkrepo() { git init -q "$1"; git -C "$1" commit -q --allow-empty -m init; }
test_spawn_git_repo() {
  mkrepo "$AF_TMP/repo"; n=$(cd "$AF_TMP/repo" && af-spawn)
  assert_eq agent_02 "$n" "name"
  assert_eq idle "$(af_status_get agent_02)" "ready"
  assert_eq "agent_force/agent_02" "$(af_meta_get agent_02 branch)" "branch"
  wt=$(af_meta_get agent_02 worktree); assert_eq "$wt" "$(af_meta_get agent_02 cwd)" "cwd=worktree"
  assert_eq "agent_force/agent_02" "$(git -C "$wt" branch --show-current)" "wt branch"
  af_alive agent_02
}
test_spawn_second_worker()  { mkrepo "$AF_TMP/repo"; cd "$AF_TMP/repo"; af-spawn >/dev/null; assert_eq agent_03 "$(af-spawn)" "second"; }
test_spawn_branch_taken()   { mkrepo "$AF_TMP/repo"; git -C "$AF_TMP/repo" branch agent_force/agent_02; (cd "$AF_TMP/repo" && af-spawn >/dev/null)
                              assert_eq "agent_force/agent_02-2" "$(af_meta_get agent_02 branch)" "suffix"; }
test_spawn_non_git()        { mkdir "$AF_TMP/plain"; (cd "$AF_TMP/plain" && af-spawn >/dev/null)
                              assert_eq "$AF_TMP/plain" "$(af_meta_get agent_02 cwd)" "cwd"; assert_eq "" "$(af_meta_get agent_02 branch)" "no branch"; }
test_spawn_dir_flag()       { mkrepo "$AF_TMP/other"; af-spawn --dir "$AF_TMP/other" >/dev/null; assert_eq "$AF_TMP/other" "$(af_meta_get agent_02 repo)" "repo"; }
test_spawn_path_with_space(){ mkrepo "$AF_TMP/my repo"; (cd "$AF_TMP/my repo" && af-spawn >/dev/null); assert_eq idle "$(af_status_get agent_02)" "space"; }
test_spawn_ready_timeout()  { mkdir "$AF_TMP/p"; AF_READY_TIMEOUT=2 AF_ADAPTER_DIR="$AF_TMP/never" ; mkdir -p "$AF_TMP/never"
                              printf '#!/usr/bin/env bash\necho "sleep 100"\n' > "$AF_TMP/never/launch.sh"; printf '#!/usr/bin/env bash\nexit 1\n' > "$AF_TMP/never/ready.sh"; chmod +x "$AF_TMP/never/"*.sh
                              export AF_READY_TIMEOUT AF_ADAPTER_DIR; assert_fail af-spawn --dir "$AF_TMP/p"; assert_eq dead "$(af_status_get agent_02)" "dead"; }
```

(`AF_TMP` is the temp dir from `af_test_setup`.)

- [x] **Step 2: Run** `bash tests/run.sh` → Expected: `test_spawn` FAIL.
- [x] **Step 3: Implement `utils/af-spawn`.**
- [x] **Step 4: Run** `bash tests/run.sh` → Expected: all PASS.
- [x] **Step 5: Commit** `git commit -m "feat: add af-spawn and fake adapter"`

---

### Task 4: `utils/af-send`

**Files:**
- Create: `utils/af-send`, `tests/test_send.sh`

**Interfaces:**
- Consumes: `af-spawn`, `af-parse`, lib.
- Produces: `af-send [--force] AGENT [FILE]` (prompt from `FILE`, or stdin if absent or `-`). Exit codes: `0` sent; `1` error (unknown/closed/dead agent, empty prompt); `2` worker is `working` and no `--force`; `3` worker was `blocked` but the user already answered it in its pane.
- Steps inside:
  1. `TTT = tasks + 1` (3 digits). `TAG="(task NAME-TTT)"`.
  2. Full text = prompt + blank line + marker instruction (exact text below). Save to `agents/NAME/tasks/TTT.md`.
  3. If status `blocked`: capture screen with scrollback, `af-parse NAME last_tag`; if `COUNT > blocked_count` → print `NAME is no longer blocked (answered in its pane); not sent`, exit 3.
  4. `af_tmux load-buffer -b af_NAME FILE`, `paste-buffer -p -d -b af_NAME -t NAME`, sleep 0.3, `send-keys -t NAME -l " $TAG"`, sleep 0.3, `send-keys -t NAME Enter`. The tag is typed, not pasted, so it stays visible even when the paste is shown collapsed.
  5. meta `tasks=TTT`, `last_tag=TAG`, `last_task_title=<first non-empty prompt line, cut to 60 chars>`; status `working`. Print `NAME TAG`.
- Marker instruction (exact, `NAME` filled in):

```
At the very end of every answer, on its own line, write exactly one of:
[NAME: done] if you succeeded, [NAME: failed] if you failed,
[NAME: blocked] if you need input or cannot continue,
[NAME: working] if you are not finished yet.
```

- [x] **Step 1: Write failing `tests/test_send.sh`**

```bash
cap() { af_tmux capture-pane -p -J -S - -t "$1"; }
spawn() { mkdir -p "$AF_TMP/p"; af-spawn --dir "$AF_TMP/p" >/dev/null; }
test_send_basic() {
  spawn; out=$(echo "do thing" | af-send 2)
  assert_eq "agent_02 (task agent_02-001)" "$out" "out"
  assert_eq working "$(af_status_get agent_02)" "status"
  assert_contains "$(cat "$AF_HOME/agents/agent_02/tasks/001.md")" "[agent_02: blocked] if you need input" "instruction saved"
  sleep 2; assert_eq "done 1" "$(cap agent_02 | af-parse agent_02 '(task agent_02-001)')" "fake answered"
}
test_send_refuses_when_working() { spawn; echo a | af-send 2 >/dev/null; set +e; echo b | af-send 2; rc=$?; set -e; assert_eq 2 "$rc" "busy"; }
test_send_force()                { spawn; echo a | af-send 2 >/dev/null; echo b | af-send --force 2 >/dev/null; assert_eq 2 "$(af_meta_get agent_02 tasks | sed 's/^0*//')" "two tasks"; }
test_send_long_prompt_tag_visible() {
  spawn; for i in $(seq 1 200); do echo "line $i"; done > "$AF_TMP/long.txt"
  af-send 2 "$AF_TMP/long.txt" >/dev/null; sleep 2
  assert_eq "done 1" "$(cap agent_02 | af-parse agent_02 '(task agent_02-001)')" "long prompt"
}
test_send_unknown_agent() { assert_fail sh -c 'echo x | af-send 7'; }
test_send_blocked_answered_in_pane() {
  spawn; echo PLEASE_BLOCK | af-send 2 >/dev/null; sleep 2
  af_status_set agent_02 blocked; af_meta_set agent_02 blocked_count 1
  af_tmux send-keys -t agent_02 -l "fine (task agent_02-001)"; af_tmux send-keys -t agent_02 Enter; sleep 2
  set +e; echo answer | af-send 2; rc=$?; set -e; assert_eq 3 "$rc" "answered directly"
}
```

- [x] **Step 2: Run** → Expected: `test_send` FAIL.
- [x] **Step 3: Implement `utils/af-send`.**
- [x] **Step 4: Run** `bash tests/run.sh` → Expected: all PASS.
- [x] **Step 5: Commit** `git commit -m "feat: add af-send"`

---

### Task 5: `af-watch`, `af-read`, `af-status`, `af-close`

**Files:**
- Create: `utils/af-watch`, `utils/af-read`, `utils/af-status`, `utils/af-close`, `tests/test_watch.sh`

**Interfaces:**
- Consumes: `af-parse`, `af-send`, lib.
- `af-watch AGENT` — reads `last_tag` once at start. Loop every `AF_POLL_INTERVAL` s:
  - session gone → status `dead`, print `NAME dead`, exit 0.
  - `last_tag` in meta changed (newer send) → print `NAME superseded`, exit 0.
  - parse (capture with `-J -S -`): `done|failed|blocked` → write status, write `af-parse --body` to `last_response.md`, set `blocked_count` = COUNT, print `NAME STATE TAG`, exit 0. `none|working|notag` → keep polling.
- `af-read AGENT` — if session alive and `last_tag` set: print `af-parse --body` from a fresh capture if non-empty; else print `last_response.md`; else print nothing.
- `af-status [--all]` — one line per agent (workers; `--all` also `agent_01` first), sorted by name, tab-separated: `NAME ROLE STATUS FOLDER BRANCH TITLE`. For a worker whose session is gone and status not `closed` → shows and saves `dead`. For a live worker with status `working` → parse screen once and update status/last_response the same way `af-watch` does (shared function `af_check NAME` in `lib.sh`).
- `af-close AGENT` — kill its tmux session, status `closed`, meta `closed=true`. Keep worktree and state. Print `NAME closed`.

- [x] **Step 1: Write failing `tests/test_watch.sh`**

```bash
spawn() { mkdir -p "$AF_TMP/p"; af-spawn --dir "$AF_TMP/p" >/dev/null; }
test_watch_done()    { spawn; echo hi | af-send 2 >/dev/null; out=$(af-watch 2)
                       assert_eq "agent_02 done (task agent_02-001)" "$out" "watch"; assert_eq done "$(af_status_get agent_02)" "status"
                       assert_contains "$(cat "$AF_HOME/agents/agent_02/last_response.md")" "result: ok" "response"; }
test_watch_failed()  { spawn; echo PLEASE_FAIL  | af-send 2 >/dev/null; assert_contains "$(af-watch 2)" "failed" "failed"; }
test_watch_blocked() { spawn; echo PLEASE_BLOCK | af-send 2 >/dev/null; af-watch 2 >/dev/null
                       assert_eq blocked "$(af_status_get agent_02)" "blocked"; assert_contains "$(af-read 2)" "Question: which one?" "question"; }
test_watch_ignores_working() { spawn; echo PLEASE_SLOW | af-send 2 >/dev/null; out=$(af-watch 2); assert_contains "$out" "done" "waited past working"; }
test_watch_dead_session()    { spawn; echo PLEASE_SLOW | af-send 2 >/dev/null; af_tmux kill-session -t agent_02
                               assert_eq "agent_02 dead" "$(af-watch 2)" "dead"; }
test_watch_two_workers()     { spawn; spawn; echo a | af-send 2 >/dev/null; echo PLEASE_FAIL | af-send 3 >/dev/null
                               af-watch 2 >/dev/null; af-watch 3 >/dev/null
                               assert_eq done "$(af_status_get agent_02)" "w2"; assert_eq failed "$(af_status_get agent_03)" "w3 not mixed up"; }
test_status_lists()          { spawn; s=$(af-status); assert_contains "$s" "agent_02" "listed"; assert_contains "$s" "idle" "idle"; }
test_status_updates_working(){ spawn; echo hi | af-send 2 >/dev/null; sleep 2; assert_contains "$(af-status)" "done" "status parses screen"; }
test_close()                 { spawn; af-close 2 >/dev/null; assert_eq closed "$(af_status_get agent_02)" "closed"
                               ! af_alive agent_02; test -d "$(af_meta_get agent_02 cwd)"; }
```

- [x] **Step 2: Run** → Expected: `test_watch` FAIL.
- [x] **Step 3: Implement the four scripts and `af_check NAME` in `lib.sh`.**
- [x] **Step 4: Run** `bash tests/run.sh` → Expected: all PASS.
- [x] **Step 5: Commit** `git commit -m "feat: add af-watch, af-read, af-status, af-close"`

---

### Task 6: `agent_force` CLI

**Files:**
- Create: `agent_force`, `tests/test_cli.sh`

**Interfaces:**
- Consumes: lib, adapter contract, `af-status`.
- `agent_force start`:
  1. `af_alive agent_01` → die `leader agent_01 already runs; use 'agent_force stop' first`.
  2. If `agents/` exists → `mv` to `archive/<YYYYmmdd-HHMMSS>/`.
  3. meta for `agent_01`: `role=leader`, `cwd=$PWD`, new `session_id`.
  4. `af_tmux new-session -d -s agent_01 -c "$PWD" -e PATH="$AF_ROOT/utils:$PATH" -e AF_AGENT=agent_01 -e AF_HOME=… -e AF_SOCKET=… "<launch.sh leader agent_01 ID new>"`. Wait ready like `af-spawn` (reuse a lib function `af_wait_ready NAME`, moved from `af-spawn` in this task). Status `idle`.
  5. Print `agent_01 started. Connect: agent_force connect 1`.
- `agent_force start --latest`:
  1. Fail if `agent_01` alive, or no `agents/agent_01/meta.json` (`no saved session; run 'agent_force start'`).
  2. Relaunch `agent_01` in its saved `cwd` with `launch.sh leader agent_01 ID resume`.
  3. For each worker with `closed=false`: relaunch in saved `cwd` with `launch.sh worker NAME ID resume`, wait ready, status `idle` (a worker that does not become ready → `dead`, keep going).
  4. Print one line per relaunched agent.
- `agent_force stop` — `af_tmux kill-server` (no error if no server). Keep all files. Print `stopped`.
- `agent_force list` — `af-status --all`; if empty print `no agents`.
- `agent_force connect N` — `name=$(af_name N)`; not alive → die `NAME is not running`. Else `TMUX= af_tmux attach -t NAME` (`exec`). Print once before attach: `Detach: Ctrl-b d`.
- No args / unknown command → usage text, exit 1.

- [x] **Step 1: Write failing `tests/test_cli.sh`**

```bash
af() { "$REPO/agent_force" "$@"; }   # REPO set by helpers.sh
test_start_creates_leader() { cd "$AF_TMP"; af start >/dev/null; af_alive agent_01; assert_eq leader "$(af_meta_get agent_01 role)" "role"; }
test_start_twice_fails()    { cd "$AF_TMP"; af start >/dev/null; assert_fail af start; }
test_start_archives_old()   { cd "$AF_TMP"; af start >/dev/null; af stop >/dev/null; af start >/dev/null
                              assert_eq 1 "$(ls "$AF_HOME/archive" | wc -l | tr -d ' ')" "archived"; }
test_start_path_with_space(){ mkdir "$AF_TMP/a b"; cd "$AF_TMP/a b"; af start >/dev/null; assert_eq "$AF_TMP/a b" "$(af_meta_get agent_01 cwd)" "cwd"; }
test_stop_keeps_state()     { cd "$AF_TMP"; af start >/dev/null; af-spawn >/dev/null; af stop >/dev/null
                              ! af_alive agent_01; test -f "$AF_HOME/agents/agent_02/meta.json"; }
test_latest_resumes()       { cd "$AF_TMP"; af start >/dev/null; af-spawn >/dev/null; af-spawn >/dev/null; af-close 3 >/dev/null
                              id=$(af_meta_get agent_01 session_id); af stop >/dev/null; af start --latest >/dev/null
                              af_alive agent_01; af_alive agent_02; ! af_alive agent_03; assert_eq "$id" "$(af_meta_get agent_01 session_id)" "same id"; }
test_latest_without_state() { assert_fail af start --latest; }
test_list()                 { cd "$AF_TMP"; af start >/dev/null; af-spawn >/dev/null; s=$(af list); assert_contains "$s" agent_01 l; assert_contains "$s" agent_02 w; }
test_connect_missing()      { assert_fail af connect 4; }
test_usage()                { assert_fail af; assert_fail af bogus; }
```

The fake adapter's `launch.sh` must echo `MODE` into the screen (`FAKE READY resume`) so `test_latest_resumes` can also assert `assert_contains "$(af_tmux capture-pane -p -t agent_02)" "resume"`. Add that assertion.

- [x] **Step 2: Run** → Expected: `test_cli` FAIL.
- [x] **Step 3: Implement `agent_force`; move ready-wait into `af_wait_ready NAME` in `lib.sh` and use it from `af-spawn`.**
- [x] **Step 4: Run** `bash tests/run.sh` → Expected: all PASS (including earlier tasks).
- [x] **Step 5: Commit** `git commit -m "feat: add agent_force CLI"`

---

### Task 7: Claude adapter, role prompts, README, live smoke test

**Files:**
- Create: `adapters/claude/launch.sh`, `adapters/claude/ready.sh`, `prompts/leader.md`, `prompts/worker.md`
- Modify: `README.md`

**Interfaces:**
- `adapters/claude/launch.sh ROLE NAME ID MODE` prints (values shell-quoted with `printf %q`):
  - `new`: `claude --dangerously-skip-permissions --session-id ID --append-system-prompt "$(cat prompts/ROLE.md)"`
  - `resume`: same but `--resume ID` instead of `--session-id ID`.
  - Before printing, replace `{{NAME}}` in the prompt text with `NAME`.
- `adapters/claude/ready.sh < screen` — exit 0 when the Claude Code input box is shown. Pick the exact pattern in Step 1 from a real capture; also handle any first-run dialog seen there (for example the bypass-permissions confirmation) by documenting it in the README, not by auto-accepting.

`prompts/leader.md` must cover, in this order (spec 6.8):
1. You are `agent_01`, the agent_force leader; the user talks only to you.
2. For each ask: new worker (`af-spawn [--dir PATH]`) or existing one (user may name `agent_NN`). If unsure which worker, ask.
3. Rewrite the ask into a clear task prompt: goal, context, constraints, what "done" means, what to report. Keep the user's meaning; add no scope. If the ask is unclear in a way that changes the work, ask the user first.
4. Send with `af-send AGENT FILE` (write the prompt to a temp file first). Then start `af-watch AGENT` as a background Bash command (`run_in_background`). Tell the user in one line which worker got the task. Then stop; do not wait.
5. When an `af-watch` finishes: run `af-read AGENT`, report worker, task title, outcome, and the response (full; or short summary plus full text if very long). For `blocked`, show the question and ask the user. Send the answer with `af-send`; on exit code 3, tell the user the worker was already answered in its pane. For `dead`, tell the user.
6. Do not report turns you did not send.
7. Never commit, merge, push, or delete a worktree, and never `af-close`, unless the user says so.
8. On start or resume: run `af-status` and report anything finished, blocked, or dead.
9. Helper reference: one line per `af-*` command with its arguments and exit codes.

`prompts/worker.md` (spec 6.9): you are `{{NAME}}`, a worker in agent_force; tasks come from the leader; work only in your current folder; do not commit, push, or merge unless the task says so; end each answer with a short report (what you did, where, what is left), then exactly one status marker on its own line as the task instruction says; use `blocked` only when you cannot reasonably continue, with the question clearly stated above the marker.

`README.md`: dependencies, install (`ln -s "$PWD/agent_force" ~/.local/bin/agent_force` or run from repo root), the five CLI commands, how to detach (`Ctrl-b d`), where state and worktrees live, env vars (`AGENT_FORCE_HOME`, `AF_SOCKET`, `AF_POLL_INTERVAL`), the one-time Claude first-run note found in Step 1.

- [x] **Step 1: Capture real Claude screens.** In a scratch folder: `tmux -L af_probe new-session -d -s p "claude --dangerously-skip-permissions"`; wait; `tmux -L af_probe capture-pane -p -t p`. Record: the ready pattern, any first-run dialog, and how a 50-line paste via `paste-buffer -p` plus typed ` (task agent_09-001)` shows before and after Enter. Confirm the tag line stays visible and that an answer ending with `[agent_09: done]` parses with `af-parse`. Kill the probe server.
- [x] **Step 2: Write `adapters/claude/launch.sh`, `ready.sh`, the two prompts, and README** per above and Step 1 findings. If Step 1 shows the tag is not visible, stop and report back before changing the send method.
- [x] **Step 3: Live smoke test** (real Claude, `AF_POLL_INTERVAL=10`, temp `AGENT_FORCE_HOME`, scratch git repo):
  1. `agent_force start` → `agent_force list` shows `agent_01 idle`.
  2. In the leader (`tmux -L agent_force send-keys`), ask: "create a file hello.txt with the word hi". Expected: leader runs `af-spawn`, `af-send`, background `af-watch`, returns at once; within ~1 minute the leader pane reports `agent_02 done` with the worker's response; `hello.txt` exists in agent_02's worktree, not in the scratch repo; no commit made.
  3. Ask a follow-up for `agent_02`. Expected: same worker gets it.
  4. `agent_force stop`, `agent_force start --latest` → `agent_force list` shows `agent_01` and `agent_02` alive.
  5. `agent_force stop`.
  Record results in the commit message.
- [x] **Step 4: Run** `bash tests/run.sh` → Expected: all PASS.
- [x] **Step 5: Commit** `git commit -m "feat: add Claude adapter, role prompts, README"`

---

## As-built changes

This section records where the build differs from the tasks above. The tasks keep their original text.

**Result:** 7 tasks done, 103 tests pass. The live smoke test with real Claude (Task 7, Step 3) passed steps 1–5.

### Changes made during the tasks

1. **Task 1** (`3299288`): `tests/run.sh` ran each test inside `if ( … )`, which turns off `set -e`, so a failed assert still passed. The runner now runs the test outside the `if` and checks `rc=$?`. A fixture covers it.
2. **Task 3:** `af_wait_ready NAME` lives in `utils/lib.sh` from the start, not in `af-spawn` (it was to move there in Task 6).
3. **Task 3:** meta `type` is the adapter folder name (`claude`, or `fake_adapter` in tests).
4. **Task 3:** tmux pane targets use `=NAME:` (with the colon). `ready.sh` does not use `grep -q` on a pipe (it breaks under `pipefail`).
5. **Task 4:** `test_send_blocked_answered_in_pane` types an untagged answer. The planned test typed the tag again, and `af-parse` counts only lines below the last tag, so that test could not pass.
6. **Task 6:** a fresh `agent_force start` kills the whole tmux server, also live workers. Worktrees and archived state stay.
7. **Task 7** (`6b527d7`): tmux ignores `new-session -e PATH`. `af_launch` puts `utils/` on `PATH` for the tmux call itself, so the leader finds `af-*`.
8. **Task 7** (`7e1c8a2`): the launch command runs as `bash -c "$cmd"` (argv), not through the user's default shell. `$'…'` quoting broke under dash and fish.

### Changes from the final review (`2245944`, `825beb2`, `4cb0ae7`)

1. **Worktree reuse:** after a fresh start, `af-spawn` in a repo used before failed on the old path. The worktree path and the branch now take the same suffix (`agent_02-2`, `agent_02-3`, …) until both are free. If `git worktree add` fails, the agent folder is removed.
2. **Resume keeps status:** `start --latest` reads each worker's old status before the relaunch. `working` becomes `interrupted`. `done`, `failed`, `blocked`, `interrupted` and `lost` stay.
3. **`stop` saves results:** `agent_force stop` runs `af-status` before `kill-server`, so a worker that finished but was not checked shows `done`, not `interrupted`.
4. **`af-watch` exit:** it exits on any status other than `working` and prints `NAME STATE TAG`. `dead` and `closed` print `NAME STATE`.
5. **Lost tag:** `af_launch` sets `history-limit 100000` before the first pane. New `af_tag_seen NAME TAG`. After `AF_LOST_POLLS` (default 10) polls in a row without the tag, `af-watch` sets `lost` and prints `NAME lost TAG`.
6. **New status words:** `interrupted` and `lost` (in addition to the plan's list).
7. **Leader status:** `af-status` runs `af_check` for the leader too, so a stopped leader shows `dead`.
8. **Ready wait:** `af_wait_ready` returns at once when the session is gone, and kills the session on timeout.
9. **Fresh start output:** `start` prints `killed session NAME` for each live session.
10. **Docs:** `prompts/leader.md` covers `closed`, `interrupted` and `lost`. README has a "Status words" section. `docs/.DS_Store` is no longer tracked.

### Change after the final review (`9996f60`)

1. **Status after `stop` → `list` → `start --latest`:** once sessions are gone, `af_check` writes `dead` over the saved status, so workers came back `idle`. `af_check` now saves the old status as meta `prev_status` before it writes `dead`. `start --latest` uses `prev_status` when the status is `dead`. `list` still shows `dead` after `stop`.
2. Tests: `test_latest_after_list`, `test_latest_after_two_stops`.

### Changes requested by the user after v1

1. **Worktree only for code work:** `af-spawn` makes a worktree only with the new `--worktree` flag (error if the target is not in a git repo). Without it, the worker runs in the target folder, also inside a git repo. `prompts/leader.md` tells the leader to pass `--worktree` for tasks that write code or work on git or GitHub, and not to give code tasks to a worker without a worktree. `prompts/worker.md`: a folder that is not the worker's worktree belongs to the user. Tests: `test_spawn_repo_no_worktree`, `test_spawn_worktree_needs_repo`; the worktree tests now pass `--worktree`.
2. **Marker rules in the system prompt:** `af-send` no longer appends the status-marker instruction to each task. The task file holds the task as sent; `af-send` still types the task tag. The rules are in `prompts/worker.md`, which also says not to repeat the tag. Tests: `test_send_basic` checks the task file, `test_worker_prompt_has_markers`.
3. **Worktree wording:** `prompts/leader.md` says to choose by what the task does, not by the folder. A research task in a git repo gets no worktree.
4. **Overview table:** when the user asks how many workers or sessions run or ran, the leader runs `af-status --all` and answers with a table: Agent, Status, Worktree (absolute path, empty if none), Focus (fewer than 30 words, from the tasks it sent), plus a count line. Rule 9 in `prompts/leader.md`.
5. **`list` shows live agents only:** `agent_force list` hides agents with no tmux session (closed, dead, and all after `stop`) and prints `no live agents` when none run. `af-status --all` (used by the leader) still lists every agent. Tests: `test_list_after_stop`, `test_list_hides_closed`, `test_list_hides_dead` (replaces `test_list_leader_dead`).

### Known gaps (not fixed)

1. A task prompt that starts with `#`, `/` or `!` may switch Claude's input mode. Not checked with real Claude.
2. `af-spawn --dir repo/sub` starts the worker at the worktree root, not in `sub`.
3. A `lost` worker stays `lost` if it finishes later.
4. A restored `blocked` worker keeps its old `blocked_count`.
