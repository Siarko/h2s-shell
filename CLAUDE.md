# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Project

A **Quickshell desktop shell configuration** — a custom Wayland/Hyprland desktop panel
built with Qt 6 and QML. Not a compiled application: QML files are interpreted directly
by the Quickshell runtime.

## Documentation

`docs/` holds user and developer documentation only; for now that is (both to be
rewritten, see the tracker's step 12):

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — runtime model, directory layout,
  module resolution, the Process/SplitParser I/O idiom, the config system, the widget
  contract, how to add a widget, testing and where the test tools come from.
- **[docs/FEATURES.md](docs/FEATURES.md)** — what the shell does: every widget, panel,
  HUD element, settings page, and the external tools it depends on.

Working notes live in **`notes/`** — not documentation, may be out of date, never linked
from `docs/` or the README:

- **[notes/tracker.md](notes/tracker.md)** — the one tracker for the shell and its
  modules: what is next, the order of work, open points. **Start here when resuming work.**
- **[notes/decisions.md](notes/decisions.md)** — the owner's decisions, by topic; read the
  topic you work on.
- **[notes/workflow.md](notes/workflow.md)** — how sessions work: roles, mockups first,
  review, briefs, what must not be touched, the two machines, deploying, git.
- **[notes/done.md](notes/done.md)** — done items, numbers kept ("TODO 11.22" in a commit
  or comment), with their notes.
- **[notes/cleanup.md](notes/cleanup.md)** — findings from a full read, with severities;
  check it before "fixing" something.
- **`notes/plans/`** (designs and plans per feature), **`notes/reviews/`**,
  **`notes/upstream/`** (drafts of Quickshell issues), `notes/pttd-protocol.md` (dictation).

The rules for `docs/`: English only; where NixOS and Arch differ, a "NixOS" and an "Arch"
subsection — never one system without the other; nothing that names or relies on a
developer's own environment (user names, home paths, machines); checked for consistency at
each major release.

## Running

There is no build step:

```
quickshell                 # reads shell.qml from the current directory
tests/run-unit.sh FormatTest LockRulesTest   # while iterating: the suites the change touches
tests/lock/run.sh relock fallback            # … the lock scenarios it touches
tests/run-all.sh           # before committing: everything, about four minutes
tests/run-all.sh --quick   # the same without the lock bed, under a minute
```

**While iterating** run the named suites or scenarios the change touches (a suite is named
by its file in `tests/` without `.qml`, a lock scenario by its file in `tests/lock/tests/`
without `.sh`; a wrong name is an error, nothing runs). **Before committing** run
`tests/run-all.sh` (the general set and this system's): it stops at the first failing part
(`--keep-going` goes on) and ends with a summary naming every part PASS, FAIL or NOT RUN with
the reason — read it: a part that could not be set up is not a pass. Its parts, each
runnable alone:

```
tests/run-unit.sh          # the unit suites, in a private headless compositor (--log <file>)
tests/run-modules.sh <dir> # a module's suites, against this tree (--suite <name> for some)
tests/install-test.sh      # install.sh under stand-ins: what it would do, nothing done
tests/run-system.sh        # this system's set (tests/system/nixos, tests/system/arch)
tests/lock/run.sh          # the lock screen, end to end, in an invisible compositor
tests/*-selftest.sh        # self-tests: the runners' own verdicts, the deploy check's
```

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
  module directory, loaded by URL from outside the scanned tree, is the exception: see
  "Modules" in `docs/ARCHITECTURE.md`.)
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
- **Development never depends on an LLM.** Tests, checks and every key step (releasing,
  generating docs) are plain scripts that run without one; LLM steps live at most in an
  optional wrapper. — A project that needs an LLM to be tested or released cannot be worked on
  without one.
- **Docs and comments describe the code as it is,** never how or when it was built.
  User-visible strings are the few plain words a person would put on a control. — History
  in comments goes stale; long hints read as machine-written.
- **One slice = one change with its test.** While iterating run only the suites the change
  touches; run the full set before committing. — Small reviewed steps, fast feedback.
