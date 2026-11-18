# Test seams: a gate, or a test tree

**Status (2026-11-18):** the owner chose Option 2 (the test tree, no gate), kept the name
`TestSeams` for the production file of constants, and accepted manual use through a test
tree on the condition that test runs are well documented. Built on branch `test-seams`: O1
(production `TestSeams` constants, the reader and `TestSeamRules` in `tests/lock/seams/`,
`TestSeamsShapeTest`, the bed's swap check), O2 (`scripts/seams.sh` and its test version for
`lock-auth-methods.sh` and `launch.sh`), O3 (`moduleTestMode` → `ModuleHost.testMode`, told
in `modules list`), L1 (`LockscreenShapeTest`), O4 (the `locktest` IPC in the test seam
file), O5 (`tests/test-tree.sh`, used by `run.sh` too; `TestTreeTest`; docs in
`tests/lock/README.md` "The test tree" and `docs/ARCHITECTURE.md` "The test tree"). Open:
A3 (module test mode's effects) and O6.

Analysis and a trial of 2026-11-18, against `cafd3ce`.
**Verified** = read in the code or seen in the trial; **assumed** = not tried.

## 1. The problem

The whole-shell test beds (the lock bed above all, and the module's lock bed, which runs
through it) change what the real shell does through environment variables: which `gdbus`
it runs, where it looks for the system's PAM configs, which script tells it the ways to
log in, how long its timers are, whether a reload IPC is on, whether a stand-in VPN
provider is loaded. Since slice A2b every QML read goes through one reader,
`singletons/TestSeams.qml`; two scripts (`lock-auth-methods.sh`, `launch.sh`) read theirs
directly. The installed shell honours all of them in any session.

That is not an attack surface: whoever sets the shell's environment can already run code as
the user (`LD_PRELOAD`). It is an accident surface. A variable left in a terminal or in the
systemd user environment, inherited by a shell restarted from there, would silently change
the lock screen's authentication (`H2S_LOCK_AUTH_METHODS` names any program that answers
"use this PAM directory"; `H2S_LOCK_SYSTEM_PAM_DIR` names any directory of configs). The
planned answer (decision 7.5, option a) is a gate. The owner asks whether something more
solid exists.

## 2. Every seam today, and where it goes (verified, `grep` of the tree)

| Seam | Read by | Option 1 | Option 2 |
|---|---|---|---|
| `H2S_LOCK_TOOLS` (stand-in `gdbus`, `systemd-inhibit`) | TestSeams → Lockscreen (handed to LogindMonitor, SleepInhibitor as `toolDirectory`, kind C); `lock-auth-methods.sh` | behind the gate | test seam file only |
| `H2S_LOCK_SYSTEM_PAM_DIR`, `H2S_LOCK_SYSTEM` | TestSeams → Lockscreen; `lock-auth-methods.sh` | gate | test seam file only |
| `H2S_LOCK_AUTH_METHODS` (another methods script) | `lock-auth-methods.sh` | gate | test `seams.sh` only |
| `H2S_LOCK_LEDS_DIR` | TestSeams → CapsLockLed | gate | test seam file only |
| `H2S_LOCK_TEST_TIMINGS` | TestSeams → Lockscreen | gate | test seam file only |
| `H2S_LOCK_TEST_RELOAD` (IPC `locktest`) | TestSeams → Lockscreen's `IpcHandler` | gate | the handler moves into the test seam file |
| `H2S_SHELL_TEST_MODULE_GUARD_MS` / `_CHECK_PATH` / `_CHECK_MS` | TestSeams → Modules | gate | test seam file only |
| `H2S_FAKE_VPN_PROVIDER` (manual use only) | TestSeams → VpnManager | gate (+ a script that makes the marker) | test seam file; manual use through a test tree |
| `H2S_LAUNCHER_TEST_TIMINGS` | `launch.sh` | gate in bash | test `seams.sh` only |
| `H2S_TAILSCALE_TOOLS`, `H2S_TEST_MODULES` | the Tailscale module itself | → `Api.testMode` (A3) | → `Api.testMode` (A3), from the seam file |

Not seams, and they stay as they are under both options: the launcher's inputs
(`H2S_SHELL_DIR`, `H2S_SHELL_MODULE_PATH`, `H2S_SHELL_MODULE_DATA_DIRS`), the
launcher-to-shell contract (`H2S_SHELL_MODULES`, `_SAFE_MODE`, `_SUPERVISOR`, `_LAUNCHER`),
`XDG_SESSION_ID`, and the inputs of the test entry files, read only by them
(`H2S_TEST_SUITES`, `H2S_TEST_MODULES`, `H2S_TEST_MODULE_SUITES` in `tests.qml`,
`tests-modules.qml`, `tests/TestCase.qml`). Kind A (inspection IPC: `shelltest`,
`settings itemRect`/`currentPage`) changes nothing and stays on.

`tests/device/` (verified): uses only `h2s-shell ipc call shelltest …` (`cellRect`,
`popupItemRect`, `popupState`, all read-only) against the real session. It already is
inspection-IPC only and needs nothing from either option.

## 3. Option 1: the gate (the plan as it stands)

**How.** Seams count only when `H2S_TEST_BED=1` is set and a marker file
`$XDG_RUNTIME_DIR/h2s-test-bed` (the user's, mode 600) exists. The runners create it in
their private runtime directory. `TestSeams` checks both before the lock driver builds; the
two scripts repeat the check in bash; the module learns it from `Api.testMode`.

**Protects against** a single stray variable. Two stray things (the variable and the file in
the real runtime directory, e.g. a developer's `scripts/dev-test-bed.sh` left on) still
switch the real session.

**Cost.** Slices S1, S2 of the cleanup plan (about 3 changes): a synchronous file read at
start (FileView `blockLoading` or `test -O`) in the lock's start path, the same rule written
three times (QML, two bash scripts), marker creation in three runners (`headless.sh`,
`lock/lib.sh`, the module's bed). The switch stays in the installed shell, and the code that
honours the auth-changing seams stays reachable in it.

## 4. Option 2: a test tree with the seam files swapped

**How.** The reader keeps its consumers and loses its switch:

- `singletons/TestSeams.qml` in the tree becomes **constants**: no tools directory,
  `/etc/pam.d`, `/sys/class/leds`, no timings, no reload IPC, no module overrides, no
  stand-in provider, `moduleTestMode: false`, `inForce: []`. No `Quickshell.env` at all.
- `tests/lock/seams/TestSeams.qml` is today's reader (env → values, via `TestSeamRules`,
  which moves next to it), plus the `locktest` `IpcHandler`.
- The scripts source `scripts/seams.sh` (constants: `/etc/pam.d`, plain `gdbus`, no
  methods override, the launcher's normal pauses); `tests/lock/seams/seams.sh` reads the
  variables as the scripts do today.
- The lock bed **already** runs every test from a copy of the checkout
  (`tests/lock/run.sh` 284–320, 399: one template, `cp -a` per test, about 20–30 ms, with
  `tests/lock` removed and `pam/` replaced by deny-all configs; verified). It adds two
  `cp` lines: the two test seam files over the production ones in the template. It starts
  that copy as today, through `h2s-shell`/`launcher.sh` with `H2S_SHELL_DIR`.
- `tests/lock/` is not in the Nix package (`nix/package.nix` fileset; verified). On Arch the
  install is a git checkout, so the files lie on disk, but nothing loads them unless copied
  over `singletons/` — which only a test tree does.

**Protects against** every stray variable, however many: the installed shell and any
developer checkout read none of them. The lock screen's authentication paths in the
installed code are constants an auditor can read. Test behaviour needs a tree that was
assembled as one, and those live in the bed's temp directories. No start-time check, no
marker, no rule written three times.

**What it does not change, honestly.** The packaged launcher honours `H2S_SHELL_DIR`
(verified), which runs any tree and so grants more than all seams together. That is the
documented development path and stays; Option 2 relies on it rather than removing it. A
stray `H2S_SHELL_DIR` pointing at a deleted bed copy fails loudly (no shell), never
silently changes authentication. Neither option protects against an attacker.

**Risks and their guards.**
- *The two seam files drift apart* (a property in one only → `undefined`). Guard: a unit
  case that reads both files as text and compares their property names, and checks the
  production one has no `Quickshell.env`.
- *A consumer reads a variable directly again.* Guard: a unit case (grep of the tree outside
  `tests/`) that no production file names an `H2S_LOCK_*`, `H2S_*TEST*` or
  `H2S_FAKE_*` variable except in comments.
- *The swap silently missing in the bed.* Guard: the bed checks `testSeams` in the lock
  screen's `state` is non-empty at stack start (it is `[]` in the production file).
- *Lock screen reload carry-over (R5.2).* Swapping a singleton changes no child of
  `Lockscreen`. Moving the `locktest` handler out of it does shift `CapsLockLed` and
  `_helperSweepOnce` one position: that slice waits for L1, exactly as S2 does today.
- *`tests/launcher-selftest.sh`* runs the checkout's `launch.sh` directly with
  `H2S_LAUNCHER_TEST_TIMINGS`: it must run a copy of `scripts/` with the test `seams.sh`
  (it already builds a modified copy for its control run; verified).
- *Lock closure check.* `tests/lock-closure.sh` does not follow singletons used by name; the
  test seam file imports only `Quickshell`, `Quickshell.Io`, `QtQuick` and nothing of the
  module system, as the reader does today (verified by reading).

**Cost.** About 5 small slices (§7), touching `TestSeams.qml`, two scripts, `run.sh`, the
launcher self-test, one new unit suite; consumers (Lockscreen, CapsLockLed, Modules,
VpnManager) do not change at all, since A2b already routed them through the reader.

**What the trial showed (verified, Quickshell 0.3.2, headless labwc as `tests/headless.sh`
runs it, never on the screen).** A probe root file importing `qs.singletons` and
`qs.singletons.lock`, printing `TestSeams` and a `CapsLockLed`'s `directory` (which reads
`TestSeams` from another directory):

| Tree | Assembly | Swap seen | `Quickshell.shellDir` |
|---|---|---|---|
| full copy (as the bed makes it) | 29 ms | yes, also from `singletons/lock/` | the copy |
| every file a symlink, swapped file real | 175 ms | yes | the farm, not the real tree |
| top directories symlinked, `singletons/` files symlinked | 52 ms | yes | the farm |
| root `.qml` itself a symlink | — | yes | the copy |
| control: `singletons/` a symlink to the real one | 9 ms | no (production values) | — |

Quickshell does not canonicalise symlinks back to the real tree, and its per-directory
registration takes the file in the assembled directory. Every probe start took 470–480 ms
whatever the assembly: no start cost from copying. A QML module under `tests/lock/seams/`
imports fine as `qs.tests.lock.seams` (so the unit suite can still reach `TestSeamRules`
there). Symlinks are nevertheless **not** usable for the lock bed: tests edit their copy on
purpose (`edit-while-locked`, `reload-*`), which through a symlink would write into the
checkout; and `launch.sh` finds its tree by `readlink -f "$0"`, so a symlinked
`scripts/launch.sh` would run the real tree. Copies it is — which is what the bed does now.
Not tried: the Nix package itself (no `nix` on this machine; its fileset was read), and a
`Quickshell.reload()` called from an `IpcHandler` inside a singleton (assumed to work as
from `Lockscreen`, which is a singleton too).

## 5. Options considered and rejected

- **One "system tools" layer wrapping every program the shell runs, real and test
  implementations.** Only the lock's `gdbus`/`systemd-inhibit` and the module check's PATH
  are swapped by any test; `nmcli`, `bluetoothctl` and the rest are not stand-ins anywhere
  (the bed cuts the bus off instead). Wrapping them all is a large change for nothing tested.
  The right size is Option 2's seam file. Where `gdbus` comes from in production (today:
  plain `gdbus` on PATH; later: the trusted lookup, `CommandTools`/`ModuleRules.programVerdict`)
  is a property of that file, a separate later slice (§7, O6) — the lock closure must
  allow what it imports.
- **A separate entry file** (a test root that sets the seams, then loads the shell). The
  qs module root is the root file's directory, so it must sit at the tree's top (shipped);
  it cannot replace a singleton, only set properties on one, and singletons such as
  `Lockscreen` are built while the root's children are created, before its
  `onCompleted` — the order is not ours. And `launch.sh` would need an option to start
  another root: a new switch.
- **Injection through a settable object or IPC** (`Seams.configure(…)`, `ipc call testbed
  set`). Any QML in the process — modules included — or any process of the user could call
  it at run time: more exposed than the environment. QML has no access control to stop it.
- **Mount namespaces** (`unshare --user --mount`, binding stand-ins over `/etc/pam.d`,
  `/sys/class/leds`). Available here (verified: `unshare --user --map-current-user --mount`
  works), and it would remove the directory seams from the code entirely. But timings,
  the reload IPC and the module overrides still need a file, nested Hyprland inside a user
  namespace is untried, and it adds a kernel setting both systems must allow. Worth
  revisiting only if the PAM directory seam itself should go; not now.
- **Kind C injection for the whole shell.** Stays the shape for suites that build their
  objects (`ModuleHost` properties, `tests-modules.qml`), but the bed does not build
  `Lockscreen`; it cannot reach it this way.

## 6. Recommendation

**Option 2.** It removes the switch from the installed shell instead of guarding it, costs
about the same number of slices as the gate, needs no start-time check on the lock path,
keeps one rule in one place per language, and fits what the bed already does: it runs a
copy of the tree with `pam/` swapped; it would swap two more files. The trial found no
loading problem. Decision 7.5 would change from (a) to "test tree".

Module test mode (A3) fits it directly: `ModuleHost.testMode` is set in process by
`tests-modules.qml` (kind C, needs nothing from this design); in the lock bed `Modules` sets
it from `TestSeams.moduleTestMode`, `true` only in the test seam file. `Api.testMode` reads
it. The Tailscale module then drops its own `H2S_TAILSCALE_TOOLS`/`H2S_TEST_MODULES` reads
for `testPrograms` — no marker contract between the repositories is needed.

## 7. Slices for Option 2

Each is one change with its test; the lock bed stays green after each.

| # | Slice | Files | Test |
|---|---|---|---|
| O1 | The QML seam file swapped: production `TestSeams` becomes constants; today's reader and `TestSeamRules` move to `tests/lock/seams/`; `run.sh` copies the test file into its template; the bed checks `testSeams` is non-empty at stack start | `singletons/TestSeams.qml`, `tests/lock/seams/TestSeams.qml`, `…/TestSeamRules.qml`, `tests/TestSeamRulesTest.qml` (import), `tests/lock/run.sh`, `tests/lock/lib.sh` | new `TestSeamsShapeTest` (same property names, no `Quickshell.env` in production, no production file names a seam variable); lock bed full run |
| O2 | The scripts' seams: `scripts/seams.sh` (constants) sourced by `lock-auth-methods.sh` and `launch.sh`; `tests/lock/seams/seams.sh` reads the variables; the bed and `launcher-selftest.sh` use it | the two scripts, `scripts/seams.sh`, `tests/lock/seams/seams.sh`, `run.sh`, `launcher-selftest.sh` | shape case extended to the scripts; launcher self-test; lock bed `fallback`, `methods-*`, `harness*`, `supervisor`, `restart-*`, `modules-discovery` |
| O3 | `moduleTestMode` in both seam files and `Modules` → `ModuleHost` (the property only, `false` in production) | both seam files, `Modules.qml` | shape case; lock bed `modules` |
| A3 | Module test mode (commands.md §3.3), unchanged in scope; needs O3 for the lock bed path only, nothing for `tests-modules.qml` | as in commands.md | `ModulesTest` cases of §3.3 |
| O4 | The `locktest` reload IPC moves into the test seam file (needs **L1**, the child-order test; L1's list updated) | `Lockscreen.qml`, test seam file, L1's suite | lock bed `reload-*`, full run |
| O5 | Manual test tree: `tests/test-tree.sh <dest>` makes a copy with the test seam files, for running by hand (e.g. the stand-in VPN provider) through `H2S_SHELL_DIR` in a nested compositor; docs (ARCHITECTURE "Testing", both systems) | new script, `docs/ARCHITECTURE.md`, `tests/FakeVpnProvider.qml` header | a self-test of the script (the copy has the test files, the checkout is untouched) |
| O6 | (later, separate) The lock's `gdbus`/`systemd-inhibit` in production from the trusted lookup, named by the seam file; only if the lock closure may import it | `TestSeams.qml`, `Lockscreen.qml`, `lock-closure.sh` | unit; lock bed full run, NixOS and Arch |

The cleanup plan's S1/S2 (the gate) are replaced by O1–O4; S3 (gathering kind A IPC into
`TestIpc.qml`) and S4 (the module behind `Api.testMode`) stay. `tests/device/` needs no
slice.

## 8. For the owner

1. Option 1 (gate) or Option 2 (test tree)? Recommended: 2.
2. Under Option 2, manual use of test behaviour (the stand-in VPN provider) needs a test
   tree started by hand (O5) instead of exporting a variable. Acceptable?
3. Keep the name `TestSeams` for the production file of constants (smallest diff, says what
   the file is about), or rename (`SystemSeams`)?
