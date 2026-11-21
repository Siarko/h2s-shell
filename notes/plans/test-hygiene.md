# Test methodology and hygiene

A plan for the owner (no test or code changed by it). Measured on the Arch machine
(32 threads, Quickshell 0.3.2 from pacman, tools from `PATH`) on 2026-11-21 at `8a95ef9`,
while other agents ran `--quick` in their trees (load noted with each number).
Marks: **[measured]**, **[read]** (in the code), **[assumed]** (to be checked in the slice
that names it), **[NixOS]** (reported from the NixOS machine by another session).

## 1. Today

### 1.1 The parts of `tests/run-all.sh`

| Part | Time | Notes |
|---|---:|---|
| run-all / run-system self-tests, install.sh | 0 s each | |
| unit suites (`tests/run-unit.sh`) | **89–90 s** | one Quickshell process; the critical path is §1.3 |
| module fixture suites | 1 s | |
| privileged runs fixture | **26 s** | real queue timings: "3 s with the request open", killAfterMs 3000, the head's 2 s |
| tool lookup self-test | 4 s | |
| supervisor self-test (`launcher-selftest.sh`) | **20 s** | real launcher timings, a `sleep 3`, `within 3/5/10` |
| deploy check, docs lint | 0 s | |
| unit runner self-test | 10 s | stand-in Quickshells that hang and are timed out |
| system set (Arch) | 4 s | |
| **`--quick` total** | **155 s** | CLAUDE.md and the runner's header say "under a minute" |
| lock bed (`tests/lock/run.sh`, `-j 4`) | **209 s** | 72 scenarios, 745 s of scenario time at `-j 4`; load 5–7 (average 4.9, two other agents' runners alongside) |
| **full set** | **≈ 364 s (6 min)** | 155 + 209; the header says "about four minutes" |

**[measured]** `--quick` at load ≤ 3; the unit run alone took 88.9 s and 89.0 s at load
0.4–3.3. The parts run one after another although all but the lock bed share nothing but
the processor (`tests/headless.sh`: private compositor, runtime dir, HOME).

### 1.2 The slowest suites and scenarios

Unit suites: own time (start to summary, from timestamps added in a scratch copy of the
tree; the tree itself unchanged), and the time when run alone (`run-unit.sh <Suite>`,
startup included). Lock scenarios: the bed's own per-scenario time in a `-j 4` run at load 5–7 (two other agents' unit runs alongside), so a few seconds above an idle machine's.

| # | Suite / scenario | Time | Why |
|---:|---|---:|---|
| 1 | lock `sleep-lockers` | 41 s | one stack; the sleep-locker reader's schedule (first read 1 s after start, then every second) watched through 16 conditional waits of 5–10 s |
| 2 | lock `modules-launcher` | 39 s | lives out the launcher's real 30 s quick-death window ("the safe-mode shell has run for 32 s") |
| 3 | lock `methods-fprintd` | 39 s | `sleep 31`: the real 30 s re-detection pause |
| 4 | lock `restart-no-restore` | 37 s | `sleep 12` counting looks at Hyprland after a refusal (backoff 5 s, then 10 s) |
| 5 | lock `two-outputs` | 33 s | many short fixed sleeps (0.3–1 s) between output changes, 15 waits |
| 6 | lock `fingerprint-timeout` | 33 s | the stand-in's rounds and a `check_within 45` for PAM's own timeout; `sleep 4.5` |
| 7 | lock `restart-crash-finger` | 32 s | Quickshell restarts in place only a shell that ran 10 s (upstream rule); `sleep 4`, `sleep 2` |
| 8 | unit `ButtonKindsTest` | 26 s | every kind × state waits for a colour animation, polled with `driver.wait(10)` **[assumed]**; blocks every other async suite meanwhile (§1.3) |
| 9 | lock `notifications` | 26 s | toast durations lived out (2 s, the user's 5 s), fade-ins slept |
| 10 | lock `restart-crash-locked` | 23 s | the same 10 s in-place restart rule; `sleep 2` |
| 11 | lock `modules-discovery` | 20 s | module host checks on real timers |
| 12 | lock `idle` | 18 s | idle timeouts lived out |
| 13 | lock `supervisor` | 17 s | `sleep 5`, `sleep 3`; the launcher's real windows |
| 14 | unit `ModulesTest` | 11 s | loads fixture modules, waits for the host's checks; 12 s alone |
| 15 | unit `AnchorsTest` | 11 s own | the settings window opened and closed over and over; 29 s alone (pulls ModuleRegistries, Modules, VpnProviders) |

Beyond the 15: unit `PointerInput` 6.1 s, `SidePanel` 6.1 s, `ToastDrag` 5.2 s,
`ApiElements` 4.7 s, `StatusPill` 4.0 s, `ModuleRegistries` 4.0 s own; the lock bed's median
scenario is 6 s, its shortest 1–2 s (one stack's start).

Startup of one unit run (compositor, Quickshell, every suite built): **0.9 s**
(`run-unit.sh FormatTest`, 885 ms) **[measured]**. The 46 synchronous suites together take
**4.5 s**; `LockRules` (3.7 s) is most of it.

### 1.3 Why the unit run takes 90 s: the asynchronous suites do not run side by side

`tests.qml` and `docs/ARCHITECTURE.md` say the asynchronous suites "run side by side", each
limit "counted from the start of the suites". They do not **[measured]**: every
window-driving suite waits with QtTest's `driver.wait(10)` in a loop (`_until`), a nested
event loop that runs inside its `runAsync()`. The `Qt.callLater` that starts the next suite
cannot run until that `runAsync()` returns, so the window suites run strictly one after
another:

```
 0.0– 4.5  synchronous suites (LockRules 3.7 s)
 4.6–10.7  PointerInput        6.1
10.7–36.7  ButtonKinds        26.0
36.7–41.9  ToastDrag           5.2
41.9–46.6  ApiElements         4.7
46.6–52.8  SidePanel           6.1
52.8–58.1  SettingsModal, StatusPill, LockView, AuthPromptView
59.0–61.0  CommandRunner, NetworkCardGeometry, …
61.0–72.0  Modules            11.1
72.0–76.1  ModuleRegistries    4.0  (after: Modules)
76.1–86.9  Anchors            10.8  (after: ModuleRegistries)
86.9–88.3  FileChooser         1.5  (waits for every other suite)
```

FileChooser ends at **88.3 s of a 90 s limit on Arch too** — the same margin that fails it
on NixOS [NixOS]. AnchorsTest's own `timeLimitMs: 90000` is counted from the start, so it
has the same 2 s margin. Any new window suite, or a slower machine, tips the chain over.

The `after:` chains exist because suites share one process: `ModuleRegistries` waits for
`Modules` (both load modules into the one `Modules` singleton and write `Config`),
`Anchors` for `ModuleRegistries`, `SettingsModal` for `SidePanel` (the keyboard), and
`FileChooser` for all (a real dialog takes the keyboard) **[read]**.

### 1.4 Shared mutable state in the one process

Suites that write singletons other suites read **[read]** (grep of assignments and setters):

- `Config`: Anchors, ModuleRegistries, Modules, Notifier, SettingsPages, ToastDrag
  (`Config.readOnly` is set once for all in `tests.qml`).
- `Profiles`: Anchors, FileChooser, KeyedViews, Network, SettingsModal, SidePanel.
- Other singletons: Network, Notifier, VpnProviders (`VpnManager`, `Notifier`), and
  `Modules.host` (Modules, ModuleRegistries, Anchors, FileChooser).

Most restore what they changed (`_saved…`), but nothing checks it, and a suite that throws
half-way leaves its writes for the suites after it. The order dependency is real: running
`AnchorsTest` alone pulls `ModuleRegistries`, `Modules` and `VpnProviders` with it (29 s
alone).

### 1.5 Fixed deadlines and sleeps

- Lock bed **[read]**: 646 `check_within` (322 × 5 s, 145 × 10 s, 86 × 3 s, 17 × 2 s…) and
  83 fixed `sleep`s in scenarios. The `sleep`s that are waits rather than stand-ins:
  `methods-fprintd` 31 s (the real 30 s re-detection pause), `restart-no-restore` 12 s
  (counting looks over a window), `supervisor` 5 + 3 s, `fingerprint-timeout` 4.5 s,
  `reload-while-locked` 4 s, `restart-crash-finger` 4 s, `edit-while-locked` 3 + 3 + 2 s,
  `marker-stale` 3 × 2 s, `harness` 2 + 1 + 1 + 1 s, `escape`, `scale`, `notifications`
  (fade-ins). A `check_within 3` is an upper time bound on a loaded machine, not a hang
  guard. (The 40 s `sleep`s in `modules-hung`/`modules-reload` are stand-ins that never
  answer, which is right.)
- Unit **[read]**: `_until(…, 3000)` in the window suites; FileChooser's 8 s per step;
  ModuleRegistries' 15 s; CommandRunner "killAfterMs after the limit (… < 5000 ms)"; the
  privileged fixture's `after >= 1500 && after < 4500`, `waited >= 2500` — two-sided time
  bounds on real timers, which a loaded machine breaks.
- Self-tests: `launcher-selftest.sh` `sleep 3`, `within 3 "SIGHUP to the supervisor"`.
- Global deadlines: `tests.qml` 90 s from the start for every async suite; `headless.sh`
  `timeout 240` on Quickshell and 300 on labwc; the lock bed 150 s per scenario.

### 1.6 The known flaky list and its causes

| Flake (tracker) | Cause | Fix (slice) |
|---|---|---|
| `launcher-selftest` "SIGHUP … (not within 3 s)", lock `supervisor` [NixOS] | started with SIGHUP ignored (nohup / detached ssh): bash cannot trap an inherited-ignored signal, so `trap … HUP` (`scripts/launch.sh:590`) never fires | start the launcher under test with `env --default-signal=HUP` (`launcher-selftest.sh:132`, `spawn` in `tests/lock/lib.sh:115`) — T0 |
| `FileChooserTest` timed out (90 s) | §1.3: the serial chain under one global limit | each chained suite's limit counted from the end of the one before — T0; gone with shards — T4 |
| `AnchorsTest` order of a section's parts | a measurement before layout settled **[assumed]** | wait on the layout condition — T6 |
| `ModulesTest` start guard (300 ms) | `guardClearMs = 300` lived out on a real timer | a condition on the counter; the window via the host's clock seam — T6 |
| Lock `restart-kill-locked`, `harness` env, `fallback` PAM stand-in, `modules-discovery` silent 44 s | load: 4 stacks plus other agents' runners, against 3–10 s deadlines | hang-guard deadlines (§4.2), automatic rerun-alone with a FLAKY verdict — T7 |
| QtTest `'windowShown' of null` | a driver used before its window exists | wait for the window's exposure before the first event — T6 |
| `TaildropLiveTest` (module repository) | real transfer timings | same rules, in the module's repository; not in this plan's slices |

### 1.7 Tests that cannot fail, duplicated coverage

- No `assert(true)` outside an `if/else` with a `fail` (WidgetRegistry, SettingsPages: fine)
  **[read]**. Nothing catches a suite that reports `0/0 passed`, or a lock scenario with no
  `PASS` line: both count as passed today **[read]** (`headless_verdict`, `run.sh`).
- Nothing shows that a new check fails when its subject breaks: review is the only guard.
- Duplication: the launcher's restart/SIGHUP behaviour is checked both in
  `launcher-selftest.sh` (20 s) and in the lock bed's `supervisor` and `restart-*`
  scenarios; `methods-script` and `methods-fprintd` share the real methods script.
  Overlap is cheap where the self-test is the fast first line; it is listed so that a
  slice touching the launcher does not run both by default (§2).

### 1.8 What `--quick` runs that a slice rarely needs

Of 155 s: the privileged fixture (26 s) matters for slices touching `PrivilegedRuns`, the
module host or the API; the supervisor self-test (20 s) for `scripts/launch.sh`; the unit
runner self-test (10 s), tool lookup (4 s) and docs lint for the runners, `resolve.sh` and
docs. A slice touching one widget needs the unit suites and nothing else; `--quick` gives it
an extra 65 s, and the unit run's 90 s are mostly the window suites it did not touch.

## 2. Affected-test selection, made mechanical

`tests/affected.sh <git range>` (default `master...HEAD` plus the working tree) prints the
commands to run, one per line, and `--run` runs them (through the same runners, so their
verdicts and summaries are unchanged):

```
tests/run-unit.sh ButtonKindsTest PillSizesTest
tests/lock/run.sh relock fallback
tests/launcher-selftest.sh
```

### 2.1 The mapping

1. **QML suites — derived, not written.** QML type names are file names, so a suite's
   dependencies are readable: a closure scanner (the generalisation of
   `tests/lock-closure.sh`) follows from `tests/<Suite>.qml` every type instantiated
   (`Name {`), every singleton used by name (`Name.` where `singletons/Name.qml` exists;
   `lock-closure.sh` deliberately skips these, this one must not), every
   `Qt.resolvedUrl("…")`/`createComponent` path and every string literal naming an existing
   file or directory of the tree (fixtures, scripts read through `Process`). The reverse
   index (file → suites) is the map. Nothing to keep true by hand for the common case.
2. **Declared extras, for what a scan cannot see.** A suite's or a scenario's header may
   add `// covers: <path or glob>` (`# covers:` in a scenario): a script the shell runs by
   a computed name, a `module.json`, a seam.
3. **Lock scenarios.** The bed runs the whole shell, so a closure would select all 72.
   A scenario runs when the change touches its `# covers:` (each scenario declares them —
   `restart-*`: `scripts/launch.sh`; `methods-*`: `scripts/lock-auth-methods.sh`,
   `singletons/lock/`; `modules-*`: `singletons/Modules.qml`, `singletons/modules/`…) or
   the closure of `tests/lock-closure.sh`'s roots plus the launcher; a scenario without a
   `covers` line runs on any change in that closure.
4. **Scripts and runners** — a fixed table in `affected.sh` (each runner → its self-test:
   `run-all.sh` → `run-all-selftest.sh`, `run-unit.sh`/`headless.sh`/`count-suites.sh` →
   `run-unit-selftest.sh`, `resolve.sh` → `resolve-selftest.sh`, `scripts/launch.sh` →
   `launcher-selftest.sh` and the `restart-*`/`supervisor` scenarios, `install.sh` →
   `install-test.sh`, `docs/`, `README.md` → `docs-check-selftest.sh`, module host/API →
   the module fixture parts).
5. **No tests by design**: `notes/`, `CHANGELOG.md` (VersionTest covers the number),
   `site/` — an explicit list, so that "maps to nothing" is a decision, not a hole.

### 2.2 How it is kept true

`tests/affected-selftest.sh`, a part of `run-all.sh`:

- every tracked file maps to at least one suite, scenario or self-test, or is on the
  no-tests list: a new file nothing covers fails the self-test with its name;
- every `covers:` line matches at least one tracked file (a renamed file is caught);
- every suite reaches its subject (`FormatTest` reaches `Format.qml` or `FormatRules.qml`
  where one exists by name);
- canned ranges give the expected commands (a `Theme.qml` change selects every suite
  reading Theme; a `notes/` change selects nothing; `tests/TestCase.qml` everything).

### 2.3 The fallback

Anything the map cannot place precisely selects more, never less: `tests/TestCase.qml`,
`tests.qml`, `tests-modules.qml`, `tests/headless.sh`, `tests/lock/resolve.sh`,
`tests/lock/tools.nix`, `shell.qml`, `api/Api.qml` → all unit suites; `tests/lock/lib.sh`,
`tests/lock/run.sh`, `tests/test-tree.sh`, `singletons/TestSeams.qml` → the whole lock
bed; an unmapped file (should not exist, §2.2) → `run-all.sh --quick`. The end of a
segment still runs the full set on both machines: selection speeds the slice, the segment
run is the net.

## 3. Speed

### 3.1 Unit suites in parallel shards

The runner already gives each run its own compositor, runtime dir and HOME, so shards are
separate `headless_setup`/`headless_run` pairs in one `run-unit.sh`, each with its own
`H2S_TEST_SUITES`, and one verdict over all their logs (the counts add up exactly as now).

- **Shard plan**: each window suite and each of the long async suites in a shard of its
  own; the synchronous suites and the short async ones packed by measured time
  (`tests/unit-times.txt`, written by the runner at each full run, longest first —
  as `LONG_TESTS` does for the bed). `-j N`, default `min(cores/2, 8)`; `-j 1` is today's
  single process.
- **The chains go**: in separate processes `Modules`, `ModuleRegistries`, `Anchors` and
  `FileChooser` no longer share a `Modules` singleton, `Config` or a keyboard. An `after:`
  stays only where a suite consumes another's result (ModuleRegistries' `vpnSuite`); a
  suite that needs a fresh process declares `ownProcess: true` and the shard plan obeys.
- **Startup cost**: 0.9 s per process; with 8 shards ~1 s of CPU each, invisible in wall
  time.
- **The longest suite becomes the floor**: ButtonKinds 26 s. Its waits are colour
  animations (`Theme.duration("hover")` on every state change) polled 10 ms at a time
  **[assumed: confirm with per-check timestamps]**; the unit runner sets
  `animation.speed` to its maximum (or `reduceMotion`) through the test profile, and a suite
  that measures an animation sets it back for itself. Expected: ButtonKinds and the window
  suites at a few seconds each; Modules (11 s) and Anchors (11 s) the floor.
- **Limits**: each suite's limit counted from its own start (with shards, each process
  starts its suites at once), the global 90 s replaced by a per-suite budget (§4.3).

Target: **unit suites ≤ 15 s** wall (Arch, 32 threads), ≤ 25 s on a 6-core machine.

### 3.2 `run-all.sh`: independent parts side by side

All parts but the lock bed are headless-isolated or pure scripts. `run-all.sh` starts them
together (at most `-j` at once, each its own process group and log, as now), prints each
part's output in order when it ends, and the summary is unchanged. The lock bed still runs
last, alone. Then `--quick` ≈ the longest part:

- privileged runs fixture 26 s → the queue's timings through module test mode (the
  2 s head, the 3 s "request open", killAfterMs scaled, e.g. ×0.25): ~7 s;
- supervisor self-test 20 s → the launcher's windows already come from `scripts/seams.sh`
  in the test tree **[assumed]**: shorter windows there, the `sleep 3` a condition: ~6 s;
- unit runner self-test 10 s: its stand-ins hang until the runner's limit; a
  `RUN_UNIT_TIMEOUT` for the self-test: ~3 s.

Target: **`--quick` ≤ 30 s** (from 155 s).

### 3.3 The lock bed

- `-j` is capped at 4 since a 6-core machine (`run.sh:82`); on 32 threads that leaves most
  of the machine idle. Default: `min(cores - 1, max(4, cores / 4))` — 8 on this machine,
  still 4 or 5 on the NixOS one — with `LOCKTEST_JOBS` to override. The serial set stays
  serial; `LONG_TESTS` is generated from the last run's times (as `unit-times.txt`).
- The long fixed waits become seams: `methods-fprintd`'s 30 s re-detection pause, the
  restart backoff windows `restart-no-restore` watches for 12 s, the launcher's 30 s
  quick-death window `modules-launcher` lives out (`H2S_LAUNCHER_TEST_TIMINGS` already
  shortens its first pause), the PAM stand-in's timeout in `fingerprint-timeout`. Each
  scenario then lasts as long as its conditions. Not shortenable: Quickshell's 10 s rule
  for restarting in place (`restart-crash-finger`, `restart-crash-locked`) — those two
  start first (`LONG_TESTS`).
- Together these take about 130 s out of the 745 s of scenario time; at `-j 8` the rest
  is ≈ 615 / 8 ≈ 80 s plus the serial `reload-window` (10 s) and the tail.
- Scenarios do not all need the machine alone: the flock stays (other beds' stacks would
  overload it), but the unit and module runners no longer slow it once they take seconds.

Target: **lock bed ≤ 100 s** at `-j 8` here; **full set ≤ 150 s** on Arch.

## 4. Isolation and determinism

### 4.1 Shared state

- A suite runs with fresh singletons: per-process shards (§3.1) give it for the long
  suites; the packed shards of short suites keep a check in `TestCase`: after `run()` /
  `finish()` the runner compares a fingerprint of `Config`'s and `Profiles`' stored values
  and `Modules.host`'s loaded list with the one taken before, and fails the suite that left
  them changed ("left Config.disabledModules changed").
- A suite that throws is ended and its shard's remaining suites still run in a fresh
  process (the runner restarts the shard without it), so one exception does not poison
  others' state.

### 4.2 Conditions, not deadlines

- **A deadline only guards a hang.** A wait is `until condition` with a deadline that is
  generous (≥ 10× the expected time, at least 10 s in the lock bed) and the same for every
  wait of a kind; `check_within 3` becomes `check_within "$SETTLE"` (one constant in
  `lib.sh`, scaled by `LOCKTEST_SLOW=2` on a known slow machine).
- **A time bound is a test of timing**, allowed only where timing is the subject, with
  both bounds read from a seam clock or the stand-in's own record (when it was called),
  never from `Date.now()` around a loaded event loop; such a test goes in `SERIAL` with its
  reason, as `reload-window` does.
- **A fixed `sleep` in a scenario** is allowed only to let a negative claim stand ("nothing
  happened in N s"); each one says so in a comment, and `tests/lock/lint.sh` (a self-test)
  rejects the others.

### 4.3 Budgets instead of one global limit

Each async suite declares its own `timeLimitMs` counted from its own start (or, until
shards land, from the end of the suite it follows — T0); `tests/unit-times.txt` records the
last measured times, and the runner warns (never fails) when a suite took more than twice
its recorded time — a slow drift is seen before it becomes a time-out.

### 4.4 Flaky tests as data

`tests/lock/run.sh` reruns a failed scenario once alone at the end of the run (as it does
for the serial set); passing alone it is reported **FLAKY** (counted, the run still
passes, its log kept) and appended to `${XDG_CACHE_HOME}/h2s-shell-tests/flaky.log` with
the date, the machine's load and the commit. The unit runner does the same per shard. The
tracker's list becomes `tests/flaky-report.sh` (counts per test from that log), and a test
flaky twice in a segment is a slice to fix, not a rerun.

## 5. The two machines: `tests/remote-run.sh`

```
H2S_REMOTE=<ssh destination> tests/remote-run.sh [--full|--quick|<affected range>] [<branch>]
tests/remote-run.sh --status | --fetch | --stop
```

1. Checks the branch is committed; makes `git bundle create <tmp> <base>..<branch>`
   (base: the remote's `master` read with `git ls-remote` over ssh; a full bundle if
   unknown).
2. Copies it with `ssh "$H2S_REMOTE" 'cat > …'`, fetches it into a working tree of its own
   on the remote (`H2S_REMOTE_DIR`, default `~/wt/remote-run`), checks out the exact commit
   detached, and verifies `git rev-parse HEAD` against the local one.
3. Starts the run **detached without nohup**: `setsid -f env --default-signal=HUP
   tests/run-all.sh --keep-going > run.log 2>&1 < /dev/null; echo $? > status` — a new
   session, so the ssh hang-up does not reach it, and SIGHUP back to default so the
   launcher's own SIGHUP tests still see it (§1.6). A `run.pid` and `run.commit` beside the
   log; a second start while one runs refuses.
4. `--wait` (the default) polls `test -f status` over ssh every 15 s (a plain loop in the
   script), then brings back `run.log` to
   `${XDG_CACHE_HOME}/h2s-shell-tests/remote/<branch>-<commit>.log` and prints the summary
   (from `All (` to the end), the tool source and the launcher lines, and the commit.
   Exit status: the remote run's.
5. Interrupted locally, the remote run goes on; `--fetch` collects it later; `--stop`
   ends its process group.

The address is `H2S_REMOTE` (or `--host`), never written in the repository; no
password prompt (ssh `BatchMode=yes`). `tests/remote-run-selftest.sh` runs it with
`H2S_REMOTE_SSH` pointing at a stand-in `ssh` that runs the remote half locally in a
temp directory (the rule: a real I/O path runs against stand-ins).

## 6. Rules for CLAUDE.md

To add under "Development rules", in its style:

- **A deadline in a test only guards a hang.** Waits are on conditions, with one generous
  deadline per kind; an upper time bound is a test of timing, made against a seam clock and
  run alone (`SERIAL`). — "Not within 3 s" failed on loaded machines.
- **Real waits longer than a second come through a seam** in a test (backoffs, pauses,
  grace windows). — 30 s pauses made scenarios minutes long.
- **A suite leaves the shell's singletons as it found them** (the runner checks), or
  declares `ownProcess`. — One suite's writes changed another's verdict.
- **A new check is seen failing once**: break its subject (`tests/mutate.sh`, or by hand),
  watch it fail, put it back. A suite or scenario with no check fails. — Checks that could
  not fail passed review.
- **What a change runs is `tests/affected.sh`'s answer**; a file it cannot place is
  covered (`covers:`) or on its no-tests list. — Choosing suites by memory missed some.

And in "Running": `tests/affected.sh --run` while iterating, `run-all.sh --quick` before a
commit (≤ 30 s), the full set and `tests/remote-run.sh --full` at the end of a segment.

### How a test that cannot fail is caught

1. The verdicts: `0/0 passed` and a scenario without a `PASS` line fail (T1).
2. `tests/mutate.sh <file> [<suite>…]`: in a scratch copy of the tree, applies one
   mechanical mutation at a time to a `*Rules.qml` or a singleton function (`===`↔`!==`,
   `<`↔`<=`, `&&`↔`||`, a `return` of a boolean negated, a constant + 1), runs the suites
   `affected.sh` gives for the file, and lists the mutants no suite noticed. The author of
   a new rule runs it on the rule's file; the end of a segment runs it on the `*Rules.qml`
   files the segment changed. Plain bash and sed; never in the live checkout.
3. For lock scenarios: the XFAIL mechanism already makes a reverted fix visible; a
   scenario's fix commit records once that the scenario failed before it (review).

## 7. Slices, in order

Each is one change with its test; "check" is what proves it.

- **T0 — the two flakes' causes** (being fixed now on the segment branch by another agent;
  described here, not part of this plan's work): the launcher under test started with
  `env --default-signal=HUP` (`tests/launcher-selftest.sh:132`, `spawn` in
  `tests/lock/lib.sh:115`); each chained async suite's limit counted from the end of the
  one before (`tests.qml:97`, `AnchorsTest` `timeLimitMs`). Check: `launcher-selftest.sh`
  and `tests/lock/run.sh supervisor` under `nohup … &` pass on both machines; a stand-in
  delay of 10 s in `ModulesTest` no longer fails FileChooser.
- **T1 — verdicts that catch empty tests**: `headless_verdict` fails a `0/0` suite; the
  bed fails a scenario with no `PASS`. Check: `run-unit-selftest.sh` and the bed's
  self-check gain the two cases.
- **T2 — `tests/affected.sh` and its self-test** (§2), the closure scanner shared with
  `lock-closure.sh`; `covers:` lines on the lock scenarios. Check:
  `affected-selftest.sh` (every tracked file placed, canned ranges), added to `run-all.sh`.
- **T3 — animations off in unit runs**: the runner's profile sets animation speed to the
  maximum; suites measuring an animation set it back. Check: ButtonKinds < 5 s, every
  window suite still passes; `unit-times.txt` shows the drop.
- **T4 — unit shards**: `run-unit.sh -j N`, the shard plan from `unit-times.txt`,
  `ownProcess`, the `after:` chains reduced to real data dependencies, per-suite limits
  from their own start. Check: `run-unit-selftest.sh` cases for a shard that crashes, a
  shard that times out, the exact count across shards; unit run ≤ 15 s here.
- **T5 — `run-all.sh` runs parts side by side** (lock bed last, alone), output per part
  in order; the privileged fixture's and the supervisor self-test's timings through their
  seams. Check: `run-all-selftest.sh` cases for parallel parts (order of output, a failing
  part, an interrupt ends all); `--quick` ≤ 30 s.
- **T6 — the unit flakes**: AnchorsTest layout wait, ModulesTest guard window on a
  condition, window exposure before the first event, the two-sided time bounds in the
  privileged fixture and CommandRunner made one-sided hang guards or seam-timed. Check:
  each suite 20 runs in a row under `stress`-like load (`tests/soak.sh <suite> 20`, which
  this slice adds) without a failure.
- **T7 — lock bed: hang-guard deadlines, seams for the long waits, `-j` by cores, rerun
  alone as FLAKY, `tests/lock/lint.sh`** for fixed sleeps. Check: the bed's time ≤ target,
  `lint.sh` in `run-all.sh`, a scenario made to fail once by a stand-in shows as FLAKY.
- **T8 — state fingerprint in `TestCase`** (§4.1). Check: a fixture suite that leaves
  `Config.disabledModules` changed fails with that message.
- **T9 — `tests/remote-run.sh` and its self-test** (§5). Check: the self-test with the
  stand-in ssh; one real run on the NixOS machine whose summary matches the one made there
  by hand.
- **T10 — `tests/mutate.sh`** (§6). Check: run on `LockRules.qml` and two other Rules
  files; surviving mutants listed in the slice's report and given checks or reasons.
- **T11 — docs and rules**: CLAUDE.md "Running" and "Development rules" (§6),
  `notes/workflow.md` "Tests", `docs/ARCHITECTURE.md` "Testing" (the asynchronous suites,
  shards, `affected.sh`, the remote run), the runners' headers' times. Check:
  `docs-check-selftest.sh`; the numbers in the docs are the measured ones.

Expected after T0–T7: unit suites ≤ 15 s, `--quick` ≤ 30 s, lock bed ≤ 100 s, the full
set ≤ 150 s on Arch; a slice typically runs `affected.sh --run` in seconds plus one
`--quick`.
