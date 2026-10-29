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
   *Done 2026-10-29, verified on the host.* `ThemeRules` (pure: chain, layering)
   and `Theme` (reads, watches). Theme files and palettes are watched, and so are their
   folders, so a file created later (a theme, a palette matugen writes) or a broken file
   being fixed applies too. The setting `appearance.theme` (string, for now) arrived
   here rather than in stage 3. Groups so far: `colors` (the base colours; transparent
   variants stay derived) and `fonts` (family and sizes) — which answers the open
   question: font family is per theme. Errors go to the log and `Theme.errors`.
3. **Theme per profile**: `appearance.theme` setting; migration of bar geometry into
   themes; Bar.qml and the bar's readers switch from `Profiles.value("bar.layout.*")` to
   theme tokens.
   *Done 2026-10-29, verified on the host.* `ThemeRules.themesFromBarLayout`
   (tested): each profile with its own geometry gets a theme named after it (not "Main"
   as first planned — it keeps the generic case of any number of profiles simple), which
   extends the theme of the profile before it; pinned global geometry goes into each;
   geometry from a config older than profiles goes to the first. Runs once (marker
   `theme.barLayout` in `migratedKeys`), with a config backup; theme files are written
   before the profiles that pick them. Decided with the user: the geometry sliders stay
   on the Bar page for now, editing the theme of the profile being edited
   (`Theme.writeToken`, `Theme.valuesOf`, `Theme.usersOf`); they move to Appearance → Bar
   in stage 6.
4. **Animation tokens**: roles, durations, speed multiplier and reduce motion; the
   hard-coded durations move to roles. Fix while there: the heavy calendar panel is
   created during the popup's open animation and drops its first frames.
   *Roles agreed with the user 2026-10-29*, by the kind of motion rather than the place:
   hover 100 OutQuad · state 150 OutQuad (switches, focus, field state) · expand 150
   OutQuad (height/width in place) · popup 100 with two curves, popupOpen OutQuad and
   popupClose InQuad · popupResize 100 OutQuad · enter 250 OutCubic · exit 200 InCubic ·
   move 200 OutCubic (restacking) · slide 300 OutCubic (menus, pages) · fade 150 OutQuad
   · value 400 Linear · heartbeat 350 OutQuad · pop 380 OutBack ("Clear all" is timed
   from it; its 750 ms reading pause is fixed) · pulse 1000 InOutQuad · spin 800 Linear ·
   themeChange 400 OutQuad. Unifying 120–200 ms into one value was accepted. The
   screensaver's fade stays a profile setting (the user's call).
   Theme groups `durations` and `curves`; `Theme.duration(role)` (speed applied; with
   reduced motion everything but hover/state/fade/themeChange/spin takes 1 ms, never 0,
   so code waiting for an animation's end still sees it) and `Theme.easing(curve)`. The
   pulse holds still dimmed and the heartbeat stops with reduced motion.
   *Existing animations moved to roles 2026-10-29, verified on the host.*
   *Calendar's first frames fixed 2026-10-29, verified on the host.* Measured: creating
   the content happens before the animation, so its cost (20–26 ms, the first time only:
   compiling the panel and starting Google Calendar) only delayed the popup; the frames
   were lost to the content's first render (28–30 ms), inside the animation. Fixed by
   rendering new content once before animating (`Popup._whenRendered`), opening and
   switching alike, and by compiling the popup panels in the background after start
   (shell.qml; Google Calendar is not started early, it would contact Google on every
   start). Found while there: at the bar's right end the popup's target position was
   computed from its animated width, restarting the position's animation every frame.
   Switching panels fades the new content in; a true cross-fade (old content as a frozen
   `ShaderEffectSource`) was offered and is not wanted for now.
   New animations, a few at a time:
   - *Hover (candidate 1) and workspace focus (2), 2026-10-29, verified on the host:* a
     `Behavior on color` with the hover role on every colour that depends on the pointer
     (68 places in 27 files; the workspace buttons use state). `Theme.surfaceHoverClear`
     replaces "transparent" where a hover fades in, so it does not darken on the way.
   - *Bar geometry on a theme change (3), 2026-10-29, verified on the host:* Bar.qml keeps
     an animated copy of the shape (`_shape`), animated with slide only for a moment after
     `Theme.themeName` changes — editing the theme in use (the sliders) stays immediate.
     The exclusive zone is set to the reserved space at once (`exclusionMode: Normal`), so
     windows are re-tiled once; the bar's window is as tall as the animated bar needs.
     Popup and HUD positions follow the new theme at once.
   - *Bell (11), dictation state (14), volume sliders (13), 2026-10-29, verified on the
     host:* there is no unread badge — the bell turns accent — so the bell fades
     (state) and jumps on a new notification (pop; not with reduced motion). Volume
     sliders draw `_shownValue`, animated with value except while dragged.
   - *Theme colours (5), tray icons (12), scan results (15), 2026-10-29, verified on
     the host:* the 24 base colours have a `Behavior` enabled only while a reload brings
     different colours that the shell did not write itself (a theme switch, matugen, a
     hand edit — not `writeToken`, not the first load); derived colours follow. Tray
     icons grow from width 0 (also at start, as items register). The network ListView
     has add/displaced/move transitions; Bluetooth's device rows got a Column of their
     own for its add/move transitions. Removal is not animated (Repeater destroys the
     delegate at once).
   - *Settings pages (7), calendar (9), track change (10), 2026-10-29, verified on the
     host:*
     one sliding mark for the selected settings page (slide, only on a page change, not
     the first layout) and the page fading in, rising 12 px (enter). The month grid
     slides: the old month out, the new one in from the side it comes from, the full
     width (slide; the user asked for a full slide over a short nudge). The old month is
     one of three `ShaderEffectSource`s of the grid taking turns: the live one is parked
     outside the clipped area (rendered, so current, but not seen); when the month
     changes — synchronously, before the grid redraws — it freezes and slides out, and
     the oldest goes live. So a change mid-slide slides too, from where the grid is, and
     the month that was sliding out keeps going beside it (the third; not when the
     direction reverses, where the grid covers it). The user found one snapshot, hidden
     mid-slide, made quick clicks jump, and two left a gap at the edge; the week
     frame moves (move), day cells fade (state). The cover fades in once loaded and the
     title/artist on a title change (fade) — no true cross-fade, as for popups.
   - *Bar content (4), lock screen (8), 2026-10-29, verified on the host:* each section
     shows its model plus the widgets going (`ProfileRules.withLeaving`, tested), kept in
     place marked `leaving` until exit has run; a widget's width (and the section's
     spacing, as a negative margin) scales with an animated 0–1, clipped, so neighbours
     slide. Not in the first 3 s, while the bar starts. A widget whose preset changes has
     a new key, so the old one shrinks while the new grows beside it. Lock screen: the
     scrim fades in; prompt and notifications fade across, the prompt growing from 96 %. Found while
     testing: `Lockscreen.lock()`/`unlock()` had been lost (1a02c55), so the lock never
     came on; and the screensaver's first fade lost its start to the window's first frame
     — the window now maps clear and fades after a frame, like popups.
     Later fixes: the settings page mark sometimes jumped (it was enabled for a moment
     by a handler that could run after the position had already changed; now enabled
     once the list is first laid out). The Bar page looped bindings while editing a
     profile whose theme is not active: `FileView.text()` is reactive, so resolving a
     chain of files inside a binding re-triggered it — `Theme.valuesOf` now resolves
     other themes outside bindings and keeps them until the next reload.
   - The list of candidates is done. Later (the user's idea): variants per element,
     `expand.dictate` falling back to `expand` — and the same for colours.
5. **Curves**: the library, roles use them by name, the Curves editor page.
   *Scope agreed with the user 2026-10-29:* assigning curves to roles stays in stage 6
   (Animations page); the Curves page gets its own sidebar entry until Appearance exists.
   Copies of Qt's curves are Bézier approximations (easings.net); Bounce/Elastic cannot
   be copied. Control points' x stays within 0–1, y is free. Names may not be Qt's.
   Renaming rewrites references in theme files (a file that does not parse is skipped
   and reported); deleting leaves references to fall back to OutQuad.
   *Library and resolution, 2026-10-29, verified on the host with the page:* `ThemeRules.curveEasing`
   (tested) returns the value an animation's `easing` takes — `{ type }` for a Qt curve,
   `{ type: BezierSpline, bezierCurve }` for a library curve; Qt accepts the object as a
   whole (checked in a scratch run). `Theme.curve(role)` replaced `Theme.easing` at all
   148 sites (`easing: Theme.curve("hover")`). The library is read with the theme and
   watched like it; unknown or broken curves are listed in `Theme.errors` by role.
   *Curves page, 2026-10-30, verified on the host:* panels/settings/CurvesSettings.qml, its
   own sidebar entry. A draft (name, points) is edited by dragging the two control points,
   or typing them, and written on Save; Save with a new name renames (`Theme.renameCurve`
   rewrites the themes using it, via `ThemeRules.renameCurveIn`, tested). The graph draws
   the Bézier and a compared curve sampled through an animation's
   `easing.valueForProgress`; the preview loops a square per curve. Usages come from
   `Theme.themeFiles`, every theme file read on reload. Curves of several segments are
   shown, not edited. Found while testing: the graph's y range now zooms (scroll; opening a
   curve fits its points), as a point beyond it could not be grabbed; the preview applied
   the curve twice (an eased animation of a value then eased again) — time now runs
   linearly and dots on the graph follow each curve at the preview's moment.
   *Next, asked for by the user:* more control points — editing curves of several
   segments (the format and resolution already take them): add a point on the curve,
   which splits a segment, drag the joints and their handles, remove a point. Not
   scheduled yet; after stage 5 or with stage 6.
6. **Appearance pages**: theme picker, Colors (colour picker), Fonts, Bar, Popups,
   Notifications, Animations; create/copy/rename/delete themes. The Animations page lists
   every role with its **duration** (ms) and its **curve** (the user's requirement,
   2026-10-29) — popup with its two curves — each inherited from the extended theme
   until set, with a reset; plus a preview of the role.
7. **Radii, borders, spacing** as tokens per element, with their controls — the user's
   next ideas (toast radius, borders, …) land here.
8. **matugen**: a template in the repo mapping its palette to our colour tokens, a
   "wallpaper" theme reading the generated file, and docs for adding the template to
   matugen's config.

Each stage ships and is verified on the host on its own.

## Open

- Should "reduce motion" also follow a system setting, if one exists on the laptop?
- Whether profiles may override single theme tokens (decided for now: no — one path,
  pick a theme; a small `extends` theme covers the variation).
