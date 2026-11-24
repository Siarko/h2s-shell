# Features

What the shell does, from the outside. For how it is put together see
[ARCHITECTURE.md](ARCHITECTURE.md).

## The bar

A panel on every monitor, along the edge chosen in **Settings → Bar → Position** (top,
bottom, left or right; per profile). At a side the widgets stack down it, and their text
is turned — read down a bar at the right, up a bar at the left — or written as letters
one under another (**Text on a
vertical bar**, the same for every widget); popups open sideways from it. Popups open
away from the bar at any edge. At the top it reserves 40 px of screen space
(`bar.layout.reservedSpace`) and draws a 36 px rounded bar inside it
(`bar.layout.barHeight`, `topOffset`), so the bar appears to float below the screen
edge. Margins, padding and the four corner radii are configurable; the radii are
expressed as a percentage of half the bar height, so 100 gives a fully rounded end.

The bar has three sections — left, centre, right. Each is an ordered list of widgets
chosen in **Settings → Bar → Content**, and a widget can appear more than once with a
different *preset* (a named set of that widget's settings): two clocks with different
formats, two hardware capsules showing different sensors. Like every setting, the bar —
geometry, sections, popup modes — can differ per shell profile (see Profiles below).

Widgets available to place:

| Widget | Shows | Interaction |
|---|---|---|
| **Power** | power glyph | opens the power menu |
| **Settings** | gear | toggles the settings window |
| **Workspaces** | Hyprland workspace pills, including special/scratchpad | click to switch, click a special to toggle it |
| **Clock** | the time, format per preset | opens the calendar |
| **Music** | current track | opens the music panel |
| **Sound** | volume % and icon | opens the sound panel; scroll to change volume, middle-click to mute |
| **Bluetooth** | adapter state and connected-device count | opens the bluetooth panel |
| **System Tray** | the StatusNotifier tray icons | left-click activates, right-click opens the item's menu |
| **Network** | one icon per link — ethernet, wifi, VPN | opens the network panel |
| **Notifications** | bell, accented while notifications are waiting | opens the notification panel |
| **Hardware** | a compact sensor capsule, e.g. `CPU 12%` | opens the hardware panel |
| **Battery** | the charge as an icon in tens (charging or not) and in percent, left or right of it or not at all; the icon coloured by the preset's thresholds (any number, each a charge and a hex colour); no-battery icon without one | opens the battery popup: the charge, time left, power drawn, the power profile to override, the history (charge with time on the charger, power drawn) over 6 h / 24 h / 7 d, and use per app since the last full charge (estimated) — or within a stretch dragged on the graph |
| **Dictation** | microphone state, pending counter, live transcript | click toggles dictation |

Only one popup is open at a time, across all monitors. Each widget can be set to open
its popup on **click** or on **hover** (Settings → Bar → Content → the widget's own
settings); a hover popup closes when the pointer leaves it, a click popup stays until
clicked again.

### Network widget icons

Each link gets its own icon, and the colour is the link's own state — accent green when
that link is connected, white when it is on but not connected, dim when it is
unavailable. So ethernet and wifi both up shows two green icons.

- **Ethernet** — hidden when the machine has no managed port. Dim when the interface is
  up but has no carrier, i.e. the cable is out.
- **WiFi** — hidden entirely while the radio is off. The glyph carries signal strength
  once connected.
- **VPN** — shown only while a tunnel is actually up; shield when every VPN up is
  WireGuard, padlock otherwise.

Container and VM interfaces (veth pairs, taps) report as type `ethernet` to
NetworkManager but are unmanaged, and are ignored when picking which port to report on.

## Panels

Opened from their bar widget, rendered in the single popup below the bar.

- **Calendar** — month grid with navigation (arrows, the wheel over the month or year, or
  a finger swipe across the grid, which follows the finger with the coming month beside
  it; a click on the month or the year shows the year's months, to move by years and pick
  one), event dots on days that have events, and
  day/week/month views of the event list. With Google Calendar connected it supports
  full event CRUD: create, edit (including recurrence rules), and delete, with a colour
  picker and a per-calendar picker.
- **Music** — current track, art, seek bar, transport controls, player list when more
  than one MPRIS player is running (application icons; play one alone, pausing the rest;
  hide players, kept per profile, under a "Hidden" expander), and a live audio
  visualiser fed by `cava`. A change of player slides the cover and track vertically (a
  player lower in the list from below), a new track sideways (next from the right,
  previous from the left). With a finger, swiping the cover up or down changes the player
  — the next one's view follows the finger in — and left or right skips the track,
  ⏭/⏮ showing in the gap
  (waveform / bars / dots / glow / even glow, horizontal or vertical — centred or
  glued to the popup's edges — or around the cover,
  configurable in Settings → Media, with the cover's rounding and turning speed;
  around the cover it can take its colours from the cover).
- **Sound** — default sink and source with volume sliders, output/input device
  selection, and a per-application volume row for every Pipewire stream. Per-app volumes
  are remembered across restarts and reapplied when the app reappears.
- **Bluetooth** — adapter toggle, paired and discovered devices, connect/disconnect.
- **Network** — VPN connections (by UUID, several up at once, each its own Connect /
  Disconnect with "Connecting…"), ethernet with a connect toggle, wifi with a radio
  toggle, the scanned network list with signal strength and security, hidden-network
  entry, saved-profile management, plus live throughput (click it for a
  download/upload history graph), IP and DNS per link.
- **Notifications** — the list of unread notifications with per-item dismiss, dismiss
  all, a pin that keeps a notification on the screen beside the toasts, and codes
  (one-time passwords and similar) extracted by the regexes in Settings → Notifications.
  A card swiped sideways by finger is dismissed.
- **Hardware** — every sensor source with its current value, a history graph and a
  progress bar.
- **Power** — shutdown, restart, logout.
- **Tray menu** — the menu of a tray item, rendered in the popup rather than by the app.

## HUD

A click-through overlay above everything, one per monitor. It is transparent and passes
input through except where a card is actually visible.

- **Notification toasts** slide in from the right as notifications arrive, under the bar,
  in three stacks — critical, staying and ordinary — each queue's badge "+N" beside its
  lowest toast counting what waits there (see [Notifications](#notifications)).
- **Volume OSD** appears on volume or mute changes.
- **Shell toasts** — a pill at the bottom centre for the shell's own messages
  (notifications sent with category `x-qs-shell`): its title for 2.5 s, one after another,
  on the toasts' screen. They are kept apart from application notifications: never in the
  panel, not held back by "Show toasts" off, not shown where a fullscreen window with
  "Don't show" leaves no screen for toasts.

## Notifications

The shell *is* the notification server (`org.freedesktop.Notifications`), with support
for body markup, hyperlinks, images, action buttons, action icons and inline replies.
Arrival times are recorded, and the regex patterns in Settings → Notifications extract
codes from the summary and body, so a verification code can be copied without opening the
sending app. A notification stays in the panel until it is dismissed; a critical one is
outlined in red, in its toast and in the panel. An app's action buttons and the reply's
Send are filled with the theme's accent, their labels in its "On accent" colour, lighter
under the pointer or a finger. Running an action takes the toast away — except on a
resident notification (one its app keeps until dismissed, such as a music player's
controls), which stays in the panel and keeps its toast on screen, as the spec asks.

### Toasts

How long a toast shows is the app's to say (the spec's expire timeout): an app asking for
0 keeps its toast up until it is taken away, one asking for 30 s gets 30 s, and one leaving
it to the shell (most do) gets "Show each toast for". With "Apps choose how long" off, every
app's time, 0 included, gives way to that time. A toast stays, whatever the app asks or
the setting says, when it is critical, and when it is resident unless "Resident
notification hide" is on (then it counts down like any other). The time is only the
toast's: the entry stays in the panel. The countdown waits while the pointer rests on the
toast, while a reply is being written, and while a finger drags it.

Toasts stack in three queues, top to bottom, with a wider gap between two queues:

- **critical** — at most "Critical toasts shown, at most" (1–3, 1 by default);
- **staying** — the toasts that stay until taken away, at most "Toasts that stay, at most"
  (1–5, 1 by default);
- **ordinary** — the toasts that count down: one at a time ("One at a time, the rest
  counted") or a column of "Toasts in the column" (2–10).

What does not fit waits in its queue, oldest first, and that queue's badge "+N" beside its
lowest toast counts it (the critical badge outlined in red; a queue with nothing on screen
has its badge below the stack). A click on a badge opens the notification panel on that
screen, or closes it there. Queues never overtake each other. Ordinary toasts with the
user's time count down one at a time, the oldest first; one with its app's own time counts
by itself. A toast that stays has no timer bar. A job whose toast stays and that ends while
waiting moves to the ordinary queue; one that ends on screen counts down where it is.

A toast's "×", or a finger swipe sideways (past a third of its width, or flung), dismisses
the notification: its entry leaves the panel too. For a job, "×" says so in its tooltip
("Dismiss. The job goes on."): the job is not stopped.

Toasts show on the screen with the focused workspace, or on a chosen one. When that screen
has a fullscreen window they show anyway, show only the critical ones ("Don't show": the
others go to the panel only), or show on another screen — a chosen one, or any without a
fullscreen window. Nothing of the toasts lands over the bar, at any edge. With the panel
open, the ordinary toasts leave — shown and waiting, the panel lists them — and new ones
are not queued; critical and staying toasts stay and new ones still show, standing left of
the panel where they would be level with it. "Show toasts" off drops what waits in every
queue; toasts on screen end as they would. The lock screen and the screensaver pause
nothing: toasts keep counting down and the queues keep moving under them.

### Moving and pinning

A critical or staying toast can be dragged by its title line (the grip at its top) and
dropped anywhere on its screen, kept inside it and off the bar ("Move toasts by dragging",
on by default; off, toasts moved out stay where they are and no new drag starts). Moved
out, it has an accent outline (a critical one keeps the red), stays where it was put, and
its queue's place goes to the next toast. Each entry in the panel has a pin that puts its
notification on the panel's screen the same way, beside the toasts, with no countdown,
until it is unpinned. A moved or pinned toast ends with its "×", its unpinning, its app
closing it, or — a job's, once the job has ended — its countdown. It stays when the panel
opens or toasts are switched off, hides under a fullscreen window with "Don't show" until
that window goes, and waits in its queue again when its screen goes. Places are not kept
over a restart of the shell.

### Progress

A notification that carries a progress value (the spec's `value` hint, 0–100) shows a bar
under its text — in the toast, the panel, and on the screensaver and lock screen where
they show a notification's text. An app updating the same notification (by its id) moves
the bar in place: no new entry, no new toast, and the bell rings only for a changed
title or text. While the job is moving (the value grew in the last 10 seconds) bands of
light pass through the bar's filled part ("Progress wave" and "Progress wave: travel" in
Settings → Appearance → Animations); they stop when the value stands still or the job ends, and with reduced
motion. A job that ended shows how beside its title — ✓ in the success colour when done,
✗ in the error colour when it failed, a muted ✗ when cancelled. Its toast, counting down
then, draws no progress bar, so the countdown is the only bar; the panel, the screensaver
and the lock screen keep the full coloured bar.

Modules can show a long job (a transfer, a backup) this way, its bar moving as the job
goes. Its toast either shows for "Show each toast for" and leaves the entry with its moving
bar in the panel, or stays on screen while the job runs (in the staying queue) and counts
down once it ends. When the job's status changes in a way worth seeing — it started,
stalled, finished or failed — the module can bring the toast back once (not with toasts
off, nor an ordinary toast while the panel is open). Its buttons ("Cancel") stay after a
click. Dismissing it, in the panel or by its toast's "×", takes it away for good; the job
goes on. Turning a module off takes its progress notifications away; one left from before
a reload of the shell, whose sender is gone, is dismissed.

### The shell's own notifications

`singletons/Notifier.qml` is the outbound side: the shell sends its own notifications,
with actions and dismiss callbacks (no inline reply: notify-send cannot ask for one), and
they go through the same toasts as any app's. One with a progress bar (a module's job) is
sent with `gdbus` and replaced in place by its id; a click on its button or its dismissal
reaches the shell inside the process, from its own notification server. Short messages
about the shell itself go to the pill at the bottom of the screen (see [HUD](#hud)).

## Dictation

A client for `pttd`, an external dictation daemon driven by Whisper. The shell is
*only* a client — audio capture and keyboard emulation stay in the daemon. The protocol
is pttd's own; the shell talks to it over its Unix socket.

Wake mode and dictation are two independent switches. The bar widget reflects both: an
accent outline means wake is on and the microphone is listening for the start phrase;
the microphone glyph's colour and pulsing track the server state and whether dictation
is active. A pending counter shows words still being transcribed, and a fixed-width
preview line shows the live partial transcript, then briefly the text that was actually
typed.

Clicking the widget toggles dictation. Wake mode and server start/stop are left to the
Hyprland shortcuts and the `ptt` CLI. Settings → Dictation shows the configured wake
phrases read-only, since the CLI and other clients can change them at any time.

While dictating, music is paused and resumed afterwards — but only if the shell was the
one that paused it, so a track paused by hand stays paused. This runs from `shell.qml`,
so it works with the keyboard shortcut whether or not the widget is on the bar.

## Wallpaper

Off by default (Settings → Wallpaper). The shell draws the wallpaper itself, on the
background layer of each screen (`wallpaper/WallpaperSurface.qml`), a new image fading in
over the old. The source is an image (the same everywhere) or a folder, searched to a
chosen depth of subfolders. A folder's images are shown one everywhere, per monitor or
per workspace, and chosen by the user, at random (no repeats while others are left; at
start, every so often, and on Shuffle — `ipc call wallpaper shuffle`) or by weekday;
pinned monitors or workspaces keep theirs. Fit: fill, fit, centre or tile, over a
background colour; a small preview beside the choice plays what the picked fit does
with an image of other proportions (`components/WallpaperFitPreview.qml`). When another program (hyprpaper, swww) also draws on the background
layer, the page warns. How it changes is the theme's (Appearance → Animations): a switch
to a workspace with its own image slides with the workspaces, or changes like a new image,
which fades, zooms, slides, wipes, opens as a circle, dissolves or pixelates
(`wallpaper/shaders/transition.frag`, run only during the change); timed and eased by the
roles "Wallpaper: workspace" and "Wallpaper: new image". Each image is resized once to
each screen it shows on (vipsthumbnail, in the background, at low priority) and kept as a
JPEG in `~/.cache/h2s_shell/wallpapers`, named by the image, its modification time and
size, the screen's pixels and the fit — so a larger screen never gets a smaller copy; the
oldest copies go past 300 MB. The nearest workspaces' images are decoded ahead, so a switch
shows its wallpaper at once. Rules: `singletons/WallpaperRules.qml`; state:
`singletons/Wallpapers.qml`.

## Screensaver and lock screen

The shell does idle itself: from Wayland idle notifications (ext-idle-notify) it runs up
to five stages, each counted from the last input and each with its own switch and time in
Settings → When away — the screensaver (`screensaverEnabled`, `screensaverTimeout`), screens
off ("Turn screens off", `screenOffTimeout`), the lock ("Lock when idle", `lockAfter`),
sleep (`sleepEnabled`, `sleepTimeout`) and hibernation (`hibernateEnabled`,
`hibernateTimeout`); on the lock screen, screens off again after
`lockedScreenOffTimeout`. All but the lock screen's screen-off are off by default. No idle daemon is needed; one can still run beside it
(below, "hypridle and other idle daemons").

- **Screensaver** — after `screensaverTimeout` the screen is covered by a black surface
  that fades in, optionally showing the notification list. It takes the keyboard while it
  shows: the key that wakes the screen reaches no window. Commands run when you go away and
  come back (see "Commands" below). A lock while it shows takes the screen
  and the screensaver goes; an unlock counts as the user being back, with or without input
  (logind's Unlock). A profile switch while it shows keeps it (one that turns it off hides
  it without the commands for coming back); waking from sleep ends it.
- **Commands** — a list of entries (`lockscreen.commandEntries`, one value in a profile,
  overridden as a whole), each with its moment and two commands for `sh -c`, run detached:
  the first when the moment comes, the second at its end, and only after the first ran.
  Moments: every screen it waits for dark (by default every monitor that goes dark; a
  monitor that never does is not waited for; the end: your first input), locked (any lock;
  the end: the unlock, not input at the lock screen), before sleep (any sleep, the shell's
  or another program's; the end: the resume). The second command that runs is the one of
  the first: a profile switched while you are away (a stage switched off, another list)
  still runs it when you come back. The commands that ran are kept across a restart of the
  shell (a file in `$XDG_RUNTIME_DIR`, of this compositor session only): a shell restarted
  while locked does not run the lock's first command again, and the second commands still
  due run at their moment's end. In the editor the last monitor an entry waits for cannot be
  unticked. The default is one "every screen dark" entry without commands.
- **Screens off** — the shell turns monitors off itself at "Turn screens off after"
  (`screenOffTimeout`, off by default); with the screensaver off, straight from the
  desktop (an OLED's own protection mode starts even on a black picture); with the
  screensaver at or just before that time, once the screensaver has faded in. Input, an unlock and waking from sleep turn them on again, and so does a shell
  that restarted while they were off; a monitor another program turned off is left alone.
  The lock screen's screen-off waits while somebody is at it (the prompt awake, a check under
  way). On the lock screen
  they go off after `lockedScreenOffTimeout` without input there (1 minute by default,
  0 never). It needs a compositor that can cut a monitor's power — Hyprland, or elsewhere
  one with wlr-output-power-management (sway, labwc, river) and `wlopm` installed, where a
  monitor is known by the make, model and serial Qt reports (a field it leaves empty matches
  any, so a monitor keeps the times set on Hyprland); without either the screen-off shows
  the black screensaver at its time, and on the lock screen the lock surface goes plain
  black instead. A screen-off of another program (hypridle's `dpms` listener) can run
  beside it: each acts on its own times.
- **Per monitor** — with `perMonitor` on, each monitor can have its own screensaver and
  screen-off, switches and times, in `monitorIdle` (by make, model and serial; no entry:
  the default's): the laptop panel off at 2 minutes, an OLED off at 5 without a
  screensaver, an LCD with the screensaver at 5 and off at 15. One clock for all: input on
  any monitor counts for every one, and an app keeping the screen on holds every monitor.
  A monitor plugged in counts as you being back, as input: whatever was reached ends and
  the counting starts again from it (on the lock screen the lock stays). A monitor that
  drops off while dark and comes back — some do when their power is cut — is not one
  plugged in: within a minute of the shell turning it off, or 15 seconds while it showed
  the screensaver (known by its make, model and serial, its connector, or a loose match of
  them); later it is. A monitor that comes back on after each power cut is turned off again
  after a growing pause, and after a few tries left under a black surface until you are
  back. A screensaver started by hand shows on every monitor; each one's screen-off
  then comes as long after it as after its own screensaver. Where monitors cannot be turned off, a monitor
  is known by the make, model and serial Qt reports, and its own times still apply (its
  screen-off the black screensaver). The idle lock stays one for the session. Set on
  Settings → When away ("Set per monitor": a card per monitor, "Same as all monitors" or
  "Own times"; a monitor not connected keeps its times and can be forgotten), or with the
  IPC `idle setMonitorTimes <id> <json|default>` (`idle state` lists the monitors' ids).
- **Keeping the screen on** — while the session is unlocked, three kinds of request hold the
  next stage (what was reached stays; the count starts again when the last one ends): a
  Wayland idle inhibitor (a fullscreen video, an app asking the compositor), an app's
  `Inhibit` on `org.freedesktop.ScreenSaver` (browsers playing video, mpv, VLC), and a logind
  `idle` block (`systemd-inhibit --what=idle`, read at each deadline that would start a
  stage; a failed read counts as not held, logged once). While locked all three are ignored:
  the lock screen's screen-off applies. The `org.freedesktop.ScreenSaver` service is the
  shell's helper (`h2s-helper screensaver`, at `/org/freedesktop/ScreenSaver` and
  `/ScreenSaver`): it answers `Inhibit`/`UnInhibit`, `GetActive`, `GetActiveTime`,
  `GetSessionIdleTime`, `SetActive` (true starts the screensaver, not while locked) and
  `SimulateUserActivity` (counts as input), signals `ActiveChanged` (active: a monitor not
  on, or locked), and drops an app's requests when it leaves the bus. The shell asks for
  the name only while one of its idle stages is on ("Enable screensaver", "Turn screens
  off" or "Enable lock screen"); with all three off it leaves the name free, also its place
  in the queue, and asks again when one is turned on. It never takes the name from another
  owner: while another program holds it (hypridle does, unless told not to), the shell
  waits in the bus's queue and takes the name when it frees; meanwhile only that program
  hears apps' requests, and `h2s-shell ipc call idle state` names it
  (`screenSaverService`). Without the helper (not built) the shell works without these
  requests.
- **Lock screen** — a real `WlSessionLock`, so the compositor enforces it. It can be
  reached on idle (`lockAfter`), and shows a password
  prompt and optionally the notification list — the app's name only by default, or the
  title, or everything (Settings → When away; it applies to every lock), always as plain
  text with nothing to click. It also locks on request: logind's Lock
  signal for the shell's session (`loginctl lock-session`, or `HandlePowerKey=lock` in
  logind.conf) and `h2s-shell ipc call lockscreen lock`; a request while locked changes
  nothing. The lock is reported to logind (the session's `LockedHint`) once the compositor
  holds it, and cleared at the unlock. Every lock starts afresh: nothing of one lock carries into the next.
  Another program's session lock (another locker) is seen under Hyprland (`hyprctl -j
  locked`, read before every lock the shell asks — idle, IPC, logind's Lock, before sleep —
  at the start, and when the compositor refuses the shell's): while it lasts the shell asks
  no lock of its own (Hyprland would end it), a lock before sleep counts as done, the `screen.locked` profile condition holds, and
  `lockscreen status` says `foreign-locked`; it is read again with a growing pause (1 s to
  30 s) until it ends. Elsewhere the compositor's refusal is all that shows it, and the idle
  lock is asked again with a growing pause.
- **The prompt** — on one screen at a time; it wakes on a key, pointer motion or a click,
  and sleeps after 10 s without activity (a question left unanswered is cancelled then, a
  password check under way is not). A click on another screen brings it there; keys typed
  on another screen go to it where it is. No key is lost to a focus change: the key that
  wakes it is typed into it, and so are Enter and Backspace right after. Dead keys, Compose
  sequences, AltGr, the keypad and text an input method commits type into it (the input
  method is told it is a password field: nothing predicted or learned). It says "Caps Lock
  is on" when the keyboard's Caps Lock LED is lit (`/sys/class/leds/*::capslock`, read
  when the prompt wakes and at each key); with no such LED it says nothing. A middle click
  pastes nothing into it. The field empties only when
  what was sent is taken — a second Enter during a check is refused and keeps the text. It
  shows "Verifying…" while a password is checked, PAM's reason when one is refused, and
  what each passive method is doing. When the screen showing it goes away the prompt moves
  to another; a screen added while locked gets its own lock surface.
- **Unlocking** — by password, fingerprint or security key (FIDO2/U2F), each a PAM
  conversation of its own, all running side by side: a finger on the reader or a touch of
  the key unlocks with nothing typed, and a typed password is checked at once. The prompt
  shows what the reader or key last said, and when PAM asks for more after the password (a
  one-time code) the question replaces "Password" and the next thing typed answers it. An
  empty password is never sent — so an account with an empty password cannot unlock by
  password (no config allows one either: no `nullok`). A fingerprint or key config that
  asks for typed input is not used. The reader waits for a finger for as long as the
  screen is locked (`pam_fprintd timeout=-1` in the configs; a round that times out anyway
  is started again, not counted as a fault). `scripts/lock-auth-methods.sh` says which are there: the password always, the
  fingerprint when fprintd (asked over D-Bus, within 4 s) has a finger enrolled for the
  user, the key when the user has one registered where the key's PAM config looks
  (pam_u2f's `authfile`, else `~/.config/Yubico/u2f_keys`). Of those, the settings
  `lockscreen.offerFingerprint` and `lockscreen.offerSecurityKey` (on by default, per
  profile; no control on a settings page yet) leave out a method switched off: one switched
  off while locked stops at once (its conversation ends), one switched on starts; the
  password is always offered. An answer of "not there" is
  not asked again at every wake of the prompt; a question that could not be answered
  (fprintd stuck or failing) is asked again at the first wake of the prompt at least 30 s
  after the last question. Each uses
  `/etc/pam.d/h2s-shell-<password|fingerprint|u2f>` if the system has one (the NixOS
  module writes them; there the fingerprint and key work only with those, and without
  the password one the password goes through `login`, which waits for the reader first),
  else the shell's own `pam/<method>`. When
  the script fails, prints nothing or does not answer within 5 s, the password uses the
  fallback, chosen the same way (`/etc/pam.d/h2s-shell-password`, else `login` on NixOS,
  else the shipped `pam/password`); when the password's config cannot be used (PAM refuses
  to start it or reports an error), the next attempt takes the other of the two. A check
  that cannot start or never answers (90 s) shows an error, never a lasting "Verifying…".
  A config whose first auth line is `auth [default=ignore] pam_echo.so h2s-shell-lock.started`
  (the shipped ones) is watched: a check that says nothing at all within 8 s is stuck
  before any module ran, and is started again (three starts at most); after that line or
  any other word it is never started again. Configs without the line are not watched.
- **The compositor's confirmation** — the screen counts as locked once the compositor says
  so; until then the password is already checked, and an unlock waits for that word
  ("Unlocking…"), since unlocking a lock the compositor has not confirmed is a protocol
  error. A confirmation late by more than 5 s is shown ("Waiting for the compositor…").
- **Failure and recovery** — the screen stays locked whatever happens to the shell. A file
  written in its folder while locked does not reload it, not even in development mode
  (`--dev`, where the edit takes effect at the next file change after the unlock). A reload asked for while locked keeps the lock (a new
  authentication is needed); a lid closed while the shell reloads still locks before sleep
  (with lock before sleep on) as long as the lock is up within a few seconds.
  A shell that dies while locked — a crash, a kill, the OOM killer, `qs kill`,
  `h2s-shell --restart` — is started again by the launcher (`h2s-shell`, which stays as its
  supervisor, one per session) or by Quickshell's own crash handler, and
  locks again at once: it finds the lock marker it left in `$XDG_RUNTIME_DIR`. A shell
  stopped on purpose while unlocked is not started again; one that keeps dying while
  unlocked is given up after 5 quick restarts in 2 minutes. What it left behind (a
  fingerprint conversation holding the reader) is killed. Under Hyprland this needs
  `misc:allow_session_lock_restore = true` in the Hyprland config; without it Hyprland
  keeps its "lockscreen app died" screen, the shell says `compositor-locked` and waits for
  the setting.
- **The limit while locked** — the launcher starts a shell that died while locked at most 3
  times while the session stays locked (an unlock starts the count afresh; Quickshell's own
  restarts in place are not counted). When it dies a fourth time the launcher gives up and
  ends: the session stays locked, at the compositor's own screen (Hyprland: "lockscreen app
  died"), and is never unlocked by this. The way back is a text console (Ctrl+Alt+F2, log
  in): read what happened (`h2s-shell --lock-log`, or the launcher's log
  `$XDG_RUNTIME_DIR/h2s-shell-launcher.log`), fix what kills the shell if it is known, and
  start the launcher again inside the session — with `WAYLAND_DISPLAY` and
  `HYPRLAND_INSTANCE_SIGNATURE` set to the session's (`hyprctl instances` lists both):
  - NixOS: `h2s-shell --restart`
  - Arch: `~/.config/quickshell/default/scripts/launch.sh --restart` (the checkout
    `install.sh` made; its `--lock-log` is the log command)

  The new shell locks again at once (the marker), so the password or finger unlocks the
  session as usual. Once it is unlocked, one notification says that the shell stopped
  while locked, after how many restarts, and where the launcher's log is.
- **Other ways out** — logind's Unlock for the shell's session (`loginctl
  unlock-session`, from another console), and the compositor ending the lock. There is no
  unlock over IPC, and no key unlocks: Escape shows a hidden prompt (as any key) and hides a
  showing one, emptying the field (as the prompt's time-out does); a held Escape's repeats
  count for nothing.
- **Sleep** — with Settings → When away → "Lock before the computer sleeps" on
  (`lockscreen.lockOnSleep`, off by default; on while the settings file cannot be read), the
  screen locks before the computer sleeps, the
  shell holding a logind delay inhibitor (`systemd-inhibit`) until the compositor confirms
  the lock (at most 4 s), so the desktop is not what shows on waking. The fingerprint and
  key conversations stop for the sleep and start again after it, with the methods looked
  for again; the inhibitor is taken again after every wake, and when it is lost.
- **Sleep when idle** — with Settings → When away → Sleep on (`sleepEnabled`, after
  `sleepTimeout`, 30 minutes by default), the shell asks logind to suspend the whole computer
  (`Suspend`, non-interactive) once per idle period. Only where logind answers `CanSuspend`
  "yes" (read at the start and when the page opens): where a polkit rule wants a password
  ("challenge") the section says "Not available here: the system asks for a password to
  sleep" and nothing is asked. Apps keeping the screen on hold it while unlocked (a forced
  screensaver too, after which it comes no sooner than it would after the screensaver's own
  time), not while locked; logind's `sleep` block inhibitors (`systemd-inhibit --what=sleep`,
  a backup) are read before the call — which goes only after a read found none — and pause
  it, locked or not ("Paused: borg blocks sleep" under the
  timeline). An idle lock due no later than the sleep is waited for a moment, so it goes down
  locked; "Lock before the computer sleeps" locks at the sleep as for any other. With neither,
  the section says beforehand that it sleeps unlocked, and the notice below does not count
  that sleep. logind's own `IdleAction` (logind.conf) is read and, when it acts, the section
  says so — whichever comes first acts. The same on NixOS and Arch (systemd-logind on both).
- **Hibernate when idle** — Settings → When away → Hibernate (`hibernateEnabled`,
  `hibernateTimeout`, 2 hours by default). With sleep on, the shell's sleep is logind's
  `SuspendThenHibernate`: the system wakes the computer after its own delay and hibernates it
  (sleep.conf's `HibernateDelaySec`, one setting for the machine — the shell cannot pass a
  delay). When the profile's time differs from that delay, the timeline and the line under
  the times show what will happen — the system's delay — and the section says the picked time
  takes effect after Apply on Arch, or names the module option on NixOS (below). With sleep off, the shell
  hibernates the computer itself (`Hibernate`), counted from the last stage switched on before
  it — the screensaver (per monitor: the latest of the connected monitors') or the lock,
  whichever comes later; neither: the last input — and the row says from where ("after the
  lock"), with the time from the last input under it. Only where logind answers
  `CanSuspendThenHibernate` (sleep on) or `CanHibernate` (sleep off) "yes"; otherwise
  "Not available here" with the reason the shell can read without root: a password asked
  ("challenge"), the kernel's lockdown (Secure Boot), no swap or only zram (lost at
  power-off), swap smaller than the memory in use, no resume device. Apps keeping the screen
  on and logind's `sleep` blocks hold it as they hold sleep. logind judges a hibernation at
  the call (swap against the memory in use then): a `SuspendThenHibernate` it refuses is
  followed, after a fresh read of its inhibitors, by a plain `Suspend`, so the computer
  still sleeps.
  - **NixOS**: `/etc` is generated: set the delay with
    `programs.h2s-shell.idle.hibernateDelay = "3h";` (it goes into sleep.conf). Hibernation
    itself needs a swap device (`swapDevices`) and `boot.resumeDevice`.
  - **Arch**: Apply writes `/etc/systemd/sleep.conf.d/h2s-shell.conf` (`[Sleep]`,
    `HibernateDelaySec=`) through pkexec, asking for the password on that click, keeping the
    file it replaces as a backup that Undo puts back; Undo goes back one change, to the file as
    it was before the last Apply. When another file sets the delay, the section says "Set in
    <file>: <value>". A file systemd reads after the shell's (a drop-in in any of its folders
    whose name sorts after `h2s-shell.conf`) wins over it: no Apply is offered. A file read
    before it (your own `/etc/systemd/sleep.conf`, a vendor drop-in sorting before it) would
    lose to it: Apply asks first ("Use the shell's value instead?"). When the shell's own file
    was changed by hand, the section says so and Apply asks once more before replacing it.
    Hibernation
    itself needs a swap partition or file (zram does not count) and the `resume` hook in the
    initramfs (or `resume=` on the kernel's command line).
- **Not locked while asleep** — at each sleep the shell looks whether the session is
  locked: its own lock, the compositor's lock state on Hyprland (`hyprctl -j locked`), else
  logind's LockedHint (set by lockers that report their lock). For that it holds a logind
  delay inhibitor of its own while awake ("Check the screen is locked before sleep") and
  lets go as soon as it has seen a lock, or a second after the sleep began when it has not
(longer only while its own lock before sleep is still coming up). After a
  sleep that went down unlocked it shows a critical notification, "Not locked while asleep",
  once; clicking it opens Settings → When away at the lock screen's section, closing it
  acknowledges it, and that section keeps a line until a sleep locks. The next unlocked sleep after that is told again. No program is named: off
  Hyprland, a locker that does not set LockedHint cannot be seen, and nothing is said then.
  The state is remembered in the config. The same on NixOS and Arch (systemd-logind on both).
- **The log** — every authentication event leaves a `[Lockscreen]` line in the shell's
  log (what was asked, started, answered, refused, why a lock ended), never what was
  typed: what to read when unlocking fails on the real machine.
- Design and tests: `docs/ARCHITECTURE.md` ("Lock screen"),
  `tests/LockRulesTest.qml`, and the end-to-end test bed `tests/lock/`.

### hypridle and other idle daemons

The shell needs no idle daemon, but one can run beside it. Both act on the same idle time,
so for each job pick one side and turn it off on the other:

| Job | In the shell (Settings → When away) | In hypridle (`hypridle.conf`) |
|---|---|---|
| Screensaver, dimming | the Screensaver section's switch, `screensaverTimeout`; the command entries (`commandEntries`) run when every screen they wait for is dark, at a lock or before sleep, and at the end of that moment | a `listener` whose `on-timeout` dims (`brightnessctl`) and whose `on-resume` restores |
| Screens off | "Turn screens off" and `screenOffTimeout` (per monitor with `perMonitor` and `monitorIdle`) | a `listener` with `on-timeout = hyprctl dispatch dpms off` and `on-resume = hyprctl dispatch dpms on` |
| Screens off on the lock screen | `lockedScreenOffTimeout` (60 s by default; 0 leaves it to the daemon) | a short `listener` that turns screens off only while locked |
| Lock when idle | "Lock when idle", `lockAfter` | a `listener` whose `on-timeout` is `loginctl lock-session` |
| Lock before sleep | "Lock before the computer sleeps" (`lockOnSleep`) | `before_sleep_cmd = loginctl lock-session` |
| Screens on after a wake | always: the monitors the shell turned off | `after_sleep_cmd = hyprctl dispatch dpms on` (needed while hypridle turns screens off) |
| Apps keeping the screen on | always, while unlocked: Wayland inhibitors, logind `idle` blocks, and `org.freedesktop.ScreenSaver` when the shell holds the name | `ignore_wayland_inhibit`, `ignore_systemd_inhibit`, `ignore_dbus_inhibit` in `general` |
| Suspend when idle | the Sleep section's switch, `sleepTimeout` (logind's `Suspend`) | a `listener` with `on-timeout = systemctl suspend` |
| Hibernate when idle | the Hibernate section's switch, `hibernateTimeout` (logind's `Hibernate`, or `SuspendThenHibernate` with sleep on) | a `listener` with `on-timeout = systemctl hibernate` |

Whichever side locks, the lock is the shell's: it follows logind's Lock signal for its
session, so `loginctl lock-session` (and a power key set to `lock` in logind.conf) locks it.
hypridle's `lock_cmd` runs on that same signal, so it must not start another locker (two
lockers race for the screen, and only one can hold it); leave `lock_cmd` out, or point it
at the shell's IPC lock — a lock asked while locked changes nothing. Another locker that
does lock is seen under Hyprland (above, "Lock screen").

**The `org.freedesktop.ScreenSaver` name** has one owner, and apps' keep-awake requests
reach only that owner. The shell asks for it only while one of its idle stages is on, never
takes it away from another owner, and otherwise waits in the bus's queue; hypridle asks for
it unless `ignore_dbus_inhibit = true`, and finding it taken says "Another service is
already providing the org.freedesktop.ScreenSaver interface" in its log. So with the shell's
stages in use, set `ignore_dbus_inhibit = true` in hypridle's `general` (or the requests
reach whichever started first); with all of the shell's stages off, the name is hypridle's.

**Keeping hypridle for everything idle** is a working choice: turn the shell's stages off
(Settings → When away: the screensaver, "Turn screens off" and "Lock when idle" off, "Turn
screens off on the lock screen" Never), keep hypridle's listeners, and lock with
`loginctl lock-session` or the IPC lock. The shell then leaves `org.freedesktop.ScreenSaver`
free. hypridle asks for the name only when it starts and does not wait for it, so if it was
running while the shell held the name, restart it after turning the shell's stages off;
from then on apps' requests hold hypridle's listeners. Whenever the name changes owner, the
requests made before are lost until each app asks again (most ask at their next video). The
lock screen itself stays the shell's.

**Moving over to the shell** takes the table from right to left: set the times in Settings →
When away (each counted from the last input, as hypridle counts), then remove the listeners
the shell now covers — or hypridle altogether, after which the shell takes the
`org.freedesktop.ScreenSaver` name by itself (at once while it runs and one of its stages is
on: it waits in the bus's queue). Only an idle suspend has no counterpart in the shell. The shell's IPC lock, for
hypridle's `lock_cmd` or a key binding, and how to stop hypridle:

#### NixOS

- The IPC lock: `h2s-shell ipc call lockscreen lock`.
- hypridle from Home Manager: `services.hypridle.enable = false;` (its listeners are in
  `services.hypridle.settings`); started from the compositor's autostart instead: remove
  that line. Then rebuild.

#### Arch

- The IPC lock, from the checkout `install.sh` made (no `h2s-shell` is on `PATH`):
  `"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/default/scripts/launch.sh" ipc call
  lockscreen lock`.
- hypridle as a user service (the package ships `hypridle.service`): `systemctl --user
  disable --now hypridle`; started from `hyprland.lua`'s autostart instead: remove that line
  and end the running one (`pkill hypridle`). Its listeners are in
  `~/.config/hypr/hypridle.conf`.

swayidle and other idle daemons are the same story: their timeouts map to the same settings,
their lock command must call the shell (or nothing), and one that owns
`org.freedesktop.ScreenSaver` keeps the shell waiting for it.

## Network settings

Settings → System → Network unfolds into its pages. **Overview**
(`singletons/network/NetworkOverview.qml`): online or not (NetworkManager's connectivity),
the Wi-Fi, mobile broadband, airplane-mode and networking switches, each device with its
hardware, MAC, speed, Wi-Fi signal and channel, addresses, gateway, DNS, search domains and
MTU (bridges, containers' and tunnels folded under "Other devices"), and the hostname, a
global DNS and the connectivity check — through `nmcli` and NetworkManager's D-Bus
properties (`busctl`); a change refused for want of rights goes to the polkit prompt. The
connectivity check's address is NetworkManager's configuration, which the page reads in
NetworkManager's order: an address set in another of its files is shown with the file ("Set
in <file>: <address>"), not overridden when that file is read after the shell's, and
overridden only after asking when it is read before.

**Wi-Fi** (shown when the computer has Wi-Fi): the radio's switch on the page's heading, the
network in use, the saved networks with connect, edit and forget on each card's name line
(under the name in a narrow window or while a long question asks),
autoconnect, priority and the password (shown for 30 s, or changed) when it is opened, a hidden network, and "Find networks": the networks in range sliding in from
the right — the popup's own list (`panels/network/WifiNetworkList.qml`), so connecting works
the same in both; the Overview's Wi-Fi card and summary line lead there. **Hotspots**:
this computer's own networks (Wi-Fi profiles in access-point mode, IPv4 "Be the router"),
each a card like a saved network's — turn on (asking first when it would leave the network
the Wi-Fi is on with no cable or modem to share), turn off (by the profile, so the saved
network comes back), start automatically, the password shown, the devices on it (IP and
MAC from `ip neigh`, every 5 s), edit, forget; "New hotspot" opens the editor on a fresh
one: the computer's name, 2.4 GHz, WPA2, a random 12-letter password.
While one is on, the network popup shows it in the Wi-Fi network's place (devices, speed,
address, "Turn off hotspot") instead of the list, and the bar shows an access point. The
popup lists the saved hotspots under the hidden network (`panels/network/HotspotRow.qml`),
each with "Turn on".
**Ethernet** (with a wired device): each device's card or "Cable unplugged", and the wired
profiles with use or disconnect, autoconnect, priority and forget.
**The connection editor** (a profile → Edit,
`panels/settings/NetworkConnectionEditor.qml`): general, IPv4, IPv6, DNS, routing (only
its own network, route metric, require the family), "Be the router" (this computer's
address, the range handed out, the lease time), and the Wi-Fi's or the cable's own
settings; every option explained (on hover, and the picked one's under it); wrong fields marked (`NetworkRules.editorErrors`), only the
changes sent, in one `nmcli connection modify` (`editorChanges`); on the connection in use,
"Save and reconnect" and a 20 s "Keep these settings?" that puts the old ones back.
Saved profiles are known by UUID (`NetworkProfiles`); commands that change something report
nmcli's errors (`CommandAction`, `Nmcli.errorKind`).
**VPN** (`panels/settings/NetworkVpnSettings.qml`): each VPN profile as a card — its kind
(WireGuard, or its plugin's), whether it is up, its server; connect, disconnect, start
automatically (WireGuard), edit, delete; while up its interface, address, DNS, the data it
moved and its speed. "Import…" makes a profile from a VPN's file (a WireGuard .conf —
imported off, from a copy named for a valid interface —, an OpenVPN .ovpn, another
plugin's); "New WireGuard" opens the editor on a fresh profile. WireGuard's part of the
editor: interface, private key (Generate with `wg`, the public key shown to copy; pasted
when wireguard-tools is missing, which a note says), listen port, MTU, the peers (public
key, endpoint, allowed IPs with "All traffic", preshared key, keepalive). A Wi-Fi or wired
profile's editor picks VPNs to "Connect a VPN with it" (`system.vpnWithNetworks`,
VpnManager, `VpnWithNetworkRules.vpnWithNetworkPlan`): wanted while a linked network is up, taken
down when none is if the shell brought them up (remembered in Config), held down when
taken down by hand — the shell's doing, from its start (shell.qml), as
NetworkManager's connection.secondaries takes no WireGuard; the VPN's card lists them.
Only through the VPN (`singletons/network/VpnLockdown.qml`): always, or on the networks set
for it in their editors — the table `inet h2s_vpn_lockdown`, built by
`scripts/h2s-vpn-lockdown` (root's, through pkexec; it takes checked settings, never rules),
letting out only loopback, the VPNs' interfaces and servers, virtual interfaces, DNS, DHCP
and IPv6 ND, and the local network when allowed; passed-on traffic only through a VPN.
"The VPNs' interfaces" are NetworkManager's VPN profiles' and any named `tun*`, `tap*`,
`ppp*`, `vpn*` or `wg*`; the virtual ones `docker*`, `br-*`, `veth*`, `virbr*`, `podman*`,
`vnet*`, `lxc*`, `incus*`. A provider's VPN (Tailscale's `tailscale0`) is not let through
unless its interface matches those names; its card says so while blocking, and a network
editor that links one to a blocking network, or the VPN page with "always" on, says it
cannot connect.
Only the installed script runs — a copy root owns (`scripts/vpn-lockdown-check.sh` checks it
is a regular file nobody else may change, in folders nobody else may change), with a polkit rule letting this user run it
without a password; never the shell's own copy in its tree. Installed so, it switches by
itself, and its `status` is checked at the start, after network events and every 5 minutes
to mend a firewall reload. Without it nothing switches and nothing asks for a password by
itself: the page says the blocking needs its script installed. When the installed script
still asks (its rule does not apply), a question opened by an automatic run is closed at
once and nothing runs by itself; with another polkit agent, whose question the shell cannot
see, an automatic run that pkexec ends refused or unanswered stops the automatic runs the
same way. "Apply again" runs it on a click, with its question; a run on a click that needs
no password, or the page opened again, lets it switch by itself again. While the blocking is
wanted but nothing may switch it, a notification says so once. What
was switched on in which boot is kept in Config. "Password-free blocking" shows the state,
the script and the rule in full; how it is installed is the distribution's
(`network.vpnLockdown`; elsewhere "Not supported on this distribution.").
"Files you can import" lists each kind (`NetworkRules.vpnImportKinds`) with its
files and whether it can be imported now — a missing plugin named with what it is for,
other installed plugins after. Modem follows.

#### The connectivity check's address: NixOS

The address is the option `networking.networkmanager.settings.connectivity.uri`: "Copy for
configuration.nix" copies the line; "Write anyway" writes NetworkManager's file outside the
system's configuration, without Undo.

#### The VPN blocking's script: NixOS

A module to save as `/etc/nixos/h2s-vpn-lockdown.nix` and import holds the script, nftables
and the polkit rule ("Copy the module", "Show the module", "Check again"); the script is
looked for at `/run/current-system/sw/bin/h2s-vpn-lockdown`, the rule in
`/etc/static/polkit-1/rules.d`.

#### The VPN blocking's script: Arch

Install… writes the script to `/usr/local/libexec/h2s-vpn-lockdown` and the rule to
`/usr/share/polkit-1/rules.d/49-h2s-vpn-lockdown.rules` with one password; Remove… takes the
shell's away; each keeps both files as they were in `/var/lib/h2s-shell/vpn-lockdown-backup`
for Undo. A script or rule there that the shell did not write is shown ("Show what is there")
and replaced only after "Replace…" asks; Remove leaves it. polkit also reads
`/etc/polkit-1/rules.d`, which the user cannot read: a rule of the same name there takes the
shell's place (the page says so). A folder at the script's place (an older install's layout)
is never run; the page names it.

#### The connectivity check's address: Arch

Save writes `/etc/NetworkManager/conf.d/90-h2s-connectivity.conf` (Default removes it), keeping
the file it replaces as a backup that Undo puts back, and NetworkManager reads its
configuration again.

## Authentication prompts (polkit)

The shell can be the session's polkit agent (`singletons/Authentication.qml`,
`polkit/AuthPrompt.qml`): when a program needs an administrator's rights, a prompt over
the focused screen, the rest dimmed and the keyboard held, says what asks, lets the
account be picked, shows PAM's messages and asks again after a wrong password. Only one
agent can answer per session, so `system.polkitAgent` is decided at the first start (off
when a known agent runs, on when the shell registers) and changed in Settings → System →
Authentication, which also shows what answers now. Notifications say when no agent answers
or another one cannot register beside the shell's.

When a module runs something as administrator, the prompt also says who asks and what for:
"Module" (the module's name, with its id in brackets) and "Authorization" (what the run
does, in the module's few words) under the title, and "Command", which opens on a click to
the command handed to pkexec, whole. A command of the shell's own (the Hibernate section's
Apply) is announced the same way, on a "Shell" row reading "h2s-shell", which no module's name
can take. These lines are attached when polkit's own message
names the module's command; another program's request shows polkit's message alone. polkit
names a command longer than 80 bytes by its first and last few words only, so another
command that starts and ends the same way would get the same lines: they say what a module
asks, they do not guard against a program bent on fooling the user. Every text in the
prompt is plain text. When another password agent answers instead of the shell (or none
does), the shell cannot add these lines to that agent's prompt: just before a module's run
starts, a notification names the module and what the run does ("Module: Tailscale",
"Authorization: Send a file"). It does not mean a password will be asked; that is up to the
other agent. When the screen locks, an open prompt is cancelled: the program asks again when
the user tries again after unlocking.

polkit's helper runs one PAM stack, `polkit-1`; NixOS puts a fingerprint reader first in
it, so PAM asks for the password only after the reader gives up (30 s, or three fingers
that do not match). The prompt's field is there from the start: a password typed and
Entered meanwhile is held and sent the moment it is asked for, and a line under PAM's
message says what the prompt waits for (`PolkitRules.conversationHint`). Settings → System →
Authentication says which order this computer has (read from `/etc/pam.d/polkit-1`).

#### NixOS

The module's `programs.h2s-shell.pam.rules` (or `pam.polkit.rules`) sets polkit's `auth`
rules — a password row above the fingerprint row asks the password at once —, and sudo's
(`pam.sudo.rules` for a list of its own); the README's "sudo and polkit" has the rows. The
rows go above NixOS's own rules (the `system` row) or replace them; NixOS's own fingerprint
and key rules are off where the shell's rules are. A list that would keep everyone out stops
the build with an assertion; a module from outside the store, or a store path written out,
is a warning. Without polkit rules the deprecated `programs.h2s-shell.polkit.passwordFirst`
(on by default with fprintd) still moves pam_fprintd after pam_unix: the password is asked at
once, and Enter on an empty field goes on to the reader.

#### Arch

polkit's stack is the system's `/etc/pam.d/polkit-1`, else the vendor file in
`/usr/lib/pam.d`, as it is.

### Sign-in rules

Settings → System → Authentication, under the polkit agent's rows, sets how sudo and
administrator prompts (polkit) ask who you are (`panels/settings/PamRulesSection.qml`). At
the top what is in force now, as steps per service (e.g. fingerprint → password; one row when
both ask the same, "not known" when a file cannot be read), what the computer has (a finger
enrolled, a security key registered) and where the rules go; all of it is read again each
time the page shows, the window reopened included (fprintd is asked again). "Separate rules for
administrator prompts" gives each service a list of its own; turning it off while they differ
asks first. Each list holds rows tried from the top: a method (fingerprint, security key,
password, a raw PAM line) with PAM's control word and its details as chips, and the fixed
last row "Password (as the system)" — the service's own lines, kept as they are; removing it
asks first. A row opens to its control words (with what each means), the fingerprint's
timeout and tries (each may be "No limit"), the key's PIN, whether wrong passwords count
toward pam_faillock, or a raw line's text. Rows are dragged by their handle; "Add a row"
lists the methods, those the computer lacks off with the reason. Under each list its checks:
refusals in red (nothing is saved while one stands), warnings in the warning colour. A raw
line that asks for nothing is refused where it lets anyone in on its own (at once, or a line
that must pass with no other such row that still asks — a line counts as one that must pass
only where a wrong credential's code, `auth_err`, else `default`, is `bad` or `die`); beside
a row that still asks it is a warning: only the other rows decide. A
security key row whose check pam_u2f's settings void gets a warning, not a refusal — the
settings are the system's, kept as they are: `alwaysok` (no key), `userpresence=0` (the last
one, as pam_u2f reads it: no touch), and on a raw line whose word takes PAM_IGNORE as no
answer `nouserok` (a user without a key). Where the row lets in on its own the warning says
so; where another row that must pass still asks ("Password (as the system)" among them) it
says the row no longer asks and only the other rows decide. The shell's own key rows, and
raw lines whose ignore is not "ignore", treat PAM_IGNORE as a failure, so `nouserok` never
opens them. The settings read: on NixOS the module's
`/etc/pam.d/h2s-shell-u2f` (`security.pam.u2f.settings`), elsewhere
`/etc/security/pam_u2f.conf`; a raw pam_u2f line by its own words (a refusal where it lets
in on its own) and by `pam_u2f.conf`. Settings that cannot be read — the file, or which
system this is or where the file is not known — or a settings file a raw line names itself,
are a warning too. "Show
file" shows the file that would be written, the shell's lines in the accent colour.
What the page offers is the distribution integration's (`pam.rules`): Apply on Arch, the
options to copy on NixOS; on a distribution the shell does not know, only what is in force
and the lock screen's switches, with "Not supported on this distribution."

#### NixOS

`/etc/pam.d` is NixOS's: the page shows the module's options for the rows
(`programs.h2s-shell.pam`), with Copy; they take effect after `nixos-rebuild switch`.

#### Arch

Apply first tries the new rules as you, in the shell's own prompt, on a private copy (nothing
is written yet); only when they let you in is each file written, as administrator (sudo,
then administrator prompts: "1 of 2"). The old file goes to `/var/lib/h2s-shell/pam-backup`
first; Undo puts it back. When the second write stops, the page says which file was
written ("Saved in part"), Undo puts that one back, and the list warns that the two services
now differ. A file changed outside the shell is shown read-only with the
offending lines marked: "Read again", or "Replace…", which takes its lines in as rows (what
the editor does not make itself as raw lines) and replaces it at the next Apply.

### Unlocking the lock screen

Under the sign-in rules, which ways the lock screen offers: the password always, the
fingerprint and the security key each with a switch (`lockscreen.offerFingerprint`,
`lockscreen.offerSecurityKey`), off and dimmed with the reason while the computer lacks one,
and what it needs: fprintd or pam_u2f, named as the system gets it (Arch: the package;
NixOS: the option), and an enrolled finger or a registered key.
Changed at once, without a password. Under the security key a warning when the system's
pam_u2f settings let it unlock without a key (`alwaysok`) or a touch (`userpresence=0`),
hold `interactive` (the key will not work: the lock screen cannot answer its Enter prompt),
or cannot be read; and a note when the NixOS module left `interactive` out of the lock's
config. Read: the lock's key config's pam_u2f line and the settings file it reads (its
`conf=`, else `/etc/security/pam_u2f.conf`; on NixOS pam_u2f's default file lives inside its
package, where nixpkgs installs none, and is not read). `nouserok` is not said there: the
lock's one line must pass, so a user without a key is refused.

### Remember the password

Under the lock screen's switches: after the administrator password is typed for one of the
shell's own root runs (a module's action, a PAM write, the Hibernate section's Apply), the
next ones pass without asking for a while. Other programs' pkexec still asks.
"Remember for" (`system.rememberAdminMinutes`, 1–60 min, 5 by default) sets how long: shorter
than the system keeps a password, the shell forgets it itself (for every program in the
session); longer, the system's length changes for every program. Under the buttons one box
says whether the rule is installed (outdated, or changed outside the shell), how long the
system keeps a password and where that comes from, where the files are, and, while a password
is kept, "Remembered, 4 min left", counting down, with "Forget now". It is also forgotten
when the screen locks and when the shell restarts. While kept, "Try the prompt" says no
prompt will show, and a module's lock marks show an open, dimmed lock. The shell's prompt
says "Remembered for 5 min" under the password field for its own runs while the rule is
installed (not for an old module's runs, which do not go through the shell's `timeout`).

#### NixOS

The page shows the module's option `programs.h2s-shell.polkit.rememberAdmin` built from the
setting, with Copy; it is in force after `nixos-rebuild switch`, and the page reads it back.

#### Arch

Install writes the rule (`/usr/share/polkit-1/rules.d/40-h2s-shell.rules`) as administrator,
and, when the setting is longer than the system's length, `/etc/polkit-1/polkitd.conf`;
"Install again" follows a longer setting or a moved `timeout`; Remove takes them away. Each is
one password prompt (none while a password is kept). The old files go to
`/var/lib/h2s-shell/polkit-backup` first; Undo puts them back. A file changed outside the
shell is shown with the lines that are not the shell's marked: "Read again", or "Replace…",
whose question names every file it touches; a hand-made file it does not name stays as it is.

## Settings

A separate floating window, reachable from the Settings widget, from
`Shell.openSettings(pageId)`, or over IPC — which also works with no Settings widget on
the bar: `qs ipc call settings open`, `openPage <id>` (a page's id, e.g. `openPage profiles`,
`openPage bar_appearance`), `currentPage` (the open page's id), `itemRect <objectName>` (where a shown item is in the window, for tests), `toggle`, `close`. Three tabs: **Behaviour**, whose pages edit
a profile; **Appearance**, whose pages edit a theme; and **System** (Authentication,
Network), whose pages change this computer's settings, at once and in every profile. The sidebar shows which profiles
are active right now, and picks what the tab's pages edit — the profile (with the theme it
uses, a click away) or the theme (with the profiles that use it, and Preview to show it
on the whole shell while editing).

Behaviour pages:

| Page | Covers |
|---|---|
| **Profiles** | the profile list: conditions, order, enable switch, rename, delete, simulation of conditions for testing |
| **General** | debug switches and the icon theme (always global; the icon theme is picked from the installed ones, with sample icons, and applies on a restart — "Restart to apply"); the profile's theme, animation speed and reduced motion |
| **Calendar** | enabling Google Calendar, the account connection, which calendars are enabled, debug |
| **Media** | audio visualiser style, layout and frame rate; the cover's rounding and rotation |
| **Bar** | the content of the three sections, including each widget's popup mode and preset |
| **Notifications** | toasts: on or off, whether apps choose how long, the time, one at a time or a column, each queue's limit, moving by dragging, resident ones counting down, the screen and a fullscreen window there; code-extraction regex patterns |
| **When away** | what happens while nobody uses the computer, in the order it happens. At the top, "Set per monitor" and a timeline from the last input: a lane per monitor (per monitor) with its screensaver and screen-off, the lock, the sleep and the hibernation as lines across them (the last of them, long after the rest, after a break "≈"), a mark for each command entry's moment (▸1, ▸2); times that would collide labelled on the other side of the line; always drawn, its line under it saying what the lock screen does, nothing at all, or which app keeps the screen on or blocks sleep ("Paused: …"). **Screensaver** (its switch on the title line): its time, "Turn screens off" and its time, the per-monitor cards, how it looks (fades, notifications) — dimmed while no monitor shows it. **Lock screen** ("Lock when idle" on the title line, which dims only its time; the rest serves every lock): lock before sleep (off by default) and the sleep notice's line, screens off on the lock screen, its notifications, signing in (→ Authentication). **Sleep** (its switch on the title line; "Not available here" with the reason where logind will not let the shell sleep the computer without a password): its time, whether it locks first or sleeps unlocked, and a warning when logind sleeps the computer by itself. **Hibernate** (its switch on the title line; "Not available here" with the reason): its time — after sleeping with sleep on (the system's delay compared, Apply and Undo on Arch, the NixOS option named, a delay set in another file shown), else after the lock, the screensaver or the last input — and when that is from the last input. **Keeping the screen on**: the apps holding it now. **Commands**: a list of entries, each a line (its number, its moment with its time — greyed when it can no longer come —, its two commands cut short, Edit, Remove); editing opens its moment (Screens dark, Locked, Before sleep), for Screens dark the monitors it waits for as chips with their dark times (one that never goes dark greyed, not waited for), and its two commands; "Add commands". Parts that open on a switch slide open and shut (at once with reduced motion). Opened at the lock screen's section by the sleep notice; its id stays `lockscreen` (`settings openPage lockscreen`) |
| **Dictation** | transcript preview, pending counter, music pause, socket path and debug (always global), and the daemon's wake configuration (read-only) |
| **Performance** | polling rates of hardware, temperatures, disk and network, GPU load sampling, graph heartbeat, the system power profile |

Every setting shows where its value comes from in the edited profile — set there,
inherited from a profile above it, the default, or global — with a pin to make it the
same in every profile and a reset to inherit again.

Appearance pages:

| Page | Covers |
|---|---|
| **Themes** | the picked theme: who uses it, what is wrong with it, what it extends; new theme (extending it, or a copy), rename, delete |
| **Curves** | the curves library shared by every theme: a graph editor with any number of points, a looping preview, compare, save, rename, delete, where each is used |
| **Colors** | the theme's base colours by group, with a colour picker |
| **Fonts** | the font family (any installed; missing glyphs such as icons come from another font) and 13 sizes |
| **Bar** | the bar's height, reserved space, offset, margins, padding and corner radii |
| **Animations** | each animation role's duration and curve, with a preview |

On the theme's pages each value shows where it comes from — changed, set in the theme,
inherited from the theme it extends or its palette, built in — with Reset and Undo.
Changes are drafts (`~/.config/h2s_shell/theme-drafts/`), kept until saved, also across
restarts: each page has Save and Cancel, a banner saves or throws away all of the theme's
changes, and ✎ marks pages and themes with unsaved changes. Themes are files in
`~/.config/h2s_shell/themes/`.

### Profiles

A profile is a named set of setting overrides that applies while its conditions hold:
on battery, battery below a level, a system power profile, screen locked, a fullscreen
window, a given popup open. Several can apply at once; the one lower in the list wins.
New configs start with **Full** (always on, today's behaviour spelled out) and **Power
save** (on battery: slower polling, no graph heartbeat, 15 fps visualiser, the
power-saver system profile). With no profiles, built-in defaults apply.

Changes apply live and are written to `~/.config/h2s_shell/config.json`, debounced by
one second.

## Modules

Integrations can come as modules, loaded into the shell (see
[Modules](ARCHITECTURE.md#modules)). A module runs inside the shell with the user's rights:
it could read anything the shell sees, the lock screen's password included. The shell's
checks catch mistakes, not a module built to get around them. Built-in modules come with the
shell; modules a system administrator installed are theirs to answer for; modules on a
developer's development path (`H2S_SHELL_MODULE_PATH`) are not asked about; any other module
is its author's work, and the shell waits for the user's confirmation before it first loads
one, and again when it starts to declare administrator actions or names another author. The
confirmation guards against mistakes and against modules put there unnoticed, not against a
program already running as you: on Arch the built-in modules' folder
(`~/.local/share/h2s-shell/builtin`) is yours, and what lies there loads without a question. A
module asks for administrator rights only through the shell's password prompt, which names
the module, what the action is for and the command — read it, and cancel when it does not
match what you just did. Install a module only from someone you trust, pinned to a tag.

Settings → System → Modules → Installed lists every module as a card: the enabled ones
first, their names in the accent colour, then the ones turned off, muted, "Off" under the
name. A pill stands beside the name only for a state that needs attention (Failed, Needs …,
New — off, Approval required); warnings and deprecated API uses are marks with a count, their
tip on hover. Opened, a card shows the module's description, where it comes from (and the
copies it replaces), the API it asks for, whether it runs administrator actions, the modules
it needs, can use and is used by, its programs, its errors and warnings as written, and its
data folder. "Enable" asks for the confirmation first when the module is not part of
h2s-shell; "Disable" asks on the button, or in a dialog listing the running modules that need
it, which are disabled with it. "Remove", offered for what your modules folder holds, asks
first what it deletes (only the link of a module you linked; the folder of one placed by
hand), names the modules that stop working, and offers to delete the module's data and
settings and the modules installed only for it — all unchecked. "Check all" and a card's
"Check for updates" look for newer versions of the modules installed from a repository; each
card shows the result under its name, and a downloaded update an "Update to …" button.
"Add a module" installs one from a repository address or a folder: the downloads with their
progress, then a preview — what it is and where it comes from, its programs, the modules it
brings or needs, the statement for each module not part of h2s-shell, the changelog in the side
panel — before anything moves in; "Cancel" deletes the downloads. Updates run in one queue
shown on the page; an update that needs approval asks on its card ("Update" / "Keep"), "Switch
version…" goes to a kept version or a tag, "Backups…" restores a module's settings, and when the
queue ends the shell offers one restart ("Later" keeps a banner over Settings until then).
Modules' own settings pages follow under the Modules group.

## External dependencies

Beyond Quickshell and Qt 6, the shell shells out to:

| Tool | Used for |
|---|---|
| `nmcli` (NetworkManager) | all network state and actions |
| `hyprctl` / Hyprland IPC | workspaces, logout — expects a Lua config (`hyprland.lua`, Hyprland 0.5x): special workspaces and logout dispatch `hl.dsp.*` Lua expressions |
| `systemctl` | restart, shutdown |
| `gdbus`, `systemd-inhibit` (logind) | the lock screen: lock requests, sleep and wake, holding the sleep until locked |
| `gdbus` (fprintd), `timeout`; PAM (`pam_unix`, `pam_fprintd`, `pam_u2f`) | unlocking: which methods there are (`scripts/lock-auth-methods.sh`), and the checks themselves (fprintd and pam_u2f optional) |
| `notify-send`, `gdbus` | the shell's own outbound notifications (`gdbus` for those with a progress bar, a module's among them) |
| `jq`, `gsettings` | `scripts/launch.sh`: the icon theme setting from the config, the system's icon theme for "Automatic" (both optional — without them the first installed theme is used) |
| `flock`, `setsid` (util-linux) | `scripts/launch.sh`: one supervisor per session (without `flock` it warns and goes on unguarded), the detached restart |
| `timeout` (coreutils), `setpriv` (util-linux) | time limits of the commands the shell and modules run through the command runner, taken from the system's directory (NixOS: `/run/current-system/sw/bin`; Arch: `/usr/bin`), never from `PATH` (optional — without both, a limit is kept by the shell alone and ends with it) |
| `wlopm` | turning monitors off where Hyprland is not running, through wlr-output-power-management (optional — without it, and without Hyprland, screens are not turned off: the screensaver and the lock screen's black stand in). Not part of the shell's own install on either system: NixOS: the `wlopm` package of nixpkgs; Arch: `wlopm` from the AUR |
| `cava` | the music visualiser (optional — there is an ambient fallback) |
| `vipsthumbnail` (libvips) | wallpapers resized to each screen once, kept in `~/.cache/h2s_shell/wallpapers` (optional — without it the images themselves load, slower) |
| `python3` | the Google OAuth helper, `scripts/google_auth.py` |
| `h2s-helper` (the shell's own, `helper/`) | what Quickshell cannot do from QML: the `org.freedesktop.ScreenSaver` service (apps keeping the screen on). Built from source: on NixOS by the package; on Arch by `install.sh` and the launcher, with `cmake`, `base-devel` and `qt6-base` (optional — without it the shell runs, the launcher's log says so) |
| `pttd` / `ptt` | dictation (optional) |
| sysfs | CPU, RAM, disk, temperatures, GPU, network throughput |

A JetBrainsMono Nerd Font is assumed for the glyphs (`Theme.fontFamily`); without any Nerd Font a
warning under the bar says so and names the font as this system gets it (Arch: the package;
NixOS: the module's option, or the package in `fonts.packages`).
