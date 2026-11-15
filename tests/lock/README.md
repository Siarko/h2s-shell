# The lock test bed

Runs the real shell, from a copy of this checkout, in a compositor nobody can see, and
drives its lock screen as a person would: the screen is locked for real (the compositor says so),
keys are typed and the pointer is moved through the compositor, PAM runs real
conversations — against test PAM stacks, never the system's. Each test starts a fresh
stack and prints a PASS or FAIL line per check.

```
tests/lock/run.sh                     # every test in tests/lock/tests/
tests/lock/run.sh relock harness      # some of them, by file name without .sh
LOCKTEST_KEEP=1 tests/lock/run.sh     # keep logs and screenshots even when all pass
```

Exit status 0 when every test passed or failed exactly as expected, 1 when one failed (or
a test marked as failing passed; a test whose stack does not come up counts as failed),
2 when the test bed could not be set up before any test ran (tools, launcher, paths),
130 when interrupted. A full run takes about a minute (six tests, each starting its own
stack in 2–3 s).

Ctrl-C (or SIGTERM/SIGHUP) stops the running test and its stack, sweeps, removes the
runtime and artifacts dirs (kept with `LOCKTEST_KEEP=1`) and exits 130.

It needs `nix` (for the tools), the `h2s-shell` launcher on PATH (the NixOS module puts
it there; `LOCKTEST_LAUNCHER` names another). Nothing privileged: no root, no seat, no
GPU device, no real input device.

## What runs

```
labwc        headless (wlroots' headless backend): only gives the nested compositor a
│            GPU allocator — Hyprland 0.57 cannot run on the headless backend alone,
│            and sway does not work as the parent
└─ Hyprland  nested in labwc (Aquamarine's Wayland backend), Lua config written per run
   ├─ input/ltinput.py   one virtual keyboard + one virtual pointer, alive for the whole
   │                     test, fed commands through a FIFO
   └─ the shell          `H2S_SHELL_DIR=<the run's copy> h2s-shell`, a plain start
```

All of it runs with no new privileges (`setpriv --no-new-privs`, inherited by every
child).

`lib.sh` holds the helpers, `tests/*.sh` the tests, `pam/` the test PAM stacks and the
scripts they run (templates: `@...@` is filled in per run), `tools.nix` the pinned tools,
`run.sh` the runner.

## Isolation, and why each measure is there

The owner works in a real Hyprland session on the same machine while this runs. Nothing
here may reach it.

- **A private, short `XDG_RUNTIME_DIR`** (`/tmp/lt.XXXXXX`, made and removed by `run.sh`
  for each test, so it goes even when a test is killed). Every socket is found
  through it: both compositors', Quickshell's instance registry (`qs ipc`, `qs list`),
  hyprctl's, pipewire's. So a test's `qs ipc` or `hyprctl` cannot address the real shell or
  the real Hyprland even by mistake. Short, because Unix socket paths are limited to 107
  bytes and Hyprland nests its sockets inside it. IPC calls also name the shell by pid.
- **D-Bus addresses that point at nothing.** The shell watches logind for Lock and
  PrepareForSleep (`gdbus monitor --system`) and takes a sleep inhibitor
  (`systemd-inhibit`). With the real bus, the test shell would lock when the real session
  locks and hold up the real machine's sleep. With a bogus address both fail at start;
  `harness.sh` checks that no such helper is running and that no process of the run
  holds an inhibitor on the real logind, and `run.sh` checks that again after every test
  (before the sweep). The real list is only read, and an inhibitor is told to be the
  run's by its PID carrying the run's marker — not by its name, which the real shell's
  inhibitor shares.
- **No new privileges** for every process of a test (`setpriv --no-new-privs`, from
  `tools.nix`): the variables above are ignored by setuid programs, so `pkexec` (which
  the shell runs on some clicks, and `VpnLockdown.qml` at start when its helper is
  installed) would otherwise reach the real polkit and put a password dialog on the real
  screen. With no-new-privs setuid has no effect: `pkexec` and the system's `unix_chkpwd`
  cannot work at all. `harness.sh` checks `NoNewPrivs: 1` for the shell. The processes
  still sit in the user's real logind session and cgroup (moving them would mean asking
  the real systemd).
- **`LIBSEAT_BACKEND` set to a backend that does not exist, `AQ_DRM_DEVICES` to a path
  that does not exist.** The nested Hyprland cannot open a seat, a DRM device or libinput
  devices, so it cannot take the real screen or read the real keyboard.
- **No uinput.** Input comes from Wayland's virtual keyboard and pointer protocols,
  inside the nested compositor. A uinput device (ydotool, dotool) would type into the real
  session.
- **Private `HOME` and XDG directories** under the artifacts dir: the shell does not read
  or write the user's `~/.config/h2s_shell/config.json`, cache or state.
- **The shell runs from a copy.** Quickshell reloads a shell on any file written in its
  folder, and a reload while locked unlocks; so `run.sh` copies the checkout once per run
  into the artifacts dir (`shell/`: everything but `tests/lock`, `.git` and `result*`)
  and the shell runs from there. Edits to the checkout during a run cannot disturb it;
  `run.sh` notes them, as the results are for the copy taken at the start. In the copy,
  `pam/` is replaced by configs that only deny: the shell falls back to `pam/password`
  (`pam_unix`, the real account) when the methods script fails or names no password, and
  a typed test string must never reach the real password check. Logs and screenshots go
  to the temp dir; Python is told not to write bytecode. A change to the real
  config.json is noted.
- **The launcher probe is isolated too.** `run.sh` asks the launcher which `qs` it runs
  by pointing it at a stand-in folder. A launcher that ignored `H2S_SHELL_DIR` would
  start a real shell there, so the probe runs with an empty environment but `PATH`, a
  private `HOME`, an empty runtime dir (no Wayland socket), D-Bus addresses that lead
  nowhere, no new privileges, in its own session, and is killed after 5 s; its answer
  must be one executable path, or setup fails.
- **Every process in its own process group under `timeout`**, stopped with its group at
  the end of each test (an EXIT trap); each test under a time limit too; and after each
  test `run.sh` kills anything still carrying the run's marker variable
  (`LOCKTEST_RUN_ID`) in its environment — which catches what left its group, such as a
  shell helper re-parented to a subreaper. Not the scripts `pam_exec` runs: they get
  PAM's environment only, without the marker. Those are stopped with the shell's process
  group and, when their PAM helper dies, by their own orphan check (`wait-finger.sh`).
- **No session variables leak in**: `WAYLAND_DISPLAY`, `WAYLAND_SOCKET`, `DISPLAY`,
  Hyprland's and sway's sockets, `PIPEWIRE_REMOTE`, `PIPEWIRE_RUNTIME_DIR`,
  `PULSE_SERVER`, the session id and the activation tokens are unset.
- **`HYPRLAND_NO_SD_*`**: the nested Hyprland does not push its environment into the
  user's systemd or notify it.

## The seam: test PAM stacks in the real shell

`scripts/lock-auth-methods.sh` says which ways of unlocking exist and with which PAM
config. When `H2S_LOCK_AUTH_METHODS` names an executable, it answers instead, in the same
format. `stack_start --methods "password fingerprint"` writes such a script listing the
test stacks. The list must include `password` (`stack_start` refuses it otherwise), and
`lock_by_ipc` waits until the shell reports the test stack as its password config, and
aborts the test if it does not; `type_text` checks it again before every string. So a
typed string can only ever reach the test stack.

- **password** (`pam/password`, `pam/check-password.sh`): accepts exactly
  `LOCKTEST_PASSWORD` (in `lib.sh`), through `pam_exec` with `expose_authtok`. Each run
  of the script appends `right` or `wrong` (never what was typed) to `pam/check.log`, so
  a test can tell a rejected password from a script that never ran
  (`wrong-password.sh` does).
- **fingerprint** (`pam/fingerprint`, `pam/wait-finger.sh`): a stand-in for the reader. A
  conversation announces itself as `finger/waiting.<pid>` and waits for
  `finger/result.<pid>`; `finger ok` / `finger fail` in a test answers the one waiting
  conversation and waits until it has consumed the answer. Answers are addressed to one
  conversation and used once, and a conversation whose PAM helper was killed
  (Quickshell's `abort()` SIGKILLs it, leaving `pam_exec`'s child behind) notices that it
  was re-parented and ends within 0.1 s — so an orphan can never take an answer meant for
  a later conversation. It also checks at start that its parent runs Quickshell's binary
  (a helper killed before the script looked would leave a subreaper as the parent), and
  checks the parent again right before taking an answer. `tests/harness-orphan.sh`
  checks this by killing a conversation's PAM helper — only after making sure that the
  process is a child of the shell under test, runs Quickshell's binary and carries the
  run's marker. More than one waiting conversation fails the test: the shell should never
  run two.

PAM modules are taken from the libpam Quickshell links (a module must match the library
that loads it), by absolute path. Scripts run by `pam_exec` get no PATH. The stacks have
the shape `[success=1 default=ignore] pam_exec` / `requisite pam_deny` /
`required pam_permit`: `pam_exec` failing on its own is a system error, which the shell
reports as "not available" rather than a wrong password.

## Reading the shell's state

- `shell_ipc lockscreen status` — the shell's word (`locked` / `unlocked`);
- `state_field <path>` on `ipc call lockscreen state`, a read-only JSON added for this:
  the shell's lock mirror, the WlSessionLock's own property, `secure`, the prompt, and
  LockAuth's state (armed, verifying, error, which PAM configs) — nothing typed;
- `compositor_locked` — `hyprctl -j locked` in the nested instance, the ground truth;
- `screenshot <name>` and `screenshot_ppm <name>` (grim), `reddish_pixels <name>` (red in
  the prompt's area: it depends on the built-in theme's error colour being a clear red)
  and `prompt_region_changes <a> <b>` (pixels that differ in the prompt's area between
  two PPM screenshots);
- the logs in the artifacts dir: `shell.log`, `hyprland.log`, `labwc.log`, `input.log`,
  `finger/log` (each fingerprint conversation: start, answer, orphaned, timeout),
  `pam/check.log` (each password check's verdict).

## Adding a test

A file `tests/<name>.sh`, sourced after `lib.sh` in a fresh bash:

```bash
# What it checks, and why.
stack_start                       # or: stack_start --methods "password fingerprint"
lock_by_ipc
check_within 5 "lock by IPC locks the compositor" compositor_locked
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
```

`check <description> <command…>` and `check_within <seconds> <description> <command…>`
print PASS or FAIL and count; `abort` ends the test for a setup failure (`FAIL (setup)`);
the test fails if any check failed. Input: `type_text`, `press_key
Return|BackSpace|Escape|Tab|space`, `move_pointer x y`, `wake_prompt`. Input goes through
a FIFO to `input/ltinput.py`; a client that has died, or does not read within 5 s, aborts
the test with its last words from `input.log`, and so does a character it cannot type
(it refuses the whole string rather than type a different one). Its acknowledgement
means the compositor has the input, not that the shell has handled it. Escape unlocks for now (the owner's decision); a test
may use it to get out, and must not count it as authentication.

A test that fails with today's code on purpose — a red test for a coming fix — goes in
`EXPECTED_TO_FAIL` at the top of `run.sh`, with the reason, and the checks expected to
fail in `EXPECTED_FAILING_CHECKS` beside it (descriptions as printed after `FAIL `,
without `(not within N s)`). It shows as XFAIL only when it ran to its end — no setup
failure, no time-out — and the checks that failed are some of those, at least one; any
other failure is a FAIL. Once it passes it shows as XPASS and fails the run until the
mark is removed.

## Artifacts

A temp dir (`$TMPDIR` or `/tmp`, `h2s-locktest.XXXXXX`): the copy of the checkout
(`shell/`) and one subdirectory per test: logs, screenshots, the generated PAM stacks,
the private HOME. `$TMPDIR` must be a plain path (letters, digits, `._/+-`): its path
goes into PAM stacks. Printed and kept when a
test failed or with `LOCKTEST_KEEP=1`, removed otherwise. An expected failure alone does
not keep it.

## Tools

`tools.nix` builds, from one pinned nixpkgs, labwc, Hyprland and hyprctl, grim, setpriv,
a Python with pywayland, the Python bindings of the virtual keyboard/pointer protocols
and a US keymap. The pin is the nixos-unstable revision the owner's system takes Hyprland
from, so the test bed runs the same Hyprland as the real session (the repo's flake pins
nixos-26.05, whose Hyprland is older); move it when the system's Hyprland moves —
`run.sh` prints a NOTE when the versions differ (both binaries asked `--version` only).
It is fetched with `fetchTarball` and a hash, which needs no experimental Nix feature. Quickshell
is not pinned here: the shell runs with the one its launcher provides.

## What it cannot simulate

Real fprintd and security keys; `pam_unix` with the real password; suspend and resume and
logind's signals (there is no logind); real DRM hotplug and DPMS (outputs can be added
and removed with `hyprctl output create headless` / `remove`); real input devices, and
anything below the Wayland seat (a touchpad dead after hibernation); more than what
Hyprland's virtual devices do (no touch, no tablet).
