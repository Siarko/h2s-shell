# The lock test bed

Runs the real shell, from this checkout, in a compositor nobody can see, and drives its
lock screen as a person would: the screen is locked for real (the compositor says so),
keys are typed and the pointer is moved through the compositor, PAM runs real
conversations — against test PAM stacks, never the system's. Each test starts a fresh
stack and prints a PASS or FAIL line per check.

```
tests/lock/run.sh                     # every test in tests/lock/tests/
tests/lock/run.sh relock harness      # some of them, by file name without .sh
LOCKTEST_KEEP=1 tests/lock/run.sh     # keep logs and screenshots even when all pass
```

Exit status 0 when every test passed or failed as expected, 1 when one failed (or a test
marked as failing passed), 2 when the test bed could not be set up. A full run takes
about a minute (six tests, each starting its own stack in 2–3 s).

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
   └─ the shell          `H2S_SHELL_DIR=<this checkout> h2s-shell`, a plain start
```

`lib.sh` holds the helpers, `tests/*.sh` the tests, `pam/` the test PAM stacks and the
scripts they run (templates: `@...@` is filled in per run), `tools.nix` the pinned tools,
`run.sh` the runner.

## Isolation, and why each measure is there

The owner works in a real Hyprland session on the same machine while this runs. Nothing
here may reach it.

- **A private, short `XDG_RUNTIME_DIR`** (`/tmp/lt.XXXXXX`). Every socket is found
  through it: both compositors', Quickshell's instance registry (`qs ipc`, `qs list`),
  hyprctl's, pipewire's. So a test's `qs ipc` or `hyprctl` cannot address the real shell or
  the real Hyprland even by mistake. Short, because Unix socket paths are limited to 107
  bytes and Hyprland nests its sockets inside it. IPC calls also name the shell by pid.
- **D-Bus addresses that point at nothing.** The shell watches logind for Lock and
  PrepareForSleep (`gdbus monitor --system`) and takes a sleep inhibitor
  (`systemd-inhibit`). With the real bus, the test shell would lock when the real session
  locks and hold up the real machine's sleep. With a bogus address both fail at start;
  `harness.sh` checks that no such helper is running and that the real logind's list of
  `h2s-shell` inhibitors is unchanged, and `run.sh` checks the list again at the end.
- **`LIBSEAT_BACKEND` set to a backend that does not exist, `AQ_DRM_DEVICES` to a path
  that does not exist.** The nested Hyprland cannot open a seat, a DRM device or libinput
  devices, so it cannot take the real screen or read the real keyboard.
- **No uinput.** Input comes from Wayland's virtual keyboard and pointer protocols,
  inside the nested compositor. A uinput device (ydotool, dotool) would type into the real
  session.
- **Private `HOME` and XDG directories** under the artifacts dir: the shell does not read
  or write the user's `~/.config/h2s_shell/config.json`, cache or state.
- **Nothing written into the checkout.** The shell under test runs from it and reloads on
  any file written there (and a reload while locked unlocks). Logs and screenshots go to a
  temp dir; Python is told not to write bytecode. `run.sh` fails the run if any file in
  the checkout changed while it ran, and notes a change to the real config.json.
- **Every process in its own process group under `timeout`**, stopped with its group at
  the end of each test (an EXIT trap); each test under a time limit too; and after each
  test `run.sh` kills anything still carrying the run's marker variable
  (`LOCKTEST_RUN_ID`) in its environment — which catches what left its group, such as a
  PAM helper's orphan.
- **`HYPRLAND_NO_SD_*`**: the nested Hyprland does not push its environment into the
  user's systemd or notify it.

## The seam: test PAM stacks in the real shell

`scripts/lock-auth-methods.sh` says which ways of unlocking exist and with which PAM
config. When `H2S_LOCK_AUTH_METHODS` names an executable, it answers instead, in the same
format. `stack_start --methods "password fingerprint"` writes such a script listing the
test stacks:

- **password** (`pam/password`, `pam/check-password.sh`): accepts exactly
  `LOCKTEST_PASSWORD` (in `lib.sh`), through `pam_exec` with `expose_authtok`.
- **fingerprint** (`pam/fingerprint`, `pam/wait-finger.sh`): a stand-in for the reader. A
  conversation announces itself as `finger/waiting.<pid>` and waits for
  `finger/result.<pid>`; `finger ok` / `finger fail` in a test answers the one waiting
  conversation and waits until it has consumed the answer. Answers are addressed to one
  conversation and used once, and a conversation whose PAM helper was killed
  (Quickshell's `abort()` SIGKILLs it, leaving `pam_exec`'s child behind) notices that it
  was re-parented and ends within 0.1 s — so an orphan can never take an answer meant for
  a later conversation. `tests/harness-orphan.sh` checks this by killing a
  conversation's PAM helper. More than one waiting conversation fails the test: the shell
  should never run two.

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
- `screenshot <name>` (grim) and `reddish_pixels <name>` (red in the prompt's area);
- the logs in the artifacts dir: `shell.log`, `hyprland.log`, `labwc.log`, `input.log`,
  `finger/log` (each fingerprint conversation: start, answer, orphaned, timeout).

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
print PASS or FAIL and count; `abort` ends the test for a setup failure; the test fails
if any check failed. Input: `type_text`, `press_key Return|BackSpace|Escape|Tab|space`,
`move_pointer x y`, `wake_prompt`. Escape unlocks for now (the owner's decision); a test
may use it to get out, and must not count it as authentication.

A test that fails with today's code on purpose — a red test for a coming fix — goes in
`EXPECTED_TO_FAIL` at the top of `run.sh`, with the reason. It then shows as XFAIL; once it
passes it shows as XPASS and fails the run until the mark is removed.

## Artifacts

A temp dir (`$TMPDIR` or `/tmp`, `h2s-locktest.XXXXXX`), one subdirectory per test:
logs, screenshots, the generated PAM stacks, the private HOME. Printed and kept when a
test failed or with `LOCKTEST_KEEP=1`, removed otherwise. An expected failure alone does
not keep it.

## Tools

`tools.nix` builds, from one pinned nixpkgs, labwc, Hyprland and hyprctl, grim, a Python
with pywayland, the Python bindings of the virtual keyboard/pointer protocols and a US
keymap. The pin is the nixos-unstable revision the owner's system takes Hyprland from, so
the test bed runs the same Hyprland as the real session (the repo's flake pins
nixos-26.05, whose Hyprland is older); move it when the system's Hyprland moves. Quickshell
is not pinned here: the shell runs with the one its launcher provides.

## What it cannot simulate

Real fprintd and security keys; `pam_unix` with the real password; suspend and resume and
logind's signals (there is no logind); real DRM hotplug and DPMS (outputs can be added
and removed with `hyprctl output create headless` / `remove`); real input devices, and
anything below the Wayland seat (a touchpad dead after hibernation); more than what
Hyprland's virtual devices do (no touch, no tablet).
