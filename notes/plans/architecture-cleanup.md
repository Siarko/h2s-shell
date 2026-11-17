# Architecture clean-up: the shell and the Tailscale module

Written 2026-11-17 against `master` at `259335d` and the module at `dd5ebdb`. This is a plan
only. Nothing here is decided until the owner approves it, and section 7 lists what the
owner must choose.

Related plans, not repeated here:
- `api-next.md` covers the module API's next pieces: the command runner, the shared module
  object, system facts, formatting helpers, the host's handle. This plan names where it
  depends on them (marked **[api-next]**).
- `documentation.md` covers the docs structure. Pure docs items from the review go there
  (marked **[docs]**).

Sources: `notes/reviews/architecture-2026-11-16.md` (called "the review", items by number), a
fresh read of the code, `CLAUDE.md`, `docs/ARCHITECTURE.md`, `notes/plans/modules.md`.

## 0. Rules for every slice

- One slice is one reviewable change. When it is done, the unit suites pass, and so do the
  lock-bed tests named for that slice.
- A pure move changes no behaviour. It moves code and updates its callers and tests, and
  nothing else. Do not fix anything on the way. Write down what you find and do it in its
  own slice.
- The following must not change unless a slice says so and the owner has agreed:
  - **Module API names (1.3):** `Api.*`, the handle (`module.*`), `ModuleStore`, the slot
    names and context shapes (`ModuleRules.slotTable`), every property of
    `components/VpnProvider.qml`, including the unused `kind` and `ready`, and the
    components the Tailscale module uses (review 3.1).
  - **IPC targets and functions:** `lockscreen` (lock, status, state), `modules` (list,
    setEnabled), `settings` (open, openPage, currentPage, itemRect, toggle, close),
    `shelltest`, `locktest`, `fakevpn`, `profiles`, `authentication`, `wallpaper`, `tablet`.
    The module's targets `tailscale*` too.
  - **Setting keys:** `lockscreen.*`, `system.vpnWithNetworks`, `mod.<id>.*`.
  - **Config keys:** `disabledModules`, `network.vpnMemory`, `network.lockdown`.
  - **Files and formats shared between processes:** the lock marker
    `$XDG_RUNTIME_DIR/h2s-shell-lock` ("locked <key>" / "unlocked") and the start guard
    `$XDG_RUNTIME_DIR/h2s-shell-module-starts`. Also `scripts/h2s-vpn-lockdown`'s
    arguments and `VERSION`.
  - **Environment the launcher sets for the shell:** `H2S_SHELL_MODULES`,
    `H2S_SHELL_SAFE_MODE`, `H2S_SHELL_SUPERVISOR`, `H2S_SHELL_LAUNCHER`.
- The lock screen never depends on anything under `api/`, `Modules`, `ModuleHost` or a
  module (`tests/lock-closure.sh`). If the lock screen needs the new command runner, it uses
  the shell's own copy in `singletons/io/`, never the module API's wrapper.
- After editing a singleton, restart the shell (CLAUDE.md). Test on the host only after a
  restart.
- **Lock-bed slices need Nix.** `tests/lock/run.sh` needs `nix` (`tests/lock/resolve.sh:10`).
  The owner's Arch host has none, so each slice marked "lock bed" runs on the NixOS
  Framework or on a machine with Nix (see decision 7.1).

## 1. State table

Status words: **true** (still as the review says), **partly** (part fixed), **changed**
(the facts moved, so the item reads differently now), **fixed**. Line numbers are current.

Risk words:
- **leave**: what goes wrong if nothing is done.
- **change**: what could break.
- **verify**: which suites prove the change. "New test first" means write that test before
  the change and see it pass on the old code.

### 1a. The shell

| # | Where | What is wrong | Status | Risk: leave | Risk: change | Verify |
|---|---|---|---|---|---|---|
| R3.5 | `singletons/ModuleRules.qml` (1667 lines) | One file for manifest, files, tokenizer (`_rootText` 994-1084), shell scripts (`fileCheckScript` 809, `startGuardScript` 912, `guardClearScript` 927), merging, API views (1452-1500). Tokenizer tests cover comments, quoted text and regex (`ModuleRulesTest.qml:555-566`), not template strings or `"` inside `'`. | true | Hard to review; the tokenizer decides what a module gets (`module` property). | Low: pure. Callers in 19 files (list in §2.1). | ModuleRulesTest, ModulesTest, ModuleRegistriesTest, QuickshellPinTest. New tokenizer cases first. |
| R3.6 | `Bar.qml:148-154`, `panels/Popup.qml:552-557`, `panels/WidgetSettingsPane.qml:224-230`, `panels/settings/VpnProviderPageFrame.qml:89` | Four copies of "load by URL, with the module's handle when it is a module's". The ternary `owner !== "" ? Modules.initialProperties(url) : {}` is redundant: `Modules.initialProperties` already returns `{}` for a file that belongs to no module (`singletons/Modules.qml:91-93`). Two sources say who owns a URL (`WidgetRegistry.moduleOf` and the host's directory lookup). | true (4 copies, not 3) | The next loader gets it wrong. | Low. A core URL must still get `{}`. | ModuleRegistriesTest (widget, popup, pane, VPN page), WidgetRegistryTest; lock bed `modules`. |
| R3.7 | `singletons/ModuleHost.qml:535, 840, 872, 902` | Four hand-made `Process` blocks with their own deadline timers (540, 866, 887, 926). | true | Duplicated deadline logic. | Medium: the deadlines keep the lock screen independent of a hung mount. | ModulesTest; lock bed `modules-hung`, `modules`. Needs **[api-next]** runner with `timeoutMs` and `env`. |
| R3.8 | `notes/plans/modules.md:441-445` vs `:467-471` | "The Nix one wins" contradicts the search order. `programs.h2s-shell.modules` does not exist yet (`nix/module.nix`). | true | M4/M5 built on the wrong order. | none (docs) | — Settled in §5. |
| R3.12 | `tests.qml:63` | One 60 s deadline. `TestCase.timeLimitMs` is honoured only by `tests-modules.qml:79`. | true | A slow suite in `tests.qml` looks like a hang. | Low. | run-unit-selftest. |
| R3.12b | `CHANGELOG.md:20`, `docs/ARCHITECTURE.md:677` and others | Lines of 130-150 characters. The WidgetPresets `__proto__` fix sits inside the 1.3 entry (`CHANGELOG.md:23-25`). | true | — | — | **[docs]** |
| R4.1 | `singletons/network/VpnManager.qml` (709 lines, was 643) | A hub. It holds the provider registry and reads (127-260), slot and page routing (292-345), provider calls and notices (378-428), the connect rule (438-468), "VPN with a network" (470-557), the stand-in loader (567-583), WireGuard and plugins (608-677). It depends on Modules, Shell, Notifier, Profiles, Config. `lastProviderNotice` (378) is read only by `tests/VpnProvidersTest.qml:393, 500`. | true | Every VPN change touches one file; the test hook stays in production. | Medium: the kill switch reads `VpnManager.vpns` and `interfaceNames`; modules see `contextFor` shapes. | VpnProvidersTest, NetworkTest, ModuleRegistriesTest (`vpn-slots`, `vpn-page`). New test: the row/card notice (R4.2). |
| R4.2 | `panels/network/VpnSection.qml:70-71, 159-188`, `panels/settings/NetworkVpnSettings.qml:65-68, 216-253` | Connect, the primary label and "attends instead" are now in the singleton (`VpnManager.qml:438-468`). Still twice: the notice text (row: separate lines; card: joined at 252), when the attention's action shows (row: only while active, 175; card: always, 253), and the state words (card `_stateText` 65; row 67-68). | partly | The two disagree again, as in review 1.3. | Low. | VpnProvidersTest. New test first: one derived `presentation(vpn)` per entry. |
| R4.3 | `VpnManager.qml:680, 698` | Two id checks. | **fixed** (`vpnIdParts` everywhere) | — | — | — |
| R4.4 | provider ids in `system.vpnWithNetworks` | Never pruned, by design. | true | Users are surprised. | — | **[docs]** |
| R4.5 | `components/VpnProvider.qml:121` (`kind`), `:125` (`ready`) | `kind` is unused. `ready` is read once, to re-run the network follow (`VpnManager.qml:479`); no view reads it. | changed | none | **Removing either is an API break** (VpnProvider is API 1.1). | Keep both; document `kind` as informative. |
| R4.6 | `panels/settings/NetworkProfileCard.qml:44-46, 165-172, 185-188` | Two modes in one card (`external`), and the card calls `NetworkProfiles.activate/deactivate/disconnectDevice` itself. | true | I/O in a view. | Low. The Wi-Fi and Ethernet pages use the card too. | SettingsPagesTest, NetworkTest. |
| R4.7 | `singletons/network/NetworkRules.qml` (1295 lines, was 1246) | VPN providers (898-1145), "VPN with a network" (697-897), the kill switch (1146-1295) and the editor (105-470) in one file. | true | Size. | Low: pure. | NetworkTest, VpnProvidersTest. |
| R5.1 | `singletons/Lockscreen.qml` (1132 lines), `_build()` 181-797 | One closure holds the effect executor (333-445), recovery (498-671: `lockKey`, `markerState`, `restoring`, `restoreDelay`) and the driver API (710-784). The recovery decisions have no unit tests; only the lock bed covers them. | true | Recovery is the riskiest code in the shell and is only tested end to end. | **High**: the lock screen. A mistake can leave the session locked with no prompt, or unlock it. | Lock bed: `restart-*`, `reload-*`, `marker-stale`, `supervisor`, `relock`. New unit tests first (§2.6). |
| R5.2 | `Lockscreen.qml:808` (`_carried`), `:1098` (`_helperSweepOnce`), comment `:1074` | Quickshell matches a reloaded singleton's children by position. Adding, removing or reordering children before a `PersistentProperties` breaks the carry-over. | true | Any edit to Lockscreen's children can break the reload-while-locked path, with no unit test to catch it. | — | New unit test (slice L1), before any other Lockscreen slice. |
| R5.3a | `Lockscreen.qml:1109-1131` and `scripts/launch.sh:419` (`clean_up_after`) | Two PAM helper sweeps. **They differ on purpose**: the launcher picks by process group after a death and must not fork per process; the shell picks its own children started before the check, only after an in-place relaunch. | true | Little; they already point at each other. | Medium: kills processes; a wrong pick kills a live PAM helper. | Lock bed `restart-crash-finger`, `restart-kill-locked`, `harness-orphan`. |
| R5.3b | `Lockscreen.qml:874` (`_markerProbe`), `:918` (`_restoreProbe`), `:940` (`_fallbackProbe`) | Three hand-made "run and collect lines" processes; `CommandQuery` (`singletons/io/CommandQuery.qml`) does the same. | true | Duplication. | Medium: child positions (R5.2). | Lock bed `marker-stale`, `restart-no-restore*`, `restart-hyprctl-hang`, `fallback`. |
| R5.3c | multi-line `sh -c` text in QML: `Lockscreen.qml:878-890, 1111-1126`, `ModuleRules.qml:809, 912, 927`, `ModuleHost.qml:793`, `Wallpapers.qml:113, 327, 382`, `VpnLockdown.qml:173`, `lock/LogindMonitor.qml:116`, `lock/SleepInhibitor.qml:85`, `lock/CapsLockLed.qml:71`, `hardware/*` | No shellcheck, hard to read. | true | Readability. | Low for scripts run as the user. | Per file, the suites that run it. |
| N-root | `VpnLockdown.qml:499, 509`, `NetworkOverview.qml:348` | `pkexec sh -c <inline>`. | new (keep) | — | **Moving these into `scripts/` would make a root script that the user can edit.** Inline text is the safer form here. | Write the rule down (§2.6). |
| R5.4 | `Lockscreen.qml:122-150, 1063-1071`; `shell.qml:126-178`; `Bar.qml:374-404`; `Modules.qml:130-142`; `VpnManager.qml:567-583`; `lock/CapsLockLed.qml:29`; `scripts/lock-auth-methods.sh:36, 48`; `scripts/launch.sh:298, 450` | Test hooks spread over nine files, each read and logged its own way. `H2S_LOCK_TOOLS` swaps `gdbus`, which could fake logind's `Unlock` (`LockRules.unlockSources`). `H2S_LOCK_SYSTEM_PAM_DIR` can point the password fallback at any PAM config. | true (more places than the review lists) | A stray variable changes how the lock screen authenticates, and nothing says so loudly. | Medium: the lock bed and `tests/device/` depend on them. | §3. Lock bed all; `tests/device/*` by hand. |
| R5.5 | `singletons/LockIoRules.qml:83-91` | The fallback PAM config is user-writable (`pam/`); on NixOS the fallback is the whole `login` stack; Quickshell runs only `auth`. | true | A user process can turn the fallback into `pam_permit`. | — | Part of the trust write-up (§5); README **[docs]**. |
| R5.6 | `singletons/LockRules.qml` (1648 lines; suite 2515) | One file. | true | Size. | Medium: pure but central. | LockRulesTest, LockViewTest, LockIoRulesTest; lock bed full run. |
| R5.7 | `LockRules.qml` (439 × `tx`), `screensaver/LockSurface.qml:195` (`Math.min(360, …)`) | Naming convention; a literal size. | true | — | Low (mechanical). | LockRulesTest, LockViewTest. |
| R6.1 | `docs/TODO.md:15` ("Status (2026-11-12)") vs `notes/plans/next-steps.md` | Two trackers. | true | Agents resume from a stale file (CLAUDE.md says to start at TODO.md). | — | §4. |
| R6.2 | `README.md:182` | Says `quickshell -p tests.qml`. | true | — | — | **[docs]**, after decision 7.1. |
| R6.3 | `CHANGELOG.md` `### Module API` | Convention not in CLAUDE.md. | true | — | — | **[docs]** |
| N1 | `panels/settings/NetworkConnectionEditor.qml:164-195` (file: 1098 lines) | The view runs a save across three singletons. It saves the profile, then in `onSaved` writes `VpnManager.setVpnsWith` and `VpnLockdown.setFor`. If the page is gone when `saved` arrives, the VPN link and the **kill-switch choice are silently not written**. | new | A kill-switch setting the user chose is lost. | Medium: kill switch. | New test first (NetworkTest): save, destroy the editor, answer `saved` → mapping and lockdown written. |
| N2 | `Lockscreen.qml:103-107` | Every setting has a repeated default (`?? false`, `?? 300`, `?? true`) that the schema already holds. | new (wider than review 2.2) | Two defaults drift. | Low. | ProfilesTest; LockIoRulesTest. Wait for decision 7.3. |
| N3 | module test seam reads the shell runner's `H2S_TEST_MODULES` (`TailscaleClient.qml:310`) | An unwritten contract between the repos. | new | Renaming the variable in the shell silently lets module tests reach the real `tailscale`. | — | §3. |

### 1b. The Tailscale module (`/home/h2s/src/h2s-shell-tailscale-wt`, read-only here)

| # | Where | What is wrong | Status | Risk: leave | Risk: change | Verify |
|---|---|---|---|---|---|---|
| T8.4 | `module/TailscaleClient.qml:802-839` | `notifyDigest` is now used (808). But `_scheduleRead()` still runs at the end of every bus message (839), so each one starts `status --json` and `debug prefs`. The watch poll reads everything too (2092-2097). | true (changed: digest in use) | Two processes per Taildrop progress message, for up to 6 h. | Medium: a missed re-read leaves the entry stale. | New pure rule test first (§2.8). TailscaleStateTest, TailscaleIoTest, TailscaleLiveTest. |
| T8.5 | `TailscaleClient.qml:172, 230, 2100-2105` | A 5 s `_clock` writes `now`, which feeds `facts` (230). So `entries` becomes a new array every 5 s, and the shell's `VpnManager` re-reads the provider and re-binds every VPN view. | true | Constant work on a laptop; "VPN with a network" re-follows every 5 s (`VpnManager.qml:479-481`). | Medium: grace and expiry must still fire on time. | New test first: entries unchanged by value across clock ticks (TailscaleStateTest). |
| T8.6 | `CertClient.qml`, `LockClient.qml:53`, `NetworkExitClient.qml`, `ServeClient.qml`, `TaildropClient.qml`; **also `TailscalePage.qml` → `client._loginElevated`** | Sub-clients use the client's private members: `_spawn`, `_generation`, `_alive`, `_limit`, `_watchdogMs`, `_timedArgv`, `_runChange`, `_runLocked`, `_finish`, `_origin`, `_opToken`, `_readPrefsNow`. ServeClient assigns `client._opProcess`. A view reaches a private member. | true (one more place) | Any change in the client breaks five files. | Medium. | TailscaleIoTest, ServeTest, ServeLiveTest, TaildropTest, TaildropLiveTest, NetworkExitTest. |
| T8.7 | `TailscaleClient.qml` 2106 (was 1836), `TailscaleRules.qml` 2766 (was 2635), `TailscalePage.qml` 844 (was 829); `_isObject` in five Rules files, `_get/_string/_number` in two | Size; copied helpers. | true (grown) | — | Rules: low (pure). Client: medium. Page: low. | Suites per file (§2.8). |
| T8.9 | `TailscaleClient.qml:301-316` | `H2S_TAILSCALE_TOOLS` makes IPC calls count as the user and skips the trust check, so pkexec would run `$seam/tailscale`. | true | A stray variable runs an untrusted `tailscale` as root after the user's password. | Low. | §3. Module lock bed `tests/lock-bed/tests/tailscale.sh`. |
| T8.10 | `TailscaleRules.qml:90` (`notifyMask` unused), `:97` (`watchMask` literals), `:132` (`_prototypeKeys` unused), `:2285` (`commandNames`, tests only), `:2471-2472` (`lockStatus` without `--json`; `LockClient.qml:53` writes its own argv), `:2454-2461` (`fileGet`, unused, `writesAsRoot`; `privileged()` at 2511 does not check it); old-shell checks: `Main.qml:331`, `TailscaleWidget.qml:25`, `TailscaleWidgetSettings.qml:21`, `TailscalePopup.qml:33`, the live suites' `"timeLimitMs" in suite`, `Tailscale.qml:10`/`TailscalePage.qml:23` (`context.provider.client`) | Dead and mismatched code. | true | `fileGet` could later run `file get` as root. | Low. | TailscaleIoTest (it tests `fileGet` at 190, 239, 258: update), live suites. |
| T8.11 | `ServeClient.qml:48-57` (a read during a read is dropped), `TailscaleRules.qml:1385-1397` (unreadable routes dropped), `TailscaleClient.qml:1624, 1661, 1691` (`systemctl`, `xdg-open` not trust-checked), `CopyChips.qml:48` (`centred: false`) | Correctness items, not structure. Taildrop "Replace" with auto-save, tailnet-lock read while stopped, and the IPC comment were not re-checked. The stale comment at `tests/TaildropLiveTest.qml:8` now matches (Taildrop send retries through pkexec). | true (one changed) | As the review says. | Low each. | Per item; own slice M-fix. |
| T8.12 | `TaildropClient.qml:44-64` (preferences in `module.store`); `tests/run.sh:31, 46-55` and `tests/harness.qml` (fallback; default `../h2s-shell-wt`); three live suites with copied scenario code; `tools/stand-in/tailscale` (1675 lines; JSON read by line patterns); README and CHANGELOG | Preferences outside the schema; dead runner path; test scaffolding. | partly (README and CHANGELOG fixed) | Fixture re-indent breaks the stand-in; nothing checks it against a real CLI. | Low (test code), except moving preferences (data migration). | `tools/test.sh`, live suites. |
| T8.13 | `TailscaleRules.qml:1789-1797` (`jsonFeed`); `:2597-2631` (copies of `Format`) | `jsonFeed` is needed: `watch-ipn` prints indented JSON, so one `JSON.parse` per line is not enough. Format copies remain. | changed (jsonFeed: keep) | — | — | Format: **[api-next]** (review 9.5). |
| N4 | `module/LockRules.qml` (tailnet lock) | Same name as the shell's `LockRules` (lock screen). | new | Confusing in logs, grep and reviews. | Low (module-internal; qmldir). | LockSection tests. |

### 1c. Already fixed, verified

- 1.1 (`tests/count-suites.sh`)
- 1.3 (`VpnManager.canConnect` at 443, used by both views)
- 1.4 (commit `e25d7eb`)
- 4.3 (above)
- module 8.1-8.3 (commit `8fc9777`)
- the module's README and CHANGELOG

### 1d. Counts

Of the 37 review items in scope (1.2, 2.1-2.5, 3.5-3.8, 3.12, 4.1-4.7, 5.1-5.7, 6.1-6.3,
8.4-8.7, 8.9-8.13):
- 33 still true;
- 3 partly or changed (4.2, 4.5, 8.13);
- 1 fixed (4.3).

The fresh read added 7 items: N1-N4, N-root, R5.4 being wider than reviewed, and N2.

## 2. Target structure

For each file: what moves where, what stays, and the public surface that must stay stable.
File names are proposals. New singletons go flat in their current directory, so no import
line changes.

### 2.1 `ModuleRules.qml` → five files (pure move)

| New file | Takes (current lines) |
|---|---|
| `singletons/ModuleManifestRules.qml` | id and naming rules (`validId` 288, `isOwnName` 293, `isOwnFact` 302, `isOwnSettingKey` 307), `_topFields` 316, `_list`, `_entries`, `_file`, `_check*` 374-575, `presetDefaultsProblem` 415, `parseManifest` 575-719, `_dropRepeated`. Plus a new `isPresetKey`: review 3.11, an **[api-next]** item. The move only makes room for it. |
| `singletons/ModuleFileRules.qml` | `canonicalPath` 200, `moduleDirectories` 217, `pathProblem` 236, `fileUrl` 254, `manifestFiles` 733, `qmldirFiles` 754, `maxFileBytes`, `filesToCheck` 785, `parseFileCheck` 824, `fileTexts` 836, `withoutBadFiles` 857, `directoryIndexOf` 1645. Also the guard: `guardLimit`, `guardClearMs`, `startGuard` 934. |
| `singletons/ModuleSourceRules.qml` | the QML reader: `rootProperties` 964, `modulePropertyWarning` 981, `_rootText` 994-1084, `initialProperties` 1085, `importsOf` 1099, `importAllowed` 1122, `importWarnings` 1147, `allowedImports*` 145-146. |
| `singletons/ModuleMergeRules.qml` | `precedence` 1160, `stateOf` 1181, `contributes`, `merge` 1222, `slotContributions`, `statusOf` 1272, `unknownSlotWarnings`, `merge*` 1308-1350, `modulesGroup`, `mergeSettingsPages` 1361, `contributionKey` 1638. |
| `singletons/ModuleRules.qml` (stays) | what the API is: `apiVersion` 82, `parseApi`, `apiCompatibility`, `slotTable`, `slotNames`, `reservedIds`, `states`, `settingTypes`, `factTypeNames`, `settingsTabs`, limits; the API's views `openUrlProblem` 1423, `apiNetworks` 1452, `apiVpnsUp` 1476, `frozenRows`, `factValue`, `ownSettingKey`, `ownFactName`, `settingValueProblem`, store `maxStoreBytes`/`storeText`/`parseStore`, `sameContext`, `_isQtObject`; the shared small readers `_isObject`, `_isString`, `_has`, `_get`, `_show` (public as `isObject` and so on, for the four files above). About 450 lines. |

- The three script strings (`fileCheckScript`, `startGuardScript`, `guardClearScript`) move
  to `scripts/module-file-check.sh` and `scripts/module-start-guard.sh` (with a `clear`
  argument), run by path (`Quickshell.shellDir + "/scripts/…"`). Do this in its own slice
  (M3), not in the pure move. The modules-hung test still works: it puts a fake `head`
  first on the script's PATH.
- Stable: `ModuleRules.apiVersion` (modules.md names it; the CHANGELOG test of review 3.9
  will read it) and `ModuleRules.slotTable` (read by `components/ModuleSlot.qml`, `api/Api.qml`).
  Every other caller is updated in the same slice: `api/*`, `singletons/{ModuleHost, Modules,
  SettingsSchema, WidgetRegistry, WidgetPresets, ProfileRules}`,
  `components/{ModuleSlot, ModuleContribution}`, `panels/{SettingsWindow, NotificationPanel,
  NetworkPanel}`, `panels/settings/GeneralSettings.qml`, `VpnManager`, `tests-modules.qml`
  and four suites.
- Tests: `ModuleRulesTest.qml` (613 lines) splits along the same lines. Add tokenizer cases
  before the move:
  - template strings with `${ { } }`;
  - `"` inside `'…'`;
  - `//` inside a string;
  - a `/` that is division, not a regex.

### 2.2 `ModuleHost.qml` (934 lines)

- Wait for the **[api-next]** runner (`run(cmd, done, { env, timeoutMs, onOutput })` with
  `cancel()`). Then the four Processes (535, 840, 872, 902) and their deadline Timers (540,
  866, 887, 926) become four runner calls. That is about 120 lines less, with no behaviour
  change: each deadline stays at `checkTimeoutMs`.
- The host uses the runner's core copy in `singletons/io/`, not the `api/` wrapper. This
  keeps the host free of `qs.api`, as modules.md §3 asks.
- Stable: every public property and function (`load`, `unload`, `setEnabled`, `status`,
  `handle`, `handleAt`, `initialProperties`, `slotUrl`, `slotComponent`, `describe`, the
  seams `guardFile`, `guardIdentity`, `guardClearMs`, `checkTimeoutMs`, `checkEnvironment`,
  `storeDirectory`).
- Not in this plan: making the handle's `host` private (review 3.2). That is
  **[api-next]**.

### 2.3 One way to load a file by URL (review 3.6)

- Use `Modules.initialProperties(url, extra)` without the `owner !== ""` ternary in all four
  places. It already returns `{}` for a file that belongs to no module.
- `Bar.qml` and `WidgetSettingsPane.qml` keep their `WidgetRegistry.moduleOf` lookup only
  where they report an error. A small `ModuleUrlLoader` (a `Loader` with `url`, `extra`
  and a `failed(owner)` signal) is optional. Skip it unless a fifth copy appears.
- `components/ModuleContribution.qml:96` stays as it is: it adds `context` and owns its
  guard.

### 2.4 `VpnManager.qml` → `VpnManager` + `VpnProviders`

| `singletons/network/VpnProviders.qml` (new) | `VpnManager.qml` (stays) |
|---|---|
| `_providers`, `registerProvider`, `unregisterProvider`, `_alive`, `_disconnectHandler`, `_readProvider`, `_providerReads`, `providerVpns`, `providerProblems` (127-255) | `nmVpns`, `vpns` (merge of `nmVpns` + `VpnProviders.providerVpns`), `activeVpns`, `activeType`, `activeGlyph`, details, interfaces |
| `providerOf`, `busyFor`, `needFor` (259-290) | `connect`, `disconnect`, `attend` (route by `vpnIdParts`; provider calls go to `VpnProviders.call`) |
| slots and pages: `slots`, `extrasFor`, `settingsPageOf`, `pageOf`, `openSettingsPageOf`, `contextFor` (144, 292-345) | the connect rule `attentionOf`, `canConnect`, `attendsInstead`, `primaryLabel`, and the new `presentation(vpn)` (R4.2) |
| `_callProvider`, `_request`, `_providerFailed`, `_notify` (380-428) | "VPN with a network" (470-557), `vpnsWith`, `networksWith`, `setVpnsWith`, `labelOf`, `unavailableVpnIds`, `providerKindsAmong` |
| — | WireGuard, plugins, import (608-677) |

- **Stable names with forwarders.** `components/VpnProvider.qml:153, 157` calls
  `VpnManager.registerProvider` / `unregisterProvider`. `components/VpnExtras.qml` and
  `VpnProviderPageFrame.qml` call `VpnManager.extrasFor`, `contextFor`, `pageOf`, `slots`.
  Modules see `contextFor`'s shape through the slots. So `VpnManager` keeps one-line
  forwarders for `registerProvider`, `unregisterProvider`, `slots`, `extrasFor`,
  `contextFor`, `pageOf`, `settingsPageOf` and `openSettingsPageOf`. The views move to
  `VpnProviders.*` in the same slice. The forwarders `VpnProvider.qml` uses stay for good.
- **The stand-in provider** (567-583, `fakeProviderUrl`, `_startFakeProvider`): to the test
  seams (§3). `VpnProviders` only gets `registerProvider` calls from it.
- **`lastProviderNotice`** (378): goes. The suite checks the notification through a test
  sink on `Notifier` (§3). This needs a new `Notifier.sent(summary, options)` signal, or a
  seam property `Notifier.sink`. Choose in slice V2.
- **`presentation(vpn)`** (new, in `VpnManager`): `{ stateText, primaryLabel, attendsInstead,
  canConnect, notices: [lines], noticeAction, noticeActionVisible }`. `VpnSection` and the
  `NetworkVpnSettings` delegate only render it. Whether the row should show the action only
  while active (175) and the card always (253) is decision 7.9. Until then, keep both
  behaviours behind a `where: "row" | "card"` argument.
- Optional defence for T8.5: `VpnProviders._readProvider` keeps the previous read when the
  new one is equal by value, so a provider that hands out new but equal arrays does not
  re-bind the views. A test pins it. This is behaviour-changing in a harmless way, so it
  goes in its own slice after V1.
- Must not change: `vpns` entries' shape (`uuid`, `name`, `state`, `active`, `attention`,
  `provider` …), which the kill switch (`VpnLockdown.qml:99-103`), `Api.vpnsUp` and the
  module read. `Config.network.vpnMemory`. `system.vpnWithNetworks`.

### 2.5 `NetworkRules.qml` → four files (pure move)

| New file | Takes |
|---|---|
| `singletons/network/VpnProviderRules.qml` | 898-1145: `isVpnProviderId`, `isVpnEntryId`, `vpnId`, `vpnIdParts`, `vpnStates`, `vpnProviderDetail`, `vpnProviderEntries`, `vpnProviderVpns`, `mergedVpns`, `activeVpnGlyph`, `vpnGlyph`, `vpnFailureNotice`, `lockdownProviderNote`, `sameVpnContext`, and its private helpers. |
| `singletons/network/VpnWithNetworkRules.qml` | 697-897: `vpnWithNetworkPlan`, `vpnAttentionGraceMs`, `prunedVpnMapping`, `unavailableVpnIds`, `editorVpnIds`, `vpnsToWrite`. |
| `singletons/network/VpnLockdownRules.qml` | 1146-1295: `lockdownWanted` … `lockdownNixosModule`. |
| `singletons/network/NetworkRules.qml` (stays) | validation, the editor (105-470), hotspots, writing, VPN plugins/import, WireGuard. About 700 lines. |

- Callers: `VpnManager`, `VpnLockdown`, `NetworkProfiles`, the network panels and settings
  pages. The suites NetworkTest and
  VpnProvidersTest are updated in the same slice. No forwarders: nothing outside the shell
  reads `NetworkRules`.

### 2.6 The lock screen

The order matters here: L1 (test) comes before any other edit to `Lockscreen.qml`.

**`Lockscreen.qml`**
1. **L1 — Pin the child order (R5.2), test only.** Add a unit test (in `LockViewTest` or a
   new `LockscreenShapeTest`) that reads `singletons/Lockscreen.qml` as text. It lists the
   types of the root's direct children in order and compares them with a list kept in the
   test. The comment in the test says why. The pinned order is
   `PersistentProperties(_carried)` before `WlSessionLock`, and `CapsLockLed`, then
   `PersistentProperties(_helperSweepOnce)`, then `Process(_helperSweep)` last. Every later
   slice that changes children updates this list on purpose, and its review checks the
   reload path. (Making the carry-over independent of order is not possible from QML.
   Quickshell matches by position.)
2. **L2 — Recovery decisions to pure rules (R5.1), behaviour-preserving.** Create
   `singletons/LockRecoveryRules.qml` (pure, with a suite). It is a small state machine over
   `{ lockKey, markerState, restoring, restoreDelay, refusalLogged, restorePending }`, with
   events `markerProbed(facts)`, `lockCommitted`, `lockConfirmed`, `lockOver(lastEnd)`,
   `restoreProbed(facts)`, `retryDue`, `markerUnlockDue`. Its actions are `writeMarker(word)`,
   `requestLock`, `probeHyprland`, `startRetry(ms)`, `startUnlockDelay`,
   `exitForRestart(why)`, `log`. It takes over the decisions now in `writeMarker`,
   `markerUnlockDue`, `lockOver`, `restoreRefused`, `lockConfirmed`, `restoreFromMarker`,
   `tryRestore` and the marker probe's handler (`Lockscreen.qml:500-671`). It keeps using
   `LockIoRules.markerFacts`, `markerDecision`, `hyprlandLockFacts`, `lockSurelyRefused`
   and `restartDelay`. The QML objects (`_marker`, the probes, the timers) stay where they
   are, so the child order does not change. **New tests first**: write one unit case for
   each lock-bed recovery scenario (`marker-stale`, `restart-kill-locked`,
   `restart-no-restore`, `restart-no-restore-generic`, `restart-locked-retry`,
   `restart-hyprctl-hang`, `reload-*`). Each case is a sequence of events with the actions
   expected.
3. **L3 — Probes onto `CommandQuery` (R5.3b).** `_markerProbe`, `_restoreProbe` and
   `_fallbackProbe` become `singletons/io/CommandQuery` at the same positions. The type
   changes but the position does not. L1's list is updated, and the reload tests
   (`reload-while-locked`, `reload-hard`, `reload-explicit`) must pass. The marker probe's
   script moves to `scripts/lock-marker-probe.sh`; it is run as the user, so a file is fine.
4. **L4 — `_build` in named parts.** Split `_build()` (615 lines) into three closures in the
   same file: the executor (`execute`, `startTimer`, `scopeFor`), the recovery driver (now
   thin, after L2) and the API object. Do this only if L2 still leaves `_build` above about
   300 lines. No new children.
- **Test seams** (122-150, 1063-1071): see §3, slice S2. Removing the `locktest`
  `IpcHandler` moves `CapsLockLed` and `_helperSweepOnce` up one position. That is safe only
  with L1 in place. The risk is limited to the reload that deploys the change: `watchFiles`
  is off while locked, so a locked session does not reload on that edit.
- **PAM sweep (R5.3a)**: recommended to **leave both**. They pick different processes at
  different moments, and the launcher's copy must not fork per process. Each copy already
  points at the other (`Lockscreen.qml:1096-1097`). If the owner still wants one script
  (decision 7.10), it becomes `scripts/pam-helper-sweep.sh` (bash) with `--group <pgid>` and
  `--children-of <pid> --started-before <ticks>`, written fork-free for the group mode. It
  is guarded by `restart-crash-finger`, `restart-kill-locked` and `harness-orphan`.
- Must not change: IPC `lockscreen` (lock, status, state; the `driver` keys in `state`, which
  `tests/lock/lib.sh:876-930` reads), the marker format, `H2S_SHELL_SUPERVISOR`, the
  `lockscreen.*` keys.

**`LockRules.qml` (1648 lines): split by layers, not by region**
- The handlers call each other across regions: PAM ends a lock (`_endLock`), sleep wakes the
  prompt (`_wakeLock`), every handler reconciles (`_reconcile`). Split by region and the
  singletons reference each other in a cycle. Split by layers instead, so every reference
  points one way:

| New file | Takes |
|---|---|
| `singletons/LockTransaction.qml` | the step primitives 1478-1640: `_ignored`, `_emit`, `_log`, `_setTop`, `_set`, `_setPassive`, `_nextId`, `_startTimer`, `_stopTimer`, `_anyPassive`, `_isSurfaceId`, `_findSurface`, config helpers, `_settingsFrom`, `_freshLockRegions`. |
| `singletons/LockViewRules.qml` | `view` 197, `describe` 237, `describeEvent`, `describeEffect`, `_passiveView` 1609, `_redacted` 1633, `_withoutSecret` 1172. |
| `singletons/LockParseRules.qml` | `parseMethods` 280, `parseLogind` 301, `parseSessionPath` 321, `retryDelay` 337. |
| `singletons/LockRules.qml` (stays) | constants (`timings`, `limits`, …), `initial`, `step`, `running`, the handler table and every handler, reconcile. About 1000 lines. |

- `LockRules.view`, `describe`, `describeEvent`, `describeEffect`, `parse*` and `retryDelay`
  stay as one-line forwarders. The driver, `screensaver/LockPrompt.qml` and
  `singletons/lock/LogindMonitor.qml` call them, and forwarders keep the lock slice small.
- One-way calls between singletons are common already (`VpnManager` → `NetworkRules`,
  `Lockscreen` → `LockRules`/`LockIoRules`). A cycle between singletons has never been tried
  in this tree, so the layering must keep every reference pointing one way. The review of
  K3 checks this with a grep.
- `tx` → `transaction` (R5.7) is a separate mechanical slice before the split. It needs no
  review beyond the diff stat and the suites.
- `LockRulesTest.qml` (2515) splits along the same lines.

### 2.7 `NetworkProfileCard` external mode and the connection editor

- **Card (R4.6).** The card stops calling `NetworkProfiles`. It always emits
  `useRequested()` / `stopRequested()`. `external` is removed. `editable` and `deletable`
  stay as plain properties (default true), and the VPN provider delegate sets them to false.
  The Wi-Fi, Ethernet and VPN pages call `NetworkProfiles.activate(uuid, device)`,
  `deactivate` or `disconnectDevice`, and `VpnManager.connect`/`disconnect` for provider
  entries. A helper keeps the three pages alike: `NetworkProfiles.use(profile, device)` and
  `NetworkProfiles.stop(profile, stopsProfile, label)`. Behaviour-preserving.
- **Editor save (N1).** Add one call,
  `NetworkProfiles.saveConnection({ uuid, changes, original, reconnect, vpns, lockdown })`.
  It returns a token. When the profile write succeeds, the singleton itself writes
  `VpnManager.setVpnsWith` and `VpnLockdown.setFor`. The editor only shows the result. This
  is **behaviour-changing**: a save now finishes after the page is left. Decision 7.8.
  Write the test first.

### 2.8 The Tailscale module

**Shared helpers (T8.7):** `module/PlainRules.qml` (module singleton, in `qmldir`) with
`isObject`, `get`, `string`, `number`, `strings`, and `prototypeKeys` if one is needed. The
five Rules files (`TailscaleRules`, `ServeRules`, `TaildropRules`, `NetworkExitRules`,
`LockRules`) use it.

**`TailscaleRules.qml` (2766) → six files (pure move):**

| New file | Takes (current sections) |
|---|---|
| `TailscaleAddressRules.qml` | Addresses 2631-end. |
| `TailscaleBusRules.qml` | the IPN bus 1786-1969: `jsonSplitter`, `jsonFeed`, `notifyDigest`, `notifyMask`, `watchMask`; plus the new `readsAfter(digest)` (behaviour slice, below). |
| `TailscaleCommandRules.qml` | Output of the CLI 1970-2057, Errors 2058-2149, Which programs run 2150-2240, Commands 2241-2530 (`commandFor`, `commandNames`, `privileged`, `timed`). |
| `TailscaleDiagnosticsRules.qml` | Diagnostics 1621-1785, Warnings 2531-2596. |
| `TailscaleSharingRules.qml` | Sharing 1307-1620 (routes, forwarding, switches). |
| `TailscaleRules.qml` (stays) | constants, readers (thin, using PlainRules), status, prefs, who may change, state, the provider entry, plans, the click-failure status line, logging, rechecks, devices, exit nodes, accounts, this device. About 1300 lines. |
| `Formatting` 2597-2630 | stays until **[api-next]** gives formatting helpers (review 9.5). Then it is deleted. |

**`TailscaleRunner.qml` (T8.6), behaviour-preserving.** Its public interface takes options
objects:
- `run({ argv, seconds, onDone, onChunk, env })` → handle `{ cancel() }`;
- `runChange({ name, argv, origin, onDone, retryElevated })`;
- `runLocked({ token, … })` and `finish(token, outcome)`;
- `generation` (read-only), `alive(generation)`;
- `timedArgv(argv, seconds)`.

The runner owns `_opProcess`, `_opToken` and the operation lock. The sub-clients get
`runner` as a property and never touch `client._*`. `TailscalePage` calls a public
`client.loginElevated()` (rename of `_loginElevated`). Later, the runner's process code
switches to the **[api-next]** runner, and the watchdog and `timeout` wrapping disappear
then.

**`TailscaleClient.qml` (2106) → clients, after the runner:**

| New file | Takes |
|---|---|
| `TailscaleTools.qml` | the tools seam and probe (126-155, `_start` 301-316 tool part, `_resolveTools`), the trust check. |
| `AccountsClient.qml` | Accounts 1067-1157, This device 1158-1171. |
| `SharingClient.qml` | Sharing 1172-1327. |
| `DiagnosticsClient.qml` | Diagnostics 1328-1406, Ping 1407-1714. |
| `LoginClient.qml` | Logging in 1715-1894. |
| `TailscaleClient.qml` (stays) | state, start/stop, reading, logging, rechecks, the event stream, connect/disconnect/attend, watching, resume, and the sub-clients as children. About 900 lines. |

Stable: every property and function the views, `Main.qml` and IPC use (`view`, `prefs`,
`busy`, `canChange`, `running`, `watch()`/`unwatch()`, the action functions). Where one
moves, the client keeps a forwarder. `Tailscale.client` stays.

**Read and clock (T8.4, T8.5): behaviour-changing, tests first.**
- `TailscaleBusRules.readsAfter(digest)` → `{ status, prefs }`. Status is read for `State`,
  `LoginFinished`, `NetMap` and "changed". Prefs are read only when the message changed state
  and carried no `Prefs`. Nothing is read for Taildrop progress (`OutgoingFiles` /
  `IncomingFiles`), `Health`, `SuggestedExitNode` or `ErrMessage`.
  - `_onBusMessage` calls `_scheduleRead(readsAfter(digest))`.
  - `_watchPoll` reads status only.
  - Test: a table of recorded bus messages → expected reads (TailscaleIoTest). The live
    suite still sees state changes.
- Clock:
  - Take `now` out of `facts` (230).
  - The offline exit node's grace gets a one-shot Timer set to `offlineSince + grace`.
  - Key expiry uses `nowMinute`, updated every 60 s.
  - "Last seen" labels use a page-local `now` Timer that runs only while the page is
    `shown`.
  - Test first: `entries` and `facts` stay equal by value, and keep their identity, across
    ticks of the old 5 s clock when nothing else changed. Grace and expiry still fire at
    their times (TailscaleStateTest with `fixedNow`).

**`TailscalePage.qml` (844) → sections (view move):** `AccountsSection.qml` (219-369),
`DevicesSection.qml` (563-593), `DiagnosticsSection.qml` (594-723),
`AdministrationSection.qml` (724-795). Connection, this device, exit node and network stay
in the page, which ends near 350 lines. Guard: TailscaleUiTest, TailscaleModuleTest.

**Rename (N4):** module `LockRules.qml` → `TailnetLockRules.qml` (with `qmldir`,
`LockClient`, `LockSection` and the tests).

**Test scaffolding (T8.12):**
1. Delete the `tests/run.sh` fallback and `tests/harness.qml`. `run.sh` becomes a wrapper
   around the shell's `tests/run-modules.sh`. `H2S_SHELL_DIR` is required, with no
   `../h2s-shell-wt` default, and the error message tells how to set it.
2. Extract `module/tests/ScenarioSuite.qml` from `TailscaleLiveTest`, `TaildropLiveTest`,
   `ServeLiveTest` (same scenarios, test code only). Scenarios wait on conditions, never on
   fixed sleeps (next-steps backlog).
3. The stand-in `tailscale`:
   - read fixtures with `jq` (already a dev tool: `tools/redact-status.jq`), not line
     patterns (`:439, 442, 746-755`);
   - move the serve semantics into `tools/stand-in/lib/serve.sh`;
   - add `fixtures/transcripts/1.104.4/` (recorded real CLI output, redacted with
     `redact-status.jq`) and a check in `tools/test.sh` that the stand-in answers the same
     commands with the same shape.
   - Porting it to Python is decision 7.11.

## 3. Test hooks in production code: one design

### Kinds

| Kind | Examples | Danger |
|---|---|---|
| **A. Inspection IPC**: reads where things are; changes nothing | `shelltest` (`Bar.qml:380`), `settings itemRect` / `currentPage` (`shell.qml:148, 159`) | None beyond what the screen shows. `tests/device/` runs them **against the real session** on the Framework. |
| **B. Behaviour seams**: change timings, tools, configs or trust | `H2S_LOCK_TOOLS`, `H2S_LOCK_SYSTEM_PAM_DIR`, `H2S_LOCK_AUTH_METHODS`, `H2S_LOCK_LEDS_DIR`, `H2S_LOCK_TEST_TIMINGS`, `H2S_LOCK_TEST_RELOAD`, `H2S_SHELL_TEST_MODULE_GUARD_MS` / `_CHECK_PATH` / `_CHECK_MS`, `H2S_FAKE_VPN_PROVIDER`, `H2S_LAUNCHER_TEST_TIMINGS`; the module's `H2S_TAILSCALE_TOOLS` and its use of `H2S_TEST_MODULES` | Lock-screen authentication, root commands, module trust. |
| **C. Injection by the owner object**: properties set by the suite that created the object | `ModuleHost.guardFile`, `guardIdentity`, `checkEnvironment`, `checkTimeoutMs`, `storeDirectory`; `TailscaleClient.toolsDir`, `fixedNow` | None in production: only code that builds the object sets them. **This is the preferred shape.** |
| **D. Test-only reads** | `VpnManager.lastProviderNotice`, `TailscaleRules.commandNames` | Dead weight. |

### Design

1. **One reader.** A new pure-ish singleton `singletons/TestSeams.qml`. It is the only place
   that reads B-kind variables. It exposes `active` (bool), `timings`, `lockTools`,
   `systemPamDirectory`, `ledsDirectory`, `reloadIpc`, `moduleGuardMs`, `moduleCheckPath`,
   `moduleCheckMs`, `fakeVpnProvider`, and `inForce` (the list of names in force). It may
   not import anything that the lock-closure check forbids. `Lockscreen`, `Modules`,
   `VpnManager` and `CapsLockLed` read it instead of `Quickshell.env`. The shell scripts
   (`lock-auth-methods.sh`, `launch.sh`) cannot read QML, so they apply the same gate
   themselves (step 2).
2. **Gate.** B-kind seams count only when both of these hold:
   - `H2S_TEST_BED=1` is set;
   - a marker file exists at `$XDG_RUNTIME_DIR/h2s-test-bed`, owned by the user, mode 600.
     The runners (`tests/headless.sh`, `tests/lock/lib.sh`, the module's lock bed) create it
     in their **private** runtime directory. A real session never has it.

   Without both, the seams are ignored, and one warning line names each variable that was
   set and ignored. Be honest about what this gate is: it **prevents accidents** (a variable
   left in a terminal or a systemd user environment), **not attacks**. A process that can
   set the shell's environment can already run code as the user (`LD_PRELOAD`). Write this
   in the trust section (§5).
   - The marker check must not delay the lock screen's start. Read it once, synchronously,
     with a `FileView` (`blockLoading: true`) on `XDG_RUNTIME_DIR` (tmpfs). Or decide from
     the variable alone and let the runner pass `H2S_TEST_BED=<path of the marker>`, which
     the shell checks with one `test -O` at start, before the lock driver `_build`s. Pick
     one in slice S1 and document it.
3. **Logging.** At start, when `active`, print one `console.warn` line: `[TestSeams] test
   bed: <names in force>`. Add `testSeams: [names]` to the lock screen's `state` driver block
   and to `modules list`, so the lock-bed logs show it. Each user of a seam may log what it
   changed, but the summary line is the contract.
4. **Inspection IPC (kind A)** stays always on: `tests/device/` needs it against the real
   session, and it reveals nothing the screen does not. Move `settings itemRect` and
   `currentPage` and `shelltest` into one file, `TestIpc.qml`, created by `shell.qml` and by
   each bar. This is only to gather them; the names stay. Its header says "read-only,
   changes nothing; anything that changes behaviour belongs behind TestSeams".
5. **`locktest reload`** (a kind B IPC): enabled by `TestSeams.reloadIpc` instead of its own
   variable. It stays where it is (Lockscreen) until slice S2, and it moves only with L1 in
   place.
6. **Stand-in provider:** `VpnManager._startFakeProvider` moves to `TestSeams` (or a
   `TestBedLoader` it owns). `TestSeams.fakeVpnProvider` gates it, and it still loads
   `tests/FakeVpnProvider.qml` by URL. Manual use: the runner's marker, or a documented
   `scripts/dev-test-bed.sh` that creates it for a session the developer chooses.
7. **Kind D:** `lastProviderNotice` is replaced by a notification sink: a seam property on
   `Notifier` set by the suite (kind C). `commandNames` stays (it is the command table's key
   list) with a comment that only tests read it.
8. **The module's seam (T8.9, N3).** The module needs to know "is this the shell's test
   bed?". Preferred: a read-only `Api.testBed` (bool, `TestSeams.active`). That is an
   **[api-next]** item: one minor bump, and modules learn nothing new about the environment.
   The module then:
   - honours `H2S_TAILSCALE_TOOLS` only when `Api.testBed`;
   - picks its stand-ins under the shell's module runner only when `Api.testBed`, not on the
     shell runner's private `H2S_TEST_MODULES` variable;
   - logs one line when the seam is in force.

   Fallback if `api-next.md` does not take it: the module checks the same marker file
   itself, and both repos' docs name the file as a contract.

## 4. Trackers: one, not two

| Option | What it means | Costs |
|---|---|---|
| **A. `docs/TODO.md` is the tracker** | Fold `next-steps.md`'s order (Tailscale, rest of modules, texts and languages) and backlog into TODO.md as Stage 12. next-steps.md shrinks to a pointer, or goes. CLAUDE.md stays as it is ("start here"). | One edit now. TODO.md already has the numbering (`11.34`), the working agreement, TODO-DONE.md and the code comments that cite numbers. Its status line must actually be kept current (it says 2026-11-12). |
| **B. `notes/plans/next-steps.md` is the tracker** | Move TODO.md's open items (11.31-11.37, 11.5-11.8, 11.20, 11.23, 11.24) into next-steps.md. Change CLAUDE.md to point there. Retire TODO.md, and keep TODO-DONE.md for history. | Loses the numbering, unless it is carried over. Commits and code comments that cite "TODO 11.x" point at a retired file. next-steps.md has no done list and no working agreement, so both must be added. |

**Recommendation: A.** It has the numbers, the done file, the working agreement, and
CLAUDE.md already points at it. `documentation.md` §3 proposes moving the tracker to
`notes/tracker.md`. That is a rename of whichever file wins, so A also keeps that move
simple. This plan's slices go into the chosen tracker as one stage, with the slice ids of §6.

## 5. Closing modules for now

**Precondition, whatever the option.** Write the trust model honestly in ARCHITECTURE's
Modules section and in modules.md (review 3.3; the wording and the docs layout are
**[docs]**). It must say:
- A module runs in the shell's process. That process also runs the lock screen's PAM prompt
  and the polkit agent. So a module can read typed passwords, answer polkit requests, and
  run any program through `Quickshell.Io`.
- The import allowlist is a warning, not a boundary (§7 of modules.md).
- Per-module namespacing (`setValue`, `setPresetValue`) is a convention between cooperating
  modules. The handle's `host` is still reachable (review 3.2, **[api-next]**).
- The test-bed gate of §3 prevents accidents, not attacks.
- The PAM fallback in the shell's folder is user-writable (R5.5).
- Installing a module means trusting its author as much as the shell's.

**Options:**

| Option | What is done before pausing | Cost | Leaves |
|---|---|---|---|
| **1. Write and stop** | The trust write-up; settle the discovery-order contradiction in modules.md by writing "decided in M4/M5" (R3.8); fix the handle's `host` exposure **[api-next]**. No new code beyond that. | S | Turning a module off and on stays `qs ipc call modules setEnabled <id> false/true`. Safe mode only notifies. |
| **2. Write, plus a Settings → Modules page (recommended)** | Option 1, plus a minimal **Settings → Modules** page (System tab, the `modules` group, which `ModuleRules.modulesGroup` already defines). For each module: name, version, API state, `state`, errors and warnings, missing programs, setup hints; an on/off switch (`Modules.setEnabled`); and the **Reload** button the owner decided on (`setEnabled(id, false)`, then `true` on the next event loop turn). A short "Installing today" text in the module's README: copy or link the module into `~/.local/share/h2s-shell/modules/`, or name it in `H2S_SHELL_MODULE_PATH`. | M (one page; `Modules.statuses` already has every field) | No install from a repository, no Nix option, no signatures. |
| **3. Option 2 plus M4** | `modules sync` from git (`{ source, ref }` list, clone or fetch into the data home, record the commit), "Add a module" on the page, and "Check for updates". | L | Brings code from the network into the process that runs the lock screen. Without M6 nothing says who wrote it. Needs the discovery order settled (R3.8) and git error handling at start. |

- **M5 pieces worth taking now, small, either option:**
  - the safe-mode banner. `hud/StartupWarning.qml` exists; safe mode today only sends a
    notification (`Modules.qml:113-118`). S.
  - only if the owner wants Tailscale on the NixOS Framework through the system flake: a
    `programs.h2s-shell.modules` option that puts the modules' paths into the wrapper's
    `H2S_SHELL_MODULE_PATH`. That path is searched first, so "the Nix one wins" holds
    without reordering discovery. S-M.
- **What waits:** the author guide (**[docs]**, after `api-next.md`), M4 sync, M6
  signatures, the NixOS evaluation-time API check.
- **Recommendation: option 2,** with the safe-mode banner. Write the trust model first, as
  the first slice of this part. The page is also where the owner's per-module Reload
  belongs, and it replaces the IPC-only way of doing it.

## 6. Order of work

Each slice leaves every suite green. Size: S (under half a day), M (a day or two), L (more).
"Unit" means `tests/run-unit.sh` (or `quickshell -p tests.qml` on the Arch host, decision
7.1). "Lock bed" means `tests/lock/run.sh`, which needs Nix. Module slices run
`tests/run-modules.sh <module>` and `tools/test.sh` in the module repo.

### Phase 0: decisions and the tracker

| Id | Slice | Size | Depends | Guard | Kind |
|---|---|---|---|---|---|
| D0 | Owner answers §7. Fold this plan into the chosen tracker (§4). | S | — | — | docs |

### Phase 1: pure moves of well-tested rules, shell

| Id | Slice | Size | Depends | Guard | Kind |
|---|---|---|---|---|---|
| M1 | Tokenizer test cases (§2.1), on the current code | S | — | ModuleRulesTest | test only |
| M2 | Split `ModuleRules` into five (§2.1); split its suite | M | M1 | unit (ModuleRules, Modules, ModuleRegistries, QuickshellPin, WidgetRegistry, Profiles, SettingsPages) | pure move |
| M3 | Module scripts out of QML strings into `scripts/module-*.sh` | S | M2 | ModulesTest; lock bed `modules`, `modules-hung`, `modules-launcher` | pure move (runs by path) |
| N1 | Split `NetworkRules` into four (§2.5) | M | — | unit (Network, VpnProviders) | pure move |
| U1 | One URL-loading form (§2.3) | S | — | ModuleRegistriesTest, WidgetRegistryTest; lock bed `modules` | pure (same result) |

### Phase 1: pure moves, module (independent of the shell's phase 1)

| Id | Slice | Size | Depends | Guard | Kind |
|---|---|---|---|---|---|
| T1 | `PlainRules.qml` shared helpers | S | — | all module suites | pure move |
| T2 | Split `TailscaleRules` into six (§2.8) | M | T1 | TailscaleState/Io/Devices/Accounts/Sharing tests, live suites | pure move |
| T3 | Rename module `LockRules` → `TailnetLockRules` | S | — | LockSection tests, TailscaleUiTest | pure move |

### Phase 2: hubs and views, behaviour-preserving

| Id | Slice | Size | Depends | Guard | Kind |
|---|---|---|---|---|---|
| V1 | `VpnProviders` singleton (§2.4), with forwarders | M | N1 | VpnProvidersTest, NetworkTest, ModuleRegistriesTest (`vpn-slots`, `vpn-page`), module TailscaleModuleTest | pure move |
| V2 | `VpnManager.presentation(vpn)`; both views render it. Test first. | S | V1, decision 7.9 | VpnProvidersTest (new cases) | behaviour-preserving (or changing per 7.9) |
| V3 | `NetworkProfileCard` without `external` and without I/O (§2.7) | S | V1 | SettingsPagesTest, NetworkTest | pure (same behaviour) |
| V4 | Provider read kept when equal by value (§2.4, optional) | S | V1 | VpnProvidersTest (new) | behaviour-changing, harmless |
| T4 | `TailscaleRunner` (§2.8); sub-clients and the page off private members | M | T2 | TailscaleIoTest, ServeTest/ServeLiveTest, TaildropTest/TaildropLiveTest, NetworkExitTest, CertClient/Lock suites | behaviour-preserving |
| T5 | Split `TailscaleClient` into clients (§2.8) | L (two reviews: tools+accounts+sharing, then diagnostics+login) | T4 | all module suites, module lock bed | pure move |
| T6 | `TailscalePage` sections (§2.8) | M | T4 | TailscaleUiTest, TailscaleModuleTest | pure move (view) |
| T7 | Dead code (T8.10): `watchMask` from `notifyMask`; drop `_prototypeKeys`; `lockStatus` gets `--json` and `LockClient` uses the table; `fileGet` deleted and `privileged()` refuses `writesAsRoot`; old-shell checks removed (the manifest already needs 1.3) | S | T2 | TailscaleIoTest (update `fileGet` cases), live suites | behaviour-changing (small) |

### Phase 3: behaviour changes with tests first

| Id | Slice | Size | Depends | Guard | Kind |
|---|---|---|---|---|---|
| E1 | Editor save in `NetworkProfiles.saveConnection` (N1). Test first: page destroyed before `saved`. | M | N1, decision 7.8 | NetworkTest (new), VpnProvidersTest | behaviour-changing (kill switch) |
| T8 | Reads after bus messages and poll (T8.4). Test table first. | M | T2 | TailscaleIoTest (new), TailscaleLiveTest | behaviour-changing |
| T9 | Clock out of `facts` (T8.5). Test first. | M | T2, T4 | TailscaleStateTest (new), TailscaleLiveTest, shell VpnProvidersTest | behaviour-changing |
| T10 | T8.11 correctness items, one commit each | S each | T4 | per item | behaviour-changing |
| T11 | Test scaffolding (§2.8, steps 1-2) | M | — | module suites | test code |
| T12 | Stand-in: `jq` fixture reads, `lib/serve.sh`, transcript check | M-L | T11, decision 7.11 | `tools/test.sh`, live suites | test code |
| R1 | `tests.qml` honours `timeLimitMs` (R3.12) | S | — | run-unit-selftest | test runner |

### Phase 4: test seams

| Id | Slice | Size | Depends | Guard | Kind |
|---|---|---|---|---|---|
| L1 | Lockscreen child-order test (§2.6) | S | — | unit (new) | test only |
| S1 | `TestSeams` singleton + gate + marker in the runners; Modules, VpnManager stand-in and CapsLockLed read it; Notifier sink replaces `lastProviderNotice` | M | V1, decision 7.5 | unit; lock bed full run (every test sets the marker); `tests/device/*` by hand on the Framework | behaviour-changing (seams need the gate) |
| S2 | Lockscreen and `lock-auth-methods.sh` read the gate; `locktest` by `TestSeams.reloadIpc`; L1's list updated | S | S1, L1 | lock bed full run | behaviour-changing (tests only) |
| S3 | `TestIpc.qml` gathers kind-A IPC (names unchanged) | S | — | `tests/device/*`, lock bed `modules` | pure move |
| S4 | Module: seam behind `Api.testBed` (or the marker file) | S | S1, **[api-next]** `Api.testBed` | module suites, module lock bed | behaviour-changing |

### Phase 5: module host on the runner, then modules closed

| Id | Slice | Size | Depends | Guard | Kind |
|---|---|---|---|---|---|
| H1 | `ModuleHost` processes on the runner (§2.2) | M | **[api-next]** runner, M3 | ModulesTest; lock bed `modules-hung`, `modules` | pure (same deadlines) |
| T13 | Module runner internals on the API runner | M | T4, **[api-next]** runner | module suites | behaviour-preserving |
| C1 | Trust model written (§5) | S | — | — | docs **[docs]** |
| C2 | Settings → Modules page with on/off and Reload (§5 option 2) | M | C1, decision 7.7 | SettingsPagesTest (page present), ModuleRegistriesTest (toggle via page = IPC result); manual | behaviour-changing (new page) |
| C3 | Safe-mode banner | S | — | ModulesTest (`safeMode` → banner text), manual | behaviour-changing |
| C4 | (if wanted) `programs.h2s-shell.modules` | S-M | decision 7.7 | `nix build`, Framework | behaviour-changing |

### Phase 6: the lock screen, last, behind tests

| Id | Slice | Size | Depends | Guard | Kind |
|---|---|---|---|---|---|
| K1 | `tx` → `transaction` (R5.7) and the `Theme.lock` token for 360 | S | — | LockRulesTest, LockViewTest | pure (mechanical) |
| K3 | `LockRules` by layers (§2.6), with forwarders; suite split | M | K1 | unit (LockRules, LockView, LockIoRules); lock bed full run | pure move |
| L2 | `LockRecoveryRules` + unit cases for each recovery scenario first | M-L | L1 | unit (new suite); lock bed `restart-*`, `reload-*`, `marker-stale`, `supervisor`, `relock` | behaviour-preserving |
| L3 | Lock probes on `singletons/io/CommandQuery`; marker probe script to `scripts/` | S | L2, L1 | lock bed `marker-stale`, `restart-no-restore*`, `restart-hyprctl-hang`, `fallback`, `reload-*` | behaviour-preserving |
| L4 | `_build` in named parts (only if still > 300 lines) | S | L2 | lock bed full run | pure move |
| N2 | Lockscreen setting defaults from the schema only | S | decision 7.3 | ProfilesTest; lock bed `idle`, `idle-lock`, `logind` | behaviour-preserving (unless 7.3 changes the default) |

The phases are a suggestion. Phases 1-2 of the shell and of the module can run in
parallel, since they touch different repositories. Phase 6 needs a Nix machine for every
slice.

## 7. Owner's decisions needed

Each one is a choice. The recommendation follows "→".

**7.1 Unit tests without Nix (review 1.2).**
- (a) `run-unit.sh` falls back to running `tests.qml` directly when `nix` is missing. The two
  window suites are skipped, or run on the real display, and the output says so.
- (b) Nix stays required, and CLAUDE.md and README say so. Lock-bed slices (phase 6, S1,
  S2) need the Framework or Nix either way.
- → (a) for the unit runner; it keeps the host usable. Add Nix on the Arch host if the
  owner wants to run lock-bed slices there.

**7.2 Next version (review 2.1).** The migration of `lockscreen.lockNotificationDetail`
("full" → "app", `SettingsSchema.qml:181`; `ProfileRules` `formerDefault`) makes the next
release 3.0.0 under the project's rule.
- (a) Release 3.0.0.
- (b) Drop the migration and release 2.x.
- → (a): the migration is already written and described (`CHANGELOG.md` Unreleased).

**7.3 `lockscreen.lockOnSleep` default true (review 2.2; `SettingsSchema.qml:173`,
`Lockscreen.qml:107`).**
- (a) Keep true and list it under Changed.
- (b) Default false.
- Either way, N2 removes the repeated defaults in `Lockscreen.qml:103-107`.
- → (a): locking before sleep is the safe default for a lock screen. The owner's host keeps
  it pinned off.

**7.4 NixOS polkit PAM default (review 2.3; `nix/module.nix:32-35, 73-74`).**
- (a) Default false (opt-in).
- (b) Keep `config.services.fprintd.enable`.
- Either way, document it in the README's NixOS section.
- → (a): turning a shell on should not reorder the system's PAM stack for every polkit
  agent.

**7.5 Test-seam gate (§3).**
- (a) The variable plus a marker file in the private runtime directory.
- (b) The variable alone, with a loud log.
- (c) Leave the seams as they are, logging only.
- → (a), stated as protection against accidents, not attacks.

**7.6 Trackers (§4).** → A (TODO.md), later renamed by `documentation.md` if approved.

**7.7 Closing modules (§5).**
- (1) Write and stop.
- (2) Plus a Settings → Modules page with on/off and Reload, and the safe-mode banner.
- (3) Plus M4 sync.
- Separately: is `programs.h2s-shell.modules` (C4) wanted now?
- → (2). C4 only if Tailscale should come from the Framework's system flake soon.

**7.8 The connection editor's save (N1).**
- (a) The save finishes in `NetworkProfiles` even if the page is left.
- (b) Keep it in the view, but block leaving the page while it saves.
- → (a): the kill-switch choice must not depend on a page staying open.

**7.9 The attention action on the row (R4.2).** Today the row shows it only while the VPN is
up (`VpnSection.qml:175`) and the card always (`NetworkVpnSettings.qml:253`).
- (a) Make them the same: always.
- (b) Make them the same: only while up.
- (c) Keep the difference on purpose.
- → (a): an entry that needs the user offers its action everywhere.

**7.10 PAM helper sweep (R5.3a).**
- (a) Leave the two copies, which point at each other.
- (b) One bash script with two modes.
- → (a): they select differently at different moments, and the launcher's must not fork.

**7.11 Stand-in `tailscale` (T8.12).**
- (a) Keep sh, read the fixtures with `jq`, split serve, add a transcript check.
- (b) Port it to Python 3.
- → (a): smaller change, no new language in the module repo.

**7.12 API minor versions that tighten (review 2.4).**
- (a) A minor version may refuse what was allowed when it closes a hole (1.2's `file:`
  refusal), with a CHANGELOG "Module API" line marked *tightened*.
- (b) Tightening always needs a major version.
- Write the rule in modules.md (or in its successor per `documentation.md`).
- → (a): a hole should not wait for a major.

**7.13 The supervisor retries forever while locked (review 2.5; `scripts/launch.sh:613-622`,
every 60 s).**
- (a) Confirm: it is the way back to a prompt.
- (b) Cap it.
- → (a), and say so in the lock screen docs **[docs]**.

**7.14 Taildrop preferences (T8.12; `TaildropClient.qml:44-64`).**
- (a) Move them to `mod.tailscale.taildrop*` settings in the manifest, migrating from the
  store once.
- (b) Keep them as store data and write down why.
- → (a): they are preferences, and the schema gives them profiles and the settings UI.
  The cost is one small migration in the module.
