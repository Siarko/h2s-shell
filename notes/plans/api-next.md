# Module API: the next versions

Status: a plan, for the owner to approve. Nothing here is built.

It covers tracker steps 3 (API extension), 4 (UI anchors) and 5 (a module's public API), and
says what step 6 (the Tailscale migration) then removes. The owner's decisions in
`notes/tracker.md` ("Decisions") are binding; this plan follows them.

References: the shell at `50129d9`, the Tailscale module (`h2s-shell-tailscale`, files under
its `module/`) at `13468e9`. `TC` is the module's `TailscaleClient.qml`, `TR` its
`TailscaleRules.qml`. "Verified" means read in the code at those commits; "assumed" is
marked. The lists are in §9.

---

## 1. What the module works around today

Every row is a place where the module does by hand what the API should give. When this plan
and step 6 are done, none is left. "Shell too" names core code with the same need; it moves
onto the same new piece.

### Running commands

| # | The module today | Shell too | Answer |
|---|---|---|---|
| 1 | Its own process factory with a watchdog, `abandon()` and output chunks (`TC` `_spawn`, `_processComponent`) | `ModuleHost.qml`: four `Process` blocks with deadline timers; `Lockscreen.qml`: three probes; `Api._opener` | Command runner (§3.1) |
| 2 | Wraps every command in coreutils `timeout -k` (`TC` `_timedArgv`, `TR` `timed`) | `Lockscreen.qml` (`timeout 2 hyprctl`) | Runner `timeoutMs` |
| 3 | A long-lived stream (`curl … watch-ipn-bus`) as a bare `Process` (`TC` `_stream`) | `NetworkEvents.qml`, `lock/LogindMonitor.qml` | Runner with `timeoutMs: 0` and `onStdout`. The restart backoff stays the module's |
| 4 | Generation tokens so late answers are dropped (`TC` `_alive`, and in `CertClient`, `LockClient`, `ServeClient`, `TaildropClient`) | `ModuleHost` `_storeDirectoryKnown`, `_guardKnown` | Runner: no callback after `cancel()` or destruction |
| 5 | The elevated login runs `[pkexecPath, …]` itself, to read the login link while it waits (`TC` near `_opProcess = _spawn([pkexecPath]…`) | — | Privileged start, streamed (§3.4) |
| 6 | Two `PrivilegedAction`s, `_admin` and `_adminSpare` (`TC` `_freeAdmin`) | — | A cancelled run leaves the queue at once (§3.4) |
| 7 | Maps pkexec's 126/127 again (`TR` `pkexecOutcome`) | — | Goes with #5 |
| 8 | Sets `PrivilegedAction.elevate` to its own pkexec (`TC` `_admin.elevate = …`) | — | The shell picks pkexec; in test mode the stand-in (§3.3, §3.4) |
| 9 | Finds tailscale, timeout, pkexec, curl and judges whether the user could replace them (`TC` `_resolveTools`, `TR` `toolsProbe`) | `ModuleHost._checkPrograms` finds names, returns no path and no verdict | Program lookup with trust (§3.2) |
| 10 | Runs `systemctl` and `xdg-open` by name | — | Program lookup; `Api.openUrl` |

### Test seams

| # | The module today | Answer |
|---|---|---|
| 11 | Reads `H2S_TAILSCALE_TOOLS` and the runner's `H2S_TEST_MODULES` to pick stand-ins; with the seam set no trust check runs (`TC` `_start`) | Test mode, manifest `testPrograms` (§3.3) |
| 12 | IPC calls count as "the user" when the tools seam is set (`Main.qml` `_ipcOrigin`) | `Api.testMode` |
| 13 | Opens links with the seam's `xdg-open` instead of `Api.openUrl` | `Api.openUrl` records in test mode |
| 14 | Directory seams `H2S_TAILSCALE_FORWARDING_DIR`, `_CERT_DIR`, `_DOWNLOAD_DIR` | `Api.system`, `module.dataDirectory`, set by the test kit (§3.7) |
| 15 | Its suite reaches the host: `module.host.widgetEntries`, `module.host.setEnabled` (`tests/TailscaleModuleTest.qml`) | `ModuleTestKit` (§3.3) |

### Structure

| # | The module today | Answer |
|---|---|---|
| 16 | A singleton holds the live client (`Tailscale.qml`); Main sets and clears it; popup, widget, page, row and card read it | `module.main` (§3.5) |
| 17 | An extra `client` property on its `VpnProvider`, so slot contributions find the client | `module.main` |
| 18 | The widget writes `Tailscale.popupPreset`; the popup reads it | Popup `opener` (§3.5) |
| 19 | Relies on `availableHeight` being set by `panels/Popup.qml`; not documented | Panel inputs documented and tested (§3.5) |
| 20 | "Send file…" in the popup sets a timed request and opens the settings page, whose section opens the `FileDialog` | `module.chooseFiles` (§3.9) |
| 21 | The exit node per network is edited in a table on the module's own page (`NetworkExitTable.qml`) | An anchor on the saved network's card (§4.7, §4.8) |

### Helpers and facts

| # | The module today | Shell too | Answer |
|---|---|---|---|
| 22 | Runs `id -u; id -un`, `cat /proc/sys/kernel/hostname` | — | `Api.system` (§3.7) |
| 23 | Reads `HOME`, `XDG_*` with `Quickshell.env`; parses `user-dirs.dirs` | `NetworkVpnSettings.qml` (`Quickshell.env("HOME")`) | `Api.system` |
| 24 | Builds its own folder under the shell's data name (`CertRules.certDir`) | — | `module.dataDirectory` |
| 25 | Reads IPv4 and IPv6 forwarding with `sh -c cat` | — | `Api.system.readIpForwarding()` |
| 26 | Runs `ip -o addr show scope global` for the LAN subnets (`TC` `_readLan`) | `IpManager.qml`, `Nmcli.qml` | `Api.localNetworks` (§3.8) |
| 27 | Copies `Format.bytes` and `Format.ago` (`TR`) | `singletons/Format.qml` | `Api.format` (§3.6) |
| 28 | Parses IPv4, IPv6, CIDR, overlap; hides addresses in text (`TR`) | `NetworkRules.qml` (`isIpv4`, `isCidr4`, `inSubnet4`): a second partial copy | `Api.address` on one core `AddressRules` |
| 29 | A 5 s clock re-derives the whole state | `singletons/Time.qml` (1 s) | `Api.minuteNow`; grace periods become the module's one-shot timers |
| 30 | Escapes markup in notification bodies; strips a leading "-" | `Notifier.command` already puts `--` first | `notify(…, { format: "plain" })`; the strip is dropped |
| 31 | Logs once per change of outcome (`TC` `_logOutcome`) | `components/Logger.qml` (no dedupe) | `module.log` |
| 32 | Treats an empty `Api.networks` as "not read yet" (`NetworkExitClient.qml`) | — | `Api.networksReady` (§3.8) |
| 33 | "Another VPN is also on" beside any other VPN, even a split one | `NetworkRules` reads `neverDefault` and `allowedIps` for the editor only | `vpnsUp` rows gain `fullTunnel`, `setsDns`, `routes` |
| 34 | Checks for older shells (`typeof module?.presetValue === "function"` and alike) | — | Dead once the manifest asks for the new minor |

Shell-side defects found on the way, fixed in the same slices: `Api.networks` can list a
hotspot for a moment (`listRead` turns true before the Wi-Fi mode is read); the polkit
prompt shows polkit's message with no `textFormat` (`polkit/AuthPrompt.qml`), and the
blocks `qs.api` already offers (`SwitchRow`, `Heading`, `Hint`, `SectionTitle`) show a
module's text with none either, against the plain-text rule (§4.8); `ModuleHandle.host`
and `Api.module(id)` hand a module the host and other modules (§5.4).

Module-internal, not API: the operation lock and "plain first, then elevated" (the module
builds its own runner object on the command runner); the JSON readers copied in five Rules
files; `jsonFeed` (needed: `watch-ipn-bus` prints indented JSON); Taildrop preferences
moving from the store to `mod.tailscale.*` settings; the manual "for now" exit-node
override (module state that wins over the per-network choice).

---

## 2. Rules for everything below

- **Callbacks, not promises;** results are plain frozen objects; errors are fields, never
  exceptions. Bad input gives a result with `error` set.
- **Decisions are pure functions** in `*Rules.qml` with unit cases; the new singletons only
  do I/O.
- **Module off.** Every object a module makes from `qs.api` lives under its main or its
  views. The host destroys them; no callback runs after that.
- **Session locked** (new read-only `Api.sessionLocked`). Plain runs continue (a VPN must
  follow the networks). Nothing that asks the user starts: no password prompt, no dialog.
  Those return `blocked: "locked"`.
- **Trust.** A module runs in the shell's process, which also holds the lock screen's
  password prompt and the polkit agent; QML has no sandbox. Every guard below stops
  mistakes, not a hostile module. Step 8 writes this down for users.

---

## 3. Step 3: the API extension

### 3.1 Command runner

A new core type `singletons/io/CommandRunner.qml`, with `api/CommandRunner.qml` as its
`qs.api` name. `CommandAction` and `CommandQuery` keep their contracts and are rebuilt on
it. `ModuleHost` and the lock screen use the core type, never `qs.api`.

```
CommandRunner {
    property var environment: ({})   // added to every run
    property int maxParallel: 8      // more runs wait, in order
    readonly property int running
    function start(argv, options) → handle { running, cancel() }
    function cancelAll()
}
options = { timeoutMs: 30000 (0: no limit), killAfterMs: 3000, environment, workingDirectory,
            stdin, onStdout, onStderr, onLine (line, stream), keepOutput: true,
            maxOutputBytes: 1048576, done }
result  = { ok, code, stdout, stderr, timedOut, cancelled, failedToStart, truncated, durationMs }
```

- `argv` is a non-empty array of strings; the runner never uses a shell itself.
- The time limit is enforced twice: coreutils `timeout -k` around the command (found and
  trusted by the shell, so the run ends even if the shell dies), and a watchdog in the
  runner for when `timeout` is missing.
- `done` runs exactly once, except after the runner is destroyed. `cancel()`: TERM, then
  KILL after `killAfterMs`; `done` gets `cancelled: true`; chunk and line callbacks stop at
  once.
- `timedOut`: code 124 and the run took at least `timeoutMs`.
- `failedToStart`: Quickshell emits no `exited` then; `running` just turns false (assumed
  from the module's working code).

Test: `tests/CommandRunnerTest.qml` with `sh -c` scripts: time-out, cancel waiting and
running, KILL after a TERM trap, separate stderr, lines split across chunks, the output
cap, a program that cannot start, no callback after destroy, `maxParallel` order. The
`CommandAction` and `CommandQuery` suites stay as they are.

### 3.2 Program lookup with trust

Manifest: `requires.programs` as today, plus `optionalPrograms` (a missing one does not
stop the module). On the handle:

```
module.programs        // frozen { name: { path: "/abs/…" | "", trusted: bool, reason } }
module.programsReady
module.recheckPrograms()   // look again; at most every 2 s; also run on resumed()
```

- The host's program check (`ModuleHost._checkPrograms`) also prints the path, the real
  path and their owners and modes. The verdict is a pure rule in `ModuleRules`, moved from
  the module (`TR` `toolsProbe`, `_statTrusted`) with its cases.
- **Trusted** means: in the Nix store, or the file, its real file and both their
  directories are owned by root and writable by no one else. That holds on NixOS
  (`/run/current-system/sw/bin` leads into the store) and on Arch (`/usr/bin`).
- A read that fails gives `trusted: false`, never true.

Test: verdict cases in `ModuleRulesTest`; a fixture module with a missing optional program
and a user-owned one.

### 3.3 Test mode

One switch, set only by the shell's test entry points: `tests-modules.qml` sets it in
process; the lock bed sets it through the single test-seam reader that
`notes/plans/architecture-cleanup.md` §3 plans (its `Api.testBed` is this plan's
`Api.testMode`: one name, `testMode`). A stray environment variable alone never turns it
on.

In test mode:
- `module.programs` come from the manifest's `testPrograms` directory (inside the module),
  with `trusted: true, reason: "test stand-in"`.
- Privileged runs use `<testPrograms>/pkexec`, which must exist. **Stand-ins never meet the
  real pkexec.**
- `Api.openUrl` and `module.chooseFiles` record the call and open nothing.
- `module.dataDirectory` and `Api.system` come from the test kit.
- `Api.testMode` is true (read-only).

`qs.tests` gains `ModuleTestKit` (tests only; the running shell has no `qs.tests`):
`setEnabled(id, on)`, `status(id)`, `widgetEntries`, `anchorEntries(path)`,
`setSystem(facts)`, `setNow(ms)`, `opened`, `chooserAnswer`.

Test (`ModulesTest`): a fixture's stand-in is used only in test mode; with test mode off
`testPrograms` is ignored; a privileged run in test mode never calls a pkexec found on
`PATH` (one is put there that fails the suite if run).

### 3.4 Privileged start, and the prompt's "who and what for"

**The surface is on the handle**, so the shell knows which module asks without being told:

```
module.privileged.available          // trusted pkexec and timeout found
module.privileged.unavailableReason
module.privileged.start(argv, options) → handle { running, cancel() }

options = { what (required), timeoutMs (required, 1 s … 1 h), onStdout, onStderr, onLine,
            notifyFailures: true, done }
result  = { ok, code, stdout, stderr, dismissed, refused, notFound, timedOut, cancelled,
            blocked ("" | "locked" | "untrusted" | "no-purpose"), error }
```

- **One queue for the whole shell** (`singletons/PrivilegedRuns.qml`): one password prompt
  at a time. A run leaves the queue when it ends or is cancelled, even if its root process
  still runs.
- **Time limit.** The shell puts its own trusted `timeout` inside pkexec. `cancel()` after
  the program started as root stops waiting; the root process ends at its limit.
- **No time window** after a click (the owner's decision). That nothing prompts without the
  user's click stays a development rule, checked in review and by the module's tests; what
  the user gets instead is a prompt that says who asks and what for.
- **Refused before pkexec runs:**
  - `untrusted`: `argv[0]` has no trusted verdict (§3.2), or is a shell or `env` (then the
    real program would be an argument nobody checked).
  - `locked`; `no-purpose` (`what` empty after cleaning); `notFound` as today.
- **Root helpers.** By the rule above, nothing under a module's own directory in the user's
  data home ever runs as root. No module has a root helper today; where a packaged helper
  is looked up is designed when the first one needs it.

**The prompt** (`polkit/AuthPrompt.qml`, when the shell's agent answers). Under the shell's
title: two labelled lines in the body size, a line "Command" that opens on a click, then
polkit's own message and action as today.

```
Authentication required
Module          Tailscale
Authorization   Send a file
▸ Command
```

opened:

```
▾ Command
/usr/bin/timeout -k 3 30 /usr/bin/tailscale file cp -- report.pdf laptop:
```

- **One pure function makes every text:** `PolkitRules.announcement({ moduleName, moduleId,
  what, pkexecArgv })` → `{ module, authorization, command, summary, body }`. The prompt
  and the notification below only show them.
- **`Module`**: the manifest's `name`, taken by the shell from the handle the run was
  started on. The id follows in brackets only when the name does not read as the id (name
  lower-cased, letters and digits only, differs from the id): "Tailscale", but
  "System update (xmod)". The id cannot be a word for the shell (`ModuleRules.reservedIds`
  holds `shell`, `system`, `polkit`, `h2s-shell`: verified); the name is free text, so the
  id is what keeps it honest.
- **`Authorization`**: the run's `what`, a few words naming the action ("Send a file",
  "Connect"), never a sentence.
- **`Command`** (the owner's decision: hidden, shown on a click). Closed for every new
  request. Opened, it shows the real command: exactly the words the shell hands to pkexec,
  joined with shell quoting, the shell's `timeout` in front included. It is the same list
  the shell starts, not a second text made for showing, so what is read is what runs; and
  it agrees with polkit's own message, which names `timeout` (below). The line is a
  `PointerArea` like a card's header; it never takes the keyboard from the password field.
- **Plain and capped.** The rule drops control characters, folds white space to one line
  and cuts with "…": name 40, `what` 40, the command 400 characters (it wraps). All texts are
  `Text.PlainText`; polkit's message and action become plain text too.
- **Not spoofable as the shell.** A module's words only fill the two values and the opened
  command. The title, the labels and the frame are the shell's; one line per value, so a text
  cannot fake a second line.
- **Which request is announced.** The agent's flow carries only `message`, `actionId` and
  `cookie` (verified in Quickshell's polkit types): no command line, no caller. So
  `PolkitRules.announces(flow, run)` matches the run at the head of the queue when the
  action is pkexec's (`org.freedesktop.policykit.exec`) and the message names the program
  pkexec is given, which is the shell's `timeout`, not the module's `argv[0]` (assumed:
  pkexec's message holds that program's path in every locale). So polkit's own message
  names only `timeout`; the two lines and the opened command tell the user what runs.
  Anything else shows
  as today, with no module lines: a request the shell did not start is never dressed up.
- **Another agent answers** (`Authentication.state` is `other`): the shell cannot change
  that prompt. The run goes ahead (the owner's answer), and when it reaches the head of
  the queue, just before pkexec starts, the shell sends one notification from the same
  rule: summary `Module: Tailscale`, body `Authorization: Send a file`, plain text. The
  shell cannot know whether that agent will ask at all (a polkit rule may allow the run),
  so the text states who runs what, not that a password is wanted. With the shell's own
  agent no notification is sent.

The old `PrivilegedAction` type keeps working unchanged until the closing slice (§7); its
runs go through the same queue and are announced with `Module  Not named` and no
`Authorization` line.

Test: `PolkitRulesTest` (announcement cleaning and caps, the bracketed id, matching, a
hostile name and `what`, the notification's two texts); a shell suite with a stand-in
pkexec that prints and sleeps: streaming, cancel while queued and after start, a second run
not blocked by a cancelled one, the time limit in the argv, every `blocked` reason, 127
reported once, with the agent state `other` one notification recorded before the stand-in
starts and none with `active`, and the command shown equal to the stand-in's own
arguments; a `LockViewTest`-style view test for the prompt's lines and the click.


### 3.5 Shared module object, and what a popup panel is given

```
module.main    // the object made from the manifest's `main` while the module is active;
               // null while off or with no main; notifies
```

The host sets it right after creating the main and clears it before destroying it. Views
read through it (`module.main?.client`) and must allow null.

A module's popup panel gets, each only when its root declares the property:

| Property | Value |
|---|---|
| `opener` | frozen `{ widgetType, preset, edge, byTouch }`: the bar widget that opened it |
| `availableHeight` | the most height before the panel must scroll; kept current |
| `fitsShownHeight` | declared true by the panel: it is sized to the height shown while the popup animates |
| `popupAnimating` | true while the popup moves or resizes |

`PopupWidget.togglePopup` passes `{ widgetType, preset }` as `contentData`
(`panels/Popup.qml` already carries it); the last three are set today and only get
documented and tested.

Test (`ModuleRegistriesTest`): `main` is set before the module's widgets complete, null
when off, a new object when on again; two bar entries on different presets each see their
own `opener.preset`.

### 3.6 Helpers

```
Api.format.bytes(n) / rate(n) / ago(ms, nowMs)
Api.address.isIpv4 / isIpv6 / isIp / parseCidr / contains / overlap / redact
Api.minuteNow                               // ms, updated on each minute boundary
module.notify(summary, { body, format: "plain" })   // also Api.notify
module.log(level, text, key)                // "[<id>]" prefix; with `key`: only when the
                                            // text for that key changed
```

One pure core singleton `singletons/AddressRules.qml` (from the module's tested code, with
its cases); `NetworkRules` delegates to it. `format: "plain"` escapes `&`, `<`, `>` and
drops control characters.

Test: `AddressRulesTest`, `FormatTest` (TB, `ago` in milliseconds), `NotifierTest` (plain),
`ModulesTest` (log dedupe).

### 3.7 System facts and the data directory

```
Api.system = { ready, userName, uid, hostName, home, configHome, dataHome, runtimeDirectory,
               downloadDirectory, isNixOS, readIpForwarding() → { ipv4, ipv6 }, refresh() }
module.dataDirectory     // "<dataHome>/h2s-shell/module-data/<id>", made 700 by the host
```

- `downloadDirectory` is `XDG_DOWNLOAD_DIR` from `user-dirs.dirs` (read, never sourced),
  else `~/Downloads`. `readIpForwarding` gives `null` for a value it could not read.
- The data directory is apart from `modules/<id>`, which installing and removing a module
  (step 8) owns. Moving the module's certificates there is module work.

Test: `SystemFactsTest` with fake files passed in as paths.

### 3.8 Network facts

```
Api.networksReady      // profiles and their Wi-Fi details are read
Api.networks           // a Wi-Fi row appears only once its details are read (no hotspot)
Api.localNetworks      // frozen [{ device, kind, family, address, network }], global scope,
                       // no VPN, tun, WireGuard or provider devices
Api.localNetworksReady
Api.vpnsUp             // rows gain fullTunnel, setsDns (true | false | null), routes
```

`VpnProvider` entries may set the same three fields; absent is `null` (unknown, never
"false"). The VPN anchors' context gains `otherVpns` (the rows) beside `otherVpnsUp`.

Test: `ModuleRulesTest` (`apiNetworks` with details missing, `apiVpnsUp`, `apiLocalNetworks`).

### 3.9 File chooser

```
module.chooseFiles({ mode: "open" | "openMany" | "folder", title, startDirectory }, done)
result = { paths: [absolute…], cancelled, blocked ("" | "locked" | "busy"), error }
```

A minimal version in this round (the owner's answer). It covers what the module's
dialogs do today (verified in its `TaildropSection.qml`): several files to send, starting
in the home directory; the folder for received files, starting in the current one. Saving
under a new name and name filters come when a module needs them.

- On the handle, not on `Api`: the shell closes the dialog and drops `done` when the module
  is turned off.
- Hosted by the shell, not by the caller's window, so a popup can call it and close.
- One at a time for the whole shell (`busy`); refused while locked; a lock while it is open
  closes it (`cancelled`). Absolute paths, never URLs. `title` is plain text, capped at 60.

**Starts with a spike**, a day at most, on NixOS and on Arch. Done when a `FileDialog`
owned by the shell, with no settings window open:
1. opens as a window of its own from a click in a popup, and stays when the popup closes;
2. takes the keyboard, in Hyprland and in the test bed's compositor;
3. returns several files, one folder, and a cancel, and starts in `startDirectory`;
4. can be destroyed while open without a crash.

If 1 or 2 fails, the same four with a small shell window as the dialog's parent. If that
fails too, the slice stops and reports: the API is not built on a guess, and row 20 of §1
stays until it is solved.

### 3.10 Not in this plan

- A terminal call and a terminal setting: the owner decided a global "default programs"
  setting later. "Copy ssh command" stays.
- A time window after a click for privileged runs.
- API 2.0: with "a minor may tighten", removals ship in a minor (§6).

---

## 4. Step 4: UI anchors

### 4.1 Blocks and placements

Views are built from five shared blocks. Each has an `anchor` name; that is all a view's
author writes. The files are new, in `components/`, on one base (`AnchorBlock.qml`: the
path, the hosts, reporting itself).

| Block | File | What it is | Its frame | Placements |
|---|---|---|---|---|
| Settings page | `SettingsPage.qml` | a page's root: scrolling, margins | the heading, and a banner under it (`KeepSettingsBar`) | prepend, append |
| Section | `SettingsSection.qml` | a titled group on a page | the title's line, with its buttons ("Find networks") | before, after, prepend, append |
| Card | `SettingsCard.qml` | a framed item that opens (a saved network, a VPN) | the header and the notice line | before, after; inside it through its regions (§4.8) |
| Row | `SettingsRow.qml`, in a popup `PopupRow.qml` | one line: a label with a control or a value | — | before, after |
| Popup section | `PopupSection.qml` | a group in a popup panel; the panel's root is one too | its header line and its closing divider | before, after, prepend, append |

**The four placements.** `before` and `after` put an element next to the block, outside it
(a card's frame included). `prepend` and `append` put it inside, as the first or the last
of the block's content. The frame is never content: a prepended element comes under a
page's heading, a section's title, a popup section's header; an appended one above a popup
section's divider.

**One order, top to bottom,** for a block B holding c1 … cn:

```
B.before · B's frame · B.prepend · c1.before · c1 · c1.after · … · cn.after · B.append · B.after
```

It follows from where the hosts stand (§4.4), so `prepend` on a section and `before` on its
first row never compete: the section's element is above the row's.

**How consistent the views are today** (verified by reading `panels/`):
- 26 settings pages with four kinds of root: `Flickable` (14), `ShapeSettings` (5),
  `ColumnLayout` (4, scrolled by the window), `Item` (3: network pages with an editor
  laid over them). There is no page block.
- Sections are a `SectionTitle` (or a hand-made title line with a button) followed by loose
  siblings, and only on the network pages; other pages mark sections with a comment or a
  `Label`. There is no section block.
- Cards exist as `NetworkProfileCard` and `NetworkDeviceCard`. Rows exist as `SwitchRow`,
  `DetailRow`, `SettingEditor`, `SettingInputRow`, and many hand-made `RowLayout`s.
- 9 popup panels, each a bare `Item` with a `Column`; only the network popup has parts in
  files of their own (`panels/network/VpnSection.qml` and others). There is no popup
  section block.

**What is refactored first.** Not everything. A view gets blocks when it gets its first
anchor. This round converts only what today's slots and the first consumer need: the
General page, the network and notifications popups, the VPN, Wi-Fi and Ethernet pages.
`NetworkProfileCard` is rebuilt on `SettingsCard`. Other views follow when a module needs
them or when step 7 touches them; until then they have no anchors, and the table says so.

### 4.2 Naming

```
<surface>.<view>[.<block>]…[.<region>]
```

- `surface`: `settings` or `popup`. The bar has no anchors.
- `view`: the settings page's id (`SettingsWindow.pages`: `general`, `network_vpn`, …) or
  the popup's key (`WidgetRegistry`: `network`, `notifications`, …). These ids are public
  already (`Api.openSettings`).
- `block`: the block's `anchor` name, `[a-z][a-zA-Z0-9]*`, written in the code. It says
  what the block holds (`saved`, `vpns`, `connections`), never where it is (`top`,
  `bottom`) and never the title's words, so a new title or a translation changes nothing.
- A block repeated per item is named by its kind: `card`, `row`. All instances share one
  path; the item is in the element's `context` (`context.networkId`).
- `region`: `actions` or `settings`, under a card only (§4.8).
- Unique among siblings. A block with no `anchor` is not addressable and adds no level.

The anchors of this round:

| Path | What | Placements | Scope |
|---|---|---|---|
| `settings.general` | the General page | append | — |
| `popup.network.connections` | the VPN, Ethernet and Wi-Fi parts of the network popup | append | — |
| `popup.network.connections.vpn.row` | each VPN's row in the popup | after | own-provider |
| `popup.notifications` | the notifications popup, under its header | prepend | — |
| `settings.network_vpn.vpns.card.settings` | each VPN's card, its opened part | prepend, append | own-provider |
| `settings.network_vpn.vpns.card.actions` | the same card's buttons | prepend, append | own-provider |
| `settings.network_wifi.saved.card.settings` | each saved Wi-Fi network's card, its opened part | prepend, append | — |
| `settings.network_wifi.saved.card.actions` | the same card's buttons | prepend, append | — |
| `settings.network_ethernet.profiles.card.settings` | each wired profile's card, its opened part | prepend, append | — |
| `settings.network_ethernet.profiles.card.actions` | the same card's buttons | prepend, append | — |

A block kind can take more than the table offers (a section's `before`, a card's `after`);
a placement is published when a module needs it. Hotspot cards stand in another section
(`hotspots`) and are not published.

### 4.3 How a path is derived and stays stable

- The window gives a page's root its base (`settings.<page id>`), the popup gives a panel's
  root `popup.<key>`. A block's path is its nearest enclosing block's path plus its own
  `anchor`; it finds that block by walking up `parent` when it is completed.
- So a path changes only when a block is renamed or moved under another block. Reordering
  blocks, changing titles or wrapping them in layouts changes nothing.
- The list of anchors is a table, `ModuleRules.anchorTable`:
  `{ path, kind, placements, takes, marks, context, scope, since, where }`. `Api.anchors` is its
  frozen copy; the documentation's list is generated from it. Only paths in the table take
  content: naming a block does not publish it.
- Views built by a module are not anchors in this round, and neither are a module's
  elements (§4.5 says why).

### 4.4 Registration and building, within the Repeater rules

- **A block's root is a plain column:** its `before` host, its body (the frame and the
  content: a card's border is the body's), its `after` host. The parent layout sees one
  item, so a block works in a `Column`, a layout, or as a `Repeater`'s delegate; the view
  puts layout properties on the block and the block hands its width to the body. A hidden
  block hides its `before` and `after` content with it.
- `prepend` and `append` hosts are the first and the last child of the block's content.
- **A host is today's `ModuleSlot` machinery,** kept as it is (`components/AnchorContent.qml`):
  a `Repeater` on a `ScriptModel` keyed by `ModuleRules.contributionKey`, each element in a
  `ModuleContribution` guard. It is created only when the module host lists content for
  that path and placement, so a block nobody targets costs one string.
- Both Repeater rules hold as they do for `ModuleSlot` today (verified: it sits in
  `NetworkPanel.qml`, built by `panels/Popup.qml` outside the window's incubation, and in
  `GeneralSettings.qml`): popup content is still created through `Qt.callLater`, and no
  host binds a live array.
- **Repeated blocks.** The pages build their cards from a `ScriptModel` keyed by the item
  (`objectProp: "uuid"`: verified on the three network pages), so one delegate stands for
  one network as long as it lives, and the elements inside it never change item. A change
  to the item (renamed, connected) reaches an element as a new `context`, passed only when
  it differs by value (`ModuleContribution`, as today). An item that goes takes its
  delegate, the hosts and the elements with it.
- Blocks also report themselves to a plain core singleton, `singletons/Anchors.qml`
  (`live`: path → count). Nothing in the running shell decides by it; the pin test and
  `modules list` read it.

**An element** is what a slot contribution is today: built in its own guard; its root may
declare `module`, `context` and `shown`. `context` is `{ anchor, placement, … }` plus what
the table documents for that path.

**Scope.** `own-provider` (the VPN paths) builds a module's element only on the items of
its own VPN provider. The block tells its hosts the item's provider id; the host lists only
that module's content (a pure rule, `ModuleRules.anchorContent(anchors, path, placement,
scopeId)`). A card's regions are part of the card, so they follow its scope.

Manifest:

```
"anchors": [{ "at": "settings.network_wifi.saved.card.settings", "place": "append", "component": "ExitNodeRow.qml" }]
```

`at` is a path in the table, `place` one of that path's placements, `component` a file of
the module. The same three twice is an error (the second is dropped): the key that keeps
an element alive across changes is the module and the file. An older shell keeps the
unknown `anchors` field with a warning (verified: `ModuleRules`, "unknown field … kept").

### 4.5 Missing anchors, and order

- **A path this shell does not offer**, or a placement that path does not take: an error in
  the module's status ("anchors: `x` is not a place this shell offers"), shown in
  Settings → Modules and `modules list`. The rest of the module loads. Today an unknown slot
  is only a warning.
- **An anchor removed by a later shell**: the same error, and the shell's API floor (§6)
  says which version the module must be written for.
- **A path in the table that no view builds any more** is a shell defect; the pin test
  (§4.6) catches it before release. At run time such content shows nowhere; `modules list`
  names table paths that were never live in a view that has been opened.
- **Several modules on one path and placement**: by module id, alphabetically; within a
  module, manifest order; top to bottom, the same for all four placements. A module's
  elements there stay together. Stable across machines (verified: `ModuleRules.merge` sorts
  by id today, not by the search path).

The order of modules, both the order they are loaded in and the order of their elements
in one place, is the owner's to design in a later stage (§7, "Later"). Until then there is
one rule everywhere: by module id. `ModuleRules.anchorContent` is the only place that
orders elements, so a later rule changes one function.

### 4.6 The test that pins the list

`tests/AnchorsTest.qml`:
1. builds every converted settings page and popup panel with the fixture module off,
   collects `Anchors.live`, and compares it with the table: every table path is live, and
   every live path that is not in the table is listed in the test as "named, not published";
2. checks every path against the naming rule, and that no table path is under
   `lockscreen`, the screensaver or `singletons/lock` (`tests/lock-closure.sh` takes
   `AnchorContent` and the five block files in place of `ModuleSlot`: none may be reached
   from the lock screen's path);
3. with the fixture module on: one element per published placement of each path appears,
   in the order of §4.1, with the documented context; an unknown path gives a status error;
   an element that is not the public `SmallButton` on an `actions` region is refused
   (§4.8); a mark set and cleared shows and goes on a closed card (§4.10).

The suites run with no D-Bus (verified: `tests/headless.sh`), so building a network page
reads nothing real. Repeated blocks need an item to be live: the VPN page gets
`tests/FakeVpnProvider.qml`; for Wi-Fi and Ethernet the suite sets
`NetworkProfiles.profiles` (a plain property: verified).

The pure parts have their own cases in `ModuleRulesTest`: the manifest check, the slot
aliases, `anchorContent` (scope and order), `cardMarks` (§4.10).

### 4.7 Today's slots, and the first consumer

| Slot (`ModuleRules.slotTable`) | Becomes | Where it shows |
|---|---|---|
| `network.popup.sections` | `popup.network.connections`, append | unchanged |
| `notifications.popup.top` | `popup.notifications`, prepend | unchanged: under the header, above the list |
| `settings.general.bottom` | `settings.general`, append | unchanged |
| `network.vpn.row` | `popup.network.connections.vpn.row`, after, own-provider | unchanged |
| `network.vpn.card` | `settings.network_vpn.vpns.card.settings`, prepend, own-provider | unchanged: today it is the first of the page's rows (verified: `NetworkVpnSettings.qml`), and a provider's card has no rows of its own above them |
| `network.vpn.page` | removed: a provider's page is its `settingsPage` (API 1.2); the module does not use the slot | — |

A slot keeps its `ModuleSlot` until the slice that converts its view. From then on a
manifest's `slots` entry for it is read as the anchor, with a warning; their `context` also carries `slot`, and on the card `open: true`, as the old
names promise. One thing differs for the VPN card: its content was built with the card and
is now built when the card opens. The module's card content only shows details (verified:
`TailscaleCard.qml` reads no `context.open`), so nothing is lost.

`components/ModuleSlot.qml`, `Api.slots`, the `slots` field, and `components/VpnExtras.qml`
with `VpnProvider.rowExtras` / `cardExtras` (used only by the test stand-in: verified) go in
the closing slice (§7).

**First consumer: the exit node per network.** The saved network's card, opened, already
holds that network's own choices, each applied at once (connect automatically, priority:
`NetworkProfileCard.qml`). The module appends one row there, on
`settings.network_wifi.saved.card.settings` and
`settings.network_ethernet.profiles.card.settings`, with context
`{ networkId (the profile's UUID, as in Api.networks), name, kind, active }`.
The choice stays in `module.store`, keyed by `networkId`, and applies at once like its
neighbours. Hotspots and VPNs have other paths, so the row never shows there.
`NetworkExitTable.qml` on the module's page goes; with it goes the one place that showed
every network's choice at a glance; the icon on the closed cards takes its place (§4.10).

### 4.8 Inside a card

A card is not one list. `NetworkProfileCard.qml` (verified) has a header (the name and a
line; on the right the primary button and, opened, the secondary buttons stacked under it,
each as wide as its label, on one right edge), a notice line, and, opened, a column: the
card's own rows (connect automatically, priority), then the rows the page adds (the Wi-Fi
password; a VPN's details). The same card serves Wi-Fi, Ethernet, hotspots and VPN
providers' entries; some have no "Edit connection…", no "Forget", or a "Settings…".

So a card takes no `prepend` or `append` itself. It has two regions, each an anchor under
the card's path:

| Region | Holds | `prepend` | `append` | An element must be |
|---|---|---|---|---|
| `<card>.actions` | the secondary buttons | under the primary button, above "Settings…" | under "Edit connection…", above "Forget" / "Delete" | the public `SmallButton` (§4.9) |
| `<card>.settings` | the opened column | above "Connect automatically" | under the page's own rows | anything; `SettingsRow` or `ExpandingRow` is what fits |

- **Built while the card is open,** both. A page keeps one card open (`_open`: verified),
  so a module's element exists once per page, not once per network. Closing the card
  destroys it; what it showed (an `ExpandingRow` left open) starts closed next time.
- **`actions`.** "Forget" stays last whatever a module adds: the destructive button is
  never pushed up or left in the middle. The region right-aligns each button at its own
  width, as the card's are; it gives a button at most a third of the card's width, and a
  longer label is cut (`SmallButton` gains eliding). The stack's size is `normal`.
- **Why a button is required there and nothing else is.** The stack sits in the card's
  header beside the name; anything but a button breaks the header of every card. The host
  checks the built element (`instanceof` the public `SmallButton`; assumed to work for a QML
  type, checked in `QuickshellPinTest` first) and refuses another with an error in the
  module's status. `settings` is a full-width column where today's VPN card content
  (detail rows, warnings, a hint) is legitimate, so there the blocks are offered, not
  demanded.
- **Variants.** A region exists on every card of a published path, whatever buttons that
  card has; with no "Edit connection…" the appended button simply stands above "Forget",
  or last.
- **Context** is the card's item, per path (§4.2): a saved network's
  `{ networkId, name, kind, active }`; a VPN's
  `{ vpnId, entryId, vpn, provider, otherVpnsUp, otherVpns }`. No `open`: a region's
  element exists only while the card is open.
- **Not regions:** the header's name and line, the primary button, the notice line. A
  module does not change them.

- **Variants on `actions`.** A module's button there is shown in the `normal` variant
  (proposed; Q1 in §8): a red one-click button beside the card's "Forget", which asks
  first, or a second confirm-coloured button beside "Connect", would make the card's own
  buttons harder to read. Another variant is shown as `normal`, with a warning in the
  module's status.

**A closed card** builds no module element. It can show the module's icon (§4.10).

### 4.9 Public elements

A module builds its views from **public elements**: types in `qs.api`, made for the API,
that use the shell's internal components inside (the owner's decision). The shell changes
its internals freely; a public element keeps its own properties. Modules are meant to use
as many of them as they can, and at the end of the migration a module imports nothing from
`qs.components`.

**How an element is made.**

- **A control is a wrapper, not a subtype.** `api/SmallButton.qml` is an `Item` holding the
  internal button. It declares only the public properties and signals and maps them onto
  the internal ones; it takes its size from the inner item, so it stands in a layout as the
  internal one does. A subtype would hand a module every internal property with it; that
  is what today's six `qs.api` types are (verified: `Settings.SwitchRow {}`).
- **A base type is a subtype:** `PopupWidget`, `BarText`, `BarRow`, `PointerArea`,
  `VpnProvider`. The bar, the pointer and `VpnManager` need the object itself. Their
  public properties are pinned by name; what else they inherit is not promised.
- **Variants are small enumerated properties,** never a colour or a size in pixels:
  `variant` for what the element is, `size` for how large (the module passes `fontSize`
  today: verified). An unknown value shows as the default, with one warning in the
  module's status.
- **Themed.** Elements read `Theme` only.
- **Pointer and keyboard.** Everything that lights up does so through `PointerArea`'s
  `lit`. None of the shell's buttons takes the keyboard today (tracker backlog); when they
  do, every module gets it with the elements.
- **Plain text.** Every text property is shown as `Text.PlainText`, on one line where it
  is a label. That is not so today for `SwitchRow`, `Heading`, `Hint` and `SectionTitle`
  (verified: no `textFormat`); F3 fixes them.
- **Pinned** by `tests/ApiElementsTest.qml`: for every element its public property and
  signal names; every variant value builds; a label "<b>x</b>" is shown as written. A
  change to that list is an API version change.

**The starting set**: what the Tailscale module uses from `qs.components` (13 types:
verified), what `qs.api` offers already (6), and what the anchors need (3 new).

| Public element | Inside | Public properties and signals | Variants |
|---|---|---|---|
| `SmallButton` | `components/SmallButton.qml` | `label`, `available`, `checked`, `tooltip`, `clicked()` | `variant`: `normal`, `confirm`, `confirmChange`, `cancel`, `delete` (today's `kind`: normal, save, saveChange, cancel, delete); `size`: `normal`, `small`, `tiny` |
| `DeleteButton` | `components/DeleteButton.qml` | `label`, `question`, `cancelTooltip`, `available`, `asking`, `confirmed()` | `size` |
| `Dropdown` | `components/Dropdown.qml` | `options`, `value`, `placeholder`, `picked(value)` | `size` |
| `InputField` | `components/InputField.qml` | `text`, `placeholder`, `problem`, `password`, `revealed`, `accepted()`, `edited()`, `editingFinished()` | `variant`: `plain`, `outlined`; `size` |
| `Pill` | `components/Pill.qml` | `label`, `picked`, `tooltip`, `clicked()` | `size`: `normal`, `large` |
| `Checkbox` | `components/Checkbox.qml` | `label`, `checked`, `toggled()` | — |
| `ToggleSwitch` | `components/ToggleSwitch.qml` | `checked`, `available`, `toggled()` | — |
| `PrivilegedMark` | `components/PrivilegedMark.qml` | `need` | `need`: none, `auth` (asks for a password), `no` (not allowed) |
| `SwitchRow` | `panels/settings/SwitchRow.qml` | `label`, `hint`, `checked`, `need`, `toggled()` | as `PrivilegedMark` |
| `DetailRow` | `panels/settings/DetailRow.qml` | `label`, `value` | — |
| `SettingsRow` (new) | the row block (§4.1) | `label`, `hint`, `value`; its children are the controls on the right | — |
| `ExpandingRow` (new) | `components/ExpandingRow.qml` | `label`, `hint`, `open`; its child is the content | — |
| `Heading`, `SectionTitle` | `panels/settings/` | `text` | the two are the two levels |
| `Hint` | `panels/settings/Hint.qml` | `text` | — |
| `Notice` (new) | a line as the card's notice line | `text` | `variant`: `warning`, `error`, `success` |
| `SettingEditor` | `panels/settings/SchemaSettingEditor.qml` | `key`, `editIndex` | — |
| `PopupWidget`, `BarText`, `BarRow` | `components/` (base types) | what a bar widget sets today, pinned by name | — |
| `PointerArea` | `components/PointerArea.qml` (base type) | `lit`, `centred`, `reach`, and a `MouseArea`'s own | — |
| `VpnProvider` | `components/VpnProvider.qml` (base type) | its documented contract (API 1.1), without `rowExtras`, `cardExtras`, `pageUrl` | — |

- The names are the internal ones where a module uses them today, so the migration is a
  change of import and of the few properties that became variants. None is `Row` or
  `Button`: with `import QtQuick` beside `import qs.api` those would silently replace
  QtQuick's `Row` (and Controls' `Button`) in a module's file.
- `Notice` replaces the warning lines the module writes by hand as a `Text` in the
  theme's warning colour (verified: `TailscaleCard.qml`).
- `ExpandingRow` is how a module adds an element that opens, on a card's `settings`, a
  section or a page. Its line looks and answers as a card's header does: the same "▸" /
  "▾" mark, the whole line a `PointerArea` (`centred: false`). Its child is held as a
  `Component` (QML wraps a child given to a `Component` property, as a `Repeater`'s
  delegate: assumed, checked in `QuickshellPinTest`), so nothing of it exists while closed.
  It is not an anchor.
- The six that `qs.api` offers already stay subtypes until the closing slice, which makes
  them wrappers (a tightening: a module could set an internal property on them today).

**How the set grows.** A module that needs an element, a property or a variant the set
lacks stops and has it added: one public element or one variant per slice, a minor version,
its line in `ApiElementsTest`. Nothing is added ahead of a module that needs it.

**Keeping modules off the internals.** QML cannot stop an import. The import check
(`ModuleRules.allowedImports`) reports `import qs.components` as a warning in the module's
status from the slice that completes the set (F4), and as an error from the closing slice,
when `qs.components` leaves the allowed list. The module still loads (the owner's earlier
decision: the check never refuses); the error shows in Settings → Modules and
`modules list`, and `tests/run-modules.sh` fails a module that has it.

### 4.10 The module's icon on a closed card

A closed card shows no module element, but it can show a module's icon: "something of
this module is set for this network". The detail is on the opened card, in the module's
row (the exit node's name).

- **Where.** At the end of the card's name line, after the name, before the buttons; the
  name is cut first, the icons keep their place. Shown open and closed.
- **What the icon is.** One glyph of the shell's icon font, declared once in the manifest:
  `"icon": "<glyph>"`. The shell draws glyphs this way everywhere, and the module already
  gives one for its VPN provider and its bar widget (verified: `VpnProvider.glyph`). The
  manifest check takes one visible character, nothing else. The shell draws it: the body
  text size, the muted text colour. No file, no QML of the module, no colour or size from
  the module.
- **Setting and clearing.**

  ```
  module.setMark(path, itemId, label)     // label: what it stands for, "Exit node: home"
  module.clearMark(path, itemId)
  ```

  `path` is a card's path whose table row says `marks` (in this round the saved Wi-Fi
  networks' and the wired profiles' cards); `itemId` is the item's id as in the card's
  context (`networkId`). `label` is the icon's accessible name and its tooltip, shown as
  "Tailscale: Exit node: home": plain text, one line, 40 characters. A module with no
  `icon` in its manifest, or a path that takes no marks: nothing shows, one warning in the
  status. At most 200 marks per module and path.
- **Several modules on one card:** in module id order, at most three icons, then "+2" in
  the muted colour with the rest in its tooltip. A pure rule,
  `ModuleRules.cardMarks(marks, path, itemId)` → `{ shown: [{ module, icon, label }], more }`.
- **The module goes off:** the host holds the marks and drops that module's, so its icons
  go at once. They are not stored; a module sets them again when it starts.
- A mark does nothing on a click; the card's header keeps the click.

---

## 5. Step 5: a module's public API, basic version

### 5.1 Declaring and using

```
// the provider's module.json
"exports": { "version": "1.0" }
// its main
readonly property QtObject exports: QtObject { … }     // what other modules may use

// the dependent's module.json
"uses": { "tailscale": "1.0" }
// in its files
module.uses.tailscale        // the provider's `exports` object, and nothing else of it
```

- The version is "major.minor", checked like the shell's: same major, the provider's minor
  at least the one asked for. What a provider's minor may change is the provider's rule.
- A dependent gets the `exports` object only. It is a plain `QtObject`, which has no way up
  to the main (no `parent` in QML).
- A module with `exports` in the manifest and no such property on its main: an error in its
  status; dependents count it as missing.
- Basic version: required dependencies only. Optional ones later.

### 5.2 Load order

A pure rule, `ModuleRules.dependencyPlan(manifests, states)`, gives the order and the
reasons. A dependent's main is created after its providers' and destroyed before them.

### 5.3 Missing, incompatible, reload

- A new state `missing-module` (beside `missing-program`), with the reason in the status:
  "needs module tailscale 1.0: not installed" / "turned off" / "failed" / "has 0.9".
- A cycle: every module in it is `failed`, naming the cycle.
- **A provider turned off or reloaded**: its dependents go first (`missing-module`), then
  the provider; turned on again, the provider first, then they come back. So
  `module.uses.x` never changes under a live main, and is never null while the dependent
  runs.
- A shell reload rebuilds everything in the same order.

Test: `ModuleRulesTest` (order, cycle, each reason, version check); `ModulesTest` with two
fixture modules (provider off and on, the dependent follows; the object given is the
`exports` object).

### 5.4 Reach closed

- `Api.module(id)` goes. `Api.moduleStatus(id)` gives a frozen
  `{ id, name, version, state, active }`.
- `ModuleHandle.host` becomes internal (`_host`). QML cannot hide a property, so this is a
  name, a status error on use, and the test kit (§3.3) for what suites needed it for.
- The import check (`ModuleRules.allowedImports`) reports `qs.singletons*` and another
  module's directory as an error in the status, not a warning. The module still loads (the
  owner's earlier decision: the check never refuses).
- `qs.components` leaves the allowed imports with the closing slice (§4.9). The module
  uses 13 of its types (verified): `BarRow`, `BarText`, `Checkbox`, `DeleteButton`,
  `Dropdown`, `InputField`, `Pill`, `PointerArea`, `PopupWidget`, `PrivilegedMark`,
  `SmallButton`, `ToggleSwitch`, `VpnProvider`; in 17 of its files.

---

## 6. Versioning

**A minor may tighten** (the owner's decision, for now). What it means here:

- Every slice bumps the minor once and adds one `- 1.x:` line under `### Module API` in
  `CHANGELOG.md`. What a slice refuses or removes is named in that line after
  "Tightened:".
- There is no 2.0 in this plan.
- **The manifest check gains a floor.** `ModuleRules.apiFloor` is the oldest API version
  whose modules still run unchanged on this shell. A slice that removes or refuses
  something a module could rely on raises it to its own version. `apiCompatibility` then
  answers: same major, `apiFloor` ≤ the module's `api` ≤ the shell's. Below the floor the
  module is `incompatible`, with the reason "written for module API 1.3; this shell needs
  1.24 or newer (the module needs updating)". So a tightening is never silent.
- **During this plan the floor moves once.** Slices in steps 3–5 only add: the old ways
  (`PrivilegedAction`, `elevate`, `slots`, `Api.module`, `host`) keep working, with a
  warning in the module's status. New calls are strict from their first version. One
  closing slice after step 6 removes the old ways and raises the floor. `master` therefore
  always runs the released module.
- A test compares the newest `- 1.x:` line in `CHANGELOG.md` with `ModuleRules.apiVersion`
  (`ModuleRulesTest.qml` stops hard-coding "1.3").
- When someone else uses the shell, the rule is tightened (the owner's decision); the
  floor stays as the mechanism.

---

## 7. Slices

Every slice: one change with its test; `tests/run-unit.sh` green, and `tests/run-modules.sh`
on the released module green; the `Api.qml` header, `ModuleRules.apiVersion` and one
CHANGELOG line updated together. The numbers assume this order; a slice merged out of
order, or after one that was dropped, takes the next free minor.

### Step 3

| Slice | API | Files | Verified by |
|---|---|---|---|
| A0 Version gate and floor | — | `ModuleRules.qml` (`apiFloor`, `apiCompatibility`), `tests/ModuleRulesTest.qml` | rule cases; CHANGELOG ↔ `apiVersion` test |
| A1 Command runner | 1.4 | `singletons/io/CommandRunner.qml`, `api/CommandRunner.qml`, `io/CommandAction.qml`, `io/CommandQuery.qml`, `api/Api.qml` (`_opener`) | `CommandRunnerTest`; old suites unchanged |
| A1b Host on the runner | — | `ModuleHost.qml` (four blocks) | `ModulesTest`; lock bed `modules`, `modules-hung` |
| A2 Program lookup with trust | 1.5 | `ModuleRules.qml`, `ModuleHost.qml`, `api/ModuleHandle.qml`, a fixture | verdict cases; fixture |
| A3 Test mode | 1.6 | `ModuleHost.qml`, `Modules.qml`, `api/Api.qml`, `tests-modules.qml`, `tests/ModuleTestKit.qml` | `ModulesTest` (three cases in §3.3) |
| A4 Privileged start | 1.7 | `singletons/PrivilegedRuns.qml`, `PolkitRules.qml`, `api/ModuleHandle.qml`, `api/PrivilegedAction.qml` (onto the queue) | stand-in pkexec suite |
| A5 The prompt says who and what for | — (user-visible: CHANGELOG "Unreleased") | `PolkitRules.qml` (`announcement`, `announces`), `polkit/AuthPrompt.qml`, `Authentication.qml` | `PolkitRulesTest`; view test; by hand on both systems, once |
| A6 The notification when another agent answers | — (user-visible) | `singletons/PrivilegedRuns.qml` | stand-in pkexec suite: one notification before the start with `other`, none with `active` |
| B1 Shared module object, popup inputs | 1.8 | `ModuleHost.qml`, `api/ModuleHandle.qml`, `components/PopupWidget.qml`, `panels/Popup.qml` | `ModuleRegistriesTest` |
| C1 Helpers | 1.9 | `singletons/AddressRules.qml`, `network/NetworkRules.qml`, `Format.qml`, `Notifier.qml`, `api/Api.qml`, `api/ModuleHandle.qml` | `AddressRulesTest`, `FormatTest`, `NotifierTest`, `ModulesTest` |
| C2 System facts, data directory | 1.10 | `singletons/SystemFacts.qml`, `ModuleHost.qml`, `api/Api.qml`, `api/ModuleHandle.qml`, test kit | `SystemFactsTest` |
| D1 Network facts | 1.11 | `ModuleRules.qml` (`apiNetworks`, `apiVpnsUp`, `apiLocalNetworks`), `api/Api.qml`, `network/VpnManager.qml`, `components/VpnProvider.qml` | `ModuleRulesTest` |
| E0 File chooser: the spike | — | none kept; the finding goes into this plan | the four points of §3.9, on both systems |
| E1 File chooser | 1.12 | `singletons/FileChooser.qml`, `ModuleHost.qml`, `api/ModuleHandle.qml`, test kit | recorded calls in test mode; closed with the module; by hand |

### Step 4

| Slice | API | Files | Verified by |
|---|---|---|---|
| U0 Anchor rules | — | `ModuleRules.qml` (`anchorTable`, empty; the path rule; the manifest's `anchors` check; slot aliases; `anchorContent`), `tests/ModuleRulesTest.qml` | rule cases |
| U1 The host and the page block; the General page | 1.13 | `components/AnchorBlock.qml`, `AnchorContent.qml` (from `ModuleSlot`), `SettingsPage.qml`, `singletons/Anchors.qml`, `ModuleRules.qml` (the first table row), `ModuleHost.qml`, `api/Api.qml` (`anchors`), `SettingsWindow.qml`, `GeneralSettings.qml`, `tests/lock-closure.sh` | `AnchorsTest` (new); the walk up `parent` in `QuickshellPinTest`; `ModuleRegistriesTest` slot cases still pass through the aliases |
| U2 Popups | 1.14 | `components/PopupSection.qml`, `PopupRow.qml`, `panels/Popup.qml`, `NetworkPanel.qml`, `panels/network/VpnSection.qml`, `NotificationPanel.qml` | `AnchorsTest`; by hand: both popups unchanged to the eye |
| F1 Public elements: the pattern, and the buttons | 1.15 | `api/SmallButton.qml`, `api/DeleteButton.qml` (wrappers, `variant`, `size`), `components/SmallButton.qml` (eliding), `tests/ApiElementsTest.qml` | `ApiElementsTest` (new): names, every variant, plain text; a wrapper in a layout, in `QuickshellPinTest` |
| F2 Public elements: the controls | 1.16 | `api/Dropdown.qml`, `InputField.qml`, `Pill.qml`, `Checkbox.qml`, `ToggleSwitch.qml`, `PrivilegedMark.qml` | `ApiElementsTest` |
| F3 Public elements: rows and texts | 1.17 | `components/SettingsRow.qml`, `ExpandingRow.qml`, `api/SettingsRow.qml`, `ExpandingRow.qml`, `Notice.qml`; plain text in `SwitchRow`, `Heading`, `Hint`, `SectionTitle` | `ApiElementsTest`; the `Component` child in `QuickshellPinTest` |
| F4 Public elements: the base types; the import warning | 1.18 | `api/PopupWidget.qml`, `BarText.qml`, `BarRow.qml`, `PointerArea.qml`, `VpnProvider.qml`, `ModuleRules.qml` (import check: `qs.components` warns) | `ApiElementsTest`; `ModuleRulesTest`; `VpnProvidersTest` with a provider made from `qs.api` |
| U4 The card and its regions; the VPN page | 1.19 | `components/SettingsSection.qml`, `SettingsCard.qml`, `NetworkProfileCard.qml` (on `SettingsCard`), `NetworkVpnSettings.qml`, `AnchorContent.qml` (scope, `takes`), `network/VpnManager.qml` | `AnchorsTest`, `VpnProvidersTest`; `instanceof` in `QuickshellPinTest`; by hand: the three network pages unchanged to the eye |
| U5 The Wi-Fi and Ethernet pages | 1.20 | `NetworkWifiSettings.qml`, `NetworkEthernetSettings.qml`, `ModuleRules.qml` (table rows) | `AnchorsTest`; by hand |
| U6 The module's icon on a closed card | 1.21 | `ModuleRules.qml` (manifest `icon`, `cardMarks`), `ModuleHost.qml`, `api/ModuleHandle.qml` (`setMark`, `clearMark`), `components/SettingsCard.qml` | `ModuleRulesTest` (the glyph check, order, the cap, a module off); `AnchorsTest` |

U4 changes `NetworkProfileCard`, which all three network pages use, so its hand check
covers all three although only the VPN page gains anchors there.

### Step 5

| Slice | API | Files | Verified by |
|---|---|---|---|
| P1 `exports` and `uses` | 1.22 | `ModuleRules.qml` (`dependencyPlan`, state), `ModuleHost.qml`, `api/ModuleHandle.qml`, two fixtures | `ModuleRulesTest`, `ModulesTest` |
| P2 Reach warnings, `moduleStatus` | 1.23 | `api/Api.qml`, `api/ModuleHandle.qml`, `ModuleRules.qml` (import check) | `ModuleRulesTest`, `ModulesTest` |

### Step 6: the module, then the closing slice

Each module slice raises its manifest `api` and removes one group of §1:

| Slice | Removes (rows of §1) | Needs |
|---|---|---|
| M1 Runner | 1–4 | A1 |
| M2 Programs and test mode | 9–15 | A2, A3, C2 |
| M3 Privileged, with a `what` for every run | 5–8 | A4, M2 |
| M4 Main and popup | 16–19 | B1 |
| M5 Helpers and facts | 22–33 | C1, C2, D1 |
| M6 Its row and card move from `slots` to `anchors` | the `slots` field | U2, U4 |
| M7 The exit node per network on the network cards, with the icon | 21 | F3, U5, U6, M6 |
| M8 "Send file…" from the popup; both Taildrop dialogs through the chooser | 20 | E1 |
| M9 The manual "for now" override | — (module state) | M7 |
| M10 Public elements only: every `import qs.components` goes (17 files, 13 types); `kind` and `fontSize` become `variant` and `size`; hand-made warning lines become `Notice` | — (the import) | F1–F4 |

M10 is one change per group of files (the popup, the page's sections, the widget), each
with the module's UI suites green; the import warning in the module's status counts down
to none.

**Z, the closing slice (core, 1.24, floor 1.24):** removes the `PrivilegedAction` type and
`elevate`, the `slots` field, `Api.slots`, `components/ModuleSlot.qml`,
`components/VpnExtras.qml` with `VpnProvider.rowExtras` / `cardExtras` (the stand-in in
`VpnProvidersTest` becomes a fixture module), `network.vpn.page`, `Api.module`, `host`;
`qs.components` leaves the allowed imports (an error in the status), and the six older
`qs.api` types become wrappers (§4.9); row 34 of §1 goes in the module with its `api`
raised to Z's version.

### What can run in parallel

- Chains that must stay in order: A0 → A1 → A2 → A3 → A4 → A5 → A6; U0 → U1 → U2;
  F1 → F2, F3, F4 (these three in any order); U1 and F1 → U4 → U5 → U6; P1 → P2.
- Parallel to the A chain: B1, C1, the U chain and the F chain. The F chain touches only
  `api/` and two new files in `components/`, so it runs beside U0–U2.
- C2 after A3 (test kit); D1 after C1 (`NetworkRules` delegates to `AddressRules`); E0 any
  time, E1 after A3 and E0.
- Everything touches `ModuleRules.qml`, `api/Api.qml`'s header and the CHANGELOG. To keep
  that from colliding, the pure split of `ModuleRules.qml` into five files
  (`architecture-cleanup.md` §2.1) goes first, and each slice adds its version line last,
  at merge.
- Module slices M1–M10 touch only the module's repository and run beside the core slices
  that do not block them.

### Later, not in this round

Recorded, not designed (the owner, 2026-11-17; also in the tracker's "Later"):

- **The order of modules:** the order in which modules are loaded, and the order of
  different modules' elements in one place. Two separate things. Until then both are by
  module id (loading also follows `uses`, §5.2).
- **Modules' own elements:** a module defines an element of its own, with its own public
  styles that a theme can set, and publishes it through a public API, so that libraries of
  extra elements can exist.

---

## 8. The owner's answers, and what is still open

Answered 2026-11-17:

| What | The owner's answer | Where |
|---|---|---|
| Where the per-network exit node sits | The saved network's card, opened. The connection editor can follow as a second anchor once a module's row can join a form | §4.7 |
| A module's privileged run when another polkit agent answers | Run, with a shell notification just before, naming the module and what for | §3.4 |
| The prompt's "what for" | A few words given with each run: "Module: Tailscale, Authorization: Send a file" must already say what it is about. The labels "Module" and "Authorization" stay | §3.4 |
| The command in the prompt | Hidden; shown on a click; it must be the real command | §3.4 |
| The file chooser | In this round, a minimal version | §3.9 |
| Placements | `before`, `after` (outside the block), `prepend`, `append` (inside, first and last) | §4.1 |
| The shell's controls in modules | Not a promise on the internals: a layer of public elements made for the API, which use the internal ones inside. Modules use only those, and as many as they can | §4.9 |
| Variants | A public element lets a module pick its variant (a plain, a confirm, a delete button, …); for all elements, not only buttons | §4.9 |
| A module's button on a card | The shell's button, always above "Forget" / "Delete" | §4.8 |
| An element that opens | The shell's `ExpandingRow` | §4.9 |
| A closed card | Shows the module's icon when the module has something set for that network; the detail is on the opened card | §4.10 |
| The order of modules (loading, and elements in one place) | Both wanted, both later; for now by module id | §7, "Later" |
| Modules' own elements, element libraries | Later | §7, "Later" |

Still open. Each is written to be read on its own.

**Q1. Which kinds of button may a module put among a card's buttons?**

- *Today.* An opened network card (Settings → Network → Wi-Fi, a saved network) has its
  buttons on the right: "Connect" in the confirm colour, under it "Edit connection…" in
  the plain look, and last "Forget", which turns red and asks "Forget?" before it does
  anything.
- *What is new.* A module can add its own button to that stack, above "Forget". The
  shell's button comes in five looks: plain, confirm (green), confirm a change, cancel,
  delete (red under the pointer, acts on the first click).
- *Example.* A module adds "Remove exit node" in the delete look. The card then has two
  red buttons one above the other; the module's acts at once, the shell's asks first. Or
  it adds a second green button next to "Connect", and the eye no longer finds the card's
  main action.
- *Options.* (a) Only the plain look in that stack; another look is shown as plain.
  Elsewhere (the module's own rows, its page, its popup) every look is allowed. (b) Every
  look everywhere.
- *Recommendation:* **(a)**. A module that must delete something from a card does it in
  its own row, with the button that asks first.

**Q2. What is a module's icon?**

- *Today.* The shell draws its icons as characters of an icon font (the VPN mark in the
  network popup is one). The Tailscale module already names such a character for its VPN
  entry and its bar widget.
- *What is new.* The icon a closed card shows for a module (your answer above).
- *Options.* (a) One character of the icon font, named in the module's manifest. The shell
  draws it in its own size and colour, so it always fits the theme; a module can only pick
  among the font's icons. (b) A picture file shipped with the module (the real Tailscale
  logo, in its colours). It looks like the brand, but it does not follow the theme, and
  the shell has to check, scale and tint a file it did not make.
- *Recommendation:* **(a)** now. A picture can be added later without changing how marks
  are set.

---

## 9. Verified, assumed, hard

**Verified in the code.**
- Every module reference in §1 (the module's QML is unchanged since the earlier read; only
  its `CLAUDE.md` differs).
- `ModuleHost.qml` has four `Process` blocks with their own deadlines; `Lockscreen.qml`
  three probes; `api/PrivilegedAction.qml` checks only "absolute and executable" and
  queues per instance; nothing in the core uses that type.
- `apiCompatibility` checks major and minor only; `tests/ModuleRulesTest.qml` hard-codes
  "1.3".
- The slot table has six names; the module uses `network.vpn.row` and `network.vpn.card`.
  `ModuleSlot` is used in `NetworkPanel.qml`, `NotificationPanel.qml` and
  `GeneralSettings.qml`; the two VPN slots are built by `components/VpnExtras.qml`.
  `ModuleRules.merge` orders modules by id.
- The survey in §4.1; `NetworkProfileCard`'s controls apply at once; the connection editor
  saves on a button.
- `NetworkProfileCard.qml`: the secondary buttons are right-aligned at their own width,
  "Forget" last; the opened column is the card's two rows, then the page's (`_extra`); all
  of it is built with the card today and only hidden while closed. On the VPN page the
  provider's content is the first of the page's rows. The three network pages build their
  cards from `ScriptModel`s keyed by `uuid` and keep one card open (`_open`).
- What `qs.api` offers today: `SettingEditor`, `SectionTitle`, `Heading`, `Hint`,
  `DetailRow`, `SwitchRow`; four of them set no `textFormat`.
- The module's two dialogs (`TaildropSection.qml`): several files, from the home directory;
  a folder, from the current one. The core has a `FileDialog` on the VPN page.
- The unit suites run with D-Bus addresses that lead nowhere (`tests/headless.sh`), and
  today only compile the network pages (`tests/SettingsPagesTest.qml`);
  `NetworkProfiles.profiles` is a plain property a suite can set.
- A manifest's unknown top-level field is kept with a warning.
- Quickshell's polkit flow exposes `message`, `actionId`, `cookie`, identities and the
  conversation; no command line. `AuthPrompt.qml` sets no `textFormat` on those texts.
- `Process` has `signal(int)`, `stdinEnabled` and `write()`, `environment`,
  `workingDirectory` (Quickshell 0.3.2's types).

**Assumed.**
- A program that cannot start gives no `exited` (seen in the module's working code).
- pkexec's message names the path of the program it is given (the shell's `timeout`) in
  every locale. A4 checks it with the real pkexec's message text, by hand, on both systems.
- Signalling pkexec while its prompt shows ends it; a destroyed `Process` may not kill its
  child (the runner signals explicitly).
- NetworkManager may or may not report `tailscale0`'s addresses; the filter covers both.
- A block can find its enclosing block by walking `parent` at completion, also inside a
  `Loader` and a `Repeater` delegate. U1 starts by checking it in `QuickshellPinTest`.
- `instanceof` tells a built element is the public `SmallButton` (U4); a child given to a
  `Component` property is wrapped, not built (F3); a wrapper `Item` that takes its size
  from the item inside stands in a `RowLayout` and a `ColumnLayout` as that item did (F1).
  Each slice starts by checking its own in `QuickshellPinTest`.
- The shell's font has a glyph for whatever a module names as its icon; a missing one
  shows as an empty box.
- `tests/run-modules.sh` can be made to fail on an import error in a module's status.
- A `ScriptModel` keeps a delegate when its item's values change. If it rebuilds it
  instead, a module's element on that card is rebuilt too: harmless, an opened
  `ExpandingRow` closes.
- Whether `FileDialog` opens as its own window in the shell (the spike, §3.9). The
  module's dialogs have never been clicked on a real machine (tracker backlog).
- The pin test can build the network pages with no D-Bus without errors that fail a suite.

**What the current code makes hard.**
- **No shared blocks exist.** Anchors need them first; converting all 26 pages and 9 popups
  at once would be a large visual-risk change, so the plan converts view by view and the
  anchor list starts short.
- **The prompt cannot identify its caller.** The flow has no command line or process id;
  matching rests on the queue's head and pkexec's message (the assumption above). With
  another agent the shell cannot show anything in the prompt, and that prompt names only
  `timeout`: the notification is all the user is told.
- **"Connection's options" has two homes** with different save models; the owner chose the card (§8).
- **The VPN slots are filtered per provider** and built through `VpnManager.extrasFor` and
  `VpnExtras`, not `ModuleSlot`. U2 and U4 move a module's content to the anchor hosts with
  `scope`; `VpnExtras` stays for a provider that is no module's (the test stand-in) until
  the closing slice.
- **One card for four uses.** `NetworkProfileCard` serves Wi-Fi, Ethernet, hotspots and
  VPN providers; rebuilding it on `SettingsCard` (U4) is the largest visual risk of step 4,
  and all three network pages are checked by hand in that slice.
- **A public control is one more `Item`** around the internal one (§4.9). The module has
  65 buttons; the cost is small but real, and layout properties a module sets must reach
  the wrapper, not the inside.
- **Variants freeze today's looks.** What the internal components offer as `kind`,
  `fontSize`, `outlined` becomes five, three and two named values; a look the shell adds
  later is a new variant, a look it drops needs a mapping.
- **A block's root gains a level** (§4.4), so a converted view's layout properties move
  from today's item to the block. Views that anchor into their children by `id` need care.
- **`ModuleRules.qml` is one 1667-line file** that nearly every slice edits; the planned
  split should go first.
- **QML cannot hide anything.** `host`, `module.main` and `exports` are reachable by a
  module that tries; the plan closes them by name, status errors and review.
- **The core breaks its own rule:** `network/VpnLockdown.qml` runs `pkexec sh <script>`
  from the shell's tree (tracker, "Found while writing the development rules"). It is not
  a module run and stays outside this plan, but the prompt will show it without module
  lines, as a plain pkexec request.
