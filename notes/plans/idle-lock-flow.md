# Idle, screensaver, lock and screen-off: design (option C, per-monitor blanking)

The analysis (§1–§5) was read on the Arch machine, 2026-11-21, against `master` 2815bf9:
the code, `~/.config/hypr/hypridle.conf`, `~/.config/hypr/hyprland.lua`,
`~/.config/h2s_shell/config.json`, `systemd-inhibit --list`, `loginctl show-session`, logind's
properties over `busctl`, the user journal. Quickshell 0.3.2, Hyprland 0.57.2, hypridle 0.1.8,
hyprlock 0.9.7. Since then, on the owner's machine: Super+L and hypridle's `lock_cmd` call the
shell's IPC lock, and the Power save profile's test commands are cleared (§6). The owner
decided (§6, two rounds); the design is §7–§18, the one new question §6b. The settings'
mockup:
`~/src/h2s-mockups/idle-settings-planned/` (`shoot.sh` for headless shots, `qs -p` on its
`shell.qml` to open it).

## 1. What is configured

### The shell's settings (`singletons/SettingsSchema.qml:141-185`)

| Key | Default | What it does |
|---|---|---|
| `lockscreen.screensaverEnabled` | false | the black overlay with notifications after idle time |
| `lockscreen.screensaverTimeout` | 300 s | idle seconds before the screensaver |
| `lockscreen.fadeInDuration` / `fadeOutDuration` | 800 / 400 ms | its fades |
| `lockscreen.notificationsOnScreensaver`, `…NotificationDetail` | true, "full" | what it shows |
| `lockscreen.screensaverCommands`, `…StartCommand`, `…EndCommand` | false, "", "" | `sh -c` commands at the start and end of an idle period |
| `lockscreen.lockscreenEnabled` | false | the idle lock |
| `lockscreen.lockscreenTimeout` | 300 s | **counted from the screensaver's start when the screensaver is on, from the last input when it is off** |
| `lockscreen.lockOnSleep` | false | hold a logind sleep delay inhibitor and lock before sleep |
| `lockscreen.notificationsOnLock`, `lockNotificationDetail` | true, "app" | the lock screen's notifications |

There is no screen-off (DPMS) setting and no screen-off code anywhere in the shell
(`grep -ri dpms` finds nothing outside notes).

### This machine

- `~/.config/h2s_shell/config.json`: globals `lockscreen.lockOnSleep: false`. Profile
  "Full" (always): screensaver **off** (timeout 10 s), lock **off** (timeout 5 s). Profile
  "Power save" (`power.onBattery`), layered over it: screensaver **on**, lock **on**, fade in
  2000 ms, notifications on the screensaver by title, and screensaver commands on with
  `notify-send "start"` / `notify-send "back"` (they look like leftovers of a test). So: **on
  AC the shell does nothing at idle; on battery the screensaver comes after 10 s and the lock
  5 s later (15 s from the last input).**
- `hypridle.conf`: `lock_cmd = pidof hyprlock || hyprlock` (runs on logind's Lock signal);
  one listener, 600 s → `hyprctl dispatch dpms disable`, on resume `dpms enable`; no
  `before_sleep_cmd`, no `after_sleep_cmd`.
- `hyprland.lua`: Super+L runs `hyprlock` directly (line 68, `local lockscreen = "hyprlock"`);
  `mouse_move_enables_dpms = true`, `key_press_enables_dpms = true`.
- logind: `HandleLidSwitch=suspend`, `HandleLidSwitchExternalPower` unset (follows it),
  `HandleLidSwitchDocked=ignore`, `InhibitDelayMaxUSec=5 s`, `IdleAction=ignore`,
  `HandlePowerKey=poweroff`.
- `systemd-inhibit --list` (sleep, delay, uid 1000): **hypridle** ("Hypridle wants to delay
  sleep until it's before_sleep handling is done.") and **bitwarden-app** ("Application cleanup
  before suspend"); root: NetworkManager, rtkit, UPower. No `h2s-shell` (lockOnSleep is off).
- `loginctl show-session`: `LockedHint=no`, `IdleHint=no`.
- Journal: hypridle receives Brave's wake lock over D-Bus — "ScreenSaver inhibit: true dbus
  message from /opt/brave-bin/brave … Video Wake Lock" (11:54:30).

## 2. Today's flow, as a timeline

### Idle detection

The shell uses Quickshell's `IdleMonitor` (ext-idle-notify-v1), wrapped in `IdleWatch`
(`singletons/lock/IdleWatch.qml`), which makes a new monitor whenever `enabled` or `timeout`
change (a workaround for `isIdle` sticking false in 0.3.2). `respectInhibitors` is left at its
default (true): Wayland idle-inhibit clients count; D-Bus `org.freedesktop.ScreenSaver` and
logind `idle` inhibitors do not (the shell owns neither). Two monitors and one timer
(`singletons/Lockscreen.qml:950-970`):

- `_screensaverMonitor` — enabled by `screensaverEnabled`, timeout `screensaverTimeout`.
- a Timer of `lockscreenTimeout` running while `lockscreenEnabled && screensaverEnabled &&
  isIdle && !locked` → `lock("idle")`.
- a second IdleWatch, enabled by `lockscreenEnabled && !screensaverEnabled`, timeout
  `lockscreenTimeout` → `lock("idle")`.

### With the screensaver and the lock on (this machine on battery: 10 s + 5 s)

| t | What happens | Where |
|---|---|---|
| 0 | last input | |
| 10 s | `isIdle` true → `_idleChanged(true)` runs the start command (`notify-send "start"` here); `Lockscreen.idle` true; each screen's `ScreensaverSurface` maps (overlay layer, transparent), waits two frames, fades its scrim + notifications in (2 s here) | `Lockscreen.qml:986-994`, `screensaver/ScreensaverSurface.qml:26-55` |
| 10–15 s | input: `isIdle` false → fade out, end command (`notify-send "back"`). A **key** goes to the focused window underneath (the overlay has `keyboardFocus: None`); a **click** lands on the overlay (no input mask) and is swallowed | `ScreensaverSurface.qml:12` |
| 15 s | Timer → `lock("idle")` → `LockRecoveryRules` writes the marker → `lockRequested` → `LockRules._enterLock`: `lockCompositor` (WlSessionLock), `announceLocked` (Profiles' `screen.locked`, file watching off), method detection, a 5 s confirm timer. `Lockscreen.locked` true → the screensaver fades out under the lock surface | `Lockscreen.qml:958-963`, `LockRules.qml:229-243, 309-322` |
| ~15 s | compositor `locked` → `secureStateChanged` → `compositorLocked` → phase `locked`. The lock surface: scrim, notifications; the prompt sleeps after 10 s without input (`timings.prompt`) | `Lockscreen.qml:671-678`, `LockRules.qml:270-290`, `LockStepRules.qml:24` |
| 600 s | **hypridle**, not the shell: `hyprctl dispatch dpms disable`. Input → Hyprland turns the monitors on (`*_enables_dpms`), hypridle's on-resume `dpms enable` | `hypridle.conf` |

While locked the screensaver stays hidden (`_show = idle && !locked`) but the idle commands still
follow idleness (end command at the first input, at the lock prompt too).

### On AC (both off here)

Nothing in the shell reacts to idleness. At 600 s hypridle turns the monitors off. Nothing
locks — the screen stays unlocked behind the dark monitors.

### `loginctl lock-session`

logind emits `Session.Lock` on the session's path. Two listeners act at once:

1. the shell's `LogindMonitor` (`gdbus monitor`) → `LockParseRules.parseLogind`
   (`LockParseRules.qml:47-48`) → `lockRequested(source "logind")` → the same `_enterLock`;
2. hypridle's `lock_cmd` → `hyprlock`.

Both ask Hyprland for an ext-session-lock; Hyprland grants the first and sends `finished` to
the second. If the shell is second, Quickshell's lock gets `finished` → `secureStateChanged`
with secure false → `compositorFinished` → "the compositor refused the lock", the shell's lock
ends (`LockRules.qml:293-305`) and hyprlock is the lock. If hyprlock is second, it is refused.

`loginctl unlock-session` → `Session.Unlock` → `unlockRequested(logind)`, an allowed source
(`LockRules.qml:65, 245-255`): the shell's lock ends. hyprlock (no `unlock_cmd` in hypridle)
does not follow it.

### Super+L

`hyprlock` directly. The shell does not know: `Lockscreen.locked` stays false,
`Profiles.screenLocked` false, the screensaver window is mapped (unseen) at the idle timeout,
and on battery the idle lock fires and is refused by the compositor (a warning in the log).

### Suspend, resume, lid

The lid is logind's (`HandleLidSwitch=suspend`); the shell does not watch it. logind emits
`PrepareForSleep(true)`, waits for delay inhibitors (≤ 5 s), suspends.

- **lockOnSleep off (this machine):** `_prepareForSleep` (`LockRules.qml:988-1012`) locks
  nothing; it only sets the sleep region (`missedResume` 60 s, `minSuspend` 5 s timers) and
  pauses passive methods if already locked. hypridle holds its inhibitor but has no
  `before_sleep_cmd`. **Nothing locks: the machine sleeps and wakes unlocked**, unless it was
  already locked.
- **lockOnSleep on:** the inhibitor (`systemd-inhibit --what=sleep --mode=delay`) is held
  while awake (`LockRules.qml:1184-1194`, `singletons/lock/SleepInhibitor.qml`); on
  `PrepareForSleep(true)` the shell enters the lock and keeps the inhibitor until the
  compositor confirms or `inhibitorFallback` (4 s, `LockStepRules.qml:36`) passes. A
  PrepareForSleep missed during a reload is recovered by asking `PreparingForSleep`
  (`LogindMonitor.qml:166-199`).
- **Resume:** `PrepareForSleep(false)` → `resumed`: methods asked again after `resumeGrace`
  (4 s), `SystemSleep.reportResumed` for modules (`Lockscreen.qml:682-685`). The idle timers
  are Qt timers on the monotonic clock: a screensaver up at the lid close comes back up
  after resume, and an idle-lock Timer that was counting continues where it stopped.

### Screen off

Only hypridle (600 s from the last input, Wayland idle-inhibit, D-Bus ScreenSaver and logind
idle inhibitors respected). The shell has no DPMS of its own, and does not turn the screen
off sooner once locked.

## 3. Defects, races and gaps

Severity: high — the screen is left unlocked or a lock is lost; medium — wrong state or
behaviour the user notices; low — confusing or rare.

1. **The laptop sleeps unlocked at every lid close, and nothing says so** — high (config plus
   a silent notice). lockOnSleep off, hypridle without `before_sleep_cmd`, lid → suspend. The
   sleep notice stays silent because hypridle is a "possible" locker
   (`LockIoRules.qml:412, 543`) and the "unlocked during sleep" notice needs `none`
   (`LockIoRules.qml:591`). This is the tracker's open point "Lock before sleep, the notice".
2. **Two lockers on logind's Lock** — medium. The shell and hypridle's `hyprlock` race for one
   ext-session-lock; which lock screen appears depends on timing. When hyprlock wins, the
   shell believes the session unlocked (point 3's consequences), and `loginctl
   unlock-session` no longer unlocks. The screen is locked either way.
3. **A lock the shell did not take is invisible to it** (Super+L's hyprlock, or point 2) —
   medium. `Lockscreen.locked` false: the `screen.locked` profile fact is wrong, the idle lock
   asks and is refused ("the compositor refused the lock", `LockRules.qml:302`), the sleep
   notice reads and may notify while nobody can see it, and the shell's toasts/HUD carry on.
   Wayland gives a client no way to see another client's session lock; on Hyprland
   `hyprctl -j locked` does (already used, `Lockscreen.qml:895`).
4. **Keys typed at the screensaver reach the app underneath** — medium.
   `WlrLayershell.keyboardFocus: WlrKeyboardFocus.None` (`ScreensaverSurface.qml:12`): the key
   that wakes the screen is typed into the focused window (Enter into a terminal runs the
   line). Clicks, on the other hand, are swallowed by the full-screen overlay. Nothing in the
   lock path is affected (the lock surface takes keys).
5. **The shell and hypridle disagree on what keeps the computer awake** — medium, to verify.
   The shell's IdleMonitor honours Wayland idle-inhibit only; hypridle also honours
   `org.freedesktop.ScreenSaver.Inhibit` (Brave's "Video Wake Lock" arrives that way here,
   journal) and logind `idle` inhibitors. If Brave does not also use the Wayland protocol, a
   video on battery gets the screensaver after 10 s and the lock after 15 s while hypridle
   keeps the monitors on. Check: play a video on battery, watch `lockscreen state`.
6. **A settings change while idle ends the idle period without input** — low-medium.
   IdleWatch remakes its monitor on any `enabled`/`timeout` change (`IdleWatch.qml:28-39`); a
   new ext-idle notification counts from zero, so `isIdle` drops: the screensaver fades out,
   the end command runs (`Lockscreen.qml:990-993`) though nobody came back, the lock Timer
   stops and starts over. Triggers: plugging/unplugging (the Power save profile switches both
   features), battery-level or module-fact profiles, a profile on `screen.locked`.
7. **"Lock after" means two things** — low. From the screensaver's start when it is on, from
   the last input when it is off (`Lockscreen.qml:957-970`). With the defaults (300 + 300) the
   lock comes at 600 s, the very second hypridle's listener turns the monitors off.
8. **No screen-off of its own, none sooner once locked** — gap. The lock surface stays lit
   (scrim plus notifications, static text: OLED) until hypridle's 600 s from the last input;
   a touch of the mouse at the lock relights it for another 600 s. Without hypridle the
   screen never goes off.
9. **The shell's locks are invisible to the system** — medium gap. The shell never calls
   `SetLockedHint` (`LockedHint=no` while locked) and does not go through logind's Lock for
   its idle/IPC locks, nor offers `org.freedesktop.ScreenSaver.GetActive/ActiveChanged`;
   programs that lock themselves when the session locks (password managers: Bitwarden runs
   here, KeePassXC) do not see the shell's lock.
10. **Waking with the screensaver up and lockOnSleep off** — low. The idle-lock Timer paused
    through the suspend (monotonic) and fires its remainder after the wake; until then the
    screensaver is shown over an unlocked session. Gone with lockOnSleep on.
11. **No `after_sleep_cmd` in hypridle** — low. Monitors turned off before a lid close stay
    off after the wake until the first input (Hyprland's `*_enables_dpms` then handles it);
    hypridle's documented example uses `after_sleep_cmd = hyprctl dispatch dpms on`.
12. **Observation:** the Power save profile's screensaver commands are `notify-send "start"` /
    `"back"`: each idle period on battery sends two notifications, which show on the
    screensaver and the lock screen.

## 4. "Another program locks before sleep": how it decides, and whether it can be generic

### Today: a hard-coded list plus one generic heuristic

`singletons/lock/SleepLockers.qml:136-153` reads logind's `ListInhibitors` (and `id -u`) once
30 s after the start and every 15 min (`SleepLockNotice.qml:79-96`). `LockIoRules.sleepLockers`
(`LockIoRules.qml:529-554`) keeps sleep delay inhibitors of this uid, not `h2s-shell`, then:

- name in `possibleSleepLockerNames` = `["hypridle", "swayidle", "xss-lock"]`
  (`LockIoRules.qml:412`) → **possible** (says nothing);
- name in `sleepLockerNames` = light-locker, xfce4-screensaver, cinnamon-screensaver,
  mate-screensaver, "gnome shell", "screen locker" (KDE), xscreensaver, xsecurelock, hyprlock,
  swaylock (`LockIoRules.qml:407-409`), **or** a reason matching `/\block/i` and
  `/\b(screen|session)\b/i` (`LockIoRules.qml:545`) → **present**;
- else **none**.

`sleepLockNotice` (`LockIoRules.qml:581-602`): present + lockOnSleep on → "Two programs lock";
none + lockOnSleep off → "stays unlocked". So it is **not agnostic**: two name lists decide,
with a reason-text heuristic as the only generic part.

### What can be known without naming programs

| Source | What it says | Generic? | Limits |
|---|---|---|---|
| logind `ListInhibitors` (`What=sleep`, `Mode=delay`, who, why, uid, pid) | something of this user wants to act before sleep | yes | not *what* it does: hypridle holds one here with no `before_sleep_cmd`, bitwarden-app holds one for its own clean-up. Generic = "something may act", never "something locks" |
| the reason text | free text | yes | a heuristic; most lockers' reasons say nothing usable ("Hypridle wants to delay sleep…") |
| `LockedHint` | set by lockers that call `SetLockedHint` (GNOME, KDE) | yes | swaylock, hyprlock, the shell itself do not set it: absent ≠ unlocked |
| `Session.Lock` signal | someone asked logind to lock | yes | a request, not a lock; nothing tells who answered it |
| the session lock itself | whether the compositor holds a lock | **no generic protocol**: ext-session-lock shows other clients nothing | Hyprland: `hyprctl -j locked` (a compositor, not a locker, is named); else only LockedHint |
| the outcome at past sleeps | whether the screen was locked when the machine went down | yes, given the lock-state source above | needs at least one sleep; needs a moment before the freeze to look |

### A generic version: observe the outcome, not the program

At each `PrepareForSleep(true)`, look at whether the session is locked — the shell's own lock,
`hyprctl -j locked` on Hyprland, else `LockedHint` — and once more shortly after (a locker
may need a second); record "went down locked / unlocked / unknown". After a sleep that went
down unlocked, tell the user once: "The last sleep left the screen unlocked." With lockOnSleep
on and another lock present at the same moment (only the shell's own being refused shows it),
the "two lockers" case.

To have that moment, the shell must be awake between PrepareForSleep and the freeze. Without
an inhibitor of its own it is only racing the other holders (here NetworkManager, UPower,
hypridle, bitwarden: usually tens of ms; nothing guarantees it). A sound version holds a short
delay inhibitor whatever lockOnSleep says and releases it as soon as it has looked (≤ ~1 s,
at once when already locked) — a change in behaviour: an `h2s-shell` inhibitor would then
always appear in `systemd-inhibit --list`.

What it would report wrongly:

- before the first sleep it knows nothing (the "possible" case today is the same);
- a locker that locks after the look but before the freeze reads as "unlocked" (a false
  alarm), and one that locks only at resume reads as "unlocked" (true: the contents were in
  RAM unlocked, and visible at the wake for a moment);
- off Hyprland, a locker that does not set `LockedHint` reads as unknown — nothing said;
- a sleep while already locked by idle says nothing about the next lid close: only sleeps
  from an unlocked session count;
- it cannot predict, only report after the fact.

Where naming stays unavoidable: (a) *predicting* before any sleep what will happen — the
inhibitor list cannot tell hypridle with and without `before_sleep_cmd` apart; only reading
`hypridle.conf` can, one program's file format; (b) *saying which* program locks in a notice
("…and GNOME Shell does too"): the inhibitor's `who` is shown as given, which needs no list,
but deciding that this holder is a locker does; (c) the lock-state query is per compositor
(Hyprland's IPC), with `LockedHint` as the only generic fallback.

## 5. Options for idle and screen-off

Hardware monitor-off is the same either way: `hyprctl dispatch dpms disable` (or the generic
wlr-output-power-management protocol, which Hyprland also implements; Quickshell 0.3.2 has no
QML type for it, `wlopm` is a tool) — hypridle gives the timer, not a different "off".

**A. hypridle for screen-off, the shell for screensaver and lock (today), tidied.** Config,
no code: lockOnSleep on; hypridle `lock_cmd` removed (the shell follows logind's Lock) or set to
`h2s-shell ipc call lockscreen lock`; Super+L → the shell's IPC lock; `after_sleep_cmd = hyprctl
dispatch dpms on`; screen-off later than the lock. Plus shell fixes 4, 6, 7, 9. Remains: two
idle sources with different inhibitor rules (5); no screen-off without hypridle; no earlier
screen-off at the lock.

**B. hypridle drives everything, the shell renders.** hypridle listeners call the shell:
`ipc call lockscreen screensaver` at T1 (new IPC; `on-resume` ends it), `loginctl
lock-session` at T2 (the shell follows it), dpms at T3, `before_sleep_cmd = loginctl
lock-session` with the shell's inhibitor for the timing. One idle source, all inhibitor kinds.
Costs: the times live in `hypridle.conf`, outside the shell's settings (the page would say
"set by hypridle"); hypridle-only; new IPC.

**C. The shell does idle, lock and screen-off; hypridle removed.** A "Turn the screen off
after" setting, and a shorter one while locked; DPMS through a per-compositor command
(Hyprland's dispatcher) or the wlr protocol. To match hypridle's inhibitor handling the shell
would own `org.freedesktop.ScreenSaver` (Inhibit/UnInhibit, GetActive/ActiveChanged — also
fixes 9's half) and read logind idle inhibitors. Costs: the most code; owning the D-Bus name
conflicts with a hypridle still running; a per-compositor DPMS path.

**D. Hybrid: the shell owns all timing, hypridle stays for inhibits only.** The shell calls
`hyprctl dispatch dpms` itself on its own screen-off setting; hypridle keeps no listeners.
Less code than C (no D-Bus name), but hypridle's inhibitor knowledge is then unused and
point 5 stays.


## 6. Decided (the owner, 2026-11-21)

The questions of the analysis, answered:

1. **The sleep notice** works by observing the outcome (§4, "a generic version"): no program
   names, no prediction. The short delay inhibitor that gives the shell its moment to look is
   accepted.
2. **Option C, if it can be done well**: the shell owns idle detection, the screensaver, the
   lock, hardware screen-off (DPMS) and the screensaver/inhibit D-Bus interface
   (`org.freedesktop.ScreenSaver`). Until the shell turns monitors off itself, hypridle stays,
   for DPMS only; after that it is redundant.
3. **Super+L and hypridle's `lock_cmd`** call the shell's IPC lock — done on the owner's
   machine (`scripts/launch.sh ipc call lockscreen lock`, backups `*.bak-<time>` in
   `~/.config/hypr`). Defects 2 and 3 no longer happen there; the docs still have to say so.
4. **The Arch machine is a desktop PC** with one OLED monitor: no automatic lock wanted,
   `lockOnSleep` stays off; the screensaver matters and the screensaver ↔ lock flow must work
   well. The lid defect (1) is not this machine's, but stays a defect for laptops.
5. **The screensaver takes the keyboard** while shown; the waking key is swallowed.
6. **The shell reports its lock to the system**: `SetLockedHint`, and with option C the
   screensaver interface's `ActiveChanged`.
7. The Power save profile's test commands are cleared (done).
8. **Per-monitor blanking** (the owner's "7–9"): the owner's OLED starts its own protection
   mode even on a black picture (turned off only with a button on its back); only a hardware
   off avoids it. Each monitor's way of going dark is a choice: an OLED hardware off, an LCD a
   black overlay (a slideshow later), a laptop panel off (its backlight costs power on black).
   Per-monitor choice is optional: one default for all, overrides per monitor for who wants
   them.
9. **The times are the owner's** to set; what matters is the settings: readable, grouped,
   never everything in one place.

Second round, on the design (the owner, 2026-11-21):

10. **Turning monitors off**: Hyprland is an integration, not a requirement — natively
    through Hyprland; elsewhere through `wlopm` when it is installed; without either, "Turn
    off" is unavailable and says why.
11. **Keep-awake requests are ignored while locked**; the lock screen's own screen-off applies.
12. **The screensaver interface in full, no Python**: a small C++/Qt helper (QtDBus; Qt is
    already a dependency) owns `org.freedesktop.ScreenSaver`, and later whatever else
    Quickshell cannot do (the Google sign-in's local server, replacing the Python one). The
    project gets its first build step: the NixOS package builds it, `install.sh` builds it on
    Arch (later the AUR); tests on a stand-in bus; `CLAUDE.md`'s "no build step" and the docs
    change. In parallel a feature request or contribution to Quickshell for D-Bus services
    from QML (`notes/upstream/quickshell-dbus-service.md`); once it lands, the helper's D-Bus
    part goes. Python leaves the project over time.
13. **The sleep notice is a cycle**: shown once as a critical notification; closing it means
    acknowledged; then "waiting for a fix", with a line on the Lock screen page; a later sleep
    that locked means fixed; the next unlocked sleep is told again. No "Don't tell me again".
    A pure rule with cases (§14).
14. **The lock screen's screen-off is on by default after 1 min**; every other new time
    defaults to off.

## 6b. Open question

1. **Arch: the helper after an update.** On Arch the shell runs from a git checkout; an
   update (`git pull`, or the lead's fast-forward) can change the helper's source while the
   built program stays old. Example: an update adds a method to the screensaver interface; the
   old helper answers without it until someone rebuilds. Options: (a) `launch.sh` rebuilds
   at start when the source changed (a stamp of its files beside the build; ~10 s once, with
   cmake and a compiler, which `install.sh` installs anyway), and on a failed build starts the
   shell without the helper and says so once; (b) only `install.sh` builds, and the shell
   says "helper out of date — run install.sh"; (c) a prebuilt binary from releases.
   **Recommendation: (a)** — an update keeps working without a step to remember. NixOS is
   unaffected (the package builds it).

## 7. The design in short

One owner for everything idle: a new singleton **`Idle`** (I/O) feeding a pure **`IdleRules`**
(decisions), which says, for every moment, what each monitor should show — the desktop, the
screensaver, or nothing (powered off) — and when to lock. `Lockscreen` keeps the lock;
**`ScreenPower`** turns monitors off and on; a helper owns `org.freedesktop.ScreenSaver`.

All idle times count **from the last input**, one meaning for each (defect 7):

```
last input ──── Screensaver after ──── Turn screens off after ──── Lock after
                (per monitor: its way)  (all monitors: power off)   (the lock screen)
locked ───────── Turn screens off on the lock screen after (from the lock or the last input there)
```

Each monitor has a **way** of going dark at "Screensaver after": `screensaver` (the black
screensaver, with notifications if they are on), `off` (hardware off at once: the OLED, the
laptop panel) or, later, `slideshow`. One default way for all; with "Set per monitor" on, an
override per monitor. "Turn screens off after" then cuts the power of every monitor still on.
Locking never turns a monitor on; only input does.

## 8. The idle state machine: `IdleRules`

`singletons/IdleRules.qml`, pure functions with unit cases (`tests/IdleRulesTest.qml`).
Decisions are **declarative**: from the current facts it computes the *wanted* picture per
monitor; the actions are the difference between the wanted picture and the one in place.
Settings changes, monitors plugged in, resume and wake are then all the same step, and no
stage can be "left behind".

### Facts (`state`) and settings (`config`)

| Field | Meaning |
|---|---|
| `inputIdle` | no input for the base time (ext-idle-notify, inhibitors **ignored**) |
| `awayIdle` | the same, Wayland idle-inhibitors **respected** (`inputIdle && !awayIdle` = a Wayland inhibitor holds) |
| `idleSince` | monotonic ms of the last input (the notification's time minus the base time); moved forward when an inhibitor is released and at resume |
| `busInhibitors` | count of `org.freedesktop.ScreenSaver` inhibits held (by live clients) |
| `logindIdleBlock` | logind holds an `idle` block inhibitor (read, §11) |
| `locked`, `lockQuietSince` | the session lock (own, or a foreign one seen on Hyprland), and the later of the lock moment and the last input at the lock |
| `sleeping` | between `PrepareForSleep(true)` and the resume |
| `forcedSince` | the screensaver was asked for (IPC, D-Bus `SetActive(true)`) |
| `lockedThisPeriod` | locked in this idle period (the idle lock is not asked again); `lockAsks`, `lockAskedAt` the asks not taken (the retry pause); `lockSince` a profile switch that made the lock due |
| `shown` | per monitor id: `on`, `saver`, `off` — what is in place |

`config = IdleRules.config(values, monitors, canPowerOff)` normalises the profile's values:
`saverAfter`, `screenOffAfter`, `lockAfter`, `lockedScreenOffAfter` (seconds, 0 = never),
`defaultWay`, `perMonitor`, `ways` (id → way), `canPowerOff` (§9). A way `off` without power
control and a way `slideshow` (not built yet) both fall back to `saver`.

### The functions

- `wanted(state, config, now)` → `{ monitorId: "on" | "saver" | "off" }`
  - sleeping: nothing changes (the shown picture stays);
  - locked: `off` for every monitor once `now − lockQuietSince ≥ lockedScreenOffAfter`
    (inhibitors ignored, §6.11), else what idle had reached (never back to `on`
    without input), shown under the lock surface;
  - unlocked and held (a Wayland, bus or logind inhibitor, not forced): what was reached stays,
    nothing further;
  - else from `idleFor = now − idleSince`: `idleFor ≥ screenOffAfter` → `off`; `idleFor ≥
    saverAfter` → the monitor's way (`saver` or `off`); else `on`.
- `lockDue(state, config, now)` → true once per idle period when unlocked, not held,
  `lockAfter > 0`, `idleFor ≥ lockAfter`.
- `nextDeadline(state, config, now)` → the next moment `wanted` or `lockDue` changes, or −1;
  `Idle` runs one Timer to it (no Timer per stage).
- `step(state, event, config, now)` → `{ state, actions }`. Events: `inputIdle(bool)`,
  `awayIdle(bool)`, `busInhibitors(n)`, `logindIdleBlock(bool)`, `deadline`, `config` (a
  profile or settings change), `monitors(list)`, `locked`, `unlocked`, `sleep`, `resumed`,
  `force`, `activity` (D-Bus `SimulateUserActivity`). Actions: `showSaver(ids)`,
  `hideSaver(ids)`, `powerOff(ids)`, `powerOn(ids)`, `lock`, `startCommand`, `endCommand`,
  `active(bool)` (for `ActiveChanged`).

### The cases (each a unit case)

| Case | Outcome |
|---|---|
| idle reaches "Screensaver after", ways all `screensaver` | `showSaver(all)`, `startCommand`, `active(true)` |
| the OLED's way is `off` | `powerOff(oled)` and `showSaver(others)` at the same deadline; the OLED gets a black surface too (it takes the keys, §12) |
| "Turn screens off after" | `powerOff` of every monitor still on or in `saver` |
| "Lock after" | `lock`; not taken (no `locked` came) → asked again while due, after a growing pause (5 s doubling, at most 5 min; logged at the first ask again); `lockedThisPeriod` set only by `locked` |
| a profile switch makes the lock due (turned on, or "Lock after" shortened below the time idle) | counted from the switch (`max(idleSince, switch)`), never at once, as the old code did |
| input at any stage | `hideSaver`, `powerOn` of what the shell turned off, `endCommand` (only after a start), `active(false)` unless locked |
| input at the lock screen | `powerOn`; the lock's quiet time starts again |
| locked, no input for the lock screen's time | `powerOff(all)`; with no power control, the lock surface goes black instead |
| inhibitor (bus, logind, Wayland) while unlocked | the next stage waits; released → counting starts at the release (as hypridle) |
| inhibitor while locked | ignored (§6.11) |
| a profile changes during idle (unplugging, battery level, `screen.locked`) | `wanted` recomputed: reached stages stay unless switched off (a screensaver turned off is hidden, **without** the end command: the user is still away), later stages take the new times; no IdleMonitor is remade (defect 6) |
| a monitor's way changes during idle | applied at once (the OLED switched to `off` goes off now) |
| a monitor is plugged in during idle | gets the stage's picture for its way |
| a monitor is unplugged | dropped from `shown`, no action |
| `sleep` | the Timer stops; nothing is changed (the lock before sleep is `LockRules`') |
| `resumed` | counts as input: `idleSince` = now, screensaver hidden, monitors the shell turned off powered on (defect 11); the lock, if any, stays (defect 10: no screensaver over an unlocked session after a wake) |
| forced (IPC / `SetActive(true)`) | `idleSince` = now − `saverAfter` (or the screensaver now if it is off), held stages ignored until input |
| idle reaches "Screensaver after" while locked | the stages run on under the lock (inhibitors ignored): the start command runs, as today; the pictures stay under the lock surface |

### Wiring: `Idle` (I/O)

`singletons/Idle.qml` replaces `Lockscreen.qml`'s idle part (§2): two IdleMonitors made once
with a fixed base time of 5 s (the schema's minimum) — `inputIdle` with `respectInhibitors:
false`, `awayIdle` with `true` — so settings never remake them (defect 6; IdleWatch stays as
the way to make them). One Timer to `nextDeadline`. It reads the profile values, the monitors
from `ScreenPower`, the bus inhibitor count from the helper (§11), logind's idle block at each
deadline (§11), and `Lockscreen.locked` / sleep from `LockRules`; it executes the actions
(`Lockscreen.lock("idle")`, `ScreenPower`, the screensaver surfaces, the commands). IPC:
`idle state` (JSON, for the tests) and `lockscreen screensaver` (start it now).

## 9. Turning monitors off: what is generic, what needs the compositor

**Quickshell 0.3.2 has nothing for it** (checked on the installed package): its Wayland module
offers IdleInhibitor, IdleMonitor, Screencopy, ShortcutsInhibitor, ToplevelManagement and the
layer shell; the binary binds no `zwlr_output_power`. `Quickshell.screens` gives each screen's
connector name and model; its `serialNumber` is **empty** on Wayland (read here: DP-2
`C27JG5x`, serial ""), and there is no make.

- **Generic, in principle:** the `wlr-output-power-management-v1` protocol (sway, labwc,
  river, Hyprland implement it: Hyprland 0.57.2's binary carries
  `zwlr_output_power_manager_v1`). A client is needed — the tool `wlopm`, or a Quickshell type
  that does not exist yet. GNOME and KDE offer no such protocol (they blank by themselves).
- **Hyprland:** per monitor through its dispatcher, Lua API `hl.dsp.dpms({ action =
  "disable", monitor = "<connector>" })` / `"enable"` (0.57.2's `dpms(action, optional
  monitor)`; checked on a private nested Hyprland: `monitor` is the key, `hyprctl dispatch`
  prints "ok" even for a bad action, and **a monitor name it does not know turns every monitor
  off** — so only a connector of the last reading is ever dispatched), classic config
  `hyprctl dispatch dpms off <connector>`. The power state is `dpmsStatus` in
  `hyprctl -j monitors`, which also carries `make`, `model`, `serial`.
  Hyprland's `key_press_enables_dpms` / `mouse_move_enables_dpms` turn monitors on at input by
  themselves — kept: a wake works even when the shell hangs.
- **What always needs the compositor:** cutting one output's power and reading its power
  state. What is generic: idle and input (ext-idle-notify), the lock (ext-session-lock), the
  screensaver surfaces (layer shell).

**`ScreenPower`** (`singletons/ScreenPower.qml`, I/O; decisions in `MonitorRules`): picks a
backend at start (§6.10), each through `Process` so a stand-in program serves the tests:

| Backend | When | Read | Act |
|---|---|---|---|
| Hyprland | `HYPRLAND_INSTANCE_SIGNATURE` set | `hyprctl -j monitors` (power, make, model, serial) | `hyprctl dispatch` (§9 above) |
| wlopm | elsewhere, `wlopm` on `PATH` | `wlopm --json` (outputs and their power) | `wlopm --off <connector>` / `--on` |
| none | neither | — | — |

With none, `canPowerOff` is false: the page greys "Turn off" and "Turn screens off" with
"Not supported here" (the hint names `wlopm` once: "Install wlopm to turn monitors off"),
and such monitors get the black screensaver. `wlopm` is an optional program: listed in the
docs under both systems (NixOS: in `pkgs` as `wlopm`, not added to the package's `PATH` since
Hyprland users do not need it; Arch: AUR `wlopm`), never installed by `install.sh`. It
re-reads the monitors on Hyprland's `monitoradded`/`monitorremoved` events, on Qt's screen
list changing elsewhere, and after each action (a failed read = power state unknown: the
shell does not assume a monitor is off). It powers on only what it turned off.

### Monitors identified stably

`MonitorRules.identity(monitor)` → `make|model|serial` from Hyprland (`Samsung Electric
Company|C27JG5x|H4ZMC00268`), never the connector (a cable moved to another port keeps its
settings). Without a serial (some panels report none) the key is `make|model|` plus the
connector when two connected monitors share make and model. Off Hyprland (wlopm gives names
only): `|model|connector` from Qt. `MonitorRules.isBuiltIn(connector)` — `eDP-`, `LVDS-`, `DSI-` — names it "Built-in
screen" on the page. Overrides for monitors not connected are kept and listed, greyed, with
"Not connected" and a "×" (DeleteButton) to forget them. Mirrors and disabled outputs are
skipped.

## 10. The lock reported to the system

- **`SetLockedHint`**: `LockRules` gets an action `reportLockedHint(bool)` at the compositor's
  confirmation and at the unlock; `Lockscreen` runs `gdbus call --system --dest
  org.freedesktop.login1 --object-path <session> --method
  org.freedesktop.login1.Session.SetLockedHint <bool>` (the session's owner needs no polkit).
  A failure is logged once (on a change of outcome). Defect 9, first half.
- **`ActiveChanged`** comes with the screensaver interface (§11): active = any monitor not
  `on`, or locked.
- **A foreign lock** (defect 3; with the owner's config change it no longer happens there, but
  any other locker can still lock): on Hyprland, `hyprctl -j locked` is read when the shell's
  own lock is refused and at each idle deadline; a foreign lock counts as `locked` for
  `IdleRules` (no idle lock attempt, the lock screen's screen-off applies) and for the sleep
  notice.

## 11. Apps keeping the screen on (inhibitors)

Three sources, all respected while unlocked (hypridle's set), all ignored at the lock (§6.11):

- **Wayland idle-inhibit**: `awayIdle` (§8) — no names are known; the page says "an app".
- **`org.freedesktop.ScreenSaver`**: the helper's `screensaver` service (§18), started by
  `Idle`, owns the name on the session bus at `/org/freedesktop/ScreenSaver` and
  `/ScreenSaver`: `Inhibit(app, reason)` → cookie, `UnInhibit(cookie)`, `GetActive`,
  `GetActiveTime`, `GetSessionIdleTime`, `SetActive`, `SimulateUserActivity`, signal
  `ActiveChanged`. It drops a client's cookies when its bus name vanishes
  (`NameOwnerChanged`). The shell treats app names and reasons as text from outside (plain,
  capped, one line). It asks for the name **without replacing** another owner: name taken →
  a line on the Screensaver page, "<owner's process name> answers apps that ask to keep the
  screen on. Stop it to let the shell do it." (the name read from the bus, no list), and the
  shell works on without bus inhibitors; when the name frees up the helper takes it (it
  stays queued for it).
- **logind `idle` block inhibitors** (`systemd-inhibit --what=idle`, mpv and others): read with
  `ListInhibitors` at each deadline that would start a stage (logind sends no signal when one
  appears); a failed read counts as "not held" for the screensaver but is logged once — it
  must not keep the screen on for ever (a failed read is unknown; here the safe side is the
  screensaver, which ends at the first input).

The page's "Keeping the screen on" list shows the bus and logind holders by name and reason,
and "an app (unnamed)" for a Wayland one.

## 12. The screensaver surface

- **Keyboard** (defect 4): `WlrLayershell.keyboardFocus: Exclusive` while shown, `None`
  otherwise; the waking key goes to the surface and nowhere else. A click is already
  swallowed. Every monitor gets its surface, also those powered off (a black, mapped surface
  takes the keys; its picture does not matter).
- **Per monitor**: `ScreensaverSurface` shows when its monitor's `shown` is `saver` or `off`;
  in `off` it skips the fade and notifications (plain black, in case the power cut fails).
- **The lock screen with no power control**: at the lock screen's screen-off time the lock
  surface fades to plain black (no notifications, no prompt) until input.

## 13. Settings: where each lives

Two pages instead of one ("Lockscreen & Screensaver"), each in a few sections; every row is a
profile setting edited as today (the profile picker, inherited values dimmed, the pin for
global) unless marked global. The mockup shows them.

**Page "Screensaver"**

| Section | Rows | Keys |
|---|---|---|
| **When idle** | a timeline drawn from the values (§7's line; one lane per monitor when "Set per monitor" is on; a held stage shows "Paused: <who>"); "Screensaver" switch + "after" pills; "Turn screens off" switch + "after"; "Lock" switch + "after"; hint "Counted from your last input." | `screensaverEnabled`, `screensaverTimeout`; **new** `screenOffEnabled` (false), `screenOffTimeout` (600 s); `lockscreenEnabled`, **new** `lockAfter` (600 s, from the last input; replaces `lockscreenTimeout`) |
| **Monitors** | "When the screensaver starts": pills "Screensaver", "Turn off", "Slideshow" (greyed, "Later"); "Set per monitor" switch; when on, a card per monitor (name, connector, "Built-in", "Not connected") with pills "Default", "Screensaver", "Turn off", "Slideshow" | **new** `blanking` (enum, "screensaver"), `perMonitor` (bool, false), `monitorBlanking` (structured `monitorBlanking`, `{ id: way }`, overridden as a whole) |
| **Screensaver** | fade in, fade out, notifications, their detail | as today |
| **Keeping the screen on** | read-only list of current holders (§11); the name-taken line | — |
| **Commands** | one opening row (`ExpandingRow`) "Run commands": the switch and the two fields | as today |

**Page "Lock screen"**

| Section | Rows | Keys |
|---|---|---|
| **Locking** | "Lock before the computer sleeps"; under it, while the sleep notice waits for a fix, the line "The last sleep left the screen unlocked (today 07:58). Waiting for a sleep that locks."; "Locking when idle" with a button to the Screensaver page | `lockOnSleep`; the cycle's state is remembered data in `Config`, not a setting |
| **On the lock screen** | "Turn screens off after" pills (30 s, 1 min, 2 min, 5 min, Never); notifications and their detail | **new** `lockedScreenOffTimeout` (60 s, 0 = never; §6.14); as today |
| **Sign-in** | (from `plans/pam-config.md`: not offering fingerprint / a security key) | later |

Profiles: the per-monitor map is one structured value, so a profile that changes one monitor's
way holds the whole map (the editor copies the inherited map on the first change, as the other
structured settings). The per-monitor cards appear only while "Set per monitor" is on in the
edited profile. `lockscreenTimeout` → `lockAfter`: migrated (`lockAfter = screensaverTimeout +
lockscreenTimeout` where the screensaver was on, else `lockscreenTimeout`) only if it is in use
— on the Arch machine it is set in "Power save", which never applies on a PC; the NixOS
machine is checked at the slice and, if used, the owner asked (decisions, "Data migrations").

## 14. The sleep notice, by outcome

Replaces `SleepLockers` and the name lists in `LockIoRules` (§4). The shell holds a sleep
delay inhibitor always (`h2s-shell`, "Checks the screen is locked before sleep"), not only
with `lockOnSleep`. At `PrepareForSleep(true)` it looks: own lock, else `hyprctl -j locked` on
Hyprland, else `LockedHint`; once more after 500 ms if unlocked; then releases (at once when
already locked; ≤ 1 s otherwise; `lockOnSleep` keeps today's longer hold until the lock is
confirmed). The outcome of a sleep is `locked`, `unlocked` or `unknown`; a sleep that started
from an already locked session is `locked`.

### The cycle: `SleepNoticeRules.step(state, event)`

Pure, in `singletons/SleepNoticeRules.qml`, cases in `tests/SleepNoticeRulesTest.qml`. The
state (`quiet`, `shown`, `waiting`, with the time of the unlocked sleep) is remembered in
`Config` (data, not a preference), so a restart neither repeats nor loses it.

| State | Event | Next | Action |
|---|---|---|---|
| quiet | slept `unlocked` (after the resume) | shown | the critical notification "Not locked while asleep" — "The screen was not locked while the computer slept." (stays until closed; its default action opens the Lock screen page) |
| shown | notification closed (×, or its action) | waiting | — (acknowledged) |
| shown | slept `unlocked` again before it was closed | shown | the notification replaced (one, never two), its time updated |
| shown | slept `locked` | quiet | the notification withdrawn (fixed before it was read) |
| waiting | slept `unlocked` | waiting | nothing (still not fixed; the page's line takes the new time) |
| waiting | slept `locked` | quiet | the page's line goes (fixed) |
| any | slept `unknown` | same | nothing (no lock state could be read: never an alarm) |
| quiet | slept `locked` | quiet | nothing |
| shown | the shell restarts | shown | the notification shown again (it was never closed) |

So a system that was fixed and fails again is told again; no "Don't tell me again". With
`lockOnSleep` on and the shell's own lock refused at that moment, the "two programs lock"
notice stays as today.

## 15. hypridle, retired in steps

1. **Now:** hypridle keeps its DPMS listener only (`lock_cmd` already calls the shell). The
   shell's screen-off is off by default, so both never act on the same thing unless set.
2. **The shell's screen-off lands** (slices below): the owner sets "Turn screens off after"
   and removes hypridle's listener — or hypridle altogether. Docs, in "NixOS" and "Arch"
   subsections: NixOS `services.hypridle.enable = false` (Home Manager) or dropping it from
   the compositor's autostart; Arch removing its `exec-once` / `systemctl --user disable
   hypridle`.
3. **The screensaver interface lands** (the helper, §18): the shell takes
   `org.freedesktop.ScreenSaver` when it is free; while hypridle (or anything) holds it, the
   page says who, as in §11.
4. `docs/FEATURES.md` and `docs/ARCHITECTURE.md` lose the hypridle/swayidle/xss-lock passages
   about guessing lockers; they describe the outcome check.

## 16. Defects (§3) to slices

| Defect | Where it ends |
|---|---|
| 1 Laptop sleeps unlocked, notice silent | Sleep notice by outcome |
| 2 Two lockers on logind's Lock | owner's config (done); docs in the hypridle step |
| 3 A foreign lock invisible | owner's config (done); Foreign lock seen |
| 4 Keys reach the app under the screensaver | Screensaver takes the keyboard |
| 5 Different inhibitor rules | logind idle inhibitors; Screensaver interface |
| 6 Settings change ends idle | Idle rules and wiring |
| 7 "Lock after" two meanings | Idle rules and wiring (`lockAfter`) |
| 8 No screen-off of its own | Screen-off |
| 9 Lock invisible to the system | Lock reported to logind; Screensaver interface (`ActiveChanged`) |
| 10 Screensaver over an unlocked session after a wake | Idle rules and wiring (`resumed`) |
| 11 Monitors stay off after a wake | Screen-off (power on at resume) |
| 12 Power save test commands | owner's config (done) |

## 17. Slices

Each with its test; stand-ins only — no real logind, D-Bus service, polkit or DPMS of the
session. "The lock bed" is `tests/lock/run.sh`: its own invisible Hyprland with headless
outputs, stand-in `gdbus` / `systemd-inhibit`, never the session's compositor.

1. **Idle rules (I1)** — `IdleRules` with §8's cases; `tests/IdleRulesTest.qml`. No wiring.
2. **Idle rules and wiring (I2)** — `Idle` replaces `Lockscreen`'s idle part; the two fixed
   IdleMonitors; `lockAfter` from the last input (migration check); the commands follow idle
   periods as today. Tests: `IdleRulesTest`; lock bed `idle.sh`, `idle-lock.sh` updated, new
   `idle-profile.sh` (a profile switch mid-idle keeps the screensaver, no end command), and a
   resume case in `logind.sh` (stand-in `PrepareForSleep(false)`: the screensaver ends).
3. **Screensaver takes the keyboard (I3)** — Exclusive focus while shown. Lock bed
   `key-wake.sh` extended: a key at the screensaver reaches no window (the bed's test client
   records nothing).
4. **Lock reported to logind (I4)** — `reportLockedHint`. `LockRulesTest` cases; lock bed
   `logind.sh`: the stand-in `gdbus` records `SetLockedHint true` / `false`.
5. **Monitors and their power (I5)** — `MonitorRules` (identity, built-in, twins),
   `ScreenPower` on `hyprctl`. `tests/MonitorRulesTest.qml`; a reading suite running
   `ScreenPower` against a stand-in `hyprctl` (monitors JSON in, dispatches recorded, a failed
   read = unknown).
6. **Screen-off (I6)** — `screenOff*`, `lockedScreenOffTimeout`, `blanking` (default way);
   actions wired to `ScreenPower`; power on at wake and resume; the lock surface's black
   fallback. Tests: `IdleRulesTest`; lock bed `screen-off.sh`: the bed's own headless outputs'
   `dpmsStatus` goes false and back true at input (its private Hyprland; the session's monitors
   are never touched).
7. **Per-monitor ways (I7)** — `perMonitor`, `monitorBlanking` and its editor; per-monitor
   surfaces. `IdleRulesTest` cases; lock bed `outputs.sh` extended (two headless outputs, one
   `off`, one `screensaver`).
8. **The two pages (I8)** — Screensaver and Lock screen pages per the mockup, the timeline
   element. With them come I7's editor rows: the "Set per monitor" switch
   (`lockscreen.perMonitor`) and the per-monitor cards (`lockscreen.monitorBlanking`,
   written through `IdleRules.withMonitorWay`), which I7 declared and wired without a view;
   until then the IPC `idle setMonitorWay <id> <way>` sets them. `SettingsPagesTest`; the mockup re-run on the real code for the owner.
9. **logind idle inhibitors (I9)** — `ListInhibitors` read and parsed (`LockParseRules`).
   Parse cases; a reading suite on a stand-in `gdbus`.
10. **The helper and its build (I10a)** — §18: the source tree, `scripts/build-helper.sh`,
    the NixOS package and `install.sh` building it, `launch.sh` finding it (and §6b),
    `CLAUDE.md` and the docs. Tests: `tests/run-helper.sh` builds it and runs a `--version`
    check; `tests/install-test.sh` sees the build step; the package builds on NixOS.
11. **Screensaver interface (I10b)** — the `screensaver` service, `Idle`'s holder list,
    `ActiveChanged`, the name-taken line. Tests: `tests/run-helper.sh` on a private bus (§18);
    a reading suite running the shell's side against the real helper on that bus.
12. **Sleep notice by outcome (I11)** — §14; `SleepLockers` and the name lists removed.
    `SleepNoticeRulesTest` (the cycle), `LockIoRulesTest` cases; lock bed `logind.sh`: stand-in `PrepareForSleep` with the shell
    unlocked → the notice after resume; locked → none; the inhibitor released within 1 s.
13. **Foreign lock seen (I12)** — `hyprctl -j locked` at a refusal and at deadlines. Lock bed:
    a second locker client in the bed's Hyprland; the shell neither tries the idle lock nor
    says "unlocked".
14. **hypridle retired (I13)** — docs (§15), both systems; a draft feature request in
    `notes/upstream/` for an output-power type in Quickshell.
15. **The wlopm backend (I14)** — `ScreenPower` on `wlopm` (§9). A reading suite on a stand-in
    `wlopm` (JSON in, `--off`/`--on` recorded); `canPowerOff` false with neither program.

Order: 1–4 first (they help the desktop PC today: the screensaver ↔ lock flow, the keyboard),
then 5–8 (screen-off; after 6 the owner can drop hypridle's listener), then 9–15. Views (8)
wait for the owner's notes on the mockup.

## 18. The helper: `h2s-helper` (C++/Qt)

The project's first compiled part (§6.12): one small program for what Quickshell cannot do
from QML, starting with the screensaver interface. Not a daemon of its own and not a module:
the shell starts it and it ends with the shell.

### Source and shape

- `helper/` at the top of the tree: `CMakeLists.txt`, `src/main.cpp` (subcommands),
  `src/ScreenSaverService.{h,cpp}`, `src/LineChannel.{h,cpp}` (the protocol below),
  `tests/` (its own test client, built only for the tests). C++17, Qt 6 **Core and DBus only**
  (no GUI; `find_package(Qt6 REQUIRED COMPONENTS Core DBus)`), no other library.
- One binary, subcommands: `h2s-helper screensaver` now; `h2s-helper oauth-callback` later
  (the Google sign-in's local server, replacing `scripts/google_auth.py`), and so on.
  `h2s-helper --version` prints the shell's version and a protocol number the shell checks
  (a mismatch = "helper out of date", the feature off, said once).
- Decisions stay in QML `*Rules.qml`: the helper is I/O only — it owns the name, keeps the
  cookies, follows `NameOwnerChanged`, and reports; what the shell does with an inhibitor is
  `IdleRules`'.

### How it talks to the shell: stdin/stdout lines

The shell starts it with `Process` and reads it with `SplitParser`, the shell's usual idiom;
one JSON object per line each way:

- helper → shell: `{"event":"ready","protocol":1}`, `{"event":"name","owned":true}` /
  `{"event":"name","owned":false,"owner":"hypridle"}`, `{"event":"inhibitors","list":[{"app":…,
  "reason":…,"cookie":…}]}`, `{"event":"activity"}` (SimulateUserActivity),
  `{"event":"setActive","active":true}`, `{"event":"error","message":…}`;
- shell → helper: `{"active":true,"since":<epoch s>}` (for `GetActive`, `GetActiveTime`,
  `ActiveChanged`), `{"idleSeconds":…}` (for `GetSessionIdleTime`, sent when asked through a
  `{"event":"askIdle"}`).

Why not a socket: the pipe ties the helper's life to the shell's (the shell dies → stdin
closes → the helper exits and the bus name is released at once, so another program can take
it); there is no socket path, no permissions and no stale file to handle, and nothing else
on the machine can talk to it; the tests drive it the same way the shell does. A second
client is never needed — anything else talks to the helper through D-Bus, the interface it
exists for. The shell restarts a helper that exits, with a backoff, logging a change of
outcome only.

### Building

- **The checkout:** `scripts/build-helper.sh` → `cmake -S helper -B build/helper && cmake
  --build build/helper`; `/build/` is ignored by git. `launch.sh` looks for the helper in
  this order: `H2S_HELPER` (a path), the package's (`$H2S_SHELL_LIBEXEC/h2s-helper`, set by
  the NixOS launcher), `build/helper/h2s-helper` in the tree being run. Not found → the shell
  runs without the screensaver interface; the Screensaver page says "Not built" in the
  "Keeping the screen on" section. Rebuilding after an update: §6b.
- **NixOS:** `nix/package.nix` becomes two derivations: `h2s-helper` (`stdenv.mkDerivation`,
  `nativeBuildInputs = [ cmake ]`, `buildInputs = [ qt6.qtbase ]`, `dontWrapQtApps = true` —
  no QPA plugin is loaded) installed to `$out/libexec/h2s-shell/`, and the shell's files as
  today, its launcher exporting `H2S_SHELL_LIBEXEC`. The `qt6.qtbase` should be the one
  Quickshell is built with (the same nixpkgs), so one Qt is in memory per machine.
  `H2S_SHELL_DIR=<checkout>` keeps using the package's helper unless the checkout has built
  its own.
- **Arch:** `install.sh` adds `cmake` and `base-devel` (the compiler; Qt's headers and
  `Qt6DBus` come with `qt6-base`, already a dependency through Quickshell) to its packages
  and runs `scripts/build-helper.sh` after cloning. Later an AUR package builds it as NixOS
  does.

### Tests (a stand-in bus only)

`tests/run-helper.sh`, a new part of `tests/run-all.sh` (general set, both systems):

1. builds the helper into a temporary directory (cmake, a compiler and Qt's development
   files from `tests/lock/tools.nix` where there is `nix` — added there — else from the
   system; missing → status 2 with the name, as every runner);
2. starts a **private `dbus-daemon`** with the suite's own config
   (`tests/helper/session.conf`: a session-type bus on a socket in the run's directory,
   no service activation, no system policy) — never the session's bus;
3. runs `h2s-helper screensaver` on it, fed and read by the suite like the shell does, and
   the test client (`helper/tests/client.cpp`: Inhibit and hold until told, UnInhibit, exit
   without UnInhibit, GetActive, call SimulateUserActivity) plus `gdbus` for one-shot calls.

Cases: the name is taken and `ready` / `name owned` reported; Inhibit → `inhibitors` with app
and reason; UnInhibit → empty; a client exiting while holding → its cookie dropped; two
clients, one leaves; a cookie of another client cannot be removed; `active` from the shell →
`GetActive` true and one `ActiveChanged`; the name held by another connection first →
`owned:false` with its owner, then taken when it leaves; stdin closed → the helper exits and
the name is free; markup and a 10 kB reason in `app`/`reason` come through as plain text
(the shell caps them). On the QML side, a reading suite runs `Idle`'s helper client against
the real helper on the same private bus.

### What the docs and `CLAUDE.md` say

- `CLAUDE.md` "Running": "There is no build step" becomes "QML needs no build; one helper is
  compiled: `scripts/build-helper.sh` (NixOS: the package builds it; Arch: `install.sh`)";
  "Conventions": the helper is I/O only, decisions stay in `*Rules.qml`; a new capability goes
  into the helper only when Quickshell cannot do it, and leaves it when Quickshell can.
- `docs/ARCHITECTURE.md`: the runtime model (the shell and its helper process, the line
  protocol), the directory layout (`helper/`), "Where the test tools come from" (cmake, a
  compiler, Qt's development files, the private bus), each with NixOS and Arch subsections.
- `docs/FEATURES.md`: "Keeping the screen on" and the dependencies (`cmake`, `base-devel`
  on Arch; nothing extra on NixOS; `wlopm` optional off Hyprland).
- `notes/upstream/quickshell-dbus-service.md`: the request to Quickshell (drafted with this
  plan).
