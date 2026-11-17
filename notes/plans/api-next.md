# Module API: the next versions (1.4 → 2.0)

Status: a plan, for the owner to approve. Nothing here is built.

Leads came from `notes/reviews/architecture-2026-11-16.md` (sections 3, 8.6, 8.8, 8.9 and 9).
Every item below was checked again in the code. References are to the shell at
`plan-architecture` (`953493e`+) and to the Tailscale module at `dd5ebdb`
(`/home/h2s/src/h2s-shell-tailscale-wt`, written `ts:` below; `TC` is
`ts:module/TailscaleClient.qml` and `TR` is `ts:module/TailscaleRules.qml`).

**The rule this plan serves (the owner's).** The shell and the module have the same author. A
module never works around the API. When a module needs something the shell should give, the API
grows. When this plan is done, the Tailscale module has no workaround left. The next module
author will not need new ones for the same kinds of needs.

---

## 1. Inventory

"Same need in the shell" names other shell code that solves the same problem by hand. That
code moves onto the new API too. "Not API" means a module-side change, with the reason.

### 1a. Running commands

| # | What the module does today | Why | Same need in the shell | Answer |
|---|---|---|---|---|
| 1 | Its own process factory with a watchdog, `abandon()` and output chunks: `TC:480-490`, `TC:1946-2028` | `CommandAction` has no time limit, no cancel, no streamed output, no separate stdout/stderr text | `ModuleHost` hand-rolls 4 Process blocks with deadline Timers: `singletons/ModuleHost.qml:535-547, 840-870, 872-895, 902-933`; lock screen probes `singletons/Lockscreen.qml:874, 918, 940` (5.3: they re-implement `CommandQuery`); `api/Api.qml:107` (`_opener`) | **`CommandRunner`** (§2.1) |
| 2 | Wraps every command in coreutils `timeout -k` by hand: `TC:495-503`, `TR:2225` (`timed`) | Nothing in the API stops a hung command | `Lockscreen.qml:922` (`timeout 2 hyprctl` inside a string) | `CommandRunner` `timeoutMs` (§2.1) |
| 3 | A long-lived stream (`curl … watch-ipn-bus`) declared as a bare `Process`, restarted with a backoff: `TC:765-793`, `TC:2030-2039` | No streamed run in the API | `singletons/network/NetworkEvents.qml` (`nmcli monitor`), `singletons/lock/LogindMonitor.qml` | `CommandRunner` with `timeoutMs: 0` and `onLine` (§2.1). The backoff stays the module's: it is a policy |
| 4 | Generation tokens so late answers are dropped: `TC:292, 361-364`; in every sub-client (`ts:module/CertClient.qml:38-40`, `LockClient.qml:51-55`, `ServeClient.qml:62-64`, `TaildropClient.qml:201-208`) | A `CommandAction` callback fires even after the owner stopped | `ModuleHost` `_storeDirectoryKnown` / `_guardKnown` guards (`ModuleHost.qml:524-528, 569-571`) | `CommandRunner`: no callback after `cancel()`, after `cancelAll()` or once the runner is destroyed (§2.1) |
| 5 | The elevated login runs `[pkexecPath, …]` itself (`TC:1840-1866`) | `PrivilegedAction` cannot stream output, and the login URL must be read while `tailscale login` waits | — | **`PrivilegedAction.start()`** with streamed output (§2.2) |
| 6 | It keeps two `PrivilegedAction`s, `_admin` and `_adminSpare` (`TC:1462-1464, 1937-1943`) | A `PrivilegedAction` queue stays blocked while an abandoned root process runs to its time limit | — | `start()` handle `cancel()` leaves the queue at once (§2.2) |
| 7 | Maps pkexec's codes again and reports 127 itself (`TR:2114`, `TC:1520-1535`, `TC:1868-1875`) | It ran pkexec outside the API (#5) | `Authentication.reportDenied` is the shell's way | Goes away with #5 (§2.2) |
| 8 | Sets `PrivilegedAction.elevate` to its own resolved pkexec (`TC:410-411`) | `elevate` is a public property (API 1.0, "a module's suites put a stand-in here") | — | The shell picks pkexec. In test mode it picks the stand-in. `elevate` stops being writable in 2.0 (§2.2, §2.11) |
| 9 | Finds tailscale, timeout, pkexec and curl by hand. It also judges whether the user could replace them (root-owned or Nix store): `TC:367-428`, `TR:2176` (`toolsProbe`) | `PrivilegedAction` checks only "absolute and executable" (`api/PrivilegedAction.qml:174-183`). A user-writable program would run as root | `ModuleHost._checkPrograms` finds names on PATH but returns no path and no verdict (`ModuleHost.qml:786-799`) | **`module.programs`** with a trust verdict. `PrivilegedAction` refuses untrusted programs (§2.3) |
| 10 | Runs `systemctl` and `xdg-open` by name, unchecked (`TC:1619-1630`, `TC:1656-1695`; review 8.11) | No path resolution in the API | — | `module.programs` (§2.3), and `Api.openUrl` in test mode (§2.10) |

### 1b. Test seams

| # | What the module does today | Why | Same need in the shell | Answer |
|---|---|---|---|---|
| 11 | Reads `H2S_TAILSCALE_TOOLS` and `H2S_TEST_MODULES` to pick stand-ins (`TC:300-317`). With the seam set, no trust check runs, so pkexec could run `$seam/tailscale` | Only an env variable can tell it that it runs under tests | Lock screen: `H2S_LOCK_TOOLS` and friends (`Lockscreen.qml:122-150`, review 5.4) | **Test mode** set by the shell, plus manifest `testPrograms` (§2.10) |
| 12 | IPC calls count as "the user" (no prompt guard) when the tools seam is in use (`ts:module/Main.qml:316-322`) | Same as #11 | — | `Api.testMode`, read-only and set only by the shell (§2.10) |
| 13 | Opens links with the seam's `xdg-open`, not with `Api.openUrl` (`TC:1656-1695`) | `Api.openUrl` would open a real browser in a test | — | In test mode `Api.openUrl` records the call and opens nothing (§2.10) |
| 14 | Directory seams from the environment: `H2S_TAILSCALE_FORWARDING_DIR` (`TC:1191-1195`), `H2S_TAILSCALE_CERT_DIR` (`ts:module/CertClient.qml:17-25`), `H2S_TAILSCALE_DOWNLOAD_DIR` (`ts:module/TaildropClient.qml:536-545`) | The real places are found by hand (#21-#24), so tests must redirect each one | — | Come from `Api.system` and `module.dataDirectory`, which tests can set (§2.7, §2.10) |
| 15 | Its suite reaches the host: `module.host.widgetEntries`, `module.host.setEnabled` (`ts:module/tests/TailscaleModuleTest.qml:87, 101, 111`) | Turning the module off and on is part of what it tests | `tests-modules.qml:22` | **`ModuleTestKit`** in `qs.tests` (§2.10), so `host` can close (§2.11) |

### 1c. Structure: main, popup, pages

| # | What the module does today | Why | Same need in the shell | Answer |
|---|---|---|---|---|
| 16 | A module singleton holds the live client (`ts:module/Tailscale.qml:13-16`). Main sets it and clears it (`Main.qml:333, 337-340`). The popup, widget, page, row and card read it (`TailscalePopup.qml:21`, `TailscaleWidget.qml:22`, `TailscalePage.qml:24`, `TailscaleRow.qml:15`, `TailscaleCard.qml:19`) | Pages, popups and widgets cannot reach what the main owns | — | **`module.main`** (§2.4) |
| 17 | Adds an undocumented `client` property to its `VpnProvider` so slot contributions find the client (`Main.qml:23-24`) | Same as #16 | — | `module.main` (§2.4) |
| 18 | The popup learns its widget's preset through a singleton: the widget writes `Tailscale.popupPreset` (`TailscaleWidget.qml:36`) and the popup reads it (`TailscalePopup.qml:31-35`) | A popup panel is not told which widget opened it | `panels/Popup.qml:110-116` already carries `contentData` (the tray menu uses it); `components/PopupWidget.qml:31` passes `null` | **`opener`** given to the panel (§2.5) |
| 19 | Declares `availableHeight` and relies on the popup setting it (`TailscalePopup.qml:39-43`) | It is set by `panels/Popup.qml:578-585`. That code also sets `fitsShownHeight` and `popupAnimating`. None of the three is documented API | `NetworkPanel.qml:18`, `MusicPanel.qml:12` | Document the panel inputs (§2.5) |
| 20 | "Send file…" in the popup sets a timed request and opens the page. The page's Taildrop section opens its `FileDialog` (`TaildropClient.qml:145-156`, `TaildropSection.qml:362-412`) | A dialog owned by the popup's window dies when the popup closes | `panels/settings/WallpaperSettings.qml:283-290`, `NetworkVpnSettings.qml:70` (they work because they live in the settings window) | **`Api.chooseFiles`** (§2.9) |

### 1d. Helpers and system facts

| # | What the module does today | Why | Same need in the shell | Answer |
|---|---|---|---|---|
| 21 | Runs `id -u; id -un` (`TC:444-453`) | No user identity in the API | — | **`Api.system.userName` / `uid`** (§2.7) |
| 22 | Runs `cat /proc/sys/kernel/hostname` (`TC:431-441`) | No host name in the API | — | `Api.system.hostName` (§2.7) |
| 23 | Runs `ip -o addr show scope global` for the LAN subnets (`TC:457-470`) | No local addresses in the API | `singletons/network/IpManager.qml:12-15` has one address per kind, as text. `Nmcli.qml:207` parses `IP4.ADDRESS` lists | **`Api.localNetworks`** (§2.8) |
| 24 | Reads `HOME`, `XDG_CONFIG_HOME` and `XDG_DATA_HOME` with `Quickshell.env`, and parses `user-dirs.dirs` with `cat` (`TaildropSection.qml:395, 401`, `TaildropClient.qml:536-555`, `CertClient.qml:24`) | No user directories in the API | `NetworkVpnSettings.qml:73` (`Quickshell.env("HOME")`) | `Api.system.home`, `downloadDirectory`, … (§2.7) |
| 25 | Builds its own folder under the shell's data name: `$XDG_DATA_HOME/h2s-shell/tailscale/certs` (`ts:module/CertRules.qml:34-38`) | No per-module data directory. The store holds JSON only | — | **`module.dataDirectory`** (§2.7) |
| 26 | Reads `/proc/sys/net/ipv4/ip_forward` and IPv6 forwarding with `sh -c cat` (`TC:1191-1215`) | No such fact in the API | — | `Api.system.readIpForwarding()` (§2.7). Any module that shares a network needs it |
| 27 | Copies `Format.bytes` and `Format.ago` (`TR:2598-2631`, "the shell's Format is a core singleton modules may not import") | No formatting in the API | `singletons/Format.qml` | **`Api.format`** (§2.6) |
| 28 | Parses IPv4, IPv6 and CIDR, and tests overlap (`TR:2633-2766`). It also hides addresses in text (`TR:2143`, `withoutAddresses`) | No address helpers in the API | `singletons/network/NetworkRules.qml:19-45, 182-210` (`isIpv4`, `isCidr4`, `inSubnet4`), a second partial copy | **`Api.address`**, backed by one core `AddressRules` (§2.6) |
| 29 | A 5 s clock writes `now`, which re-derives the whole state (`TC:172, 2100-2105`; review 8.5) | No shared slow clock | `singletons/Time.qml` (1 s) | **`Api.minuteNow`** (§2.6). The one-shot timers for grace periods are the module's (8.5) |
| 30 | Escapes markup in notification bodies (`TaildropClient.qml:355-360`). It also strips a leading "-" (`Main.qml:49-54`) | The shell reads the body as markup. The "-" fix is obsolete: `Notifier.command` puts `--` before the texts (`singletons/Notifier.qml:24-26`) | — | `notify(…, { format: "plain" })` (§2.6). The module drops the "-" strip now (not API) |
| 31 | Logs once per change of outcome (`TC:516-528`, `TR:898` `logChange`) | No module logger. Polling a daemon would flood the log | `components/Logger.qml` (gated by `general.debug`, no dedupe) | **`module.log`** (§2.6) |

### 1e. Network facts

| # | What the module does today | Why | Same need in the shell | Answer |
|---|---|---|---|---|
| 32 | Treats an empty `Api.networks` as "not read yet" and does nothing (`ts:module/NetworkExitClient.qml:91-96`) | Empty is ambiguous: no networks, or not read yet | — | **`Api.networksReady`** (§2.8) |
| 33 | — (a shell bug the module inherits) `Api.networks` can list a hotspot for a moment: `listRead` turns true before the Wi-Fi `mode` is read (`api/Api.qml:61-63`, `ModuleRules.qml:1261-1280`; review 3.10) | — | — | Hold Wi-Fi rows back until their details are read (§2.8) |
| 34 | Shows "Another VPN is also on" beside any other VPN, even a split one (`TailscalePage.qml:486-487`). `twoVpnsNote` assumes the other VPN wants all traffic and sets DNS (`TR:2582-2595`) | `Api.vpnsUp` and `otherVpnsUp` give names only | `NetworkRules.qml:139` (`neverDefault`) and `:604-618` (`allowedIps`) are read for the editor only | `vpnsUp` rows get `fullTunnel`, `setsDns` and `routes` (§2.8) |
| 35 | Keeps an exit node per network in its store, keyed by `Api.networks` ids (`NetworkExitClient.qml:31-33, 59-62`). Its editor is on the module's own page (`ts:module/NetworkExitTable.qml`) | No per-network place in the shell. The shell keeps its own table, `system.vpnWithNetworks` | `system.vpnWithNetworks` (`VpnManager.qml:474-475`) | A **`network.profile.card` slot**. The data stays in the store (§2.8; owner question Q4) |

### 1f. UI, terminal, reach

| # | What the module does today | Why | Same need in the shell | Answer |
|---|---|---|---|---|
| 36 | Offers "Copy ssh command" (`ts:module/DeviceRow.qml:107-109`) | No way to start a terminal, and no terminal setting | — | **`Api.openTerminal`** and a `general.terminal` setting (§2.9) |
| 37 | Uses 13 `qs.components` types. Only `VpnProvider` is specified: `PopupWidget`, `BarRow`, `BarText` (`TailscaleWidget.qml`), `SmallButton` (11 files), `InputField` (5), `Dropdown` (3), `Pill` (2), `ToggleSwitch`, `Checkbox`, `DeleteButton` (4), `PointerArea` (2), `PrivilegedMark` (6) | `qs.components` is allowed but not versioned (review 3.1) | `api/Api.qml:7` reads `qs.singletons.network` names (review 3.1) | **Wrap them in `qs.api`**, pinned by a test (§2.11) |
| 38 | — (shell side) `ModuleHandle.host` is public (`api/ModuleHandle.qml:27`). `Api.module(id)` hands out other modules' handles (`api/Api.qml:68-70`) | — | — | Close both (§2.11) |

### 1g. Module-side items (not API)

| # | What | Why it is not an API matter |
|---|---|---|
| 39 | Sub-clients call `client._spawn`, `_runChange`, `_runLocked`, `_finish`, `_opProcess` (review 8.6; for example `ServeClient.qml:85-90`, `NetworkExitClient.qml:150`) | The operation lock, "plain first, then pkexec on Access denied" and "prepare under the lock" are Tailscale logic. Once #1 and #5 land, the module builds its own `TailscaleRunner` on `CommandRunner` and `PrivilegedAction.start` |
| 40 | `_isObject`, `_get`, `_string` and `_number` are copied in five Rules files (`TR:138-171`, `TaildropRules.qml:35-53`, `ServeRules.qml:43`, `LockRules.qml:17`, `NetworkExitRules.qml:23`) | Defensive JSON reading is module-internal. One module helper file is enough |
| 41 | `jsonFeed`, a streaming parser behind a newline splitter (`TR:1797`) | With `onLine` from the runner, one `JSON.parse` per line may be enough if the bus sends one object per line (unverified). Either way it is module code |
| 42 | Taildrop preferences live in `module.store` (`TaildropClient.qml:45-89`) | `mod.<id>.*` settings with `global: true` and `module.setValue` already cover them. The module declares them (review 8.12) |
| 43 | Checks for older shells: `Main.qml:331`, `TailscaleWidget.qml:25`, `TailscalePopup.qml:33`, `TailscaleWidgetSettings.qml:21` | Dead once the manifest asks for the new minor |

Checked and found to need nothing: IPC (`IpcHandler` from `Quickshell.Io`, `<id>` targets),
`Api.copy`, `Api.openSettings`, `module.openSettings`, `setFact`, own settings, `module.store`
as data (`lastTailnet`, `exitByNetwork`), `module.resumed()`, `shown` on pages and sections.

---

## 2. API design

Common rules for everything below:
- **Callbacks, not promises.** The API already uses `done(result)` everywhere.
- **Results are plain frozen objects.** Errors are fields, never exceptions. Bad input gives a
  result with `error` set; it never throws.
- **Module unload.** Every object a module makes from `qs.api` lives under its main or its
  views. When the module goes off, the host destroys them, and they stop: no callback runs
  after that.
- **Shell reload.** Quickshell rebuilds everything. Plain processes started under the runner's
  `timeout` wrapper end by themselves at their limit. Root processes end at their `timeout`
  inside pkexec.
- **Session locked** (`Lockscreen.locked`; new read-only `Api.sessionLocked`). Plain runs
  continue: a VPN must still follow the networks. Nothing that asks the user for anything
  starts: no password prompt, no dialog, no terminal. Those return `blocked: "locked"`.
- **Trust model** (review 3.3; to be written in ARCHITECTURE's Modules section). Modules run in
  the shell's process. That process also runs the lock screen's PAM prompt and the polkit
  agent. QML has no sandbox. A module can import `Quickshell.Io` and run anything. So the
  guards below catch mistakes, not malice. They make the right way the easy way, and they keep
  test stand-ins away from real pkexec.

### 2.1 `CommandRunner` (1.4): plain commands

**Decision: a new core type, with the old helpers rebuilt on it.**
- A new core type, `singletons/io/CommandRunner.qml`. The lock screen and `ModuleHost` may use
  it, and it knows nothing of modules.
- `api/CommandRunner.qml` is `Io.CommandRunner {}`, as `CommandAction` is today.
- `CommandAction` and `CommandQuery` keep their contracts and become thin wrappers on it.

Why not extend them:
- `CommandQuery` *is* a `Process` (`singletons/io/CommandQuery.qml:5`), so every Process
  property is its surface.
- `CommandAction` is a one-at-a-time queue with positional arguments.
- Handles, cancel and parallel runs are a different model. Grafted onto either, the 1.0
  semantics would change.

Surface:

```
CommandRunner {
    property var environment: ({})      // added to every run's environment
    property int maxParallel: 8         // more runs wait in order (a guard against loops)
    readonly property int running       // runs started and not ended
    readonly property int waiting
    function start(argv, options) → RunHandle
    function cancelAll()                // every run: as RunHandle.cancel(); no callbacks after
}

options = {
    timeoutMs:   30000     // 0: no limit (a stream). The limit is enforced twice: coreutils
                           // `timeout -k <killAfter> <s>` around the command (resolved by the
                           // shell, trusted), so it ends even if the shell dies; and a watchdog
                           // in the runner, for when timeout(1) is missing
    killAfterMs: 3000      // TERM, then KILL this long after
    environment: {}        // merged over the runner's (the way to pass a secret)
    workingDirectory: ""   // absolute, or "" (the shell's)
    stdin: ""              // written once at start (Process.stdinEnabled + write())
    onStdout: text => …    // raw chunks as they come (SplitParser splitMarker "")
    onStderr: text => …
    onLine:   (line, stream) => …   // or lines ("stdout" | "stderr"); not with onStdout/onStderr
    keepOutput: true       // collect stdout/stderr for done (capped: maxOutputBytes)
    maxOutputBytes: 1048576
    done: result => …
}

result = { ok, code, stdout, stderr, timedOut, cancelled, failedToStart, truncated, durationMs }
RunHandle = { id, running (bool, read at call time), cancel() }
```

Semantics:
- `argv` must be a non-empty array of strings. `argv[0]` is an absolute path or a name.
  `sh -c` is allowed as before: pass values as `$1…`, never pasted into the script.
- `done` runs exactly once. The exceptions are cancelled runs (below) and a runner destroyed
  first. `ok` is code 0 with no time-out.
- `timedOut`: the code is 124 and the run took at least `timeoutMs`. A command that itself
  exits 124 sooner is not a time-out. Document this, as `PrivilegedAction` does for 126/127.
- `failedToStart`: Quickshell emits no `exited` when the program cannot start; `running` just
  turns false. The module copes with this in `TC:1999-2009`. Seen in that code; not checked in
  Quickshell's source.
- `cancel()`, while waiting: the run is dropped. While running: TERM to the `timeout` wrapper
  (it passes the signal on), then KILL after `killAfterMs`, using `Process.signal(int)`, which
  0.3.2 has (checked in `quickshell-io.qmltypes`). `done` is called once with
  `cancelled: true`. Callbacks for chunks or lines stop at once.
- Destroyed (module off, view gone): every run is cancelled and no callback runs. The runner
  signals its processes itself in `Component.onDestruction`. Whether a destroyed `Process`
  kills its child is unverified, so we do not rely on it.
- Order: runs start in call order up to `maxParallel`. There is no global lock. A module that
  needs "one change at a time" keeps its own lock (#39).

Security:
- Nothing new: a module can already run anything through `Quickshell.Io`.
- Output is capped, so a chatty process cannot fill memory.
- The runner never uses a shell itself.

Tests:
- A new `tests/CommandRunnerTest.qml`, using `sh -c` scripts.
- Cases: time-out (code and `timedOut`), cancel while waiting and while running, KILL after a
  TERM trap, separate stderr, lines split across chunks, the output cap, a program that cannot
  start, no callbacks after destroy, `maxParallel` order.
- The `CommandAction` and `CommandQuery` suites stay as they are.

Replaces in the module: `_spawn`, `_processComponent`, `_timedArgv`, `_watchdogMs`, `_alive`
and the generation checks, the bare `_stream` Process, and `_misc` (#1-#4). In the shell: the
4 `ModuleHost` Process blocks with their deadline Timers, and the 3 `Lockscreen` probes.

### 2.2 `PrivilegedAction.start()` (1.4): root, streamed, cancellable

**Decision: extend `PrivilegedAction`; do not add a second type.**
- It is the one gate to pkexec. It holds the denial report (`Authentication.reportDenied`),
  the `notFound` check and the queue.
- Two types would split them.
- `run(command, what, done, environment)` stays as it is.

```
PrivilegedAction {
    readonly property bool available        // the shell found trusted pkexec and timeout
    readonly property string unavailableReason
    function start(argv, options) → RunHandle
}
options = {
    what: "Connecting Tailscale",  // shown in failure notices; required
    timeoutMs: 120000,             // required, 1 s … 1 h: pkexec <timeout> -k 5 <s> <argv…>
    onStdout, onStderr, onLine,    // as CommandRunner
    notifyFailures: true,
    done: result => …
}
result = { ok, code, stdout, stderr, dismissed, refused, notFound, timedOut, cancelled,
           blocked ("" | "locked" | "untrusted" | "no-user-action"), error }
```

Semantics:
- **Queue.** One password prompt at a time, shell-wide (today the queue is per instance). A
  run leaves the queue when it ends or when it is cancelled, even if its root process still
  runs. That removes the need for `_adminSpare` (#6).
- **Time limit.** The shell puts its own trusted `timeout` inside pkexec. The limit starts
  after the password is accepted. A run that is still prompting is the agent's to end.
- **`cancel()`.**
  - While queued: dropped.
  - While the prompt shows: the shell signals pkexec, which still runs with the user's real
    uid at that point (unverified). If the shell's own agent shows the prompt, it closes it.
    The result is `cancelled` and `dismissed`.
  - After the program started as root: the user cannot signal it. The run stops waiting and
    the root process ends at its `timeout`. `done` gets `cancelled: true`.
  - Docs must say: "cancel stops waiting; a root process ends at its time limit".
- **Refusals before pkexec runs:**
  - `blocked: "untrusted"`: `argv[0]` must have a trusted verdict (§2.3). This is a tightening:
    today any executable absolute path passes. See §3.
  - `blocked: "locked"`.
  - `blocked: "no-user-action"`: only if the owner takes Q5.
  - `notFound`: kept.
- **The click rule (Q5).** The shell stamps the time of the last pointer press, tap or key
  press in a shell window (popup, settings, bar). `start()` and `run()` refuse when the last
  stamp is more than 10 s old. Nothing in the API can then ask for a password without a user's
  action. IPC calls and timers get `blocked`. It guards against mistakes only: a module could
  still run pkexec through `Quickshell.Io` (see the trust model).
- **Environment.** pkexec clears it. As today, pass values as arguments, never secrets.

Tests:
- Extend the `PrivilegedAction` cases in a shell suite, with a stand-in pkexec that prints and
  sleeps.
- Cases: streaming, cancel while queued, cancel after "authorised", a second run not blocked
  by a cancelled one, `timeoutMs` in the argv, all three `blocked` reasons, 127 reported once.

Replaces in the module: the elevated login's own spawn (`TC:1840-1866`), `_adminSpare` and
`_freeAdmin`, its own 127 mapping, `elevationProblem` (`TC:143-145`; it reads `available`
instead), and setting `elevate` (#5-#8).

### 2.3 `module.programs` (1.4): finding and trusting programs

Manifest, new optional fields:
- `"optionalPrograms": ["tailscale", "curl", "systemctl", "openssl"]`: looked up like
  `programs`. A missing one does not stop the module.
- `"testPrograms": "tools/stand-in"`: a directory inside the module, used only in test mode
  (§2.10).

Handle:

```
module.programs     // frozen { name: { path: "/abs/…" | "", trusted: bool, reason: "" } }
                    // for `programs` + `optionalPrograms`; {} until first resolved
module.programsReady
module.recheckPrograms()   // look again (installed since): at most every 2 s
```

How it works:
- The host's program check (`ModuleHost.qml:786-799`) is extended to print the path, the real
  path and `stat` lines.
- The verdict comes from rules moved out of the module into `ModuleRules`. `TR:2165-2215`
  (`_statTrusted`, `toolsProbe`) are written and tested already.
- Trusted means: in the Nix store, or owned by root and writable by no one else. This holds
  for the program, its real file and both directories.
- Run once at load, again on `recheckPrograms()`, and on `resumed()`.

Security:
- `PrivilegedAction` takes `argv[0]`'s verdict from the same resolver. It refuses an
  untrusted path.
- The shell resolves pkexec and timeout itself; a module never names them.

Tests: `ModuleRulesTest` gets the verdict cases (ported from the module's suite). A fixture
module declares an optional program that is missing and one that is user-owned.

Replaces in the module: `_resolveTools` and `toolsProbe` (`TC:367-428`, `TR:2176`), and the
unchecked `systemctl` and `xdg-open` (#9, #10).

### 2.4 `module.main` (1.5): what the main owns

```
module.main     // the object made from the manifest's `main` while the module is active;
                // null while off, before it is made, or with no main
```

Semantics:
- It is a notifying property. The host sets it on the handle right after `createObject` and
  clears it before `destroy()`.
- Views read what they need through it: `module.main?.client`. Each binding must allow null:
  on disable, the main goes in the same pass that removes the views.
- It is the module's own. Once `Api.module` closes (§2.11), other modules cannot reach it.

Why not a separate "shared object" on the handle: the main already owns everything that acts,
under the lifetime contract. A second object would need its own lifetime rules.

Tests: `ModuleRegistriesTest` with the `good` fixture. It checks that `main` is set before
its widgets complete, is null when the module is off, and is a new object when it is on again.

Replaces in the module: `Tailscale.qml` (the singleton) and the extra `client` on
`VpnProvider` (#16, #17).

### 2.5 Popup panels: `opener` and the panel inputs (1.5)

Today a module's panel gets only `module` (`panels/Popup.qml:556`). It will also get these,
each only when its root declares the property:

| Property | Type | Value |
|---|---|---|
| `opener` | object, frozen | `{ widgetType, preset, edge ("top"/"bottom"/"left"/"right"), byTouch }`: the bar widget that opened it. `preset` is that bar entry's preset name, or "" |
| `availableHeight` | real | the most height the popup gives the panel before the panel must scroll (`popup.availableContentHeight`); kept current |
| `fitsShownHeight` | bool, declared by the panel | when true, the panel is sized to the height shown while the popup animates |
| `popupAnimating` | bool | true while the popup moves or resizes; kept current |

How:
- `PopupWidget.togglePopup` passes `{ widgetType, preset }` as `contentData`
  (`components/PopupWidget.qml:31, 39`), reading `preset` when the widget has one.
- `Popup` hands it on as `opener`.
- The table goes into `ModuleRules` beside `slotTable`, so docs and tests read one list.

Tests:
- `ModuleRegistriesTest`: a fixture with two bar entries on different presets. Each one's popup
  sees its own `opener.preset`.
- A panel that declares none of these gets no warning.

Replaces in the module: `Tailscale.popupPreset` and the reliance on an undocumented
`availableHeight` (#18, #19).

### 2.6 Helpers (1.6): format, address, clock, plain notifications, log

```
Api.format.bytes(n)          // "742 MB", "15.6 GB", "1.2 TB" (core Format gains TB)
Api.format.rate(n)           // "3.4 MB/s"
Api.format.ago(ms, nowMs)    // milliseconds (core Format.ago is seconds: the API converts)

Api.address.isIpv4(t) / isIpv6(t) / isIp(t)
Api.address.parseCidr(t)     // → { family: 4|6, address, bits, network ("a.b.c.0/24") } | null
Api.address.contains(cidr, ip)
Api.address.overlap(a, b)
Api.address.redact(text)     // IPv4/IPv6 addresses and prefixes → "[address]"

Api.minuteNow                // Date.now() ms, updated on each minute boundary (one shared timer)

module.notify(summary, { body, format: "plain", … })   // also Api.notify: "plain" escapes
                             // &, <, > and drops control characters in summary and body
module.log(level, text, key) // "info" | "warn" | "debug" (debug only with general.debug);
                             // prefixed "[<id>]"; with `key`: logged only when the text for
                             // that key changed (once per change)
```

Where they live:
- One pure core singleton, `singletons/AddressRules.qml`, with a suite.
- `NetworkRules.isIpv4`, `isCidr4`, `inSubnet4` and the rest delegate to it, so there is one
  implementation.
- Its source is the module's tested code (`TR:2633-2766`, `TR:2143`) with its test cases.
- `Api.format` and `Api.address` are frozen objects of functions.

Lifetime: pure functions. `minuteNow` keeps ticking while locked; it is cheap.

Tests:
- `AddressRulesTest` (ported cases plus NetworkRules' current cases).
- `FormatTest` gains TB and the milliseconds `ago`.
- `NotifierTest` gains a case for plain format.
- `module.log` dedupe gets a case in `ModulesTest`.

Replaces in the module: `bytes`, `ago`, the address code and `withoutAddresses`, the 5 s
`_clock` (with one-shot timers, 8.5), its markup escaping, and `_logOutcome`/`logChange`
(#27-#31).

### 2.7 System facts and the data directory (1.6)

```
Api.system: {
  ready,                       // true once the first read is done
  userName, uid,               // id -un / -u, read once by the core (a valid Unix name or "")
  hostName,                    // /proc/sys/kernel/hostname (FileView, no process); re-read on
                               // resume and on refresh()
  home, configHome, dataHome, runtimeDirectory,   // the XDG values, absolute
  downloadDirectory,           // XDG_DOWNLOAD_DIR from user-dirs.dirs (read, never sourced),
                               // else ~/Downloads
  isNixOS,
  readIpForwarding() → { ipv4: bool|null, ipv6: bool|null }   // synchronous (KernelFile)
  refresh()
}
module.dataDirectory           // "<dataHome>/h2s-shell/module-data/<id>", made 700 by the host
                               // before the main is created (as the stores' directory is today)
```

Notes:
- **Not under `modules/<id>`.** M4 installs modules there, and a sync would wipe the data.
- **Migration.** The module's certificates live at `…/h2s-shell/tailscale/certs` today. The
  module looks there once and moves them. Or it says where they were. This is module work.
- **Lifetime.** The shell's, read-only. Values are the same while locked.
- **Security.** All of it is already readable by any process of the user. The address list in
  §2.8 is the most sensitive: modules see the same as `ip addr`.

Tests: `SystemFactsTest`, with a fake user-dirs file and fake /proc files passed in as paths.
In test mode, `ModuleTestKit.setSystem({ … })` (§2.10).

Replaces in the module: `_readIdentity`, `_readSystemHostname`, the `Quickshell.env` reads,
the `user-dirs.dirs` parsing, the cert folder logic, the forwarding reads, and their three
`H2S_TAILSCALE_*_DIR` seams (#14, #21, #22, #24-#26).

### 2.8 Network facts (1.7)

```
Api.networksReady      // true once profiles AND their Wi-Fi details are read
Api.networks           // as 1.3; a Wi-Fi row appears only once its details are read (no
                       // hotspot window); `networksChanged` (QML's own signal) fires only when
                       // the content changes (already true; now documented)
Api.localNetworks      // frozen [{ device, kind ("wifi"|"ethernet"|"other"), family (4|6),
                       // address ("192.168.1.5/24"), network ("192.168.1.0/24") }], global
                       // scope; no VPN, tun, WireGuard or provider devices
Api.localNetworksReady
Api.vpnsUp             // rows gain: fullTunnel (true | false | null unknown),
                       // setsDns (true | false | null), routes ([CIDR], ≤ 64; [] unknown)
```

Sources:
- `localNetworks` comes from NetworkManager's device details (`Nmcli.qml:207` already parses
  `IP4.ADDRESS` lists). Whether unmanaged devices such as `tailscale0` show up there with
  addresses is unverified. The rule "drop VPN, tun and WireGuard types, and devices a provider
  names" covers both answers.
- `fullTunnel` for NetworkManager VPNs: `ipv4.never-default` and `ipv6.never-default` are
  "no", and for WireGuard some peer's `allowed-ips` holds `0.0.0.0/0` or `::/0`. The parsing
  exists (`NetworkRules.qml:139, 604-618`). It must be read for active VPNs (the
  `VpnManager.details` read, `VpnManager.qml:37-50`).
- `setsDns`: the connection has DNS servers.
- For providers, `VpnProvider` entries may set the same three fields. They are optional,
  copied through, and null when absent.
- `otherVpnsUp` in the VPN slots' context stays a list of names. It gains a sibling,
  `otherVpns`, which holds the `vpnsUp` rows.

**Per-network slot (Q4).** A new slot, `network.profile.card`: on a saved network's card in
Settings → System → Network, while it is open. Its context is
`{ slot, networkId, name, kind, active }`. A module shows its per-network choice where the
user edits that network.
- The data stays in `module.store`, keyed by `networkId`. It is data, not a profile setting.
  `system.vpnWithNetworks` stays the shell's.
- Once `networksReady` is true, a module may drop ids no longer listed. Like the shell, it
  should not prune without the user's word (review 4.4).

Tests:
- `ModuleRulesTest`: `apiNetworks` with details missing, `apiVpnsUp` with the new fields, and
  `apiLocalNetworks`.
- `ModuleRegistriesTest`: the new slot.

Replaces in the module: the "empty means not read" guard, `_readLan` (`ip -o addr`), and the
"Another VPN" guess (#23, #32-#34). The network card can host the exit-node choice (#35).

### 2.9 Terminal and file chooser (1.8)

```
Api.openTerminal(argv, { title, workingDirectory }) → { ok, blocked, error }
setting general.terminal     // string, "" = automatic: xdg-terminal-exec, then $TERMINAL,
                             // then foot, kitty, alacritty, wezterm (the first on PATH)

Api.chooseFiles({ mode: "open" | "openMany" | "folder" | "save", title, folder,
                  nameFilters }, done)   // done(paths: [absolute paths]) or done(null)
```

Terminal:
- `argv` is an array, with no shell and no control characters. The terminal is started
  detached and runs `argv` as its command: `-e` for the known terminals, `--` for
  xdg-terminal-exec.
- Refused while locked, and when no terminal is found (`error` says to set
  `general.terminal`).
- Security: a terminal shows the user what runs. It adds no power, since modules can already
  run commands.
- Tests: `TerminalRulesTest` for the argv per terminal.

File chooser:
- The shell hosts it in a long-lived object, not in the caller's window. A popup can call it
  and close. One chooser at a time: a second call gets `done(null)` with a log line.
- Refused while locked.
- Paths come back as absolute paths, never URLs.

Feasibility of the file chooser is unverified, so start with a spike. The shell runs with
`UseQApplication` (`shell.qml:1`), so `FileDialog` may open as its own top-level window. If
it can only draw inside a parent window, the fallback is a small `FloatingWindow` that the
shell opens to host it.

Replaces in the module: "Copy ssh command" becomes "Open SSH" (the copy can stay), and the
popup's timed request to the page (#20, #36).

### 2.10 Test mode and `ModuleTestKit` (1.4, with §2.3)

Test mode, `ModuleHost.testMode`:
- Set in-process by `tests-modules.qml`.
- The lock bed sets it through the shell's single test-seam place. That place honours its
  variable only together with the bed's own marker, and logs loudly when set (review 5.4).
  The bed is the only path that comes from the environment.

In test mode:
- `module.programs` resolve from the manifest's `testPrograms` directory: `trusted: true`,
  `reason: "test stand-in"`.
- `PrivilegedAction` uses `<testPrograms>/pkexec`, which must exist, and never the real
  pkexec. **Stand-ins and real pkexec never meet.** This is the rule that fixes 8.9.
- `Api.openUrl`, `Api.openTerminal` and `Api.chooseFiles` record the call and open nothing.
  `chooseFiles` answers from `ModuleTestKit.chooserAnswer`.
- `module.dataDirectory` is under a temporary directory the runner made.
- `Api.testMode` is true, read-only. A module may use it for things like "an IPC call counts
  as the user".

`qs.tests` gains `ModuleTestKit`. It exists only in tests, because the running shell has no
`qs.tests`:
- `setEnabled(id, on)`, `status(id)`, `widgetEntries`, `slotEntries(name)`
- `setSystem(facts)`, `setNow(ms)` (drives `Api.minuteNow`)
- `opened` (recorded openUrl, terminal and chooser calls), `chooserAnswer`

A module's own unit suites still build their objects with explicit properties (the module's
`toolsDir`, `fixedNow`, `environment`). Those are not environment hooks and stay.

Tests: `ModulesTest` checks:
- a fixture's stand-in is used only in test mode;
- with test mode off, a `testPrograms` entry is ignored;
- a privileged run in test mode never calls the real pkexec, by putting a pkexec on PATH that
  fails the suite if it runs.

Replaces in the module: `H2S_TAILSCALE_TOOLS` and `H2S_TEST_MODULES` (`TC:300-317`), the
seam's `xdg-open`, `_ipcOrigin` keyed on `toolsMode`, the three directory seams, and the
test's `module.host` use (#11-#15).

### 2.11 Stable UI types, and closing the handle's reach (1.9 → 2.0)

**UI types: wrap them in `qs.api` and pin them with a test.**
- Each type gets a file under `api/`: `VpnProvider`, `PopupWidget`, `BarRow`, `BarText`,
  `SmallButton`, `InputField`, `Dropdown`, `Pill`, `ToggleSwitch`, `Checkbox`, `DeleteButton`,
  `PointerArea`, `PrivilegedMark`. Each file is `Base {}`, as `SettingEditor` is.
- They keep the core names, so a module changes one import line. It must drop
  `import qs.components`: the same name from two imports is ambiguous.
- A table `ModuleRules.apiComponents` lists each type's documented properties and signals.
  `tests/ApiComponentsTest.qml` builds each type and checks that the list still holds.
- A wrapper still inherits every property of its base. The test pins what is documented, and
  the docs say "only the listed properties are API".
- Why wrap rather than only list:
  - the module's imports then say what is API;
  - the import check can then warn on `qs.components`;
  - a core rename stays inside the wrapper.
- Add a comment in each wrapped core file: "API through api/X.qml" (as review 3.4 asks for
  `panels/settings`).

The import check in 2.0:
- `qs.components` leaves the allowlist. It stays a warning, by the owner's §7 decision.
- `Quickshell.Io` stays allowed for `IpcHandler`. Q8 asks whether to warn on `Process` in a
  module file.

Closing reach:
- `ModuleHandle.host`: in 1.9, rename it to `_host` and keep `host` as a deprecated alias.
  The first read warns once in the module's status. In 2.0, remove the alias. QML cannot make
  a property truly private, so this is a convention plus a warning.
- `Api.module(id)`: in 1.9, add `Api.moduleStatus(id)`, a frozen
  `{ id, name, version, state, active }`. `Api.module(id)` keeps working but warns. In 2.0,
  remove it (Q3).
- `PrivilegedAction.elevate`: in 2.0, a read-only report of what the shell uses. Suites use
  test mode instead.

---

## 3. Versioning

| Version | Adds | Tightens |
|---|---|---|
| 1.4 | `CommandRunner`; `PrivilegedAction.start()`, `available`, `unavailableReason`; `module.programs`, `programsReady`, `recheckPrograms()`; manifest `optionalPrograms`, `testPrograms`; test mode, `Api.testMode`, `ModuleTestKit`; `Api.sessionLocked` | Privileged runs refuse untrusted `argv[0]`, and refuse while locked (rule below) |
| 1.5 | `module.main`; popup `opener`; documented `availableHeight`, `fitsShownHeight`, `popupAnimating` | — |
| 1.6 | `Api.format`, `Api.address`, `Api.minuteNow`, `Api.system`, `module.dataDirectory`, notify `format: "plain"`, `module.log` | — |
| 1.7 | `Api.networksReady`, `Api.localNetworks`, `localNetworksReady`, `vpnsUp` tunnel fields, `VpnProvider` entry fields, `otherVpns` in the VPN context, slot `network.profile.card` | `Api.networks` holds Wi-Fi rows back until read (a fix: it matches the docs) |
| 1.8 | `Api.openTerminal`, setting `general.terminal`, `Api.chooseFiles` | — |
| 1.9 | The UI types in `qs.api`, `ApiComponentsTest`; `Api.moduleStatus`; `_host`; deprecation warnings for `qs.components`, `host` and `Api.module` | The click rule for privileged runs, if Q5 is yes |
| 2.0 | — | Remove `Api.module` (or make it read-only), remove `host`, `qs.components` out of the allowlist, `elevate` read-only; maybe notify defaults to plain (Q9) |

What forces 2.0: removing `Api.module` or `host`, and taking `qs.components` off the
allowlist. 1.0 promised all three. Everything else is additive.

A version gate for every slice:
- Add a test that reads the newest `- 1.x:` line under `### Module API` in `CHANGELOG.md` and
  compares it with `ModuleRules.apiVersion` (review 3.9).
- `ModuleRulesTest.qml:23` stops hard-coding "1.3".

**Open owner decision: may a minor version tighten behaviour?** Options:

| Option | Rule | Consequences |
|---|---|---|
| A | Never. Anything that refuses what a 1.x module could do waits for 2.0 | Simple and honest. The pkexec trust check and the locked refusal wait. Until then a user-writable program can be run as root through the API |
| B | Only to close a security hole, or to match what the docs already promise. It goes under "Tightened" in the CHANGELOG | Follows the 1.2 precedent (`openUrl`, "a tightening, taken as a fix"). The trust check, the locked refusal and the hotspot fix can ship in 1.4/1.7. "Security hole" needs judgement each time |
| C | Warn for one minor, then enforce in the next. The warning goes in the module's status and the log | A module author sees it coming, and nothing breaks silently. Every tightening takes two releases. The click rule fits here |
| D | Freely until install-from-repository (M4) ships, then A, B or C | Fits today (one author, one module). It needs a date or a stage written down, or it drifts |

---

## 4. Order of work

Each slice:
- leaves the shell and the module working, with all suites green (`tests/run-unit.sh` and
  `tests/run-modules.sh` on the module);
- bumps the minor once, with one CHANGELOG `### Module API` line;
- does the core change first, then the module's migration, which also raises its manifest
  `api`.

| # | Slice | Core | Module | Size | Needs |
|---|---|---|---|---|---|
| 0 | Version gate | The CHANGELOG/`apiVersion` test (review 3.9); comments at `Nmcli.profiles` and `VpnManager.activeVpns` (review 3.1); trust model text in ARCHITECTURE (review 3.3) | — | S | — |
| 1 | Runner (1.4a) | `Io.CommandRunner` + `api/CommandRunner`; rebuild `CommandAction` and `CommandQuery` on it; move `ModuleHost`'s 4 blocks and `Api._opener` onto it; `CommandRunnerTest` | Extract `TailscaleRunner` (module-internal, review 8.6) on `CommandRunner`; drop `_spawn`, `_processComponent`, `_timedArgv`, `_watchdogMs`, generation checks, the bare stream Process; sub-clients use the runner's public calls | L | 0 |
| 2 | Programs and test mode (1.4b) | `optionalPrograms`, `testPrograms`, `module.programs` with verdicts (rules moved from `TR`); `ModuleHost.testMode`; `Api.testMode`; test-mode `openUrl`; `ModuleTestKit` (enable, status, entries, opened) | Drop `_resolveTools`, `toolsProbe`, `H2S_TAILSCALE_TOOLS`, `H2S_TEST_MODULES`, the seam's `xdg-open`, `_ipcOrigin` on `toolsMode`; the suite uses `ModuleTestKit` instead of `module.host` | M | 1 |
| 3 | Privileged runs (1.4c, released together as 1.4) | `PrivilegedAction.start()`, `available`, shell-wide prompt queue, cancel, trusted `timeout` inside pkexec, `blocked` (untrusted, locked: subject to the §3 decision), test-mode pkexec | Login onto `start()`; drop `_adminSpare`, `_freeAdmin`, the 127 mapping, `elevationProblem`, setting `elevate` | M | 1, 2 |
| 4 | Main and popup (1.5) | `module.main`; `opener` through `PopupWidget`/`Popup`; panel inputs documented and tested | Delete `Tailscale.qml`; views use `module.main?.client`; drop `provider.client` and `popupPreset` | S | 0 (may go before 3) |
| 5 | Helpers and system (1.6) | `AddressRules` (NetworkRules delegates); `Api.format`, `Api.address`, `Api.minuteNow`, `Api.system`, `module.dataDirectory`, notify plain, `module.log`; `ModuleTestKit.setSystem` / `setNow` | Drop the copies (`bytes`, `ago`, addresses, `withoutAddresses`), `_readIdentity`, `_readSystemHostname`, env reads, user-dirs parsing, the three dir seams; move certs; the 5 s clock becomes one-shot timers + `minuteNow` (8.5); the logger | M | 2 |
| 6 | Network facts (1.7) | `networksReady`, hold Wi-Fi rows back, `localNetworks`, `vpnsUp` tunnel fields, provider entry fields, slot `network.profile.card` | Drop the empty-list guard and `_readLan`; the "Another VPN" hint only for `fullTunnel`; its entry reports `fullTunnel` while an exit node is used; exit node per network on the network card (if Q4 yes) | M | 0 |
| 7 | Terminal and chooser (1.8) | Spike on the file chooser first (S); then `Api.chooseFiles`, `Api.openTerminal`, `general.terminal` | "Send file…" picks files from the popup; the page's request flag goes; "Open SSH" on device rows | M | 2 (test mode records) |
| 8 | UI types (1.9) | The `api/` wrappers, `ModuleRules.apiComponents`, `ApiComponentsTest`, `Api.moduleStatus`, `_host` + deprecation warnings | Import only `qs.api` and `Quickshell*` | M | 0 |
| 9 | 2.0 | Remove `Api.module`, `host`, `qs.components` from the allowlist, `elevate` read-only, the tightenings deferred by the §3 rule | Manifest `api: "2.0"` | S | 8, owner's §3 decision |

The module's other review items (8.1-8.5, 8.7, 8.10-8.13) are module work. Slices 1 and 4
unblock its structural refactor (8.6, 8.7), so they come first. 8.1-8.5 can run in parallel
with slices 2-3.

---

## 5. Open questions for the owner

| # | Question | Choices | Recommendation |
|---|---|---|---|
| Q1 | May a minor version tighten behaviour? (§3) | A never / B security and documented promises only / C warn one minor, then enforce / D freely until M4 | **B + C**: security holes and broken promises as fixes right away (trust check, locked refusal, hotspot window); everything else warns for one minor first |
| Q2 | `qs.components`: wrap in `qs.api`, or list and pin in place? | Wrap + pin test / list + pin test, import stays | **Wrap**: the imports then show what is API, and core renames stay internal |
| Q3 | `Api.module(id)` in 2.0 | Remove / read-only status | **Remove**, after `Api.moduleStatus` in 1.9; no module uses it today |
| Q4 | An exit node per network (and future per-network choices) | (a) slot `network.profile.card` + data in the module's store / (b) a shell-kept per-network settings table for modules / (c) nothing: keep it on the module's page | **(a)**: UI where the user edits the network, no new storage model. A per-network choice is data keyed by a UUID, not a profile setting |
| Q5 | Privileged runs need a user action in a shell window within 10 s | Yes / no (convention only, as today) | **Yes**: cheap, and it turns "never prompt without a click" from a comment into a check (mistakes, not malice) |
| Q6 | Where module data lives | `~/.local/share/h2s-shell/module-data/<id>` / inside the store directory | **`module-data/<id>`**: apart from `modules/<id>`, which M4's sync owns |
| Q7 | Terminal setting | Free command prefix / pick from known terminals + "custom" | **A string, "" = automatic** (xdg-terminal-exec, `$TERMINAL`, a known list); known terminals get their `-e` form, others `-e` |
| Q8 | In 2.0, warn on `Process`, `Quickshell.env` and `execDetached` in module files | Warn / say nothing | **Warn** (text check like the import check): it points authors to the runner and to `Api.system` |
| Q9 | In 2.0, notifications from modules are plain text unless `format: "markup"` | Yes / keep markup default | **Yes**: every module text so far needed escaping; markup by default is the trap |
| Q10 | If the file chooser cannot outlive the popup, a small shell window hosts it | Accept / drop `chooseFiles` | **Accept**: "Send file…" from the popup is a daily action |

## Feasibility notes (Quickshell 0.3.2)

- **Checked** in `quickshell-io.qmltypes`. `Process` has `signal(int)`, `stdinEnabled` +
  `write()`, `environment`, `clearEnvironment`, `workingDirectory`, `started` and `exited`.
  `SplitParser` with `splitMarker: ""` gives raw chunks, as `singletons/io/CommandAction.qml:48-51`
  and `TC:1956-1968` use it. `FileView` reads /proc without a process
  (`singletons/io/KernelFile.qml`).
- **Seen in working code, not checked in Quickshell's source.** A program that cannot start
  gives no `exited`, only `running` turning false (`TC:1999-2009`). Processes created from a
  `Component` per run work in the running shell (the module does it today).
- **Unverified:**
  - whether a destroyed `Process` kills its child (the runner signals explicitly);
  - closing stdin after `write()` (no method is listed);
  - signalling pkexec while its prompt shows;
  - whether NetworkManager reports `tailscale0`'s addresses;
  - whether `FileDialog` opens as a top-level window under `UseQApplication`;
  - whether coreutils `timeout` signals the whole group. Its docs say it does unless
    `--foreground` is given.
- **What QML cannot isolate.** Any property is readable, so `_host` is a convention. A module
  can still use `Quickshell.Io` directly. Every guard in this plan stops mistakes, not a
  hostile module (the owner's trust decision, `notes/plans/modules.md` §7).
