# Mockup: the NixOS page and the rebuild panel (implemented)

The implemented Settings → System → NixOS on stand-in readings, for comparing with the
approved plan (`mockups/plans/distribution-nixos/`). The real page
(`NixosSettings`), the real run (`NixosRebuild` and `NixosRebuildRules`), the window's wiring
(`NixosRebuildFlow`, `SideDrawer` with `NixosRebuildPanel`, `SettingsModalHost`). Under the
run, nix and pkexec are stood in for at the build's and the root step's place: stand-in nix
lines go through `NixBuildRules.step` and `NixBuildRules.outcome`, the root step's stand-in
last line through `NixosApplyRules.reply`. `NixosBuild` and `NixosApply` themselves are not
run: their program seams exist only in module test mode, and a mockup keeps no time and
starts no process (their real paths run in the NixOS build, root step and rebuild fixtures).

- Headless: `tests/run-mockups.sh --shoot views/nixos-page` (`--compare` against `baseline/`).
- On a screen: `tests/mockup.sh open views/nixos-page`.

Each cell is the settings window's page area (890 x 960), without the window's tabs and page
list. The cells are too large to lie side by side on the shooter's 1920 x 1200 output: they
lie on one another, only the state's cell is shown, and the pointer rests on a strip below
them from the first state on (no state simulates a pointer).

## States

not-connected · found-not-in-force · home-folder · ready · apply-announcement · building ·
built-apply-now · waiting-password · switching · applied · build-failed ·
applied-with-errors · cancelled · set-in-configuration · undo-announcement · undo-building

## Compared with the plan

- **Built. [Apply now]** replaces "Password after the build": the build ends at "Built in
  1 min 12 s." with Apply now and the privileged mark; the prompt comes only from that click
  (open question 2, decided). After the click: "Waiting for the password", a state the
  plan did not have; the panel's time counts from the click, not from the build.
- **No "Locked during the build"**: the run no longer stops on a lock; a build goes on, and
  only the Apply now click starts the root run.
- **The delay's place**: the plan's page showed the times as pills and "In force: 1 h" with
  Apply/Undo and a hint; the implemented page shows one line ("Picked 3 h; the system now
  hibernates after 1 h. Apply rebuilds NixOS.") with Apply. The times are picked in
  Behaviour → When away. Not connected, the page shows no delay section and no line to copy:
  When away keeps the copy line.
- **Set in your configuration**: one line, "Set in your configuration: 10 min. Your own line
  wins. To change it here, remove it from your configuration.", without the dot and the
  separate caption.
- **Applied, with errors**: "Applied, with errors: some services did not start again." / "The
  new values are in force." — the failed unit is not named in the box (it is in the output's
  lines), and no journalctl hint.
- **Cancelled**: the panel's Output is empty (the plan showed nix's lines up to
  the cancel and "build stopped").
- **The build's lines**: nix's own lines as the rules keep them (the derivations, "building
  '…'"), not the plan's "copying … to a scratch folder" and "evaluating …" lines;
  Output's caption is "nix's last lines" for a failed build only.
- **Undo**: on the page it sits on the delay's line ("Undo puts back the shell's previous
  value and rebuilds NixOS.") once an Apply ran, not beside Apply.
- **Generation**: "Applied in 9 s. Generation 15 is in use." — the time is the root run's
  from the Apply now click.
