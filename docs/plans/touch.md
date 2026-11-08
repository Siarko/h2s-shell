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

*Touch works everywhere, not only in tablet mode* (the user, 2026-11-08): the shell tells
a finger from a pointer per event; the "Tablet" profile is for preferences (larger
targets, the keyboard button), not for making touch work.

*Popups (11.9, 11.10), 2026-11-08:*
- A hover popup opened by a finger stayed open for good (the finger's "hover" opened it,
  nothing it does closes it); a tap now toggles it as a click (`PointerRules`,
  `PopupWidget`).
- **The device a hover names is no guide**: on the Framework a tap reported a touch
  screen, a finger sliding into an item a touchpad; under QtTest every hover a touchpad.
  `BarWidget` tells them by timing instead: hover is passed on 60 ms after the pointer
  comes over, unless a touch press came meanwhile.
- A popup opened by a tap (`touchOpened`) closes on a tap outside it and the bar
  (`HyprlandFocusGrab`) and is keyboard-focusable without hover. Mouse-opened popups
  unchanged — the user keeps popups open while working elsewhere.
- Tests: `PointerRulesTest`, and `PointerInputTest` driving real components with QtTest
  (mouse, touch) — the first test of the shell that sends input. It fails on the old
  behaviour (checked by putting it back).
- Found on the way: `ProfilesTest` had thrown since the icon theme setting (11.16, options
  from `optionsFrom`) and printed nothing; the harness now counts a throw as a failure.

*On-screen keyboard (oskbd), 2026-11-08* — the user: fields did not open the keyboard,
tapping the keyboard closed the popup, panels drew under it. Measured with a probe (a
layer surface with four fields, `WAYLAND_DEBUG=1`):
- Qt does its part: a focused field sends `text_input.enable` with the right content type
  (digits → purpose 2, url → 5, a password → hint `sensitive_data` only, no `hidden_text`).
- An **on-demand** layer gets the keyboard on the tap and **loses it 3–4 ms later when
  oskbd's panel appears** (Hyprland refocusing on the new layer); with oskbd asleep the
  focus stays. **Exclusive** keyboard focus keeps it — popups opened by touch now take it.
- The focus grab closed the popup on a tap on the keyboard (another client's surface):
  suspended while a layer "osk" is up (`ScreenKeyboard`, from Hyprland's
  `openlayer`/`closelayer` events).
- oskbd's side, for its agent: the user's `layout.toml` has no `opens_for`; the default
  layout maps no layer to `digits`; Qt sends no `hidden_text`; unknown whether oskbd
  switches layer on a content-type change without a new `activate` (what switching fields
  in an exclusive popup does).
- Left: panels avoiding the keyboard (dock mode reserves space the popup windows ignore;
  overlay mode reserves none). Not yet checked by the user on the shell itself.
- Regression found and fixed: a hover popup closed when the pointer went back onto its
  cell (hover now passed on after 60 ms) — it now closes 120 ms after the pointer leaves,
  and reopening cancels that.

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
