# Device tests

Tests that drive the running shell on a real touch device — the Framework 12 — through the
whole stack: a virtual touchscreen (uinput) → libinput → Hyprland → the shell, and the
on-screen keyboard (oskbd) reacting. What `quickshell -p tests.qml` cannot reach: QtTest
sends its events to the Qt window directly, past the compositor, so keyboard focus, the
input method and layer stacking never come into it.

- `touchtap.py` — the virtual touchscreen: `tap x y`, `hold x y ms`, `swipe x1 y1 x2 y2 ms`,
  `pinch cx cy start end ms` (two fingers), `sleep ms`, in the monitor's logical pixels.
- `keyboard-popup.sh` — the calendar popup by touch: the keyboard shows for a text field
  and hides after, a tap on the keyboard keeps the popup, a tap outside closes it.

They find what to tap through the shell's `shelltest` IPC (`Bar.qml`): a bar cell's
place, a popup item's place by `objectName`, the popup's state.

## Needs

- Write access to `/dev/uinput`. On NixOS:

  ```nix
  users.groups.uinput = { };
  users.users.<you>.extraGroups = [ "uinput" ];
  services.udev.extraRules = ''
    KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", GROUP="uinput", MODE="0660"
  '';
  ```

  The group lets any program running as you type and click as a keyboard and mouse would.
- `nix` (python-evdev and grim are fetched with `nix shell` for the run).
- oskbd awake (`oskbd -w`), for the keyboard checks.

Run from the device (or over ssh): `tests/device/keyboard-popup.sh`. It switches to the
empty workspace 9 for the run — a terminal there keeps oskbd up on its own — and goes back
after. (Before oskbd 9896278 a neutral window was needed too: oskbd showed only while some
window had the focus.)

oskbd also offers `oskbd --probe-text <purpose> [hold-ms [then-purpose]]`: a layer with an
exclusive keyboard and a real text-input field, without touch or the shell.
