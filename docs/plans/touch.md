# Plan: touch and stylus (TODO 11.9–11.14)

Status: **planned 2026-11-08; stage 0 waits** — the Framework 12 is shared with another
agent working on the on-screen keyboard (`~/src/oskbd`); the user says when the probe can
run there.

## Why

The Framework 12 (NixOS, Hyprland, `ssh h2s@nixos.lan`) folds into a tablet. The shell
runs there (TODO 11.23, from `~/src/h2s-shell` through the flake's `h2s-shell` with
`H2S_SHELL_DIR`), but it was built for a mouse. The user's own list for tablet mode
(`~/TODO.md` on the laptop): a battery indicator, the clock, workspaces, a keyboard
button — Hyprland's gestures cannot run commands, so a button on the bar is the only way
to call anything with a finger.

## The machine (measured 2026-11-08)

- Screen: eDP-1, 1920×1200, Hyprland scale 1.2, 260×160 mm.
- Touch and stylus: `ILIT2901:00 222A:5539` (touch `event9`, stylus `event10`). The
  user's notes say the stylus produced no events in Hyprland's log yet.
- Tablet mode: `gpio-keys` (`event4`) reports `SW_TABLET_MODE`. Group `input`, which the
  user is not in.
- `iio-sensor-proxy` runs (`monitor-sensor`), for rotation.
- The user's other projects there: `oskbd` (on-screen keyboard, `osk` toggles it, Super+K)
  and `touchgest` (finger scrolling for apps without touch).

## The shell today (counted 2026-11-08)

| | Count |
|---|---|
| `MouseArea` | 95 in 58 files |
| `containsMouse` (looks that depend on hover) | 75 in 40 files |
| `hoverEnabled` | 61 in 40 files |
| `onWheel` | 8 in 7 files (sliders, bar widgets, month grid, curve graph, colour row) |
| `HoverHandler` / `TapHandler` | 10 / 5 |
| `DragHandler`, press-and-hold | 0 |
| `Flickable` / `ListView` | 15 / 7, with 4 `ScrollBar`s in one file |

Qt turns a touch into mouse events for a `MouseArea` that does not take touch itself, so
taps probably work already. What hover does under touch (stuck after the finger lifts, or
never on), how popups behave, and what the stylus sends are not known — stage 0 measures
them. CLEANUP #24–29 has the analysis written before the machine was at hand.

## Stages

Each verified on the Framework before the next.

0. **Measure.** A scratch layer-shell window on the laptop logging every event, and the
   user tapping, holding, dragging with a finger and the stylus while it runs: hover
   after a tap, `TapHandler` vs `MouseArea`, a stylus hovering above the screen, a tap
   outside a popup. Then a walk through the real shell: what does not work by finger.
   The result decides stages 2–5.
1. **Tablet mode as a profile condition.** Folding the laptop switches to a "Tablet"
   profile (the profile system already has conditions, e.g. on battery): popups open on
   a tap (11.10), larger targets, the keyboard button shown. To decide: how the shell
   learns the switch — a udev rule from the Nix module giving the session access to the
   switch device, or a Hyprland switch binding calling `qs ipc`.
2. **Popups close on a tap outside** (11.9), and focus stops depending on hover.
3. **Feedback on touch and finger-sized targets** (11.11, 11.14) — through the shared
   components (buttons, rows, toggles), not 75 separate edits. Minimum sizes in the theme.
4. **Instead of the wheel** (11.12): dragging sliders, swiping workspaces.
5. **Gestures** (11.13): swipe a notification away, an edge swipe for panels.
6. **New for the tablet:**
   - a battery widget (the shell has none — it was never needed on a desktop);
   - a keyboard button (`osk`, configurable);
   - **the lock screen in tablet mode**: no keyboard to type the password. Check whether
     `oskbd` shows over a session lock; if not, a keyboard of the lock screen's own, or
     the fingerprint reader.

## Stylus

Beyond acting as a pointer that can hover (useful for tooltips and hover popups), no part
of the shell needs pressure or tilt. Stage 0 checks it sends anything at all.

## Open

- How to read the tablet-mode switch without the `input` group (stage 1).
- Whether hover-mode popups stay available for the stylus in tablet mode.
- Rotation: whether the bar and popups follow when the screen turns.
