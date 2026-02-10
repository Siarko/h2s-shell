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

Three QML files compose the entire shell:

- **shell.qml** — Entry point. Uses `Variants` with `Quickshell.screens` to instantiate a `PanelWindow` (top-anchored, 40px bar) on every monitor. Contains a `FlexboxLayout` with a time display and four `Cell` widgets. Includes a `LazyLoader`-managed popup that toggles on cell interaction, positioned at the clicked cell's x-coordinate.

- **Cell.qml** — Reusable interactive widget. A colored rectangle with `MouseArea` that emits `plonked(color)` on click and `hover(bool)` on enter/exit. Uses flexible layout properties to fill available space.

- **Time.qml** — `pragma Singleton`. Wraps `SystemClock` to expose a `time` property formatted as `"hh:mm:ss"` with second precision.

## Key Patterns

- **Multi-monitor**: `Variants` + `Quickshell.screens` creates per-screen panel instances
- **Signals**: Cell uses Qt signal/slot pattern (`plonked`, `hover`) for parent communication
- **Lazy loading**: Popup window only instantiates when `LazyLoader.active` is true
- **Singleton**: Time.qml uses `pragma Singleton` for shared state across components

## Dependencies

- Quickshell runtime
- Qt 6 (QtQuick, QtQuick.Layouts)
