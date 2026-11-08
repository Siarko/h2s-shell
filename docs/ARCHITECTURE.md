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

On the desktop the shell is started by `scripts/launch.sh` (Hyprland's autostart calls
it): Quickshell takes the icon theme only at launch, from `QS_ICON_THEME`, and the script
sets it from the `appearance.iconTheme` setting — the system's theme or the first one
installed when that is empty. `launch.sh --restart` restarts the shell the same way, which
is what the setting's "Restart to apply" runs — a shell that does not answer is
terminated by its process id; `--list` and `--resolve` print the installed themes and
the one that would be used, `--preview <theme>` the files of a few sample icons, which
the settings show as images (`singletons/IconThemes.qml` asks it). The script marks the
shell it starts with `H2S_SHELL_LAUNCHER=1`; a shell started without it (plain `qs`)
shows a banner under the bar (`hud/StartupWarning.qml`, placed by `Hud.qml`) explaining that the icon theme
cannot apply — it does not restart itself, which would drop the arguments it was given.

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
shell.qml                 process root — one Bar, one Hud, one ScreensaverSurface per screen; the settings window
├── Bar.qml               the panel window: widget rows + the popup
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

`SettingsWindow` is the exception: one instance for the whole shell, in `shell.qml`,
opened with `Shell.openSettings(category)` and toggled with `Shell.toggleSettings()`, and
over IPC (`qs ipc call settings open | openPage <page id> | toggle | close`, in `shell.qml`).

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

The network managers are the exception to polling: `singletons/network/NetworkEvents.qml`
keeps one `nmcli monitor` running and emits `changed()` when NetworkManager's state
changes, and they re-query then (with a slow fallback poll).

`splitMarker: "\n"` reads line-wise; `splitMarker: ""` accumulates raw chunks (used
where the output is one value, as in `singletons/hardware/GpuDevice.qml`).

A `Process` must never be started with a declarative `running: true` binding —
Quickshell writes `running = false` when the process exits, which destroys the
binding. Start it from `Component.onCompleted` or a `Timer` instead.

`singletons/Stt.qml` is the one exception to the whole idiom: it is the only user of
`Socket` from `Quickshell.Io`, holding a long-lived Unix-socket connection with a 2 s
reconnect loop.

### Config and profiles

Settings live in **shell profiles**; the design is in
[plans/global-profiles.md](plans/global-profiles.md).

- `singletons/SettingsSchema.qml` lists every setting: key (`media.visualizerStyle`,
  `bar.left`, `widgets.music.popupMode`, …), label, type, default, settings page group,
  and optionally `global: true` (never per profile — debug switches, the dictation
  socket) and `legacy` (where it lived in a config file written before profiles). The
  defaults together are the built-in **system profile**.
- A **profile** is a named list of overrides with a condition (`when`) over live facts:
  battery, battery level, power profile, lock state, fullscreen, open popup. Active
  profiles layer in list order over the system profile; the user can also pin a setting
  as global, which no profile changes. `singletons/ProfileRules.qml` holds the pure logic
  (conditions, layering, migration) and has its own tests.
- `singletons/Profiles.qml` evaluates them: **read any setting with
  `Profiles.value(key)`** in a binding — it follows profile switches. It also seeds new
  configs with Full and Power save, applies the system power profile, and migrates old
  configs once. Facts can be simulated with `qs ipc call profiles simulate '{…}'`.
- Settings pages edit the profile picked in the settings sidebar through
  `panels/settings/SchemaSettingEditor.qml`, which shows where a value comes from
  (set here, inherited from a profile above, default, global) with a pin and a reset.
  A new setting is a schema entry, a `Profiles.value()` reader, and usually one editor
  line on its page.

`singletons/Config.qml` wraps a `FileView` with a `JsonAdapter` over
`~/.config/h2s_shell/config.json`. It holds the profiles and globals (as JSON strings),
the widget preset library (`widgetPresets`), and data that is not a preference: the
Google account and tokens, the chosen calendars, remembered per-app volumes. Writes are
debounced 1 s by `_saveTimer`, which then emits `Config.saved`; `Config.ready` turns true
once the file has been read, and `Config.readOnly` (set by `tests.qml`) keeps the test
suites from writing the user's file.

### Version

`singletons/Version.qml` holds the version number (semver) and what the settings sidebar
shows: the number alone on a tagged release, otherwise the number plus the commit from
`git describe` (`1.0.0+9d98c91`, `.dirty` with uncommitted changes). Releases are
recorded in `CHANGELOG.md` and tagged `v<number>`; `Config` stores the version that last
wrote the file (`writtenBy`).

### Bar composition

The bar is three sections, each a profile setting — `bar.left`, `bar.center`,
`bar.right` — holding a list of entries:

```
[{ "type": "power", "preset": "" }, { "type": "workspaces", "preset": "default" }]
```

`ProfileRules.sectionModel()` gives each entry a key that only changes with the entry, a
`Repeater` over a `ScriptModel { objectProp: "key" }` drives a `Loader` per entry (so a
profile change elsewhere keeps the widgets), and the `Loader` gets the widget's file from
`WidgetRegistry.widgetUrl(type)`. Geometry is `bar.layout.*`, popup mode is
`widgets.<type>.popupMode`.

A **preset** is a named set of one widget type's settings in the shared library
`Config.widgetPresets`, `{ type: { name: { … } } }`, so the same widget type can appear
twice with different settings (two clocks with different formats, two hardware capsules
showing different sensors). Presets are not per profile; a profile picks which preset an
entry uses. `singletons/WidgetPresets.qml` is the one place that parses and
writes the library and holds each type's defaults; it also lists where a preset is used,
and renames or deletes it while repointing the bar entries of every profile.

### Popup

There is exactly one popup window per Bar. `panels/Popup.qml` is a `LazyLoader` around
a full-screen transparent `PanelWindow` whose `mask: Region` restricts input to the
visible card, so the rest of the screen stays click-through. `open(element, persistent,
contentType)` records the trigger cell's x position and width, `contentType` selects the
panel — from `Popup._componentMap` for the two that need wiring, otherwise by URL from
`WidgetRegistry.popupPanelUrl()` — and the card animates its height from 0.

`persistent: true` means click-to-close; `persistent: false` means the popup closes as
soon as the pointer leaves it, via `HoverHandler`.

### The Repeater crash

For months the shell crashed at random — a SIGSEGV, usually when a popup opened. It was
traced in May 2026 to a Qt 6.11 regression in `QQmlDelegateModel`, the model behind every
`Repeater`. Two rules come out of it, and both are load-bearing.

**What happens.** A `Repeater` created inside an asynchronous incubation (`LazyLoader` →
`PanelWindow` → `Loader` → panel, which is exactly how popup content is built) can end up
with an invalid internal delegate reference. The object finishes loading and looks fine;
the corruption only bites later, the next time the model changes and `regenerate()` runs.
It always dies at the same place: `libQt6QmlModels.so.6 + 0xa758e`, with
`QQuickRepeater::regenerate()` on the stack. If `QQmlObjectCreator::finalize()` is also on
the stack the crash happened during incubation; if the stack goes through
`sendPostedEvents` instead, it is a model corrupted earlier, crashing from the event loop.

**Rule 1 — popup content is created outside the incubation.** `panels/Popup.qml` does not
bind `contentLoader.sourceComponent`; it assigns it in `Qt.callLater` from the window's
`Component.onCompleted`, so panels and their Repeaters are first built on the main event
loop after the `PanelWindow` has finished incubating. Two earlier fixes failed because
they only deferred *setting the model*, not *creating the Repeater*.
`MusicPanel`, `BluetoothPanel`, `NetworkPanel` and `AudioChannelRow` additionally hold a
`_ready` guard set via `Qt.callLater`, as a second line of defence.

**Rule 2 — never bind a live array straight to `Repeater.model`.** Every reassignment of
the array resets the model and runs `regenerate()`, the crashing path. Wrap it in
`ScriptModel { values: … }`, with `objectProp` as the identity key where delegates should
be reused; ScriptModel diffs the values instead of resetting. A literal constant array
(`model: ["Day", "Week", "Mon"]`) never changes and is fine.

**If it comes back:** look for a new `Repeater` whose `model` is a live expression,
especially inside anything a popup loads, and for any path that builds popup content
during the `PanelWindow` incubation.

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
| `widgetType` | the type string, matching the `WidgetRegistry` entry |
| `popup` | the Bar's `Popup`, if it has one |
| `preset` | the name of its widget preset, assigned by the Bar's `Loader` |

`widgetType` is declared on `BarWidget` itself. A widget whose content has several click
targets of its own (the tray, the workspaces) sets `interactive: false`, which keeps the
cell's size and background but disables its full-size `MouseArea` — otherwise that sits
above the content and takes every click and hover.

The bar can stand at any screen edge (`bar.edge`; `singletons/BarLayout.qml` says where,
for every widget, and `singletons/BarGeometry.qml` turns the theme's edge-relative tokens
into geometry). On a bar at a side `BarWidget.vertical` is true, the cell is as wide as the
bar and its height comes from its content. So that a widget works at every edge without
code of its own, it lays out its pieces with `components/BarRow.qml` (a row, or a column at
a side — its children set no anchors) and writes text with `components/BarText.qml`
(plain, or turned or stacked as `bar.verticalText` says; a single character stays
upright). A widget that animates a piece's size animates `BarText.length`, which runs
along the bar at any edge.

### Hardware sources

`singletons/hardware/HardwareSource.qml` is a non-instantiated template documenting the
interface every sensor must implement (`sourceId`, `label`, `unit`, `value`, `minValue`,
`maxValue`, `available`, `history`, `maxHistory`, `subtitle`, `showProgressBar`).

`singletons/Hardware.qml` is the registry: `sources` is the ordered list panels iterate,
`sourceIds` lists their ids for the settings UI, and `sourceForId()` resolves a source by
its id. Fixed ids: `cpu`, `ram`, `disk`, `cpuTemp`. Every GPU adds three more, keyed by
its PCI slot because `cardN` numbering can change between boots: `gpu@0000:03:00.0`
(load), `vram@…` and `gpuTemp@…`. The bare `gpu`, `vram` and `gpuTemp` of configs from
before multi-GPU support still resolve, to the primary card. User labels are stored under
the configured id, so look them up with `Hardware.displayLabel()`; a label of only a space
deliberately shows as blank.

Sources poll with `singletons/polling/PollTimer.qml`, their interval bound to a
`Profiles.value("polling.<category>.interval")` setting (0 = paused, see
docs/plans/adaptive-polling.md), and keep their graph history with `History.append`.

Sources read procfs and sysfs through `singletons/io/KernelFile.qml`, a `FileView` read
synchronously on every poll — no `cat` subprocess, and values read in one tick come from
the same moment. Only things that are not a file still use a `Process`: `df` for the
disk, and the one-time sensor discovery at startup.

`GpuDevices.qml` finds every amdgpu card once at startup, with its name from `lspci`,
its temperature sensor, and which one is primary (a dedicated card before an APU's
carve-out). `Hardware.qml` instantiates a `GpuCard` — load, memory and temperature
sources — per card.

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
  the identity key so only changed delegates are rebuilt. The history and the second
  rule that goes with it are in [The Repeater crash](#the-repeater-crash).
- **`ShapePath` has no `visible` property.**
- Only commit when explicitly asked.

## Adding a widget

Every bar widget type is one entry in `singletons/WidgetRegistry.qml`; the bar, the
section editor's picker and names, the widget settings pane and the popup all read it.

1. `widgets/<Name>Widget.qml` — the widget itself, setting `widgetType`. Extend
   `PopupWidget` if it opens a popup, otherwise `BarWidget`.
2. If it has a popup: the panel under `panels/`. It is loaded by URL, so it needs no
   wiring; a panel that must talk back to the popup (close it, know the screen) is the
   exception and goes in `Popup.qml`'s `_componentMap`, like the tray menu.
3. If it has per-preset settings: a page under `panels/widget_settings/` with
   `presetName` and `widgetType` properties (and `editIndex`, if it also edits profile
   settings).
4. One entry in `WidgetRegistry.entries` naming those files — the field list is in the
   comment at the top of that file.

Then run `quickshell -p tests.qml`: the WidgetRegistry suite checks that every file the
registry names exists and compiles. Global settings (a page under `panels/settings/`)
are still wired by hand in `SettingsWindow`'s navigation model and `sourceComponent`
if-chain.

## Testing

`tests/` holds a minimal harness (`TestCase.qml` with `assert`/`assertEqual`/`fail`) and
the suites `tests.qml` lists. Most run their assertions in `Component.onCompleted`, on pure
functions (the `*Rules` and geometry singletons, parsers). A suite that throws counts as
failed, not as missing.

A suite that needs the event loop sets `asynchronous: true`, does its work in
`runAsync()` and calls `finish()`; `tests.qml` lists it in `_asyncSuites` and waits for it
(20 s at most). `PointerInputTest.qml` is one: it puts real components (`BarWidget`,
`PopupWidget`) in a small layer window and drives them with QtTest's `TestCase` used by
hand (`when: false`) — `mouseMove`, `mouseClick`, `touchEvent` — to check what a mouse and
a finger do. It needs a Wayland session (the window shows in a corner for a moment). A
stylus cannot be sent that way.

Everything else is verified by hand: run `quickshell` from the repo root and check that
the bar renders, the clock ticks, cells respond, and popups toggle. There is no
automated coverage of any singleton that touches the system.
