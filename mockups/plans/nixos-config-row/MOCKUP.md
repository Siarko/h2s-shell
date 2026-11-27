# Plan mockup: the NixOS configuration's folder

## Purpose

Where Settings → System → NixOS shows the configuration's folder and its button. Before:
"Choose folder…" and "Look again" in the status line while nothing was found, "Select
directory" beside the title once found, "Choose another…" in the home-folder warning, and the
folder only as the "Configuration" fact. Decided (the owner, 2026-11-27) and now in the real
page: in the status box, directly under the status, always

    Configuration   /srv/nixos-config                  [Select directory]
    Configuration   /etc/nixos                         [Select directory]   (nothing found: where the shell looked)

— the configuration's folder, or while none is found the folders looked in (a chosen folder
that holds none: that folder) — with "Select directory", the page's one folder button. "Look
again" stays in the status line. No "Configuration" fact: the row carries its label. While
the page looks, the folder stays shown and both buttons wait.

- Headless: `tests/run-mockups.sh --shoot plans/nixos-config-row`.
- On a screen: `tools/mockup.sh open plans/nixos-config-row`.

## Scenes

1. not-connected: nothing found: /etc/nixos (where the shell looked), Select directory, Look again.
2. found: a classic configuration at /etc/nixos, not connected yet.
3. connected: a flake at /srv/nixos-config (no Look again).
4. nixos-config-row-live: the real page on stand-ins. Select directory opens a stand-in
   picker (/etc/nixos: found; /srv/nixos-config: connected; /home/alex/Documents: nothing
   there, so that folder is shown), Look again reads the same folder again ("Looking for the
   configuration…" for a moment), and three buttons beside the page switch the reading.

## Wording

- Buttons: "Select directory", "Look again". "Choose folder…" and "Choose another…" are gone.
