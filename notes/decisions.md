# Decisions

The owner's decisions for the shell and its modules, newest at the end of each topic.
Kept here, out of the tracker, so the tracker stays short; the tracker links here. A decision
that replaces an earlier one says so.

By the owner; 2026-11-17 unless dated. Where a later decision replaced an earlier one, only
the later stands here.

**Way of working**
- Larger work goes analysis → plan (owner approves) → implementation.
- Coding is done by strong models only; no weaker models for mechanical moves.
- Tests: one general set independent of the system, plus a set per system (NixOS, Arch). A
  developer runs the general set and their system's.
- Data migrations while the shell is in development (2026-11-19): before writing one, check
  whether the feature is in use (on both machines). Not in use → no migration. In use → ask
  the owner.
- Versioning: a settings migration may ship in a minor release, never in a patch. The pending
  release is a minor (the owner 2026-11-20: also with toasts following the sender's time).
- Documentation: English only; Markdown with "NixOS" and "Arch" subsections wherever the
  systems differ (a site with tabs maybe later); pages for system-only features where it makes
  sense; never one system without the other; nothing refers to or relies on the developers'
  own environments; screenshots are the owner's; docs verified for consistency at each major
  release, not on every change; `docs/` never links into `notes/`.

**Direction, modules and trust**
- Direction: the shell becomes a fairly small framework that defines the structure and the
  way of working; parts built in today can be split out into modules, some shipped with the
  shell. The shell provides the services, or abstractions for reaching them; a module adds the
  whole feature (popups, elements, widgets, settings pages). Every built-in feature is to be
  gone through and divided this way. The lock screen, password prompts and privileged runs
  stay in the framework. Shipped modules use only the public API, like anyone's: one class of
  modules; every feature split out proves the API.
- Order after the API round: the author guide, a module template and a module's tests
  runnable without a checkout of the shell; then the built-in features are divided, one first,
  as the proof; only then is the shell announced as open to module authors.
- Module authors: that every module is the owner's is true today, not an assumption to build
  on; the shell is built up to the point where others can write modules without problems.
- Trust: no isolation ("the shell must work and modules need access to its functions");
  running modules in a process of their own is not a later question. A module that does not
  come from the project is announced as such (a plain statement and a confirmation when a
  module not shipped is first enabled; shown when a user's copy replaces a shipped one), and
  is then not the project's responsibility. Review as a guard is for the project's own
  modules; for an outside module the password prompt's text (Module, Authorization, the
  command) is the only protection.
- (Temporary, until step 15.) Modules closed for now = the trust model written down honestly
  (a module runs in the shell's process, which also handles the lock screen's password and the
  polkit agent), Settings → Modules (enable, disable, reload, install, update, remove from a
  repository), the safe-mode banner. Later: NixOS option for modules, signatures.

**Module API**
- The module API is ours: a module never works around a gap; the API is extended first. It
  covers capabilities (running things, system state, privileges, places in the shell's views),
  not looks.
- The module API is agnostic (2026-11-19): not built for the Tailscale module; it gives
  modules as wide an access as it can. So network facts keep Docker/libvirt bridges
  (`kind: "bridge"`), the kinds and left-out types as built, `setsDns` = "has DNS servers of
  its own while up".
- Versioning: for now a minor version may tighten or remove things (nobody else uses the
  shell yet). This ends at the first release announced as open to module authors: from then a
  removal comes only with a major version, after being listed as deprecated for at least one
  release, announced in `CHANGELOG.md`'s "Module API" section and the author guide. Merging
  the closing slice only after the module is released is a one-off for today's one module.
- UI anchors: views are built from shared blocks (settings page, section, card, row, popup
  section) that register under a path derived from where they stand; a module names a path, a
  placement and its element. Placements: `before`, `after` (outside the block), `prepend`,
  `append` (inside, first and last). Addressable: settings pages and popup content; not the bar
  (the user places widgets there). One naming convention; the list of anchors pinned by a test
  and documented. Today's slots move onto anchors.
- A module may publish its own versioned API object for other modules (declared in the
  manifest; a dependent gets only that object). Reaching into another module or the host goes
  away.
- Dependencies between modules (2026-11-19): hard (today's `uses`: missing →
  `missing-module`) and soft (the module loads anyway, after the provider when it is there; its
  `uses` entry is null without it). A malformed entry fails the module; a function handed to a
  provider is the dependent's job; a failed provider stays failed until turned off and on.
- Order: by module id for now; a module's say in the load order and in the order of elements
  in one place comes later.
- Elements (replaces "only from public elements"): modules use public elements (`qs.api`)
  wherever possible and sensible and may build their own from QtQuick; every colour and type
  size from the theme's public tokens (`Api.theme`), never a literal; a module asks for a new
  public element when it is of general use. Only importing the shell's internal components is
  detected: listed as deprecated, then an error in the module's status. The token names are
  pinned by a test.
- Variants on public elements are meanings, not looks; never raw colours or sizes. A button's
  kind is `primary`, `secondary`, `danger`, `warning` or `success` (more may come); asking first
  goes with any kind; a danger button may act on the first click. A module's "Cancel" is
  `secondary`.
- Buttons with a tone (`danger`, `warning`, `success`) are bordered: at rest a border in the
  tone's colour, under the pointer or a finger the whole background in it — every such button
  in the shell, the Bluetooth popup's per-row "✕" and "Disconnect" included.
- Pills: three sizes, `s`, `m`, `l`, set by the theme and offered through the API (the shell's
  24 px pills became `s`, 22 px). Their text size always comes from the theme's tokens; a module
  may choose among the theme's sizes (small, body).
- Network cards: the place for a module's button is the shell's, of any kind, always above
  "Forget" / "Delete"; the module chooses its size (`m` is the default). An element that opens
  is the shell's `ExpandingRow`.
- A module's icon (2026-11-19; replaces the icon on closed cards and `setMark` / `clearMark`):
  a glyph of the icon font, an SVG or an image; it is the module's face in Settings → Modules.
  A module that adds something to a network shows it on that card itself, with its own element
  in a place the card offers on its name line (closed and open); the shell only bounds its size.
- File chooser for modules (2026-11-18/19): the platform theme's standard dialog, minimal; an
  empty title shows the module's name; a lock closing it answers `blocked: "locked"`, told
  apart from the user cancelling. No chooser of the shell's own now; file-manager integration
  later (backlog).

**Privileged runs and the password prompt**
- Privileged runs, 2026-11-18: the shell does not parse or judge a module's command (no lists
  of shells, launchers or interpreters, no declared program). The checks left (absolute
  existing program, printable words, a purpose, not while locked, one prompt at a time, the
  shell's timeout inside the trusted pkexec) catch mistakes and keep the prompt honest.
  Written in `docs/ARCHITECTURE.md` "Modules".
- No time window. The prompt says which module asks and what for: labels "Module" and
  "Authorization"; the real command hidden and shown on a click, a long one whole, scrolling.
  With another polkit agent the run goes ahead, with a shell notification naming module and
  purpose just before.
- A prompt open or waiting when the screen locks is cancelled as if dismissed; the user clicks
  again after unlocking. Only the password question is one at a time; with another polkit
  agent strictly one action at a time. A run with no password asked shows nothing; one log line
  names the module.

**Lock and PAM**
- `lockscreen.lockOnSleep` defaults to off. To investigate: detecting, independent of the
  system, that something else locks the screen, and telling the user.
- Lock supervisor: at most 3 restarts while locked; then the session stays locked, the user
  logs in on a TTY and starts the launcher by hand; the user is told what happened and how to
  look into it; documented.
- PAM: the order of password and fingerprint is the system's PAM stack, not the prompt's.
  Wanted: configuring PAM rules from the shell; needs its own analysis and plan.

**Views**
- An opened card ends as far under its last line as its first line is under the top.
- Contrast: a question in the confirm colour (dark green on the surface) and warning/success
  buttons under the pointer are left for the themes' rework.
- Two bar entries of one widget type (2026-11-19): a click on the second switches the popup to
  it, as hover does.
- The Wi-Fi settings page (2026-11-19): the Wi-Fi switch in the page's heading; no "Wi-Fi …
  Off" row.
- Network cards (2026-11-19): the main button, Edit and Forget in one row on the name line,
  also while closed; order main, Edit, Forget. When the row does not fit, it moves to its own
  line under the name, right-aligned, a question getting the card's width.
- No terminal setting of its own: a global "default programs" setting later.

**Notifications**
- A plain notification's body keeps its line breaks (the title stays one line) (2026-11-19).
- Progress notifications: a module updates one notification's progress instead of sending new
  ones (the spec's `value` hint and replacement; the shell is the notification server)
  (2026-11-19).
- The flow (2026-11-20, plans/notification-flow.md §7, §8.10): three toast queues (critical,
  staying, ordinary) with their own limits and badges; opening the centre hides only ordinary
  toasts; lock and screensaver never pause; "×" dismisses; a resident notification stays after
  any action ("Resident notification hide" makes it count); "Apps choose how long" off turns an
  app's "stay" into counting but not critical, resident or the shell's jobs; movable toasts on
  by default; every centre entry has a pin (a modal on screen); fullscreen "Don't show" keeps
  only critical toasts.

**Tailscale and Taildrop**
- Exit node: a per-network choice on the saved network's opened card (through an anchor), and
  a manual choice "for now" in the popup that overrides it. "Default" drops the override; the
  manual choice lives in memory only and ends at a shell or computer restart and at wake.
  With no per-network choice for the networks up, "Default" and a wake turn the exit node off;
  joining a network with its own choice keeps the "for now" pick; only a pick in the shell's
  chooser is "for now"; a network set to "No exit node" shows no mark on its card.
- Taildrop (2026-11-19): no fixed time limits on transfers; a list of transfers with progress,
  per file Skip and a forced start beside a stuck one; no progress shows "no progress for N
  min" and waits for the user. "The program could not be started." kept.
- Taildrop send from the popup (2026-11-19): everything stays in the popup — after picking, a
  row under the device names the file(s) with Send, then the send's progress there; the
  settings window does not open.
- Taildrop's settings page (2026-11-20): one way to send — files, devices (the pills), Send or
  Cancel; no per-device "Send file…" on the page (the popup keeps its own).
- Taildrop's words (D1, the owner 2026-11-20: kept for now): "Queued"; "Sending…" / "Saving…"
  for an unknown size; "Failed" without a reason; save reasons "Bad name", "Not fetched", "No
  free name"; "To laptop · 1 file". A file held back because the same name is already going to
  that device waits while the files behind it may start (confirmed).
- Taildrop off is soft: the module's switch only; `TS_DISABLE_TAILDROP` is not written,
  offered or documented (2026-11-20). "Web interface" is renamed to say this computer's
  settings are shared ("Share this computer's settings"); "Web console" stays for the button
  to Tailscale's site.
