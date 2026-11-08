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

**Status (2026-11-08):** stages 1–10 done; stage 11 under way, touch input first (next: 11.29).

---

## Stage 11 — Next, in order

Touch input on the Framework 12 — the current work ([plans/touch.md](plans/touch.md)):

- [ ] **11.29 A keyboard button on the bar** (plans/touch.md stage 6) — calls `osk` (or
      a configured command): Hyprland's gestures cannot run commands, so a button is the
      only way to call the keyboard by finger. Shown by the "Tablet" profile.
- [ ] **11.30 The lock screen in tablet mode** (plans/touch.md stage 6) — no keyboard to
      type the password. Check whether oskbd shows over a session lock; if not, a
      keyboard of the lock screen's own, or the fingerprint reader.
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
- [ ] **11.6 Explore styling with CSS-like selectors** (was 10.14) (requested 2026-10-30)
      First meant for after the whole themes plan; the user put it before matugen (11.7),
      which it does not depend on.
      Themes today set values per element kind (`button.radius`, `osdToast.padding`, …,
      themes stage 7). Explore going further: styling by something like CSS selectors —
      targeting an element by kind, place and state (e.g. `popup button:hover`,
      `bar .clock`, `osdToast.critical`), with cascading and specificity — and what it
      would take in QML (element identity, a resolver, live updates, cost). Exploration
      only; to discuss with the user before any design. Related: the user's earlier idea
      of per-element variants (`expand.dictate` falling back to `expand`, themes plan).
      Analysed and decided with the user 2026-11-01: plan
      [plans/selectors.md](plans/selectors.md) (our CSS variant in `.css` files, resolved
      statically into a table addressed by an element's key, descendant selectors over
      contexts only, layered cascade, inheritance; an audit of every element, a read-only
      inspector window, parser with a validator, themes rewritten in CSS and edited both
      ways). The language reference grows in [STYLES.md](STYLES.md). Stage 0, the
      prototype, done 2026-11-01 (the model holds, cost far below a frame); paused 2026-11-06
      while the user thinks over the open questions (plans/selectors-questions.md); then
      stage 1, the audit.
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
