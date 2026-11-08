# Plan: touch and stylus (TODO 11.9–11.14)

Status: **stage 0 under way 2026-11-08** (first probe run done, a second for the gaps);
stage 1's way of reading the switch decided.

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
5. **Gestures** (11.13), the user's list after walking the shell by finger (2026-11-08):
   - **Calendar:** a swipe changes the month (today only buttons and the wheel).
   - **Music panel:** a swipe across the whole cover area — horizontal changes the track
     (next / previous), vertical changes the player. The slides follow the same axes,
     and that changes what exists: today the cover slides *horizontally on a change of
     player* (`PlayerCarousel`, 11.22) and a change of track has no animation. To be:
     horizontal slide for a track, vertical for a player — by gesture and when it
     happens on its own (a track ending, the active player changing).
   - **Notifications:** a sideways swipe dismisses a card, as on Android — the toasts in
     the HUD and the cards in the notifications panel.
   - Possibly an edge swipe for panels.
6. **New for the tablet:**
   - a battery widget (the shell has none — it was never needed on a desktop);
   - a keyboard button (`osk`, configurable);
   - **the lock screen in tablet mode**: no keyboard to type the password. Check whether
     `oskbd` shows over a session lock; if not, a keyboard of the lock screen's own, or
     the fingerprint reader.

## Progress

*Stage 0, probe 1 (2026-11-08):* a scratch layer-shell window on the Framework, the user
tapping with a finger, then the stylus.
- **Finger:** `MouseArea` gets mouse events synthesised by Qt; `containsMouse` goes true
  on the press and **false again on release — no stuck hover**. `TapHandler`,
  `DragHandler` and flicking a `ListView` work; the device is reported as a touchscreen.
- **Stylus:** works, reported as a stylus/pen (`QPointingDevice` type 16, pointer type
  4). **It hovers**: held above the screen it sets `containsMouse` and `HoverHandler` — so
  hover popups can stay for the stylus. Taps and drags work with the handlers.
- Not in the log, re-run asked for: a stylus tap on a `MouseArea`, press-and-hold
  (`pressAndHold`, `longPressed`), a press dragged out of an area.

*Stage 1, decided (2026-11-08):* tablet mode comes from Hyprland — switch bindings in
`hyprland.lua` call `ipc call tablet set true|false` (`singletons/TabletMode.qml`, the
profile fact `input.tabletMode`). No device access needed; Hyprland reports only changes,
so the shell starts as a laptop until the next flip. Kept in memory, not in the config
(the user: a passing state; a write also showed "Settings saved"). Verified on the
Framework: folding and unfolding reaches the shell. Considered: a udev `uaccess` rule on the switch
device (the user has one for `gpio-keys`, for `~/.local/bin/tablet-mode`), the
`cros-ec-lid-angle` sensor (sysfs, no permissions, ChromeOS EC hardware only), the `input`
group (rejected: every device, keyboards included).

## Stylus

Beyond acting as a pointer that can hover (useful for tooltips and hover popups), no part
of the shell needs pressure or tilt. Stage 0 checks it sends anything at all.

## Open

- Whether hover-mode popups stay available for the stylus in tablet mode.
- Rotation: the user's own script (`~/.local/bin/autorotate`) turns the screen; check the
  bar and popups follow.
