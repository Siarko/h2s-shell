# Documentation plan

A plan for the owner to approve: the shell's user, developer and module-author documentation
(tracker steps 12 and 13). Revised on 2026-11-21 for the owner's decisions of 2026-11-17 on
(`notes/decisions.md`, "Documentation", "Module API", "Direction") and for the code as it is
(core 2.0.0 plus Unreleased, module API 1.35). The first version (2026-11-17) is in git
(`git show 159d20b:notes/plans/documentation.md`); its voice sample and before/after example
(§6 there) still stand, without the machine-model line.

## 1. The rules every page meets

From the decisions and `CLAUDE.md`; a page that breaks one is not done.

1. **English only.** Translations come later with the UI texts pass (tracker, "Later").
2. **NixOS and Arch together.** Wherever the systems differ, a "NixOS" and an "Arch"
   subsection — never one system without the other. A feature only one system has gets its
   own page where that reads better (decision: "pages for system-only features").
3. **Nothing names or relies on a developer's environment**: no user names, home paths,
   machine models, host names, "the owner's machine".
4. **`docs/` never links into `notes/`.** Code comments may; documents may not.
5. **About the code as it is.** No history: no stages, plan codes (M3, U2), "since",
   "no longer", "until <date>". An API version where it is a fact a module needs ("added in
   API 1.20") only in the API reference (question 2).
6. **Plain short sentences**, one idea each; lists and tables for lists and tables. The
   README is short; details live in `docs/`.
7. **Screenshots are the owner's.** A page that wants one carries a marked placeholder
   (`<!-- screenshot: the network popup, two VPNs up -->`); agents never take or commit
   images.
8. **Checked for consistency at each major release**, not on every change (§5).

## 2. What exists today

Lines on `master` at `159d20b`.

| File | Lines | What it holds | State |
|---|---|---|---|
| `README.md` | 185 | features, requirements, install (Arch, NixOS), starting, tablet mode, the full PAM setup, Google Calendar, a development pointer | too long (rule 6); a WIP banner (:3); a machine model (:112); a wrong test command (:182) |
| `docs/FEATURES.md` | 543 | every widget, panel, HUD, notifications (toasts, moving and pinning, progress), dictation, wallpaper, lock, network settings, polkit, settings, dependencies | mostly current (the notification flow is in, :120–220); history at :344; a false claim at :468 |
| `docs/ARCHITECTURE.md` | 1683 | runtime, layers, I/O idiom, VPN providers, config, bar, popup, Repeater crash, shaders, widget contract, hardware, promises, notifications (:382–460), lock (:461–606), **modules (:607–1327, 720 lines)**, logging, conventions, adding a widget, testing (:1390–1683, with NixOS/Arch subsections) | the Modules section is today's API reference and author guide in one; stale spots below |
| `api/Api.qml` header | ~300 of 1243 | the module API reference as comments (`CLAUDE.md`: "the reference in `api/Api.qml`") | current by rule (every API change edits it) |
| `CHANGELOG.md` | 1420 | Unreleased is ~1160 lines; its "Module API" part (:17–421) is the API's history | history by nature; the release after step 8 cuts it |
| `tests/lock/README.md` | 636 | the lock test bed, the test tree | developer; not re-read for this plan |
| `site/` | 54 | GitHub Pages: home, OAuth privacy policy | keep |
| `CLAUDE.md` | 225 | the agents' guide; links into `notes/` on purpose | not documentation; outside these rules |

**Done since the first version:** working documents moved to `notes/` (tracker, done,
cleanup, decisions, plans, reviews, upstream); `STYLES.md` → `notes/plans/styles.md`; the
pttd protocol → `notes/pttd-protocol.md`; `docs/` and `README.md` hold no link into `notes/`
(a grep finds none); the test chapter has NixOS/Arch subsections; the `Promises.await` claim
is gone (`ARCHITECTURE.md:374–380` is right now). The first version's questions on language,
tracker, the place of working documents, the stylesheet spec, the pttd protocol and "release
first" are settled by the decisions or by what was done.

### Stale or false today

| Where | Says | The code |
|---|---|---|
| `README.md:3` | "THIS IS ALL WORK IN PROGRESS. README AS WELL" | rule 6 |
| `README.md:112` | "`gpio-keys` on the Framework 12" | rule 3 |
| `README.md:182` | "`quickshell -p tests.qml` runs the test suites" | `tests/run-unit.sh`, `tests/run-all.sh` (`CLAUDE.md` "Running") |
| `FEATURES.md:344` | "(Escape at a showing prompt unlocked until 2026-11-15.)" | rule 5 |
| `FEATURES.md:468` | the settings window has "Two tabs" | three: `behaviour`, `appearance`, `system` (`panels/SettingsWindow.qml`, the `tab:` fields) |
| `ARCHITECTURE.md:8` | Quickshell at `quickshell.outfoxxed.me` | the README uses `quickshell.org` |
| `ARCHITECTURE.md:611` | "What exists: the rules, the host, discovery, …" | rule 5 |
| `ARCHITECTURE.md:1340–1345` | `Logger { … enabled: Config.stt.debug }`; switches `Config.general.debug` … | settings `general.debug`, `general.fetchDebug`, `gcal.debug`, `stt.debug`, read with `Profiles.value` (`singletons/Stt.qml`, `SettingsSchema.qml`) |
| `ARCHITECTURE.md:1350` | "~37 places still do" (literal colours) | not re-counted; a backlog count does not belong in a reference |
| `ARCHITECTURE.md:1387` | settings pages "still wired by hand" | the `SettingsWindow.corePages` table |
| `ARCHITECTURE.md`, Modules | "(API 1.13)", "(1.28: no `marks` any more)" | rule 5 outside the reference |

### Missing

- **For users:** an install page per system (today in the README); a settings reference
  (every key); an IPC reference (13 `IpcHandler`s outside `tests/`); troubleshooting
  (logs, a locked screen that will not unlock, safe mode); a page on modules (what one is,
  the trust statement, Settings → Modules — the last two come with step 8).
- **For module authors (step 13):** the author guide, the API reference, a module
  template, how to run a module's suites without a checkout of the shell, the public
  versioning rule. Today it is the 720-line Modules section and the `api/Api.qml` header,
  or nothing (template, tests outside a checkout).
- **For developers:** the conventions as one page (today copied between `CLAUDE.md` and
  `ARCHITECTURE.md:1347`); releasing (version, changelog, tags, the module API's rules).

## 3. Target structure

One topic per file; the README links to all. Three folders, by reader (question 3).

```
README.md                    what it is, a screenshot placeholder, quick start (NixOS, Arch), link table  ~70
docs/
  install.md                 NixOS (flake, module options) | Arch (install.sh, by hand); Hyprland
                             autostart, allow_session_lock_restore, updating, removing                   ~120
  requirements.md            tool, what for, optional; Arch package | NixOS source                        ~60
  using.md                   first run, the settings window, profiles and conditions, tablet mode         ~120
  settings-reference.md      every core key: type, default, page, global or per profile                   ~250
  bar.md, notifications.md, lock-screen.md, polkit.md, network.md, themes.md, wallpaper.md,
  calendar.md, media.md, dictation.md                                                          ~40–200 each
  modules.md                 what a module is, the trust statement, Settings → Modules, safe mode          ~80
  ipc.md                     every target and function, with examples                                    ~120
  troubleshooting.md         logs, restart, unlocking from a console, safe mode, the supervisor's limit   ~100
  dev/
    architecture.md          runtime, directory map, layers, rules/driver pattern, config, popup, I/O     ~250
    conventions.md           the one copy of the conventions and development rules                       ~120
    widgets.md               writing a bar widget                                                        ~120
    lock-screen.md, network.md, notifications.md     internals per area                           ~120–180 each
    testing.md               the runners, the general and system sets, the lock bed, the test tree       ~200
    releasing.md             version, changelog, tags, the module API's version rules, the checklist     ~60
  modules/                   for module authors (step 13)
    guide.md                 a module from nothing to loaded: layout, manifest, lifetime, settings,
                             places (anchors), elements and tokens, commands, privileged runs, tests     ~250
    api-reference.md         Api, the handle, ModuleStore, CommandRunner/Query/Action,
                             PrivilegedAction, facts, notifications and progress, file chooser,
                             exports and uses                                                            ~400
    anchors.md               the anchors and placements (the test-pinned list)                            ~150
    elements.md              public elements, button kinds, pill sizes, theme tokens (pinned names)       ~150
    versioning.md            what a minor and a major may change, deprecations, the floor                 ~60
```

`themes.md` describes today's theme files and pages; the selectors are shelved (tracker
11.6), so nothing waits for a stylesheet format.

**The API reference and `api/Api.qml`.** Two hand-written references of one API drift.
`docs/modules/api-reference.md` becomes the reference; the header of `api/Api.qml` shrinks to
a pointer and a member list, and `CLAUDE.md`'s rule changes to "the reference in
`docs/modules/api-reference.md`" (question 4). This edits a code file and `CLAUDE.md`, so it
is the reference slice's last commit, reviewed with it.

**The module template** is a directory in the repository (`templates/module/`): a manifest,
a main, a widget, a settings page, one suite, a `run.sh` that runs the suite against an
installed shell. A unit case (`tests/run-modules.sh` on the template) keeps it loading.
Running a module's suites without a checkout needs the shell to ship its test runner; that is
step 13's own work, which this plan only documents.

## 4. Sources of truth

Each list a document repeats already exists in code or is pinned by a test:

| Document | Source |
|---|---|
| `settings-reference.md` | `SettingsSchema.entries` with no module loaded |
| `using.md` page ids | `SettingsWindow.corePages` (`ipc call settings openPage <id>` takes them) |
| `bar.md` widgets | `WidgetRegistry.coreEntries` |
| `modules/anchors.md` | `ModuleRules.anchorTable` (pinned by `tests/AnchorsTest.qml`) |
| `modules/elements.md` tokens | `api/ThemeTokens.qml` (pinned by `tests/ApiThemeTokensTest.qml`) |
| `modules/api-reference.md` | public members of `api/*.qml` (no leading `_`); manifest fields in `ModuleManifestRules` |
| `ipc.md` | `IpcHandler` blocks outside `tests/` |
| `install.md` | `options.programs.h2s-shell` in `nix/module.nix`; `install.sh`; `scripts/launch.sh`'s flags |

## 5. Checks

Two kinds, run at two times (the decision: consistency at each major release, not on every
change).

- **Rules lint, with every change** (`tests/docs-check.sh --rules`, in `tests/run-all.sh
  --quick`, a second or two): relative links resolve; no link from `README.md` or `docs/`
  into `notes/`; no home path, user name or machine model (a short word list); no history
  words (`since`, `no longer`, `until 20`, plan codes outside code blocks). A lint, not
  proof; review reads for the rest. These are rules, not consistency (question 1).
- **Consistency, at a major release** (`tests/docs-check.sh --release` plus a QML suite
  `tests/DocsTest.qml`, outside `run-all.sh`; the release checklist in `dev/releasing.md`
  names them): every list of §4 against its source, both ways. A failure is fixed before the
  release is tagged.

## 6. Dependencies

| Pages | Wait for | Why |
|---|---|---|
| `modules.md`, the trust statement | step 8 (modules closed for now) | Settings → Modules and the safe-mode banner change what users do |
| `lock-screen.md`, `troubleshooting.md` (supervisor) | step 9 (lock) | the 3-restart limit and what the user is told |
| `lock-screen.md`, `polkit.md` (PAM parts) | step 11 (PAM from the shell) | the PAM setup moves out of hand-edits |
| `docs/modules/*` | the API's closing slice Z, and step 13's template and test runner | Z removes the legacy paths; the guide must not teach them |
| `dev/architecture.md`, `dev/lock-screen.md`, `dev/network.md`, `dev/notifications.md` | the clean-up slices of that area (`architecture-cleanup.md`) | file names |
| `install.md`, `requirements.md`, `using.md`, `settings-reference.md`, `ipc.md`, `bar.md`, `notifications.md`, `network.md`, `themes.md`, `wallpaper.md`, `calendar.md`, `media.md`, `dictation.md`, `dev/testing.md`, `dev/conventions.md` | nothing | settled behaviour |

Step 14 (dividing built-in features into modules) moves pages later: a feature that becomes
a module takes its user page with it (a shipped module's page stays in `docs/`, under its
feature's name).

## 7. Order of work

Each slice is written by one agent and fact-checked by a second that did not write it: every
claim gets the file:line that backs it, or is marked unbacked. The owner reads for voice.
No slice touches a view; they wait only on the steps of §6. Sizes: S < 150 lines of docs,
M 150–400, L > 400.

| # | Slice | Size | Can start |
|---|---|---|---|
| D0 | Fix the stale statements of §2 in place (README, FEATURES, ARCHITECTURE); no restructuring | S | now |
| D1 | `tests/docs-check.sh --rules` in `run-all.sh --quick`; passes on today's files after D0 | S | after D0 |
| D2 | README cut to the front door; `install.md` (NixOS/Arch), `requirements.md`, `using.md` | M | when step 12 starts |
| D3 | `settings-reference.md`, `ipc.md`, `bar.md` | M | when step 12 starts |
| D4 | `notifications.md`, `network.md`, `themes.md`, `wallpaper.md`, `calendar.md`, `media.md`, `dictation.md` (out of FEATURES) | M | when step 12 starts |
| D5 | `dev/conventions.md` (one copy; `CLAUDE.md` points to it), `dev/testing.md` (out of ARCHITECTURE "Testing" and `tests/lock/README.md`) | M | when step 12 starts |
| D6 | `modules.md` with the trust statement | S | after step 8 |
| D7 | `lock-screen.md`, `polkit.md`, `troubleshooting.md` | M | after step 9 (PAM parts after step 11) |
| D8 | `dev/architecture.md`, `dev/widgets.md`, `dev/lock-screen.md`, `dev/network.md`, `dev/notifications.md`; the widget page walked through by an agent writing a throw-away widget in a test tree | L | area by area, after its clean-up slices |
| D9 | `docs/modules/versioning.md`, `elements.md`, `anchors.md` | M | after Z |
| D10 | `docs/modules/api-reference.md`; `api/Api.qml`'s header to a pointer; `CLAUDE.md`'s rule | L | after Z |
| D11 | `docs/modules/guide.md` and the template with its loading case | L | after D10, with step 13 |
| D12 | `tests/docs-check.sh --release`, `tests/DocsTest.qml`, `dev/releasing.md` with the checklist | S | after D3 and D10 |
| D13 | `FEATURES.md` and `ARCHITECTURE.md` deleted once every part has a new home; final lint | S | last |

Old documents stay until the slice that replaces their content is done. D0 and D1 are small
and independent: they can run any night. D2–D5 come with step 12, which the tracker puts
after step 8 and the release.

## 8. Open questions for the owner

1. The decision says documents are checked for consistency at each major release, not on
   every change. Should the rules lint of §5 (no link into `notes/`, no developer paths, no
   history words, links that resolve) still run with every change in `tests/run-all.sh
   --quick`, as this plan proposes, or only at a major release too?
2. Should the module API reference mark each member with the API version that added it (one
   "API" column, so an author knows what to put in the manifest's `api`), even though every
   other page keeps version history out?
3. Is the split into three folders right — user pages in `docs/`, developer pages in
   `docs/dev/`, module-author pages in `docs/modules/` — or would you rather have one flat
   `docs/`, as the Tailscale module has?
4. Should the module reference move from the comments of `api/Api.qml` into
   `docs/modules/api-reference.md`, leaving only a member list in the code, so that there is
   one reference instead of two that can drift apart?
