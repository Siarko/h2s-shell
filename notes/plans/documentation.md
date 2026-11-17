# Documentation plan

A plan for the owner to approve. It covers the shell's user and developer documentation.
The plan itself is a working document. It may name stages and dates. The documents it plans may not.

Readers:

- **User**: installs the shell, configures it, uses it.
- **Developer**: reads the architecture, writes a widget or a module, runs tests, contributes.

The three rules every planned document must meet:

1. The README is short. Details live in `docs/`.
2. Plain short sentences, one idea each. Lists and tables for lists and tables. Nothing obvious explained.
3. Self-contained and about the code. No delivery history: no stages, plans, reviews, "since", "no longer", "earlier".

## 1. Inventory

Counts are lines / words in this worktree (`plan-architecture`, at `259335d`).

### User and developer documents

| File | Size | Audience | What it really contains | Rules 1/2/3 | Stale |
|---|---|---|---|---|---|
| `README.md` | 185 / 1313 | user, some dev | features, requirements, install (Arch, NixOS), autostart, supervisor, tablet mode, full PAM setup, security key registration, Google Calendar, dev pointer | fails 1, 2, 3 | some |
| `docs/FEATURES.md` | 439 / 5066 | user, with dev detail | every widget, panel, HUD, lock screen, network settings, polkit, settings pages, external tools | fails 2, 3 | yes |
| `docs/ARCHITECTURE.md` | 714 / 6499 | developer | runtime, layers, I/O idiom, VPN providers, profiles, bar, popup, Repeater crash, shaders, widget contract, hardware, promises, lock screen internals, modules, logging, conventions, adding a widget, testing | fails 2, 3 | yes |
| `docs/STYLES.md` | 87 / 829 | developer | a draft spec of a CSS dialect for themes. Nothing of it exists in the code. | it is a plan, not a document | n/a |
| `docs/quickshell-integration.md` | 274 / 2098 | pttd client author | the `pttd` dictation daemon's socket protocol, in Polish, with a "changes since the previous version" section | fails 3, wrong repo | not checked |
| `CLAUDE.md` | 111 / 898 | agents | project summary, doc pointers, how to run, conventions (a copy of ARCHITECTURE's), environment | mostly fine for its reader | yes |
| `CHANGELOG.md` | 911 / 11912 | user, module authors | release history. `[Unreleased]` alone is 650 lines and holds the module API history. | history by nature | n/a |
| `tests/lock/README.md` | 423 | developer | the lock test bed | not reviewed in depth | not checked |
| `tests/device/README.md`, `tests/manual/README.md` | 39, 15 | developer | device tests, the manual PAM check | fine | not checked |
| `site/index.md`, `site/privacy.md` | 16, 38 | public | GitHub Pages: homepage, privacy policy for Google OAuth | fine | keep as is |

### Working documents (development history)

| File | Size | What it is |
|---|---|---|
| `docs/CLEANUP.md` | 703 / 4892 | findings backlog from a full read, with severities and fix notes |
| `docs/TODO.md` | 159 / 1678 | the open checklist, in the owner's order, with status |
| `docs/TODO-DONE.md` | 906 / 9566 | done items, numbers kept |
| `notes/plans/*.md` | 17 files, 5 018 lines | designs and delivery plans per feature |
| `notes/reviews/architecture-2026-11-16.md` | 559 / 4734 | one architecture review |
| `notes/upstream/quickshell-session-lock-unlock-notify.md` | 243 / 1393 | analysis of a Quickshell bug, for upstream |

Code comments point into these in 113 places (`notes/plans/…`, `TODO 11.36`, `CLEANUP #12`).

### The worst three

**1. `docs/ARCHITECTURE.md`.** The only developer reference, but written as a log of decisions.
Paragraphs are single sentences of 10+ lines. It cites plans for the real contracts.

- Rule 2, line 450–459: one sentence from "`scripts/launch.sh` supervises the shell" to "not the crash reporter", with five parentheticals, two dashes and a semicolon chain.
- Rule 3, line 238: "For months the shell crashed at random … It was traced in May 2026 to a Qt 6.11 regression".
- Rule 3, line 495: "What exists (M0–M2): the rules, the host, discovery, …".
- Rule 3, line 156: "The contract in full: [plans/tailscale.md](plans/tailscale.md) §3".

**2. `docs/FEATURES.md`.** The user's only feature list, but full of internals and history.
Network settings (line 271–337) is one paragraph of 67 lines.

- Rule 3, line 257: "(Escape at a showing prompt unlocked until 2026-11-15.)"
- Rule 3, line 184: "(not yet wired up — see CLEANUP.md #12)". It is also false, see below.
- Rule 2, line 115: "The shell's own messages follow the same rules (Settings → Notifications). A finger swipe sideways dismisses a toast (past a third of its width, or flung); its countdown pauses while it is being dragged."

**3. `README.md`.** The front door, but it holds the full PAM manual and the lock supervisor's internals.

- Rule 1 and 3, line 3: "**THIS IS ALL WORK IN PROGRESS. README AS WELL**".
- Rule 3, line 89: "see `notes/plans/lockscreen.md`, section 7, "Recovery"".
- Rule 2, line 138–144: one sentence about `pam_faillock` with a dash-delimited aside of four lines inside it.

`STYLES.md` is not ranked. It is a design spec and moves to the working documents.

### False or outdated statements found

Spot checks against the code. Each line: where the document says it, what the code says.

| Document | Claim | Code |
|---|---|---|
| `ARCHITECTURE.md:344–352` | `Promises.await()` busy-waits; "the most serious known defect" | `singletons/Promises.qml` has no `await`. Its functions are `create`, `resolved`, `rejected`, `allSettled` (lines 9–121). |
| `ARCHITECTURE.md:611–613` | debug switches are `Config.general.debug`, `Config.general.fetch_debug`, `Config.gcal.debug`, `Config.stt.debug` | they are global settings `general.debug`, `general.fetchDebug`, `stt.debug`, `gcal.debug`: `singletons/SettingsSchema.qml:94–97, 210, 216` |
| `ARCHITECTURE.md:608` | `Logger { … enabled: Config.stt.debug }` | `singletons/Stt.qml:59`: `enabled: Profiles.value("stt.debug") ?? false` |
| `ARCHITECTURE.md:652–655` | settings pages "are still wired by hand in `SettingsWindow`'s navigation model and `sourceComponent` if-chain" | `panels/SettingsWindow.qml:32`: a `corePages` table. ARCHITECTURE itself says so at line 524. |
| `ARCHITECTURE.md:617–618` | "~37 places still" hold a literal colour | a grep finds about 10 `"#…"` / `Qt.rgba(` uses outside `singletons/`, most derived from theme colours (e.g. `panels/music/VisualizerCanvas.qml:101`) |
| `FEATURES.md:184` | screensaver commands are "not yet wired up" | `singletons/Lockscreen.qml:1005–1016`: `_runCommand` runs them when `lockscreen.screensaverCommands` is on |
| `FEATURES.md:365` | the settings window has "Two tabs" | three: `behaviour`, `appearance`, `system` (`panels/SettingsWindow.qml:33–70`) |
| `FEATURES.md:389–398` | Appearance has 6 pages | 11: Widgets, Popups, Controls, Notifications and Other are missing (`panels/SettingsWindow.qml:51–60`) |
| `FEATURES.md:371–383` | the Behaviour pages | Wallpaper is missing (`panels/SettingsWindow.qml:40`) |
| `README.md:182` | "`quickshell -p tests.qml` runs the test suites" | the runner is `tests/run-unit.sh`. `CLAUDE.md:42` says not to run `tests.qml` directly. |
| `CLAUDE.md:104` | "In the dev container (`.devcontainer/`)" | there is no `.devcontainer/` in the repo |
| `CLAUDE.md:101` | the host is "Arch, Hyprland" | the owner's machine runs NixOS. The doc should name neither. |
| `ARCHITECTURE.md:9` | Quickshell at `quickshell.outfoxxed.me` | the README and site use `quickshell.org` |

Claims that checked out: the widget table (`singletons/WidgetRegistry.qml:33–59`), the NixOS options (`nix/module.nix:24–45`), the launcher flags (`scripts/launch.sh:660–690`), the tablet IPC (`singletons/TabletMode.qml:27–44`).

## 2. Target structure

User documents sit in `docs/`. Developer documents sit in `docs/dev/`.
The README links to both. Nothing in either links to `notes/` (section 3).

```
README.md                      user        what it is, screenshot, quick start (NixOS, Arch), link table          ~70
CHANGELOG.md                   user, dev   releases; new entries follow rule 2                                    as is
docs/
  install.md                   user        NixOS flake and module options; Arch: install.sh and by hand;
                                           Hyprland autostart, allow_session_lock_restore, updating, removing     ~120
  requirements.md              user        table: tool, needed for, optional, Arch package, NixOS source           ~60
  getting-started.md           user        first run: what appears, opening settings, adding widgets,
                                           the seeded profiles, tablet mode bindings                              ~70
  settings.md                  user        the settings window: tabs, pages, profiles and conditions,
                                           where a value comes from, pin and reset, config files                  ~120
  settings-reference.md        user        every setting key: type, default, page, global; one table per page     ~250
  bar.md                       user        edges, sections, presets, popup modes; each widget and its popup       ~150
  notifications.md             user        the server, toasts and their screen rules, history, codes, OSD         ~70
  lock-screen.md               user        screensaver, lock, idle, sleep, unlocking methods, PAM on NixOS
                                           and Arch, registering keys, recovery, honest limits                    ~200
  polkit.md                    user        the agent: switching it on, the prompt, fingerprint order on NixOS     ~50
  network.md                   user        popup, settings pages, hotspots, connection editor, VPNs,
                                           VPN with a network, kill switch and its limits                         ~200
  themes.md                    user        themes, curves, drafts, theme files, icon theme                        ~100
  wallpaper.md                 user        sources, modes, fits, transitions, cache                               ~60
  calendar.md                  user        Google account, own OAuth client, privacy                              ~40
  media.md                     user        music popup, visualiser, cava                                          ~40
  dictation.md                 user        pttd client: widget, settings, music pause                             ~40
  modules.md                   user        installing a module, trust, turning one off, safe mode, paths          ~80
  ipc.md                       user        every IPC target and function, with examples                           ~120
  troubleshooting.md           user        logs, restart, unlocking from a console, safe mode, common faults      ~100
  dev/
    architecture.md            developer   runtime model, directory map, layers, rules/driver pattern,
                                           per-screen objects, popup, config and profiles, I/O idiom              ~250
    conventions.md             developer   the rules: Repeater crash, Process start, PointerArea,
                                           DeleteButton, Theme, names, comments, no qmldir, singleton reload      ~120
    widgets.md                 developer   writing a bar widget: contract, BarRow/BarText, registry entry,
                                           popup panel, preset settings, its test                                 ~120
    lock-screen.md             developer   rules, driver, adapters, views; fail-closed; recovery; test seams      ~180
    network.md                 developer   network managers, events, VPN provider contract, kill switch script    ~120
    modules.md                 developer   writing a module: layout, manifest, lifetime, slots, commands,
                                           storage, testing it in another repo                                    ~200
    module-api.md              developer   reference: Api, ModuleHandle, ModuleStore, ThemeTokens, types,
                                           manifest fields, slot table, API versions                              ~250
    testing.md                 developer   run-unit, run-modules, the lock bed, device and manual tests,
                                           writing a suite, async suites, the docs check                          ~150
    releasing.md               developer   version number, changelog, tags, module API version rules,
                                           shaders, the flake                                                     ~50
site/                          public      unchanged
notes/                         working     section 3
```

About 25 files and 3 400 lines, against 3 700 lines of user/dev text today.
The structure follows the Tailscale module's docs and the owner's reference project: a short README with a link table, one topic per file.

### Generated or hand-written

Everything is hand-written. Generated text reads like a schema dump, and schema labels are UI strings, not explanations.

Drift is caught by checks instead. Each check compares a document with a list the code already holds.

| Document | Source of truth | Check |
|---|---|---|
| `settings-reference.md` | `SettingsSchema.entries` with no module loaded | QML suite `tests/DocsTest.qml`: every key is in the doc; every key-shaped name in the doc's tables exists. Pattern keys (`widgets.<type>.popupMode`, `bar.<side>`) are expanded from `WidgetRegistry`. |
| `settings.md` page list | `SettingsWindow.corePages` ids | same suite. The ids matter: `ipc call settings openPage <id>` takes them. |
| `bar.md` widget list | `WidgetRegistry.coreEntries` types | same suite |
| `module-api.md` slots and manifest | `ModuleRules.slotTable`, the manifest field list in `ModuleRules` | same suite |
| `module-api.md` members | public `property` and `function` names in `api/*.qml` | `tests/docs-check.sh`, a grep: names without a leading `_` must appear in the doc |
| `ipc.md` | `IpcHandler` blocks: `target` and `function` names | `tests/docs-check.sh`, an awk over `IpcHandler {` blocks. Test-only targets (`shelltest`, `locktest`, `fakevpn`) go in `dev/testing.md`. |
| `install.md` NixOS options | `options.programs.h2s-shell` in `nix/module.nix` | `tests/docs-check.sh`, a grep |
| `install.md`, `troubleshooting.md` launcher flags | the `case "$1"` in `scripts/launch.sh` | `tests/docs-check.sh` |
| all of `README.md`, `docs/` | the rules | `tests/docs-check.sh`: relative links resolve; no link into `notes/`; backticked repo paths exist; a word list for rule 3 (`since`, `no longer`, `earlier`, `until 20`, `TODO`, `CLEANUP`, `plans/`, `stage`, `M[0-9]`) |

Cost: one QML suite (FileView reads the doc, like `singletons/io/KernelFile.qml`) and one shell script. `tests/run-unit.sh` runs both, so the checks run with every unit run.

`qs ipc show` on a running shell would be the exact IPC list. It needs the lock bed, which is slow. The awk check is enough while every handler keeps the current layout.

The rule 3 word list is a lint, not proof. It catches the common slips. Review still reads for the rest.

## 3. Working documents

Plans, reviews, TODO, CLEANUP and upstream notes are history. User and developer docs must not link to them.

Options:

| Option | For | Against |
|---|---|---|
| A. `notes/` at the repo root | outside `docs/`; agents and code comments still reach it in every worktree; one `git mv` | still in the public repo |
| B. `docs/internal/` | no move of the top level | sits inside `docs/`; easy to link by mistake |
| C. a separate repo or orphan branch | the public tree stays clean | worktrees and agents lose it; 113 code comments point at nothing |
| D. GitHub issues for the tracker, A for the rest | issues suit open items | the owner's agents work from files |

**Recommendation: A.**

```
notes/
  README.md          one paragraph: development history and the tracker, not documentation
  tracker.md         TODO.md and the open items of CLEANUP.md, one list
  done.md            TODO-DONE.md and the closed CLEANUP.md items
  plans/             today's notes/plans/, plus STYLES.md as plans/stylesheets-spec.md
  reviews/
  upstream/
```

- `docs/quickshell-integration.md` belongs in the pttd repository. Until it moves, it goes to `notes/`. `docs/dictation.md` names the socket path and the pttd project only.
- The 113 code comments are rewritten from `notes/plans/` to `notes/plans/` in the same commit. A comment that only cites a TODO number loses the number where the code says enough. Coordinate with `notes/plans/architecture-cleanup.md`: it may rewrite those files anyway.
- `docs-check.sh` fails on any link from `README.md` or `docs/` into `notes/`.

`CLAUDE.md` afterwards:

- points to `docs/dev/architecture.md`, `docs/dev/conventions.md` and `docs/dev/testing.md`;
- points to `notes/tracker.md` as the place to resume work, and `notes/plans/` for designs;
- keeps only what is about agents: commit only when asked, restart after a singleton edit, the `flock` wrapper for parallel test runs;
- drops its copy of the conventions. `docs/dev/conventions.md` becomes the one copy;
- drops the `.devcontainer` and "host is Arch" section.

## 4. Dependencies

Two plans run in parallel: `notes/plans/api-next.md` (module API extension) and `notes/plans/architecture-cleanup.md`.

| Document | Waits for | Why |
|---|---|---|
| `dev/module-api.md`, `dev/modules.md` | API extension | the reference would be written twice |
| `docs/modules.md` (user) | install-from-repository work (`next-steps.md` §2, M4), if it is near | adds a Settings → Modules page and `modules sync` |
| `dev/architecture.md`, `dev/widgets.md`, `dev/conventions.md`, `dev/lock-screen.md`, `dev/network.md` | architecture clean-up | file names, contracts and seams may change |
| `themes.md` | the owner's choice on the stylesheet spec (question 5) | the theme file format may change |
| everything else in `docs/` | nothing | describes behaviour, not structure |
| `dev/testing.md`, `dev/releasing.md` | nothing, unless the clean-up touches the runners | stable |

The user docs can all start now except `themes.md` and `modules.md`.
If the clean-up renames setting keys or IPC functions, the checks of section 2 show which docs to touch.

## 5. Order of work

Each slice is written by an agent and fact-checked by a second agent that did not write it.
The fact-checker lists every claim with the file:line that backs it, or marks it unbacked.
The owner reads for voice and approves. Sizes: S < 150 lines of docs, M 150–400, L > 400.

| # | Slice | Size | Truth checked by |
|---|---|---|---|
| 0 | Move working docs to `notes/`; rewrite comment paths; trim `CLAUDE.md` | S | `docs-check.sh` link rules; a grep that no `notes/plans/` path remains |
| 1 | `tests/docs-check.sh` and `tests/DocsTest.qml`, failing until the docs exist (or skipping missing files) | S | `run-unit.sh` on the host |
| 2 | `README.md`, `install.md`, `requirements.md`, `getting-started.md`, `troubleshooting.md` | M | fact-check against `install.sh`, `nix/module.nix`, `nix/package.nix`, `scripts/launch.sh`, `scripts/lock-log.sh`; NixOS options and launcher flags by the check |
| 3 | `lock-screen.md`, `polkit.md` | M | fact-check against `singletons/LockRules.qml`, `Lockscreen.qml`, `pam/`, `scripts/lock-auth-methods.sh`, `nix/module.nix`; each behaviour claim mapped to its lock-bed test (`tests/lock/tests/*.sh`) where one exists |
| 4 | `settings.md`, `settings-reference.md`, `ipc.md` | M | keys, page ids, IPC names by the checks; descriptions by fact-check |
| 5 | `bar.md`, `notifications.md`, `wallpaper.md`, `calendar.md`, `media.md`, `dictation.md` | M | widget list by the check; the rest by fact-check; the owner looks at the running shell for the bar |
| 6 | `network.md` (user) | M | fact-check against `singletons/network/`, `scripts/h2s-vpn-lockdown`, `NetworkRules`; kill switch claims against `VpnProvidersTest.qml` and the script |
| 7 | `dev/testing.md`, `dev/releasing.md` | S | fact-check against `tests/*.sh`, `tests.qml`, `VersionTest.qml` |
| 8 | after the clean-up: `dev/architecture.md`, `dev/conventions.md`, `dev/widgets.md`, `dev/lock-screen.md`, `dev/network.md` | L | fact-check; `dev/widgets.md` walked through by an agent writing a throw-away widget in the isolated test harness |
| 9 | after the API extension: `dev/modules.md`, `dev/module-api.md`, `docs/modules.md` | M | API names by the check; `tests/fixtures/modules/good` as the worked example, loaded by `run-modules.sh` |
| 10 | after question 5: `themes.md` | S | fact-check against `ThemeFiles.qml`, `ThemeRules.qml` |
| 11 | delete `ARCHITECTURE.md`, `FEATURES.md`, `STYLES.md`; final link and lint pass | S | `docs-check.sh` |

Old documents stay until the slice that replaces their content is done.

## 6. Voice sample

Source: `README.md:73–114`, "Starting it" and "Tablet mode". 42 lines.

### Before

```markdown
### Starting it

From Hyprland's autostart, in `hyprland.lua`:

    hl.on("hyprland.start", function()
    	hl.exec_cmd("h2s-shell")  -- NixOS
    	-- Arch: hl.exec_cmd(os.getenv("HOME") .. "/.config/quickshell/default/scripts/launch.sh")
    end)

`launch.sh` (which `h2s-shell` runs) starts the shell with the icon theme chosen in its
settings, and stays as its supervisor: a shell that dies (a crash, a kill) is started
again, and one that died while the screen was locked locks again at once. For that the
lock screen needs one line in `hyprland.lua`'s `misc` settings,
`allow_session_lock_restore = true` (without it Hyprland refuses to let a restarted lock
screen take the lock back; see `notes/plans/lockscreen.md`, section 7, "Recovery").
`h2s-shell --restart` stops the shell (and its supervisor) and starts it again, detached;
there is one supervisor per session (a second start waits briefly, then gives up). If the
lock screen misbehaves, `h2s-shell --lock-log` (or `scripts/lock-log.sh`, also from a text
console while the screen is locked) prints what happened: the shell's lock lines
(Quickshell's log, `qs log`), the supervisor's log (`$XDG_RUNTIME_DIR/h2s-shell-launcher.log`)
and the journal's PAM, fprintd and logind lines — nothing typed is ever logged. A locked
screen that will not take the password is unlocked from a text console with `loginctl
unlock-session <id>` (the graphical session's id, from `loginctl list-sessions`); Escape
does not unlock, it only hides the prompt. Settings are kept in `~/.config/h2s_shell/`.

### Tablet mode

On a convertible, the shell can tell when it is folded into a tablet — a condition for
profiles (Settings → Profiles: "Tablet mode"). Hyprland reads the switch and tells the
shell, through two bindings in `hyprland.lua`:

    local shell = "h2s-shell"  -- Arch: os.getenv("HOME") .. "/.config/quickshell/default/scripts/launch.sh"
    hl.bind("switch:on:Tablet Mode Switch", hl.dsp.exec_cmd(shell .. " ipc call tablet set true"), { locked = true })
    hl.bind("switch:off:Tablet Mode Switch", hl.dsp.exec_cmd(shell .. " ipc call tablet set false"), { locked = true })

The switch's name differs between machines (`gpio-keys` on the Framework 12): see the
"Switches" in `hyprctl devices`. Hyprland reports only changes, so the shell starts as a
laptop until the next one; `ipc call tablet set true` by hand corrects it.
```

### After

The first part goes to `docs/install.md`, the log and unlock part to `docs/troubleshooting.md`, tablet mode to `docs/getting-started.md`.

````markdown
## Start the shell

Start the shell from Hyprland's autostart in `hyprland.lua`.

On NixOS:

```lua
hl.on("hyprland.start", function()
	hl.exec_cmd("h2s-shell")
end)
```

On Arch, start the launcher in the checkout:

```lua
hl.on("hyprland.start", function()
	hl.exec_cmd(os.getenv("HOME") .. "/.config/quickshell/default/scripts/launch.sh")
end)
```

On NixOS, `h2s-shell` runs the same launcher.
These docs write `h2s-shell` for both.

In the `misc` settings of `hyprland.lua`, set `allow_session_lock_restore = true`.
Without it, a restarted shell cannot take back a locked screen.

### The launcher

- It starts Quickshell with the icon theme from the settings.
- It starts the shell again when it crashes or is killed.
- A shell that dies while the screen is locked comes back locked.
- It runs once per session. A second launcher waits a moment, then exits.

| Command | What it does |
|---|---|
| `h2s-shell --restart` | stops the shell and starts it again in the background |
| `h2s-shell ipc call <target> <function> [args]` | calls the running shell, see [IPC](ipc.md) |
| `h2s-shell --lock-log` | prints the lock screen's log, see [Troubleshooting](troubleshooting.md) |

Settings are stored in `~/.config/h2s_shell/`.
````

````markdown
## The screen stays locked

Escape does not unlock. It only hides the prompt.

To unlock from a text console:

1. Find the graphical session's id with `loginctl list-sessions`.
2. Run `loginctl unlock-session <id>`.

To see what happened, run `h2s-shell --lock-log`. It works from a text console too. It prints:

- the shell's `[Lockscreen]` lines, from `qs log`;
- the launcher's log, `$XDG_RUNTIME_DIR/h2s-shell-launcher.log`;
- the journal's PAM, fprintd and logind lines.

It covers the last 30 minutes. `--minutes N` changes that, `--no-journal` leaves the journal out.
Nothing typed is ever logged.
````

````markdown
## Tablet mode

On a convertible, a profile can apply only in tablet mode.
Choose "Tablet mode" as its condition in Settings → Profiles.

Hyprland reads the tablet switch. Two bindings in `hyprland.lua` pass it on:

```lua
local shell = "h2s-shell"
hl.bind("switch:on:Tablet Mode Switch", hl.dsp.exec_cmd(shell .. " ipc call tablet set true"), { locked = true })
hl.bind("switch:off:Tablet Mode Switch", hl.dsp.exec_cmd(shell .. " ipc call tablet set false"), { locked = true })
```

- The switch name differs between machines. `hyprctl devices` lists it under "Switches".
- Hyprland reports only changes. Until the first one, the shell assumes laptop mode.
- `h2s-shell ipc call tablet status` prints the current mode.
- `h2s-shell ipc call tablet set true` sets it by hand.
````

What changed:

- One idea per sentence. The 20-line paragraph became a list, a table and three short sections.
- The link to `notes/plans/lockscreen.md` is gone. The reason is one sentence.
- The Framework 12 example is gone. It describes the owner's machine.
- Facts added from the code: `ipc call tablet status` (`singletons/TabletMode.qml:41`), the log window and its options (`scripts/lock-log.sh:9–24`).

## 7. Open questions for the owner

1. **Language.** English only now; translations later, as a separate task with the planned UI text pass. *Recommended: yes.*
2. **Screenshots.** The repo has no images. Options: none; one bar screenshot in the README; one per user page. *Recommended: one README screenshot now, at `docs/img/`, taken by the owner (the machine is shared). Others later.*
3. **Tracker.** One `notes/tracker.md` from TODO.md and the open CLEANUP items, or GitHub issues. *Recommended: one file. The agents work from files.*
4. **Working docs location.** `notes/` at the root (section 3, option A). *Recommended: A.*
5. **Stylesheet spec.** `STYLES.md` describes a CSS dialect nothing implements. Move it to `notes/plans/` and document today's theme files in `themes.md`, or hold `themes.md` until the dialect exists. *Recommended: move it; write `themes.md` from the settings pages now and add the file format when it is settled.*
6. **pttd protocol.** Move `quickshell-integration.md` to the pttd repository. *Recommended: yes; `notes/` until then.*
7. **API versions in the reference.** A module states the API it needs (`"api": "1.3"`). Mark each member with the API version that added it? It reads like "since", but it is a fact the manifest needs. *Recommended: one column "API" in `module-api.md`, nothing like it elsewhere.*
8. **Changelog.** `[Unreleased]` is 650 lines. Cut a release before the docs, so they describe a tagged version? Module API history moves to the API table of question 7. *Recommended: release first.*
9. **Folder split.** User docs in `docs/`, developer docs in `docs/dev/`. Or one flat `docs/` like the Tailscale module. *Recommended: the split. There are about 25 files.*
10. **Docs check in the unit run.** `docs-check.sh` and `DocsTest.qml` make `run-unit.sh` fail on a doc that drifted. *Recommended: yes. A failing doc is cheaper than a wrong one.*
