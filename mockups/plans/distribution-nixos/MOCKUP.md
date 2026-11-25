# Mockup: NixOS configuration page and the rebuild side panel (planned)

A plan on the shell's tree (`Mockup.qml` on the mockup kit's `MockupWindow`): the
shell's real theme, SideDrawer, SettingsModal, SmallButton, Pill, ProgressBar, PrivilegedMark
on stand-in data. Nothing reads the system, nothing runs nix or pkexec.

- Headless check: `tests/run-mockups.sh --load-only plans/distribution-nixos`, or
  `--shoot` for one image per scene.
- On a screen: `tests/mockup.sh open plans/distribution-nixos` — the kit's scene
  buttons under the window; Apply, Build, Cancel build, the password card, Undo and Copy
  work on the stand-ins (a stand-in build runs on a timer).

Stand-in configurations (a configuration can live anywhere; none is the central one): a flake
at /srv/nixos-config in git (most scenes), a classic configuration.nix at /etc/nixos not in git
(scenes 1 and 9), a flake at ~/nixos-config in git (scene 2).

## Revisions

- 2026-11-24, the owner's requests: the section intro says what the feature is; the facts
  panel shows one fact per line (Configuration, Type, Git, Host, The shell's file, File status,
  Generations); /etc/nixos no longer singled out in texts and the stand-ins vary (flakes outside
  /etc/nixos); the Undo modal is one sentence. The password-after-build scene is unchanged
  (open question 2).

## Scenes (0 … 15; the scene names are these in kebab case)

0 Not connected · 1 Found, line not in force · 2 In the home folder (warning) · 3 Ready ·
4 Apply: the announcement · 5 Building · 6 Password after the build · 7 Switching ·
8 Applied, Undo offered · 9 Build failed · 10 Applied, with errors · 11 Locked during the build ·
12 Cancelled · 13 Set in your configuration · 14 Undo: the announcement · 15 Undo: building

## Proposed wording (for the owner to decide)

- Section "NixOS configuration": "The shell can keep its settings in your NixOS configuration
  and apply them by rebuilding NixOS. Turn that on here." States "Connected" / "Found, not
  connected yet: the shell's file is not in force." / "Not connected" ("No NixOS configuration
  found that imports the shell's NixOS module. Built on another machine? Then keep copying the
  lines."). Facts, one per line: Configuration (the path) · Type ("Flake" / "Classic
  (configuration.nix)") · Git ("Yes" / "No") · Host · The shell's file (the path) · File status
  ("In force" / "Created, not in force yet" / "Not created") · Generations (the number), under
  them "Each Apply adds a generation. The shell never deletes them."
- One-time setup: "1. Create the shell's file, h2s-shell.json." [Create] · "2. Add this line
  once to your configuration, then run nixos-rebuild switch." + the line + [Copy].
- Home folder: "This configuration is in your home folder." / "Any program you run can change
  it, and NixOS builds it as root at every rebuild. The shell writes its file there without a
  password." [Use it] [Choose another…]
- Modal "Rebuild NixOS": "A new NixOS system is built first, as you. No password yet." / "This
  may take minutes and load the machine. You can cancel while it builds." / "When it is built,
  your password applies it." [Build] [Cancel]
- Side panel "Applying: rebuilding NixOS": steps "Build, as you" / "Your password" / "Switch";
  [Cancel build]; "Closing this panel does not stop the build."; outcomes "Applied in … .
  Generation 15 is in use." / "The build failed. Nothing changed." / "Applied, with errors:
  <unit> did not start again." / "The screen locked during the build. Nothing changed." /
  "Cancelled. Nothing changed."
- Override: "Set in your configuration: 10 min" / "Your own line wins. To change it here,
  remove it from your configuration."
- Undo modal "Undo the last Apply": "The shell's previous settings are put back and NixOS is
  rebuilt." [Undo and build] [Cancel]

## Open questions

1. A configuration in the home folder: allowed with the one-time warning above (scene 2)?
2. The password prompt opens by itself when the build ends (minutes after the Apply click).
   The development rule "nothing asks for a password without the user's click" may want a
   button instead: "Built. [Apply now]" in the side panel, the prompt on that click.
3. The NixOS section's place: a page "NixOS" under System (as shown), or a section on an
   existing page.
