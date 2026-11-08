# Plan: the battery widget's popup

Status: **planned 2026-11-08; stage 1 under way.** Requested by the user with the battery
widget (`widgets/BatteryWidget.qml`): the power profile with an override, and — as on
Android — a graph of energy use and use per app.

## What the system gives (measured on the Framework 12, 2026-11-08)

- **Power profile**: power-profiles-daemon, read and set through Quickshell's
  `PowerProfiles`. The shell already sets it from its profiles (`system.powerProfile`,
  `Profiles._applyPowerProfile`): only when the effective value changes; a change by hand
  stays until then.
- **Battery history**: UPower records it and serves it over D-Bus without root —
  `org.freedesktop.UPower.Device.GetHistory(kind, timespan, resolution)` → `a(udu)`
  (time, value, state) for `charge` (percent) and `rate` (watts, every few tens of
  seconds: 537 points in 4 h). The files in `/var/lib/upower/` are root's; the D-Bus call
  is enough. On the Framework the history starts 2026-11-08 14:32 (UPower enabled that
  day); how long UPower keeps it is not checked yet. `Energy`, `EnergyRate`,
  `TimeToEmpty`, `GetStatistics` are there too.
- **Power now**: `current_now × voltage_now` in `/sys/class/power_supply/BAT1` (3.9 W
  measured), or UPower's `EnergyRate`.
- **Per process**: CPU time from `/proc/<pid>/stat` (every process); GPU time from the
  `xe` driver's `drm-cycles-*` in `/proc/<pid>/fdinfo` (the user's own processes);
  `/proc/<pid>/cgroup` names systemd units (services, kitty's per-tab scopes).
- **Not available**: RAPL energy counters (`/sys/class/powercap/intel-rapl*`, `psys`
  included) are root-only — closed on purpose after the Platypus side channel; not to be
  reopened. Nothing attributes the screen, Wi-Fi or the platform to an app.

## Decisions (with the user, 2026-11-08)

- The override lasts **until the next change**: the existing rule — a profile wanting
  another power profile (plugging in, Power save on battery) sets it again. The popup
  says which profile will and when.
- Use per app is counted **since the last full charge**, as on Android; sampled only on
  battery.

## Stages

1. **Popup with the power profile.** The widget opens a popup (it becomes a
   `PopupWidget`): the charge, charging or not, time to empty or full; the system power
   profile as three choices, the current one picked; a line saying whether it is what the
   shell's profiles want, or overridden and which profile will set it back.
2. **Graph from UPower's history.** Charge over the last 24 h, charging marked, and the
   power drawn beneath it — `GetHistory` through `busctl --json` (a Process, the idiom of
   ARCHITECTURE.md), drawn with `components/HistoryChart.qml`.
3. **Use per app, estimated.** A sampler in a singleton, on battery only, every ~30 s:
   battery power, CPU time per process, GPU cycles per process; processes grouped into
   apps (a systemd unit's name; kitty's scopes → kitty; what Hyprland started, by name;
   kernel threads → System). The power above a learned baseline (the lowest draw with the
   CPU idle) is split by CPU and GPU share; the baseline goes to "System and screen". Sums
   since the last full charge in a state file (`~/.local/state/h2s_shell/`), shown as an
   estimate. First probe (15 s): 3.9 W, CPU 8 % busy, 90 % of it one terminal's process.

## Open

- How long UPower keeps its history; whether the graph needs its own record beyond it.
- Grouping apps by window class (Hyprland's `clients` pid → class) rather than process
  name, for nicer names.
- Hyprland's own GPU cycles read as 0 in the probe — whether the compositor's rendering
  is counted elsewhere.
