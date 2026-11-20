# Architecture clean-up: the shell and the Tailscale module

A plan for the owner to approve (tracker step 7). Revised on 2026-11-21 against `master` at
`159d20b` (module API 1.35) and the module's `main` at `1c1a322`, for the owner's decisions
of 2026-11-17 on (`notes/decisions.md`) and the work since: the API plan's batches, the test
tree, the notification flow, progress notifications, Taildrop's transfers and views. The
first version (2026-11-17, `git show 159d20b:notes/plans/architecture-cleanup.md`) keeps
the detail of the moves it proposed (§2 there); this one says what is left of them, what is
new, and in which order. Items keep their old keys (R4.1, T8.6, N1) for lookup.

## 0. Rules for every slice

- One slice is one reviewable change with its test; the suites it names pass, and
  `tests/run-all.sh` passes on both machines before a merge (`notes/workflow.md`).
- A pure move changes no behaviour: code and its callers and tests move, nothing is fixed on
  the way. A finding goes into its own slice or the tracker.
- **Stable unless the owner agrees:** the module API (`Api.*`, the handle, `ModuleStore`,
  the public elements of `api/`, the anchor table and the slot names, every property of
  `components/VpnProvider.qml`, the theme token names — anchors and tokens are pinned by
  tests); IPC targets and functions; setting keys (`lockscreen.*`, `system.vpnWithNetworks`,
  `mod.<id>.*`); config keys; the lock marker and the start guard files;
  `scripts/h2s-vpn-lockdown`'s arguments; the launcher's environment for the shell
  (`H2S_SHELL_MODULES`, `_SAFE_MODE`, `_SUPERVISOR`, `_LAUNCHER`).
- The lock screen never depends on `api/`, `Modules`, `ModuleHost` or a module
  (`tests/lock-closure.sh`); the core uses core types, never `qs.api`.
- A root script is never loaded from a place the user can write: the inline
  `pkexec sh -c` texts (`VpnLockdown.qml`, `NetworkOverview.qml`) stay inline.
- After a singleton changes, the shell is restarted, not reloaded (`CLAUDE.md`).
- **Views** (`notes/workflow.md`, "the mockup first"; the owner's overnight rule): every
  slice is marked
  - **—** no view file changes;
  - **file** a view file changes but nothing on screen does — a headless screenshot of the
    element before and after (a test tree or a mockup run on the real code) is identical;
    these may run without a mockup;
  - **screen** what the user sees changes — waits for a mockup and the owner.

## 1. The old items against today's code

**Done or obsolete** (no slice):

| Key | What | Now |
|---|---|---|
| R3.5 | `ModuleRules` split | done (S0): `ModuleManifestRules` 919, `ModuleFileRules` 491, `ModuleSourceRules` 438, `ModuleMergeRules` 678 lines. `ModuleRules` grew back to 1866 (new item X2) |
| R3.7 | `ModuleHost`'s four `Process` blocks | done (API plan, fifth batch): one `CommandRunner` (`ModuleHost.qml:1726`); left: `_clearGuard`'s `execDetached` (`:993`, X3) |
| R4.3 | two id checks | done (`vpnIdParts`) |
| R4.5 | `VpnProvider.kind`, `ready` | kept: API |
| R5.2 | Lockscreen's child order | done (L1): `tests/LockscreenShapeTest.qml` |
| R5.4, 7.5 | test hooks in production | done by the test tree (`plans/test-seams.md`): `singletons/TestSeams.qml` (36 lines) holds constants; the readers live in `tests/lock/seams/`. Production reads only the launcher's contract (`Modules.qml:126–127`, `IconThemes.qml:22`, `Lockscreen.qml:850`). Left: one IPC (A10) |
| R6.1–6.3 | two trackers; `### Module API` convention | done: `notes/tracker.md`; the convention is in `CLAUDE.md`. `README.md:182` goes to the documentation plan (D0) |
| R3.8 | discovery order in `plans/modules.md` | moves to the plan for installing modules (tracker step 1) |
| R3.12b, R4.4 | long changelog lines; never-pruned provider ids | documentation plan |
| N3, T8.9 | the module reading `H2S_TEST_MODULES` / `H2S_TAILSCALE_TOOLS` | done (A3, module M2): `module/tests/TailscaleModuleTest.qml:323–327` pins that no file reads them |
| T8.5 | the module's 5 s clock in `facts` | done: `now` is `max(Api.minuteNow, _moment)` (`TailscaleClient.qml:173`), the grace has its own timer (`:2052`) |
| T8.13 | `Format` copies in the module | done: `Api.format` (`TailscaleRules.qml`, `DeviceRow.qml`) |
| 7.1–7.4, 7.12, 7.13 | Nix for tests; 3.0.0; `lockOnSleep`; NixOS polkit PAM; tightening minors; supervisor | decided or moved: the runners need no `nix`; the pending release is a minor; `lockOnSleep` off is step 2; PAM is step 11; minors may tighten until step 15; 3 restarts while locked is step 9 |
| R5.3a, 7.10 | two PAM helper sweeps | left as they are: they pick different processes at different moments and point at each other |
| R5.5 | the fallback PAM config is user-writable (`LockIoRules.qml:90`) | step 11 (PAM) and step 8's trust statement |

**Still true** (slices in §3):

| Key | Where (today) | What |
|---|---|---|
| R3.6 | `Bar.qml:157` | the last of four `owner !== "" ? Modules.initialProperties(url) : {}`; `Modules.initialProperties` returns `{}` for a core file (`Modules.qml:91–93`) |
| R3.12 | `tests.qml:88` | one 90 s deadline for every async suite; `TestCase.timeLimitMs` honoured only by `tests-modules.qml:110–113` |
| R4.1 | `singletons/network/VpnManager.qml` (745) | a hub: providers' registry and reads, slots and pages, provider calls, the connect rule, "VPN with a network", WireGuard and plugins. Test-only `lastProviderNotice` (`:411–417`, read by `tests/VpnProvidersTest.qml:423–427`); `Notifier.recorded` (`Notifier.qml:40–63`) now does that job |
| R4.2 | `panels/network/VpnSection.qml:187`, `panels/settings/NetworkVpnSettings.qml:66, 277–278` | state words and notice twice; the attention's action shows on the row only while up, on the card always (question 1) |
| R4.6 | `panels/settings/NetworkProfileCard.qml:46–48, 85–114` | `external` mode; the card calls `NetworkProfiles` itself |
| R4.7 | `singletons/network/NetworkRules.qml` (1397) | VPN with a network (824–1001), providers (1002–1250), the kill switch (1251–1397) and the editor in one file |
| N1 | `panels/settings/NetworkConnectionEditor.qml:178–184` | the view writes `VpnManager.setVpnsWith` and `VpnLockdown.setFor` on `saved`: a page gone by then loses the VPN link and the **kill-switch choice** |
| N2 | `singletons/Lockscreen.qml:103–107` | repeated defaults (`?? true` for `lockOnSleep`) the schema holds — wrong once step 2 turns the default off |
| R5.1, R5.3b | `Lockscreen.qml` (1237): `_build` from `:177`; probes as `Process` at `:1009`, `:1043`, `_fallbackDirectProbe` | recovery decisions without unit cases; three hand-made probes where `singletons/io/CommandQuery` fits |
| R5.6, R5.7 | `singletons/LockRules.qml` (1648, 439 × `tx`); `screensaver/LockSurface.qml:195` (`Math.min(360, …)`) | size; naming; a literal size |
| T8.4 | module `TailscaleClient.qml:834` | every bus message ends in `_scheduleRead()`: a status and prefs read per Taildrop progress message |
| T8.6 | module `ServeClient`, `TaildropClient`, `LockClient`, `CertClient`, `NetworkExitClient`; `TailscalePage.qml` → `client._loginElevated` | sub-clients and a view use the client's private members (`_run`, `_runChange`, `_tailscaleArgv`, `_limitMs`, `_finish`, `_opToken` …; ServeClient alone 14 uses) |
| T8.7 | module `TailscaleRules.qml` 2869, `TailscaleClient.qml` 2058, `TailscalePage.qml` 825; `_isObject` in six Rules files | size; copied helpers |
| T8.10 | module `TailscaleRules.qml:92` (`notifyMask` unused), `:99` (`watchMask` literals), `:133` (`_prototypeKeys`), `:2411, :2575` (`fileGet`); `LockClient.qml:52` writes its own argv; `Main.qml:369` an old-shell check | dead and mismatched code |
| T8.12 | module `tests/run.sh:29` (default `../h2s-shell-wt`); `module/tests/ScenarioHandle.qml`, `liveSuites.js`; `TaildropClient.qml:65–69` (preferences in the store) | test scaffolding the shell's `ModuleTestKit` should replace (tracker, "Module test kit"); preferences outside the schema (question 2) |
| N4 | module `LockRules.qml` | the same name as the shell's lock-screen rules |

## 2. New since the first version

| Key | Where | What |
|---|---|---|
| X1 | `components/NotificationCard.qml` (799) | header (icon, app, time, pin, "×"), pictures (probe, thumbnail or preview, `_pictureSource` :125), progress and its wave (:153–200), the finger swipe (:51–62), body with links and reply (:239–300), timer bar and copy overlay (:706–) in one file |
| X1b | `NotificationCard.qml:347, 376` | the pin's and "×"'s hover from a `MouseArea`'s `containsMouse`, not `PointerArea`'s `lit` (convention; tracker "Left open") |
| X2 | `singletons/ModuleRules.qml` (1866) | anchors (94–410), a module's icon (411–500), program lookup (579–854), test mode (855–940), the pre-1.10 gate (941–1046, removed by Z), facts (1076–1573), runtime hand-overs (1574–1726), helpers, exports (1820–) |
| X3 | `singletons/ModuleHost.qml` (1735) | applying (997–1532) and programs (1533–1702) in one object; `guardClearScript` through `execDetached` (`:993`) |
| X4 | `api/Api.qml` (1243) | ~300 lines of header are the API reference (documentation plan D10 moves it) |
| X5 | `singletons/Notifications.qml` (710) | the server and history beside the three toast queues and modals (226–656); callers: `Bar.qml`, `hud/ToastStack.qml`, `hud/NotificationHudItem.qml`, `hud/ShellNotificationHudItem.qml`, `panels/Popup.qml`, `NotificationCard.qml`, two suites |
| X6 | `singletons/ToastRules.qml` (578) | cohesive (queues, modals, placement, badges): **leave**; revisit past ~800 |
| X7 | `Bar.qml:379` | `shelltest notificationState` is live in the production shell and hands held notifications' summaries to any process of the user, also while locked; only the lock bed reads it (`tests/lock/tests/notifier-progress.sh`), which runs a test tree |
| X8 | `components/ReorderList.qml:124` | a bare array (`root._shown`) bound to `ListView.model`, against the Repeater-crash rule |
| X9 | tests: `tests/ModulesTest.qml` start guard (~268–301); unit suites that open the real `SettingsWindow` | a check inside a 300 ms timer fails under load; suites start the real `nmcli monitor` and try `notify-send` (against "tests never touch a real daemon") |
| X10 | `panels/settings/NetworkConnectionEditor.qml` (1103) | one view file for every connection type's sections |
| X11 | module `TaildropClient.qml` (1290), `TaildropTransferRules.qml` (1352) | new and large; settle after the Taildrop work in progress |
| X12 | code comments | 115 lines in 85 files point into `notes/`; section headers carry "(API 1.26)". Fine for comments, but a pointer to a plan that has aged says less than one sentence of reason. Low; with each file's own slice, never alone |

## 3. Slices

Size: S under half a day, M a day or two, L more. "Tonight" = no view on screen and no
collision with steps 2, 8 and 9 or the module work in progress.

**Collisions.** Step 2 changes `lockOnSleep` (`SettingsSchema.qml:174`, `Lockscreen.qml:107`).
Step 8 (modules closed for now) touches `ModuleHost`, `Modules`, `ModuleRules`, `SettingsWindow`
and the safe-mode banner. Step 9 (lock) touches `Lockscreen`, `LockRules`, `LockIoRules`,
`scripts/launch.sh`. The API's closing slice Z touches `ModuleRules`, `ModuleHost`, `api/`
and the module, after the module's 0.7.0. The module's Taildrop work is on its own branch.

### A. Tonight: network, notifications, tests (shell)

| Id | Slice | Size | Depends | Guard | View |
|---|---|---|---|---|---|
| A1 | `VpnProvidersTest` reads `Notifier.recorded` (the suite sets `recordOnly`); `lastProviderNotice` deleted | S | — | VpnProvidersTest | — |
| A2 | `NetworkRules` into four, pure move: `VpnWithNetworkRules` (824–1001), `VpnProviderRules` (1002–1250), `VpnLockdownRules` (1251–1397), the rest stays (~820). Callers in 16 core files; no module reads it | M | — | NetworkTest, VpnProvidersTest, AddressRulesTest, ModuleRulesTest, AnchorsTest | file |
| A3 | `VpnProviders` singleton out of `VpnManager` (registry, reads, slots and pages, provider calls); `VpnManager` keeps one-line forwarders for `registerProvider`, `unregisterProvider`, `slots`, `extrasFor`, `contextFor`, `pageOf`, `settingsPageOf`, `openSettingsPageOf` | M | A1, A2 | VpnProvidersTest, NetworkTest, ModuleRegistriesTest, AnchorsTest; the module's suites against the tree | — |
| A4 | The editor's save finishes in `NetworkProfiles.saveConnection({ uuid, changes, original, reconnect, vpns, lockdown })`; the editor shows the result. Test first: the page destroyed before `saved` → link and kill-switch choice written | M | A2 | NetworkTest (new case), VpnProvidersTest | file |
| A5 | `NetworkProfileCard` without `external` and without I/O: it emits `useRequested` / `stopRequested`; the Wi-Fi, Ethernet and VPN pages act (`NetworkProfiles.use`, `stop`) | S | A3 | SettingsPagesTest, NetworkTest | file |
| A6 | `Bar.qml:157` → `Modules.initialProperties(_url)` | S | — | ModuleRegistriesTest, WidgetRegistryTest | file |
| A7 | `Toasts` singleton out of `Notifications` (226–656: queues, modals, placement, HUD hand-over), pure move, callers updated, no forwarders | M | — | NotifierTest, ToastDragTest, the notification suites; lock bed `notifier-progress` | file |
| A8 | `NotificationCard` into parts under `components/notification/` (header, picture, progress, swipe, body), pure move | M | A7 | the notification suites; screenshots of a toast and a centre entry (plain, image, progress, critical) identical | file |
| A9 | `shelltest notificationState` into the test seam file, as `locktest reload` went (O4) | S | — | lock bed `notifier-progress` | — |
| A10 | `ReorderList` through a `ScriptModel` / `KeyedModel` | S | — | the suites of the pages using it; drag by hand in a test tree | file |
| A11 | `tests.qml` honours `timeLimitMs` per suite (as `tests-modules.qml`) | S | — | run-unit-selftest | — |
| A12 | `ModulesTest`'s start guard waits on conditions, not inside a 300 ms timer | S | — | ModulesTest under load (`--keep-going`, twice) | — |
| A13 | Unit suites with the real `SettingsWindow` get stand-in `nmcli` and `notify-send` (the runner's `PATH`) | S | — | ModuleRegistriesTest, AnchorsTest; no "nmcli monitor exited" in the log | — |

### B. Tonight if the module lane is free (module repository)

| Id | Slice | Size | Depends | Guard | View |
|---|---|---|---|---|---|
| B1 | Reads after bus messages from a rule: `readsAfter(digest)` → `{ status, prefs }`; nothing read for Taildrop progress, `Health`, `SuggestedExitNode`, `ErrMessage`; the watch poll reads status only. Test table first | M | — | TailscaleIoTest (new), TailscaleLiveTest, TaildropLiveTest | — |
| B2 | Dead code (T8.10): `watchMask` from `notifyMask`, `_prototypeKeys` and `fileGet` gone, `privileged()` refuses `writesAsRoot`, `LockClient` takes its argv from the command table, the old-shell check in `Main.qml:369` gone | S | — | TailscaleIoTest (update `fileGet` cases), live suites | — |

### C. After step 8 and Z (module host)

| Id | Slice | Size | Depends | Guard | View |
|---|---|---|---|---|---|
| C1 | Tokenizer cases on `ModuleSourceRules` (template strings, `"` in `'…'`, `//` in a string, a dividing `/`), on the current code | S | — | ModuleRulesTest | — |
| C2 | `ModuleRules` into `ModuleAnchorRules` (anchors, icon), `ModuleProgramRules` (lookup, test mode), `ModuleFactRules` (facts, runtime hand-overs); `apiVersion`, `slotTable`, `anchorTable` names stay reachable from `ModuleRules` (forwarders) | M | Z, C1 | ModuleRulesTest (split along), ModulesTest, ModuleRegistriesTest, AnchorsTest, ApiElementsTest | — |
| C3 | `ModuleHost`'s programs into a child object; the guard's clearing on the runner, not `execDetached` | M | step 8, C2 | ModulesTest; lock bed `modules`, `modules-hung`, `modules-launcher` | — |
| C4 | `api/Api.qml` by area if still above ~800 lines once its header is in `docs/` | S | documentation D10 | ApiElementsTest, the API suites | — |

### D. After step 9 (lock screen)

| Id | Slice | Size | Depends | Guard | View |
|---|---|---|---|---|---|
| D0 | N2: `Lockscreen.qml:103–107` read the schema's defaults — **in step 2's `lockOnSleep` slice**, not here | S | step 2 | ProfilesTest, LockIoRulesTest; lock bed `idle`, `logind` | — |
| D1 | `tx` → `transaction`; the 360 in `LockSurface.qml:195` from a `Theme` token of the same value | S | step 9 | LockRulesTest, LockViewTest | file |
| D2 | `LockRules` by layers (step primitives, view and describe, parsers), forwarders for `view`, `describe*`, `parse*`, `retryDelay`; suite split along | M | D1 | unit lock suites; lock bed, full | — |
| D3 | `LockRecoveryRules`: the marker, restore and retry decisions as a pure state machine; one unit case per recovery scenario (`marker-stale`, `restart-*`, `reload-*`) written first | M–L | step 9 | new suite; lock bed `restart-*`, `reload-*`, `marker-stale`, `supervisor`, `relock` | — |
| D4 | The probes on `CommandQuery` at the same child positions (`LockscreenShapeTest`'s list updated on purpose) | S | D3 | lock bed `marker-stale`, `restart-no-restore*`, `restart-hyprctl-hang`, `fallback`, `reload-*` | — |

### E. Module, after its 0.7.0 and Z

T1 `PlainRules` (the six `_isObject` copies) · T2 `TailscaleRules` into address, bus, command,
diagnostics and sharing rules (first version §2.8) · T3 `LockRules` → `TailnetLockRules` ·
T4 `TailscaleRunner`: sub-clients and the page off private members (`client.loginElevated()`)
· T5 `TailscaleClient` into clients · T6 `TailscalePage` sections (file) · T7 `tests/run.sh`
requires `H2S_SHELL_DIR`; `ScenarioHandle` and `liveSuites.js` replaced by `ModuleTestKit`
once the shell's kit can (tracker) · T8 `TaildropClient` / `TaildropTransferRules`, looked at
once the Taildrop work settles. Order: T1, T3, T2, T4, then T5–T8. All **—** but T6.

### F. On screen — wait for a mockup

| Id | Slice | Depends |
|---|---|---|
| F1 | `VpnManager.presentation(vpn)`: one state text, notice and action for the row and the card | A3, question 1 |
| F2 | The notification card's pin and "×" lit by `PointerArea` (tap feedback, larger target) | A8 |
| F3 | `NetworkConnectionEditor` in sections — a pure move (**file**), listed here because the editor's look is due for the views' rework; do it with that rework or alone after A4 | A4 |

## 4. Order

Tonight, one after another on one branch per slice: A1 → A2 → A3 → A4 → A5, with A6, A9–A13
in between (no shared files); A7 → A8 after them. B1, B2 in the module repository when its
lane is free. D0 goes with step 2. C after step 8 and Z; D after step 9; E after the module's
release and Z; F with the mockups. The documentation plan's developer pages for an area
follow that area's slices.

## 5. Open questions for the owner

1. A VPN that needs you (for example Tailscale asking for a login) offers its action — "Log
   in" — on its card in the settings at all times, but on its row in the network popup only
   while the VPN is up. Should both show it always, both only while up, or should they stay
   different on purpose? Until answered, F1 keeps both behaviours.
2. Taildrop's preferences (the folder, what to do on a name conflict, auto-save) are kept in
   the module's own store, not in its settings schema, so they have no profiles and no
   settings-page rows of their own. Where they are set, moving them needs a migration (the
   decision asks to check both machines first). Should they move to `mod.tailscale.taildrop*` settings with a one-time migration in
   the module's next minor release, or stay in the store with a comment saying why?
