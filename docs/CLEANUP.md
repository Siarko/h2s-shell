# Cleanup backlog

Findings from a full read of the project (103 QML files, ~15 600 lines) in October 2026.
Ordered by severity. Each entry says what is wrong, why it matters, and what the fix
looks like.

Nothing here was reproduced on real hardware — `quickshell` is not installed in the dev
container. Items marked **confirmed** were verified by reading the code plus, where the
logic is pure JavaScript, by running it in isolation. Items marked **likely** are
reasoned from the code and still need a check on the machine.

Context for the ordering: the shell is about to be installed on a Framework 12 with a
touchscreen, so the touch and HiDPI section is not "nice to have" — it is the next
feature's prerequisite.

---

## P0 — Can take the whole shell down

### 1. `Promises.await()` busy-waits and will hard-freeze the shell — **confirmed, FIXED**

`singletons/Promises.qml:117-129` (line numbers as they were before the fix)

```js
promise.then(...).catch(...).finally(() => waiting = false);
while (waiting) {
}
```

QML is single-threaded. If the promise is not already settled when `await` is called,
nothing can ever settle it, because the event loop that would deliver the XHR callback
is blocked by this loop. The shell — bar, popups, lock screen, everything — freezes
permanently and has to be killed.

It is reachable. `singletons/googlecalendar/GoogleCalendar.qml:178` and `:305`:

```js
let enabledCalendars = Promises.await(getEnabledCalendarIds()).resolved ?? [];
```

`getEnabledCalendarIds()` resolves synchronously *only* when `calendars` is already
populated; otherwise it fires `fetchAllCalendars()` and resolves from its callback.

The path in: `initialize()` wraps the startup fetches in `Promises.allSettled`, which
never rejects, so `_initialized` is set to `true` even when `fetchAllCalendars()` failed
and `calendars` is still empty. The next `fetchDayEvents()` / `fetchMonthEvents()` then
takes the asynchronous branch and spins forever. In other words: **boot the laptop with
no network, or with an expired refresh token, then open the calendar.** That is a
routine situation on a laptop.

Fix: delete `await` and make the two call sites asynchronous —
`getEnabledCalendarIds().then(ids => …)`. The surrounding `exec()` already returns a
promise, so this is a local change. Also stop setting `_initialized` when the
initialising fetches failed.

Note: a previous review filed this as "Promises.await fragility, low risk". That was
wrong — it is a hard hang with a plausible trigger, and finding #39 makes the trigger
likelier still: a merely invalidated token reaches the same state.

**Fixed.** `await` is gone, `fetchMonthEvents()` chains instead, `getEnabledCalendarIds()`
gained its missing `.catch`, and `initialize()` no longer claims readiness it does not
have. The dead `fetchDayEvents()` path — the other `await` call site — was deleted along
with its only consumer `fetchCalendarEvents()`, 80 lines in total. Awaiting host
verification.

### 2. `Fetch._printf()` substitutes the string `undefined` into URLs — **confirmed**

`singletons/network/Fetch.qml:86`

```js
return typeof args[num] !== undefined ? args[num] : match;
```

`typeof` yields a string, so the comparison is against the *value* `undefined` and is
always true. The guard never fires. Verified in isolation:

```
_printf("/cal/{0}/ev/{1}", ["abc"])  →  "/cal/abc/ev/undefined"
```

Any endpoint template called with too few params silently requests a URL containing
`undefined` instead of failing or leaving the placeholder. Affects
`_ENDPOINT_EVENTS`/`_ENDPOINT_EVENT`, which take 1–2 params.

Fix: `typeof args[num] !== "undefined"`, or simply `args[num] !== undefined`.

### 3. HTTP requests have no timeout, and a hung request wedges its id forever — **confirmed**

`singletons/network/Fetch.qml:20-82`

`request()` de-duplicates by `data.id`, storing the in-flight promise in
`_pendingRequests[id]` and clearing it in `finally`. There is no `xhr.timeout` and no
`ontimeout`/`onerror` handler, only `onreadystatechange`. A request that never completes
(captive portal, dropped connection) leaves the promise pending, so the `finally` never
runs, so that id stays in `_pendingRequests` for the rest of the session — and every
later request with the same id returns the same dead promise. The affected day or month
of the calendar then never loads again until the shell is restarted.

Fix: set `xhr.timeout`, handle `ontimeout` and `onerror` by rejecting, and clear
`_pendingRequests[id]` in both.

---

## P1 — Bugs

### 4. `SettingsWindow` is created once per monitor — **likely**

`Bar.qml:247`

`SettingsWindow` is declared inside `Bar.qml`, and `shell.qml` instantiates one `Bar`
per screen. On a two-monitor setup there are two independent settings windows with
independent `selectedCategory`, and the `Connections { target: Shell }` at `Bar.qml:253`
means `Shell.openSettings()` opens *both*.

Fix: hoist it to `shell.qml` as a single instance and route to it through the `Shell`
singleton. This matters for the laptop-plus-external-monitor setup.

### 5. `Notifications.timestamps` is mutated in place, so its readers never update — **confirmed (latent)**

`singletons/Notifications.qml:39` writes `timestamps[notification.id] = …` and `:69`
deletes from it, both without reassigning the property. QML emits no change signal for
an in-place mutation of a `var` object, so the binding at
`panels/NotificationPanel.qml:116` is never re-evaluated.

Today it mostly works by accident: the write happens in the same handler as
`notification.tracked = true`, so a delegate created later reads the already-populated
map. But `tracked = true` is set at `:31`, *eight lines before* the timestamp is stored,
so any delegate created synchronously on model insertion reads an empty map and keeps an
empty timestamp for good. Expect "the timestamp is sometimes missing".

Note the same file handles `extractedCodes` correctly — it copies, mutates, reassigns.
The inconsistency is the tell.

Fix: treat `timestamps` the same way as `extractedCodes`, and set the timestamp before
`tracked = true`.

### 6. `singletons/Audio.qml` leaks a `Connections` object per stream — **confirmed**

`singletons/Audio.qml:54,79`

`applySavedVolume()` calls `monitorNodeVolume()`, which `createObject`s a `Connections`
parented to the singleton — never destroyed. Worse, `:79` attaches
`object.readyChanged.connect(…)` without ever disconnecting, so every subsequent
`readyChanged` on that node calls `applySavedVolume()` again and creates *another*
monitor. Over a long session, every application that plays audio adds permanent objects,
and a node that toggles ready repeatedly multiplies them.

Fix: keep the created monitors in a map keyed by node name, destroy them in
`onObjectRemovedPre`, and disconnect the ready handler after the first call (or use a
one-shot `Connections`).

Related, same file: `:72` keys off `object.type === 21` with the comment *"21 is releated
to the app source for some reason"*. An unexplained magic number in the Pipewire node
type is a time bomb across Quickshell upgrades — find the named constant or at least
document what 21 means.

Also `appNodesByIndex` is keyed by Pipewire's *index*, which is recycled. A remove/insert
pair in the wrong order can drop the wrong node.

### 7. `Notifier` has one callback slot and clobbers it — **confirmed**

`singletons/Notifier.qml:89`

An interactive notification (actions, inline reply, or a dismiss callback) stores its
callbacks in the single `_pendingCallbacks` and runs `_waitProcess`. Sending a second
interactive notification while the first is still open sets `_waitProcess.running = false`
— killing the first `notify-send --wait` — and overwrites the callbacks. The first
notification's actions are lost silently.

Fix: one `Process` per interactive notification (an `Instantiator` over a pending list,
or `createObject`), keyed so each reply reaches its own callbacks.

### 8. Power menu uses paths relative to the working directory — **confirmed**

`panels/PowerMenu.qml:72` runs `["bash", modelData.script]` where `script` is
`"scripts/shutdown.sh"`. That only resolves when `quickshell` was launched from the repo
root. Started from a systemd user unit, a launcher, or any other directory, all three
power actions silently do nothing.

The rest of the project already does this correctly —
`singletons/googlecalendar/GoogleCalendarAuth.qml:33` uses `Quickshell.shellDir + "/scripts/…"` and
`panels/MusicPanel.qml:19` uses `Qt.resolvedUrl()`. PowerMenu is the odd one out.

Fix: `Quickshell.shellDir + "/" + modelData.script`.

### 9. The power popup closes on pointer-out even when opened by click — **confirmed**

`widgets/PowerWidget.qml:18` passes `persistent: false` on the *click* path, where every
other widget passes `true`. Click the power widget, move the mouse, and the menu
vanishes before it can be used.

Fix: `popup.open(this, true, "power")` on click.

### 10. Lockscreen mirrors config imperatively instead of binding — **likely**

`singletons/Lockscreen.qml:24-52`

`_ssMonitor.enabled` and `_lockMonitor.enabled` are hardcoded `false` and then assigned
inside `Config.lockscreen` change handlers wrapped in `Qt.callLater`. Nothing applies the
*initial* state, so correct startup behaviour depends on the stored config differing from
the declared defaults and thus emitting a change. The timeout handlers additionally
toggle `enabled` off and on to force the Wayland idle-notification object to be recreated.

This works today but is held together by ordering assumptions. Fix: bind `enabled`
declaratively and find a supported way to react to a timeout change, or at minimum apply
the initial state in `Component.onCompleted` and document why `callLater` is needed.

---

## P2 — Architecture

### 11. Config stores JSON inside JSON, and 23 files parse it by hand

`widgetProfiles`, `audio.appVolumes` and the bar's `leftProfiles`/`centerProfiles`/
`rightProfiles` are `string` properties holding serialised JSON. Consequences:

- **~50 `JSON.parse` call sites across 23 files.** Worst offenders:
  `panels/widget_settings/WorkspacesWidgetSettings.qml` (9),
  `panels/widget_settings/HardwareWidgetSettings.qml` (4),
  `widgets/WorkspacesWidget.qml` (4).
- Most sit **inside property bindings**, so the whole blob is re-parsed on every
  dependency change — for every widget, on every config write.
- No schema, no validation, no autocomplete. A typo in a profile key fails silently.
- `leftProfiles` is an index-aligned parallel array to `left`; reordering the bar has to
  keep two structures in sync by hand (`Bar._zipModel`).

This is the most pervasive debt in the project. Fix in two steps: (a) a single helper
that parses once and exposes a cached object, invalidated on `Config.saved`; (b) migrate
the storage to real `JsonObject` structures, with profiles keyed by name instead of
positional arrays.

### 12. The same widget type string keys four parallel registries

Adding one bar widget means editing: `Bar.qml` (a `Component` plus `_widgetMap`),
`panels/BarSectionList.qml` (`displayName()` plus the picker list),
`panels/WidgetSettingsPane.qml` (`_settingsComponentMap` plus the `Component`), and —
if it has a popup — `panels/Popup.qml` (`_componentMap`), and — if it has global
settings — `panels/SettingsWindow.qml` (navigation model plus an if-chain over indices).

Six places, no single source of truth, and nothing detects a type that is registered in
three of them and forgotten in the fourth.

Fix: one declarative registry (`singletons/WidgetRegistry.qml`) listing per type its
component, display name, popup panel, settings pane and default popup mode; have all the
call sites read from it.

### 13. Popup wiring is copy-pasted into seven widgets

Each of `PowerWidget`, `ClockWidget`, `MusicWidget`, `SoundWidget`, `BluetoothWidget`,
`NetworkWidget`, `HardwareWidget` carries the identical 15 lines:

```qml
readonly property string _popupMode: {
    var data = JSON.parse(Config.widgetProfiles || "{}")
    return data["<type>"]?.["_popupMode"] ?? "click"   // or "hover", inconsistently
}
active: popup?.active && popup?.contentType === "<type>"
onClicked: { if (_popupMode !== "click") return; … }
onHover: state => { if (_popupMode !== "hover") return; … }
```

Seven near-identical copies, each repeating its own type string four times, each with its
own hardcoded default mode (`click` for power/network/hardware, `hover` for
clock/sound/bluetooth) for no stated reason.

Fix: a `components/PopupWidget.qml` extending `BarWidget` that takes `widgetType` and
`popup` and does all of it once. This also makes the touch work in #30/#31 a one-file
change instead of a seven-file change — worth doing *before* the touch support, not
after.

### 14. `NetworkPanel` reverse-engineers the popup's private geometry

`panels/NetworkPanel.qml:496-506`

```js
var panelTopY = Config.bar.layout.topOffset + Config.bar.layout.barHeight
var maxH = Screen.height - panelTopY - 10 - _wifiSection.y - networkList.y
         - _hiddenRow.height - 8 - 10 - 16
```

Those `10`, `10` and `16` are `Popup.qml`'s `paddingTop`, `paddingBottom` and internal
spacing, copied into a panel as literals. Change a padding value in `Popup.qml` and the
wifi list silently mis-sizes. It is also the only use of `Screen` in the codebase, in a
file that otherwise knows nothing about the screen.

Fix: have `Popup` expose the available content height as a property and let panels bind
to it.

### 15. The widget contract is not followed — **FIXED**

`widgetType` is missing from `NotificationsWidget`, `SettingsWidget`, `TrayWidget` and
`WorkspacesWidget`, and `TrayWidget` is a bare `Row` rather than a `BarWidget` — so it
has no cell background, no hover state and none of the shared signals. `SettingsWidget`
has neither `widgetType` nor `popup`.

Fix: make the contract real (see #12/#13) and bring the four stragglers onto it.

### 16. Scroll-notch accumulation implemented twice

`components/BarWidget.qml:67-80` and `components/CustomMouseArea.qml:17-28` contain the
same algorithm, down to the `event.angleDelta.y * (1 / 8) / 14` constant, differing only
in signal names. Two copies to keep in sync, and the magic constant is unexplained in
both.

Fix: one implementation, named constants, used by both.

### 17. `GoogleCalendar.qml` is a 683-line module with seven hand-rolled caches

`events`, `eventsByCalendar`, `eventsLoading`, `calendars`, `_colorMapEvents`,
`_colorMapCalendars`, `_busyRequests`, `_fetchedMonths` — eight `var` maps with manual
invalidation, plus endpoint templates, request builders, date-key helpers, timezone
formatting, event body construction, merging and sorting, all in one file.

Fix: split into an API client (endpoints and requests), a store (caches and
invalidation), and date/RRULE helpers. The OAuth half is already separate, which shows
the seam works.

### 18. Colours and sizes escape the theme

17 literal hex colours and 20 named colours (`"white"`, `"black"`, `"green"`,
`"#1e3a5f"`, …) outside `Theme.qml`. Heaviest:
`panels/NetworkPanel.qml` (4), `panels/calendar/EventForm.qml` (3, including the submit
button's `#1e3a5f`/`#2d4a6d`), `screensaver/LockPrompt.qml` (2).

The palette cannot be changed without hunting through panels. Fix: move them into
`Theme.qml` under semantic names.

### 19. Three byte/rate formatters

`Hardware.formatBytes()`, `NetworkManager.formatSpeed()` and a third `formatBytes` inside
`singletons/hardware/GpuSource.qml`. Same job, three implementations, inconsistent
rounding.

Fix: one formatting helper.

### 20. `singletons/Tray.qml` stores view animation state globally

`menuHandle`, `lastItemIndex`, `slideDirection` and `calculateDirection()` are a
17-line singleton whose entire purpose is remembering which way the tray menu should
slide. That is view state in global state, and it breaks the moment two tray menus exist
(two monitors).

Fix: move it into the tray menu component.

---

## P3 — Files that are too big

Current worst offenders:

| File | Lines | Problem |
|---|---|---|
| `panels/calendar/EventForm.qml` | 1033 | one `Column` of giant anonymous blocks; lines 611–979 are a single 368-line `Item` |
| `panels/NetworkPanel.qml` | 928 | VPN + ethernet + wifi header + info + speeds + disconnect + network list + hidden-network entry, all inline |
| `singletons/googlecalendar/GoogleCalendar.qml` | 683 | see #17 |
| `panels/MusicPanel.qml` | 481 | player UI + visualiser + cava parsing |
| `panels/BarSectionList.qml` | 425 | list editing + drag/drop + the type picker |
| `panels/widget_settings/WorkspacesWidgetSettings.qml` | 394 | 9 `JSON.parse` call sites |
| `panels/calendar/EventCard.qml` | 385 | |
| `panels/HardwareSourceList.qml` | 378 | |
| `singletons/network/WifiManager.qml` | 359 | radio polling + scanning + saved profiles + connect/disconnect + speed |
| `components/NotificationCard.qml` | 359 | |

`EventForm` is the clearest win: the recurrence-rule editor, the colour picker, the
calendar picker and the all-day/time row are four independent components sharing nothing
but the form's properties. `NetworkPanel` splits cleanly along the section comments that
are already in the file.

---

## P4 — Cost while idle (matters on a laptop)

### 21. The shell spawns roughly 250 subprocesses per minute at rest

Steady-state polling, all unconditional (`running: true`):

| Source | Interval | Processes/min |
|---|---|---|
| `CpuSource`, `RamSource`, `GpuSource`, `GpuTempSource` | 2 s | 30 each = 120 |
| `LinkSpeed` ×2 (ethernet + wifi connected) | 2 s | 60 |
| `WifiManager` radio + saved profiles | 5 s | 24 |
| `NetworkManager` device status | 5 s | 12 |
| `VpnManager` connection list | 5 s | 12 |
| `CpuTempSource` | 5 s | 12 |
| `IpManager` ×2 devices | 10 s | 12 |
| `DiskSource` | 10 s | 6 |

That is a `fork`+`exec` every ~0.25 s, forever, much of it `nmcli` — which is itself a
DBus round trip per call. On a desktop it is invisible; on a Framework 12 on battery it
is not.

Three independent fixes, in order of payoff:

- **Replace `nmcli` polling with NetworkManager's DBus signals.** The state is
  event-driven at the source; the shell is polling it five times a second between all
  the managers. Removes ~60 process spawns/min and makes the UI react instantly instead
  of up to 5 s late.
- **Read sysfs with `FileView` instead of `cat` subprocesses.** CPU, RAM, GPU,
  temperatures and `LinkSpeed` are all plain file reads. Removes ~180 spawns/min.
- **Gate polling on visibility.** Nothing currently stops when the popup is closed.

### 22. All six hardware sources poll even when one sensor is displayed

`HardwareWidget` shows `["cpu"]` by default, but touching `singletons/Hardware.qml`
instantiates all six sources and every one starts its timer. Fix: start a source's timer
only while something observes it (a reference count, or binding `running` to "is in the
capsule, or the hardware panel is open").

### 23. `cava` runs at 60 fps and is parsed in JavaScript — **FIXED** (configurable per profile)

`panels/MusicPanel.qml:147-163` with `framerate = 60` and 48 bars in
`scripts/cava.ini` — 60 line-splits and 48 `parseInt`s per second, in the QML JS engine,
while the music panel is open. It is correctly scoped to the panel being open, so this is
a "measure it" rather than a "fix it", but 30 fps would likely be indistinguishable.

---

## P5 — Touch and HiDPI readiness (blocks the Framework 12 plan)

The shell is built entirely around a mouse pointer. Counted across the project:

| | Count |
|---|---|
| `MouseArea` | 108 |
| `containsMouse` (hover-dependent visuals) | 64, in 23 files |
| `hoverEnabled` | 58 |
| `onWheel` | 7 |
| `TapHandler` / `PinchHandler` / `DragHandler` | 0 |

### 24. The popup closes on pointer-exit, which a touchscreen never reports

`panels/Popup.qml:232-238` closes a non-persistent popup from
`HoverHandler.onHoveredChanged`. With touch input there is no hover, so a hover-mode
popup either never opens or never closes, depending on how the compositor synthesises
pointer events. `focusable: hoverHandler.hovered` at `:74` means keyboard focus is
hover-driven too.

Fix: close on a tap outside the card (the full-screen window is already there — extend
the mask or add an outside-press handler) and make `focusable` not depend on hover.

### 25. "Hover" popup mode is meaningless on touch, and it is the default for three widgets

Clock, sound and bluetooth default to `_popupMode: "hover"`. On a touch-only session
those three widgets become unusable. Fix: detect the input type, or force click mode when
the primary input is touch — one place once #13 is done.

### 26. 64 hover-only visual states give no touch feedback

Buttons, list rows, cards and sliders change appearance only via `containsMouse`. Under
touch they either never highlight, or highlight and stay stuck after the finger lifts.
Fix: drive visual state from a handler that covers both (`TapHandler.pressed` plus
`HoverHandler.hovered`), ideally through shared components so it is not 64 edits.

### 27. No scaling: 245 hardcoded pixel dimensions and nothing reads the DPI — **NOT A PROBLEM**

There is no `devicePixelRatio`, `Screen.pixelDensity` or scale factor anywhere in the
project. `Theme.qml` holds absolute font sizes (9–52 px), the bar is 36 px tall, bar cells
are at least 40 px wide, tray icons are 18 px, toggle switches are 44×24 and
`BarWidget.Layout.preferredHeight` is 20.

On the Framework 12's high-density panel everything will be physically tiny, and the
touch targets will be well below the ~9 mm that a finger needs. `EventForm.qml` alone has
45 hardcoded sizes.

Fix: introduce a scale unit in `Theme.qml` (a `dp()` function or a `scale` multiplier
driven by the screen and an explicit user setting), and express sizes in it. This is a
wide but mechanical change, and it is the one that has to happen before the laptop is
usable.

**Verified otherwise on the host (2026-10-28):** QML sizes are logical pixels, and
Hyprland's per-monitor scale is applied by Qt — the whole shell scaled correctly with a
monitor's scale changed. The analysis above assumed a compositor scale of 1. What is
left is touch-target size, a design decision tracked as TODO 4.6.

### 28. Wheel-only interactions have no touch equivalent

Seven `onWheel` handlers — volume on the sound widget, workspace switching, sliders. A
finger cannot scroll a wheel. Fix: add drag/swipe gestures for the same actions.

### 29. No gestures at all

No swipe to dismiss a notification, no edge swipe to open a panel, no pinch, nothing.
This is the new feature surface rather than a defect, but it depends on #24–#27 being
sorted first.

Only two `ScrollBar`s exist in the whole project against 16 `ListView`s and 7
`Flickable`s — worth checking which scrollable areas are currently wheel-only.

---

## P6 — Security

### 30. The Google client secret is passed as a command-line argument

`singletons/googlecalendar/GoogleCalendarAuth.qml:33`

```qml
command: ["python3", Quickshell.shellDir + "/scripts/google_auth.py",
          Config.gcal.clientId, Config.gcal.clientSecret]
```

Command lines are world-readable on Linux — any local process can read the secret from
`/proc/<pid>/cmdline` for as long as the helper runs. Fix: pass it on stdin or through
the environment.

### 31. OAuth tokens sit in plaintext config with unchecked permissions

`Config.gcal.clientSecret`, `accessToken` and `refreshToken` are stored in
`~/.config/h2s_shell/config.json`. The refresh token is a long-lived credential for the
account's calendar. Nothing in the code sets the file mode, so it inherits whatever
`FileView` writes with — verify it is `0600` on the real machine, and consider keeping
the tokens in a separate file, or in the keyring.

### 32. HTTP failures log the response body

`singletons/network/Fetch.qml:68` builds the rejection message with `xhr.responseText`
included, and `GoogleCalendar` logs rejections. A failing token request can therefore put
token-endpoint output into the log. Fix: log the status and a truncated body, never the
whole thing, for auth endpoints.

**Partly fixed** with #39: the message now carries at most 200 characters of the body, and
the full text moved onto the error object as `body` for callers that need it. The remaining
work is the call sites that log a whole rejection object.

### 33. A workspace name is interpolated into a Hyprland dispatch string

`singletons/Workspaces.qml:30` builds
`hl.dsp.workspace.toggle_special("<name>")` by string concatenation with no escaping. A
workspace name containing a quote produces a malformed — or differently interpreted —
dispatch. Low impact since the names are the user's own, but it is the wrong shape.

While there: both this and `scripts/logout.sh` depend on the `hl.dsp.*` dispatcher
naming, which is unusual and undocumented. Worth a comment saying which Hyprland version
or plugin provides it, so the new install does not silently lose logout and special
workspaces.

---

## P7 — Hygiene

### 34. `CLAUDE.md` describes a shell that no longer exists

It documents four panels and three singletons. The project now has 12 widget types,
9 popup panels, 7 settings pages, ~30 singletons, a HUD layer, a screensaver and lock
screen, Google Calendar integration and a dictation client. It also claims testing is
manual, though `tests.qml` exists. Superseded by this `docs/` directory — `CLAUDE.md`
should shrink to conventions plus pointers.

### 35. `console.log` bypasses `Logger`

`singletons/Config.qml:132` ("[CONFIG] Saved" on every write),
`singletons/Notifications.qml:33` (`console.log("Icon", …)` — leftover debugging),
`singletons/Lockscreen.qml:58`. All unconditional, none respecting a debug switch.

### 36. Stale comments

`panels/Popup.qml:23` says `contentType` is `"calendar" or "power"` — there are nine.
`singletons/Shell.qml:8` lists category indices 0–4 — there are seven, and they are
magic numbers matched against a hardcoded if-chain in `panels/SettingsWindow.qml:110-116`.
`singletons/Music.qml:74` says "Interpolated position" for what is a 1 s poll.

### 37. Leftovers

- `assets/` is empty.
- `panels/settings/LockscreenSettings.qml` has no trailing newline.
- `components/Logger.qml` is an `Item`, so every logger instantiates a `QQuickItem` for
  three functions; `QtObject` would do.
- `screensaverExecCmd` / `screensaverExecSleep` / `screensaverExecWakeup` exist in config
  and in the settings UI, but nothing executes them — the feature is a stub that looks
  finished to the user.

### 38. Test coverage is one suite

`tests/PromisesTest.qml` covers `Promises`; nothing else is tested. The parsing functions
are the obvious candidates — they are pure and were the source of several bugs found
here: `NetworkManager._processStatus`, `WifiManager._processWifiList`,
`IpManager._parse`, `GoogleCalendar._getEventDayKeys` / `_prepareEventData`,
`Fetch._printf`, `LinkSpeed._update`.

---

## Added while implementing

### 39. The 401 token refresh was dead code — **confirmed, FIXED**

`singletons/googlecalendar/GoogleCalendarAuth.qml:109` decides whether to refresh an
expired token with `if (reason.status === 401)`, but `singletons/network/Fetch.qml` rejected
with a plain `new Error("Unexpected HTTP response status " + xhr.status + …)` — the status
only ever existed inside the message string, never as a field. The condition could not be
true, so a real 401 was passed straight through as a rejection and the token was never
refreshed. Only the `left < 300` pre-check in `ensureAuthorized` ever refreshed anything.

This is why #1's trigger is more likely than first assessed: an invalidated or revoked
refresh token produces a failed calendar fetch that is never retried, leaving `calendars`
empty — exactly the state that used to freeze the shell.

Fixed by attaching `status` (and the full `body`) to the rejection, so the existing check
in `GoogleCalendarAuth` works unchanged.

### 40. `Promises.allSettled` does not preserve argument order, and its test hides that — **confirmed**

`singletons/Promises.qml:136` pushes each result as it settles:

```js
let tryResolve = function (r) { results.push(r); promiseCount--; … }
```

So `results` is in completion order, not argument order. `tests/PromisesTest.qml:100-101`
and `:113-114` assert entries positionally, but only with promises that settle
synchronously, where the two orders coincide — so the suite passes on a guarantee the
implementation does not provide.

Nothing in production depends on it today: all three production `allSettled` call sites
do `.then(() => …)` and ignore the results. Fix: either preserve order by index, or
document that the result order is arbitrary and change the test to stop implying otherwise.

### 41. The hand-rolled `Promises` library may be replaceable — **open question**

Native `Promise` would make `singletons/Promises.qml` (182 lines) and
`tests/PromisesTest.qml` (231 lines) redundant. The surface is small: three production
files (`Fetch.qml`, `GoogleCalendar.qml`, `GoogleCalendarAuth.qml`), 4 API functions, and
no production reader of the non-standard `{status: boolean}` result shape.

Two unknowns block it, neither checkable without a Qt runtime: whether this build's engine
has native `Promise`, and — a separate question — whether it supports `async`/`await` (V4
has had `Promise` for a long time but historically not `async function`). There is also a
semantic difference: the hand-rolled `then()` invokes its handler synchronously when the
promise is already settled (`singletons/Promises.qml:69`), where native always defers to a microtask;
8 executors in the codebase resolve synchronously. The claim to verify is that with `await`
gone, nothing depends on inline settling any more.

Filed as TODO 1.5, which starts with a probe script rather than a migration.

### 42. Rapid month switching can overlap calendar fetches — **likely**

`GoogleCalendar.fetchMonthEvents()` only sets `_fetchedMonths[monthKey]` once the whole
fetch completes, so clicking through months faster than the requests return starts several
overlapping fetches for different months. `Qt.callLater` in `panels/Calendar.qml:43` only
deduplicates within one event-loop tick. Pre-existing; the #1 fix widens the window by one
tick, since the enabled-calendar list is now resolved asynchronously. Fix: mark the month
as in-flight when the fetch starts, not when it finishes.

### 43. Live arrays still bound straight to `Repeater.model` — **confirmed**

Found 2026-10-28 while starting the widget registry. The rule in
[ARCHITECTURE.md](ARCHITECTURE.md#the-repeater-crash) is broken in these places, each
binding a recomputed array directly:

- `Bar.qml:170`, `:194`, `:219` — the three bar sections (`_leftModel` etc.). Fixed with
  the widget registry.
- `panels/BarSectionList.qml:380` — the add-widget picker. Fixed with the widget registry.
- `panels/HardwarePanel.qml:39` — `_popupSources`, inside a popup panel: the riskiest one. Fixed.
- `components/NotificationCard.qml:164` — `_regularActions`; the card is used in the
  notification panel (a popup) and in the HUD.
- `panels/HardwareSourceList.qml:335` — an inline `.filter()`.
- `panels/WidgetSettingsPane.qml:193` — `_filteredProfiles`.
- `panels/settings/SettingOptions.qml:32` — `options`; usually set once, but a `var`. Fixed.

Fix: `ScriptModel { values: … }` in each. Literal constant arrays elsewhere are fine.

---

## Suggested order

Given the Framework 12 install:

1. **P0 (#1–#3)** — a shell that can freeze is not worth optimising. Small, local fixes.
2. **#13 and #12** — the popup/widget base and the registry. Do these *before* touch
   work, so touch is one change rather than seven.
3. **#27** — the scale unit. Wide but mechanical, and nothing about the laptop is usable
   without it.
4. **#24–#26, #28** — touch input proper.
5. **#21** — DBus instead of `nmcli`, `FileView` instead of `cat`. Battery life.
6. **#11** — the config/JSON rework. Big, and everything else gets easier after it.
7. **P3 file splits**, opportunistically, when touching a file anyway.
8. **P6**, before the account is set up again on the new machine.
