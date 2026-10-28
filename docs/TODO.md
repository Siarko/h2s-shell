# Cleanup TODO

Working checklist for the project cleanup agreed on 2026-10-28, ordered as justified in
[CLEANUP.md](CLEANUP.md#suggested-order). Numbers in brackets are the finding ids in
[CLEANUP.md](CLEANUP.md) — go there for the analysis, the file:line references and the
reasoning. This file is only the plan and the progress.

**Working agreement:** before starting an item, investigate the relevant code, state the
drawbacks of the proposed approach, and ask about anything genuinely unclear rather than
guessing. One item at a time. Commit only when asked. Tick a box only after the change is
verified on the host — the dev container has no `quickshell`.

**Status: not started.** Next item: 1.1.

---

## Stage 1 — Stop the shell from freezing  [P0]

- [ ] **1.1 Remove `Promises.await()` and make its two callers async** [#1]
      `singletons/Promises.qml:117-129`, `singletons/googlecalendar/GoogleCalendar.qml:178,305`
      The busy-wait hard-freezes the whole shell. Also stop `initialize()` from setting
      `_initialized` when the startup fetches failed, which is what makes the freeze
      reachable.
- [ ] **1.2 Fix `Fetch._printf()`** [#2] — `singletons/network/Fetch.qml:86`
      `typeof args[num] !== undefined` is always true; URLs get the string `undefined`.
- [ ] **1.3 Add request timeout and error handling to `Fetch`** [#3]
      `singletons/network/Fetch.qml:20-82` — no `xhr.timeout`, no `ontimeout`/`onerror`,
      so a hung request wedges its dedup id for the rest of the session.
- [ ] **1.4 Add test suites for the pure parsers** [#38]
      `NetworkManager._processStatus`, `WifiManager._processWifiList`, `IpManager._parse`,
      `Fetch._printf`, `LinkSpeed._update`, `GoogleCalendar._getEventDayKeys`. These are
      pure functions and were the source of several bugs found in the review.

## Stage 2 — Groundwork that makes touch a one-place change

- [ ] **2.1 `components/PopupWidget.qml`** [#13]
      Extract the `_popupMode` + click/hover + `active` block duplicated across
      `PowerWidget`, `ClockWidget`, `MusicWidget`, `SoundWidget`, `BluetoothWidget`,
      `NetworkWidget`, `HardwareWidget`. Settle the inconsistent per-widget default mode
      while doing it. Do this **before** any touch work.
- [ ] **2.2 `singletons/WidgetRegistry.qml`** [#12]
      One declarative source for type → component, display name, popup panel, settings
      pane, default popup mode. Replaces the four parallel maps in `Bar.qml`,
      `panels/BarSectionList.qml`, `panels/WidgetSettingsPane.qml`, `panels/Popup.qml`.
- [ ] **2.3 Bring the four stragglers onto the widget contract** [#15]
      `NotificationsWidget`, `SettingsWidget`, `TrayWidget` (currently a bare `Row`),
      `WorkspacesWidget`.

## Stage 3 — Scaling  [blocks the Framework 12 install]

- [ ] **3.1 A scale unit in `Theme.qml`** [#27]
      No `devicePixelRatio`/`Screen.pixelDensity` anywhere; 245 hardcoded pixel sizes and
      absolute font sizes. Needs a `dp()` or `scale` driven by the screen plus an explicit
      user override, since compositor scaling and shell scaling interact.
- [ ] **3.2 Migrate sizes to the scale unit**
      Mechanical but wide. `panels/calendar/EventForm.qml` alone has 45. Worth doing
      per-file alongside the Stage 6 splits rather than in one sweep.

## Stage 4 — Touch input

- [ ] **4.1 Popup must close on outside tap, not on pointer-exit** [#24]
      `panels/Popup.qml:232-238`, and `focusable: hoverHandler.hovered` at `:74`.
- [ ] **4.2 Pick the popup mode from the input type** [#25]
      Hover mode is unusable on touch and is the default for clock, sound and bluetooth.
      One place once 2.1 is done.
- [ ] **4.3 Touch feedback for the 64 hover-only visual states** [#26]
      Drive visual state from both `TapHandler.pressed` and `HoverHandler.hovered`,
      through shared components so it is not 64 separate edits.
- [ ] **4.4 Touch equivalents for the 7 wheel-only interactions** [#28]
      Volume on the sound widget, workspace switching, sliders.
- [ ] **4.5 Gestures** [#29]
      Swipe to dismiss a notification, edge swipe for panels. New feature surface —
      depends on 4.1–4.4.

## Stage 5 — Idle cost  [battery]

- [ ] **5.1 Read sysfs with `FileView` instead of `cat` subprocesses** [#21]
      Biggest single win: ~180 of the ~250 process spawns per minute. Affects the six
      `singletons/hardware/` sources and `singletons/network/LinkSpeed.qml`.
- [ ] **5.2 Replace `nmcli` polling with NetworkManager DBus signals** [#21]
      `NetworkManager`, `WifiManager`, `VpnManager`, `IpManager`, `EthernetManager`.
      Removes ~60 spawns/min and makes the UI react instantly instead of up to 5 s late.
- [ ] **5.3 Gate polling on whether anything is observing it** [#21, #22]
      Nothing stops when the popup closes, and all six hardware sources poll even when
      the capsule shows one.
- [ ] **5.4 Consider dropping `cava` to 30 fps** [#23] — measure first.

## Stage 6 — Architecture and size

- [ ] **6.1 Config: stop storing JSON inside JSON** [#11]
      `widgetProfiles`, `audio.appVolumes`, `bar.content.*Profiles`. ~50 `JSON.parse`
      call sites in 23 files, most inside bindings. Two steps: a cached parse helper
      first, then migrate the storage to real `JsonObject`s keyed by profile name.
- [ ] **6.2 `Popup` should expose its available content height** [#14]
      `panels/NetworkPanel.qml:496-506` hardcodes Popup's private paddings.
- [ ] **6.3 Split `panels/calendar/EventForm.qml`** (1033 lines) [P3]
      The RRULE editor, colour picker, calendar picker and all-day/time row are four
      independent components.
- [ ] **6.4 Split `panels/NetworkPanel.qml`** (928 lines) [P3]
      Splits cleanly along the section comments already in the file.
- [ ] **6.5 Split `singletons/googlecalendar/GoogleCalendar.qml`** (683 lines) [#17]
      API client / store / date+RRULE helpers.
- [ ] **6.6 Split `singletons/network/WifiManager.qml`** (359 lines) [P3]
- [ ] **6.7 Remaining large files** [P3]
      `MusicPanel` 481, `BarSectionList` 425, `WorkspacesWidgetSettings` 394,
      `EventCard` 385, `HardwareSourceList` 378, `NotificationCard` 359.

## Stage 7 — Security  [before the Google account is set up on the new machine]

- [ ] **7.1 Stop passing the client secret on the command line** [#30]
      `singletons/googlecalendar/GoogleCalendarAuth.qml:33` — world-readable via
      `/proc/<pid>/cmdline`. Use stdin or the environment.
- [ ] **7.2 Check and enforce config file permissions** [#31]
      The refresh token is a long-lived credential in plaintext in
      `~/.config/h2s_shell/config.json`. Verify the mode is `0600` on the real machine.
- [ ] **7.3 Stop logging full HTTP response bodies** [#32] — `singletons/network/Fetch.qml:68`
- [ ] **7.4 Escape the workspace name in the Hyprland dispatch** [#33]
      `singletons/Workspaces.qml:30`, and document where `hl.dsp.*` comes from so the new
      install does not silently lose logout and special workspaces.

## Stage 8 — Correctness fixes, fold into whichever stage touches the file  [P1]

- [ ] **8.1 One `SettingsWindow`, not one per monitor** [#4] — `Bar.qml:247`
- [ ] **8.2 `Notifications.timestamps` reassign instead of mutate** [#5]
- [ ] **8.3 Fix the `Connections` leak in `Audio.qml`** [#6], and document `type === 21`
- [ ] **8.4 `Notifier`: one process per interactive notification** [#7]
- [ ] **8.5 `PowerMenu`: absolute script paths** [#8] — `panels/PowerMenu.qml:72`
- [ ] **8.6 Power popup `persistent: true` on click** [#9] — `widgets/PowerWidget.qml:18`
- [ ] **8.7 `Lockscreen`: bind config declaratively** [#10]

## Stage 9 — Hygiene, opportunistic  [P7]

- [ ] **9.1 Route `console.log` through `Logger`** [#35]
      `Config.qml:132`, `Notifications.qml:33`, `Lockscreen.qml:58`
- [ ] **9.2 Fix stale comments** [#36] — `Popup.qml:23`, `Shell.qml:8`, `Music.qml:74`
- [ ] **9.3 One byte/rate formatter** [#19]
- [ ] **9.4 Move stray colours into `Theme.qml`** [#18] — 17 hex + 20 named
- [ ] **9.5 One scroll-notch implementation** [#16] — `BarWidget` vs `CustomMouseArea`
- [ ] **9.6 Move tray slide state out of the `Tray` singleton** [#20]
- [ ] **9.7 Implement or remove the screensaver exec commands** [#37]
      Config and UI exist; nothing runs them, so it looks finished to the user.
- [ ] **9.8 Leftovers** [#37] — empty `assets/`, missing trailing newline in
      `LockscreenSettings.qml`, `Logger` as `Item` rather than `QtObject`.
