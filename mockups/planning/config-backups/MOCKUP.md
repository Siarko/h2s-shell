# Config backups (planning)

## Purpose

Shows the plan for the config backups in Settings (a list with Apply, Make a backup now,
Delete) and for the notice of a failed settings update, before any code. One stand-in
Settings window (1000 x 620) per scene with a note under it. Stand-in data: this shell is
2.2.0; now is the kit's 15 Jan 2026, 10:30.

Open on a screen: `tests/mockup.sh open planning/config-backups` (`--scene <name>` for one
scene). Headless: `tests/run-mockups.sh --shoot planning/config-backups`.

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
4. `apply-confirm`: Apply's question (warning modal): reason and version, then the steps —
   current settings backed up, this one loaded and brought up to date, the shell restarts.
5. `apply-confirm-failing`: the same when the preview finds an update that fails under this
   version: the named part is loaded as it was and stays unused until the next shell update.
6. `newer-version`: the 2.3.0 backup selected: the full warning in the row; Apply available.
7. `newer-confirm`: its question, led by the warning in bold; no updates run.
8. `delete-confirm`: Delete's question (danger modal), naming date, reason, version.
9. `failure-notification`: the critical notification after a failed update at start.
10. `failure-dashboard`: the same notice as a Dashboard entry with the same three choices.
11. `failure-restore-confirm`: Restore previous settings… asks first.

## Proposed wording

- Page: "Backups" (System tab). Intro: "Copies of your settings file, all profiles included.
  Apply loads one, brings it up to this version and restarts the shell. Modules' stores and
  data have their own backups, on the Modules page."
- Section "Settings backups", button "Make a backup now"; after it: "✓ Backup made: <date>".
- Reasons: "Before a settings update", "Before updating <module> <from> → <to>", "Before a
  restore", "Made by you" (+ chip "Kept"), "Older backup, reason not recorded"; missing
  version: "version unknown".
- Under the list: "Automatic backups (before a settings update, a module update or a
  restore): the newest 10 are kept. Manual backups stay until you delete them."
- Opened row: "<file name>" (manual: "· kept until you delete it"); "Apply: 1 settings
  update brings it up to 2.2.0." / "Apply: No settings updates are needed: it is loaded as it
  is." / "… One fails under this version (music widget presets)."; buttons "Apply…",
  "Delete…".
- Newer: "⚠ Written by h2s-shell 2.3.0, newer than this version: what this version does not
  know is kept, unused; nothing is converted back." (doc-004 §5.1).
- Apply question: title "Apply the backup of <date>?"; body "<reason> · written by h2s-shell
  <v>." / "1. Your current settings are saved first, as a new backup (Before a restore):
  nothing is lost." / "2. This backup is loaded. <updates>" / (failing, bold) "One of them
  fails under this version: <part>. That part is loaded as it was and stays unused (it
  behaves as defaults) until the next update of the shell, which tries again." / "3. The
  shell restarts to finish."; buttons "Apply and restart", "Cancel".
- Delete question: "Delete the backup of 5 Jan 2026, 21:30 (manual, 2.1.0)?" / "Only this
  backup is removed. This cannot be undone."; buttons "Delete", "Cancel" (the owner's draft
  in HS-179.12).
- Failure notice (notification and Dashboard): "Some settings were reset to defaults" /
  "Updating your settings for 2.2.0 failed for: music widget presets (Popup mode is now a
  widget action). That part now uses its defaults; the rest of your settings were updated.
  Your previous settings are kept in the backup of 15 Jan 2026, 10:29."; actions "Keep
  defaults", "Restore previous settings", "Details".
- Restore question: "Restore your settings from before the update?" / "Your current settings
  are saved first, as a new backup (Before a restore): nothing set since is lost." / "Your
  settings from before the update come back. The part that failed (music widget presets)
  stays unused until the next update of the shell, which tries again." / "The shell restarts
  to finish."; buttons "Restore and restart", "Cancel".

## Open questions

1. Place: a page of its own under System (shown), or a section on the Profiles page, or
   under General? System fits "this computer's, never per profile".
2. Apply vs Restore: the owner's word is "Apply"; the Modules page's module backups say
   "Restore". One word for both?
3. Selecting a row to show Apply/Delete (shown) vs both buttons on every row at all times
   (busier, one click less).
4. The notice names the backup by its date (shown) instead of the file name doc-004 §2.5
   drafts; the file name stays in Details and in the opened row.
5. Restore previous settings from the notification: does its question open the Settings
   window at the Dashboard (as in scene 11), or a standalone modal?
6. The Dashboard does not exist yet (HS-176): until it does, does the entry go to the top
   of the Backups page instead?
7. Not shown: the `*`-scope failure (read-only session, "Start with default settings") and
   its preview warning "the shell would start read-only with this backup". Wanted as scenes?
