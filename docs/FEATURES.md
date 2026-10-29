# Features

What the shell does, from the outside. For how it is put together see
[ARCHITECTURE.md](ARCHITECTURE.md).

## The bar

A top-anchored panel on every monitor. It reserves 40 px of screen space
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
- **VPN** — shown only while a tunnel is actually up; shield for WireGuard, padlock
  otherwise.

Container and VM interfaces (veth pairs, taps) report as type `ethernet` to
NetworkManager but are unmanaged, and are ignored when picking which port to report on.

## Panels

Opened from their bar widget, rendered in the single popup below the bar.

- **Calendar** — month grid with navigation, event dots on days that have events, and
  day/week/month views of the event list. With Google Calendar connected it supports
  full event CRUD: create, edit (including recurrence rules), and delete, with a colour
  picker and a per-calendar picker.
- **Music** — current track, art, seek bar, transport controls, player picker when more
  than one MPRIS player is running, and a live audio visualiser fed by `cava`
  (waveform / bars / dots, horizontal or vertical, configurable in Settings → Media).
- **Sound** — default sink and source with volume sliders, output/input device
  selection, and a per-application volume row for every Pipewire stream. Per-app volumes
  are remembered across restarts and reapplied when the app reappears.
- **Bluetooth** — adapter toggle, paired and discovered devices, connect/disconnect.
- **Network** — VPN connections, ethernet with a connect toggle, wifi with a radio
  toggle, the scanned network list with signal strength and security, hidden-network
  entry, saved-profile management, plus live throughput (click it for a
  download/upload history graph), IP and DNS per link.
- **Notifications** — the list of unread notifications with per-item dismiss, dismiss
  all, and codes (one-time passwords and similar) extracted by the regexes in
  Settings → Notifications.
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
  open.
- **Volume OSD** appears on volume or mute changes.
- **Shell toasts** — a bottom pill for the shell's own messages (notifications sent with
  category `x-qs-shell`), kept separate from application notifications.

## Notifications

The shell *is* the notification server (`org.freedesktop.Notifications`), with support
for body markup, hyperlinks, images, action buttons, action icons and inline replies.
Notifications stay in the panel until dismissed. Arrival timestamps are recorded, and
configured regex patterns extract codes from the summary and body so a verification code
can be copied without opening the sending app.

`singletons/Notifier.qml` is the outbound side: the shell can send its own
notifications, with actions, inline replies and dismiss callbacks.

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

## Screensaver and lock screen

Two independent stages, both driven by Wayland idle notifications:

- **Screensaver** — after `screensaverTimeout` the screen is covered by a black surface
  that fades in, optionally showing the notification list. Commands can be configured to
  run when it activates and deactivates (not yet wired up — see CLEANUP.md #12).
- **Lock screen** — a real `WlSessionLock`, so the compositor enforces it. It can be
  reached either after the screensaver or on its own idle timer, and shows a password
  prompt and optionally the notification list. On multi-monitor only one screen shows
  the prompt.

## Settings

A separate floating window, reachable from the Settings widget, from
`Shell.openSettings(category)`, or over IPC — which also works with no Settings widget on
the bar: `qs ipc call settings open`, `openPage <page>` (e.g. `openPage profiles`),
`toggle`, `close`. The sidebar shows which profiles are active right now and
picks the profile every page edits. Pages:

| Page | Covers |
|---|---|
| **General** | debug switches (always global) |
| **Calendar** | enabling Google Calendar, the account connection, which calendars are enabled, debug |
| **Media** | audio visualiser style, layout and frame rate |
| **Bar** | geometry (height, reserved space, offsets, margins, padding, corner radii) and the content of the three sections, including each widget's popup mode and preset |
| **Notifications** | code-extraction regex patterns |
| **Lockscreen** | screensaver and lock timeouts, fade durations, notification visibility, screensaver commands |
| **Dictation** | transcript preview, pending counter, music pause, socket path and debug (always global), and the daemon's wake configuration (read-only) |
| **Performance** | polling rates of hardware, temperatures, disk and network, GPU load sampling, graph heartbeat, the system power profile |
| **Profiles** | the profile list: conditions, order, enable switch, rename, delete, simulation of conditions for testing |

Every setting shows where its value comes from in the edited profile — set there,
inherited from a profile above it, the default, or global — with a pin to make it the
same in every profile and a reset to inherit again.

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
| `hyprctl` / Hyprland IPC | workspaces, logout |
| `systemctl` | restart, shutdown |
| `notify-send` | the shell's own outbound notifications |
| `cava` | the music visualiser (optional — there is an ambient fallback) |
| `python3` | the Google OAuth helper, `scripts/google_auth.py` |
| `pttd` / `ptt` | dictation (optional) |
| sysfs | CPU, RAM, disk, temperatures, GPU, network throughput |

A JetBrainsMono Nerd Font is assumed for the glyphs (`Theme.fontFamily`).
