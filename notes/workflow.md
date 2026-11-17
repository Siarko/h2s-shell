# Workflow

How the work on the shell and its modules is run. Read this with
[tracker.md](tracker.md) when starting a session on any machine.

## Start of a session

1. Read `CLAUDE.md` (this repository and the module's), this file and the tracker.
2. Ask the owner for what is not kept in a repository: the address of the other machine,
   and whether the screen may be used.
3. Continue at the tracker's "Now".

## Roles

- The owner decides: plans, priorities, wording of user-visible texts, anything in the
  tracker's "Open points". The owner talks in Polish; code, comments, docs and notes are
  English.
- The lead session coordinates. It plans, briefs, checks results and reports. It does not
  write code or read large files itself.
- Agents on strong models write code and review it. No weaker models for coding, not even
  for mechanical moves.
- Larger work goes: analysis → plan → the owner approves → implementation.
- Every change is reviewed by a second agent that gets the code, not the author's
  conclusions. Findings go back to the author. Recurring findings become a rule in
  `CLAUDE.md`.
- One slice is one change with its test. Reports say plainly what was only checked on
  stand-ins.

## Briefing an agent

Each brief names:

- the one working tree and branch it may write to;
- what it must not touch (below);
- the exact test commands;
- that a missing API piece is reported, never worked around;
- what to report back, in a few lines.

Agents clean up only their own temporary files.

## What agents must not touch

- The session in use: no locking, unlocking, signals, windows on the real screen.
- The real polkit, PAM, fprintd, D-Bus services, `pkexec`, `systemctl`, `nmcli`, `nft`.
- A real `tailscale` command that changes state. Reads are fine.
- The live checkouts the running shell is started from, the installed modules folder and
  the user's configuration folder. Work happens in separate working trees.
- `quickshell` run directly. Tests go through the runners.

## Working trees

- The running shell uses one checkout per repository. Writing a file there reloads the
  running shell, so nobody edits it; it only receives fast-forward merges.
- Agents work in separate working trees (`git worktree add`), one per agent when they run
  in parallel.
- A module is tested against a core tree that nobody is editing at that moment.

## Tests

| What | Command | Needs |
|---|---|---|
| Core unit suites | `tests/run-unit.sh` | today: `nix` |
| Runner self-test | `tests/run-unit-selftest.sh` | today: `nix` |
| Lock screen, end to end | `tests/lock/run.sh [tests…]` | `nix`; about 15 minutes for all |
| Module suites | `H2S_SHELL_DIR=<core tree> tests/run.sh` in the module repository | today: `nix` |
| Module on the lock bed | `H2S_SHELL_DIR=<core tree> tests/lock-bed/run.sh tailscale` | `nix` |

- When more than one run can happen at once on a machine, wrap each in
  `flock /tmp/h2s-locktest.flock …`.
- All of them run in an invisible compositor. They use the processor, nothing shows.
- From the Arch machine, the runs that need `nix` go over SSH to the NixOS machine, in a
  working tree there that is fetched to the commit under test. The tracker's test split
  (step 10, planned in step 1) is what lets the general set run on Arch directly.

## Deploying to the running shell

Only on the owner's word, and never while the session is locked.

1. Is the session locked? `h2s-shell ipc call lockscreen status` prints `unlocked` when
   not. The lock marker file in the runtime directory always exists; its presence says
   nothing.
2. Tell the owner first: the bar flickers on a restart.
3. Fast-forward the live checkouts (`git merge --ff-only <branch>`), core and module.
4. Restart the shell through the compositor, never from an agent's own shell. A shell
   started from an agent session inherits that session's environment and passes it to
   every program the user starts from the bar. With Hyprland:
   `hyprctl dispatch 'hl.dsp.exec_cmd("h2s-shell --restart")'`.
5. Check: `h2s-shell ipc call modules list` (no safe mode, modules loaded, no errors) and
   `h2s-shell ipc call tailscale state`.

When the shell runs from a checkout instead of an installed package, every `h2s-shell`
command needs `H2S_SHELL_DIR=<live checkout>` in front, in step 4 too.

After changing anything under `singletons/`, a full restart is needed; the automatic
reload keeps the old singleton.

## Git

- Agents commit on work branches. The lead merges to `master` / `main` by fast-forward
  after review and after its own test run.
- Pushing is the owner's. A session can fetch without credentials over HTTPS.
- Merged branches and finished working trees are removed.

## Shared machine

The owner uses the machines while work goes on. Before anything that shows on the screen
or takes input, say so and wait if asked. Background tests need no notice.
