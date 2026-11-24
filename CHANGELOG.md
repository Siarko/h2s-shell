# Changelog

Notable changes to the shell, newest first. Versions follow semantic versioning:
**major** for changes to behaviour people rely on, **minor** for features, **patch** for
fixes; a settings migration may ship in a minor release, never in a patch. The number lives
in `singletons/Version.qml`; each release is tagged `v<number>` in git.

The module API has its own number (`Api.version`, in each section's "Module API"): until the
first release announced as open to module authors, its minor version may tighten or remove
things; from then a removal comes only with a major, after being listed as deprecated for at
least one release.

Add an entry under **Unreleased** with each user-visible change; a release renames that
section to the new version and date.

## [Unreleased]

### Module API
The interface modules are written against (`qs.api`), versioned on its own
(`Api.version`; its reference is `api/Api.qml`).
- 1.41: a list or object inside the plain data the API hands out is a new frozen copy at
  each read (the routes in `Api.vpnsUp`'s rows, `Api.anchors`' placements,
  `Api.system.distribution`'s facts, `module.manifest`'s lists and objects, a list in an
  `Api.theme` group): a module that changes one changes only its own copy. So two reads are
  no longer the same object — `row.routes === row.routes` is false — and a write into
  `module.manifest`'s nested objects (`module.manifest.widgets[0].type = …`), which used to
  stay, is now ignored. A list handed out as a value (`Api.networks`, `Api.vpnsUp`,
  `Api.localNetworks`, `Api.slots`, `Api.anchors`) is shared by every module: copy it before
  changing it.
- 1.40: `Api.system.distribution`, frozen `{ ready, id, label, facts }`: which distribution
  the shell runs on (`"nixos"`, `"arch"`, `"generic"`; `""` while not known) and its static
  facts (where its programs, PAM files and polkit rules are, whether `/etc` is generated), a
  read-only copy. A module that behaves differently per system reads this instead of
  looking for `/etc/NIXOS` itself. In module test mode
  `ModuleTestKit.setDistribution(id)` names it.
- 1.40: `Api.system.distribution.facts.packages`: how the system gets a package the shell
  names to the user (`nerdFont`, `fprintd`, `pamU2f`), each `{ option, package, in }` as
  plain names — the option of its configuration on NixOS (`services.fprintd.enable`), the
  package on Arch (`fprintd`), `in` where a package goes (`fonts.packages`); `{}` for a
  system the shell has no distribution for. A frozen copy at each read.
- 1.39: `module.privileged.remembered`, frozen `{ kept, untilMs }`: while the shell's
  process holds a remembered administrator password, a run through
  `module.privileged.start` asks for none until `untilMs`; a new object when it changes and
  when it runs out. `PrivilegedMark` and `SwitchRow` take it as `remembered`: while kept, a
  mark that asks shows an open lock, dimmed, its tooltip the time left ("No password needed
  for 4 min"). In module test mode `ModuleTestKit.setRemembered(untilMs)` sets it.

### Added
- Settings → System → Authentication: "Sign-in rules" for sudo and administrator prompts
  (polkit) — what is in force as steps, rows of methods (fingerprint, security key,
  password, a raw PAM line) tried from the top with their control words and details, one list
  for both or one each, checks under each list, the file it would write. Arch: Apply tries
  the new rules first, then writes each file as administrator with a backup; Undo; a file
  changed outside the shell is shown and can be replaced. NixOS: the module's options, with
  Copy. Under it, "Unlocking the lock screen": switches for the fingerprint and the security
  key.
- NixOS: the module's `programs.h2s-shell.settingsFile = ./h2s-shell.json;` reads the
  shell's settings file, JSON whose keys are the module's options with a `version` (now 1):
  `idle.hibernateDelay`, `pam.rules`, `pam.sudo.rules`, `pam.polkit.rules`,
  `polkit.rememberAdmin.{enable,users,minutes}`. Each value is taken just below `mkDefault`, so
  the same option in the configuration wins, even at `mkDefault`; when the configuration sets
  any of the three PAM rule lists, none of the file's are taken (a warning); a wrong value (type, range, a hibernation delay that is no
  systemd time span, a PAM row with a field the rows do not have) or schema version stops
  the build with an assertion naming the key; an unknown key is a warning and is ignored.
  What was taken in and what is in force is published as `/etc/h2s-shell/settings.json`.
  Unset (the default), nothing is read and nothing published.
- NixOS: the module's `programs.h2s-shell.pam.rules` (sudo and polkit) — or
  `pam.sudo.rules` and `pam.polkit.rules`, one list per service — set sudo's and polkit's
  `auth` rules as an ordered list of rows: fingerprint (`timeout` 1–600 s and `tries`
  1–20, each -1 for no limit), security key (`pin`; the machine's
  `security.pam.u2f.settings` apply as they are, always with `cue`; a setting with a tab
  or a line break stops the build), password (`counted`), a raw line (`module`, `args`), and
  `{ method = "system"; }` for NixOS's own rules below them; without that row the list ends
  with closing lines that keep NixOS's own rules from being reached.
  `control` is PAM's word (`sufficient` by default; `optional` only on a raw row — a
  fingerprint, key or password row's result would be ignored). NixOS's own fingerprint and
  key rules are off for a service with rules. A list nobody could get in with, a required
  reader the machine does not have, both services without a password, a raw line that lets
  anyone in on its own (a module that asks for nothing, with no other row that must pass and
  still asks), an optional fingerprint, key or password row,
  or a module of another package named without its path stops the build with an assertion;
  a reader as the only way in, a store path written out (`"${pkgs.…}/lib/security/…"` is
  the way), a module from outside the store, a required raw line of a module the shell does
  not know without the `system` row (it lets in a user the module says it does not apply
  to), a raw line that asks for nothing beside a row that still asks, and a fingerprint with
  no time limit above a password (the password waits for the finger) are warnings. null (the default) leaves the service as NixOS makes it.
- Settings → System → Authentication: "Remember the password" — after the administrator
  password is typed for one of the shell's own root runs, the next ones pass without asking
  for "Remember for" minutes (1–60, default 5). One box says whether the rule is installed,
  how long the system keeps a password and where that comes from, and, while kept,
  "Remembered, 4 min left" with "Forget now"; it is also forgotten at lock and when the shell
  restarts. Arch: Install / Install again / Remove / Undo, one password prompt each, with
  backups in `/var/lib/h2s-shell/polkit-backup`; a file changed outside the shell is shown
  and replaced only through "Replace…", which names every file it touches. NixOS: the
  module's option, with Copy. The shell's prompt says "Remembered for N min" under the field
  for its own and its modules' runs while the rule is installed; "Try the prompt" says no
  prompt will show while a password is kept.
- NixOS: the module's `programs.h2s-shell.polkit.rememberAdmin = { enable; users; minutes; }`
  remembers the administrator password for the shell's own root runs, for the listed users:
  a polkit rule keeps a typed password for the shell's process; `minutes` (1–60, default 5)
  above polkit's 5 sets polkitd's `ExpirationSeconds` for the whole system, and polkit
  reloads when it changes.

### Changed
- A missing package is named as this system gets it, never as a command to type: the
  warning about a missing Nerd Font names Arch's package or NixOS's option, or the package
  for `fonts.packages` (and,
  on another system, the font's upstream name), and the lock screen's fingerprint and
  security key switches, while the computer lacks one, say what they need (fprintd or
  pam_u2f, as Arch's package or NixOS's option, and an enrolled finger or a registered key).
- `install.sh` runs the Arch installer, now `distributions/arch/install.sh`, on Arch and
  systems based on it (EndeavourOS, …); another system with pacman (and its
  `/etc/pacman.conf`) gets a warning and the same installer; NixOS and systems without
  pacman are told it does not support them, and nothing changes. The README's
  `curl … | bash` line and `install.sh --update` (from a checkout, on any system but NixOS)
  work as before.
- Only through the VPN: the blocking runs only the installed script, never the shell's own
  copy. Without it installed nothing switches and nothing asks for a password by itself;
  the page says the blocking needs its script. A password question raised by an automatic
  run of the installed script is closed at once; "Apply again" runs it on a click.
- Arch: "Password-free blocking" installs the script to /usr/local/libexec/h2s-vpn-lockdown
  and its polkit rule to /usr/share/polkit-1/rules.d (readable, so the page shows what is
  there), with Undo; a script or rule there not written by the shell is shown and replaced
  only after "Replace…" asks.
- Settings → When away → Hibernate: Apply of the system's delay keeps the file it replaces
  as a backup, and Undo puts it back. A delay set in another file is shown as "Set in
  <file>: <value>": one read after the shell's file wins and no Apply is offered; one read
  before it (your own sleep.conf) is overridden only after Apply asks; a hand-edited copy of
  the shell's own file is replaced only after Apply asks again ("Replace?"). On a
  distribution the shell does not know, no Apply: "Not supported on this distribution."
- Settings → System → Network → Overview, the connectivity check's address: on Arch, Save and
  Default keep the file they replace as a backup, Undo puts it back, and NetworkManager reads
  its configuration again after each. An address set in another of NetworkManager's files is
  shown as "Set in <file>: <address>": one read after the shell's file wins and no Save is
  offered; one read before it (NetworkManager.conf, a NixOS configuration's setting) is
  overridden only after Save or Write anyway asks; a hand-edited copy of the shell's own file
  is replaced or removed only after it asks again ("Replace?", "Remove?"). The distribution's
  packaged address (Arch's 20-connectivity.conf) counts as the default, not as set elsewhere.
  On a distribution the shell does not know, no Save: "Not supported on this distribution."
  An address of yours that the shell's file overrides is shown too ("Set in <file>:
  <address>; the shell's file overrides it"; Default puts yours back), and a notification says
  when the file was written but NetworkManager did not read it again. On NixOS, "Write anyway"
  with the field emptied says "Default" (it removes the shell's file).
- Settings → When away → Hibernate: a delay of yours that the shell's drop-in overrides is
  shown ("Set in <file>: <time>; the shell's file overrides it").
- Settings → System → Authentication, sign-in rules: on a distribution the shell does not
  know, the rules are not edited there (no Apply, no lists): "Not supported on this
  distribution." Arch and NixOS are as before.
- The machine's u2f settings are no longer changed: a security key row of
  `programs.h2s-shell.pam` keeps `nouserok`, `alwaysok`, `userpresence`, `interactive` and
  `pinverification` from `security.pam.u2f.settings` instead of stripping them or stopping
  the build. Where they let someone in without a key or a touch (`alwaysok`,
  `userpresence = 0`), or turn a row that must pass into one that no longer asks, the build
  warns (for a key row and for the lock screen), the sign-in rules page warns under the row
  (for an own key row and a raw pam_u2f line, from `/etc/security/pam_u2f.conf` too on
  Arch), and the lock screen's security key switch says so. The lock screen alone leaves
  `interactive` out (it cannot answer the Enter prompt) and says so on its switch; a
  `security.pam.u2f.settings.conf` file, or a raw pam_u2f row's own `conf=`, is a warning:
  its options are not checked.
- The shell's own runs as administrator (the sign-in rules' Apply, the Hibernate section's
  Apply, "Remember the password"'s Install / Remove / Undo) run inside the shell's
  `timeout`, as modules' runs do: ended after 5 minutes at most, and covered by a
  remembered password.
- NixOS: `programs.h2s-shell.polkit.passwordFirst` is deprecated (a warning when set): a
  password row above the fingerprint row in `programs.h2s-shell.pam.rules` does the same.
  Without polkit rules it works as before; set to true beside them, it stops the build.

### Fixed
- Buttons can be used from the keyboard: Tab reaches them (a ring shows which), Space or
  Enter presses one, and Escape cancels a button's question; an unavailable button is passed
  over. Tab stays inside an open side panel and inside a toast, and a Settings page scrolls to
  the control Tab reaches.
- A module's popup panel that declares `availableHeight` or `popupAnimating` readonly no
  longer stops the popup giving it the other one: it keeps its own value, and the module's
  status names the panel and the property.
- The Arch installer: a checkout of a fork, or of another repository whose address contains
  this one's name, is no longer taken for an install ("Already installed"), but left alone
  with where it comes from (never its user or password); this repository is recognised in
  any spelling of GitHub's address, but not under an SSH host alias, for which it says how
  to go on. What is in the target is checked before anything is installed: a folder without
  `shell.qml` that is not empty, one that cannot be read, a file or a `shell.qml` link to
  nothing is left alone with the installer's own message instead of `git clone`'s error.
  Without a terminal or without `sudo` it stops with its own message naming what is
  missing; run as root it runs `pacman` without `sudo`; packages that were not installed
  are said plainly; an `fc-list` that fails no longer ends the install silently.
- A number setting edited by hand outside its range is used at the nearest bound, a
  fraction in a whole-number setting rounded; one that is not a number — a number written as
  text ("30") included — falls back to the default. The config file keeps what was written;
  a banner under the bar names the settings, the log says so once, and Settings shows the
  value in use with a note.
- A screensaver that came late (a profile switched while you were away, the computer slow
  to check what keeps the screen on) went dark at once where the screen was due off by
  then: the screen now turns off only once the screensaver has faded in on it.
- A run as administrator that ignored the end of its time limit and had to be killed is
  told as "It did not end within <limit> s", not with its last output line; one that wrote
  more than 1 MB of errors before failing is told with its last line, not an early one.
- Settings pages that read the system read it again each time the window is shown, not only
  when the page is first built: the sign-in rules and the lock screen's switches (a security
  key registered meanwhile), "Remember the password", what sleep logind allows, the
  installed VPN plugins, the installed modules and the icon themes.
- The plus before "Add a row", "Add widget", "Add source" and "Add" is the icon font's: it
  showed as an empty box where no font had the full-width plus. The theme drafts' pencil, the
  bar section editor's cog, the power menu's restart and the drag handles are the icon
  font's too, not drawn from another font.
- The network pages watch the connection state and scan for Wi-Fi networks only while the
  Settings window shows them, not while it is hidden.

## [2.1.0] - 2026-11-23

A minor release, though it changes two things people rely on: toasts now follow the
display time an app asks for, which changes how long some toasts show (apps that leave it to
the shell, most, see no change, and Settings → Notifications → "Apps choose how long", off,
keeps the old behaviour; below, under Added); and the screen no longer locks before the
computer sleeps unless Settings → When away → "Lock before the computer sleeps" is on
(below, under Changed).

### Module API
The interface modules are written against (`qs.api`), versioned on its own
(`Api.version`; its reference is `api/Api.qml`).
- 1.38: `SectionTitle` takes the look of the core's sections: a size larger
  (`fontSizeMedium`) in the primary text colour, with room and a line above it across the
  column it stands in; `divider` (default true) — false leaves the line out, for the first
  section under a page's heading. `Api.theme.settings` has the three gaps it uses:
  `sectionGap` (above the line), `sectionLineGap` (line to title) and `sectionTitleGap`
  (under the title). `ExpandingRow` slides open and shut (the theme's expand duration and
  curve; at once with reduced motion); its child is destroyed once the row has slid shut.
- 1.37: module.json's `backup`, a list of paths inside the module's data directory
  (`["notes.db", "accounts"]`: relative, no `..`, at most 32) that belong in its
  configuration backups; the data directory itself never goes in one. A path that is not
  such a path is dropped with a warning. The id `idle` is reserved: it is the core's IPC
  target for idleness and the screensaver. CommandRunner's `_runner`, the internal runner it
  held, is removed: it was internal, and through it a module could change what the runner
  refuses and read its runs. A run's handle carries no state of the runner's either.
- 1.36: module.json's `privileged` block, `{ "why": "…", "programs": [names] }`: a module
  says what it runs as administrator and why (`why` plain text on one line, at most 200
  characters; `programs` names among its `requires.programs` and `optionalPrograms`); a
  malformed block fails the module. The shell refuses `module.privileged.start` from a
  module without the block, without the user's approval of it, or with an `argv[0]` that is
  not the path `module.programs` has for a declared, trusted program — before any prompt,
  nothing run, `blocked: "undeclared"`, the reason among the module's status errors; and
  `PrivilegedAction` the same way (its command[0] for argv[0]), and whenever its call cannot
  be traced to a module's code. This holds for
  modules written for any API: one that runs anything as administrator must add the block.
  A guard against mistakes and a statement for the user, not a sandbox: a module runs in
  the shell's process and can start programs by other means. `author` (plain text on one
  line, at most 100 characters, malformed fails the module); a `uses` entry's `source`
  (`"<repository address>#<ref>"`, where to get a missing provider; not an address: an
  error, the entry kept without it). Tightened with it: the handle's `host` is gone
  (undefined); `Api.moduleAt(url)` answers only for the calling module's own directory and
  `Api.module(id)` only with the caller's own handle (another module: null);
  `module.privileged.start` and `PrivilegedAction` are refused for a call whose stack names
  another module's directory too, or none; `PrivilegedAction`'s `elevate` must be the one
  word `"pkexec"` (module test mode: its stand-in, one word) — any other words are refused
  before anything runs. `StatusPill`'s `expandable` (default true): false, a click neither
  expands the pill nor reaches what it stands on; the parts' tips still show on hover. The
  id `modules_installed` is reserved: it is the core's Settings → Modules page.
- 1.35: `ProgressBar`'s `wave` (default false): the owner says the bar is moving now, and
  bands of light pass through its filled part, a new one every theme duration
  `progressWave` (300 ms by default), each crossing in `progressWaveTravel` (1200 ms); none
  while the bar is full, of unknown length or hidden, or with reduced motion. `StatusPill`, a pill that sums up a state: `icon` (a glyph of the shell's icon
  font), `label` (one line), `kind` `"normal"` (the default: the icon in the accent, the
  label in the text colour), `"muted"`, `"success"`, `"warning"` or `"danger"`; `parts`
  `[{ icon, text, kind, tip, line }]`, after the label, each an icon and a short text in its
  kind's colour with its tip over it on hover; `expanded` (a click flips it while there are
  parts, the owner may set it): the parts one per line under a rule, each its icon and
  `line` (empty: the tip, or the text) in its colour; `toggled(expanded)`. Texts plain, one
  line, cut past 80 characters; past 12 parts the rest are dropped and an unknown kind
  shows as `"normal"`, each logged once. It fills no width.
- 1.34: `SidePanel`, a panel sliding in from the right over a module's settings page, the
  page dimmed beside it: `open` (the owner sets it true; the panel sets it false when it
  closes itself), `title` (one line, plain), `size` `"s"`, `"m"` (the default) or `"l"`
  (the theme's widths, at most 90 % of the page area; another word shows as `"m"`, logged
  once), `closed(reason)` — `"close"` (its Close button), `"outside"` (a click on the dimmed
  page), `"escape"` (Escape closes a dropdown's list open inside it first), `"replaced"`
  (another SidePanel opened), `"page"` (the page changed, the window closed, the module
  went away; run while the page is torn down, other items of it may be gone), `"lock"`
  (the session locked); the owner setting `open` false closes it without a reason. Its one child is its content, built when it opens, destroyed once it
  has closed, laid out at the panel's inner width and scrolled below a fixed title line.
  One is open per page; outside a module's settings page, or while the session is locked,
  it does not open (`open` goes back to false, logged once); it takes no room where it is
  written. In module test mode `ModuleTestKit.pageFrame` is the settings window's page
  frame for a suite's own window, and `ModuleTestKit.setSessionLocked` closes an open
  panel. `SectionTitle` and `Heading` take children: controls at the right end of the
  title's line (a switch for the section, its buttons); without children they are as
  before.
- 1.33: two command runner run options. `endWithShell` (default false): the command ends
  with the shell (a crash, a restart) even without a time limit — started behind
  util-linux's `setpriv --pdeathsig KILL` where that was found, after the shell's look-up
  of it; such a run that cannot start is `failedToStart`, its code setpriv's 127 (or 126),
  setpriv's message in `stderr`. Runs without it are started as before. A privileged run
  ignores it. `outputAfterCancel` (default false): after `cancel()` the lines the command
  still prints are handed to the callbacks and kept in the result, which says `cancelled`.
  Progress notifications: `module.notify(summary, options)` with
  `options.progress` (a number, 0–100, or -1 for a run of unknown length) returns a handle
  — `open`, `state` (`"starting"`, `"running"`, `"done"`, `"failed"`, `"cancelled"`,
  `"closed"`, `"unknown"`), `update({ summary, body, progress, actions, state, announce })`
  (an end state ends the job; `announce: true` brings its toast back once), `close()` —
  else `null` as before (`Api.notify` refuses a progress: `null`, nothing shown, as it has
  no module to close it); `options.toast` `"brief"` (the default, also for any other value)
  or `"whileRunning"` (the toast stays while the job runs); actions stay after a click;
  `onDismissed` runs once when the user closes it; urgency `critical` is taken as `normal`
  and the module's name is the app name, whatever `options.appName` says (a plain
  notification keeps taking `options.appName`). A module's open handles are closed when
  it is turned off; while it is off, `module.notify` with a progress shows nothing. Every
  hint key starting with `x-qs-` is dropped from a module's notification, plain ones too.
  `options.expireTime` is now followed by the shell's toasts (0 stays until closed) unless
  the user turned that off. Module test mode records each show, update and close of a
  progress notification, and `ModuleTestKit.dismissNotification(handle)` and
  `pressNotificationAction(handle, actionId)` act as the user.
- 1.32: the network popup's rows offer a name-line place, as the network cards do:
  `popup.network.wifi.row.title` (each Wi-Fi network in range, closed and open) and
  `popup.network.connections.wired.row.title` (the wired row), `append`, any module's; an
  element there is as tall as the name's line, all of them a quarter of the row at most, the
  name cut first. Context `{ networkId, name, kind, active }` as the cards give it, and on
  a Wi-Fi row `ssid`, the SSID scanned; a Wi-Fi network not saved has `networkId` `""` and
  its SSID as `name`, the wired row with no profile up `networkId` and `name` `""`. The
  saved Wi-Fi networks' cards give `ssid` in their context too. Names in a network context
  lose bidi override characters. The public `Pill` takes a `textSize`: `"small"`
  (the default, as before) or `"body"`, the theme's type sizes.
- 1.31: two public elements — `ProgressBar` (`value` 0 to 1, below 0 a run of unknown
  length; `kind` `normal`, `success`, `warning`, `danger`) and `HoverTip` (a plain-text
  tooltip over its `target`, by default the item it is written in, taking no room); the
  theme's new `progress` group (`thickness`, `radius`; Settings → Appearance → Controls) is
  offered as `Api.theme.progress`.
- 1.30: soft dependencies between modules — a `uses` entry may be
  `{ "version": "1.2", "optional": true }`: the module loads with or without that provider,
  after it when it is there, and `module.uses.<id>` is null without it (a provider there that
  does not fit is a warning). The provider coming or going turns the module's main off and on
  again, a new main that has lost what the old one held, and with it every main that uses it,
  which goes before it (only the mains given its object); a module with views only is not
  turned off when the provider comes or goes, its views get the new `module.uses` — while the
  provider is pending (restarting, starting) it is pending too, its views gone until the
  provider is back. A provider pending whose manifest does not fit is not waited for. A cycle closed by a soft use is broken, not an error. `{ "version": … }` alone, like
  the plain string, stays hard. The file chooser: no `title` shows the module's name; a lock
  that closes an open chooser answers `blocked: "locked"` (was `cancelled`), so a module can
  tell it from the user cancelling.
- 1.29: a card's buttons (`….card.actions`) stand in one row on the card's name line, closed
  and open: the card's main button, its own ("Settings…", "Edit" — was "Edit connection…"),
  the modules' buttons, then "Forget" / "Delete". The region `actions` is now built while the
  card is closed too, as long as the card is (1.25: built only while the card is open): a
  module's button there is made when the card is, and its startup code runs for every card
  of the place, open or not. Each button 6 apart, centred on its line, at most a third of the
  card. The row stays on the name's line while it fits beside a few characters of the name
  and the name line's elements; else it moves to a line of its own under the name,
  right-aligned, and wider than the card the main button takes that line alone, the rest
  under it; the card's own buttons keep their room, the modules' buttons beyond a line's
  room are cut on the right. The VPN cards' name line is a place:
  `settings.network_vpn.vpns.card.title` (`append`, any module's, whatever the VPN's provider;
  context as the card's `settings`). On a name line an element made with no `implicitWidth`
  and a width of its own (a `Rectangle { width: 16 }`) keeps that width instead of standing
  at no width; any other follows its `implicitWidth`. Elsewhere (a card's `before`, `after`
  and `settings`, popup rows, page sections) an element is as wide as its place, one anchored
  to its parent's sides too.
- 1.28: a plain notification's body (`format: "plain"`) keeps its line breaks — CR and CRLF
  become one, at most 20 lines, the last kept one ending in "…"; the summary stays one line.
  A VPN provider's `failed(entryId, what, reason)` is sent as such a plain notification: a
  provider need not clean its texts of markup.
  A module's button in a card's `actions` keeps the size it sets; `m` (the card's own buttons')
  is only the default, for a button that sets none — the public `SmallButton`'s new
  `defaultSize`, which a place gives and `size` follows until the button sets it.
  A card's name's line is a place: `settings.network_wifi.saved.card.title` and
  `settings.network_ethernet.profiles.card.title` (`append`, closed and open, after the name;
  context as the card's `settings`) — a module shows there what it adds to that network, with
  any element on the theme's tokens. Each element is given the line's height and cut to it,
  they stand side by side 4 apart in module id order, at most a quarter of the card all
  together (cut on the right); the name is cut first, and they never cover the card's own
  parts. A card's region may now be `title` too (`<card>.title`). Removed before any release:
  1.27's marks — `module.setMark`, `module.clearMark` and the anchor rows' `marks` (and the
  `settings.network_wifi.saved.card` and `settings.network_ethernet.profiles.card` rows that
  took only marks); a module's icon is its face in Settings → Modules, not on cards.
- 1.27 (its marks removed in 1.28, before any release): the mark on a card — `module.setMark(path, itemId, label)` and
  `module.clearMark(path, itemId)`: the card of an item shows the module's icon at the end of its
  name's line, closed and open, after the name (cut first), with "<module's name>: <label>" as
  its tooltip and accessible name (plain text, one line, control and format characters dropped,
  40 characters). The places that take marks are `settings.network_wifi.saved.card` and
  `settings.network_ethernet.profiles.card` (`Api.anchors`' `marks`; they take no element), the
  item being the card's `networkId`. A card shows the first three modules' marks, in module id
  order; a mark does nothing on a click. `setMark` → false, with a warning in the module's status
  (one line per kind of refusal, with how often), for a path that takes no marks, an id or label
  that is no text, or a module's 201st mark on a path; false while the module is off. The shell does not store marks: a module going off takes its marks with it, and sets
  them again when it starts. A card's `before` and `after` hosts add their gap only for an
  element built and shown (one that failed takes no room).
- 1.26: a module's icon — the manifest's `icon`: one glyph of the shell's icon font
  (`{ "glyph": "…" }`, a private-use character, not a lock or no-entry sign; drawn in its
  place's text colour), an SVG file (`{ "svg": "icon.svg" }`,
  painted in its place's text colour, or in its own colours with `"colors": "own"`) or a PNG or
  WebP picture (`{ "image": "icon.png" }`, in its own colours). A file lies inside the module's
  directory and passes the file check (at most 64 KiB for an SVG, 256 KiB for a picture). Its
  content is read only to refuse what the renderer would follow out of the file — an SVG with
  any external reference (`<image>`, an `href` or `url(` not starting with `#`, a document type,
  a style sheet, `<script>`, `<foreignObject>`), a picture whose first bytes are not its name's
  type (PNG, WebP). A wrong icon, or one whose file cannot be drawn, is an error in the
  module's status and no icon; with none the shell shows the first letter of the module's
  name. The handle's new read-only `icon` says what the shell draws:
  `{ kind, glyph, url, colors }`, or null.
- 1.25: a card's buttons — `settings.network_vpn.vpns.card.actions` (own-provider),
  `settings.network_wifi.saved.card.actions` and `settings.network_ethernet.profiles.card.actions`,
  `append`: a button among the opened card's buttons, under the card's own, above "Forget" /
  "Delete" (which stays last), built while the card is open, with the card's context. They take
  the public `SmallButton` only, marked by its new read-only `apiElement`: another element is
  not shown and is an error in the module's status. Each button stands at its own width on the
  stack's right edge, at most a third of the card wide (a longer label is cut), in size `m`. A
  `SmallButton` that asks, given less than its width, now takes it and cuts its label or
  question. A saved Wi-Fi network's card is a place only once its details are read (as
  `Api.networks` lists it).
- 1.24: the saved networks' places — `settings.network_wifi.saved.card.settings` and
  `settings.network_ethernet.profiles.card.settings`, `append`: an element in the opened card
  of each saved Wi-Fi network on Settings → System → Network → Wi-Fi and of each wired profile
  on its Ethernet page, under the page's rows, built while the card is open (not on a
  hotspot's card). Their context is the network as `Api.networks` names it:
  `{ networkId, name, kind, active }`.
- 1.23: the VPN places, own-provider (only the elements of the module that is the VPN's
  provider) — `popup.network.connections.vpn.row`, `after`: an element under the row of each
  of the provider's VPNs in the network popup; `settings.network_vpn.vpns.card.settings`,
  `prepend`: an element in the opened card of each of them on Settings → System → Network →
  VPN, above the card's own rows, built while the card is open. Their context is the VPN's
  `{ vpnId, entryId, vpn, provider, otherVpnsUp, otherVpns }`. The slots `network.vpn.row` and
  `network.vpn.card` are read as them (listed in the module's `deprecations`; the card's
  context still has `open: true`), where they showed before.
- 1.22: the popups' places — `popup.network.connections`, `append`: an element in the network
  popup under the VPN, Ethernet and Wi-Fi parts, above the divider over the network list, its
  context `{ wifiEnabled, wifiConnected, ethernetConnected }`; `popup.notifications`,
  `prepend`: an element in the notifications popup under its header, above the list, its
  context `{ count }`. The slots `network.popup.sections` and `notifications.popup.top` are
  read as them (listed in the module's `deprecations`), where they showed before.
- 1.21: the first place — `settings.general`, `append`: an element at the end of Settings →
  Behaviour → General, its context `{ editIndex }` (the profile being edited). The slot
  `settings.general.bottom` is read as it (listed in the module's `deprecations`), where it
  showed before.
- 1.20: anchors — the manifest's `"anchors": [{ "at", "place", "component" }]` puts a module's
  element at a place in the shell's views: `at` a path, `<surface>.<view>[.<block>]…`
  (`settings` or `popup`, a page's id or a popup's key, the names of the blocks around it),
  `place` one of `before`, `after` (next to the block), `prepend`, `append` (first and last
  inside it). The element gets its handle as `module` and `context` (`{ anchor, placement, …}`)
  as a slot's does; several modules at one place by module id. `Api.anchors` lists the places
  offered — none yet: the shell's views get them one by one. A place not offered, or a
  placement it does not take, is an error in the module's status; the rest of the module
  loads. On a VPN provider's card or row, a place shows only the elements of the module that
  is that provider. A slot whose view is built from anchor blocks is read as its anchor (its
  context keeps `slot` and what the slot gave) and listed in the module's `deprecations`.
- 1.19: reach closed, the old ways listed — `Api.moduleStatus(id)` gives another module's
  plain state, frozen `{ id, name, version, state, active }` (null for no such module).
  `Api.module(id)` and the handle's `host` still work and are listed in the module's
  `deprecations` where its code uses them (QML and JavaScript files; comments and strings do
  not count); both go with the shell's next tightening. Importing `qs.singletons` (and below)
  or a directory outside the module's own is now an error in its status instead of a warning,
  in a JavaScript file's `.import` too; the module still loads. The import scan reads a
  module's JavaScript files as well as its QML. A module turned off and on again before its old main is gone waits for it, so the
  old main reads its own `module.uses` to the end; a dependent's main deleted by something
  other than the shell no longer keeps its provider waiting.
- 1.18: a module's API for other modules — `"exports": { "version": "1.0" }` in a provider's
  manifest offers its main's `exports` property (a plain `QtObject`) to other modules;
  `"uses": { "<id>": "1.0" }` in a dependent's (same major, the provider's minor at least
  the one asked for; all required) gives it `module.uses.<id>`, that object and nothing else
  of the provider. A dependent loads after its providers and goes before them: a provider
  turned off, failing or reloaded turns it off first, and it comes back after; the provider's
  main is destroyed only once the dependent's is gone, and `module.uses` stays the same
  object from the dependent's start until its next, so its main and views read it while they
  go. A handle as `exports` is refused; `exports` or `uses` in a manifest asking for an API
  below 1.18 is a warning. A new state, `missing-module`, with the reason ("needs module
  tailscale 1.0: turned off", "not installed", "failed", "exports no API", "has 0.9", "gives
  no exports object"); a cycle of `uses` fails each module in it, the cycle named.
- 1.17: a file chooser — `module.chooseFiles({ mode, title, startDirectory }, done)` on the
  handle (`mode` `"open"`, `"openMany"` or `"folder"`; `done` gets frozen `{ paths, cancelled,
  blocked, error }`, absolute paths): the system's dialog, hosted by the shell so a popup can
  ask and close, one at a time for the whole shell (`blocked: "busy"`), refused while the
  session is locked (`blocked: "locked"`) and closed by a lock (`cancelled`), closed with no
  answer when the module is turned off or the shell reloads. In module test mode no dialog
  opens: the calls are recorded and answered by the module's own suite
  (`ModuleTestKit.chooserCalls`, `chooserOpen`, `answerChooser(moduleId, paths)`,
  `cancelChooser(moduleId)`, `setChooserLocked`).
- 1.16: network facts — `Api.networksReady` (the profiles and every Wi-Fi profile's details
  read; a failed reading of either leaves it false), `Api.networks` lists a Wi-Fi network only
  once its details are read (a hotspot no longer shows for a moment), `Api.vpnsUp` rows gain
  `fullTunnel` (all traffic of IPv4 or IPv6, its default route or the two halves), `setsDns`
  and `routes` (each `null` where not known, never `false` for "not read": while a VPN is
  still activating, WireGuard with peer-routes off, more than 256 routes; a `VpnProvider`
  entry may report them), `Api.localNetworks` (frozen `{ device, kind, family, address,
  network }`: global addresses only, no deprecated IPv6 privacy address, `network` null for a
  /32 or /128, none on a VPN's, tun, WireGuard or provider device but a Wi-Fi or Ethernet one
  an IPsec VPN runs on, less its addresses) with `Api.localNetworksReady`, and the VPN slots'
  context `otherVpns` (the other VPNs up as `Api.vpnsUp` rows) beside `otherVpnsUp`. In module
  test mode they are `ModuleTestKit.setNetworks`' facts, nothing of NetworkManager read.
- 1.15: a module's shared object and what its popup panel is given — `module.main` (the
  object made from the manifest's `main` while the module is active, set before its
  widgets, popups and pages are built, null while it is off, a new object when it is turned
  on again), and a popup panel's `opener` (the bar widget that opened it, frozen
  `{ widgetType, preset, edge, byTouch }`, so two bar entries on different presets each
  see their own), given when the panel declares `property var opener` (a readonly one or
  another type is not, and its status warns). `availableHeight`, `fitsShownHeight`
  and `popupAnimating`, given before without a word, are now part of the API.
- 1.14: `module.privileged.start`'s `options.environment`, in module test mode only — the
  variables (CommandRunner's shape, read once into a copy) reach the stand-in pkexec and the
  command it runs, so a module's suites can give each scenario its own stand-in state.
  Outside test mode a run given an environment is refused with an `error`, nothing run.
- 1.13: system facts and a data directory — `Api.system` (`ready`, `userName`, `uid`,
  `hostName`, `home`, `configHome`, `dataHome`, `runtimeDirectory`, `downloadDirectory`
  from `user-dirs.dirs` read as text, `readIpForwarding()` → `{ ipv4, ipv6 }`,
  `refresh()`; a fact that could not be read is `""` or `null`, never a guess) and
  `module.dataDirectory` (`<dataHome>/h2s-shell/module-data/<id>`, made 700 by the shell
  before the module loads, every folder from the data home down checked; `""` with a
  warning in the status when it cannot be made safely). Nothing in it may be run as root.
  In module test mode `Api.system` is `ModuleTestKit.setSystem`'s made-up facts and the
  data directory lies in a private temporary home (`ModuleTestKit.dataHome`); the facts
  are reset before each suite and by `clearRecords()`.
- 1.12: helpers — `Api.format` (`bytes(n)`, now up to terabytes, `rate(n)`, `ago(ms,
  nowMs)` in milliseconds), `Api.address` (`isIpv4`, `isIpv6`, `isIp`, `parseCidr`,
  `contains`, `overlap`, `redact`: the shell's one reader of addresses, which its network
  settings use too), `Api.minuteNow` (the start of the current minute, in ms, changing on
  the minute), `module.log(level, text, key)` (a line prefixed "[<id>]", on one line; with
  a key written only when the key's text changed) and the notification option
  `format: "plain"` for `Api.notify` and `module.notify` (summary and body on one line,
  control characters dropped, capped at 200 and 1000 characters, the body's `&`, `<`, `>`
  shown as written). `ModuleTestKit` gains `setNow(ms)` for `Api.minuteNow`, and
  `notified` entries a `format`. `redact` keeps what is around an address (a port, a
  label, brackets: `[address]:443`) and leaves names with `::` in code alone; `module.log`
  writes the same text again at another level, and a debug line not written (debug off)
  is not remembered for its key; format "plain" drops format characters too (a
  right-to-left override, a zero-width joiner); a module's notification cannot take the
  shell's own category `x-qs-shell` (dropped, as an option or a hint). The clock
  `setNow` sets is reset before each suite and by `clearRecords()`, and
  `tests/run-modules.sh` fails a run that never said how many suites it would run.
- 1.11: running as administrator through the handle — `module.privileged.start(argv,
  options)` runs a command (argv[0] an absolute path) as root through pkexec, with
  `what` (a few words saying what it does) and `timeoutMs` (1 s to 1 h) required, output as
  it comes and one frozen answer (`dismissed`, `refused`, `notFound`, `timedOut`,
  `cancelled`, `blocked`); `module.privileged.available` and `unavailableReason`. The
  shell's own `timeout` runs inside pkexec, so the command ends at its limit even when the
  shell cannot stop it. `argv` must be a real array of strings and is read once, as are
  the options. Refused before pkexec runs: a word with a control, format or line separator
  character (`unprintable`), an empty `what` (`no-purpose`), the session locked
  (`locked`); argv[0] not an absolute path or not an executable file is `notFound`. One queue for the whole shell, one password question at a time; runs waiting
  when the session locks end dismissed; a module turned off loses its runs, quietly.
  `PrivilegedAction` runs through the same queue (a run still waiting at a lock answers
  `dismissed` with `blocked: "locked"`), and its default `elevate: ["pkexec"]` is the
  shell's trusted setuid pkexec, never one found first on `PATH`. Every command runner
  reads a command once: what is checked is what runs. In test mode only the module's
  `<testPrograms>/pkexec` is used; `ModuleTestKit` gains `setPolkitAgent`,
  `setPolkitRequest`, `setSessionLocked`, `privilegedIdle`, and for the prompt's lines
  `setPolkitRequest(true, { command })` (pkexec's request for those words, its message
  written by the kit as pkexec writes it), `pkexecMessage(words)`, `polkitRequestOpen` and
  `polkitAnnouncement`.
  Fixes to the public elements and the module checks: `SmallButton`'s `asking` holds
  whichever of `asking` and `confirm` is declared first, and a binding on it keeps
  following the owner's value; a label, a button's question, a pill's text and a
  dropdown's option labels and placeholder a module hands over are one line, cut at 80
  characters with "…"; a dropdown option's other fields (an undocumented `color` among
  them) are dropped; `checked` is documented as shown only on a secondary button. The
  import check reads an import on the line of the first "{" (`import qs.singletons; Item {`),
  and the import warnings and deprecations cover every QML file under a module's
  directory (subdirectories, files only a Loader builds), not only the ones it names —
  up to 100 files, 8 directories deep, after every module's named files (so a slow scan
  never fails another module); the files it left out or could not read are one warning,
  "imports not checked in N files", and import warnings are capped at 5 per file and 50
  per module.
- 1.10: module test mode — on only under the shell's test entry points (`tests/run-modules.sh`,
  a test tree), never from a variable alone and never by a module, and told by the new
  read-only `Api.testMode`.
  The manifest's new `testPrograms` (a directory inside the module) is where a module's
  programs come from in test mode (`module.programs`: the file there, `trusted`, reason
  "test stand-in"; a name it does not hold, or a link that leads out of the module, is not
  found, never taken from PATH); outside test mode it is ignored. In test mode
  `Api.openUrl` and the notifications record the call and open or send nothing, and no
  command a module starts runs a pkexec other than a module's `<testPrograms>/pkexec`,
  wherever in the command it stands (`PrivilegedAction`'s `elevate` must be that stand-in).
  A module written for an API below 1.10 may still put its own stand-in, wherever it lies,
  into `elevate` — never the real pkexec — until slice Z; its `deprecations` say so.
  `qs.tests` gains `ModuleTestKit` for a module's suites: `testMode`, `setEnabled`,
  `status`, `widgetEntries`, `opened`, `notified`, `clearRecords`.
  Tightened: in test mode a module's suite that ran a pkexec of its own choosing, or a
  `PrivilegedAction` with another `elevate`, is refused.
- 1.9: a module's programs, judged — the manifest's new `optionalPrograms` (looked up like
  `requires.programs`; a missing one does not stop the module) and, on the handle,
  `programs` (per name the path found on PATH, `""` when none, `trusted` — only root can
  change what runs: the path walked as the kernel resolves it, every directory passed, the
  directory holding each link met and the real file root's and writable by no one else; a
  Nix store that is root's and the user cannot write to counts as root's — and
  a `reason`), `programsReady` and `recheckPrograms()` (at most every 2 s; also after the
  machine wakes). The command runner takes `timeout` and `setpriv` from PATH now, only
  trusted ones, instead of two fixed system directories.
- 1.8: `CommandRunner` — `start(argv, options)` runs a command (a list of words, no shell)
  and returns a handle (`running`, `cancel()`); any number at once, `cancelAll()`, `running`,
  `environment`. Each run has a time limit (`timeoutMs`, 30 s unless given, 0 for none; kept
  by coreutils' `timeout` from a system directory and by the shell's own timer; TERM, then
  KILL after `killAfterMs`), its output line by line as it comes (`onLine`, `onStdout`, `onStderr`) and
  one answer, `done(result)`: `ok`, `code`, `stdout`, `stderr` (kept up to `maxOutputBytes`,
  else `truncated`), `timedOut`, `cancelled`, `failedToStart`, `durationMs`, `error`. When
  the runner is destroyed its runs are ended and nothing is called. `CommandAction` and
  `CommandQuery` are run by it and keep what they promise; a `CommandAction` whose program
  cannot start is now answered (`ok` false, `code` -1) instead of never.
- 1.7: the base types, in `qs.api` — `PopupWidget`, `BarText`, `BarRow`, `PointerArea` and
  `VpnProvider`: the shell's own types, with the names a module may rely on pinned. With them
  `qs.api` has everything a module took from `qs.components`, and **`import qs.components` is
  deprecated**: a module that still imports it loads as before, and its status
  (`modules list`, `deprecations`) lists the import with the number of files.
- 1.6: rows and texts — `SettingsRow` (`label`, `hint`, `value`; its children are the
  controls on the right), `ExpandingRow` (`label`, `hint`, `open`; its child is what it opens,
  built only while open) and `Notice` (`text`; `kind` `warning` — the default —, `danger`,
  `success`). `SectionTitle`, `Heading`, `Hint`, `SwitchRow`, a `SettingEditor`'s label, hint
  and unit and a page's name in the settings window show their texts as written: markup in
  them is no longer read, in the shell's own pages too.
- 1.5: the public controls — `Dropdown` (`options`, `value`, `placeholder`, `picked(value)`;
  `size` `xs`, `s`, `m`), `InputField` (`text`, `placeholder`, `problem`, `password`,
  `revealed`, `accepted()`, `textEdited()`, `editingFinished()`, `revealToggled()`; `size`
  `xs`, `s`, `m`), `Pill` (`label`, `picked`, `tooltip`, `clicked()`; `size` `s`, `m` — the
  default —, `l`: the theme's three pill heights), `Checkbox` (`label`, `checked`,
  `toggled()`), `ToggleSwitch` (`checked`, `toggled()`) and `PrivilegedMark` (`need`: `auth`,
  `no`, `yes` or empty; one it does not know shows the lock). The labels of a dropdown and
  its options, a field's placeholder and a checkbox's label are shown as written, on one
  line, in the shell's own views too.
- 1.4: public elements — types in `qs.api` made for modules, which hold the shell's internal
  component inside and show only their own properties; a module picks a meaning (`kind`) and a
  `size`, never a colour or a number of pixels, and a word an element does not know shows as
  its default (logged once). The first is `SmallButton`: `label`, `available`, `checked`,
  `tooltip`; `kind` `primary`, `secondary` (the default), `danger`, `warning`, `success`;
  `size` `xs`, `s`, `m` (the default); `confirm` — the first click asks (`confirmLabel`, the
  label and "?" unless given; `cancelTip`; `asking`; `asked()`), the second acts; `clicked()`
  is "do it" either way. `qs.components` keeps its own `SmallButton`: a file that imports
  both gets the one whose import is written last.
- 1.3: `Api.networks` — the saved Wi-Fi and Ethernet networks (no hotspots, VPNs or bridge
  ports) as frozen `{ id (profile UUID), name, kind, active }`, active first — and
  `Api.vpnsUp` — the VPNs up now as frozen `{ name, type, provider }`; both read-only, a new
  array only when the content changes. `module.presetValue(type, preset, key)` and
  `module.setPresetValue(type, preset, key, value)` — a module reads and writes the presets of its own bar widgets (WidgetPresets, falling
  back to its manifest's `presetDefaults`), so its widget and its widget settings pane can use
  the `preset` / `presetName` the bar and the section editor give them. Writing needs an existing
  preset (it never creates one), refuses `__proto__` and keys that are not names, and keeps the
  preset within 50 keys and 16 KiB. WidgetPresets reads and writes own properties only (a preset
  named `__proto__` or `constructor` no longer "exists").
- 1.2: `module.resumed()` (signal: the machine woke from sleep; only while active); `shown`
  given to a settings page or slot contribution (and a VPN page) whose root declares
  `property bool shown` — true while on screen, kept current; `PrivilegedAction`'s answer has
  `notFound` (command[0] must be an absolute path to an executable file, checked before
  pkexec: a missing program is a plain failure, never "not authorised");
  `Api.openUrl(url, options)` opens only http:, https:, mailto: — file: with
  `{ allowFile: true }` — and refuses (logs) everything else, a bare path included (a
  tightening, taken as a fix); `module.store` is written synchronously and atomically (600, in
  a 700 directory the host makes first), flushed when destroyed, read by a process and capped
  (a file over 1 MiB is refused and left alone); `Api.theme`'s groups and `curve()` are deep
  frozen copies; `setFact` with the value a fact has is a no-op; only `property var module`
  receives the handle (other spellings get a warning in the module's status);
  `VpnProvider.settingsPage` — the id of the provider's own page among the settings pages
  (its module's `settingsPages` id): the VPN card's "Settings…" goes there, and the
  `network.vpn.page` slot / `pageUrl` is only the fallback for a provider without one.
- 1.1: the VPN provider seam's slots `network.vpn.row`, `network.vpn.card` and
  `network.vpn.page` in the slot table — a module's VPN provider (`VpnProvider` from
  `qs.components`, its `providerId` the module's id) fills them through its manifest's
  `slots`; their context adds `otherVpnsUp` (the other VPNs up); a provider page gets its
  module's handle as `module`.
- 1.0: `Api` (version, theme tokens, slot table, `module(id)`, `moduleAt(url)`, notify,
  openUrl, copy, openSettings); a module's handle (its status, `active`, manifest, files, own
  settings read and written, facts, a JSON store, notifications, its settings pages, runtime
  errors), injected as `module`; `SettingEditor`, `SectionTitle`, `Heading`, `Hint`,
  `DetailRow`, `SwitchRow`; `CommandAction`, `CommandQuery`, `PrivilegedAction` (pkexec);
  slots `network.popup.sections`, `notifications.popup.top`, `settings.general.bottom`;
  manifest field `widgets[].presetDefaults`; every file a manifest names must be a regular
  file inside the module's directory (≤ 1 MiB).

### Added
- A compiled helper (`helper/`, C++/Qt), built by the package or `install.sh` (now `cmake base-devel qt6-base`).
- The shell answers apps that ask to keep the screen on (`org.freedesktop.ScreenSaver`, through
  the helper): video players and browsers hold off the screensaver while unlocked, and see it
  start and end. When another program already answers them, the shell says which and takes
  over once it stops.
  With the screensaver, screen-off and the idle lock all off, the shell leaves that to
  another program (an idle daemon such as hypridle doing idle instead).
- Apps that keep the screen on through logind (`systemd-inhibit --what=idle`, video
  players) hold off the screensaver, screen-off and the idle lock while unlocked.
- Screens off: Settings → When away → "Turn screens off" (after a time from your last
  input; with the screensaver off, straight from the desktop — an OLED's own protection
  mode starts even on black). On the lock screen the screens go off after a minute without
  input there ("Turn screens off on the lock screen after", 0 for never); input turns them
  on, and so do an unlock and waking from sleep. Needs Hyprland; elsewhere the screen-off
  shows the black screensaver at its time, and the lock screen goes plain black instead.
- Screens off beyond Hyprland: on another compositor with wlr-output-power-management
  (sway, labwc, river), monitors are turned off through `wlopm` when it is installed.
- Settings → When away replaces the Lockscreen page: what happens while you are away, in
  the order it happens. At the top "Set per monitor" and a timeline from your last input
  (a lane per monitor, the lock one line across them, colliding times labelled on the other
  side, "Paused: …" while an app keeps the screen on; drawn with everything off too). Then
  the Screensaver (its switch on the title line, its time, "Turn screens off", the monitors'
  cards, how it looks — dimmed while no monitor shows it), the Lock screen ("Lock when
  idle" on the title line dims only its time; the rest serves every lock, and signing in
  points to the Authentication page), the apps keeping the screen on, the commands. Times
  are picked from pills (1 min to 1 h; on the lock screen 30 s to 5 min or Never); parts
  that open on a switch slide open and shut, at once with reduced motion. The sleep notice
  opens it at the lock screen's section; `settings openPage lockscreen` opens it.
- Each monitor its own screensaver and screen-off times: with `lockscreen.perMonitor` on,
  `lockscreen.monitorIdle` gives a monitor (by make, model and serial, so it keeps its
  times on another port) its own switches and times for both, on the one clock from your
  last input — the laptop panel off at 2 min, an OLED off at 5 min without a screensaver,
  an LCD with the screensaver at 5 min; a monitor without an entry follows the default.
  A monitor plugged in counts as input. Set on Settings → When away ("Set per monitor": a card per monitor,
  a monitor not connected kept and forgettable), or over IPC: `idle state` lists the
  monitors, `idle setMonitorTimes <id> <json|default>`.
- Commands when you go away and come back: Settings → When away → Commands, a list of
  entries, each with its moment and two commands — one when the moment comes, one at its
  end, only after the first ran: every screen it waits for dark (by default every monitor
  that goes dark; pick the monitors as chips — a small always-on display left out) and
  your first input, a lock and the unlock, a sleep (the shell's or another's) and the
  resume. Each entry with a command is a mark on the timeline (▸1, ▸2).
  `lockscreen.commandEntries` replaces `screensaverCommands`, `screensaverStartCommand`
  and `screensaverEndCommand`; those are not carried over (a profile that still uses
  them is told once in the log).
- Sleep when idle: Settings → When away → Sleep (off by default; 10 min to 2 h from your last
  input, in profiles as `lockscreen.sleepEnabled` and `lockscreen.sleepTimeout`). The whole
  computer, through logind, without ever asking for a password: where the system would ask
  for one, the section says so and the shell does not sleep it. Apps keeping the screen on
  hold it while unlocked; a program blocking sleep (a backup) pauses it, and the timeline says
  who. It locks first when "Lock before the computer sleeps" is on, or when the idle lock
  comes no later; otherwise the section says beforehand that it sleeps unlocked, and the
  sleep notice says nothing about such a sleep. When logind already sleeps the computer by
  itself after idle (its IdleAction), the section says so: whichever comes first acts. The
  timeline marks the sleep across all monitors; a sleep long after the rest sits after a
  break, so the minutes keep their room.
- Hibernate when idle: Settings → When away → Hibernate (off by default; 30 min to 6 h, in
  profiles as `lockscreen.hibernateEnabled` and `lockscreen.hibernateTimeout`). With sleep on,
  the sleep becomes a sleep that turns into hibernation after the system's delay (sleep.conf's
  `HibernateDelaySec`, one for the machine): the section shows it and, when another time is
  picked, offers Apply, which writes `/etc/systemd/sleep.conf.d/h2s-shell.conf` after asking
  for the password; on NixOS it names the new module option
  `programs.h2s-shell.idle.hibernateDelay` instead. With sleep off, the shell hibernates the
  computer itself, counted from the screensaver or the lock, whichever comes later (neither:
  from your last input) — "after the lock", "Hibernates 2 h after the lock (2 h 20 min after
  your last input)". Never with a password: where hibernation is not possible the section says
  why (the system asks for a password, no swap or only zram, Secure Boot lockdown, no resume
  device). The same rules as sleep: apps keeping the screen on hold it while unlocked, a
  program blocking sleep pauses it; a sleep-then-hibernate the system refuses at the moment
  becomes a plain sleep. The timeline marks it across all monitors, after a break.
- Safe mode has a banner, under the bar and at the top of Settings → Modules: why the shell
  started without modules, the modules on when it crashed and one installed or updated in
  the last day, with "Open Modules" and "Load modules" (loads them again without a
  restart); × hides it under the bar for this run. Never on the lock screen. The safe-mode
  notification points to it.
- Settings → System → Modules → Installed: every module as a card, enabled ones first (their
  names in colour), then the ones turned off ("Off" under the name); a pill only for a state
  that needs attention (Failed, Needs …, New — off, Approval required), warnings and
  deprecated API uses as marks beside the name, each with a tip. Opened, a card shows the
  description, where the module comes from, the API, whether it runs administrator actions,
  the modules it needs, can use and is used by, its programs, its errors and warnings, and
  its data folder. "Enable" asks first for a module that is not part of h2s-shell; "Disable"
  asks on the button, or in a dialog listing the modules that need it and go off with it.
  The Modules group is always there; modules' own pages follow under it.
- Settings → Modules: updates on the page. "Update all (n)" beside "Check all"; the update queue
  with a row per module and its step (downloading with its bar and speed, verifying, backing
  up, installing, done, approval required, not finished, failed); a module whose update needs
  your approval shows why, with "Update" or "Keep" its running version; a refused update says
  so and offers to delete the new version. "Switch version…" lists the kept versions and the
  repository's tags; "Backups…" lists the settings backups, each restorable (it asks first and
  says when it is done); "What's new" opens the changelog in the side panel; "Module updates"
  (by hand / automatically) is on the page. When the queue ends, one offer to restart the
  shell; "Later" leaves a banner over every Settings page until the restart, and clicking the
  update notification opens Settings → Modules.
- Settings → Modules: "Add a module" installs from a repository address or a folder ("Choose
  folder…" opens the system's folder dialog). Each download shows a bar with its percent and
  speed, then the preview says what the module is, where it comes from (the commit), whether
  its API fits, whether it runs administrator actions, which of its programs were found, the
  modules it also installs, updates or can use and any that cannot be had, what it replaces
  and where it goes, with the statement for every module that is not part of h2s-shell and
  "What's new" in the side panel. "Install and enable", "Install, keep off" — or "Install
  anyway" when a module it needs cannot be had — and "Cancel", which deletes the downloads.
  A failure says what happened and why.
- Settings → Modules → Installed: "Remove" on a module in your modules folder (never on a
  built-in or system one) asks first, saying what is deleted — only the link for a module you
  linked, the folder for one you placed there by hand ("Not installed by the shell") — which
  modules stop working without it, with "Also delete its data and settings" and any module
  installed only for it offered unchecked. "Check all", and "Check for updates" on a card,
  look for newer versions: "Checking 2 of 3…", then each card's result under its name ("Up to
  date · checked 14:32", "1.3.0 available", "Check failed: …"); a downloaded update gets an
  "Update to 1.3.0" button.
- Built-in modules have their place: on NixOS in the package (`share/h2s-shell-builtin`), on
  Arch in `~/.local/share/h2s-shell/builtin`, which `install.sh` fills from the checkout. None
  ships yet. On Arch, update with `git pull` and then `./install.sh --update` in the shell's
  folder: it copies the built-in modules again, nothing else.
- Modules can be installed, updated to another version and removed through IPC:
  `qs ipc call modules install <address-or-folder>` (a git address, `#<tag|branch|commit>`
  allowed, or a folder; `installKeepOff` keeps it off) downloads it with the modules it needs,
  checks it and turns it on; each version is kept in
  `~/.local/share/h2s-shell/module-versions/<id>/` and the modules folder links to the active
  one, so `switchVersion <id> <version>` goes back and forth and `deleteVersion` drops one;
  an update that does not start goes back to the version before. `remove <id> <directory>`
  (`removeWithData` with its data and settings) removes a module — only the link of one you
  linked by hand. Nothing installs while the screen is locked; `modules job` tells how the
  last one went.
- A module's configuration is backed up before every update, switch of version and restore:
  its settings, its store and only the data files its manifest names, in
  `~/.local/share/h2s-shell/module-backups/<id>/<version>-<time>/`, the newest 5 kept.
  `qs ipc call modules backups <id>` lists them; `modules restore <id> <backup>` turns the
  module off, puts that configuration back and turns it on again. A backup that cannot be
  taken stops the update. Not while the screen is locked.
- Installed modules can be updated: `qs ipc call modules check <id>` (`checkAll` for every
  one) looks for a newer version where the module was installed from and downloads it beside
  the running one; `update <id>` / `updateAll` switch to it. An update that comes from another
  source, names another author, first asks for administrator rights or needs a module not
  installed waits for `approve <id> <version-dir>`; `refuse` keeps the old version and that
  version is never offered again. With the setting "Module updates" (`modules.autoUpdate`)
  set to "Automatically" the shell does this once a day by itself, never while the screen is
  locked. One notification tells what was updated and, when only a restart loads the new
  files, asks for one; it goes away by itself once the shell has restarted. `modules updates`
  tells where things stand.
- Settings → Appearance → Other has a "Settings modal" section: the corners, padding, border,
  spacing and widths of the questions that open over the Settings window; their dimming is
  a colour of its own, "Modal dimming" (Colors → Backgrounds).
- The shell tells you when the screen was not locked while the computer slept: at each
  sleep it looks whether the session is locked (its own lock, Hyprland's lock state, else
  logind's LockedHint; it holds the sleep back for about a second to look), and after an
  unlocked one shows a critical notification, "Not locked while asleep", once. Closing it
  leaves a line on Settings → When away until a sleep locks; the next unlocked sleep after
  that is told again. No program is named or guessed; a sleep whose lock state could not be
  read says nothing.
- Toasts stack in three queues, top to bottom: critical, staying (until taken away) and
  ordinary (they count down), each showing at most its own number and counting what waits
  on its own "+N" badge beside its lowest toast (the critical badge outlined in red); a
  badge opens the notification centre on its screen. Settings → Notifications: "Critical
  toasts shown, at most" (1–3, one by default) and "Toasts that stay, at most" (1–5, one).
- Toasts show as long as the app asks (an app asking for 0 stays until closed); "Apps
  choose how long", off, gives every toast your time. Critical toasts stay until dismissed
  or answered, as the notification spec asks, and are outlined in red, in the toast and in
  the centre; the authentication agent's warnings are critical. A resident notification
  (one its app keeps, such as a music player's controls) stays on screen too, unless
  "Resident notification hide" is on (an info icon says what resident means); pressing one
  of its buttons leaves its entry in the centre and its toast on screen.
- Toasts can be moved: a critical or staying toast dragged by its title line (the grip at
  its top) stays where it is dropped, with an accent outline, until its "×", and its place
  in the queue goes to the next one. A pin on each notification in the centre keeps it on
  the screen the same way, beside the toasts, until it is unpinned. Moved toasts stay when
  the centre opens or toasts are switched off. "Move toasts by dragging", on by default.
- Notifications show an app's progress: a bar under the text when the app sends one (the
  notification spec's `value` hint), moving as the app updates the same notification — in
  the toast, the notification panel, and on the screensaver and lock screen where they show
  a notification's text. A finished job shows how it ended beside its title: a green ✓
  when done, a red ✗ when it failed, a muted ✗ when cancelled; its toast, which then counts
  down, shows the countdown as its only bar.
- Modules can show a job's progress in a notification: its bar moves as the job goes, its
  toast can stay on screen while the job runs, and comes back when the job's status changes
  (started, stalled, done); turning a module off takes its progress notifications away.
- Settings → Appearance → Controls: "Progress bars", their thickness and corner radius; the
  hardware popup's bars follow them.
- A notification's progress bar shows bands of light passing through its filled part while
  the app's job is moving (its value grew in the last 10 seconds); they stop when the job
  stands still or ends, and with reduced motion. Their pace is "Progress wave" and
  "Progress wave: travel" in Settings → Appearance → Animations.
- Enter in a Wi-Fi network's password field connects, as Connect beside it does (the
  network popup), or saves the new password, as Save does (a saved network's card in
  Settings) — only when that button could be pressed and the network's row is open: never
  with the field empty.
- Modules (no Settings → Modules page yet): the launcher finds modules in
  `~/.local/share/h2s-shell/modules`, each system data directory's `h2s-shell/modules` and the
  directories `H2S_SHELL_MODULE_PATH` names, and hands them to the shell in
  `H2S_SHELL_MODULES`; `ipc call modules list` reports each one's state, errors and warnings,
  `ipc call modules setEnabled <id> <true|false>` turns one off or on.
- Modules contribute to the shell: bar widgets with their popups, preset defaults and preset
  panes; settings pages (under a core group, a "Modules" group, or at the end of a tab);
  settings of their own (`mod.<id>.*`, per profile or global, with the popup-mode setting of
  their widgets made automatically); profile facts (`<id>.*`) that profile conditions can test
  (the condition editor now also compares numbers and texts); and content in named slots of
  the network popup, the notifications popup and Settings → General. Turning a module off
  takes all of it away at once, without a restart; a bar entry of a widget that is gone stays
  and shows nothing ("not installed" in the section editor).
- Safe mode: after the shell died within 30 s of starting twice in a row — seen by the
  launcher, or by the shell itself when Quickshell restarted it in place — it starts without
  modules (and says why in `modules list` and the log); a start that lasts 30 s ends it.
- Lock screen: locks when systemd-logind asks for it — `loginctl lock-session`, or a power
  key or lid switch set to `lock` in logind.conf — and on `ipc call lockscreen lock`; and
  unlocks on logind's Unlock for the shell's own session (`loginctl unlock-session`, the
  way back in from another console). Another session's Unlock is ignored.
- Lock screen: unlocks with a fingerprint or a security key (FIDO2/U2F) as well as the
  password, each checked on its own, so a finger on the reader unlocks with nothing typed
  and a typed password never waits for the reader to give up. It shows what the reader or
  key is waiting for, and asks for anything more PAM wants after the password (a one-time
  code). A fingerprint or key configuration that asks for typed input is not used (it
  would count failed password attempts); this leaves pam_u2f's interactive mode out. The
  reader waits for a finger for as long as the screen is locked (`pam_fprintd timeout=-1`
  in the shipped and the NixOS module's configs), and a round that times out anyway is
  started again rather than counted against the reader. An account with an empty password
  cannot unlock by password.
- Lock screen: locks before the computer sleeps (Settings → When away, off by default),
  holding the sleep back until the compositor confirms the screen is covered (at most 4 s).
- Lock screen: every authentication event goes to the shell's log — locks and unlocks and
  why, each PAM conversation started, answered, aborted or finished, the methods found,
  failures to run a helper — never what was typed.
- `h2s-shell --lock-log` (`scripts/lock-log.sh`): what happened to the lock screen in the last
  half hour, readable from a text console while the screen is locked — the shell's lock
  lines with their time (Quickshell's log), the supervisor's own log
  (`$XDG_RUNTIME_DIR/h2s-shell-launcher.log`), the lock marker and the journal's PAM, fprintd
  and logind lines. The log now also says when the prompt woke or slept and why, a refused
  submit, the error shown, how long each PAM conversation took, the marker written, the
  sleep inhibitor taken and released, and whether the shell is supervised.
- Lock screen: the screen stays locked when the shell does not. The launcher (`h2s-shell`)
  now stays as the shell's supervisor and starts it again when it dies (a crash, a kill,
  the OOM killer; at most 5 times in 2 minutes; not after a deliberate stop while unlocked),
  and a shell that stopped while locked — also by `qs kill` or `h2s-shell --restart` —
  locks again at once when it comes back. Under Hyprland this needs
  `misc:allow_session_lock_restore = true`; without it Hyprland's "lockscreen app died"
  screen stays, and the shell waits for the setting instead of getting itself killed
  (`ipc call lockscreen status` says `compositor-locked`).
- Lock screen: says "Caps Lock is on" under the password field, from the keyboard's Caps
  Lock LED (`/sys/class/leds/*::capslock`, read when the prompt wakes and at each key; any
  keyboard's LED on counts). Without such an LED it says nothing rather than guess.
- Lock screen: a crash that Quickshell restarts in place no longer leaves the old
  fingerprint conversation holding the reader: the restarted shell ends what its process
  left.
- Settings → System → Network → Overview: whether the computer is online; Wi-Fi, mobile
  broadband, airplane mode (every radio, Bluetooth too, put back as it was) and networking
  switches; each network device with its hardware, MAC, speed, signal, addresses, gateway,
  DNS and MTU; the hostname, a global DNS over every connection's, and the connectivity
  check. Pages of the settings' sidebar can unfold into sub-pages (Network → Overview).
- Settings → System → Network → Wi-Fi: the radio and the network in use; the saved networks
  (in use, in range, out of range; security, hidden, last used), each with connect or
  disconnect, connect automatically, priority (which wins when several are in range), the
  password — shown for a while from NetworkManager, or changed — and forget; joining a
  network that hides its name; "Find networks" slides in the networks in range from the
  right, to connect to a new one as in the network popup (the same list). The Overview's
  Wi-Fi card and summary line lead to it.
- Settings → System → Network → Ethernet (with a wired device): each device's card, or that
  its cable is out, and the wired profiles — in use or when last, use or disconnect,
  connect automatically, priority, forget. The Overview's Ethernet card and line lead to it.
- Only through the VPN (a kill switch): "Block traffic outside a VPN, always" on the VPN
  page, or "Block traffic outside a VPN here" in a Wi-Fi or wired profile's editor — an
  nftables table loaded through pkexec that lets out only the VPNs, their servers, joining
  a network (DHCP, IPv6 neighbour discovery), virtual interfaces (containers) and, when
  allowed, the local network; a hotspot's devices and containers get out only through a
  VPN; DNS still looked up, so a VPN set by its server's name connects. Switched again
  only when the rules change; the page says whether it is blocking, and "Apply again"
  finds the servers anew. "Password-free blocking": the script that builds the rules
  (scripts/h2s-vpn-lockdown, readable on the page; it checks and rebuilds every argument,
  so nothing else can be had from it) installed with a polkit rule for this
  user alone — one password, "Install…" and "Remove…" on the page with its state
  (installed, outdated, still asking); on NixOS a module to import instead. Installed, no
  password is asked again, and the shell checks (at the start, after network changes, every
  5 minutes) that the blocking is still
  loaded.
- A VPN with a network: "Connect a VPN with it" in a Wi-Fi or wired profile's editor picks
  VPNs the shell keeps up while that network is connected — linked to several, while any
  of them is — and takes down when none is, if it brought them up (remembered across
  restarts; one taken down by hand stays down until the networks change). WireGuard too —
  which NetworkManager's own connection.secondaries refuses —, and a VPN that fails leaves
  the network up. The VPN's card lists the networks it comes up with.
- Settings → System → Network → VPN: "New WireGuard" and WireGuard's own editor — the
  interface, the private key (Generate with wireguard-tools' wg, or pasted; the public
  key shown to copy for the server; a note when wireguard-tools is missing), listen port,
  MTU, and the peers: public key, endpoint, allowed IPs with "All traffic", preshared key,
  keepalive; IPv4 and IPv6 manual or off.
- Settings → System → Network → VPN: the VPN profiles as cards — kind, state, server;
  connect, disconnect, edit, delete; while up the interface, address, data moved and speed
  — and "Import…" for a WireGuard .conf (imported off, so a whole-traffic tunnel does not
  take the internet over by itself; any file name), an OpenVPN .ovpn or another plugin's
  file; "Files you can import" lists each kind with its files and whether it can be
  imported now (a missing plugin named with what it is for). The Overview's VPN line and
  cards lead there.
- Settings → System → Network → Wi-Fi: hotspots — this computer's own Wi-Fi networks, in a
  section of their own: turn on (asking first when that would drop the network in use with
  no cable or modem to share), turn off, start automatically, the password, the devices on
  it, edit, forget; "New hotspot" makes one (the computer's name, 2.4 GHz, WPA2, a random
  password), in the connection editor fitted to it (security and password, the addresses
  handed out).
- While a hotspot is on, the network popup shows it in the Wi-Fi network's place — its
  devices, speed and address, "Turn off hotspot" — and says joining a network needs it off,
  instead of the stale list of networks; the bar shows an access point instead of the
  signal, and the Overview and the Wi-Fi page say "Hotspot on".
- The network popup lists the saved hotspots under "Connect to hidden network" (a section
  that opens, shown when there are some), each with "Turn on" — asking first, as on the
  settings page, when it would leave the network in use with nothing to share.
- Settings → System → Network: a saved Wi-Fi or wired profile's connection editor (Edit
  connection…). First the profile's name and the medium's own settings — the Wi-Fi's SSID
  (the profile's name follows it while the two match), band, MAC address and hidden; the
  cable's MAC address and MTU — then, below a line, connect automatically, priority,
  metered, only for me; IPv4 and IPv6 (automatic, manual addresses and gateway, link-local,
  off; for IPv4 "Be the router", handing addresses out from this computer, with its own
  address, the range and the lease time), DNS servers, search domains, ignoring DHCP's DNS,
  use only for its own network, route metric, require the family, IPv6 privacy. Every
  option says what it means (on hover, and the picked one's under it), and the list fields
  how to write several. Wrong fields are marked; Save, at the top and the bottom, sends only
  what changed, at once.
  "Save and reconnect" on the connection in use asks "Keep these settings?" for 20 s and
  otherwise puts the old ones back — what really changed, a manual profile's addresses
  too; the countdown carries on when the editor is left, and shows on the Wi-Fi and
  Ethernet pages as well.
- The shell can be the session's authentication agent (polkit): a themed prompt for an
  administrator's password when a program needs one — what asks, the account, PAM's
  messages, a wrong password asked again. Decided at the first start: off when another
  agent runs, on when none does; notifications when no agent answers or two collide.
  Settings → System → Authentication, with a button to try the prompt.
- The shell's password prompt says who asks and what for when a module runs something as
  administrator: "Module" and "Authorization" under the title, and the command handed to
  pkexec behind a click on "Command". The lines are attached when polkit's message names
  the module's command; polkit shortens a command past 80 bytes to its two ends, so another
  command with the same ends would get them too. Its texts are shown as plain text. When the screen locks, an open
  prompt is cancelled; click again after unlocking.
- When another password agent answers (or none, or which one is not known yet), the shell
  cannot add those lines to its prompt: a module's run as administrator is then announced
  by a notification just before it starts, "Module: <name>" and "Authorization: <what>",
  in plain text. It says who runs what, not that a password will be asked.
- Settings: a System tab for this computer's settings, which apply at once in every
  profile; Authentication is its first page.
- Wallpaper transitions, set in the theme (Appearance → Animations): a switch to a
  workspace with its own image slides the way the workspaces go (or changes as a new image
  does); a new image fades, zooms, slides, wipes, opens as a circle, dissolves or
  pixelates. Two animation roles time and ease them, with curves from the library.
- Wallpapers load fast: each image is resized once to each screen it shows on and kept in
  `~/.cache/h2s_shell/wallpapers` (300 MB at most, the oldest go first), and the nearest
  workspaces' images are decoded ahead. Needs `vipsthumbnail` (libvips), now a dependency.
- Wallpapers drawn by the shell (Settings → Wallpaper; off by default): an image, or a
  folder (subfolders to a chosen depth) chosen by you, at random — at start, every so
  often, or on Shuffle (`ipc call wallpaper shuffle`) — or by weekday; one everywhere, per
  monitor or per workspace, faded in on a change. Picked from the folder's thumbnails:
  the images to use, one per monitor or workspace, one per day, and monitors or
  workspaces that keep theirs while the rest are drawn. A warning when another program
  (hyprpaper, swww) draws a wallpaper too.
- Notifications: where toasts show — the screen with the focused workspace, as before, or
  a chosen screen — and what a fullscreen window on that screen changes: show anyway,
  don't show (the notification goes to the panel only), or show on another screen, a
  chosen one or any without a fullscreen window. The shell's own messages follow them.
  Settings → Notifications.
- Battery widget: a colour of its own while plugged in (charging, full on the charger),
  over the colour thresholds; empty keeps the thresholds. Widget settings → Charging.
- Battery widget settings: clicking a colour's swatch opens a colour picker under it, as on
  the Colors page; typing the hex still works.
- Calendar: a click or a tap on the month or the year shows the year's twelve months; the
  arrows (or a swipe) move by years there and a month goes to it — moving by years no
  longer needs the wheel over the year.
- Curves settings: two fingers zoom the curve's graph, as the wheel does.
- Touch and mouse alike: buttons, icons, rows and bar cells show their hover look when
  tapped (it holds a moment after the finger lifts, so a tap is seen), and small controls
  take a click or a tap a little past their edge — at least 36 px round them, the theme's
  new Appearance → Controls → Targets — without changing how anything looks. A tap on
  the bar's edge above a cell now reaches it.
- Notifications: swipe a card sideways with a finger to dismiss it — a toast in the HUD
  (its countdown waits while the finger is down) or a card in the notifications panel. A
  short swipe lets it go back. The mouse still selects text by dragging.
- Calendar: swipe the month grid with a finger to change the month — left for the next,
  right for the one before. The grid follows the finger with the month it brings in
  beside it, events and all, and slides on from where you let go; a tap still selects a
  day.
- Music panel: a new track slides in sideways — the next from the right, the previous
  from the left — and a change of player slides vertically, a player lower in the list
  coming in from below (before, a change of player slid sideways and a new track only
  faded its title in). With a finger: swipe the cover left or right to skip the track
  (⏭/⏮ shows in the gap, lit once far enough), up or down to change the player, whose
  view follows the finger in.
- Calendar: the "Today" button's line is kept when it is hidden, so the grid stays the
  same size — its days no longer jump when you move to or from the current month.
- On-screen keyboard: a popup no longer draws under it. While the keyboard is up, a popup
  by a bar at the top ends above it, and its content moves within it — by itself to keep
  the field being typed in in sight, or by a drag or the wheel. A drag no longer counts as
  a tap off the field, so scrolling keeps the keyboard.
- Bar: a battery widget. An icon showing the charge in tens, charging or not; the
  percentage left or right of it, or not at all; and colour thresholds — any number, each a
  charge and a hex colour, the icon taking the colour of the lowest one the charge is at or
  below. Per preset, in the widget's settings. It opens a popup: the charge, charging or
  not, time left and the power drawn; the system power profile, to change by hand — it
  stays until the shell's profiles next want another one, and the popup says which; and the
  history as UPower records it — the charge over 6 h, 24 h or 7 days with the time on the
  charger shaded, and the power drawn beneath; and beside it, as on Android, use per app
  since the last full charge — estimated from each app's CPU and GPU time while on
  battery, the screen and the rest as "System and screen". Dragging across the graph picks
  a stretch of time, and the list shows the use within it; a tap, or ×, goes back.
- Google Calendar: no OAuth client of your own needed — the shell carries one (a client
  entered in the settings still takes its place). The sign-in uses PKCE and checks its
  `state`, since the client's secret is public.
- Installing: `install.sh` for Arch (the packages, then a checkout where Quickshell looks
  for its config), and a Nix flake for NixOS — an `h2s-shell` command carrying every
  program the shell calls, and a module (`programs.h2s-shell.enable`) adding the font and
  the services its widgets read. `launch.sh` now works from wherever the shell lies.
- Profiles: "Tablet mode" as a condition, for convertibles. Hyprland tells the shell when
  the device folds (two switch bindings, see the README); `ipc call tablet set|toggle`
  sets it by hand.
- A banner under the bar when no Nerd Font is installed — the icons are its glyphs and
  show as empty boxes without one — saying how to install it.
- Bar: it can stand at the left or right of the screen too. The widgets stack down it and
  popups open sideways from it; text is turned — read down a bar at the right, up a bar
  at the left — or written as letters one under another (Behaviour → Bar → Text on a
  vertical bar, the same for every widget). A single character, such as an icon, stays
  upright.
- Bar: it can stand at the bottom of the screen (Behaviour → Bar → Position, per
  profile); popups then open upward from it. The Bar shape page names the edge offset
  and corners by the screen's edge and the desktop side, so a theme looks the same at
  either edge.
- Music panel: changing player slides the cover, its visualiser and the track sideways —
  a player further down the list comes in from the right, one further up from the left —
  each view keeping its own player, so the cover turns and the ring moves only for a
  player that is playing. Not with reduced motion.
- Music panel: the player list shows each player's application icon, and two buttons
  beside each: play — pausing every other listed player, so switching between, say,
  Spotify and a browser is one click (pause while it plays) — and hide. Hidden players
  (a phone's, through KDE Connect, say) go under a "Hidden" expander over the list, to be
  shown again with the eye beside them; they are never picked by themselves. The list
  is kept per profile ("media.hiddenPlayers", also in Settings → Media).
- Music: the visualiser can go around the cover (Settings → Media → Layout, "Around
  cover") — waveform, rays, dots or glow following the cover's shape, bass at the bottom.
  Two glow styles, in every layout: Glow, light reaching as far as each band; Even glow,
  one halo pulsing with the bass. The cover's rounding is a slider, from square to a
  circle (33 %, the old look, by default), and it can turn while playing, either way, up
  to 360° a second (off by default; never with reduced motion).
- Music: two more visualiser layouts glued to the popup's edges, growing inward only —
  Horizontal (bottom) along the bottom edge, Vertical (sides) down both sides — cut to the
  popup's rounded corners. The old two are now Horizontal (centered) and Vertical
  (centered), unchanged.
- Music: around the cover, the visualiser can take its colours from the cover (Settings →
  Media, "Colours from the cover", off by default): two or three, read from each cover as
  it loads, running round it — the visualiser fades in once they are known, never
  first in the theme's colour. A grey cover keeps the theme's colour.
- Themes: a colour of its own for the music visualiser (Appearance → Colours → Music).
  Until a theme sets it, it follows the accent, as the visualiser always did.
- Settings: a slider whose range goes both ways (the cover's rotation) is filled from
  its resting value, marked on the track, rather than from its left end.
- Notifications widget: a badge on the bell with how many notifications wait ("9+" past
  nine), and the bell rings when one comes — lifted, shaken in the air, put back. Its
  preset (Bar → Content → Notifications) turns the badge off and picks the ringing: off,
  once for each notification, until opened (again every few seconds until the panel is
  opened) or until cleared (again every few seconds while any notification is left). Not
  with reduced motion.
- Notifications: formatting in the text — bold, italic, underline, line breaks — and
  links: web and mail links in the accent colour open on a click; any other kind (a file,
  an app's own) is in the warning colour and asks first, with Open, Copy and Cancel. An
  image in the text is never loaded: it is a tinted row of its own with an image icon,
  linking to it, its address shown under its description. Hovering a link shows where
  it goes. Other tags are dropped, their text kept; the body is read by a small
  parser, so tags of any shape (self-closing, quoted ">" in attributes, comments) are
  understood. Codes are found in the text, not in link addresses.
- Settings, General: an icon theme for the shell — its notifications, tray and every
  other icon, picked from a list of the installed themes. Automatic, the default, is the
  system's icon theme if it is installed, else the first one found; a row of sample icons
  under the list shows the theme picked before it is applied. It applies when the shell
  restarts, which a "Restart to apply" button next to it does. The shell now starts
  through `scripts/launch.sh` (Hyprland's autostart calls it), as Quickshell takes the
  icon theme only at launch. Before, the shell had none: app icons loaded, status icons
  such as warnings did not.
- A banner under the bar when the shell was started directly (`qs`, `qs -c default`)
  rather than through `scripts/launch.sh`: the icon theme setting cannot apply then, and
  it says why and how to start the shell instead. It restarts nothing by itself, so the
  arguments the shell was started with are never dropped; × closes it for that run.
- Calendar: events can span several days. The event form has a start and an end date
  (DD.MM.YYYY, typed like the times: digits only where they make a date, "." moves on,
  Up and Down step, a day past the month's end becomes its last); moving the start takes
  the end along, an end before the start becomes the start. A timed event ending earlier
  in the day than it starts goes on past midnight.
- Calendar: going into a date field arms the calendar for it — the next day clicked fills
  it (the start, then the end), and a hint says which; the event's days are shaded in the
  grid while the form is open. Without an armed date a click only moves the calendar,
  and an event being edited stays in the list while other days are looked at.
- Calendar grid: an event spanning days is a bar in its colour above the day numbers,
  running through its days — on into the next week's row, keeping its place, rounded
  where it starts and ends — instead of a dot on each day; up to three stacked. Under the
  number, a dot for each single-day event, in the event's colour (two rows of four at
  most), instead of one accent dot for the day.

### Changed
- Settings: every page's sections stand apart the same way — a line and room above each
  section, its title a size larger than the rows. A theme can change the spacing (Appearance
  → Other → Settings window: "Section spacing", "Line to title", "Under a title").
- The shell no longer reloads itself when one of its files changes: a file written in its
  folder (an update, a module install, an editor) leaves the running shell as it is until it
  is restarted. Reloading on file changes is for development: start the shell with
  `h2s-shell --dev` (Arch: `launch.sh --dev`) or with `H2S_SHELL_DEV=1`; `H2S_SHELL_DEV=0`
  turns it off even with `--dev`. It stays off while the screen is locked, as before.
- The shell's lock is reported to logind (the session's LockedHint: `loginctl show-session`
  says `LockedHint=yes` while locked), so programs that lock themselves when the session
  locks, such as password managers, see it.
- Settings → When away → "Lock after" now counts from your last input, whether the
  screensaver is on or not (it counted from the screensaver's start when the screensaver was
  on); its default is 10 minutes. A value set before is not carried over: set it again if
  you had changed it. An unlock without input (`loginctl unlock-session`) counts as you
  being back: the screensaver does not come back at once.
- The password prompt names the account first, as an "As user" row above Module. For a
  module's request polkit's own message and action move under Command, where they show with
  the command; other requests keep them as their description.
- A module that is not part of h2s-shell — one you put into `~/.local/share/h2s-shell/modules`
  yourself, linked or copied — starts off the first time the shell finds it, until you
  confirm it (`qs ipc call modules confirm <id> <directory>`, the directory as `modules list`
  shows it; Settings → Modules will ask). Modules you already had on keep running without a
  question: the first start of this version takes them as confirmed. A configuration file
  that cannot be read is no longer saved over with the defaults. A module you placed by hand that starts asking for administrator rights,
  or names another author, is held off until you approve it the same way. Built-in modules,
  your system's and those on the development path (`H2S_SHELL_MODULE_PATH`) never ask.
- A notification says when modules are held off for your confirmation or approval: which
  ones and why, with "Open Modules" (Settings → Modules). It stays until none waits, one for
  all of them; dismissed, it comes back only when the modules waiting change.
- `qs ipc call modules rediscover` finds modules put on disk since the shell started and
  loads them without a restart; `qs ipc call modules loadWithoutSafeMode` loads the modules
  after a crash loop, in place. `qs ipc call modules list` says where each module comes from,
  and names a module whose files changed in place, which needs a restart of the shell.
- A module asks for an administrator's password only when its module.json says what it
  runs as administrator and why (`privileged`); one that does not is refused before any
  prompt, and Settings → Modules shows why among its errors.
- A shell that keeps dying while the screen is locked is started again at most 3 times
  while the session stays locked (an unlock starts the count afresh), no longer once a
  minute for good. Then the launcher gives up and the session stays locked; the way back is
  a text console, where the launcher is started again (docs/FEATURES.md, "The limit while
  locked"). Once unlocked, the new shell says in one notification what happened and where
  the log is.
- "Lock before the computer sleeps" (Settings → When away) is off by default: a change of
  behaviour people rely on. A configuration that holds no value for it — a new one, or one
  made before the setting came — no longer locks the screen before sleep; turn it on to keep
  that. A configuration that already holds a value keeps it. When the configuration file
  cannot be read (or is not valid), the screen locks before sleep as if the setting were on.
- A notification's action buttons and its reply's Send are drawn like the shell's other
  buttons: the accent, with the label in the theme's "On accent" colour (readable on a
  light accent too), lighter under the pointer or a finger. Send is dimmed while there is
  nothing to send.
- A toast's "×" (and its swipe) dismisses the notification: its entry leaves the centre
  too; a job goes on. Opening the centre hides only the ordinary toasts: critical and
  staying ones stay, beside it. A fullscreen window with "Don't show" on the toasts' screen
  leaves the critical toasts on screen.
- Settings → System → Network → Wi-Fi: the Wi-Fi switch is on the page's heading; the
  "Wi-Fi" row under it is gone.
- Network cards (saved Wi-Fi networks, hotspots, wired profiles, VPNs): their buttons stand
  in one row on the name's line, also while the card is closed — the main one (Connect,
  Disconnect, Turn on), "Settings…", "Edit" (was "Edit connection…"), what a module adds,
  then "Forget" or "Delete". When they do not fit beside the name (a narrow window, a long
  question while a button asks), they move to a line of their own under it, on the right;
  a long question gets the card's whole width, on more lines if need be, never cut. A click
  between two buttons no longer opens the card.
- Sizes of a terabyte and more show in TB ("1.8 TB" instead of "1843.2 GB"), on the disk
  card among others.
- The connection editor no longer takes an IPv4 address written with leading zeros
  ("192.168.01.1"), which NetworkManager refuses.
- Pills (the small choice buttons) come in three sizes, small, medium and large: 22, 26
  and 30 px, each height set in Settings → Appearance → Controls → Pills. The pills of the
  profile condition editor and of the widget settings pane's presets are 2 px lower (22
  instead of 24).
- Buttons: the ones that stop or remove something — "Disconnect", "Turn off hotspot",
  "Forget", "Delete", the "✕" on a Bluetooth device — have a red border, so they stand out
  before the pointer is over them and on a touch screen; under the pointer they fill red.
  A button that asks first shows its question with a border around it and its "×". The two
  that ask before turning something on ("Connect" on a network's card, "Turn on" for a
  hotspot) are green like other confirming buttons, and ask in that colour instead of red.
  The theme gains two shapes, "Buttons that warn" and "Buttons for a good outcome"
  (Appearance → Controls), for buttons in the warning and the success colour; nothing in
  the shell uses those yet.
- Modules: a module written for a module API older than the oldest this shell still runs
  unchanged (its floor, today 1.0) is listed as incompatible, with the version the shell
  needs. A module's status (`modules list`) gains `deprecations`: the old ways of the API it
  still uses. Until the shell is announced as open to module authors a minor version of the
  API may remove things that were listed there; after that only a major one.
- Only through the VPN: Tailscale's `tailscale*` interfaces are no longer let out as virtual
  interfaces (a tailnet reaches the internet through exit nodes and subnet routers). The
  script is version 4 and records its version with the rules it loads: the VPN page offers
  to install it again. Rules an older script loaded are loaded again by themselves only when
  the installed script needs no password; otherwise they stay, the page says so, and "Apply
  again" or "Install again…" loads them.
- Settings → Network: a network's editor says when a provider's VPN picked under "Connect a
  VPN with it" cannot connect because traffic is blocked there (or always); the VPN page
  says it under "Block traffic outside a VPN, always" when a network brings one up.
- Module test runner: each asynchronous suite has its own time limit (`TestCase.timeLimitMs`,
  20 s by default, capped at 60 s), instead of one 20 s deadline shared by every module suite
  running side by side.
- Settings → Network → VPN: "Settings…" on a VPN whose module has its own settings page
  (Tailscale) goes to that page — the list on the left selects it, under Network beside
  VPN — instead of opening a copy of it over the VPN page with a Back button. The framed
  page stays for a provider that has a page but no entry in the list.
- Network popup: a VPN's status ("Tailnet only", "Via <exit node>") is a second, muted line
  under its name instead of sitting beside it; rows without a status are unchanged.
- Settings → Network → VPN: shorter hints and notes (the blocking of traffic outside a VPN,
  password-free blocking, importable files, a network's VPNs in its editor); the same facts,
  no repetitions — the password note is said once, under "Password-free blocking".
- `h2s-shell` (the launcher): one supervisor per session — a second start waits a little for
  the first to end and then gives up, and `--restart` tells the supervisor even when it is
  between two restarts (two shells came of it). It now needs `flock` (util-linux), and
  logs to `$XDG_RUNTIME_DIR/h2s-shell-launcher.log`. SIGHUP (the terminal it was started
  from closing) no longer stops it.
- `h2s-shell` (the launcher): after the shell dies it looks for leftover PAM helpers without
  starting a process per running process, so the restart comes ~1.5 s sooner (more on a
  busy machine).
- `h2s-shell ipc call …` tries a call again for up to 3 s while the shell is reloading or
  restarting (Quickshell drops it, "Not ready to accept queries yet.", and exits 0), and
  fails if it was never taken: a Super+L pressed during a reload is no longer lost.
- Lock screen setup: `install.sh` now suggests starting the shell with `launch.sh
  --restart` (detached and supervised, as the autostart runs it) instead of `launch.sh -d`,
  which ran it unsupervised — nothing started it again after a crash while locked. It and
  the README show how to register a further security key without overwriting the first
  (`pamu2fcfg -n >> …`), and warn against `auth include system-auth` for the password
  config (faillock: wrong passwords at the lock count toward an account lockout).
- Lock screen: notifications show the app only by default ("Notifications on the lock
  screen show", Settings → When away): a message's text, a one-time code in it, is not for
  whoever stands at the locked screen. A config still holding the old default ("In full",
  which every config seeded before had) moves to the new one once; another choice stays.
  The two notification settings are no longer greyed out when the idle lock is off: they
  apply to every lock.
- Popups slide out from under the bar as a whole, and back under it, instead of being
  uncovered by a growing cut; the curves joining them to the bar stay until only the
  popup's rounded end is left.
- Popups grow and shrink with a panel's own animation (an expander opening a list of
  devices, say) frame by frame, instead of trailing behind it.
- Music: the player list and the controls stay in view while the popup changes size —
  opening, or coming from another panel — and the cover between them is cut to the room
  left.
- Calendar: an event card's edit and delete buttons are larger, on a button's background
  so it is clear what is clicked, and level with the event's title instead of the middle
  of the card; editing is a pencil icon instead of the tiny "✏" character.
- Notifications: each picture has its place. The app's icon stays small in the header;
  a square image (an avatar, album art, an app's logo sent as an image) is a rounded
  thumbnail beside the title and text; a wide or tall one (a screenshot) a preview across
  the card. It used to be one image for everything, centred under the text — app logos
  included.
- Notifications: clicking a notification that has a default action (opening the chat it
  came from, say) runs it — the header, the text or the image; such a card lights up
  under the pointer, which is a hand over it, the text included. The text can still be
  selected by dragging, and a click that clears a selection only clears it. The default
  action used to be an empty button.

### Fixed
- Clicking a module update notification opens Settings → Modules.
- Restarting the shell within a few seconds of a reload (a saved file, an update) no longer
  crashes it: Quickshell's reload popup is gone — a failed reload is written to the shell's
  log instead (`qs log`) — and the launcher's stop waits while the
  shell takes no requests.
- When cava cannot run (missing, or broken by a library update), the music visualiser no
  longer fails silently: the shell logs why, once; a cava that exits is tried again with a
  backoff, a missing one when the panel opens again; once it runs again that is logged too.
  Visualizer's `cavaState` and `cavaProblem` say where it stands.
- Another program's lock screen (hyprlock) is seen under Hyprland: the shell no longer asks
  for its idle lock over it (Hyprland ended the shell for that), and "screen locked"
  profiles apply while it lasts.
- On Arch, Settings → Authentication now says what the administrator prompt asks first:
  polkit's PAM stack is read where Arch keeps it (`/usr/lib/pam.d`), its `include
  system-auth` followed.
- The key that wakes the screen from the screensaver no longer reaches the window under it
  (an Enter into a terminal ran the line): the screensaver takes the keyboard while it shows.
- A profile switch while the screensaver showed (unplugging the charger, a battery level)
  took the screensaver down and ran its end command, as if you had come back; it now stays,
  and a screensaver switched off by the profile goes without the end command. Waking the
  computer ends a screensaver that was up when it went to sleep.
- A screen turned off at the same time as its screensaver (or just after it) went dark at
  once, without the screensaver's fade in: the screen now turns off once the fade in is over.
- The launcher could lose the exit status of a shell that died just as the launcher got SIGHUP
  (its terminal closed), and take it for a crash: a shell that had quit was started again.
  SIGHUP is now ignored by the launcher (it no longer logs a line for it).
- Settings rows: a long value (such as Tailscale's "Save to" folder) is shortened with an ellipsis instead of cutting off the row's label.
- A checkbox with a long label wraps it to more lines inside its width instead of running past the edge (the Settings dialogs' checkboxes, `Checkbox` of the module API).
- At each unlock the screensaver's window was put on the screen for a moment, clear, over
  the desktop until its fade out ended (under half a second).
- Toasts sat lower than meant under a top bar — by the bar's reserved space — and the shell's
  own message at the bottom touched the screen's edge: the toasts' window now covers the
  whole screen, and nothing it shows — toasts, a moved toast, the volume and the shell's
  messages — lands over the bar, at any edge.
- The network popup's Connect is not available while the password typed is too short for
  the network (WPA: 8 to 63 characters), and says so, as connecting to a hidden network does.
- A network's card in Settings is no longer highlighted while the pointer rests in a gap
  between its buttons, where a click does nothing; a long question beside the lock stays
  inside the card's margin.
- A notification toast stays small: a long body shows its first six lines and fades out
  (a body of exactly six shows whole, nothing cut); the notification centre shows it whole.
- A word in a notification's body longer than the card is wide breaks onto the next line
  instead of running off the side unseen.
- With two bar entries of one widget type, a click on the second while the first's popup is
  open switches the popup to it, as hovering does, instead of closing it; only the entry
  that opened the popup shows as active. That entry built again while its popup shows (the
  bar changed) still shows as active, and its click closes the popup.
- A notification from a module that sends plain text keeps the line breaks of its
  body instead of running every line into one; empty lines at its start and end are dropped
  and a run of empty lines shows as one.
- An opened wired profile's or hotspot's card no longer leaves extra space under its last
  row: it ends as far under it as its name is under the top.
- A VPN's failure notification shows the provider's reason as written: a "<" or "&" in it
  is no longer read as markup.
- A module's command run that is cancelled before its answer comes — one refused, or one
  whose program cannot start — is now answered with `cancelled: true`, as any other
  cancelled run is.
- Turning a module on or off no longer rebuilds another module's element at the same place
  (losing what it held); adding a widget to a bar section no longer reloads the widgets
  after it, and the new one is the one that grows in.
- Editing a calendar event while the calendar refreshes no longer moves the edit to another
  event's card, and Save no longer changes another event: an edit saves only to the event
  it was started on, and says so when that event has been deleted meanwhile.
- Calendar: an event that Google refuses to save keeps its edit open with "Couldn't save the
  event"; the edit closes only once the change is saved.
- Calendar: an event moved to another calendar while it is edited is saved in the calendar
  it is in now, not the old one; found in more than one other calendar, the save is refused
  and the form says so.
- Calendar: the same event in two calendars (an invitation) shows as two cards that no
  longer swap when one of them is removed or the order changes — an open edit stays with
  its own event and calendar.
- A Wi-Fi password typed into a saved network's card in Settings stays with that network
  when the list is read again; it no longer moves to another network's card (and was saved
  there). A network that connects shows as connected at the top of the list.
- The network popup's Wi-Fi list: a network that appears fades in on its own row, rows
  slide to their new place when re-sorted, and signal and "in use" are current.
- A module's run as administrator through the old `PrivilegedAction` asked for in the
  first seconds after the shell starts no longer starts when the session has locked
  meanwhile, and no longer lets the next run start beside it.
- The shell's own short messages at the bottom of the screen ("Copied: …") show their text
  as written, never as formatting, and so do a notification's app name, link and buttons.
- A pill or a button that asks shows a label with line breaks on one line, at its usual
  height, instead of growing taller.
- A switch that cannot be used is dimmed, as an unavailable button is; and an unavailable
  button that is asking dims its "×" and ignores clicks on it too.
- The password prompt no longer lets windows behind it show through.
- Modules: a module that is only its `module.json` (no main, no widgets, no pages) could
  stay "pending" for good after a start.
- After the shell was killed, the launcher now and then never started it again and filled
  its log instead (a defect in bash's `wait -f`); while the shell was stopped, the launcher
  kept a processor busy.
- VPNs: what a VPN provider reports (names, status lines, what needs the user, glyphs, the
  card's details) is shown as plain text in the popup, the bar, the VPN and overview pages
  and the network editor; text that looked like markup was read as rich text (Qt's
  AutoText), so part of it could vanish or an image be loaded. Buttons, pills, tooltips and
  detail rows show their text plainly too.
- VPNs: a provider's VPN that needs the user and offers no action to take (waiting for
  approval, say) showed Connect on its card in Settings, though not in the popup; neither
  offers it now, and connecting it is refused whoever asks.
- Unit test runner: a suite registered with arguments (`ModuleRegistriesTest { after: … }`)
  is counted, so the run fails when it does not report.
- Text on the bar (BarText) is always plain text: a track title, a window name or a module's
  device name holding markup showed it rendered as rich text (Qt's AutoText); it now shows the
  characters as they are.
- Settings → System → Network (Wi-Fi, Ethernet, VPN): on an opened connection card the buttons
  read as plain text (the card was the buttons' own colour); they are buttons again, and
  "Settings…", "Edit connection…" and "Forget"/"Delete" now sit under Connect/Disconnect,
  on its right edge, instead of at the bottom of the card.
- Authentication prompt (polkit): with a fingerprint reader first in polkit's PAM stack
  (NixOS's default) the prompt showed only "Place your finger…" — no field, Esc dead — for
  up to 30 s until the reader gave up. The field is there from the start: a password typed
  and Entered early is held (never logged, cleared on cancel and at the end) and sent the
  moment PAM asks for it, and a line says what the prompt waits for. The NixOS module's new
  `programs.h2s-shell.polkit.passwordFirst` (on by default with fprintd) asks for the
  password first; Enter on an empty field then goes on to the reader. Settings → System →
  Authentication says which order this computer has.
- Settings: a module turned off while its settings page was open left the window on that
  vanished page id; it goes back to General, as intended.
- Modules: the shell reads no module file on its GUI thread while starting (the manifest,
  qmldir and the files' texts come out of the module host's time-limited check), and nothing
  the lock screen needs waits for the modules — a module on a mount that hangs on read can no
  longer keep the shell, and a locked session after a crash, from coming up; the module is
  failed after 5 s, with the reason. Entering safe mode now says so in a notification.
- Profiles: a condition on a module's fact that is not known (its module absent or still
  loading) holds neither way — `not <fact>` no longer switches a profile (and possibly the
  power profile) on at every start; the condition editor names such a fact
  "(module not installed)".
- Notifications: a summary or body starting with "-" is no longer read by notify-send as an
  option.
- Lock screen: closing the lid while the shell reloads (a file of it saved) now still locks
  before sleep: the new generation asks logind whether a sleep is under way, and the old
  one's sleep inhibitor holds logind a few seconds longer (narrowed, not closed: the lock
  must be up within those seconds). The reload right after an unlock
  that followed edits made while locked (which opened that window after every such
  unlock) is gone.
- `h2s-shell`: a shell stopped with SIGSTOP (or by a terminal) is no longer killed and
  replaced; a dead compositor whose socket file is left behind is recognised (no restarts
  against it, and none on a new compositor under the same name); the fingerprint helper of
  a shell Quickshell had restarted in place is killed when that shell dies.
- Lock screen: a shell killed right after an unlock comes back locked rather than believing
  the screen unlocked while the compositor may still hold it; asking Hyprland before taking
  a lock back no longer hangs for good when `hyprctl` does not answer.
- Lock screen: the fingerprint no longer stops working after a few minutes on a lock
  nobody touches. Each round the reader's PAM module timed out on its own (30 s) counted
  as a fault, and the fifth broke the fingerprint until the next sleep.
- Lock screen: a middle click can no longer paste the primary selection (whatever was last
  selected on the desktop) into the password.
- Lock screen: Backspace, Delete and the arrow keys no longer split a character beyond the
  basic plane (an emoji) in the password field, which sent PAM an invalid byte sequence.
- Lock screen: the check for a fingerprint reader no longer fails on a warning printed by
  gdbus, takes a user name and a key file name literally, and logs one line per reason.
- Lock screen: a reload of the shell while locked no longer unlocks the screen — the new
  generation takes the lock over (and a new authentication is needed); a hard reload
  restarts the shell, which locks again. Files edited while locked take effect at the next
  file change after the unlock, as before. After a crash, the old shell's fingerprint
  conversation no longer keeps the reader from the new one.
- Lock screen: dead keys and Compose sequences type into the password field (and so does
  what an input method commits). A password with "é" typed as ´ then e was checked as
  "e" — the dead key was dropped — so it was refused, and the plain letter accepted in its
  place. AltGr characters, Caps Lock, the keypad and held keys work as before.
- Screensaver and idle lock: they could fail to come at all. Quickshell's idle monitor,
  given the configured timeout once the settings were read (or any later change), could
  stop reporting idle for good — seen every time in the test bed. Each is now made anew
  whenever its settings change.
- Lock screen: a notification's title or text that looks like markup is shown as written,
  never as rich text (a link drawn, an image fetched while the screen is locked).
- Lock screen: the prompt no longer wakes by itself when the lock appears under a resting
  pointer on a slow first frame; a click in the first moments of a lock counts; the prompt
  fits a small or highly scaled screen, a long password scrolls inside its field instead of
  running over its edge, and a question too long for the field is shown in full above it.
- Lock screen: it worked once per shell. After the first unlock the shell still believed
  the screen locked (Quickshell 0.3.2 never reports a session lock's unlock): a typed
  password was dropped without a word, the fingerprint reader was never asked again,
  `ipc call lockscreen status` said `locked`, the screensaver and "lock after the
  screensaver" never came back, and a prompt left showing at the unlock never woke on the
  next lock. Every lock now starts afresh, and the shell no longer relies on that report.
- Lock screen: "Verifying…" no longer sticks. A methods script that fails, prints nothing
  or hangs (5 s) falls back to a password config of its own; a PAM config that cannot be
  started says "Password check could not start"; a check that never answers is given up
  after 90 s ("Password check timed out"). With a fingerprint reader set up, a typed
  password no longer waits for it.
- Lock screen: keys are no longer lost to focus changes. The key that wakes the prompt is
  typed into it, and so are Enter and Backspace right after it, keys typed while the
  prompt fades in, and keys typed on another screen (they go to the prompt where it is).
  An Enter on an empty field sends nothing. (Dead keys, compose sequences and input
  methods do not work in the field yet.)
- Lock screen: a file written in the shell's folder while the screen is locked no longer
  reloads the shell — a reload unlocked the screen with no password. Changes made while
  locked take effect at the next change after unlocking.
- Lock screen: never unlocks the compositor before it has confirmed the lock — a protocol
  error that a strict compositor answers by killing the shell (the session then stays
  locked for good) and a lenient one by unlocking. The lock waits for the confirmation as
  long as it takes ("Waiting for the compositor…" after 5 s, e.g. a slow screen after a
  suspend); the password can be checked meanwhile, and an unlock — by password or logind —
  shows "Unlocking…" and happens when the compositor confirms.
- Lock screen: Escape no longer dismisses the lock screen without a password, as it did in
  every released version: it now shows a hidden prompt and hides a showing one (emptying
  the field); `loginctl unlock-session` unlocks from another console.
- Lock screen: a password config that cannot be used (PAM refuses to start it, or reports an
  error) no longer makes every password fail for the rest of the lock: the next attempt
  uses the fallback, which is now chosen like the methods script's password config
  (`/etc/pam.d/h2s-shell-password` when readable, else `login` on NixOS, else the shipped
  one) instead of always the shipped config.
- Lock screen: which ways of unlocking the machine has is asked of fprintd over D-Bus, with
  a time limit (4 s), instead of read from `fprintd-list`'s text. A machine without a
  reader or an enrolled finger is no longer asked again at every wake of the prompt;
  fprintd stuck (as it can be around a suspend) no longer leaves a process behind, and is
  asked again later. A security key is offered only when the user has one registered where
  the key's PAM config looks (its `authfile=`, or `~/.config/Yubico/u2f_keys`).
- Lock screen: the shipped password config no longer unlocks an account that has no
  password with whatever is typed (`nullok` removed), and the configs no longer carry
  `account` lines that never ran. On NixOS the module's password config leaves out second
  factors that would make the typed password wait or ask again (smartcard, face, one-time
  codes…; each can be switched back on), and its fingerprint and security key configs hold
  only their own module, so a global PAM switch can no longer put a password prompt in
  them; the key's honours `security.pam.u2f.settings` but never `interactive`.
- Lock screen: a security key config that never works stops being retried after a few
  rounds per lock.
- Lock screen: the field empties only when what was sent is taken; a second Enter while a
  password is being checked is refused and keeps what was typed. The prompt hiding after
  10 s idle no longer cancels a password check under way (a question left unanswered, such
  as a one-time code, still is).
- Lock screen: the prompt follows the screens: when the one showing it goes away (a
  monitor unplugged, a laptop's screen over a suspend) it moves, awake, to another, and a
  screen added while locked gets its own lock surface; a click brings the prompt there.
- Lock screen: the fingerprint reader works again after the computer wakes. Its check was
  started as the machine went to sleep and was dead on waking; now nothing is started
  until it is back, and the reader is looked for again then.
- Lock screen: logind's monitor no longer leaves `gdbus` processes behind when the shell
  crashes, and no longer restarts every 10 s without a logind session; the sleep inhibitor
  is taken again when it is lost.
- Network settings: moving between the network pages no longer stops the new page's
  updates; the popup and the Wi-Fi page no longer stop each other's scanning; a saved Wi-Fi
  password with ':' or '\' shows as it is; a password being typed is never overwritten
  when the shown one hides, and the eye works again after a change; connecting no longer
  holds up every other button for as long as it waits.
- Network popup: "Connect to hidden network" shows "Connecting…" for a name typed with a
  space at its end too.
- Network popup: VPNs are known by their profile's UUID, so two with the same name no
  longer get mixed up, and several can be up at once — each row connects or disconnects
  its own VPN (before, Disconnect took down whichever was found first) and says
  "Connecting…" while it does; a failed connection is reported.
- Network popup: a failed Wi-Fi connection says why (wrong password, out of range, not
  allowed, or nmcli's own words) at once — nmcli's errors were never read, so "Wrong
  password" never showed and a failure waited out a 30 s timeout. Saved networks are known
  by their SSID, and "Forget" removes their profiles by UUID: a profile named otherwise
  than its network was neither shown as saved nor forgotten.
- The count of waiting toasts showed on every screen; it shows on the toasts' screen.
- Music: skipping a paused track (the buttons or a swipe) no longer starts it playing in
  players that do so against MPRIS, such as Spotify — the shell pauses it again.
- `launch.sh --restart` (`h2s-shell --restart`) closes every running copy of the shell, not
  only its own folder's: restarting the package's copy with a checkout running
  (`H2S_SHELL_DIR`) left two shells.
- On-screen keyboard: it shows when you tap a text field in a popup opened by touch and
  hides when you tap anywhere else, as in a browser; tapping it keeps the popup and the
  field. The same for the reply field on a notification. A popup opened by touch closes on
  a tap outside it, and that tap no longer goes on to the window beneath. Fields say what
  they are — digits for dates and times, password for passwords — so the keyboard can pick
  its layout; a tap anywhere on a field's box focuses it. In the settings window the
  keyboard hides after a field too, with Qt 6.12.
- Calendar: the + and refresh icons take a tap from around them, not only on the glyph.
- A hover popup no longer closes when the pointer goes back from it onto its bar widget.
- Touch: a tap on a bar widget opens its popup even when the widget opens it on hover —
  such a popup opened by a finger used to stay open for good. A popup opened by a tap
  closes on a tap outside it and the bar, and takes the keyboard (a text field in it gets
  typing, the on-screen keyboard too) without the pointer over it. Popups opened by the
  mouse behave as before; one opening on hover does so 60 ms later.
- Settings: the list of pages scrolls when the window is too short for it (a small
  laptop screen); the pages at the bottom could not be reached.
- Bluetooth stays off after a restart when you left it off. BlueZ powers the adapter on
  whenever it starts; the shell now puts back the state it was last in.
- Google Calendar: losing the network (e.g. right after waking the laptop) no longer signs
  you out; only a sign-in Google itself has expired or revoked asks for a new login.
- Music: the popup no longer opens short and grows to its height after.
- A popup closed before it had appeared (another screen's opening at that moment) no
  longer stays open for good, its widget lit and deaf to clicks.
- Bar popups: each opens on its own bar's screen. They went to the screen with the focus,
  which at the top happened to be the bar's.
- After a review of the day's changes:
  - Music: the ring round the cover no longer stays hidden for good when the cover fails
    to load or its colours cannot be read; no small copy of the last cover shows where
    the next has none; the cover's colours are read only when they are used.
  - Music: dictation pauses every player that plays, hidden ones too, and resumes them.
  - Music: the player list shows while any player is hidden, even with no other.
  - Music: the ring round the cover is no longer cut at the top, and a glow no longer
    spills outside the popup in any layout; the edge layouts follow the popup's real
    edges at the bar's end.
  - Music: cava keeps running through pauses instead of restarting each time.
  - Music: a player's icon given as a file path shows.
  - Notifications widget: a reload of the shell no longer makes every notification
    unread (the bell rang until the panel was opened).
  - Notifications widget: a notification its sender replaces (same id: a download's
    progress, what is playing) counts as new and rings — once, if the panel was opened
    since; further updates before the panel is opened again do not ring.
  - Hiding a player never writes into a profile that is not in effect.
- Popups under the middle of the bar (the calendar's top half) took no clicks: the hidden
  launch warning banner still caught them, over every popup there.
- Music panel: the seek bar shows. It had been there all along, 0 px tall.
- Music panel: playerctld no longer shows as a second copy of the last player used.
- Music panel: showing a paused player while another plays, the visualiser falls flat
  instead of moving to the other's sound — smoothly, at the visualiser's frame rate, in
  half a second (it fell in 10 steps a second, for up to two seconds).
- Notifications: replying from the notification works. Apps that can take a reply (chat
  apps, say) now get a reply field on the card — in the panel and on the toast — with
  their own hint text; Enter or Send sends it, Escape clears it. A toast takes the
  keyboard only while its reply field is under the pointer or being written, and does
  not count down meanwhile. The field never showed before, and the shell did not tell
  apps it could take replies.
- Tooltips no longer fail to open when what they say changes at the moment they are
  asked to show.
- Screensaver: notification previews show the text, no longer the body's HTML drawn
  as is (which could load images from the network).
- Wi-Fi: a password typed into an open network row stays with that network when the
  list refreshes; it used to jump to whichever network took the row's place.
- Wi-Fi: a network seen through several access points — on two bands, or a mesh — is one
  row, with its strongest signal and every band it is on, instead of a row for each.
- Notifications: an icon the icon theme lacks shows nothing instead of a purple
  checkerboard.
- Notifications: a toast whose button was clicked keeps its content while it slides
  away; it used to empty first, as the notification closes the moment its action runs.
- Toasts no longer stop counting down after the shell reloads its files: a toast removed
  by the reload stayed first in line, and the ones after it waited for it for ever.
- Calendar: events of a read-only calendar (a holiday calendar, say) have no edit and
  delete buttons, which Google would refuse anyway, and new events can only go to
  calendars that can be written to.
- Calendar: editing an event keeps its dates. It used to move to the day selected in the
  calendar — a multi-day event edited from its second day became a one-day event there,
  and one going past midnight could not be saved at all.
- Calendar: an event's times are sent with the time zone offset of its own date, not
  today's, so an event across the end of summer time no longer lands an hour off.
- A tray menu opening with no menu open comes in from the bar like every other popup;
  it used to slide in sideways, as when switching from another icon's menu.

## [2.0.0] - 2026-10-31

Themes: the shell's look — colours, fonts, shapes, animations and the bar's geometry —
moved out of the profiles into theme files, edited in the settings window's new Appearance
tab. Major because the bar's geometry is migrated out of the profiles into themes, and
`qs ipc call settings openPage` now takes a page's id.

### Added
- Curves page: the graph pans and zooms freely — drag its background to move around,
  scroll to zoom in at the pointer (up to 20×), double-click off the curve to fit it
  again — for working on fine detail.
- Text selection colours in themes (Colors → Text: Selection, Selected text), used by every
  field and selectable text: the default is the dark accent with white text, instead of
  Qt's navy that most fields fell back on.
- Themes set the shape of every kind of element — corner radii, padding, spacing, border
  widths — by kind: bar cells, workspace pills, popups, rows, list items, dropdowns,
  buttons (general, save, cancel, delete, icon), pills, fields, notification cards and
  toasts, the volume OSD, the message pill, tooltips, the settings window, calendar days,
  checkboxes, the lock screen (notes/plans/themes-stage7.md). New: borders along the
  bar's edge facing the desktop (following it if the bar moves to another edge), around
  popups — one line down their curved ears, sides and bottom, open where they join the
  bar, so it carries on from the bar's — and around bar cells, toasts, the volume OSD and
  the message pill, each with its own width and colour (none by default). The Bar page sets the cells' margin, the widgets' spacing and
  the bar's border.
- Theme files: `~/.config/h2s_shell/themes/<name>.json` sets colours and fonts over the
  built-in look, can `extend` another theme and take colours from a palette file
  (`colorsFrom`, e.g. from matugen). The setting "Theme" picks one per profile; files are
  watched, so an edit applies at once.
- Animations by role: every animation takes its duration and curve from the theme
  (`durations`, `curves`: hover, state, expand, popup, enter, exit, move, slide, fade,
  value, heartbeat, pop, pulse, spin, …). Per profile: "Animation speed" and "Reduce
  motion", for now on the General page with the theme name.
- Colours change smoothly under the pointer (bar cells, tray icons, buttons, list rows,
  sliders, links — the "hover" animation role), and the workspace buttons fade between
  focused, active and hovered ("state").
- Switching to a profile with another theme (Power save on battery, say) slides the bar
  into its new shape ("slide"); the space kept free for windows changes at once.
- The notification bell fades to the accent and jumps when a notification arrives; the
  dictation icon fades between its states; volume sliders and the volume OSD follow the
  volume keys smoothly ("value"), while dragging stays immediate.
- Changing theme fades the colours over ("themeChange"), also when a theme file is changed
  by another program, such as matugen; edits from the settings apply at once.
- Tray icons grow in when an application adds one ("enter"); networks and Bluetooth
  devices found by a scan fade in, and re-sorted networks slide to their place ("move").
- Settings: the mark of the selected page slides to the new one and the page fades in;
  page names highlight under the pointer.
- Calendar: months slide past each other, the new one coming from its side, and the selected day and
  week move smoothly. Music: a new track's title and cover fade in.
- When a profile change adds or removes widgets on the bar, they grow in and shrink away
  ("enter", "exit"), and the widgets beside them slide over. The lock screen fades in,
  and waking it fades the notifications out and the password prompt in.
- A curves library, `~/.config/h2s_shell/curves.json`: named cubic Béziers
  (`"springy": [0.3, 1.6, 0.4, 0.9]`) that a theme's `curves` can use by name, alongside
  Qt's own (OutQuad, OutBack, …). Watched, like themes; an unknown curve falls back to
  OutQuad and is reported.
- Settings → Curves: an editor for the curves library — a graph with two draggable control
  points (scroll to zoom), exact numbers, a looping preview against a second curve with
  a dot following each curve on the graph, new curves blank or copied from Qt's, rename
  (themes using the curve follow), delete (asking first), and where each curve is used.
  Curves can have more points: double-click the curve to add one, select a point to
  type its position, remove it, or switch off "Smooth" for a corner there.
- Settings has two tabs: Behaviour, whose pages edit a profile (picked at the top of the
  sidebar, which also says which theme that profile uses, a click away), and Appearance,
  whose pages edit a theme (picked the same way, starting at the edited profile's theme,
  saying which profiles use it, with "Preview" to try the theme on the whole shell while
  editing it — saved nowhere, the theme list locked meanwhile, ended by "Stop preview",
  leaving Appearance or closing the window). Appearance's first page, Themes, shows who
  uses the picked theme and what is wrong with it, sets what it extends, and makes a
  new theme (extending it, or as a copy), renames it (themes and profiles follow) or
  deletes it (asking first; profiles using it go back to the default theme). Curves moved
  into the group.
- Settings → Appearance → Colors: every base colour of the picked theme, by group, with
  what it is for and where its value comes from (set here, inherited, a palette, built
  in), and a colour picker (saturation and brightness, hue, opacity, hex). Changes are
  drafts, kept in `~/.config/h2s_shell/theme-drafts/` until saved — across restarts too:
  the page has Save and Cancel, a banner offers to save or throw away all of a theme's
  changes, ✎ marks the pages and themes with unsaved changes, and Preview shows a theme
  with its changes (also the theme in use, when it has some). Reset returns a colour to
  the inherited value; Undo takes back one colour's unsaved change.
- Settings → Appearance → Fonts: the theme's font family, picked from the installed fonts
  (searchable, each shown in itself), and its 13 sizes, each with a sample, a slider,
  where its value comes from, Reset and Undo; drafts like colours. Warns when the bar's
  larger icons would not fit its cells.
- Settings → Appearance → Bar: the bar's size, margins and corners, moved from the Bar page
  (which keeps the widgets) into the theme's pages, as drafts with Reset and Undo.
- Settings → Appearance → Animations: each animation role's duration and curve (a
  popup's two), from the curves library or Qt's, with where each comes from, Reset, Undo
  and a preview that plays it; drafts like the other theme pages.
- Settings → Appearance: Widgets (bar cells, workspace pills, tray icons), Popups, Controls,
  Notifications and Other pages — every shape token of the theme (radii, padding,
  sizes, border widths) with a slider, where its value comes from, Reset and Undo, as
  drafts. Border colours are in Colors → Borders.

### Changed
- Calendar: deleting a single event asks on its ✕ button, which turns into "Delete?"
  with a × to cancel, like every other delete; an event of a series still offers what
  to delete.
- One checkbox everywhere: the calendar list in the calendar settings uses the event
  form's look (14 px, a muted outline when unchecked), and every checkbox takes the
  keyboard focus on Tab and toggles with Space.
- Popups, the calendar and the settings window's sidebar grow with the theme's text size;
  each popup's width (and all of them at once) can be widened or narrowed in Appearance →
  Popups → Widths, shown with the width it comes to. Wi-Fi rows grow with their content,
  the events header gives way when narrow, and the event form's repeat row wraps instead
  of running out of its card.
- Save buttons take the confirm colour (adding) or the second confirm colour (saving a
  change), as the event form's did; the event form's buttons are the shared ones. Profile
  cards have the common card radius (6), the toast queue badge the toast's (8).
- Dropdowns and pickers float over the content instead of pushing it down: the event
  form's repeat frequency and calendar, the Bar page's "+ Add widget", the hardware
  sources' "+ Add source", the Theme setting's suggestions. They open upwards when there
  is no room below, and a click elsewhere closes them.
- Text fields are one shared component everywhere (settings, Wi-Fi, the event form, the
  colour and curve editors): the same look, focus outline and placeholder; password
  fields have an eye to show what is typed.
- The event form's time fields: "HH" and "MM" placeholders in their own segments; one
  minute digit means tens ("3" → 30), one hour digit that hour ("1" → 01), also when
  clicking away; an hour that can only be one digit moves straight on ("7" → 07); Up and
  Down step the value; Backspace in empty minutes goes back to the hours.
- Buttons, pills and switches are shared components everywhere: the Network, Bluetooth
  and calendar settings buttons, the preset and choice pills, the event form's choices,
  every on/off switch, the slider's tooltip. Small changes follow: Network VPN, scan and
  Bluetooth buttons have the common rounded corners and height; a running scan shows as
  a filled button; disconnecting is red under the pointer.
- Forgetting a Wi-Fi network or a Bluetooth device, and disconnecting the Google account,
  ask first, like every other delete.
- Settings pages are named by id: `qs ipc call settings openPage` takes a page's id
  (`profiles`, `bar_appearance`, …), not its label.
- Ready for larger fonts: buttons, pills, fields, icon buttons, Bluetooth device cards,
  event cards and calendar rows grow with their text instead of letting it spill out
  (today's sizes are the minimum, so nothing changes at the default sizes); long names in
  the settings sidebar and label columns are cut with "…"; the notification bell and
  the small symbols (×, ✓, ▾) take their font from the theme.
- A click anywhere in the settings window or a popup — the background too — takes the
  focus from a text field; before, only clicking another control did. (It watches clicks
  without a cursor of its own, so controls keep their pointing-hand cursor.)
- The "Theme" setting suggests the theme files as you type (and "default"), and warns
  when the name has no file.
- Deleting a profile, a widget preset or a curve asks the same way everywhere: the button
  turns into a red question with a "×" attached to cancel.
- Animations of a kind share one timing: expanding and collapsing takes 150 ms everywhere
  (was 120–200), a notification card arrives in 250 ms (was 200), the password field's
  colour changes in 150 ms (was 120).
- The bar's geometry (height, reserved space, offset, margins, padding, corners) is part
  of the theme instead of a profile setting. Each profile that had its own geometry gets
  a theme named after it with those values (Power save's extends Full's), so the bar
  looks as before. The sliders on the Bar page edit the theme of the profile being
  edited — and so every profile that uses it.
- Colours are named by role and come only from the theme: one red, one green and one
  blue where there were several shades (the disconnect buttons, the lock screen's error
  and the calendar's connection status change shade slightly).

### Fixed
- Bluetooth: Scan scans. `bluetoothctl scan on` exits at once in recent BlueZ, and the
  scan ended with it, so nothing was ever found and "Scanning…" never showed.
- Curves page: the preview's second square moves with the curve compared with; both used
  to move with the curve being edited.
- Music visualiser: the right channel of the vertical layout stays at the panel's edge
  when popups are made wider or narrower; the channels' order no longer depends on how
  often the canvases happened to repaint.
- The notifications popup ends 16 px above the bottom of the screen, whatever the bar's
  height; it used to assume a 40 px bar and, with a taller one, run past the edge.
- Scrolling by notches (sliders, the music widget's next/previous track, the music
  panel's player) went the wrong way on the first notch, and on the first notch after
  turning the wheel back.
- Wi-Fi list: an open network and its typed password stay with that network; after a scan
  or a connection they used to jump to whichever network took its place in the list.
- The calendar's and the hardware popup's left curved corner no longer shows a faint seam
  next to the panel (the popup now comes to rest on whole pixels; while moving it does
  not, which made it jump at the bar's end).
- Notifications on the lock screen and screensaver have the same padding below as above.
- Switching from a taller popup to a shorter one animates the height too; the panel's
  background used to drop to the new height at once.
- Numbers no longer spill out of their columns: a slider's value ("3000 ms"), the
  track's times, mixer volumes, the volume OSD's "100%", the hex and coordinate fields.
- The lock screen never came on: locking and unlocking were lost when its settings
  became per profile.
- The screensaver's first fade after start keeps its full duration.
- Settings: the selected page's mark always slides (it sometimes jumped), and the Bar page
  no longer logs binding loops while editing a profile whose theme is not in use.
- The first opening of a popup no longer loses part of its animation: panels are
  compiled in the background after start, and new content renders once before the
  animation starts (the calendar dropped a third of its frames).
- Moving from one widget's popup to another's: the popup no longer crawls after its
  size at the right end of the bar, and the new content fades in as the popup moves
  instead of jumping in first.
- No more warnings in the log when an app stops playing with the sound popup open.

## [1.1.0] - 2026-10-29

### Added
- Toast settings, per profile: show toasts at all, how long each stays, and one at a time
  or a column of them (with how many). A column shows the newest on top, and only the
  oldest counts down, so they leave one at a time.
- Notification privacy on the screensaver and the lock screen, separately and per
  profile: show notifications in full, title only, or the app alone.

### Fixed
- The screensaver's start and end commands now run — they could be set but nothing ran
  them. They follow idle time rather than the screensaver's visibility, so locking the
  screen does not count as coming back, and they can differ per profile.
- Popups stay under the bar when it does not reach the screen edges, stopping short of
  its rounded ends; switching between popups of different widths keeps the edge they
  are held against and animates the width instead of jumping.
- A binding loop when a profile switched the system power profile.

## [1.0.0] - 2026-10-29

The first numbered version: the shell as it stands after the 2026-10 cleanup, which
began in February 2026 as a single Hyprland bar.

### Added
- **Shell profiles.** Every setting can differ per profile — named sets of overrides that
  apply while their conditions hold (on battery, battery level, power profile, screen
  locked, fullscreen window, open popup), layered in list order. New configs start with
  Full and Power save. A setting can be pinned as global, and some (debug switches, the
  dictation socket) always are. The settings window picks the profile every page edits
  and shows where each value comes from.
- **Performance settings:** polling rates for hardware, temperatures, disk and network,
  GPU load sampling, a graph heartbeat, the visualizer frame rate, and the system power
  profile — all per profile.
- **Widget presets** (formerly "widget profiles"): a shared library of widget settings,
  with usages, rename and delete; clock, hardware and workspaces may appear more than
  once in a section.
- History graphs for every hardware source and for network throughput (download and
  upload), with a heartbeat wave on each sample.
- Every GPU is listed with its own load, VRAM and temperature.
- Calendar load errors are shown in the panel, with a retry.
- `qs ipc call settings open | openPage <page> | toggle | close`, and
  `qs ipc call profiles simulate | clearSimulation | status`.
- The shell's version in the settings sidebar.

### Changed
- The config moved into profiles; settings from older configs are migrated once, with a
  backup next to the config.
- Network state follows NetworkManager's events instead of polling `nmcli`, and the
  hardware sources read `/proc` and `/sys` directly instead of spawning `cat`.
- One settings window for the whole shell instead of one per monitor.

### Fixed
- Months of random crashes: no live arrays bound to `Repeater.model`, and popup content
  is created after its window.
- The shell freezing while the calendar loaded, token refresh, all-day events, Wi-Fi
  names containing colons, notification action buttons, and many smaller issues — see
  the git history.

### Security
- The Google client secret no longer appears on a process command line.
- The config directory is restricted to its owner (700, files 600).
- Workspace names are escaped in Hyprland dispatches.
