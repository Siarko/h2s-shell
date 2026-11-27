# Plan mockup: the NixOS configuration's row

## Purpose

Where Settings → System → NixOS shows the configuration's folder and its buttons. Today:
"Choose folder…" and "Look again" in the status line while nothing is found, "Select
directory" beside the title once a configuration is found, and the folder only as the
"Configuration" fact in the table below. Proposed: one row at the top,

    Configuration: /etc/nixos                 [Select directory] [Look again]
    Configuration: Not found                  [Select directory] [Look again]
    Configuration: /srv/nixos-config          [Select directory]

and no "Configuration" fact in the table. Nothing else on the page changes.

- Headless: `tests/run-mockups.sh --shoot plans/nixos-config-row`.
- On a screen: `tools/mockup.sh open plans/nixos-config-row`.

## Scenes

1. not-connected: today (status line buttons) beside the proposal.
2. found: a classic configuration at /etc/nixos, not connected yet: today beside the proposal.
3. connected: a flake at /srv/nixos-config: today beside the proposal (no Look again).
4. nixos-config-row-live: the proposal working on stand-ins. Select directory opens a
   stand-in picker (/etc/nixos: found; /srv/nixos-config: connected; /home/alex/Documents:
   nothing), Look again reads the same folder again ("Looking for the configuration…" for a
   moment), and three buttons beside the page switch between the readings.

The pages are the real one (`NixosSettings`) and a copy of it with the row (`ProposedPage`,
an inline component of `Mockup.qml`, its rebuild line left out), on the stand-in readings
of `views/nixos-page`.

## Wording

- Row label: "Configuration:"; value: the folder, or "Not found".
- Buttons: "Select directory", "Look again" (both kept from today; "Choose folder…" goes).

## Open questions

1. One row at the top as proposed, or keep today's places?
2. Look again stays while connected hidden (as today), or always shown?
3. The label "Configuration:" (the section's title is "NixOS configuration"), or "Folder:"?
