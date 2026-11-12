# TODO

What is left to do, in the order agreed with the user. Done items move to
[TODO-DONE.md](TODO-DONE.md) with their numbers kept — commits and the docs refer to them
("TODO 9.7", "11.22"); look a number up there if it is not here. Numbers in brackets are
finding ids in [CLEANUP.md](CLEANUP.md), which has the analysis and the file:line
references. User-visible changes are in [CHANGELOG.md](../CHANGELOG.md).

**Working agreement:** before starting an item, investigate the relevant code, state the
drawbacks of the proposed approach, and ask about anything genuinely unclear rather than
guessing. One item at a time. Commit only when asked. An item is done once verified where
it can be — the host, or the Framework 12 for touch (the dev container has no
`quickshell`) — and then moves to TODO-DONE.md.

**Status (2026-11-12):** stages 1–10 done; stage 11 under way, touch input first (next: 11.34). Wallpapers (11.33) done.

---

## Stage 11 — Next, in order

Touch input on the Framework 12 — the current work ([plans/touch.md](plans/touch.md)):

- [ ] **11.34 A command button widget** (requested 2026-11-12) — a bar widget that does
      nothing by itself: each instance (a preset) is given a label and/or icon and a
      command (or one per click: left, right, middle; maybe a long press for touch), run
      detached. Covers what 11.29 wanted (calling the on-screen keyboard: `osk`) without
      the shell knowing about keyboards, and anything else the user wants a button for.
- [ ] **11.31 Popups clear of the on-screen keyboard everywhere** — done for a bar at the
      top; left: a bar at the bottom (the keyboard covers the bar), popups by a bar at a
      side, the settings window (an ordinary window, which oskbd's overlay covers).

A finding to look into:

- [ ] **11.32 "Settings saved" seen on the Framework with nothing changed** (found
      2026-11-08, 21:28, while device tests opened the calendar and files were synced)
      — the toast shows when the shell writes its config. Unknown whether the user
      changed something then; if not, something writes the config by itself (a hot reload
      after a sync?). To reproduce before anything else.

Then, in the user's order:

- [ ] **11.36 A System tab in the settings** (agreed 2026-11-12; the tab exists since 11.35, with Authentication) — beside Behaviour and
      Appearance: "Settings of this computer, kept by the system — they apply at once, in
      every profile." The rule, by who holds the value: what the shell holds and applies
      (the power profile, polling, later Hyprland options it generates) can vary by
      profile and stays in Behaviour; what a system service holds (NetworkManager, BlueZ,
      PipeWire…) is edited in System, with no profile and no profile picker. A profile may
      still pick among system things (Power save turning Wi-Fi off, joining a VPN), as it
      picks a power profile today. 11.8 (Hyprland) is decided by the same rule.
- [ ] **11.37 Network management, the System tab's first page** (requested 2026-11-12) —
      today the network popup connects to Wi-Fi and VPNs and nothing more. Through
      `nmcli`: saved Wi-Fi networks (forget, autoconnect, priority, password), hidden
      networks; VPNs (list, import `.ovpn` and WireGuard `.conf`, edit the basics, delete);
      a connection's IPv4/IPv6 (DHCP or manual: addresses, gateway), DNS; Ethernet; later a
      hotspot. A plan in `docs/plans/` first.

- [ ] **11.23 Installing: Arch and NixOS** (requested 2026-11-08, before touch input —
      the Framework 12 runs NixOS). `install.sh` for Arch (pacman, then a checkout in
      `~/.config/quickshell/default`); `flake.nix` + `nix/package.nix` (an `h2s-shell`
      command with Quickshell v0.3.2 from its own flake and every program the shell calls
      on PATH; `H2S_SHELL_DIR=<checkout>` runs a checkout instead, for development) +
      `nix/module.nix` (`programs.h2s-shell.enable`: font, UPower, power-profiles-daemon,
      BlueZ, NetworkManager). `launch.sh` addresses the instance by its folder (`qs -p`),
      scripts use `#!/usr/bin/env bash` (NixOS has no /bin/bash). A HUD banner when no
      Nerd Font is installed (`Theme.nerdFontInstalled`, `hud/StartupWarning.qml`, which
      the launch warning now uses too). Package built and run on the Framework
      2026-11-08, the module in the user's system flake (`programs.h2s-shell.enable`) and
      Hyprland's autostart there too; `launch.sh --restart` closes every copy of the shell
      (a checkout and the package's ran side by side). Left: `install.sh` untested (needs
      sudo, on Arch). For the user only so far; publishing (AUR, docs for others) later.
      Found on the way, not fixed: on a first run `Config` chmods `config.json` before it
      exists (one warning).
- [ ] **11.24 Dictation as a separate, optional module** (requested 2026-11-08)
      `pttd` is the user's private daemon: the dictation widget, its settings, the HUD
      preview and the music pause should install separately, not ship with the shell.
      Until then the user turns it off. Without the daemon the shell logs a socket error
      every few seconds.
- [ ] **11.20 Animation editor, and animations assigned to elements** (requested 2026-11-01)
      Today each animation is written in its element's code (the bell's ring, 11.18).
      Wanted: animations as data — tracks for x, y, rotation and scale, each with a
      duration and a curve from the Curves library (Appearance → Curves already edits
      easing curves) — an editor with a live preview, a player in QML, and named slots
      in elements ("bell: new notification", say) an animation is assigned to, played
      once or in a loop. Likely kept in the theme. A feature of its own; the bell's ring
      would be its first slot.
- [ ] **11.5 Bar shape and anchoring: e.g. a "dynamic island" bar** (was 10.13) (requested
      2026-10-30)
      The bar's size can only be tuned with margins and padding today. Wanted: choosing
      what the bar is anchored to, so it can be e.g. a floating island — centred, as wide
      as its content, perhaps growing with what it shows (a dynamic island). The idea needs
      working out with the user first: what can be anchored (the whole bar, or each of its
      left / centre / right sections as separate islands), width from content or fixed,
      how the exclusive zone behaves for a floating bar, how popups join an island (their
      curved corners assume a bar running to its ends; see 8.12 for the margin case), and
      animation when the island resizes. Related to 11.4 (position) and themes stage 7.
- [ ] **11.7 Themes: matugen, the rest of the themes plan** (was 10.9)
      Agreed 2026-10-29: [plans/themes.md](plans/themes.md). Look goes in a theme (shared
      library, profiles pick one), behaviour stays in the profile; custom animation curves
      with an editor; an Appearance section in settings; matugen-ready colours. Absorbs
      10.1 and 9.4. Stages 1–7 done and released in 2.0.0; left is stage 8, matugen: a
      template mapping its palette to our colour tokens, a "wallpaper" theme reading the
      generated file, and docs for adding the template to matugen's config.
- [ ] **11.8 Compositor integration, Hyprland first** (was 10.15, scroll sensitivity;
      widened 2026-10-31)
      Decided with the user: the shell is a real shell — its settings change the system,
      not only itself. Started from scroll sensitivity: the shell cannot scale the
      scrolling of its own lists (Qt's `wheelScrollLines` is read-only from QML, checked),
      while Hyprland's `input:scroll_factor` and `input:touchpad:scroll_factor` scale it
      for every app, the shell's notches included. Principles agreed:
      - **An integration layer, not Hyprland everywhere.** One singleton boundary
        (`Compositor`, name to settle) with Hyprland as its first backend, so another
        compositor can be added later. What talks to Hyprland today has to move behind
        it: `singletons/Workspaces.qml` (workspaces, focus, `Hyprland.dispatch` with
        `hl.dsp.*` Lua, the `activespecial` raw event), `widgets/WorkspacesWidget.qml`
        (bound to the live Hyprland ObjectModel — keep that binding's crash-safety, see
        "The Repeater crash"), `singletons/Profiles.qml` (the `window.fullscreen` fact),
        `scripts/logout.sh` (`hyprctl dispatch 'hl.dsp.exit()'`).
      - **The shell owns one generated file and never edits the user's.** The user's
        config is Lua (`~/.config/hypr/hyprland.lua`, Hyprland 0.56); nwg-displays already
        generates `monitors.lua`, loaded with `require("monitors")`. The shell writes its
        own (e.g. `h2s_shell.lua`, "generated, do not edit"), and one `require` line in
        `hyprland.lua` loads it — added by the user, or once by the shell with consent and
        a backup. A change is applied live with `hyprctl eval <lua>` and written to the
        file, so it holds without the shell running and across reloads. The shell's config
        is the source of truth. Monitors stay nwg-displays'.
      - **Conflicts shown plainly.** When the user's config sets an option after the
        `require` and wins, the setting says so (read back with `hyprctl getoption`);
        `hyprctl configerrors` reaches the settings window.
      - **Profiles change the compositor too** (Power save turning off blur and
        animations, say), so the shell and Hyprland feel like one environment. To work
        out: the file holds base values and profiles apply through `eval`; reapplying
        after a config reload (Hyprland's event) and what is left if the shell dies.
      - **Scope grows step by step**, aiming at Hyprland's whole configuration through the
        settings, the most important first. First case: scroll sensitivity, mouse and
        touchpad. Candidates after: keyboard layout and repeat, natural scroll, pointer
        sensitivity, window border colours from the theme (and matugen), Hyprland's
        animations, hyprsunset, hypridle (overlaps our lock screen).
      Shell-side, with the first case: the **volume step** per notch (the bar widget ~1 %
      via `notches()`, the volume sliders 2 % — `VolumeSlider.step`,
      `VerticalSlider.step`, also the arrow keys); keep the user's current steps. The
      horizontal-scroll volume step of 5 is a Hyprland keybind of the user's — leave it.
      Also fold `MonthGrid`'s own 120-step wheel counting into `ScrollNotches`.
      Next: a plan, `docs/plans/compositor.md`, agreed with the user before any work.

---

## Later — ideas kept, not planned

- **11.6 Styling with CSS-like selectors** — shelved 2026-11-12 with the user: likely more
  than a personal shell needs (seven stages, the state logic of ~120 QML files moved into
  a stylesheet, a parser, an inspector, themes migrated) while today's themes already
  cover what is wanted. Instead, a token is added to the themes when a concrete need comes
  up. Worth reopening if such exceptions pile up, or if the shell is published and others
  are to write themes. The analysis, the prototype's results and the open questions stay
  in [plans/selectors.md](plans/selectors.md) and
  [plans/selectors-questions.md](plans/selectors-questions.md).
- **A bar widget to shuffle the wallpaper** (left from 11.33) — until then,
  `ipc call wallpaper shuffle` from a keybind, or a command button (11.34).

