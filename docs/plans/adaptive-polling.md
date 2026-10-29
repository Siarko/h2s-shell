# Plan: shell profiles, and polling rates as their first use

Status: **design agreed 2026-10-28, not started.** Replaces TODO 5.3 ("gate polling on
whether anything is observing it") and absorbs 5.4 (cava frame rate).

## Why

TODO 5.3 offered three fixed behaviours: always poll, poll only while watched, or a
fast/slow split. The user's call: none of them should be hard-coded. On a laptop on
battery they may want the minimum; plugged in, full-rate graphs.

The user's further direction (2026-10-28): this is the first use of a general feature —
**shell profiles**. A profile is a named list of setting overrides, activated by
conditions. Later profiles will reach many settings across the shell, with a richer
condition engine; for now they only need to cover polling rates and the system power
profile, but the design must not need reworking when they grow.

Where things stand after 5.1 and 5.2 (measured on the desktop, 2026-10-28): the shell
idles at ~0.6% of one core and ~25 main-thread wakeups/s. About 10 of those wakeups are
the GPU load sampling (200 ms, two cards); the Framework 12's Intel GPU has no amdgpu
counters, so it will not have that cost.

## Decisions (2026-10-28)

1. **Categories** of polling, each with its own rate: `hardware` (CPU, RAM, GPU load,
   VRAM), `temperatures` (every temperature, CPU and GPU, at one rate), `disk`,
   `network` (link throughput), `visualizer` (cava fps).
2. **No built-in watched/background split.** "A panel is open" is a condition like any
   other; a profile activated by it raises the rate. One mechanism, not two.
3. **Conditions**: a structured engine that will grow. Format is a tree from the start;
   v1 facts are the four below plus fullscreen.
4. **The shell may set the system power profile**, as a profile setting. The power
   widget that will expose profile switching comes later.
5. **Every profile is a config entry** the user can edit, reorder and delete. The config
   starts with one profile, **Full** (no condition, today's values). Behind them sits a
   read-only **system profile** — the schema defaults — which is what applies when the
   user has deleted every profile. **Power save** (on battery) is seeded alongside Full
   on first run (decided 2026-10-29).
6. **Settings UI**: a global **Profiles** page for profiles, their conditions and order;
   a **Performance** section for the polling rates. Both edit through one schema
   registry.
7. **Loop guard**: the UI refuses to save a profile that both reads `power.profile` and
   sets `system.powerProfile`, and says why.

## What polls today

| Poller | File | Rate | Category |
|---|---|---|---|
| CPU, RAM | `singletons/hardware/{Cpu,Ram}Source.qml` | 2 s | hardware |
| GPU load, per card | `singletons/hardware/GpuLoadSource.qml` | 2 s tick, 200 ms samples | hardware |
| VRAM, per card | `singletons/hardware/GpuMemorySource.qml` | 2 s | hardware |
| CPU temperature | `singletons/hardware/CpuTempSource.qml` | 5 s | temperatures |
| GPU temperature, per card | `singletons/hardware/GpuTemperatureSource.qml` | 2 s | temperatures |
| Disk (`df`, a process) | `singletons/hardware/DiskSource.qml` | 10 s | disk |
| Link throughput, per link | `singletons/network/LinkSpeed.qml` | 2 s while the link is up | network |
| cava visualiser | `singletons/Music.qml` / CLEANUP #23 | 60 fps while playing | visualizer |

Not categories, stay fixed: the network fallback poll (60 s; events do the work), the
Wi-Fi scan (5 s, only while the panel is open), music position (1 s, only while
playing). Event-driven already: workspaces, notifications, tray, audio, network state,
MPRIS metadata.

## Concepts

### Setting schema

A registry of the settings profiles may override, `singletons/SettingsSchema.qml`
(name open). Each entry:

```
{ key: "polling.hardware.interval", label: "Hardware", group: "Polling",
  type: "interval", min: 0, max: 60000, default: 2000 }
```

`type` drives the editor widget (interval picker with "paused" = 0, enum dropdown,
bool, number). The defaults are today's values, so an empty config behaves exactly as
the shell does now.

v1 keys:

| Key | Type | Default |
|---|---|---|
| `polling.hardware.interval` | interval | 2000 |
| `polling.hardware.gpuSampling` | enum `averaged` / `single` | `averaged` |
| `polling.temperatures.interval` | interval | 2000 — CPU temperature was 5 s, GPU 2 s; one rate now, so CPU temperature reads more often than before |
| `polling.disk.interval` | interval | 10000 |
| `polling.network.interval` | interval | 2000 |
| `polling.visualizer.fps` | number | 60 |
| `system.powerProfile` | enum `unchanged` / `power-saver` / `balanced` / `performance` | `unchanged` |

### Profile

```
{ name: "Power save",
  enabled: true,
  when: { all: [ { fact: "power.onBattery", is: true } ] },
  set:  { "polling.hardware.interval": 10000,
          "polling.hardware.gpuSampling": "single",
          "polling.temperatures.interval": 30000,
          "polling.disk.interval": 0,
          "polling.network.interval": 10000,
          "polling.visualizer.fps": 15,
          "system.powerProfile": "power-saver" } }
```

Only the keys a profile sets are overridden; everything else falls through.

**Layering.** Several profiles can match at once. Profiles are an ordered list, and the
effective value of a key is the system profile overlaid by every active profile in
order — a later profile wins a conflict. The user reorders the list in the UI. (Same
model as CSS: defaults, then cascading layers.)

**System profile.** Built in, read-only, not in the config: every schema key at its
default. It is always the bottom layer, so a key no profile sets has a value, and it is
the whole story once the user deletes every profile.

**Full.** The profile the config starts with: no condition (always active), setting
today's values explicitly, so they are visible and editable as a profile rather than
hidden defaults.

### Conditions

A tree, so the engine can grow without migrating stored profiles:

- `{ all: [...] }`, `{ any: [...] }`, `{ not: {...} }`
- leaf: `{ fact: "<name>", is: <value> }` or `{ fact: "<name>", lt: <n> }` / `gt`
- an empty or missing `when` means "always" — a profile that is just switched on

v1 facts, all signals rather than polls:

| Fact | Source |
|---|---|
| `power.onBattery` | `UPower.onBattery` |
| `battery.percent` | `UPower.displayDevice.percentage` |
| `power.profile` | `PowerProfiles.profile` (power-profiles-daemon) |
| `screen.locked` | the shell's own `Lockscreen` state |
| `window.fullscreen` | Hyprland: the focused window on any monitor is fullscreen |
| `panel.open` | which popup content is open (`hardware`, `network`, …) — replaces "watched" |

Checked on the host 2026-10-28: `Quickshell.Services.UPower` exposes `onBattery`,
`displayDevice` and `PowerProfiles` (with `PowerProfileHold`).

v1 UI edits only a flat `all` list of leaves; the stored format already allows nesting.

**Feedback loops.** A profile that sets `system.powerProfile` must not be activated by
`power.profile`, or it can flip itself. v1: the resolver ignores `power.profile` changes
caused by the shell's own hold — or simpler, the UI refuses to save a profile that both
reads `power.profile` and sets `system.powerProfile`. Decide when implementing.

### `singletons/Profiles.qml`

- Owns the fact values (binding to UPower, Lockscreen, Hyprland, Popup state).
- Evaluates every profile's `when` with a pure function `matches(condition, facts)`,
  exposes `activeProfiles` (names, in order) and, per key, which profile set it — the UI
  shows "polling.disk.interval: paused (Power save)".
- `value(key)` returns the effective value: the last active profile that sets it, else
  the schema default (the system profile). Reactive — bindings follow profile
  changes immediately.
- A **simulate** override for facts ("on battery, 15 %"), so profiles can be tested on
  the desktop, which has no battery.
- `system.powerProfile`: while the effective value is not `unchanged`, hold a
  `PowerProfileHold` with that profile; released when it changes back.

Pure functions (`matches`, the overlay) get a test suite, like `CalendarDates`.

### Consumers

Each source's `Timer` binds `interval` to `Profiles.value("polling.<category>.interval")`
and `running` to "interval > 0" (plus its own existing gates). `GpuLoadSource` runs its
200 ms sampler only when `gpuSampling` is `averaged`.

### History and graphs

- Slower sampling keeps history continuous; `HistoryChart` places points by timestamp.
- Paused (interval 0) leaves a real gap. `HistoryChart` currently draws a straight line
  across it, which looks like data: store the interval with each sample (`{ t, v, dt }`)
  and break the line where the gap is much longer than `dt`.
- On a rate change, sample at once rather than waiting a full new interval.
- History is capped by sample count (1800, i.e. 1 h at 2 s). At a faster rate that is
  less than the graph's 1 h, at a slower one more: trim by age instead.
- CPU usage and link speed are deltas: after a pause, the first sample only re-establishes
  the baseline (LinkSpeed already does this via `_reset()`; CpuSource needs the same).
- The capsule on the bar shows live values: if a profile pauses a category the capsule
  shows, its values freeze. Acceptable — it is the user's profile — but the settings UI
  should say so next to "paused".

### Config

`Config.profiles`, the ordered list, stored as a JSON string as `widgetProfiles` is
today; CLEANUP #11 (the config/JSON rework, Stage 6) is the proper fix, and it moves
with that. When the key is absent (first run, or a config from before profiles) it is
seeded with Full and Power save. An empty list is different from an absent one: it means the user
deleted everything, and the system profile applies.

**Host behaviour must not change**: Full and the system profile both equal today's
rates — except the temperatures, now one rate (see the schema table).

### Settings UI

- **Profiles** page (new, global): the ordered profile list with enable switches and
  drag to reorder; per profile, its conditions (flat list of fact / comparison / value
  rows) and its overrides (pick a setting from the schema, set its value with the
  schema's editor). Top of the page: what is active right now and why. The simulate
  override lives here.
- **Performance** section: the polling rates (every `polling.*` key), edited with the
  schema editors. It edits one profile at a time, chosen at the top of the section
  (Full by default), and marks values that a later active profile overrides. This is the
  pattern every settings page can adopt once profiles reach more settings: a page is a
  view of a schema group, editing the chosen profile.

## Implementation order

1. `SettingsSchema` with the v1 keys and today's defaults; `Profiles` with `value()`
   returning base/default only; sources bind to it. Verify on the host that nothing
   changed.
   *Done 2026-10-29, awaiting host verification.* `visualizer.fps` waits for step 8.
   LinkSpeed now divides by the time actually elapsed between reads, not by the
   configured interval, since a profile can change the rate between two reads.
2. The condition engine and overlay as pure functions, with tests; `Profiles` evaluates
   profiles from a hard-coded list.
   *Done 2026-10-29.* `singletons/ProfileRules.qml`: `matches`, `resolve`, `saveError`
   (the loop guard), `seedProfiles`. An unknown fact satisfies no comparison, so a
   missing fact never switches a profile on — but `not` of it holds ("battery is not
   below 20 %" is true on a desktop). `system.powerProfile` is in the schema already, so
   the seed can carry it; nothing applies it until step 6.
3. Facts: UPower, battery, power profile, lock, fullscreen, open panel; the simulate
   override.
   *Done 2026-10-29, verified on the host.* Simulation is an IPC call for now:
   `qs ipc call profiles simulate '{"power.onBattery": true}'`, `clearSimulation`,
   `status`. Measured with a simulated battery: 28 → 3 wakeups/s, 6 → ~0 ms CPU/s.
   `battery.percent` assumes Quickshell's 0–1 `percentage` — check on the laptop.
4. Graph gap handling and the delta baseline reset.
5. Config storage for profiles and base values; the shipped "Power save".
6. `system.powerProfile` via `PowerProfileHold`, with the loop guard.
7. Profiles settings page; base polling rates in settings.
8. Visualiser fps (TODO 5.4) wired to `polling.visualizer.fps`.

Each step is shippable alone and verifiable on the desktop (steps 3 and 6 through the
simulate override, or the laptop).

Independent quick win, any time: disk usage barely moves, so its default could go from
10 s to 60 s — but that changes host behaviour, so only with the user's say-so.

## Decided 2026-10-29

- The Performance section edits a chosen profile (option A above). The user wants to try
  it before judging how usable it is — build it so that switching to "edits only Full"
  would be a small change.
- The settings must show which profiles are active right now, and why: on the Profiles
  page, and as a compact indicator visible from the other settings pages (e.g. the
  settings window header) — "Active: Full, Power save (on battery)".
