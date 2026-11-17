# Test split: a general set and a set per system

A plan for the owner to approve (tracker step 1; implemented in step 10). No code is
changed by it.

The decision it serves: "Tests: one general set independent of the system, plus a set per
system (NixOS, Arch). A developer runs the general set and their system's."

Marks used below: **[read]** — verified by reading the code at `50129d9` (core) and
`13468e9` (module); **[assumed]** — not verified, to be checked in the slice that names it.
Nothing was run for this plan.

## 1. The problem

Every runner sources `tests/lock/resolve.sh`, which **[read]**:

- exits 2 without `nix` ("nix is needed to provide the test tools");
- builds the whole of `tests/lock/tools.nix` and checks all of it (labwc, Hyprland, hyprctl,
  grim, python3, setpriv, xkbcli, dbus-daemon, gdbus, wl-copy, wl-paste, wlr-randr, the
  protocol bindings, the keymaps) — also for the unit suites, which use only labwc and
  setpriv from it;
- exits 2 without an `h2s-shell` launcher on `PATH` (or `LOCKTEST_LAUNCHER`), and asks that
  launcher which `qs` it runs.

On the Arch machine there is no `nix`, no `labwc` and no `h2s-shell` command; Quickshell
and Hyprland are the system's. So nothing runs there. No CI runs tests either
(`.github/workflows/` holds `pages.yml` only) **[read]**.

## 2. Inventory

Classes: **G** general (no system knowledge, tools may come from either source);
**G\*** general, with checks that branch on the system; **N** NixOS only; **D** device;
**M** manual.

### Runners

| Runner | What it runs | Needs today | Really needs | Class |
|---|---|---|---|---|
| `tests/run-unit.sh` (+ `headless.sh`, `count-suites.sh`) | `tests.qml`: 36 suites | nix, full tool set, launcher | Quickshell; labwc (headless Wayland); setpriv, setsid, timeout; sh, grep, sed, sort (two suites run them) | G |
| `tests/run-unit-selftest.sh` | `run-unit.sh`'s verdict against stand-in Quickshells | as above | labwc, setpriv (Quickshell is a stand-in) | G |
| `tests/run-modules.sh <dir>` | `tests-modules.qml`: a module's suites | as above | as `run-unit.sh` | G |
| `tests/lock/run.sh` (+ `lib.sh`, `input/`, `pam/`) | 61 scenarios in `tests/lock/tests/` | nix, full tool set, launcher | see "Lock bed" below | G\* |
| `tests/lock-closure.sh` | called by `ModuleRegistriesTest` | POSIX sh, find, grep, sed | same | G |
| `tests/device/keyboard-popup.sh`, `touchtap.py` | the running shell on a touch device | `nix shell` (python-evdev), `h2s-shell`, `hyprctl`, `/dev/uinput`, oskbd | python with evdev, a launcher, the real session | D |
| `tests/manual/pam-probe.sh` | one real PAM conversation | `qs` on `PATH`; `QT_QPA_PLATFORM=offscreen` | same; real account | M |
| module `tests/run.sh` | 14 suites (`module/module.json` "tests") | delegates to the core's `run-modules.sh`; an own copy of the isolation as fallback | the core's runner | G |
| module `tests/lock-bed/run.sh` | `tests/lock-bed/tests/tailscale.sh` | delegates to the core's `tests/lock/run.sh` (`LOCKTEST_EXTRA_TESTS`) | the core's lock bed | G |
| module `tools/test.sh` | the stand-ins in `tools/stand-in/` | bash, sh, awk, sed, date, sleep | same — runs on Arch today **[assumed]** | G |

### Unit suites (`tests.qml`) **[read]**

| Suites | What they need beyond Quickshell |
|---|---|
| `PointerInputTest`, `LockViewTest` | a real window: a `PanelWindow` with `WlrLayershell` (layer `Overlay`). Events come from QtTest, straight to the Qt window. This is the only reason for a compositor, and it must speak wlr-layer-shell. |
| `ModulesTest`, `ModuleRegistriesTest` | `Process`: `sh`, `head`, `grep`, `sed`, `sort`, `tests/lock-closure.sh`; fixtures in `tests/fixtures/modules`. `ModuleRegistriesTest` builds `SettingsWindow` with `visible: false`. |
| `QuickshellPinTest` | fixture `tests/fixtures/qs-pin`; pins Quickshell's *behaviour* (loading by URL, singletons), not a version. |
| `VersionTest` | reads `CHANGELOG.md` and `singletons/Version.qml`. |
| the other 30 (`*RulesTest`, `FormatTest`, `ThemeTest`, `NetworkTest`, …) | nothing: pure functions. NixOS and Arch text (`/nix/store/…`, `/usr/lib/…`, `nixos: true/false`) is input data, both variants in each suite (`LockIoRulesTest`, `PolkitRulesTest`, `NetworkTest`). |

None of the 36 reads a system file or asks which system it is on. All are **G**.

### Lock bed (`tests/lock/`) **[read]**

| Dependency | Where from today | Why | Either source? |
|---|---|---|---|
| labwc | `tools.nix` | parent compositor: Hyprland cannot run on the headless backend alone (`tests/lock/README.md`) | yes |
| Hyprland, hyprctl | `tools.nix`, pinned to "the system's" | the compositor under test; a `NOTE` when the pin and the system's differ | yes — the system's is the one meant |
| grim, wlr-randr, wl-copy/wl-paste, dbus-daemon, gdbus, xkbcli, setpriv | `tools.nix` | screenshots, output size, selection, private bus, keymap questions, no-new-privs | yes |
| python3 with pywayland | `tools.nix` | `input/ltinput.py`, `input/ltwindow.py` | yes |
| `share/ltproto` (bindings) | generated in `tools.nix` from `pkgs.wlroots.src` XML | virtual keyboard and pointer protocols; no package installs that XML | only if the two XML files are in the repository |
| `share/us.xkb`, `share/keymaps/*` | generated in `tools.nix` (`xkbcli compile-keymap`) | layouts the virtual keyboard sends | yes, generated at set-up |
| PAM modules (`pam_exec`, `pam_deny`, `pam_permit`, `pam_stress`) | beside the libpam Quickshell links (`ldd`), or `LOCKTEST_PAM_MODULES` | test stacks | yes; `pam_stress` on Arch **[assumed]** |
| launcher | `h2s-shell` on `PATH` / `LOCKTEST_LAUNCHER`; started as `H2S_SHELL_DIR=<copy> <launcher>` | the shell is started as in real use, from the run's copy | NixOS: the package. Arch: none exists — `scripts/launch.sh` ignores `H2S_SHELL_DIR` |
| Quickshell | asked of the launcher, or `LOCKTEST_QS` | — | yes |
| `systemd-inhibit --list` | system | reads the real inhibitor list (read only) | both |

Scenarios: 60 of 61 have no system knowledge. `tests/lock/tests/methods-script.sh` branches
on `/etc/NIXOS` in three places (as `scripts/lock-auth-methods.sh` does): on each system
only that system's branch runs. The Arch branch ("the shipped one") has never run
**[assumed]**: all runs so far were on the NixOS machine.

### What does not exist

No test of `install.sh` (tracker 11.23), of `nix/package.nix`, `nix/module.nix` or
`flake.nix`, of the device set on Arch. Nothing is Arch-only today.

## 3. Target design

### The sets

| Set | Contents | Command | Tools |
|---|---|---|---|
| general, quick | unit suites, the runners' self-tests; for module work the module's suites and `tools/test.sh` | `tests/run-unit.sh`, `tests/run-unit-selftest.sh`; module: `tests/run.sh`, `tools/test.sh` | Quickshell, labwc, util-linux, coreutils |
| general, lock bed | the 61 scenarios; the module's lock-bed test | `tests/lock/run.sh`; module: `tests/lock-bed/run.sh` | the lock bed's list above |
| NixOS | checks of `flake.nix`, `nix/`, NixOS's file layout | `tests/run-system.sh` on NixOS | `nix` |
| Arch | checks of `install.sh`, Arch's file layout | `tests/run-system.sh` on Arch | `pacman` (read only) |
| device, manual | as today | as today | — |

"General" means: the test's verdict does not depend on which system it runs on, and it
takes its tools by the one lookup below. It does not mean "needs nothing".

Layout of the system sets: `tests/system/nixos/<name>.sh` and `tests/system/arch/<name>.sh`,
one check file each, written like a lock-bed test (`check <description> <command…>`,
PASS/FAIL lines). `tests/run-system.sh [name…]` detects the system (`/etc/NIXOS`; else
`ID`/`ID_LIKE` in `/etc/os-release` naming `arch`) and runs that directory. On any other
system, or when a name is not in this system's directory, it exits 2 and says which system
it found — it never prints a pass for a set it did not run.

Before committing, on either system: the general quick set; the lock bed when the change
touches what it covers; `tests/run-system.sh`. A last slice adds `tests/run-all.sh` for
exactly that. The lead's run before a merge is the same, lock bed always included.

### Tool lookup

One source for a whole run, not tool by tool:

1. `H2S_TEST_TOOLS=nix` or `=system` — an explicit choice;
2. else `nix`, when a `nix` command exists — the pinned `tests/lock/tools.nix`, as today;
3. else `system` — every tool from `PATH`.

Per-item overrides stay as they are: `LOCKTEST_QS`, `LOCKTEST_LAUNCHER`,
`LOCKTEST_PAM_MODULES`.

Why per run: the tools depend on each other (python and pywayland, Hyprland and hyprctl,
labwc and wlr-randr); a mix of pinned and system parts is a third configuration nobody
tests. Why `nix` first when present: it keeps today's behaviour on NixOS unchanged and
gives the same answer on an Arch machine that has `nix`.

Each runner asks only for what it uses: `resolve.sh` takes a need, `unit` (labwc, setpriv,
setsid, timeout) or `lock` (the full list). With `system`, the lock bed's generated parts
are made at set-up in the run's temp dir: the bindings with pywayland's scanner from two
protocol files kept in `tests/lock/protocols/` (and `tools.nix` reads the same two files),
the keymaps with `xkbcli compile-keymap`.

Quickshell is never pinned by the tests (as today). Order: `LOCKTEST_QS`; the launcher
(`LOCKTEST_LAUNCHER`, else `h2s-shell` on `PATH`), asked as today; else `qs`, then
`quickshell`, on `PATH`. The lock bed needs a launcher that honours `H2S_SHELL_DIR`; where
none is found it uses `tests/lock/launcher.sh`, which only runs
`$H2S_SHELL_DIR/scripts/launch.sh` — the way the shell is started on Arch.

Every run prints what it took, before any test (the versions here are examples):

```
tools: system (PATH) — labwc 0.8.4, Hyprland 0.57.1
quickshell: /usr/bin/qs 0.3.2 (PATH)
```

Versions are printed, not checked: no version requirement is known today, and a check
nobody can justify would be noise. The Hyprland `NOTE` (pinned differs from the system's)
stays for the `nix` source.

### A missing tool

A set-up error: exit 2, before any test, one line per missing tool, all of them at once,
each naming the tool and its use — for example
`run-unit.sh: labwc not found on PATH (the headless compositor the suites' windows open in)`.
No install command lines. No fallback, no skipped suite: a run either has everything or
does not start. The uses are one table in `resolve.sh`.

### The pinned guarantees

- `QuickshellPinTest` stays in the general set, so it runs on each system against the
  Quickshell that system's shell runs — where a Quickshell upgrade lands first.
- `tools.nix` stays the pinned reference ("a run today and a run in a month use the same
  compositor") for every machine with `nix`. A `system` run says so in its first line, so a
  report shows which it was.
- `tests/run-unit-selftest.sh` keeps guarding the verdict (crash, partial, complete) on
  both sources.

### The module repository

Its runners delegate to the core's and so get the lookup for free. The own harness in the
module's `tests/run.sh` (a second copy of the isolation, with `tests/harness.qml`) is
removed: the core has `tests/run-modules.sh` **[read]**, and the copy would need every
change twice. `tools/test.sh` stays as it is. The module has no system set; a
`tests/system/` there follows the core's layout if one is needed.

## 4. System tests that should exist

Candidates only. "Cheap" = a shell check file, seconds, no new tool.

General (they need no system, though they are about one):

- `install.sh` against stand-in `pacman`, `sudo`, `git`, `fc-list` in a private `HOME`: the
  package list handed over, the clone target, "already installed", "another config" (exit
  1), no pacman (exit 1). Cheap; `install.sh` reads `/dev/tty`, which a headless run lacks —
  the script needs a small change first.
- Both branches of the system detection in `scripts/lock-auth-methods.sh` on both systems,
  through a seam beside `H2S_LOCK_SYSTEM_PAM_DIR`. Cheap; a product change (a test seam).
- A first start in an empty `HOME` prints no warning (11.23: `Config` chmods
  `config.json` before it exists). Cheap, in the lock bed.

NixOS:

- The package builds; its launcher honours `H2S_SHELL_DIR`; its version is
  `singletons/Version.qml`'s; `tests/lock`, `notes`, `docs` are not in it. Cheap once the
  inputs are in the store.
- Every program in the shared command list (below) resolves on the launcher's `PATH`. Cheap.
- `nix/module.nix` evaluates in a minimal system and yields the three
  `h2s-shell-*` PAM services. Medium: an evaluation, no VM.
- The NixOS module text the shell offers for the VPN lockdown
  (`NetworkRules.lockdownNixosModule`) parses as Nix. Cheap.
- The layout the code assumes: `/etc/NIXOS`, a readable `/etc/pam.d/login`,
  `/etc/static/polkit-1/rules.d`, `/run/current-system/sw/bin`. Cheap; read only.
- A NixOS VM test of the module with a real PAM stack. Expensive; later.

Arch:

- Every name in `install.sh`'s `packages` exists in the sync database (`pacman -Si`, read
  only). Cheap.
- Every program in the shared command list resolves on `PATH`. Cheap. (The list — `nmcli`,
  `bluetoothctl`, `python3`, `notify-send`, `jq`, `gsettings`, `gdbus`, `cava`, `git`,
  `xdg-open`, `vipsthumbnail`, `flock`, `setsid`, `timeout` — is one file, read by both
  system sets, so `install.sh` and `nix/package.nix` cannot drift apart unnoticed.)
- Each module the shipped `pam/password`, `pam/fingerprint`, `pam/u2f` name is found where
  the system's libpam looks, or is one the README calls optional. Cheap; read only.
- `install.sh` in a clean Arch container. Expensive (a container runtime, the network);
  before publishing.

## 5. Delivery slices (step 10)

Each is one change with its test. "Both" = run on the NixOS machine and on the Arch machine.

1. **The unit suites run without nix.** `tests/lock/resolve.sh`: the source choice, needs
   (`unit` / `lock`), Quickshell from `PATH` as the last resort, the printed lines, the
   missing-tool errors. With it `tests/run-modules.sh` and the module's `tests/run.sh` run
   on Arch too. `notes/workflow.md` ("Needs") and `CLAUDE.md` ("Running", "Environment")
   updated in the same change.
   Test: a new `tests/resolve-selftest.sh` — `resolve.sh` against fabricated `PATH`s of
   stand-in executables (a `nix` that prints a made-up store path; none; one without
   labwc): the source taken, the lines printed, exit 2 naming each missing tool. It starts
   no compositor.
   Verified — both: `resolve-selftest.sh`, `run-unit.sh`, `run-unit-selftest.sh`.
   Lead checks: NixOS — the line says `nix`, 36 suites report, timing as before; Arch —
   the line says `system`, 36 suites report; with labwc taken off `PATH`, exit 2 and the
   labwc line.
2. **The module's own harness goes** (module repository): `tests/run.sh` only delegates;
   `tests/harness.qml` deleted. Test: `tests/run.sh` reports its 14 suites — both. Lead
   checks: a core tree without `run-modules.sh` gives exit 2 with a reason.
3. **The lock bed's tools from the system.** The two protocol files in
   `tests/lock/protocols/` (their licence checked **[assumed]** permissive), bindings and
   keymaps generated at set-up for `system`, `tools.nix` reading the same files,
   `tests/lock/launcher.sh`. Test: `resolve-selftest.sh` cases for the `lock` need and the
   launcher fallback; `tests/lock/run.sh harness harness-orphan` — both. Lead checks: on
   NixOS the `tools.nix` output still holds every entry `resolve.sh` lists.
4. **The whole lock bed on Arch.** No runner change expected; each scenario that fails on
   Arch only is reported to the lead as a finding (a difference in Hyprland's version, in
   PAM, in a path), then fixed in the test or the shell one at a time. Verified: the full
   `tests/lock/run.sh` and the module's `tests/lock-bed/run.sh` — both. Lead checks: the
   two summaries name the same 61 (+1) tests.
5. **System detection behind a seam** in `scripts/lock-auth-methods.sh` (and the shell's
   own probe in `singletons/Lockscreen.qml`); `methods-script.sh` runs both branches
   everywhere. Verified: `tests/lock/run.sh methods-script fallback` — both; the check
   count is the same on both.
6. **`tests/run-system.sh`** with the layout and the first cheap check of each set
   (NixOS: the package and its launcher; Arch: the package names). Test: a self-test of the
   detection against fabricated `os-release` files, and of exit 2 for an unknown system and
   a foreign name. Verified — both: the self-test; each system: its own set. Lead checks:
   on each machine the other system's check name gives exit 2.
7. **`install.sh` under stand-ins** (general; closes the first half of 11.23) — both.
8. **The remaining cheap system checks** of section 4, one per change.
9. **`tests/run-all.sh`**, and the rule in `CLAUDE.md` and both `notes/workflow.md` tables
   reduced to it. Verified — both.

Later, outside step 10: the device set's python from the same lookup; the expensive
candidates.

## 6. Assumptions to check

| Assumption | Checked in |
|---|---|
| labwc, python-pywayland, grim, wlr-randr, wl-clipboard are packages in Arch's official repositories | before slice 1 (labwc), slice 3 |
| Arch's util-linux and coreutils give `setpriv --no-new-privs`, `setsid --wait`, `timeout -k` as used | slice 1 |
| pywayland's scanner is usable from the installed python package | slice 3 |
| `pam_exec.so` and `pam_stress.so` are in Arch's PAM module directory | slice 3 |
| the lock bed's generated Hyprland config works with the Arch machine's Hyprland | slice 4 |
| a `PanelWindow` cannot be created under `QT_QPA_PLATFORM=offscreen` (question 2) | not planned; ten minutes if the owner wants it known |

## 7. Open questions for the owner

1. **Are un-pinned system tools acceptable for the general set** on a machine without
   `nix`? Recommended: yes. The versions are printed; the pinned run on a machine with
   `nix` stays the reference; before a release the general set passes on both systems.
2. **Is labwc a required development dependency on Arch?** The unit suites need a
   compositor only for two suites' layer-shell windows; `QT_QPA_PLATFORM=offscreen` starts
   a windowless Quickshell (`tests/manual/pam-probe.sh` does it) and might do for the other
   34. Recommended: require labwc (and, for the lock bed, the tools of section 2), named in
   the developer documentation, never installed by `install.sh`. An offscreen mode would be
   a second way to run with a second verdict, and the lock bed needs labwc anyway.
3. **What does the `tools.nix` pin follow?** Today its comment ties it to one machine's
   system revision, which the development rules now exclude. Recommended: the pin is "the
   Hyprland version the tests are known to pass with", moved on purpose when either system
   moves ahead; the `NOTE` stays as information.
4. **Is the lock bed part of every commit's run?** About five minutes. Recommended: the
   author runs it when the change touches the lock screen, the launcher, module loading or
   `scripts/`; the lead runs it before every merge.
5. **An `h2s-shell` command on Arch** (`install.sh`)? The tests do not need one with
   `tests/lock/launcher.sh`; `notes/workflow.md`'s deploy steps and the device tests assume
   it. Recommended: decide it with 11.23, outside this plan.
6. **The expensive tests** (an Arch container install, a NixOS VM): wanted now?
   Recommended: no; before publishing the package.
