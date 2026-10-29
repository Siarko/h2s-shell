# Changelog

Notable changes to the shell, newest first. Versions follow semantic versioning:
**major** for changes that need a config migration or change behaviour people rely on,
**minor** for features, **patch** for fixes. The number lives in
`singletons/Version.qml`; each release is tagged `v<number>` in git.

Add an entry under **Unreleased** with each user-visible change; a release renames that
section to the new version and date.

## [Unreleased]

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
