# Changelog

Notable changes to the shell, newest first. Versions follow semantic versioning:
**major** for changes that need a config migration or change behaviour people rely on,
**minor** for features, **patch** for fixes. The number lives in
`singletons/Version.qml`; each release is tagged `v<number>` in git.

Add an entry under **Unreleased** with each user-visible change; a release renames that
section to the new version and date.

## [Unreleased]

### Added
- Theme files: `~/.config/h2s_shell/themes/<name>.json` sets colours and fonts over the
  built-in look, can `extend` another theme and take colours from a palette file
  (`colorsFrom`, e.g. from matugen). The setting "Theme" picks one per profile; files are
  watched, so an edit applies at once.
- Animations by role: every animation takes its duration and curve from the theme
  (`durations`, `curves`: hover, state, expand, popup, enter, exit, move, slide, fade,
  value, heartbeat, pop, pulse, spin, …). Per profile: "Animation speed" and "Reduce
  motion", for now on the General page with the theme name.
- Colours change smoothly under the pointer (bar cells, tray icons, buttons, list rows,
  sliders, links — the "hover" animation role), and the workspace buttons fade between
  focused, active and hovered ("state").
- Switching to a profile with another theme (Power save on battery, say) slides the bar
  into its new shape ("slide"); the space kept free for windows changes at once.
- The notification bell fades to the accent and jumps when a notification arrives; the
  dictation icon fades between its states; volume sliders and the volume OSD follow the
  volume keys smoothly ("value"), while dragging stays immediate.

### Changed
- Animations of a kind share one timing: expanding and collapsing takes 150 ms everywhere
  (was 120–200), a notification card arrives in 250 ms (was 200), the password field's
  colour changes in 150 ms (was 120).
- The bar's geometry (height, reserved space, offset, margins, padding, corners) is part
  of the theme instead of a profile setting. Each profile that had its own geometry gets
  a theme named after it with those values (Power save's extends Full's), so the bar
  looks as before. The sliders on the Bar page edit the theme of the profile being
  edited — and so every profile that uses it.
- Colours are named by role and come only from the theme: one red, one green and one
  blue where there were several shades (the disconnect buttons, the lock screen's error
  and the calendar's connection status change shade slightly).

### Fixed
- The first opening of a popup no longer loses part of its animation: panels are
  compiled in the background after start, and new content renders once before the
  animation starts (the calendar dropped a third of its frames).
- Moving from one widget's popup to another's: the popup no longer crawls after its
  size at the right end of the bar, and the new content fades in as the popup moves
  instead of jumping in first.
- No more warnings in the log when an app stops playing with the sound popup open.

## [1.1.0] - 2026-10-29

### Added
- Toast settings, per profile: show toasts at all, how long each stays, and one at a time
  or a column of them (with how many). A column shows the newest on top, and only the
  oldest counts down, so they leave one at a time.
- Notification privacy on the screensaver and the lock screen, separately and per
  profile: show notifications in full, title only, or the app alone.

### Fixed
- The screensaver's start and end commands now run — they could be set but nothing ran
  them. They follow idle time rather than the screensaver's visibility, so locking the
  screen does not count as coming back, and they can differ per profile.
- Popups stay under the bar when it does not reach the screen edges, stopping short of
  its rounded ends; switching between popups of different widths keeps the edge they
  are held against and animates the width instead of jumping.
- A binding loop when a profile switched the system power profile.

## [1.0.0] - 2026-10-29

The first numbered version: the shell as it stands after the 2026-10 cleanup, which
began in February 2026 as a single Hyprland bar.

### Added
- **Shell profiles.** Every setting can differ per profile — named sets of overrides that
  apply while their conditions hold (on battery, battery level, power profile, screen
  locked, fullscreen window, open popup), layered in list order. New configs start with
  Full and Power save. A setting can be pinned as global, and some (debug switches, the
  dictation socket) always are. The settings window picks the profile every page edits
  and shows where each value comes from.
- **Performance settings:** polling rates for hardware, temperatures, disk and network,
  GPU load sampling, a graph heartbeat, the visualizer frame rate, and the system power
  profile — all per profile.
- **Widget presets** (formerly "widget profiles"): a shared library of widget settings,
  with usages, rename and delete; clock, hardware and workspaces may appear more than
  once in a section.
- History graphs for every hardware source and for network throughput (download and
  upload), with a heartbeat wave on each sample.
- Every GPU is listed with its own load, VRAM and temperature.
- Calendar load errors are shown in the panel, with a retry.
- `qs ipc call settings open | openPage <page> | toggle | close`, and
  `qs ipc call profiles simulate | clearSimulation | status`.
- The shell's version in the settings sidebar.

### Changed
- The config moved into profiles; settings from older configs are migrated once, with a
  backup next to the config.
- Network state follows NetworkManager's events instead of polling `nmcli`, and the
  hardware sources read `/proc` and `/sys` directly instead of spawning `cat`.
- One settings window for the whole shell instead of one per monitor.

### Fixed
- Months of random crashes: no live arrays bound to `Repeater.model`, and popup content
  is created after its window.
- The shell freezing while the calendar loaded, token refresh, all-day events, Wi-Fi
  names containing colons, notification action buttons, and many smaller issues — see
  the git history and `docs/TODO.md`.

### Security
- The Google client secret no longer appears on a process command line.
- The config directory is restricted to its owner (700, files 600).
- Workspace names are escaped in Hyprland dispatches.
