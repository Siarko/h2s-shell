# Modules: integrations as separate packages

Written 2026-11-15. M0 and M1 are implemented (the test bed, the rules, the host,
discovery and safe mode in the launcher; §3 and §5 say what was built); the rest is a
plan. The first module is Tailscale ([tailscale.md](tailscale.md)); dictation (TODO
11.24) is the natural second.

"Verified" below means read in Quickshell 0.3.2's source or tried in a headless
Quickshell; "assumed" is marked.

## 1. What an integration has to plug into, and how that is wired today

| Area | Today | For modules |
|---|---|---|
| Bar widgets, popup panels, widget settings | `singletons/WidgetRegistry.qml`: one static list; everything is loaded by URL from it | the list becomes built-in + modules' entries; absolute URLs accepted |
| Widget presets | `singletons/WidgetPresets.qml`: a hard-coded map | merged with modules' defaults |
| Settings pages | `panels/SettingsWindow.qml`: a hand-written list with one static component per page | pages may carry a URL; modules add pages under existing groups |
| Settings schema | `singletons/SettingsSchema.qml`: one list (the popup-mode entries are already derived from the registry) | modules' entries appended, forced into `mod.<id>.*` |
| Profile facts | `singletons/ProfileRules.qml` `factTypes`, `Profiles.realFacts`: hard-coded | modules push facts as plain values, namespaced `<id>.*` |
| Config | `singletons/Config.qml`: a `JsonAdapter` that drops unknown keys | each module gets a file of its own |
| VPNs | `singletons/network/VpnManager.qml`: NetworkManager profiles only | a provider seam (tailscale.md §3) |
| Kill switch | `scripts/h2s-vpn-lockdown`, run as root | stays core; modules can only ask for what a checked option allows |
| IPC, notifications, privileged actions | per object (`IpcHandler`), `Notifier`, `pkexec` + the shell's polkit agent | usable as they are |
| Lock screen | hosts nothing foreign | must stay so: no extension point there, ever |

## 2. What Quickshell allows (verified)

- The `qs.` prefix is bound to the config directory; qmldir files are made only for
  directories the scanner reached from `shell.qml`. There is no plugin facility.
- A QML file outside the tree, loaded by a `file://` URL, can `import qs.…` and gets
  the SAME singletons as the core. With a `qmldir` of its own, the directory's
  `pragma Singleton` files are real singletons shared by its files.
- A syntax error in a file loaded that way is contained (`status Error`).
- A static `import` of a broken module makes the whole config fail to load: no bar and
  no lock screen. So modules are never imported statically.
- One directory reached through two path spellings gives two sets of singletons: paths
  are made canonical once (a repeated `/` and a symlink do it; `.` and `..` do not —
  Qt normalises those).
- Files loaded by URL are not watched: editing a module does not hot-reload.
- An `IpcHandler` in a dynamically created object works.
- Assumed: that `file://` files resolve `qs.*` is not a documented promise. A unit test
  pins it (`tests/QuickshellPinTest.qml`), to be re-run on every Quickshell upgrade.
- An exception thrown in a dynamically created object's `Component.onCompleted` is
  caught and printed by the engine: `createObject` returns the object, the caller cannot
  see the error.

## 3. The design

A module is a directory of QML with a manifest, found at start and loaded by URL; the
core's hard-coded lists become registries the manifest fills. I/O and logic sit in the
module's own singleton(s) with a pure `*Rules` part, as in the core.

```
h2s-shell-tailscale/              its own repository and flake
  module/                         → <prefix>/share/h2s-shell/modules/tailscale
    module.json                   id, name, version, api; widgets, settingsPages, settings,
                                  facts, requires.programs, setupHints, main, tests
    qmldir                        the module's singletons
    Main.qml                      created by the host at start: IPC, facts, VPN provider
    Tailscale.qml, TailscaleRules.qml, TailscalePanel.qml, TailscaleSettings.qml, …
    tests/                        suites, fixtures, stand-in tools
```

- **Discovery** (built, M1): `scripts/launch.sh` (`discover_modules`) builds
  `H2S_SHELL_MODULES` — colon-separated canonical (`pwd -P`) directories holding a
  `module.json`, each once — from the entries the variable held when the launcher started
  (each a module directory or a directory of modules), then
  `${XDG_DATA_HOME:-~/.local/share}/h2s-shell/modules/*`, then each
  `$XDG_DATA_DIRS/h2s-shell/modules/*`. Before every start of the shell, so a restart picks
  up what was installed since. An inherited list (a `--restart` run from inside the shell)
  does not reorder: entries the search finds again keep their search place. The shell takes
  the first module of an id and reports the later ones (`duplicate`).
- **NixOS**: `programs.h2s-shell.modules = [ pkg ];` re-wraps the launcher with the
  modules' paths; a module flake also exports a NixOS module for its system side.
  The API version is checked at evaluation.
- **API**: modules import `qs.api` (a facade: theme read-only, notify, setFact, own
  settings, a per-module store) and `qs.components`. The API has its own `major.minor`,
  separate from the shell's version, with its own CHANGELOG heading. Built so far (M1):
  only the version, `Api.version` in `api/Api.qml` ("1.0"); a module's `api` is
  compatible when the major is the same and the shell's minor is not below the one asked.
- **Enable/disable**: global, in Settings → Modules, which also lists version, API
  status, load errors and missing tools. Built (M1): `Config.disabledModules` (ids; a module
  is on unless listed), `ModuleHost.setEnabled(id, on)`; turning one off destroys its main
  and drops its contributions, on again re-creates them.

### The manifest, as built (M1; `singletons/ModuleRules.qml` is the reference)

| Field | | Rule |
|---|---|---|
| `id` | required | `^[a-z][a-z0-9_-]{0,31}$`, not a reserved id (the core's namespaces: every setting and fact prefix, `mod`, `core`, `api`, `qs`, …; a test keeps the list complete) |
| `name` | required | non-empty text, ≤ 100 |
| `version` | required | `^[0-9A-Za-z][0-9A-Za-z.+~-]{0,63}$` (semver recommended) |
| `api` | required | `"major.minor"` |
| `description` | optional | text ≤ 1000 (else a warning) |
| `main` | optional | a `.qml` file of the module, created while it is enabled; a bad path fails the module |
| `widgets` | optional | `[{ type, name, widget, popup?, popupPanel?, settings?, multiple? }]` (WidgetRegistry's fields); `type`, `popup`: `<id>` or `<id>.<name>` |
| `settingsPages` | optional | `[{ id, label, component, tab?, parent? }]`; `id`: `<id>` or `<id>.<name>`; `tab`: behaviour (default) / appearance / system; `parent`: a core page group |
| `settings` | optional | `[{ key, label, type, default, group?, global?, hint?, suffix?, min?, max?, options? }]` (SettingsSchema's fields); `key`: `mod.<id>.<name>`; `type`: bool, number, slider, interval, enum, string, stringList; the default must fit; `group` defaults to `mod.<id>` |
| `facts` | optional | `[{ fact, label, type, options? }]` (ProfileRules.factTypes' fields); `fact`: `<id>.<name>`; `type`: bool, number, percent, string, enum |
| `slots` | optional | `[{ slot, component }]`; `slot` a dotted name |
| `requires.programs` | optional | program names looked up on PATH |
| `setupHints` | optional | texts, shown while a program is missing |
| `tests` | optional | `.qml` suites (`tests/run-modules.sh`) |

Files are relative paths inside the module's directory (no `..`, no leading `/`, `.qml`).
A required field missing or malformed: the module fails. A bad entry in a list (outside the
namespace, a default of the wrong type, a path outside the directory, listed twice): that
entry is dropped with an error, the module still loads. Unknown fields (top level and in
entries) are kept (`raw`) and reported as warnings. At most 256 KiB, 200 entries per list.

### The host and the status model, as built (M1)

`singletons/ModuleHost.qml` (an instance per host; the shell's is in the `Modules`
singleton, fed from the environment; `shell.qml` touches it first). It reads each manifest
with a blocking `FileView` read (missing or unreadable: the module fails with FileView's
reason), checks it, reads the files the manifest and the module's `qmldir` name for the
import check, looks the required programs up on PATH (one process; the module is `pending`
until it answers), waits for the config (which modules are off), then creates each `main` by
`file://` URL. Each module's status (`ModuleRules.statusOf`): `id, name, version, api,
description, directory, state, enabled, errors, warnings, missingPrograms, setupHints,
shadowedBy`; `state` is one of `loaded`, `disabled`, `failed`, `incompatible`,
`missing-program`, `duplicate`, `pending`, `safe-mode`. The merged contributions of the
loaded modules (`widgetEntries`, `settingsPages`, `settingEntries`, `factTypes`,
`slotContributions(name)`) are ordered by module id, then manifest order, with absolute
`file://` URLs. `qs ipc call modules list` prints all of it as JSON (read-only).

What the guard contains: a file that does not compile or imports something missing, a main
that cannot be created (`failed`, with the error). What it cannot even see: an exception in
a module's signal handler (`Component.onCompleted` included) or binding — the engine prints
it and carries on; anything a module's singletons do later; a module that blocks the event
loop or crashes the process (safe mode, §4 item 5). A module's singletons outlive its main:
turning it off destroys the main, not them.

## 4. Safety

Enforced:
1. No extension point in `screensaver/`, `singletons/lock/`, `Lockscreen`.
2. Settings keys forced into `mod.<id>.*`, facts into `<id>.*`: a module cannot touch
   `lockscreen.*` or any core key.
3. Facts arrive as checked plain values; a module cannot break `Profiles`.
4. Every module file is loaded dynamically inside a guard; errors land in a status.
5. After two quick crashes the launcher starts the shell without modules, with a banner.
   Built (M1, the banner not yet): `supervise` counts deaths within 30 s of starting, in a
   row; from two on, the next start gets `H2S_SHELL_SAFE_MODE=1` (logged), and the host
   reads the manifests but loads nothing (state `safe-mode`). A start that lives 30 s ends
   it. The variable is never inherited (a `--restart` from a safe-mode shell starts normally).
6. A lock-bed test: a broken and a busy module installed — the lock still locks and
   unlocks.
   Built (M1) with the broken fixtures (`tests/lock/tests/modules.sh`); a busy one is not
   there yet.

Convention only (QML has no sandbox): a load-time check warns about a module whose files
import anything outside an allowlist (`QtQuick*`, `Quickshell`, `Quickshell.Io`,
`qs.api`, `qs.components`, its own directory) — a warning in its status, by the owner's
decision (§7), not a refusal. Built (M1): `QtQml*` is allowed too; the files checked are
those the manifest and the module's `qmldir` name. It guards against mistakes, not malice.

Not solvable in-process: a module that blocks the event loop freezes the shell, the
lock screen with it. The compositor keeps the session locked, but nobody can unlock
until the shell is killed from another console. The alternative — modules as separate
processes describing their UI over a protocol — isolates that, at the price of a
generic UI vocabulary in the core and much poorer module UI. Decision for the owner
(§6, question 1).

## 5. Stages

Each ends with tests green and one independent review; only what blocks goes back for
fixes, the rest to the backlog. Work happens on a branch in a worktree, committed per
stage; the unit suites and a module test runner are the gate.

- **M0 — test bed first.** Done: `tests/run-modules.sh <dir>…` (headless, sharing
  `tests/headless.sh` with `run-unit.sh`; the runner is `tests-modules.qml`), fixture
  modules in `tests/fixtures/modules` (`good`, `broken`, `broken-main`, `wrong-api`,
  `key-collision`, `bad-manifest`, `bad-manifest-fields`, `forbidden-import`,
  `duplicate-id` + `duplicate-id-2`, `needs-program`), and `tests/QuickshellPinTest.qml`
  pinning §2.
- **M1 — rules and host.** Done: `ModuleRules` (manifest, API compatibility, namespacing,
  the import check, precedence, states, merging) with its suite; `ModuleHost` and the
  `Modules` singleton (guarded loading, status, merged lists, enable/disable, the
  `modules` IPC) with `ModulesTest`; discovery and safe mode in `launch.sh`, with the
  lock-bed tests `modules` and `modules-launcher`.
- **M2 — the API and the registries.** `qs.api`; WidgetRegistry, WidgetPresets,
  SettingsSchema, facts, settings pages take modules' entries.
- **M3 — the VPN provider seam** in the core, with a lasting "needs attention" state
  (tailscale.md §3). Independent of M1–M2; can run beside them.
- **M4 — packaging and operation.** `withModules` and the NixOS option; Settings →
  Modules; safe mode; the lock-bed test; an author's guide in ARCHITECTURE.
- Later: move dictation out; a reload-on-edit for module development.

## 6. Questions for the owner (suggested answer after the arrow)

1. In-process QML modules, accepting that a module can freeze the shell and with it
   the lock screen (never unlock it)? → Yes, with the lint, safe mode and the lock-bed
   test.
2. Modules may import only `qs.api` and `qs.components`? → Yes.
3. A newly installed module is enabled by default? → Yes.
4. Module settings may vary per profile (`mod.<id>.*`)? → Yes; settings held by a
   system service (tailscaled's own) are not profile settings.
5. Tailscale in a separate repository from day one, run from a sibling checkout? → Yes.
6. Dictation as the second module? → Yes, after Tailscale.

## 7. Decisions (the owner's, 2026-11-15) — these override §4 and §6 where they differ

- **Trust**: whoever installs a module knows what they are doing. Modules run in the
  shell's process; isolation from the lock screen is not a design goal beyond what is
  free (no extension point there, namespaced settings). The import allowlist of §4
  becomes a warning in Settings → Modules, not a refusal; crash-loop safe mode stays
  (it is cheap and it is what gets a broken session back).
- **Declarative installation from a repository**: the user names a repository and the
  shell installs the module from it.
  - A global setting lists modules: `{ source, ref }` — `source` a git URL or
    `github:owner/repo[/subdir]`, `ref` a tag, branch or commit (default: the default
    branch). The same list can be edited in Settings → Modules ("Add a module": paste
    the link).
  - `h2s-shell modules sync` (run by the launcher at start when the list changed, and
    by the settings page) clones or fetches each into
    `~/.local/share/h2s-shell/modules/<id>` at the wanted commit, checks the manifest
    and the API version, and records what is installed (source, commit, time). Removed
    entries are uninstalled. No network at shell start unless the list changed;
    updating is explicit ("Check for updates", or a moving `ref`).
  - Needs `git` on PATH (already a runtime program). A failed fetch never blocks the
    shell: the module is simply absent, with the reason shown.
  - NixOS keeps its own declarative route as well (`programs.h2s-shell.modules`), for
    modules pinned by the system flake; a module installed both ways: the Nix one wins.
- **Signatures** (optional, later stage): a module's commit or tag may be signed (git's
  SSH or GPG signatures); the user keeps a list of trusted keys; Settings → Modules
  shows "signed by …" / "unsigned" / "signature does not match", and a setting can
  require signatures. Unsigned modules install with a notice, not a refusal.
- **Embedding into existing panels — yes, as named slots.** A module must be able to
  put content INTO panels the core owns, not only add its own widgets and pages: the
  VPN list's rows and cards are the first case (Tailscale's exit-node chooser under its
  row). The core declares slots — `ModuleSlot { name: "network.vpn.row"; context: … }`
  — at the places worth extending; a manifest lists `slots: [{ slot, component }]`;
  the slot instantiates each contribution with the context it documents, inside a
  guard. First slots: the VPN popup row extras, the VPN card extras, the network
  popup's sections, the network overview's lines, the settings pages' group lists.
  New slots are added as modules need them; each is part of the module API (minor
  version bump).
- Tailscale lives in a separate repository from the start; dictation later.

Stages are re-cut accordingly: M0 test bed; M1 rules + host + discovery; M2 API,
registries and slots; M3 the VPN provider seam; M4 install-from-repository
(`modules sync`, Settings → Modules); M5 NixOS packaging, safe mode, author's guide;
M6 signatures.

Settled while building M0–M1 (2026-11-15):
- Search order is explicit entries, then the data home, then the data dirs (first id
  wins). That puts a module installed from a repository (M4, into the data home) before
  one Nix installed (data dirs), the opposite of "the Nix one wins" above: M4/M5 must
  either reorder discovery or mark Nix-installed modules.
- The import allowlist is a warning (as decided), and also allows `QtQml*`.
- A module needs no `main`; a module's settings default to the group `mod.<id>`.
- The module API version lives in `api/Api.qml` (`qs.api`), the start of the facade.
