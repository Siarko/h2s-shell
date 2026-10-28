# Plan: user-configurable, condition-driven polling rates

Status: **proposal, not started** (written 2026-10-28, to be continued 2026-10-29).
Replaces TODO 5.3 ("gate polling on whether anything is observing it") and absorbs 5.4
(cava frame rate). Open questions for the user are at the end — settle those first.

## Why

TODO 5.3 offered three fixed behaviours: always poll, poll only while watched, or a
fast/slow split. The user's call: none of them should be hard-coded. On a laptop on
battery they may want the minimum; plugged in, full-rate graphs. So the rates are
configuration, and which set of rates applies is chosen by conditions.

Where things stand after 5.1 and 5.2 (measured on the desktop, 2026-10-28): the shell
idles at ~0.6% of one core and ~25 main-thread wakeups/s. About 10 of those wakeups are
the GPU load sampling (200 ms, two cards); the Framework 12's Intel GPU has no amdgpu
counters, so it will not have that cost. The rest are the hardware sources, link speed,
the clock, and whatever is animating.

## What polls today

| Poller | File | Rate | Feeds a graph |
|---|---|---|---|
| CPU, RAM | `singletons/hardware/{Cpu,Ram}Source.qml` | 2 s | yes |
| CPU temperature | `singletons/hardware/CpuTempSource.qml` | 5 s | yes |
| Disk (`df`, a process) | `singletons/hardware/DiskSource.qml` | 10 s | yes |
| GPU load, per card | `singletons/hardware/GpuLoadSource.qml` | 2 s tick, 200 ms samples | yes |
| VRAM, GPU temperature, per card | `GpuMemorySource.qml`, `GpuTemperatureSource.qml` | 2 s | yes |
| Link throughput, per link | `singletons/network/LinkSpeed.qml` | 2 s while the link is up | yes |
| Network fallback poll | `NetworkManager`, `WifiManager`, `VpnManager`, `IpManager` | 60 s (events do the rest) | no |
| Wi-Fi scan | `singletons/network/WifiManager.qml` | 5 s, only while the panel is open | no |
| Music position | `singletons/Music.qml` | 1 s, only while playing | no |
| cava visualiser | `singletons/Music.qml` / CLEANUP #23 | 60 fps while playing | no |

Event-driven already, out of scope: workspaces, notifications, tray, audio, network
state (NetworkEvents), MPRIS metadata.

## Concepts

**Category** — a group of pollers that share a rate. Proposed:
`hardware` (CPU, RAM, GPU load/VRAM, temperatures), `disk`, `network` (link
throughput), `visualizer` (cava fps). Fine enough for "graphs fast, disk slow", coarse
enough for a settings page that fits on screen. The network fallback, Wi-Fi scan and
music position stay fixed — they are already cheap or already gated.

**Watched / background** — a poller is *watched* while something on screen shows it: its
popup panel is open, or it is in the bar capsule. Otherwise it runs in the *background*.
Every category has two rates, one per state. "Paused" is a valid background rate.

**Profile** — a named set of rates: for each category, the watched interval and the
background interval (or paused), plus the GPU sampling mode (averaged 200 ms samples vs
one sample per tick). Shipped presets, editable and extendable by the user:

| Profile | hardware watched / bg | disk | network | GPU sampling | visualizer |
|---|---|---|---|---|---|
| Full (= today) | 2 s / 2 s | 10 s / 10 s | 2 s / 2 s | averaged | 60 fps |
| Balanced | 2 s / 10 s | 30 s / 60 s | 2 s / 10 s | averaged when watched | 30 fps |
| Saver | 5 s / paused | 60 s / paused | 5 s / paused | single sample | 15 fps or off |

The numbers are a starting point, not a decision.

**Rules** — an ordered list; the first rule whose conditions all hold picks the profile,
and a final default rule always matches. Conditions are a fixed vocabulary, not an
expression language, so the settings UI can be a list of dropdowns:

- power source: on battery / on AC — `UPower.onBattery`
- battery level below N % — `UPower.displayDevice.percentage`
- system power profile: power-saver / balanced / performance —
  `PowerProfiles.profile` (power-profiles-daemon; follows the user's existing choice)
- screen locked or screensaver active — the shell knows this itself (`Lockscreen`)

Example: `on battery AND battery < 20 % → Saver`, `on battery → Balanced`,
`default → Full`.

All of these are signals, not polls: Quickshell's `Quickshell.Services.UPower` exposes
`onBattery`, `displayDevice` and `PowerProfiles`, checked on the host 2026-10-28.

## Design

### `singletons/Activity.qml` (name open)

The one place that knows the current profile and hands out rates.

- Reads profiles and rules from config, evaluates the rules against the condition
  inputs, exposes `activeProfile` (name) and `reason` (which rule matched, for the UI).
- `interval(category, watched)` — the interval in ms, or 0 for paused. Pure function of
  the active profile, so a `Timer` binds to it and follows changes immediately.
- The rule evaluation is a pure function, `resolveProfile(rules, conditions)`, so it can
  be unit-tested without a battery.
- A debug override ("simulate: on battery, 15 %") in settings, so the rules can be tested
  on the desktop, which has no battery.

### Watching

A small component, `PollingWatch { category: "hardware" }`, placed inside a panel or
widget: it registers on creation and unregisters on destruction, so Activity keeps a
count per category (or per source id, for the capsule, which shows individual sources).
Popup content is created per open and destroyed on close, so this needs no extra wiring.

Granularity question: per category is simpler; per source lets the capsule keep only the
sources it shows at the watched rate. Proposal: per source id, with a category fallback.

### Sources

Each source's `Timer` binds `interval` and `running` to `Activity.interval(...)`
instead of a literal. Paused → `running: false`. Switching rate does not reset history.

`GpuLoadSource` takes its sampling mode from the profile: averaged (the 200 ms sampler
runs) or single sample per tick (it does not).

### History and graphs

- History stays continuous whenever the background rate is not paused; samples are simply
  further apart, and `HistoryChart` already places points by timestamp.
- When paused, there is a real gap. `HistoryChart` currently draws a straight line across
  it, which looks like data. It should break the line where consecutive samples are much
  further apart than the rate they were taken at — store the interval with each sample
  (`{ t, v, dt }`) or break on a gap larger than, say, 3× the slowest configured rate.
- Coming back to watched after a pause: take a sample immediately (`triggeredOnStart`
  semantics on rate change), so the graph does not wait a full interval.
- CPU usage and link speed are deltas: after a pause, the first sample only re-establishes
  the baseline (LinkSpeed already does this via `_reset()`; CpuSource needs the same), so a
  10-minute average does not show up as a single point.

### Config

`Config.polling` holding `profiles` and `rules`. These are dynamic maps and lists, which
the config currently stores as JSON strings (like `widgetProfiles`) — CLEANUP #11, the
config/JSON rework, is the proper fix and is in Stage 6. Proposal: follow the existing
pattern now, migrate with #11.

**Host behaviour must not change** (see memory "preserve host behaviour"): with no
`polling` section in the config, the result is a single rule `default → Full`, and Full
equals today's rates exactly.

### Settings UI

A new settings page, "Performance" (name open):

- Current state on top: active profile and why ("Balanced — on battery").
- Rules: an ordered list, each row "conditions → profile", add/remove/reorder; the last
  row is the default and cannot be removed.
- Profiles: one card per profile, a row per category with watched and background rate
  pickers (dropdowns of sensible values, including "paused"), plus GPU sampling and
  visualiser fps. Duplicate / rename / delete; the shipped presets can be reset.
- The simulate override for testing.

## Implementation order

1. `Activity` with the shipped profiles hard-coded, the `Full` default, the pure
   resolver, and tests for it. No UI, no config. Sources bind to it. Verify nothing
   changed on the host.
2. Watching (`PollingWatch`) in the hardware panel, network panel and hardware capsule.
3. Graph gap handling and baseline reset after a pause.
4. Conditions: UPower, power profile, lock state; the simulate override.
5. Config: `Config.polling`, read and written by Activity.
6. Settings page.
7. Visualiser fps (TODO 5.4) as a category.
8. Disk interval: independent quick win — 10 s → 60 s in `Full` is worth discussing
   even before any of this, since disk usage barely moves.

Each step is shippable on its own and verifiable on the desktop; step 4 needs the
simulate override, or the laptop.

## Open questions for the user

1. Categories: are `hardware`, `disk`, `network`, `visualizer` the right split, or should
   e.g. temperatures be separate from load?
2. Watched/background per category — or is one rate per category per profile enough,
   with "pause in background" as a single switch?
3. Conditions: is the list complete? Candidates not listed: a specific monitor connected
   (docked), time of day, fullscreen app focused.
4. Should the shell also *set* the system power profile, or only follow it? (Proposal:
   only follow; setting it is a different feature.)
5. Preset names and numbers — Full / Balanced / Saver as above?
6. Settings page name and place in the settings navigation.
