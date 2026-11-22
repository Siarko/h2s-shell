# Architecture

Technical reference for the H2S Quickshell desktop shell. For what the shell does from
a user's point of view see [FEATURES.md](FEATURES.md).

## Runtime model

This is not a compiled application. [Quickshell](https://quickshell.org)
interprets the QML directly, so the QML needs no build. One small helper program is
compiled ([The helper](#the-helper)):

```
quickshell                 # reads shell.qml from the current directory
scripts/build-helper.sh    # builds the helper (scripts/launch.sh does it when needed)
tests/run-unit.sh          # runs the unit suites (tests.qml), prints PASS/FAIL, exits
tests/run-unit.sh FormatTest LockRulesTest   # only the named suites
```

On the desktop the shell is started by `scripts/launch.sh` (Hyprland's autostart calls
it): Quickshell takes the icon theme only at launch, from `QS_ICON_THEME`, and the script
sets it from the `appearance.iconTheme` setting — the system's theme or the first one
installed when that is empty — and stays as the shell's supervisor, starting it again
when it dies (see "Lock screen", "Recovery"). `launch.sh --restart` restarts the shell the same way, which
is what the setting's "Restart to apply" runs — a shell that does not answer is
terminated by its process id; `--list` and `--resolve` print the installed themes and
the one that would be used, `--preview <theme>` the files of a few sample icons, which
the settings show as images (`singletons/IconThemes.qml` asks it). `--dev` (with a start or
`--restart`) starts the shell in development mode, handed to it as `H2S_SHELL_DEV_FLAG=1`:
only then does Quickshell reload the shell when one of its files changes
(`Quickshell.watchFiles`). `H2S_SHELL_DEV` (`1` on, `0` off), when set to either, decides over
the flag — `H2S_SHELL_DEV=0 launch.sh --dev` is off; `singletons/DevRules.qml` decides, and
the lock screen's driver sets `watchFiles` from it (and off while locked). Out of development
mode a file written in the shell's folder — an update, a module install, an editor — leaves
the running shell as it is until a restart. The flag is inherited by what the shell starts,
so the settings' restart keeps development mode; it is left by a restart with
`H2S_SHELL_DEV=0`, or by one from outside the shell's environment (a terminal, the
compositor's autostart). The script marks the
shell it starts with `H2S_SHELL_LAUNCHER=1`; a shell started without it (plain `qs`)
shows a banner under the bar (`hud/StartupWarning.qml`, stacked by `hud/StartupWarnings.qml`) explaining that the icon theme
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
no `qmldir` in the shell's own directories and none should be added — registration is
automatic. (Modules are the exception: a module directory is loaded by its `file://` URL,
never imported, and brings its own `qmldir` — whether it lies outside the shell's tree (an
installed module, the packaged built-in copy) or inside it, as the fixture modules under
`tests/fixtures/` and the built-in modules under `builtin-modules/` do; see
[Modules](#modules).)

Two consequences worth knowing:

- A file with `pragma Singleton` becomes a singleton; the same directory can also hold
  ordinary instantiable components (`singletons/network/LinkSpeed.qml`,
  `singletons/hardware/HardwareSource.qml`).
- Types in the *same* directory resolve without any import at all —
  `singletons/Time.qml` references `Config` with no import line. Several files still
  import their own directory explicitly; that is redundant but harmless.

### The helper

`helper/` is a CMake project: `h2s-helper`, C++17 on Qt 6 Core and DBus only, one program
with subcommands, for what Quickshell cannot do from QML (`h2s-helper screensaver`, the
`org.freedesktop.ScreenSaver` service, is the first). It is I/O only — it reports and acts on request; what the shell
does with a report is decided in `*Rules.qml`. The shell starts it as a child process and
talks to it in JSON lines, one object per line each way, on its standard input and output
(`Process` and `SplitParser`, as for any command); it ends when its standard input closes,
so it never outlives the shell, and nothing else can talk to it. `h2s-helper --version`
prints `{"version":"<the shell's version>","protocol":<n>}`; the protocol number changes
whenever a message changes meaning, and `singletons/HelperRules.qml` holds the number the
shell speaks: a helper with another is out of date, its features off. `h2s-helper ping`
answers `{"ping":…}` with `{"event":"pong","ping":…}` after a `{"event":"ready",…}` line;
the tests use it.

`scripts/launch.sh` finds the helper before starting the shell and hands its path to the
shell as `H2S_SHELL_HELPER` (empty: none). In this order: `H2S_HELPER`, a path (set and
empty: no helper at all); the checkout's own build — where the installation brings no
helper, or the checkout has built one; the installation's, `$H2S_SHELL_LIBEXEC/h2s-helper`.
A start never waits for a build: when the checkout's source changed since its build
(`scripts/build-helper.sh --status`), the binary there is handed over as it is and
`--if-changed` runs in the background (detached, niced) for the next start; with no binary
yet the shell starts without one. No build while the session is locked by a shell that
died, and none again for a source that failed to build. No helper: the shell runs without
it, and the launcher's log says so once per change of that outcome. `singletons/Helper.qml` runs `--version` once at start and keeps
the state (`missing`, `ready`, `outdated`, `failed`); a feature that uses the helper
checks `Helper.available`.

The helper runs as the user only — never through pkexec or sudo, and its build never as
root (`build-helper.sh` refuses). A privileged action goes through the root-helper path,
from a root-owned location, never one the user can write; `tests/run-helper.sh` checks that no escalation names the helper, its build or
its path.

`scripts/build-helper.sh` builds the checkout's `helper/` into
`${XDG_CACHE_HOME:-~/.cache}/h2s-shell/helper/<a hash of the checkout's path>/` (or
`--out <dir>`), never into the tree: it refuses a directory inside the checkout, a link,
one holding files it did not make, one not the user's, or one inside a directory the group
or others can write to, and makes it mode 700. The binary is renamed into place, so a
running helper keeps running; a stamp of the source (`helper/` and the script — not the
shell's version, which alone rebuilds nothing) beside it says whether `--if-changed` has
anything to do. The build is bounded (`--time-limit`, 300 s); a source that failed or ran
out of time is not tried again until it changes or the script is run without
`--if-changed`. It needs cmake,
a C++ compiler and Qt 6's development files (Core, DBus).

#### NixOS

`nix/package.nix` builds the helper as a derivation of its own (the flake's `h2s-helper`,
with the qtbase of the nixpkgs Quickshell is built with) into its
`libexec/h2s-shell/`; the package's `h2s-shell` command sets `H2S_SHELL_LIBEXEC` to it. The
shell's own files leave `helper/` out. A checkout run through `H2S_SHELL_DIR` uses the
package's helper unless it has built its own.

#### Arch

`install.sh` installs `cmake`, `base-devel` (the compiler) and `qt6-base` with the other
packages, and runs `scripts/build-helper.sh` as the user after the clone and at
`--update`; a build that fails is a warning, not the install's failure. After an update the
launcher rebuilds the helper in the background; the rebuilt one runs from the next start.

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
├── Hud.qml               click-through overlay: toasts and their badges, volume OSD, the shell's pill
│   └── hud/
├── screensaver/          screensaver surface + the lock surface and prompt (views of Lockscreen)
├── pam/                  the lock screen's own PAM configs, one per way of unlocking
├── helper/               the helper program (C++/Qt, CMake): what QML cannot do; built, not interpreted
├── components/           reusable building blocks (BarWidget, Logger, sliders, cards)
└── singletons/           all shared state and all I/O
    ├── network/          nmcli/sysfs-backed network state
    ├── hardware/         sysfs-backed sensor sources
    ├── lock/             the lock screen's adapters: PAM, methods script, logind, sleep inhibitor
    └── googlecalendar/   Google Calendar API client and OAuth
```

The intended rule is **state and I/O live in singletons; QML under `widgets/`,
`panels/` and `hud/` only renders it and calls singleton methods**. Widgets are meant
to be thin. Most are; the large panels are where that rule has eroded.

### Per-screen instantiation

`shell.qml` drives three `Variants` over `Quickshell.screens`, so a Bar, a Hud and a
ScreensaverSurface exist per monitor. Only one popup may be open across all screens:
each `Bar` emits `popupOpened`, `shell.qml` records it in `activeScreen`, and every
other Bar closes its own popup when `activeScreen` stops matching its own screen.

`SettingsWindow` is the exception: one instance for the whole shell, in `shell.qml`,
opened with `Shell.openSettings(category)` (`Shell.openSettingsAt(category, section)` with
a section of the page shown at the top, as the sleep notice opens the When away page's lock
screen section) and toggled with `Shell.toggleSettings()`, and
over IPC (`qs ipc call settings open | openPage <page id> | currentPage | itemRect <objectName> | toggle | close`, in `shell.qml`).

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

### VPN providers

A VPN is either a NetworkManager profile (by UUID) or an entry of a **VPN provider**
(by `"<providerId>:<entryId>"` — the colon never occurs in a UUID): an object extending
`components/VpnProvider.qml` that registers itself with `singletons/network/VpnManager.qml`
when made and leaves when destroyed. It reports `entries` (`{ id, name, state, attention,
detail, active, status, busy }`, in NetworkManager's state words, `detail` in the shape of
`VpnManager.details`), `busy`, `canChange`, and performs `connect`/`disconnect` (told who
asked: the user, or a network — then it must not prompt) and `attend`;
failures come back through its `failed` signal as the same notification NetworkManager's
get. Everything it reports is checked by `VpnProviderRules.vpnProviderEntries` (wrong entries
dropped and logged, never shown). `VpnManager.vpns`, `details`, `interfaceOf` and the rest
are the merged model the popup, the bar, the overview, the VPN page and the connection
editor read; with no provider registered they are NetworkManager's lists themselves. The
kill switch (`VpnLockdown`) reads `nmDetails`/`nmInterfaceNames` only — it does not support
provider VPNs, and says so on their cards (and rows, while up) while blocking. A provider's
module puts its elements under its VPNs' rows in the network popup and in their opened cards
through the own-provider places `popup.network.connections.vpn.row` and
`settings.network_vpn.vpns.card.settings` ("Modules", below; the old slots `network.vpn.row`
and `network.vpn.card` are read as them); its page is its `settingsPage`, else the slot
`network.vpn.page` (`VpnManager.pageOf`). A provider that is no module's (the stand-in) hands
over its own `rowExtras` and `cardExtras` (`VpnManager.ownExtrasOf`, built by
`components/VpnExtras.qml` beside the hosts) and `pageUrl`.
The contract is in `components/VpnProvider.qml`; the stand-in provider
for tests is `tests/FakeVpnProvider.qml` (by hand: a test tree started with
`H2S_FAKE_VPN_PROVIDER=1`, "The test tree" under "Testing"; IPC target `fakevpn`).

### Config and profiles

Settings live in **shell profiles**.

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
  `inline` puts it on one line — a section title's switch, a stage's times as pills after
  a lead word —; a number with `presets` in the schema is edited as pills.
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
`Repeater` over a `KeyedModel` of those keys drives a `Loader` per entry (so a profile
change elsewhere, or a widget added before it, keeps the widgets), and the `Loader` gets the widget's file from
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
the array resets the model and runs `regenerate()`, the crashing path. Wrap it in a
`ScriptModel`, which diffs the values instead of resetting. A literal constant array
(`model: ["Day", "Week", "Mon"]`) never changes and is fine.

**Rule 3 — a ScriptModel's values are strings or QObjects, never rebuilt JS objects.**
ScriptModel (Quickshell 0.3.2) finds inserts, removals and moves only among values that
are strictly equal. JS objects built anew on each read — a refetch, a rescan, a re-sort,
`map()` — are not: with `objectProp`, or the default structural comparison, it overwrites
every row after the first changed one by position. A removal in the middle then destroys
the *last* delegate and moves the later items into the earlier ones, each keeping its
state: text typed into one card's field ends up in the next item's card, an open edit form
saves to another record. A list of records goes through `components/KeyedModel.qml`:

```qml
KeyedModel { id: _networks; values: root._saved; keyProp: "uuid" }   // or keyOf: item => …
Repeater {
    model: _networks.model                     // a ScriptModel of string keys
    delegate: Card {
        required property string modelData     // the key
        readonly property var network: _networks.byKey[modelData] ?? null
    }
}
```

Each delegate keeps its item for its whole life, and a changed item reaches it through the
binding (`ListKeyRules` makes the keys, unique, and the map). Strings (`keysInGroup()`,
names) and QObjects (`SystemTray.items`, Bluetooth devices) compare strictly and go into a
ScriptModel as they are. `tests/QuickshellPinTest.qml` (g) pins the bug, so an upgrade that
fixes it is noticed.

**If it comes back:** look for a new `Repeater` whose `model` is a live expression,
especially inside anything a popup loads, and for any path that builds popup content
during the `PanelWindow` incubation.

### Shaders

Qt 6 loads only precompiled shaders. A shader's GLSL source and its compiled `.qsb` sit
side by side and both are committed (`wallpaper/shaders/transition.frag` and
`transition.frag.qsb`), so neither machine needs Qt's shader tools to run the shell. After
changing a source, compile it again on the host (Arch: `qt6-shadertools`):

```
/usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o transition.frag.qsb transition.frag
```

A shader runs only while it has work: the wallpaper's for the length of a transition,
the image drawn plainly before and after.

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
"Config and profiles"), and keep their graph history with `History.append`.

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
`rejected`, `allSettled`), used by `singletons/network/Fetch.qml` and the Google
Calendar client. It predates and substitutes for native async/await in this QML runtime.
There is no blocking `await`: QML is single-threaded, so waiting in a loop for a promise
would freeze the whole shell. Chain with `then`.

### Notifications and toasts

`singletons/Notifications.qml` is the notification server (`NotificationServer`, every
capability on: markup, links, images, actions, action icons, inline replies). It tracks
each notification it receives and records its arrival time and extracted codes.
`singletons/Toasts.qml` keeps the toasts: their screen, the shell's pill queue, the three
queues, modals, and what each screen's HUD takes. Every decision is in two pure singletons
with their suites:
`singletons/NotificationRules.qml` (a card's progress view and the wave, whether an action
also dismisses — not on a resident notification —, the shell's own sender's hints and
announces, orphans after a reload) and `singletons/ToastRules.qml` (which screen, how
long, which queue, and every change of the queues).

**The toast state** is one plain object of notification ids, `Toasts.toastState`
(`ToastRules.emptyState`'s shape): `waiting` and `shown`, each with the three queues
`critical`, `staying` and `ordinary` (ids oldest first — ids grow with arrival), and
`moved`, the modals (`{ id, queue, x, y, keep? }`: dragged out or pinned, x and y `null`
until placed). It changes only through the rules, each of which returns a new state, and
is always replaced, never mutated: a toast is on screen only while the state says so, so
no stale slot can show or hold one, and an answer from before a change cannot bring one
back. Beside it, by id: the notification objects, each toast's timing kind and time
(`toastKinds`, `toastDurations`) and the screen it went to (`toastScreens`). Derived from
it: `countingToasts` (`ToastRules.counting` — in the ordinary queue the sender's time at
once and the user's one at a time, the oldest first; elsewhere whatever no longer stays),
`toastBadges` and `hudQueue` (the waiting notification objects, oldest first). The flow:

- `ToastRules.timing` gives a notification's kind — `"default"` (the user's time), `"own"`
  (the sender's) or `"stays"` — from its expire timeout, urgency, the resident hint and
  the settings; the shell's own progress handles (hint `x-qs-progress-run`) are resident by
  make and are not taken as resident there. `queueFor` puts critical ones in `critical`,
  ones that stay in `staying`, the rest in `ordinary`; `limits` reads the three limits.
- `enqueue` lets a queue take a new toast when it can (`accepts`: toasts on, a screen for
  it, not an ordinary one while the centre is open, only critical ones under a fullscreen
  window with "Don't show"). Each screen's `ToastStack` pulls (`Toasts.takeToast`,
  `ToastRules.nextWaiting`/`show`): a queue with room shows its oldest waiting toast;
  queues never overtake each other.
- The notification changing (a job ending, a new time or urgency, a timing setting) runs
  `requeue`: a waiting toast moves to its new queue by age, a shown ordinary one that now
  stays goes up to its queue, a shown critical or staying one or a modal counts where it
  is. The centre opening runs `centreOpened` (only the ordinary queue goes), a fullscreen
  window with "Don't show" `fullscreenHid`, "Show toasts" off `dropWaiting`.
- A toast ends through `Toasts.toastGone` (its time ran out, an action, its
  notification closed) or `dismissToast` ("×" and the swipe: `notification.dismiss()`, so
  a job's handle learns it as from the centre).
- An announce from the shell's own sender (`NotificationRules.announced`) goes through
  `ToastRules.announceEffect`: on screen its time starts again, gone it queues like a new
  one.

**The HUD** (`Hud.qml`, one per screen) is a layer-shell overlay window over the whole
screen, the bar's reserved space too, and keeps everything it shows clear of the bar
(`BarGeometry.reservedInsets`). It takes no keyboard except while a toast's reply is
hovered or written. Its input mask is a `Region` per visible part: the toasts' strip
(`ToastStack`, as tall as its toasts and badges, left of the open centre when that stands
level with it — `ToastRules.stackEdge`, from the centre's rectangle each popup reports to
`Toasts.setCentreArea`), a `Region` per modal's toast (a `Variants` over
`ToastStack.modalToasts`, so the set follows modals as they come, go and move), the volume
OSD, the shell's pill and a startup warning while one shows. Everywhere else clicks pass
through.

`hud/ToastStack.qml` makes one `hud/NotificationHudItem.qml` per toast on its screen, from
a `KeyedModel` of ids: made when the toast shows, destroyed after it slid out (the leaving
ones are kept until then), so a toast keeps its countdown, its reply text and its swipe
while it changes place or becomes a modal. It places the three stacks (`onScreen`) and each
queue's badge (`badgeLook`; each bar answers a click by `badgeClick`: the centre opens
or closes on the badge's screen), and
gives a pinned modal its first place (`pinSpot`). A toast drags by its title line with a
`DragHandler` while `canMove` allows it; on release it is clamped inside its screen, off
the bar (`clampToScreen`), and becomes a modal (`moveOut`). A modal whose screen goes
waits in its queue again (`returnToQueue`); places are not kept over a restart. The card
itself is `components/NotificationCard.qml` (its header, pictures, progress bar, body and
swipe in `components/notification/`), shared with the centre
(`panels/NotificationPanel.qml`), which adds the pin (`pinToast`/`unpinToast`,
`ToastRules.pinLook`); a toast's countdown is an animation that pauses while held and
drives the card's timer bar (`ToastRules.showsTimer`). Nothing pauses under the lock
screen or the screensaver.

Notifications with category `x-qs-shell` are the shell's own short messages: not tracked,
they go to `Toasts.shellQueue` and `hud/ShellNotificationHudItem.qml` shows each
summary for 2.5 s in a pill at the bottom of the toasts' screen. `singletons/Notifier.qml`
sends the shell's notifications: a plain one with one `notify-send`, a progress one
through a handle (below, "Progress notifications").

### Lock screen

Four layers, so that what decides can be tested without what does (the rules and the
launcher agree on the contract described under "Recovery" below):

- **Rules** — `singletons/LockRules.qml`, pure: `initial(settings)` and
  `step(state, event, now) → { state, effects }` on plain objects that are replaced, never
  mutated; `view(state)` for the views, `describe(state)` for anything shown (no secret).
  Every decision is here — when a conversation starts, what a PAM answer means, where the
  prompt is, when the field empties, what sleep does. Below it, each pure as well:
  `LockStepRules.qml` (the constants and the primitives every change of a state goes
  through), `LockViewRules.qml` (`view`, `describe*`) and `LockParseRules.qml` (the
  methods script's and logind's lines); `LockRules` forwards what callers use of them.
  Unit-tested in `tests/LockRulesTest.qml` (behaviours, a seeded sweep, a liveness
  oracle), `tests/LockViewRulesTest.qml` and `tests/LockParseRulesTest.qml`.
- **Driver** — `singletons/Lockscreen.qml`, the one owner of the lock's state. It feeds
  events to the rules one at a time (`LockIoRules.serialQueue`: an event raised while a
  step's effects run is queued, never re-entered), stores the new state before running its
  effects, and carries the effects out (`LockIoRules.runStep`: each part guarded, so a
  view that fails to publish cannot keep the lock from being set): the `WlSessionLock`,
  one single-shot `Timer` per timer name (tokens from the rules), `Profiles.screenLocked`
  and `Quickshell.watchFiles` (`DevRules.watchFiles`: on only in development mode, and off
  while locked — a reload while locked would unlock), the
  adapters. It exposes only `view`, `locked`, `lock()`, the surface
  functions the views call (they take the `LockSurface` object and act only for a
  registered one), and the IPC (`lock`, `status`, `state` = `describe` plus a few driver
  facts). There is no unlock and no dispatch function: the state, queue and surface
  registry live in a closure (`_build()`), not in properties. Same-process QML is still no
  security boundary (it can emit its child objects' signals, or run `loginctl
  unlock-session`). It also owns
  the password fallback (`LockIoRules.passwordFallback`, from a probe of the machine).
- **Idle** — `singletons/Idle.qml` feeds the pure `singletons/IdleRules.qml` (input idle,
  the lock, sleep from `SystemSleep`, the profile's settings) and carries out what it
  returns: the picture per monitor (`shownFor(connector)`, which each screen's screensaver
  window follows: the screensaver, or plain black over a monitor turned off), the monitors'
  power (`ScreenPower.setPower`; every reading of `ScreenPower.monitors` is a `monitors`
  and a `power` event: an action a reading does not show is asked again with a growing
  pause; the monitors it turned off are remembered in `Config.screensOff`, so a restarted
  shell turns those, and only those, on again), the lock surface's black fallback
  (`lockBlack`; the lock screen's screen-off waits while `Lockscreen.attended`), the idle lock (`Lockscreen.lock("idle")`), the start and end commands. Another program's
  session lock read as held (`Lockscreen.foreignLocked`, `singletons/lock/ForeignLock.qml`
  around the pure `LockRules.foreignStep`) counts as locked for `IdleRules` and the
  `screen.locked` fact; it is read again with a growing pause until it ends (three
  unreadable answers in a row and it is no longer counted). Every lock the rules take on
  Hyprland but a restore waits for a read at `lockCompositor` (`ForeignLock.beforeAsk`;
  unanswered after 2.5 s it is unknown, and the lock is asked): another lock standing, the
  compositor is not asked (Hyprland ends a client that asks then) and the rules hear
  `foreignLocked` (the lock ends, a sleep inhibitor is released); so the marker's "locked"
  means a lock of the shell's own. The start and a refusal read too.
  Its two `IdleMonitor`s (`singletons/lock/IdleWatch.qml`: one ignoring Wayland idle
  inhibitors, one respecting them) are made once with a fixed 5 s, so a settings change
  never ends an idle period; every stage counts from the last input. One `Timer` runs to
  the rules' next deadline. Apps keeping the screen on reach it three ways, all events
  for the rules (which count them only while unlocked): the second `IdleMonitor` (Wayland
  inhibitors), `singletons/helper/ScreenSaverClient.qml` (runs `h2s-helper screensaver`,
  which owns `org.freedesktop.ScreenSaver` when the name is free and queues for it when
  another program holds it — only while one of the shell's idle stages is on
  (`HelperRules.wantsScreenSaverName`; otherwise it releases the name and leaves the
  queue) — and reports the apps' requests and the name's owner —
  `HelperRules.serviceStatus`), and a logind `idle` block read at the deadlines that would
  start a stage (`singletons/lock/LogindIdleBlock.qml`, `ListInhibitors`). The sleep after
  idle is a stage of the whole machine: `singletons/lock/LogindSleep.qml` reads logind's
  `CanSuspend` and `IdleAction` (at the start and when the page opens; the stage exists only
  on "yes") and makes the one call, `Suspend(false)` (non-interactive: never a password
  prompt), when the rules return `sleep`; the same `ListInhibitors` read gives logind's
  `sleep` blocks, which the rules take in the same step, locked or not. A sleep the settings
  leave unlocked is flagged (`Idle.sleepLeftUnlocked`) for the sleep notice, which then
  does not count it. IPC: `idle state` (JSON, with the monitors' ids) and
  `idle setMonitorTimes <id> <json|default>` (one monitor's entry in
  `lockscreen.monitorIdle`, `IdleRules.withMonitorTimes`).
- **Adapters** — `singletons/lock/`, thin: I/O to events, effects to I/O, no decisions.
  Per lock (`LockScope.qml`, created when a lock begins and destroyed when it has ended,
  so destruction is the cleanup): `PamMethod.qml` (one `PamContext` per method,
  conversations tagged with the rules' id, a refused `start()` reported, stale or second
  answers dropped) and `MethodDetector.qml` (one run of `scripts/lock-auth-methods.sh`,
  tagged with its generation; a newer run destroys, so kills, the older; exit 0 is an
  answer, also "no fingerprint here", non-zero a question it could not answer, such as
  fprintd stuck — the script asks fprintd over D-Bus with a 4 s deadline — and what it
  says on stderr is logged). For the shell's
  lifetime: `LogindMonitor.qml` (one `gdbus monitor`, parsed by `LockRules.parseLogind`,
  restarted with a growing pause, kept from outliving a crashed shell by a stdin watcher),
  `SleepInhibitor.qml` (`systemd-inhibit` held as a level, taken again when lost) and
  `LockedHint.qml` (`SetLockedHint` on the session for the rules' `reportLockedHint`: true
  at the compositor's confirmation, false when a confirmed lock ends and at the start (a hint
  left true by a crashed shell); one call at a time,
  the latest value wins, a failure logged once and not retried).
  Their small pure helpers are in `singletons/LockIoRules.qml` (tested in
  `tests/LockIoRulesTest.qml`).
- **The sleep notice** — `singletons/SleepLockNotice.qml`, beside the driver: it tells the
  user, by the outcome of each sleep, when the screen was not locked while the computer
  slept — no locker is named. While awake it holds a sleep delay inhibitor of its own (a
  second `SleepInhibitor`, "Check the screen is locked before sleep"); at PrepareForSleep it
  looks: the shell's own lock confirmed by the compositor, else
  `singletons/lock/SleepLockState.qml` (`hyprctl -j locked` on Hyprland, and logind's
  LockedHint for the session, decided by `LockIoRules.sleepLockState`: the compositor's word
  first, a LockedHint true is locked, false or a failed read unknown; hyprctl and gdbus a
  second each). It reads again every 250 ms until `SleepNoticeRules.look` ends the look:
  at once when locked, "unlocked" only at its 1 s deadline, the shell's own lock on its way
  waited for while the lock's inhibitor holds (unknown past that, never unlocked); then the
  inhibitor is let go. After the resume the outcome (locked, unlocked, unknown) goes to
  `SleepNoticeRules.step` (the cycle quiet → shown → waiting, tested in
  `tests/SleepNoticeRulesTest.qml`): a critical notification, closed means acknowledged, a
  line in the When away page's lock screen section while it waits for a sleep that locks
  (the notification's click opens it there: `Shell.openSettingsAt`). The state is kept in
  `Config.sleepLockNotice` (JSON). The reading runs against stand-ins in
  `tests/SleepLockStateReadingTest.qml`, the whole in the lock bed's `sleep-notice`. Not
  covered: off Hyprland, a locker that does not set LockedHint reads as unknown (nothing
  said); a locker that locks only after the look reads as unlocked.
- **Views** — `screensaver/LockSurface.qml` (one per screen, an instance with its own id)
  and `screensaver/LockPrompt.qml` render `Lockscreen.view` and report input. Keys arrive
  in one place per surface — a key catcher that holds the focus; the field never takes it
  — and reach the field as the rules' `forwardKey` effects (`LockIoRules.editField`). The
  catcher is a hidden, input-method-enabled `TextInput` (password hints, invisible), so text
  Qt composes — dead keys, Compose sequences, an input method's commit — arrives too: sent
  on as a `key` with that text and emptied from the catcher at once. Pointer motion counts
  only where the pointer really moved (`LockIoRules.pointerMoved`), so a surface appearing
  under a resting pointer does not wake the prompt. The catcher lies outside the surface and
  the surface's `MouseArea` keeps every button but the left from what is under it: a
  middle click on a text input pastes the primary selection. Caps Lock (Qt does not report
  it) is read from the keyboards' LEDs by `singletons/lock/CapsLockLed.qml`
  (`/sys/class/leds/*::capslock/brightness`, when the prompt wakes and at each key; no LED,
  no indicator), exposed by the driver as `capsLock` and said on the prompt.
  Notifications are listed by `screensaver/NotificationList.qml`
  (plain text, nothing to act on; the lock screen's detail is "app only" by default).

**Fail closed against the compositor**: ext-session-lock-v1 makes an unlock before the
compositor's `locked` a protocol error, and Quickshell sends one whenever
`WlSessionLock.locked` is set false before `secure`. So the rules emit `unlockCompositor`
only for a session the compositor confirmed: an unlock decided while locking (a password,
logind's Unlock) is pending until `compositorLocked`, and a slow confirmation is
only reported — the lock is never set again or given up.

**The Quickshell bug worked around**: Quickshell 0.3.2 never emits `lockStateChanged`
when a `WlSessionLock` unlocks (`src/wayland/session_lock.cpp`), so a binding to its
`locked` stays true after the first unlock — the old lock screen worked once per shell.
(Fixed in Quickshell's master after 0.3.2, in no release yet.)
The driver never binds or watches `locked`: it sets it in the `lockCompositor` /
`unlockCompositor` effects, reads it back only right after setting it true (to catch a
refused lock), and takes the compositor's word from `secureStateChanged`, tagged with the
session of the last `lockCompositor`.

**Recovery** (a reload or a restart never comes up unlocked over a locked
session). What the driver does about the marker, taking a lock back and asking again is
decided by `singletons/LockRecoveryRules.qml`, a pure state machine like the rules (one
case per recovery scenario of the lock test bed in `tests/LockRecoveryRulesTest.qml`):

- *A reload while locked* keeps the lock. Quickshell hands a reloaded singleton's children
  their old instances by position; a `PersistentProperties` (`_carried`: "this process holds
  a compositor lock", "the compositor confirmed it") placed before the `WlSessionLock` gets
  its `reloaded` first, and sets the new `WlSessionLock`'s `locked` before Quickshell
  realizes it — so it takes the old lock over instead of unlocking. The rules go on from
  their `restored` event (a fresh lock on the carried compositor lock: no new lock request,
  fresh adapters, methods asked again, nothing typed before survives). File changes still do
  not reload while locked (`watchFiles` off: a new generation starts with Quickshell's
  default, on, and the driver sets it as `_carried` loads — off while it says locked); in development
  mode edits made meanwhile take effect at the next file change after the unlock (no reload
  at unlock: it dropped lock requests). A reload that cannot carry the lock (a hard reload, `reload(true)`)
  leaves Quickshell's process-wide lock manager with a stale lock: the process quits
  (status 1) and the launcher starts a fresh one, which the marker locks.
- *A shell that stops while locked* — crash, SIGKILL, `qs kill`, `--restart` — comes back
  locked. The driver writes a lock marker (`$XDG_RUNTIME_DIR/h2s-shell-lock`: "locked
  <key>" from the lock request to the end of the lock, the key naming this compositor
  session: boot id, display, socket identity); a starting shell that finds "locked" for its
  session locks at once (a marker of another boot or compositor is stale and ignored).
  `scripts/launch.sh` supervises the shell, one supervisor per session (a `flock` on
  `$XDG_RUNTIME_DIR/h2s-shell-launcher.lock`): it runs it as a child (in a process group of
  its own), waits for it to end (a stopped shell is left alone), and starts it again when it
  dies, not when it was stopped on purpose (clean exit or SIGTERM/INT/HUP while unlocked;
  SIGUSR1 to the launcher lets the shell go, which `--restart` does — to the lock's holder
  even when no shell is alive), nor once its compositor is gone (another socket, or nobody
  holding `<socket>.lock`); with a growing pause. A shell that died while the screen was
  locked (the marker says so) is started again at most 3 times while the session stays
  locked; the fourth death ends the launcher, the compositor keeping the session locked
  (the launcher is then started again by hand from a text console; FEATURES, "The limit
  while locked"). "While the session stays locked": the launcher writes its count
  to `$XDG_RUNTIME_DIR/h2s-shell-lock-restarts` at each such restart, and the shell overwrites
  it when a lock ends (with the marker's "unlocked") — anything but the launcher's own number
  there is an unlock; a new launcher starts at 0. Giving up, it leaves its count in
  `$XDG_RUNTIME_DIR/h2s-shell-lock-notice`; the next launcher removes that file and hands
  the count to its first shell only (`H2S_SHELL_LOCK_NOTICE`), where `LockNotice` sends one
  notification (`LockIoRules.lockNotice`) once the session is unlocked. Deaths outside the lock:
  at most 5 restarts in 2 minutes (deaths under the lock not counted). It kills what the dead shell left of
  Quickshell's own binary in that group (PAM helpers, which would keep a fingerprint reader
  claimed; not the crash reporter). SIGHUP (its terminal closed) does not stop it. Quickshell's own crash handler restarts a crashed shell
  in the same process (unless it crashed within 10 s of starting): no second shell, and the
  launcher sees nothing — so the restarted shell itself kills, once, the PAM helpers its
  process had forked before the crash (`_helperSweep`).
- *A reload while unlocked* (a file saved in development mode) blocks the event
  loop for about two seconds and tears the old generation down: IPC calls get "Not ready"
  and logind's PrepareForSleep reaches no monitor. The launcher's `ipc` retries such calls
  (3 s); the new logind monitor asks logind's `PreparingForSleep` once it listens; the old
  generation's sleep inhibitor lingers 3 s after its holder vanished, so logind waits while
  the new generation locks.
- *The compositor will not give the lock back* (Hyprland without
  `misc:allow_session_lock_restore`): Hyprland refuses a new lock while a dead client's lock
  stands, and kills the client that asks. So under Hyprland the shell first asks `hyprctl`
  (the option, `locked`) and does not ask for a lock it would be refused: it reports
  `compositor-locked`, counts as locked for the rest of the shell, and looks again with a
  growing pause (5 s to 1 min) — the setting switched on at runtime brings the prompt back.

Where state lives: the lock's state only in the driver (in `_build()`'s closure, never
exposed — it holds the typed password between submit and PAM's prompt); the half-typed text
only in the prompt's field; the I/O handles in the adapters; across a reload, two booleans
in `_carried`; across a restart, the marker. The test bed's seams, read only in a test
tree ("Testing", below; the shell's own `singletons/TestSeams.qml` holds constants):
`H2S_LOCK_AUTH_METHODS` (read by the methods script), `H2S_LOCK_TOOLS` (a
directory whose `gdbus` and `systemd-inhibit` stand in for the real ones — the shell's
and the methods script's),
`H2S_LOCK_SYSTEM_PAM_DIR` (where the system-wide `h2s-shell-*` PAM configs are looked for,
`/etc/pam.d` otherwise — so a test shell's password fallback is never the real PAM stack),
`H2S_LOCK_SYSTEM=nixos|other` (which system the methods script — and the driver, where it asks the machine itself — takes itself to be on,
counted only together with `H2S_LOCK_SYSTEM_PAM_DIR` — so both systems' answers are tested
on every machine),
`H2S_LOCK_TEST_RELOAD=1` (an IPC target `locktest` whose `reload(hard)` asks for
`Quickshell.reload()`, which nothing in the shell calls), `H2S_LOCK_LEDS_DIR` (where the
Caps Lock LEDs are read, `/sys/class/leds` otherwise), `H2S_LOCK_TEST_TIMINGS` (JSON
overrides of `LockRules.timings`, so that minutes of PAM rounds run in seconds) and the
launcher's `H2S_LAUNCHER_TEST_TIMINGS` (its restart pauses, in seconds). Inside a test tree
one singleton reads the seams, `TestSeams` (the lock screen's above, the module host's
`H2S_SHELL_TEST_MODULE_*` and `H2S_FAKE_VPN_PROVIDER`; the list and what each value says:
`tests/lock/seams/TestSeamRules.qml`, tested by `tests/TestSeamRulesTest.qml`). When any is in force it logs one line,
`[TestSeams] test bed: <names>`, and `qs ipc call modules list` and the lock screen's
`state` (its `driver` block) carry them as `testSeams`. The two scripts take theirs from
`scripts/seams.sh` (constants), which a test tree replaces in the same way.

### Modules

Integrations as separate packages. The module API's reference
(the facade, the slot table, the anchors, the handle, the lifetime rules) is the header of `api/Api.qml`;
the manifest schema is in `singletons/ModuleManifestRules.qml`. The parts: the rules, the host, discovery,
the `qs.api` facade, the registries taking modules' contributions, slots and anchors. The
trust model ("Modules and trust") and where the built-in modules live ("Built-in modules")
close this section.

- A **module** is a directory with a `module.json` (the schema: `singletons/ModuleManifestRules.qml`'s
  header), a `qmldir` for its singletons, and QML loaded by `file://` URL —
  never imported statically (a broken one would fail the whole config). Every file the
  manifest names must be a regular file inside the directory (a link out of it, a FIFO, a
  file over 1 MiB: the entry is dropped, or the module fails for its main).
- **A module's icon** (the manifest's `icon`, API 1.26): a glyph of the shell's icon font (a
  private-use character, not a lock or no-entry sign), an SVG file (painted in its place's
  text colour unless `"colors": "own"`) or a PNG or WebP picture. Its file passes the same
  check — an SVG at most 64 KiB, a picture at most 256 KiB — and its content is read only to
  refuse what the renderer would follow out of the file: an SVG with any external reference
  (the renderer loads an `<image>` by path, through any image plugin; a FIFO there would stall
  every asynchronous image of the shell), a picture whose first bytes are not its name's type
  (`ModuleManifestRules.iconContentProblem`). It is drawn, never run. One component draws it everywhere,
  `components/ModuleIcon.qml` (a square as tall as a line of body text); a wrong icon, or a
  file that cannot be drawn, is an error in the module's status, and with none the first
  letter of the module's name stands in its place (`ModuleHost.icons`, the handle's `icon`).
- **Discovery**: `scripts/launch.sh` (`discover_modules`, before every start of the shell)
  builds `H2S_SHELL_MODULES` (the shell's input; the launcher's output) — canonical module
  directories from `H2S_SHELL_MODULE_PATH` (the developer's list), then
  `~/.local/share/h2s-shell/modules/*`, then the built-in modules' directory
  (`H2S_SHELL_BUILTIN_MODULES`, given by the shell's installation: see "Built-in modules"
  at the end of this section), then the system data
  directories' `h2s-shell/modules/*` (`H2S_SHELL_MODULE_DATA_DIRS`). The running shell runs
  the same search again (`launch.sh --discover-modules`) on `qs ipc call modules rediscover`
  and loads its list in place. Safe mode (no module loads): after
  two deaths within 30 s of starting in a row (the launcher: `H2S_SHELL_SAFE_MODE=1`), or two of
  Quickshell's in-place relaunches after a crash in a row, neither living 30 s — which the
  launcher does not see; the shell counts them (`$XDG_RUNTIME_DIR/h2s-shell-module-starts`).
- **The host**: `singletons/ModuleHost.qml`, one instance in the `Modules` singleton, which
  `shell.qml` touches before the bars. It reads no module file on the GUI thread: the
  manifests, qmldirs and file texts come out of its file check (a process, with a deadline),
  then it checks them and looks up the programs they name (a process too: the program
  lookup below), creates each enabled module's `main` inside
  a guard (the file check, the program look-up, the start guard, the making of the
  stores' directory and of the modules' data directories each run one command through a
  `singletons/io/CommandRunner`, under
  the host's `checkTimeoutMs`), keeps a handle per module (`api/ModuleHandle.qml`) and each one's facts, and
  exposes the statuses and the merged contributions. `qs ipc call modules list` prints them;
  `qs ipc call modules setEnabled <id> <bool>` turns one off or on (`Config.disabledModules`;
  `Config.enabledModules` for a built-in one its `builtin.json` lists as off).
- **Sources and confirmations**: at each load a process reads where the modules lie — the
  user root and its entries (links or folders), the built-in directory and its
  `builtin.json`, the record of what the shell installed — and each module's status says
  where it comes from (`source`, `sourceLabel`, `replaces`, `installedFor`;
  `ModuleInstallRules.sourceOf`). A module that is not built in, the system's or on the
  development path loads only once the user has acknowledged it (`Config.acknowledgedModules`,
  kept in the config file: source, address, author, whether it runs administrator actions):
  a new one is `unconfirmed`, a hand-placed one that now declares administrator actions or
  names another author waits for `approval` (`ModuleInstallRules.needsConfirmation`).
  `qs ipc call modules confirm <id> <directory>` (the directory as `modules list` shows it;
  refused when the id now names another) acknowledges it and turns it on; `setEnabled`
  refuses it, saying why. Confirmations hold only in a shell the launcher started from its
  own directory (`H2S_SHELL_DISCOVERY` names it and the launcher's pid, the shell's own or
  its parent's), never in a `quickshell` started by hand. The first start that confirms finds no list and writes one from the hand-placed modules that are on,
  so they keep running without a question — only from a launcher search that answered, with
  at least one module read; otherwise nothing is written. A module counts as the system's
  only in a data directory root owns and the user cannot write (a user-writable one, such as
  a Flatpak export, counts as placed by hand). Nothing is
  confirmed, searched for or loaded again over IPC while the session is locked. The host
  writes the ids of the modules loaded to `$XDG_RUNTIME_DIR/h2s-shell-modules-on` (never in
  safe mode) and reads at its first load what the last run wrote (`previousModulesOn`);
  `qs ipc call modules loadWithoutSafeMode` loads the modules in place out of safe mode. In
  safe mode a banner (`hud/SafeModeBanner.qml`, its words from
  `ModuleInstallRules.safeModeBanner`) stands under the bar (`hud/StartupWarnings.qml`, ×
  closes it for the run) and at the top of Settings → Modules: why, the modules on when it
  crashed, one installed or updated in the last day, "Open Modules" and "Load modules" (the
  same load); never while the session is locked, and `tests/lock-closure.sh` names it. A
  module whose files changed in place since the engine first built them runs its old code
  until the shell restarts (the engine keeps a file by URL for its life,
  `tests/QuickshellPinTest.qml` (h)): it is named in `restartNeeded`.
- **The installer**: `singletons/ModuleInstaller.qml`, one instance in `Modules` beside the
  host, everything as the user under the data and config homes. Installing (`qs ipc call
  modules install <address-or-folder>`, `installKeepOff`): a git address (`#<ref>` allowed;
  `ModuleInstallRules.installSource`, `downloadCommands` — no hooks, no submodules, no
  credential prompt, only https/ssh/git/file) is cloned, a folder copied without following
  links, into `<dataHome>/h2s-shell/module-staging/`, under a time limit and a size cap — git's
  progress read as git redraws it (`progressOf`) and the directory measured while it is
  written; a link out of it refuses it; then the host's own file
  check and manifest rules (`ModuleHost.checkDirectory`) and the id free or the shell's own
  (`installTarget`: what was placed by hand, under any name, is never replaced or joined); then the chain
  (`ModuleDependencyRules.plan`: each missing dependency with a `source` fetched and checked
  the same way). Each module moves in by renames: `module-versions/<id>/<version>-<commit7>`
  (a folder: `<version>-<time>`); the record `module-sources.json` (by a temporary file and a
  rename) then lists the new versions, the links `modules/<id>` move onto them (providers
  first), and the record makes them active; a failure halfway takes back what moved and the
  record's entries (`ModuleDependencyRules.rollbackPlan`). A record that cannot be read is
  never written over; Remove takes its entries out of the text as read. At the shell's start
  `tidy()` empties staging, removes temporary links and puts the record right after a run
  that was cut off (`reconcileRecord`). Then the host searches and loads again; new modules
  are acknowledged and turned on (the command was the confirmation), or kept off — each only
  as loaded from the version directory the job made. `switchVersion <id> <version-dir>` relinks to a kept version and
  `deleteVersion` drops one (at most three kept, `ModuleUpdateRules.keepPlan`); an update or
  a switch whose module then fails to start goes back to the version before
  (`backOnFailedStart`). `remove <id> <directory>` (`removeWithData`) follows
  `ModuleInstallRules.removalPlan`: a hand-made link only the link, a hand-placed folder that
  folder, the shell's own its link and versions; every deletion only where `deletionTarget`
  allows, never through a link. One job at a time, never started while locked; `modules job`
  says how the last ended.
- **Configuration backups**: `singletons/ModuleBackups.qml`, run by the installer inside its
  job before a module moves to another version (an update, a switch, the way back after a
  failed start) and before a restore. A backup is
  `<dataHome>/h2s-shell/module-backups/<id>/<version>-<YYYYMMDD-HHMMSS>/`: `settings.json`
  (the module's `mod.<id>.*` values in every profile and the pinned globals, as stored),
  `store.json` (its store's file), `data/<path>` (only the paths its manifest's `backup`
  names) and `meta.json`; written in a staging directory beside it (`.incoming-…`) and
  renamed in, the newest 5 kept (`ModuleBackupRules.keepPlan`). Links are never followed: a
  store that is a link, or a named path whose resolved place is outside the data directory,
  is left out (and a restore leaves it alone); a link inside a named folder is kept as a
  link. A backup that cannot be taken (settings that could not be read, a folder that is a
  link) stops the update or switch before anything moves. `modules backups <id>` lists them;
  `modules restore <id> <backup>` (`ModuleBackupRules.restorePlan`) backs up first, turns the
  module off, writes its settings through `Profiles`, its store and named files back by
  temporary names and renames (folders made one level at a time, never through a link), and
  turns it on again when it was on.
- **The registries** read the merged lists — through `ModuleLists` (plain values the
  `Modules` singleton feeds; never `Modules` itself, so the lock screen, which reads its
  settings through Profiles, never constructs or waits for the host; modules arrive after the
  first frame): `WidgetRegistry.entries` (the core's
  `coreEntries`, then modules' — files as `file://` URLs, each entry naming its `module`),
  `WidgetPresets.defaults`, `SettingsSchema.entries` (popup-mode entries follow the registry),
  `ProfileRules.factTypes` and `Profiles.facts`, `SettingsWindow.pages` (`corePages`, then
  `ModuleMergeRules.mergeSettingsPages`). With no module each is the core's list itself (the
  suites check it). Everything is reactive: a module turned off leaves its bar entries in
  place showing nothing, closes its popup, takes its pages, settings, facts and slot content.
  The core builds a module's objects by URL and gives each the module's handle as `module`
  (only when its root object declares it: `Modules.initialProperties`).
- **A module's API for other modules**: a provider declares `"exports": { "version": "1.0" }`
  in its manifest and gives the object as its main's `exports` property (a plain `QtObject`,
  no `parent`, read once when the main is made); a dependent declares
  `"uses": { "<id>": "1.0" }` (same major, the provider's minor at least the one asked for;
  all required) and gets `module.uses.<id>`, that object and nothing else of the provider.
  `ModuleMergeRules.dependencyPlan` gives the order — providers first, otherwise by id — and
  the state each ends in: a provider missing, not loaded, exporting nothing or an older
  version, or whose main gives no `exports` object leaves its dependent `missing-module`, one
  reason per provider in its errors ("needs module tailscale 1.0: turned off"); a provider
  pending leaves it pending; a cycle of `uses` fails every module in it, the cycle named. The
  host destroys in the reverse of that order and makes in it: a provider turned off,
  failing or reloaded (`load()` again) takes its dependents off first, and they come back
  after it. `module.uses` is set just before the dependent is turned on and kept, the same
  object, until it is turned on again; a provider's main is destroyed only once its
  dependents' mains are gone (`ModuleHost._reap`, told by a watcher object inside each main),
  so a dependent's main and views read it for as long as they live, `Component.onDestruction`
  included. A module turned on again before its old main is gone (off and on in one turn of
  the event loop) stays pending until it is: a new main never lives beside the old one, and
  the old one reads its own `module.uses` to the end. A main deleted by something other than
  the host keeps nothing waiting. The host waits for mains, not views: the views of a
  dependent without a main are taken down by the core as it goes off and are gone before the
  provider's main (a suite checks it), but nothing in the host holds the provider for them. When the shell reloads, the engine runs every main's
  `Component.onDestruction` newest first, and a dependent's main is always newer than its
  providers'.
- **Soft uses** (API 1.30): `"uses": { "<id>": { "version": "1.2", "optional": true } }` —
  the module loads with or without that provider; `{ "version": "1.2" }` alone, like the
  plain string, is hard; (API 1.36) `"source": "<repository address>#<ref>"` in it says
  where to get the provider when it is missing (not such an address: an error, the entry
  kept without it). One object form under the one id rather than a second field, so an
  id is never both hard and soft and `module.uses.<id>` has one meaning. With the provider
  there and fitting, the plan puts the dependent after it and `module.uses.<id>` is its
  object; without it (not installed, off, failed, not fitting, no `exports` object) the
  entry is `null` and the module loads all the same — a provider that is there and does not
  fit is a warning in the dependent's status ("can use module x 1.2: has 2.0"). A provider
  pending leaves a soft dependent pending too, so a start does not make it twice. When a
  soft provider comes or goes while the dependent is on, the host turns the dependent's
  main off and on again (`ModuleHost._usesChange`: pending until the old main is gone, the
  provider's going main waiting for it as above): `module.uses` never holds a provider that
  is gone, and one main sees one `module.uses` for its whole life, so the frozen-`uses` rule
  of hard uses holds unchanged. The restart is a new main each time: what the old one held in
  memory is lost, so a soft dependent keeps what must last in its data directory or settings.
  Every running main that uses the restarting one, hard or soft, directly or through others,
  restarts with it: the whole set is taken down in the reverse of the plan, each dependent
  queued in `_going` before its provider's main is asked to go, so it still reaches its
  providers while it goes, and made again in the plan's order. Only the mains given the
  restarting one's object restart with it: a soft dependent that never got it (a cycle edge
  left out, a version that does not fit) keeps its main. A soft dependent without a
  main (views only) is not turned off when its provider comes or goes: its `module.uses` is
  replaced by a new object under its live views — a binding on `module.uses.<id>` follows it
  (`null` once the provider has gone), and a view keeps no reference to the old object. While
  that provider is pending, though — restarting with a module it uses, or starting — the
  views-only dependent is pending too, its views gone until the provider is back. A soft
  provider pending whose manifest does not fit (another major, an older version, no
  `exports`) is not waited for. Cycles: only hard edges make a cycle an error; a soft edge
  whose provider already reaches its dependent is left out (dependent ids, then provider
  ids, in order), its entry `null`, warned about ("left out, a cycle of uses").
- **Reaching another module or the host**: a module knows of another only its plain state,
  `Api.moduleStatus(id)` (frozen `{ id, name, version, state, active }`, or null), and its
  `exports` through `uses`. The old ways are listed among the module's `deprecations`, found
  in its QML and JavaScript code by `ModuleSourceRules.codeDeprecations` (comments and strings
  do not count; a file the module does not name, reached only by the scan below, in its first
  64 KB): `Api.module(id)`, which (API 1.36) answers only with the calling module's own
  handle and goes with the shell's next tightening, and `module.host` (where the handle is
  named `module` or comes straight from `Api.moduleAt`: QML cannot notice a property read, so
  a handle under another name is not found), gone since API 1.36 — the handle reaches its
  host through `ModuleHandleHosts`, inline, never as a property or a function's answer.
  `Api.moduleAt(url)` answers only for the caller's own directory (the call's stack names it
  alone).
  Importing `qs.singletons` (and below) or a directory outside the module's own is an error
  in its status (a JavaScript file's `.import` too); the module still loads.
- **Slots**: `components/ModuleSlot.qml` — `ModuleSlot { name; context }` where a core panel
  lets modules in; the names and contexts are `ModuleRules.slotTable`. Never on the lock
  screen (a suite checks `screensaver/`, `singletons/lock/`, `Lockscreen`, `pam/` and the
  components they build, transitively: `tests/lock-closure.sh`).
- **Anchors**: the places in the shell's views where a module puts elements, replacing the
  slots view by view. A view is built from shared blocks on one base,
  `components/AnchorBlock.qml` — so far the settings page, `components/SettingsPage.qml`
  (it scrolls, keeps the page's margins, draws the heading and a banner, then the content),
  the popup section, `components/PopupSection.qml` (a group in a popup panel: its header
  line, its content in a column, its closing divider; a panel's root is one too), and the
  popup row, `components/PopupRow.qml` (one line of a popup, with what goes under it), the
  settings section, `components/SettingsSection.qml` (a titled group on a page: a line
  above it, its title's line with its buttons, then its content; the line, the room around
  it and the title's size are those of `panels/settings/SectionTitle.qml`, which a page of
  plain rows uses for its titles, and the gaps are the theme's `settings` tokens
  `sectionGap`, `sectionLineGap`, `sectionTitleGap`; the first section under a page's
  heading has no line), and the settings card,
  `components/SettingsCard.qml` (a framed item that opens: its header and notice line, then,
  opened, its own rows; the network pages' card for a saved profile, a hotspot or a VPN,
  `panels/settings/NetworkProfileCard.qml`, is built on it); the settings row follows. A card takes no element inside itself:
  its opened part is its region `settings`, a block of kind `region` around its rows
  (`prepend` above them, `append` under them), whose elements are built only while the card
  is open and destroyed when it closes. Its buttons stand in one row, closed and open — the
  main one (and the lock beside it), the card's own, the region
  `actions` (`prepend` before the card's own, `append` after them and before the button that
  removes the item — "Forget", "Delete" stays last, whatever a module adds), built as long as
  the card is. The row stands on the name's line when it fits there beside the name's least
  (`nameMinimumWidth`, a few characters, plus the room kept for the name line's elements)
  and the arrow; else it moves to a line of its own under the name and its line,
  right-aligned; wider than the card (a long question while a button asks), the main button
  takes that line alone and the rest stand on a line under it (`buttonPlace`: `nameLine`,
  `ownLine`, `twoLines`, decided from the row's width alone). A question longer than the card
  goes on to more lines (`DeleteButton`'s `wraps`). The row's area takes the clicks that miss
  a button, so a click between two buttons does not open the card. Regions get the card's context and scope. `actions` takes the public
  `SmallButton` only (the row's `takes`). The host reads the mark the public button carries
  (`apiElement`, not `instanceof`: `qs.api` imports `qs.components`, so the host cannot name
  the public type) from the element as soon as it is made, and destroys another, with
  "anchors: "<path>" takes a SmallButton" in the module's status. The region puts the
  buttons side by side (a host with `inline` set, a layout, so edges stand on whole pixels),
  6 apart, centred on the line, each at its own width, at most a third of the card wide — a
  longer label is cut — the card's own buttons keeping their room and the modules' cut on the
  right beyond what is left of a line (`buttonRoom`, the card's width inside its margins), and in
  the size it sets, or, setting none, the row's (`m`: the region sets the public
  button's `defaultSize` after it is made, which `size` follows until the module sets it —
  the module's own `size` replaces that binding, so it is never overridden); a button hidden (`visible:
  false`) and an element refused take no room and no gap. Its name's line is its region
  `title`, closed and open (`append`, after the name): the host lays its elements side by side
  (`AnchorContent`'s `inline`), 4 apart, each given the line's height and cut to it, all of
  them at most a quarter of the card (`titleMaxWidth`), cut on the right; the name's right
  padding keeps their room and its minimum width is that room and the name's least, so the
  name is cut first and the elements never cover the card's own parts; with less room left
  on the line, the buttons move under the name sooner. Such inline hosts size each element
  from itself (`ModuleContribution`'s `sizedByElement`): one made with a width of its own and
  no implicit width keeps that width, any other follows its implicit width, down to none.
  Every other host (a column: a card's `before` and `after`, its `settings`, a popup's rows,
  a page's sections, a vertical slot, a module's settings page) makes each element as wide as
  itself, so one anchored to its parent's sides fills it. A card made
  per item by a `Repeater` on a `KeyedModel` (string keys, the card looking its item up by
  key — [The Repeater crash](#the-repeater-crash)) takes its elements with it when its item
  goes, and keeps them while other items come and go. A view's author writes only a block's
  `anchor`, a word for what it holds (`saved`, `vpns`), never where it stands or its title's
  words. The block's path follows from where it stands, found by walking up `parent` (a
  binding: a block moved has the new path):
  `<surface>.<view>[.<block>]…[.<region>]` — surface `settings` or `popup`; view the page's id
  or the popup's key, the base the window or popup gives the view's root (the first item up
  the parents with a string `anchorBase`); then the names of the enclosing blocks and its
  own; a block repeated per item is named by its kind (`card`, `row`), its item in the
  element's context; a card's regions `actions`, `settings` and `title` last, and a row's
  region `title` (a popup row's name line, `components/PopupRowTitle.qml`) right after `row`
  (`ModuleRules.anchorRegionHolders`). A block with no anchor
  adds no level and has no path of its own — except the view's root, a block of a root kind
  (`ModuleRules.anchorRootKinds`: the settings page, the popup section) right at the base,
  whose path is the base itself; sections with no anchor straight under a plain item are not
  the page. Addressable are settings pages and popup content; never the bar, the lock
  screen or the screensaver (the anchor blocks and `AnchorContent` are among the names
  `tests/lock-closure.sh` looks for). The rule is `ModuleRules.anchorPathProblem`. A module
  names a path, a placement and its file in its manifest's `anchors`
  (`{ "at", "place", "component" }`): `before` and `after` put the element next to the block,
  outside it; `prepend` and `append` inside it, first and last of its content, under its
  frame. Top to bottom, for a block B holding c1 … cn: B.before · B's frame · B.prepend ·
  c1.before · c1 · c1.after · … · B.append · B.after. Only the paths in
  `ModuleRules.anchorTable` take content (`Api.anchors` is its frozen copy): naming a block
  does not publish it, and a place not in the table
  or a placement it does not take is an error in the module's status, the rest of the module
  loading. Each placement a kind has is a host, `components/AnchorContent.qml` — the slot's
  machinery: a `Repeater` on a `ScriptModel` keyed by module and file, each element in a
  `ModuleContribution` guard, given `module` and `context` (`{ anchor, placement, …the
  block's context }`); its list is built only while the module host lists elements for it,
  and only on a block of its row's kind that has that placement (`ModuleRules.anchorBlockFits`).
  A row of scope `own-provider` (the card or row of a VPN provider's item) shows only the
  elements of the module the block's `scopeId` names — the view sets it on the item's block
  to the provider's module id, the blocks inside take it; with none the place shows nothing.
  Several modules at one place: by module id, a module's in its manifest's order
  (`ModuleMergeRules.anchorContent`, the one place that orders them). Blocks report
  themselves to `singletons/Anchors.qml` (`live`: path → count), which only the suites read.
  A slot whose view has been converted is read as its anchor (`ModuleRules.slotAliases`: the
  element's context keeps `slot`) and listed in the module's `deprecations`; the converted
  block's `context` must give the keys the slot gave (the alias's `needs`: `wifiEnabled` in
  the network popup), and the slot's `ModuleSlot` goes. Each table row names the file that
  builds its block (`view`); `tests/AnchorsTest.qml` checks, for every alias whose place is
  published, that no file outside the tests still names the slot and that the view builds
  the block and names those keys (`ModuleRules.slotAliasProblems`).
  The settings window's page loader gives a core page's root its base, `settings.<page id>`
  (`anchorBase`, set before the page is built, so a page never sees another's base); a
  module's page gets none; the popup gives a panel of the shell's its base the same way,
  `popup.<key>` (`panels/Popup.qml`, set before the panel is made from `Qt.callLater`), a
  module's panel none. The places offered so far:

  | Path | Placements | Context | Where | Since |
  |---|---|---|---|---|
  | `settings.general` | `append` | `editIndex` (the profile being edited) | Settings → Behaviour → General, at the end of the page (`panels/settings/GeneralSettings.qml`); the slot `settings.general.bottom` is read as it | 1.21 |
  | `popup.network.connections` | `append` | `wifiEnabled`, `wifiConnected`, `ethernetConnected` | the network popup, under the VPN, Ethernet and Wi-Fi parts, above the divider over the network list (`panels/NetworkPanel.qml`); the slot `network.popup.sections` is read as it | 1.22 |
  | `popup.notifications` | `prepend` | `count` (the notifications in the list) | the notifications popup, under its header, above the list (`panels/NotificationPanel.qml`); the slot `notifications.popup.top` is read as it | 1.22 |
  | `popup.network.connections.vpn.row` | `after` | `vpnId`, `entryId`, `vpn`, `provider` (the provider object), `otherVpnsUp`, `otherVpns` | the network popup's VPN part, under the row of each VPN of the module's provider (`panels/network/VpnSection.qml`); own-provider; the slot `network.vpn.row` is read as it | 1.23 |
  | `settings.network_vpn.vpns.card.settings` | `prepend` | as the VPN's row | Settings → System → Network → VPN, the opened card of each VPN of the module's provider, above the card's own rows (`panels/settings/NetworkVpnSettings.qml`); own-provider; built while the card is open; the slot `network.vpn.card` is read as it (its context adds `open: true`) | 1.23 |
  | `settings.network_wifi.saved.card.settings` | `append` | `networkId` (the profile's UUID, `Api.networks`' `id`), `name`, `kind` (`"wifi"`), `active` (fully up) — the network as `Api.networks` names it — and `ssid` (its SSID, plain, on one line; API 1.32) | Settings → System → Network → Wi-Fi, the opened card of each saved network, under the page's rows (the password) (`panels/settings/NetworkWifiSettings.qml`); built while the card is open; not on a hotspot's card | 1.24 |
  | `settings.network_ethernet.profiles.card.settings` | `append` | as the saved Wi-Fi network's (`kind` `"ethernet"`) | Settings → System → Network → Ethernet, the opened card of each wired profile, under the card's rows (`panels/settings/NetworkEthernetSettings.qml`); built while the card is open | 1.24 |
  | `settings.network_vpn.vpns.card.actions` | `append` | as the VPN's row | the same VPN cards' buttons, closed and open: in the row on the name's line, after the card's own ("Settings…", "Edit"), before "Delete"; own-provider; a `SmallButton` only | 1.25 |
  | `settings.network_wifi.saved.card.actions` | `append` | as the saved Wi-Fi network's `settings` | the same Wi-Fi cards' buttons, closed and open: in the row on the name's line, after "Edit", before "Forget"; a `SmallButton` only | 1.25 |
  | `settings.network_ethernet.profiles.card.actions` | `append` | as the wired profile's `settings` | the same wired profiles' cards' buttons, the same | 1.25 |
  | `settings.network_wifi.saved.card.title` | `append` | as the saved Wi-Fi network's `settings` | each saved Wi-Fi network's card, closed and open: its name's line, after the name — what a module adds to that network (any element, on theme tokens), as tall as the line, a quarter of the card at most for all | 1.28 |
  | `settings.network_ethernet.profiles.card.title` | `append` | as the wired profile's `settings` | each wired profile's card, the same | 1.28 |
  | `settings.network_vpn.vpns.card.title` | `append` | as the VPN's row | each VPN's card, whatever its provider (not own-provider), the same | 1.29 |
  | `popup.network.wifi.row.title` | `append` | as the saved Wi-Fi network's `settings`; a network not saved (no profile) has `networkId` `""` and its SSID as `name`; `ssid` is the SSID scanned, saved or not; of several profiles for one SSID the one fully up, else the one coming up, else the one last used (`ModuleRules.wifiRowContext`). Saved is what the row offers Forget for (`ModuleRules.savedWifiProfile`): a hotspot profile is not, and a profile just saved is only once its details are read, a moment after | the network popup's list of Wi-Fi networks in range, each network's row, closed and open: its name's line, after the name, as on the cards (`panels/network/WifiNetworkRow.qml`, a quarter of the row at most); not the same list in Settings → Wi-Fi. A long list builds only the rows in view: a row scrolled out goes with its elements and is built anew when it comes back, so an element there keeps no state of its own (its module keeps it, by the context) | 1.32 |
  | `popup.network.connections.wired.row.title` | `append` | as the wired profile's `settings`, for the wired profile up on the Ethernet device; with none up `networkId` and `name` `""` (`ModuleRules.wiredRowContext`) | the network popup's Ethernet part, the wired row's name line, the same (`panels/NetworkPanel.qml`) | 1.32 |

  A module's icon (the manifest's `icon`) is its face in Settings → Modules; the shell puts
  it on no card. A module shows what it adds to a network in that card's `title` place.

  A saved Wi-Fi network's card is a place only while `Api.networks` names its network
  (`ModuleRules.networkListed`): until its details are read it could be a hotspot, so its
  card has no anchor and no module's element or button is built in it.

  Named but not places yet: `popup.network` (the network panel's root), its VPN part
  `popup.network.connections.vpn`, its Ethernet part `popup.network.connections.wired` and
  the wired row `….wired.row`, the network list's part `popup.network.wifi` and each
  network's row `popup.network.wifi.row`, the VPN page's section of cards `settings.network_vpn.vpns`
  and each card `….vpns.card` with its name's line `….vpns.card.title`; the Wi-Fi page's
  sections `settings.network_wifi.saved` and `settings.network_wifi.hotspots`, each saved
  network's card `….saved.card`, each hotspot's card `….hotspots.card` and its opened part,
  buttons and name's line `….hotspots.card.settings`, `….hotspots.card.actions`,
  `….hotspots.card.title`; the Ethernet page's section `settings.network_ethernet.profiles`
  and each wired profile's card `….profiles.card`.

  `tests/AnchorsTest.qml` checks the blocks and hosts on a fixture view, and the shell's
  views against the table: every place in it live once they are built, and where the rows of
  a converted page and the parts of a converted popup stand.

Writing a module, from the author's side (everything through `import qs.api`; nothing from
`qs.singletons` — importing it, or a directory outside the module's own, is an error in its
status — and `qs.components` — the shell's internal components, which may change
in any release — only for a module not yet moved off it: the import still works and is
listed among the module's `deprecations` in `qs ipc call modules list`; any other import
outside those, `Quickshell`, `Quickshell.Io`, `QtQuick…`, `QtQml…` and the module's own
directory is a warning there. Every QML and JavaScript file under
the module's directory is read for its imports, in subdirectories too — up to 100 files,
8 directories deep, hidden directories, links and other file systems skipped; a file the
module does not name is read in its first 64 KB; the files it left out or could not read
are one warning, "imports not checked in N files"):

```qml
// module.json: "widgets": [{ "type": "example", "name": "Example", "widget": "Widget.qml",
//   "popup": "example", "popupPanel": "Panel.qml" }],
//   "settings": [{ "key": "mod.example.greeting", "label": "Greeting", "type": "string", "default": "hi" }],
//   "facts": [{ "fact": "example.up", "label": "Example up", "type": "bool" }],
//   "settingsPages": [{ "id": "example", "label": "Example", "component": "Page.qml", "tab": "system" }],
//   "anchors": [{ "at": "popup.network.connections", "place": "append", "component": "NetworkLine.qml" }]

// Widget.qml — a bar cell; PopupWidget opens the popup the manifest names
import QtQuick
import qs.api
PopupWidget {
    widgetType: "example"
    property var module: null          // the handle, set before Component.onCompleted
    Text { text: module?.value("greeting") ?? ""; color: Api.theme.textPrimary
           font.family: Api.theme.fontFamily; font.pixelSize: Api.theme.fontSizeBody }
}

// Page.qml — a settings page: a plain ColumnLayout, framed and scrolled by the window
import QtQuick.Layouts
import qs.api
ColumnLayout {
    property var module: null
    property int editIndex: -1         // the profile picked (Behaviour tab)
    Heading { text: "Example" }
    SettingEditor { key: "mod.example.greeting"; editIndex: parent.editIndex; Layout.fillWidth: true }
}

// NetworkLine.qml — an element at a place; `context` as the anchor table says
import QtQuick
import qs.api
Text { property var module: null; property var context: null
       text: context?.wifiConnected ? "online" : "offline"; color: Api.theme.textMuted }
```

**Public elements** are types in `qs.api` made for modules: each holds the shell's internal
component inside and shows only its own properties, so the shell changes its insides
without breaking a module. On one a module picks a meaning, never a look: `kind` (what the
element is about) and `size` (`xs`, `s`, `m`, `l`; an element takes the ones it has); a
theme decides how they look, and a word an element does not know shows as its default,
logged once (`singletons/ApiElements.qml`; the words: `singletons/ApiElementRules.qml`).
The button is `SmallButton` (`api/SmallButton.qml`): `kind` is `primary`, `secondary`,
`danger`, `warning` or `success`, `size` is `xs`, `s` or `m`, and `confirm: true` makes the
first click ask, the second act — `clicked()` is "do it" either way. `qs.components` has
a `SmallButton` of its own: in a file that imports both, the import written last gives the
name. The other controls are `Dropdown`, `InputField` (each with `size` `xs`, `s` or `m`),
`Pill` (`size` `s`, `m` or `l`: the theme's three pill heights; `textSize` `small` or `body`: the theme's type sizes, API 1.32), `Checkbox`, `ToggleSwitch`
and `PrivilegedMark`, whose `need` is polkit's answer (`auth`, `no`, `yes` or none; one it
does not know shows the lock); their names are `qs.components`' too, and the same holds
for a file that imports both. Rows and texts: `SettingsRow` (a label, a hint under it, a
value, and its children as the controls on the right), `ExpandingRow` (a line that opens;
its child is held as a `Component`, so nothing of it exists while the row is closed; it
slides open and shut as `components/Reveal.qml` does every part of a settings page that opens
on a switch) and
`Notice` (a small line of kind `warning`, `danger` or `success`); inside the first two are
`components/SettingsRow.qml` and `components/ExpandingRow.qml`. `ProgressBar` (API 1.31;
`value` 0 to 1, below 0 a run of unknown length; `kind` `normal`, `success`, `warning` or
`danger`; inside, `components/ProgressBar.qml`, as thick as the theme's
`progress.thickness`; `wave`, API 1.35: the owner says the bar moves, and bands of light
pass through the fill, a new one every `Theme.duration("progressWave")`, each crossing in
`Theme.duration("progressWaveTravel")` — a fixed pool of bands, reused, timed by
`ApiElementRules.progressWaveSchedule`; whether they run is `ApiElementRules.progressWaves`) and `HoverTip` (1.31: a plain-text tooltip over its `target`, the item
it is written inside by default, taking no room; inside, `components/HoverTip.qml`).
`SidePanel` (API 1.34) slides in from the right over a module's settings page: `open`,
`title`, `size` (`s`, `m`, `l`: `Theme.sidePanelWidths`, at most 90 % of the page) and
`closed(reason)` (`close`, `outside`, `escape`, `replaced`, `page`, `lock`); its child is
held as a `Component`, built when it opens and destroyed once it has closed. It takes no
room where it is written: the panel shows in the page frame (`components/ModulePageFrame.qml`,
the settings window's frame for a module's page and the test kit's `pageFrame`), in its
layer outside the page's scrolling (`components/SidePanelHost.qml`, one `components/SideDrawer.qml`).
The element finds that layer by walking up its parents to a frame `ApiElements` knows by
identity, so nothing a module names makes a place a frame; elsewhere it does not open.
Which reason a close gives, and the width, are `ApiElementRules`' (`sidePanelEvent`,
`sidePanelWidth`). The settings blocks `SectionTitle` and `Heading` take controls as their
children, at the right end of the line (1.34); a `SectionTitle` has a line above it, as the
core's sections do, `divider: false` without (1.38). `StatusPill` (API 1.35) sums up a state:
`icon`, `label`, `kind` (`normal`, `muted`, `success`, `warning`, `danger`: the colours in
`ApiElementRules.statusKinds`), `parts` (`[{ icon, text, kind, tip, line }]`, each with its
tooltip; made plain and capped at 12 by `ApiElementRules.statusParts`), `expanded` (a click
flips it while there are parts: one part per line under a rule) and `toggled(expanded)`;
inside, `components/StatusPill.qml`, its parts in a `KeyedModel` keyed by place. The base types —
`PopupWidget`, `BarText`, `BarRow`, `PointerArea`, `VpnProvider` — are the shell's own
types under their public names, not wrappers: the bar, the pointer and `VpnManager` need
the object itself, and only the names listed in `api/Api.qml` are promised. Every element's properties and signals are pinned in
`tests/ApiElementsTest.qml`, with what each kind and size is inside and how the element
stands in a layout; a change there is a change of the API's version.

What acts (an `IpcHandler`, a `Process`, a `Timer`, a provider) lives under the module's
`main`, which the host destroys when the module is turned off, or binds to `module.active`
(a singleton's timer: `running: module.active`) — a module's singletons outlive the main.
A singleton finds its handle with `Api.moduleAt(Qt.resolvedUrl("."))`. Commands go through
`CommandRunner` (below), `CommandAction` / `CommandQuery` (one after another, or a query run
again on request; both run by a `CommandRunner`, without a time limit) and
`module.privileged.start` (a command as root, below; the older `PrivilegedAction`
— pkexec, by an absolute path checked first, `notFound` otherwise; 126 dismissed, quietly;
127 refused, said once — runs through the same queue). Wake-up: `module.resumed()`;
a page or slot contribution that declares `property bool shown` does its expensive reading only
while it is on screen. What the module's views share (a client, its state) lives on the main
and is read through `module.main` (set by the host right after the main is made, before the
module's views are built; null while the module is off; `module.main?.client`). A popup
panel is given, when it declares them, `opener` (the bar widget that opened it, frozen
`{ widgetType, preset, edge, byTouch }`: `PopupWidget` passes its type and its entry's
preset to `Popup.open`, `ModuleRules.popupOpener` makes the object), `availableHeight`,
`popupAnimating`, and with `fitsShownHeight: true` the height shown while the popup
animates; `api/Api.qml` has the details. Preferences are settings (`mod.<id>.*`, `module.value` /
`module.setValue`); anything else (tokens, remembered state) goes in `module.store`, and
files (certificates, caches) in `module.dataDirectory`.

**System facts and the data directory.** `Api.system` is what the shell read of the
system: `userName`, `uid`, `hostName`, `home`, `configHome`, `dataHome`, `runtimeDirectory`,
`downloadDirectory`, `ready`, and `readIpForwarding()` and `refresh()`. `singletons/SystemFacts.qml`
holds the shell's one `singletons/io/SystemFactsReader.qml`, which reads; the pure
`singletons/SystemFactsRules.qml` decides from what it read. The readings are the same on
both systems: the environment (`HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
`XDG_RUNTIME_DIR`; a relative `XDG_*` is ignored, as the XDG specification says),
`/proc/self/status` for the user id, `id -un` for the name (the user database, through NSS),
`/proc/sys/kernel/hostname`, `user-dirs.dirs` in the config home (read as text, never run:
only `"$HOME/…"` or an absolute path in double quotes counts), and `/proc`'s two forwarding
switches, read when asked. A reading that failed or says something unexpected is unknown
(`""`, or `null` for the id and a switch), never a guess.
- NixOS: `user-dirs.dirs` is home-manager's when `xdg.userDirs` is on (often a link into
  the store, read the same way), else there is none and the download folder is
  `~/Downloads`.
- Arch: `user-dirs.dirs` is xdg-user-dirs' when it is installed, else there is none and the
  download folder is `~/Downloads`.

A module's data directory is `<dataHome>/h2s-shell/module-data/<id>`, apart from its own
directory (which installing and removing it owns). The host makes it before the module
loads (`ModuleHost.dataRoot`, set by `Modules` from `SystemFacts.dataHome`), again at each
load and when the module is turned on, by a script run as the user
(`SystemFactsRules.makeScript`): under umask 077 it goes from the data home down with
`cd -P` and checks each folder it is in — owned by the user or root, writable by no one else
(a sticky folder of root's aside), no link below the data home — then the root and the
module's directory must be the user's own and are set to 700 (`chmod 700 .`, on the folder
checked). One that others could write before is refused rather than closed. One it cannot
make so leaves the module loading with `module.dataDirectory` `""` and a warning in its
status. The shell never removes it. Nothing in the data directory may be run as root — the
user can write there. It is never in a configuration backup as a whole: only the files or
folders inside it that the manifest's `"backup": ["notes.db", "accounts"]` (API 1.37;
relative paths, no `..`, at most 32) names.

**Network facts.** `Api.networks` (the saved Wi-Fi and Ethernet networks, a Wi-Fi one only
once its details are read, so a hotspot never shows) with `Api.networksReady`;
`Api.vpnsUp`, whose rows say what each VPN does with the traffic — `fullTunnel`, `setsDns`,
`routes`, each `null` where it is not known, never `false` for "not read"; and
`Api.localNetworks` (`{ device, kind, family, address, network }`: the global addresses of
every device that is no VPN's, deprecated IPv6 privacy addresses left out by the flags `ip -j
-6 address show` gives) with `Api.localNetworksReady`, false while the reading has
not worked. All come from what the shell's network singletons read from NetworkManager
(`NetworkProfiles`, `VpnManager.details`, `IpManager.devices`); the pure functions in
`singletons/ModuleRules.qml` (`apiNetworks`, `apiNetworksReady`, `vpnRouting`,
`apiVpnsUp`, `apiLocalNetworks`) decide. Those readings run through
`singletons/io/LatestQuery.qml`, which says whether a run worked and drops the answer of a run
something changed under. A NetworkManager WireGuard VPN's routing is its
peers' allowed-ips with the profile's never-default, peer-routes and IPv6 method; a plugin
VPN's is what NetworkManager set up, read while it is activated (a gateway, a `/0` route or
the two halves of the addresses is a full tunnel); a provider's is what its
entry reports (`components/VpnProvider.qml`). A field an older nmcli does not know
(`wireguard.peer-routes`, `GENERAL.IP-IFACE`…) is asked again without when nmcli names it.
The context of the VPN places (and of the page's slot) has the other VPNs up
as such rows too (`otherVpns`).

Helpers, so a module copies none of the shell's code: `Api.format` (`bytes`, `rate`, `ago`
in milliseconds — `singletons/Format.qml`), `Api.address` (IPv4, IPv6, networks: `isIp`,
`parseCidr`, `contains`, `overlap`, `redact` — `singletons/AddressRules.qml`, the reader the
shell's network settings use too), `Api.minuteNow` (the start of the current minute, for
"5 min ago" without a clock of the module's own), `module.log(level, text, key)` (a line
"[<id>] …"; with a key, written only when that key's level or text changed — a failure
once, not once per attempt) and notifications with `format: "plain"` (`Notifier.prepared`:
the summary on one line, the body keeping its line breaks — at most 20 lines
(`Notifier.plainBodyLines`) — control and format characters dropped, capped, the body's
`&`, `<`, `>` shown as written) for any text from outside. A module's notification never
carries the shell's own category (`x-qs-shell`, the toast at the bottom of the screen) nor
any hint whose key starts with `x-qs-` (the shell's own sender's: the progress state, the
announce count), judged as the server would receive the key
(`ModuleRules.moduleNotifyOptions`).

**Progress notifications** (API 1.33): `module.notify` with `options.progress` (0–100, -1
for a run of unknown length; `Api.notify` refuses one, having no module to close it) returns
a handle — `open`, `state`, `update({ summary, body,
progress, actions, state, announce })`, `close()` — for any long job (a transfer, a backup,
a sync), else `null`. It is a frozen plain object whose getters and functions close over
Notifier's own handle, so nothing of how it is sent is reachable from it
(`singletons/io/NotificationHandle.qml`, made by `Notifier.send`; what a module gets:
`Api._notification`). That handle sends with one-shot `gdbus` calls to the notification server,
replaces the notification in place by its id, coalesces updates, retries, and learns a
click or a dismissal from the shell's own server in-process; every decision is in
`NotificationRules`. `options.toast` chooses how long its toast shows: `"brief"` (the
user's time) or `"whileRunning"` (it stays while the job runs); `announce: true` brings the
toast back once for a change of status. Notifier keeps a module's open handles under its
module handle (`Notifier.own`), out of reach of any module — `Api.module` hands out other
modules' handles — and the module handle (`api/ModuleHandle.qml`) has them closed in its
teardown, when the module is turned off, the same place its runs end
(`Notifier.closeOwned`); a progress notification's urgency is never critical, by the option
or a hint; while it is off a progress notification is not shown. In module test
mode nothing is sent: each show, update and close is recorded (`ModuleTestKit.notified`),
and a suite dismisses one or presses its action through `ModuleTestKit`. The lock bed's
`modules-notify` scenario runs the real path with the `good` fixture, on its private bus.

**The command runner** (`api/CommandRunner.qml`; inside it and in the shell's own code
`singletons/io/CommandRunner.qml`): `start(argv, options)` starts a command — a list of
words, never read by a shell — and returns a handle (`running`, `cancel()`); any number
run at once. Each run has a time limit (30 s unless given; 0 for none), gets its output
line by line as it comes (`onLine`; `onStdout` and `onStderr` per stream; read in whole
lines, so a character whose bytes arrive in two reads is never broken) and is answered once, through
`done`, with a frozen result: `ok`, `code`, `stdout`, `stderr` (each kept up to
`maxOutputBytes`, `truncated` beyond), `timedOut`, `cancelled`, `failedToStart`,
`durationMs`, and `error` when what was asked could not be run at all. The decisions are
pure functions in `singletons/CommandRules.qml` (what may be run, the command line, a run's
life as `step`, the cuts, the result); the runner starts processes and keeps timers.

- The time limit is kept twice: the command is started inside coreutils' `timeout -k`,
  which ends it even when the shell is gone, and the runner has a watchdog of its own.
  Between `timeout` and the command is util-linux's `setpriv --pdeathsig KILL`, which
  becomes the command after asking the kernel to kill it when `timeout` dies: a KILL
  that reaches `timeout` (the shell's child) cannot be passed on, and the command would
  go on without a limit. `singletons/CommandTools.qml` looks for both programs once, on
  `PATH`, and takes the first match that is trusted (the program lookup below: only root
  can change it); runs with a limit wait for its answer. With either missing a run is
  started bare, and the watchdog is its only limit.
- A run without a limit is started as it is, at once, and outlives the shell: what it
  starts may be meant to (a program a launcher opens), and nothing is put around pkexec.
  A run started with `endWithShell: true` waits for the look-up instead and, without a
  limit (or with `timeout` missing), is started behind `setpriv --pdeathsig KILL` alone:
  its parent is then the shell, and it ends with the shell (a crash, a restart) instead of
  running for ever. There 126 and 127 count as `failedToStart` only with `setpriv`'s own
  message last on stderr, since a command may exit with them itself. A privileged run
  (below) ignores the option.
  - NixOS: `/run/current-system/sw/bin/timeout` and `setpriv` there, which lead into the
    Nix store.
  - Arch: `/usr/bin/timeout`, `/usr/bin/setpriv`.
- Past the limit, and on `cancel()`, the command gets TERM, and KILL `killAfterMs` later.
  From a `cancel()` on no output is handed over; `done` comes when the process is gone.
  A run started with `outputAfterCancel: true` still gets, and keeps, the lines the
  command prints until it is gone — for a command whose last words matter even when it
  is stopped (whether a file was already moved into place); its answer says `cancelled`
  all the same.
- A program that cannot start is `failedToStart`. Quickshell reports it as a process that
  ends without an exit status; inside `timeout` it is that program's exit status 126 or 127.
- When the runner is destroyed (a module turned off) nothing is called any more and its
  runs are ended at once: a destroyed `Process` takes its child with it, which for a run
  with a limit is `timeout`, and the command dies with that; the runner also sends KILL
  to the process group `timeout` leads, for what the command started itself.

**The program lookup**: a module names the programs it runs in its manifest,
`requires.programs` (without one it is not loaded: `missing-program`) and
`optionalPrograms` (looked up the same way; a missing one does not stop it). The host
looks each up on `PATH` (an executable file; absolute entries only) and judges what it
finds; the module reads the result on its handle, `module.programs`: per name the path
(`""` when not found), `trusted` and a `reason`. `module.recheckPrograms()` looks again (at
most every 2 s); the host does so itself after the machine wakes. A program is trusted
when only root can change what runs: the path is walked component by component, as the
kernel resolves it (as `namei -l` shows it), and every directory passed, the directory
holding each link met and the real file must be root's and writable by no one else. The
Nix store counts as root's as a whole only when `/nix/store` is root's and the user cannot
write to it. A read that fails, two answers for one path, or a name holding a line break
or a tab is untrusted. The probe is `ModuleRules.programProbeScript`, run by `/bin/sh` with
the system's directories as its own `PATH` (`ModuleRules.probeToolPath`), never the `PATH`
it judges; the verdict is `ModuleRules.programVerdict`. Each change of a verdict is one
line in the shell's log, with the path, the real file, its owner and mode.
- NixOS: `/run/current-system/sw/bin` leads into the store, which the daemon owns as root;
  the setuid wrappers (`/run/wrappers/bin`) are root's files. A program under
  `~/.nix-profile` is untrusted: the link lives in a directory the user owns. A single-user
  Nix install's store is the user's, and is judged like any other directory.
- Arch: root's `/usr/bin`. A program in `~/.local/bin` is untrusted.

**Running as administrator** (`module.privileged` on the handle; `singletons/PrivilegedRuns.qml`
with its decisions in `singletons/PrivilegedRules.qml`): `start(argv, options)` runs a command
as root through pkexec; argv[0] is an absolute path, normally one of the module's programs.
`start()` does not check `trusted`: the module itself must pass only a program whose
`module.programs[name].trusted` is true — a program in a place the user can write, run as
root, lets any user process become root. The shell knows which module asks from the
handle; the run says what it does in a few words (`what`, required) and how long it may
take (`timeoutMs`, required, 1 s to 1 h). `available` is true once a trusted, setuid pkexec
and a trusted `timeout` are found.
- **Declared in the manifest** (API 1.36): a module that runs anything as administrator has
  `"privileged": { "why": "…", "programs": [names] }` in its `module.json` — `why` a few
  words for the user, `programs` names among its `requires.programs` and `optionalPrograms`
  (`singletons/ModuleManifestRules.qml`; a malformed block fails the module). The shell
  refuses `start()` with `blocked: "undeclared"` — before any prompt, the reason among the
  module's status errors, logged once — when the block is missing, not approved by the user,
  or when argv[0] is not the path `module.programs` has for a declared, trusted program
  (`PrivilegedRules.declaration`); `PrivilegedAction` the same (command[0] for argv[0]), and
  refused outright when the call cannot be traced to a module's code. This holds whatever API the manifest asks for. It is a guard against
  mistakes and a statement for the user, not a sandbox: a module runs in the shell's process
  and can start programs by other means. `"author"` (plain text, one line) names who wrote
  the module.
- **Refused before pkexec runs**, with `blocked` saying why: `unprintable` (a word holds a
  control or format character: a line break, a right-to-left override), `no-purpose`
  (`what` empty once cleaned), `locked`. A program not there is `notFound` (argv[0] `""` or
  not an absolute path, or not an executable file when the run's turn comes); options of
  the wrong kind give `error`. These checks catch mistakes and keep the command printable
  as it is; they do not stop a hostile module, which runs in the shell's process and could
  start pkexec itself. Against a module that is not the project's, the user's protection is
  knowing what they install: the prompt's lines below say what pkexec's message says, and
  past 80 bytes that message cannot tell two commands with the same ends apart.
- **The prompt says who asks and what for.** With the shell's own prompt
  (`polkit/AuthPrompt.qml`) a run's request shows, under the title, "Module" (the
  manifest's name, its id in brackets when the name does not read as the id), "Authorization"
  (the run's `what`) and "Command", closed for every new request, which opens on a click to
  the words handed to pkexec, the shell's `timeout` in front, shell-quoted, whole, in a box
  that scrolls, each word kept in its place whatever its script; then polkit's message and
  action. Every text there is plain text, each value on one line, cut with "…" at 40
  characters; a long name elides on the screen, leaving the room to the bracketed id, which is cut (in
  the middle) only when it alone is wider than the line; white space and
  blank-looking fillers fold to one space. A run of the old `PrivilegedAction` shows "Not
  named" and no Authorization line. The texts are one pure function,
  `PolkitRules.announcement`. Which request is a run's: the agent's flow names no caller
  and no command line, so `PolkitRules.announces` takes the run at the head of the queue
  when the action is pkexec's (`org.freedesktop.policykit.exec`) and the text between the
  message's first and last quote mark (of any language, one space inside each allowed) is
  exactly the run's command as pkexec puts it (polkit 0.120 and later: the words joined
  with spaces, past 80 bytes only their first 38 bytes, " ... " and their last 37). The
  fixed part of the message holds no other quote mark in any translation polkit ships, so
  a longer command holding quote marks of its own does not match. The decision is made
  once per request and kept, so a request still open when the next run takes the head is
  not dressed as that run's. A run is announced at most once. **The lines are attached by
  pkexec's message, which is all polkit tells:** past 80 bytes another command with the
  same two ends — another program's too — gives the very same message and is dressed as
  the run's. They help the user see what a module asks; they are not a guard against
  hostile code in the session. Any other request is shown as polkit sent it.
- **With another polkit agent** (`Authentication.state` `other`, `blocked`, `deciding` or
  `none`: the shell's prompt does not answer, or that is not known yet) the shell adds
  nothing to that agent's prompt, which names only the shell's `timeout`. Instead, when a
  run's turn comes, just before its pkexec starts, the shell sends one notification from
  the same announcement: summary "Module: <name>", body "Authorization: <what>" (an old
  `PrivilegedAction` run: "Module: Not named", no body), as plain text
  (`PrivilegedRules.launchNotice`). It says who runs what, not that a password is wanted:
  the shell cannot know whether that agent asks. One per run started; none for a run
  refused before pkexec, none while locked (nothing starts then), none with the shell's
  own prompt.
- **The words pkexec gets**: `<pkexec> <timeout> -k 3 <limit> <argv…>`. The shell's own
  trusted `timeout` runs inside pkexec, as root, and ends the command at its limit whatever
  happens to the shell. Nothing is put around pkexec: once the command runs as root the
  shell cannot signal it, and the kernel drops `setpriv --pdeathsig` at the exec of a setuid
  program. So `cancel()` after the start sends TERM and stops waiting; the command itself
  ends at its limit.
- **One queue** for the whole shell: one password question at a time. A run holds the head
  while its question can still come; with the shell's own prompt
  (`Authentication.state` `active` or `conflict`) until its own polkit request (the one
  `PolkitRules.announces` ties to it) was seen and no request is open any more, or 2 s
  with none. The agent shows one request at a time, so the run's own may wait behind
  another program's: while another request is open before the run's own was seen, the 2 s
  do not run (they start again when it ends). Any other program's open request — before
  the run's own or after it — holds the head at most 2 minutes from the run's start; only
  the run's own open request holds it longer, while the user answers. With another agent, which
  the shell cannot see, until it ends, at most 2 minutes. Then the next may start though the first still runs. A
  run cancelled while it holds the head keeps it until its pkexec has exited, or 3 s
  (`killAfterMs`) have passed, so its request is never shown with the next run's. A module
  turned off: its waiting runs leave, its started ones are cancelled, nothing of it is
  called. The session locked (`Profiles.screenLocked`): nothing starts, the waiting runs end
  `dismissed` with `blocked: "locked"`, quietly, and the shell's agent cancels the open
  prompt (and any that opens while locked), so the run whose pkexec was asking ends
  `dismissed` when pkexec exits. One log line per run started, with the
  module's id and its `what`.
- NixOS: pkexec is the setuid wrapper `/run/wrappers/bin/pkexec` (the store's copy is not
  setuid); `timeout` leads into the store.
- Arch: `/usr/bin/pkexec`, `/usr/bin/timeout`.

**The file chooser** (`module.chooseFiles(options, done)` on the handle;
`singletons/FileChooser.qml`, its decisions in `singletons/FileChooserRules.qml`): asks the
user for files or a folder. `options`: `mode` (`"open"`, the default: one file; `"openMany"`;
`"folder"`), `title` (plain text, one line, `<`, `>` and `&` dropped, at most 60
characters), `startDirectory` (an
absolute path; none: the home directory, `Api.system.home`). `done(result)`, called once
after the call has returned: frozen `{ paths (absolute paths, never URLs), cancelled,
blocked ("" | "locked" | "busy"), error }`; it returns `{ open, cancel() }`.
- **One at a time for the whole shell**, hosted by the shell and not by the caller's window,
  so a popup can ask and close: another call while one is open is `blocked: "busy"`.
- **The dialog is the system's**: QtQuick.Dialogs' `FileDialog` / `FolderDialog`, which Qt's
  platform theme (`QT_QPA_PLATFORMTHEME`) makes the portal's or GTK's where the user's theme
  says so, else Qt Quick's own. Qt Quick's own opens only with a visible window of the shell
  as its parent: the shell shows a window of one transparent pixel, which takes no input, while
  a dialog is open, and makes the dialog in it. Qt Quick's own returns one file even in
  `openMany`; the portal's can return several. Qt Quick's own folder dialog selects the
  first sub-folder as it opens: Open with nothing else picked returns it, and the folder
  shown only when it has no sub-folders.
- **The session locked**: nothing opens (`blocked: "locked"`); a lock while one is open closes
  it, answered the same (`blocked: "locked"`; `cancelled` is only the user's or the module's
  `cancel()`). **No title**: the dialog shows the module's name. **The module turned off**: its dialog is closed and `done` is never
  called. A portal's window belongs to another process and stays on screen in both cases;
  what is chosen in it then is dropped. The dialog is closed before it is destroyed:
  destroyed while open, Qt Quick's own leaves its window behind. **The shell going** (a
  reload): the dialog is closed at once, `done` is not called.
- The lock screen never depends on it (`tests/lock-closure.sh`).
- NixOS and Arch: the same; which dialog appears follows the user's Qt platform theme on
  either.

- **Tests**: `tests/CommandRulesTest.qml` and `tests/CommandRunnerTest.qml` (the runner's
  rules, and the runner against `sh -c` scripts), `tests/PrivilegedRulesTest.qml` (the rules
  of runs as administrator, the queue's life among them) and the fixture
  `tests/fixtures/modules/privileged` (its suite runs its stand-ins through the queue in
  module test mode: a stand-in pkexec that prints its arguments, streaming, cancels, the
  head and which request is its own, a module turned off, the lock),
  `tests/PolkitRulesTest.qml` (the prompt's texts and the matching of a request to a run),
  `tests/FileChooserRulesTest.qml` (the chooser's rules), `tests/FileChooserTest.qml` (the
  real dialog in the runner's headless compositor, driven by keys: a file chosen, a cancel,
  busy, a folder's Open with nothing picked, a lock, the shell going, the module turned
  off; each time the dialog's window gone from the compositor's list),
  `tests/AuthPromptViewTest.qml` (the prompt's Module, Authorization and Command lines),
  `tests/ModuleRulesTest.qml` (the rules), `tests/SystemFactsTest.qml` (the system facts
  from made-up readings, the reader on made-up files), `tests/ModulesTest.qml` (the host on
  the fixtures in `tests/fixtures/modules`: guard, file check, start guard, program lookup,
  data directories, and `provider` / `consumer` / `consumer-soft` and the chain `zmid` / `ztop` / `ztop-soft` / `ztop-unfit` for
  `exports` and `uses`),
  `tests/ModuleRegistriesTest.qml` (the registries, slots and the turning-off contract on
  the shell's own host), `tests/QuickshellPinTest.qml` (the Quickshell behaviour it all rests
  on — if it fails after a Quickshell upgrade, modules are broken by the upgrade), and the
  lock-bed tests `modules`, `modules-launcher`, `modules-discovery`, `modules-hung` and `modules-reload` (a reload while the file check runs). A module's own suites
  run with `tests/run-modules.sh <module dir>…` — the module may live in another repository;
  it is loaded into the shell's own host, with this tree as the config root, so its suites
  extend `TestCase` (`import qs.tests`, allowed in its tests only), use `qs.api` as in the
  shell and reach the module's singletons (`import ".."` from its `tests/`).
  `tests/fixtures/modules/good` is the worked example of everything above.
- **Module test mode** (`ModuleHost.testMode`, read by modules as `Api.testMode`): set only
  by the shell's test entry points — `tests-modules.qml` in process, a test tree through
  `TestSeams.moduleTestMode` — never by a variable alone, and never by a module:
  `ModuleHost.setTestMode` fixes it once, before the first load that names a module
  directory, and it is read-only from then on (`Notifier.recordOnly` follows that value).
  A module whose manifest names `testPrograms` (a directory inside the module) then gets
  every program it names from there (`module.programs`: trusted, reason "test stand-in"; a
  name the directory does not hold is not found, never taken from `PATH`); without test
  mode the field is ignored. A stand-in counts only when it, and the directory, resolve
  with links followed to a place inside the module's real directory, as its `.qml` files
  must — a link out (to `/usr/bin/pkexec`, `/run/wrappers/bin/pkexec`, anything) is no
  stand-in. `Api.openUrl` and `Notifier.send` record the call (`Api._opened`,
  `Notifier.recorded`) and open or send nothing. No command a module starts through the API
  (`CommandRunner`, `CommandAction`, `CommandQuery`, `PrivilegedAction`) holds a word whose
  last path part is `pkexec` — the program, or one handed to `env`, `timeout`, `setsid` —
  other than a module's `<testPrograms>/pkexec` (one its manifest names among its
  programs), and `PrivilegedAction`'s `elevate` must be that stand-in
  (`ModuleRules.testRunProblem`, `testElevateProblem`). A module written for an API below
  1.10 may still put a stand-in that lies anywhere into `elevate`: it runs unless a check
  finds it is the system's pkexec (the same file as
  `/run/wrappers/bin/pkexec`, `/usr/bin/pkexec` or what `command -v pkexec` finds on the
  system's directories) or a setuid or setgid file, and a check that fails counts as the
  real one. Which rule a run is under is read from the code that called it (the modules
  whose files are on its JavaScript stack: the gate only when all are older ones), and the
  gate is listed in the module's `deprecations`. `tests/run-modules.sh` puts a pkexec
  first on `PATH` that fails the run if anything starts it. `module.privileged` takes the
  module's `<testPrograms>/pkexec` and nothing else — without one it is not available —
  and its runs see the test kit's polkit agent and lock, never the shell's.
  `module.chooseFiles` opens no dialog: each call that would open one is recorded and waits
  for the suite's answer, and the lock it sees is the test kit's.
  `Api.system` and the network facts are then the test kit's made-up facts, nothing read, and the data
  directories lie below a private temporary home the host makes before the first module
  loads (`ModuleHost.testHome`: `mktemp -d` in `XDG_RUNTIME_DIR`, else `/tmp`), never in the
  user's data home. A module's suites see test mode through `ModuleTestKit` (`qs.tests`):
  `setEnabled`, `status`, `widgetEntries`, `opened`, `notified`, `setNow`, `setSystem`
  (the facts `Api.system` tells; never moves `module.dataDirectory`), `setNetworks` (the
  network facts: by default read and empty), `dataHome`, `chooserCalls`, `chooserOpen`,
  `answerChooser(moduleId, paths)`, `cancelChooser(moduleId)`, `setChooserLocked` (the
  file chooser; an open call and its lock are reset before each suite), `clearRecords`
  (shared by every module's suites), and for runs as
  administrator
  `setPolkitAgent`, `setPolkitRequest` (`{ command }`: pkexec's request for those words,
  its message written by the kit from pkexec's algorithm, not the shell's),
  `pkexecMessage`, `polkitRequestOpen`, `polkitAnnouncement`, `setSessionLocked` (the file
  chooser's lock too, and side panels': an open one closes), `privilegedIdle`, and
  `pageFrame` (the settings window's frame for a module's page, for a suite's own window:
  the page's `SidePanel`s open in it).

#### Modules and trust

A module is QML and JavaScript that the shell loads into its own process. Nothing separates
it from the shell: a module can do what the shell can — read and change the user's files,
run programs as the user, use the network, and see what the shell shows and what is typed
into it. The lock screen's password field and the password prompt for administrator actions
run in the same process, so a module could read what is typed there too.

**What the shell checks** before it loads a module: that its manifest is well formed and
asks for an API version this shell has; that every file it names lies inside its own
directory and is not too large; that its icon refers to nothing outside itself; which
programs it needs and where they were found (and whether each is trusted); whether it
reaches into the shell's internal parts; and that only a module whose manifest declares
administrator actions (`privileged`, API 1.36) runs them, and only once the user approved
that declaration. These checks catch mistakes. They do not make a module safe: a module that
wants to get around them can, because it runs inside the shell — the declaration is a
statement for the user and a guard against mistakes, not a sandbox. A shell that dies twice
in a row within 30 s of starting loads no module the next time (safe mode).

**What protects the user.** Built-in modules (the directory `H2S_SHELL_BUILTIN_MODULES`
names, given by the shell's installation) come with the shell and are reviewed with it; they
load without a question. Modules in a system data directory that root owns (a distribution
package, a NixOS configuration) are the administrator's to answer for, and count as
confirmed. Modules on the developer's `H2S_SHELL_MODULE_PATH` are not asked about either.
Any other module is its author's work, not the project's: a module placed in the user's
root loads only once the user has confirmed it, and waits for approval again when it starts
to declare administrator actions or names another author; installing one with the shell's
installer is the user's confirmation. The confirmation guards against mistakes and against
modules put there unnoticed, not against a program already running as the user: such a
program can write the user's files, the shell's configuration included, and on Arch the
built-in directory (`~/.local/share/h2s-shell/builtin/`) is the user's too — whatever lies
there counts as built in and is never asked about. A module asks for administrator rights only through
the shell's password prompt, which names the module, says what the action is for and shows
the command; for a module that is not the project's, that text is the only protection — it
is to be read, and cancelled when it does not match what the user just did. The shell never
installs or turns on a module without the user's action, and never asks for a password by
itself.

**What to install.** A module is like a program run as oneself: installed only from someone
trusted, from a repository one could read, and pinned to a tag rather than a branch that can
change underneath. What changed is read before updating.

#### Built-in modules

The repository's built-in modules are in `builtin-modules/`, each a module directory, with
`builtin.json` (`{ "off": [ids] }`: the ones that start off). None ships yet: it holds only
`builtin.json`, and a built-in root that holds nothing else finds no module and changes
nothing for the host. The shell loads them from a copy outside its own tree, which the
launcher names to the shell in `H2S_SHELL_BUILTIN_MODULES`. In a checkout run as the shell
(Arch; NixOS with `H2S_SHELL_DIR`), `builtin-modules/` lies inside what Quickshell scans: its name has a
hyphen, so no `import qs.…` can reach it, and each module brings its own `qmldir`, as the
fixture modules under `tests/fixtures/` do.

##### NixOS

`nix/package.nix` installs them to `$out/share/h2s-shell-builtin`, beside the shell's tree
(`$out/share/h2s-shell`, which leaves `builtin-modules/` out), and the `h2s-shell` command
sets `H2S_SHELL_BUILTIN_MODULES` to it — also when `H2S_SHELL_DIR` runs a checkout, and
whatever the caller had set.

##### Arch

`install.sh` copies the checkout's `builtin-modules/` to
`~/.local/share/h2s-shell/builtin/` (under `$XDG_DATA_HOME` when set), replacing what was
there; `install.sh --update`, after a `git pull` in the checkout, copies it again and does
nothing else. A link or a file in that place is left alone (status 1). The directory is
written only there, never by Settings or by the module installer; it is still a directory the
user owns, so a program running as the user can put a module there, and it loads as built in
without a question (see "Modules and trust"). `scripts/launch.sh`, when
`H2S_SHELL_BUILTIN_MODULES` is unset, sets it to that directory; set (empty included), it
takes what is given, and only an absolute path counts. When the root is that directory and the
checkout has `builtin-modules/`, the launcher's module search compares the two and says in its
log when the copy differs or is missing ("install.sh --update copies it again"), once per change
of that outcome.

### Logging

The lock screen logs on its own terms: every step of a
lock, one line each, `[Lockscreen]`, always on, never typed text; Quickshell keeps them in
`$XDG_RUNTIME_DIR/quickshell/by-id/<instance>/log.qslog` (`qs log`, stamped to the
second), the supervisor in `$XDG_RUNTIME_DIR/h2s-shell-launcher.log`, and
`scripts/lock-log.sh` (`h2s-shell --lock-log`) prints both with the journal's PAM / fprintd /
logind lines. The rest of the shell:

`components/Logger.qml` gives each subsystem a prefixed, individually switchable logger:

```qml
Logger { id: logger; prefix: "[STT]"; enabled: Profiles.value("stt.debug") ?? false }
```

`log()` and `warn()` respect `enabled`; `error()` always prints. The debug switches are
the global settings `general.debug`, `general.fetchDebug`, `gcal.debug` and `stt.debug`
(`singletons/SettingsSchema.qml`), read with `Profiles.value`. A handful of files call
`console.log` directly, bypassing this.

## Conventions

- **Colours and type sizes come from `singletons/Theme.qml`.** Nothing else should
  contain a literal colour.
- **Full variable names.** `calendar`, `response`, `calendarId` — not `c`, `r`, `cid`.
  Loop indices (`i`, `j`) are the exception.
- **Comments in English**, explaining *why* rather than restating the code.
- **Never bind a live reactive array straight to `Repeater.model`** — it crashes
  Quickshell. Wrap it in a `ScriptModel`; a list of JS objects goes through
  `components/KeyedModel.qml` (a ScriptModel of string keys, the delegate looking its item
  up by key), never into a ScriptModel as objects. The history and the rules that go with
  it are in [The Repeater crash](#the-repeater-crash).
- **`ShapePath` has no `visible` property.**
- **A control that looks different under the pointer uses `components/PointerArea.qml`**
  and its `lit`, not a `MouseArea` and `containsMouse`. The same for a mouse and a finger:
  `lit` holds a moment after a press, so a tap — over in ~80 ms — is seen, and the area
  is at least `Theme.target.minSize` (36 px) round the control, past its look, so a small
  control is easy to hit. Rows of a list that touch each other take `centred: false`
  (no larger area: it would take clicks from the next row); `reach` asks for more room
  than the minimum. Tooltips (`HoverTip`) stay on `containsMouse`: they are the cursor's.
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

Then run `tests/run-unit.sh`: the WidgetRegistry suite checks that every file the
registry names exists and compiles. A settings page of the shell's own (under
`panels/settings/`) is one entry in `SettingsWindow.corePages`: its id, label, tab and
component.

## Testing

`tests/run-all.sh` runs everything there is to run before a commit: the runners' own
self-tests and the deploy check's, `install.sh` under stand-ins, the unit suites, a module's
suites on the fixture module, the checks of the system the machine runs, and the lock
screen end to end — nearly all of the time the lock test bed; `--quick` leaves that out.
All parts but the lock bed run side by side (`-j <n>` at most n at once, `-j 1` one after
another), each with its output in a log of its own, printed in the list's order; the lock
bed runs last and alone. It stops at the first part that fails — nothing more starts, the
parts still running are ended (`--keep-going` goes on) — and ends with a summary naming
every part as PASS, FAIL or NOT RUN with the reason: a missing tool (named with its use), a
system without a set, a part left out, not reached or ended. A part that
did not run is never counted as passed; the exit status is 0 only when every part ran and
passed, 1 when one failed, 2 when one could not be set up. `tests/run-all-selftest.sh`
checks that verdict against made-up parts. The deploy check, `tests/device/deploy-check.sh`,
is run by hand against a running shell after it was updated: it reads the module host's
and the Tailscale module's state over the shell's IPC (reads only; no `tailscale` command)
and fails on a line repeated in the shell's log; `tests/deploy-check-selftest.sh` checks it
on canned answers. `tests/docs-check.sh` lints `README.md` and `docs/` for the
documentation's hard rules (no link out of the repository or to a missing file, no
developer's home path or machine, a NixOS heading only with an Arch one beside it, English
only); `tests/docs-check-selftest.sh`, a part of `--quick`, checks it on stand-in Markdown
and then runs it on the checkout. `tests/notes-ref-check.sh` fails on a file of the
repository (tracked, or untracked and not ignored) that refers to the working notes, which
are kept outside the repository (the released sections of `CHANGELOG.md` excepted; files
listed in `tests/notes-ref-allowance.txt`, with the number of mentions each may keep, are
reported, not failed); `tests/notes-ref-check-selftest.sh`, a part of `--quick`, checks it
on stand-in trees and then runs it on the checkout. Each part runs alone too, and takes
names for a part of it; the rest of this section describes them.

The tests are in two kinds of set. The **general** set gives the same verdict on every
system: the unit and module suites, the lock test bed, `tests/install-test.sh` and the
self-tests. A **system** set holds what is true of one system only ("The system sets",
below).

`tests/` holds a minimal harness (`TestCase.qml` with `assert`/`assertEqual`/`fail`) and
the suites `tests.qml` lists. `tests/run-unit.sh` (and `tests/run-modules.sh`, for modules'
own suites — see [Modules](#modules); both share `tests/headless.sh`) runs them in a private headless labwc
(private runtime dir, HOME and XDG dirs, D-Bus addresses that lead nowhere, no new
privileges), so the suites' windows never show on the real screen. `run-unit.sh` runs the
suites in parallel **shards**, each a Quickshell process with a compositor of its own and
only its suites selected: a suite whose file says `ownProcess: true` runs alone (and a
process where others report beside it fails) (it changes
what is shared in one process — the module host, `Config`'s list of modules turned off, the
keyboard its window takes); the others are packed by the time each took last
(`~/.cache/h2s-shell-tests/unit-times.txt`, rewritten after each run; without it 5 s for an
asynchronous suite, 0.1 s for another) into as many shards as it takes for none to run longer
than the longest suite, at most half the processors' worth at once, and no more than the
memory available holds at about 1.1 GB a shard (`-j <n>` says how many).
The plan is computed (`plan_shards` in `tests/count-suites.sh`), never kept by hand. Each
shard is the runner again on its suites, with its own verdict, printed when it ends; the
verdict over them wants every suite run to report exactly once. The whole set takes about
15 s on a 32-thread machine (15 shards, all at once), and about a minute where the memory
allows three at a time; the floor is the longest suite alone (`AnchorsTest` and `ModulesTest`,
about 11 s each). In a unit run every animation that ends takes 1 ms
(`Theme.instantAnimations`, set by `tests.qml`), so no suite waits on motion; a suite that
tests an animation keeps them (`TestCase.animations`). Each suite that shares its process is
checked when it reports: `TestCase` compares the shared state (`tests/SharedStateReader.qml`:
`Config`'s stored fields, the profiles, the module lists the core reads, the toasts, the Theme
switches suites flip, and the network's state where a suite names it) with what it was when
the suite started, and fails it, naming what changed, when it left it otherwise (a suite with
`ownProcess: true` is not checked). `run-unit.sh` also puts
stand-ins for `nmcli` and `notify-send` first on `PATH` (`tests/fixtures/unit-path`), for the
suites that build the real settings window and with it the network readers; it finds labwc and
Quickshell through `tests/lock/resolve.sh` ("Where the test tools come from", below) and fails on any `FAIL`, a
`TypeError`/`ReferenceError`, a non-zero exit of a shard's Quickshell (a crash after a
partial summary), the suites that report not being exactly those run, a suite reporting
0/0, or more `PASS:` lines than the summaries count (a check made after its suite
reported); the lock bed fails a scenario that ends well without a `PASS` line;
`tests/run-unit-selftest.sh` checks that verdict against stand-in Quickshells, in one shard
and over several, the suite count (`tests/count-suites.sh`: a suite written with arguments
counts too) and the shard plan.

Both runners can run a part: `tests/run-unit.sh FormatTest LockRulesTest` runs the named
suites (a suite is named by its type, the file in `tests/` without `.qml`), and
`tests/run-modules.sh --suite GoodApiTest <module dir>…` the named suites of the modules
given. `--log <file>`, before the names, also saves the output. The list of suites stays
`tests.qml`, one `property var _name: SomethingTest {}` line per suite and no other list:
the runner reads the suites from those lines, and `tests.qml` finds its asynchronous ones
among its own properties. No suite waits for another — each builds its own state; a suite
given another on its line (`SomethingTest { other: _name }`) would run in its shard and be
counted, and none is now. The names reach `TestCase` as
`H2S_TEST_SUITES`: every suite is still built, one that was not selected does nothing
(`TestCase.selected`), and it is found by its `suiteName` followed by `Test`, so a suite's
file is called that. With names the verdict wants exactly the selected suites to report; a
name that is no suite ends the runner with status 2 before anything is started. For a
module the names reach `tests-modules.qml` as `H2S_TEST_MODULE_SUITES`, which creates only
those suites and says so when a name is in no module's list.

Most suites run their assertions in `Component.onCompleted`, on pure
functions (the `*Rules` and geometry singletons, parsers). A suite that throws counts as
failed, not as missing.

A suite that needs the event loop sets `asynchronous: true`, does its work in
`runAsync()` and calls `finish()`; `tests.qml` waits for it. Each asynchronous suite has
its own limit, counted from when its process starts the suites: `TestCase.timeLimitMs`, or
the runner's default — 90 s in `tests.qml`; 20 s in `tests-modules.qml` (a module's suites,
`tests/run-modules.sh`), which caps it at 60 s. A suite with many concurrent scenarios
declares more. In one process the window suites do not run side by side: one that waits in
a nested event loop (QtTest's `wait`) holds the next one's start until it returns.
`FileChooserTest`, which opens a real dialog that takes the keyboard, runs in a process of
its own. Of the shell's own, `PointerInputTest.qml` is one asynchronous suite: it puts real components (`BarWidget`,
`PopupWidget`) in a small layer window and drives them with QtTest's `TestCase` used by
hand (`when: false`) — `mouseMove`, `mouseClick`, `touchEvent` — to check what a mouse and
a finger do. It needs a Wayland session — `run-unit.sh` gives it its own. A stylus cannot
be sent that way. `ButtonKindsTest.qml` does the same for the buttons (`SmallButton`,
`DeleteButton`): each kind's fill, label and border at rest, under the pointer, asking and
not available. `PillSizesTest.qml` builds a `Pill` of each size, and reads the sources
(`tests/pill-sizes.sh`): no pill of the shell sets its height itself, each names the size
written in the test. `LockViewTest.qml` is another: the lock prompt and a notification card fed
views the way `Lockscreen` feeds them (answer hidden or shown, a long question in full, an
error, the compositor's late notice, "Unlocking…", the passive methods' lines, Caps Lock,
each notification detail as plain text). `VpnProvidersTest.qml` is a third: the VPN
provider seam's rules, then `VpnManager` driven with the stand-in provider — a provider
destroyed while registered, who asked a connect, a slow operation (steps wait on conditions;
provider ids unique to the suite), the popup's VPN section, a card and a provider's page frame
built with a provider's VPNs.

The window suites drive their window through `tests/WindowDriver.qml`, QtTest's `TestCase`
used by hand: it counts the window as shown once a frame of it was drawn, and `waitShown()`
comes before the first event, in place of a fixed wait.

`tests/device/` drives the running shell on a touch device through the whole stack — a
virtual touchscreen (uinput) → Hyprland → the shell, and the on-screen keyboard reacting —
which QtTest, sending events to the Qt window directly, cannot reach. It finds what to tap
through the `shelltest` IPC (`Bar.qml`). See its README.

`tests/lock/` runs the real shell, from a copy of the checkout made at the start of a run
(so edits during a run cannot reload it; each test gets its own copy of that) — a test
tree, below — in an invisible, isolated compositor (Hyprland nested in a
headless labwc, private runtime dir, no D-Bus, no seat, no new privileges) and drives its
lock screen end to end: locked for real, keys typed and the pointer moved through the
compositor, PAM against test stacks (`H2S_LOCK_AUTH_METHODS`, see
`scripts/lock-auth-methods.sh`; the copy's own `pam/` configs only deny, and the "system"
PAM directory the password fallback is chosen from is the test's own,
`H2S_LOCK_SYSTEM_PAM_DIR`), logind's signals, the sleep inhibitor and fprintd through
stand-ins (`H2S_LOCK_TOOLS`; the real methods script runs against the fprintd one in
`methods-script.sh` and `methods-fprintd.sh`; the first runs it as NixOS and as any other
system on every machine, `H2S_LOCK_SYSTEM`). `tests/lock/run.sh`
runs it, several tests at a time, each in a stack of its own (`-j N`; `-j 1` one after
another); nothing appears on screen and the real session cannot be reached. See its README.

`tests/install-test.sh` runs `install.sh` without letting it change anything: an empty
environment, a private home directory and a `PATH` of one directory that holds recording
stand-ins for `sudo`, `pacman`, `git`, `fc-list` and for the programs that could change a
system, plus the plain tools the script uses (`cp`, `mv` and `rm` among them, for the
built-in modules); no new privileges; a terminal of the
run's own (`script`), since the script hands `pacman` the terminal. Before anything runs it
checks that every privileged name on that `PATH` is one of its stand-ins, and reads
`install.sh` for ways around them, stopping with status 2 at any: a program named by its
path, `command -p`, an assignment to `PATH`, `exec`, `eval`, `source` or `.`, a variable as
the command, a command substitution in a here-document. That reading refuses these forms
and proves nothing more; what holds whatever the script says is the empty environment, the
one-directory `PATH`, the private home and no new privileges. It checks
the packages asked for and how, where the shell is cloned, where its built-in modules are
copied (and that `--update` copies them again, alone: no packages, no `sudo`), that nothing
else runs as root, that a second run changes nothing, another Quickshell config and a link
where the built-in modules go left alone, and what happens when `pacman`, the clone or
reading the config's origin fails, and that the helper is built as the user after the
clone and at `--update` (by a stand-in `scripts/build-helper.sh` in the stand-in clone), a
build that fails being a warning only. It runs on both systems.

`tests/run-helper.sh` builds the helper into a temporary directory and runs it: `--version`
(the shell's version and the protocol `HelperRules` speaks), a wrong subcommand, and a
`ping` conversation driven as the shell drives it (a round trip, what is not a JSON
object, a line too long, its standard input closed: it ends). Then
`scripts/build-helper.sh` in a copy of the tree with a stand-in `cmake` (the directories it
refuses, `--status`, a build, `--if-changed` with the source unchanged, changed and only
the version changed, a failed build, one past its time limit), and `scripts/launch.sh
--helper` with a stand-in build script (each place the helper is looked for, a stale build
handed over at once and rebuilt in the background without being waited for, none yet, a
failed build, a locked session, the log line once per outcome), and that nothing runs the
helper through pkexec, sudo or the like. The shell's
side, `HelperRules` and the `--version` reading, is the unit suite `HelperTest`, on
stand-in programs.

### Which tests a change needs

`tests/affected.sh` answers it mechanically and prints the commands that run them (`--run`
runs them too, one after another, the lock bed last). The change is the branch's: from its
nearest base — the fewest commits back of where it left a `segment-*` branch or `master` —
to the working tree, untracked files included; a git range (`HEAD~3`, `master...HEAD`) or
`--files <path>…` names another. `--why` prints each changed file and what it selects. A unit
suite covers its closure: every type and singleton its file names, every path quoted in it,
transitively; a module fixture part covers `tests-modules.qml`'s closure and its directories;
a self-test covers itself; a lock scenario covers its file and runs on any change in the lock
closure. `tests/affected-map.txt` places what a closure cannot see — scripts, the runners, the
lock scenarios' subjects — and lists what needs no test (`none`). A changed file nothing
places selects everything. `tests/affected-selftest.sh` runs `affected.sh --check` (every
tracked file placed, every map line true) and checks the selection on made-up repositories.

### Finding checks that cannot fail, and flakes

A suite that reports 0/0 fails, and so does a lock scenario that ends without a `PASS` line.
`tests/mutate.sh <file> [<suite>…]` goes further: in scratch copies of the tree (never the
checkout) it applies one mechanical mutation at a time to a `*Rules.qml` or a singleton —
`===`↔`!==`, `<`↔`<=`, `&&`↔`||`, `true`↔`false`, a `!` dropped, an integer constant + 1, a
one-line `return` negated — on code only, not in comments or strings, and runs each mutant
against the file's own suite first, then the other unit suites `affected.sh` selects for the
file. A mutant is killed (a suite failed, or it ran past four times the unmutated run's time),
not compiled, not run, or survived; the survivors are listed with file, line and column, and
each is a missing check or a mutation that changes nothing. `--list` prints the mutants, `--max
<n>` (with `--seed`) picks some at random, `-j <n>` runs that many at once (by default as many
as the unit runner's shards). Suites that fail unmutated end it with status 2. It is run by
hand on a new or much changed Rules file; `tests/mutate-selftest.sh`, a part of `--quick`,
checks its verdicts on a fixture Rules file with a mutant of each outcome.

`tests/soak.sh <suite | module dir> <n>` runs one unit suite, or a module's suites, n times
in a row under busy loops (one per processor, `--load <k>` for k), keeps the output of a run
that failed and names it: a check that depends on timing fails there in minutes. It exits 1
when any run failed, 2 when a run could not be set up.

The lock bed runs a scenario that failed once more at the end of its run, alone; passing then
it is **FLAKY** — still a failure of the run, written to
`${XDG_CACHE_HOME:-~/.cache}/h2s-shell-tests/flaky.log` with the commit, the machine's load and
where its first log is kept (`LOCKTEST_RERUN=0` runs nothing twice). `tests/lock/lint.sh`, run
by the bed on its scenarios and by `tests/lock/selftest.sh`, refuses a fixed `sleep` that does
not say why on its own line (`# fixed sleep: <reason>`); a scenario waits on conditions, and a
check whose subject is a time bound runs alone (`check_timed`, `SERIAL`). The full bed takes
about two minutes on a 32-thread machine and about four where fewer scenarios run at once
(`tests/lock/README.md`).

### The test tree

The lock test bed changes what the shell does through environment variables — stand-in
`gdbus` and `systemd-inhibit`, its own PAM directory and methods script, short timings, a
reload IPC, the module host's checks, a stand-in VPN provider (the seams; the list, with
what each changes, is in `tests/lock/README.md`, "The test tree"). The shell itself reads
none of them: a variable left in a terminal or the systemd user environment must never
change the real lock screen. They reach the shell through two files, each in two versions
with the same names:

- `singletons/TestSeams.qml` — read by `Lockscreen`, `CapsLockLed`, `Modules` and
  `VpnManager`. The shell's version holds constants (what the reader gives with nothing set:
  the real directories and tools, no timings, no stand-ins, module test mode off). The test
  version, `tests/lock/seams/TestSeams.qml` with `TestSeamRules.qml` beside it, reads the
  variables, and holds the `locktest` reload IPC and module test mode on (so in the lock
  bed the shell's notifications are recorded, not sent: "Module test mode" under
  "Modules").
- `scripts/seams.sh` — sourced by `scripts/lock-auth-methods.sh` and `scripts/launch.sh`.
  The shell's version sets constants; `tests/lock/seams/seams.sh` sets the same names from
  the variables.

A **test tree** is a copy of the checkout with the test versions in place:
`tests/test-tree.sh <dest>` makes one (the checkout without `.git` and `result*`, the three
files copied over). `tests/lock/run.sh` makes each run's copy with it, then removes
`tests/lock` from the copy and replaces `pam/` with configs that only deny; `stack_start`
checks that the shell under test reports the seams in force, so a copy without the swap
fails at once. Unit suites guard the arrangement: `TestSeamsShapeTest` (the two versions
have the same names and types, the shell's are constants with the no-seam values, and no
file of the shell outside `tests/` reads a seam variable — `H2S_LOCK_*`, `H2S_*TEST*`,
`H2S_FAKE_*` — itself), `TestSeamRulesTest` (what each variable says) and `TestTreeTest`
(the tree has the test files, the checkout is untouched). Adding a seam means a name in both
versions and a case; `tests/lock/README.md` lists the steps.

To use test behaviour by hand — the stand-in VPN provider, say — make a test tree and start
the shell from it with the variable set, in a nested compositor (labwc opens as a window)
with a runtime and config directory of its own, so that it shares neither the launcher's
lock, the lock marker nor the settings with the session's shell. `tests/lock/README.md`
gives the commands. They differ only in the launcher:

#### NixOS

The package's `h2s-shell` runs the tree named by `H2S_SHELL_DIR` (with the programs the
package puts on `PATH`). `tests/lock/` is not in the package, so an installed shell has no
test files at all.

#### Arch

The shell is a checkout, so the test files are on disk, but nothing loads them unless they
are copied over the production ones, which only `tests/test-tree.sh` does. The tree is
started with its own `scripts/launch.sh`, which runs the `qs` on `PATH`.

### The system sets

`tests/run-system.sh` runs the checks of the system the machine runs, read from
`/etc/os-release` (`ID=nixos`; `ID=arch`, or `arch` among `ID_LIKE`): the files in
`tests/system/nixos/` or `tests/system/arch/`, each a short list of
`check <description> <command…>` lines. `tests/run-system.sh <check>…` runs the named
ones. On another system, for a name that is not in this system's set (the other system's
included) or for an empty set it ends with status 2 and says which system it found — a set
that did not run is never printed as a pass; a check that lacks its tool is NOT RUN, with
the tool and its use. The checks only read: nothing is installed, nothing runs as root.
`tests/run-system-selftest.sh` checks the runner against made-up sets and `os-release`
files, on either system.

#### NixOS

- `package`: the flake's package builds (`nix`, into the store; no link, no lock file
  written); its version is `singletons/Version.qml`'s; `tests/lock`, `docs` and `helper`
  are not in it; its `h2s-shell` command runs the checkout `H2S_SHELL_DIR` names with the
  arguments given, and every program the shell calls is on the `PATH` it sets; the
  built-in modules are in `share/h2s-shell-builtin`, as `builtin-modules/` holds them, not
  in the shell's tree, and the command hands that directory to the launcher
  (`H2S_SHELL_BUILTIN_MODULES`).
- `layout`: the files the shell's code reads on NixOS are where it looks for them.

#### Arch

- `packages`: every package `install.sh` installs, and every one it or the HUD names to
  the user, is in the repositories (`pacman -Si`).
- `test-tools`: the packages the test tools come from (the list under "Where the test
  tools come from", Arch) are in the repositories; one that is not installed is noted
  with its use.

`tests/manual/` holds checks no suite runs because they touch the real system — the one
there runs a single PAM conversation with the real password against the shipped
`pam/password` (its README).

Everything else is verified by hand: run `quickshell` from the repo root and check that
the bar renders, the clock ticks, cells respond, and popups toggle. Apart from the lock
screen, there is no automated coverage of any singleton that touches the system.

### Running the tests on another machine

`tests/remote-run.sh` runs a branch's tests on another machine over SSH — the way a change
made on one system is tested on the other, NixOS and Arch alike:

```
H2S_REMOTE=<ssh destination> tests/remote-run.sh [<ref>] [-- <command…>]
H2S_REMOTE=<ssh destination> tests/remote-run.sh --attach <id>
```

The destination comes from `H2S_REMOTE` (or `--host`) and is never written to a file, here
or there; ssh runs with `BatchMode=yes`, so it never asks for a password. `<ref>` defaults
to `HEAD`, which must then have no uncommitted changes; the command defaults to
`tests/run-all.sh --keep-going`. The remote is asked which commits its repository has
(a default checkout path on the remote, named in the script's header; `H2S_REMOTE_REPO` or
`--repo` names another), and what it lacks goes over as
a `git bundle` — the whole history when they share none. It is fetched into that
repository's objects under a ref of its own, and the run gets a detached working tree of
its own in `~/.cache/h2s-shell-tests/remote-run/<id>/` on the remote, beside its log, so
the remote's checkout and a shell running from it are never touched. The command starts in
a new session (`setsid`), so a dropped connection does not end it, with SIGHUP at its
default (`env --default-signal=HUP`, not `nohup`: the launcher's tests check it). The script
polls for its end (every `H2S_REMOTE_POLL` seconds, default 15; for at most
`H2S_REMOTE_WAIT` or `--wait-max` seconds, default 3600), brings the log back to
`~/.cache/h2s-shell-tests/remote/<id>.log`, prints the tool lines, the log's last lines
and the runner's summary, removes the remote tree and bundle, and exits with the remote
command's status — 2 when the run could not be set up (no destination, the remote
unreachable, no repository there), was lost, or was still going at the limit. Interrupted
or cut off, it prints the run's id and the run goes on; `--attach <id>` collects it later.

It needs git and ssh here, and git, bash, `setsid` and coreutils' `env` (8.31 or later) on
the remote; the run there takes its test tools as any run on that system does. The
arguments go to the remote's bash on standard input, so the remote login shell only runs
the words `bash -s` and one single-quoted `bash -c` command: a POSIX shell, bash, zsh and
fish all do. Cleaning up removes the run's own worktree entry only, never the remote
repository's other worktrees.
`tests/remote-run-selftest.sh`, a part of `--quick`, checks it against a stand-in `ssh` that
runs the remote half locally in a temp directory: a pass and a failure status, a dropped
connection and the time limit each picked up with `--attach`, an unreachable remote, a
missing repository, and the destination in no file written.

### Where the test tools come from

The unit and module suites need Quickshell, labwc, `setpriv` and `setsid` (util-linux) and
`timeout` (coreutils). `tests/lock/resolve.sh` takes labwc and `setpriv` from one source
for the whole run: the pinned build of `tests/lock/tools.nix` when a `nix` command exists,
else the programs on `PATH`, in whatever version is installed. `H2S_TEST_TOOLS=nix` or
`H2S_TEST_TOOLS=system` chooses. Quickshell is `LOCKTEST_QS` when set, else the one the
`h2s-shell` launcher runs (`LOCKTEST_LAUNCHER` names another launcher), else `qs` or
`quickshell` on `PATH`. A run starts by saying what it took:

```
tools: system (PATH, not pinned) — labwc 0.9.1, setpriv 2.42.4
quickshell: /usr/bin/qs 0.3.2 (PATH)
```

Versions are printed, not checked. A missing tool is a set-up error: status 2, every
missing tool named with its use, nothing run. `tests/resolve-selftest.sh` checks the lookup
against stand-in programs; it needs neither `nix` nor labwc.

`tests/run-helper.sh` makes the same choice for the helper's build: with `nix`, the flake's
`h2s-helper` package, with nix's own cmake, compiler and Qt; from the system, `cmake`, a
C++ compiler and Qt 6's development files on the machine (a missing `cmake` is a set-up
error, status 2).

The deploy check (`tests/device/deploy-check.sh`) and its self-test take only a `python3`
(for the shell's JSON answers) from the same source: the pinned set's where there is `nix`,
else the one on `PATH`; none is a set-up error, status 2.

The lock test bed (`tests/lock/run.sh`) takes a larger set from the same source: labwc,
Hyprland and `hyprctl`, grim, wlr-randr, `wl-copy` and `wl-paste`, `xkbcli`, `dbus-daemon`,
`gdbus`, `setpriv`, a `python3` that imports pywayland, the Python bindings of the virtual
keyboard, virtual pointer and xdg-shell protocols, and three keymaps. `tests/lock/tools.nix`
builds all of it. From the system the programs are those on `PATH`, and the bindings and
keymaps are made at the start of each run, in the run's own directory, by the commands
`tools.nix` runs: pywayland's scanner over `wayland.xml`, `xdg-shell.xml` (found with
`pkg-config`) and the two wlroots protocol files kept in `tests/lock/protocols/`, and
`xkbcli compile-keymap`. `setsid` and `timeout` are the ones on `PATH` either way.

The bed starts the shell through a launcher, as it is started for real:
`LOCKTEST_LAUNCHER` when set, else the `h2s-shell` on `PATH`, else its own
`tests/lock/launcher.sh`, which runs the `scripts/launch.sh` of the checkout
`H2S_SHELL_DIR` names with the arguments it is given — what the packaged launcher does
with that variable set. A run through it says so in its first lines and in its summary:
the supervisor, the restart and `ipc` under test are `scripts/launch.sh` either way, but
what the package adds (its Quickshell and the shell's programs first on `PATH`) is not
tested by such a run.

```
tools: system (PATH, not pinned) — labwc 0.9.1, setpriv 2.42.4, Hyprland 0.57.2
launcher: …/tests/lock/launcher.sh (the test bed's stand-in: no LOCKTEST_LAUNCHER, no h2s-shell on PATH)
quickshell: /usr/bin/qs 0.3.2 (asked of the launcher …/tests/lock/launcher.sh)
```

The PAM modules of the test stacks (`pam_exec`, `pam_deny`, `pam_permit`, `pam_stress`)
are the ones beside the libpam Quickshell links, on both systems.

#### NixOS

`nix` builds the pinned tools, for the unit suites, the lock test bed and the deploy check's
`python3` alike (there is no `python3` on `PATH` to fall back on), and the helper's package
for `tests/run-helper.sh`. The
launcher is the package's `h2s-shell`, so the tests run the Quickshell the installed shell
runs.

#### Arch

Without `nix`, the tools are development dependencies to have installed; `install.sh`
does not install them. The packages, each with what the tests use it for
(`tests/system/arch/test-tools.sh` checks the names):

| Package | Used for |
|---|---|
| `quickshell` | runs the suites and the shell under test |
| `labwc` | the headless compositor the suites' windows open in |
| `util-linux` | `setpriv`, `setsid`, `flock`, `script`: the test processes' isolation, the bed's lock, a terminal for `install.sh` |
| `coreutils` | `timeout`: ends a compositor or a Quickshell that hangs |
| `hyprland` | the compositor the lock screen is tested in |
| `grim` | screenshots of the lock screen |
| `wlr-randr` | sets the headless output's size |
| `wl-clipboard` | `wl-copy`, `wl-paste`: the primary selection of the paste test |
| `libxkbcommon` | `xkbcli`: tells the virtual keyboard which keys type a character |
| `dbus`, `glib2` | `dbus-daemon`, `gdbus`: a private session bus for the notification tests |
| `python`, `python-pywayland` | the virtual keyboard and pointer, and the scanner their bindings are made with; `python` also reads the shell's answers in the deploy check |
| `pkgconf`, `wayland`, `wayland-protocols` | finding the protocol files those bindings are made from |

`tests/run-helper.sh` builds the helper with `cmake`, `base-devel` (the compiler) and
`qt6-base`, which `install.sh` installs.

The first four are enough for everything but the lock test bed. The bed takes the first
`python3` on `PATH`; it has to be one that imports pywayland. There is no `h2s-shell` command, so the unit and module suites run
the `qs` on `PATH`, and the lock test bed starts the shell through `tests/lock/launcher.sh`.
With `nix` installed, the pinned tools are used as on NixOS.

For the unit and module suites: `labwc` (the headless compositor); `util-linux` and
`coreutils` are part of every system.

For the lock test bed, beside those:

| Package | What the test bed uses it for |
|---|---|
| `hyprland` | the compositor the lock screen is tested in, and `hyprctl` |
| `grim` | screenshots of the lock screen |
| `wlr-randr` | sets the headless output's size |
| `wl-clipboard` | `wl-copy` and `wl-paste`: the primary selection of the paste test |
| `libxkbcommon` | `xkbcli`: compiles the keymaps, tells the virtual keyboard which keys type a character |
| `dbus`, `glib2` | `dbus-daemon` and `gdbus`: a private session bus for the notification tests |
| `python`, `python-pywayland` | the virtual keyboard and pointer, and the scanner that generates their protocol bindings |
| `pkgconf` | `pkg-config`: finds the protocol files the bindings are generated from |
| `wayland`, `wayland-protocols` | those files: `wayland.xml`, `xdg-shell.xml` |
| `pam` | the modules of the test stacks |

The `python3` taken is the first on `PATH`; where a Python version manager puts its own
first, that one has no pywayland, and the run says so — start the run with the system's
directory first on `PATH`.
