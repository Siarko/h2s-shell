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

- Hyprland with a Lua config (`hyprland.lua`, 0.5x), Quickshell 0.3.2, Qt 6
- NetworkManager, BlueZ, UPower, power-profiles-daemon
- `notify-send`, `python3`, `jq`, `gsettings`, `cava`, `git`, `xdg-open`
- A JetBrainsMono Nerd Font

The installers below bring all of these.

## Installing

### Arch Linux

```sh
curl -fsSL https://raw.githubusercontent.com/Siarko/h2s-shell/master/install.sh | bash
```

It installs the packages with pacman (asking first) and clones the shell into
`~/.config/quickshell/default`, then prints the two things left to you: enabling the
services, and the autostart line for Hyprland. Update with `git pull` in that folder.

### NixOS

Add the flake to your system flake and enable the module:

```nix
{
  inputs.h2s-shell.url = "github:Siarko/h2s-shell";

  outputs = { nixpkgs, h2s-shell, ... }: {
    nixosConfigurations.<host> = nixpkgs.lib.nixosSystem {
      modules = [
        h2s-shell.nixosModules.default
        { programs.h2s-shell.enable = true; }
        # ...
      ];
    };
  };
}
```

The module installs the `h2s-shell` command (the shell with every program it calls),
the font, and turns on UPower, power-profiles-daemon, Bluetooth and NetworkManager
unless your configuration says otherwise. Update with `nix flake update h2s-shell`.

Without the module: `nix run github:Siarko/h2s-shell`.

### Starting it

From Hyprland's autostart, in `hyprland.lua`:

```lua
hl.on("hyprland.start", function()
	hl.exec_cmd("h2s-shell")  -- NixOS
	-- Arch: hl.exec_cmd(os.getenv("HOME") .. "/.config/quickshell/default/scripts/launch.sh")
end)
```

`launch.sh` (which `h2s-shell` runs) starts the shell with the icon theme chosen in its
settings. Settings are kept in `~/.config/h2s_shell/`.

### Tablet mode

On a convertible, the shell can tell when it is folded into a tablet — a condition for
profiles (Settings → Profiles: "Tablet mode"). Hyprland reads the switch and tells the
shell, through two bindings in `hyprland.lua`:

```lua
local shell = "h2s-shell"  -- Arch: os.getenv("HOME") .. "/.config/quickshell/default/scripts/launch.sh"
hl.bind("switch:on:Tablet Mode Switch", hl.dsp.exec_cmd(shell .. " ipc call tablet set true"), { locked = true })
hl.bind("switch:off:Tablet Mode Switch", hl.dsp.exec_cmd(shell .. " ipc call tablet set false"), { locked = true })
```

The switch's name differs between machines (`gpio-keys` on the Framework 12): see the
"Switches" in `hyprctl devices`. Hyprland reports only changes, so the shell starts as a
laptop until the next one; `ipc call tablet set true` by hand corrects it.

## Google Calendar

Connect an account in **Settings → Calendar** and sign in in the browser. The shell
carries its own Google OAuth client; Google has not verified the app yet, so the sign-in
page warns about that ("Advanced" → continue). A client of your own (Google Cloud, type
"Desktop app", Calendar API enabled) can be entered there instead. The shell talks to Google directly; see
the [privacy policy](https://siarko.github.io/h2s-shell/privacy.html).

## Development

There is no build step: the shell runs from a git checkout, and reloads itself when a
file changes. `quickshell -p tests.qml` runs the test suites. On NixOS, run a checkout
with the package's programs: `H2S_SHELL_DIR=~/src/h2s-shell h2s-shell`. How the shell is
put together: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); changes:
[CHANGELOG.md](CHANGELOG.md).
