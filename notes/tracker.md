# Tracker

The one list of what is next, for the shell and its modules (the module repository
`h2s-shell-tailscale` keeps no tracker of its own). Done items go to [done.md](done.md) in
full. Plans are in [plans/](plans/); how sessions work is in [workflow.md](workflow.md).
Machines are named only "the NixOS machine" and "the Arch machine".

## Now

State on 2026-11-19: all done work is on `master` (core, module API 1.22) and `main`
(module `h2s-shell-tailscale` 0.6.0, manifest `api` 1.14, not released since); the live
shell runs it on both machines. Development is on the Arch machine; runs that need `nix`
go over SSH to the NixOS machine. One topic at a time: the API plan
([plans/api-next.md](plans/api-next.md), approved 2026-11-17; a slice's brief names the
index and the slice's area file, nothing more).

The codes in brackets (C1, U2, M3 …) are lookup keys into the slice table in
[plans/api-next.md](plans/api-next.md) §7.

### What remains of the API plan

Done slices are in [done.md](done.md), "API plan and the work around it". Left:

- [ ] the module: its runner (M1), main and popup (M4), helpers and facts (M5), row and
      card onto anchors (M6), exit node per network on the cards (M7), "Send file…" through
      the chooser (M8), the "for now" override (M9), off the shell's internals (M10), the
      last (M11)
- [ ] the closing slice (Z), after the module is released
- [ ] a short independent review of what changed in the plan after its last review
      (button kinds, icons, the password queue, a module's own elements), folded into the
      review of each area's first slices

Running a session cheaply (the owner): one topic at a time; the owner's answers handed to
an agent in one go; fresh agents with narrow briefs; no agent waits on a test queue; review
what carries risk, look at one-line fixes yourself.

## Open points

For the owner. Until answered, the agent's choice stands. (`plans/architecture-cleanup.md`
and `plans/documentation.md` predate the decisions of 2026-11-17: step 1 revises them.)

**To look at on a screen**

- **The Wi-Fi and Ethernet settings pages on anchor blocks** (U5): the "Saved networks"
  and "Hotspots" titles with their buttons at the right edge, the cards' spacing, an opened
  card with the password row, the "None yet" lines on a machine with none; Ethernet: "Wired
  profiles" as far under the device card as before, an opened profile card.

- **The popups on anchor blocks** (U2). Network popup with Tailscale up: VPN header, rows
  4 px apart, the exit-node chooser right under its row, Ethernet and Wi-Fi spacing
  unchanged, the divider over the network list only while Wi-Fi is on, the list not cut
  short, a hotspot on its line with "Turn off hotspot". Notifications: header and "Clear
  all" 8 px in, the list filling and scrolling, cards sliding, "All caught up" then
  closing. Moving the pointer between bar cells with a popup open.
- **The file chooser for modules** (E1, both machines): opened from a module popup that is
  then closed, the dialog stays, has the keyboard, opens where asked, returns the pick; a
  lock closes it; with `QT_QPA_PLATFORMTHEME=xdgdesktopportal` "several files" returns
  several. Not tried: Ctrl/Shift+click in Qt's own dialog; "Open" in the folder dialog
  with nothing chosen.
- **The password prompt on a real module run** (A5, M3): seen on Arch (`/usr/bin/true`,
  polkit 128); not yet on NixOS, and a real Tailscale action through the queue on neither.
- **The public settings row and expanding row** (F3, when the module uses them in M7):
  value right-aligned, at most 220 px; no hover on the opening line; content not indented.

**To decide**

- **A module's icon and marks on closed cards** (U7a, U7b, the agent's looks): 6 px between a
  card's name and the first mark, 4 px between marks; icons in the name's colour, also on an
  active card; a module without an icon shows the first letter of its name, upper case,
  muted. Marks are on saved Wi-Fi and wired cards only (as the plan's table) — VPN cards too?

- **A module's buttons in a card** (U6): the region forces size `m` (a module's `size: "s"`
  is overridden), reading the plan's "the size is m"; the alternative is `m` as the default
  and the module's choice kept. A long label is cut at a third of the card's width.

- **An opened network card with no page rows** (wired, hotspot) keeps 6 px of empty space at the
  bottom, inherited from the old card and kept so the rebuilt card measures the same (U4b).
  Remove it?

- **Hover on warning and success buttons**: white text on `#e8a854` / `#44d47a`, about 2:1
  contrast (text wants 4.5:1). Dark text, or darker fills?
- **A question in the confirm colour**: "Connect" on a network card and "Turn on" for a
  hotspot ask in dark green on the surface, hard to read. Keep, or another colour?
- **The public pill's text** (before M10): small font at every size, as the shell's pills;
  the module's pills get smaller text than today when it moves. Keep?
- **Plain notifications on one line** (C1): line breaks become spaces, so the module's
  "received several files" reads "a.txt b.txt". Or keep line breaks in a plain body? Caps:
  summary 200, body 1000, a `module.log` line 1000 characters.
- **The Tailscale module's texts since M3** (the agent's words):
  - "Authorization" lines: Connect, Disconnect, Log in, Add an account, Log out; Change
    the exit node; Allow / Block the local network; Accept / Ignore routes; Use / Ignore
    Tailscale DNS; Block / Allow incoming connections; Start / Stop the SSH server; Start /
    Stop the web interface; Offer an exit node / Stop offering an exit node; Turn on / off
    automatic updates, source NAT, stateful filtering; Offer an app connector / Stop the
    app connector; Report device posture / Stop posture reports; Run a peer relay / Turn
    off the peer relay; Check for updates / Stop update checks; Rename this device, Change
    offered routes, Name the account; Become the operator / Give up the operator role;
    List accounts, Switch account, Remove an account; Stop every share, Stop Funnel; Share
    a port, Share a port on the internet, Stop a share, Turn on / off Funnel.
  - Refused: "<what> — not allowed"; the entry "Not allowed." (was "No authentication
    agent answered."); "It was not run as administrator: the command holds characters that
    can't be shown" / "… it doesn't say what it is for" / "… the screen is locked".
  - "Can't ask for the password." (no way to run as administrator); "Changes that need an
    administrator are not offered: pkexec is still being looked for." (just after start).
  - Funnel left public after a wait: "Port N is public with something else on it." with
    "Turn off Funnel", and the notice "… Turn Funnel off on Tailscale's page."
- **Two bar entries of one widget type share one popup**: a click on the second closes the
  first's popup (only hover re-targets). Should the click switch to the second?
- **Network facts** (D1): `Api.localNetworks` includes Docker and libvirt bridges — leave
  them out? The `kind` words (wifi, ethernet, bridge, modem, other); left out: loopback,
  tun, wireguard, vpn, ip-tunnel, wifi-p2p. `setsDns` = "has DNS servers of its own while
  up", not "takes over DNS".
- **The file chooser** (E1): whichever dialog the platform theme gives, not forced to Qt's
  own (the lead's reading of "the system's dialog"); an empty title shows Qt's default —
  the module's name instead?; a lock reads as `cancelled`, like the user cancelling.
- **Dependencies between modules** (P1): a malformed `exports` / `uses` fails the whole
  module; a function a dependent handed its provider may be called after the dependent is
  off (the dependent's job, says `Api.qml`); a provider whose main failed stays failed
  until turned off and on.
- **Spacing in a settings page** (U1a, from the old General slot): 16 px between the page
  and the module hosts before and after it, 4 px between elements in a host. Status texts
  quote paths in JSON quotes, not backticks.
- **Agents' wording**: the Controls page's "Warning buttons" / "Success buttons" and their
  CHANGELOG line (F1a); `modules list`: "import qs.components (in 17 files): use the
  elements of qs.api (goes with the shell's next tightening)" (F4).

## Left open by done work

Still work or a known risk; the detail is in [done.md](done.md).

**Privileged runs and the prompt**
- polkit's limit: past 80 bytes, a command with the same first 38 and last 37 bytes gets
  the same prompt lines (documented; the flow carries no more).
- Legacy `PrivilegedAction`: no refusals until Z, an explicit `elevate` path runs as given,
  relative programs not announced, not yet in `deprecations`; its notice reads "Module:
  Not named". A Georgian message is never announced (polkit's `ka.po`).
- A prompt left open holds the queue (`timeoutMs` starts as root). `deciding` after start
  counts as "the prompt does not answer". A run asking at lock ends `dismissed`.
- One-turn races: a request opening and closing within a turn is missed; an answer just
  before a module off/on is delivered.
- Only stand-ins so far: the real pkexec and NixOS wrapper, TERM, a real notification
  daemon (a server without body markup would show `&lt;`); fixture windows may flake.
- Test mode's guard reads program words only (mistakes, not a sandbox); the stack-based
  transitional gate for modules below API 1.10 goes in Z.

**Command runner and program lookup**
- No `timeout` / `setpriv`: not wrapped, the watchdog keeps the limit. One empty line too
  many at the end of output (Quickshell 0.3.2's parser; worth a `notes/upstream/` note).
- `Lockscreen.qml` uses `$PPID` (change when its probes move to the runner);
  `ModuleHost._clearGuard` uses `execDetached`. Untested: a quit with a run in flight.
- The probe's fixed `PATH` finds nothing on a system with tools elsewhere; an untrusted
  required program does not stop a module; the NixOS cases are unit cases only.

**Module host, dependencies and facts**
- A dependent with only views is not waited for (one turn); a consumer's suites need the
  provider's directory. The reach scan misses a handle not named `module`.
- `importsOf` misses a quoted import holding `{`; S0's tokenizer cases are not added; a
  floor of another major is not designed.
- Plans still name rules by `ModuleRules.*`: they are in `ModuleMergeRules`,
  `ModuleSourceRules`, `ModuleManifestRules`, `ModuleFileRules`.
- Data directory not made → module loads with `""`; test-mode home not removed; no OS fact
  in `Api.system`; the core's `Quickshell.env("HOME")` not on `SystemFacts`.
- Plugin VPN full-tunnel unchecked on a machine; an IPsec VPN without its own addresses
  looks like its device. `opener` is null without a bar widget.

**Anchors, places and elements**
- An element through an old slot reports errors under the anchor's name. Untested:
  `editIndex`, the General page's scrolling, `_panel.contentTop` in the network list.
- The public `SettingsRow` has no anchor yet. Public controls share names with
  `qs.components` (last import wins) and `Pill.minimumHeight` stays, both until M10/Z;
  `tests/run-modules.sh` fails on deprecations only from Z.

**Tests and the lock bed**
- Flaky: `CommandRunnerTest` (one check in ~20 runs); `restart-kill-locked` once on NixOS
  (keep `LOCKTEST_KEEP=1` artifacts); QtTest's `'windowShown' of null` once.
- The test tree's by-hand recipe (`tests/lock/README.md`) never run; `TestSeamsShapeTest`
  finds literal names only; O6 (lock tools from the trusted lookup) not built.

**The Tailscale module**
- `ModuleTestKit` should replace its `ScenarioHandle.qml` and `liveSuites.js`: per-suite
  program overrides, suites that run alone or last.
- Fix with M10: `PrivilegedMark` `visible: need !== ""` (`ServeSection.qml` ×2,
  `TailscalePopup.qml`) shows the lock for `need: "yes"`.
- Certificates move from `h2s-shell/tailscale/certs` to the data directory in M5. With
  Qt's own dialog "send files" sends one file per pick (M8).

## Order of work

0. Workflow:
   - [ ] (b) own working trees and test bed per agent; modules tested against a pinned core tree
   - [ ] (d) flaky live tests first: the Tailscale stand-in's event replay
         (`tools/stand-in/curl`); the tailnet-lock read not retried (`module/LockClient.qml`)
   - [ ] (e) a read-only check against the real Tailscale daemon at deploy (state, devices,
         no repeated log lines)
1. Planning, no code:
   - [ ] analysis + plan: PAM configuration from the shell (polkit and lock, NixOS and Arch)
   - [ ] plan: installing, updating and removing modules, with Settings → Modules
   - [ ] revise [plans/documentation.md](plans/documentation.md) and
         [plans/architecture-cleanup.md](plans/architecture-cleanup.md) for the decisions
2. Release — open
   - [ ] `lockscreen.lockOnSleep` default off (`singletons/SettingsSchema.qml`, today `true`)
   - [ ] versioning rule corrected (`CHANGELOG.md` header, `singletons/Version.qml` comment)
   - [ ] cut a minor release (today 2.0.0)
4. UI anchors replace today's slots (`ModuleSlot.qml`, `Api.slots`): the cards and network
   pages (U4a–U7b)
6. Tailscale module migration — open: every workaround removed; exit node per network in
   the connection's options (through an anchor); the manual "for now" override
7. Architecture clean-up per [plans/architecture-cleanup.md](plans/architecture-cleanup.md)
   (splits, hubs, test hooks, the module's read/clock performance, the network editor's
   save that can lose the kill-switch choice), alongside 3–6 where slices do not collide — open
8. Modules closed for now (a state of today, ended by step 15) — open: the trust model
   written down honestly (no isolation; review covers the project's own modules; for others
   the prompt's text is the only protection); Settings → Modules (enable, disable, reload,
   install, update, remove from a repository); the safe-mode banner
9. Lock — open: supervisor limit (3 restarts while locked, then stay locked, tell the user);
   lock-before-sleep conflict detection; screensaver and lock screen together checked
11. PAM configuration from the shell — open
12. Documentation per [plans/documentation.md](plans/documentation.md); architecture and API
    chapters after 3–7 — open
13. Ready for outside authors — open: the author guide and API reference in `docs/`; a
    module template; a module's tests without a checkout of the shell; the public
    versioning rule (removals only with a major, after a release listing them deprecated;
    in force from step 15); the trust text and a confirmation when a module not shipped is
    first enabled; Settings → Modules shows where a module comes from and when a user's
    copy replaces a shipped one
14. Divide the built-in features (abstraction in the shell, feature in a module) — open: go
    through every feature; one first, shipped, on the public API only, as the proof; then
    the rest
15. Announce the shell as open to module authors, after step 14's first feature — open: the
    release that says so; from it a removal from the module API needs a major version

What steps 3–6 must leave possible for 13–15: [plans/api-next/versioning.md](plans/api-next/versioning.md) §11.

Later: pttd (dictation) as its own module in its own repository (was 11.24; protocol in
[pttd-protocol.md](pttd-protocol.md)); global default programs (the terminal among them);
a NixOS option for modules (`programs.h2s-shell.modules`) and module signatures; a UI texts
pass with translations, the owner reviewing the voice; documentation as a site with
per-system tabs; module order (load order, and the order of different modules' elements in
one place — two things, both by module id until then); modules' own elements published
(public styles a theme can set, so libraries of elements can exist; building one's own for
oneself is allowed now).

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
- Privileged runs, 2026-11-18: the shell does not parse or judge a module's command (no lists of shells, launchers or interpreters, no requirement of a declared program). A module runs in the shell's process, so such checks never stop a hostile one; the checks left (absolute existing program, printable words, a purpose, not while locked, one prompt at a time, the shell's timeout inside the trusted pkexec) catch mistakes and keep the prompt honest. The protection against a module not from the project is the prompt and the user knowing what they install. Written in `docs/ARCHITECTURE.md` "Modules".
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
- File chooser for modules (2026-11-18): the system's standard dialog is enough for now. No chooser of the shell's own in this round, and sending files is not extended. The better answer is wanted later: integration with file managers (backlog).

## Backlog / later

- [ ] A VPN provider's id is matched against module ids without checking the module that registered it is that module (`VpnManager.register`): a module could register under another's id and get its elements under its VPNs (older than U4c). Also `VpnManager.ownExtrasOf` serves `rowExtras` for a module's provider too (unreachable for Tailscale)

- [ ] `components/ReorderList.qml` binds a bare array (`root._shown`) to `ListView.model` — against the Repeater-crash rule (found in the ScriptModel key fix)

Defects and risks:
- [ ] `panels/Popup.qml` `contentLoader.onLoaded` sets `availableHeight` / `popupAnimating`
      on a panel unguarded: a readonly one throws and skips the rest (core and module panels)
- [ ] `singletons/network/VpnLockdown.qml` without the installed script: a network coming up
      asks for the password by itself and runs the tree's own `scripts/h2s-vpn-lockdown` as
      root (user-writable in a checkout) — against two development rules
- [ ] 11.32 "Settings saved" toast seen with nothing changed (NixOS, 2026-11-08) — reproduce first
- [ ] Quickshell 0.3.2: a second polkit request while a prompt is open replaces it, never
      finished (upstream)
- [ ] The muted status line has low contrast on an active row's green tint in the network
      popup; opened connection cards have ~20 px empty under the detail line (neither re-checked)
- [ ] A start guard for slow crash loops (not re-checked); module widgets pop in after the
      first frame (`singletons/ModuleLists.qml`, by design today)
- [ ] `SmallButton` / `DeleteButton` have no keyboard focus or activation
- [ ] `Math.max(22, …)` for a pill's width in `panels/calendar/RecurrenceEditor.qml` (seen, not touched)
- [ ] `install.sh` (found by its test): the font warning can be false under `pipefail`
      (`fc-list` still writing as `grep -q` leaves); no terminal or no `sudo` ends with
      bash's own error; "ours" is too loose (a fork reads as "Already installed"); a target
      without `shell.qml` is left to `git clone`'s error
- [ ] The lock's password fallback (all low): the direct question's branch (`test -e
      /etc/NIXOS`, `Lockscreen.qml`) never runs live — add a stack without
      `H2S_LOCK_SYSTEM` and an unrunnable script to `fallback.sh`; a fallback taken at a
      failed detection can stay the unusable one (`LockRules.qml:914`): replace it in
      `_settingsChanged` while no conversation runs; neither probe has a time limit; the
      request numbering belongs in a rules function with cases

Tests:
- [ ] Suites that open the real `SettingsWindow` (ModuleRegistriesTest, AnchorsTest) and
      module runs in the headless compositor start the real `nmcli monitor` (dead D-Bus,
      "restarting") and try `notify-send`: against "tests never touch a real daemon" —
      stand-ins or a switch-off
- [ ] `tests/ModulesTest.qml` (start guard, lines 268–301) asserts within a 300 ms timer:
      fails under load (3 checks, NixOS)
- [ ] Lock scenarios: `fallback` failed once (the PAM stand-in never answered);
      `modules-discovery` once saw the supervisor silent 44 s under load;
      `restart-crash-locked` hit a race in Quickshell 0.3.2's crash handler (accepted since
      P1; upstream fix `pread`, `notes/upstream/quickshell-session-lock-unlock-notify.md`
      finding 5) — watch for it
- [ ] `tests/lock/tools.nix`'s comment ties the pin to one machine; the module's
      `tests/lock-bed/run.sh` header still advises `flock` (stale)

Features (old TODO numbers kept, see done.md):
- [ ] 11.34 A command button bar widget: label and/or icon, a command per click (left,
      right, middle, maybe long press), run detached; or a bar widget to shuffle the wallpaper
- [ ] 11.31 Popups clear of the on-screen keyboard: done for a bar at the top; left: a bar
      at the bottom, popups by a side bar, the settings window (`panels/Popup.qml`)
- [ ] 11.23 Installing: `install.sh` never run for real on a clean Arch; on a first run
      `Config` chmods `config.json` before it exists (a first start in an empty home as a
      lock-bed check is not written); publishing (AUR, docs) later
- [ ] 11.20 Animation editor; animations as data assigned to named element slots
- [ ] 11.5 Bar shape and anchoring ("dynamic island") — to work out with the owner first
- [ ] 11.7 Themes stage 8, matugen: a template mapping its palette to the colour tokens, a
      "wallpaper" theme reading it (`colorsFrom` exists), docs
- [ ] 11.8 Compositor integration, Hyprland first (scroll sensitivity, volume step, …) —
      first a plan, `notes/plans/compositor.md`, agreed with the owner
- [ ] A QR code to join a network (`qrencode`) (left from 11.37)
- [ ] Tailscale later: re-authentication without the profile reset (`login-interactive`),
      settings re-applied after a same-account login, certificate renewal, a terminal
      launcher for SSH (with the default programs); warn when an accepted subnet route
      covers the local network (LAN replies then leave through the tunnel; seen with "Use
      routes from other devices"); Taildrop's dialogs never clicked on a real machine
- 11.6 Styling with CSS-like selectors — shelved; [plans/selectors.md](plans/selectors.md),
  [plans/styles.md](plans/styles.md)

Files, later (the owner, 2026-11-18):
- [ ] Integration with file managers instead of a richer dialog: "send with Tailscale" on
      files chosen in Dolphin (a service menu, likely); explore what a module needs from
      the API to offer an action to any file manager (a project's own may come). First, no
      code of ours: `xdg-desktop-portal-kde` (`FileChooser=kde` in `hyprland-portals.conf`)
      makes Dolphin's dialog every portal user's file chooser.
- [ ] A file chooser of the project's own as a portal backend (with a project's own file
      manager): a D-Bus service implementing `org.freedesktop.impl.portal.FileChooser`, a
      `.portal` file, and a line preferring it in
      `~/.config/xdg-desktop-portal/<desktop>-portals.conf` (packages' files in
      `/usr/share/xdg-desktop-portal/`). Qt asks the portal only when the platform theme
      says so (`qt6ct`: "Standard dialogs"), the user's setting. Its own backend could close
      the dialog on a lock. NixOS and Arch differ in where the files go.
