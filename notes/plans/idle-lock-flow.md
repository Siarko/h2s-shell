# Idle, screensaver, lock and screen-off: how it works today, what is wrong, options

Analysis only, no code changed. Read on the Arch machine, 2026-11-21, against `master`
2815bf9 (branch `idle-plan`). Reads only: the code, `~/.config/hypr/hypridle.conf`,
`~/.config/hypr/hyprland.lua`, `~/.config/h2s_shell/config.json`, `systemd-inhibit --list`,
`loginctl show-session`, logind's properties over `busctl`, the user journal. Quickshell 0.3.2,
Hyprland 0.57.2, hypridle 0.1.8, hyprlock 0.9.7.

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

## 6. Open questions for the owner

1. **The sleep notice with hypridle (the tracker's open point).** Today: on this machine the
   laptop sleeps unlocked at every lid close and the shell says nothing, because hypridle
   *might* lock. Example: you close the lid in a café, open it at home — the desktop is there,
   no password. Options: (a) say "may stay unlocked" whenever only possible lockers hold
   inhibitors (a false alarm where hypridle has `before_sleep_cmd = loginctl lock-session`);
   (b) observe the outcome (section 4) and say "the last sleep left the screen unlocked" after
   the fact; (c) leave it silent. **Recommendation: (b)**, with the short inhibitor; it names
   no program and is never wrong about what happened on Hyprland.
2. **Who owns idle and screen-off (section 5).** Example: today on AC hypridle turns the
   monitors off at 10 min and nothing locks; on battery the shell locks after 15 s. Options A,
   B, C. **Recommendation: A now** (config only, plus fixes 4, 6, 7, 9), then decide between B
   and C after point 5 is checked; C if the shell should work without hypridle on other
   compositors.
3. **Super+L.** It runs hyprlock, a second lock screen the shell does not know about. Example:
   on battery, locked by Super+L, the shell still tries its idle lock and logs a refusal.
   **Recommendation:** bind it to `h2s-shell ipc call lockscreen lock` and drop hypridle's
   `lock_cmd` (or point it there), so one lock screen answers every path.
4. **Turn lockOnSleep on for this machine?** The default stays off (decided); here nothing
   else locks before sleep. **Recommendation: on**, in your config (yours to change).
5. **Keys at the screensaver.** Example: the screensaver is up, you press Enter to wake it, the
   terminal behind runs the half-typed line. Options: swallow the waking key (the overlay
   takes keyboard focus while shown), or let keys through as now. **Recommendation: swallow.**
6. **Tell the system about the shell's lock** (`SetLockedHint` at lock/unlock — no polkit for
   the session's owner — and/or `org.freedesktop.ScreenSaver.ActiveChanged`). Example:
   Bitwarden or KeePassXC set to lock with the screen do not lock on the shell's idle lock.
   **Recommendation: SetLockedHint**, tested against a stand-in logind.
7. **Screen-off while locked.** Example: locked at 15 s on battery, the lock surface stays lit
   until 10 min of no input, and again after every touch. Options: a "Turn the screen off on
   the lock screen after" setting (shell DPMS, option C's first piece) or a second hypridle
   listener. **Recommendation:** decide with question 2; on OLED a short one (30–60 s).
8. **The Power save profile's `notify-send "start"` / `"back"` commands** — keep or clear?
   (They send two notifications every idle period on battery.)
