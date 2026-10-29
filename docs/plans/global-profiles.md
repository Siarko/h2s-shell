# Plan: every setting per profile, with user-pinned global settings

Status: **agreed 2026-10-29, first stage in progress.** Follows
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

Each shippable and verified on the host on its own.

1. **Window-level editing-profile picker**; un-migrated pages show the note. Visualizer
   fps (adaptive-polling step 8) lands on the Media page as its first per-profile
   setting.
   *Done 2026-10-29.* The picker is in the settings sidebar under the active-profile
   indicator; `SchemaSettingEditor` now takes `editIndex` and works out own / inherited
   / overridden itself, so a page only lists keys.
2. **Global settings**: `Config.globals`, the last layer in `resolve`, the pin control in
   `SchemaSettingEditor`, tests.
3. **Schema for every per-profile setting**, consumers switched to `Profiles.value()`,
   per page group. Migrating the config's values into Full, with a backup.
4. **Pages, simple first**: General, Media, Lockscreen, Notifications, Dictation, Calendar
   view settings.
5. **Structured settings**: bar layout and content, widget profiles, hardware source
   lists, notification code patterns — each with an editor that overrides the whole value.
6. Remove the old Config sections; CLEANUP #11 closed.

## Open

- Whether `widgetProfiles` (per-widget-instance settings such as labels) becomes part of
  profiles as one structured value, or is split into keys.
- Text settings (date format, commands) need a text editor in `SchemaSettingEditor`.
