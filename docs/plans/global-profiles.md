# Plan: every setting per profile, with user-pinned global settings

Status: **done 2026-10-29** — all five stages. Follows
[adaptive-polling.md](adaptive-polling.md), which built profiles for the polling,
graph and power settings. This extends them to the whole shell. It is also, in effect,
CLEANUP #11 (the config/JSON rework).

## Why

The user wants to pick, in the settings window, which profile they are editing, and
have every setting saved per profile — a different bar, notification behaviour or
lockscreen timeout on battery, for example. And some settings must be independent of
the profile: **the user decides which**, by marking a setting as global, not a list
fixed by us.

## Scale (counted 2026-10-29)

- 55 settings in `singletons/Config.qml`; about 40 make sense per profile.
- 44 files read `Config.*` directly (59 distinct settings).
- About 150 writes to `Config.*` in the settings pages.

## Model

Layers, bottom to top, for each setting key:

1. **System profile** — the schema default (`SettingsSchema`).
2. **Profiles** — every active profile that sets the key, in list order.
3. **Global values** — if the user has pinned the key as global, its global value,
   which ignores every profile.

So `value(key)` = the global value if the key is pinned, else the last active profile
that sets it, else the default.

### Global settings, chosen by the user

- Stored as `Config.globals`: `{ key: value }` — the pinned keys with their one value.
- Pinning a key (a pin control next to every setting): its global value starts as the
  current effective value, so nothing visibly changes.
- While pinned, editing the setting writes the global value, whichever profile is being
  edited; the editor says "global — the same in every profile".
- Profile values for a pinned key are **kept, not deleted**, and shown as "ignored while
  global". Unpinning brings them back into effect.
- `ProfileRules.resolve` takes the globals as a last layer; `setBy(key)` reports
  "global". Pure, so it gets tests like the rest.
- **Always-global settings, by the schema** (asked for 2026-10-29): a schema entry with
  `global: true` behaves as if pinned and cannot be unpinned — its pin is locked and says
  so. For settings where per-profile values make no sense: Debug Mode and fetch debug
  (to be flagged when the General page is migrated), likely more later. Whether the
  Google Calendar integration is one is undecided — it might reasonably be off on battery.
  Mechanism built 2026-10-29 (`SettingsSchema.systemGlobalDefaults`).
- Some settings are never per profile, by nature rather than by choice — credentials and
  tokens (Google client id/secret/tokens/expiry), remembered per-app volumes, internal
  flags. These stay out of the schema and out of profiles entirely, and do not get a pin.

### Where the base values live

Today the values sit in Config's sections (`general`, `media`, `bar`, …). With profiles
for everything, they move once into **Full**, which then spells out the user's values,
and the old sections go away (keeping the excluded settings above). A backup is taken
first. This is the config rework of CLEANUP #11.

## Settings UI

- The **editing profile** picker moves from the Performance page to the settings window
  itself, next to the active-profile indicator, and applies to every page.
- Pages edit the picked profile. Simple settings (bool, number, enum, interval, text) use
  the shared `SchemaSettingEditor` — such pages become a declarative list of keys.
  Structured settings (the bar's widget lists, hardware source lists, notification code
  patterns, widget profiles) get their own editors and are overridden as a whole value.
- Every editor shows: set here / inherited / overridden now by a later profile / global,
  with the pin control and a reset to inherited.
- Until a page is migrated, it says so when a profile other than Full is picked, and
  keeps editing the config directly.

## Stages

1. Window-level editing-profile picker — *done 2026-10-29*.
2. User-pinned and always-global settings — *done 2026-10-29*.
3. Foundations, then the simple pages (below).
4. The bar.
5. Cleanup.

Decisions taken with the user on 2026-10-29 for stages 3–5:
- Widget "profiles" stay a **shared, global library** and are **renamed "presets"** (UI,
  code, config key). Shell profiles decide which widgets the bar has and which preset each
  instance uses; preset contents are not per profile.
- A profile overrides the bar **per section** (left / center / right are three settings).
- **Popup mode** (click / hover / none) becomes a per-profile setting per widget type.

### Classification of the Config settings

- **Per profile (schema keys):** media style/layout; lockscreen enable/timeouts/fades/
  notification visibility; notifications codePatterns; stt previewEnabled, previewWidth,
  finalLingerMs, showPending, pauseMusicWhileDictating; gcal.enabled;
  bar.layout.* (11 ints); bar.left/center/right; widgets.<type>.popupMode; hardware popup
  sources, popup labels and capsule labels.
- **Always global (schema `global: true`):** general.debug, general.fetch_debug,
  stt.debug, gcal.debug, stt.socketPath (machine wiring; a profile switch would drop the
  dictation connection).
- **Not settings, stay in Config, no schema:** gcal clientId/secret/tokens/tokenExpiry,
  gcal.enabledCalendarIds and gcal.viewMode (account data / UI state written by code),
  audio.appVolumes (remembered per-app volumes), the widget preset library, profiles,
  globals.
- **Left alone:** lockscreen screensaverExecCmd/Sleep/Wakeup — nothing reads them; TODO
  9.7 decides implement-or-remove. They keep their current Config storage.

### Stage 3a — foundations

1. **Schema types** in `singletons/SettingsSchema.qml` + `panels/settings/SchemaSettingEditor.qml`:
   - `string` (text field; datetimeFormat), `number` (min/max/suffix; timeouts, linger),
     `slider` presentation for bounded ints (bar geometry, fades, previewWidth),
     `stringList` (codePatterns), and `custom` with an `editor` name for structured values
     (bar sections, hardware source lists/labels) whose editors live with their pages.
   - Structured values are overridden as a whole; editing an inherited one first copies
     the inherited value into the edited profile (copy-on-write), so the editor always
     edits a full value.
2. **Logger cycle:** `components/Logger.qml` reads `Profiles.value("general.debug")`;
   Profiles' own Logger gets an explicit `enabled` so constructing Profiles does not need
   Profiles. (`SettingsSchema`/`ProfileRules` import nothing of ours — safe.)
3. **Change-signal consumers:** code that reacts to `Connections { target: Config.x }`
   (MusicPanel repaint, Lockscreen idle monitors) switches to local
   `readonly property … : Profiles.value(…)` with `on…Changed` handlers, plus one apply at
   startup (today they only fire because loading the file emits change signals).
4. **Config migration, incremental, per key** (refined when implementing, 2026-10-29):
   groups move one at a time while un-migrated pages keep writing the old sections, so a
   one-shot copy would lose edits made in between. Instead each schema entry names its
   old location (`legacy`), and a key is copied into Full — or into `globals` if always
   global — exactly once, the first time it appears in the schema; `Config.migratedKeys`
   records which. A backup of the config file is written before any migration that
   changes it. The pure part (`ProfileRules.migrateLegacy`) is tested with a fixture
   shaped like the user's real config. The preset rename and the moving of per-type
   `_popupMode` / hardware `_popup*` keys out of the preset library happen in stage 4.

### Stage 3b — pages, simple first

Each group: schema entries → consumers switched to `Profiles.value()` → page rebuilt from
`SchemaSettingEditor` (taking `editIndex` from `panels/SettingsWindow.qml`) → removed
from the window's scope-note list (`_perProfileCategories`). One commit per group,
verified on the host before the next.

1. **General:** the two debug switches (always global, locked pin). Readers:
   `components/Logger.qml`, `singletons/network/Fetch.qml`.
   *Done 2026-10-29, verified on the host.* `datetimeFormat` was dropped rather than
   migrated (the user's call): its only reader was the clock widget's fallback when its
   preset has no format, and `Time.time` was dead code — the clock format belongs to the
   clock preset; without one it is a fixed "hh:mm:ss".
2. **Media:** visualizerStyle/Layout; `panels/MusicPanel.qml` bindings and its repaint
   `Connections`.
   *Done 2026-10-29, verified on the host.*
3. **Lockscreen:** `singletons/Lockscreen.qml` idle monitors (imperative enable — see
   foundation 3), `screensaver/ScreensaverSurface.qml`, `screensaver/LockSurface.qml`.
   *Done 2026-10-29, verified on the host.* Lockscreen now reports the lock to Profiles
   (`Profiles.screenLocked`) instead of Profiles reading Lockscreen — the two would have
   depended on each other. Found while testing: the screensaver's fade never showed,
   since the window itself was black; the black now lives in the fading layer. The
   schema gained `number` and `slider` types; the editor `available` and `label`.
4. **Notifications:** codePatterns with the `stringList` editor;
   `singletons/Notifications.qml`.
   *Done 2026-10-29, verified on the host.*
5. **Dictation:** stt.*; `singletons/Stt.qml`, `widgets/SttWidget.qml`,
   `singletons/DictationMusicPause.qml`. Order for a widget instance: preset value →
   `Profiles.value` → schema default (`panels/widget_settings/SttWidgetSettings.qml`
   placeholder text follows).
   *Done 2026-10-29, verified on the host.* The schema gained `hint` (a note under the
   setting); the stt widget preset's "Global" option became "Inherit".
6. **Calendar:** gcal.enabled (per profile) and gcal.debug (global); credentials and
   tokens untouched. Note: today `gcal.enabled` only changes a status message — the sync
   ignores it; making the sync honour it is filed in TODO, not done here.
   *Done 2026-10-29, verified on the host* (TODO 8.10 filed for the sync).

### Stage 4 — the bar

- **Keys:** `bar.layout.<name>` ×11; `bar.left`, `bar.center`, `bar.right`, each a list
  of `{ type, preset }` (replacing the two parallel arrays and their short-array case);
  `widgets.<type>.popupMode` for each popup widget type (from `WidgetRegistry`);
  `widgets.hardware.popupSources`, `.popupLabels`, `.capsuleLabels`.
- **Consumers:** `Bar.qml` builds each section's model from `Profiles.value("bar.<side>")`
  (keeps `ScriptModel` and `_wireWidget`'s binding through `delegate.modelData`; the
  widget property `profile` becomes `preset`); layout readers `Bar.qml`,
  `panels/Popup.qml:97`, `panels/NetworkPanel.qml:481`, `Hud.qml:61`,
  `hud/NotificationHudItem.qml:23`; `components/PopupWidget.qml` popup mode;
  `widgets/HardwareWidget.qml`, `panels/HardwarePanel.qml`, `panels/HardwareSourceList.qml`
  for the hardware keys.
- **Presets rename:** `Config.widgetProfiles` → `Config.widgetPresets` and every reader/
  writer (`widgets/{Clock,Workspaces,Hardware,Stt}Widget.qml`,
  `panels/widget_settings/*.qml`, `panels/WidgetSettingsPane.qml`); UI text "Profile" →
  "Preset".
- **Settings UI:** `panels/settings/BarSettings.qml` geometry through the schema editor
  (slider presentation, keeping the existing barHeight/reservedSpace/topOffset clamping as
  the editor's `onEdited` logic); each section's `panels/BarSectionList.qml` shows the
  edited profile's section, or the inherited one dimmed with "inherited from Full" and a
  pin / reset like other settings — the first edit copies it in. `WidgetSettingsPane`
  writes popup mode to the edited profile and keeps the preset picker (global library).
- Same bar on every monitor, as today; a per-monitor bar would be a new condition fact
  later, not part of this plan.
- *Done 2026-10-29, verified on the host.* Refinements made while implementing: the
  hardware capsule labels moved into the hardware preset (a preset now describes its
  capsule completely; the popup's sources and labels are one profile setting,
  `widgets.hardware.popup`); `legacy` can be a function for values spread over several
  old places; the bar's section models carry a stable key (`ProfileRules.sectionModel`)
  so a profile change elsewhere does not recreate the widgets; the preset picker became
  pills applied at once plus a "new preset" field. A review of presets is TODO 10.7.

### Stage 5 — cleanup

Remove the migrated sections from `singletons/Config.qml` (keeping the excluded settings
above), the scope note in `SettingsWindow.qml`, update `docs/ARCHITECTURE.md` (Config,
Bar composition, Widget contract), `docs/FEATURES.md`, close CLEANUP #11 and TODO 10.3.

*Done 2026-10-29, verified on the host.* The migration now reads old values from the raw
config file rather than from Config properties, so an old config (a restored backup, a
copy on another machine) still migrates after the sections are gone; a missing section
means nothing to move — never an empty bar. Tested against a fixture shaped like the
user's old config.

### Verification

- `quickshell -p tests.qml` after every change: ProfilesTest (migration fixture with the
  user's config shape; every Config key is classified — schema, excluded or left alone —
  so nothing is forgotten; resolve with structured values and copy-on-write), plus
  SettingsPagesTest / WidgetRegistryTest compile checks.
- On the host, per group: back up `~/.config/h2s_shell/config.json`, restart the shell
  myself (`qs kill -c default && qs -c default -d`), check `qs log` is clean, check
  `qs ipc call profiles status`, diff the config against the backup (migration must only
  move values, not change them), then the user checks the page and the affected
  feature behave exactly as before.
- For per-profile behaviour: set a different value in Power save, simulate battery
  (`qs ipc call profiles simulate '{"power.onBattery": true}'` or the Profiles page),
  watch it apply, clear the simulation.
- Bar specifically: Power save without the hardware capsule on the left section →
  simulated battery removes it, AC brings it back with its preset labels intact
  (the earlier regression where workspace/hardware labels vanished must not return).

## Open

- Whether `widgetProfiles` (per-widget-instance settings such as labels) becomes part of
  profiles as one structured value, or is split into keys.
- Text settings (date format, commands) need a text editor in `SchemaSettingEditor`.
