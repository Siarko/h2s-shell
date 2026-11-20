# Tracker

The one list of what is next, for the shell and its modules (the module repository
`h2s-shell-tailscale` keeps no tracker of its own). Done items go to [done.md](done.md) in
full. Plans are in [plans/](plans/); how sessions work is in [workflow.md](workflow.md).
Machines are named only "the NixOS machine" and "the Arch machine".

## Now

State on 2026-11-19: all done work is on `master` (core, module API 1.32) and `main`
(module `h2s-shell-tailscale` 0.6.0, manifest `api` 1.32, migration M1–M11 done, not released since); the live
shell runs it on both machines. Development is on the Arch machine; runs that need `nix`
go over SSH to the NixOS machine. One topic at a time: the API plan
([plans/api-next.md](plans/api-next.md), approved 2026-11-17; a slice's brief names the
index and the slice's area file, nothing more).

The codes in brackets (C1, U2, M3 …) are lookup keys into the slice table in
[plans/api-next.md](plans/api-next.md) §7.

### What remains of the API plan

Done slices are in [done.md](done.md), "API plan and the work around it". Left:

- [ ] the closing slice (Z), after the module is released

### Notifications with a progress bar and Taildrop's list of transfers

Both plans are built and on `master` (core, module API 1.33) and `main` (module, manifest
`api` 1.33); done slices in [done.md](done.md). Left, the owner's:

- [ ] Next, after the open questions: an analysis of the whole notification flow (the owner,
      2026-11-20) — every case and possibility, logically and visually, probably two separate
      queues (toasts that count down and toasts that stay or carry a job); whether a click on a
      progress notification's button should close it (Cancel, Skip) or replace it ("Send now"
      → a new one with progress only), and whether the `gdbus` path is then still needed. To be
      discussed with the owner before a plan.
- [ ] Taildrop on a real tailnet: the owner has used it for a while and it works; a failure and
      a stall are hard to see because files go at once.
- [ ] Releases: the core's minor (CHANGELOG Unreleased: progress notifications, toasts that
      follow the sender's time, module API 1.33) and the module's 0.7.0.
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

- **The progress handle's details** (N2, agent's choice stands): a failed update is not
  retried (the next change sends the whole content); test mode records every `update()` at
  once without coalescing; handles are never destroyed (one small object each).
- **Progress notifications for modules** (N3, agent's choice stands): a module gets a thin
  wrapper (`open`, `state`, `update`, `close`), not the handle's id or content; while a module
  is off, a progress `notify` shows nothing and returns `null`; a handle from `Api.notify`
  belongs to no module (only its own `close()` closes it); `toast` without `progress` is
  dropped.
- **Taildrop's list on the page, looks not in the plan** (D4, agent's choice stands): the list
  under the Save / Open folder row, incoming files first; titles bold; the state text cut at
  half the section's width; incoming files "Receiving · 40 %"; an ended save keeps the title
  "Saving N files".
- **Several devices from the page** (D8, agent's choice stands): a device row's "Send file…"
  makes that device the only one picked (not added to the choice); a picked device that drops
  out stays out when it comes back; "Send to N devices".
- **How the progress handle talks to the server** (N2, the lead's choice, for the owner's
  eyes): `notify-send` closes a notification itself after a click (and `--action` always
  waits), so the plan's waiter could not keep actions after a click. The handle instead sends
  and updates with a one-shot `gdbus call … Notify` (arguments as GVariant text through an
  escaping rule with adversarial cases) and learns clicks and closing from the shell's own
  server objects by id; with another daemon owning the name the handle reads "unknown". Plain
  notifications still go through `notify-send` as before.
- **Taildrop words** (D1; the owner 2026-11-20: kept for now, the held-back file rule confirmed): a queued file
  "Queued"; a running file of unknown size "Sending…" / "Saving…"; a failure without a reason
  "Failed"; save reasons "Bad name", "Not fetched", "No free name"; a one-file title
  "To laptop · 1 file". A file held back because the same name is already going to that
  device waits while the files behind it may start (the plan says only "in order").
- **Progress on a card** (N1, agent's choice stands): an action on a resident notification
  keeps its entry for the default action and the inline reply too, not only the buttons.
- **Toasts and the sender's time, choices not in the plan** (N5, agent's choice stands): with
  the limit of staying toasts reached, a staying toast at the head of the queue waits and later
  ordinary toasts may show past it; in "One at a time" a toast with the app's own time takes the
  one slot (it waits behind a shown ordinary toast); changing "Show each toast for" while a
  toast counts restarts its count from full; the release holding it is a minor (the owner
  2026-11-20: minor).

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
- Flaky: `AnchorsTest` (the General page's rows read -28 wide; three times in full runs on 2026-11-20, never alone); `restart-kill-locked` once on NixOS
  (keep `LOCKTEST_KEEP=1` artifacts); QtTest's `'windowShown' of null` once.
- The test tree's by-hand recipe (`tests/lock/README.md`) never run; `TestSeamsShapeTest`
  finds literal names only; O6 (lock tools from the trusted lookup) not built.

**Notifications with a progress bar**
- `shelltest.notificationState()` (N1) is live in the production shell like the other
  `shelltest` functions and returns the summaries of held notifications to any process of
  the user, also while locked; ids and progress only, or a gate, would be tighter.
- A `value` below 0 gives a bar of unknown length for any sender; the plan meant that for
  the shell's own sender only (other daemons clamp it).
- No test drives the toast (`NotificationHudItem`) through `actionInvoked`.

**Taildrop's list of transfers**
- The popup row shows only the newest popup send per device: a second popup send queued
  behind the first, Cancel stops the second, the first runs on unseen (until D5/D6's panels).
- `TaildropLiveTest` "two-devices: both sent" timed out once (agents' tests side by side).
- (notifications) A slot taking its next toast from `slideOut.onStopped` still holds its old
  notification, so `nudge` and `slideIn` animate `x` at once (cosmetic, older than N5).
- (notifications) That Quickshell emits `closed` before freeing a notification is assumed
  (the slot's release on close is tested on stand-in objects only).
- A save stopped (Skip, Cancel, logout) after its rename shows "Skipped" though the file was
  saved: the runner passes no output after `cancel()` (core opt-in being added; then the
  module wires it). A DELETE already sent to the daemon when an account switch starts cannot
  be called back.
- Unlimited runs (sends, saves) are not wrapped in `setpriv --pdeathsig`: a shell crash leaves
  them running (core fix in progress).

- (Taildrop) The page's transfers list is not limited to the operator (the old send line was).
  Incoming files are keyed by name only: two peers sending one name at once show one row.
- (Taildrop) `fileOffers` runs `schedule` twice per file row on every tick of the popup's
  files panel; the cost grows with rows and transfers.

- (tests) `AnchorsTest` failed once (5 checks) in a full run under load during N2; alone and in
  the next full run it passed.
- (notifications) The progress handle's run token travels as a `gdbus` argv word, readable in
  `/proc/<pid>/cmdline` by the user's own processes (worst case: a toast shown again).
  If `hintsChanged` fires before `expireTimeoutChanged`, a re-queued announced toast is taken
  with its old timing and a column can briefly hold one toast too many.
- (module API) `Api.module(id)` / `Api.moduleAt(url)` hand out other modules' handles, so a
  module can send notifications, progress ones too, under another module's name (an older
  cross-module gap; Z removes `Api.module`). A plain `module.notify` still takes `appName`.
- (Taildrop) One `TaildropLiveTest` run during D7 failed one check (not captured; another
  tree's tests ran at the same time); 14 reruns passed.

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

Later: Taildrop's history of sends with "send again" (a file no longer there handled; the
owner 2026-11-20); pttd (dictation) as its own module in its own repository (was 11.24; protocol in
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
- Taildrop (2026-11-19): no fixed time limits on transfers (sending, or copying received
  files out of Tailscale's inbox). Instead a list of transfers with progress; per file "Skip"
  (stop it, the rest go on) and "Fetch in parallel" (start the next file beside a stuck one);
  a transfer with no progress shows "no progress for N min" and waits for the user. A feature
  of the module, planned after the migration slices. A run that cannot start says "The
  program could not be started." (kept).
- Notifications (2026-11-19): a plain notification's body keeps its line breaks (the title
  stays one line). Notifications with a progress bar are wanted: a module updates one
  notification's progress instead of sending new ones (the spec's `value` hint and
  replacement; the shell is the notification server). An API feature, planned.
- A module's icon (2026-11-19): it is the module's face in the list that manages modules
  (Settings → Modules), not something the shell puts on cards. A module that adds something
  to a network shows it on that network's card itself, with its own element in a place the
  card offers on its name line (closed and open); the shell only bounds its size.
  `setMark` / `clearMark` (unreleased, 1.27) go.
- A module's button in a card (2026-11-19): the module chooses its size; `m` is only the
  default. The module's author keeps it consistent.
- An opened card ends as far under its last line as its first line is under the top (the
  6 px left by an empty page-rows column go).
- A question asked in the confirm colour (dark green on the surface): left for the themes'
  rework, with the hover contrast.
- Pills (2026-11-19): their text size always comes from the theme's tokens, never pixels in
  code; a module may choose among the theme's sizes (small, body). M10 keeps to it.
- Two bar entries of one widget type (2026-11-19): a click on the second switches the popup
  to it, as hover does (a fix to make).
- Data migrations while the shell is in development (2026-11-19): before writing one, check whether the feature is in use (on both machines, as was done for the Tailscale certificates: no old folder anywhere). Not in use → no migration. In use → ask the owner.
- The module API is agnostic (2026-11-19): it is not built for the Tailscale module; it
  gives modules as wide an access as it can, and Tailscale is one user of it. So network
  facts keep Docker/libvirt bridges (`kind: "bridge"`), the kinds and left-out types as built,
  `setsDns` = "has DNS servers of its own while up".
- The file chooser (2026-11-19): the platform theme's dialog (as built); an empty title shows
  the module's name; a lock closing it answers `blocked: "locked"`, told apart from the user
  cancelling (a change to make).
- Dependencies between modules (2026-11-19): soft and hard. Hard = a requirement (today's
  `uses`: missing → `missing-module`). Soft = the module loads anyway, after the provider when
  it is there, and integrates with it optionally (its `uses` entry is null without it). Soft
  dependencies are to be added. P1's other choices stand (a malformed entry fails the module;
  a function handed to a provider is the dependent's job; a failed provider stays failed
  until turned off and on).
- The Wi-Fi settings page (2026-11-19, looked at on a screen: the pages are fine): the Wi-Fi
  switch moves into the page's heading; the "Wi-Fi … Off" row under it goes (the switch shows
  the state).
- Network cards (2026-11-19): the main button, Edit and Forget stand in one row on the name
  line, also while the card is closed (saved Wi-Fi, hotspot, wired; nothing stacked when
  opened). Order: main, Edit, Forget.
  When the row does not fit (a narrow window, a long question while a button asks), it moves to
  its own line under the name, right-aligned, the question getting the card's width.
- Taildrop send from the popup (2026-11-19, seen on a screen: picking a file opens the settings
  window where Send must be clicked — impractical): everything stays in the popup. After the
  file(s) are picked, a row under that device's row names the file (or "N files") with a Send
  button; after Send, a progress bar of the send in that row (from the bus's outgoing files);
  the same for several files. The settings window does not open (M8).
- Taildrop names with U+2028/U+2029 (module, low): `TaildropRules._unsafeCharacters` misses them, so such a name shows on two lines in the received-files notification; Tailscale itself refuses such names. One regex range.
- Contrast of warning/success buttons under the pointer: left as is until the themes' rework.
- Exit node "for now" (2026-11-19): the popup's chooser has a "Default" choice that drops the manual override and goes back to the per-network setting. The manual choice is kept only in memory: it ends when the shell or the computer restarts and when the computer wakes from sleep or hibernation (M9).
- Exit node "for now", details (2026-11-19): with no per-network choice for the networks up,
  "Default" and a wake turn the exit node off; joining a network with its own choice while
  "for now" lasts keeps the pick (only Default, restart or wake end it); only a pick in the
  shell's chooser is "for now" (a change from the `tailscale` command is not); a network set
  to "No exit node" shows no mark on its card.
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

- [ ] Two bar entries of one type and preset: the adopted "active" mark can land on the other cell than the popup sits over (rare)

- [ ] `AnchorsTest` failed twice under load, each time once and never on rerun (a section's parts' order; an earlier one in U7a): find the wait that measures before layout

- [ ] Tailscale module: the event stream is started outside `_run`, so one bus message is cut at the runner's default 1 MB (a very large netmap message)

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
