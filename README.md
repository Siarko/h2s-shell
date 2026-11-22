# h2s-shell

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
- **Modules** add integrations. A module runs inside the shell with your rights, so install
  only modules you trust: see [Modules](docs/FEATURES.md#modules).

The full list is in [docs/FEATURES.md](docs/FEATURES.md).

## Requirements

- Hyprland with a Lua config (`hyprland.lua`, 0.5x), Quickshell 0.3.2, Qt 6
- NetworkManager, BlueZ, UPower, power-profiles-daemon
- `notify-send`, `python3`, `jq`, `gsettings` and `gdbus` (glib), `cava`, `git`, `xdg-open`, `vipsthumbnail` (libvips: wallpapers resized to the screen), `systemd-inhibit`
- For the lock screen's fingerprint and security key, optionally: fprintd, pam_u2f (see
  [Lock screen](#lock-screen-password-fingerprint-security-key))
- A JetBrainsMono Nerd Font

The installers below bring all of these.

## Installing

### Arch Linux

```sh
curl -fsSL https://raw.githubusercontent.com/Siarko/h2s-shell/master/install.sh | bash
```

It installs the packages with pacman (asking first), clones the shell into
`~/.config/quickshell/default` and copies its built-in modules to
`~/.local/share/h2s-shell/builtin`, then prints the two things left to you: enabling the
services, and the autostart line for Hyprland. Update with `git pull` in that folder, then
`./install.sh --update` there (it copies the built-in modules again, nothing else).

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
the font, the lock screen's PAM configs (see [Lock screen](#lock-screen-password-fingerprint-security-key)),
and turns on UPower, power-profiles-daemon, Bluetooth and NetworkManager unless your
configuration says otherwise. Update with `nix flake update h2s-shell`.

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
settings, and stays as its supervisor: a shell that dies (a crash, a kill) is started
again, and one that died while the screen was locked locks again at once. For that the
lock screen needs one line in `hyprland.lua`'s `misc` settings,
`allow_session_lock_restore = true` (without it Hyprland refuses to let a restarted lock
screen take the lock back).
`h2s-shell --restart` stops the shell (and its supervisor) and starts it again, detached
(`--dev` for development mode, "Development" below);
there is one supervisor per session (a second start waits briefly, then gives up). If the
lock screen misbehaves, `h2s-shell --lock-log` (or `scripts/lock-log.sh`, also from a text
console while the screen is locked) prints what happened: the shell's lock lines
(Quickshell's log, `qs log`), the supervisor's log (`$XDG_RUNTIME_DIR/h2s-shell-launcher.log`)
and the journal's PAM, fprintd and logind lines — nothing typed is ever logged. A locked
screen that will not take the password is unlocked from a text console with `loginctl
unlock-session <id>` (the graphical session's id, from `loginctl list-sessions`); Escape
does not unlock, it only hides the prompt. Settings are kept in `~/.config/h2s_shell/`.

### Tablet mode

On a convertible, the shell can tell when it is folded into a tablet — a condition for
profiles (Settings → Profiles: "Tablet mode"). Hyprland reads the switch and tells the
shell, through two bindings in `hyprland.lua`:

```lua
local shell = "h2s-shell"  -- Arch: os.getenv("HOME") .. "/.config/quickshell/default/scripts/launch.sh"
hl.bind("switch:on:Tablet Mode Switch", hl.dsp.exec_cmd(shell .. " ipc call tablet set true"), { locked = true })
hl.bind("switch:off:Tablet Mode Switch", hl.dsp.exec_cmd(shell .. " ipc call tablet set false"), { locked = true })
```

The switch's name differs between machines (`gpio-keys` on some): see the
"Switches" in `hyprctl devices`. Hyprland reports only changes, so the shell starts as a
laptop until the next one; `ipc call tablet set true` by hand corrects it.

### Lock screen: password, fingerprint, security key

The lock screen checks each way of unlocking in a PAM conversation of its own, side by
side, so that a fingerprint reader waiting for a finger never holds up a typed password.
`scripts/lock-auth-methods.sh` says which ways exist on the machine and which PAM config
each one uses: `/etc/pam.d/h2s-shell-<method>` when the system has it, else the one
shipped in `pam/`.

- **NixOS**: the module writes the configs. `h2s-shell-password` is the system's usual
  password stack (pam_unix, and systemd-homed, SSSD, LDAP or Kerberos when the system uses
  them) without second factors — a module of those that you do want there is switched on
  with e.g. `security.pam.services.h2s-shell-password.oathAuth = true;`.
  `h2s-shell-fingerprint` exists when `services.fprintd.enable` is set, `h2s-shell-u2f` when
  `security.pam.u2f.enable` is (with your `security.pam.u2f.settings`, always `cue`, never
  `interactive`). Enroll a finger with `fprintd-enroll`; register a key with `pamu2fcfg`
  (into `~/.config/Yubico/u2f_keys`, or the `authfile` your settings name — the forms
  below).
- **Arch and others**: nothing to set up for the password — the shipped `pam/password`
  checks the local password (`pam_unix`, accounts in `/etc/shadow`). For the fingerprint,
  install `fprintd` and enroll a finger (`fprintd-enroll`); for a security key, install
  `pam-u2f` and register it (below). Each is offered only once that is done.
  Accounts that are not in `/etc/shadow` (systemd-homed, LDAP/SSSD) need a
  `/etc/pam.d/h2s-shell-password` of the administrator's. Do not simply write `auth
  include system-auth`: Arch's `system-auth` (and many others') has **`pam_faillock`** —
  wrong passwords typed at the lock then count toward the account's lockout, and a
  locked-out account cannot unlock the screen by password at all until the lockout
  expires — and it often has `pam_fprintd` or `pam_u2f` added, and then the password
  check waits for a finger or a key first. Write the modules your accounts need instead,
  `auth` lines only, e.g. for homed users

  ```
  auth  [success=done default=ignore]  pam_systemd_home.so
  auth  required                       pam_unix.so
  ```

  (for SSSD `pam_sss.so` in place of `pam_systemd_home.so`, with `use_first_pass` on it
  or not as your SSSD setup wants), and include nothing that holds `pam_faillock`,
  `pam_fprintd` or `pam_u2f`.

Registering a security key (`pamu2fcfg`, from pam-u2f): the FIRST key with
`mkdir -p ~/.config/Yubico && pamu2fcfg > ~/.config/Yubico/u2f_keys`; every further key
with `pamu2fcfg -n >> ~/.config/Yubico/u2f_keys` (`-n` leaves out the user name, so the key
is added to your line). `>` replaces the file: run on a file that has keys, it throws away
every key registered before.

An account with an **empty password** cannot unlock by password: the lock never sends an
empty password, and no config allows one (no `nullok`). Give the account a password, or
unlock with a fingerprint or a key.

A config of your own in `/etc/pam.d/h2s-shell-<method>`: only `auth` lines matter (the shell
runs no account, session or password phase). The fingerprint and key configs must never
reach a module that asks for typed input — no `pam_unix`, no `include` of a stack that has
it, no `interactive` for pam_u2f, no key that needs a PIN: the lock treats a fingerprint or
key check that asks for input as broken and stops it.

## Google Calendar

Connect an account in **Settings → Calendar** and sign in in the browser. The shell
carries its own Google OAuth client; Google has not verified the app yet, so the sign-in
page warns about that ("Advanced" → continue). A client of your own (Google Cloud, type
"Desktop app", Calendar API enabled) can be entered there instead. The shell talks to Google directly; see
the [privacy policy](https://siarko.github.io/h2s-shell/privacy.html).

## Development

The shell runs from a git checkout; started with `--dev` (`h2s-shell --dev`, `launch.sh
--dev`) or with `H2S_SHELL_DEV=1` it reloads itself when one of its files changes (development
mode; `H2S_SHELL_DEV=0` turns it off even with `--dev`, and without either a file change
never reloads it). Development mode is inherited by the programs the shell starts, so a
restart from inside the shell (Settings' "Restart to apply") keeps it; to leave it, restart
with `H2S_SHELL_DEV=0` or from outside the shell's environment (a terminal, the compositor's
autostart). Only its small
helper program (`helper/`, C++/Qt) is compiled, by the package on NixOS and by `install.sh`
(and the launcher, after an update) on Arch. `tests/run-all.sh` runs every test before a commit (`--quick` leaves out
the lock screen's end-to-end tests); `tests/run-unit.sh` runs the unit suites. On NixOS,
run a checkout with the package's programs: `H2S_SHELL_DIR=<checkout> h2s-shell`. How the shell is
put together: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); changes:
[CHANGELOG.md](CHANGELOG.md).
