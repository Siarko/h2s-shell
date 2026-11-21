# Managing modules: Settings → Modules, installing and updating, the trust model, the safe-mode banner

Tracker: order of work step 1 (second item: this plan), step 8 ("Modules closed for now"),
and the parts of step 13 that land here (the trust text, the confirmation, where a module
comes from). Decisions: [decisions.md](../decisions.md), "Direction, modules and trust"; the
owner's answers to this plan's questions are in §10.
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
  the shell reads it.
- **Privileged runs**: `module.privileged.start` and `PrivilegedAction` (`api/Api.qml`
  "Running as administrator"): any module may ask; the prompt names the module, `what` and
  the command. Nothing in the manifest says a module will ask.
- **Dependencies**: `ModuleMergeRules.dependencyPlan` :131 (hard and soft `uses`); reasons
  already land in `errors` ("needs module tailscale 1.0: turned off") and soft notes in
  `warnings`.
- **Icons**: `components/ModuleIcon.qml` (glyph, SVG, picture, else the name's letter),
  fed by `ModuleHost.icons`. Nothing draws it yet but tests: Settings → Modules is its place.
- **Safe mode**: the launcher's (`launch.sh:607`, two deaths within 30 s →
  `H2S_SHELL_SAFE_MODE=1`) and the start guard's (`ModuleFileRules.qml:420–466`, two
  in-place relaunches). `Modules.qml:116` sends one notification "Started without modules:
  <reason>"; no banner. Leaving safe mode takes a restart.
- **IPC**: `Modules.qml:165` — `modules list` (JSON), `modules setEnabled <id> <bool>`.
- **Settings**: a "Modules" group exists in the System tab only when a module has a page
  (`ModuleMergeRules.qml:612` `modulesGroup`, `:621` `mergeSettingsPages`); a group opens its
  first child. No page of the core's own.
- **Storage today**: modules' own directories (whoever put them there), data
  `<dataHome>/h2s-shell/module-data/<id>` (made by the host, never removed), stores
  `<configHome>/h2s_shell/modules`. The owner's Tailscale module is a link in the user root
  (to a checkout of the module repository), and it uses privileged runs.
- **Banners**: `hud/StartupWarning.qml` (title, body, ×; `Hud.qml:76`), no buttons.
- **Packaging**: NixOS copies the tree to `$out/share/h2s-shell` (`nix/package.nix:80`), git
  is a runtime input (:43); Arch's `install.sh:15` clones into `~/.config/quickshell/default`.
  No module is shipped yet, and there is no place for shipped modules outside the scanned
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
> **What protects you.** Modules shipped with the shell are reviewed with it. Modules your
> system's administrator installed (a NixOS configuration, a distribution package) are
> theirs to answer for. Any other module is its author's work, not the project's: the shell
> says so and asks before it first turns one on, and asks again when an update comes from a
> different source or starts to run administrator actions. A module asks for administrator
> rights only through the shell's password prompt, which names the module, says what the
> action is for and shows the command; for a module that is not the project's, that text is
> the only protection — read it, and cancel when it does not match what you just did. The
> shell never installs, updates or turns on a module without your click, never asks for a
> password by itself, and looks for updates by itself only when you turn that on.
>
> **What to install.** Treat a module like a program you run as yourself: install it only
> from someone you trust, from a repository you could read, and pin it to a tag rather
> than a branch that can change under you. Read what changed before you update.

The confirmation shown when a module that is neither shipped nor installed by the system is
first turned on (UI words): "**<Name> is not part of h2s-shell.** It runs inside the shell
with your rights and could read anything the shell sees, your lock screen password included.
Turn it on only if you trust where it comes from." — buttons "Turn on" (`save`), "Cancel"
(`cancel`). The update consent (§6.4) uses the same box with its own first line.

## 3. Where a module comes from

A pure rule, `ModuleInstallRules.sourceOf(directory, link, roots, records)`, from the
canonical directory, whether the entry in the root is a link, and the record of what the
shell installed:

| Source | Found in | Card says | Consent | Actions |
|---|---|---|---|---|
| `shipped` | the shell's shipped place (below) | "Shipped" | never asked | on/off, reload |
| `system` | a system data dir (`/usr/share/h2s-shell/modules`, NixOS profiles), anything else under `/nix/store` | "Installed by the system — not part of h2s-shell" | counts as given | on/off, reload |
| `repository` | user root, link the shell made into `module-versions/<id>/`, with a record | "From <host/path> @ <ref>" | asked | on/off, reload, check, update, switch version, remove |
| `folder` | the same, record of a copied folder | "Copied from <path>" | asked | on/off, reload, update (copy again), switch version, remove |
| `user` | user root, no record: a folder placed by hand, or a link | "Your copy" / "Your link → <target>" | asked | on/off, reload, remove |
| `developer` | `H2S_SHELL_MODULE_PATH` | "Development path" | never asked | on/off, reload |

**Shipped places** — outside the tree Quickshell scans, found from the shell's own
installation (the launcher passes the root; never from a place a module could name):
- NixOS: in the package, `$out/share/h2s-shell-modules` (`nix/package.nix`; the wrapper
  hands it to the launcher).
- Arch now: `~/.local/share/h2s-shell/shipped/`, filled by `install.sh` and by the shell's
  own update — never by the user, never by Settings → Modules (the page writes only the
  user root). Later, with an AUR package of the shell, a directory under `/usr/share` (§10b
  Q1 names which).
Shipped is trusted by design: never asked, no Remove (an update of the shell brings or drops
them). Some ship off: the shipped place holds `shipped.json`, `{ "off": ["<id>", …] }`; a
module listed there is off until the user turns it on (remembered in
`Config.enabledModules`, the counterpart of `disabledModules` for what starts off).

**System-installed** modules (an administrator's AUR package, a NixOS configuration) are
consented by whoever installed them: they run at once, read-only (no Remove, no Update, no
Switch version: "Change it in the system's configuration").

**Replacing**: the winner of an id gets `replaces: [{ directory, source, version }]`
(precedence extended), shown on its card: "Replaces the shipped copy (1.2.0)" — the
decision's "shown when a user's copy replaces a shipped one".

**Remove** is offered for everything the user root holds — installed by the shell or not,
folders and links (§4, "Remove"). It is never offered for `shipped`, `system` or `developer`.

## 4. Settings → Modules

The System tab's "Modules" group becomes permanent; its first page is the core's
`modules` page ("Installed"), modules' own pages follow under it.

**At the top**: "Check all" (one `ls-remote` per repository module, §6.3) beside
"Update all (n)" once updates are known; under them, while a queue runs or has news, the
update queue (§6.5); in safe mode, the banner (§7).

**The list**: one `SettingsCard` per module (a `KeyedModel` keyed by id; duplicates are
shown inside their winner's card, not as cards). Closed: the icon (`ModuleIcon`), the name,
a subtitle "version · source"; on the name line a `StatusPill` (s) with the state:

| State | Pill | Kind |
|---|---|---|
| loaded | "On" (parts: warnings, deprecations as counts) | success |
| disabled | "Off" | muted |
| unconfirmed (new, §5) | "New — off" | warning |
| update waits for consent (§6.4) | "Needs your OK" | warning |
| update refused (§6.4) | "Update not finished" | warning |
| failed / incompatible | "Failed" / "Needs API 2.x" | danger |
| missing-program / missing-module | "Needs gcalcli" / "Needs Tailscale" | warning |
| pending | "Starting…" | muted |
| safe-mode | "Safe mode" | warning |

The two update pills stand beside the running state (the old version keeps running: "On"
stays, the update pill follows it).

Its button row: the main button — "Turn off" / "Turn on" (one decision from the state:
`ModuleInstallRules.actionsFor(status, source, context)` returns labels and effects
together); "Update to 1.3.0" when one is known and downloaded; Remove (`DeleteButton`,
"Remove?") last. Opened: the description; source (address, ref, commit, installed when; or
the path; for `system` "Installed by the system — not part of h2s-shell"); API asked and the
shell's; whether it runs administrator actions (§6.4, the manifest's words); dependencies —
"Needs: Tailscale 1.0 — on" (hard), "Can use: Weather 1.x — not installed" (soft), "Used by:
Exit map"; programs, missing ones with the manifest's `setupHints`; then errors (`Notice`
danger, one per line), warnings and deprecations ("Uses Api.module(), which goes in the next
tightening"), all as plain text, capped; "New in this version" after an update (§6.6); the
data directory's path; buttons "Reload", "Check for updates", "What's new" (the changelog,
§6.7), "Switch version…" (§6.8).

**Above the list**, a section "Add a module": one field ("Repository address or folder"),
"Choose folder…" (the platform's folder dialog), "Install". Under it, while an install runs,
its step ("Fetching…", "Checking…") and Cancel; then the preview (§6.2).

**Actions and what they do**
- *Turn on / off*: `ModuleHost.setEnabled`. Off with running dependents: the button asks
  first, naming them ("Also turns off Exit map?", `DeleteButton` kind `warning`).
- *Reload*: the module off and on (a new main); when its files changed on disk (an update,
  an edit) and Qt's component cache or its singletons keep the old code, the card says
  "Restart the shell to load the new files" with "Restart shell" (§6.5; M2 measures which).
  "Restart shell" is always the user's click, never automatic.
- *Install*: §6.2. *Update*: §6.3–6.6. *Switch version*: §6.8.
- *Remove*: a `DeleteButton` "Remove". Its first click turns it into "Remove?" and opens,
  under the button row, what will be deleted and one checkbox:
  - installed by the shell: "Deletes Weather 1.2.0 and the kept versions (1.1.0)."
  - placed by hand: "**Not installed by the shell.** Deletes the folder
    ~/.local/share/h2s-shell/modules/player."
  - a link: "**Not installed by the shell.** Deletes only the link; ~/Projects/h2s-backup
    stays." (the link only, never its target: `unlink`, never a recursive delete through it)
  - a provider with dependents adds "Exit map needs it."
  - `Checkbox` "Also delete its data and settings", unchecked each time the question opens:
    then the data directory, its store and its `mod.<id>.*` settings in every profile go too.
  The second click turns the module off, moves what it deletes to staging (same filesystem),
  deletes it, drops its record and acknowledgement. Without the box, data, store and settings
  stay (a later install of the same id finds them). The question is the `DeleteButton`'s
  asking state; the lines and the box are shown while it asks (no second confirm of its own).

**Privileges: none.** Every file the page writes is the user's own, under the data home;
nothing runs as root, no `pkexec`, no `sudo`. Shipped and system modules are read-only in the
list.

**Never automatic**: installing, updating (switching to a new version), removing, turning on
a module found on disk, deleting data, following a link to delete, running anything from a
module's files during an install (no hooks, no submodules, no build step), asking for a
password, restarting the shell, acting while the session is locked (IPC refuses, the window is
closed then). Checking and downloading run by themselves only when the setting says so (§6.3).

## 5. The confirmation (first turned on)

A module that is not `shipped`, `system` or `developer` starts **off** the first time the
host sees it (`unconfirmed`, a new state), until the user turns it on through the
confirmation (§2's text). Acknowledged = `Config.acknowledgedModules[id]` (remembered state,
not a preference): `{ source, address, author, privileged }` — the source kind, the address
or path it comes from, the manifest's `author` (§6.4) and whether it was consented to run
administrator actions. It is keyed by id and source, not by the version's directory, so a new
version of the same module keeps it (§6.1). A different source for the same id (a user copy
replacing a shipped one, an install from another address) asks again.

Installing through the page with "Install and turn on" is the confirmation (the preview
carries the text). IPC: `modules setEnabled` refuses an unconfirmed module with the reason;
`modules confirm <id>` acknowledges it (a typed command is a click).

A hand-placed module (`user`) changes outside the shell (the owner's Tailscale link is a git
checkout). At each load the host compares its manifest with the acknowledgement: when it now
declares administrator actions (or its `author` changed), it is held off as "Needs your OK"
with the same box as an update's consent (§6.4) — there is no old copy to keep running.

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
  directory, the store, the bar's widgets of its types. An older version may not read data a
  newer one wrote: the module's to handle; the version list says "older" next to such an entry.

### 6.2 Installing from an address or a folder

- **Source**: a git address (`https://`, `ssh://`, `git@host:path`, `git://`, `file://`),
  optionally with `#<ref>` (a tag, a branch, or a full commit id); or a folder.
  `ModuleInstallRules.repositoryProblem` refuses anything else (`ext::` and `fd::` run
  commands; a leading `-`; control characters; over 1000 characters). The address is always an
  argument after `--`, never in a shell string.
- **Fetch** into `<dataHome>/h2s-shell/module-staging/<random>` (same filesystem as the
  versions, so moving in is a rename): `git -c core.hooksPath=/dev/null
  -c protocol.allow=never -c protocol.{https,ssh,git,file}.allow=always clone --depth 1
  --no-recurse-submodules [--branch <ref>] -- <url> <dir>` (a commit id: `init` + `fetch
  --depth 1 -- <url> <commit>`; a server that refuses it is said in one line), with
  `GIT_TERMINAL_PROMPT=0`, `GIT_ASKPASS=` / `SSH_ASKPASS=` empty, `GIT_SSH_COMMAND="ssh -o
  BatchMode=yes"` (never a credential prompt), under a time limit and a size cap (a fetch too
  large is stopped). A folder is copied (`cp -R --no-dereference`, then the file check refuses
  links out). Through the host's `CommandRunner`, as the user.
- **Check**: the host's own file check and manifest rules on the staged directory (no new
  checker): valid, API fits, the id free or held by a copy it would replace (said in the
  preview), files inside. A module failing here is never moved in.
- **Preview** (the confirmation): icon, name, id, version, API (fits / not), source with the
  commit, author (when the manifest names one), whether it runs administrator actions and its
  words for them, the programs it names (found / missing), the modules it uses (there / not),
  what it would replace, "What's new" (the changelog, §6.7, folded), the §2 statement;
  "Install and turn on" (`save`), "Install, keep off", "Cancel" (deletes the staging directory).
- **Move in**: rename to `module-versions/<id>/<dir>`, make the link, write the record; then
  the shell runs discovery itself (`launch.sh --discover-modules`, the same code) and `load()`s
  the new list — no restart needed for a new module. Failures at any step leave no partial
  module (staging is removed; the page says why, one line).
- **Record**: `<dataHome>/h2s-shell/module-sources.json`, `{ <id>: { kind, address, ref,
  versions: [{ dir, version, commit, fetchedAt }], active, refused, checkedAt } }`, written by
  a temp file and a rename; a missing or unreadable record makes the module `user`
  ("unknown", never "fine": no update, no switch; Remove asks as for a hand-placed folder).

### 6.3 Checking for updates

- **By hand**: "Check for updates" on a card, "Check all" at the top of the page.
- **By itself**: a setting, `modules.checkUpdates` (`SettingsSchema`, global, read with
  `Profiles.value`): "Check for module updates" — "Never by itself" (default) / "Daily". When
  daily: at most once a day, not while locked, after a failure with a backoff, logged on a
  change of outcome only; never a prompt.
- A check is `git ls-remote` of the recorded address for its ref (a tag ref: newer tags, for
  "Switch version" and for "a newer tag exists"; a branch: its head). A newer commit is
  **downloaded in the background** into staging and checked (§6.2's steps); the old version
  keeps running. Once it is ready the card says "Update to 1.3.0" and "What's new" opens the
  new changelog — before anything changes. A check by itself ends with one notification
  ("Updates for 2 modules", action "Open Modules"), never more than one a day.
- A version the user refused (§6.4) is not offered again; a newer one is.

### 6.4 Consent for an update

An update switches by itself once downloaded **after the user's "Update" click** (§10b Q2),
unless it needs consent. `ModuleUpdateRules.consentFor(acknowledgement, record, newManifest,
newAddress)` → `{ needed, reasons }`. Consent is needed when:

1. **the source changed**: the address it would come from is not the acknowledged one (the
   user changed it, or installed the id from elsewhere), or the manifest's `author` changed;
2. **it first declares administrator actions**: the running version has no `privileged` in
   its manifest and the new one has.

Not consent, only shown after the update (§6.6): new programs, new modules it uses, a new
major version, a wider `privileged.programs` list.

**The manifest declaration** (API 1.36, `ModuleManifestRules`):

```json
"author": "Anna Nowak",
"privileged": {
    "why": "Connect, change Tailscale's settings, send files",
    "programs": ["tailscale", "systemctl"]
}
```

- `author`: optional string, plain text, at most 100 characters, one line.
- `privileged.why`: required in the block, a few words, plain text, at most 200 characters —
  shown on the card, the preview and the consent box.
- `privileged.programs`: names among the module's `requires.programs`/`optionalPrograms`;
  the only programs a privileged run may start (`argv[0]` must be their resolved path).
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
github.com/siarko/…") / "Tailscale 0.7.0 asks for administrator rights." ("For: <why>.
Programs: tailscale, systemctl.") — then §2's statement, "What's new", buttons "Update"
(`save`), "Keep 0.6.0" (`cancel`).

- **Accepted**: the acknowledgement takes the new address/author/`privileged`; the switch
  goes on (§6.5).
- **Refused**: the old version stays and keeps running; the record keeps `refused: { version,
  commit }`; the new one is never linked, so it never activates at a restart. The card shows
  "Update not finished" and "Update to 0.7.0 not finished. 0.6.0 is active." with
  "Review" (the box again) and "Delete 0.7.0" (`DeleteButton`; frees its directory). The
  user is told once (the queue's row, and the queue's notification).

### 6.5 The update queue

- "Update" on several cards, or "Update all", puts them into **one queue**
  (`ModuleUpdateRules.queueStep(queue, event)`, a pure state machine). Downloads may run side
  by side; switches run one at a time: unload the old version → relink → `load()` the
  module → it loaded once (else back to the old link: "0.7.0 failed to start; 0.6.0 is
  active again").
- Rows at the top of the page: "Weather 1.2.0 → 1.3.0 — Downloading… / Checking… /
  Switching… / Done / Needs your OK / Not finished / Failed: <one line>", a `ProgressBar`
  for the queue (unknown length per download). A row that needs consent waits there with
  "Review"; the rest of the queue goes on.
- **Shell-wide actions are grouped**: an update whose new files a reload cannot pick up
  (§4 Reload) adds "restart the shell" to the queue's list instead of offering it; when the
  whole queue has ended (every row done, failed, refused or waiting for consent), one offer:
  "Restart the shell to load the new files of Weather and Notes." + "Restart shell", on the
  page and in one notification (action "Restart shell"). Never once per module, never
  automatic. A consent accepted later that needs a restart makes its own single offer.
- The queue's end sends one notification: "Modules updated: Weather 1.3.0, Notes 0.4.0.
  Tailscale waits for your OK."

### 6.6 After an update

On the card, under "New in this version" (`Notice` info, until the user closes it or the
next update): new programs ("Needs the program curl — found"), new modules it uses, a new
major version ("Now 2.0: a major version"), more privileged programs. Plain text, capped.

### 6.7 What's new (the changelog)

- From the staged or kept copy: the manifest's `changelog` (a file in the module, default
  `CHANGELOG.md`). Read at most 64 KiB; `ModuleUpdateRules.changelogSince(text, fromVersion,
  toVersion)` keeps the sections whose `## <version>` headings lie after the installed one up
  to the new one (an install: the newest few sections), else the text's start.
- Shown as plain text (`Text.PlainText`: Markdown is not rendered, never markup), line breaks
  kept, at most 200 lines and 20 000 characters shown, then "(cut)". None: "No changelog".
- Where: folded in the install preview, the consent box, the card's "What's new" (the
  downloaded version before an update, the active one after), each entry of "Switch version"
  that is kept.

### 6.8 Switch version

"Switch version…" opens a list in the card (`ModuleUpdateRules.versionList(kept, tags,
heads, active)`):
- the kept versions (instant): "0.6.0 — active", "0.5.2 — kept", "0.7.0 — not finished";
- from the repository (needs a check; downloaded when chosen): its tags, newest first by
  version order (semver where it parses, else the tag's date), the ten newest, then "More…";
  and the recorded branch's head as "main — latest commit 1a2b3c4". Other commits: install
  with `#<commit>`.
Choosing one runs the update path (download, preview with its changelog, consent rules —
going to a version that declares less never asks); state is kept (§6.1).

## 7. Safe mode and the banner

**When**: `Modules.safeMode` (either counter). **Where**: the HUD under the bar (a
`StartupWarning` with buttons) and on top of Settings → Modules (the page's `banner`).
Never on the lock screen (lock-closure). **What it says**: "Started without modules" and
why, in plain words — "The shell crashed twice within 30 seconds of starting." — then
"Modules on when it crashed: Tailscale, Weather." (the host writes the enabled ids to
`$XDG_RUNTIME_DIR/h2s-shell-modules-on` at each load; safe mode reads the last one) and, when
one was installed or updated in the last day, "Weather was updated 10 minutes ago."
**What it offers**: "Open Modules" (the page, to turn suspects off or switch one back),
"Load modules" (the host `load()`s the list again without safe mode, in place; a module that
crashes the shell now counts towards the launcher's next safe mode as any start does), × (for
this run; the page banner stays). The safe-mode notification stays as the announcement; its
body points to the banner instead of the IPC command. No updates or installs run in safe mode
(switching back to a kept version does).

## 8. NixOS and Arch

- **NixOS**: shipped modules in the package, `$out/share/h2s-shell-modules`. A module from the
  system's data dirs (`/run/current-system/sw/share`, `/etc/profiles/per-user/<user>/share`)
  or any other path under `/nix/store` is `system`: consented, read-only; the later NixOS
  option (`programs.h2s-shell.modules`) puts its modules there too, never in the user root.
  git comes with the package. A user's install of the same id wins (user root first) and its
  card says it replaces the system's copy.
- **Arch**: shipped modules in `~/.local/share/h2s-shell/shipped/`, written by `install.sh`
  and the shell's update only; later a directory under `/usr/share` from an AUR package of the
  shell (§10b Q1). `/usr/share/h2s-shell/modules` (another package's) is `system`. git is
  already needed by `install.sh`; Settings → Modules says "git is needed to install from a
  repository" when it is missing (a folder install still works).
- Both: the user root, versions, staging, records and data are the same paths; no privileges.

## 9. Slices

Each with its tests; while iterating the named suites, before committing `tests/run-all.sh`.
Stand-ins only: a repository is a local bare git repo made in the suite's temporary home
(`git init --bare`, a fixture module committed and tagged, a second commit with a changelog, a
`privileged` block, another `author`) reached by `file://`, or a folder; a stand-in `git`
(hangs, refuses, too large) for failures; a fake clock for the daily check; the network is
never touched (a suite asserts nothing it ran named a non-`file` address). Pure rules first.

| | Slice | Views | Tests |
|---|---|---|---|
| M0 | The trust text in `docs/` (§2: ARCHITECTURE "Modules", FEATURES, README one line) | none | — |
| M1 | Where a module comes from (`ModuleInstallRules`, pure): `sourceOf` (shipped root, system, link vs folder, record + link inside `module-versions`), `replaces`, `actionsFor`, `needsConfirmation` (shipped/system/developer exempt; absent list = baseline), `removalPlan` (link only / folder / versions, with or without data), `repositoryProblem`, the git argv, record parse, `shippedOff`; `stateOf` gains `unconfirmed` | none | `ModuleInstallRulesTest`, `ModuleRulesTest` cases |
| M1b | Updates as rules (`ModuleUpdateRules`, pure): `consentFor`, `afterNotes`, `queueStep` with the grouped shell-wide actions, `keepPlan`, `versionList`, `changelogSince` with its caps, `offerFor` (refused not re-offered), `checkDue` (daily, backoff) | none | `ModuleUpdateRulesTest` |
| M1c | The `privileged` and `author` declaration (API 1.36): manifest read, the host refuses undeclared or unconsented privileged runs, `argv[0]` among declared programs; `Api.qml` reference with the caveat; CHANGELOG "Module API". First, in the module repository: Tailscale declares `privileged` (an unknown field is only a warning on today's shell) | none | `ModuleRulesTest` cases, `ModulesTest` fixture (undeclared module's run blocked, no prompt), Tailscale's suites |
| M2 | The host: acknowledgements and their baseline, shipped root + `shipped.json` + `enabledModules`, `unconfirmed` and "Needs your OK" for changed hand-placed modules, `source`/`replaces` in the status and `modules list`, `modules confirm`, the modules-on file, "load without safe mode", re-discovery + `load()`; what Reload can pick up (a `QuickshellPinTest` case: changed file after off/on) | none | `ModulesTest` fixtures, lock bed `modules-discovery` extended |
| M2b | Shipped places in packaging: `nix/package.nix` (`share/h2s-shell-modules`, the wrapper passes it), `install.sh` and the update fill `~/.local/share/h2s-shell/shipped/`, the launcher's shipped root | none | `tests/install-test.sh` case, NixOS system test case |
| M3 | The installer (`singletons/ModuleInstaller.qml`): stage, check, version directories and the link, record, remove (`removalPlan`, with data), switch version, delete a version, roll back on a failed start; IPC `modules install/remove/switch` | none | `ModuleInstallerTest` on local repos, folders, links (the target untouched), stand-in `git` |
| M3b | The updater: check (`ls-remote`), the daily setting (`modules.checkUpdates`), background download, the queue, consent hold and refusal, the grouped restart offer, the notifications; IPC `modules check/update` | none | `ModuleUpdaterTest` (local bare repos, stand-in `git`, fake clock, recorded notifications) |
| M4 | Settings → Modules page: list, cards (`SettingsCard` gains a leading item for the icon), on/off, reload, the confirmation, remove with its lines and checkbox, dependencies, "Check all" | page | `ModulesPageTest` (stand-in host, clicks), `AnchorsTest` (the page's anchor) |
| M5 | Install and update on the page: field, folder dialog, progress, preview, changelog, the queue rows, consent box (accept, refuse, delete the new version), switch version, the restart offer | page | the page suite on local repos |
| M6 | The safe-mode banner (HUD and page) | banner | `HudTest`-style suite on a host in safe mode; lock-closure |

M0–M3b need no views and can go while the mockups are judged. CHANGELOG lines with M1c (API),
M2 (behaviour: new modules start off), M4, M5, M6.

## 10. Decided (the owner, 2026-11-21)

1. Shipped modules live outside the shell's tree: NixOS `$out/share/h2s-shell-modules`; Arch `~/.local/share/h2s-shell/shipped/` (filled by the shell's install and update only), later under `/usr/share` with an AUR package; shipped = trusted, some may ship off.
2. A module keeps its state across updates (so today's Tailscale stays on); update check by hand or automatic (a setting, default off); background download, old version runs; switch when nothing needs consent; consent when the source changed or the module first declares administrator actions (undeclared modules' prompts refused, honestly not a guarantee); refusal remembered, old version stays, the user is told, the new one can be deleted and never activates; "Switch version"; changelog before install and update; new programs and a major version only shown after.
3. Shipped modules are authorized by design; modules installed by the system count as consented ("Installed by the system — not part of h2s-shell").
4. Removing asks with a checkbox "Also delete its data and settings", unchecked.
5. Remove is offered for everything in the user root, hand-placed folders and links (the link only); the question says it was not installed by the shell and what is deleted.
6. The development path is exempt from the confirmation; its card says "Development path".
7. "Restart shell" is the user's click, never automatic; several updates form a queue and shell-wide actions are offered once after it ends.
8. "Check all" at the top of the page, besides each card's own.

## 10b. Open questions

1. **Arch's later system place for shipped modules.** You named `/usr/share/h2s-shell/modules`
   for an AUR package of the shell — but that is also where other packages' modules go, which
   the shell shows as "Installed by the system — not part of h2s-shell". If both share it, a
   shipped module would wear that label (and a package's module would count as shipped).
   Recommendation: the shell's package uses `/usr/share/h2s-shell/shipped`, other packages
   `/usr/share/h2s-shell/modules`.
2. **Does an update switch without a click?** Your model: download in the background, then
   switch when nothing needs consent. Read literally with the daily check on, a module would
   change under you overnight, and "read what changed before you update" could not happen.
   Example: Weather 1.3.0 appears at 9:00; does it run at 9:01, or does the card show
   "Update to 1.3.0" until you click? Recommendation (in this plan): the check and the
   download run by themselves, the switch follows your "Update" / "Update all" click and then
   needs nothing more unless consent is due. A later setting "Install updates by themselves"
   (off) could add the other way.
3. **More administrator programs in an update.** A module that already declares
   `privileged` adds a program to it (example: Tailscale 0.8.0 starts running `nft` as root
   besides `tailscale`). Your rule makes only the first declaration a consent trigger.
   Recommendation: keep it so (shown after the update, like a new program) — the prompt still
   names the command each time.
