# Architecture

Technical reference for the H2S Quickshell desktop shell. For what the shell does from
a user's point of view see [FEATURES.md](FEATURES.md); for the known problems and the
cleanup backlog see [CLEANUP.md](CLEANUP.md).

## Runtime model

This is not a compiled application. [Quickshell](https://quickshell.outfoxxed.me/)
interprets the QML directly, so there is no build step:

```
quickshell                 # reads shell.qml from the current directory
quickshell -p tests.qml    # runs the test suites, prints PASS/FAIL, exits
```

The target compositor is Hyprland on Wayland. The shell uses Wayland layer-shell
surfaces (`PanelWindow`, `WlSessionLock`) and talks to the session over DBus
(notifications, MPRIS, system tray), Pipewire (audio), and `nmcli`/sysfs subprocesses
(network, hardware).

Qt 6 is required: QtQuick, QtQuick.Layouts, QtCore, plus the Quickshell modules
`Quickshell`, `Quickshell.Io`, `Quickshell.Wayland`, `Quickshell.Hyprland`,
`Quickshell.Services.{Notifications,Mpris,Pipewire,SystemTray}`, `Quickshell.Bluetooth`.

### Module resolution

Quickshell exposes every uppercase QML file in a directory as a type under
`import qs.<dirname>` (`qs.widgets`, `qs.panels`, `qs.singletons.network`, …). There is
no `qmldir` anywhere in the repo and none should be added — registration is automatic.

Two consequences worth knowing:

- A file with `pragma Singleton` becomes a singleton; the same directory can also hold
  ordinary instantiable components (`singletons/network/LinkSpeed.qml`,
  `singletons/hardware/HardwareSource.qml`).
- Types in the *same* directory resolve without any import at all —
  `singletons/Time.qml` references `Config` with no import line. Several files still
  import their own directory explicitly; that is redundant but harmless.

Singletons are created lazily, on first reference. A singleton that nothing touches
never runs its timers — which is why hardware polling only costs anything when the
hardware widget or panel is actually in use.

## Layers

```
shell.qml                 process root — one Bar, one Hud, one ScreensaverSurface per screen
├── Bar.qml               the panel window: widget rows + the popup + the settings window
│   ├── widgets/          bar cells (clock, network, …) — thin, read singletons
│   └── panels/Popup.qml  the single popup window, lazily loaded, hosts one panel at a time
│       └── panels/       popup content (NetworkPanel, MusicPanel, Calendar, …)
├── Hud.qml               click-through overlay: toasts, volume OSD, queue badge
│   └── hud/
├── screensaver/          screensaver surface + the WlSessionLock surface and prompt
├── components/           reusable building blocks (BarWidget, Logger, sliders, cards)
└── singletons/           all shared state and all I/O
    ├── network/          nmcli/sysfs-backed network state
    ├── hardware/         sysfs-backed sensor sources
    └── googlecalendar/   Google Calendar API client and OAuth
```

The intended rule is **state and I/O live in singletons; QML under `widgets/`,
`panels/` and `hud/` only renders it and calls singleton methods**. Widgets are meant
to be thin. Most are; the large panels are where that rule has eroded (see CLEANUP.md).

### Per-screen instantiation

`shell.qml` drives three `Variants` over `Quickshell.screens`, so a Bar, a Hud and a
ScreensaverSurface exist per monitor. Only one popup may be open across all screens:
each `Bar` emits `popupOpened`, `shell.qml` records it in `activeScreen`, and every
other Bar closes its own popup when `activeScreen` stops matching its own screen.

`SettingsWindow` is also instantiated inside `Bar.qml`, which means one instance *per
monitor* — see CLEANUP.md #6.

## Key patterns

### Process + SplitParser is the universal I/O idiom

Almost every external read follows the same shape — a `Timer` drives a `Process`,
`SplitParser` accumulates lines, and the parse happens when the process exits:

```qml
Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!proc.running) proc.running = true
}

Process {
    id: proc
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device", "status"]
    property var _lines: []
    stdout: SplitParser {
        splitMarker: "\n"
        onRead: line => { if (line.trim() !== "") proc._lines.push(line) }
    }
    onRunningChanged: if (!running) { root._parse(_lines); _lines = [] }
}
```

`splitMarker: "\n"` reads line-wise; `splitMarker: ""` accumulates raw chunks (used
where the output is one value, as in `singletons/hardware/GpuDevice.qml`).

A `Process` must never be started with a declarative `running: true` binding —
Quickshell writes `running = false` when the process exits, which destroys the
binding. Start it from `Component.onCompleted` or a `Timer` instead.

`singletons/Stt.qml` is the one exception to the whole idiom: it is the only user of
`Socket` from `Quickshell.Io`, holding a long-lived Unix-socket connection with a 2 s
reconnect loop.

### Config

`singletons/Config.qml` wraps a `FileView` with a `JsonAdapter` over
`~/.config/h2s_shell/config.json`. Nested `JsonObject` blocks are exposed through
`property alias`, so the rest of the shell reads and writes `Config.bar.layout.barHeight`
and the adapter persists it. Writes are debounced 1 s by `_saveTimer`, which then emits
`Config.saved`.

Defaults live in the adapter declaration, so a missing key in the JSON file is simply
the declared default and no migration step is needed.

Several values are stored as **JSON strings inside the JSON config** rather than as
structured objects — `widgetProfiles`, `audio.appVolumes`, and the bar's
`leftProfiles`/`centerProfiles`/`rightProfiles`. Every reader therefore calls
`JSON.parse` itself, usually inside a property binding. There are ~50 such call sites.
This is the single most pervasive piece of technical debt in the project; see
CLEANUP.md #4.

### Bar composition

The bar is three sections (`left`, `center`, `right`), each a list of widget type
strings in `Config.bar.content`, zipped with a parallel list of profile names:

```
Config.bar.content.left         = ["power", "settings", "workspaces"]
Config.bar.content.leftProfiles = "[]"        // JSON array, index-aligned with the above
```

`Bar._zipModel()` merges the two into `[{ type, profile }]`, a `Repeater` drives a
`Loader` per entry, and `Bar._widgetMap` maps the type string to a `Component`.

A *profile* is a named per-instance override, so the same widget type can appear twice
on the bar with different settings (two clocks with different formats, two hardware
capsules showing different sensors).

### Popup

There is exactly one popup window per Bar. `panels/Popup.qml` is a `LazyLoader` around
a full-screen transparent `PanelWindow` whose `mask: Region` restricts input to the
visible card, so the rest of the screen stays click-through. `open(element, persistent,
contentType)` records the trigger cell's x position and width, `contentType` selects the
panel from `Popup._componentMap`, and the card animates its height from 0.

`persistent: true` means click-to-close; `persistent: false` means the popup closes as
soon as the pointer leaves it, via `HoverHandler`.

### Widget contract

A bar widget extends `components/BarWidget.qml`, which provides the cell background,
hover state, and the `clicked` / `hover` / `scrolled` / `scrollNotch` / `middleClicked`
signals. Children go into a zero-sized centred `contentItem`, and the cell's width comes
from `contentItem.childrenRect.width + 16` — which is why a widget cannot draw a
full-width child of its own without a binding loop (hence `borderColor`/`borderWidth`
on BarWidget itself).

By convention a widget declares:

| property | purpose |
|---|---|
| `widgetType` | the type string, matching the `_widgetMap` key |
| `popup` | the Bar's `Popup`, if it has one |
| `profile` | the active profile name, assigned by the Bar's `Loader` |

This contract is only loosely followed: four widgets omit `widgetType` and `TrayWidget`
is a bare `Row` rather than a `BarWidget` (CLEANUP.md #7).

### Hardware sources

`singletons/hardware/HardwareSource.qml` is a non-instantiated template documenting the
interface every sensor must implement (`sourceId`, `label`, `unit`, `value`, `minValue`,
`maxValue`, `available`, `history`, `maxHistory`, `subtitle`, `showProgressBar`).

`singletons/Hardware.qml` is the registry: `sources` is the ordered list panels iterate,
and `sourceForId()` resolves a source by its id. Current ids: `cpu`, `ram`, `disk`,
`cpuTemp`, `gpu`, `gpuTemp`.

`GpuDevice.qml` is a non-source helper that decides *which* DRM card the two GPU sources
read, so they cannot disagree. It is deliberately absent from `Hardware.sources`.

### Promises

`singletons/Promises.qml` is a hand-rolled promise implementation (`create`, `resolved`,
`rejected`, `allSettled`, `await`), used by `singletons/network/Fetch.qml` and the Google
Calendar client. It predates and substitutes for native async/await in this QML runtime.

`Promises.await()` busy-waits on `while (waiting) {}` and will hard-freeze the entire
shell if given a promise that is not already settled. See CLEANUP.md #1 — this is the
most serious known defect in the project.

### Logging

`components/Logger.qml` gives each subsystem a prefixed, individually switchable logger:

```qml
Logger { id: logger; prefix: "[STT]"; enabled: Config.stt.debug }
```

`log()` and `warn()` respect `enabled`; `error()` always prints. Debug switches exist as
`Config.general.debug`, `Config.general.fetch_debug`, `Config.gcal.debug` and
`Config.stt.debug`. A handful of files still call `console.log` directly, bypassing this.

## Conventions

- **Colours and type sizes come from `singletons/Theme.qml`.** Nothing else should
  contain a literal colour. ~37 places still do.
- **Full variable names.** `calendar`, `response`, `calendarId` — not `c`, `r`, `cid`.
  Loop indices (`i`, `j`) are the exception.
- **Comments in English**, explaining *why* rather than restating the code.
- **Never bind a live reactive array straight to `Repeater.model`** — it crashes
  Quickshell. Wrap it in `ScriptModel { values: … }`, optionally with `objectProp` as
  the identity key so only changed delegates are rebuilt.
- **`ShapePath` has no `visible` property.**
- Only commit when explicitly asked.

## Adding a widget

A new bar widget currently has to be registered in four places, because the type string
is the key in four parallel maps:

1. `widgets/<Name>Widget.qml` — the widget itself, extending `BarWidget`.
2. `Bar.qml` — a `Component` wrapper plus an entry in `_widgetMap`.
3. `panels/BarSectionList.qml` — a display name in `displayName()` and the type in the
   picker's list of available types.
4. `panels/WidgetSettingsPane.qml` — an entry in `_settingsComponentMap` if it has
   per-profile settings, plus the `Component`.

If it also owns a popup panel, add the panel to `Popup._componentMap`, and if it needs
global settings, add a page under `panels/settings/` plus an entry in
`SettingsWindow`'s navigation model and its `sourceComponent` if-chain.

Collapsing these into one registry is CLEANUP.md #5.

## Testing

`tests/` holds a minimal harness (`TestCase.qml` with `assert`/`assertEqual`/`fail`) and
one suite, `PromisesTest.qml`. Suites run their assertions in `Component.onCompleted`;
`tests.qml` instantiates them and quits on the next event-loop tick.

Everything else is verified by hand: run `quickshell` from the repo root and check that
the bar renders, the clock ticks, cells respond, and popups toggle. There is no
automated coverage of any singleton that touches the system.
