# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Project

A **Quickshell desktop shell configuration** — a custom Wayland/Hyprland desktop panel
built with Qt 6 and QML. Not a compiled application: QML files are interpreted directly
by the Quickshell runtime. One small helper program is compiled (`helper/`, C++/Qt): what
Quickshell cannot do from QML.

## Documentation

`docs/` holds user and developer documentation only; for now that is (both to be
rewritten, see the tracker's step 12):

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — runtime model, directory layout,
  module resolution, the Process/SplitParser I/O idiom, the config system, the widget
  contract, how to add a widget, testing and where the test tools come from.
- **[docs/FEATURES.md](docs/FEATURES.md)** — what the shell does: every widget, panel,
  HUD element, settings page, and the external tools it depends on.

The session notes (tracker, decisions, workflow, plans, reviews) live outside this
repository; nothing in it links to them.

The rules for `docs/`: English only; where NixOS and Arch differ, a "NixOS" and an "Arch"
subsection — never one system without the other; nothing that names or relies on a
developer's own environment (user names, home paths, machines); checked for consistency at
each major release.

## Running

QML needs no build; one helper is compiled — `scripts/build-helper.sh` (cmake, a C++
compiler, Qt 6's Core and DBus development files) builds `helper/` into
`~/.cache/h2s-shell/helper/<checkout>/`, never into the tree. NixOS: the package builds it
(`nix/package.nix`, into its `libexec/`); Arch: `install.sh` builds it, and
`scripts/launch.sh`, when its source changed, hands over the binary it has at once and
rebuilds in the background for the next start — a start never waits for a build (none yet
or a failed build: the shell runs without it, said once in the launcher's log). The shell is handed its path as
`H2S_SHELL_HELPER` (`singletons/Helper.qml`).

```
quickshell                 # reads shell.qml from the current directory
scripts/build-helper.sh    # builds the helper (launch.sh does it when needed)
tests/affected.sh --run    # while iterating: the suites, scenarios and self-tests the change needs
tests/run-unit.sh FormatTest LockRulesTest   # … or named suites
tests/lock/run.sh relock fallback            # … or named lock scenarios
tests/run-all.sh --quick   # a slice's commit: everything but the lock bed, about half a minute
tests/run-all.sh           # the end of a segment of work: everything, both machines
tests/remote-run.sh        # … run on the other machine over SSH (H2S_REMOTE=<destination>)
tests/mutate.sh <file>     # a new or much changed *Rules.qml: which mutants no suite notices
tests/soak.sh <suite> 20   # a suite suspected of flaking: 20 runs in a row under CPU load
```

**While iterating** run `tests/affected.sh --run`: it runs the unit suites, module fixture
parts, self-tests and lock scenarios the change needs — the branch against its nearest base
(the fewest commits back of where it left a `segment-*` branch or `master`), the working tree
and untracked files included (a git range as its argument names another change; without
`--run` it prints the commands, `--why` each changed file and what it selects).
The selection is mechanical: each suite covers the QML it uses, transitively, and
`tests/affected-map.txt` places what that cannot see (scripts, runners, the lock scenarios'
subjects, what needs no test); a file placed nowhere fails `tests/affected-selftest.sh` until
the map gives it a test or `none`. Named suites or scenarios run as well (a suite is named
by its file in `tests/` without `.qml`, a lock scenario by its file in `tests/lock/tests/`
without `.sh`; a wrong name is an error, nothing runs). **A slice's commit** needs those plus
`tests/run-all.sh --quick` on one machine. **The full `tests/run-all.sh`** runs on both machines at
the end of a segment of work (a group of slices, before it is merged to `master` and deployed),
not per slice; `tests/remote-run.sh` runs it on the other machine from this one (a branch or
commit sent as a `git bundle`, run in a worktree of its own there, the summary brought back;
`--attach <id>` collects a run whose connection dropped). Its parts run side by side, the lock
bed last and alone; it stops at the first failing part
(`--keep-going` goes on) and ends with a summary naming every part PASS, FAIL or NOT RUN with
the reason and its seconds — read it: a part that could not be set up is not a pass. Measured
on a 32-thread machine: the unit suites about 15 s, `--quick` about 26 s, the full set about
2.5 minutes, of which the lock bed about 125 s; where memory allows three shards at once, the
unit suites take about a minute and the lock bed about 250 s. Its parts, each runnable alone:

```
tests/run-unit.sh          # the unit suites, in parallel shards of private headless compositors (--log <file>)
tests/run-modules.sh <dir> # a module's suites, against this tree (--suite <name> for some)
tests/install-test.sh      # install.sh under stand-ins: what it would do, nothing done
tests/run-helper.sh        # the helper built and run; its build script and launch.sh's look-up
tests/run-system.sh        # this system's set (tests/system/nixos, tests/system/arch)
tests/lock/run.sh          # the lock screen, end to end, in an invisible compositor
tests/*-selftest.sh        # self-tests: the runners' own verdicts, the deploy check's, affected.sh's map
tests/lock/selftest.sh     # the lock bed's runner: its lint (tests/lock/lint.sh) and FLAKY reruns
```

The unit suites run in shards: the runner packs them by the time each took last
(`~/.cache/h2s-shell-tests/unit-times.txt`) so that no shard runs longer than the longest
suite; a suite that changes what one process shares says `ownProcess: true` and runs alone.
A shard's asynchronous suites (`asynchronous: true`, `runAsync()`, `finish()`) run side by
side, none waiting for another. A lock scenario that fails runs once more at the end, alone: passing then it is
**FLAKY**, still a failure of the run, with a line in `~/.cache/h2s-shell-tests/flaky.log`.
`tests/lock/lint.sh`, run by the bed, refuses a `sleep` in a scenario without its reason.

`tests/mutate.sh <file>` applies one mechanical mutation at a time to a `*Rules.qml` or a
singleton, in scratch copies of the tree, runs the suites `affected.sh` gives for it, and lists
the mutants that survived. Run it on a new Rules file or after a big change to one — a slice
may run it on its own file —; each survivor gets a check, or a reason in the slice's report
why it cannot be told apart (an equivalent mutant). `run-all.sh` runs only its self-test.
`tests/soak.sh <suite | module dir> <n>` runs a suite n times in a row under busy loops:
a check that depends on timing fails there in minutes.

Never run `quickshell -p tests.qml` directly: five suites open a small window.

Every runner takes its tools from the pinned `tests/lock/tools.nix` where there is a `nix`
command, else from `PATH` (`H2S_TEST_TOOLS=nix` or `=system` says which), and says which
in its first lines; a missing tool ends the run with status 2 and its name
(`tests/lock/resolve.sh`). Only the lock bed needs the machine to itself (it takes
`/tmp/h2s-locktest.flock`); the other runners run side by side, and a lock-bed failure seen
while they ran is run again alone before it is believed.

A running shell reloads itself when a file changes, but keeps the old singletons (new
functions show up as `TypeError: ... is not a function`): restart it fully after changing
anything under `singletons/`.

Beyond the test suites, verification is manual: check that the bar renders, the clock
ticks, cells respond to clicks, and popups toggle. A feature with views starts with a
mockup the owner sees before any code (`notes/workflow.md`).

## Conventions

- **The helper (`helper/`) is I/O only**: it reports and acts on request, decisions stay
  in `*Rules.qml`. A capability goes into it only when Quickshell cannot do it, and leaves
  it when Quickshell can. It talks to the shell in JSON lines on its standard input and
  output, and ends when its input closes. It runs as the user only — never through
  pkexec or sudo; a privileged action goes through the root-helper path, from a root-owned
  location (`tests/run-helper.sh` checks no escalation names it).
- **State and I/O live in `singletons/`.** QML under `widgets/`, `panels/` and `hud/`
  renders that state and calls singleton methods — it should not own system access.
- **All colours and type sizes come from `singletons/Theme.qml`.** No literal colours
  elsewhere.
- **Settings are read with `Profiles.value(key)`** and declared in
  `singletons/SettingsSchema.qml` — never as a new `Config` property. `Config` holds only
  data that is not a preference (accounts, tokens, remembered state). See "Config and
  profiles" in `docs/ARCHITECTURE.md`.
- **Full variable names** — `calendar`, `response`, `calendarId`, not `c`, `r`, `cid`.
  Loop indices (`i`, `j`) are the exception.
- **Comments in English**, explaining *why* rather than restating the code.
- **Never bind a live reactive array directly to `Repeater.model`** — it crashes
  Quickshell. Use a `ScriptModel`. This and the rule that popup content is created via
  `Qt.callLater` in `Popup.qml` are the fix for months of random SIGSEGVs — read "The
  Repeater crash" in `docs/ARCHITECTURE.md` before touching either.
- **A `ScriptModel` takes strings (or QObjects), never JS objects built anew on each
  read**: for a list of records use `components/KeyedModel.qml` (a ScriptModel of string
  keys) and let the delegate look its item up by key (`list.byKey[modelData]`). Quickshell
  0.3.2 puts rebuilt objects into rows by position — even with `objectProp` — so a
  delegate's state ends up with another item (`notes/upstream/quickshell-scriptmodel-replace.md`).
- **Never start a `Process` with a declarative `running: true`** — Quickshell writes
  `running = false` on exit and destroys the binding. Use `Component.onCompleted` or a
  `Timer`.
- **A question is the button's or the Settings modal's, nothing else asks.** A one-word
  question stays on the button, `components/DeleteButton.qml`: the first click turns it into
  a red question ("Delete?") with a "×" attached that cancels, a second click acts. No
  time-outs. The owner resets `asking` when the item it acts on changes. A button that asks
  before something else (turning a hotspot on) is the same component with its `kind`
  (`"save"`): the question takes the kind's colour. A question with a list, a choice or an
  explanation opens the Settings modal (`notes/plans/modules-management.md` §4.1). Don't
  hand-roll another confirm; not everything needs a modal.
- **How a button looks is `ThemeRules.buttonLook(kind, state)`**: `SmallButton` and
  `DeleteButton` draw what it names. A new kind or state is added there, with its cases.
- **A control's hover look comes from `components/PointerArea.qml`'s `lit`**, not a
  `MouseArea`'s `containsMouse` — so a tap shows too, and small controls get a larger
  target. Rows of a list that touch take `centred: false`. See "Conventions" in
  `docs/ARCHITECTURE.md`.
- **`ShapePath` has no `visible` property.**
- **Do not add a `qmldir`.** Quickshell registers types per directory automatically. (A
  module directory, loaded by `file://` URL, is the exception: a copy outside the tree, or
  in-tree under a hyphenated folder no `import qs.…` can reach, as `tests/fixtures/` and
  `builtin-modules/`; see "Modules" in `docs/ARCHITECTURE.md`.)
- **Versioning:** the number is in `singletons/Version.qml` (semver — major for changes
  to behaviour people rely on, minor for features, patch for fixes; a settings migration
  may ship in a minor release, never in a patch). The module API has its own number
  (`Api.version`): until the first release announced as open to module authors, its minor
  version may tighten or remove things; from then a removal comes only with a major, after
  being listed as deprecated for at least one release. With every
  user-visible change, add a line under **Unreleased** in `CHANGELOG.md`; a release moves
  them to a new section, bumps the number and tags `v<number>`. `tests/VersionTest.qml`
  checks the two agree.
- **Commit on a work branch only**, as `notes/workflow.md` describes; merging to `master`
  and pushing follow review and are the owner's call.

## Environment

Developed and tested on NixOS and on Arch, by sessions on different machines; nothing about
a session survives outside this repository (what is next and why: `notes/tracker.md`). What differs between the two systems for
development (the full list of test tools per runner: `docs/ARCHITECTURE.md`, "Where the
test tools come from"):

- **Quickshell.** The runners take `LOCKTEST_QS`, else the one the `h2s-shell` launcher
  runs (`LOCKTEST_LAUNCHER` names another), else `qs` or `quickshell` on `PATH`.
  - NixOS: the launcher is this flake's package (`nix/package.nix`).
  - Arch: `install.sh` installs Quickshell from pacman and puts no `h2s-shell` on `PATH`,
    so the suites run the `qs` on `PATH`, and the lock test bed takes its own
    `tests/lock/launcher.sh` (the checkout's `scripts/launch.sh`) and says so: what the
    package adds to `PATH` is not tested there.
- **Test tools.** One source for a whole run: the pinned build of `tests/lock/tools.nix`
  where there is a `nix` command (the built path cached in
  `${XDG_CACHE_HOME:-$HOME/.cache}/h2s-shell-tests/` while `tools.nix` is unchanged;
  `H2S_TEST_TOOLS_CACHE=0` asks nix anyway), else the system's programs, un-pinned.
  - NixOS: `nix` builds everything, the lock bed's whole set included.
  - Arch, without `nix`: labwc (the suites' headless compositor) and the lock bed's
    programs are packages to have installed for development (`install.sh` installs
    neither); the lock bed makes its Python bindings and keymaps at each start.
- **The helper's build.** `tests/run-helper.sh` builds it with the same choice of source.
  - NixOS: as the flake's `h2s-helper` package (the derivation the NixOS package
    installs), with nix's own cmake, compiler and Qt.
  - Arch, without `nix`: with `cmake`, a C++ compiler (`base-devel`) and `qt6-base` from
    the system, which `install.sh` installs.
- **Paths.** Scripts start with `#!/usr/bin/env bash`: NixOS has no `/bin/bash`.
  System files differ (NixOS: `/run/current-system/sw/bin`, `/etc/static`, a generated
  `/etc/pam.d`); code that reads them handles both systems.

## Development rules

Each comes from defects reviews found more than once. Add to the list when a review finds a
new kind.

- **Text from outside the shell** (a module, a daemon, a command's output, a network name)
  is shown as plain text (`textFormat: Text.PlainText`), length-capped, and on one line where
  it stands in a line (a label, a row, a title); a notification's body keeps its line
  breaks. Never interpreted as markup, never put on a command line unquoted. — Markup injection and
  shell injection both happened.
- **Nothing asks for a password without the user's click.** Automatic actions (timers,
  network changes, IPC) never prompt; a dismissed prompt is silent (`PrivilegedAction`'s
  `dismissed`). — An unasked prompt trains people to type passwords into anything.
- **Decisions live in pure functions in `*Rules.qml`** with unit cases; clients and
  singletons only do I/O and call them. A state machine's lifetime rules are rules too
  (`LockRules.step`). — What is not pure is not tested.
- **A button's label and its effect are one decision**, derived from the current state when
  the view is built. — Labels and actions drifted apart.
- **A question an action asks is keyed to what it acts on**: an asking button, offer or
  notification action carries the ids it will act on (its subject), and acts on those, not on
  whatever is current when the answer comes. — Answers landed on items that had moved or changed.
- **A failed read is "unknown/unsafe", never "fine".** — Silent failures showed as healthy.
- **Late answers lose.** An answer from a process started before the state changed — or
  arriving after a cancel, a stop or an account switch — must not overwrite newer state or
  act. — Stale reads overwrote fresh ones; answers after a cancel still acted.
- **Log on a change of outcome, not on every attempt;** repeated work follows a backoff. —
  Logs filled with the same line every few seconds.
- **Live tests wait on conditions, never on fixed sleeps;** a test that cannot fail is
  deleted. — Sleeps make tests flaky under load.
- **A deadline in a test only guards a hang.** Waits are on conditions, with one generous
  deadline per kind; an upper time bound is a test of timing, made against a seam or a
  monotonic clock, and a lock scenario whose subject is a time runs alone (`SERIAL`,
  `check_timed`). — "Not within 3 s" failed on loaded machines.
- **Real waits longer than a second come through a seam** in a test (backoffs, pauses,
  grace windows). — 30 s pauses made scenarios minutes long.
- **A suite leaves the shared state as it found it** (`TestCase` compares
  `tests/SharedStateReader.qml`'s snapshot when it reports), or declares `ownProcess: true`. — One
  suite's writes changed another's verdict.
- **A new check is seen failing once**: break its subject (`tests/mutate.sh`, or by hand),
  watch it fail, put it back. A suite that reports 0/0 or a scenario without a PASS line
  fails. — Checks that could not fail passed review.
- **What a change runs is `tests/affected.sh`'s answer;** a file it cannot place gets a line
  in `tests/affected-map.txt` (a test, or `none`). — Choosing suites by memory missed some.
- **A real I/O path runs in at least one test, against stand-ins.** What test mode or the
  test kit hands a module in its place does not test it: the reading itself (the command,
  its parsing, its steps) gets a suite that runs it on stand-in programs. — Two defects
  passed every suite and showed only in the live shell, because test mode never reached
  the real path.
- **Tests never touch the real session, polkit, PAM, the network or a real daemon:** stand-ins
  only, and stand-ins never meet the real `pkexec`. — A test must not change the machine.
- **Root helpers and scripts run as root are never loaded from a place the user can
  write.** — Otherwise any user process can become root at the next prompt.
- **The module API is ours.** If it lacks something, stop and extend it (minor version, a
  `### Module API` line in `CHANGELOG.md`, the reference in `api/Api.qml`) — never build a
  substitute in a module. It covers capabilities (running things, system state,
  privileges, places in the shell's views), not looks: a module may build its own elements
  from the theme's tokens. — Workarounds in modules became the real API.
- **Whatever a module can reach through an object it is handed is API.** A handle given to a
  module is a frozen object of closures over the shell's internals, never properties holding
  them (no `_handle`, runner, server or token reachable). — A raw handle was reachable through
  a "private" property.
- **Animations stop when nothing shows them**: a running animation or timer is gated on the
  window and the item being visible (and on reduce motion). — Hidden windows kept animating
  every frame.
- **An overlay window's input mask covers only what it draws**, never other surfaces; an
  overlay that ignores exclusive zones keeps clear of the bar with insets
  (`BarGeometry.reservedInsets`). — Clicks beside a toast were swallowed; the HUD sat over the
  bar.
- **Nothing relies on one developer's environment;** NixOS and Arch are treated together. —
  Code and docs that worked on one machine only.
- **Only Wayland is assumed.** No distribution, compositor or tiling window manager is
  required: Hyprland is an integration used when present, and a feature that needs a
  compositor's own interface has a path (or a plain "not available here") without it. NixOS
  and Arch are where it is tested, not what code may assume. — The shell is meant to run on
  any Wayland compositor with the protocols it needs.
- **Development never depends on an LLM.** Tests, checks and every key step (releasing,
  generating docs) are plain scripts that run without one; LLM steps live at most in an
  optional wrapper. — A project that needs an LLM to be tested or released cannot be worked on
  without one.
- **Docs and comments describe the code as it is,** never how or when it was built.
  User-visible strings are the few plain words a person would put on a control. — History
  in comments goes stale; long hints read as machine-written.
- **One slice = one change with its test.** While iterating run only the suites the change
  touches, `--quick` before the commit; the full set at the end of a segment. — Small reviewed
  steps, fast feedback; the full set on both machines took longer than the work it checked.
