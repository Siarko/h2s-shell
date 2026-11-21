# Done

The items of the old TODO list (now [tracker.md](tracker.md)) that are done, with their numbers, their notes and how
they were verified — kept for the decisions and the analysis behind them, which the
commits and the docs refer to by number. Stages 1–10 as they stood when closed, then the
done items of stage 11 in number order, then
the sections added later, each dated. User-visible changes are in
[CHANGELOG.md](../CHANGELOG.md).

## Contents

- Host verification — 1.1 (2026-10-28)
- Stages 1–10 of the old TODO list (2026-10-28 to 2026-10-31): freezing, groundwork,
  scaling, touch, idle cost, architecture, security, correctness, hygiene, requested features
- Stage 11 — done items in number order (2026-10-30 to 2026-11-17)
- From next-steps.md (2026-11-17)
- Test split — tracker step 10 (2026-11-17); found during the test split (2026-11-17)
- API plan and the work around it (2026-11-17 to 2026-11-19)
- Small items done (2026-11-19)
- The tracker's open sections as worded before 2026-11-19 (archive)
- Notifications with a progress bar and Taildrop's list of transfers (2026-11-19 to 2026-11-20)
- Taildrop's views reworked (2026-11-20)
- The notification flow (2026-11-20 to 2026-11-21)
- Tracker housekeeping (2026-11-21): items moved out of the tracker

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
[cleanup.md](cleanup.md) findings #1 and #39.

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
      11.14 (was 4.6).
- [x] **3.2 Migrate sizes to the scale unit**
      Mechanical but wide. `panels/calendar/EventForm.qml` alone has 45. Worth doing
      per-file alongside the Stage 6 splits rather than in one sweep.
      **Dropped with 3.1.** The sizes stay as they are; they still belong in `Theme.qml`
      where they are shared, but that is ordinary hygiene, not a scaling prerequisite.

## Stage 4 — Touch input

Moved to stage 11 (11.9–11.14) on 2026-10-31, last in the agreed order: 4.1 → 11.9,
4.2 → 11.10, 4.3 → 11.11, 4.4 → 11.12, 4.5 → 11.13, 4.6 → 11.14.

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
- [x] **5.3 Gate polling on whether anything is observing it** [#21, #22]
      Nothing stops when the popup closes, and all six hardware sources poll even when
      the capsule shows one.
      **Replaced by a plan (2026-10-28): [plans/adaptive-polling.md](plans/adaptive-polling.md).**
      Design agreed 2026-10-28: polling rates become the first use of global shell
      profiles — named lists of setting overrides, activated by conditions (battery,
      battery level, power profile, lock, fullscreen, open panel), layered in list
      order. Absorbs 5.4.
- [x] **5.4 Consider dropping `cava` to 30 fps** [#23] — measure first.
      Done 2026-10-29 as a profile setting, `polling.visualizer.fps` (Media page): 60 by
      default, 15 in Power save.

## Stage 6 — Architecture and size

- [x] **6.1 Config: stop storing JSON inside JSON** [#11]
      `widgetProfiles`, `audio.appVolumes`, `bar.content.*Profiles`. ~50 `JSON.parse`
      call sites in 23 files, most inside bindings. Two steps: a cached parse helper
      first, then migrate the storage to real `JsonObject`s keyed by profile name.
      Superseded by 10.3: settings are read through `Profiles.value()`; what is still a
      JSON string is parsed in one place each.
- [x] **6.2 `Popup` should expose its available content height** [#14]
      `panels/NetworkPanel.qml:496-506` hardcodes Popup's private paddings.
      Done 2026-10-30: `availableContentHeight` in `Popup.qml` (screen height less the bar,
      the paddings and a 16 px gap), set on a panel with an `availableHeight` property.
      NetworkPanel's list and NotificationPanel (which had its own `- 40 - 16`) use it.
- [x] **6.3 Split `panels/calendar/EventForm.qml`** (1033 lines) [P3]
      The RRULE editor, colour picker, calendar picker and all-day/time row are four
      independent components.
      Done 2026-10-30 (667 lines by then, 222 after): `RecurrenceEditor.qml` (rule state
      and editor; the rule text built and read by `CalendarDates.recurrenceRule` /
      `parseRecurrence`, tested), `EventColorRow.qml`, and a shared
      `components/Checkbox.qml` for All day, Recurring and the calendar settings list.
- [x] **6.4 Split `panels/NetworkPanel.qml`** (928 lines) [P3]
      Splits cleanly along the section comments already in the file.
      Done 2026-10-31 (706 lines by then, 303 after): `panels/network/` — `VpnSection`,
      `LinkInfo` (speeds, address, DNS; was written twice, for Ethernet and Wi-Fi),
      `WifiNetworkRow` (state still kept by SSID in the panel), `HiddenNetworkRow`,
      `SignalBars`.
- [x] **6.5 Split `singletons/googlecalendar/GoogleCalendar.qml`** (683 lines) [#17]
      API client / store / date+RRULE helpers.
      Done 2026-10-31 (640 lines by then, 384 after): `GoogleCalendarApi` (endpoints and
      requests), `GoogleCalendarData` (pure: Google's JSON to the panels' shapes and back,
      the series cut for "delete from here", failures in words; tested), `GoogleCalendar`
      the store. The store's hand-kept caches are unchanged — rethinking their
      invalidation would be its own item, not part of a split.
- [x] **6.6 Split `singletons/network/WifiManager.qml`** (359 lines) [P3]
      Done 2026-10-31 (394 lines by then, 314 after): the run-again-if-asked-mid-run nmcli
      query, hand-written six times (Wi-Fi radio and saved profiles, NetworkManager status,
      VPN, IP ×2), is `singletons/io/CommandQuery.qml`; the Wi-Fi list and saved-profile
      parsers are pure functions in `Nmcli`; the two connect functions are one. Scanning
      stays in WifiManager, having its own rescan and repeat logic.
      Functional check on the host done 2026-10-31. It found a typed password jumping
      to another network when the list refreshed (the row copied the password on
      ssidChanged, before `passwordText` followed the new SSID) — fixed, and one SSID
      from several access points is now one row, as the row state is kept by SSID.
- [x] **6.7 Remaining large files** [P3]
      `MusicPanel` 481, `BarSectionList` 425, `WorkspacesWidgetSettings` 394,
      `EventCard` 385, `HardwareSourceList` 378, `NotificationCard` 359.
      Re-measured 2026-10-31; order agreed with the user, one file at a time:
      - [x] `MusicPanel` (549 → 304): cava, the ambient wave and the decay in the
        `Visualizer` singleton (running only while the panel shows it), the drawing in
        `panels/music/VisualizerCanvas.qml`.
      - [x] `Theme.qml` (1088 → 673): the built-in theme in `ThemeBuiltin.qml`; reading
        and writing theme files, managing themes and the curves library, and the bar
        geometry migration in `ThemeFiles.qml`. Theme keeps resolution and drafts.
      - [x] `SettingsWindow.qml` (807 → 481): `SettingsPicker`, `WindowTab`,
        `SettingsPageList` (with the sliding mark), and the five shape pages as files
        (`WidgetsShapeSettings`, `PopupsShapeSettings`, …).
      - [x] `CurvesSettings.qml` (772 → 431): the point maths in `CurvePoints` (pure,
        tested), the graph in `CurveGraph.qml` — which also gained full pan and zoom (drag
        the background, zoom at the pointer, to 20×) — and the preview in `CurvePreview.qml`.
      - [x] `BarSectionList` (447 → 116) and `HardwareSourceList` (422 → 114): the shared
        card — drag to reorder with auto-scroll, remove, add from a floating list — is
        `components/ReorderList.qml`; each list gives only its row content (and the bar
        its ⚙ detail). An empty `_dragGhost` item left from an older version is gone.
      - [x] `EventCard` (399 → 289): a single event deletes through `DeleteButton`, as the
        convention says; an event of a series offers its three deletions in
        `RecurringDeleteChoice.qml`. `NotificationCard` (360 → 252): the inline reply in
        `NotificationReply.qml`, the code chips in `CodeChips.qml`.
- [x] **6.8 I/O out of `PowerMenu` and `BluetoothPanel`** (found 2026-10-31)
      Both start processes themselves, against "state and I/O live in singletons/"
      (CLAUDE.md), as MusicPanel did with cava.
      Done 2026-10-31: `Session` (shutdown, restart, logout — the scripts started
      detached, so the popup closing cannot stop them) and `BluetoothDiscovery` (the
      `bluetoothctl` scan, now `--timeout 30`: plain `scan on` exits at once in BlueZ 5.87
      and the scan died with it, so Scan never found anything; the panel stops it when
      it closes). No
      view file under panels/, widgets/, hud/ or components/ starts a process now.

## Stage 7 — Security  [before the Google account is set up on the new machine]

- [x] **7.1 Stop passing the client secret on the command line** [#30]
      `singletons/googlecalendar/GoogleCalendarAuth.qml:33` — world-readable via
      `/proc/<pid>/cmdline`. Use stdin or the environment.
      Done 2026-10-29: the helper gets them from GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
      (`/proc/<pid>/environ` is the owner's and root's only).
- [x] **7.2 Check and enforce config file permissions** [#31]
      The refresh token is a long-lived credential in plaintext in
      `~/.config/h2s_shell/config.json`. Verify the mode is `0600` on the real machine.
      Done 2026-10-29, verified on the host: it was 644 in a 755 directory. Config runs
      `chmod 700` on the directory and `600` on the config and its backups at every start.
- [x] **7.3 Stop logging full HTTP response bodies** [#32] — `singletons/network/Fetch.qml:68`
      Won't fix, decided 2026-10-29: only in debug mode; tokens in a debug log are an
      accepted risk.
- [x] **7.4 Escape the workspace name in the Hyprland dispatch** [#33]
      `singletons/Workspaces.qml:30`, and document where `hl.dsp.*` comes from so the new
      install does not silently lose logout and special workspaces.
      Done 2026-10-29: the name goes in as a Lua string literal (`Workspaces.luaString`,
      tested); `hl.dsp.*` is Hyprland's Lua-config dispatch (0.5x, `hyprland.lua`),
      noted in Workspaces.qml, scripts/logout.sh and FEATURES.

## Stage 8 — Correctness fixes, fold into whichever stage touches the file  [P1]

- [x] **8.1 One `SettingsWindow`, not one per monitor** [#4] — `Bar.qml:247`
      Done 2026-10-29: one window in `shell.qml`, reached through `Shell`.
- [x] **8.2 `Notifications.timestamps` reassign instead of mutate** [#5]
      Done 2026-10-29: reassigned, and set (with the codes) before `tracked = true`.
- [x] **8.3 Fix the `Connections` leak in `Audio.qml`** [#6], and document `type === 21`
      Done 2026-10-29: one watcher per app stream, destroyed with it; app streams kept by
      object, not by the shifting index; 21 is `PwNodeType.AudioOutStream`.
- [x] **8.4 `Notifier`: one process per interactive notification** [#7]
      Done 2026-10-29, verified on the host: a process per notification, destroyed on
      exit; four interactive ones at once each reached their own callbacks.
- [x] **8.5 `PowerMenu`: absolute script paths** [#8] — `panels/PowerMenu.qml:72`
      Already fixed before 2026-10-29: the Process sets `workingDirectory: Quickshell.shellDir`.
- [x] **8.6 Power popup `persistent: true` on click** [#9] — `widgets/PowerWidget.qml:18`
      Fixed by 2.1: `PopupWidget` opens every click popup persistent.
- [x] **8.7 `Lockscreen`: bind config declaratively** [#10]
      Done with 10.3: Lockscreen binds its settings from Profiles and reapplies its idle
      monitors when they change.
- [x] **8.9 Wrap the remaining live `Repeater` models in `ScriptModel`** [#43]
      The rule behind the months of random crashes — see ARCHITECTURE.md, "The Repeater
      crash". Bar and the add-widget picker are fixed with 2.2, `HardwarePanel` (the most
      urgent, inside a popup) alongside the GPU fix in 5.1.
      Done 2026-10-29: the last one, the notification card's action buttons, is wrapped
      too. The calendar's day names (an input property) got one as well. Every
      remaining Repeater model is a Quickshell ObjectModel or a ListModel.
- [x] **8.8 Show calendar errors in the UI**
      Found while verifying 1.1 on the host. A failed fetch (offline, bad token, API
      error) only reaches the log; the calendar just stays empty, indistinguishable from
      a month with no events. `GoogleCalendar` needs an error state the panel can show,
      with a retry. While there: a retry after a failed init fetches `calendarList`
      twice, and the status-0 error message ends in an empty `data:`.
      Done 2026-10-29, verified on the host (network off, then retry). With the network off
      the spinner runs until the request fails — up to Fetch's 30 s timeout when the
      connection hangs rather than being refused. `GoogleCalendar.error`, set by a failed load of
      the calendar list or of events (partial failures name how many calendars), cleared
      by a good one; the panel banner shows it and retries on click. A failed init no
      longer goes on to fetch the calendar list again; status 0 drops the empty "data:".
      The banner's click now fits its message (retry / sign in / settings), and the
      loading spinner turns around its ring's centre.

- [x] **8.10 "Enable Google Calendar" does nothing but change a message**
      Found 2026-10-29 while moving it into profiles. `gcal.enabled` is read only by
      `panels/calendar/EventsPanel.qml` for its status text; `GoogleCalendar` syncs
      regardless. Now that it is a per-profile setting (e.g. off in Power save), the sync,
      the token refresh and the calendar panel should honour it.
      Done 2026-10-29, verified on the host: `GoogleCalendar.available` (signed in and
      enabled) gates every fetch — and with it every token refresh — and the panel's
      editing; switching off clears the fetched events, switching on fetches again.

## Stage 9 — Hygiene, opportunistic  [P7]

- [x] **9.1 Route `console.log` through `Logger`** [#35]
      `singletons/Config.qml:132`, `singletons/Notifications.qml:33`,
      `singletons/Lockscreen.qml:58`
      Done 2026-10-30: the Notifications and Lockscreen calls were already gone; Config's
      "Saved" goes through a Logger, so only with the debug switch on. The `console.*`
      left in singletons are deliberate: one-time migration notes and themes that do not
      parse, which should show whatever the switch says.
- [x] **9.2 Fix stale comments** [#36] — `panels/Popup.qml:23`, `singletons/Shell.qml:8`,
      `singletons/Music.qml:74`
      Done 2026-10-30: Shell's comment was already right (pages by id); Popup's
      `contentType` and Music's polled position say what they are.
- [x] **9.3 One byte/rate formatter** [#19]
      Done 2026-10-30: `singletons/Format.qml` (`bytes`, `rate`), replacing four copies of
      `formatBytes` and `NetworkManager.formatSpeed`; same output, except a size under a
      megabyte now shows in KB rather than raw bytes. `tests/FormatTest.qml`.
- [x] **9.4 Move stray colours into `Theme.qml`** [#18] — 17 hex + 20 named
      Done 2026-10-29 as stage 1 of plans/themes.md: colours named by role, all literals
      and hand-written alphas replaced; the only literals left are Google's calendar colour
      (account data) and the music visualizer's shades of a colour it is given.
- [x] **9.5 One scroll-notch implementation** [#16] — `BarWidget` vs `CustomMouseArea`
      Done 2026-10-30: `components/ScrollNotches.qml`, used by both, the constant named
      and explained. Fixed on the way: the direction was taken before the event was added,
      so the first notch, and the first after turning back, went the wrong way.
      `tests/ScrollNotchesTest.qml`.
- [x] **9.6 Move tray slide state out of the `Tray` singleton** [#20]
      Done 2026-10-30: `singletons/Tray.qml` removed. `Popup.open()` takes a `contentData`,
      per popup (so per screen); the tray icon passes `{ menu, direction }`, working out
      the direction from the icon it opened last, and `TrayMenu.request` reads it.
- [x] **9.7 Implement or remove the screensaver exec commands** [#37]
      Config and UI exist; nothing runs them, so it looks finished to the user.
      Implemented 2026-10-29, verified on the host: schema settings (per profile), run with
      `sh -c` detached, tied to idleness rather than the screensaver's visibility — a lock
      during the screensaver is not "back"; the end command runs on return, even at the
      lock prompt, and only after a start command.
- [x] **9.8 Leftovers** [#37] — empty `assets/`, missing trailing newline in
      `LockscreenSettings.qml`, `Logger` as `Item` rather than `QtObject`.
      Done 2026-10-30: `assets/` removed (untracked, nothing referred to it), newline
      added, `Logger` is a `QtObject` (every instance sits in a `Singleton`). The
      screensaver commands in the same CLEANUP entry are 9.7.
- [x] **9.9 Hidden list editor fed objects** — `Unable to assign QJSValue to QString` at
      `panels/settings/SchemaSettingEditor.qml:338`, a dozen times when the Bar page opens.
      The text-list editor (`_listEditor`, line ~307) exists for every setting and takes
      any array as its items, so a bar section (`[{ type, preset }]`) reaches its
      `TextInput.text`. Feed it only for `type === "stringList"`, as the slider already is.
      Found 2026-10-29; harmless, predates the themes work.
      Done 2026-10-30: the editor's items are the value only for a `stringList`; after
      opening the Bar, General and Notifications pages the log has no such warning.

## Stage 10 — Requested features

Its open items moved to stage 11 on 2026-10-31, renumbered in the agreed order:
10.16–10.18 → 11.1–11.3, 10.12 → 11.4, 10.13 → 11.5, 10.14 → 11.6, 10.9 → 11.7, and
10.15 (scroll sensitivity, widened into compositor integration) → 11.8.

- [x] **10.3 Every setting per profile, with user-pinned global settings** [#11]
      Agreed 2026-10-29: [plans/global-profiles.md](plans/global-profiles.md). The
      editing-profile picker covers the whole settings window; every setting is saved per
      profile, except those the user pins as global. Doubles as the config rework (#11).
      Done 2026-10-29, verified on the host: every settings page and the bar are per
      profile; `Config.qml` keeps only data that is not a preference.
- [x] **10.4 More notification settings** (requested 2026-10-29)
      All as schema settings, so per profile (e.g. no toasts in Power save or while a
      fullscreen window is focused):
      - whether toasts show on the desktop at all;
      - how long a toast stays (today a fixed 5 s in `hud/NotificationHudItem.qml`);
      - queueing: one toast at a time with a queue badge, as now, or a column of toasts —
        and then how many at most in the column.
      Done 2026-10-29, verified on the host: four schema settings on the Notifications page;
      Hud holds ten toast slots, the setting enables one or the column's size, each placed
      by `Notifications.shownToasts` — newest on top — and only the oldest counts down.
- [x] **10.5 Notification privacy on the screensaver and lock screen** (requested
      2026-10-29)
      Separate settings for the screensaver and for the lock screen: when notifications
      are shown there, show them in full or hide their content (app and title only).
      `screensaver/ScreensaverSurface.qml`, `screensaver/LockSurface.qml`.
      Done 2026-10-29, verified on the host: `lockscreen.screensaverNotificationDetail` and
      `lockscreen.lockNotificationDetail` — full / title / app — shown by one shared
      `screensaver/NotificationPreview.qml` instead of two copies of the card.
- [x] **10.6 Dragging a slider scrolls the settings page** (reported 2026-10-29)
      Moving the mouse vertically while dragging a horizontal slider hands the drag to the
      page's Flickable, which scrolls instead. Likely fix: `preventStealing: true` on the
      slider's MouseArea in `panels/settings/SettingSlider.qml` (used by every slider,
      including the schema editor's), and the same for any other drag inside a Flickable.
      Done 2026-10-29: `preventStealing: true` on the slider's MouseArea.
- [x] **10.7 Widget presets: review findings** (2026-10-29)
      A review of the preset feature (widget settings pages, `panels/WidgetSettingsPane.qml`,
      the widgets that read presets) after the rename from "widget profiles":
      - A section's add-widget picker skips types already in it, so two clocks or two
        hardware capsules in one section — the main use of presets — need a hand edit.
      - The preset field shows for every widget, including those without preset settings
        (music, sound, tray), where assigning one does nothing.
      - Editing a preset changes every place that uses it, now including bar sections of
        other shell profiles, and nothing says so. Show where it is used.
      - Presets cannot be deleted or renamed; a name is only stored once a setting is
        edited, so an unedited new name (or a typo) points at nothing and the widget
        silently falls back to defaults.
      - A widget without a preset cannot be configured at all — open question: own
        settings for a preset-less widget, or a one-click "new preset".
      - The workspaces name-map editor loads its list once and never refreshes, so a
        second settings window (one per monitor, 8.1) or a second expanded entry editing
        the same preset gets overwritten.
      - An empty clock format: the widget falls back to "hh:mm:ss", the settings page shows
        an empty field and an empty preview.
      - Defaults are duplicated between each widget and its settings page; every read
        parses the whole preset JSON, every write repeats parse-mutate-stringify (five
        near-identical save functions in the workspaces page). A `WidgetPresets` singleton
        (get, set, usages, rename, delete) would remove that and host the fixes above.
      Done 2026-10-29, verified on the host: `WidgetPresets` singleton (the one parse and
      write, per-type defaults, usages, rename and delete repointing every profile's bar
      entries); the preset area shows only for widgets with presets, says where the
      preset is used, offers "Customize" for a widget without one (decided: no preset =
      defaults, settings always through a preset), creates a preset as soon as it is
      named; clock, hardware and workspaces may repeat in a section (`multiple` in
      WidgetRegistry); the name map editor refreshes; an empty clock format shows as the
      default. The gear is hidden for widgets with nothing to set (settings, tray).
- [x] **8.11 First toast of a queue sits against the queue badge** (reported 2026-10-29)
      With several notifications queued, the toast should keep a gap from the badge
      showing how many are waiting. The first toast has no gap; every later one does. The
      toast's resting x is `restX` in `hud/NotificationHudItem.qml`, which shifts left
      when the badge appears — likely the first toast slides in to the position computed
      before the queue (and the badge) existed, and only the next show uses the new one.
      Done 2026-10-29, verified on the host: the slide-in took its target at the start, and
      the nudge was skipped while sliding; the slide (and the nudge) now catch up to
      `restX` when they finish.
- [x] **10.8 Versioning** (requested 2026-10-29)
      Give the shell a version and a scheme for it, and show the current version at the
      bottom of the settings sidebar. To decide: the scheme (semantic versioning seems the
      natural fit — major for config or behaviour changes that need migration, minor for
      features, patch for fixes), where the number lives (a `Version` singleton or a file
      read at startup, plus git tags), whether the shown string adds the git commit for
      builds between releases, and how it ties to the config: `Config` could record the
      version that last wrote it, which the per-key migration could use instead of (or as
      well as) `migratedKeys`. A CHANGELOG would follow naturally.
      Done 2026-10-29, verified on the host: semver, starting at 1.0.0 (tag `v1.0.0`);
      `singletons/Version.qml` holds the number and shows `number+commit[.dirty]` off a
      release, selectable in the settings sidebar; CHANGELOG.md with an Unreleased section;
      `Config.writtenBy`; tests/VersionTest.qml keeps the number and changelog in step.
- [x] **8.12 Popups overhang a bar that does not reach the screen edge** (reported
      2026-10-29)
      With a left or right margin on the bar, a popup opened near that end is clamped to
      the screen edge, not the bar's: it sticks out past the bar's end, and its top
      corner curves (`PopupCurve`, `roundingLeft`/`roundingRight` in `panels/Popup.qml`)
      are drawn as if the bar continued. Clamp `clipWrapper.x` to the bar's extent
      (`bar.layout.leftMargin` … screen width − `rightMargin`) and decide the curves
      against those edges too.
      Done 2026-10-29, verified on the host: x is kept within the bar, short of a rounded
      bar corner; the edge the popup is held against is the one animated when switching,
      the width animates too, and the bar's limits apply to every frame.
- [x] **8.13 Occasional binding loop in Profiles at startup** (seen 2026-10-29)
      Sometimes, at startup only, Qt reports a binding loop on `Profiles._resolved` and
      then `facts`, followed by a config save; four restarts in a row were clean. Qt
      breaks the loop, so nothing visibly fails. Likely a startup ordering race — something
      written while `_resolved` is being evaluated (a fact source created during its
      evaluation, or a migration/seed write). Reproduce by restarting repeatedly.
      Found the same day: simulating a battery reproduced it every time. Applying the
      system power profile from the change handler of the effective value changed the
      `power.profile` fact while the facts were being re-evaluated. Deferred with
      `Qt.callLater`, as the seeding already was.
- [x] **10.10 Settings window: make "editing a profile" and "editing a theme" clear**
      (reported 2026-10-30, while testing themes stage 6a)
      The window edits two kinds of thing: behaviour pages edit a profile, Appearance
      pages (Themes, Curves, later Colors, Fonts, Bar, Animations) edit a theme. Both
      pickers sit in the same place in the sidebar, and the list silently swaps between
      profiles and themes as you move between pages. A new user would not know what is
      being edited, nor how profiles and themes relate (a profile picks a theme). Needs a
      better structure, designed with the user before stage 6 goes much further. Ideas to
      weigh, none decided: the picker in each page's header ("Editing profile Full ▾" /
      "Editing theme Full ▾") instead of the sidebar; two clearly separate sidebar
      sections, each with its own picker; showing the link — "Full uses theme X", jump to
      it — on both sides; the theme picker on Appearance pages defaulting to the theme of
      the profile being edited.
      Decided 2026-10-30: two tabs at the top of the window, Behaviour and Appearance,
      each with its own picker at the top of the sidebar (profile / theme, a list that
      opens under it) and the link shown on both sides ("Uses theme X ↗" / "Used by …");
      entering Appearance starts at the theme of the profile being edited. Added at the
      user's request: "Preview" (`Theme.preview`, shown over the profile's
      theme; the theme list locked meanwhile, not offered for the theme in use, ended by
      "Stop preview", leaving Appearance or closing the window). Verified on the host
      2026-10-30.
- [x] **10.11 Popup widths and remaining fixed layouts that do not follow the font**
      (found 2026-10-30, auditing for user-set font sizes, themes stage 6)
      Popups grow with their content vertically but have fixed widths (Network and
      Bluetooth 280, Tray 220, Power 200, Music 320, Sound 300, Notifications 350,
      Hardware 280; the calendar 270 + 280 × 340), so with larger fonts long rows crowd
      or overflow. Also: the event form's recurrence row (76 px dropdown + "Every" + 40 px
      field + "month(s)" in a ~250 px card); NetworkPanel's expanded heights (76, 102) are
      sums of fixed rows; EventsPanel's header in the 270 px column; the settings window's
      160 px sidebar. Make popup widths follow content or the font, within limits.
      Done 2026-10-30, verified on the host (decided with the user: widths follow the font,
      with multipliers on top): `Theme.fontScale` (the theme's body size over the
      built-in's), `Theme.scaled(width)`, `Theme.popupWidth(name, base)` = base × font
      scale × `popupWidth.all` % × `popupWidth.<name>` %; every popup panel and the
      calendar (columns and height) use it; the settings window and its sidebar scale
      with the font. Appearance → Popups → Widths: the multipliers (50–200 %), each with
      the width it comes to. Network's rows take their heights from their content; the
      events header elides the date when narrow; the event form's repeat row is a Flow.
- [x] **10.2 Heartbeat on graph updates**
      Requested 2026-10-29: an optional (on/off in config) visual cue at the moment a
      history graph takes a new sample — a semi-transparent wave travelling across the
      graph from its right edge to the left. Matters more now that profiles can slow
      sampling to 10–30 s: it shows the graph is alive and when it updated. Lives in
      `components/HistoryChart.qml`; the look is to be settled with the user.
      Done 2026-10-29, verified on the host: a 350 ms wave, right to left, brightening the
      line and the fill under it in a lighter shade of each series' colour, over a
      muted full-height band so it is visible where there is no data yet. Setting
      `graphs.heartbeat` (on; Power save turns it off).

- [x] **10.1 Configurable animations** — done within **10.9** (themes plan, stages 4–6:
      animation roles, the curves library and editor, Animations page); what is left of
      the themes plan is 11.7
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

---

## Stage 11 — done

- [x] **11.1 A tray menu opening fresh slides in from the bar** (was 10.16) (requested 2026-10-30; moved
      from 9.10)
      Opening a tray menu with no popup open (not switching from another icon's menu),
      the menu slides in sideways from the right, as a switch would. It should come in
      from the bar's side, the way the other popups open. Switching between tray icons'
      menus stays as it is (from the side of the icon clicked), and so does going into
      a submenu and back. Where: `panels/TrayMenu.qml` — `Component.onCompleted` runs
      `changeMenu()`, whose `beginTransition(direction)` is the sideways slide; a fresh
      open should show the menu in place and leave the entrance to the popup.
      Done 2026-10-31, verified on the host: a fresh menu is put straight into the visible
      slot in `Component.onCompleted`, without a transition.

- [x] **11.2 Multi-day events in the event form** (was 10.17) (requested 2026-10-31)
      Done 2026-10-31, verified on the host: start and end dates (DateField, typed or
      filled by clicking days in the calendar once armed), the span shaded in the grid,
      the edited event pinned in the list, edits keeping their dates, per-date time zone
      offsets; bars for spanning events above the day numbers and a coloured dot per
      single-day event; read-only calendars without edit/delete; larger card buttons.
      The form takes one day — the one selected in the calendar — and, for a timed event,
      a start and end time on it; there is no way to give an end date. Google and the
      panel already handle multi-day events (`CalendarDates.eventDayKeys`,
      `GoogleCalendarData.event`'s `allDayDuration`), and editing one made elsewhere
      would today squash it to its first day. Wanted: an end date (all day: the last
      day; timed: the end's date and time), defaulting to the start day, and editing
      keeping an existing event's span. Where: `panels/calendar/EventForm.qml`,
      `GoogleCalendarData.eventBody` (end date, exclusive for all day), and what
      `EventCard`/`EventsPanel` pass in. To settle with the user: how the end date is
      picked (a date field like the recurrence's, or a small calendar).

- [x] **11.3 Visualiser around the album cover** (was 10.18) (requested 2026-10-31)
      Another `media.visualizerStyle`: the levels drawn around the cover in the music
      panel — a ring, rays or a glow pulsing with the bass, say — instead of beside or
      below it. The levels are `Visualizer`'s; the drawing would be a new mode of
      `panels/music/VisualizerCanvas.qml` (or a sibling) laid over the cover. The look is
      to be settled with the user.
      Done 2026-11-01, verified on the host. Decided from mockups: a layout "around"
      (not a style) where waveform, bars (rays) and dots follow the cover's outline —
      `singletons/RoundedOutline.qml`, tested — bass at the bottom, bands keeping their
      places as the cover turns; styles "glow" (the waveform's shape, layered faint and
      blurred) and "glowEven" (the same at `Visualizer.bass`) in every layout; settings
      `media.coverRounding` (0–100 %, default 33 = the old 20 px) and
      `media.coverRotation` (−360–360 °/s, below 0 anticlockwise, while playing, not
      with reduced motion). The art row grows to 210 px around; no cover shows a
      stand-in with a note.
      Added on the way: layouts "horizontalBottom" and "verticalSides", glued to the
      popup's edges and growing inward (`VisualizerCanvas.edge`), past the panel by the
      popup's padding and masked to the popup background's corners (`overlayHost`); the
      old two relabelled "(centered)". A slider's optional `neutral` value (schema
      `neutral`), its fill starting there — the rotation's 0.
      Then: a theme colour `visualizer`, following the accent until set
      (`ThemeRules.colorFollows`: built in as "", filled from its leader on resolve, its
      origin "follows Accent"); `media.coverColors`, around the cover only — the cover
      sampled at 24×24 as it loads, `singletons/CoverColors.qml` (tested) picks up to
      three colours by hue, drawn as a conical gradient symmetric about the vertical.

- [x] **11.4 Bar position: bottom, and vertical at a side** (was 10.12) (requested 2026-10-30)
      Today the bar is only horizontal at the top. Wanted: the bar at the bottom of the
      screen, and — harder — a vertical bar along the left or right edge. Touches far more
      than Bar.qml: the bar's anchors and exclusive zone; every widget's layout (a
      vertical bar needs widgets that stack and fit a narrow width — text such as the
      clock or the music title has to rotate, shorten or wrap); popups (they open
      downwards from the bar today, with curved top corners joining it — PopupCurve —
      and positions computed from the bar's height); the HUD and toasts placed relative
      to the bar; the theme's bar geometry (topOffset, reservedSpace… become per-edge).
      Likely an `edge` setting (theme or profile? to decide) with top as today. Needs an
      analysis and a plan, with the user, before any work.
      Plan: notes/plans/bar-position.md (setting per profile, tokens relative to the edge,
      HUD left alone). **Stage A, the bottom edge: done (2026-11-01).** Stage B, a
      vertical bar at the left or right: done (2026-11-01). Left for other items: the
      HUD placed relative to the bar's edge (it may collide with a side bar), and the
      dictation preview as a floating window instead of text on the bar.

- [x] **11.9 Popup must close on outside tap, not on pointer-exit** (was 4.1) [#24]
      `panels/Popup.qml:232-238`, and `focusable: hoverHandler.hovered` at `:74`.
      Done 2026-11-08, verified on the Framework: a popup opened by a tap (`touchOpened`)
      closes on a tap outside it and the bar — `components/OutsideTapCatcher.qml`, a layer
      with holes, after `hyprland_focus_grab_v1` proved unusable with the on-screen
      keyboard — and takes the keyboard without hover. Mouse-opened popups unchanged (the
      user keeps them open while working elsewhere). plans/touch.md, "Popups".

- [x] **11.10 Pick the popup mode from the input type** (was 4.2) [#25]
      Hover mode is unusable on touch and is the default for clock, sound and bluetooth.
      One place once 2.1 is done.
      Done 2026-11-08, verified on the Framework: not a mode per input type but per
      event — a tap toggles any popup as a click (`PointerRules`, `PopupWidget`); hover
      is passed on 60 ms after the pointer comes over unless a touch press came, since the
      device a hover names is no guide. The stylus hovers, so hover popups stay for it.
      Tests: `PointerRulesTest`, `PointerInputTest`.

- [x] **11.11 Touch feedback for the 64 hover-only visual states** (was 4.3) [#26]
      Drive visual state from both `TapHandler.pressed` and `HoverHandler.hovered`,
      through shared components so it is not 64 separate edits.
      Done 2026-11-08 with 11.14, verified on the Framework and by the user with the mouse
      on the host. Decided with the user: the shell does not change for touch — the hover
      look on a tap, held 200 ms after the release (`components/PointerArea.qml`'s
      `lit`), about 60 areas moved to it; tooltips stay on `containsMouse`.

- [x] **11.12 Touch equivalents for the 7 wheel-only interactions** (was 4.4) [#28]
      Volume on the sound widget, workspace switching, sliders.
      Done 2026-11-08, verified on the Framework. Measured first: almost nothing was
      wheel-only — the bar's volume and track, the sliders, the player list, the colour
      row and a popup cut by the keyboard all have a way by finger (a popup, a drag, a
      swipe); workspaces have no wheel. Two gaps were real and are filled: the calendar's
      year (a click or a tap on the month or year shows the year's months — arrows and a
      swipe move by years, a month goes there) and the Curves graph's zoom (a pinch, with
      the background's drag moved from a MouseArea to a DragHandler a pinch can take the
      first finger from). `touchtap.py` learnt `pinch`.

- [x] **11.14 Touch-sized targets** (was 4.6) — with 11.11, plans/touch.md stage 3
      Split off 3.1. Compositor scaling makes everything proportionally larger but does
      not make a 40 px bar cell, a 44×24 toggle or an 18 px tray icon finger-sized
      (~9 mm). Decide minimum target sizes, put them in `Theme.qml`, and apply them in the
      shared components first.
      Done 2026-11-08 with 11.11. Decided with the user: no "Touch" theme, invisible
      targets — `PointerArea` is at least `target.minSize` (36 px, a theme token,
      Appearance → Controls → Targets) round its control, look and layout unchanged;
      `reach` for more. Rows of a list that touch, adjacent words, the delete button's
      "×", check boxes and the vertical sliders keep their own size (`centred: false` or
      untouched): a larger area would take clicks from the neighbour.

- [x] **11.13 Gestures** (was 4.5) [#29]
      Swipe to dismiss a notification, edge swipe for panels. New feature surface —
      depends on 11.9–11.12.
      Done 2026-11-08, verified on the Framework by virtual touch, the user's list:
      notifications swiped away (HUD and panel), the calendar's month swiped with the
      coming month beside it, the music panel swiped — sideways a track, vertically a
      player — with its slides moved to the same axes. `components/SwipeGesture.qml` is
      the shared part. An edge swipe for panels was only a "possibly": not done.

- [x] **11.15 Notification pictures, each in its place; the default action on the card**
      (requested 2026-10-31) — done 2026-10-31, verified on the host
      A notification has an app icon (`app_icon`, or its desktop entry's icon) and an
      image (`image-data` / `image-path`: an avatar, album art, a screenshot — or, from
      Chrome/Electron, the app's logo). The card showed every image centred under the
      text. Now: the icon small in the header; a square image a rounded thumbnail left of
      the text; a wide or tall one a preview across the card; an icon the theme lacks
      shows nothing (no checkerboard). The `default` action (clicking the notification)
      was an empty button (and never found: Quickshell's actions have `identifier`, not
      `id`): now the card itself — header, text, image — runs it, shown by a hover
      background and a hand cursor, over the text too (still selectable by dragging; a
      click that clears a selection only clears it). Header colours stay free for
      urgency or kind of message, not for "clickable" (the user's call). A card keeps
      its content while it slides away after an action closed its notification. `components/NotificationCard.qml`,
      `components/RoundedImage.qml`.

- [x] **11.16 Icon theme in the settings** (requested 2026-10-31)
      Done 2026-10-31, verified on the host: `scripts/launch.sh` (start, `--restart`,
      `--list`, `--resolve`, `--preview`), `singletons/IconThemes.qml`, a dropdown on the
      General page with sample icons and "Restart to apply", Hyprland's autostart calling
      the script (`hyprland.lua` backed up first), and a banner (`hud/LaunchWarning.qml`)
      when the shell was started without it. Plan as agreed:
      The shell has no icon theme: qt6ct sets none, so Qt looks only in `hicolor` — app
      icons load, status icons (`dialog-warning`…) do not. Quickshell sets the theme once,
      at launch (`QS_ICON_THEME` or `//@ pragma IconTheme`); nothing changes it live.
      Agreed: a `scripts/launch.sh` reads the setting from the config and starts
      `QS_ICON_THEME=… qs`; Hyprland's autostart (`hyprland.lua`, `sleep 2 && qs`) calls
      it instead (one change, backed up first); choosing a theme restarts the shell
      through it, and the page says so. A global setting (a per-profile one would restart
      the shell on a profile switch), on the theme page. "Automatic", the default: the
      system theme (gsettings) if installed, else the first theme found in
      `~/.local/share/icons`, then `/usr/share/icons` — not `hicolor`, not cursor-only
      themes such as `default`. The list offers the installed themes. Covers every icon
      of the shell, the tray's too.

- [x] **11.17 Formatting in notification text** (requested 2026-10-31) — done 2026-10-31,
      verified on the host
      The shell tells senders it supports body markup (`bodyMarkupSupported`), but the
      card shows the tags as typed: `<b>`, `<i>`, `<u>`, `<a href>` (hyperlinks are
      advertised too) and `<img>`. Render the spec's subset — and only it: other tags and
      entities escaped, links opened on click (through `Qt.openUrlExternally`), so a
      notification cannot inject arbitrary rich text. Keep text selectable and the codes
      found in it (CodeChips) working on the plain text.
      Decided 2026-10-31: `singletons/NotificationMarkup.qml`
      — a small tokenizer, then b/i/u kept, br/p line breaks, other tags dropped (text
      kept); http/https/mailto links open on a click, any other scheme in the warning
      colour asks first (Open / Copy / Cancel); images never loaded, a tinted row with an
      image glyph linking to them; `bodyImagesSupported` off. The screensaver preview
      shows plain text (it drew the body's HTML unfiltered). Tests:
      `tests/NotificationMarkupTest.qml`. Hovering a link shows its address over its
      line (image rows show it in the row instead); HoverTip fixed on the way — it never
      opened when its text and `shown` changed together.

- [x] **11.18 A count beside the notifications icon** (requested 2026-10-31) — done
      2026-11-01, verified on the host
      Decided 2026-11-01: a badge on the bell ("9+" past
      nine, hidden at zero); the bell rung — lifted, shaken, put back — "off", "once",
      "untilOpened" (every 5 s while notifications came since the panel was last open:
      `Notifications.unreadCount`) or "untilCleared" (every 5 s while any is left); both
      in the widget's preset
      (`panels/widget_settings/NotificationsWidgetSettings.qml`). Shell notifications
      never enter the panel, so they are not counted. The old ring (a scale jump) was
      there but never seen to play.
      The bar's notifications widget only turns accent-coloured when there is any
      notification (`widgets/NotificationsWidget.qml`); how many is not shown. Wanted: the
      number beside or on the icon — a badge or plain digits, to settle with the user —
      hidden at zero, capped ("9+") so the bar cell does not grow without end. The count
      is `Notifications.notifications.values.length`; shell notifications included or
      not, to decide.

- [x] **11.19 Inline reply does not work** (found 2026-10-31, with 11.15) — done
      2026-11-01, verified on the host, in the panel and on a toast: `inlineReplySupported` on the server;
      the card shows `NotificationReply` for `hasInlineReply`, with the sender's
      placeholder, and sends with `sendInlineReply`; an "inline-reply" action is never a
      button. The HUD takes no keyboard, so a toast's reply could not be typed in: Hud's
      `keyboardFocus` is OnDemand while any toast `wantsKeyboard` (its reply hovered or
      being written), None otherwise — clicking a toast still leaves the keyboard with
      the app. A toast with a reply being written does not count down. Escape clears
      the field. `Notifier`'s `inlineReply` option removed.
      Pre-existing. The card looks for an action with `id === "inline-reply"`, but
      Quickshell's actions have `identifier`, not `id` — so the reply field never shows,
      and the action, if sent, is an ordinary button. Even found, `invoke()` takes no
      text. Quickshell's way: `inlineReplySupported: true` on the `NotificationServer`
      (`singletons/Notifications.qml`), then `notification.hasInlineReply`,
      `inlineReplyPlaceholder` and `sendInlineReply(text)` in the card. Turning it on
      changes what apps offer (those that can reply would start sending a reply field),
      so it is a behaviour change to agree. Also `Notifier`'s `inlineReply` option passes
      `--inline-reply` to notify-send, which has no such option (libnotify 0.8.8); nothing
      uses it today.

- [x] **11.21 The music panel's player list** (requested 2026-11-01)
      Done 2026-11-01, verified on the host. Each player with its application's icon
      (`PlayerRules.desktopEntryFor`: the entry it names, else by name — Brave names
      none — else by bus name), a play button that pauses the other listed players
      (`Music.playOnly`; pause while it plays) and a hide button; hidden players by name
      in `media.hiddenPlayers` (per profile, written by `Profiles.writeInEffect` into the
      profile that sets it, else Full), under a "Hidden (n)" expander, shown again with an
      eye; never made active by themselves. playerctld left out (a proxy: it listed the
      last player twice, and a pause sent to it would reach the player just started).
      The visualiser listens only while the shown player plays (cava hears every
      player). `MusicPanel` split: `panels/music/{CoverArt,PanelVisualizer,PlayerList,
      PlayerRow}.qml`; tests `tests/PlayerRulesTest.qml`.

- [x] **11.22 Sliding between players in the music panel** (requested 2026-11-01)
      Done 2026-11-01, verified on the host: a view per player (`PlayerView`: cover row
      and track, bound to its own player — `CoverArt` reads `player.*`, not the active
      player), two of them taking turns in `PlayerCarousel`, the one coming in from the
      side of the list it is on, a change mid-slide carrying on from where the views are;
      the cover turns, and its ring moves, only for a player that plays. The seek bar,
      transport and the panel-wide visualisers stay put. Found on the way: the seek bar
      had always been 0 px tall (Layout properties only, in a Column).

- [x] **11.25 Battery widget and popup** (requested 2026-11-08) — done, verified on the
      Framework. A bar widget (charge icon, percentage beside it or not, colour
      thresholds in hex), and its popup: charge, time left, power drawn, the power profile
      with an override kept until the next change; UPower's history as a graph (charge,
      charger stretches, power), a stretch picked by dragging across it; use per app,
      estimated from CPU and GPU use (`EnergyRules`, recorded in the background on battery
      in 5-minute buckets). [plans/battery-popup.md](plans/battery-popup.md).

- [x] **11.26 Tablet mode as a profile condition** (plans/touch.md stage 1) — done,
      verified on the Framework: Hyprland's switch bindings call `ipc call tablet set`,
      `singletons/TabletMode.qml`, the fact `input.tabletMode`; kept in memory, not the
      config. The "Tablet" profile itself is the user's to make in the settings.

- [x] **11.27 Bluetooth on or off is remembered** (requested 2026-11-08) — done: the
      shell restores it at start.

- [x] **11.28 The Google client built in, and a site** (requested 2026-11-08) — done: a
      scrambled built-in OAuth client (own credentials still possible); the homepage and
      privacy policy in `site/`, published to GitHub Pages by Actions.
- [x] **11.33 Wallpapers managed by the shell** (requested 2026-11-11, for the Framework
      12) — done 2026-11-12: the shell draws them on the background layer (Settings →
      Wallpaper): an image or a folder (to a depth), by you, at random (no repeats,
      interval, Shuffle by button or IPC) or by weekday; one for all screens, each monitor
      or each workspace, exceptions kept fixed; thumbnails opened per place; fit with a
      preview, background colour set or from the image's edge; a warning when another
      program draws a wallpaper. Transitions in the theme (slide with the workspaces;
      fade, zoom, slide, wipe, circle, dissolve, pixelate), nearby workspaces preloaded,
      copies resized to each screen in ~/.cache (libvips). Plan:
      [plans/wallpapers.md](plans/wallpapers.md). Left as an idea: a bar widget to shuffle.
- [x] **11.29 A keyboard button on the bar** and **11.30 The lock screen in tablet mode** —
      dropped from the shell 2026-11-12: they belong to the keyboard's project (oskbd),
      not the shell. What the shell can offer is a general command button (11.34), which
      can call the keyboard among other things.
- [x] **11.35 Authentication prompts: the shell as the polkit agent** (requested
      2026-11-12) — done 2026-11-12: `Authentication` + `polkit/AuthPrompt.qml`, a themed
      prompt over the focused screen (message, action, account, PAM's messages, a wrong
      password asked again). Decided at the first start (a known agent running → off; the
      shell registers → on), retried registrations, a probe telling an unknown agent from
      none, critical notifications when no agent answers or two collide (critical toasts
      now stay, outlined in the error colour). Settings → System → Authentication, with
      "Try the prompt". Verified on both machines by the user. Plan:
      [plans/polkit.md](plans/polkit.md).

- [x] **11.36 A System tab in the settings** (agreed 2026-11-12) — found done when the
      trackers were merged (2026-11-17): Settings → System holds Authentication and Network
      (`panels/SettingsWindow.qml`), no profile picker; the rule by who holds the value
      stands for later pages.
- [x] **11.37 Network management, the System tab's first page** (requested 2026-11-12) —
      found done when the trackers were merged (2026-11-17): Overview, Wi-Fi, Ethernet and
      VPN pages, the connection editor, VPN import (`panels/settings/Network*.qml`,
      `singletons/network/`). Plan: [plans/network.md](plans/network.md). Left: a QR code
      to join a network (`qrencode`), in the tracker's backlog.

## From next-steps.md (merged into the tracker 2026-11-17)

- [x] **Tailscale to completion** (order of 2026-11-15, steps 1–5): accounts, hostname,
      diagnostics; sharing (exit node, routes, tags) and Tailscale SSH; Taildrop; serve,
      Funnel, certificates, tailnet lock status, exit node per network; the module's bar
      widget. All in the module repository's CHANGELOG (Unreleased, 0.6.0).
- [x] The Tailscale page's "Tailnet" field showed an e-mail address for a personal
      tailnet — fixed: `TailscaleRules.tailnetName` skips e-mail-like names.

## Test split — tracker step 10 (done 2026-11-17)

Plan: [plans/test-split.md](plans/test-split.md). Verified on the NixOS machine (tools
from `nix`) and on the Arch machine (tools from the system).

- [x] **The runners take named suites; the unit and module suites run without `nix`**
      (`tests/lock/resolve.sh`: one source of tools for a run, nix or the system;
      `tests/resolve-selftest.sh`).
- [x] **The lock bed with the system's tools**, the whole bed on Arch; it takes the
      machine-wide lock itself and scrubs its own environment.
- [x] **System detection behind a seam**: `scripts/lock-auth-methods.sh` decides which
      system it is on in one place (`H2S_LOCK_SYSTEM=nixos|other`, counted only together
      with `H2S_LOCK_SYSTEM_PAM_DIR`), and answers the shell's fallback probe too
      (`--fallback-facts`), so the script and `Lockscreen.qml` cannot disagree. The lock
      scenario `methods-script` runs both systems' answers on every machine, with the same
      checks.
- [x] **`tests/run-system.sh`**: a set per system under `tests/system/` (NixOS: the flake's
      package and its launcher, the layout; Arch: the package names of `install.sh`, the
      test tools' packages), the system read from `os-release`; an unknown system or the
      other system's check is status 2. `tests/run-system-selftest.sh`.
- [x] **`install.sh` under stand-ins** (`tests/install-test.sh`, the first half of 11.23):
      a private `PATH` and home, no new privileges; `install.sh` itself needed no change.
      The second half (a first start in an empty home) stays in the backlog.
- [x] **`tests/run-all.sh`**: the general set and this system's set in one command, the
      summary naming what passed, failed and was not run; `--quick` without the lock bed.
      `tests/run-all-selftest.sh`.

## Found during the test split (2026-11-17)

- [x] **The supervisor spun after the shell was killed** (`scripts/launch.sh`,
      `wait_for_shell`): `wait_for: No record of process <pid>` without end, the shell never
      started again. Cause: bash 5.3's `wait -f` reads a freed record for a child killed by
      a signal and spins inside bash. Fixed: plain `wait` and a paused loop;
      `tests/launcher-selftest.sh`.
- [x] **Modules stayed `pending` after a supervisor restart** (lock scenario
      `modules-launcher`). Cause: a module with no files to check was settled but never
      applied. Fixed in `singletons/ModuleHost.qml`.

## API plan and the work around it (2026-11-17 to 2026-11-19)

Moved from the tracker's "Now" on 2026-11-19, in full, oldest first. The slice codes
(S0, A4, U2 …) are the slice table in [plans/api-next.md](plans/api-next.md) §7. "Left
open" points that are still work or a known risk are also in the tracker, grouped by area.

The tracker's state paragraphs as they stood when these moved:

> State on 2026-11-17: everything is merged to `master` (core) and `main` (module
> `h2s-shell-tailscale`, version 0.6.0, module API 1.3) and runs on the NixOS machine.
> Development moves to the Arch machine; runs that need `nix` go over SSH to the NixOS
> machine. How sessions work is in [workflow.md](workflow.md).
>
> State on 2026-11-17, end of the session on the Arch machine. One topic at a time from here
> (the owner). The test split is done; the next topic is the API plan's implementation
> (index [plans/api-next.md](plans/api-next.md)): the theme token test, the
> `ModuleRules.qml` split and the version gate (first batch), the file chooser trial and
> the bordered buttons (second), pills in three sizes and the public button (third), the
> other public elements (fourth), the command runner and the module host on it (fifth) are
> on `master` (below). The elements lane is done but for a module's icon (U7a). The first
> four batches were not reviewed by a second agent and ran on the Arch machine only; the
> fifth and sixth were reviewed and ran on both machines. The test seams moved out of the
> installed shell into a test tree (below). Module test mode (A3), privileged start (A4) and
> the prompt saying who and what for (A5) are on `master` (below). The commands lane is done
> with helpers (C1) and the notification (A6). System facts (C2) are on `master`. The
> module's M2 and M3 are on its `main` (below): its privileged runs show the full prompt.
> B1, D1 and E1 are on `master` (below): the facts lane is done. P1 and P2 are on `master`:
> the dependencies lane is done. U0, U1a, U1b of the places lane are on `master` (below).
> U2 is on `master` (below). Next: U4a–U7b, then the remaining module slices.

- [x] **API plan, first batch**: on `master` (three commits, reviewed later, see "Review of the first four batches"): the theme token test (T0, `tests/ApiThemeTokensTest.qml`), the
      `ModuleRules.qml` split into five files (S0, a pure move), and the version gate (A0:
      `ModuleRules.apiFloor`, `apiCompatibility` with the floor, `deprecations` in a
      module's status, the CHANGELOG ↔ `apiVersion` test). Run on the Arch machine only
      (system tools, not pinned); not run on the NixOS machine. Next per the index: the
      file chooser trial (E0), then the lanes that S0 and A0 open — the command runner
      (A1), the shared module object (B1), helpers (C1), the anchor rules (U0), a module's
      icon (U7a) — and, with no dependency, pills in three sizes (T1) and the bordered
      buttons (F1a). Left open by this batch:
  - `deprecations` is in the status (`ModuleMergeRules.statusOf`) and the wording is
    `ModuleRules.deprecation(what, use)`, but the host passes none yet: nothing is
    deprecated before F4 and P2. The first of those adds `record.deprecations` in
    `ModuleHost.qml` with its test. There is no Settings → Modules page to show the list
    on; `modules list` prints it.
  - S0 followed `versioning.md` ("the pure split, nothing else; `ModuleRulesTest`
    unchanged"), not the two extras of `architecture-cleanup.md` §2.1: the suite is still
    one file (only its qualifiers changed), and the tokenizer cases named there (template
    strings, `"` inside `'…'`, `//` in a string, a `/` that divides) are not added.
  - S0 made the shared readers public as the plan says (`isObject`, `isString`, `has`,
    `get`, `show`), and `isNumber` with them: `ModuleRules.settingValueProblem` and the
    manifest check both use it, so it could not stay private to one file.
  - The plans and notes still name the functions by their old home
    (`ModuleRules.statusOf`, `ModuleRules.allowedImports`, `ModuleRules.precedence`, …):
    they are in `ModuleMergeRules`, `ModuleSourceRules`, `ModuleManifestRules` and
    `ModuleFileRules` now. Slice rows that say "`ModuleRules` (import check)" mean
    `ModuleSourceRules`.
  - A floor of another major than the shell's is not designed (the plan has no 2.0): the
    rule compares major then minor, so a floor above the shell's version lets nothing
    load. `ModuleRulesTest` asserts that the floor is of the shell's major and not above
    its version.
  - Seen, not touched: the unit run logs "[NetworkEvents] nmcli monitor exited,
    restarting in 1000 ms" — the unit suites start `nmcli monitor` (it exits at once in
    the private session). Worth a look against the rule that tests never touch a real
    daemon.
  - Seen, not touched: `api/ThemeTokens.qml`'s header says "Part of the module API 1.0";
    the list is now pinned by the test, the header does not say so.

- [x] **API plan, second batch**: on `master` (reviewed later, see "Review of the first four batches"): the file chooser trial (E0; the finding is in
      [plans/api-next/facts.md](plans/api-next/facts.md) §3.9) and the bordered buttons
      (F1a: `ThemeRules.buttonLook`, `SmallButton`, `DeleteButton`, the theme groups
      `warningButton` and `successButton`, `tests/ButtonKindsTest.qml`). Run on the Arch
      machine only; not run on the NixOS machine. Left open:
  - **The file chooser (E1): the system's standard dialog** (the owner, 2026-11-18; see
    "Decisions"). No chooser of the shell's own, and sending files is not extended now.
    What the trial found stands: Qt's own dialog, the one this machine and the test bed
    get, opens only with a visible window of the shell as its parent (one transparent
    layer-shell pixel is enough), takes the keyboard, can be closed by the shell — and
    returns one file, never several. The portal's dialog returns several and needs no
    parent, but the shell cannot close it (a lock, a module turned off), and a user gets
    it only where their Qt platform theme says so. §3.9 of `plans/api-next/facts.md` is
    brought in line when E1 is built (`openMany` and "a lock closes it" hold only for
    one of the two dialogs). Still to confirm with the owner: whether "the system's
    dialog" means whichever the platform theme gives, as the module does today (the
    lead's reading), or Qt's own everywhere.
    By hand, not done: Ctrl+click on two files in Qt's own dialog; "Open" in the
    folder dialog with nothing chosen (from code it returned the first folder listed, not
    the one shown).
  - The module's "send files" and the core's two dialogs (VPN import, wallpaper) are plain
    `FileDialog`s inside a settings window: they open, with whichever dialog the platform
    theme gives; with Qt's own, "send files" sends one file per pick.
  - **A question in the confirm colour is hard to read** on the built-in theme: "Connect"
    on a network's card and "Turn on" for a hotspot now ask in `Theme.confirm` (dark green
    on the surface), as the plan's §4.9 says for a `primary` that asks. For the owner's
    eyes: keep, or another colour for that question (the plan names none).
  - The Controls page's two new section titles ("Warning buttons", "Success buttons") and
    the CHANGELOG line are this batch's wording, not the owner's.
  - F1a touched three files its row does not name, as the wiring of a theme group needs:
    `singletons/Theme.qml`, `panels/SettingsWindow.qml` (the page's draft groups),
    `panels/settings/ControlsShapeSettings.qml`. The internal `saveChange` and `cancel`
    kinds ask in `confirmSecondary` and as `normal`; the plan does not say, and nothing
    uses them that way.

- [x] **Test speed**: done — the lock bed's runner takes the machine-wide lock itself, the
      nix tool lookup is remembered; the whole lock bed takes about three minutes on either
      machine.

- [x] **Test split** ([plans/test-split.md](plans/test-split.md)): done — a general set
      that runs on NixOS and on Arch, a set per system (`tests/run-system.sh`), and one
      command before committing (`tests/run-all.sh`). Notes in "Test split — tracker step 10" above.

- [x] **API plan, third batch**: on `master` (2026-11-18, reviewed later, see "Review of the first four batches"): pills in three
      sizes (T1: the theme's `pill` group with 22, 26 and 30 px, `Pill.size`,
      `tests/PillSizesTest.qml`) and the public button (F1b, module API 1.4:
      `api/SmallButton.qml`, `ApiElementRules`, `tests/ApiElementsTest.qml`). Left open:
  - **A test of the released Tailscale module fails** under `tests/run-modules.sh`: "its
    end date — expected 1802606400000, got 0" (the suite on serve, certificates, lock,
    exit node per network). The agent reported the same on `master` before this batch;
    the lead did not check that. The module's other suites pass. To look at before the
    module's next slice.
  - `Pill.minimumHeight` stays, writable, defaulting to the size's height: the released
    module sets `minimumHeight: 26`. It goes when the module is off the shell's
    internals (M10) or with the closing slice (Z).
  - The internal `Pill` defaults to `s`, so the pills that set no height stay 22 px; the
    public `Pill` (F2) is to default to `m` and has to map that.
  - The plan counted 21 pills with a height in pixels; there were 19 (9 of 24, 9 of 26,
    one of 30).
  - A public button that asks keeps its own width in a layout (inside it is
    `DeleteButton`, a `Row`) and ignores `checked`; said in the `Api.qml` header.
  - `qs.api` and `qs.components` both have a `SmallButton`: the import written last
    wins (pinned by a test). Ends with F4 and M10.
  - "The mark" in F1b's row of the plan is not built: §4.9 does not describe it for a
    button, and `PrivilegedMark` is a public element of its own (the lead's call; the
    owner was told).
  - The tooltip of a button that asks is tested as a passed-on property only, not as
    shown under the pointer.
  - Seen, not touched: `Math.max(22, …)` for a pill's width in
    `panels/calendar/RecurrenceEditor.qml`.

- [x] **API plan, fourth batch**: on `master` (2026-11-18, reviewed later, see "Review of the first four batches"): the public
      controls (F2, module API 1.5: `Dropdown`, `InputField`, `Pill`, `Checkbox`,
      `ToggleSwitch`, `PrivilegedMark` under `api/`), rows and texts (F3, 1.6: the new
      `components/SettingsRow.qml` and `ExpandingRow.qml`, `api/SettingsRow.qml`,
      `ExpandingRow.qml`, `Notice.qml`; plain text in the shell's headings, hints, section
      titles, schema editor and page list), the base types (F4, 1.7: `PopupWidget`,
      `BarText`, `BarRow`, `PointerArea`, `VpnProvider` under `api/`;
      `ModuleSourceRules.importDeprecations`, and `ModuleHost` passes a module's
      deprecations into its status). `modules list` now shows for the Tailscale module
      "import qs.components (in 17 files): use the elements of qs.api (goes with the
      shell's next tightening)" — the agent's wording, not the owner's. Left open:
  - **For the owner's eyes, when the module first uses them** (M7): the look of the
    public `SettingsRow` and `ExpandingRow` is the agent's reading of a card's rows (value
    right-aligned, at most 220 px; no hover look on the opening line; content not
    indented). Nothing was looked at on a screen.
  - **For the owner to decide before M10:** the public `Pill` has the small font at every
    size, as the shell's pills; the module's pills have body-size text today and get
    smaller text when it moves.
  - **A defect in the module, to fix with M10:** in three places (`ServeSection.qml`
    twice, `TailscalePopup.qml`) it sets a `PrivilegedMark`'s `visible` to
    `need !== ""`, which shows the lock also for `need: "yes"` (no password asked). The
    lead read this in the module's code. With the public mark, a module that sets
    `visible` itself also keeps the layout's spacing around an empty mark; said in
    `Api.qml`.
  - The public `SettingsRow` has no anchor: the anchor blocks (U0, U1a) do not exist yet.
    The places lane puts it on that base.
  - `SettingsRow` and `ExpandingRow` each pin one name the plan does not list
    (`controls`, `content`): a default property needs a name. For the base types the plan
    gives no list of names; the ones pinned are in `pinnedBase` in `ApiElementsTest`,
    checked as present, not as the full set.
  - `InputField`'s typing signals are tested by emitting them from the inner input, not
    by key presses.
  - Every public control shares its name with a `qs.components` type; in a file that
    imports both, the import written last wins. Ends with M10.
  - `tests/run-modules.sh` does not fail on a deprecation (an error only from Z), and
    `tests-modules.qml` prints a module's deprecations beside its warnings.

- [x] **API plan, fifth batch**: on `master` (2026-11-18; reviewed by a second agent on
      the diff, two medium findings, both fixed by the author; `tests/run-all.sh` passes
      on Arch, tools from `PATH`, and on NixOS, tools from nix): the command runner (A1,
      module API 1.8: `singletons/io/CommandRunner.qml`, `CommandRules`, `CommandTools`,
      `api/CommandRunner.qml`; `CommandAction`, `CommandQuery` and xdg-open run through
      it) and the module host's four checks on it (A1b). Left open:
  - **For A4 (privileged start), answered there (the trusted `timeout` inside pkexec):** a
    run with a limit starts as
    `timeout -k … setpriv --pdeathsig KILL -- <command>`, so the command dies when
    `timeout` is killed. The kernel drops that request for a setuid program: a `pkexec`
    run is not protected by it and needs its own answer.
  - Without `timeout` or `setpriv` a run is not wrapped; the runner's own watchdog keeps
    the limit. A process stuck in uninterruptible I/O then delays the answer.
  - A run with a limit whose command exits 126 or 127 reads as `failedToStart` (inside
    `timeout` a missing program looks the same); said in the `Api.qml` reference.
  - A module's `onStdout` / `onStderr` get whole lines, not raw chunks (a character cut
    by a read boundary was decoded as two U+FFFD otherwise). An output that ends in an
    empty line shows one empty line too many: Quickshell 0.3.2's line parser holds an
    empty line back and prefixes it to the next piece, and `CommandRules.linesOf` cannot
    tell the two cases apart. Worth a note under `notes/upstream/`.
  - `maxOutputBytes` counts characters, and also caps a single line.
  - The start guard's script gets the shell's process id as an argument
    (`ModuleFileRules`), since `$PPID` is `timeout` inside the runner. `Lockscreen.qml`
    uses `$PPID` in a script too: the same change when its probes move to the runner.
  - `ModuleHost._clearGuard` still uses `execDetached` (not one of the four blocks).
  - An orderly quit of the shell with a run in flight has no test of its own: covered
    only by the unit case that kills `timeout` with KILL from outside. A reload in place
    is covered by the lock scenario `modules-reload`, which passed without the fix too.
  - No test hangs the lookup of `timeout` itself or the stores' directory check.
  - A `CommandAction` whose program cannot start is answered with an error now; before,
    its queue hung.

- [x] **API plan, sixth batch**: on `master` (2026-11-18; reviewed by a second agent on
      the diff, four findings in the trust verdict, all fixed by the author with a failing
      case each; `tests/run-all.sh` passes on Arch, tools from `PATH`, and on NixOS, tools
      from nix): program lookup with trust (A2, module API 1.9: `module.programs`,
      `optionalPrograms`, `ModuleRules.programProbeScript` / `programWalk` /
      `programVerdict`; `CommandTools` takes the first trusted `timeout` / `setpriv` on
      `PATH`, the fixed-directory stand-in is gone) and one reader for the test seams
      (A2b, `TestSeams`, no API change). Left open:
  - The verdict walks the path component by component (as `namei -l`), judging the
    directory that holds each link; it is stricter than the plan's wording.
  - A required program found but untrusted does not stop the module: it shows
    `trusted: false`. Only a missing required program gives `missing-program`.
  - A PATH entry the user chose that points straight into a root-owned Nix store
    (nix-shell, direnv) is trusted: the user picks what runs, though nobody can change it.
    The store counts as root's only when `/nix/store` is root's and not writable by the
    user (a single-user install is judged path by path).
  - The probe runs as `/bin/sh` with a fixed PATH (`/run/current-system/sw/bin:/usr/bin:/bin`,
    `ModuleRules.probeToolPath`); the PATH judged is an argument. A system with its tools
    elsewhere would find none.
  - A recheck that does not answer in time keeps the old path but marks it untrusted, so a
    slow wake does not unload the module. Relative and empty PATH entries are skipped.
  - The NixOS cases (system profile into the store, `~/.nix-profile`, the `/run/wrappers`
    setuid `pkexec`) are unit cases on made-up probe output; the real probe ran on both
    machines only through the suites' fixtures.
  - `ModuleHost.programEnvironment` (the lookup's PATH) is a property for the suites.

- [x] **Test seams in a test tree** ([plans/test-seams.md](plans/test-seams.md)): on
      `master` (2026-11-18; the owner chose the test tree over the gate of
      `architecture-cleanup.md` decision 7.5, and asked that how test runs work be well
      documented: `docs/ARCHITECTURE.md` "Testing", `tests/lock/README.md`. Reviewed by a
      second agent on the diff: no defect in production paths, one in `tests/test-tree.sh`,
      fixed by the lead; `tests/run-all.sh` passes on Arch, tools from `PATH`, and on
      NixOS, tools from nix). The production `singletons/TestSeams.qml` and
      `scripts/seams.sh` are constants; the readers live in `tests/lock/seams/` and
      `tests/test-tree.sh` copies them over the production ones (the lock bed builds its
      copies through it). Also: `ModuleHost.testMode` from `TestSeams.moduleTestMode`
      (O3), the Lockscreen child-order test (L1, `LockscreenShapeTest`), the `locktest`
      reload IPC in the test seam file (O4). Left open:
  - The by-hand recipe in `tests/lock/README.md` ("The test tree": a nested labwc, a
    private runtime and config directory) was never run; the agent could not use the
    screen. Try it once before relying on it.
  - In a test tree module test mode is always on (a constant in the test seam file), not
    switched by a variable.
  - `TestSeamsShapeTest` finds code that reads a seam variable by its literal name
    (`Quickshell.env("H2S_…")`, `$H2S_…`); a read through a computed name would pass.
    `Lockscreen` and `VpnManager` still name the variables in log strings.
  - O6 (the lock's `gdbus` / `systemd-inhibit` from the trusted lookup) is not built.
  - Seen once, not this branch's code: `CommandRunnerTest` "killAfterMs after the limit
    (499 ms)" failed in one run on Arch and passed three times alone — a timing margin.

- [x] **API plan, A3 module test mode**: on `master` (2026-11-18; module API 1.10; reviewed
      by a second agent on the diff, three findings — a module could switch test mode on
      through `module.host`, a stand-in could be a link to the real pkexec, the guard read
      only argv[0] — all fixed by a second author with cases; `tests/run-all.sh` passes on
      Arch, tools from `PATH`, and on NixOS, tools from nix; the Tailscale module's suites
      pass as on `master`). `ModuleHost.testMode` is fixed once by `setTestMode()` before
      the first load naming a module directory (`tests-modules.qml`; `Modules` only when
      `TestSeams.moduleTestMode`), read-only after. Manifest `testPrograms` (inside the
      module, links resolved, setuid refused); `Api.openUrl` and `Notifier` record in test
      mode; no pkexec but a `<testPrograms>/pkexec` anywhere in a module's command;
      `ModuleTestKit` in `qs.tests`; `tests/run-modules.sh` puts a failing pkexec first on
      `PATH`. Left open:
  - **Transitional gate (the owner's decision):** a module below API 1.10 in test mode may
    put its own stand-in, wherever it lies, into `PrivilegedAction.elevate` (the released
    Tailscale module keeps its in `tools/stand-in/`); a system pkexec or a setuid file is
    refused, a failed probe counts as real. Shown in the module's `deprecations`; removed
    in slice Z (`plans/api-next/migration.md`). Which module called is read from
    `new Error().stack` at `run()` — a heuristic; with no module frame the strict rule
    applies. The module drops it by moving its stand-ins under `module/`, declaring
    `testPrograms` and API 1.10, taking `elevate` from `module.programs.pkexec.path` and
    dropping its `H2S_TEST_MODULES` / `H2S_TAILSCALE_TOOLS` reads (M2).
  - In the lock bed `Notifier` records too, so the shell's own notifications are not sent
    there.
  - The guard looks at the program words of a command; a `pkexec` inside a script string,
    `refuse: null`, or a raw `Process` gets past it. Mistakes, not a sandbox.
  - A module may use another module's `<testPrograms>/pkexec`.
  - A module in test mode without `testPrograms` keeps the normal PATH lookup (the lock
    bed's fixtures rely on it).
  - `ModuleHandle.host` is still handed to modules (renamed in Z); nothing on it changes
    the mode.
  - Left for later slices: `ModuleTestKit` anchors, chooser, `setSystem`, `setNow`;
    privileged runs through `<testPrograms>/pkexec` (A4, done).
  - `/run/wrappers/bin/pkexec` as a link target was refused on Arch only because it does
    not exist there; not exercised on NixOS beyond the full run.
  - Seen once, not this change: unit suites failed with `TypeError: Cannot read property
    'windowShown' of null` from QtTest's `TestCase.qml`; passed alone and on rerun.

- [x] **API plan, A4 privileged start**: on `master` (2026-11-18; module API 1.11; reviewed
      by a second agent on the diff, eight findings, all handled by a second author with
      cases that fail before the fix; `tests/run-all.sh` passes on Arch, tools from `PATH`,
      and on NixOS, tools from nix; the Tailscale module's suites pass against it).
      `module.privileged` (`available`, `unavailableReason`, `start`) on the handle; one
      shell-wide queue `singletons/PrivilegedRuns.qml`; pure rules in
      `singletons/PrivilegedRules.qml` (not `PolkitRules.qml`, which only gained
      `deniedNotice`); `PrivilegedAction` runs through the same queue; fixture
      `tests/fixtures/modules/privileged` (suite `PrivilegedRunsTest`) is its own part of
      `tests/run-all.sh`, not in `--quick`. Review findings fixed: argv (and options) read
      once into a plain copy at the boundary — an accessor/Proxy argv got `/bin/sh` past
      every refusal (high; also in `CommandRunner`'s test-mode guard and the legacy path);
      U+2028/2029 unprintable; the legacy default `elevate: ["pkexec"]` takes the trusted setuid
      pkexec outside test mode; the queue's clock is monotonic (`ElapsedTimer`). The two
      points left open before:
  - **pdeathsig and setuid:** pkexec gets `<pkexec> <trusted timeout> -k 3 <limit> <argv…>`;
    nothing is wrapped around pkexec. `cancel()` sends TERM (ends pkexec while it asks);
    once the command runs as root it ends at its own limit. Pinned by the fixture suite.
    Quickshell 0.3.2's `~Process` kills and never waits (read in its source), so a reload
    during a root run does not block; the `QProcess` leaks until the child exits.
  - **The gate for modules below 1.10:** unchanged; the queue repeats the test-mode check
    per run. `module.privileged` has no gate: in test mode only `<testPrograms>/pkexec`,
    without one `available` is false.
  - **The command is not parsed** (the owner's decision, 2026-11-18, "Decisions"): after a
    first round that refused undeclared or untrusted programs, shells, launchers and
    interpreters, the refusals were cut to argv[0] an absolute existing executable
    (`notFound` otherwise), printable words, a `what`, not while locked. Reviewed on the
    diff (docs claimed the A5 prompt and the enable warning as built — fixed; `start()`
    not checking `trusted` now said; a test-mode pkexec word through `module.privileged`
    pinned). Documented in `docs/ARCHITECTURE.md` "Modules" and `Api.qml`. A module must
    itself pass only a program whose `module.programs[name].trusted` is true.
  Left open:
  - `CommandRunnerTest` fails one check about once in 20 runs, alone too, on a branch that
    did not touch it; which check is not known (also "Seen once" under the test seams).
  - **For A5 (done there, see A5):** with the agent `active` or `conflict`, any polkit request seen while the
    head asks counts as the head's (also a foreign one, or one open at launch) until
    `PolkitRules.announces`; a run whose pkexec has started is left to its prompt when the
    session locks (only waiting runs end `locked`); the prompt's lines. With any other agent
    state the head is held until the run exits, at most 2 minutes. A6 sends its
    notification from the queue's launch step; `ModuleTestKit.setPolkitAgent` exists.
  - `timeoutMs` starts when the command runs as root: a prompt left open is not bounded and
    holds the queue (said in `Api.qml`). `timeout`'s own 125/126/127 read as failure,
    dismissed, refused (said; the check just before launch makes 127 rare).
  - The legacy `PrivilegedAction` has none of the refusals (until Z), and an explicit path
    in `elevate` outside test mode runs as given. It is not yet listed in a module's
    `deprecations` (needs a scan of where the type is used).
  - The lock state is `Profiles.screenLocked`, not `Lockscreen.locked` (reading
    `Lockscreen` would create it in the suites). pkexec is looked up once.
  - Two small races: an answer made just before a module is turned off and on within one
    event-loop turn is delivered; a request opening and closing within one turn is missed
    (the head then releases by the 2 s rule).
  - The non-test-mode legacy pkexec swap, the monotonic clock, the real pkexec, the NixOS
    wrapper, pkexec on TERM and the real agent's flow were not exercised: suites run in
    test mode on stand-ins only. The fixture's timing windows (1.5–4.5 s around the 2 s
    release) may flake under heavy load.

- [x] **API plan, A5 the prompt says who and what for**: on `master` (2026-11-18; no API
      bump, user-visible: CHANGELOG "Unreleased"; reviewed twice by a second agent on the
      diff — first round eight findings, second round three, all fixed by other authors
      with cases that fail before the fix; `tests/run-all.sh` passes on Arch, tools from
      `PATH`, and on NixOS, tools from nix; the Tailscale module's suites pass against it).
      `PolkitRules.announcement` makes every text (Module, Authorization, Command, and the
      summary/body A6 sends); `polkit/AuthAnnouncement.qml` in `AuthPrompt.qml`: Module and
      Authorization lines, "Command" closed for every request, opens on a click, focus
      stays in the password field; all prompt texts plain. `PolkitRules.announces`: the
      text between the first and last quote mark of pkexec's message equals the head's
      `cmdline_short` (pkexec.c: args joined by spaces, past 80 bytes 38 + " ... " + 37),
      read in polkit's source 126–128 and all 28 translations. The decision is made once
      per flow object. Only the head's own request holds it without bound; another
      program's open request holds it at most 2 minutes from launch and never releases it.
      On lock the open request is cancelled (any, not only the shell's) and the prompt is
      not shown while locked. Left open:
  - **Read by hand on Arch (2026-11-18, polkit 128, English):** the shell's prompt showed
    "Authentication is needed to run `/usr/bin/true' as the super user", as the matcher
    expects (backtick, apostrophe). Still to read on NixOS. A run from a module through the
    queue has not been seen on a real prompt.
  - **polkit's limit, documented:** past 80 bytes another command with the same first 38
    and last 37 bytes (another program's too) gets the same lines. Not fixable from the
    flow, which carries only message, action and cookie. Consistent with the trust
    decision.
  - Legacy `PrivilegedAction` runs with a relative program, or with pkexec options in
    `elevate`, are not announced (shown as today).
  - A Georgian message is never announced: polkit's `ka.po` misspells `$(cmdline_short)`.
  - The run whose pkexec was asking at lock ends as pkexec reports it (`dismissed`), without
    `blocked: "locked"`. The "Module" line elides the name first; an id too wide alone
    elides in the middle.
  - Right-to-left words are isolated (LRI/PDI) in the shown command; checked as a string,
    not on screen. A request that opens and closes within one event-loop turn is missed.
  - `ModuleTestKit` gained polkit seams (`setPolkitRequest` with a command or a foreign
    `{ actionId, message }`, `pkexecMessage`, `polkitRequestOpen`, `polkitAnnouncement`),
    listed in the unreleased `- 1.11:` line.

- [x] **Review of the first four batches**: on `master` (2026-11-18). Two reviewers on the
      diffs of T0, S0, A0 (no defect: S0 confirmed a pure move, the version gate numeric)
      and F1a, T1, F1b–F4 (no high finding); fixes by another author with cases that fail
      before; the new file scan reviewed once more and fixed; `tests/run-all.sh` passes on
      Arch, tools from `PATH`, and on NixOS, tools from nix; the Tailscale module's suites
      pass. Fixed: the public `SmallButton`'s `asking` follows a binding and either
      declaration order; module text one line and capped at 80 characters in the public
      elements (`ApiElementRules.oneLine`), the internal `Pill` and `DeleteButton` one line;
      the public `Dropdown` drops an option's `color`; a disabled `ToggleSwitch` and an
      unavailable asking "×" are dimmed; `importsOf` reads imports on the first `{` line;
      the import check scans every `.qml` under a module (at most 100 files, 8 directories
      deep, no links, no other file systems, required files first so a slow scan only
      warns, "imports not checked in N files" when incomplete, warnings capped 5 per file
      and 50 per module); a floor test that can fail; no Settings → Modules page claimed.
      Documented: the public `checked` shows only on `secondary`. Left open: the hover
      contrast of warning/success buttons ("Open points"); a quoted import holding `{` is
      still missed by `importsOf`.

- [x] **API plan, C1 helpers and A6 the notification**: on `master` (2026-11-19; module API
      1.12; each reviewed by a second agent on the diff, fixed by other authors with cases
      that fail before; `tests/run-all.sh` passes on Arch, tools from `PATH`, and on NixOS,
      tools from nix; the Tailscale module's suites pass). C1: `Api.format` (bytes, rate,
      ago), `Api.address` (`singletons/AddressRules.qml`: isIpv4/isIpv6/isIp/parseCidr/
      contains/overlap/redact; `NetworkRules` delegates — IPv4 with leading zeros now
      refused, as `inet_pton`), `Api.minuteNow` (+ `ModuleTestKit.setNow`, reset per
      suite), `module.log(level, text, key)` (dedupe by key and level, 256 keys, cleared
      on module off), `format: "plain"` notifications (one line, Cc/Cf dropped, caps 200/
      1000, body escaped after the cut); a module can no longer send the shell's
      `x-qs-*` categories; the shell's toast and notification card show plain text;
      `redact` handles ports, brackets and `::` in identifiers; emoji are never cut
      (`PrivilegedRules.characters`; `Array.from` splits surrogate pairs in this engine,
      `for…of` does not); `tests/run-modules.sh` fails when the suite count is missing.
      A6: with another polkit agent (state `other`, `blocked`, `deciding`, `none`) a run
      reaching the head sends one plain notification "Module: <name>" / "Authorization:
      <what>" just before pkexec (`PrivilegedRules.launchNotice`). Review found an older
      defect, fixed: a legacy `PrivilegedAction` run with the default `elevate` waiting for
      the pkexec lookup survived a lock and launched pkexec while locked, and could launch
      beside the next run; it now waits in the check step (`legacyCheckWaits`). Test seam
      `testLookupHeld` (test mode only) and `tests/PrivilegedLookupSeam.qml`. Left open:
  - A legacy run's notification reads "Module: Not named" with no body (as the plan says);
    urgency and app name are the defaults ("H2S Shell").
  - `deciding` (the first moments after start) counts as "the shell's prompt does not
    answer": runs then get the notification and the strict one-at-a-time rule.
  - The plain body is entity-escaped; a notification server without body markup would show
    `&lt;` literally.
  - Nothing was sent to a real notification daemon or seen next to another agent's prompt.
  - The lock scenario `restart-crash-locked` failed once in a full run on Arch and passed
    alone and in the next full run.

- [x] **API plan, C2 system facts and the data directory**: on `master` (2026-11-19; module
      API 1.13; reviewed by a second agent on the diff, fixed by another author with cases
      that fail before; `tests/run-all.sh` passes on Arch, tools from `PATH`, and on NixOS,
      tools from nix — one lock-bed failure there, the whole bed passed twice on rerun; the
      Tailscale module's suites pass; on the Arch machine the live shell made
      `~/.local/share/h2s-shell/module-data/tailscale`, 700). `Api.system` (user name,
      uid, host, home, XDG directories, runtime and download directory, `readIpForwarding()`,
      `refresh()`; `SystemFactsRules`, `io/SystemFactsReader`, `SystemFacts`; a failed read
      is `""` / `null`); `module.dataDirectory` made by the host before load: every part
      from the data home down checked (owner user or root, not group/other-writable unless
      root's and sticky, no links below the data home), `cd -P` then `chmod 700 .`; a root
      or module directory others could write before is refused (the module loads with
      `dataDirectory ""` and a warning); retried at each load and when a module is turned
      on. `ModuleTestKit.setSystem`, a private temporary data home in test mode. C2's own
      refusal of a privileged program inside the data root was removed (the owner's
      decision: the shell does not judge commands); the docs say nothing there may run as
      root. Left open:
  - When the data directory cannot be made the module still loads (`dataDirectory ""`, a
    warning); unknown uid is `null`; an unreadable `user-dirs.dirs` gives `""`, a missing
    one `~/Downloads` (the agent's reading of "a failed read is unknown").
  - No OS fact (NixOS/Arch) in `Api.system` (§3.7 lists none); the core's own
    `Quickshell.env("HOME")` uses were not moved onto `SystemFacts`.
  - The module's existing certificates live in `h2s-shell/tailscale/certs`; moving them to
    the data directory is module work (M5).
  - The test-mode temporary home is not removed by the shell (the runners remove their
    private runtime directory).
  - The lock scenario `restart-crash-locked` failed in three full runs today (Arch twice,
    NixOS once probably), each time passing alone: a flaky scenario to look into.

- [x] **Module M2 programs and test mode, M3 privileged with a `what`; core: an environment
      for privileged runs in test mode**: on the module's `main` and core `master`
      (2026-11-19; core module API 1.14, the module's manifest `api` 1.14, version still
      0.6.0, nothing released; M2/M3 reviewed by a second agent on the diff — no high or
      medium finding, fixes by another author with cases that fail before; the core slice
      reviewed by the lead; core `tests/run-all.sh` passes on both machines; the module's
      suites, `tools/test.sh` and its lock bed pass on Arch, tools from `PATH`, and on NixOS,
      tools from nix). The module declares `optionalPrograms` and `testPrograms`
      (stand-ins moved to `module/tests/stand-in`), takes paths and trust from
      `module.programs`, uses `Api.system` for forwarding and the download folder, drops its
      `H2S_*` reads and the transitional gate; every run as administrator goes through
      `module.privileged.start` with a `what` (the words are under "Open points"),
      `tailscale` must be trusted, results mapped by `TR.privilegedOutcome`, `blocked`
      reasons in plain words. Older defects fixed on the way: the Funnel check after a wait
      could ask for a password without a click (now it never prompts; a "Turn off Funnel"
      button does), and a dismissed prompt there notified. A login cancelled before it ran
      as root says "Login cancelled." Core: `options.environment` for
      `module.privileged.start`, taken in module test mode only (refused outside). Left open:
  - **For the core's `ModuleTestKit` (a later slice):** the module still has two test
    helpers the kit should replace — `module/tests/ScenarioHandle.qml` (per-scenario
    `module.programs` and "privileged unavailable", recording calls to the real
    `privileged.start`) and `module/tests/liveSuites.js` (the live suites register so the
    host suite waits before switching the polkit agent or turning the module off). Wanted:
    per-suite program overrides and suites that run alone or after the others.
  - The module's existing certificates stay in `h2s-shell/tailscale/certs` until M5.
  - Only `tailscale` must be trusted now; a user-writable `timeout` no longer marks the
    module "Not trusted" (the shell's own trusted `timeout` is used).
  - The full prompt on a real Tailscale run has not been seen yet (to look at on both
    machines).

- [x] **API plan, B1 the shared module object and popup inputs, D1 network facts**: on
      `master` (2026-11-19; module API 1.15 and 1.16; each reviewed by a second agent on the
      diff, fixed by other authors with cases that fail before; `tests/run-all.sh` passes on
      Arch, tools from `PATH`, and on NixOS, tools from nix — NetworkManager 1.56 there, 1.58
      on Arch, both accept the new fields; the Tailscale module's suites pass). B1:
      `module.main` (null while off or while the main is built; not writable through the
      handle — `moduleId` and `host` became readonly too), an `opener` `{ widgetType,
      preset, edge, byTouch }` for a module's popup panel that declares `property var
      opener` (decided by the same root-property scan at the first build and on reopen; a
      failed write goes to the module's status), `availableHeight` / `fitsShownHeight` /
      `popupAnimating` documented. D1: `Api.networksReady` (false after a failed read),
      `Api.networks` (Wi-Fi rows only after their details), `Api.vpnsUp` rows with
      `fullTunnel` / `setsDns` / `routes` (null when not read; `up` only when `GENERAL.STATE`
      says activated; WireGuard from allowed-ips, `peer-routes`, `ipv6.method`, the /1
      halves; routes beyond 256 unknown), `Api.localNetworks` + ready (from `nmcli device
      show` and `ip -j -6 address show` flags, deprecated IPv6 left out, VPN addresses left
      out, a /32 or /128 without a network), slot context `otherVpns`,
      `ModuleTestKit.setNetworks`; `singletons/io/LatestQuery.qml` (a newer request drops
      the answer under way) for the profile list, the VPN details and the devices. Left open:
  - **Seen in the live shell after the merge:** `IpManager.qml` called its child queries
    as `root._flagsQuery` / `root._devicesQuery` (ids, not properties): `Api.localNetworks`
    never became ready. Fixed on `master` (the reading is `DeviceAddressReading.qml`,
    `tests/DeviceAddressReadingTest.qml` runs it on stand-in `nmcli` and `ip`); the live log
    is clean after a restart. A new development rule in `CLAUDE.md` came of it (a real I/O
    path runs in a test against stand-ins).
  - A click on another bar entry of the same widget type closes its popup ("Open points").
  - `opener` is null when no bar widget opened the panel (tray, `open()` without data).
  - Docker/libvirt bridges in `localNetworks`, the `kind` words, `setsDns`'s meaning
    ("Open points"); the plugin VPN full-tunnel reading is unchecked on a machine.
  - A VPN that reports no addresses of its own cannot be told apart from the device it
    rides on (IPsec).

- [x] **API plan, E1 the file chooser**: on `master` (2026-11-19; module API 1.17; reviewed
      by a second agent on the diff, fixed by another author with cases that fail before;
      `tests/run-all.sh` passes on Arch, tools from `PATH`, and on NixOS, tools from nix —
      one earlier NixOS failure of the module fixture part was most likely the chooser test
      locking the privileged queue, fixed; the Tailscale module's suites pass).
      `module.chooseFiles(options, done)` → `{ open, cancel() }` (`open` / `openMany` /
      `folder`, title one line without `<>&`, `startDirectory`); one chooser for the whole
      shell (`busy`), never while locked, a lock closes it, module off closes it with no
      callback, a reload closes it (`onDestruction`); paths absolute; the dialog is the
      platform theme's, in a 1-px click-through layer-shell window
      (`singletons/FileChooser.qml`, `FileChooserRules`); `ModuleTestKit` chooser records
      (`answerChooser(moduleId, paths)`, `cancelChooser(moduleId)`, `setChooserLocked`),
      reset per suite; `tests/FileChooserTest.qml` drives the real dialog headless with
      keys. The unit run's limit for asynchronous suites is 90 s (was 60 s). Left open:
  - The by-hand checks and choices are under "Open points" (the file chooser).
  - A folder dialog opened in a folder with sub-folders selects the first one: accepted
    without a click, it returns that sub-folder (Qt; documented). With no sub-folders it
    returns the folder shown.
  - The `onDestruction` close has no test of its own (cannot be triggered in the unit run).

- [x] **API plan, P1 `exports` and `uses`**: on `master` (2026-11-19; module API 1.18;
      reviewed by a second agent on the diff, fixed by another author with cases that fail
      before, the lifecycle fix reviewed once more — low findings only; `tests/run-all.sh`
      passes on Arch, tools from `PATH`, and on NixOS, tools from nix, apart from one
      lock-bed scenario each time that passed alone; the Tailscale module's suites pass).
      Manifest `exports` `{ version }` with the main's `readonly property QtObject exports`
      (refused: the main, a non-QtObject, an object with a parent, a handle, the host);
      manifest `uses` `{ id: "major.minor" }` (same major, minor at least); `module.uses`
      frozen per module id, set before the module turns on, kept until it next turns on;
      state `missing-module` with reasons; cycles fail their members;
      `ModuleMergeRules.dependencyPlan`; the host creates providers first and destroys a
      provider only after its dependents' mains are gone (a watcher in each main,
      `_reap`). Fixtures `provider`, `consumer`, `provider-no-exports`,
      `provider-failing-main`, `provider-exports-handle`. Left open (low, for P2):
  - A dependent turned off and on in one event-loop turn: its going main reads the new
    `module.uses` (its clean-up acts on the new provider), and the old provider main lives
    one turn beside the new one.
  - A dependent's main deleted by something other than the host (or whose `destroy()`
    throws) leaves its provider waiting forever; the `catch` should drop the entry.
  - A dependent with no main and only views is not waited for (one turn).
  - A consumer's own suites under `tests/run-modules.sh` need the provider's directory too;
    the test kit is unchanged. The choices for the owner are under "Open points".
  - Lock-bed restart scenarios: `restart-crash-locked` failed now and then because of a race
    in Quickshell 0.3.2's crash handler (the crash reporter and the relaunch share one file
    position on the instance-info file; the second read gets nothing: empty config path,
    wrong "crashed within 10 s" decision). The scenario now accepts that branch as it
    already did for the first crash (`notes/upstream/quickshell-session-lock-unlock-notify.md`
    finding 5, upstream fix: `pread`); 5 full beds in a row on Arch and 3 on NixOS passed.
    `restart-kill-locked` failed once on NixOS (fingerprint conversation not within 5 s),
    not reproduced since; keep `LOCKTEST_KEEP=1` artifacts when it does.

- [x] **API plan, P2 reach closed**: on `master` (2026-11-19; module API 1.19; reviewed by a
      second agent on the diff, fixed by another author with cases that fail before;
      `tests/run-all.sh` passes on Arch, tools from `PATH`, and on NixOS, tools from nix;
      the Tailscale module's suites pass and its status is unchanged).
      `Api.moduleStatus(id)` (frozen `{ id, name, version, state, active }`); `Api.module(id)`
      and `module.host` listed in the calling module's `deprecations` (a source scan of
      every QML and JS file: comments, strings, regex literals skipped, template
      substitutions read; `ModuleSourceRules.codeText`, computed once per file); importing
      `qs.singletons` or a directory outside the module is an error in the status (it still
      loads), also through a script's `.import`. P1's low findings: a module turned off and
      on in one turn stays pending until its old main is gone; a main deleted elsewhere no
      longer leaves its provider waiting; the watcher holds the main from outside it. The
      scan is about 15× faster than before (1 MB in ~0.15 s on the host). Left open:
  - `name` from `moduleStatus` is the manifest's raw text: callers render it plain.
  - A handle kept under another name than `module` is not found by the scan.
  - A JavaScript reference to a deleted object never reads as null in this engine: the
    `!entry.main` branch in `_reap` never runs (only a throwing `destroy()` catches it).

- [x] **API plan, U0 anchor rules, U1a the host and the page block, U1b the General page**:
      on `master` (2026-11-19; module API 1.20 and 1.21; U0/U1a reviewed by a second agent
      on the diff, fixed by another author with cases that fail before; U1b reviewed, no
      defect; `tests/run-all.sh` passes on Arch, tools from `PATH`, and on NixOS, tools from
      nix; the Tailscale module's suites pass — it uses only the VPN slots, still slots).
      Manifest `anchors: [{ at, place, component }]`, `Api.anchors`; paths
      `<surface>.<view>[.<block>]…[.<region>]`; `components/AnchorBlock.qml` (path from the
      first `anchorBase` up the parents; only a `page` block is addressable as the base;
      `scopeId` for own-provider places), `AnchorContent.qml` (ScriptModel; shows nothing
      when the block's kind or placements do not fit the row), `SettingsPage.qml`,
      `singletons/Anchors.qml`; table rows carry `view`, slot aliases `needs`;
      `ModuleRules.slotAliasProblems` checks a published alias leaves no `ModuleSlot` behind.
      The settings window's page loader sets the base (`_showPage()`); the General page is a
      `SettingsPage` (rows at the same places, measured), the first row `settings.general`
      (append, `{ editIndex }`), the old General slot read through its alias. Left open:
  - The General page now scrolls and clips (before, overflow was cut off); an open list
    (icon theme, theme suggestions) stays put while the page scrolls under it, as on the
    other scrolling pages.
  - An element that came through an old slot reports errors under the anchor's name.
  - `editIndex` changes and the page's scrolling are not tested.
  - Spacing choices are under "Open points".

- [x] **API plan, U2 popups**: on `master` (2026-11-19; module API 1.22; reviewed by a
      second agent on the diff, no code defect; test fixes by another author; `tests/run-all.sh`
      passes on Arch, tools from `PATH`, and on NixOS, tools from nix; the Tailscale module's
      suites pass). `components/PopupSection.qml` (before / header / prepend / content /
      append / divider / after, `fillHeight`, `inset`), `PopupRow.qml`; `panels/Popup.qml`
      gives a shell panel's root base `popup.<key>` in `loadContent`; the network panel's
      root a PopupSection with section `connections`, `VpnSection` a PopupSection of
      PopupRows, the notifications panel a PopupSection; anchors `popup.network.connections`
      (append, `{ wifiEnabled, wifiConnected, ethernetConnected }`) and `popup.notifications`
      (prepend, `{ count }`), old slots read through aliases; parts at the same places
      (measured, waiting for layout). Left open:
  - **`popup.network.connections.vpn.row` is named but not published** (the lead's call):
    the plan has U2 publish it, but its slot `network.vpn.row` (the Tailscale module's
    exit-node chooser) is still served through `VpnExtras` / `VpnManager.extrasFor` and
    needs the per-VPN context and the own-provider scope: U4c publishes it with the VPN
    page's rows.
  - The by-hand look is under "Open points". `- _panel.contentTop` in the network list's
    height has no test (nothing can stand above the panel's root content yet).

## Small items done (moved from the tracker 2026-11-19)

- [x] `polkit/AuthPrompt.qml` sets no `textFormat` on polkit's texts (plain-text rule) — done
      with A5 (was under "Found during the test split" in the backlog).
- [x] Order of work, step 0 (workflow): (a) the test runners can run one suite or one
      scenario; (c) recurring defects written down as development rules in `CLAUDE.md`
      (both repositories), the list grows with every review; (f) development runs on the
      Arch machine, `nix` runs go to the NixOS machine.
- [x] Order of work, step 1: the plan for the test split, [plans/test-split.md](plans/test-split.md).
- [x] Order of work, step 3 (API extension in the core): command runner; program lookup
      with trust; test mode; privileged start (A4), the prompt says who and what for (A5);
      helpers (C1); shared module object (B1); system and network facts (C2, D1).
- [x] Order of work, step 10 (test split implemented, 2026-11-17): the unit and module
      suites run without `nix` (tools from the system); the lock bed with the system's
      tools, the whole lock bed on Arch; system detection behind a seam (`methods-script`
      runs both branches everywhere); `tests/run-system.sh` and the first checks per
      system; `install.sh` under stand-ins; `tests/run-all.sh`.
- [x] Soft dependencies, low (second review of 1.30), 2026-11-19: the docs now say a
      views-only soft dependent goes pending while its provider is pending; only the mains
      given a restarting module's object restart with it, and a soft provider pending whose
      manifest does not fit is not waited for (`ztop-unfit` fixture, ModulesTest,
      ModuleRulesTest); a main that went (or was found gone, or whose `destroy()` threw)
      applies the waiting module again one turn later, reading who waits then (`_afterGoing`).
- [x] Network card row, low (second review of 1.29), 2026-11-19: the button row's area
      takes hover with the plain arrow, so a gap no longer tints the card; the question
      beside the lock in whole pixels (the lock's width rounded up, the room floored); the
      name's six-character minimum pinned on its own font (NetworkCardGeometryTest).
- [x] Wi-Fi password: Enter in the password field (the owner, 2026-11-19), done 2026-11-19 —
      in the network popup Enter connects as Connect does (`NetworkRules.wifiEnterConnects`:
      a password typed, the network not in use, not connecting), on a saved network's card it
      saves as Save does while Save is available. KeyedViewsTest drives both against stand-ins
      (the row's `wifi`, the page's `profiles`); NetworkTest has the rule's cases.

## The tracker's open sections as worded before 2026-11-19

When the tracker was cut down (2026-11-19), "Order of work", "Backlog / later" and "Open
points" were shortened there. Their earlier full wording is kept here for the detail; the
tracker is the current list, this copy is not kept up to date. Headings are demoted one level.

### Order of work

0. Workflow — open
   - [x] (a) the test runners can run one suite or one scenario
   - [ ] (b) each agent gets its own working trees and its own test bed, so runs go in
         parallel; a module is always tested against a pinned core tree nobody is editing
   - [x] (c) recurring defects written down as development rules in `CLAUDE.md` (both
         repositories); the list grows with every review
   - [ ] (d) fix the known flaky live tests first: the Tailscale stand-in's event-stream
         replay timing (`tools/stand-in/curl`); the tailnet-lock read that is not retried
         (`module/LockClient.qml`)
   - [ ] (e) a small read-only check against the real Tailscale daemon at deploy: state,
         device list, no repeated log lines
   - [x] (f) development runs on the Arch machine; `nix` runs go to the NixOS machine
1. Planning, no code — open
   - [ ] revise [plans/api-next.md](plans/api-next.md): UI anchors and their naming
         convention, a module's public API, the password prompt's "who and what for",
         the versioning rule, a module's own elements, other authors, the direction
   - [ ] analysis + plan: PAM configuration from the shell (polkit and lock screen, NixOS
         and Arch)
   - [x] plan: the test split (general + per system): [plans/test-split.md](plans/test-split.md)
   - [ ] plan: installing, updating and removing modules, with the Settings → Modules page
   - [ ] revise [plans/documentation.md](plans/documentation.md) and
         [plans/architecture-cleanup.md](plans/architecture-cleanup.md) for the decisions
         below (environment-neutral, both systems together, `notes/`, verification at
         major releases)
2. Release — open
   - [ ] `lockscreen.lockOnSleep` default off (`singletons/SettingsSchema.qml`, today `true`)
   - [ ] versioning rule corrected (`CHANGELOG.md` header, `singletons/Version.qml` comment;
         `CLAUDE.md` done)
   - [ ] cut a minor release (today 2.0.0)
3. API extension in the core, in small slices, per [plans/api-next.md](plans/api-next.md) — open
   - [x] command runner
   - [x] program lookup with trust
   - [x] test mode
   - [x] privileged start (A4), the prompt says who and what for (A5)
   - [x] helpers (C1)
   - [x] shared module object (B1)
   - [x] system and network facts (C2, D1)
4. UI anchors; today's slots (`components/ModuleSlot.qml`, `Api.slots`) moved onto them — open
5. A module's public API for other modules, basic version — open
6. Tailscale module migration — open
   - [ ] every workaround removed
   - [ ] exit node per network in the connection's options (through an anchor)
   - [ ] the manual "for now" override
7. Architecture clean-up per [plans/architecture-cleanup.md](plans/architecture-cleanup.md)
   (splits, hubs, test hooks, the module's read/clock performance, the network editor's save
   that can lose the kill-switch choice). Runs alongside 3–6 where slices do not collide — open
8. Modules closed for now (see Decisions: a state of today, ended by step 15) — open
   - [ ] the trust model written down honestly: no isolation; review covers the project's
         own modules only; for any other module the password prompt's text is the only
         protection
   - [ ] Settings → Modules: enable, disable, reload, install, update, remove from a repository
   - [ ] the safe-mode banner
9. Lock — open
   - [ ] lock supervisor limit (3 restarts while locked, then stay locked, tell the user)
   - [ ] lock-before-sleep conflict detection
   - [ ] screensaver and lock screen working together checked
10. Test split implemented — done (2026-11-17)
    - [x] the unit and module suites run without `nix` (tools from the system)
    - [x] the lock bed with the system's tools; the whole lock bed on Arch
    - [x] system detection behind a seam (`methods-script` runs both branches everywhere)
    - [x] `tests/run-system.sh` and the first checks per system; `install.sh` under stand-ins
    - [x] `tests/run-all.sh`
11. PAM configuration from the shell — open
12. Documentation for users and developers per [plans/documentation.md](plans/documentation.md);
    the architecture and API chapters after 3–7 — open
13. Ready for outside authors — open
    - [ ] the author guide and the API reference in `docs/` (was "M5 author guide" in the
          backlog)
    - [ ] a module template
    - [ ] a module's tests runnable without a checkout of the shell
    - [ ] the public versioning rule written down (removals only with a major version,
          after a release listed as deprecated); in force from step 15
    - [ ] the trust text, and the confirmation when a module that is not shipped is first
          enabled
    - [ ] Settings → Modules shows where a module comes from, and when a user's copy
          replaces a shipped one
14. Divide the built-in features: abstraction in the shell, feature in a module — open
    - [ ] go through every built-in feature: what is the service or the abstraction (stays),
          what is the feature (moves)
    - [ ] one feature first, as the proof of the API; shipped with the shell, on the public
          API only
    - [ ] the rest, feature by feature
15. Announce the shell as open to module authors, after the first feature of step 14 is
    split out — open
    - [ ] the release that says so; from it a removal from the module API needs a major
          version

What steps 3–6 must leave possible for 13–15 is in [plans/api-next/versioning.md](plans/api-next/versioning.md), §11 "Doors to keep open".

Later:
- pttd (dictation) as its own module in its own repository (was TODO 11.24); until then
  the protocol is in [pttd-protocol.md](pttd-protocol.md)
- global default programs (the terminal among them)
- NixOS option for modules (`programs.h2s-shell.modules`); module signatures
- UI texts pass and translations, in one go; the owner reviews the voice (short plain wording)
- documentation as a site with per-system tabs
- module order: the order in which modules are loaded, and the order of different modules'
  elements in one place (two separate things; until then both by module id)
- modules' own elements, published: a module defines an element with its own public
  styles, settable by a theme, and publishes it through a public API, so that libraries of
  extra elements can exist (building its own elements for itself is allowed now)

### Backlog / later

- [ ] Unit suites that open the real `SettingsWindow` (ModuleRegistriesTest, AnchorsTest) start the `NetworkManager` singleton's real `nmcli monitor` (it exits in the headless runner, but it touches the rule "never the real network"): give those suites stand-ins or keep the singleton from starting there
- [ ] `panels/Popup.qml` `contentLoader.onLoaded` assigns `availableHeight` / `popupAnimating` to a panel unguarded: a readonly one throws and skips the rest of the handler (found in B1's review fixes; core and module panels)
From the old TODO (numbers kept, see done.md for the rest):
- [ ] 11.34 A command button bar widget: label and/or icon, a command per click (left, right, middle, maybe long press), run detached
- [ ] 11.31 Popups clear of the on-screen keyboard: done for a bar at the top; left: a bar at the bottom, popups by a bar at a side, the settings window (`panels/Popup.qml`)
- [ ] 11.32 "Settings saved" toast seen with nothing changed (the NixOS machine, 2026-11-08) — reproduce first
- [ ] 11.23 Installing: `install.sh` is tested under stand-ins (`tests/install-test.sh`), never yet run for real on a clean Arch; on a first run `Config` chmods `config.json` before it exists (one warning; a first start in an empty home as a lock-bed check is not written); publishing (AUR, docs for others) later
- [ ] 11.20 Animation editor; animations as data assigned to named element slots
- [ ] 11.5 Bar shape and anchoring ("dynamic island") — needs working out with the owner first
- [ ] 11.7 Themes stage 8, matugen: a template mapping its palette to the colour tokens, a "wallpaper" theme reading it (`colorsFrom` exists), docs
- [ ] 11.8 Compositor integration, Hyprland first (scroll sensitivity, volume step, …) — first a plan, `notes/plans/compositor.md`, agreed with the owner
- [ ] A QR code to join a network (`qrencode`) (left from 11.37)
- [ ] A bar widget to shuffle the wallpaper, or a command button (11.34)
- 11.6 Styling with CSS-like selectors — shelved; [plans/selectors.md](plans/selectors.md), [plans/styles.md](plans/styles.md)

From next-steps (2026-11-15):
- [ ] The muted status line has low contrast on the green tint of an active row in the network popup (not re-checked)
- [ ] The lock test `fallback` failed once (the PAM stand-in never answered): find out why
- [ ] Module widgets pop in after the first frame (`singletons/ModuleLists.qml`: by design today)
- [ ] A start guard for slow crash loops (not re-checked)
- [ ] Quickshell 0.3.2: a second polkit request while a prompt is open replaces it, never finished (upstream)
- [ ] `SmallButton` / `DeleteButton` have no keyboard focus or activation
- [ ] Opened connection cards have about 20 px of empty space under the detail line (not re-checked)
- [ ] Tailscale later: re-authentication without the profile reset (`login-interactive`), settings re-applied after a same-account login, certificate renewal, a terminal launcher for SSH (with the default programs)
- [ ] Taildrop's file and folder dialogs never clicked on a real machine
- [ ] Tailscale module: warn when an accepted subnet route covers the local network the
      computer is on (replies to LAN peers then leave through the tunnel and LAN connections
      to this computer fail); seen with "Use routes from other devices" on

Found while writing the development rules (2026-11-17):
- [ ] `singletons/network/VpnLockdown.qml` without the installed script: a network coming up asks for the password by itself, and runs the shell tree's own `scripts/h2s-vpn-lockdown` as root (user-writable in a checkout) — against two development rules

Found during the test split (2026-11-17):
- [ ] Module runs in the headless compositor start the `nmcli` on `PATH` against a dead
      D-Bus address (`[NetworkEvents] nmcli monitor exited, restarting`) and try `notify-send`:
      against "tests never touch a real daemon"; a stand-in or a switch-off is needed
- [x] `polkit/AuthPrompt.qml` sets no `textFormat` on polkit's texts (plain-text rule) — done with A5
- [ ] `tests/ModulesTest.qml` (start guard, lines 268-301) asserts within a 300 ms timer:
      fails under load on a slow machine (3 checks, seen on the NixOS machine)
- [ ] Lock scenario `modules-discovery` once saw the supervisor silent for 44 s under load
      (not looked at)
- [ ] `tests/lock/tools.nix`: the comment ties the pin to one machine's system
- [ ] The module repository's `tests/lock-bed/run.sh` header still advises wrapping the run
      in `flock` (harmless, stale)
- [ ] Lock scenario `restart-crash-locked`, the check "Quickshell said it would not
      restart": failed twice in whole runs of the bed on the Arch machine (Quickshell 0.3.2),
      passed three times alone; belongs with the upstream notes (`notes/upstream/`). A
      SIGSEGV 0.2 s after the shell started: Quickshell's crash
      handler printed "Quickshell has been restarted", then `Launching config: ""` and
      "Could not open config file", exit 255 — not its "crashed within 10 seconds of
      launching. Not restarting". The launcher started a new shell either way and the screen
      stayed locked; the check expects one of two ways Quickshell ends an early crash
- [ ] `install.sh`, found by its test (2026-11-17): the font warning can be false under
      `pipefail` when `fc-list` is still writing as `grep -q` leaves; no controlling
      terminal or no `sudo` ends at the packages with bash's own error, unexplained; "ours"
      is too loose (any origin containing the repository's name, so a fork reads as
      "Already installed"); a target directory without `shell.qml` is left to `git clone`'s
      own error
- [ ] The lock screen's password fallback, from the review of its probe (2026-11-17), all low:
      the direct question's own branch (`test -e /etc/NIXOS`, `singletons/Lockscreen.qml`) is
      never run live — `tests/lock/tests/fallback.sh` always names the system; add a stack
      without `H2S_LOCK_SYSTEM` and an unrunnable script. A fallback taken at a failed
      detection can be the unusable one when the right one arrives a moment later
      (`singletons/LockRules.qml:914`; NixOS, shell restarted while locked, script not
      runnable): replace it in `_settingsChanged` while no password conversation runs.
      Neither probe has a time limit. The request numbering lives in the driver, untested:
      a rules function with unit cases when next touched.
- [ ] Explore integration with file managers (the owner, 2026-11-18), instead of a richer
      file dialog: the action lives in the file manager itself — "send with Tailscale" on
      files chosen in Dolphin, the owner's file manager for now (a service menu is the
      likely way). Dolphin is not the only one, and a file manager of the project's own
      may be written; so explore what a module needs from the API to offer such an action
      to any file manager, not Dolphin's format alone. To look at first, no code of ours:
      the KDE portal backend (`xdg-desktop-portal-kde`, `FileChooser=kde` in the user's
      `hyprland-portals.conf`) makes Dolphin's dialog the file chooser of every program
      that asks the portal.
- [ ] A file chooser of the project's own as a portal backend (the owner, 2026-11-18;
      with a file manager of the project's own, for one look across the system): a D-Bus
      service that implements `org.freedesktop.impl.portal.FileChooser`, a `.portal` file
      that announces it, and a line in the user's portal configuration that prefers it
      (`~/.config/xdg-desktop-portal/<desktop>-portals.conf`; packages' files are under
      `/usr/share/xdg-desktop-portal/`). Then every program that asks the portal gets it,
      not the shell alone. A program reaches the portal only if its toolkit is told to:
      Qt by the platform theme (`qt6ct`: "Standard dialogs"), which is the user's setting,
      not the shell's. The shell cannot close another process's dialog on a lock — its own
      backend could. NixOS and Arch differ in where the files go.

### Open points

- None of the owner's decisions are pending. The plans in `plans/` (`api-next.md`,
  `architecture-cleanup.md`, `documentation.md`) are drafts written before the decisions
  of 2026-11-17; step 1 revises them, and the owner approves them before implementation.

For the owner, from the autonomous run (2026-11-18 on):

- **Hover contrast of warning and success buttons** (review of the elements batches): under
  the pointer a warning or success button has white text on `#e8a854` / `#44d47a` in the
  built-in theme, a contrast of about 2:1 (readable text wants 4.5:1). Options: dark text on
  those fills, or darker fills. Not changed; the look is the owner's.
- **Plain notifications on one line** (C1, module API 1.12): `format: "plain"` turns line
  breaks into spaces (the one-line rule for outside text). After M5 the Tailscale module's
  "received several files" body, which lists one name per line today, reads
  "a.txt b.txt". Alternative: keep line breaks in a plain body only. Caps chosen by the
  agent: summary 200, body 1000 characters, a `module.log` line 1000.
- **The Tailscale module's "Authorization" words** (M3, the agent's choice; shown in the
  password prompt): Connect, Disconnect, Log in, Add an account, Log out; Change the exit
  node; Allow / Block the local network; Accept / Ignore routes; Use / Ignore Tailscale
  DNS; Block / Allow incoming connections; Start / Stop the SSH server; Start / Stop the
  web interface; Offer an exit node / Stop offering an exit node; Turn on / off automatic
  updates, source NAT, stateful filtering; Offer an app connector / Stop the app
  connector; Report device posture / Stop posture reports; Run a peer relay / Turn off the
  peer relay; Check for updates / Stop update checks; Rename this device, Change offered
  routes, Name the account; Become the operator / Give up the operator role; List
  accounts, Switch account, Remove an account; Stop every share, Stop Funnel; Share a
  port, Share a port on the internet, Stop a share, Turn on / off Funnel.
- **What else changes for the user with M3**: a refused run is announced by the shell
  ("<what> — not allowed"), the module's entry reads "Not allowed." (was "No
  authentication agent answered."); with no way to run as administrator the status reads
  "Can't ask for the password."; for a moment after the shell starts the card may say
  "Changes that need an administrator are not offered: pkexec is still being looked for.";
  a user-writable `timeout` no longer marks the module "Not trusted" (the shell's own
  trusted `timeout` is used).
- **Tailscale module, plain words for a refused run** (M3 review fixes): "It was not run as
  administrator: the command holds characters that can't be shown" (unprintable), "… it
  doesn't say what it is for" (no purpose), "… the screen is locked" (locked; normally
  silent). A Funnel left public after a wait now shows "Port N is public with something
  else on it." with a "Turn off Funnel" button, and a notice "Port N is public with
  something else on it. Turn Funnel off on Tailscale's page."
- **Two bar entries of one widget type share one popup** (B1): clicking the second entry
  while the first's popup is open closes it instead of switching to it (only hover
  re-targets an open popup). Older than B1. Should a click on another entry switch the
  popup?
- **Network facts for modules** (D1, the agent's choices): `Api.localNetworks` includes
  Docker and libvirt bridges (`kind: "bridge"`), as the Tailscale module's own read does
  today — leave them out? The `kind` words (wifi, ethernet, bridge, modem, other) and the
  device types left out (loopback, tun, wireguard, vpn, ip-tunnel, wifi-p2p). `setsDns` on
  a VPN means "has DNS servers of its own while up", not "takes over DNS" (priority, split
  DNS). Unchecked on a machine: a plugin VPN taking the default route shows `IP4.GATEWAY`
  or a /0 route; WireGuard's `ip4-auto-default-route` and `peer-routes` are not read.
- **The file chooser for modules** (E1, to check by hand on a real screen, both machines):
  open a chooser from a module popup and close the popup — the dialog stays, has the
  keyboard, opens in the folder asked for, returns the file / folder picked; locking the
  screen closes it; with `QT_QPA_PLATFORMTHEME=xdgdesktopportal` "several files" returns
  several (Qt's own dialog returns one even then; Ctrl/Shift+click untested). Choices to
  confirm: the dialog is whichever the platform theme gives (not forced to Qt's own); an
  empty title shows Qt's default (put the module's name there?); a lock closing it reads
  as `cancelled`, so a module cannot tell it from the user cancelling.
- **Dependencies between modules** (P1, the agent's choices): a malformed `exports` or
  `uses` fails the whole module (not "drop the entry, keep loading", which would let it run
  without something it requires); a function a dependent hands its provider may still be
  called after the dependent is off — QML cannot stop it, `Api.qml` makes it the
  dependent's job; a provider whose main failed stays failed until turned off and on (its
  dependents `missing-module` meanwhile).
- **Spacing of modules' elements in a settings page** (U1a, copied from today's General
  slot): 16 px between the page and the hosts before and after it, 4 px between elements
  in one host. Status texts quote paths in JSON quotes (the code's style), not backticks.
- **The popups on anchor blocks** (U2, to look at once by hand): network popup with
  Tailscale up — the VPN header, rows 4 apart, Tailscale's exit-node chooser right under its
  row, Ethernet and Wi-Fi spacing unchanged, the divider over the network list only while
  Wi-Fi is on, the list not cut short, with a hotspot on the hotspot line and "Turn off
  hotspot"; notifications popup — header and "Clear all" 8 px in, the list filling to the
  bottom and scrolling, cards sliding in and out, "All caught up" after Clear all then the
  popup closing; moving the pointer between bar cells with a popup open.

- **The section and the card, on a fixture view (U4a)** — on `master` 2026-11-19, no API
  change. `components/SettingsSection.qml` (before, title + buttons, prepend, content,
  append, after), `components/SettingsCard.qml` (frame ported from `NetworkProfileCard`; a
  `settings` region shown only while open; scope from the card), `AnchorContent.active`,
  region paths in `ModuleRules.anchorBlockPaths`. Reviewed on the diff; `tests/run-all.sh`
  passed on both machines. The review confirmed a Quickshell 0.3.2 `ScriptModel` defect
  (rows replaced by position for rebuilt objects) exposing several of the shell's lists;
  fixed separately (string-key models).

- **Lists fed to `ScriptModel` as string keys** — on `master` 2026-11-19. Quickshell 0.3.2's
  `ScriptModel.updateValuesUnique` replaces rows by position for rebuilt objects (a delegate
  gets another item, the wrong one is destroyed; draft
  `notes/upstream/quickshell-scriptmodel-replace.md`, pinned in `QuickshellPinTest` (g)).
  `singletons/ListKeyRules.qml` (`keyed`), `components/KeyedModel.qml` (`model`, `byKey`);
  ~30 views converted (calendar, network settings pages, the Wi-Fi popup list, VPN rows,
  bar sections, module slots and anchor contents, `Dropdown`, the lock prompt's methods …);
  a calendar edit saves only to the event it started on; `SettingsCard` fixes (48 px closed,
  buttons right-aligned, no gap when none shows). Rule in `CLAUDE.md`. Reviewed on the diff
  (low findings left for a follow-up); `tests/run-all.sh` passed on both machines.

- **Calendar follow-ups to the key fix** — on `master` 2026-11-19: a failed event save keeps
  the form open ("Couldn't save the event"; late answers ignored; no double send); a moved
  event saves to the calendar it is in now (refused if in several); calendar events keyed by
  calendar + id in every view; GPU cards fed to their Instantiator by key; `KeyedViewsTest`
  restores the network singletons on any exit. Quick set passed on both machines.

- **The network profile card on the settings card (U4b)** — on `master` 2026-11-19, no API
  change. `NetworkProfileCard` built on `SettingsCard` (header slot: lock + main button;
  stacked Settings…, Edit connection…, Forget; page rows as `pageRows`; objectNames kept);
  `SettingsCard`'s stacked buttons in a ColumnLayout, put on the right edge unless they name
  an alignment. `tests/NetworkCardGeometryTest.qml` written on the old card: identical numbers
  for a Wi-Fi, wired, hotspot and provider card, closed and open. Reviewed, no defect (test
  gaps left for the VPN page slice); `tests/run-all.sh` and the Tailscale lock bed passed on
  both machines.

- **The VPN page (U4c)** — on `master` 2026-11-19, module API 1.23. Own-provider places
  `popup.network.connections.vpn.row` (after) and `settings.network_vpn.vpns.card.settings`
  (prepend), context `{ vpnId, entryId, vpn, provider, otherVpnsUp, otherVpns }`, `scopeId`
  the provider's module; `VpnManager.extrasFor` / slots gone; the Tailscale module's
  `network.vpn.row` / `network.vpn.card` slots read through aliases (it now lists them as
  deprecations, until M6); `VpnExtras` only for providers that are no module's. Card wiring
  tests (title, active border, notice while busy); `SettingsCard` right-edge rule uses the
  horizontal part of an alignment. Reviewed, no defect; `tests/run-all.sh` and the Tailscale
  suites and lock bed passed on both machines. The Tailscale card is now built when it
  opens (it rechecks Tailscale then, not on page open).

- **The Wi-Fi and Ethernet pages (U5)** — on `master` 2026-11-19, module API 1.24. Places
  `settings.network_wifi.saved.card.settings` and `settings.network_ethernet.profiles.card.settings`
  (append, any module, built only while the card is open), context `{ networkId, name, kind,
  active }` (`ModuleRules.networkContext`); sections and cards named; `SettingsSection`'s
  buttons in a RowLayout (whole pixels). Pages measured identical before and after (280
  positions). Reviewed, no defect; `tests/run-all.sh` passed on both machines.

- **The card's button place (U6)** — on `master` 2026-11-19, module API 1.25. A card's
  `actions` region (prepend host, own buttons, append host for module buttons, `lastButtons`
  — Forget/Delete stays last); rows `….card.actions` on the VPN, saved Wi-Fi and wired cards
  (append, `takes: "SmallButton"`, a non-button refused with one status error); module buttons
  on the stack's right edge at size `m`, cut at a third of the card; a hidden or refused
  element takes no room; `DeleteButton.maximumWidth`; `ModuleRules.networkListed` (no card
  path before a Wi-Fi profile's details are read); the Wi-Fi and Ethernet pages' positions
  pinned. Reviewed, two layout defects fixed with cases; `tests/run-all.sh` and the Tailscale
  lock bed passed on both machines.

- **A module's icon (U7a) and marks on closed cards (U7b)** — on `master` 2026-11-19, module
  API 1.26 and 1.27. Manifest `icon`: a glyph of the icon font (private-use ranges only, the
  shell's own marks and 46 lock / no-entry lookalikes refused), an SVG (read and refused
  with any external reference, other encodings or a wrong start; theme-coloured or its own
  colours) or a PNG/WebP picture (magic bytes checked); `components/ModuleIcon.qml`, handle
  `icon`, a fallback letter. `module.setMark(path, itemId, label)` / `clearMark` on the saved
  Wi-Fi and wired cards (first three marks by module id, right after the name, also for
  right-to-left names; labels cleaned of C1/bidi; warnings one line per kind).
  `SettingsCard`'s before/after host gap only for something visible. Reviewed (an SVG
  could load any file and stall every image through a FIFO — fixed); `tests/run-all.sh`
  passed on both machines.

- **The module's runner (M1) and main and popup (M4)** — on the module's `main` 2026-11-19
  (manifest `api` 1.15, version 0.6.0, not released). Every command through one shell
  `CommandRunner` (`TailscaleClient._run`; the own process factory, watchdog and `timed`
  wrapping gone; the event stream on the runner; answers after a stop dropped; a cut answer
  is a failed read, cap 32 MB; `tailscale cert` and each Taildrop file keep their own
  `timeout`); `module.main?.client` replaces the `Tailscale` singleton, the popup's
  `opener.preset` replaces `Tailscale.popupPreset`. Core fix on `master` with it: a cancelled
  run whose answer was still queued answers `cancelled: true`. Reviewed; the module's suites,
  stand-ins and lock bed and the core's full set passed on both machines.

- **The module's helpers and facts (M5) and its row and card onto anchors (M6)** — on the
  module's `main` 2026-11-19 (manifest `api` 1.23). `Api.system`, `Api.localNetworks`,
  `Api.format`, `Api.address`, `Api.minuteNow`, `module.log`, plain notifications replace the
  module's own copies and reads; certificates in `<module.dataDirectory>/certs` (no move:
  the owner's decision, the old folder existed on neither machine); "another VPN" warnings
  from `Api.vpnsUp` (full tunnel, own DNS, overlapping routes); the provider reports
  `fullTunnel` / `setsDns` / `routes` (null when unknown). Manifest `slots` → `anchors`: the
  status lists only the `qs.components` import now. Reviewed, fixed; suites, stand-ins and
  lock bed passed on both machines.

- **The owner's answers, first round (core)** — on `master` 2026-11-19, module API 1.28. Plain
  notifications keep line breaks in the body (20 lines, 1000 characters); VPN provider failures
  sent as plain text; the public `SmallButton.defaultSize` (a card passes `m`, a module's own
  `size` wins); an opened card ends 8 px under its last line; marks removed before any release,
  replaced by the name-line places `settings.network_wifi.saved.card.title` and
  `settings.network_ethernet.profiles.card.title` (closed and open, clipped to the line, a
  quarter of the card, the name cut first). Reviewed (low findings left for the next round);
  `tests/run-all.sh` passed on both machines.

- **The owner's answers, second round (core)** — on `master` 2026-11-19, module API 1.29 and 1.30.
  The Wi-Fi switch in the Wi-Fi page's heading (the "Off" row gone); a network card's buttons
  in one row on the name line (main, Settings…/Edit — "Edit connection…" became "Edit" —,
  the modules' actions, Forget/Delete), closed and open, moving under the name when they do
  not fit and the main alone on a line when wider than the card; a long question wraps; the
  actions region built while closed; `settings.network_vpn.vpns.card.title`; an element's own
  width on a name line, full width elsewhere. 1.30: soft dependencies (`uses` entry
  `{ version, optional: true }`; the dependent restarts when its provider comes or goes, its
  users going first); the file chooser's title is the module's name when none, a lock answers
  `blocked: "locked"`; a click on the other bar entry of one widget type switches the popup;
  plain notification bodies trimmed and blank runs folded; toasts cut at six laid-out lines,
  long words wrap. Each reviewed twice where the first review found something high;
  `tests/run-all.sh` passed on both machines.
- **"Send file…" from the popup (M8)** — on the module's `main` 2026-11-19. Picking files in
  the shell's chooser leaves a row under the device with Send / ×, a progress bar and Cancel,
  the result; the settings window does not open; one choice per device; a busy chooser says
  so; both Taildrop dialogs through `module.chooseFiles`. Reviewed, fixed; suites, stand-ins
  and lock bed passed on both machines (the lock bed against the core's new card row).

- **Core round three** — on `master` 2026-11-19, module API 1.31. Public `ProgressBar` (theme
  group `progress`) and `HoverTip` (owns its hover handler); Enter in the Wi-Fi password field
  connects (popup: the row open, a WPA password 8–63 characters; saved card: Enter = Save);
  soft-dependency fixes (only mains given a provider restart with it; no wait on an unfit soft
  provider; no member left pending); network card gap hover, whole-pixel question beside the
  lock; `Dropdown` option width guarded. Reviewed, fixed; `tests/run-all.sh` passed on both
  machines.

- **The exit node per network on the cards (M7) and "for now" (M9)** — on the module's `main`
  2026-11-19 (manifest `api` 1.31). On an opened saved Wi-Fi / wired card a "Tailscale exit
  node" row (Not set / No exit node / Automatic / a node); on the name line a mark for a
  network routing through an exit node (none for "No exit node"); the page's table gone. A pick
  in the chooser is "for now" once it succeeds (in memory); "Default" goes back to the
  network's choice or turns the exit node off; a wake drops it (with a 30 s hold so a network
  coming back applies its own choice); joining a network keeps the pick. The module's progress
  bar and tooltip are the public `ProgressBar` / `HoverTip`. Reviewed, fixed (a flaky wait in
  `NetworkExitTest` too); suites, stand-ins and lock bed passed on both machines.

- **Name-line places on the network popup's rows; a pill's text size** — on `master`
  2026-11-19, module API 1.32. `popup.network.wifi.row.title` (each Wi-Fi row, saved or not;
  context with `ssid`, unsaved rows `networkId ""`) and `popup.network.connections.wired.row.title`;
  `components/PopupRowTitle.qml`; elements on the line take their own clicks; one "saved" rule
  (`ModuleRules.savedWifiProfile`, hotspots not saved); bidi controls stripped from context
  names; public `Pill.textSize` ("small" | "body"). Reviewed, fixed; `tests/run-all.sh` passed
  on both machines.
- **The module off the shell's internals (M10)** — on the module's `main` 2026-11-19 (manifest
  `api` 1.32, no deprecations). Every `qs.components` import gone onto the public elements;
  six confirm buttons on the module's `ConfirmButton` (drops its question when hidden or when
  its subject changes, tested); warning lines on `Notice`; "Funnel on" a warning button; the
  operator no longer sees a lock beside "Switch"; the exit-node mark on the popup's network rows
  too. Reviewed, fixed; suites, stand-ins and lock bed passed on both machines.

- **The module's last migration slice (M11)** — on the module's `main` 2026-11-19 (manifest
  `api` 1.32). No checks for older shells left (`typeof module?.…`, `system?.…`, `run?.cancel`);
  the received-files notification lists one name per line. Reviewed (nothing found); suites,
  stand-ins and lock bed passed on both machines. The module uses nothing the closing slice (Z)
  removes.


## Notifications with a progress bar and Taildrop's list of transfers (2026-11-19 on)

Plans: [plans/notification-progress.md](plans/notification-progress.md),
[plans/taildrop-transfers.md](plans/taildrop-transfers.md).

- **The card shows a sender's progress (N1)** — on `master` 2026-11-19. `NotificationRules.progress`
  (the `value` hint 0–100 and a state; a string, NaN or none → no bar; over 100 full; below 0
  unknown length; cancelled no bar); the bar on the card and, at "full" detail only, on the
  lock/screensaver preview; an action on a resident notification (buttons, default action,
  inline reply) keeps its entry. `shelltest.notificationState()`; lock-bed scenario
  `notification-progress`. Quickshell 0.3.2, seen on the bed: `value` arrives in `hints` as a
  number; a `replaces_id` keeps the object, emits `hintsChanged` and replaces `hints` whole;
  `expireTimeout` is the sender's value in ms unchanged (-1, 0, 2000), updated with
  `expireTimeoutChanged` on a replacement. Reviewed (nothing medium or higher);
  `tests/run-all.sh` passed on both machines.
- **The transfer rules and sends per file without time limits (D1, D2)** — on the module's
  `main` 2026-11-19 (manifest `api` 1.32, unreleased). `TaildropTransferRules`: states,
  stall (from 2 min, only while progress can be read), per-device scheduling with
  `maxParallel` 4 and extra slots, Skip / "Send now" / "Fetch now" offered only when they start
  something, a "saved" answer winning over a later Skip, the per-file save script (TERM held
  after the rename, staging removed), `popupSplit`, bus entries assigned so they never cross
  files of one name (newest 512 kept). Sends: one `file cp` per file, `timeoutMs: 0`, stall
  line instead of a stop, a second send to a device queued, several devices at once, one
  click one transfer (the chosen files move into it), the page's Cancel stops the page's
  sends; IPC `transfers`, `cancelTransfer`, `skipFile`, `nowFile`; stand-in
  `TS_FAKE_SEND_STALL`. Reviewed, fixed; module suites and stand-ins on both machines, the
  module's lock bed on NixOS. Only on stand-ins: one file per `file cp`, a kill of one file,
  two devices at once, the bus's per-peer entries (D6 checks them for real).
- **Toasts follow the sender's display time (N5)** — on `master` 2026-11-19. `ToastRules.timing`
  / `duration` (-1, none, NaN → the user's time; 0 stays until taken away; a positive time
  with a 1 s floor; critical stays; `notifications.followSenderTime` off → the user's time),
  `slots` / `nextToast` / `stackOrder`: toasts that stay take none of the layout's slots and
  stack above them, at most `notifications.maxStayingToasts` (1–5, default 3), more wait,
  counted; critical toasts stack the same way in both layouts (they held the slot before).
  `isPersistent` split into `isCritical` (red border) and the timing; a toast's countdown
  restarts or stops when its sender replaces it with another time. A slot takes a toast
  through `Notifications.takeHudNotification()` (on the shown list before the queue changes,
  so a draining backlog never exceeds the room); a notification closed while shown or waiting
  leaves (its `closed` and `tracked` signals). The lock bed's `notify` helper sends -1.
  `CommandRunnerTest`'s bare-run bounds allow Qt's coarse timers 5% early (the known flaky
  check failed steadily on the NixOS machine). Reviewed twice (a high each time), fixed;
  `tests/run-all.sh` passed on both machines.
- **Saves per file, with progress, outside the lock (D3)** — on the module's `main` 2026-11-19.
  One run per received file through `schedule` (`saveFileArgv`, `timeoutMs: 0`), progress from
  the script's own lines, stall, Skip (left in the inbox, never auto-retried; Save by hand
  still can), "Fetch now"; files arriving during a save join it. Save is off during an
  account switch, login, logout or added account (`saveOffer`), saves are cancelled when one
  starts and `waiting` is re-read after it. The inbox DELETE runs under `curl --max-time` 30 s
  (on timeout `saved-kept`); the progress watcher ends the fetch and removes the staging
  folder when its script is killed. The old whole-inbox `saveScript` and `timeLimits.save` are
  gone. Reviewed, fixed; module suites and stand-ins on both machines, the module's lock bed on
  NixOS. Only on stand-ins (no real curl / LocalAPI).
- **The transfers list on the page (D4)** — on the module's `main` 2026-11-19. Sends and saves
  as one keyed list in `TaildropSection.qml` (title rows with Cancel / Clear from
  `transferOffers`, file rows with a bar, text and Skip / "Send now" / "Fetch now" from
  `fileOffers`; incoming files as rows without buttons, `incomingRow`); the page-wide
  Cancel / Clear, the send lines and the `saved` lines went. New `TaildropListTest`. Reviewed
  (nothing medium or higher); module suites and stand-ins on both machines, the module's lock
  bed on NixOS.
- **Several devices from the page (D8)** — on the module's `main` 2026-11-19. The target pills
  are toggles; Send's label ("Send to laptop" / "Send to N devices"), availability and targets
  from one rule (`sendButton`); `targetIds` instead of `targetId`, kept to picked devices still
  there and available and emptied by account operations (`keptTargets`); pills keyed by device
  id. The `find -P` check runs once for several devices. Reviewed, fixed; module suites and
  stand-ins on both machines, the module's lock bed on NixOS.
- **The command runner: `endWithShell` and `outputAfterCancel` (module API 1.33)** — on
  `master` 2026-11-19, found by D3. `endWithShell: true` (opt-in): the run waits for the tool
  look-up and starts as `setpriv --pdeathsig KILL -- <argv>` (inside `timeout` when it has a
  limit), so it dies with the shell; only such runs read setpriv's 126/127 as `failedToStart`.
  Default runs unchanged (argv, timing, codes); privileged runs ignore the option.
  `outputAfterCancel: true`: lines after `cancel()` and the result (`cancelled: true`) still
  arrive. A first version made `setpriv` the default for unlimited runs; its review found it
  wrapped `pkexec`, turned "cannot start" into a silent "dismissed" and killed programs modules
  launch on every restart — hence the opt-in. `tests/run-all.sh` passed on both machines.
- **The popup on transfers, in two panels (D5)** — on the module's `main` 2026-11-19. More than
  2 files across all devices (sends from the page and the popup, saves; refused files not
  counted) → the popup becomes the existing panel, a rule and `TaildropFilesPanel.qml` (a header
  per device with Cancel / Clear, its file rows, "Received files", its own scroll); otherwise
  one line per device under its row (`TaildropPopupState.qml`), with the stall line and Skip /
  "Send now" / "Fetch now". A second send queued to a device shows on its line, Cancel stops
  both; a send to a device no longer listed gets a header under its last known name. Fits half
  of a 1366-px screen. Shared `TaildropFileRow.qml`. Reviewed (page sends were missing from the
  popup), fixed; module suites and stand-ins on both machines, the module's lock bed on NixOS.
- **Taildrop's runs end with the shell; a save stopped after its rename reports "Saved"** — on
  the module's `main` 2026-11-19 (manifest `api` 1.33). Each `file cp`, each per-file save and
  the event stream take `endWithShell`; saves take `outputAfterCancel`, so the script's
  `saved` line after a Skip / Cancel / logout reaches `answerCounts`. Live scenario
  `skip-after-rename`; a recording runner checks the options. Read by the lead (small); module
  suites and stand-ins on both machines, the module's lock bed on NixOS.
- **Taildrop docs against the code (D6, the docs part)** — on the module's `main` 2026-11-20.
  The save script's steps in `docs/architecture.md`, the IPC shapes and stops in `docs/ipc.md`,
  `docs/privileges.md`, `docs/features.md`, the stand-in `TS_FAKE_DELETE_HANG`; the Unreleased
  CHANGELOG merged into a short set ("Needs … 1.33" kept, no version bump). No text names a time
  limit on sends or saves. Read by the lead; module suites on both machines. Left to the owner:
  the real tailnet checks and the 0.7.0 release (tracker).
- **Notifier's progress handle (N2)** — on `master` 2026-11-20. `Notifier.send` with `progress`
  returns a handle (`singletons/io/NotificationHandle.qml`: `open`, `state`, `update()`,
  `close()`, `finished`). Not the plan's `notify-send --wait` waiter: on the bed, `notify-send`
  closes the notification itself after a click and `--action` always waits, so actions could
  not stay. Instead one-shot `gdbus call … Notify -- <GVariant text>` / `CloseNotification`,
  one call in flight per handle, coalesced (`nextSend`); clicks and closing from the shell's
  own server in-process (`Notifications.actionInvoked`, `notificationClosed`, `tracks()`,
  `invokeAction()` — the card's actions go through it); an id the server does not hold →
  "unknown", closing what it made (found by `x-qs-progress-handle` when the first show
  failed); a failed update retried after 1, 2, 4, 8, 16 s, then "unknown"; early clicks
  buffered; orphans dismissed after a reload. `NotificationRules.gvariantString` and friends:
  printable ASCII in single quotes, `'` and `\` escaped, all else `\u`/`\U`, NUL and lone
  surrogates dropped, cut at 4000 first; `x-qs-` keys filtered on the received form. Plain
  `send` unchanged. Lock-bed scenario `notifier-progress` (real gdbus, the shell's own server;
  adversarial text round-trips). Reviewed (escaping held; a failed "done" and an unknown
  handle's leftovers fixed); `tests/run-all.sh` passed on both machines.
- **A sender's announce brings its toast back (N4)** — on `master` 2026-11-20.
  `NotificationRules.announced` / `announceEffect`: a raised `x-qs-announce` on a notification
  carrying this run's `x-qs-progress-run` token (never given to modules or apps) restarts a shown
  toast's time, or sends a toast no longer shown or queued back through the normal queue once;
  toasts off, no toast screen, the centre open → nothing. `Notifications.screensOverride` (null;
  for suites). Reviewed (nothing medium or higher); `tests/run-all.sh` passed on both machines.
- **`notify` returns the handle (N3, module API 1.33)** — on `master` 2026-11-20.
  `module.notify(summary, { progress, toast: "brief" | "whileRunning", actions, onDismissed })`
  returns a frozen plain object (`open`, `state`, `update({…, announce})`, `close()`) closing over
  the shell's handle — nothing on it leads to the handle, its runner, the server or the run
  token; `Api.notify` refuses `progress` (no owner to close it). Notifier keeps each module's
  open handles (`own`, `closeOwned`, `forgetOwned`), closed when the module is turned off. A
  module's notifications lose every `x-qs-` hint key (normalised, any case); a progress one is
  never critical (urgency hints dropped, the shell's own urgency byte) and always carries the
  module's name. `ModuleTestKit.dismissNotification` / `pressNotificationAction`; the good
  fixture's `progress` IPC; lock-bed scenario `modules-notify` (seam
  `H2S_SHELL_TEST_MODULE_NOTIFY`). Reviewed twice (a high: the raw handle reachable through
  `_handle`), fixed; `tests/run-all.sh` passed on both machines (`AnchorsTest` failed once in a
  NixOS run, passed alone three times and in the rerun).
- **Progress notifications for transfers (D7)** — on the module's `main` 2026-11-20 (manifest
  `api` 1.33, unreleased). Setting `mod.tailscale.taildropNotifications` ("stay" default,
  "brief"), a row on the page; `TaildropTransferRules.notification`: none before 3 s, one handle
  per transfer, Skip / "Send now" / "Fetch now" on a stall (the page's rule), `whileRunning` for
  "stay", an announce when a file first stalls and at done / failed / a stop with a message,
  none on Skip, Cancel or moving again. When the Tailscale client stops, transfers end and
  their notifications read "Stopped"; an ended transfer's notification stays in the centre
  after a clear; handles close when the client goes. Reviewed, fixed; module suites and
  stand-ins on both machines against the final core, the module's lock bed on NixOS.
- **Taildrop's page sends one way** — on the module's `main` 2026-11-20 (the owner's decision).
  The page's device rows lost "Send file…"; the page sends only from its Taildrop section
  (files, device pills, Send / Cancel); the popup keeps its per-device button.
  `TaildropClient.chooseFor` became `chooseFiles`. Read by the lead; module suites on both
  machines, the module's lock bed on NixOS.

## Taildrop's views reworked (2026-11-20 on)

Plan: [plans/taildrop-ui.md](plans/taildrop-ui.md), approved on two mockups.

- **The rules, file capsules, the one-panel popup (M1–M3)** — on the module's `main` 2026-11-20.
  M1: every Cancel / Skip an asking "×" (per file, per transfer, asking about the ids it
  cancels); warning tone for stalled, failed and refused files; "Send now" / "Fetch now" on
  every queued file (a forced start past the device's slot and the limit of 4, never beside a
  same-named file to that device, then greyed with the reason); a stalled file offers only its
  "×"; the notification's "Send now" for the device's first waiting file across its
  transfers; `pageSummary`; Send turns into the asking "×" while the page's sends run. M2:
  `TaildropFileCard` (name alone on line 1; state, buttons and bar inside) and one keyed
  `TaildropFileList` with group headers and rules, used by the popup's files panel. M3: the
  one-panel popup per the plan (stalled line, "b.txt · Queued [Send now]", Clear). Reviewed
  (M1: two fixed), module suites and stand-ins on both machines, the module's lock bed on NixOS.
- **The side panel and headings with controls (C1, module API 1.34)** — on `master` 2026-11-20.
  Public `SidePanel { open; title; size: "s"|"m"|"l"; content; onClosed(reason) }` (close,
  outside, escape, replaced, page, lock; content built on open, destroyed after sliding out;
  widths `Theme.sidePanelWidths` 320/420/520 grown with the font, at most 90 % of the page;
  refused outside a module page or while locked); its state kept in `ApiElements`, nothing
  reachable through the element. Module pages render in `components/ModulePageFrame.qml`
  (scrolling + the panel layer). `SectionTitle` / `Heading` take controls at the right end.
  `ModuleTestKit.pageFrame`. Wi-Fi's own drawer untouched (C2 optional). Reviewed (a panel
  sliding on window resize and content outliving its page fixed); `tests/run-all.sh` passed on
  both machines.
- **The side panel on the page; "Web console" (M4, M6)** — on the module's `main` 2026-11-20
  (manifest `api` 1.34). M4: the page's Taildrop part keeps a heading, a summary row
  (`pageSummary`, warning tone) with "Files…" opening a `SidePanel` (`TaildropPanel.qml`: pills,
  files, Send / asking "×", waiting files with Save / Open folder, incoming capsules, the shared
  `TaildropFileList`); the four settings as `SettingsRow`s, controls at the row ends; a drop on
  the row only when the files can be added (`canAddFiles`). M6: "Admin console" → "Web console"
  everywhere (tooltip login.tailscale.com); the "Web interface" switch → "Share this computer's
  settings". Reviewed (M4: a silently lost drop fixed); M6 read by the lead; module suites and
  stand-ins on both machines, the module's lock bed on NixOS.
- **Taildrop off (M5)** — on the module's `main` 2026-11-20. Setting `mod.tailscale.taildrop`
  (on by default), its switch in the "Taildrop" heading; `TaildropRules.offState`: off → no
  sending (page, popup, IPC), no arrival notifications, no auto-save, no new progress
  notifications; files already running finish, every send file not started stops ("Stopped:
  Taildrop off", `offStop`); the page says Tailscale still accepts files into its inbox; Save by
  hand works (the popup keeps Save and the count, the bar badge goes). Turning on again announces
  what came meanwhile once (Save) and does not auto-save it. Soft only (no daemon setting, the
  owner's answer). Reviewed (queued sends after off and a silent save on re-enable fixed);
  module suites and stand-ins on both machines, the module's lock bed on NixOS.
- **"Save in…" (M8)** — on the module's `main` 2026-11-20. While auto-save or Taildrop is off,
  every place offering to save received files (arrival and re-enable notifications, the popup,
  the side panel) offers "Save" and "Save in…" (`saveOffers`): a folder chooser, then the files
  waiting when pressed are saved there for that one save through the same per-file script and
  folder checks; the settings folder unchanged. A cancel saves nothing; "blocked: locked" says
  so; late answers (account change, stop) do nothing; a notification's "Save in…" acts as
  offered (`saveInOffer`); refused up front when the list is not read. Reviewed, fixed; module
  suites and stand-ins on both machines, the module's lock bed on NixOS.
- **Taildrop views, docs (M7, the docs part)** — on the module's `main` 2026-11-20. features,
  architecture, ipc, limitations, README; the Unreleased CHANGELOG merged into short lines
  ("Needs … 1.34" kept, no version bump). Read by the lead; module suites on both machines.
- **Taildrop views after the mockup on the real code** — on the module's `main` 2026-11-20 (the
  owner's notes). The device group's cancel is "Cancel all" asking "Cancel all?"
  (`groupCancelOffer`); no greyed Save with auto-save on and nothing waiting; a device's files
  oldest send first; "Send now" / "Fetch now" with a visible face (`ConfirmButton.outlined`);
  the page summary in parts, warning only on problems; the two-panel popup's device row says
  "No progress" / "N failed". Read by the lead; module suites and stand-ins on both machines,
  the module's lock bed on NixOS.
- **The bar wave and the status pill (C3, module API 1.35)** — on `master` 2026-11-20. Public
  `ProgressBar.wave` (a band through the fill every `Theme.duration("progressWave")` 300 ms; a
  fixed gradient, only moved; only in a shown window with something filled; none with reduce
  motion); the notification card's bar waves while the job runs and grew in the last 10 s. New
  public `StatusPill` (icon, label, kind, parts with tips and lines, `expanded`, `toggled`).
  Reviewed (the wave's per-frame cost and hidden-window runs fixed); `tests/run-all.sh` passed
  on both machines.
- **Status pills, nine statuses, the wave in the module (M10, M11)** — on the module's `main`
  2026-11-20 (manifest `api` 1.35). M10: the nine statuses (icon, kind, words; failed danger,
  stalled warning), `fileStatus` (one status per file), `statusPills` (Sending X/Y, Receiving
  X/Y, parts with tips and lines; Sent N/N, Sent X/Y · ✕n, Off · n in inbox, "No transfers";
  inbox files of running saves only excluded), the notification body "name · i of n" (the
  running file) with "Skip" only. M11: the page's summary as `StatusPill`s (expand on click),
  `TaildropStatusIcon` before the state in capsules and popup lines, `ProgressBar.wave` on
  moving bars. Reviewed (M10: an inbox file counted nowhere fixed); module suites and stand-ins
  on both machines, the module's lock bed on NixOS.
- **Status pills, docs and a fix (M12)** — on the module's `main` 2026-11-20. A pill whose
  parts drop to none folds for good (`pillExpanded`); docs and CHANGELOG for the pills, the nine
  statuses, the wave and the notification. Module suites on both machines. Mockup on the real
  code: `~/src/h2s-mockups/taildrop-status-pills-implemented/`.
- **Several slower waves; the capsules' words and the save group (C4, M13)** — 2026-11-20 (the
  owner's notes on the mockup). Core: `ProgressBar` keeps a pool of 6 bands; a new one every
  `progressWave` (300 ms), each crossing in `progressWaveTravel` (1200 ms), about four at once
  (`ApiElementRules.progressWaveSchedule`). Module: capsules read "Sending · 67 %" / "Saving ·
  12 %"; a "Receiving" header over incoming files; the save group "Saving to Downloads · N
  files" right after them. Read by the lead; core `tests/run-all.sh` and module suites on both
  machines.

## The notification flow (2026-11-20 on)

Plan and analysis: [plans/notification-flow.md](plans/notification-flow.md), approved on the
interactive mockup `~/src/h2s-mockups/notification-queues-planned/`.

- **Three toast queues; "×" dismisses; the centre and fullscreen (slices 1–3)** — on `master`
  2026-11-20. `ToastRules`: the queue of a notification (critical / staying / ordinary; resident
  stays unless `notifications.residentHide`; the shell's jobs keep their own time; "Apps choose
  how long" off turns an app's "stay" into counting but not critical, resident or jobs), per-queue
  limits (`criticalToastLimit` 1, `stayingToastLimit` 1, ordinary as the layout), badges (the
  critical one outlined), requeue on a change of timing, modal data for slice 4, announce
  effects. `Notifications.qml` drives one state through them; `hud/ToastStack.qml` shows the
  three stacks. The toast's "×" / swipe dismisses; an action on a resident toast keeps it;
  opening the centre hides only ordinary toasts; "Show toasts" off drops what waits; fullscreen
  "Don't show" keeps only critical toasts; lock / screensaver never pause (lock bed).
  `maxStayingToasts` removed (unset on both machines, no migration). Reviewed (each slice; two
  medium in slices 1 and 3 fixed); `tests/run-all.sh` passed on both machines.
- **Movable and pinned toasts (slice 4)** — on `master` 2026-11-20. Critical and staying toasts
  drag out by their title line (grip) and become modals (accent outline, slot freed, kept on the
  screen); every centre entry has a pin that puts it on screen as a modal (left of the toasts'
  column, stacked); a pinned ordinary toast stays until unpinned (`keep`), a finished job counts
  down; "×" dismisses. Kept in the HUD's overlay with one input-mask rectangle per modal (lock
  bed `toast-modal`: clicks beside it reach the window below). `notifications.movableToasts` on
  by default. Reviewed twice (a dragged pinned toast vanishing, a refused drop off the mask —
  fixed); `tests/run-all.sh` passed on both machines.
- **Settings rows; the HUD off the bar; pinned toast fixes (slice 5)** — on `master` 2026-11-20.
  Settings → Notifications: "Critical toasts shown, at most", "Toasts that stay, at most", "Move
  toasts by dragging", "Resident notification hide" (schema field `info`: an info icon with a
  tip, tap-readable). The HUD overlay ignores exclusive zones and keeps everything clear of the
  bar on any edge (`BarGeometry.reservedInsets`): toasts, badges, drops, pin spots, the volume
  OSD, the shell pill (lock bed `toast-modal`, `hud-bar-bottom`). From the owner's live test: a
  pinned toast has no countdown bar; a pin from the centre lands on the centre's screen.
  Reviewed (the HUD over the bar fixed); `tests/run-all.sh` passed on both machines.
- **Finished-job marks, action buttons, toasts beside the centre (slices 6–7 and live fixes)** —
  on `master` 2026-11-21. A finished job shows ✓ / ✗ beside its summary and, on a toast that
  counts down, no progress bar (`NotificationRules.progressView`); the centre and lock preview
  keep the bar. Action buttons and the reply's Send are `SmallButton`s of the new `buttonLook`
  kind "action". From the owner's live test: with the centre open, critical and staying toasts
  stand left of it (`Notifications.centreArea`, `ToastRules.stackEdge`, reported once the panel
  settles); a queue's badge opens or closes the centre on its own screen
  (`ToastRules.badgeClick`; lock bed `toast-centre`, two outputs). `AnchorsTest` waits for the
  General page's layout (the flake seen four times). Reviewed; `tests/run-all.sh` passed on
  both machines.
- **Notification docs (slice 8)** — on `master` 2026-11-21. docs/FEATURES.md "Notifications"
  rewritten (toasts, moving and pinning, progress, the shell's own notifications);
  docs/ARCHITECTURE.md "Notifications and toasts"; the Unreleased CHANGELOG merged. The
  notification flow plan is complete.

## Tracker housekeeping (2026-11-21)

Moved out of the tracker as done; checked against the code and the sections above.

- **Order of work, step 4: UI anchors replace today's slots** (U4a–U7b) — done 2026-11-19 (see
  "API plan and the work around it").
- **Order of work, step 6: the Tailscale module's migration** (M1–M11: every workaround
  removed, the exit node per network on the cards, the manual "for now" override) — done
  2026-11-19; only the closing slice (Z) is left, kept in the tracker.
- **Taildrop's views reworked** — built and live 2026-11-20 (core API 1.35, manifest 1.35); the
  owner approved the result on the mockup of the implemented pills. C2 (the Wi-Fi drawer on
  `SidePanel`) stays in the tracker, optional.
- **Open points answered by the owner**: Taildrop's words (D1) kept, the held-back file rule
  confirmed (2026-11-20) — now under the tracker's Decisions; the release holding the
  sender's-time toasts is a minor (2026-11-20).
- **Left open by done work, since fixed**:
  - the HUD's overlay started below the bar (toasts 40 px low) — notification flow slice 5
    (`BarGeometry.reservedInsets`);
  - `AnchorsTest`'s General page rows read -28 wide under load — the test waits for the
    page's layout (notification flow slices 6–7);
  - the popup showed only the newest popup send per device — D5 (a second send shows on the
    device's line, Cancel stops both);
  - a save stopped after its rename showed "Skipped" — `outputAfterCancel` (API 1.33) wired by
    the module;
  - unlimited runs (sends, saves) not ended with the shell — `endWithShell` (API 1.33), taken
    by Taildrop's runs;
  - `PrivilegedMark` `visible: need !== ""` showing the lock for `need: "yes"` — the marks now
    bind `need` (M10);
  - certificates in `h2s-shell/tailscale/certs` — in the module's data directory (M5).
- **Duplicates dropped**: the open points on the progress handle (N2) and progress
  notifications for modules (N3) stood twice; four leftovers (`AnchorsTest` under load during
  N2, the run token in `gdbus`'s argv, `Api.module` handing out handles, a `TaildropLiveTest`
  check during D7) stood twice.
- **"Running a session cheaply"** (the owner's advice) moved to `notes/workflow.md`.

## The overnight run (2026-11-21/22)

- **Lock before sleep off by default; the versioning rule; the deploy check; worktrees (order of
  work 0(b), 0(e), step 2's first two items)** — on `master` 2026-11-21. `lockscreen.lockOnSleep`
  defaults to off (schema, `LockRules.initial`, `Lockscreen` through the pure
  `LockRules.lockOnSleepSetting`); an unreadable config fails safe to on (`Profiles.configFailed`,
  `ProfileRules.configReadFailed` / `profilesBroken`); existing configs keep their stored value.
  Lock-bed scenario `sleep-default`. The versioning rule says the same in the CHANGELOG header,
  `Version.qml` and CLAUDE.md. `tests/device/deploy-check.sh`: two read-only shell IPC calls
  (`modules list`, `tailscale state`), the reached instance's log scanned for repeated lines,
  python3 from `tests/lock/resolve.sh`; self-test in run-all; the last step of "Deploying".
  workflow.md: a worktree per agent, modules against `~/src/core-pin`. Reviewed (the default
  untested end to end, the unreadable config — fixed); `tests/run-all.sh` passed on both
  machines; the deploy check PASSED on the live shell.
- **Two flaky core tests fixed** — `AnchorsTest` (waits for the General page's layout, earlier)
  and `ToastDragTest` (waits for the toast to settle before reading its start; reproduced 6/6
  under load before, 0/6 after).
- **Architecture clean-up A1–A6 (network)** — on `master` 2026-11-22. A1 VpnProvidersTest reads
  `Notifier.recorded`; A2 `NetworkRules` split into `VpnWithNetworkRules`, `VpnProviderRules`,
  `VpnLockdownRules` (pure move); A3 `VpnProviders` out of `VpnManager` (forwarders); A4 the
  editor's save finishes in `NetworkProfiles.saveConnection` (link and kill switch written even
  if the page closes; only the newest save of a profile writes them; plain Save off while a
  "Save and reconnect" runs; a revert by "Keep these settings?" puts them back); A5
  `NetworkProfileCard` without I/O; A6 `Bar.qml` through `Modules.initialProperties` (the same
  owner check stays in WidgetSettingsPane.qml:228 and Popup.qml:636). Reviewed (an older save
  overwriting a newer — fixed); `tests/run-all.sh` passed on both machines.
