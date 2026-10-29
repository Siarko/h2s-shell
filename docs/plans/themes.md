# Plan: themes — every visual value in a theme, curves in a library

Status: **agreed 2026-10-29, not started.** Replaces TODO 10.1 (configurable animations)
and absorbs 9.4 (stray colours) and 6.x work where it touches visual constants.

## Why

The user wants every visual value — colours, sizes, radii, borders, animation timing
and curves — out of the code and into data, so it can be customised, including by
tools such as **matugen** (installed, not in use yet: it fills templates from a
wallpaper's palette). They also want their own animation curves, with an editor.

## The rule: look goes in the theme, behaviour in the profile

- **Theme** — how the shell looks: colours, fonts and sizes, bar geometry, radii and
  borders of elements (capsules, popups, cards, toasts, buttons), spacing, animation
  durations and the curve for each animation role.
- **Profile** — what the shell does and when: polling, power profile, which widgets the
  bar has and their presets, popup modes, notification and screensaver behaviour,
  dictation, calendar — and **which theme**, plus an animation speed multiplier and
  "reduce motion".

The user's example: how long a toast stays is behaviour (profile); the toast's corner
radius is look (theme).

## Model

### Themes — a shared library

- Files in `~/.config/h2s_shell/themes/<name>.json`, shared by every profile: a profile
  picks one with the setting `appearance.theme`. Two profiles that should look the same
  point at the same theme; there are no per-profile copies. (The same shape as widget
  presets: one library, profiles choose.)
- A theme is **partial**: what it does not set comes from the theme it `extends`, and at
  the root from the built-in default theme. So "like my main theme, but a narrower bar"
  is a small file. Cycles in `extends` are refused.
- A theme may take its colours from another file — `"colorsFrom": "<path>"` — which is
  how a matugen-generated palette comes in.
- Files are **watched**: an external change (matugen after a wallpaper change, a hand
  edit) applies live.

### Tokens

Semantic names, chosen so they map onto Material You roles (so a matugen template can
fill them): background, surface, surface variant, primary, on-primary, secondary,
outline, error, text primary/secondary/dim, … Sizes and radii by element (bar, capsule,
popup, card, toast, button), border width/colour by element, spacing steps, font family
and sizes (the existing `Theme.fontSize*`). Animation: named durations per role (popup
open/close, toast in/out, hover, slide, graph heartbeat, …) and a curve name per role.

`singletons/Theme.qml` stays the one place code reads visual values from, but its
properties are bound to the resolved theme (default ⊕ extends chain ⊕ colours file)
instead of literals — so the ~existing `Theme.x` readers keep working, and new tokens
are added there.

### Curves — a shared library

- Named cubic Béziers, `{ "snappy": [0.2, 0.9, 0.1, 1.0] }`, in
  `~/.config/h2s_shell/curves.json`, shared by all themes; a theme assigns curves to
  animation roles by name. Qt's standard easings (OutQuad, OutCubic, OutBack, …) are
  built in, read-only, and can be copied as a starting point.
- Applied with `easing.type: Easing.BezierSpline` and `easing.bezierCurve`. Control
  points may leave 0–1 (overshoot, "back"). Multi-segment curves are a later addition —
  the format allows them; the editor starts with one segment.
- Usages, rename and delete like presets (a deleted curve falls back to the default).

### Animations

A small helper (`Anim` / `Theme.anim(role)`) gives `duration` and `easing` for a role,
scaled by the profile's speed multiplier; "reduce motion" makes durations 0 or near 0.
The ~50 hard-coded `duration:` values move to roles.

## Settings window

- **Behaviour pages** (General, Calendar, Notifications, Lockscreen, Dictation,
  Performance, Bar's content/presets/popup modes, Profiles) edit the **profile** picked
  in the sidebar.
- **Appearance**, with sub-pages — Colors, Fonts, Bar, Popups, Notifications,
  Animations, Curves — edits the **theme** picked at the top of those pages; there the
  sidebar's profile picker gives way to a theme picker, so it is always clear what is
  being changed. Themes can be created, copied (as `extends` or as a full copy), renamed
  and deleted; shows which profiles use a theme.
- Bar geometry moves from the Bar page to Appearance → Bar.
- **Curves** page: a graph with two draggable control points, numeric fields, a live
  preview (a square moving with the curve, looping, adjustable duration, optionally
  against a second curve), name, save, rename, delete, and where it is used.

## Migration (host behaviour unchanged)

- Today's `Theme.qml` values become the built-in default theme.
- The user's bar geometry in Full (`bar.layout.*`) becomes their main theme (a file
  extending the default); Power save's geometry overrides become a theme "Power save"
  extending it, and Power save gets `appearance.theme: "Power save"`. Full gets the main
  theme. The `bar.layout.*` profile settings then go.
- Backups first, as for profiles.

## Stages

1. **Colours in order** (TODO 9.4): the 17 hex and 20 named colours outside Theme move
   in; token names reviewed against the Material You roles.
   *Done 2026-10-29, verified on the host.* Colours renamed by role (accent, surface,
   text primary/secondary/muted/disabled, divider, outline, error, warning, success,
   workspace states, confirm buttons, lock-screen glass, …), with the transparent variants
   derived in Theme with Qt.alpha. Decided with the user: one green, one red, one blue
   (the dark workspace green stays a colour of its own, `accentDark`); six text greys
   become four. Google's calendar colours are account data and stay out of themes.
2. **Theme files**: Theme resolves default ⊕ extends ⊕ colours file, watched; tests for
   the resolution (partial themes, extends chain, cycles, missing file).
3. **Theme per profile**: `appearance.theme` setting; migration of bar geometry into
   themes; Bar.qml and the bar's readers switch from `Profiles.value("bar.layout.*")` to
   theme tokens.
4. **Animation tokens**: roles, durations, speed multiplier and reduce motion; the
   hard-coded durations move to roles. Fix while there: the heavy calendar panel is
   created during the popup's open animation and drops its first frames.
5. **Curves**: the library, roles use them by name, the Curves editor page.
6. **Appearance pages**: theme picker, Colors (colour picker), Fonts, Bar, Popups,
   Notifications, Animations; create/copy/rename/delete themes.
7. **Radii, borders, spacing** as tokens per element, with their controls — the user's
   next ideas (toast radius, borders, …) land here.
8. **matugen**: a template in the repo mapping its palette to our colour tokens, a
   "wallpaper" theme reading the generated file, and docs for adding the template to
   matugen's config.

Each stage ships and is verified on the host on its own.

## Open

- Font family per theme, or only sizes?
- Should "reduce motion" also follow a system setting, if one exists on the laptop?
- Whether profiles may override single theme tokens (decided for now: no — one path,
  pick a theme; a small `extends` theme covers the variation).
