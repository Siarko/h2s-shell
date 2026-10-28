# Cleanup TODO

Working checklist for the project cleanup agreed on 2026-10-28, ordered as justified in
[CLEANUP.md](CLEANUP.md#suggested-order). Numbers in brackets are the finding ids in
[CLEANUP.md](CLEANUP.md) — go there for the analysis, the file:line references and the
reasoning. This file is only the plan and the progress.

**Working agreement:** before starting an item, investigate the relevant code, state the
drawbacks of the proposed approach, and ask about anything genuinely unclear rather than
guessing. One item at a time. Commit only when asked. Tick a box only after the change is
verified on the host — the dev container has no `quickshell`.

**Status: Stages 1, 2 and 3 done, 5.1 and 5.2 done** (2026-10-28). Stage 4 (touch) is
deferred until the Framework 12 is at hand, since it cannot be verified here. Next item:
5.3, now shell profiles — [plans/adaptive-polling.md](plans/adaptive-polling.md), design
agreed; four small points are still open at its end.

---

## Host verification — 1.1 (complete, 2026-10-28)

Written in the dev container, where there is no `quickshell`. Nothing below has been run.
The logic was checked by loading the real `singletons/Promises.qml` into node and driving
the new chain through four scenarios plus a counter-test, but that proves the promise
plumbing only — not the Google API path, and not the shell.

Turn on `Config.gcal.debug` in `~/.config/h2s_shell/config.json` first; most of these are
read from the log.

1. **Test suites** — ✅ passed on the host 2026-10-28, 31/31.
   `quickshell -p tests.qml`, every assertion `PASS`. The suite never
   touched `await`, so it should pass unchanged; it is the regression check for the
   promise chaining the fix relies on (`tests/PromisesTest.qml:168` delayed path, `:178`
   deep chain).
2. **The freeze, reproducible before the fix.** Put junk in `Config.gcal.accessToken` and
   `refreshToken`, start the shell, open the calendar, click through months. Before: the
   whole shell stops responding. After: bar and popups keep working, the spinner clears,
   and the log shows the rejection.
   ✅ Passed on the host 2026-10-28: no freeze, one failed refresh, logout, spinner cleared.
   It took four more fixes, all found on this path:
   - `Promises._flatten` overwrote a rejection with the resolved state of a settled chain
     returned by the executor, so a failed refresh carried on as "Token refreshed".
     Guarded, with a regression test (`tests/PromisesTest.qml`, test 24).
   - Every request waiting on the refresh notified and logged out on its own, four
     interactive notifications at once. `GoogleCalendarAuth` now shares one refresh.
   - `Notifier` passed `--action=id:label`; notify-send 0.8 wants `id=label`, so the reply
     was the button index and no action ever matched. Reconnect now works.
   - Clicking connect again while a login waited on a closed browser tab did nothing;
     it now restarts the login. And a successful login did not fetch the open month —
     `panels/Calendar.qml` now does.
3. **401 self-healing** — the path that was dead until now. Keep a *valid* `refreshToken`,
   corrupt only `accessToken`, and set `tokenExpiry` far in the future so the
   `left < 300` pre-check is bypassed. Expect a 401, then a token refresh, then a retry:
   two requests in the log and a populated calendar.
   ✅ Passed on the host 2026-10-28, after a second fix. The first run showed no refresh:
   `fetchColorMappings()` and `fetchAllCalendars()` caught their own errors *inside* the
   `ensureAuthorized` callback, so the 401 never reached it and init failed with no
   calendars. Both now return the bare request and parse after `ensureAuthorized`. Second
   run: both 401s triggered a refresh, Fetch's dedup made it one token request, and init
   and the month fetch succeeded with the new token.
   **Rule:** an `ensureAuthorized` callback must return the bare request, never a chain
   with its own `.catch`.
4. **Start with no network.** Disable networking, start the shell, open the calendar —
   empty, and the spinner must clear. Enable networking, change month: events arrive
   without restarting the shell. This is what the `initialize()` change buys.
   ✅ Passed on the host 2026-10-28. Offline, every attempt failed with status 0, the
   shell stayed responsive and init retried on each month change; once back online the
   events loaded without a restart. Two side findings, filed as 8.8: the UI gives no sign
   that anything failed, and each retry fetches `calendarList` twice (once from
   `initialize()`, once from `getEnabledCalendarIds()`).
5. **Happy path** — click several months forward and back; events, colours and the
   per-day dots should look exactly as before, and creating/editing/deleting an event
   should still refresh its month.
   Refresh after create confirmed working on the host 2026-10-28. Testing it turned up an
   unrelated, pre-existing bug: all-day events were saved with `end.date == start.date`,
   which Google accepts but `_getEventDayKeys` dropped, so they never appeared in the
   shell. Fixed (exclusive end date on save, zero-length tolerated on read) and verified.
   ✅ Create, edit and delete all confirmed on the host 2026-10-28.

Tick 1.1's box once these pass. If something fails, the analysis behind the change is in
[CLEANUP.md](CLEANUP.md) findings #1 and #39.

---

## Stage 1 — Stop the shell from freezing  [P0]

- [x] **1.1 Remove `Promises.await()` and make its callers async** [#1, #39]
      `Promises.await()` deleted. `fetchMonthEvents()` chains `getEnabledCalendarIds()`
      instead of blocking on it, and clears the loading flag on the failure path too.
      `getEnabledCalendarIds()` gained the `.catch(reject)` it was missing, without which
      a failed calendar fetch left its promise pending forever. `initialize()` now sets
      `_initialized` only when `calendars` actually came back, so a failed start retries
      instead of claiming readiness. `Fetch` rejects with a `status` field, which revives
      the dead 401 token refresh in `GoogleCalendarAuth` [#39], and keeps the response
      body off the log message [#32, partial]. The dead day-fetch path went with it:
      `fetchDayEvents()` and its only consumer `fetchCalendarEvents()`, 80 lines.
      Verified on the host 2026-10-28 — see the steps above.
- [x] **1.5 Decide whether to drop the hand-rolled `Promises` library** [#41]
      **Decided 2026-10-28: keep it.** Native `Promise` would still need hand-written
      `allSettled` and `finally`, brings no `async`, and its deferred callbacks would
      reorder the calendar code that was just verified on the host. The probe script is
      deleted.
      Starts with a probe on the host, since the engine's native `Promise` and `async`
      support cannot be checked in the container. `Promises` touches only `Fetch.qml`,
      `GoogleCalendar.qml` and `GoogleCalendarAuth.qml`, uses 4 API functions, and no
      production call site reads `.status`/`.value`/`.reason` from an `allSettled`
      result — so the migration is contained, and would delete ~410 lines
      (`Promises.qml` 182 + `PromisesTest.qml` 231). Watch the semantic difference:
      the hand-rolled `then()` runs its handler synchronously when the promise is
      already settled (`singletons/Promises.qml:69`), native defers to a microtask; 8 executors
      resolve synchronously. The probe script (`tests/probe.qml`) is deleted; results below.
      **Probe result (host, Quickshell 0.3.2, 2026-10-28):** native `Promise` exists and
      microtasks are drained, but `Promise.allSettled`, `Promise.any` and
      `Promise.prototype.finally` are all `undefined`, and `async` functions do not parse
      (`SyntaxError: Expected token ','`). A migration would still need hand-written
      `allSettled` and `finally`, and would gain no `async`/`await`.
      Counterpoint from the 1.1 verification: the library's own non-standard `_flatten`
      (adopting a promise *returned* by the executor, which native `Promise` ignores) hid
      a failed token refresh. Fixed, but it is the kind of bug native semantics rule out.
- [x] **1.2 Fix `Fetch._printf()`** [#2] — `singletons/network/Fetch.qml:86`
      `typeof args[num] !== undefined` is always true; URLs get the string `undefined`.
      Fixed; a missing argument now leaves its `{n}` placeholder in place. Covered by
      `tests/FetchTest.qml`, which fails against the old code.
- [x] **1.3 Add request timeout and error handling to `Fetch`** [#3]
      `singletons/network/Fetch.qml:20-82` — no `xhr.timeout`, no `ontimeout`/`onerror`,
      so a hung request wedges its dedup id for the rest of the session.
      Done 2026-10-28, verified on the host. `xhr.timeout` turned out not to exist in QML
      (setting it is silently ignored, `ontimeout` never fires), so each request gets a
      `Timer` that calls `xhr.abort()`; default 30 s, per call via `data.timeout`. A timed
      out request rejects with `status: 0` and `timedOut: true`, so callers can tell it
      from a network error (`status: 0` alone) or an HTTP error. The dedup id is now
      released when the request completes, before any handler runs — releasing it in
      `finally` handed a handler that retried the same id the already settled promise.
- [x] **1.4 Add test suites for the pure parsers** [#38]
      `NetworkManager._processStatus`, `WifiManager._processWifiList`, `IpManager._parse`,
      `Fetch._printf` (done with 1.2), `LinkSpeed._update`, `GoogleCalendar._getEventDayKeys`. These are
      pure functions and were the source of several bugs found in the review.
      Add one for `Promises.allSettled` ordering too [#40] — the existing assertions only
      cover synchronously settled promises, so they pass on a guarantee the code does not
      actually provide.
      Done 2026-10-28, verified on the host. New suites `tests/NetworkTest.qml` and
      `tests/CalendarDatesTest.qml`, plus an out-of-order `allSettled` test. Each new test
      that targets a bug fails against the old code. Bugs fixed along the way:
      - `allSettled` returned results in settlement order [#40]; now in input order.
      - **New:** `nmcli -t` escapes `:` and `\` in values with a backslash, and four parsers
        split on a bare `:` — status, wifi list, saved networks, VPN list. An SSID or
        connection name containing a colon came out as `Home\:5G`, matched nothing, and
        left "connecting" stuck. They now use `Nmcli.splitTerse()`
        (`singletons/network/Nmcli.qml`).
      - The date helpers moved from `GoogleCalendar` to the pure
        `singletons/googlecalendar/CalendarDates.qml`, since loading `GoogleCalendar` in a
        test connects to the real account. `GoogleCalendar` delegates; a first slice of 6.5.

## Stage 2 — Groundwork that makes touch a one-place change

- [x] **2.1 `components/PopupWidget.qml`** [#13]
      Extract the `_popupMode` + click/hover + `active` block duplicated across
      `PowerWidget`, `ClockWidget`, `MusicWidget`, `SoundWidget`, `BluetoothWidget`,
      `NetworkWidget`, `HardwareWidget`. Settle the inconsistent per-widget default mode
      while doing it. Do this **before** any touch work.
      Done 2026-10-28, verified on the host. `PopupWidget` extends `BarWidget`; widgets set
      `widgetType` and, for the clock, `popupContent: "calendar"`. The default mode is now
      `click` for all seven, since hover cannot fire on touch;
      `panels/WidgetSettingsPane.qml` repeats that default until 2.2 removes the copy.
      The user's machine keeps its old behaviour through explicit `_popupMode` values
      (music and sound set to `hover`). Every popup widget is now highlighted while its
      popup is open, not only power/network/hardware, and click-opened popups are all
      persistent — which fixes 8.6.
- [x] **2.2 `singletons/WidgetRegistry.qml`** [#12]
      One declarative source for type → component, display name, popup panel, settings
      pane, default popup mode. Replaces the four parallel maps in `Bar.qml`,
      `panels/BarSectionList.qml`, `panels/WidgetSettingsPane.qml`, `panels/Popup.qml`.
      Done 2026-10-28, verified on the host. Bar, picker, settings
      pane and popup load files by URL from the registry; `tests/WidgetRegistryTest.qml`
      checks every listed file compiles. Bar and picker now use `ScriptModel`. Regression
      found and fixed on the host: `ScriptModel` updates `modelData` in place, so the
      bar must bind `profile` to the delegate's `modelData`, not capture it once — the
      custom workspace and hardware labels had disappeared.
- [x] **2.3 Bring the four stragglers onto the widget contract** [#15]
      `NotificationsWidget`, `SettingsWidget`, `TrayWidget` (currently a bare `Row`),
      `WorkspacesWidget`.
      Done 2026-10-28, verified on the host. `widgetType` moved down into `BarWidget`, and
      every widget sets it. `BarWidget` gained `interactive` (false: the cell keeps size
      and background but its full-size `MouseArea` stops swallowing the clicks of the
      tray icons and workspace buttons) and `horizontalPadding`. Tray and workspaces look
      as before; tray icons now highlight on hover and while their menu is open.
      `NotificationsWidget` is a `PopupWidget`, so its popup mode is configurable; its
      accent colour for unread notifications never worked (it read `.count`, which the
      `ObjectModel` does not have) and now does.

## Stage 3 — Scaling  [blocks the Framework 12 install]

- [x] **3.1 A scale unit in `Theme.qml`** [#27]
      No `devicePixelRatio`/`Screen.pixelDensity` anywhere; 245 hardcoded pixel sizes and
      absolute font sizes. Needs a `dp()` or `scale` driven by the screen plus an explicit
      user override, since compositor scaling and shell scaling interact.
      **Not needed — verified on the host 2026-10-28.** On Wayland the QML sizes are
      logical pixels: Hyprland's per-monitor scale reaches Qt (6.12, fractional scale
      supported) and the whole shell — bar, popups, fonts, reserved space — scaled
      correctly when the user changed a monitor's scale. HiDPI on the Framework 12 is a
      `monitor=` line in Hyprland, as for every other app. What scaling does not cover
      is how big touch targets should be, which is a design decision and belongs to
      Stage 4 (4.6).
- [x] **3.2 Migrate sizes to the scale unit**
      Mechanical but wide. `panels/calendar/EventForm.qml` alone has 45. Worth doing
      per-file alongside the Stage 6 splits rather than in one sweep.
      **Dropped with 3.1.** The sizes stay as they are; they still belong in `Theme.qml`
      where they are shared, but that is ordinary hygiene, not a scaling prerequisite.

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
- [ ] **4.6 Touch-sized targets**
      Split off 3.1. Compositor scaling makes everything proportionally larger but does
      not make a 40 px bar cell, a 44×24 toggle or an 18 px tray icon finger-sized
      (~9 mm). Decide minimum target sizes, put them in `Theme.qml`, and apply them in the
      shared components first.

## Stage 5 — Idle cost  [battery]

- [x] **5.1 Read sysfs with `FileView` instead of `cat` subprocesses** [#21]
      Biggest single win: ~180 of the ~250 process spawns per minute. Affects the six
      `singletons/hardware/` sources and `singletons/network/LinkSpeed.qml`.
      Done 2026-10-28, verified on the host. `singletons/io/KernelFile.qml` is a
      `FileView` read synchronously per poll (~18 µs). Sensor discovery runs once at
      startup; only `df` for the disk is still a process. While verifying: GPU load was
      a single instantaneous sample that was mostly 0 — now averaged over 200 ms samples;
      VRAM got its own source instead of a subtitle under the load bar; the history
      graph's time axis now spans the selected window instead of the samples; every
      amdgpu card gets its own load, VRAM and temperature sources; a label of a single
      space shows as blank.
- [x] **5.2 Replace `nmcli` polling with NetworkManager DBus signals** [#21]
      `NetworkManager`, `WifiManager`, `VpnManager`, `IpManager`, `EthernetManager`.
      Removes ~60 spawns/min and makes the UI react instantly instead of up to 5 s late.
      Done 2026-10-28, verified on the host — with `nmcli monitor` rather than DBus:
      `Quickshell.Networking` exists but has no VPN, IP/DNS, hidden-network or wired
      connect, so it would have meant two sources of truth. `NetworkEvents` runs one
      `nmcli monitor`, debounces its output into `changed()`, and restarts it with a
      doubling delay (1 s → 60 s) if it dies; the managers re-query on `changed()` and
      keep a 60 s fallback poll. Queries that are busy when a change arrives run once
      more afterwards. Fixed on the way: the popup's Wi-Fi status lagged behind the
      widget after the radio came on, because "which network is in use" came only from
      scans — the cached list is now re-read on every change.
- [ ] **5.3 Gate polling on whether anything is observing it** [#21, #22]
      Nothing stops when the popup closes, and all six hardware sources poll even when
      the capsule shows one.
      **Replaced by a plan (2026-10-28): [plans/adaptive-polling.md](plans/adaptive-polling.md).**
      Design agreed 2026-10-28: polling rates become the first use of global shell
      profiles — named lists of setting overrides, activated by conditions (battery,
      battery level, power profile, lock, fullscreen, open panel), layered in list
      order. Absorbs 5.4.
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
- [x] **8.6 Power popup `persistent: true` on click** [#9] — `widgets/PowerWidget.qml:18`
      Fixed by 2.1: `PopupWidget` opens every click popup persistent.
- [ ] **8.7 `Lockscreen`: bind config declaratively** [#10]
- [ ] **8.9 Wrap the remaining live `Repeater` models in `ScriptModel`** [#43]
      The rule behind the months of random crashes — see ARCHITECTURE.md, "The Repeater
      crash". Bar and the add-widget picker are fixed with 2.2, `HardwarePanel` (the most
      urgent, inside a popup) alongside the GPU fix in 5.1.
- [ ] **8.8 Show calendar errors in the UI**
      Found while verifying 1.1 on the host. A failed fetch (offline, bad token, API
      error) only reaches the log; the calendar just stays empty, indistinguishable from
      a month with no events. `GoogleCalendar` needs an error state the panel can show,
      with a retry. While there: a retry after a failed init fetches `calendarList`
      twice, and the status-0 error message ends in an empty `data:`.

## Stage 9 — Hygiene, opportunistic  [P7]

- [ ] **9.1 Route `console.log` through `Logger`** [#35]
      `singletons/Config.qml:132`, `singletons/Notifications.qml:33`,
      `singletons/Lockscreen.qml:58`
- [ ] **9.2 Fix stale comments** [#36] — `panels/Popup.qml:23`, `singletons/Shell.qml:8`,
      `singletons/Music.qml:74`
- [ ] **9.3 One byte/rate formatter** [#19]
- [ ] **9.4 Move stray colours into `Theme.qml`** [#18] — 17 hex + 20 named
- [ ] **9.5 One scroll-notch implementation** [#16] — `BarWidget` vs `CustomMouseArea`
- [ ] **9.6 Move tray slide state out of the `Tray` singleton** [#20]
- [ ] **9.7 Implement or remove the screensaver exec commands** [#37]
      Config and UI exist; nothing runs them, so it looks finished to the user.
- [ ] **9.8 Leftovers** [#37] — empty `assets/`, missing trailing newline in
      `LockscreenSettings.qml`, `Logger` as `Item` rather than `QtObject`.

## Stage 10 — Requested features

- [ ] **10.1 Configurable animations**
      Requested 2026-10-28: the user wants to tune animation speed and easing curves.
      There are ~50 hard-coded `duration:` values across the QML, the popup open/close
      ones being 100 ms with `OutQuad`/`InQuad` (`panels/Popup.qml`). Plan: named
      durations and easings in `Theme.qml` (or a `Config.animations` section, if it
      should be editable from settings), a global speed multiplier, and every
      `NumberAnimation` reading from there.
      Measured on the host (DP-2, 144 Hz) while looking into popups that felt not quite
      smooth: frames come every ~6–7 ms as they should, but the calendar popup's first
      frames have a 51 ms gap — creating the panel (~37 ms) lands inside the running
      animation, so the 100 ms open took 161 ms and visibly jumps at the start. Worth
      fixing alongside: start the height animation a frame after the content is
      created. Do not move the content creation itself out of `Qt.callLater` — see
      "The Repeater crash" in ARCHITECTURE.md.
