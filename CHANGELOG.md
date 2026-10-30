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
- Changing theme fades the colours over ("themeChange"), also when a theme file is changed
  by another program, such as matugen; edits from the settings apply at once.
- Tray icons grow in when an application adds one ("enter"); networks and Bluetooth
  devices found by a scan fade in, and re-sorted networks slide to their place ("move").
- Settings: the mark of the selected page slides to the new one and the page fades in;
  page names highlight under the pointer.
- Calendar: months slide past each other, the new one coming from its side, and the selected day and
  week move smoothly. Music: a new track's title and cover fade in.
- When a profile change adds or removes widgets on the bar, they grow in and shrink away
  ("enter", "exit"), and the widgets beside them slide over. The lock screen fades in,
  and waking it fades the notifications out and the password prompt in.

- A curves library, `~/.config/h2s_shell/curves.json`: named cubic Béziers
  (`"springy": [0.3, 1.6, 0.4, 0.9]`) that a theme's `curves` can use by name, alongside
  Qt's own (OutQuad, OutBack, …). Watched, like themes; an unknown curve falls back to
  OutQuad and is reported.
- Settings → Curves: an editor for the curves library — a graph with two draggable control
  points (scroll to zoom), exact numbers, a looping preview against a second curve with
  a dot following each curve on the graph, new curves blank or copied from Qt's, rename
  (themes using the curve follow), delete (asking first), and where each curve is used.
  Curves can have more points: double-click the curve to add one, select a point to
  type its position, remove it, or switch off "Smooth" for a corner there.

- Settings has two tabs: Behaviour, whose pages edit a profile (picked at the top of the
  sidebar, which also says which theme that profile uses, a click away), and Appearance,
  whose pages edit a theme (picked the same way, starting at the edited profile's theme,
  saying which profiles use it, with "Preview" to try the theme on the whole shell while
  editing it — saved nowhere, the theme list locked meanwhile, ended by "Stop preview",
  leaving Appearance or closing the window). Appearance's first page, Themes, shows who
  uses the picked theme and what is wrong with it, sets what it extends, and makes a
  new theme (extending it, or as a copy), renames it (themes and profiles follow) or
  deletes it (asking first; profiles using it go back to the default theme). Curves moved
  into the group.

- Settings → Appearance → Colors: every base colour of the picked theme, by group, with
  what it is for and where its value comes from (set here, inherited, a palette, built
  in), and a colour picker (saturation and brightness, hue, opacity, hex). Changes are
  drafts, kept in `~/.config/h2s_shell/theme-drafts/` until saved — across restarts too:
  the page has Save and Cancel, a banner offers to save or throw away all of a theme's
  changes, ✎ marks the pages and themes with unsaved changes, and Preview shows a theme
  with its changes (also the theme in use, when it has some). Reset returns a colour to
  the inherited value; Undo takes back one colour's unsaved change.

- Settings → Appearance → Fonts: the theme's font family, picked from the installed fonts
  (searchable, each shown in itself), and its 13 sizes, each with a sample, a slider,
  where its value comes from, Reset and Undo; drafts like colours. Warns when the bar's
  larger icons would not fit its cells.

- Settings → Appearance → Bar: the bar's size, margins and corners, moved from the Bar page
  (which keeps the widgets) into the theme's pages, as drafts with Reset and Undo.

- Settings → Appearance → Animations: each animation role's duration and curve (a
  popup's two), from the curves library or Qt's, with where each comes from, Reset, Undo
  and a preview that plays it; drafts like the other theme pages.

### Changed
- Buttons, pills and switches are shared components everywhere: the Network, Bluetooth
  and calendar settings buttons, the preset and choice pills, the event form's choices,
  every on/off switch, the slider's tooltip. Small changes follow: Network VPN, scan and
  Bluetooth buttons have the common rounded corners and height; a running scan shows as
  a filled button; disconnecting is red under the pointer.
- Forgetting a Wi-Fi network or a Bluetooth device, and disconnecting the Google account,
  ask first, like every other delete.
- Settings pages are named by id: `qs ipc call settings openPage` takes a page's id
  (`profiles`, `bar_appearance`, …), not its label.
- Ready for larger fonts: buttons, pills, fields, icon buttons, Bluetooth device cards,
  event cards and calendar rows grow with their text instead of letting it spill out
  (today's sizes are the minimum, so nothing changes at the default sizes); long names in
  the settings sidebar and label columns are cut with "…"; the notification bell and
  the small symbols (×, ✓, ▾) take their font from the theme.
- A click anywhere in the settings window or a popup — the background too — takes the
  focus from a text field; before, only clicking another control did.
- The "Theme" setting suggests the theme files as you type (and "default"), and warns
  when the name has no file.
- Deleting a profile, a widget preset or a curve asks the same way everywhere: the button
  turns into a red question with a "×" attached to cancel.
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
- Wi-Fi list: an open network and its typed password stay with that network; after a scan
  or a connection they used to jump to whichever network took its place in the list.
- The calendar's and the hardware popup's left curved corner no longer shows a faint seam
  next to the panel (the popup now sits on whole pixels).
- Notifications on the lock screen and screensaver have the same padding below as above.
- Switching from a taller popup to a shorter one animates the height too; the panel's
  background used to drop to the new height at once.
- Numbers no longer spill out of their columns: a slider's value ("3000 ms"), the
  track's times, mixer volumes, the volume OSD's "100%", the hex and coordinate fields.
- The lock screen never came on: locking and unlocking were lost when its settings
  became per profile.
- The screensaver's first fade after start keeps its full duration.
- Settings: the selected page's mark always slides (it sometimes jumped), and the Bar page
  no longer logs binding loops while editing a profile whose theme is not in use.
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
