# h2s-shell

**THIS IS ALL WORK IN PROGRESS. README AS WELL**

A desktop shell for Hyprland, built with [Quickshell](https://quickshell.org) (Qt 6, QML):
a bar with popups, notifications, on-screen toasts, a lock screen and a
settings window.

## Features

- **Bar** along any screen edge (top, bottom, left, right): workspaces, clock, system
  tray, music, sound, network, Bluetooth, hardware usage, dictation - each opening a popup.
- **Google Calendar** in the clock's popup: a month view, and events you can add, edit
  and delete.
- **Notifications**: toasts on screen, a history panel, inline reply, a count on the bar.
- **Music** controls for every player (MPRIS), with an audio visualiser.
- **Screensaver and lock screen**, from Wayland idle notifications.
- **Settings**: what the bar shows, behaviour per profile (e.g. a power-saving
  profile on battery), and themes - colours, fonts, shapes, animations and their curves.

The full list is in [docs/FEATURES.md](docs/FEATURES.md).

## Requirements

- Hyprland with a Lua config (0.5x), Quickshell, Qt 6
- NetworkManager (`nmcli`), `systemctl`, `notify-send`, `python3`
- A JetBrainsMono Nerd Font
- Optional: `cava` (visualiser), `jq` and `gsettings` (icon theme)

## Running

Put the repository where Quickshell looks for configs, then start it:

```sh
git clone https://github.com/Siarko/h2s-shell ~/.config/quickshell/default
~/.config/quickshell/default/scripts/launch.sh
```

`launch.sh` starts the shell with the icon theme chosen in its settings; call it from
Hyprland's autostart. Settings are kept in `~/.config/h2s_shell/`.

## Google Calendar

Connect an account in **Settings → Calendar**. For now this needs a Google Cloud OAuth
client of your own (type "Desktop app", with the Calendar API enabled): paste its client
ID and secret there and sign in in the browser. The shell talks to Google directly; see
the [privacy policy](https://siarko.github.io/h2s-shell/privacy.html).

## Development

There is no build step. `quickshell -p tests.qml` runs the test suites. How the shell is
put together: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); changes:
[CHANGELOG.md](CHANGELOG.md).
