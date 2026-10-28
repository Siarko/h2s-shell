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
- **[docs/quickshell-integration.md](docs/quickshell-integration.md)** — the `pttd`
  dictation daemon's socket protocol.

## Running

There is no build step:

```
quickshell                 # reads shell.qml from the current directory
quickshell -p tests.qml    # runs the test suites, prints PASS/FAIL, exits
```

Beyond the one test suite, verification is manual: check that the bar renders, the clock
ticks, cells respond to clicks, and popups toggle.

## Conventions

- **State and I/O live in `singletons/`.** QML under `widgets/`, `panels/` and `hud/`
  renders that state and calls singleton methods — it should not own system access.
- **All colours and type sizes come from `singletons/Theme.qml`.** No literal colours
  elsewhere.
- **Full variable names** — `calendar`, `response`, `calendarId`, not `c`, `r`, `cid`.
  Loop indices (`i`, `j`) are the exception.
- **Comments in English**, explaining *why* rather than restating the code.
- **Never bind a live reactive array directly to `Repeater.model`** — it crashes
  Quickshell. Use `ScriptModel { values: … }`, with `objectProp` as the identity key
  where delegates should be reused.
- **Never start a `Process` with a declarative `running: true`** — Quickshell writes
  `running = false` on exit and destroys the binding. Use `Component.onCompleted` or a
  `Timer`.
- **`ShapePath` has no `visible` property.**
- **Do not add a `qmldir`.** Quickshell registers types per directory automatically.
- **Only commit when explicitly asked.** Never commit proactively after making changes.

## Environment

Development happens in a dev container where **`quickshell` is not installed** — the
shell cannot be run or tested here. Changes have to be verified on the host machine.
