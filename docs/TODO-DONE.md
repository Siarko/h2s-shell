# TODO — done

The items of [TODO.md](TODO.md) that are done, with their numbers, their notes and how
they were verified — kept for the decisions and the analysis behind them, which the
commits and the docs refer to by number. Stages 1–10 as they stood when closed, then the
done items of stage 11 in number order. User-visible changes are in
[CHANGELOG.md](../CHANGELOG.md).

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
      Plan: docs/plans/bar-position.md (setting per profile, tokens relative to the edge,
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
