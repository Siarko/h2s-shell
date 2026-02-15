# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Quickshell desktop shell configuration** — a custom desktop panel built with Qt/QML using the [Quickshell](https://quickshell.outfoxxed.me/) framework. It is not a compiled application; QML files are interpreted directly by the Quickshell runtime.

## Running

There is no build step. To run the shell:
```
quickshell
```
Quickshell looks for `shell.qml` in the current directory as its entry point. Testing is manual — verify the panel renders, time updates, cells respond to clicks, and popups toggle correctly.

## Architecture

QML files are organized into subdirectories by role. Quickshell auto-exposes uppercase QML files in subdirectories as types via `import qs.<dirname>`.

### Root (entry point + top-level shell)

- **shell.qml** — Entry point. Uses `Variants` with `Quickshell.screens` to instantiate a `Bar` on every monitor. Tracks `activeScreen` so only one popup is open at a time.
- **Bar.qml** — The main panel window. A top-anchored, 40px `PanelWindow` containing a `FlexboxLayout` with a time display and interactive `Cell` widgets. Includes a popup that toggles on cell interaction.

### `components/` (reusable building blocks)

- **Cell.qml** — Reusable interactive bar widget. A colored rectangle with `MouseArea` that emits `plonked(color)` on click and `hover(bool)` on enter/exit.
- **ArrowButton.qml** — Small clickable arrow used for calendar month navigation.
- **PopupCurve.qml** — Draws the curved corners connecting the popup to the bar edge.

### `panels/` (popup content widgets)

- **Popup.qml** — Lazily-loaded popup container. Manages open/close animations and delegates to content panels.
- **Calendar.qml** — Monthly calendar with day grid and month navigation arrows.
- **PowerMenu.qml** — Shutdown/restart/logout buttons that invoke shell scripts.
- **NotificationPanel.qml** — Scrollable list of desktop notifications with dismiss animations.

### `singletons/` (global shared state, `pragma Singleton`)

- **Theme.qml** — Centralized color palette for the entire shell.
- **Time.qml** — Wraps `SystemClock` to expose a `time` property formatted as `"hh:mm:ss"`.
- **Notifications.qml** — DBus notification server exposing a notification list.

### `scripts/` (shell scripts)

- **logout.sh**, **restart.sh**, **shutdown.sh** — Hyprland power management scripts.

## Key Patterns

- **Multi-monitor**: `Variants` + `Quickshell.screens` creates per-screen panel instances
- **Signals**: Cell uses Qt signal/slot pattern (`plonked`, `hover`) for parent communication
- **Lazy loading**: Popup window only instantiates when `LazyLoader.active` is true
- **Singleton**: Time.qml uses `pragma Singleton` for shared state across components

## Dependencies

- Quickshell runtime
- Qt 6 (QtQuick, QtQuick.Layouts)
