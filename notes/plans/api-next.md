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
| 20 | "Send file…" in the popup sets a timed request and opens the settings page, whose section opens the `FileDialog` | `Api.chooseFiles` (§3.9) |
| 21 | The exit node per network is edited in a table on the module's own page (`NetworkExitTable.qml`) | An anchor on the saved network's card (§4.7) |

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
prompt shows polkit's message with no `textFormat` (`polkit/AuthPrompt.qml`), against the
plain-text rule; `ModuleHandle.host` and `Api.module(id)` hand a module the host and other
modules (§5.4).

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
- `Api.openUrl` and `Api.chooseFiles` record the call and open nothing.
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
  the user gets instead is a prompt that says who asks and why.
- **Refused before pkexec runs:**
  - `untrusted`: `argv[0]` has no trusted verdict (§3.2), or is a shell or `env` (then the
    real program would be an argument nobody checked).
  - `locked`; `no-purpose` (`what` empty after cleaning); `notFound` as today.
- **Root helpers.** By the rule above, nothing under a module's own directory in the user's
  data home ever runs as root. No module has a root helper today; where a packaged helper
  is looked up is designed when the first one needs it.

**The prompt** (`polkit/AuthPrompt.qml`, when the shell's agent answers). Under the shell's
own title it shows three labelled lines, then polkit's own message as today:

```
Module    Tailscale (tailscale)
For       Connect Tailscale
Command   /usr/bin/tailscale up --accept-routes
```

- **Where the text comes from.** `Module`: the manifest's `name` and the module's id, taken
  by the shell from the handle the run was started on. `For`: the run's `what`. `Command`:
  the `argv` the shell passes to pkexec, joined with shell quoting.
- **Plain and capped.** A pure rule `PolkitRules.announcement(run)` drops control
  characters, folds white space to one line and caps the name at 40, `what` at 80 and the
  command at 240 characters (cut with "…"). All four texts are `Text.PlainText`; polkit's
  message becomes plain text too.
- **Not spoofable as the shell.** A module's words only ever fill the values of these
  lines. The title, the labels and the frame are the shell's; the first line always starts
  with "Module"; a module id cannot be a word for the shell (`ModuleRules.reservedIds`
  holds `shell`, `system`, `polkit`, `h2s-shell` and the like: verified). One line each, so
  a text cannot fake a second line.
- **Which request is announced.** The agent's flow carries only `message`, `actionId` and
  `cookie` (verified in Quickshell's polkit types): no command line, no caller. So
  `PolkitRules.announces(flow, run)` matches the run at the head of the queue when the
  action is pkexec's (`org.freedesktop.policykit.exec`) and the message names `argv[0]`
  (assumed: pkexec's message holds the program's path in every locale). Anything else shows
  as today, with no module lines: a request the shell did not start is never dressed up.
- **Another agent answers** (`Authentication.state` is `other`): the shell cannot change
  its prompt. See Q2.

The old `PrivilegedAction` type keeps working unchanged until the closing slice (§7); its
runs go through the same queue and are announced as "Module (not named)".

Test: `PolkitRulesTest` (announcement cleaning and caps, matching, a hostile name and
`what`); a shell suite with a stand-in pkexec that prints and sleeps: streaming, cancel
while queued and after start, a second run not blocked by a cancelled one, the time limit
in the argv, every `blocked` reason, 127 reported once; `LockViewTest`-style view test for
the prompt's three lines.

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
Api.chooseFiles({ mode: "open" | "openMany" | "folder" | "save", title, folder, nameFilters }, done)
```

Hosted by the shell, not the caller's window, so a popup can call it and close. One at a
time; refused while locked; absolute paths, never URLs. Starts with a spike: whether a
`FileDialog` opens as its own window in the shell is unverified. If not, a small shell
window hosts it.

### 3.10 Cut from the earlier draft

- A terminal call and a terminal setting: the owner decided a global "default programs"
  setting later. "Copy ssh command" stays.
- The 10 s click window for privileged runs.
- API 2.0: with "a minor may tighten", removals ship in a minor (§6).

---

## 4. Step 4: UI anchors

### 4.1 Blocks

Views are built from five shared blocks. Each has an `anchor` name; that is all a view's
author writes.

| Block | File (new, `components/`) | What it is | Placements |
|---|---|---|---|
| Settings page | `SettingsPage.qml` | a page's root: scrolling, margins, heading | prepend, append |
| Section | `SettingsSection.qml` | a titled group on a page | before, after, prepend, append |
| Card | `SettingsCard.qml` | a framed item that opens (a saved network, a VPN) | before, after; inside it through its regions (§4.8) |
| Row | `SettingsRow.qml` | one line: a label with a control or a value | before, after |
| Popup section | `PopupSection.qml` | a group in a popup panel; the panel's root is one too | before, after, prepend, append |
| Card region | part of `SettingsCard.qml` | a named part of a card: its actions, its settings (§4.8) | prepend, append |

The four placements: `before` and `after` put an element next to the block, outside it;
`prepend` and `append` put it inside, as the first or the last of the block's content (a
page's heading and a section's title stay above a prepended element).

**How consistent the views are today** (verified by reading `panels/`):
- 26 settings pages with four kinds of root: `Flickable` (14), `ShapeSettings` (5),
  `ColumnLayout` (4, scrolled by the window), `Item` (3: network pages with an editor
  laid over them). There is no page block.
- Sections are a `SectionTitle` followed by loose siblings, and only on the network pages
  (30 uses of `SectionTitle`/`Heading` in all); other pages mark sections with a comment or
  a `Label`. There is no section block.
- Cards exist as `NetworkProfileCard` and `NetworkDeviceCard`. Rows exist as `SwitchRow`,
  `DetailRow`, `SettingEditor`, `SettingInputRow`, and many hand-made `RowLayout`s.
- 9 popup panels, each a bare `Item` with a `Column`; only the network popup has parts in
  files of their own (`panels/network/VpnSection.qml` and others). There is no popup
  section block.

**What is refactored first.** Not everything. A view gets blocks when it gets its first
anchor. This round converts only what today's slots and the first consumer need: the
General page, the network and notifications popups, the VPN, Wi-Fi and Ethernet pages.
`NetworkProfileCard` becomes a `SettingsCard`. Other views follow when a module needs them
or when step 7 touches them; until then they have no anchors, and the table says so.

### 4.2 Naming

```
<surface>.<view>[.<block>]…
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
- Unique among siblings. A block with no `anchor` is not addressable and adds no level.

Examples, from today's views:

| Path | Block | Placement a module would use |
|---|---|---|
| `settings.general` | the General page | append: today's slot `settings.general.bottom` |
| `popup.network.connections` | the VPN, Ethernet and Wi-Fi parts of the network popup | append: today's `network.popup.sections` |
| `popup.network.connections.vpn.row` | each VPN's row in the popup | after: today's `network.vpn.row` |
| `popup.notifications.list` | the notification list | before: today's `notifications.popup.top` |
| `settings.network_vpn.vpns.card.settings` | each VPN's card, its opened part | append: today's `network.vpn.card` |
| `settings.network_wifi.saved.card.settings` | each saved Wi-Fi network's card, its opened part | append: the exit node for this network |
| `settings.network_wifi.saved.card.actions` | the same card's buttons | append: one more button under "Edit connection" |
| `settings.network_ethernet.profiles.card.settings` | each wired profile's card, its opened part | append: the same |

### 4.3 How a path is derived and stays stable

- The window gives a page's root its base (`settings.<page id>`), the popup gives a panel's
  root `popup.<key>`. A block's path is its nearest enclosing block's path plus its own
  `anchor`; it finds that block by walking up `parent` when it is completed.
- So a path changes only when a block is renamed or moved under another block. Reordering
  blocks, changing titles or wrapping them in layouts changes nothing.
- The list of anchors is a table, `ModuleRules.anchorTable`:
  `{ path, kind, placements, context, scope, since, where }`. `Api.anchors` is its frozen
  copy; the documentation's list is generated from it. Only paths in the table take
  content: naming a block does not publish it.
- Views built by a module are not anchors in this round.

### 4.4 Registration and building, within the Repeater rules

- A block whose path is in the table holds one small host per placement that has content.
  The host is today's `ModuleSlot` machinery, kept as it is: a `Repeater` on a
  `ScriptModel` keyed by `ModuleRules.contributionKey`, each element in a
  `ModuleContribution` guard. It is created only when the module host lists content for
  that path and placement, so a block nobody targets costs one string.
- `prepend` and `append` hosts are the first and the last child of the block's content.
- `before` and `after` hosts sit inside the block's own item, above and below its content.
  The parent layout sees one item, so a block works in a `Column`, a layout, or as a
  `Repeater`'s delegate. A hidden block hides its `before` and `after` content with it.
- Both Repeater rules hold as they do for `ModuleSlot` today (verified: it sits in
  `NetworkPanel.qml`, built by `panels/Popup.qml` outside the window's incubation, and in
  the VPN cards' delegates): popup content is still created through `Qt.callLater`, and no
  host binds a live array.
- Blocks also report themselves to a plain core singleton, `singletons/Anchors.qml`
  (`live`: path → count). Nothing in the running shell decides by it; the pin test and
  `modules list` read it.

**An element** is what a slot contribution is today: built in its own guard; its root may
declare `module`, `context` and `shown`. `context` is `{ anchor, placement, … }` plus what
the table documents for that path. `scope: "own-provider"` (the VPN row and card) builds a
module's element only on the items of its own VPN provider, as the VPN slots do today.

Manifest:

```
"anchors": [{ "at": "settings.network_wifi.saved.card.settings", "place": "append", "component": "ExitNodeRow.qml" }]
```

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
  module, manifest order; top to bottom. Stable across installs (today the order is the
  search path's; assumed from `ModuleRules.merge`).

### 4.6 The test that pins the list

`tests/AnchorsTest.qml`:
1. builds every converted settings page and popup panel with the fixture module off,
   collects `Anchors.live`, and compares it with the table: every table path is live, and
   every live path that is not in the table is listed in the test as "named, not published";
2. checks every path against the naming rule, and that no table path is under
   `lockscreen`, the screensaver or `singletons/lock` (extends `tests/lock-closure.sh`:
   none of the five blocks may be built on the lock screen's path);
3. with the fixture module on: one element per placement of each kind appears, in order,
   with the documented context; an unknown path gives a status error.

Repeated blocks (cards, rows) need an item to be live; the test feeds the page stand-in
data (`tests/FakeVpnProvider.qml` exists for the VPN ones).

### 4.7 Today's slots, and the first consumer

| Slot (`ModuleRules.slotTable`) | Becomes |
|---|---|
| `network.popup.sections` | `popup.network.connections`, append |
| `notifications.popup.top` | `popup.notifications.list`, before |
| `settings.general.bottom` | `settings.general`, append |
| `network.vpn.row` | `popup.network.connections.vpn.row`, after, own-provider |
| `network.vpn.card` | `settings.network_vpn.vpns.card.settings`, append, own-provider |
| `network.vpn.page` | removed: a provider's page is its `settingsPage` (API 1.2); the module does not use the slot |

During the migration a manifest's `slots` entries are read as these anchors, with a
warning. `components/ModuleSlot.qml`, `Api.slots` and the `slots` field go in the closing
slice (§7).

**First consumer: the exit node per network.** The saved network's card, opened, already
holds that network's own choices, each applied at once (connect automatically, priority:
`NetworkProfileCard.qml`). The module appends one row there, on
`settings.network_wifi.saved.card.settings` and
`settings.network_ethernet.profiles.card.settings`, with
context `{ networkId (the profile's UUID, as in Api.networks), name, kind, active, open }`.
The choice stays in `module.store`, keyed by `networkId`, and applies at once like its
neighbours. Hotspots and VPNs have other paths, so the row never shows there.
`NetworkExitTable.qml` on the module's page goes.

### 4.8 Inside a card

A card is not one list: `NetworkProfileCard.qml` has a header (name and a line), a stack of
buttons on the right (the primary one; opened, the secondary ones under it), a notice line,
and, opened, its settings. So a card takes no `prepend` or `append` itself; it has two
regions, each an anchor under the card's path:

| Region | What a module's element is there | Built |
|---|---|---|
| `<card>.actions` | a button in the stack of secondary buttons, on the same right edge; the card gives it its width | while the card is open |
| `<card>.settings` | a row among the card's own settings (connect automatically, priority) | while the card is open |

The header and the notice line are not regions: a module does not change a card's name,
its line or its primary button. A module's state on a closed card is not offered in this
round.

What a module puts there is built from the shell's own blocks, so it looks and behaves as
its neighbours do. `qs.api` gives, besides the five blocks:

- `Button` (today's `components/SmallButton.qml`): the element for `actions`, and for a
  button at the end of a row.
- `Row` (`SettingsRow.qml`): a label, an optional second line, and a control or a value.
- `ExpandingRow` (new, `components/SettingsExpandingRow.qml`): a row that opens, with the
  same mark and click area as a card; its content is the module's and is built while it is
  open. This is how a module adds an opening element — to a card's `settings`, a section
  or a page. An `ExpandingRow` in a module's element is not an anchor.

The element's `context` on both regions is the card's: `{ networkId, name, kind, active,
open }`.

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
- `qs.components` stays allowed in this round (Q5).

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
  1.18 or newer (the module needs updating)". So a tightening is never silent.
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
order takes the next free minor.

### Step 3

| Slice | API | Files | Verified by |
|---|---|---|---|
| A0 Version gate and floor | — | `ModuleRules.qml` (`apiFloor`, `apiCompatibility`), `tests/ModuleRulesTest.qml` | rule cases; CHANGELOG ↔ `apiVersion` test |
| A1 Command runner | 1.4 | `singletons/io/CommandRunner.qml`, `api/CommandRunner.qml`, `io/CommandAction.qml`, `io/CommandQuery.qml`, `api/Api.qml` (`_opener`) | `CommandRunnerTest`; old suites unchanged |
| A1b Host on the runner | — | `ModuleHost.qml` (four blocks) | `ModulesTest`; lock bed `modules`, `modules-hung` |
| A2 Program lookup with trust | 1.5 | `ModuleRules.qml`, `ModuleHost.qml`, `api/ModuleHandle.qml`, a fixture | verdict cases; fixture |
| A3 Test mode | 1.6 | `ModuleHost.qml`, `Modules.qml`, `api/Api.qml`, `tests-modules.qml`, `tests/ModuleTestKit.qml` | `ModulesTest` (three cases in §3.3) |
| A4 Privileged start | 1.7 | `singletons/PrivilegedRuns.qml`, `PolkitRules.qml`, `api/ModuleHandle.qml`, `api/PrivilegedAction.qml` (onto the queue) | stand-in pkexec suite |
| A5 The prompt says who and what for | — (user-visible: CHANGELOG "Unreleased") | `polkit/AuthPrompt.qml`, `PolkitRules.qml`, `Authentication.qml` | `PolkitRulesTest`; view test; by hand on both systems, once |
| B1 Shared module object, popup inputs | 1.8 | `ModuleHost.qml`, `api/ModuleHandle.qml`, `components/PopupWidget.qml`, `panels/Popup.qml` | `ModuleRegistriesTest` |
| C1 Helpers | 1.9 | `singletons/AddressRules.qml`, `network/NetworkRules.qml`, `Format.qml`, `Notifier.qml`, `api/Api.qml`, `api/ModuleHandle.qml` | `AddressRulesTest`, `FormatTest`, `NotifierTest`, `ModulesTest` |
| C2 System facts, data directory | 1.10 | `singletons/SystemFacts.qml`, `ModuleHost.qml`, `api/Api.qml`, `api/ModuleHandle.qml`, test kit | `SystemFactsTest` |
| D1 Network facts | 1.11 | `ModuleRules.qml` (`apiNetworks`, `apiVpnsUp`, `apiLocalNetworks`), `api/Api.qml`, `network/VpnManager.qml`, `components/VpnProvider.qml` | `ModuleRulesTest` |
| E1 File chooser (spike first) | 1.12 | `singletons/FileChooser.qml`, `api/Api.qml`, test kit | recorded calls in test mode; by hand |

### Step 4

| Slice | API | Files | Verified by |
|---|---|---|---|
| U1 Blocks, table, manifest field; the General page | 1.13 | the five block files, `components/AnchorContent.qml` (from `ModuleSlot`), `singletons/Anchors.qml`, `ModuleRules.qml` (`anchorTable`, manifest `anchors`, slot aliases, order), `ModuleHost.qml`, `api/Api.qml`, `SettingsWindow.qml`, `GeneralSettings.qml`, `api/` names for the blocks | `AnchorsTest`; `ModuleRegistriesTest` slot cases still pass through the aliases |
| U2 Popups | 1.14 | `panels/Popup.qml`, `NetworkPanel.qml`, `panels/network/VpnSection.qml`, `NotificationPanel.qml` | `AnchorsTest`; by hand: both popups unchanged to the eye |
| U3 Network pages and cards | 1.15 | `NetworkVpnSettings.qml`, `NetworkWifiSettings.qml`, `NetworkEthernetSettings.qml`, `NetworkProfileCard.qml` (a `SettingsCard` with the regions `actions` and `settings`), `components/SettingsExpandingRow.qml`, `api/` names `Button`, `Row`, `ExpandingRow`, `network/VpnManager.qml` (`extrasFor`) | `AnchorsTest`, `VpnProvidersTest`; by hand |

### Step 5

| Slice | API | Files | Verified by |
|---|---|---|---|
| P1 `exports` and `uses` | 1.16 | `ModuleRules.qml` (`dependencyPlan`, state), `ModuleHost.qml`, `api/ModuleHandle.qml`, two fixtures | `ModuleRulesTest`, `ModulesTest` |
| P2 Reach warnings, `moduleStatus` | 1.17 | `api/Api.qml`, `api/ModuleHandle.qml`, `ModuleRules.qml` (import check) | `ModuleRulesTest`, `ModulesTest` |

### Step 6: the module, then the closing slice

Each module slice raises its manifest `api` and removes one group of §1:

| Slice | Removes (rows of §1) | Needs |
|---|---|---|
| M1 Runner | 1–4 | A1 |
| M2 Programs and test mode | 9–15 | A2, A3, C2 |
| M3 Privileged | 5–8 | A4, M2 |
| M4 Main and popup | 16–19 | B1 |
| M5 Helpers and facts | 22–33 | C1, C2, D1 |
| M6 Anchors: its row and card; the exit node per network on the network cards | 21, the `slots` field | U3 |
| M7 "Send file…" from the popup | 20 | E1 |
| M8 The manual "for now" override | — (module state) | M6 |

**Z, the closing slice (core, 1.18, floor 1.18):** removes the `PrivilegedAction` type and
`elevate`, the `slots` field, `Api.slots`, `components/ModuleSlot.qml`, `network.vpn.page`,
`Api.module`, `host`; row 34 of §1 goes in the module with its `api: "1.18"`.

### What can run in parallel

- Chains that must stay in order: A0 → A1 → A2 → A3 → A4 → A5; U1 → U2 → U3; P1 → P2.
- Parallel to the A chain: B1, C1, the whole U chain (it lives in `components/` and
  `panels/`).
- C2 after A3 (test kit); D1 after C1 (`NetworkRules` delegates to `AddressRules`); E1
  after A3.
- Everything touches `ModuleRules.qml`, `api/Api.qml`'s header and the CHANGELOG. To keep
  that from colliding, the pure split of `ModuleRules.qml` into five files
  (`architecture-cleanup.md` §2.1) goes first, and each slice adds its version line last,
  at merge.
- Module slices M1–M8 touch only the module's repository and run beside the core slices
  that do not block them.

---

## 8. Open questions for the owner

| # | Question | Choices | Recommendation |
|---|---|---|---|
| Q1 | Where the per-network exit node sits | (a) the saved network's card, opened; (b) the connection editor ("Edit connection") | **(a).** The card's own choices apply at once, as the module's will. The editor has Save, "Save and reconnect" and a 20 s undo; a module's row there needs a contract for joining a form (`changed`, `apply()`, `reset()`), and the editor's save has an open defect (tracker step 7). (b) can follow as a second anchor once that contract exists |
| Q2 | A module's privileged run when another polkit agent answers, so the shell's prompt cannot say who asks | (a) run, and show a shell notification "Module X asks for the administrator's password: …" just before; (b) run, say nothing; (c) refuse | **(a).** The decision is kept as far as the shell can; nothing breaks for people who keep their own agent |
| Q3 | Where the prompt's "what for" comes from | (a) the text given with each run, cleaned and capped (§3.4); (b) a fixed list of purposes in the manifest, a run names one | **(a).** The module has dozens of commands, each with its own words today; the command line is shown beside it either way. (b) can be added if modules from others arrive |
| Q4 | Is the file chooser part of this round? Step 3's list does not name it; without it workaround 20 stays | in (slice E1) / later | **In, as the last slice**, after its spike. If the spike fails, the small shell window |
| Q5 | The other `qs.components` types a module uses (`PopupWidget`, `SmallButton`, `Dropdown`, …: 13) are allowed but not versioned | wrap them in `qs.api` and pin them with a test now / after step 6 / leave | **After step 6**, as its own slice. The five blocks get `qs.api` names in U1, and `Button`, `Row` and `ExpandingRow` in U3 (§4.8), because anchors make them API; the rest is not a workaround and would widen this round |
| Q6 | Order of several modules' elements on one anchor | by module id / search-path order (today) / a manifest `order` number | **By module id**: the same on every machine, nothing to configure |

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
  `GeneralSettings.qml`.
- The survey in §4.1; `NetworkProfileCard`'s controls apply at once; the connection editor
  saves on a button.
- Quickshell's polkit flow exposes `message`, `actionId`, `cookie`, identities and the
  conversation; no command line. `AuthPrompt.qml` sets no `textFormat` on those texts.
- `Process` has `signal(int)`, `stdinEnabled` and `write()`, `environment`,
  `workingDirectory` (Quickshell 0.3.2's types).

**Assumed.**
- A program that cannot start gives no `exited` (seen in the module's working code).
- pkexec's message names the program's path in every locale; a program with its own polkit
  action file would not match and would show without the module lines.
- Signalling pkexec while its prompt shows ends it; a destroyed `Process` may not kill its
  child (the runner signals explicitly).
- NetworkManager may or may not report `tailscale0`'s addresses; the filter covers both.
- A block can find its enclosing block by walking `parent` at completion, also inside a
  `Loader` and a `Repeater` delegate. U1 starts by checking it in `QuickshellPinTest`.
- Whether `FileDialog` opens as its own window in the shell.

**What the current code makes hard.**
- **No shared blocks exist.** Anchors need them first; converting all 26 pages and 9 popups
  at once would be a large visual-risk change, so the plan converts view by view and the
  anchor list starts short.
- **The prompt cannot identify its caller.** The flow has no command line or process id;
  matching rests on the queue's head and pkexec's message (the assumption above). With
  another agent the shell cannot show anything in the prompt (Q2).
- **"Connection's options" has two homes** with different save models (Q1).
- **The VPN slots are filtered per provider** and built through `VpnManager.extrasFor`, not
  `ModuleSlot`; U3 keeps that as the anchor's `scope`.
- **`ModuleRules.qml` is one 1667-line file** that nearly every slice edits; the planned
  split should go first.
- **QML cannot hide anything.** `host`, `module.main` and `exports` are reachable by a
  module that tries; the plan closes them by name, status errors and review.
- **The core breaks its own rule:** `network/VpnLockdown.qml` runs `pkexec sh <script>`
  from the shell's tree (tracker, "Found while writing the development rules"). It is not
  a module run and stays outside this plan, but the prompt will show it without module
  lines, as a plain pkexec request.
