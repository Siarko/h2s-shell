# Config backups (planning)

## Purpose

Shows the plan for the config backups in Settings (a list with Apply, Make a backup now,
Delete) and for the notice of a failed settings update, before any code. One stand-in
Settings window (1000 x 620) per scene with a note under it. Stand-in data: this shell is
2.2.0; now is the kit's 15 Jan 2026, 10:30.

Open on a screen: `tests/mockup.sh open plans/config-backups` (`--scene <name>` for one
scene). The last scene, `config-backups-live`, is interactive. Headless: `tests/run-mockups.sh --shoot plans/config-backups`.

Real pieces: the theme, `SettingsPage`, `SettingsSection`, `SmallButton`, `SettingsModal`,
`NotificationCard` (critical urgency). Drawn here as proposals: the backup rows, the "Kept"
chip, the Dashboard entry. Stand-ins: the window's tab bar and sidebar, the desktop, the
Dashboard's other lines (the Dashboard itself is HS-176, a sketch).

## Scenes

1. `list`: System → Backups. Newest first; each row: date, reason, the version that wrote it.
   Manual rows carry "Kept". Two older backups without a recorded reason, one without a
   version ("version unknown"). The 2.3.0 row shows its version in the warning colour with ⚠.
   "Make a backup now" on the section's title line; the keeping rule under the list.
2. `backup-made`: after Make a backup now: "✓ Backup made: 15 Jan 2026, 10:30" under the
   title, the new manual row at the top, selected.
3. `selected`: a row clicked opens: its file name, what Apply would do (from the in-memory
   preview: how many settings updates run), Apply… and Delete….
4. `apply-confirm`: Apply's question (warning modal): reason and version, then "Steps:" —
   create a new backup, load the selected backup, the settings update (only for a backup
   older than this version), restart the shell; numbered 1–3 or 1–4.
5. `apply-confirm-failing`: the same when the preview finds an update that fails under this
   version: the update step says which part it skips.
6. `newer-version`: the 2.3.0 backup selected: the one-line warning in the row; Apply available.
7. `newer-confirm`: "Load a backup from a newer shell?", the warning in bold, the steps (no
   settings update).
8. `delete-confirm`: Delete's question (danger modal), naming date, reason, version.
9. `failure-notification`: the critical notification after a failed update at start, short;
   clicking it opens Settings at the Dashboard entry.
10. `failure-dashboard`: the Dashboard entry: the failed parts as a bullet list, everything
    shown at once (not expandable, no Details); Keep defaults, Restore previous settings….
11. `failure-restore-confirm`: Restore previous settings… asks first, with the steps.
12. `config-backups-live`: the same window working, on its own copy of the stand-in data,
    with the theme's animations (every other scene and every shot is drawn without motion).
    Make a backup now adds a manual row at the top (the stand-in clock gives each the next
    minute after 10:30) with its "✓ Backup made" line; a click selects a row (again: closes
    it); Apply… and Delete… ask in the Settings modal, and their answers act: Apply adds a
    "Before a restore" backup (automatic ones pruned to the newest 10) and the note says the
    stand-in shell restarted; Delete removes the row. Keys: ↑ ↓ select, Enter asks to apply,
    Delete asks to delete, Escape closes the row; in a question Tab moves between the
    buttons, Space or Enter presses, Escape cancels. The sidebar's Dashboard and Backups
    switch pages. Under the window: "Failed update" raises the critical notification over
    the window's top right and the Dashboard entry (⚠ on the sidebar); clicking the
    notification opens the Dashboard; its Keep defaults clears both, Restore previous
    settings asks on the Dashboard and restores; "Reset" puts the stand-in data back.

Open the live scene: `tests/mockup.sh open plans/config-backups/config-backups-live`.

## Proposed wording

Short, to the point; the docs explain (the owner, 2026-11-25).

- Page: "Backups" (System tab). Intro: "Copies of your settings file, all profiles
  included. Modules' stores and data: on the Modules page."
- Section "Settings backups", button "Make a backup now"; after it: "✓ Backup made: <date>".
- Reasons: "Before a settings update", "Before updating <module> <from> → <to>", "Before a
  restore", "Made by you" (+ chip "Kept"), "Older backup, reason not recorded"; missing
  version: "version unknown".
- Under the list: "Automatic backups: the newest 10 are kept."
- Opened row: "<file name>"; "Apply: 1 settings update brings it up to 2.2.0." / "Apply: No
  settings updates are needed." / "… Fails for: music widget presets."; buttons "Apply…",
  "Delete…".
- Newer: "⚠ Written by shell 2.3.0 (newer than current) — may be incompatible, expect odd
  behaviour".
- Apply question: title "Apply the backup of <date>?" (newer: "Load a backup from a newer
  shell?", then the newer line in bold); body "<reason> · <version>", then "Steps:" / "1.
  Create a new backup" / "2. Load the selected backup" / ["3. Settings update to 2.2.0"
  (failing: ", skipping <part>"), only for an older backup] / "3./4. Restart the shell";
  buttons "Apply and restart", "Cancel".
- Delete question: "Delete the backup of 5 Jan 2026, 21:30 (manual, 2.1.0)?" / "Only this
  backup is removed. This cannot be undone."; buttons "Delete", "Cancel" (the owner's draft
  in HS-179.12).
- Failure notification (critical): "Updating settings to 2.2.0 failed" / "Defaults are used
  where possible. See Settings for details."; clicking it opens Settings at the Dashboard
  entry; buttons "Keep defaults", "Restore previous settings".
- Dashboard entry: "Updating settings to 2.2.0 failed" / "Defaults are used for:" and the
  failed parts as a bullet list; buttons "Keep defaults", "Restore previous settings…".
- Restore question: "Restore the settings from before the update?" / "Steps:" / "1. Create a
  new backup" / "2. Load the backup of <date>" / "3. Settings update to 2.2.0, skipping
  <parts>" / "4. Restart the shell"; buttons "Restore and restart", "Cancel".

## Open questions

1. Place: a page of its own under System (shown), or a section on the Profiles page, or
   under General? System fits "this computer's, never per profile".
2. Apply vs Restore: the owner's word is "Apply"; the Modules page's module backups say
   "Restore". One word for both?
3. Selecting a row to show Apply/Delete (shown) vs both buttons on every row at all times
   (busier, one click less).
4. The restore question names the backup by its date (shown); the file name is in the
   opened row on the Backups page.
5. Restore previous settings from the notification: does its question open the Settings
   window at the Dashboard (as in scene 11), or a standalone modal?
6. The Dashboard does not exist yet (HS-176): until it does, does the entry go to the top
   of the Backups page instead?
7. Not shown: the `*`-scope failure (read-only session, "Start with default settings") and
   its preview warning "the shell would start read-only with this backup". Wanted as scenes?
