# Architecture

Technical reference for the H2S Quickshell desktop shell. For what the shell does from
a user's point of view see [FEATURES.md](FEATURES.md); for the known problems and the
cleanup backlog see [CLEANUP.md](CLEANUP.md).

## Runtime model

This is not a compiled application. [Quickshell](https://quickshell.outfoxxed.me/)
interprets the QML directly, so there is no build step:

```
quickshell                 # reads shell.qml from the current directory
tests/run-unit.sh          # runs the unit suites (tests.qml), prints PASS/FAIL, exits
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
The contract in full: [plans/tailscale.md](plans/tailscale.md) §3; the stand-in provider
for tests is `tests/FakeVpnProvider.qml` (by hand: `H2S_FAKE_VPN_PROVIDER=1`, IPC target
`fakevpn`).

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

### Lock screen

Four layers, so that what decides can be tested without what does (plan and contract:
`docs/plans/lockscreen.md`, section 7):

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
  unlock-session`) — plan section 7, "What other QML in the shell can reach". It also owns
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
only reported — the lock is never set again or given up (plan, section 7).

**The Quickshell bug worked around**: Quickshell 0.3.2 never emits `lockStateChanged`
when a `WlSessionLock` unlocks (`src/wayland/session_lock.cpp`), so a binding to its
`locked` stays true after the first unlock — the old lock screen worked once per shell.
(Fixed in Quickshell's master after 0.3.2, in no release yet; the analysis, with two more
issues found on the way, is in `docs/upstream/quickshell-session-lock-unlock-notify.md`.)
The driver never binds or watches `locked`: it sets it in the `lockCompositor` /
`unlockCompositor` effects, reads it back only right after setting it true (to catch a
refused lock), and takes the compositor's word from `secureStateChanged`, tagged with the
session of the last `lockCompositor`.

**Recovery** (plan section 7, "Reload" and "Restart"; never comes up unlocked over a locked
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
  the new generation locks (plan section 7, "The reload window": what remains).
- *The compositor will not give the lock back* (Hyprland without
  `misc:allow_session_lock_restore`): Hyprland refuses a new lock while a dead client's lock
  stands, and kills the client that asks. So under Hyprland the shell first asks `hyprctl`
  (the option, `locked`) and does not ask for a lock it would be refused: it reports
  `compositor-locked`, counts as locked for the rest of the shell, and looks again with a
  growing pause (5 s to 1 min) — the setting switched on at runtime brings the prompt back.

Where state lives: the lock's state only in the driver (in `_build()`'s closure, never
exposed — it holds the typed password between submit and PAM's prompt); the half-typed text
only in the prompt's field; the I/O handles in the adapters; across a reload, two booleans
in `_carried`; across a restart, the marker. The test bed's seams, inert
unless set: `H2S_LOCK_AUTH_METHODS` (read by the methods script), `H2S_LOCK_TOOLS` (a
directory whose `gdbus` and `systemd-inhibit` stand in for the real ones — the shell's
and the methods script's),
`H2S_LOCK_SYSTEM_PAM_DIR` (where the system-wide `h2s-shell-*` PAM configs are looked for,
`/etc/pam.d` otherwise — so a test shell's password fallback is never the real PAM stack),
`H2S_LOCK_TEST_RELOAD=1` (an IPC target `locktest` whose `reload(hard)` asks for
`Quickshell.reload()`, which nothing in the shell calls), `H2S_LOCK_LEDS_DIR` (where the
Caps Lock LEDs are read, `/sys/class/leds` otherwise), `H2S_LOCK_TEST_TIMINGS` (JSON
overrides of `LockRules.timings`, so that minutes of PAM rounds run in seconds) and the
launcher's `H2S_LAUNCHER_TEST_TIMINGS` (its restart pauses, in seconds).

### Logging

The lock screen logs on its own terms (plan section 7, "Log every step"): every step of a
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

`tests/` holds a minimal harness (`TestCase.qml` with `assert`/`assertEqual`/`fail`) and
the suites `tests.qml` lists. `tests/run-unit.sh` runs them in a private headless labwc
(private runtime dir, HOME and XDG dirs, D-Bus addresses that lead nowhere, no new
privileges), so the suites' windows never show on the real screen; it finds labwc and
Quickshell as the lock test bed does (`tests/lock/resolve.sh`) and fails on any `FAIL`, a
`TypeError`/`ReferenceError`, a non-zero exit of Quickshell (a crash after a partial
summary), or fewer suites reporting than `tests.qml` registers; `tests/run-unit-selftest.sh`
checks that verdict against stand-in Quickshells. Most run their assertions in `Component.onCompleted`, on pure
functions (the `*Rules` and geometry singletons, parsers). A suite that throws counts as
failed, not as missing.

A suite that needs the event loop sets `asynchronous: true`, does its work in
`runAsync()` and calls `finish()`; `tests.qml` lists it in `_asyncSuites` and waits for it
(20 s at most). `PointerInputTest.qml` is one: it puts real components (`BarWidget`,
`PopupWidget`) in a small layer window and drives them with QtTest's `TestCase` used by
hand (`when: false`) — `mouseMove`, `mouseClick`, `touchEvent` — to check what a mouse and
a finger do. It needs a Wayland session — `run-unit.sh` gives it its own. A stylus cannot
be sent that way. `LockViewTest.qml` is another: the lock prompt and a notification card fed
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
(so edits during a run cannot reload it; each test gets its own copy of that), in an invisible, isolated compositor (Hyprland nested in a
headless labwc, private runtime dir, no D-Bus, no seat, no new privileges) and drives its
lock screen end to end: locked for real, keys typed and the pointer moved through the
compositor, PAM against test stacks (`H2S_LOCK_AUTH_METHODS`, see
`scripts/lock-auth-methods.sh`; the copy's own `pam/` configs only deny, and the "system"
PAM directory the password fallback is chosen from is the test's own,
`H2S_LOCK_SYSTEM_PAM_DIR`), logind's signals, the sleep inhibitor and fprintd through
stand-ins (`H2S_LOCK_TOOLS`; the real methods script runs against the fprintd one in
`methods-script.sh` and `methods-fprintd.sh`). `tests/lock/run.sh`
runs it, several tests at a time, each in a stack of its own (`-j N`; `-j 1` one after
another); nothing appears on screen and the real session cannot be reached. See its README.

`tests/manual/` holds checks no suite runs because they touch the real system — the one
there runs a single PAM conversation with the real password against the shipped
`pam/password` (its README).

Everything else is verified by hand: run `quickshell` from the repo root and check that
the bar renders, the clock ticks, cells respond, and popups toggle. Apart from the lock
screen, there is no automated coverage of any singleton that touches the system.
