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
- The lead session coordinates. It plans, briefs, checks results, merges and reports. It
  does not write code or read large files itself; one-line fixes it may look at itself.
- Agents on strong models write code and review it. No weaker models for coding, not even
  for mechanical moves.
- Larger work goes: analysis → plan → the owner approves → implementation.
- One slice is one change with its test. Reports say plainly what was only checked on
  stand-ins.

Running a session cheaply (the owner): one topic at a time; the owner's answers handed to an
agent in one go; fresh agents with narrow briefs; no agent waits on a test queue; review what
carries risk.

## Features with views: the mockup first

The owner, 2026-11-20. Before any code, a mockup: a throwaway Quickshell window on stand-in
data, built from the theme and the real or planned elements, checked headless, then opened on
the owner's screen (with notice). The plan is refined on it. After the implementation the
same mockup is run again on the real code for the owner's notes. Mockups are kept outside the
repositories, in `~/src/h2s-mockups/<feature>-planned/` and `<feature>-implemented/`.

## Review

- Each slice: the author, then one review of the diff only by a second agent that gets the
  code, not the author's conclusions; findings go back to an author.
- A second review only when the first found something high.
- Recurring findings become a rule in `CLAUDE.md` ("Development rules").

## Briefing an agent

Each brief names:

- the one working tree and branch it may write to;
- what it must not touch (below);
- the exact test commands;
- that a missing API piece is reported, never worked around;
- what to report back, in a few lines.

Agents run tests in the foreground, leave no monitors or background work behind and clean up
only their own temporary files.

## What agents must not touch

- The session in use: no locking, unlocking, signals, windows on the real screen.
- The real polkit, PAM, fprintd, D-Bus services, `pkexec`, `systemctl`, `nmcli`, `nft`.
- A real `tailscale` command that changes state. Reads are fine.
- The live checkouts the running shell is started from, the installed modules folder and
  the user's configuration folder. Work happens in separate working trees.
- `quickshell` run directly. Tests go through the runners.

## Working trees and the two machines

- The running shell uses one checkout per repository. Writing a file there reloads the
  running shell, so nobody edits it; it only receives fast-forward merges.
- Agents work in separate working trees, one per agent when they run in parallel: the lead
  makes each with `git worktree add ~/wt/<name> -b <branch> master` (`main` in the module
  repository) and names it in the brief as the only place the agent writes. Each agent's
  tests run in its own tree; the runners give every run its own compositor, runtime and
  config directories, so trees side by side share nothing but the processor (and the lock
  bed's machine-wide lock).
- A module is tested against a pinned core tree nobody is editing: a detached worktree of
  the core repository, `~/src/core-pin` (`git worktree add --detach ~/src/core-pin <commit>`),
  handed to the module's runners as `H2S_SHELL_DIR=~/src/core-pin`. The lead moves it to a
  new commit (`git -C ~/src/core-pin checkout --detach <commit>`) only between agents' runs,
  when a module change needs a newer core; agents never write there.
- Development is on the Arch machine. The NixOS machine is reached over SSH: a branch goes
  there as a `git bundle` (copied over, fetched into a working tree there), and the tests
  run there through the same runners.

## Tests

The commands, what each part needs and where the tools come from are in `CLAUDE.md`
("Running", "Environment"). Before every merge to `master` / `main`: `tests/run-all.sh` on
both machines; its summary names every part as PASS, FAIL or NOT RUN with the reason, and a
report quotes it, with the tool source and the launcher the run had. While iterating: the
named suites or scenarios the change touches.

The module repository's own (not part of `tests/run-all.sh`):

| What | Command | Needs |
|---|---|---|
| Module suites | `H2S_SHELL_DIR=<core tree> tests/run.sh [--log <file>] [suites…]` in the module repository | as the unit suites: it hands the module to the core tree's `tests/run-modules.sh` |
| Module on the lock bed | `H2S_SHELL_DIR=<core tree> tests/lock-bed/run.sh tailscale` | as the lock screen's |

Flaky tests: a single failure in a known flaky test (the tracker's list) is rerun once alone;
failing twice stops the slice and goes into the tracker. A lock-bed failure seen while other
runners were going is rerun alone before it is believed.

## Deploying to the running shell

After each finished, tested part (a slice or a group of slices, reviewed and merged), the lead
fast-forwards the live checkouts and restarts the shell — never while the session is locked.
Releases, tags and pushing stay the owner's.

1. Is the session locked? `h2s-shell ipc call lockscreen status` prints `unlocked` when
   not. The lock marker file in the runtime directory always exists; its presence says
   nothing.
2. Tell the owner first: the bar flickers on a restart. Not while the owner is testing.
3. Fast-forward the live checkouts (`git merge --ff-only <branch>`), core and module (the
   module repository's `module/` is the installed module).
4. Restart the shell through the compositor, never from an agent's own shell (a shell started
   there passes that session's environment to every program started from the bar). With
   Hyprland: `hyprctl dispatch 'hl.dsp.exec_cmd("h2s-shell --restart")'`.
5. Check: `h2s-shell ipc call modules list` (no safe mode, modules loaded, no errors) and
   `h2s-shell ipc call tailscale state`.
6. A few minutes later, `tests/device/deploy-check.sh` from any core tree: the same two reads
   checked against the real Tailscale daemon (module loaded without errors, daemon running
   and read, no failed action), and no line of the running shell's log more than 5 times in
   10 minutes (`--repeats`, `--minutes`). Read-only: no `tailscale` command, no IPC call
   that changes anything. Status 1 names what failed; it goes to the tracker.

When the shell runs from a checkout instead of an installed package, every `h2s-shell`
command needs `H2S_SHELL_DIR=<live checkout>` in front, in step 4 too. After changing anything
under `singletons/`, a full restart is needed; the automatic reload keeps the old singleton.

## Notes

- `notes/tracker.md` holds only what is open: the state, what remains, the owner's open
  points and the backlog. The owner's decisions are in `notes/decisions.md` (new ones are
  added there). A finished item moves to `notes/done.md` in full the
  moment it is done; no "done" lines stay in the tracker.
- Plan slices are named by what they are; their code (C1, U2 …) only in brackets.
- Decisions the plan does not cover (behaviour, security rules, user-visible wording or
  looks): park the slice, write the question under the tracker's "Open points", continue in
  another lane. Points a plan leaves "for the owner's eyes" take the plan's choice and are
  listed there too.

## Git

- Agents commit on work branches. The lead merges to `master` / `main` by fast-forward
  after review and after its own test run on both machines.
- Pushing is the owner's. A session can fetch without credentials over HTTPS.
- Merged branches and finished working trees are removed.

## Shared machine

The owner uses the machines while work goes on. Before anything that shows on the screen
or takes input, say so and wait if asked. Background tests need no notice.
