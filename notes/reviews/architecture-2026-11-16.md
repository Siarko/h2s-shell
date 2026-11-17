# Architecture review — 2026-11-16/17 (e367e98..953493e, Tailscale module 9395203)

This review covers the shell after the network settings (`e367e98`) up to `953493e`:
- the lock screen;
- the modules system and module API 1.3;
- VPN providers;
- the changes that touch everything: the test runner, Nix, docs and versioning.

It also covers the Tailscale module (`h2s-shell-tailscale` at `9395203`, version 0.6.0, API
1.3).

How it was done: by reading the code from the host. The first pass ran four read-only reviews
in parallel against `270bee5`. On 2026-11-17 every item was checked again against `953493e`,
and the module got two more passes, one on architecture and one on security. Findings checked
by hand are marked *checked*. Nothing here was run unless it says so.

What was run: every unit suite passes on the host at `953493e` (36 suites, through
`quickshell -p tests.qml`). The module loads in the running shell with no errors or warnings.

**How to work this list:** each item says what to do. Items that need the owner's decision
(section 2) say so, and must not be done until decided. Section 8 covers the module; section
9 lists what the shell's API lacks that the module works around, so read it before
finishing the module work.

**Overall:** the new code follows the project's conventions well:
- pure rules in `*Rules.qml` singletons, each with a suite;
- state and I/O in singletons, views that only render;
- settings through `Profiles.value` and the schema;
- Theme tokens, and `ScriptModel` for every Repeater;
- full names, and comments that say why.

The module follows the contract as well. It imports only `qs.api` and `qs.components`, uses
no literal colours or sizes, and uses PointerArea and DeleteButton. It keeps pure rules apart
from I/O clients, and its tests cannot reach the real Tailscale.

The problems are:
- size;
- singletons and clients that became integration hubs;
- test hooks in production code;
- an API surface that is wider than what is versioned;
- docs that drifted.

## 1. Fix first

1.1 **The unit runner can pass with a suite missing** *(checked)*.
- `tests/run-unit.sh:27` counts suites with `…Test \{\}`. It therefore misses
  `ModuleRegistriesTest { after: _modules; vpnSuite: … }` (`tests.qml:48`), so it expects 35
  suites while 36 are registered (with `BarTextTest` added).
- `tests/headless.sh:100` fails only when *fewer* suites report than expected. If
  ModuleRegistries dies, 35 report and the runner still says PASS. Catching exactly that is
  why `run-unit-selftest.sh` exists, and it copies the same regex (`:18`).
- What to do: count `Test \{` with or without arguments, in both files, and add a selftest
  case for a suite that takes arguments.

1.2 **The documented test command does not work on a host without Nix** *(checked)*.
- `run-unit.sh` calls `tests/headless.sh`, which calls `tests/lock/resolve.sh:10`, which
  stops when there is no `nix`. The owner's Arch host has none.
- `quickshell -p tests.qml` still runs every suite there.
- What to do (the owner decides which):
  - let `run-unit.sh` fall back to running `tests.qml` directly, with the two window suites
    skipped or run on the real display, and say so in the output; or
  - keep Nix required and say so in CLAUDE.md ("Running", "Environment").
- Until then, CLAUDE.md (`:38, 42, 102`) is wrong for the host.

1.3 **The VPN card and the popup row disagree on Connect.**
- For an entry that has `attention` and no action:
  - the row hides Connect (`panels/network/VpnSection.qml:129-137`);
  - the card shows it (`panels/settings/NetworkVpnSettings.qml:251`, `canUse: _attention ===
    null || _attention.action === ""`).
- `VpnManager.connect` (`:628`) and `_callProvider` (`:382`) never check. Only the views
  guard the contract "the core never connects an entry that has one"
  (`components/VpnProvider.qml`).
- What to do: put the rule in the singleton (`VpnManager.canConnect(vpn)`, or a helper for
  the primary action), use it in both views, and test it in `VpnProvidersTest`.

1.4 **"A VPN with a network" conflicts with the kill switch for provider VPNs.**
- By decision, the blocking lets no provider VPN through (`notes/plans/tailscale.md` §8).
  `singletons/network/VpnLockdown.qml:99-103` feeds the script only NetworkManager's
  interfaces and servers.
- But `vpnWithNetworkPlan` (`NetworkRules.qml:727`) still brings a provider VPN up on a
  network that has blocking on. The VPN stays pending for 90 s, then is held down, and only
  a line on the row says so.
- What to do:
  - Show the conflict where the choice is made: the network editor's "Connect a VPN with it"
    picker (`NetworkConnectionEditor.qml:823`), when the same network also has "Block traffic
    outside a VPN here" (`:864`). Show it on the VPN page too when "always" is on.
  - The script's patterns let some provider tunnels through, contrary to the note:
    `wg* tun* tap* ppp* vpn*`, and `tailscale*` as a virtual interface
    (`scripts/h2s-vpn-lockdown:157,161`).
  - `tailscale0` is not local: it reaches the internet through an exit node or a subnet
    router. With "allow LAN" on and an exit node on the LAN, traffic can leave outside the
    VPN.
  - So drop `tailscale*` from the virtual list. This bumps the script's VERSION, and the
    shell offers to reinstall the script. Then make the note match what the script actually
    passes.

## 2. Owner's decisions (do not act before they are made)

2.1 **Next version.**
- `ProfileRules.migrateDefaults` and `formerDefault` reset
  `lockscreen.lockNotificationDetail` from "full" to "app" (`SettingsSchema.qml:181`).
- Unreleased does describe this migration (`CHANGELOG.md:382-386`). But under the project's
  rule a config migration makes the next release **3.0.0**, and nothing says so yet.
- What to do: decide, then write the release as a major.

2.2 **`lockscreen.lockOnSleep` defaults to true** (`SettingsSchema.qml:172`).
- Every user starts locking before sleep when they upgrade. The owner's host has it pinned
  off.
- The CHANGELOG lists it under Added (`:86`), not under Changed.
- What to do: decide the default, and whatever stays, record it under Changed. Remove the
  repeated default `?? true` at `singletons/Lockscreen.qml:107`, since the schema holds it.

2.3 **The NixOS module changes the system's polkit PAM stack by default.**
- `programs.h2s-shell.polkit.passwordFirst` defaults to `config.services.fprintd.enable`
  (`nix/module.nix:32-35, 73-74`).
- So turning the shell on reorders `/etc/pam.d/polkit-1` for every polkit agent.
- What to do: consider an explicit opt-in (default false). Either way, document the option in
  the README's NixOS section; it is not mentioned there.

2.4 **API minor versions tighten behaviour.**
- 1.2 made `openUrl` refuse `file:` URLs without the flag.
- What to do: decide whether a minor version may tighten, and write the rule down in
  `notes/plans/modules.md`.

2.5 **The supervisor retries forever while locked** (`scripts/launch.sh:613-622`, every 60
s).
- A shell that crashes every time while locked restarts every minute, for good.
- This is intended. What to do: confirm it, and say it in the lock screen docs.

## 3. Modules (the shell side, to finish modules by)

3.1 **Not all that modules may use is versioned.**
- Modules may import `qs.api` *and* `qs.components`, but only `qs.api` and the slot table are
  versioned.
- `components/` has 47 files. The Tailscale module uses 13 of them (VpnProvider,
  PopupWidget, BarRow, BarText, SmallButton, InputField, Dropdown, Pill, ToggleSwitch,
  Checkbox, DeleteButton, PointerArea, PrivilegedMark). Of these, only VpnProvider is
  specified.
- Since 1.3, `api/Api.qml:7, 85-90` also reads `qs.singletons.network`:
  - `NetworkProfiles.listRead`, `.profiles` and `.wifi`;
  - `VpnManager.activeVpns`;
  - the Nmcli field names.

  Renaming any of these is now an API break, and nothing marks them as such.
- What to do:
  - List the components that are API, and keep them stable with a test that pins their
    properties. Alternatively, wrap them in `api/` as `SettingEditor` and `Heading` are, and
    refuse the rest in the import allowlist (`ModuleRules.qml:145`).
  - Either way, add the building blocks the plan promises (button, field, dropdown, pills).
  - Put a comment at `Nmcli.profiles` and `VpnManager.activeVpns`: "read by
    `ModuleRules.apiNetworks`/`apiVpnsUp` (module API 1.3)".

3.2 **The handle hands out the host.**
- `ModuleHandle.host` is a public `property var` (`api/ModuleHandle.qml:27`). Through it any
  module reaches `setEnabled`, `unload`, `setFact` and `reportError` for any id
  (`singletons/ModuleHost.qml:163, 244, 268`).
- `Api.module(id)` (`api/Api.qml:68`) gives out other modules' handles, and with them their
  store and `setValue`.
- This undoes the per-module namespacing that the handle enforces (`ownSettingKey`, and since
  1.3 `setPresetValue`).
- What to do: make the host private to the handle. Drop `Api.module`, or make it read-only
  (status and manifest, nothing writable).

3.3 **Say plainly what a module can reach.**
- The trust model ("QML has no sandbox", "modules are trusted, in-process") leaves out that
  the shell's process also runs the lock screen's PAM prompt and the polkit agent.
- So a module can read typed passwords and answer the agent. It can also run anything
  through `Quickshell.Io` (allowlisted).
- What to do: write this in ARCHITECTURE's Modules section (`:491+`) and in the plan, before
  any install-from-a-repository feature (M4).

3.4 **`qs.api` imports `qs.panels.settings`.**
- Where: `api/SettingEditor.qml`, `Heading`, `SwitchRow`, `DetailRow`, `Hint`,
  `SectionTitle`.
- So moving or renaming those settings widgets is now an API break.
- What to do: write that down where the widgets live (a comment at the top of each) and in
  ARCHITECTURE.

3.5 **`ModuleRules.qml` is 1667 lines.**
- It holds a hand-written QML tokenizer (`_rootText`, `:994-1084`), shell script text
  (`startGuardScript`, `:912`) and the 1.3 mappings (`:1443-1500`).
- What to do: split it by topic (manifest, files, merging, the API's views). Give the
  tokenizer its own test cases for comments, strings, regex literals and template strings.

3.6 **URL loading with `Modules.initialProperties` is written three times.**
- Where: `Bar.qml:153`, `panels/Popup.qml:556`, `panels/WidgetSettingsPane.qml:228`.
  `components/ModuleContribution.qml:96` calls it directly as well.
- What to do: replace them with one helper.

3.7 **`ModuleHost.qml` (934 lines) hand-rolls four `Process` blocks** (`:535, 840, 872,
902`).
- What to do: use `CommandQuery` / `CommandAction` where they fit (see 9.1 for what they lack).

3.8 **The plan contradicts itself:** `notes/plans/modules.md:442` (discovery order) against
`:470` ("the Nix one wins"). Settle it.

3.9 **Nothing ties the CHANGELOG's `### Module API` entry to the API version.**
- `ModuleRulesTest.qml:23` hard-codes "1.3".
- The CHANGELOG entry is maintained by hand. It is correct today.
- What to do: add a test that reads the newest `- 1.x:` entry and compares it with
  `ModuleRules.apiVersion`.

3.10 **`Api.networks` can briefly list a hotspot.**
- `listRead` turns true before the Wi-Fi details (`mode`) are read
  (`ModuleRules.qml:1261-1280`, `NetworkProfiles.qml:58-75`). In that window a hotspot counts
  as a joined network.
- The docs promise "no hotspots" (`Api.qml:65-70`, `notes/plans/modules.md:232`).
- What to do: hold back Wi-Fi rows until their details are read, or document the window. Add
  a `ready` flag too (see 9.12).

3.11 **`setPresetValue` (`api/ModuleHandle.qml:121-145`):**
- It repeats the key rule of `ModuleRules.presetDefaultsProblem` (`ModuleRules.qml:422`): the
  same regex and the same `__proto__` check. Move it into one named rule
  (`ModuleRules.isPresetKey`) and use that in both places.
- It reports success for values that are not JSON. `JSON.stringify` silently drops a nested
  function or `undefined`, so the write "succeeds" and the value disappears. Refuse non-JSON
  types explicitly, or compare the value with its JSON round trip.

3.12 **Smaller items:**
- `TestCase.timeLimitMs` is honoured only by `tests-modules.qml`. `tests.qml:59-63` keeps
  one shared 60 s deadline. Honour it in both, or leave it as documented.
- The `__proto__`/`constructor` fix in WidgetPresets is hidden inside the 1.3 API entry.
  Give it its own line under Fixed.
- `CHANGELOG.md:20` runs to about 150 characters on one line, and so does one line at
  `docs/ARCHITECTURE.md:672-677`. Wrap both like the rest.

## 4. VPN providers

4.1 **`VpnManager` became an integration hub** (643 lines).
- It holds the provider reads and slot routing (`:209-363`: `extrasFor` 292,
  `settingsPageOf` 307, `pageOf` 315, `openSettingsPageOf` 325, `contextFor` 338).
- It depends on Modules, Shell and Notifier.
- It has a loader for `tests/FakeVpnProvider.qml` (`:514-535`).
- `lastProviderNotice` (`:360`) is read only by tests.
- What to do: move the provider/module seam and the settings routing into a `VpnProviders`
  singleton. `VpnManager` keeps the merged list, connect and disconnect.

4.2 **The row and card rules are written twice.** Attention, the notice and the button label
are worked out in both `VpnSection` and the `NetworkVpnSettings` delegate. That is how 1.3
happened. What to do: derive them in the singleton (see 1.3).

4.3 **Two id checks.** `connect` / `disconnect` route on `uuid.indexOf(":")`
(`VpnManager.qml:629, 637`), the rest on `vpnIdParts` (`NetworkRules.qml:924`). What to do:
use `vpnIdParts` everywhere.

4.4 **Provider ids in "VPN with a network" are never pruned**, and neither is their
`broughtUp` memory. This is intended ("nothing is deleted on a provider's word"). What to do:
say in FEATURES and in `tailscale.md` that such an id stays until it is removed in the editor.

4.5 **Dead code:**
- `VpnProvider.kind` ("informative only", `components/VpnProvider.qml:121`);
- the provider's `ready` (`VpnManager.qml:228`), which no view reads.

What to do: remove them, or use them.

4.6 **`NetworkProfileCard`'s `external` mode** has 10 properties, which makes the card a
two-mode component with I/O inside: it calls `NetworkProfiles.activate`/`deactivate`/
`disconnectDevice` itself (`:165-172`). What to do: keep the card a view, with the actions
going through the singleton.

4.7 **`NetworkRules.qml` is 1246 lines.** What to do: move the provider entry checker, the
id rules, `sameVpnContext` and the glyphs into `VpnProviderRules`.

## 5. Lock screen

5.1 **`Lockscreen.qml` is 1132 lines, and `_build()` alone is about 615 (`181-797`).**
- The marker and restore recovery (about `202-640`: `restoring`, `restoreDelay`,
  `markerState`, `lockKey`) is a state machine of its own, with no unit tests.
- What to do: move it to `singletons/lock/LockRecovery.qml`, with its decisions in
  `LockIoRules` and test cases for them.

5.2 **Carrying the lock over a reload depends on the order children are declared.**
`PersistentProperties` are matched by position (`_carried` at 809, the notes at 1075 and
1098). What to do: make it independent of order, or add a unit test that fails when the
order changes.

5.3 **Duplicates:**
- The PAM helper sweep is in `Lockscreen.qml:1109-1131` and again in
  `launch.sh:419` (`clean_up_after`). Make it one script that both call.
- `_markerProbe` (875) and `_fallbackProbe` (941) re-implement `CommandQuery`.
- The multi-line shell inside QML strings belongs in `scripts/*.sh`, as with
  `lock-auth-methods.sh`.

5.4 **Test hooks in production code:**
- `H2S_LOCK_TOOLS` swaps `gdbus`, so it could fake logind's Unlock;
- `H2S_LOCK_SYSTEM_PAM_DIR` and `H2S_LOCK_TEST_TIMINGS` (`Lockscreen.qml:122-150`);
- the `locktest` reload IPC (`:1063`);
- `shell.qml`'s `settings itemRect` / `currentPage` IPC (`:128-178`).

What to do: gather them in one place, log loudly at start when any is set, and ignore
`H2S_LOCK_TOOLS` unless the test bed's own marker is present. The module has the same kind of
hook (8.9).

5.5 **PAM** (`singletons/LockIoRules.qml:88-90`):
- **User-writable fallback.** Without an `/etc/pam.d/h2s-shell-*` override, the fallback
  loads `pam/*` from the shell's folder, which the user can write. Any of the user's
  processes can turn it into `pam_permit`.

  What to do: recommend the system-wide config in the README and on the Lockscreen page, not
  only in comments, and show on the page which config is in use.
- **NixOS waits.** On NixOS the password fallback is the whole `login` stack. That stack may
  wait for fprintd, U2F or faillock, against the plan's "the password never waits".

  What to do: use the module's `h2s-shell-password` stack there, or say why not.
- **`auth` only.** Quickshell runs only PAM's `auth` step, so an expired or locked account
  still unlocks.

  What to do: say so in the user-facing docs (the README does not).

5.6 **`LockRules.qml` is 1648 lines** (its suite is 2515). What to do: split it by region
(phase, sleep, PAM, prompt).

5.7 **Conventions:**
- `tx` (439 uses in `LockRules.qml`) should be `transaction`.
- The literal `Math.min(360, …)` at `screensaver/LockSurface.qml:195` should be a
  `Theme.lock` token.

## 6. Docs and tracking

6.1 **Two trackers.**
- `docs/TODO.md` and `docs/CLEANUP.md` were not touched across the whole range. TODO's status
  still reads 2026-11-12, "next: 11.34".
- Meanwhile `notes/plans/next-steps.md` keeps its own order and backlog, and has since gained
  "3. Texts and languages" and backlog items.
- What to do: keep one tracker. Either fold next-steps into TODO.md (CLAUDE.md says to start
  there), or make CLAUDE.md point at next-steps. The owner decides; until then keep both in
  step.

6.2 **`README.md:182` still says `quickshell -p tests.qml`** (see 1.2).

6.3 **The CHANGELOG has its own `### Module API` section** above Added/Changed/Fixed. Keep
it if wanted, but describe the convention in CLAUDE.md's versioning note.

## 7. Notes for whoever picks this up

- **The owner's host:** Arch, Hyprland, no Nix.
  - hypridle locks with hyprlock, so the shell's lock on logind's Lock races it. This is
    known and left as the user's configuration for now; a later idea is to detect a lock
    that is already held.
  - `lockscreen.lockOnSleep` is pinned false there.
- **Tests on the host:** run the unit suites with `quickshell -p tests.qml` until 1.2 is
  settled.
- **The Tailscale module on the host:** it is loaded from `~/Projects/h2s-shell-tailscale/module`.
  Tailscale itself is being installed now and the owner's tests are still running, so
  nothing in section 8 has been seen against a real tailscaled yet.
- **Keep fixes small,** each with its CHANGELOG line where it is user-visible (in the module's
  own CHANGELOG for the module).

## 8. The Tailscale module (h2s-shell-tailscale 0.6.0)

Security: no injection, privilege escalation or secret leak was found.
- Every `sh -c` passes its values as `$1…`.
- No argument can be read as an option: targets cannot start with `-`, and `file cp` uses
  `--`.
- Taildrop names are cleaned, and the receive folder must be a real directory the user owns.
- pkexec is used only for the user's own clicks, always under `timeout`, with tool paths
  checked (owned by root, or in the Nix store).
- The tests always use the stand-ins.

The items below are in order: fix first (8.1-8.5), then should (8.6-8.12), then nice (8.13).

8.1 **Funnel can publish a terminal's share** *(checked)*.
- `ServeRules.parseConfig` only *counts* `Foreground` and `Services` (`ServeRules.qml:124-125`).
  Their ports never reach `entries` or `unlisted`, so `publicProblem` (`:300`) and the "port
  in use" check in `addPlan` cannot see them.
- Scenario: the user runs `tailscale serve --set-path=/docs ~/docs` on 443 in a terminal,
  then turns Funnel on for the module's 443 share. The check passes, `AllowFunnel[host:443]`
  is set, and the terminal's files are probably public.
- What to do: put the ports of every `Foreground[*]` and `Services[*]` TCP/Web entry into
  `unlisted`, or refuse Funnel while `foreground > 0`.

8.2 **There is a gap between planning and the CLI's write for Funnel.**
- `ServeClient._change` plans on its own read (`ServeClient.qml:117-129`). The CLI then does
  its own read-modify-write.
- On the pkexec path, the gap lasts for the whole password dialog. A handler added on that
  port in the meantime becomes public.
- What to do: after a Funnel-on succeeds, re-read and re-run `publicProblem` for that port.
  If it fails now, revert at once and notify. Better: write the serve config through the
  LocalAPI with `If-Match` set to the ETag of the read the plan was made on.

8.3 **The exit node per network is never retried** *(checked)*.
- `NetworkExitClient.follow` stores `lastKey` before the outcome is known
  (`NetworkExitClient.qml:90-97`). It also stores it for `unavailable`, `needs-operator`,
  `refused` and `conflict`, and a failure sends no notification.
- Scenario: "Café Wi-Fi → exit node X", and X is offline at join. Traffic goes direct, and
  nothing happens when X comes back.
- What to do:
  - Store `lastKey` only when the choice is applied, or for `already` / `none-marked`.
  - Retry `unavailable` when X appears.
  - Notify on failure, since this is a privacy choice.

8.4 **Every bus message re-reads `status --json` and `debug prefs`** *(checked)*.
- `_scheduleRead()` is at the end of the bus handler (`TailscaleClient.qml:669`), whatever
  the message was. Taildrop's progress messages (a send can last up to 6 h), health and
  suggestions each start two processes.
- `notifyDigest` already works out the message's kinds (`TailscaleRules.qml:1768-1843`), but
  only the tests use them.
- The watch poll (`:1822`, every 3 s while the page is shown) reads everything as well.
- What to do: re-read only for `state`, `login-finished` and `changed`. Skip the prefs read
  when the message carried `Prefs`. Make the poll read status only.

8.5 **A 5 s clock recomputes the whole state** *(checked)*.
- `_clock` (`TailscaleClient.qml:1830`) writes `now`, and everything is derived from it:
  first `facts`, then `stateOf`, then `entry`, `devices` (up to 5000 peers) and `keyState`.
- So `provider.entries` (`Main.qml:29`) is a new array every 5 s. The shell's VpnManager
  re-checks the provider, and every VPN view re-binds.
- What to do:
  - Give the offline exit node's grace period a one-shot timer.
  - Work out key expiry by the minute.
  - Give the "last seen" labels their own `now`, only while the page is shown.

8.6 **The sub-clients reach into `TailscaleClient`'s private members.**
- Who: `ServeClient.qml:44-128`, `TaildropClient.qml:201-551`, `CertClient.qml:38-61`,
  `LockClient.qml:51-53`, `NetworkExitClient.qml:90`.
- What they use: `_spawn`, `_generation`, `_alive`, `_timedArgv`, `_runChange` (six
  positional arguments, three of them callbacks), `_runLocked`, `_finish` and `_origin`.
  ServeClient even assigns `client._opProcess`.
- What to do: extract a `TailscaleRunner` with a public interface that takes an options
  object. It covers spawning with a watchdog, the timed argv, the operation lock with its
  token, and a plain run with a retry through pkexec. Pass it to the sub-clients.

8.7 **Split the large files.**
- **`TailscaleClient.qml` (1836 lines).** Split it into the runner (8.6), a tools probe,
  accounts, sharing (routes, forwarding, switches), diagnostics with ping, and the login flow
  (`:1469-1638`), following the clients that are already separate.
- **`TailscaleRules.qml` (2635 lines, pure, well tested, so low risk).** Split it into
  `AddressRules` (`:2500-2635`), `BusRules` (`:1662-1845`), `CommandRules` (`:1934-2400`),
  `DiagnosticsRules` and `SharingRules`.
- **Shared helpers.** `_isObject` is defined in five Rules files, and `_get`, `_string` and
  `_number` in two each. Move them into one helper.
- **`TailscalePage.qml` (829 lines).** Make Accounts, Devices, Diagnostics and Administration
  sections, as the others already are.

8.8 **The elevated login bypasses `PrivilegedAction`.**
- `TailscaleClient.qml` spawns `[pkexecPath, …]` itself. The reason is that the login URL
  has to be read while the command runs, and `PrivilegedAction` cannot stream output (9.2).
- So this path loses the shell's `notFound` check, `Authentication.reportDenied` (code 127,
  said once) and the queue.
- What to do: after 9.2, move the login onto `PrivilegedAction`. Until then, report 127 the
  same way the other actions do. Also say, at `_admin` / `_adminSpare` (`:1682-1688`), that
  keeping two of them is a workaround.

8.9 **Test seams in production code.**
- `H2S_TAILSCALE_TOOLS` makes IPC calls count as the user, and it skips the trust check. So
  pkexec would run `$seam/tailscale`.
- This is the same kind of hook as 5.4. What to do: honour it only together with the test
  bed's own marker, and log loudly when it is set.

8.10 **Dead and mismatched code.**
- `notifyMask` (`TailscaleRules.qml:90`) is unused, and `watchMask` (`:97`) is built from
  literal numbers. Build `watchMask` from `notifyMask`.
- `_prototypeKeys` (`:132`) is unused.
- `commandNames` (`:2154`) is used only by tests.
- `commandFor("lockStatus")` (`:2340`) has no `--json`, and `LockClient.qml:53` writes its
  own argv instead. Fix the table entry and use it.
- `fileGet` (`:2323-2331`) is unused, and it is marked `privileged` and `writesAsRoot`.
  `privileged()` never checks `writesAsRoot`, so a later caller could run `file get` as
  root. Delete it, or make `privileged()` refuse anything that writes as root.
- The checks for older shells are dead under api "1.3":
  - `Main.qml:318` (`"settingsPage" in provider`);
  - `TailscaleWidget.qml:25` and `TailscalePopup.qml:33` (`typeof module?.presetValue`);
  - `"timeLimitMs" in suite` in the live suites;
  - `TailscalePage.qml:23-24` (`context.provider.client`).

8.11 **Smaller correctness items.**
- **Serve view.** `ServeClient.read()` drops a read asked for while one is in flight
  (`:128-132`), and nothing polls. The page can show "not public" while a port is public.
  Queue a read-again flag, as the main client does with `_readAgain`.
- **Routes.** `routesWith` / `routesWithout` (`TailscaleRules.qml` around 1260-1275) silently
  drop advertised routes that `parseCidr` cannot read, and the next edit sends the list
  without them. Refuse the edit instead, as `advertiseRoutesCut` already does.
- **Taildrop overwrite.** Auto-save together with "Replace" lets any device that may send to
  this user replace files in the save folder, which may be `$HOME`. There is no size or
  disk-space limit either. Do not allow "Replace" with auto-save, or refuse `$HOME`.
- **Tailnet lock status.** The CHANGELOG says it is "not read while stopped or logged out",
  but `resumed()` (`:1659`) and showing the page call `LockClient.read()`, which checks only
  `client.running`.
- **IPC calls without a check.** `sendFile`, `saveReceived` and `setNetworkExit`
  (`Main.qml:226-246, 296`) skip `_ipcMayChange()`. That is acceptable (they are
  operator-only and run with the user's rights), but say so in the IPC comment.
- **Unchecked tools.** `systemctl` and `xdg-open` are run by name and not checked as trusted
  (`TailscaleClient.qml:1384, 1445`). Check them, or say why not.
- **Touch targets.** `CopyChips.qml:48` uses `centred: false` on small chips that do not
  touch each other, so they lose the minimum touch target. Use the centred area with a
  `reach` instead.
- **Stale comment.** `TaildropLiveTest.qml:8` mentions pkexec for Taildrop, which never uses
  it.

8.12 **Preferences, tests and docs.**
- **Taildrop preferences.** The folder, the conflict choice and auto-save live in
  `module.store` (`TaildropClient.qml:45-89`). By convention preferences are `mod.<id>.*`
  settings declared in the manifest. Declare them, or write down why they are store data.
  (`lastTailnet` and `exitByNetwork` are data, rightly.)
- **Test runner.**
  - The shell now has `tests/run-modules.sh`. So the fallback in `tests/run.sh` and
    `tests/harness.qml` are dead, as the script's own header says.
  - The default `H2S_SHELL_DIR=../h2s-shell-wt` is one developer's layout.
  - The three live suites repeat the same scenario machinery. Extract it into a
    `ScenarioSuite.qml`.
- **The stand-in `tailscale`** is 1657 lines of sh/awk/sed.
  - It reads the JSON fixtures by line patterns (`:439, 442, 746-755`), so re-indenting a
    fixture breaks it.
  - It re-implements serve semantics in about 450 lines.
  - Nothing checks it against a real CLI.

  What to do: narrow it to what the live tests assert, split it or port it to a language that
  reads JSON, and add a check of a recorded transcript against the version named in the
  README (1.104.4).
- **README and CHANGELOG.**
  - README:336 has a personal path (`/home/h2s/src/...`). Use a placeholder.
  - "Installing" describes only the future M4 flow. Add today's way
    (`H2S_SHELL_MODULE_PATH`, or the modules folder).
  - The CHANGELOG lists 0.2.0 to 0.6.0, all unreleased, and there are no tags. Collapse them
    under Unreleased, or tag them.
  - The 0.6.0 notes include test runner internals, which are not user-visible.

8.13 **Nice to have.**
- **`jsonFeed`.** It is a streaming parser for pretty-printed JSON (`TailscaleRules.qml:1669-1767`),
  sitting behind a `SplitParser("\n")`. If the stream is one object per line, `JSON.parse`
  per line is enough.
- **`Format` copies.** `Format.bytes` and `Format.ago` are copied (`:2466-2498`). See 9.5.

## 9. Shell API gaps the module works around (inputs for the module work)

Each of these is a workaround in the module today. Add each one to the API with an API minor
version and a CHANGELOG `### Module API` line, then remove the module's workaround.

1. **`CommandAction` / `CommandQuery` have no timeout, streamed output, cancel or separate
   stderr.** So the module has its own Process factory with a watchdog, `abandon()` and
   `onChunk` (`TailscaleClient.qml:1691-1773`), and wraps every command in `timeout`.
   Wanted: `run(cmd, done, { env, timeoutMs, onOutput })`, returning a handle with
   `cancel()`. The shell's own `ModuleHost` (3.7) and lock screen (5.3) would use it too.
2. **`PrivilegedAction` has no streamed output and no cancel.** See 8.8.
3. **A popup panel is not told which widget or preset opened it.** The module works around
   this with a singleton property (`Tailscale.popupPreset`). Wanted: pass `preset` to the
   panel.
4. **A module's pages, popup and widget cannot reach the object its main owns.** The module
   works around this with a module singleton holding `client` (`Tailscale.qml:13`). Wanted:
   `module.main`, or a module-scoped shared object on the handle.
5. **There are no formatting helpers in the API.** `Format.bytes` and `Format.ago` are
   copied, and the IPv4/CIDR helpers partly duplicate `NetworkRules`.
6. **There are no system facts:** user name and uid, host name, LAN subnets. The module
   runs `id`, reads `/proc` and runs `ip -o addr`, while the shell already knows the
   addresses from NetworkManager.
7. **There is no way to start a terminal, and no terminal setting.** SSH offers "Copy ssh
   command" instead.
8. **A popup cannot open a file chooser.** "Send file…" goes through the page.
9. **`availableHeight` given to popup panels (`panels/Popup.qml:581`) is not documented in
   the API**, and the module relies on it.
10. **`qs.components` is not versioned.** See 3.1.
11. **There is no per-network settings slot.** The exit node per network keeps its own table
    in the store, keyed by `Api.networks` ids, next to the shell's `system.vpnWithNetworks`.
12. **There is no signal or `ready` flag for `Api.networks`.** An empty array is ambiguous,
    so the module diffs the list itself (`NetworkExitClient.qml:58`). See 3.10.
13. **`Api.vpnsUp` cannot tell a full-tunnel VPN from a split one.** Wanted: `never-default`
    and the allowed IPs.

Suggested order: start with sections 1 and 3 (the shell side), then 9.1-9.4 (the API gaps that
shape the module), then 8.1-8.5, then the refactors in 8.6-8.7.
