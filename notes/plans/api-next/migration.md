# Module API, the next versions: the Tailscale module's migration and the closing slice

One area of the plan. Read [the index](../api-next.md) first: the rules for every
slice (§2), the gate every slice passes (§7), the slice list with sizes and
dependencies, the lanes. `TC`, `TR`, "verified" and "assumed" are defined there.

What the module works around today (the list every other file answers), the module's
slices that remove it, and the one core slice that then removes the old ways.

Slices in this file: M1–M11, Z.

Section numbers are the plan's and stay as they were. Where each is:
§1 `migration.md` · §2, §8, §10 the index · §3.1–3.4 `commands.md` · §3.5–3.10 `facts.md` ·
§4.1–4.7 `places.md` · §4.8, §4.10 `cards.md` · §4.9 `elements.md` · §5 `module-api.md` ·
§6, §11 `versioning.md` · §7: the list, the lanes and "Later" in the index, a slice's row
in its file, Z in `migration.md` · §9: at the end of each file.

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
| 6 | Two `PrivilegedAction`s, `_admin` and `_adminSpare` (`TC` `_freeAdmin`) | — | A cancelled run answers at once; the queue is the shell's (§3.4) |
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
module's text with none either, against the plain-text rule (§4.9); `ModuleHandle.host`
and `Api.module(id)` hand a module the host and other modules (§5.4).

Module-internal, not API: the operation lock and "plain first, then elevated" (the module
builds its own runner object on the command runner); the JSON readers copied in five Rules
files; `jsonFeed` (needed: `watch-ipn-bus` prints indented JSON); Taildrop preferences
moving from the store to `mod.tailscale.*` settings; the manual "for now" exit-node
override (module state that wins over the per-network choice).

---

## 7. Slices

The rows of this file's slices; the order, sizes and dependencies are in the index.

### Step 6: the module, then the closing slice

Each module slice raises its manifest `api` and removes one group of §1:

| Slice | Removes (rows of §1) | Needs |
|---|---|---|
| M1 Runner | 1–4 | A1 |
| M2 Programs and test mode | 9–15 | A2, A3, C2 |
| M3 Privileged, with a `what` for every run | 5–8 | A4, M2 |
| M4 Main and popup | 16–19 | B1 |
| M5 Helpers and facts | 22–33 | C1, C2, D1 |
| M6 Its row and card move from `slots` to `anchors` | the `slots` field | U2, U4c |
| M7 The exit node per network on the network cards, with the mark | 21 | F3, U5, U7b, M6 |
| M8 "Send file…" from the popup; both Taildrop dialogs through the chooser | 20 | E1 |
| M9 The manual "for now" override | — (module state) | M7 |
| M10 Off the shell's internals: every `import qs.components` goes (17 files, 13 types), onto the public elements with the renames of §4.9; what no public element fits stays the module's own element, on `Api.theme`'s tokens | — (the import) | T0, T1, F1–F4 |
| M11 The last: row 34 of §1, its suite expects no `deprecations`, `api` at the last additive version | 34 | all above |

M10 is one change per group of files (the popup, the page's sections, the widget), each
with the module's UI suites green; the list of `deprecations` in the module's status
counts down to none.

**Z, the closing slice (core; 1.27; the floor becomes 1.26, P2's version).**
It merges after M11 is released (a one-off for the one module of today, §6). M11's module declares 1.26 and uses none of the old
ways, so it runs on the shell before Z and after it; a module still written for less is
`incompatible` after Z, with the reason. (The floor cannot be Z's own version: a module
cannot ask for a version the shell does not have yet, `apiCompatibility`.) Z removes the
`PrivilegedAction` type and `elevate`, the `slots` field, `Api.slots`,
`components/ModuleSlot.qml`, `components/VpnExtras.qml` with `VpnProvider.rowExtras` /
`cardExtras` (the stand-in in `VpnProvidersTest` becomes a fixture module),
`network.vpn.page`, `Api.module`; the test-mode gate for modules below 1.10 (a stand-in
pkexec that lies anywhere in `PrivilegedAction`'s `elevate`: `ModuleRules`, "The test-mode
gate", `testPkexecRule`, `stackDirectories`, `testCallRule`, the elevate probe and
`testGateDeprecations`; `ModuleHost.testCallRule`; `PrivilegedAction._checkedElevate`; the
fixture `legacy-elevate` and `tests/fixtures/legacy-tools`) — every module is then under the
strict rule; renames `ModuleHandle.host`; takes `qs.components` off
the allowed imports (an error in the status); makes the six older `qs.api` types wrappers
(§4.9); and rewrites "Modules" in `docs/ARCHITECTURE.md` for what is left. A test then
compares the anchors and the public elements listed in `docs/` with `anchorTable` and
`ApiElementsTest`'s list, so the reference cannot drift.

---

## 9. Verified, assumed, hard

The part of the plan's §9 that is about this file.

**Verified in the code.**
- Every module reference in §1 (the module's QML is unchanged since the earlier read; only
  its `CLAUDE.md` differs).
