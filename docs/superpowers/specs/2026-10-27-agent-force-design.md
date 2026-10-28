# agent_force — Design

Date: 2026-10-27
Status: Approved

## 1. Intent

The user wants to talk to one agent only: the **leader**. The leader hands
work (coding, investigation, research) to **worker** agents. Each worker runs
in its own tmux session. The user's chat with the leader never blocks while
workers run. Workers stay alive for follow-up tasks.

Why: the user wants several pieces of work to run in parallel, driven by short
asks, without managing each agent session by hand. The user still wants to
look into any agent session directly when needed (attach and detach).

## 2. Goals

1. One leader agent, `agent_01`, for the whole machine.
2. The leader starts workers `agent_02`, `agent_03`, … on request.
3. The leader rewrites the user's short ask into a clear, detailed prompt
   before it sends the prompt to a worker.
4. Dispatch is non-blocking. The leader returns to the user at once.
5. The leader watches workers in the background. When a worker finishes, the
   leader tells the user and passes on the worker's response.
6. Workers stay alive after a task. The user can send follow-up tasks to an
   existing worker by number ("send this to agent_03").
7. Many workers can run at the same time.
8. When a worker asks a question, the leader shows it to the user and sends
   the user's answer back to that worker.
9. The user can attach to and detach from any session (leader or worker).
10. Claude Code is the only agent type now. The design keeps a clear seam so
    Codex, pi, and others can be added later, both as leader and as worker.

## 3. Non-goals

1. No separate program or daemon. The leader is an agent session itself.
2. No more than one leader per machine.
3. No automatic commit, merge, push, or PR. Changes stay in the worktree until
   the user tells the leader what to do.
4. No worker-to-worker communication. All traffic goes through the leader.
5. No Codex / pi support in this version (only the seam for it).
6. No web UI or dashboard.

## 4. Anti-goals (failure even if the code works)

1. The leader blocks the user's chat while a worker runs.
2. The leader misses a finished worker, or reports it late.
3. The leader mixes up workers (for example, sends a follow-up to the wrong one).
4. The leader's rewritten prompt changes what the user meant.
5. A worker's question sits unseen for a long time.
6. Work is lost when the user stops or restarts sessions.

## 5. Decisions made with the user

1. **Naming.** All agents are `agent_NN`, two digits, starting at `agent_01`.
   The leader is always `agent_01`. Workers are `agent_02`, `agent_03`, …
   The tmux session name equals the agent name.
2. **Leader runs in tmux too**, so the user can always reattach to it.
3. **Private tmux socket.** All agent_force sessions live on a non-default
   tmux socket (`tmux -L agent_force`), so they are easy to find and do not
   mix with the user's own tmux sessions.
4. **Worker launch.** Each worker starts as
   `claude --dangerously-skip-permissions` (plus the role prompt, below).
5. **Git worktrees.** Each coding worker works in its own git worktree, so
   workers never conflict.
6. **After a coding task**, changes stay in the worktree. The leader waits for
   the user's instruction (commit, merge, PR, discard, …).
7. **Worker questions** go to the user through the leader; the answer goes back
   to the same worker.
8. **Workers stay alive** until the user tells the leader to close them.
9. **Role prompts.** The project has a `prompts/` folder:
   - `prompts/leader.md` — role and character of the leader.
   - `prompts/worker.md` — role and character of a worker.
   These files are passed to the leader and to each worker at launch.
10. **Leader behavior = role prompt + helper scripts.** The leader is a normal
    Claude Code session. `prompts/leader.md` tells it how to do the job. Small
    helper scripts do the mechanical work (spawn, send, status, read), so the
    leader does not type raw tmux commands.
11. **Leader permissions.** The leader also runs with
    `--dangerously-skip-permissions`, so it never stops at a permission prompt.
12. **Fresh start vs resume.** `agent_force start` always starts from scratch.
    `agent_force start --latest` resumes the last leader session.
13. **Turns the leader did not send are ignored.** If the user types into a
    worker's pane directly, the leader does not report that turn.
14. **Leader pane only.** Results and questions show only in the leader's
    pane. No OS notifications. Everything stays OS-agnostic (macOS and Linux).
15. **Status comes from the screen, not hooks.** Every task prompt the leader
    sends ends with an instruction: append one status marker at the end of each
    answer. The leader reads the worker's screen with `tmux capture-pane` and
    parses the marker. After each send, a background loop captures the
    worker's screen every 30 seconds. Markers:

    | Outcome | Marker |
    |---|---|
    | Success | `[agent_NN: done]` |
    | Failed | `[agent_NN: failed]` |
    | Blocked (needs input or cannot continue) | `[agent_NN: blocked]` |
    | Still working, not finished | `[agent_NN: working]` |

    My call: the user wrote `workerXX`; this design uses the agent name
    (`[agent_03: done]`), to match the naming in item 1.
16. **User CLI `agent_force`** with these commands:

    | Command | Effect |
    |---|---|
    | `agent_force start` | Start a fresh leader `agent_01` in a detached tmux session. Do not attach. |
    | `agent_force start --latest` | Resume the last leader session (and its workers) instead of a fresh start. |
    | `agent_force stop` | Kill the leader and all workers. |
    | `agent_force list` | List all sessions (leader and workers). |
    | `agent_force connect 1` | Attach to the leader's tmux session. |
    | `agent_force connect N` | Attach to worker `agent_0N` (N = 2, 3, …). |

## 6. Design (my calls — the user can override any of these)

### 6.1 Layout of this repo

```
agent_force/
  agent_force            # user CLI (Bash), at the repo root
  utils/
    af-spawn             # leader helper: create a new worker
    af-send              # leader helper: send a task / answer to a worker
    af-status            # leader helper: show status of all workers
    af-read              # leader helper: print a worker's last response
    af-watch             # leader helper: poll one worker every 30 s until it ends
    af-close             # leader helper: close a worker (keep its worktree)
  adapters/
    claude/              # everything specific to Claude Code
      launch.sh          # build the launch command for leader / worker
      ready.sh           # tell from the screen that Claude is ready for input
  prompts/
    leader.md
    worker.md
  docs/superpowers/specs/…
```

Scripts are Bash. Dependencies: `tmux`, `git`, `claude`, `jq`.
The user runs `agent_force` from the repo root, or links it into a folder on
`PATH` (the README says how). `agent_force` must find `utils/`, `adapters/`,
and `prompts/` from its own real path, so a symlink works.

### 6.2 State on disk

State lives in `~/.agent_force/` (overridable with `AGENT_FORCE_HOME`):

```
~/.agent_force/
  agents/
    agent_02/
      meta.json          # number, type (claude), role, repo path, worktree path,
                         # branch, cwd, created time, closed flag,
                         # claude session id (for --latest resume)
      status             # one word: starting | idle | working | done |
                         # failed | blocked | closed
      last_response.md   # the worker's last full response
      tasks/             # every prompt sent, numbered: 001.md, 002.md, …
    agent_01/             # the leader: meta.json with its claude session id
  archive/<timestamp>/   # old agents/ folders, moved here by a fresh start
  worktrees/             # default place for worker worktrees (see 6.4)
```

State on disk is the source of truth. A leader that restarts reads it and
continues. `agent_force list` and `af-status` read it too, and cross-check it
with the live tmux sessions (a session that is gone shows as `dead`).

### 6.3 Starting the leader

`agent_force start` (fresh):

1. Fails with a clear message if `agent_01` already runs on the socket.
   (The user runs `agent_force stop` first.)
2. Moves the old `agents/` folder to `archive/<timestamp>/`. Worktrees and
   branches are not touched. Numbering starts again at `agent_02`.
3. Creates tmux session `agent_01` on socket `agent_force`, detached, in the
   folder where the command ran.
4. Starts `claude --dangerously-skip-permissions` with `prompts/leader.md`
   appended to its system prompt (`--append-system-prompt`), with
   `utils/` on its `PATH`. The launch passes a new UUID with
   `--session-id <uuid>` and saves it in `agents/agent_01/meta.json`, so
   `--latest` can resume it. No hooks are needed.
5. Prints how to connect (`agent_force connect 1`).

`agent_force start --latest` (resume):

1. Fails if `agent_01` already runs, or if there is no saved state.
2. Keeps `agents/` as it is.
3. Relaunches the leader in its saved folder with
   `claude --resume <saved session id>` plus the same flags as above.
4. My call (the user said "resume from the last leader session" and did not
   mention workers): also relaunches each worker that was not closed, in its
   saved folder, with `claude --resume <its session id>`. Reason: the resumed
   leader remembers those workers and expects them to exist.
5. The resumed leader runs `af-status` first and reports any state it finds.

### 6.4 Spawning a worker (`af-spawn`)

1. Picks the next free number (highest number in `agents/` plus one; numbers
   are not reused while old state exists).
2. Decides where the worker works:
   - If the target folder is in a git repo: create a worktree on a new branch
     named `agent_force/agent_NN`, from the repo's current `HEAD`. If that
     branch name exists, add a suffix. Never touch an existing branch.
   - Otherwise: the worker runs in the target folder with no worktree.
   - The target folder defaults to the leader's folder. The leader can pass a
     different repo path if the user names one.
3. Creates tmux session `agent_NN`, starts
   `claude --dangerously-skip-permissions --append-system-prompt <worker.md>
   --session-id <new uuid>`, and saves the UUID in `meta.json`.
4. Waits until `adapters/claude/ready.sh` sees on the screen that Claude is
   ready for input (with a timeout), sets `status = idle`, then returns.
   It does not send a task; `af-send` does that.

### 6.5 Knowing a worker's state (screen + markers)

The leader learns a worker's state only from the worker's screen:

```
tmux -L agent_force capture-pane -p -t agent_NN
```

**The marker instruction.** `af-send` appends this to every task prompt (the
leader does not have to remember it):

> At the very end of every answer, on its own line, write exactly one of:
> `[agent_NN: done]` if you succeeded, `[agent_NN: failed]` if you failed,
> `[agent_NN: blocked]` if you need input or cannot continue,
> `[agent_NN: working]` if you are not finished yet.

**Parsing rules (my calls).**
1. Only a marker that is alone on its line counts.
2. Only markers that appear *below* the end of the last sent prompt count.
   Reason: the sent prompt itself shows all four markers on the screen, and
   older answers above it show old markers. `af-send` records a short unique
   tag line at the end of each prompt (for example `(task agent_03-004)`), and
   the parser only looks below the last line that shows that tag.
3. The last valid marker wins.
4. `capture-pane -p` shows only the visible screen. To read a full long
   answer, `af-read` adds scrollback (`-S -` or a large negative number) and
   cuts out the text between the task tag and the marker.
5. The builder must check how Claude Code's screen draws long prompts and
   answers (for example, a pasted prompt may show collapsed as
   "[Pasted text …]"), and pick the tag method that survives that.

### 6.6 Sending a task (`af-send N <file-or-stdin>`)

1. Saves the prompt (with the marker instruction and task tag added) to
   `tasks/NNN.md`.
2. Sets `status = working`.
3. Sends the full text to the worker's tmux pane in a way that works for long,
   multi-line text (for example, `tmux load-buffer` + `paste-buffer -p`, then
   Enter). Plain `send-keys` of a long prompt is not reliable.
4. Refuses to send if the worker is `working`, unless `--force` is given.
5. Answers to a blocked worker go through `af-send` too, so they also get the
   marker instruction and a new tag.

### 6.7 Non-blocking watch (`af-watch N`)

Right after each `af-send`, the leader starts `af-watch N` as a **background**
Bash command. One watch per in-flight task.

1. Every 30 seconds, `af-watch` captures the worker's screen and parses it.
2. `working` marker, or no marker yet: keep polling.
3. `done`, `failed`, or `blocked`: write `status` and `last_response.md`,
   print the worker name and outcome, and exit.
4. If the tmux session is gone: write `status = dead` and exit.
5. When `af-watch` exits, Claude Code wakes the leader. The leader then:
   - runs `af-read N` and tells the user which worker, what task, the outcome,
     and the worker's response (full, or a short summary plus the full text
     if long);
   - for `blocked`, shows the worker's question and asks the user for an
     answer, then sends it with `af-send` and starts a new `af-watch`.

**Turns the leader did not send.** The leader only watches after its own
`af-send`, so turns the user types in a worker's pane are not reported.
My call: if the user answers a blocked worker directly in its pane, the leader
does not detect it. Before the leader sends an answer to a blocked worker, it
captures the screen once more; if the worker is no longer blocked, it tells
the user and does not send.

If the leader restarts (`--latest`), it runs `af-status`, which parses every
worker's screen once, and reports anything that finished while it was away.

### 6.8 Leader role (`prompts/leader.md`) — content outline

1. You are `agent_01`, the leader of agent_force. The user talks only to you.
2. For each ask, decide: new worker or existing worker (the user may name one).
3. Rewrite the ask into a clear task prompt: goal, context, constraints, what
   "done" means, what to report. Keep the user's meaning; do not add scope.
   If the ask is unclear in a way that changes the work, ask the user first.
4. Tell the user which worker got the task, in one line, then stop. Do not wait.
5. Start one background `af-watch` after every `af-send`.
6. Report results and questions as in 6.7.
7. Never commit, merge, push, or delete a worktree unless the user says so.
8. Never close a worker unless the user says so.

### 6.9 Worker role (`prompts/worker.md`) — content outline

1. You are `agent_NN`, a worker in agent_force. Your tasks come from the leader.
2. Work only in your current folder (your worktree).
3. Do not commit, push, or merge unless the task says so.
4. End each turn with a short report: what you did, where, what is left.
5. Follow the marker instruction at the end of each task: end every answer
   with exactly one status marker on its own line. Use `blocked` only when you
   cannot reasonably continue, and state the question clearly above it.

### 6.10 The user CLI

- `start`, `start --latest` — as 6.3.
- `stop` — kill the whole tmux server on socket `agent_force`. Keep worktrees,
  state files, and saved session ids, so `start --latest` can resume. Do not
  mark agents `closed` (`closed` means the user closed that worker on purpose).
- `list` — table: name, role, status, folder/worktree, branch, last task title.
- `connect N` — attach to `agent_NN` on the socket. If the user is already
  inside tmux, attach must still work (for example, unset `TMUX` for the
  nested attach, or open it another way). Show how to detach (`Ctrl-b d`).

### 6.11 Seam for other agents

All Claude-specific parts live in `adapters/claude/`: the launch command, how
the role prompt is passed, how the session id is set and resumed, and how to
tell from the screen that the agent is ready. Status markers are plain text,
so they work for any agent. `meta.json` records the
agent type. A later `adapters/codex/` must provide the same three things. The
`utils/` scripts and the state files stay the same.

## 7. Left to the builder

1. Exact output format of `list` and `af-status`.
2. Exact text of `prompts/leader.md` and `prompts/worker.md` (follow 6.8, 6.9).
3. How `connect` handles nested tmux.
4. Tests: a fake agent (a small script that reads input and prints answers
   with markers) is a good way to test spawn / send / watch without real
   Claude.

## 8. Open questions for the user

None. All questions from the builder check are answered in section 5
(items 11–15) and in 6.3, 6.5–6.7.
