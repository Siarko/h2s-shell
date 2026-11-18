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
tests/lock/run.sh -j 3                # at most 3 tests at a time (LOCKTEST_JOBS=3 too)
tests/lock/run.sh -j 1                # one after another, output as it comes
LOCKTEST_EXTRA_TESTS=<dir> tests/lock/run.sh <name>   # a test from another directory (a module's repository)
```

Exit status 0 when every test passed or failed exactly as expected, 1 when one failed (or
a test marked as failing passed; a test whose stack does not come up counts as failed),
2 when the test bed could not be set up before any test ran (tools, launcher, paths),
130 when interrupted. A full run takes about three minutes with the default four tests at
a time, about fifteen one after another (each test starts its own stack, in
2–3 s; the idle tests wait out real idle timeouts, the crash tests Quickshell's 10 s before
it restarts a crash in place; the launcher's restart pauses are shortened where a test only
needs their schedule, `--launcher-timings`).

**One run at a time on a machine.** The tests depend on timing, and a run starts as many
at once as the machine keeps on schedule; a second run beside it would have both fail for
no fault of the shell. So `run.sh` takes a lock itself — `flock` on
`/tmp/h2s-locktest.flock`, held from its start to its end — and while another run has it,
prints one line and waits. A caller that wraps the run in `flock /tmp/h2s-locktest.flock …`
hands its lock on, and the run does not wait for it. That holds only when the run gets the
wrapper's open file: with `flock -o`, or a wrapper between `flock` and `run.sh` that closes
the descriptors it was given, the run waits for its own caller for ever. Two runs started
under one outer `flock` both find its lock and do not exclude each other. If the lock file
is removed while a run holds it, the next run makes and locks a new file and runs beside
the first: do not remove it. The file is readable for everybody, so that the users of one
machine share it. Only `run.sh` itself holds the lock — not the tests' processes, nor the
programs of its set-up — so nothing a run leaves behind keeps the next one waiting. The
unit, module and self-test runners take no lock; they do take the processor, so a failure
of this bed seen while they were running on a small machine is run again alone before it
is believed.

Ctrl-C (or SIGTERM/SIGHUP) stops the running tests and their stacks, sweeps, removes the
runtime and artifacts dirs (kept with `LOCKTEST_KEEP=1`) and exits 130.

**Several at a time.** `-j N` (or `LOCKTEST_JOBS`) runs at most N tests at once; the default
is one fewer than the cores, at most 4 (with 5 stacks on 6 cores the launcher's restart
tests no longer keep to their schedule). Each test has its own stack, runtime dir,
artifacts dir, copy of the shell and marker (`LOCKTEST_TEST_ID`, beside the run's
`LOCKTEST_RUN_ID`): what a test looks for among processes (`run_processes`, `test_pgrep`,
the checks before a signal) is its own, and the sweep after a test kills only what carries
its marker, never a sibling's. Each test's output is printed as one block when it ends,
with a line as each starts; the summary is in the usual order. The longest tests start
first (`LONG_TESTS` in `run.sh`), and the tests in `SERIAL` — those whose subject is a
timing a loaded machine cannot keep, each with its reason — run alone after the others.
`-j 1` is the old way: one after another, the output as it comes.

It needs its tools ("Tools", below): the pinned set `nix` builds where there is a `nix`
command, else the system's, from `PATH`. And a launcher: `LOCKTEST_LAUNCHER`, else the
`h2s-shell` on `PATH`, else the test bed's own `launcher.sh`. The first lines of a run say
what was taken; a missing tool ends it with status 2, named with its use. Nothing
privileged: no root, no seat, no GPU device, no real input device.

## What runs

```
labwc        headless (wlroots' headless backend): only gives the nested compositor a
│            GPU allocator — Hyprland 0.57 cannot run on the headless backend alone,
│            and sway does not work as the parent; its output pinned to 1920x1080
│            (wlr-randr; the headless default is 1280x720)
└─ Hyprland  nested in labwc (Aquamarine's Wayland backend), Lua config written per run;
   │         its output, the window in labwc, set to 1920x1080 at runtime (the config's
   │         rule does not take at start) and checked: OUTPUT_WIDTH × OUTPUT_HEIGHT, the
   │         one size the tests' pointer coordinates are measured in (move_pointer)
   ├─ input/ltinput.py   one virtual keyboard + one virtual pointer, alive for the whole
   │                     test, fed commands through a FIFO; the keymap is the test's
   ├─ input/ltwindow.py  (stack_start --window) a solid magenta window: the desktop the
   │                     lock must hide
   ├─ dbus-daemon        (stack_start --session-bus) a private session bus, no activation
   └─ the launcher       `H2S_SHELL_DIR=<the run's copy> h2s-shell` (or launcher.sh), a plain
      │                  start: the copy's scripts/launch.sh, which stays as the shell's supervisor
      └─ the shell       its child, in a process group of its own; started again by the
                         launcher when it dies (SUPERVISOR_PID / SHELL_PID in lib.sh)
```

All of it runs with no new privileges (`setpriv --no-new-privs`, inherited by every
child).

`lib.sh` holds the helpers, `tests/*.sh` the tests, `pam/` the test PAM stacks and the
scripts they run (templates: `@...@` is filled in per run), `tools.nix` the pinned tools,
`resolve.sh` the lookup of the tools, the launcher and Quickshell, `protocols/` the two
protocol files the input bindings are generated from, `launcher.sh` the launcher for a
machine without an `h2s-shell` command, `run.sh` the runner.

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
  locks and hold up the real machine's sleep. With a bogus address both fail at start (and are
  tried again after a growing pause); `harness.sh` checks that no such helper stays running
  (the same process still there a second later) and that no process of the run
  holds an inhibitor on the real logind, and `run.sh` checks that again after every test
  (before the sweep). The real list is only read, and an inhibitor is told to be the
  run's by its PID carrying the run's marker — not by its name, which the real shell's
  inhibitor shares.
- **No new privileges** for every process of a test (`setpriv --no-new-privs`): the variables above are ignored by setuid programs, so `pkexec` (which
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
  folder (and a reload while locked used to unlock); so `run.sh` copies the checkout once per run
  into the artifacts dir (`shell/`: everything but `tests/lock`, `.git` and `result*`),
  and that again for each test (`shells/<test>`, a few MB, some 20 ms), which the test's shell
  runs from: tests that run side by side never see each other's edits. Edits to the checkout during a run cannot disturb it;
  `run.sh` notes them, as the results are for the copy taken at the start. (The shell itself
  no longer reloads while locked — file watching is off then — and `reload-while-locked.sh`
  and `edit-while-locked.sh` check that; a reload asked for while locked keeps the lock,
  `reload-explicit.sh`; the copy guards the rest of a run. Tests that edit the copy on
  purpose — `edit-while-locked`, `reload-while-locked`, `reload-window`,
  `restart-locked-retry` — write only their own.) In the copy, `pam/` is replaced by
  configs that only deny: the shipped `pam/password` (`pam_unix`, the real account) is one
  of the configs the shell's password fallback can be, and a typed test string must never
  reach the real password check. And the copy is a *test tree*: the test seam files take
  the production ones' place, so that the copy — and only the copy — reads the seams below
  from its environment ("The test tree"). Logs and screenshots go
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
  test `run.sh` kills anything still carrying that test's marker variable
  (`LOCKTEST_TEST_ID`) in its environment, and at the end of the run and when interrupted
  anything carrying the run's (`LOCKTEST_RUN_ID`, which every test's processes carry too) —
  which catches what left its group, such as a
  shell helper re-parented to a subreaper. Not the scripts `pam_exec` runs: they get
  PAM's environment only, without the marker. Those are stopped with the shell's process
  group and, when their PAM helper dies, by their own orphan check (`wait-finger.sh`).
- **No session variables leak in**: `run.sh` starts each test with an empty environment
  and a list of what to keep of the caller's — `PATH`, `TMPDIR`, `USER`, `LOGNAME`, `TZ`,
  `LOCALE_ARCHIVE`, `XDG_DATA_DIRS`, and the two settings for a test
  (`LOCKTEST_QT_LOGGING`, `LOCKTEST_PROCESS_TIMEOUT`) — so no display, bus, seat, agent
  socket or toolkit setting of the session reaches the shell under test (`harness.sh`
  checks a few). `lib.sh` unsets the session's variables by name as well (`WAYLAND_DISPLAY`,
  `WAYLAND_SOCKET`, `DISPLAY`, Hyprland's and sway's sockets, `PIPEWIRE_REMOTE`,
  `PIPEWIRE_RUNTIME_DIR`, `PULSE_SERVER`, the session id, the activation tokens, the input
  method variables, `LC_ALL`/`LC_CTYPE`), should the list ever grow, and sets `LANG` to
  `en_US.UTF-8` — the locale picks the Compose table the dead-key and Compose tests rely on.
- **No core files.** Tests that crash the shell on purpose (`restart-crash-locked`,
  `restart-crash-finger`, `modules`) would each leave a core of Quickshell where the system
  keeps them, outside the run's directories; the run's processes have a core size limit of
  0, so none is written. What remains, where crashes go to `systemd-coredump`: a journal
  entry per crash (`coredumpctl list` shows them, with no core file).
- **A private session bus only when asked** (`stack_start --session-bus`, the notification
  test): a `dbus-daemon` of the test's own, its socket in the private runtime dir, with no
  service directories, so nothing is activated; the real session bus is never named.
- **`HYPRLAND_NO_SD_*`**: the nested Hyprland does not push its environment into the
  user's systemd or notify it.

## The seams: test PAM stacks and logind stand-ins in the real shell

`scripts/lock-auth-methods.sh` says which ways of unlocking exist and with which PAM
config. When `H2S_LOCK_AUTH_METHODS` names an executable, it answers instead, in the same
format. `stack_start --methods "password fingerprint"` writes such a script listing the
test stacks (`password=password-question` names another stack for a method);
`stack_start --methods-script <file>` takes a test's own (a failing one, one naming a
stack that is not there). Unless a test's own script is given, the list must include
`password` (`stack_start` refuses it otherwise).

**The real methods script** runs with `stack_start --fprintd <mode>`: the shell's
`H2S_LOCK_AUTH_METHODS` names a wrapper that unsets the seam and runs the run's copy of
`scripts/lock-auth-methods.sh`. It finds the test's "system-wide" configs
(`H2S_LOCK_SYSTEM_PAM_DIR`: the password one as below, the test fingerprint stack as
`h2s-shell-fingerprint`) and asks fprintd through the `gdbus` stand-in (`H2S_LOCK_TOOLS`;
`--fprintd` implies `--logind`), which hands fprintd's calls to `standins/gdbus-fprintd`: it
answers as fprintd would in the mode in `fprintd/mode` — `enrolled`, `none`, `second`,
`nodevice`, `absent`, `hang`, `denied`, `nobus`, `malformed-devices`, `malformed-fingers`,
`warning` (a GLib warning on stderr, good replies), `gdbus-timeout` (gdbus's own "Timeout
was reached"), `vanished` (the reader gone between the two calls), `multiline` (an error of
two lines);
`fprintd_mode <mode>` changes it during a test — and notes each call in `fprintd/log`.
`methods-script.sh` runs the script alone against the same stand-in (no stack), and as
both kinds of system on every machine: `H2S_LOCK_SYSTEM=nixos|other` is the script's seam
for which system it is on, honoured only together with `H2S_LOCK_SYSTEM_PAM_DIR` (the shell
honours it the same way where it asks the machine itself, below).

**The password fallback** (used when the methods script fails or names no password, and for
the next attempt after a password config that cannot be used) is chosen by the shell from
the machine: `<system dir>/h2s-shell-password` when readable, else `login` on NixOS, else
the shipped `pam/password`. On this machine the real `/etc/pam.d` may well hold a readable
`h2s-shell-password`, and it is NixOS: either would send typed test strings to the real
account. So the shell is started with `H2S_LOCK_SYSTEM_PAM_DIR=$WORK/system-pam` (the seam;
the methods script honours it too), a directory of the test's own holding a stand-in
`h2s-shell-password` that denies everything — or, with `stack_start
--system-password-stack`, the test password stack (`fallback.sh`). `login` is never there,
so a NixOS fallback without the file is a config PAM cannot start.

`lock_by_ipc` waits until the shell reports a test stack as its password config, and has
looked for its fallback, and aborts the test if not; `type_text` checks again before every
string that BOTH the config in use and the fallback are safe (`_password_stack_is_safe`): a
test stack; the test's stand-in system-wide config (the test stack, or checked line by line
to deny everything); a config under the test's directory that does not exist (PAM cannot
start it); or the run's copy of the shipped config, checked to deny everything
(`lock_by_ipc --any-safe-config` accepts all of those for the config in use). Were the seam
lost, the fallback would be a real `/etc/pam.d` config, and nothing would be typed. So a
typed string can only ever reach a test stack or nothing.

- **password** (`pam/password`, `pam/check-password.sh`): accepts exactly
  `LOCKTEST_PASSWORD` (in `lib.sh`), through `pam_exec` with `expose_authtok`. Each run
  of the script appends `right` or `wrong` (never what was typed) to `pam/check.log`, so
  a test can tell a rejected password from a script that never ran
  (`wrong-password.sh` does). While the file `pam/slow` exists, each check first notes
  `waiting` and waits for `pam/release` (consumed; 30 s at most) — a verification a test
  can act during (`busy-submit.sh`).
- **password-question** (`pam/password-question`, `pam/check-answer.sh`): the password as
  above, then a second question (libpam's own `pam_stress` asks "STRESS Password:" with
  the answer hidden and stores the answer as the auth token), checked against
  `LOCKTEST_ANSWER` (`answer-right` / `answer-wrong` in `pam/check.log`).
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
  run two. Nobody answering, a round fails after 120 s; with `finger_timeout <seconds>` it
  ends after that long in PAM's Error instead, as pam_fprintd's own time-out does
  (PAM_AUTHINFO_UNAVAIL): the round leaves `timedout.<helper pid>`, and the stack's second
  line (`pam/finger-error.sh`, `[success=ignore default=die]`) then fails, so the stack
  returns its PAM_SYSTEM_ERR, which Quickshell reports as Error (`fingerprint-timeout.sh`).

PAM modules are taken from the libpam Quickshell links (a module must match the library
that loads it), by absolute path. Scripts run by `pam_exec` get no PATH. The stacks have
the shape `[success=1 default=ignore] pam_exec` / `requisite pam_deny` /
`required pam_permit`: `pam_exec` failing on its own is a system error, which the shell
reports as "not available" rather than a wrong password.

**logind** cannot reach the shell here: the system bus is cut off. `H2S_LOCK_TOOLS`, when
set, names a directory whose `gdbus` and `systemd-inhibit` the shell runs instead of the
ones on PATH (`singletons/Lockscreen.qml`; PATH itself cannot serve, the launcher puts
the real gdbus first). Unset — always, outside the test bed — nothing changes.
`stack_start --logind` writes the stand-ins and starts the shell with them and
`XDG_SESSION_ID=lt1`: the `gdbus` stand-in answers the session lookup and, as
`gdbus monitor`, prints every line `logind_signal lock|unlock|unlock-other|sleep|wake`
appends to `logind/signals` (`logind_signals lock unlock …` appends several in one write,
so that the shell handles them in one pass — an Unlock before the compositor can have
confirmed the Lock, `fast-unlock.sh`); the `systemd-inhibit` stand-in records `hold <pid>` and
`release <pid>` in `logind/log`, each with its time (`inhibitor_held`, `inhibitor_record`; it
runs the shell's command, so it sees the inhibitor's grace after its holder vanished, as
the real one would hold logind). Between `logind_signal sleep` and `wake` it refuses, as
logind's `Inhibit()` does while the sleep is under way (systemd's `logind-dbus.c`,
`method_inhibit`: "already running"): it records `refuse <pid>`, prints systemd-inhibit's
error and exits 1 without running the command — so a test cannot credit a new generation
with an inhibitor logind would not have given it (`reload-window`). The `gdbus` stand-in's monitor prints gdbus's own first
lines ("The name org.freedesktop.login1 is owned by …": the shell then asks whether a sleep
is under way), and it answers the `PreparingForSleep` property from `logind/preparing`,
which `logind_signal sleep` / `wake` set to true / false. Without a logind seam the shell's
monitor never gets that far (no bus) and asks nothing. No bus is reached
by either (nor by the fprintd stand-in, above).

**Caps Lock** is read from the keyboards' LEDs (`/sys/class/leds/*::capslock`); the nested
compositor has no keyboard, and the machine's real LED is not the test's. So every shell
runs with `H2S_LOCK_LEDS_DIR=$WORK/leds`, empty (Caps Lock unknown, no indicator) until a
test writes one: `caps_led 1|0|none` (`caps-keypad.sh`).

**Timings**: `stack_start --timings '<json>'` hands the shell `LockRules.timings` overrides
(`H2S_LOCK_TEST_TIMINGS`), so that what takes minutes — five rounds that time out — runs in
seconds (`fingerprint-timeout.sh`). Unset, the shell keeps its own.

## The test tree

The installed shell and a checkout read none of the seams above: `singletons/TestSeams.qml`,
through which the lock screen, the Caps Lock reader, the module host and the VPN manager
get them, holds constants, and so does `scripts/seams.sh`, which the methods script and the
launcher source. `run.sh` copies `seams/TestSeams.qml` (the reader of the variables) and
`seams/TestSeamRules.qml` (what each says) over the first in the run's copy, and
`seams/seams.sh` over the second, and
`stack_start` checks that the shell under test names the seams in force in its lock state
(`state_field test_seams`), so a copy without the swap fails at once instead of running
with the real tools and `/etc/pam.d`. `TestSeamsShapeTest` (a unit suite) checks that the
two `TestSeams.qml` have the same properties, the two `seams.sh` the same variables, and
that no file of the shell reads a seam itself.

## Reading the shell's state

- `shell_ipc lockscreen status` — the shell's word (`locked` / `unlocked`);
- `state_field <fact>` / `state_is <fact> <value>` on `ipc call lockscreen state`, a
  read-only JSON: the rules' `LockRules.describe(state)` (no secret, nothing typed, nothing
  that times keystrokes: no prompt deadline, timers by name only) plus the driver's own
  facts under `driver` (the compositor's `secure`, the surfaces, the logind session, the
  inhibitor, file watching, whether the password fallback is known). Tests ask for facts by
  name — `secure`, `locked`, `armed`, `prompt_awake`, `password_config`,
  `password_fallback`, `unlocking`, `watch_files`, `error`, `fingerprint_waiting`, … — and the
  one table in `lib.sh` (`state_field`) knows where each lives in the JSON; a name not in
  it is read as a dotted path (`phase.lastEnd`);
- `compositor_locked` — `hyprctl -j locked` in the nested instance, the ground truth;
- `pam/check-detail.log` (`password_details`) — what bytes the password stack received;
- `screenshot <name>` and `screenshot_ppm <name>` (grim), `reddish_pixels <name>` (red in
  the prompt's area: it depends on the built-in theme's error colour being a clear red)
  and `prompt_region_changes <a> <b>` (pixels that differ in the prompt's area between
  two PPM screenshots);
- the logs in the artifacts dir: `shell.log` (the shell's `[Lockscreen]` lines: every
  event, effect and decision about authentication, nothing typed), `hyprland.log`,
  `labwc.log`, `input.log`, `finger/log` (each fingerprint conversation: start, answer,
  orphaned, timeout), `pam/check.log` (each password check's verdict), `logind/log` (the
  stand-ins').

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

`stack_start` takes, beside the methods: `--no-lock-restore` (the nested Hyprland with
`misc:allow_session_lock_restore` off, its default), `--no-hyprland-ipc` (the shell without
`HYPRLAND_INSTANCE_SIGNATURE`: it cannot ask Hyprland about its lock), `--reload-seam` (the
test tree's `locktest reload <hard>` IPC, in `seams/TestSeams.qml`: `shell_ipc locktest
reload false` asks for `Quickshell.reload()`), `--hyprland-debug` (Hyprland's debug log in `hyprland.log`: what it
did with the lock and its surfaces), `--keymap us|us-intl|us-compose` (the layout the
virtual keyboard sends: plain US, US international with dead keys and AltGr, US with a
Compose key on the right Alt — compiled with the tool set; the keyboard works out which key and
modifiers type each character from the keymap itself, with `xkbcli how-to-type`, and a
character no key gives directly is fatal), `--settings '<json>'` (the shell's settings, as
the shell stores them: `write_settings` writes a config.json whose one profile sets these
keys — short idle timeouts, a notification detail), `--session-bus` (with `notify <app>
<summary> <body>` and `notification_server_up`), `--window` (the magenta stand-in), `--timings '<json>'` (the shell's timing overrides, above). A test
may set `LOCKTEST_PASSWORD` before `stack_start` (a password with é in it; no `| & \ $ \` "
'`). `password_details` lists, per check, the length in bytes and the SHA-256 of what the
password stack received (`pam/check-detail.log`, never the text), and `password_detail_of
<text>` gives the line a text would give; `screenshot_output_ppm <output> <name>` takes one
output.

Restarts (Stage 4): the launcher supervises the shell, so `SHELL_PID` changes when it is
started again — `wait_for_new_shell <old pid> <seconds>` waits for the new one and sets it.
`signal_shell <SIG>` signals the shell and `supervisor_release` tells the launcher to let it
go (SIGUSR1: it is not started again), each only after checking the pid is the run's shell
or launcher (`assert_shell_process`, `assert_supervisor_process`: the run's marker, the
binary or the copy's launch.sh, the private runtime dir) — a wrong pid could be a process
of the real session. `supervisor_environment <pid>` reads the launcher's environment into
`environment`, for a test that starts another launcher as the first was started
(`--restart`), and refuses one that does not name the private runtime dir: `--restart`
stops the shells it finds there. `start_launcher` starts a launcher (and shell) again, as `stack_start`
did. `start_lock_watch <name>` / `stop_lock_watch` poll `hyprctl -j locked` every 50 ms
across a gap, `lock_watch_never_unlocked` says no poll saw it unlocked. `marker_file_is
<locked|unlocked>` reads the lock marker on disk; `protocol_errors` / `no_protocol_errors`
look for a protocol error or a killed client in both logs. `launcher_ipc <target> <function>` calls the shell
the way the owner's keybind does (`h2s-shell ipc call …`: the launcher's `ipc`, which tries a
call again while the shell reloads). `stack_start --launcher-timings "first=0.2 slow=2
lockwait=5"` shortens the launcher's pauses (`H2S_LAUNCHER_TEST_TIMINGS`: the first pause,
the slow retry while locked, how long a second launcher waits for the lock; seconds), and
`--shell-path <dir>` puts a directory of stand-in programs first on the shell's PATH (a
`hyprctl` that hangs: `restart-hyprctl-hang`). `--modules <list>` sets the launcher's
`H2S_SHELL_MODULE_PATH` (its input: module directories or directories of modules;
`tests/fixtures/modules` holds the fixture modules, `modules`), `--data-dirs <list>` its
`H2S_SHELL_MODULE_DATA_DIRS` (the data dirs it searches for `h2s-shell/modules/*`,
`modules-launcher`). Unset, no data dir is searched: a module installed system-wide is not
seen by the test shells, which keep the caller's `XDG_DATA_DIRS` for icons and fonts. Their
data home is the run's own. `--launcher-timings "discoveryhang=60"` makes every module search
hang (`modules-discovery`: the launcher's 3 s bound). `--shell-env NAME=value` adds a variable
to the launcher's (so the shell's) environment: `modules-hung` gives the shell's module file
check a `head` that hangs (`H2S_SHELL_TEST_MODULE_CHECK_PATH`) and a 15 s deadline
(`H2S_SHELL_TEST_MODULE_CHECK_MS`). The launcher's own log is
`$RUN/h2s-shell-launcher.log`; its lines also go to `shell.log`, as do the shell's, stamped
(`--log-times`). `scripts/lock-log.sh` is run against the test shell in `lock-log`.

`check <description> <command…>` and `check_within <seconds> <description> <command…>`
print PASS or FAIL and count; `abort` ends the test for a setup failure (`FAIL (setup)`);
the test fails if any check failed. `check_within` re-runs its command, but its arguments
were expanded once: to wait on something that changes, pass a function (`no_finger_waiters`,
`lines_more_than <count> <regex> <file>`), never `test "$(…)"`. Input: `type_text`, `press_key
<keysym>` (any keysym of the stack's keymap: `Return`, `BackSpace`, `Escape`, `Tab`,
`dead_acute`, `Multi_key`, `KP_1`, `KP_Enter`, `Caps_Lock`, `Num_Lock`, …), `keys_text`
(the keys for a text with Caps Lock off, whatever the locks are), `hold_key <keysym>
<seconds>` (auto-repeat), `move_pointer x y` (pixels of the 1920x1080 output),
`send_input "abs x y w h" "click left|middle|right"`, `wake_prompt`; `caps_led`,
`finger_timeout` (above). `type_text` refuses while Caps
Lock is on (the text typed would not be the one asked for). Input goes through
a FIFO to `input/ltinput.py`; a client that has died, or does not read within 5 s, aborts
the test with its last words from `input.log`, and so does a character it cannot type
(it refuses the whole string rather than type a different one). Its acknowledgement
means the compositor has the input, not that the shell has handled it. Escape never unlocks
(it did until 2026-11-15): a test whose subject is not how the lock ends gets out with
`unlock_for_test` — logind's Unlock through the stand-in when the stack has one (`--logind`,
`--fprintd`), else the test password (one more "right" in `pam/check.log`) — or simply ends
locked: stopping the stack ends the lock.

A test that fails with today's code on purpose — a red test for a coming fix — goes in
`EXPECTED_TO_FAIL` at the top of `run.sh`, with the reason, and the checks expected to
fail in `EXPECTED_FAILING_CHECKS` beside it (descriptions as printed after `FAIL `,
without `(not within N s)`). It shows as XFAIL only when it ran to its end — no setup
failure, no time-out — and the checks that failed are some of those, at least one; any
other failure is a FAIL. Once it passes it shows as XPASS and fails the run until the
mark is removed.

## Artifacts

A temp dir (`$TMPDIR` or `/tmp`, `h2s-locktest.XXXXXX`): the copy of the checkout
(`shell/`), each test's copy of that (`shells/<test>`, removed when the test ends unless
`LOCKTEST_KEEP=1`) and one subdirectory per test: logs, screenshots, the generated PAM
stacks, the private HOME. `$TMPDIR` must be a plain path (letters, digits, `._/+-`): its path
goes into PAM stacks. Printed and kept when a
test failed or with `LOCKTEST_KEEP=1`, removed otherwise. An expected failure alone does
not keep it.

## Tools

The set, in one layout (`LOCKTEST_TOOLS`): `bin/` — labwc, Hyprland and hyprctl, grim,
setpriv, a Python with pywayland, xkbcli, dbus-daemon, gdbus, wl-copy and wl-paste (the
primary selection a middle click would paste, set inside the nested compositor while
locked: `paste.sh`), wlr-randr (labwc's output size); `share/ltproto` — the Python bindings
of the virtual keyboard, virtual pointer and xdg-shell protocols; `share/us.xkb` and
`share/keymaps/` — the keymaps (us, us-intl, us-compose). `setsid` and `timeout` are always
the ones on `PATH`.

`resolve.sh` takes the whole set from one source for a run, never tool by tool (the tools
depend on each other, and a mix of pinned and system parts is a configuration nobody
tests):

- **`nix`** — when a `nix` command exists, or with `H2S_TEST_TOOLS=nix`: `tools.nix` builds
  the set from one pinned nixpkgs, so a run today and a run in a month use the same
  compositor. The pin is the nixos-unstable revision the owner's system takes Hyprland
  from, so the test bed runs the same Hyprland as the real session (the repo's flake pins
  nixos-26.05, whose Hyprland is older); move it when the system's Hyprland moves — a run
  prints a NOTE when the versions differ (both binaries asked `--version` only). It is
  fetched with `fetchTarball` and a hash, which needs no experimental Nix feature.
  Asking nix takes seconds at every start, so the store path it gave is remembered: a file
  in `${XDG_CACHE_HOME:-$HOME/.cache}/h2s-shell-tests/`, named after a hash of `tools.nix`,
  every file it names with a relative path, and the system. The path is taken from there
  only while it exists and holds every part the run needs; otherwise nix is asked and the
  file rewritten. The `tools:` line says "remembered from an earlier run" then;
  `H2S_TEST_TOOLS_CACHE=0` asks nix whatever is remembered.
- **`system`** — without `nix`, or with `H2S_TEST_TOOLS=system`: every program is the one on
  `PATH`, in whatever version is installed, and `run.sh` has the rest made for the run, in
  its artifacts dir (`tools/`; `make_system_tools` in `resolve.sh`): `bin/` links to those
  programs, the bindings come from pywayland's scanner (`python3 -m pywayland.scanner`, as
  `tools.nix` runs it), the keymaps from `xkbcli compile-keymap` with the options
  `tools.nix` gives it — both started with an empty environment and a home of the run's
  own, since an XKB configuration in the user's home would change a keymap. It takes,
  beside the programs above: `pkg-config` (the scanner asks it for the core protocol, and
  `resolve.sh` for the two files below), `wayland.xml` where `pkg-config` says
  `wayland-scanner` keeps its data, and `xdg-shell.xml` where it says `wayland-protocols` does. The
  `python3` is the first on `PATH`, and it must be able to import `pywayland`: a `python3`
  of the user's own before the system's (a version manager's) will not have it.

The virtual keyboard and pointer protocols are installed by no package as XML (wlroots
implements them from its source tree), so `protocols/` holds the two files, unchanged from
wlroots (`protocol/virtual-keyboard-unstable-v1.xml`,
`protocol/wlr-virtual-pointer-unstable-v1.xml`; each carries its copyright and its MIT
licence text, which stay with it). Both sources generate from this one copy.

The first lines of a run say what it took — versions are printed, not checked:

```
tools: system (PATH, not pinned) — labwc 0.9.1, setpriv 2.42.4, Hyprland 0.57.2
launcher: …/tests/lock/launcher.sh (the test bed's stand-in: no LOCKTEST_LAUNCHER, no h2s-shell on PATH)
quickshell: /usr/bin/qs 0.3.2 (asked of the launcher …/tests/lock/launcher.sh)
```

What is missing ends the run with status 2 before any test: every missing tool at once,
each with its use; nothing is skipped and no other source is tried.
`tests/resolve-selftest.sh` checks all of this against stand-in programs.

**The launcher**, in this order: `LOCKTEST_LAUNCHER`; the `h2s-shell` on `PATH`; the test
bed's `launcher.sh`. The last is for a machine with no `h2s-shell` command, where the shell
is started from a checkout by `scripts/launch.sh`: it does what the packaged launcher does
when `H2S_SHELL_DIR` is set — runs that checkout's `scripts/launch.sh` with its arguments —
and nothing else. So the supervisor, `--restart`, `ipc` and the module search a test meets
are the copy's `scripts/launch.sh` either way. What the stand-in leaves out is what the
package adds: its own Quickshell and the programs the shell calls, put first on `PATH`;
with the stand-in they are the ones already on `PATH`. No test is about that, but none
checks it then either, so a run through the stand-in says so in its second line and in a
NOTE in its summary. Quickshell is never pinned: it is `LOCKTEST_QS`, else the one the
launcher runs (asked of it, "The launcher probe", above).

PAM modules are not in the set: they are the ones beside the libpam Quickshell links
(`LOCKTEST_PAM_MODULES` names another directory) — `pam_exec`, `pam_deny`, `pam_permit`
and `pam_stress`.

## What it cannot simulate

That a dead shell's PAM helper keeps a real fingerprint reader claimed, and that fprintd
releases the claim once the helper is killed: the stand-in reproduces the lingering helper
(`restart-kill-locked`), not fprintd. The real Hyprland config (the owner's); a real
logout (the launcher stops when the compositor's socket is gone — reasoning, not run).
logind itself: that it waits for the delay inhibitors held when PrepareForSleep went out,
up to InhibitDelayMaxSec (the stand-in inhibitor records holds and releases, and refuses a
new one during a sleep; `reload-window` computes when logind would have slept); real fprintd (its claim held for a whole lock with `timeout=-1`) and security keys; a real
keyboard's Caps Lock LED following Caps Lock under Hyprland (the shell reads a file the test
writes); `pam_unix` with the real password (`tests/manual/`); suspend and resume and
the real logind (its signals are delivered by a stand-in, see the seams); real DRM hotplug
and DPMS (outputs can be added and removed with `hyprctl output create headless` /
`remove`); real input devices, and
anything below the Wayland seat (a touchpad dead after hibernation); more than what
Hyprland's virtual devices do (no touch, no tablet).
