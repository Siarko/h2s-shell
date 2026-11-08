# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Project

A **Quickshell desktop shell configuration** — a custom Wayland/Hyprland desktop panel
built with Qt 6 and QML. Not a compiled application: QML files are interpreted directly
by the Quickshell runtime.

## Documentation

Read these before making structural changes:

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — runtime model, directory layout,
  module resolution, the Process/SplitParser I/O idiom, the config system, the widget
  contract, how to add a widget, testing.
- **[docs/FEATURES.md](docs/FEATURES.md)** — what the shell does: every widget, panel,
  HUD element, settings page, and the external tools it depends on.
- **[docs/CLEANUP.md](docs/CLEANUP.md)** — the known-problems backlog, prioritised, with
  file:line references. Check this before "fixing" something — it may already be filed,
  with the analysis done.
- **[docs/TODO.md](docs/TODO.md)** — the cleanup checklist derived from it, in the agreed
  order, with the current progress. Start here when resuming cleanup work.
- **[docs/TODO-DONE.md](docs/TODO-DONE.md)** — the done items of TODO.md, numbers kept, with
  their notes; look an item number up here when it is not in TODO.md.
- **[docs/STYLES.md](docs/STYLES.md)** — the shell's CSS variant for themes: selectors,
  cascade, properties, at-rules. Keep it in step with what the compiler accepts.
- **[docs/quickshell-integration.md](docs/quickshell-integration.md)** — the `pttd`
  dictation daemon's socket protocol.

## Running

There is no build step:

```
quickshell                 # reads shell.qml from the current directory
quickshell -p tests.qml    # runs the test suites, prints PASS/FAIL, exits
```

A running shell reloads itself when a file changes, but that reload is not enough after
editing a singleton: it has been seen to rebuild the panels while keeping the old
singleton, so new functions show up as `TypeError: ... is not a function`. Restart the
shell fully after changing anything under `singletons/`.

Beyond the one test suite, verification is manual: check that the bar renders, the clock
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
- **Do not add a `qmldir`.** Quickshell registers types per directory automatically.
- **Versioning:** the number is in `singletons/Version.qml` (semver — major for config
  migrations or behaviour changes, minor for features, patch for fixes). With every
  user-visible change, add a line under **Unreleased** in `CHANGELOG.md`; a release moves
  them to a new section, bumps the number and tags `v<number>`. `tests/VersionTest.qml`
  checks the two agree.
- **Only commit when explicitly asked.** Never commit proactively after making changes.

## Environment

This repo gets worked on from two places, and they differ in one way that matters:

- **On the host** (Arch, Hyprland) `quickshell` is installed, so changes can be run and
  tested directly — `quickshell` from the repo root, `quickshell -p tests.qml` for the
  suites.
- **In the dev container** (`.devcontainer/`) there is no Qt and no `quickshell`, so
  nothing can be run or linted. Changes made there have to be verified on the host, and
  anything claimed about runtime behaviour is reasoning, not observation.

The container bind-mounts this folder, so the files are the same on both sides. But
`~/.claude` is a container-local volume: session state, plans and memory do **not**
travel. Anything that has to survive the move belongs in this repo — which is what
`docs/TODO.md` is for.
