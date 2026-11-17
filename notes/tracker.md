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
(the owner). The test split is done; the next topic is the API plan's implementation
(index [plans/api-next.md](plans/api-next.md)): first the theme token test, the
`ModuleRules.qml` split, the file chooser trial, then the bordered buttons.

- [x] **Test split** ([plans/test-split.md](plans/test-split.md)): done — a general set
      that runs on NixOS and on Arch, a set per system (`tests/run-system.sh`), and one
      command before committing (`tests/run-all.sh`). Notes in [done.md](done.md).
- [x] **Test speed**: done — the lock bed's runner takes the machine-wide lock itself, the
      nix tool lookup is remembered; the whole lock bed takes about three minutes on either
      machine.
- [ ] **API plan**: approved by the owner on 2026-11-17.
      [plans/api-next.md](plans/api-next.md) is the index with the slice list (48 slices);
      one file per area is under `plans/api-next/`. A brief for a slice names the index and
      the slice's area file, nothing more. Implementation is next; first slices: the theme token test, the `ModuleRules.qml` split, the file
      chooser trial, then the bordered buttons. Not yet done: a short independent review
      of what changed after the last one (button kinds, icons, the password queue, a
      module's own elements) — fold it into the review of the first slices of each area.

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
         the versioning rule, a module's own elements, other authors, the direction
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
8. Modules closed for now (see Decisions: a state of today, ended by step 15) — open
   - [ ] the trust model written down honestly: no isolation; review covers the project's
         own modules only; for any other module the password prompt's text is the only
         protection
   - [ ] Settings → Modules: enable, disable, reload, install, update, remove from a repository
   - [ ] the safe-mode banner
9. Lock — open
   - [ ] lock supervisor limit (3 restarts while locked, then stay locked, tell the user)
   - [ ] lock-before-sleep conflict detection
   - [ ] screensaver and lock screen working together checked
10. Test split implemented — done (2026-11-17)
    - [x] the unit and module suites run without `nix` (tools from the system)
    - [x] the lock bed with the system's tools; the whole lock bed on Arch
    - [x] system detection behind a seam (`methods-script` runs both branches everywhere)
    - [x] `tests/run-system.sh` and the first checks per system; `install.sh` under stand-ins
    - [x] `tests/run-all.sh`
11. PAM configuration from the shell — open
12. Documentation for users and developers per [plans/documentation.md](plans/documentation.md);
    the architecture and API chapters after 3–7 — open
13. Ready for outside authors — open
    - [ ] the author guide and the API reference in `docs/` (was "M5 author guide" in the
          backlog)
    - [ ] a module template
    - [ ] a module's tests runnable without a checkout of the shell
    - [ ] the public versioning rule written down (removals only with a major version,
          after a release listed as deprecated); in force from step 15
    - [ ] the trust text, and the confirmation when a module that is not shipped is first
          enabled
    - [ ] Settings → Modules shows where a module comes from, and when a user's copy
          replaces a shipped one
14. Divide the built-in features: abstraction in the shell, feature in a module — open
    - [ ] go through every built-in feature: what is the service or the abstraction (stays),
          what is the feature (moves)
    - [ ] one feature first, as the proof of the API; shipped with the shell, on the public
          API only
    - [ ] the rest, feature by feature
15. Announce the shell as open to module authors, after the first feature of step 14 is
    split out — open
    - [ ] the release that says so; from it a removal from the module API needs a major
          version

What steps 3–6 must leave possible for 13–15 is in [plans/api-next/versioning.md](plans/api-next/versioning.md), §11 "Doors to keep open".

Later:
- pttd (dictation) as its own module in its own repository (was TODO 11.24); until then
  the protocol is in [pttd-protocol.md](pttd-protocol.md)
- global default programs (the terminal among them)
- NixOS option for modules (`programs.h2s-shell.modules`); module signatures
- UI texts pass and translations, in one go; the owner reviews the voice (short plain wording)
- documentation as a site with per-system tabs
- module order: the order in which modules are loaded, and the order of different modules'
  elements in one place (two separate things; until then both by module id)
- modules' own elements, published: a module defines an element with its own public
  styles, settable by a theme, and publishes it through a public API, so that libraries of
  extra elements can exist (building its own elements for itself is allowed now)

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
- Module API: a minor version may tighten behaviour for now (nobody else uses the shell yet); the rule is tightened when needed. (Temporary: it ends at the first release announced as open to module authors, see "Module API, versioning for authors" below.)
- Module API, UI anchors: views are built from shared blocks (settings page, section, card, row, popup section) that register under a path derived from where they stand; a module names a path, a placement (before, after, appended inside) and its element. Addressable: settings pages and popup content; not the bar (the user places widgets there). One naming convention for anchors; the list of anchors pinned by a test and documented. Today's slots move onto anchors.
- Module API: a module may publish its own versioned API object for other modules (declared in the manifest; a dependent module gets only that object). Basic version in this round. Reaching into another module or the host goes away.
- Privileged runs by a module: no time window; the password prompt says which module asks and what for, next to the actual command.
- Exit node (Tailscale): a manual choice "for now" that overrides the per-network setting, and a per-network choice in that connection's options (through an anchor).
- No terminal setting of its own: a global "default programs" setting later.
- (Temporary, see "Module authors" and "Trust" below.) Modules closed for now = the trust model written down honestly (a module runs in the shell's process, which also handles the lock screen's password and the polkit agent), Settings → Modules (enable, disable, reload, install, update, remove from a repository), the safe-mode banner. Later: NixOS option for modules, signatures.
- Coding is done by strong models only; no weaker models for mechanical moves.
- Module API, placements: `before`, `after` (outside the block), `prepend`, `append` (inside, first and last).
- (Replaced as to "only", see "a module's own elements" below.) Module API, public elements: modules build their views only from public elements made for the API (in `qs.api`), which use the shell's internal components inside; the internals stay free to change, the public elements keep compatibility. Modules should use as many standard elements as they can. In this round.
- Module API, variants are meanings, not looks, on every public element; never raw colours or sizes (on a public element's properties; a module's own elements are free, see below). A button's kind is `primary`, `secondary`, `danger`, `warning` or `success`, and more may come; asking first is a separate thing that goes with any kind; a danger button may act on the first click. A module's "Cancel" is `secondary`; no kind of its own.
- Buttons with a tone (`danger`, `warning`, `success`) are bordered: at rest a border in the tone's colour, under the pointer or a pressing finger the whole background in it. Every such button in the shell takes this look, the small "✕" on each row of the Bluetooth popup and the per-row "Disconnect" buttons included.
- Pills: three sizes, `s`, `m`, `l`, standard, set by the theme and offered through the API. The shell's 24 px pills become `s` (22 px).
- Module API, network cards: the place for a module's button on a card is built in this round; the button is the shell's, of any kind, always above "Forget" / "Delete" (a module that wants caution makes it ask first). An element that opens is the shell's `ExpandingRow`. A closed card shows the module's icon when the module has something set for that network; the detail is on the opened card.
- Module API, a module's icon: a glyph of the icon font, an SVG file or an image file; the module chooses.
- Module API, order: by module id for now; a module's say in the load order and in the order of elements in one place comes later.
- Password prompt: the labels are "Module" and "Authorization"; the command is hidden and shown on a click, is the real command, and a long one is shown whole, scrolling. (Replaces "next to the actual command" above as to where it shows.) With another polkit agent the run goes ahead, with a shell notification naming module and purpose just before.
- Privileged runs: a prompt open or waiting when the screen locks is cancelled as if dismissed, and the user clicks again after unlocking. Only the password question is one at a time, so a long action does not hold up the others; with another polkit agent it is strictly one action at a time. A run for which no password is asked shows nothing; one log line names the module.
- File chooser for modules: a minimal version in this round.
- Exit node per network: it sits on the saved network's opened card.
- Module API, a module's own elements: modules are not kept from building their own elements. They use the public elements wherever that is possible and makes sense, and the theme's colours always; building something the API does not offer is fine. Importing the shell's internal elements stays the thing to avoid. (Replaces "only from public elements" above: that is not a rule and not an error.)
- Module authors: that every module is the owner's is true today, not an assumption to build on. Other people are expected to write modules later; until then the shell and its module system are built up to the point where they can do so without problems.
- Direction: the shell itself becomes a fairly small framework that defines the structure and the way of working; parts of what is built in today can then be split out into modules. Such modules need not live in repositories of their own: some ship together with the shell.
- Module API, a module's own elements, in detail: built from QtQuick; every colour and type size from the theme's public tokens (`Api.theme`), never a literal; a public element is used where one exists and fits (a "should", not checked); a module asks for a new public element when it is of general use and builds its own otherwise. Only importing the shell's internal components is detected: listed as deprecated, then an error in the module's status. "The module API is ours" covers capabilities (running things, system state, privileges, places in the shell's views), not looks. The token names are pinned by a test.
- Review as a guard is for the project's own modules. An outside module has no review; there the password prompt's text (Module, Authorization, the command) is the only protection.
- Module API, versioning for authors: "a minor may remove things" ends at the first release announced as open to module authors. From then a removal comes only with a major version, after being listed as deprecated for at least one release, and is announced in `CHANGELOG.md`'s "Module API" section and the author guide. Merging the closing slice only after the module is released is a one-off for the one module of today.
- Shipped modules use only the public API, like anyone's module: one class of modules. Every feature split out proves the API.
- The shell provides the services, or abstractions for reaching them; a module builds on them and adds the whole feature (popups, elements, widgets, settings pages). Every built-in feature is to be gone through and divided this way. The lock screen, password prompts and privileged runs stay in the framework.
- Order after the API round (2026-11-17): the author guide, a module template and a module's tests runnable without a checkout of the shell; then the built-in features are divided, one first, as the proof that the API is enough; only then is the shell announced as open to module authors, and from that release a removal needs a major version.
- Trust: no isolation ("the shell must work and modules need access to its functions"); running modules in a process of their own is not a later question. The user must know what they install: a module that does not come from the project is announced as such (a plain statement and a confirmation when a module that is not shipped is first enabled; shown when a user's copy replaces a shipped one), and is then not the project's responsibility.

## Backlog / later

From the old TODO (numbers kept, see done.md for the rest):
- [ ] 11.34 A command button bar widget: label and/or icon, a command per click (left, right, middle, maybe long press), run detached
- [ ] 11.31 Popups clear of the on-screen keyboard: done for a bar at the top; left: a bar at the bottom, popups by a bar at a side, the settings window (`panels/Popup.qml`)
- [ ] 11.32 "Settings saved" toast seen with nothing changed (the NixOS machine, 2026-11-08) — reproduce first
- [ ] 11.23 Installing: `install.sh` is tested under stand-ins (`tests/install-test.sh`), never yet run for real on a clean Arch; on a first run `Config` chmods `config.json` before it exists (one warning; a first start in an empty home as a lock-bed check is not written); publishing (AUR, docs for others) later
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

Found while writing the development rules (2026-11-17):
- [ ] `singletons/network/VpnLockdown.qml` without the installed script: a network coming up asks for the password by itself, and runs the shell tree's own `scripts/h2s-vpn-lockdown` as root (user-writable in a checkout) — against two development rules

Found during the test split (2026-11-17):
- [ ] Module runs in the headless compositor start the `nmcli` on `PATH` against a dead
      D-Bus address (`[NetworkEvents] nmcli monitor exited, restarting`) and try `notify-send`:
      against "tests never touch a real daemon"; a stand-in or a switch-off is needed
- [ ] `polkit/AuthPrompt.qml` sets no `textFormat` on polkit's texts (plain-text rule)
- [ ] `tests/ModulesTest.qml` (start guard, lines 268-301) asserts within a 300 ms timer:
      fails under load on a slow machine (3 checks, seen on the NixOS machine)
- [ ] Lock scenario `modules-discovery` once saw the supervisor silent for 44 s under load
      (not looked at)
- [ ] `tests/lock/tools.nix`: the comment ties the pin to one machine's system
- [ ] The module repository's `tests/lock-bed/run.sh` header still advises wrapping the run
      in `flock` (harmless, stale)
- [ ] Lock scenario `restart-crash-locked`, the check "Quickshell said it would not
      restart": failed twice in whole runs of the bed on the Arch machine (Quickshell 0.3.2),
      passed three times alone; belongs with the upstream notes (`notes/upstream/`). A
      SIGSEGV 0.2 s after the shell started: Quickshell's crash
      handler printed "Quickshell has been restarted", then `Launching config: ""` and
      "Could not open config file", exit 255 — not its "crashed within 10 seconds of
      launching. Not restarting". The launcher started a new shell either way and the screen
      stayed locked; the check expects one of two ways Quickshell ends an early crash

## Open points

- None of the owner's decisions are pending. The plans in `plans/` (`api-next.md`,
  `architecture-cleanup.md`, `documentation.md`) are drafts written before the decisions
  of 2026-11-17; step 1 revises them, and the owner approves them before implementation.
