# agent_force

Talk to one Claude Code leader (`agent_01`). The leader gives your tasks to
Claude Code workers (`agent_02`, `agent_03`, ...), watches them in the
background, and reports their results and questions back to you. Every agent
runs in its own tmux session on a private tmux socket. Workers in a git repo
get their own git worktree and branch.

## Dependencies

- `tmux` 3.2 or newer (needs `new-session -e`)
- `git`
- `claude` (Claude Code CLI)
- `jq`
- `uuidgen` (on Linux, `/proc/sys/kernel/random/uuid` also works)

Works with macOS `/bin/bash` 3.2 and on Linux.

## Install

Run it from the repo root (`./agent_force ...`), or link it into a folder on
your `PATH`:

```sh
ln -s "$PWD/agent_force" ~/.local/bin/agent_force
```

The scripts find the repo from their own real path, so the link works from
any folder.

## One-time Claude Code setup

All agents run `claude --dangerously-skip-permissions` in a detached tmux
session. Claude Code can show two first-run dialogs there. agent_force does
not accept them for you. While a dialog is open, the agent never becomes
ready and `agent_force start` or `af-spawn` fails after 60 s.

1. **Bypass Permissions warning** ("WARNING: Claude Code running in Bypass
   Permissions mode"). You accept it once per machine. Run
   `claude --dangerously-skip-permissions` in a terminal, select
   "Yes, I accept", then exit.
2. **Folder trust** ("Quick safety check: Is this a project you created or one
   you trust?"). It shows once per folder. Before first use, run `claude`
   once and select "Yes, I trust this folder" in the folder where you run
   `agent_force start`, and in any other repo you give to `af-spawn --dir`.
   Seen with Claude Code 2.1.312: trust for a plain folder also covers the
   folders below it, but a git repo inside a trusted folder still asks for
   its own trust. A worker worktree of a trusted repo started without the
   dialog.

If an agent does not start ("did not become ready"), attach with
`tmux -L agent_force attach -t agent_NN` (or `agent_force connect N`) to see
which dialog it shows. Answer it, run `agent_force stop`, and try again.

## Commands

```
agent_force start            start a new leader agent_01 in the current folder
                             (moves old state to archive/)
agent_force start --latest   resume the last leader and its open workers
agent_force stop             kill all agents (the tmux server); keep state and worktrees
agent_force list             one line per agent: name, role, status, folder, branch, last task
agent_force connect N        attach to agent_NN (works inside tmux too)
```

Talk to the leader with `agent_force connect 1`. To detach and leave the
agents running, press `Ctrl-b d`.

The leader uses helper commands in `utils/` (on its `PATH`): `af-spawn`,
`af-send`, `af-watch`, `af-read`, `af-status`, `af-close`. You normally do
not run them yourself.

## Where things live

- State: `~/.agent_force/agents/agent_NN/` (`meta.json`, `status`,
  `last_response.md`, `tasks/NNN.md`).
- Old state from earlier fresh starts: `~/.agent_force/archive/<timestamp>/`.
- Worker worktrees: `~/.agent_force/worktrees/<repo>-<hash>/agent_NN`, on
  branch `agent_force/agent_NN` (with a `-2`, `-3`, ... suffix if the name is
  taken).

agent_force never commits, merges, pushes, or deletes a worktree.
`stop` and `af-close` keep worktrees and state. Remove old worktrees yourself
with `git worktree remove PATH`.

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `AGENT_FORCE_HOME` | `~/.agent_force` | State root (agents, archive, worktrees) |
| `AF_SOCKET` | `agent_force` | tmux socket name (`tmux -L`); agent_force never uses your default tmux socket |
| `AF_POLL_INTERVAL` | `30` | Seconds between `af-watch` screen checks |

To look at the sessions with plain tmux: `tmux -L agent_force ls`.

## Tests

```sh
bash tests/run.sh
```

The tests use a fake agent (`tests/fake_adapter/`), so they need no Claude
account.
