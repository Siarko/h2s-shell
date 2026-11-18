# Architecture

Technical reference for the H2S Quickshell desktop shell. For what the shell does from
a user's point of view see [FEATURES.md](FEATURES.md).

## Runtime model

This is not a compiled application. [Quickshell](https://quickshell.outfoxxed.me/)
interprets the QML directly, so there is no build step:

```
quickshell                 # reads shell.qml from the current directory
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
no `qmldir` in the shell's own directories and none should be added — registration is
automatic. (Modules are the exception: a module directory, loaded by URL from outside
what Quickshell scans, needs its own — see [Modules](#modules); the fixture modules under
`tests/fixtures/` have one.)

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
├── screensaver/          screensaver surface + the lock surface and prompt (views of Lockscreen)
├── pam/                  the lock screen's own PAM configs, one per way of unlocking
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
opened with `Shell.openSettings(category)` and toggled with `Shell.toggleSettings()`, and
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
get. Everything it reports is checked by `NetworkRules.vpnProviderEntries` (wrong entries
dropped and logged, never shown). `VpnManager.vpns`, `details`, `interfaceOf` and the rest
are the merged model the popup, the bar, the overview, the VPN page and the connection
editor read; with no provider registered they are NetworkManager's lists themselves. The
kill switch (`VpnLockdown`) reads `nmDetails`/`nmInterfaceNames` only — it does not support
provider VPNs, and says so on their cards (and rows, while up) while blocking. Providers fill the slots named in
`VpnManager.slots` (`network.vpn.row`, `.card`, `.page`) through `VpnManager.extrasFor`.
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

### Lock screen

Four layers, so that what decides can be tested without what does (the rules and the
launcher agree on the contract described under "Recovery" below):

- **Rules** — `singletons/LockRules.qml`, pure: `initial(settings)` and
  `step(state, event, now) → { state, effects }` on plain objects that are replaced, never
  mutated; `view(state)` for the views, `describe(state)` for anything shown (no secret).
  Every decision is here — when a conversation starts, what a PAM answer means, where the
  prompt is, when the field empties, what sleep does. Unit-tested in
  `tests/LockRulesTest.qml` (behaviours, a seeded sweep, a liveness oracle).
- **Driver** — `singletons/Lockscreen.qml`, the one owner of the lock's state. It feeds
  events to the rules one at a time (`LockIoRules.serialQueue`: an event raised while a
  step's effects run is queued, never re-entered), stores the new state before running its
  effects, and carries the effects out (`LockIoRules.runStep`: each part guarded, so a
  view that fails to publish cannot keep the lock from being set): the `WlSessionLock`,
  one single-shot `Timer` per timer name (tokens from the rules), `Profiles.screenLocked`
  and `Quickshell.watchFiles` (off while locked: a reload while locked would unlock), the
  adapters. It exposes only `view`, `locked`, `screensaverVisible`, `lock()`, the surface
  functions the views call (they take the `LockSurface` object and act only for a
  registered one), and the IPC (`lock`, `status`, `state` = `describe` plus a few driver
  facts). There is no unlock and no dispatch function: the state, queue and surface
  registry live in a closure (`_build()`), not in properties. Same-process QML is still no
  security boundary (it can emit its child objects' signals, or run `loginctl
  unlock-session`). It also owns
  idle (two `IdleMonitor`s, each made anew by `singletons/lock/IdleWatch.qml` whenever its
  settings change — a live one whose timeout changes can stop reporting idle, a Quickshell
  0.3.2 bug), the screensaver and its commands,
  and the password fallback (`LockIoRules.passwordFallback`, from a probe of the machine).
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
  restarted with a growing pause, kept from outliving a crashed shell by a stdin watcher)
  and `SleepInhibitor.qml` (`systemd-inhibit` held as a level, taken again when lost).
  Their small pure helpers are in `singletons/LockIoRules.qml` (tested in
  `tests/LockIoRulesTest.qml`).
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
session):

- *A reload while locked* keeps the lock. Quickshell hands a reloaded singleton's children
  their old instances by position; a `PersistentProperties` (`_carried`: "this process holds
  a compositor lock", "the compositor confirmed it") placed before the `WlSessionLock` gets
  its `reloaded` first, and sets the new `WlSessionLock`'s `locked` before Quickshell
  realizes it — so it takes the old lock over instead of unlocking. The rules go on from
  their `restored` event (a fresh lock on the carried compositor lock: no new lock request,
  fresh adapters, methods asked again, nothing typed before survives). File changes still do
  not reload while locked (`watchFiles` off); edits made meanwhile take effect at the next
  file change after the unlock (no reload at unlock: it dropped lock requests). A reload that cannot carry the lock (a hard reload, `reload(true)`)
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
  holding `<socket>.lock`); with a growing pause, at most 5 restarts in 2 minutes — then,
  if the screen was locked, once a minute; it kills what the dead shell left of
  Quickshell's own binary in that group (PAM helpers, which would keep a fingerprint reader
  claimed; not the crash reporter). SIGHUP (its terminal closed) does not stop it. Quickshell's own crash handler restarts a crashed shell
  in the same process (unless it crashed within 10 s of starting): no second shell, and the
  launcher sees nothing — so the restarted shell itself kills, once, the PAM helpers its
  process had forked before the crash (`_helperSweep`).
- *A reload while unlocked* (a file saved — dozens of times a day here) blocks the event
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
(the facade, the slot table, the handle, the lifetime rules) is the header of `api/Api.qml`;
the manifest schema is in `singletons/ModuleManifestRules.qml`. What exists: the rules, the host, discovery,
the `qs.api` facade, the registries taking modules' contributions, and slots.

- A **module** is a directory with a `module.json` (the schema: `singletons/ModuleManifestRules.qml`'s
  header), a `qmldir` for its singletons, and QML loaded by `file://` URL —
  never imported statically (a broken one would fail the whole config). Every file the
  manifest names must be a regular file inside the directory (a link out of it, a FIFO, a
  file over 1 MiB: the entry is dropped, or the module fails for its main).
- **Discovery**: `scripts/launch.sh` (`discover_modules`, before every start of the shell)
  builds `H2S_SHELL_MODULES` (the shell's input; the launcher's output) — canonical module
  directories from `H2S_SHELL_MODULE_PATH` (the developer's list), then
  `~/.local/share/h2s-shell/modules/*`, then the system data directories'
  `h2s-shell/modules/*` (`H2S_SHELL_MODULE_DATA_DIRS`). Safe mode (no module loads): after
  two deaths within 30 s of starting in a row (the launcher: `H2S_SHELL_SAFE_MODE=1`), or two of
  Quickshell's in-place relaunches after a crash in a row, neither living 30 s — which the
  launcher does not see; the shell counts them (`$XDG_RUNTIME_DIR/h2s-shell-module-starts`).
- **The host**: `singletons/ModuleHost.qml`, one instance in the `Modules` singleton, which
  `shell.qml` touches before the bars. It reads no module file on the GUI thread: the
  manifests, qmldirs and file texts come out of its file check (a process, with a deadline),
  then it checks them and looks up the programs they name (a process too: the program
  lookup below), creates each enabled module's `main` inside
  a guard (the file check, the program look-up, the start guard and the making of the
  stores' directory each run one command through a `singletons/io/CommandRunner`, under
  the host's `checkTimeoutMs`), keeps a handle per module (`api/ModuleHandle.qml`) and each one's facts, and
  exposes the statuses and the merged contributions. `qs ipc call modules list` prints them;
  `qs ipc call modules setEnabled <id> <bool>` turns one off or on (`Config.disabledModules`).
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
- **Slots**: `components/ModuleSlot.qml` — `ModuleSlot { name; context }` where a core panel
  lets modules in; the names and contexts are `ModuleRules.slotTable`. Never on the lock
  screen (a suite checks `screensaver/`, `singletons/lock/`, `Lockscreen`, `pam/` and the
  components they build, transitively: `tests/lock-closure.sh`).

Writing a module, from the author's side (everything through `import qs.api`; nothing from
`qs.singletons`, and `qs.components` — the shell's internal components, which may change
in any release — only for a module not yet moved off it: the import still works and is
listed among the module's `deprecations` in `qs ipc call modules list`):

```qml
// module.json: "widgets": [{ "type": "example", "name": "Example", "widget": "Widget.qml",
//   "popup": "example", "popupPanel": "Panel.qml" }],
//   "settings": [{ "key": "mod.example.greeting", "label": "Greeting", "type": "string", "default": "hi" }],
//   "facts": [{ "fact": "example.up", "label": "Example up", "type": "bool" }],
//   "settingsPages": [{ "id": "example", "label": "Example", "component": "Page.qml", "tab": "system" }],
//   "slots": [{ "slot": "network.popup.sections", "component": "NetworkLine.qml" }]

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

// NetworkLine.qml — a slot contribution; `context` as the slot table says
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
`Pill` (`size` `s`, `m` or `l`: the theme's three pill heights), `Checkbox`, `ToggleSwitch`
and `PrivilegedMark`, whose `need` is polkit's answer (`auth`, `no`, `yes` or none; one it
does not know shows the lock); their names are `qs.components`' too, and the same holds
for a file that imports both. Rows and texts: `SettingsRow` (a label, a hint under it, a
value, and its children as the controls on the right), `ExpandingRow` (a line that opens;
its child is held as a `Component`, so nothing of it exists while the row is closed) and
`Notice` (a small line of kind `warning`, `danger` or `success`); inside the first two are
`components/SettingsRow.qml` and `components/ExpandingRow.qml`. The base types —
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
`module.privileged.start` (one of its programs as root, below; the older `PrivilegedAction`
— pkexec, by an absolute path checked first, `notFound` otherwise; 126 dismissed, quietly;
127 refused, said once — runs through the same queue). Wake-up: `module.resumed()`;
a page or slot contribution that declares `property bool shown` does its expensive reading only
while it is on screen. Preferences are settings (`mod.<id>.*`, `module.value` /
`module.setValue`); anything else (tokens, remembered state) goes in `module.store`.

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
  - NixOS: `/run/current-system/sw/bin/timeout` and `setpriv` there, which lead into the
    Nix store.
  - Arch: `/usr/bin/timeout`, `/usr/bin/setpriv`.
- Past the limit, and on `cancel()`, the command gets TERM, and KILL `killAfterMs` later.
  From a `cancel()` on no output is handed over; `done` comes when the process is gone.
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
with its decisions in `singletons/PrivilegedRules.qml`): `start(argv, options)` runs one of
the module's own programs as root through pkexec. The shell knows which module asks from
the handle; the run says what it does in a few words (`what`, required) and how long it may
take (`timeoutMs`, required, 1 s to 1 h). `available` is true once a trusted, setuid pkexec
and a trusted `timeout` are found.
- **Refused before pkexec runs**, with `blocked` saying why: `untrusted` (argv[0] is not the
  path of one of the module's programs that is trusted, or it is a shell, `env` or another
  program that runs one named in its arguments — only argv[0] is judged, so a trusted
  interpreter given a script passes), `unprintable` (a word holds a control or format
  character: a line break, a right-to-left override), `no-purpose` (`what` empty once
  cleaned), `locked`. A program not there is `notFound` (argv[0] `""`, or not an executable
  file when the run's turn comes); options of the wrong kind give `error`.
- **The words pkexec gets**: `<pkexec> <timeout> -k 3 <limit> <argv…>`. The shell's own
  trusted `timeout` runs inside pkexec, as root, and ends the command at its limit whatever
  happens to the shell. Nothing is put around pkexec: once the command runs as root the
  shell cannot signal it, and the kernel drops `setpriv --pdeathsig` at the exec of a setuid
  program. So `cancel()` after the start sends TERM and stops waiting; the command itself
  ends at its limit.
- **One queue** for the whole shell: one password question at a time. A run holds the head
  while its question can still come; with the shell's own prompt
  (`Authentication.state` `active` or `conflict`) until the polkit request that opened after
  its start has ended, or 2 s with none; with another agent, which the shell cannot see,
  until it ends, at most 2 minutes. Then the next may start though the first still runs. A
  run cancelled while it holds the head keeps it until its pkexec has exited, or 3 s
  (`killAfterMs`) have passed, so its request is never shown with the next run's. A module
  turned off: its waiting runs leave, its started ones are cancelled, nothing of it is
  called. The session locked (`Profiles.screenLocked`): nothing starts, the waiting runs end
  `dismissed` with `blocked: "locked"`, quietly. One log line per run started, with the
  module's id and its `what`.
- NixOS: pkexec is the setuid wrapper `/run/wrappers/bin/pkexec` (the store's copy is not
  setuid); `timeout` leads into the store.
- Arch: `/usr/bin/pkexec`, `/usr/bin/timeout`.

- **Tests**: `tests/CommandRulesTest.qml` and `tests/CommandRunnerTest.qml` (the runner's
  rules, and the runner against `sh -c` scripts), `tests/PrivilegedRulesTest.qml` (the rules
  of runs as administrator, the queue's life among them) and the fixture
  `tests/fixtures/modules/privileged` (its suite runs its stand-ins through the queue in
  module test mode: a stand-in pkexec that prints its arguments, streaming, cancels, the
  head, a module turned off, the lock),
  `tests/ModuleRulesTest.qml` (the rules), `tests/ModulesTest.qml` (the host on
  the fixtures in `tests/fixtures/modules`: guard, file check, start guard, program lookup),
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
  1.10 may still put a stand-in that lies anywhere into `elevate`, until slice Z removes
  that gate: it runs unless a check finds it is the system's pkexec (the same file as
  `/run/wrappers/bin/pkexec`, `/usr/bin/pkexec` or what `command -v pkexec` finds on the
  system's directories) or a setuid or setgid file, and a check that fails counts as the
  real one. Which rule a run is under is read from the code that called it (the modules
  whose files are on its JavaScript stack: the gate only when all are older ones), and the
  gate is listed in the module's `deprecations`. `tests/run-modules.sh` puts a pkexec
  first on `PATH` that fails the run if anything starts it. `module.privileged` takes the
  module's `<testPrograms>/pkexec` and nothing else — without one it is not available —
  and its runs see the test kit's polkit agent and lock, never the shell's. A module's
  suites see test mode through `ModuleTestKit` (`qs.tests`): `setEnabled`, `status`,
  `widgetEntries`, `opened`, `notified`, `clearRecords`, and for runs as administrator
  `setPolkitAgent`, `setPolkitRequest`, `setSessionLocked`, `privilegedIdle`.

### Logging

The lock screen logs on its own terms: every step of a
lock, one line each, `[Lockscreen]`, always on, never typed text; Quickshell keeps them in
`$XDG_RUNTIME_DIR/quickshell/by-id/<instance>/log.qslog` (`qs log`, stamped to the
second), the supervisor in `$XDG_RUNTIME_DIR/h2s-shell-launcher.log`, and
`scripts/lock-log.sh` (`h2s-shell --lock-log`) prints both with the journal's PAM / fprintd /
logind lines. The rest of the shell:

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
registry names exists and compiles. Global settings (a page under `panels/settings/`)
are still wired by hand in `SettingsWindow`'s navigation model and `sourceComponent`
if-chain.

## Testing

`tests/run-all.sh` runs everything there is to run before a commit, the quick parts first:
the runners' own self-tests, `install.sh` under stand-ins, the unit suites, a module's
suites on the fixture module, the checks of the system the machine runs, and the lock
screen end to end — about four minutes, nearly all of it the lock test bed; `--quick`
leaves that out. It stops at the first part that fails (`--keep-going` goes on) and ends
with a summary naming every part as PASS, FAIL or NOT RUN with the reason: a missing tool
(named with its use), a system without a set, a part left out or not reached. A part that
did not run is never counted as passed; the exit status is 0 only when every part ran and
passed, 1 when one failed, 2 when one could not be set up. `tests/run-all-selftest.sh`
checks that verdict against made-up parts. Each part runs alone too, and takes names for
a part of it; the rest of this section describes them.

The tests are in two kinds of set. The **general** set gives the same verdict on every
system: the unit and module suites, the lock test bed, `tests/install-test.sh` and the
self-tests. A **system** set holds what is true of one system only ("The system sets",
below).

`tests/` holds a minimal harness (`TestCase.qml` with `assert`/`assertEqual`/`fail`) and
the suites `tests.qml` lists. `tests/run-unit.sh` (and `tests/run-modules.sh`, for modules'
own suites — see [Modules](#modules); both share `tests/headless.sh`) runs them in a private headless labwc
(private runtime dir, HOME and XDG dirs, D-Bus addresses that lead nowhere, no new
privileges), so the suites' windows never show on the real screen; it finds labwc and
Quickshell through `tests/lock/resolve.sh` ("Where the test tools come from", below) and fails on any `FAIL`, a
`TypeError`/`ReferenceError`, a non-zero exit of Quickshell (a crash after a partial
summary), or fewer suites reporting than `tests.qml` registers; `tests/run-unit-selftest.sh`
checks that verdict against stand-in Quickshells, and the suite count (`tests/count-suites.sh`:
a suite written with arguments counts too).

Both runners can run a part: `tests/run-unit.sh FormatTest LockRulesTest` runs the named
suites (a suite is named by its type, the file in `tests/` without `.qml`), and
`tests/run-modules.sh --suite GoodApiTest <module dir>…` the named suites of the modules
given. `--log <file>`, before the names, also saves the output. The list of suites stays
`tests.qml`: the runner reads the suites from its `property var _name: SomethingTest {…}`
lines, and which suites a suite is given (`ModuleRegistriesTest { after: _modules; … }`
waits for them) — those run with it and are counted. The names reach `TestCase` as
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
`runAsync()` and calls `finish()`; `tests.qml` lists it in `_asyncSuites` and waits for it
(60 s at most, for all of them together). A module's suites (`tests/run-modules.sh`,
`tests-modules.qml`) each get their own limit, counted from the start of the suites:
`TestCase.timeLimitMs`, 20 s by default, capped at 60 s — a suite with many concurrent
scenarios declares more. Of the shell's own, `PointerInputTest.qml` is one asynchronous suite: it puts real components (`BarWidget`,
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
system, plus the five plain tools the script uses; no new privileges; a terminal of the
run's own (`script`), since the script hands `pacman` the terminal. Before anything runs it
checks that every privileged name on that `PATH` is one of its stand-ins, and reads
`install.sh` for ways around them, stopping with status 2 at any: a program named by its
path, `command -p`, an assignment to `PATH`, `exec`, `eval`, `source` or `.`, a variable as
the command, a command substitution in a here-document. That reading refuses these forms
and proves nothing more; what holds whatever the script says is the empty environment, the
one-directory `PATH`, the private home and no new privileges. It checks
the packages asked for and how, where the shell is cloned, that nothing else runs as root,
that a second run changes nothing, another Quickshell config left alone, and what happens
when `pacman`, the clone or reading the config's origin fails. It runs on both systems.

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
  written); its version is `singletons/Version.qml`'s; `tests/lock`, `notes` and `docs`
  are not in it; its `h2s-shell` command runs the checkout `H2S_SHELL_DIR` names with the
  arguments given, and every program the shell calls is on the `PATH` it sets.
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

`nix` builds the pinned tools, for the unit suites and the lock test bed alike. The
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
| `python`, `python-pywayland` | the virtual keyboard and pointer, and the scanner their bindings are made with |
| `pkgconf`, `wayland`, `wayland-protocols` | finding the protocol files those bindings are made from |

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
