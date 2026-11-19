# Tracker

The one list of what is next, for the shell and its modules (the module repository
`h2s-shell-tailscale` keeps no tracker of its own). Done items go to [done.md](done.md).
Plans are in [plans/](plans/). Machines are named only "the NixOS machine" and "the Arch
machine".

## Now

State on 2026-11-17: everything is merged to `master` (core) and `main` (module
`h2s-shell-tailscale`, version 0.6.0, module API 1.3) and runs on the NixOS machine.
Development moves to the Arch machine; runs that need `nix` go over SSH to the NixOS
machine. How sessions work is in [workflow.md](workflow.md).

State on 2026-11-17, end of the session on the Arch machine. One topic at a time from here
(the owner). The test split is done; the next topic is the API plan's implementation
(index [plans/api-next.md](plans/api-next.md)): the theme token test, the
`ModuleRules.qml` split and the version gate (first batch), the file chooser trial and
the bordered buttons (second), pills in three sizes and the public button (third), the
other public elements (fourth), the command runner and the module host on it (fifth) are
on `master` (below). The elements lane is done but for a module's icon (U7a). The first
four batches were not reviewed by a second agent and ran on the Arch machine only; the
fifth and sixth were reviewed and ran on both machines. The test seams moved out of the
installed shell into a test tree (below). Module test mode (A3), privileged start (A4) and
the prompt saying who and what for (A5) are on `master` (below). The commands lane is done
with helpers (C1) and the notification (A6). System facts (C2) are on `master`. The
module's M2 and M3 are on its `main` (below): its privileged runs show the full prompt.
B1, D1 and E1 are on `master` (below): the facts lane is done. P1 is on `master`. Next:
P2 (reach closed), a look at the lock bed's restart scenarios, then the places lane and the
remaining module slices.

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
  - Lock-bed restart scenarios (`restart-crash-locked`, `restart-kill-locked`) fail now and
    then in full runs on both machines and pass alone: to look into next.

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

- [x] **Test split** ([plans/test-split.md](plans/test-split.md)): done — a general set
      that runs on NixOS and on Arch, a set per system (`tests/run-system.sh`), and one
      command before committing (`tests/run-all.sh`). Notes in [done.md](done.md).
- [x] **Test speed**: done — the lock bed's runner takes the machine-wide lock itself, the
      nix tool lookup is remembered; the whole lock bed takes about three minutes on either
      machine.
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
- [ ] **API plan**: approved by the owner on 2026-11-17.
      [plans/api-next.md](plans/api-next.md) is the index with the slice list (48 slices);
      one file per area is under `plans/api-next/`. A brief for a slice names the index and
      the slice's area file, nothing more. Implementation has started (the first batch, above); next slices: the file
      chooser trial, then the bordered buttons. Not yet done: a short independent review
      of what changed after the last one (button kinds, icons, the password queue, a
      module's own elements) — fold it into the review of the first slices of each area.

How to run a session cheaply (the owner asked; this session used most of its budget): one
topic at a time; collect the owner's answers and hand them to an agent in one go; a fresh
agent with a narrow brief instead of resuming one with a long history; no agent waits on a
test queue; review what carries risk, look at one-line fixes yourself.

## Order of work

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

## Decisions

All by the owner, 2026-11-17.

- The module API is ours: a module never works around a gap; the API is extended first.
- Larger work goes analysis → plan (owner approves) → implementation.
- Versioning: a settings migration may ship in a minor release, never in a patch. The pending release is a minor.
- `lockscreen.lockOnSleep` defaults to off. To investigate: detecting, independent of the system, that something else locks the screen, and telling the user.
- Lock supervisor: at most 3 restarts while locked; then the session stays locked, the user logs in on a TTY and starts the launcher by hand; the user is told what happened and how to look into it; documented.
- Tests: one general set independent of the system, plus a set per system (NixOS, Arch). A developer runs the general set and their system's.
- PAM: the order of password and fingerprint is the system's PAM stack, not the prompt's. Wanted: configuring PAM rules from the shell; needs its own analysis and plan.
- Documentation: English only; Markdown with "NixOS" and "Arch" subsections wherever the systems differ (a site with tabs maybe later); pages for system-only features where it makes sense; never one system without the other; nothing refers to or relies on the developers' own environments (user names, home paths, machines); screenshots are the owner's; docs verified for consistency at each major release, not on every change; `docs/` never links into `notes/`.
- Module API: a minor version may tighten behaviour for now (nobody else uses the shell yet); the rule is tightened when needed. (Temporary: it ends at the first release announced as open to module authors, see "Module API, versioning for authors" below.)
- Module API, UI anchors: views are built from shared blocks (settings page, section, card, row, popup section) that register under a path derived from where they stand; a module names a path, a placement (before, after, appended inside) and its element. Addressable: settings pages and popup content; not the bar (the user places widgets there). One naming convention for anchors; the list of anchors pinned by a test and documented. Today's slots move onto anchors.
- Module API: a module may publish its own versioned API object for other modules (declared in the manifest; a dependent module gets only that object). Basic version in this round. Reaching into another module or the host goes away.
- Privileged runs by a module: no time window; the password prompt says which module asks and what for, next to the actual command.
- Privileged runs, 2026-11-18: the shell does not parse or judge a module's command (no lists of shells, launchers or interpreters, no requirement of a declared program). A module runs in the shell's process, so such checks never stop a hostile one; the checks left (absolute existing program, printable words, a purpose, not while locked, one prompt at a time, the shell's timeout inside the trusted pkexec) catch mistakes and keep the prompt honest. The protection against a module not from the project is the prompt and the user knowing what they install. Written in `docs/ARCHITECTURE.md` "Modules".
- Exit node (Tailscale): a manual choice "for now" that overrides the per-network setting, and a per-network choice in that connection's options (through an anchor).
- No terminal setting of its own: a global "default programs" setting later.
- (Temporary, see "Module authors" and "Trust" below.) Modules closed for now = the trust model written down honestly (a module runs in the shell's process, which also handles the lock screen's password and the polkit agent), Settings → Modules (enable, disable, reload, install, update, remove from a repository), the safe-mode banner. Later: NixOS option for modules, signatures.
- Coding is done by strong models only; no weaker models for mechanical moves.
- Module API, placements: `before`, `after` (outside the block), `prepend`, `append` (inside, first and last).
- (Replaced as to "only", see "a module's own elements" below.) Module API, public elements: modules build their views only from public elements made for the API (in `qs.api`), which use the shell's internal components inside; the internals stay free to change, the public elements keep compatibility. Modules should use as many standard elements as they can. In this round.
- Module API, variants are meanings, not looks, on every public element; never raw colours or sizes (on a public element's properties; a module's own elements are free, see below). A button's kind is `primary`, `secondary`, `danger`, `warning` or `success`, and more may come; asking first is a separate thing that goes with any kind; a danger button may act on the first click. A module's "Cancel" is `secondary`; no kind of its own.
- Buttons with a tone (`danger`, `warning`, `success`) are bordered: at rest a border in the tone's colour, under the pointer or a pressing finger the whole background in it. Every such button in the shell takes this look, the small "✕" on each row of the Bluetooth popup and the per-row "Disconnect" buttons included.
- Pills: three sizes, `s`, `m`, `l`, standard, set by the theme and offered through the API. The shell's 24 px pills become `s` (22 px).
- Module API, network cards: the place for a module's button on a card is built in this round; the button is the shell's, of any kind, always above "Forget" / "Delete" (a module that wants caution makes it ask first). An element that opens is the shell's `ExpandingRow`. A closed card shows the module's icon when the module has something set for that network; the detail is on the opened card.
- Module API, a module's icon: a glyph of the icon font, an SVG file or an image file; the module chooses.
- Module API, order: by module id for now; a module's say in the load order and in the order of elements in one place comes later.
- Password prompt: the labels are "Module" and "Authorization"; the command is hidden and shown on a click, is the real command, and a long one is shown whole, scrolling. (Replaces "next to the actual command" above as to where it shows.) With another polkit agent the run goes ahead, with a shell notification naming module and purpose just before.
- Privileged runs: a prompt open or waiting when the screen locks is cancelled as if dismissed, and the user clicks again after unlocking. Only the password question is one at a time, so a long action does not hold up the others; with another polkit agent it is strictly one action at a time. A run for which no password is asked shows nothing; one log line names the module.
- File chooser for modules: a minimal version in this round.
- Exit node per network: it sits on the saved network's opened card.
- Module API, a module's own elements: modules are not kept from building their own elements. They use the public elements wherever that is possible and makes sense, and the theme's colours always; building something the API does not offer is fine. Importing the shell's internal elements stays the thing to avoid. (Replaces "only from public elements" above: that is not a rule and not an error.)
- Module authors: that every module is the owner's is true today, not an assumption to build on. Other people are expected to write modules later; until then the shell and its module system are built up to the point where they can do so without problems.
- Direction: the shell itself becomes a fairly small framework that defines the structure and the way of working; parts of what is built in today can then be split out into modules. Such modules need not live in repositories of their own: some ship together with the shell.
- Module API, a module's own elements, in detail: built from QtQuick; every colour and type size from the theme's public tokens (`Api.theme`), never a literal; a public element is used where one exists and fits (a "should", not checked); a module asks for a new public element when it is of general use and builds its own otherwise. Only importing the shell's internal components is detected: listed as deprecated, then an error in the module's status. "The module API is ours" covers capabilities (running things, system state, privileges, places in the shell's views), not looks. The token names are pinned by a test.
- Review as a guard is for the project's own modules. An outside module has no review; there the password prompt's text (Module, Authorization, the command) is the only protection.
- Module API, versioning for authors: "a minor may remove things" ends at the first release announced as open to module authors. From then a removal comes only with a major version, after being listed as deprecated for at least one release, and is announced in `CHANGELOG.md`'s "Module API" section and the author guide. Merging the closing slice only after the module is released is a one-off for the one module of today.
- Shipped modules use only the public API, like anyone's module: one class of modules. Every feature split out proves the API.
- The shell provides the services, or abstractions for reaching them; a module builds on them and adds the whole feature (popups, elements, widgets, settings pages). Every built-in feature is to be gone through and divided this way. The lock screen, password prompts and privileged runs stay in the framework.
- Order after the API round (2026-11-17): the author guide, a module template and a module's tests runnable without a checkout of the shell; then the built-in features are divided, one first, as the proof that the API is enough; only then is the shell announced as open to module authors, and from that release a removal needs a major version.
- Trust: no isolation ("the shell must work and modules need access to its functions"); running modules in a process of their own is not a later question. The user must know what they install: a module that does not come from the project is announced as such (a plain statement and a confirmation when a module that is not shipped is first enabled; shown when a user's copy replaces a shipped one), and is then not the project's responsibility.
- File chooser for modules (2026-11-18): the system's standard dialog is enough for now. No chooser of the shell's own in this round, and sending files is not extended. The better answer is wanted later: integration with file managers (backlog).

## Backlog / later

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

## Open points

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
