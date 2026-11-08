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
   - **Calendar:** a swipe changes the month (today only buttons and the wheel). *Done
     (2026-11-08):* `SwipeGesture` over `MonthGrid`'s days; the grid follows the finger
     and the existing month slide carries on from there. The side a drag uncovers shows
     the month there for real — a second grid (`MonthDays`, the days split out of
     `MonthGrid` for it), its events fetched as it first shows; let go, the grid takes
     its place and becomes that month. `components/SwipeGesture.qml`
     is the shared part (scene deltas, speed from samples, the far-or-fast rule), for the
     music panel next.
   - **Music panel:** a swipe across the whole cover area — horizontal changes the track
     (next / previous), vertical changes the player. The slides follow the same axes,
     and that changes what exists: today the cover slides *horizontally on a change of
     player* (`PlayerCarousel`, 11.22) and a change of track has no animation. To be:
     horizontal slide for a track, vertical for a player — by gesture and when it
     happens on its own (a track ending, the active player changing).
   - **Notifications:** a sideways swipe dismisses a card, as on Android — the toasts in
     the HUD and the cards in the notifications panel. *Done (2026-11-08):* a touch-only
     `DragHandler` on `NotificationCard`, dismissing past a third of the width or on a
     fling (speed from its own samples — `centroid.velocity` took a slow drag for a
     fling); checked on the Framework by virtual touch. Note for device tests: the HUD
     keeps a toast for `notifications.toastDuration` (5 s) whatever `-t` says, so the
     swipe has to come within that.
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

*On-screen keyboard, researched (2026-11-08, after four fixes that did not work).*
From source — Hyprland v0.57.1 and qtbase v6.11.0/v6.12.0, read by two agents — then
measured on the Framework with a virtual touchscreen (uinput; the user joined the group
`uinput`) driving a probe, on an empty workspace with a neutral window (`wev`): oskbd
shows only while some *window* has the focus, and a terminal on the workspace keeps it up
on its own — both oskbd's rules, not ours.

How it works:
- **Hyprland**: any layer surface mapping (the keyboard's panel) re-hit-tests at the
  *mouse cursor* and hands the keyboard to what is there (`LayerSurface::onMap` →
  `simulateMouseMovement`); touch never moves the cursor. Only an exclusive layer, or a
  layer without interactivity under the cursor, stops it. An on-demand layer also takes
  the keyboard **at map**. Input-method activate/deactivate follow the client's
  text-input enable/disable, nothing else. `hyprland_focus_grab_v1` is unusable here: a
  tap on the keyboard (another client's surface) always clears it, switching a layer to
  exclusive clears it (why the popup closed), and it hands the keyboard by cursor position,
  bypassing the input-method relay (why the bar got it).
- **Qt 6.11.0–6.11.2** (the Framework): text-input enabled on every keyboard *enter* of a
  window, disabled only on *leave* — focus moving inside the window changes nothing.
  **Qt 6.12.0** (Arch, nixpkgs-unstable): enabled only for a focus object that takes
  input; disabling on focus leaving a field needs `Qt.inputMethod.update(…)`. The full fix
  (per focus object) is on the 6.12 branch, not released. Qt never sends purpose
  `password` — a password is normal + `hidden_text`.

Measured (Qt 6.11), the working combination: the popup **maps without the keyboard**
(interactivity none) and turns **on demand** after; a tap off a text field drops the
window's keyboard (none for 100 ms, then on demand again); a **catcher** — a transparent
layer without interactivity under the popup, a hole where the popup is — takes taps
outside. Result: no text-input at open; tap a field → enable → keyboard shown, focus kept;
tap empty space → disable → hidden; tap the keyboard → reaches the keyboard, popup stays;
tap outside → the catcher. Control without the catcher: the focus was lost 11 ms after the
keyboard's panel mapped (the original symptom). Exclusive interactivity keeps the focus
but Qt 6.11 then never disables. Probe and scripts: the session's scratchpad
(`touchtest/`), to move into the repo with the implementation.

Then (same day) on Qt 6.12 too (Quickshell built against nixpkgs-unstable in a scratch
folder), and a third variant from Hyprland's code: interactivity **none at map, exclusive
on a tap on a text field, none on a tap anywhere else**, with the catcher. It works the
same on 6.11 and 6.12, and exclusive keeps the focus wherever the mouse cursor is (the
on-demand variant relies on the catcher covering the cursor: not on a second monitor).
Ordinary windows (the settings): Qt 6.12 + `Qt.inputMethod.update()` after each focus
change disables text-input when the focus leaves a field; Qt 6.11 cannot — so the
Framework takes Qt 6.12 (the user's flake: `h2s-shell.inputs.nixpkgs.follows =
"nixpkgs-unstable"`).

**The design, for the whole shell:**
- A tap watcher in every layer window with text fields (popups opened by touch, the HUD's
  reply field): a passive handler *above* the content (a press goes to the topmost item
  that takes it, so a watcher below saw only empty space), finding the text field under
  the finger by trying every field's own outline (a walk down by parents' outlines missed
  fields: children lie outside parents). A field → the window's keyboard exclusive; else
  → none, and the focus to a neutral item. The keyboard mode is never changed otherwise.
- A catcher layer (no interactivity, holes where the popup and the bar are) instead of
  `hyprland_focus_grab_v1` for taps outside a popup opened by touch; a tap there closes it
  and does not reach the window beneath (as on Android). Mouse-opened popups unchanged.
- `Qt.inputMethod.update()` after focus changes in ordinary windows (Qt 6.12).
- Tests: the components under QtTest on the host; `tests/device/` — the virtual
  touchscreen and scripts that tap a probe built from the real components on the
  Framework and check the protocol.

*Implemented (2026-11-08):* `components/TouchTextFocus.qml` (the tap watcher, finger and
stylus only) and `components/OutsideTapCatcher.qml`, in `Popup.qml` (the focus grab
removed), `Hud.qml` (reply fields) and `SettingsWindow.qml` (focus off a field on a tap
elsewhere, `Qt.inputMethod.update`). The window offset the catcher's hole needs: the popup
window lies beyond the bar's reserved space (37 px on the Framework) — the first device run
caught it. `tests/device/keyboard-popup.sh` taps the real shell's calendar on the
Framework: 11/11 (Qt 6.11). `PointerInputTest` covers the watcher under QtTest. Not
device-tested: the HUD's reply field (needs an app offering inline reply), the settings
window. Left: panels keeping clear of the keyboard; the Framework on Qt 6.12 (the user's
flake).

*oskbd's side, closed (2026-11-08, its commits to 9896278, its reply in
`~/src/oskbd/INTEGRACJA-H2S-SHELL.md`):* a field in a layer on an empty workspace raises
the keyboard (after the window focus goes, Hyprland sends no `activate`, only the state —
and echoes the old field's content type 1–2 ms later, which oskbd now tells apart by a
50 ms window); a change of `purpose` without a new `activate` switches the layer; `digits`
opens the numeric layer (built-in and the user's layout). `tests/device/keyboard-popup.sh`
runs on an empty workspace without the neutral window and checks that going there raises
no keyboard: 12/12.

*Panels clear of the keyboard (2026-11-08):* `ScreenKeyboard` knows the keyboard's screen
and top edge (`hyprctl layers` when it opens; global coordinates, a screen's y taken off).
A popup by a bar at the top is cut to end above it (`Popup._keyboardLimit`, the content's
height capped) and its content moved within it (`_keyboardScroll`): to the focused field by
itself, by a DragHandler or the wheel. The tap watcher decides on release, not press — a
drag scrolling the popup counted as a tap off the field and let the keyboard go. Measured
on the Framework: the calendar with its form 691 px → 603 px, ending at 640 above the
keyboard at 656; a drag moved the content 88 px with the keyboard kept; a tap off the field
brought the full height back; `keyboard-popup.sh` 12/12. Left: a bar at the bottom (the
keyboard covers the bar), popups by a bar at a side, the settings window (an ordinary
window: oskbd's overlay covers it).

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
