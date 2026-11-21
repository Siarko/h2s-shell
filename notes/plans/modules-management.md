# Managing modules: Settings → Modules, the trust model, the safe-mode banner

Tracker: order of work step 1 (second item: this plan), step 8 ("Modules closed for now"),
and the parts of step 13 that land here (the trust text, the confirmation, where a module
comes from). Decisions: [decisions.md](../decisions.md), "Direction, modules and trust".
Mockups: `~/src/h2s-mockups/modules-settings-planned/` (kept outside the repositories; open with
`qs -p <that folder>/shell.qml`, scenes switched at its top; `shoot.sh` takes the screenshots).

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
  `<configHome>/h2s_shell/modules`. The owner's Tailscale module is a link in the user root.
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
> internal parts. These checks catch mistakes. They do not make a module safe. A module
> that makes the shell crash twice at start is not loaded the next time (safe mode).
>
> **What protects you.** Modules shipped with the shell are reviewed with it. Any other
> module is its author's work, not the project's: the shell says so and asks before it
> first turns one on. A module asks for administrator rights only through the shell's
> password prompt, which names the module, says what the action is for and shows the
> command; for a module that is not the project's, that text is the only protection — read
> it, and cancel when it does not match what you just did. The shell never installs,
> updates or turns on a module without your click, and never asks for a password by itself.
>
> **What to install.** Treat a module like a program you run as yourself: install it only
> from someone you trust, from a repository you could read, and pin it to a tag rather
> than a branch that can change under you.

The confirmation shown when a module that is not shipped is first turned on (UI words):
"**<Name> is not part of h2s-shell.** It runs inside the shell with your rights and could
read anything the shell sees, your lock screen password included. Turn it on only if you
trust where it comes from." — buttons "Turn on" (`save`), "Cancel" (`cancel`).

## 3. Where a module comes from

A pure rule, `ModuleInstallRules.sourceOf(directory, roots, records)`, from the canonical
directory and the record of what the shell installed:

| Source | Found in | Shown as | Actions |
|---|---|---|---|
| `shipped` | the shell's own module place (§9 Q1) | "Shipped" | on/off, reload |
| `repository` | user root, with an install record | "From <host/path> @ <ref>" | on/off, reload, check/update, remove |
| `folder` | user root, with a record of a copied folder | "Copied from <path>" | on/off, reload, update (copy again), remove |
| `user` | user root, no record (placed by hand, a link) | "Your copy" (a link: "Your link → <target>") | on/off, reload |
| `system` | a system data dir, or anything under `/nix/store` | "Installed by the system" | on/off, reload |
| `developer` | `H2S_SHELL_MODULE_PATH` | "Development path" | on/off, reload |

The winner of an id gets `replaces: [{ directory, source, version }]` (precedence extended),
shown on its card: "Replaces the shipped copy (1.2.0)" — the decision's "shown when a
user's copy replaces a shipped one". Remove is offered only for what the shell installed;
a hand-placed copy or link is the user's to remove (the shell never follows a link to
delete, and never deletes a directory it did not make).

## 4. Settings → Modules

The System tab's "Modules" group becomes permanent; its first page is the core's
`modules` page ("Installed"), modules' own pages follow under it.

**The list**: one `SettingsCard` per module (a `KeyedModel` keyed by id; duplicates are
shown inside their winner's card, not as cards). Closed: the icon (`ModuleIcon`), the name,
a subtitle "version · source"; on the name line a `StatusPill` (s) with the state:

| State | Pill | Kind |
|---|---|---|
| loaded | "On" (parts: warnings, deprecations as counts) | success |
| disabled | "Off" | muted |
| unconfirmed (new, §5) | "New — off" | warning |
| failed / incompatible | "Failed" / "Needs API 2.x" | danger |
| missing-program / missing-module | "Needs gcalcli" / "Needs Tailscale" | warning |
| pending | "Starting…" | muted |
| safe-mode | "Safe mode" | warning |

Its button row: the main button — "Turn off" / "Turn on" (one decision from the state:
`ModuleInstallRules.actionsFor(status, source, context)` returns labels and effects
together); "Update to 1.3.0" when an update is known; Remove (`DeleteButton`, "Remove?")
last. Opened: the description; source (URL, ref, commit, installed when; or the path);
API asked and the shell's; dependencies — "Needs: Tailscale 1.0 — on" (hard), "Can use:
Weather 1.x — not installed" (soft), "Used by: Exit map"; programs, missing ones with the
manifest's `setupHints`; then errors (`Notice` danger, one per line), warnings and
deprecations ("Uses Api.module(), which goes in the next tightening"), all as plain text,
capped; the data directory's path; buttons "Reload", "Check for updates".

**Above the list**, a section "Add a module": one field ("Repository address or folder"),
"Choose folder…" (the platform's folder dialog), "Install". Under it, while an install runs,
its step ("Fetching…", "Checking…") and Cancel; then the preview (§6).

**Actions and what they do**
- *Turn on / off*: `ModuleHost.setEnabled`. Off with running dependents: the button asks
  first, naming them ("Also turns off Exit map?", `DeleteButton` kind `warning`).
- *Reload*: the module off and on (a new main); when its files changed on disk (an update,
  an edit) and Qt's component cache or its singletons keep the old code, the card says
  "Restart the shell to load the new files" with a "Restart shell" button (§7, M3 measures
  which).
- *Install*: §6. *Update*: the same pipeline into staging, then a swap; the old copy is kept
  until the new one has loaded once ("Go back to 0.6.0" while it is kept).
- *Remove*: asks ("Remove?"), turns the module off, moves its directory to staging, deletes
  it, drops its record. Its data directory and settings stay (the shell never removes data;
  §9 Q4). A provider with dependents names them in the question.

**Privileges: none.** Every file the page writes is the user's own, under the data home;
nothing runs as root, no `pkexec`, no `sudo`. A system module is read-only in the list.

**Never automatic**: fetching (no update check at start or on a timer — "Check for updates"
is a click), installing, updating, removing, turning on a module found on disk, deleting a
data directory, following a link to delete, running anything from a module's files during an
install (no hooks, no submodules, no build step), asking for a password, acting while the
session is locked (IPC refuses, the window is closed then).

## 5. The confirmation (first turned on)

A module that is not shipped and not from the developer path starts **off** the first time
the host sees it (`unconfirmed`, a new state), until the user turns it on through the
confirmation (§2's text) — remembered as acknowledged by `id` + `source` + canonical
directory in `Config.acknowledgedModules` (remembered state, not a preference). A new
source or directory for the same id (a user copy replacing a shipped one) asks again.
Installing through the page with "Install and turn on" is the confirmation (the preview
carries the text). IPC: `modules setEnabled` refuses an unconfirmed module with the reason;
`modules confirm <id>` acknowledges it (a typed command is a click). Migration: the modules
present on both machines today (Tailscale) are in use, so per the decision the owner is
asked (§9 Q2); the proposal is to acknowledge, once, every module found enabled at the
first start of the new version.

## 6. Installing

- **Source**: a git address (`https://`, `ssh://`, `git@host:path`, `git://`, `file://`),
  optionally with `#<ref>`; or a folder. `ModuleInstallRules.repositoryProblem` refuses
  anything else (`ext::` and `fd::` run commands; a leading `-`; control characters; over
  1000 characters). The address is always an argument after `--`, never in a shell string.
- **Fetch** into `<dataHome>/h2s-shell/module-staging/<random>` (same filesystem as the
  modules, so the final step is a rename): `git -c core.hooksPath=/dev/null
  -c protocol.allow=never -c protocol.{https,ssh,git,file}.allow=always clone --depth 1
  --no-recurse-submodules [--branch <ref>] -- <url> <dir>`, with `GIT_TERMINAL_PROMPT=0`,
  `GIT_ASKPASS=` / `SSH_ASKPASS=` empty, `GIT_SSH_COMMAND="ssh -o BatchMode=yes"` (never a
  credential prompt), under a time limit and a size cap on the result (a fetch too large is
  stopped). A folder is copied (`cp -R --no-dereference`, then the file check refuses links
  out). Through the host's `CommandRunner`, as the user.
- **Check**: the host's own file check and manifest rules on the staged directory (no new
  checker): valid, API fits, the id free or held by a copy it would replace (said in the
  preview), files inside. A module failing here is never moved in.
- **Preview** (the confirmation): icon, name, id, version, API (fits / not), source with the
  commit, the programs it names (found / missing), the modules it uses (there / not), what it
  would replace, the §2 statement; "Install and turn on" (`save`), "Install, keep off",
  "Cancel" (deletes the staging directory).
- **Move in**: rename to `<dataHome>/h2s-shell/modules/<id>`; write the record; then the
  shell runs discovery itself (`launch.sh --discover-modules`, the same code) and `load()`s
  the new list — no restart needed for a new module. Failures at any step leave no partial
  module (staging is removed; the list says why, one line).
- **Update**: "Check for updates" = `git ls-remote` of the recorded address and ref (a click,
  per module or for all); a newer commit → "Update to <version>" after a staged clone shows
  the new manifest's version. The swap keeps the old copy in staging until the new one loads.
- **Record**: `<dataHome>/h2s-shell/module-sources.json`, `{ <id>: { kind, source, ref,
  commit, installedAt, previous } }`, written by a temp file and a rename; a missing or
  unreadable record makes the module `user` (read-only for removal: "unknown", never "fine").

## 7. Safe mode and the banner

**When**: `Modules.safeMode` (either counter). **Where**: the HUD under the bar (a
`StartupWarning` with buttons) and on top of Settings → Modules (the page's `banner`).
Never on the lock screen (lock-closure). **What it says**: "Started without modules" and
why, in plain words — "The shell crashed twice within 30 seconds of starting." — then
"Modules on when it crashed: Tailscale, Weather." (the host writes the enabled ids to
`$XDG_RUNTIME_DIR/h2s-shell-modules-on` at each load; safe mode reads the last one) and, when
one was installed or updated in the last day, "Weather was updated 10 minutes ago."
**What it offers**: "Open Modules" (the page, to turn suspects off), "Load modules" (the host
`load()`s the list again without safe mode, in place; a module that crashes the shell now
counts towards the launcher's next safe mode as any start does), × (for this run; the page
banner stays). The safe-mode notification stays as the announcement; its body points to the
banner instead of the IPC command.

## 8. NixOS and Arch

- **NixOS**: a module from the system's data dirs (`/run/current-system/sw/share`,
  `/etc/profiles/per-user/<user>/share`) or any path under `/nix/store` is `system`:
  read-only (on/off only); the later NixOS option (`programs.h2s-shell.modules`) puts its
  modules there too, never in the user root. git comes with the package. A user's install of
  the same id wins (user root first) and its card says it replaces the system's copy.
- **Arch**: `/usr/share/h2s-shell/modules` (a package's) is `system`, read-only. git is
  already needed by `install.sh`; Settings → Modules says "git is needed to install from a
  repository" when it is missing (a folder install still works).
- Both: the user root, staging, records and data are the same paths; no privileges.

## 9. Slices

Each with its tests; while iterating the named suites, before committing `tests/run-all.sh`.
Stand-ins only: a repository is a local bare git repo made in the suite's temporary home
(`git init --bare`, a fixture module committed and tagged) reached by `file://`, or a
folder; a stand-in `git` (hangs, refuses, too large) for failures; the network is never
touched (a suite asserts nothing it ran named a non-`file` address).

| | Slice | Views | Tests |
|---|---|---|---|
| M0 | The trust text in `docs/` (§2: ARCHITECTURE "Modules", FEATURES, README one line) | none | — |
| M1 | `ModuleInstallRules` (pure): `sourceOf`, `replaces`, `actionsFor`, `repositoryProblem`, the git argv, record parse, `needsConfirmation`; `stateOf` gains `unconfirmed` | none | `ModuleInstallRulesTest`, `ModuleRulesTest` cases |
| M2 | The host: acknowledgements (`Config.acknowledgedModules`), `unconfirmed`, `source`/`replaces` in the status and `modules list`, `modules confirm`, the modules-on file, "load without safe mode", re-discovery + `load()`; what Reload can pick up (a `QuickshellPinTest` case: changed file after off/on) | none | `ModulesTest` fixtures, lock bed `modules-discovery` extended |
| M3 | The installer (`singletons/ModuleInstaller.qml`, scripts as rules): stage, check, move in, record, update, remove, rollback; IPC `modules install/update/remove/check` | none | `ModuleInstallerTest` on local repos and folders, stand-in `git` |
| M4 | Settings → Modules page: list, cards (`SettingsCard` gains a leading item for the icon), on/off, reload, the confirmation, remove, dependencies | page | `ModulesPageTest` (stand-in host, clicks), `AnchorsTest` (the page's anchor) |
| M5 | "Add a module" and update on the page: field, folder dialog, progress, preview, errors | page | the page suite on local repos |
| M6 | The safe-mode banner (HUD and page) | banner | `HudTest`-style suite on a host in safe mode; lock-closure |

M0–M3 need no views and can go while the mockups are judged. CHANGELOG lines with M2
(behaviour: new modules start off), M4, M5, M6.

## 10. Open questions for the owner

1. Where do shipped modules live? A modules directory inside the shell's tree would be
   scanned by Quickshell as shell types, so the proposal is a sibling place outside it
   (`$out/share/h2s-shell-modules` on NixOS, a directory next to the checkout on Arch);
   until one is shipped, "Shipped" is only a word in the rules — is that acceptable?
2. Should the modules enabled today (Tailscale on both machines) be acknowledged once
   automatically at the first start of the new version, or should you confirm each by hand?
3. Should modules found in the system's data directories (a NixOS configuration, an Arch
   package) need the confirmation too, or does installing them as administrator count as it?
4. When a module is removed, should the page offer to delete its data directory and settings
   as well (a checkbox in the question), or should the shell keep never removing data?
5. Should "Remove" also be offered for a copy you placed by hand (deleting a link only,
   never its target), or stay limited to what the shell installed?
6. Is a module from `H2S_SHELL_MODULE_PATH` (the development path) rightly exempt from the
   confirmation, since naming it in the environment is already a deliberate act?
7. When a reload cannot pick up changed files without restarting the shell, is a
   "Restart shell" button on the card acceptable, or should an update always restart?
8. Should "Check for updates" exist for all modules at once (one click, one `ls-remote` per
   repository), or only per module?
