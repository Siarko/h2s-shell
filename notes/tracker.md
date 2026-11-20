# Tracker

The one list of what is next, for the shell and its modules (the module repository
`h2s-shell-tailscale` keeps no tracker of its own). Only what is open stays here; done items
go to [done.md](done.md) in full. Plans are in [plans/](plans/); how sessions work is in
[workflow.md](workflow.md). Machines are named only "the NixOS machine" and "the Arch machine".

## Now

**Overnight run 2026-11-21/22 (the owner's rules):** do everything without bigger interface
changes first; for steps with views, prepare plans and mockups and stop there. Merging,
restarting and testing are allowed also while the screen is locked (the machines are in a safe
place; the PC has no lock screen). No computer should sleep (the laptop is plugged in), so
`lockOnSleep` off by default needs no pinning on these machines. No usage limit set.

State on 2026-11-21: notifications with a progress bar, Taildrop's list of transfers,
Taildrop's views reworked (side panel, status pills, the bar wave, Taildrop off, "Save in…")
and the notification flow (three toast queues, moving and pinning, the HUD clear of the bar)
are done and on `master` (core, module API 1.35) and `main` (module `h2s-shell-tailscale`
0.6.0, manifest `api` 1.35), not released; the live shell runs them on both machines.
Development is on the Arch machine; runs that need `nix` go over SSH to the NixOS machine.

Next, per the owner: the order of work below from step 0 up to and including step 8
("Modules closed for now"), then the release (core minor, module 0.7.0). One topic at a time.

The codes in brackets (C1, U2, M3, N2, D7 …) are lookup keys into the plans' slice tables
([plans/api-next.md](plans/api-next.md) §7, [plans/taildrop-ui.md](plans/taildrop-ui.md),
[plans/notification-flow.md](plans/notification-flow.md) §8.8, and the progress and transfer
plans named in done.md).

### Left of finished plans

- [ ] The API plan's closing slice (Z), after the module is released.
- [ ] A short independent review of what changed in the API plan after its last review
      (button kinds, icons, the password queue, a module's own elements) — meant to be folded
      into the reviews of each area's first slices; check that it was before dropping it.
- [ ] The Wi-Fi drawer on `SidePanel` (Taildrop views, C2) — optional, not started.

### The owner's open items

- [ ] Taildrop on a real tailnet: the owner has used it for a while and it works; a failure
      and a stall are hard to see because files go at once.
- [ ] Releases (the owner, 2026-11-21): not yet — first the order of work up to and including
      step 8, then the release (core minor, module 0.7.0).

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
- **The public settings row and expanding row** (F3): value right-aligned, at most 220 px;
  no hover on the opening line; content not indented.

**To decide**

- **Revised plans' questions** (2026-11-21): [plans/documentation.md](plans/documentation.md)
  ends with 4, [plans/architecture-cleanup.md](plans/architecture-cleanup.md) with 2.

**To decide: choices made by agents, for the owner to glance at**

- **"Share this computer's settings"** (M6; the rename is the owner's, the words are the
  agent's, to approve): the hint "Devices of the tailnet open them on port 5252 and, after
  logging in, change them"; the prompt reads "Share this computer's settings" / "Stop sharing
  this computer's settings"; "Web console" carries the tooltip "login.tailscale.com".
- **Taildrop** (D4, D7, M5): the page's list puts incoming files first, titles bold, state
  text cut at half the width. A cancelled transfer's notification keeps its summary with
  "Cancelled" / "Stopped: disconnected"; done and failed have no body; some files skipped and
  the rest sent counts as done. Switching Taildrop off lets running files finish and stops
  unstarted sends; turning it on announces what arrived meanwhile once (Save), without
  auto-saving it; the popup keeps Save and the count while off, the bar badge goes.
- **Progress notifications** (N2, N3): the handle talks to the server with one-shot
  `gdbus call … Notify` (escaped GVariant text) and learns clicks and closing from the
  shell's own server — `notify-send` closes a notification after a click, so it could not
  keep actions; with another daemon owning the name the handle reads "unknown". Test mode
  records every `update()` without coalescing; handles are never destroyed. A module gets a
  thin wrapper (`open`, `state`, `update`, `close`); while a module is off a progress `notify`
  returns `null`; `toast` without `progress` is dropped.
- **Toasts** (N5, notification flow slice 4): with the limit of staying toasts reached, later
  ordinary toasts may show past a waiting staying one; in "One at a time" a toast with the
  app's own time waits behind a shown ordinary toast; changing "Show each toast for" restarts
  a running count. A pinned ordinary toast stays until unpinned (a pinned job counts down when
  it ends); pinned toasts stand left of the toasts' column, each new one 48 px lower.
- **The side panel** (C1): Escape is window-wide while it is open; the owner setting `open`
  false closes it without `closed`; widths 320/420/520 are fixed in `Theme.qml` (grown with
  the font), not theme tokens; it does not open while the session is locked.

## Left open by done work

Known risks and leftovers, one line each; the detail is in [done.md](done.md).

**Privileged runs and the prompt**
- polkit's limit: past 80 bytes, commands with the same first 38 and last 37 bytes get the
  same prompt lines (documented).
- Legacy `PrivilegedAction`: no refusals until Z, an explicit `elevate` path runs as given,
  relative programs not announced, not in `deprecations`, its notice reads "Module: Not
  named". A Georgian message is never announced (polkit's `ka.po`).
- A prompt left open holds the queue (`timeoutMs` starts as root); `deciding` after start
  counts as "the prompt does not answer"; a run asking at lock ends `dismissed`.
- One-turn races: a request opening and closing within a turn is missed; an answer just
  before a module off/on is delivered.
- Only stand-ins so far: the real pkexec and NixOS wrapper, TERM, a real notification daemon
  (a server without body markup would show `&lt;`).
- Test mode's guard reads program words only (mistakes, not a sandbox); the transitional gate
  for modules below API 1.10 goes in Z.

**Command runner and program lookup**
- No `timeout` / `setpriv`: not wrapped, the watchdog keeps the limit. One empty line too many
  at the end of output (Quickshell 0.3.2's parser; worth a `notes/upstream/` note).
- `Lockscreen.qml` uses `$PPID`; `ModuleHost._clearGuard` uses `execDetached`. Untested: a
  quit with a run in flight.
- The probe's fixed `PATH` finds nothing on a system with tools elsewhere; an untrusted
  required program does not stop a module; the NixOS cases are unit cases only.

**Module host, dependencies and facts**
- A dependent with only views is not waited for (one turn); a consumer's suites need the
  provider's directory; the reach scan misses a handle not named `module`.
- `importsOf` misses a quoted import holding `{`; S0's tokenizer cases are not added; a floor
  of another major is not designed.
- Plans still name rules by `ModuleRules.*` (now `ModuleMergeRules`, `ModuleSourceRules`,
  `ModuleManifestRules`, `ModuleFileRules`).
- Data directory not made → module loads with `""`; test-mode home not removed; no OS fact in
  `Api.system`; the core's `Quickshell.env("HOME")` not on `SystemFacts`.
- Plugin VPN full-tunnel unchecked on a machine; an IPsec VPN without its own addresses looks
  like its device; `opener` is null without a bar widget.
- `Api.module(id)` / `Api.moduleAt(url)` hand out other modules' handles, so a module can
  notify under another's name (Z removes `Api.module`); a plain `module.notify` takes `appName`.

**Anchors, places and elements**
- An element through an old slot reports errors under the anchor's name. Untested:
  `editIndex`, the General page's scrolling, `_panel.contentTop` in the network list.
- The public `SettingsRow` has no anchor yet. Public controls share names with
  `qs.components` (last import wins) and `Pill.minimumHeight` stays, until Z;
  `tests/run-modules.sh` fails on deprecations only from Z.

**Notifications**
- `shelltest.notificationState()` is live in the production shell and returns held
  notifications' summaries to any process of the user, also while locked.
- A `value` below 0 gives a bar of unknown length for any sender (meant for the shell's own).
- The progress handle's run token is a `gdbus` argv word, readable in `/proc/<pid>/cmdline`
  by the user's own processes (worst case: a toast shown again).
- `hintsChanged` before `expireTimeoutChanged`: a re-queued announced toast takes its old
  timing and a column can briefly hold one toast too many.
- A slot taking its next toast from `slideOut.onStopped` still holds the old notification, so
  `nudge` and `slideIn` animate `x` at once (cosmetic).
- That Quickshell emits `closed` before freeing a notification is assumed (tested on stand-in
  objects only).
- The card's "dismiss" / "×" (`components/NotificationCard.qml` ~358) uses a `MouseArea`'s
  `containsMouse`, not `PointerArea`'s `lit`.

**Taildrop**
- A DELETE already sent to the daemon when an account switch starts cannot be called back.
- The transfers list (now in the side panel) may not be limited to the operator, as the old
  send line was (not re-checked).
- Incoming files are keyed by name only: two peers sending one name at once show one row.
- `fileOffers` is asked per file row on every tick of the files list; the cost grows with rows.
- `TaildropSendRow.qml` logs "Qt Quick Layouts: Detected recursive rearrange" on every build.
- `TaildropRules._unsafeCharacters` misses U+2028/U+2029: such a name shows on two lines in
  the received-files notification (low; Tailscale itself refuses such names; one regex range).

**Module test kit**
- Module suites cannot send Escape to a `SidePanel`; `ModuleTestKit.setSessionLocked`
  disturbs suites running alongside; a key helper or a per-frame lock would fix both.
- `ModuleTestKit` presses actions of progress notifications only (the module's suite presses a
  plain one's "Save in…" through its own `ScenarioHandle`); it should replace the module's
  `ScenarioHandle.qml` and `liveSuites.js` (per-suite program overrides, suites run alone or
  last).
- With Qt's own dialog "send files" sends one file per pick.

**Flaky tests** (each passed alone; rerun once alone before believing a failure)
- `TaildropLiveTest`: "two-devices: both sent" and "page-devices: both sent" time out under
  load; one unnamed check failed once during D7.
- `AnchorsTest`: the General page's -28-wide rows are fixed (it waits for layout); an earlier
  failure on a section's parts' order (U7a) may be another wait that measures too early.
- Lock bed: `restart-kill-locked` once on NixOS (keep `LOCKTEST_KEEP=1` artifacts); `harness`
  "the shell's environment can be read" once on NixOS (2026-11-20); `fallback` once (the PAM
  stand-in never answered); `modules-discovery` once saw the supervisor silent 44 s under load;
  `restart-crash-locked` hit a race in Quickshell 0.3.2's crash handler (accepted; upstream
  fix `pread`, `notes/upstream/quickshell-session-lock-unlock-notify.md` finding 5).
- QtTest's `'windowShown' of null` once; fixture windows may flake.
- `tests/ModulesTest.qml` (start guard, lines 268–301) asserts within a 300 ms timer: fails
  under load (3 checks, NixOS).
- The test tree's by-hand recipe (`tests/lock/README.md`) never run; `TestSeamsShapeTest`
  finds literal names only; O6 (lock tools from the trusted lookup) not built.

## Order of work

Steps 3, 4, 5, 6 and 10 are done (done.md); the API plan's closing slice (Z) is above.

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
2. Before the release (cut after step 8, the owner 2026-11-21):
   - [ ] `lockscreen.lockOnSleep` default off (`singletons/SettingsSchema.qml`, today `true`)
   - [ ] versioning rule corrected (`CHANGELOG.md` header, `singletons/Version.qml` comment)
   - [ ] cut a minor release (today 2.0.0), the module's 0.7.0 with it
7. Architecture clean-up per [plans/architecture-cleanup.md](plans/architecture-cleanup.md)
   (splits, hubs, test hooks, the module's read/clock performance, the network editor's
   save that can lose the kill-switch choice), alongside other steps where slices do not
   collide — open
8. Modules closed for now (a state of today, ended by step 15) — open: the trust model
   written down honestly (no isolation; review covers the project's own modules; for others
   the prompt's text is the only protection); Settings → Modules (enable, disable, reload,
   install, update, remove from a repository); the safe-mode banner
9. Lock — open: supervisor limit (3 restarts while locked, then stay locked, tell the user);
   lock-before-sleep conflict detection; screensaver and lock screen together checked
11. PAM configuration from the shell — open
12. Documentation per [plans/documentation.md](plans/documentation.md); architecture and API
    chapters — open
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

What the API work must leave possible for 13–15: [plans/api-next/versioning.md](plans/api-next/versioning.md) §11.

Later:
- Notification rules (the owner, 2026-11-20): properties given to notifications by rules
  ("from app X and containing text Y → property Z": stays, critical, hidden, its queue…).
- A mockup gallery (the owner, 2026-11-20): mockups kept as code, a mode that opens a panel
  listing them and shows the one picked, useful for tests too (today's are kept outside the
  repositories); visual regression tests built on them (a mockup's headless screenshot
  compared with an approved one).
- Taildrop's history of sends with "send again" (a file no longer there handled; the owner
  2026-11-20).
- pttd (dictation) as its own module in its own repository (was 11.24; protocol in
  [pttd-protocol.md](pttd-protocol.md)).
- Global default programs (the terminal among them).
- A NixOS option for modules (`programs.h2s-shell.modules`) and module signatures.
- A UI texts pass with translations, the owner reviewing the voice; documentation as a site
  with per-system tabs.
- Module order (load order, and the order of different modules' elements in one place — two
  things, both by module id until then).
- Modules' own elements published (public styles a theme can set, so libraries of elements
  can exist; building one's own for oneself is allowed now).

## Decisions

The owner's decisions live in [decisions.md](decisions.md); read the topic you work on there
before planning or briefing. New decisions are added there, not here.

## Backlog / later

- [ ] Two bar entries of one type and preset: the adopted "active" mark can land on the other
      cell than the popup sits over (rare)
- [ ] Tailscale module: the event stream is started outside `_run`, so one bus message is cut
      at the runner's default 1 MB (a very large netmap message)
- [ ] A VPN provider's id is matched against module ids without checking the module that
      registered it is that module (`VpnManager.register`); `VpnManager.ownExtrasOf` serves
      `rowExtras` for a module's provider too (unreachable for Tailscale)
- [ ] `components/ReorderList.qml` binds a bare array (`root._shown`) to `ListView.model` —
      against the Repeater-crash rule

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
