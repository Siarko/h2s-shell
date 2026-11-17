# Tracker

The one list of what is next, for the shell and its modules (the module repository
`h2s-shell-tailscale` keeps no tracker of its own). Done items go to [done.md](done.md).
Plans are in [plans/](plans/). Machines are named only "the NixOS machine" and "the Arch
machine".

## Now

State on 2026-11-17: everything is merged to `master` (core) and `main` (module
`h2s-shell-tailscale`, version 0.6.0, module API 1.3) and runs on the NixOS machine.
Development moves to the Arch machine; runs that need `nix` go over SSH to the NixOS
machine. How sessions work is in [workflow.md](workflow.md).

State on 2026-11-17, end of the session on the Arch machine. One topic at a time from here
(the owner): finish the test split first, then the API plan's implementation.

- [ ] **Test split** ([plans/test-split.md](plans/test-split.md)). Merged: runners run named
      suites; the unit and module suites run without `nix`. Waiting, unmerged:
  - core branch `test-split-lock` (working tree `h2s-shell-wt-lock`): `51eef3c` fixes the
    lock scenario `modules` that fails on `master` (fixtures counted, not "14") — small,
    merge after a look; `21626a1` the lock bed with the system's tools — **not reviewed**,
    never run on Arch (needs the packages `python-pywayland` and `wlr-randr` there, and
    `/usr/bin` first on `PATH`); first Arch runs with a scrubbed environment, `harness` first.
  - module branch `test-split` (working tree `h2s-shell-tailscale-wt`): `d005946` (own
    harness removed, reviewed: merge), `655b385` (deterministic `connect-before-read`) and
    the follow-up commits an agent was finishing (review fixes, the stand-in's `pause` race
    behind the `slow-up-disconnect` flake, fixed waits → conditions, the machine-wide
    `pgrep "sleep 5"` in `tools/test.sh`) — check the branch's log, review, merge.
  - then: speed (below), system detection behind a seam, `tests/run-system.sh`,
    `install.sh` under stand-ins, `tests/run-all.sh`.
- [ ] **Test speed** (measured 2026-11-17): the waiting is the machine-wide flock, not the
      tests. To do as one small slice: only `tests/lock/run.sh` takes the lock, itself;
      cache the resolved nix tool path in `tests/lock/resolve.sh` (keyed by `tools.nix`'s
      hash); wait for the compositor's exit instead of the fixed 0.3 s in
      `tests/headless.sh`; correct "about 15 minutes" (it is 4–5) here and in `CLAUDE.md`.
      Until then: on Arch no flock for unit, module and self-test runs; iterate on Arch with
      named suites; the NixOS machine only for the final pass and the lock bed.
- [ ] **API plan** ([plans/api-next.md](plans/api-next.md)) is final on branch
      `plan-api-next` (`036d35e`, working tree `h2s-shell-wt-plans`; it also carries the
      owner's decisions of the day in this file's Decisions — merge it). Open: one more
      decision to fold in (below), a short review of what changed since the independent
      review (buttons, icons, the password queue, the slice list), then the owner's
      approval. First slices: the `ModuleRules.qml` split, the file chooser trial, the
      bordered buttons.
- Decided after the plan's last commit (the owner, 2026-11-17), to fold into it: modules are
  **not** kept from building their own elements. They use the public elements wherever
  that is possible and makes sense, and the theme's colours always; building something the
  API does not offer is fine. So importing the shell's internal elements stays the thing
  to avoid, but "only public elements" is not a rule and not an error.

How to run a session cheaply (the owner asked; this session used most of its budget): one
topic at a time; collect the owner's answers and hand them to an agent in one go; a fresh
agent with a narrow brief instead of resuming one with a long history; no agent waits on a
test queue; review what carries risk, look at one-line fixes yourself.

## Order of work

0. Workflow — open
   - [x] (a) the test runners can run one suite or one scenario
   - [ ] (b) each agent gets its own working trees and its own test bed, so runs go in
         parallel; a module is always tested against a pinned core tree nobody is editing
   - [x] (c) recurring defects written down as development rules in `CLAUDE.md` (both
         repositories); the list grows with every review
   - [ ] (d) fix the known flaky live tests first: the Tailscale stand-in's event-stream
         replay timing (`tools/stand-in/curl`); the tailnet-lock read that is not retried
         (`module/LockClient.qml`)
   - [ ] (e) a small read-only check against the real Tailscale daemon at deploy: state,
         device list, no repeated log lines
   - [x] (f) development runs on the Arch machine; `nix` runs go to the NixOS machine
1. Planning, no code — open
   - [ ] revise [plans/api-next.md](plans/api-next.md): UI anchors and their naming
         convention, a module's public API, the password prompt's "who and what for",
         a minor may tighten
   - [ ] analysis + plan: PAM configuration from the shell (polkit and lock screen, NixOS
         and Arch)
   - [x] plan: the test split (general + per system): [plans/test-split.md](plans/test-split.md)
   - [ ] plan: installing, updating and removing modules, with the Settings → Modules page
   - [ ] revise [plans/documentation.md](plans/documentation.md) and
         [plans/architecture-cleanup.md](plans/architecture-cleanup.md) for the decisions
         below (environment-neutral, both systems together, `notes/`, verification at
         major releases)
2. Release — open
   - [ ] `lockscreen.lockOnSleep` default off (`singletons/SettingsSchema.qml`, today `true`)
   - [ ] versioning rule corrected (`CHANGELOG.md` header, `singletons/Version.qml` comment;
         `CLAUDE.md` done)
   - [ ] cut a minor release (today 2.0.0)
3. API extension in the core, in small slices, per [plans/api-next.md](plans/api-next.md) — open
   - [ ] command runner
   - [ ] program lookup with trust
   - [ ] test mode
   - [ ] privileged start
   - [ ] shared module object
   - [ ] helpers
   - [ ] system and network facts
4. UI anchors; today's slots (`components/ModuleSlot.qml`, `Api.slots`) moved onto them — open
5. A module's public API for other modules, basic version — open
6. Tailscale module migration — open
   - [ ] every workaround removed
   - [ ] exit node per network in the connection's options (through an anchor)
   - [ ] the manual "for now" override
7. Architecture clean-up per [plans/architecture-cleanup.md](plans/architecture-cleanup.md)
   (splits, hubs, test hooks, the module's read/clock performance, the network editor's save
   that can lose the kill-switch choice). Runs alongside 3–6 where slices do not collide — open
8. Modules closed for now (see Decisions) — open
   - [ ] the trust model written down honestly
   - [ ] Settings → Modules: enable, disable, reload, install, update, remove from a repository
   - [ ] the safe-mode banner
9. Lock — open
   - [ ] lock supervisor limit (3 restarts while locked, then stay locked, tell the user)
   - [ ] lock-before-sleep conflict detection
   - [ ] screensaver and lock screen working together checked
10. Test split implemented — moved to the front by the owner, in progress
    - [x] the unit and module suites run without `nix` (tools from the system)
    - [ ] the lock bed with the system's tools; the whole lock bed on Arch
    - [ ] system detection behind a seam (`methods-script` runs both branches everywhere)
    - [ ] `tests/run-system.sh` and the first checks per system; `install.sh` under stand-ins
    - [ ] `tests/run-all.sh`
11. PAM configuration from the shell — open
12. Documentation for users and developers per [plans/documentation.md](plans/documentation.md);
    the architecture and API chapters after 3–7 — open

Later:
- pttd (dictation) as its own module in its own repository (was TODO 11.24); until then
  the protocol is in [pttd-protocol.md](pttd-protocol.md)
- global default programs (the terminal among them)
- NixOS option for modules (`programs.h2s-shell.modules`); module signatures
- UI texts pass and translations, in one go; the owner reviews the voice (short plain wording)
- documentation as a site with per-system tabs

## Decisions

All by the owner, 2026-11-17.

- The module API is ours: a module never works around a gap; the API is extended first.
- Larger work goes analysis → plan (owner approves) → implementation.
- Versioning: a settings migration may ship in a minor release, never in a patch. The pending release is a minor.
- `lockscreen.lockOnSleep` defaults to off. To investigate: detecting, independent of the system, that something else locks the screen, and telling the user.
- Lock supervisor: at most 3 restarts while locked; then the session stays locked, the user logs in on a TTY and starts the launcher by hand; the user is told what happened and how to look into it; documented.
- Tests: one general set independent of the system, plus a set per system (NixOS, Arch). A developer runs the general set and their system's.
- PAM: the order of password and fingerprint is the system's PAM stack, not the prompt's. Wanted: configuring PAM rules from the shell; needs its own analysis and plan.
- Documentation: English only; Markdown with "NixOS" and "Arch" subsections wherever the systems differ (a site with tabs maybe later); pages for system-only features where it makes sense; never one system without the other; nothing refers to or relies on the developers' own environments (user names, home paths, machines); screenshots are the owner's; docs verified for consistency at each major release, not on every change; `docs/` never links into `notes/`.
- Module API: a minor version may tighten behaviour for now (nobody else uses the shell yet); the rule is tightened when needed.
- Module API, UI anchors: views are built from shared blocks (settings page, section, card, row, popup section) that register under a path derived from where they stand; a module names a path, a placement (before, after, appended inside) and its element. Addressable: settings pages and popup content; not the bar (the user places widgets there). One naming convention for anchors; the list of anchors pinned by a test and documented. Today's slots move onto anchors.
- Module API: a module may publish its own versioned API object for other modules (declared in the manifest; a dependent module gets only that object). Basic version in this round. Reaching into another module or the host goes away.
- Privileged runs by a module: no time window; the password prompt says which module asks and what for, next to the actual command.
- Exit node (Tailscale): a manual choice "for now" that overrides the per-network setting, and a per-network choice in that connection's options (through an anchor).
- No terminal setting of its own: a global "default programs" setting later.
- Modules closed for now = the trust model written down honestly (a module runs in the shell's process, which also handles the lock screen's password and the polkit agent), Settings → Modules (enable, disable, reload, install, update, remove from a repository), the safe-mode banner. Later: NixOS option for modules, signatures.
- Coding is done by strong models only; no weaker models for mechanical moves.

## Backlog / later

From the old TODO (numbers kept, see done.md for the rest):
- [ ] 11.34 A command button bar widget: label and/or icon, a command per click (left, right, middle, maybe long press), run detached
- [ ] 11.31 Popups clear of the on-screen keyboard: done for a bar at the top; left: a bar at the bottom, popups by a bar at a side, the settings window (`panels/Popup.qml`)
- [ ] 11.32 "Settings saved" toast seen with nothing changed (the NixOS machine, 2026-11-08) — reproduce first
- [ ] 11.23 Installing: `install.sh` untested on Arch; on a first run `Config` chmods `config.json` before it exists (one warning); publishing (AUR, docs for others) later
- [ ] 11.20 Animation editor; animations as data assigned to named element slots
- [ ] 11.5 Bar shape and anchoring ("dynamic island") — needs working out with the owner first
- [ ] 11.7 Themes stage 8, matugen: a template mapping its palette to the colour tokens, a "wallpaper" theme reading it (`colorsFrom` exists), docs
- [ ] 11.8 Compositor integration, Hyprland first (scroll sensitivity, volume step, …) — first a plan, `notes/plans/compositor.md`, agreed with the owner
- [ ] A QR code to join a network (`qrencode`) (left from 11.37)
- [ ] A bar widget to shuffle the wallpaper, or a command button (11.34)
- 11.6 Styling with CSS-like selectors — shelved; [plans/selectors.md](plans/selectors.md), [plans/styles.md](plans/styles.md)

From next-steps (2026-11-15):
- [ ] The muted status line has low contrast on the green tint of an active row in the network popup (not re-checked)
- [ ] The lock test `fallback` failed once (the PAM stand-in never answered): find out why
- [ ] Module widgets pop in after the first frame (`singletons/ModuleLists.qml`: by design today)
- [ ] A start guard for slow crash loops (not re-checked)
- [ ] Quickshell 0.3.2: a second polkit request while a prompt is open replaces it, never finished (upstream)
- [ ] `SmallButton` / `DeleteButton` have no keyboard focus or activation
- [ ] Opened connection cards have about 20 px of empty space under the detail line (not re-checked)
- [ ] Tailscale later: re-authentication without the profile reset (`login-interactive`), settings re-applied after a same-account login, certificate renewal, a terminal launcher for SSH (with the default programs)
- [ ] Taildrop's file and folder dialogs never clicked on a real machine
- [ ] Tailscale module: warn when an accepted subnet route covers the local network the
      computer is on (replies to LAN peers then leave through the tunnel and LAN connections
      to this computer fail); seen with "Use routes from other devices" on
- [ ] M5 author guide for modules (with step 12)

Found while writing the development rules (2026-11-17):
- [ ] `singletons/network/VpnLockdown.qml` without the installed script: a network coming up asks for the password by itself, and runs the shell tree's own `scripts/h2s-vpn-lockdown` as root (user-writable in a checkout) — against two development rules

Found during the test split (2026-11-17):
- [ ] Module runs in the headless compositor start the `nmcli` on `PATH` against a dead
      D-Bus address (`[NetworkEvents] nmcli monitor exited, restarting`) and try `notify-send`:
      against "tests never touch a real daemon"; a stand-in or a switch-off is needed
- [ ] `polkit/AuthPrompt.qml` sets no `textFormat` on polkit's texts (plain-text rule)
- [ ] `tests/ModulesTest.qml` (start guard, lines 268-301) asserts within a 300 ms timer:
      fails under load on a slow machine (3 checks, seen on the NixOS machine)
- [ ] Lock scenario `modules-launcher`: with the shell's programs missing from `PATH`
      (through `tests/lock/launcher.sh`) modules can stay `pending` after a supervisor
      restart — looks like a shell defect; `modules-discovery` once saw the supervisor
      silent for 44 s under load
- [ ] `tests/lock/tools.nix`: the comment ties the pin to one machine's system

## Open points

- None of the owner's decisions are pending. The plans in `plans/` (`api-next.md`,
  `architecture-cleanup.md`, `documentation.md`) are drafts written before the decisions
  of 2026-11-17; step 1 revises them, and the owner approves them before implementation.
