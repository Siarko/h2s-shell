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
  all, and codes (one-time passwords and similar) extracted by the regexes in
  Settings → Notifications. A card swiped sideways by finger is dismissed.
- **Hardware** — every sensor source with its current value, a history graph and a
  progress bar.
- **Power** — shutdown, restart, logout.
- **Tray menu** — the menu of a tray item, rendered in the popup rather than by the app.

## HUD

A click-through overlay above everything, one per monitor. It is transparent and passes
input through except where a card is actually visible.

- **Notification toasts** slide in from the right as notifications arrive. When several
  queue up, a badge on the right screen edge shows how many are waiting; clicking it
  opens the notification panel. Toasts are suppressed while the notification panel is
  open. They show on the screen with the focused workspace, or on a chosen screen; when
  that screen has a fullscreen window they show anyway, not at all (the notification in
  the panel only), or on another screen — a chosen one, or any without a fullscreen
  window. The shell's own messages follow the same rules (Settings → Notifications). A finger swipe sideways dismisses a toast (past a third of its width, or flung);
  its countdown pauses while it is being dragged.
- **Volume OSD** appears on volume or mute changes.
- **Shell toasts** — a bottom pill for the shell's own messages (notifications sent with
  category `x-qs-shell`), kept separate from application notifications.

## Notifications

The shell *is* the notification server (`org.freedesktop.Notifications`), with support
for body markup, hyperlinks, images, action buttons, action icons and inline replies.
Notifications stay in the panel until dismissed. A critical notification's toast stays
on screen too, until dismissed or answered (no countdown); the others count down past it. Arrival timestamps are recorded, and
configured regex patterns extract codes from the summary and body so a verification code
can be copied without opening the sending app.

`singletons/Notifier.qml` is the outbound side: the shell can send its own
notifications, with actions and dismiss callbacks (no inline reply: notify-send cannot
ask for one).

## Dictation

A client for `pttd`, an external dictation daemon driven by Whisper. The shell is
*only* a client — audio capture and keyboard emulation stay in the daemon. The protocol
is documented in [quickshell-integration.md](quickshell-integration.md).

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
`singletons/Wallpapers.qml`; plan: `docs/plans/wallpapers.md`.

## Screensaver and lock screen

Two independent stages, both driven by Wayland idle notifications:

- **Screensaver** — after `screensaverTimeout` the screen is covered by a black surface
  that fades in, optionally showing the notification list. Commands can be configured to
  run when it activates and deactivates (not yet wired up — see CLEANUP.md #12). A
  profile switch that changes the screensaver's timeout while it shows takes it down (and
  starts the idle count again): a known limit.
- **Lock screen** — a real `WlSessionLock`, so the compositor enforces it. It can be
  reached either after the screensaver or on its own idle timer, and shows a password
  prompt and optionally the notification list — the app's name only by default, or the
  title, or everything (Settings → Lockscreen; it applies to every lock), always as plain
  text with nothing to click. It also locks on request: logind's Lock
  signal for the shell's session (`loginctl lock-session`, or `HandlePowerKey=lock` in
  logind.conf) and `h2s-shell ipc call lockscreen lock`; a request while locked changes
  nothing. Every lock starts afresh: nothing of one lock carries into the next.
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
  (pam_u2f's `authfile`, else `~/.config/Yubico/u2f_keys`). An answer of "not there" is
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
- **The compositor's confirmation** — the screen counts as locked once the compositor says
  so; until then the password is already checked, and an unlock waits for that word
  ("Unlocking…"), since unlocking a lock the compositor has not confirmed is a protocol
  error. A confirmation late by more than 5 s is shown ("Waiting for the compositor…").
- **Failure and recovery** — the screen stays locked whatever happens to the shell. A file
  written in its folder while locked does not reload it (the edit takes effect at the next
  file change after the unlock). A reload asked for while locked keeps the lock (a new
  authentication is needed); a lid closed while the shell reloads still locks before sleep
  as long as the lock is up within a few seconds (plan section 7, "The reload window").
  A shell that dies while locked — a crash, a kill, the OOM killer, `qs kill`,
  `h2s-shell --restart` — is started again by the launcher (`h2s-shell`, which stays as its
  supervisor, one per session; 5 quick restarts in 2 minutes, then once a minute for as long
  as the screen is locked) or by Quickshell's own crash handler, and
  locks again at once: it finds the lock marker it left in `$XDG_RUNTIME_DIR`. A shell
  stopped on purpose while unlocked is not started again. What it left behind (a
  fingerprint conversation holding the reader) is killed. Under Hyprland this needs
  `misc:allow_session_lock_restore = true` in the Hyprland config; without it Hyprland
  keeps its "lockscreen app died" screen, the shell says `compositor-locked` and waits for
  the setting (see `docs/plans/lockscreen.md`, section 7, "Recovery").
- **Other ways out** — logind's Unlock for the shell's session (`loginctl
  unlock-session`, from another console), and the compositor ending the lock. There is no
  unlock over IPC, and no key unlocks: Escape shows a hidden prompt (as any key) and hides a
  showing one, emptying the field (as the prompt's time-out does); a held Escape's repeats
  count for nothing. (Escape at a showing prompt unlocked until 2026-11-15.)
- **Sleep** — the screen locks before the computer sleeps (`lockscreen.lockOnSleep`), the
  shell holding a logind delay inhibitor (`systemd-inhibit`) until the compositor confirms
  the lock (at most 4 s), so the desktop is not what shows on waking. The fingerprint and
  key conversations stop for the sleep and start again after it, with the methods looked
  for again; the inhibitor is taken again after every wake, and when it is lost.
- **The log** — every authentication event leaves a `[Lockscreen]` line in the shell's
  log (what was asked, started, answered, refused, why a lock ended), never what was
  typed: what to read when unlocking fails on the real machine.
- Design and tests: `docs/ARCHITECTURE.md` ("Lock screen"), `docs/plans/lockscreen.md`,
  `tests/LockRulesTest.qml`, and the end-to-end test bed `tests/lock/`.

## Network settings

Settings → System → Network unfolds into its pages (docs/plans/network.md). **Overview**
(`singletons/network/NetworkOverview.qml`): online or not (NetworkManager's connectivity),
the Wi-Fi, mobile broadband, airplane-mode and networking switches, each device with its
hardware, MAC, speed, Wi-Fi signal and channel, addresses, gateway, DNS, search domains and
MTU (bridges, containers' and tunnels folded under "Other devices"), and the hostname, a
global DNS and the connectivity check — through `nmcli` and NetworkManager's D-Bus
properties (`busctl`); a change refused for want of rights goes to the polkit prompt.
**Wi-Fi** (shown when the computer has Wi-Fi): the radio, the network in use, the saved
networks with connect, autoconnect, priority, the password (shown for 30 s, or changed)
and forget, a hidden network, and "Find networks": the networks in range sliding in from
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
**The connection editor** (a profile → Edit connection…,
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
VpnManager, `NetworkRules.vpnWithNetworkPlan`): wanted while a linked network is up, taken
down when none is if the shell brought them up (remembered in Config), held down when
taken down by hand — the shell's doing, from its start (shell.qml), as
NetworkManager's connection.secondaries takes no WireGuard; the VPN's card lists them.
Only through the VPN (`singletons/network/VpnLockdown.qml`): always, or on the networks set
for it in their editors — the table `inet h2s_vpn_lockdown`, built by
`scripts/h2s-vpn-lockdown` (root's, through pkexec; it takes checked settings, never rules),
letting out only loopback, the VPNs' interfaces and servers, virtual interfaces, DNS, DHCP
and IPv6 ND, and the local network when allowed; passed-on traffic only through a VPN.
"Password-free blocking" installs that script to /usr/local/libexec/h2s-vpn-lockdown with
a polkit rule for this user (Install… / Remove…, its state on the page, the script and the
rule shown in full; on NixOS a module to import); then no password is asked, and its
`status` is checked at the start, after network events and every 5 minutes to mend a
firewall reload. Without it each switch asks, and
what was switched on in which boot is kept in Config.
"Files you can import" lists each kind (`NetworkRules.vpnImportKinds`) with its
files and whether it can be imported now — a missing plugin named with what it is for,
other installed plugins after. Modem follows.

## Authentication prompts (polkit)

The shell can be the session's polkit agent (`singletons/Authentication.qml`,
`polkit/AuthPrompt.qml`): when a program needs an administrator's rights, a prompt over
the focused screen, the rest dimmed and the keyboard held, says what asks, lets the
account be picked, shows PAM's messages and asks again after a wrong password. Only one
agent can answer per session, so `system.polkitAgent` is decided at the first start (off
when a known agent runs, on when the shell registers) and changed in Settings → System →
Authentication, which also shows what answers now. Notifications say when no agent answers
or another one cannot register beside the shell's. Plan: `docs/plans/polkit.md`.

polkit's helper runs one PAM stack, `polkit-1`; NixOS puts a fingerprint reader first in
it, so PAM asks for the password only after the reader gives up (30 s, or three fingers
that do not match). The prompt's field is there from the start: a password typed and
Entered meanwhile is held and sent the moment it is asked for, and a line under PAM's
message says what the prompt waits for (`PolkitRules.conversationHint`). The NixOS
module's `programs.h2s-shell.polkit.passwordFirst` (on by default with fprintd) moves
pam_fprintd after pam_unix: the password is asked at once, and Enter on an empty field
goes on to the reader. Settings → System → Authentication says which order this computer
has (read from `/etc/pam.d/polkit-1`).

## Settings

A separate floating window, reachable from the Settings widget, from
`Shell.openSettings(pageId)`, or over IPC — which also works with no Settings widget on
the bar: `qs ipc call settings open`, `openPage <id>` (a page's id, e.g. `openPage profiles`,
`openPage bar_appearance`), `currentPage` (the open page's id), `toggle`, `close`. Two tabs: **Behaviour**, whose pages edit
a profile, and **Appearance**, whose pages edit a theme. The sidebar shows which profiles
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
| **Notifications** | code-extraction regex patterns |
| **Lockscreen** | screensaver and lock timeouts, fade durations, notification visibility, screensaver commands |
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
`~/.config/h2s_shell/themes/`; see [plans/themes.md](plans/themes.md).

### Profiles

A profile is a named set of setting overrides that applies while its conditions hold:
on battery, battery below a level, a system power profile, screen locked, a fullscreen
window, a given popup open. Several can apply at once; the one lower in the list wins.
New configs start with **Full** (always on, today's behaviour spelled out) and **Power
save** (on battery: slower polling, no graph heartbeat, 15 fps visualiser, the
power-saver system profile). With no profiles, built-in defaults apply.

Changes apply live and are written to `~/.config/h2s_shell/config.json`, debounced by
one second.

## External dependencies

Beyond Quickshell and Qt 6, the shell shells out to:

| Tool | Used for |
|---|---|
| `nmcli` (NetworkManager) | all network state and actions |
| `hyprctl` / Hyprland IPC | workspaces, logout — expects a Lua config (`hyprland.lua`, Hyprland 0.5x): special workspaces and logout dispatch `hl.dsp.*` Lua expressions |
| `systemctl` | restart, shutdown |
| `gdbus`, `systemd-inhibit` (logind) | the lock screen: lock requests, sleep and wake, holding the sleep until locked |
| `gdbus` (fprintd), `timeout`; PAM (`pam_unix`, `pam_fprintd`, `pam_u2f`) | unlocking: which methods there are (`scripts/lock-auth-methods.sh`), and the checks themselves (fprintd and pam_u2f optional) |
| `notify-send` | the shell's own outbound notifications |
| `jq`, `gsettings` | `scripts/launch.sh`: the icon theme setting from the config, the system's icon theme for "Automatic" (both optional — without them the first installed theme is used) |
| `flock`, `setsid` (util-linux) | `scripts/launch.sh`: one supervisor per session (without `flock` it warns and goes on unguarded), the detached restart |
| `cava` | the music visualiser (optional — there is an ambient fallback) |
| `vipsthumbnail` (libvips) | wallpapers resized to each screen once, kept in `~/.cache/h2s_shell/wallpapers` (optional — without it the images themselves load, slower) |
| `python3` | the Google OAuth helper, `scripts/google_auth.py` |
| `pttd` / `ptt` | dictation (optional) |
| sysfs | CPU, RAM, disk, temperatures, GPU, network throughput |

A JetBrainsMono Nerd Font is assumed for the glyphs (`Theme.fontFamily`).
