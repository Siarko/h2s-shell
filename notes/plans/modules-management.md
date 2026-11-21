# Managing modules: Settings → Modules, installing and updating, the trust model, the safe-mode banner

Tracker: order of work step 1 (second item: this plan), step 8 ("Modules closed for now"),
and the parts of step 13 that land here (the trust text, the confirmation, where a module
comes from). Decisions: [decisions.md](../decisions.md), "Direction, modules and trust"; the
owner's answers to this plan's questions are in §10, the Views decision this plan brings in
§4.1.
Mockups: `~/src/h2s-mockups/modules-settings-planned/` (kept outside the repositories; open with
`qs -p <that folder>/shell.qml`, scenes switched at its top; `shoot.sh` takes the screenshots
in a private compositor). The first version, before the answers, is kept as
`modules-settings-planned-v1/`.

## 1. What exists

- **Discovery** is the launcher's, before every start: `scripts/launch.sh:286` `module_roots`
  (`<dataHome>/h2s-shell/modules`, then each `<data dir>/h2s-shell/modules`), `:296`
  `find_modules` (`H2S_SHELL_MODULE_PATH` first, then the roots; canonical paths, bounded),
  `:338` `discover_modules` → `H2S_SHELL_MODULES`. The shell itself never searches: a module
  put on disk while it runs appears only at the next start.
- **Precedence**: the first with an id wins, later copies are `duplicate` with `shadowedBy`
  (`singletons/ModuleMergeRules.qml:19`). The winner carries nothing saying it replaces one.
- **The host**: `singletons/ModuleHost.qml` — `load()` :250 (all modules again), `unload()`
  :280, `setEnabled()` :293 (writes `Config.disabledModules`, `singletons/Config.qml:39/104`;
  a module is on unless listed), `describe()` :532, the start guard :944, `_publish()` :1419
  (the status per module). States: `ModuleRules.states` (`singletons/ModuleRules.qml:498`:
  loaded, disabled, failed, incompatible, missing-program, missing-module, duplicate,
  pending, safe-mode), decided by `ModuleMergeRules.stateOf` :41; the status record is
  `ModuleMergeRules.statusOf` :435 (id, name, version, api, description, directory, state,
  enabled, errors, warnings, deprecations, missingPrograms, setupHints, shadowedBy).
- **The manifest** (`module.json`, `singletons/ModuleManifestRules.qml`): an unknown top-level
  field is a warning ("kept; a newer shell may know it"), so a module can carry a field before
  the shell reads it. `uses` (API 1.18/1.30): `{ <id>: "major.minor" }` or
  `{ <id>: { version, optional } }` — ids and versions only, no address to get one from.
- **Privileged runs**: `module.privileged.start` and `PrivilegedAction` (`api/Api.qml`
  "Running as administrator"): any module may ask; the prompt names the module, `what` and
  the command. Nothing in the manifest says a module will ask.
- **Dependencies**: `ModuleMergeRules.dependencyPlan` :131 (hard and soft `uses`, load order);
  reasons already land in `errors` ("needs module tailscale 1.0: turned off") and soft notes
  in `warnings`.
- **Icons**: `components/ModuleIcon.qml` (glyph, SVG, picture, else the name's letter),
  fed by `ModuleHost.icons`. Nothing draws it yet but tests: Settings → Modules is its place.
- **Pills**: `components/StatusPill.qml` — parts (an icon and a count) each with a `tip`
  shown on hover (`HoverTip`) and a `line` when the pill is expanded.
- **Side panel**: `components/SideDrawer.qml` (the core's) and `api/SidePanel.qml` (modules',
  1.34): a panel from the right over a settings page, the page dimmed.
- **Safe mode**: the launcher's (`launch.sh:607`, two deaths within 30 s →
  `H2S_SHELL_SAFE_MODE=1`) and the start guard's (`ModuleFileRules.qml:420–466`, two
  in-place relaunches). `Modules.qml:116` sends one notification "Started without modules:
  <reason>"; no banner. Leaving safe mode takes a restart.
- **IPC**: `Modules.qml:165` — `modules list` (JSON), `modules setEnabled <id> <bool>`.
- **Settings**: a "Modules" group exists in the System tab only when a module has a page
  (`ModuleMergeRules.qml:612` `modulesGroup`, `:621` `mergeSettingsPages`); a group opens its
  first child. No page of the core's own. No modal of any kind in the Settings window; the
  one window-level strip is `panels/settings/KeepSettingsBar.qml` (network pages).
- **Storage today**: modules' own directories (whoever put them there), data
  `<dataHome>/h2s-shell/module-data/<id>` (made by the host, never removed), stores
  `<configHome>/h2s_shell/modules`. The owner's Tailscale module is a link in the user root
  (to a checkout of the module repository), and it uses privileged runs.
- **Banners**: `hud/StartupWarning.qml` (title, body, ×; `Hud.qml:76`), no buttons.
- **Packaging**: NixOS copies the tree to `$out/share/h2s-shell` (`nix/package.nix:80`), git
  is a runtime input (:43); Arch's `install.sh:15` clones into `~/.config/quickshell/default`.
  No module is built in yet, and there is no place for built-in modules outside the scanned
  tree (`notes/plans/api-next/versioning.md` §11).

## 2. The trust model, as it should stand in docs/ (draft)

> ### Modules and trust
>
> A module is QML and JavaScript that the shell loads into its own process. Nothing
> separates it from the shell: a module can do what the shell can — read and change your
> files, run programs as you, use the network, and see what the shell shows and what you
> type into it. The lock screen's password field and the password prompt for administrator
> actions run in the same process, so a module could read what you type there too.
>
> **What the shell checks** before it loads a module: that its manifest is well formed and
> asks for an API version this shell has; that every file it names lies inside its own
> directory and is not too large; that its icon refers to nothing outside itself; which
> programs it needs and where they were found; whether it reaches into the shell's
> internal parts; and that only a module whose manifest says it runs administrator actions
> asks for them. These checks catch mistakes. They do not make a module safe: a module that
> wants to get around them can, because it runs inside the shell. A module that makes the
> shell crash twice at start is not loaded the next time (safe mode).
>
> **What protects you.** Built-in modules come with the shell and are reviewed with it.
> Modules your system's administrator installed (a NixOS configuration, a distribution
> package) are theirs to answer for. Any other module is its author's work, not the
> project's: the shell says so and asks before it first turns one on, and asks again when an
> update comes from a different source or starts to run administrator actions — also when
> updates are automatic. A module asks for administrator rights only through the shell's
> password prompt, which names the module, says what the action is for and shows the
> command; for a module that is not the project's, that text is the only protection — read
> it, and cancel when it does not match what you just did. The shell never installs or turns
> on a module without your click, updates modules by itself only when you turn automatic
> updates on, and never asks for a password by itself.
>
> **What to install.** Treat a module like a program you run as yourself: install it only
> from someone you trust, from a repository you could read, and pin it to a tag rather
> than a branch that can change under you. Read what changed before you update; with
> automatic updates, read it afterwards — the notification opens it.

The confirmation shown when a module that is neither built in nor installed by the system is
first enabled (UI words): "**<Name> is not part of h2s-shell.** It runs inside the shell
with your rights and could read anything the shell sees, your lock screen password included.
Enable it only if you trust where it comes from." — buttons "Enable" (`save`), "Cancel"
(`cancel`). The update consent (§6.4) uses the same box with its own first line.

## 3. Where a module comes from

A pure rule, `ModuleInstallRules.sourceOf(directory, link, roots, records)`, from the
canonical directory, whether the entry in the root is a link, and the record of what the
shell installed:

| Source | Found in | Card says | Consent | Actions |
|---|---|---|---|---|
| `builtin` | the shell's builtin place (below) | "Built-in" | never asked | enable/disable, reload |
| `system` | a system data dir (`/usr/share/h2s-shell/modules`, NixOS profiles), anything else under `/nix/store` | "Installed by the system — not part of h2s-shell" | counts as given | enable/disable, reload |
| `repository` | user root, link the shell made into `module-versions/<id>/`, with a record | "From <host/path> @ <ref>" | asked | enable/disable, reload, check, update, switch version, backups, remove |
| `folder` | the same, record of a copied folder | "Copied from <path>" | asked | enable/disable, reload, update (copy again), switch version, backups, remove |
| `user` | user root, no record: a folder placed by hand, or a link | "Your copy" / "Your link → <target>" | asked | enable/disable, reload, remove |
| `developer` | `H2S_SHELL_MODULE_PATH` | "Development path" | never asked | enable/disable, reload |

**Builtin places** — outside the tree Quickshell scans, found from the shell's own
installation (the launcher passes the root; never from a place a module could name):
- NixOS: in the package, `$out/share/h2s-shell-builtin` (`nix/package.nix`; the wrapper
  hands it to the launcher).
- Arch now: `~/.local/share/h2s-shell/builtin/`, filled by `install.sh` and by the shell's
  own update — never by the user, never by Settings → Modules (the page writes only the user
  root). Later, with an AUR package of the shell, `/usr/share/h2s-shell/builtin`; other
  packages' modules go to `/usr/share/h2s-shell/modules` (`system`).
Built-in is trusted by design: never asked, no Remove (an update of the shell brings or
drops them). Some come off: the builtin place holds `builtin.json`, `{ "off": ["<id>", …] }`;
a module listed there is off until the user enables it (remembered in `Config.enabledModules`,
the counterpart of `disabledModules` for what starts off).

**System-installed** modules (an administrator's AUR package, a NixOS configuration) are
consented by whoever installed them: they run at once, read-only (no Remove, no Update, no
Switch version: "Change it in the system's configuration").

**Replacing**: the winner of an id gets `replaces: [{ directory, source, version }]`
(precedence extended), shown on its card: "Replaces the built-in copy (1.2.0)" — the
decision's "shown when a user's copy replaces a shipped one".

**Remove** is offered for everything the user root holds — installed by the shell or not,
folders and links (§4, "Remove"). It is never offered for `builtin`, `system` or `developer`.

## 4. Settings → Modules

The System tab's "Modules" group becomes permanent; its first page is the core's
`modules` page ("Installed"), modules' own pages follow under it.

**At the top**: "Check all" (one `ls-remote` per repository module, §6.3) beside
"Update all (n)" once updates are known (only with automatic updates off); under them,
while a queue runs or has news, the update queue (§6.5); in safe mode, the banner (§7). Over
every page of the Settings window, while a restart is pending after "Later", the restart
banner (§6.5).

**The list**: one `SettingsCard` per module (a `KeyedModel` keyed by id; duplicates are
shown inside their winner's card, not as cards), **enabled modules first, then disabled
ones, each group by name** (`ModuleInstallRules.listOrder`). Closed: the icon
(`ModuleIcon`), the name, a subtitle "version · source".

**On or off is not a pill**: an enabled module's name (and icon) is in the accent colour, a
disabled one's muted, and its subtitle ends "· Off" — together with the order, that is the
on/off state; the main button ("Disable" / "Enable") says what a click changes. Warnings and
deprecations are **marks** beside the name — the icon and a count in the kind's colour, its
tip on hover ("1 warning", "1 deprecated API use"); no click. A `StatusPill` stands on the
name line only for a state worth attention:

| State | Pill | Kind |
|---|---|---|
| loaded, disabled | none (the name's colour and the order) | — |
| unconfirmed (new, §5) | "New — off" | warning |
| update waits for consent (§6.4) | "Approval required" | warning |
| update refused (§6.4) | "Update not finished" | warning |
| failed / incompatible | "Failed" / "Needs API 2.x" | danger |
| missing-program / missing-module | "Needs gcalcli" / "Needs Tailscale" | warning |
| pending | "Starting…" | muted |
| safe-mode | "Safe mode" | warning |

A mark's count always has a tip saying what it counts: "1 warning", "2 warnings",
"1 deprecated API use" (`ModuleInstallRules.marks` words them with the count). The two update
pills stand beside any other (the old version keeps running).

**A pill takes no click here**: hover shows its tip; a click on it neither expands it nor
opens the card. The shared `StatusPill` gains `expandable` (default `true`, as today; the
page sets `false`), and its click area stops the click from reaching the card's header —
the public `api/StatusPill.qml` takes the same property in API 1.36.

Its button row: the main button — "Disable" / "Enable" (one decision from the state:
`ModuleInstallRules.actionsFor(status, source, context)` returns labels and effects
together); "Update to 1.3.0" when one is known and downloaded (automatic updates off);
"Remove" last. Opened: the description; source (address, ref, commit, installed when; or
the path; for `system` "Installed by the system — not part of h2s-shell"); "Installed for
Notes" when it came in as a dependency (§6.9); API asked and the shell's; whether it runs
administrator actions (§6.4, the manifest's words); dependencies — "Needs: Tailscale 1.0 —
on" (hard), "Can use: Weather 1.x — not installed" (soft), "Used by: Exit map"; programs,
missing ones with the manifest's `setupHints`; then errors (`Notice` danger, one per line),
warnings and deprecations ("Uses Api.module(), which goes in the next tightening"), all as
plain text, capped; "New in this version" after an update (§6.6); the data directory's
path; buttons "Reload", "Check for updates", "What's new" (the side panel, §6.7), "Switch
version…" (§6.8), "Backups…" (§6.10).

**Above the list**, a section "Add a module": one field ("Repository address or folder"),
"Choose folder…" (the platform's folder dialog), "Install". Under it, while an install runs,
its step and progress (§6.2) and Cancel; then the preview (§6.2, §6.9).

**Actions and what they do**
- *Enable*: `ModuleHost.setEnabled`; an unconfirmed module shows the confirmation (§2, §5)
  first.
- *Disable*: no running dependents → the button's own question, `DeleteButton` kind
  `warning`, "Disable?". With running dependents → a warning modal (§4.1): title "Disable
  Tailscale?", body "These modules need it and are disabled too:" and the list
  ("Exit map"), buttons "Disable" (`warning`) and "Cancel".
- *Reload*: the module off and on (a new main); when its files changed on disk (an update,
  an edit) and Qt's component cache or its singletons keep the old code, the card says
  "Restart the shell to load the new files" with "Restart shell" (§6.5; M2 measures which).
  "Restart shell" is always the user's click, never automatic.
- *Install*: §6.2, §6.9. *Update*: §6.3–6.6. *Switch version*: §6.8. *Backups*: §6.10.
- *Remove*: a plain button; its click opens a danger modal (§4.1) over the Settings window:
  title "Remove Player?", then the body by what it is —
  - installed by the shell: "Deletes Weather 1.2.0 and the kept versions (1.1.0)."
  - placed by hand: "**Not installed by the shell.**" / "Deletes the folder
    ~/.local/share/h2s-shell/modules/player."
  - a link: "**Not installed by the shell.**" / "Deletes only the link; ~/Projects/h2s-backup
    stays." (the link only, never its target: `unlink`, never a recursive delete through it)
  - modules that need it: "These stop working: Exit map." (hard) / "These lose a feature:
    …" (soft) (§6.9)
  - `Checkbox` "Also delete its data and settings", unchecked each time the modal opens:
    then the data directory, its store, its backups and its `mod.<id>.*` settings in every
    profile go too;
  - `Checkbox` "Also remove Clipboard (installed for Notes, nothing else uses it)" per such
    dependency, unchecked (§6.9).
  Buttons "Remove" (`delete`) and "Keep" (the cancel). "Remove" disables the module, moves
  what it deletes to staging (same filesystem), deletes it, drops its record and
  acknowledgement. Without the data box, data, store, settings and backups stay (a later
  install of the same id finds them). The modal carries the module's id and directory (its
  subject) and acts on those; if the module changes while it is open (reloaded, removed by
  IPC), it closes as cancelled.

**Privileges: none.** Every file the page writes is the user's own, under the data home;
nothing runs as root, no `pkexec`, no `sudo`. Built-in and system modules are read-only in
the list.

**Never automatic**: installing, removing, enabling a module found on disk, deleting data,
following a link to delete, running anything from a module's files during an install (no
hooks, no submodules, no build step), asking for a password, restarting the shell, acting
while the session is locked (IPC refuses, the window is closed then). Checking, downloading
and switching to a new version run by themselves only with automatic updates on (§6.3), and
never past a consent.

### 4.1 The Settings modal (a new shared element)

A question that needs more than a button's word — a list of what else it affects, a
checkbox, an explanation — opens a modal over the Settings window. It is a shared element
of the core, not of this page.

- **Component**: `components/SettingsModal.qml`, hosted once per Settings window by
  `components/SettingsModalHost.qml` (as `SidePanelHost` hosts side panels), filling the
  window's content area. One open at a time; a request while one is open is refused and
  logged once (a question never replaces another under the user's pointer).
- **Looks**: a centred panel with an opaque background, a border in its kind's colour, a
  header (icon and title), a body, a button row; behind it the window dimmed with
  `Theme.modalDim`. Kinds `danger`, `warning`, `success`, `info` through
  `ThemeRules.modalLook(kind)` → `{ border, icon, titleColor }` (theme colour names, as
  `buttonLook`); the dimming is a colour token of its own, `Theme.modalDim` (in the theme's
  colour sets, under "Backgrounds"; default black at 55 %, clearly visible) — never `scrim`,
  which is the lock screen's opaque black; sizes and spacing from a new theme group `Theme.modal` (`radius`,
  `padding`, `borderWidth`, `widths: { s, m }`). Nothing literal: every colour and size from
  the theme, so themes restyle it.
- **Behaviour**: it blocks clicks through (a click on the dimmed window does nothing); the
  "×" in the header, Escape and closing the window act as the cancel; the session locking
  closes it as cancelled. Buttons: any number, but always one cancel — `ApiElementRules.
  modalButtons(buttons, cancelLabel)` adds "Cancel" when none is a cancel, keeps the cancel
  last, and makes a modal with a single button an informing one: that button closes it, as
  the "×" does. Focus moves into it (Tab cycles inside), back to the opener on closing.
- **API for the core's pages**: `SettingsModal.ask({ kind, title, body, content, buttons,
  subject })` from any page under the window → the answer `{ button, values }`
  (checkboxes' states); `body` is plain text lines (`Text.PlainText`, text from outside
  capped); `content` an optional Component (a checkbox, a list); `subject` the ids it acts
  on — when the subject goes away, it closes as cancelled. Not in the module API now; giving
  it to modules is an API decision of its own later.
- **Tests**: `ThemeRulesTest` cases (each kind's look, an unknown kind falls back to
  `info`); `ApiElementRulesTest` cases (`modalButtons`: none → Cancel added, two cancels →
  one, cancel last, one button → informing); `SettingsModalTest` (opens; a click on a control
  behind does nothing; "×", Escape and closing the window answer cancel; one-button closes;
  subject gone closes; lock closes; a second request is refused).
- **Views decision, for decisions.md** (to add with the slice): "A question that needs a list
  or a choice opens the Settings modal; a one-word question stays the button's own
  (`DeleteButton`)." The `CLAUDE.md` rule "Deleting from a click goes through DeleteButton"
  then names the modal as the second form (§10b Q3).

## 5. The confirmation (first enabled)

A module that is not `builtin`, `system` or `developer` starts **off** the first time the
host sees it (`unconfirmed`, a new state), until the user enables it through the
confirmation (§2's text). Acknowledged = `Config.acknowledgedModules[id]` (remembered state,
not a preference): `{ source, address, author, privileged }` — the source kind, the address
or path it comes from, the manifest's `author` (§6.4) and whether it was consented to run
administrator actions. It is keyed by id and source, not by the version's directory, so a new
version of the same module keeps it (§6.1). A different source for the same id (a user copy
replacing a built-in one, an install from another address) asks again.

Installing through the page with "Install and enable" is the confirmation (the preview
carries the text, for every module of the chain, §6.9). IPC: `modules setEnabled` refuses an
unconfirmed module with the reason; `modules confirm <id>` acknowledges it (a typed command
is a click).

A hand-placed module (`user`) changes outside the shell (the owner's Tailscale link is a git
checkout). At each load the host compares its manifest with the acknowledgement: when it now
declares administrator actions (or its `author` changed), it is held off as "Approval
required" with the same box as an update's consent (§6.4) — there is no old copy to keep
running.

**Today's modules** (Tailscale on both machines) stay on at the new version without a
question, and no settings migration is needed: a module's state is kept across updates
(§6.1), and the shell's update to the version that brings confirmations is an update like
any other — what was on stays on. Technically, an absent `acknowledgedModules` (never
written) reads as "everything found at this start is acknowledged as it is": the first start
writes the list from what it finds, privileged declarations included. No profile key
changes; a module put on disk later is new and asks. (Tailscale's manifest gains its
`privileged` declaration before the shell starts refusing undeclared modules, §9 slice M1c,
so its first start records it as consented.)

## 6. Installing and updating

### 6.1 Versions on disk, state across versions

- A module the shell installed lives in `<dataHome>/h2s-shell/module-versions/<id>/<version>-<commit7>/`
  (a folder copy: `<version>-<date>`), one directory per version. The user root holds
  `modules/<id>`, a link the shell made to the active version; switching is one atomic rename
  of a new link over it. `sourceOf` calls it `repository`/`folder` only when the record says
  so and the link points inside `module-versions/<id>/`; anything else is `user`.
- Kept: the active version, the one before it (to go back), and at most one that is not
  active (downloaded and waiting, or refused): at most three directories per module. After a
  switch the oldest beyond that is deleted (`ModuleUpdateRules.keepPlan`).
- **State is kept across versions**: everything keyed by id stays — on/off
  (`disabledModules`, `enabledModules`), the acknowledgement, `mod.<id>.*` settings, the data
  directory, the store, the bar's widgets of its types. Before every switch the module's
  configuration is backed up (§6.10). An older version may not read data a newer one wrote:
  the module's to handle; the version list says "older" next to such an entry.

### 6.2 Installing from an address or a folder

- **Source**: a git address (`https://`, `ssh://`, `git@host:path`, `git://`, `file://`),
  optionally with `#<ref>` (a tag, a branch, or a full commit id); or a folder.
  `ModuleInstallRules.repositoryProblem` refuses anything else (`ext::` and `fd::` run
  commands; a leading `-`; control characters; over 1000 characters). The address is always an
  argument after `--`, never in a shell string.
- **Steps, as the page names them**: "Downloading" → "Verifying" → (the preview) →
  "Installing" → "Installed". Each says what it does, never what has not happened.
- **Downloading** into `<dataHome>/h2s-shell/module-staging/<random>` (same filesystem as the
  versions, so moving in is a rename): `git -c core.hooksPath=/dev/null
  -c protocol.allow=never -c protocol.{https,ssh,git,file}.allow=always clone --progress
  --depth 1 --no-recurse-submodules [--branch <ref>] -- <url> <dir>` (a commit id: `init` +
  `fetch --progress --depth 1 -- <url> <commit>`; a server that refuses it is said in one
  line), with `GIT_TERMINAL_PROMPT=0`, `GIT_ASKPASS=` / `SSH_ASKPASS=` empty,
  `GIT_SSH_COMMAND="ssh -o BatchMode=yes"` (never a credential prompt), under a time limit
  and a size cap (a fetch too large is stopped). A folder is copied (`cp -R
  --no-dereference`, then the file check refuses links out). Through the host's
  `CommandRunner`, as the user.
- **Progress**: `ModuleInstallRules.progressOf(line)` reads git's stderr lines ("Receiving
  objects:  45% (120/266), 1.20 MiB | 2.40 MiB/s", "Resolving deltas: …") into `{ phase,
  percent, bytes, rate }`; the page shows a `ProgressBar` with the percent and "1.2 MiB ·
  2.4 MiB/s" — the shared `components/ProgressBar.qml` with `wave: true` while bytes
  arrive, as Taildrop's transfers (the module API's `ProgressBar`, 1.31). Where git gives no numbers (a small repository, `file://`, `ssh` without
  progress) or for a folder copy, the bar is of unknown length and only the step is shown.
- **Verifying**: the host's own file check and manifest rules on the staged directory (no
  new checker): valid, API fits, the id free or held by a copy it would replace (said in the
  preview), files inside; then its dependencies are resolved (§6.9). A module failing here is
  never moved in.
- **Preview** (the confirmation): icon, name, id, version, API (fits / not), source with the
  commit, author (when the manifest names one), whether it runs administrator actions and its
  words for them, the programs it names (found / missing), the dependency chain (§6.9), what
  it would replace, "What's new" (opens the side panel, §6.7), the §2 statement; "Install and
  enable" (`save`), "Install, keep off", "Cancel" (deletes the staging directories).
- **Installing**: rename to `module-versions/<id>/<dir>`, make the link, write the record;
  then the shell runs discovery itself (`launch.sh --discover-modules`, the same code) and
  `load()`s the new list — no restart needed for a new module. Failures at any step leave no
  partial module (§6.9 "A failure halfway"; the page says why, one line).
- **Record**: `<dataHome>/h2s-shell/module-sources.json`, `{ <id>: { kind, address, ref,
  versions: [{ dir, version, commit, fetchedAt }], active, refused, installedFor, checkedAt
  } }`, written by a temp file and a rename; a missing or unreadable record makes the module
  `user` ("unknown", never "fine": no update, no switch; Remove asks as for a hand-placed
  folder).

### 6.3 Checking for updates; automatic updates

- **By hand**: "Check for updates" on a card, "Check all" at the top of the page.
  **Feedback, while and after**: the clicked button reads "Checking…" and is unavailable
  while it runs (a card's line shows a `ProgressBar` of unknown length beside it); "Check all"
  shows "Checking 2 of 4…". Then the result stays visible until the next check or the page is
  left: on the card "Up to date · checked 14:32" / "1.3.0 available — downloading" / "Check
  failed: codeberg.org did not answer"; at the top "2 updates · 1 up to date · 1 failed".
- **The setting** `modules.autoUpdate` (`SettingsSchema`, global, read with
  `Profiles.value`): "Module updates" — "By hand" (default) / "Automatically".
  - *By hand*: a check (by the click) downloads what it finds in the background; the card
    says "Update to 1.3.0", "What's new" opens the new changelog before anything changes;
    "Update" / "Update all" switches.
  - *Automatically*: once a day (not while locked; after a failure with a backoff; logged on
    a change of outcome only; never a prompt) the shell checks, downloads, and switches by
    itself through the queue (§6.5) — unless consent is due (§6.4): that module stops at
    "Approval required" and the old version keeps running. Afterwards one notification
    "Updated: Weather 1.3.0, Notes 0.4.0" (plus "Printers: approval required" when one
    waits); clicking it opens Settings → Modules with the side panel showing the changelog of
    that module, or of each updated module one under another (§6.7).
- A check is `git ls-remote` of the recorded address for its ref (a tag ref: newer tags, for
  "Switch version" and for "a newer tag exists"; a branch: its head). A newer commit is
  downloaded into staging and verified (§6.2's steps, with progress); the old version keeps
  running.
- A version the user refused (§6.4) is not offered again, and never switched to
  automatically; a newer one is.

### 6.4 Consent for an update

`ModuleUpdateRules.consentFor(acknowledgement, record, newManifest, newAddress)` →
`{ needed, reasons }`. Consent is needed — by hand and with automatic updates alike — when:

1. **the source changed**: the address it would come from is not the acknowledged one (the
   user changed it, or installed the id from elsewhere), or the manifest's `author` changed;
2. **it first declares administrator actions**: the running version has no `privileged` in
   its manifest and the new one has;
3. **it brings a module not installed yet** (§6.9) — that one's first confirmation;
4. **it would stop a dependent**: a new major version of a provider that an installed module
   needs at the old major (§6.9).

Not consent, only shown after the update (§6.6): new programs, new modules it uses that are
already there, a new major version with no dependent broken, programs added to an existing
`privileged.programs` list.

**The manifest declaration** (API 1.36, `ModuleManifestRules`):

```json
"author": "Anna Nowak",
"privileged": {
    "why": "Connect, change Tailscale's settings, send files",
    "programs": ["tailscale", "systemctl"]
},
"uses": { "clipboard": { "version": "0.2", "source": "https://github.com/anna/h2s-clipboard#v0.2.0" } }
```

- `author`: optional string, plain text, at most 100 characters, one line.
- `privileged.why`: required in the block, a few words, plain text, at most 200 characters —
  shown on the card, the preview and the consent box.
- `privileged.programs`: names among the module's `requires.programs`/`optionalPrograms`;
  the only programs a privileged run may start (`argv[0]` must be their resolved path).
- `uses.<id>.source`: optional, where to get the dependency when it is missing (§6.9); a
  `repositoryProblem` refusal makes the entry's source void, with an error.
- **The shell refuses** `module.privileged.start` and `PrivilegedAction` from a module without
  the block, or whose acknowledgement does not say `privileged: true`, or with an `argv[0]`
  not among its declared programs: `result.blocked`, the reason in the module's errors
  ("asks for administrator rights; module.json does not declare it"), no prompt shown.
- **Honest caveat** (in the API reference and the trust text): this is a guard and a
  statement, not a barrier. The module runs in the shell's process; one that wants to reach
  `pkexec` some other way can. What the declaration buys: an honest module cannot start asking
  without saying so, and an update that starts asking stops at a question.

**The consent box** (in the card, the same frame as §2): first line by reason —
"Tailscale 0.7.0 comes from a different source." ("From github.com/x/tailscale, was
github.com/siarko/…") / "Printers 0.5.0 asks for administrator rights." ("For: <why>.
Programs: lpadmin. 0.4.0 did not ask.") / "Notes 0.4.0 needs Clipboard, which is not
installed." / "Tailscale 2.0.0 would stop Exit map." — then §2's statement where a module
not yet trusted is involved, "What's new" (the side panel), buttons "Update" (`save`),
"Keep 0.4.0" (`cancel`).

- **Accepted**: the acknowledgement takes the new address/author/`privileged`; the switch
  goes on (§6.5).
- **Refused**: the old version stays and keeps running; the record keeps `refused: { version,
  commit }`; the new one is never linked, so it never activates at a restart. The card shows
  "Update not finished" and "Update to 0.5.0 not finished. 0.4.0 is active." with "Review"
  (the box again) and "Delete 0.5.0" (`DeleteButton`; frees its directory). The user is told
  once (the queue's row, and the queue's notification).

### 6.5 The update queue and the restart

- "Update" on several cards, "Update all", or an automatic run puts them into **one queue**
  (`ModuleUpdateRules.queueStep(queue, event)`, a pure state machine), dependencies before
  their dependents (§6.9). Downloads may run side by side (each row with its progress and
  speed); switches run one at a time: back up the configuration (§6.10) → unload the old
  version → relink → `load()` the module → it loaded once (else back to the old link and the
  backup: "0.7.0 failed to start; 0.6.0 is active again").
- Rows at the top of the page: "Weather 1.2.0 → 1.3.0 — Downloading 45% · 2.4 MiB/s /
  Verifying / Backing up settings / Installing / Done / Approval required / Not finished /
  Failed: <what and why, one line>", a `ProgressBar` for the queue and one per downloading
  row (`wave: true`). The title line: "Updating" / "Updates finished", "2 of 3", and once the
  queue has ended an "×" at its right that closes the list (tip: "Close — a pending restart
  stays at the top of Settings"). Closing it with a restart pending is "Later" (below). A row that needs consent waits there
  with "Review"; the rest of the queue goes on.
- **Shell-wide actions are grouped**: an update whose new files a reload cannot pick up
  (§4 Reload) adds "restart the shell" to the queue's list instead of offering it; when the
  whole queue has ended (every row done, failed, refused or waiting for consent), one offer:
  "Restart the shell to load the new files of Weather and Notes." + "Restart shell" and
  "Later", on the page, and one notification "Restart needed" ("To finish updating Weather and
  Notes."); clicking the notification opens Settings → Modules scrolled to the offer's
  "Restart shell". Never once per module, never automatic. The notification has its "×"
  like any other (no resident or critical urgency). **It goes away by itself once the shell
  has restarted, whoever restarted it** (the bar's menu, `h2s-shell --restart`, a crash, a new
  session): the shell is its own notification server, so a new process starts with no
  notifications; for the hot reload, which keeps them (`keepOnReload`), the reminder carries
  the hint `x-h2s-restart-for` = the process's id and start time, and at start the shell closes
  any reminder whose value is not its own. `Modules.restartNeeded` lives in memory, so it
  ends the same way. A consent accepted later that
  needs a restart makes its own single offer.
- **"Later"** closes the offer only: the pending restart is remembered (`Modules.
  restartNeeded`, the module names, in memory — a restart clears it by being the restart) and
  shown as a warning banner at the top of every page of the Settings window, where
  `KeepSettingsBar` stands on the network pages: "Restart the shell to finish updating Weather
  and Notes." with "Restart shell". It stays until the shell restarts.
- The queue's end sends one notification: "Modules updated: Weather 1.3.0, Notes 0.4.0.
  Printers: approval required." — merged with the restart one when both are due.

### 6.6 After an update

On the card, under "New in this version" (`Notice` info, until the user closes it or the
next update): new programs ("Needs the program curl — found"), new modules it uses, a new
major version ("Now 2.0: a major version"), more privileged programs ("Now also runs nft as
administrator"). Plain text, capped. A configuration backup was taken (§6.10): "Settings
from 0.6.0 are backed up" with "Backups…".

### 6.7 What's new (the changelog), in the side panel

- From the staged or kept copy: the manifest's `changelog` (a file in the module, default
  `CHANGELOG.md`). Read at most 64 KiB; `ModuleUpdateRules.changelogSince(text, fromVersion,
  toVersion)` keeps the sections whose `## <version>` headings lie after the installed one up
  to the new one (an install: the newest few sections), else the text's start.
- Shown as plain text (`Text.PlainText`: Markdown is not rendered, never markup), line breaks
  kept, at most 200 lines and 20 000 characters, then "(cut)". None: "No changelog".
- Where: in the Settings page's side panel (`SideDrawer`, size `m`, title "What's new —
  Weather 1.3.0"), opened by "What's new" in the install preview, the consent box, the card
  (the downloaded version before an update, the active one after), an entry of "Switch
  version", and the automatic-update notification. Several modules (an automatic run, a
  chain): one section per module in the same panel, each headed by name and versions.

### 6.8 Switch version

"Switch version…" opens a list in the card (`ModuleUpdateRules.versionList(kept, tags,
heads, active)`):
- the kept versions (instant): "0.6.0 — active", "0.5.2 — kept", "0.7.0 — downloaded" /
  "not finished";
- from the repository (needs a check; downloaded when chosen): its tags, newest first by
  version order (semver where it parses, else the tag's date), the ten newest, then "More…";
  and the recorded branch's head as "main — latest commit 1a2b3c4". Other commits: install
  with `#<commit>`.
Choosing one runs the update path (download, preview with its changelog, consent rules —
going to a version that declares less never asks; dependencies checked, §6.9); the
configuration is backed up first, and going back offers the backup taken at that version
("Also restore the settings from 0.5.2", a checkbox, unchecked).

### 6.9 The dependency chain

`ModuleDependencyRules` (pure) on the staged manifest, the installed statuses and what the
manifests' `uses.<id>.source` name.

- **Resolving**: `plan(root, installed, fetched)` walks the hard `uses` and lists each as
  - *there, fits* — nothing to do ("Tailscale 0.6.0 — installed");
  - *there, too old, an update fits* — joins as an update ("Weather 1.2.0 → 1.3.0, Notes needs
    1.3"), from its recorded source; a `builtin`/`system` copy that does not fit cannot be
    updated here → *incompatible*;
  - *missing, with a source* — downloaded and verified into staging too, then its own `uses`
    walked (depth at most 8, at most 16 modules per chain; a cycle or a limit refuses the
    chain, naming it);
  - *missing, no source* — *unresolved*;
  - *incompatible* — present or downloaded, but its version or its own API does not fit.
  Soft `uses` that are missing are listed as "Can use: Calendar — not installed", with a
  checkbox "Also install" when they have a source (unchecked); never downloaded otherwise.
  The downloaded ones count in the progress (one row each).
- **Order**: downloads side by side; verifying each as it lands; installing in dependency
  order (providers first: `ModuleMergeRules.dependencyPlan`'s order), then one `load()` of
  the new list. Updates in a queue are ordered the same way.
- **The preview** shows the chain under the module: "Also installs: Clipboard 0.2.0 (from
  github.com/anna/h2s-clipboard)", "Updates: Weather 1.2.0 → 1.3.0", "Already there:
  Tailscale 0.6.0", "Can use: Calendar — not installed [Also install]". Each module new to
  the user root gets its line in the trust box ("Notes and Clipboard are not part of
  h2s-shell.") and its administrator words, if any; "What's new" shows every changelog of the
  chain in the side panel. One "Install and enable" covers the listed modules; "Install,
  keep off" keeps all of them off.
- **Unresolved or incompatible**: the preview says which and why, one line each ("Needs
  Clipboard 0.2 — not installed, no address given" / "Needs Weather 2.0 — the system's copy
  is 1.2"); the buttons become "Install anyway" (installs what resolves; the module stays
  "Needs Clipboard" until it is there) and "Cancel" (§10b Q2). An update that would leave a
  dependency unresolved stops at "Approval required" with that line.
- **A failure halfway**: nothing moves in before every module of the chain is downloaded and
  verified; a failed download or check cancels the chain and deletes every staging directory.
  The page says what happened and why, nothing more: "Clipboard: download failed — the server
  did not answer." (a failure installs nothing; it is not said). Installing is renames; if one fails,
  the ones already renamed in this run are taken back (links removed, version directories
  deleted, updated ones relinked to their previous version and its backup), so the user root
  is as before. A module that installed but fails to start keeps its files and shows Failed
  with the reason; its dependents show "Needs <it>"; the queue row offers "Remove the chain"
  (the modules installed in that run).
- **Updates**: a new hard dependency of an update installs with it (a new module → consent,
  §6.4 reason 3); a provider's new major version that an installed module needs at the old
  major → consent (reason 4: "Tailscale 2.0.0 would stop Exit map"); with automatic updates
  both stop at "Approval required".
- **Removing what others need**: the Remove modal lists them — hard dependents "These stop
  working: Exit map." (left installed, shown "Needs Tailscale"), soft ones "These lose a
  feature: Weather." A dependency installed for a module (`installedFor` in the record) that
  nothing else uses is offered with that module's removal ("Also remove Clipboard (installed
  for Notes, nothing else uses it)", unchecked). Disabling: §4 "Disable".

### 6.10 Configuration backups

- **When**: before every switch of an installed module's version — an update by hand or
  automatic, "Switch version", the rollback after a failed start ("before rollback") — and
  before a restore.
- **What**: the module's `mod.<id>.*` settings in every profile (`settings.json`, values as
  stored), its store (`<configHome>/h2s_shell/modules/<id>`), and its data directory when it
  is at most 10 MiB (else left out, said in the list: "data not included, 240 MiB") (§10b
  Q1); `meta.json` `{ id, version, commit, takenAt, reason, includesData }`.
- **Where**: `<dataHome>/h2s-shell/module-backups/<id>/<version>-<YYYYMMDD-HHMMSS>/`, written
  in a staging directory and renamed in.
- **How many**: the newest 5 per module (`ModuleUpdateRules.backupKeepPlan`); older ones
  deleted after a new one is in. Removing a module keeps its backups unless the data box is
  checked. Managing disk space for all such files: later (tracker).
- **Restore**: "Backups…" on the card opens a list in it — "0.6.0 · 21 Nov 14:02 · before
  update to 0.7.0", "0.5.2 · 2 Nov 09:10 · before switch", each with "Restore". Restore asks
  in a warning modal (§4.1): "Restore Tailscale's settings from 0.6.0?" / "The current
  settings are backed up first. The module restarts." — "Restore" / "Cancel". Then: back up
  now ("before restore"), disable the module, write the settings through `Profiles`, replace
  the store (and the data directory when included), enable it. The version does not change;
  a backup from another version says so ("Taken with 0.5.2; 0.6.0 is active").

## 7. Safe mode and the banner

**When**: `Modules.safeMode` (either counter). **Where**: the HUD under the bar (a
`StartupWarning` with buttons) and on top of Settings → Modules (the page's `banner`).
Never on the lock screen (lock-closure). **What it says**: "Started without modules" and
why, in plain words — "The shell crashed twice within 30 seconds of starting." — then
"Modules on when it crashed: Tailscale, Weather." (the host writes the enabled ids to
`$XDG_RUNTIME_DIR/h2s-shell-modules-on` at each load; safe mode reads the last one) and, when
one was installed or updated in the last day, "Weather was updated 10 minutes ago."
**What it offers**: "Open Modules" (the page, to disable suspects or switch one back),
"Load modules" (the host `load()`s the list again without safe mode, in place; a module that
crashes the shell now counts towards the launcher's next safe mode as any start does), × (for
this run; the page banner stays). The safe-mode notification stays as the announcement; its
body points to the banner instead of the IPC command. No updates or installs run in safe mode
(switching back to a kept version and restoring a backup do).

## 8. NixOS and Arch

- **NixOS**: built-in modules in the package, `$out/share/h2s-shell-builtin`. A module from
  the system's data dirs (`/run/current-system/sw/share`, `/etc/profiles/per-user/<user>/share`)
  or any other path under `/nix/store` is `system`: consented, read-only; the later NixOS
  option (`programs.h2s-shell.modules`) puts its modules there too, never in the user root.
  git comes with the package. A user's install of the same id wins (user root first) and its
  card says it replaces the system's copy.
- **Arch**: built-in modules in `~/.local/share/h2s-shell/builtin/`, written by `install.sh`
  and the shell's update only; later `/usr/share/h2s-shell/builtin` from an AUR package of
  the shell. `/usr/share/h2s-shell/modules` (other packages') is `system`. git is already
  needed by `install.sh`; Settings → Modules says "git is needed to install from a
  repository" when it is missing (a folder install still works).
- Both: the user root, versions, staging, records, backups and data are the same paths; no
  privileges.

## 8b. Files the shell writes

All the user's own, under the data and config homes; nothing else is written by the page.

| Path | What | Written by |
|---|---|---|
| `<dataHome>/h2s-shell/modules/<id>` | a link to the active version (installed by the shell); hand-placed folders and links are the user's | installer; Remove deletes |
| `<dataHome>/h2s-shell/module-versions/<id>/<version>-<commit7>/` | one directory per kept version, at most 3 | installer, updater |
| `<dataHome>/h2s-shell/module-staging/<random>/` | downloads and deletions in progress; emptied at each start | installer, updater, Remove |
| `<dataHome>/h2s-shell/module-sources.json` | the record (§6.2) | installer, updater |
| `<dataHome>/h2s-shell/module-backups/<id>/<version>-<time>/` | configuration backups, newest 5 (§6.10) | updater, restore |
| `<dataHome>/h2s-shell/module-data/<id>/` | a module's data (exists today) | the host; Remove with the data box |
| `<configHome>/h2s_shell/modules/<id>` | a module's store (exists today) | the module; Remove with the data box, restore |
| `Config`: `acknowledgedModules`, `enabledModules`, `disabledModules` | remembered state | the host |
| `$XDG_RUNTIME_DIR/h2s-shell-modules-on` | modules on at the last load (safe mode reads it) | the host |
| `~/.local/share/h2s-shell/builtin/` (Arch) | built-in modules | `install.sh` and the shell's update, never the page |

## 9. Slices

Each with its tests; while iterating the named suites, before committing `tests/run-all.sh`.
Stand-ins only: a repository is a local bare git repo made in the suite's temporary home
(`git init --bare`, a fixture module committed and tagged, a second commit with a changelog, a
`privileged` block, another `author`, a `uses` with a `source` to a second fixture repo)
reached by `file://`, or a folder; a stand-in `git` (hangs, refuses, too large, prints
progress lines) for failures and progress; a fake clock for the daily run; the network is
never touched (a suite asserts nothing it ran named a non-`file` address). Pure rules first.

| | Slice | Views | Tests |
|---|---|---|---|
| M0 | The trust text in `docs/` (§2: ARCHITECTURE "Modules", FEATURES, README one line) | none | — |
| M1 | Where a module comes from (`ModuleInstallRules`, pure): `sourceOf` (builtin root, system, link vs folder, record + link inside `module-versions`), `replaces`, `actionsFor` (Enable/Disable, Remove, Update), `needsConfirmation` (builtin/system/developer exempt; absent list = baseline), `removalPlan` (link only / folder / versions, with or without data, dependencies installed for it), `repositoryProblem`, the git argv, `progressOf`, record parse, `builtinOff`, `listOrder`, `marks`, `checkResultText`; `stateOf` gains `unconfirmed` | none | `ModuleInstallRulesTest`, `ModuleRulesTest` cases |
| M1b | Updates as rules (`ModuleUpdateRules`, pure): `consentFor` (four reasons), `afterNotes`, `queueStep` with dependency order and the grouped shell-wide actions, `keepPlan`, `versionList`, `changelogSince` with its caps, `offerFor` (refused not re-offered), `autoRunDue` (daily, backoff), `backupPlan` (what, data cap), `backupKeepPlan` | none | `ModuleUpdateRulesTest` |
| M1c | The `privileged`, `author` and `uses.<id>.source` fields (API 1.36): manifest read, the host refuses undeclared or unconsented privileged runs, `argv[0]` among declared programs; `Api.qml` reference with the caveat; CHANGELOG "Module API". First, in the module repository: Tailscale declares `privileged` (an unknown field is only a warning on today's shell) | none | `ModuleRulesTest` cases, `ModulesTest` fixture (undeclared module's run blocked, no prompt), Tailscale's suites |
| M1d | The dependency chain (`ModuleDependencyRules`, pure): `plan` (there/update/download/unresolved/incompatible, soft offers, depth and size limits, cycles), install order, `rollbackPlan` for a failure halfway, dependents for Remove/Disable, `installedFor` orphans | none | `ModuleDependencyRulesTest` |
| V1 | The Settings modal (§4.1): `components/SettingsModal.qml`, `SettingsModalHost.qml` in the Settings window, `Theme.modal`, the `modalDim` colour token (all built-in themes), `ThemeRules.modalLook`, `ApiElementRules.modalButtons`; the Views decision in decisions.md and the `CLAUDE.md` rule | modal | `ThemeRulesTest`, `ApiElementRulesTest` cases, `SettingsModalTest` |
| M2 | The host: acknowledgements and their baseline, builtin root + `builtin.json` + `enabledModules`, `unconfirmed` and "Approval required" for changed hand-placed modules, `source`/`replaces`/`installedFor` in the status and `modules list`, `modules confirm`, the modules-on file, "load without safe mode", re-discovery + `load()`, `restartNeeded`; what Reload can pick up (a `QuickshellPinTest` case: changed file after off/on) | none | `ModulesTest` fixtures, lock bed `modules-discovery` extended |
| M2b | Builtin places in packaging: `nix/package.nix` (`share/h2s-shell-builtin`, the wrapper passes it), `install.sh` and the update fill `~/.local/share/h2s-shell/builtin/`, the launcher's builtin root | none | `tests/install-test.sh` case, NixOS system test case |
| M3 | The installer (`singletons/ModuleInstaller.qml`): download with progress, verify, the chain (staging all, install in order, roll back), version directories and the link, record, remove (`removalPlan`, with data and orphans), switch version, delete a version, roll back on a failed start; IPC `modules install/remove/switch` | none | `ModuleInstallerTest` on local repos (a chain of two, a missing dependency, a failure on the second), folders, links (the target untouched), stand-in `git` |
| M3b | The updater: check (`ls-remote`), `modules.autoUpdate` (daily run that switches unless consent is due), background download, the queue, consent hold and refusal, the grouped restart offer and `restartNeeded`, the restart reminder's `x-h2s-restart-for` and its closing at start, the notifications (opening the changelog panel, the restart offer); IPC `modules check/update` | none | `ModuleUpdaterTest` (local bare repos, stand-in `git`, fake clock, recorded notifications) |
| M3c | Configuration backups: taken before every switch and restore, kept 5, restore (disable, write, enable); IPC `modules backups/restore` | none | `ModuleBackupTest` (profiles with `mod.<id>.*`, a store, a data dir over and under the cap) |
| M4 | Settings → Modules page: list in `listOrder` (enabled first), cards (`SettingsCard` gains a leading item for the icon), on/off as the name's colour, marks with tips, `StatusPill.expandable` (and its API line), Enable/Disable (button question or the modal), reload, the confirmation, Remove through the modal, dependencies, "Check all" and the check feedback | page | `ModulesPageTest` (stand-in host, clicks), `AnchorsTest` (the page's anchor) |
| M5 | Install and update on the page: field, folder dialog, steps with progress (waving) and speed, preview with the chain, the changelog side panel, the queue rows, consent box (accept, refuse, delete the new version), switch version, backups and restore, the restart offer and the Settings-wide restart banner | page | the page suite on local repos |
| M6 | The safe-mode banner (HUD and page) | banner | `HudTest`-style suite on a host in safe mode; lock-closure |

M0–M3c need no views and can go while the mockups are judged; V1 goes before M4. CHANGELOG
lines with M1c (API), M2 (behaviour: new modules start off), V1, M4, M5, M6.

## 10. Decided (the owner, 2026-11-21)

1. Built-in modules (named "builtin", label "Built-in") live outside the shell's tree: NixOS in the package; Arch `~/.local/share/h2s-shell/builtin/` (the shell's install and update only), later `/usr/share/h2s-shell/builtin`; other packages' modules `/usr/share/h2s-shell/modules`; built-in = trusted, some may come off.
2. A module keeps its state across updates (so today's Tailscale stays on); consent when the source changed or the module first declares administrator actions (undeclared modules' prompts refused, honestly not a guarantee); refusal remembered, old version stays, the user is told, the new one can be deleted and never activates; "Switch version"; changelog before install and update; new programs and a major version only shown after.
3. Automatic updates (a setting, off by default): check, download and switch by themselves unless consent is due, then one notification that opens the changelog(s) in Settings → Modules; off: "Update" / "Update all" by hand.
4. Adding a program to an existing `privileged` declaration needs no consent; it is shown after the update.
5. Built-in modules are authorized by design; modules installed by the system count as consented ("Installed by the system — not part of h2s-shell").
6. Remove is offered for everything in the user root, hand-placed folders and links (the link only); the question says it was not installed by the shell and what is deleted, with "Also delete its data and settings" unchecked — in a modal with its own Remove / Keep.
7. Disable: the button's own "Disable?" without dependents; a warning modal listing the modules disabled with it otherwise.
8. The development path is exempt from the confirmation; its card says "Development path".
9. "Restart shell" is the user's click, never automatic; several updates form a queue and shell-wide actions are offered once after it ends; a notification leads to the restart button; "Later" leaves a warning banner in Settings until the restart.
10. "Check all" at the top of the page, besides each card's own.
11. Words: "Enable"/"Disable"; "Approval required"; install steps say what happens ("Downloading", "Verifying", "Installing"); a pill's count has a tip saying what it counts.
12. Downloads show a progress bar and the speed where git gives them; the changelog shows in the side panel.
13. The dependency chain is resolved and installed with the module (§6.9).
14. A configuration backup at every module update, labelled with the version, with Restore; disk space for such files later (tracker).
15. A Settings modal as a new shared element (§4.1): kinds, dimmed and blocking, always a cancel, "×" as cancel, one button = informing, fully themeable; its dimming a token of its own, not the lock's scrim.
16. A pill on this page takes no click (hover tip only); on/off is not a pill: enabled names in colour, the list enabled first, then disabled.
17. Progress bars are the shared `ProgressBar` with `wave`, as Taildrop's; checking shows "Checking…" and then its result.
18. Errors say what happened and why, nothing more.
19. "Updates finished" closes with an "×" on its title line (a pending restart then stays as the Settings banner); the restart notification has an "×" and goes away by itself once the shell has restarted.

## 10b. Open questions

1. **Does a backup include the module's data directory?** Settings and the store are small;
   a data directory can be a cache of hundreds of MiB (a map module's tiles), and five
   backups would multiply it. Example: Exit map keeps 240 MiB of tiles; each update would
   copy them. Recommendation (in this plan): include the data directory when it is at most
   10 MiB, else leave it out and say so in the backup list.
2. **A dependency the shell cannot get.** Notes needs Clipboard, but Notes' manifest gives no
   address for it (or the only copy is a system one that is too old). Should the install be
   refused, or allowed with the module left "Needs Clipboard" until you install it?
   Recommendation: allowed, but only through an explicit "Install anyway" in the preview,
   which names what is missing; an automatic update never does it (it stops at "Approval
   required").
3. **The rule for questions in `CLAUDE.md`.** Today: "Deleting from a click goes through
   DeleteButton … Don't hand-roll another confirm." With the modal, a removal asks in the
   modal (it has a list and a checkbox). Recommendation: the rule says "a one-word question
   is the button's own (`DeleteButton`); a question with a list, a choice or an explanation
   opens the Settings modal; nothing else asks" — and the same as a Views decision.
