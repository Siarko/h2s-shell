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
  contract, how to add a widget, testing.
- **[docs/FEATURES.md](docs/FEATURES.md)** — what the shell does: every widget, panel,
  HUD element, settings page, and the external tools it depends on.

Working notes live in **`notes/`** — not documentation, may be out of date, never linked
from `docs/` or the README:

- **[notes/tracker.md](notes/tracker.md)** — the one tracker for the shell and its
  modules: what is next, the order of work, the owner's decisions. **Start here when
  resuming work.**
- **[notes/workflow.md](notes/workflow.md)** — how sessions work: roles, briefing agents, what
  must not be touched, tests, deploying, git.
- **[notes/done.md](notes/done.md)** — done items, numbers kept ("TODO 11.22" in a commit
  or comment), with their notes.
- **[notes/cleanup.md](notes/cleanup.md)** — findings from a full read, with severities;
  check it before "fixing" something.
- **`notes/plans/`** — designs and delivery plans per feature; **`notes/reviews/`**,
  **`notes/upstream/`** (drafts of Quickshell issues), `notes/pttd-protocol.md` (the
  dictation daemon's socket protocol).

The rules for `docs/`: English only; where NixOS and Arch differ, a "NixOS" and an "Arch"
subsection — never one system without the other; nothing that names or relies on a
developer's own environment (user names, home paths, machines); checked for consistency at
each major release.

## Running

There is no build step:

```
quickshell                 # reads shell.qml from the current directory
tests/run-unit.sh          # runs the unit suites (tests.qml), prints PASS/FAIL, exits
tests/run-unit.sh FormatTest LockRulesTest   # only the named suites, and the suites they need
tests/run-unit-selftest.sh # checks the runners' own verdict
tests/resolve-selftest.sh  # checks where the runners take their tools from
tests/run-modules.sh <dir> # a module's suites, against this tree
tests/run-modules.sh --suite GoodApiTest <dir>   # only the named ones (--suite once per suite)
tests/lock/run.sh          # the lock screen, end to end, in an invisible compositor
```

Run the unit suites through `tests/run-unit.sh`, not `quickshell -p tests.qml` directly:
two suites open a small window, and the runner puts them in a private headless compositor
(nothing shows on your screen). While iterating, name the suites the change touches (a suite
is named by its file in `tests/` without `.qml`; a wrong name is an error, nothing runs);
run them all before committing. `--log <file>`, before the names, also saves the output.

Every runner takes its tools — that compositor (labwc), and for the lock test bed Hyprland
and the rest of its set — from the pinned `tests/lock/tools.nix` where there is a `nix`
command, else from `PATH` (`H2S_TEST_TOOLS=nix` or `=system` says which), and says which
in its first lines; a missing tool ends the run with status 2 and its name
(`tests/lock/resolve.sh`; `LOCKTEST_QS` names another Quickshell). The lock test bed starts
the shell through a launcher: `LOCKTEST_LAUNCHER`, else `h2s-shell` on `PATH`, else its own
`tests/lock/launcher.sh`. When another run of either may be going on (two people or agents in one checkout), wrap them in
`flock /tmp/h2s-locktest.flock …`.

A running shell reloads itself when a file changes, but that reload is not enough after
editing a singleton: it has been seen to rebuild the panels while keeping the old
singleton, so new functions show up as `TypeError: ... is not a function`. Restart the
shell fully after changing anything under `singletons/`.

Beyond the test suites, verification is manual: check that the bar renders, the clock
ticks, cells respond to clicks, and popups toggle.

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
  Quickshell. Use `ScriptModel { values: … }`, with `objectProp` as the identity key
  where delegates should be reused. This and the rule that popup content is created via
  `Qt.callLater` in `Popup.qml` are the fix for months of random SIGSEGVs — read "The
  Repeater crash" in `docs/ARCHITECTURE.md` before touching either.
- **Never start a `Process` with a declarative `running: true`** — Quickshell writes
  `running = false` on exit and destroys the binding. Use `Component.onCompleted` or a
  `Timer`.
- **Deleting from a click goes through `components/DeleteButton.qml`**: the first click
  turns it into a red question ("Delete?") with a "×" attached that cancels, a second
  click deletes. No time-outs. The owner resets `asking` when the item it deletes
  changes. Don't hand-roll another confirm.
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
  may ship in a minor release, never in a patch). With every
  user-visible change, add a line under **Unreleased** in `CHANGELOG.md`; a release moves
  them to a new section, bumps the number and tags `v<number>`. `tests/VersionTest.qml`
  checks the two agree.
- **Commit on a work branch only**, as `notes/workflow.md` describes; merging to `master`
  and pushing follow review and are the owner's call.

## Environment

The shell is developed and tested on NixOS and on Arch, by several sessions on different
machines. Nothing about a session survives outside this repository: what is next, what was
decided and why belongs in `notes/tracker.md`.

What differs between the two systems for development:

- **Quickshell.** The test runners take `LOCKTEST_QS` when it is set, else the Quickshell
  the `h2s-shell` launcher runs (`LOCKTEST_LAUNCHER` names another launcher), asking the
  launcher itself, else `qs` or `quickshell` on `PATH` (`tests/lock/resolve.sh`).
  - NixOS: the launcher is this flake's package (`nix/package.nix`).
  - Arch: `install.sh` installs Quickshell from pacman and puts no `h2s-shell` command on
    `PATH`, so the unit and module suites run the `qs` on `PATH`. The lock test bed, which
    starts the shell through a launcher, then takes its own `tests/lock/launcher.sh` (the
    checkout's `scripts/launch.sh`, as the packaged launcher runs it with `H2S_SHELL_DIR`)
    and says so in its output: what the package adds to `PATH` is not tested there.
- **Test tools.** One source for a whole run (`tests/lock/resolve.sh`, used by
  `tests/headless.sh` and `tests/lock/run.sh`): the pinned build of `tests/lock/tools.nix`
  where there is a `nix` command, else the system's programs on `PATH`, un-pinned;
  `H2S_TEST_TOOLS=nix` or `=system` chooses. Each run prints the source and the versions.
  - The unit and module suites (`run-unit.sh`, `run-unit-selftest.sh`, `run-modules.sh`)
    need labwc (the headless compositor), `setpriv` and `setsid` (util-linux) and `timeout`
    (coreutils). NixOS: `nix` provides labwc and `setpriv`. Arch, without `nix`: labwc is a
    package to have installed for development (`install.sh` does not install it).
  - `tests/resolve-selftest.sh` needs none of them but `setsid` and `timeout`.
  - The lock test bed (`tests/lock/run.sh`) needs labwc, Hyprland with hyprctl, grim,
    wlr-randr, wl-copy and wl-paste, xkbcli, dbus-daemon, gdbus, `setpriv`, a `python3`
    that imports pywayland, and the Python bindings of its input protocols and its
    keymaps. NixOS: `nix` builds all of it. Arch, without `nix`: the programs are packages
    to have installed for development (`docs/ARCHITECTURE.md`, "Where the test tools come
    from", names them), and the bindings and keymaps are made at the start of each run,
    which also takes `pkg-config`, the `wayland` and `wayland-protocols` packages' protocol
    files and the two kept in `tests/lock/protocols/`.
- **Paths.** Scripts start with `#!/usr/bin/env bash`: NixOS has no `/bin/bash`.
  System files differ (NixOS: `/run/current-system/sw/bin`, `/etc/static`, a generated
  `/etc/pam.d`); code that reads them handles both systems.

## Development rules

Each comes from defects reviews found more than once. Add to the list when a review finds a
new kind.

- **Text from outside the shell** (a module, a daemon, a command's output, a network name)
  is shown as plain text (`textFormat: Text.PlainText`), on one line, length-capped; never
  interpreted as markup, never put on a command line unquoted. — Markup injection and
  shell injection both happened.
- **Nothing asks for a password without the user's click.** Automatic actions (timers,
  network changes, IPC) never prompt; a dismissed prompt is silent (`PrivilegedAction`'s
  `dismissed`). — An unasked prompt trains people to type passwords into anything.
- **Decisions live in pure functions in `*Rules.qml`** with unit cases; clients and
  singletons only do I/O and call them. A state machine's lifetime rules are rules too
  (`LockRules.step`). — What is not pure is not tested.
- **A button's label and its effect are one decision**, derived from the current state when
  the view is built. — Labels and actions drifted apart.
- **A failed read is "unknown/unsafe", never "fine".** — Silent failures showed as healthy.
- **Late answers lose.** An answer from a process started before the state changed must not
  overwrite newer state. — Stale reads overwrote fresh ones.
- **Log on a change of outcome, not on every attempt;** repeated work follows a backoff. —
  Logs filled with the same line every few seconds.
- **Live tests wait on conditions, never on fixed sleeps;** a test that cannot fail is
  deleted. — Sleeps make tests flaky under load.
- **Tests never touch the real session, polkit, PAM, the network or a real daemon:** stand-ins
  only, and stand-ins never meet the real `pkexec`. — A test must not change the machine.
- **Root helpers and scripts run as root are never loaded from a place the user can
  write.** — Otherwise any user process can become root at the next prompt.
- **The module API is ours.** If it lacks something, stop and extend it (minor version, a
  `### Module API` line in `CHANGELOG.md`, the reference in `api/Api.qml`) — never build a
  substitute in a module. It covers capabilities (running things, system state,
  privileges, places in the shell's views), not looks: a module may build its own elements
  from the theme's tokens. — Workarounds in modules became the real API.
- **Nothing relies on one developer's environment;** NixOS and Arch are treated together. —
  Code and docs that worked on one machine only.
- **Docs and comments describe the code as it is,** never how or when it was built.
  User-visible strings are the few plain words a person would put on a control. — History
  in comments goes stale; long hints read as machine-written.
- **One slice = one change with its test.** While iterating run only the suites the change
  touches; run the full set before committing. — Small reviewed steps, fast feedback.
