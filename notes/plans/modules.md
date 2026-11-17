# Modules: integrations as separate packages

Written 2026-11-15. M0, M1 and M2 are implemented (the test bed, the rules, the host,
discovery and safe mode; the module API 1.0, the registries and slots — §3, §3a and §5 say
what was built); the rest is a plan. The first module is Tailscale ([tailscale.md](tailscale.md)); dictation (TODO
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
  `H2S_SHELL_MODULES` — colon-separated canonical (`cd -P`) directories holding a
  `module.json`, each once — searching, in this order: the entries of
  `H2S_SHELL_MODULE_PATH` (a developer's checkouts: each a module directory or a directory of
  modules), `${XDG_DATA_HOME:-~/.local/share}/h2s-shell/modules/*`, then each data dir's
  `h2s-shell/modules/*` — the data dirs are `H2S_SHELL_MODULE_DATA_DIRS` if set (empty: none;
  the lock test bed's default), else `$XDG_DATA_DIRS`. Input and output are separate
  variables: `H2S_SHELL_MODULE_PATH` is only read, `H2S_SHELL_MODULES` only written (the shell
  and all it starts inherit it; a `--restart` from there ignores it, so an updated module's
  old path or a removed module is not kept). Before every start of the shell, so a restart
  picks up what was installed since; in a process of its own under a hard 3 s bound (a hung
  mount must not keep a crashed lock screen from coming back): late or failed, the shell
  starts without modules, logged. At most 200 modules and 64 KiB (beyond ~128 KiB the
  shell's execve would fail); the rest is dropped, logged. The shell takes the first module
  of an id and reports the later ones (`duplicate`).
- **NixOS**: `programs.h2s-shell.modules = [ pkg ];` re-wraps the launcher with the
  modules' paths; a module flake also exports a NixOS module for its system side.
  The API version is checked at evaluation.
- **API**: modules import `qs.api` and `qs.components` — the surface is §3a ("Module API
  1.0", built in M2). The API has its own `major.minor` (`Api.version`, kept in
  `ModuleRules.apiVersion` so the host never imports `qs.api`), separate from the shell's
  version, with its own CHANGELOG heading ("Module API"); a module's `api` is compatible
  when the major is the same and the shell's minor is not below the one asked.
- **Enable/disable**: global, in Settings → Modules, which also lists version, API
  status, load errors and missing tools (M4). Built: `Config.disabledModules` (ids; a module
  is on unless listed), `ModuleHost.setEnabled(id, on)` and, since M2, `qs ipc call modules
  setEnabled <id> <bool>` (the lock test bed uses it; Settings → Modules will call the same);
  turning one off destroys its main, drops its contributions and facts and turns its
  handle's `active` off; on again re-creates them.

### The manifest, as built (M1–M2; `singletons/ModuleRules.qml` is the reference)

| Field | | Rule |
|---|---|---|
| `id` | required | `^[a-z][a-z0-9_-]{0,31}$`, not a reserved id (the core's namespaces: every setting and fact prefix, `mod`, `core`, `api`, `qs`, …; a test keeps the list complete) |
| `name` | required | non-empty text, ≤ 100 |
| `version` | required | `^[0-9A-Za-z][0-9A-Za-z.+~-]{0,63}$` (semver recommended) |
| `api` | required | `"major.minor"` |
| `description` | optional | text ≤ 1000 (else a warning) |
| `main` | optional | a `.qml` file of the module, created while it is enabled; a bad path fails the module |
| `widgets` | optional | `[{ type, name, widget, popup?, popupPanel?, settings?, multiple?, presetDefaults? }]` (WidgetRegistry's fields); `type`, `popup`: `<id>` or `<id>.<name>`; `presetDefaults` (API 1.0): `{ key: plain JSON }`, ≤ 50 keys, 16 KiB — WidgetPresets' defaults for the type |
| `settingsPages` | optional | `[{ id, label, component, tab?, parent? }]`; `id`: `<id>` or `<id>.<name>`; `tab`: behaviour (default) / appearance / system; `parent`: a core page group (its tab wins) or `modules`; another parent: shown under Modules, with a warning in the log |
| `settings` | optional | `[{ key, label, type, default, group?, global?, hint?, suffix?, min?, max?, options? }]` (SettingsSchema's fields); `key`: `mod.<id>.<name>`; `type`: bool, number, slider, interval, enum, string, stringList; the default must fit; `group` defaults to `mod.<id>` |
| `facts` | optional | `[{ fact, label, type, options? }]` (ProfileRules.factTypes' fields); `fact`: `<id>.<name>`; `type`: bool, number, percent, string, enum |
| `slots` | optional | `[{ slot, component }]`; `slot` a dotted name, one of the slot table (§3a; another: a warning, shown nowhere) |
| `requires.programs` | optional | program names looked up on PATH |
| `setupHints` | optional | texts, shown while a program is missing |
| `tests` | optional | `.qml` suites (`tests/run-modules.sh`); an asynchronous one has `timeLimitMs` (20 s default, at most 60 s) — set it from `Component.onCompleted` when `"timeLimitMs" in suite`, so the suite still compiles on a shell without it |

Files are relative paths inside the module's directory (no `..`, no leading `/`, `.qml`), and
(M2, enforced before any is read or loaded) each must resolve, symlinks followed, to a
regular file inside the module's canonical directory of at most 1 MiB — the files the
manifest names (main, components, tests) and those its `qmldir` lists. A required field
missing or malformed, a bad `main` or a bad `qmldir` file: the module fails. A bad entry in a
list (outside the namespace, a default of the wrong type, a path outside the directory or
failing the file check, listed twice): that entry is dropped with an error, the module still
loads. Unknown top-level fields are kept (`raw`) and reported as warnings; unknown fields in
an entry are dropped with a warning (nothing would read them). At most 256 KiB, 200 entries
per list. A module's IPC targets are `<id>` or `<id>.<name>` (convention: the core's
targets are reserved ids, which a suite derives from the tree).

### The host and the status model, as built (M1–M2)

`singletons/ModuleHost.qml` (an instance per host; the shell's is in the `Modules`
singleton, fed from the environment; `shell.qml` touches it first). It reads no module file on
the GUI thread before its check (since the M2 review): `module.json` and `qmldir` (≤ 256 KiB),
then the text of every file the module names, come out of the file check — one process at a
time, `ModuleRules.fileCheckScript`: resolved inside the directory, regular, ≤ 1 MiB, the text
printed with its "ok" after it, so a text cut short by the deadline is never taken. Missing or
unreadable module.json: the module fails with the reason; entries failing the check dropped, a
failing main or qmldir file fails the module. With the texts it parses the manifest, checks
the imports (and reads the properties the root objects declare), counts the start (the start guard),
looks the required programs up on PATH (one process), waits for the config (which modules
are off), then creates each `main` by `file://` URL with its handle as `module`. Each check
has a 5 s deadline (`checkTimeoutMs`): what it did not answer counts as failed (a program as
missing, with the reason), so nothing stays `pending` for good. Each module's status
(`ModuleRules.statusOf`): `id, name, version, api, description, directory, state, enabled,
errors, warnings, missingPrograms, setupHints, shadowedBy`; `state` is one of `loaded`,
`disabled`, `failed`, `incompatible`, `missing-program`, `duplicate`, `pending`,
`safe-mode`; run-time failures (a slot contribution or a page that did not build) are added
to `errors` and the module stays loaded. The merged contributions of the loaded modules
(`widgetEntries`, `settingsPages`, `settingEntries`, `factTypes`, `slotContributions(name)`,
`factValues`) are ordered by module id, then manifest order, with absolute `file://` URLs,
and are reassigned only when they change. `qs ipc call modules list` prints all of it as JSON,
with `safeModeReason` (which counter put the shell in safe mode) and `startGuard`.

A mount that answers `stat` and then blocks on read leaves a module `pending` for at most the
deadline, then `failed` ("module.json cannot be read: could not be checked within 5 s"; one
check process serves all modules, so the others in that run fail with it); the shell — the
lock screen with it — never waits for it (below). The one read left on the GUI thread is
`Qt.createComponent` of a module's files when they are loaded: only after the check has read
each of them once, as regular files inside the module; a file that starts blocking between
the two is not contained. Entering safe mode (either counter) sends one notification,
"Started without modules: <reason>" (Notifier; not under the test runners); no banner yet.

**What is known at the first frame** (since the M2 review). Nothing of the modules, by design.
The core's registries — Profiles' facts, ProfileRules' fact types, SettingsSchema's entries,
WidgetRegistry's entries — read `ModuleLists`: plain values, no host, no I/O, which the
`Modules` singleton feeds from its host as modules settle (`ModuleLists.settled` once nothing
is pending). So nothing on the lock screen's path — `Lockscreen` → `Profiles.value` →
`SettingsSchema.entries` (+ the popup-mode entries from `WidgetRegistry`) → `ModuleLists` —
constructs the host or waits for it, and `Modules.load()` itself only starts processes.
Before the modules answer there is no module widget, page, slot or setting, and a module's
facts are absent: a profile condition on an absent module fact holds neither way
(`ProfileRules.evaluate`, three-valued — unknown, and `not` of unknown stays unknown — so
`not tailscale.connected` no longer switches a profile on, and the power profile with it, at
every start; a core fact not known stays two-valued, on purpose, as before; the condition
editor names an undeclared fact "<name> (module not installed)"). The bar comes up, then the
modules' widgets join it. The lock-bed test `modules-hung` locks and unlocks while a module's
files hang.

The start guard (M2): Quickshell relaunches a crashed shell in place (execve, same pid)
unless it crashed within 10 s of starting, so the launcher — which sees processes — misses a
module that crashes the shell later, and `launch.sh -d` has no supervisor. Before loading any
module the host runs `ModuleRules.startGuardScript` on `$XDG_RUNTIME_DIR/h2s-shell-module-starts`
(a plain file only; garbage counts as nothing), which holds `<pid>:<crash> <count>` — `crash`
the coredump pid Quickshell's handler put in the relaunch's environment
(`__QUICKSHELL_CRASH_DUMP_PID`, still in `/proc/<pid>/environ` after Quickshell unsets it).
A fresh process counts 0 (a launch, a `--restart`, a launcher restart: the launcher's to
count); a relaunch of the same pid after another crash counts one more; a reload of the same
relaunched process changes nothing. A start that lives 30 s — the launcher's quick-death
window, so the two counters tell one story; `H2S_SHELL_TEST_MODULE_GUARD_MS` shortens it —
writes its count back to 0. Two relaunches in a row: safe mode, `safeModeReason` says so (as
it says when the launcher asked). An orderly quit needs nothing — and could do nothing:
Quickshell stops all JavaScript before it tears a generation down (read in its source: `qs
kill` → `EngineGeneration::quit` → the engine interrupted), so neither
`Component.onDestruction` nor `aboutToQuit` runs a handler then. Not under the test runners
(`Config.readOnly`); a host's `guardFile` and `guardIdentity` are the suites' seams.

What the guard contains: a file that does not compile or imports something missing, a main
that cannot be created (`failed`, with the error), a file that is a link out of the module,
a FIFO or too large (never opened). What it cannot even see: an exception in a module's
signal handler (`Component.onCompleted` included) or binding — the engine prints it and
carries on; anything a module's singletons do later (the contract below); a module that
blocks the event loop or crashes the process (safe mode, §4 item 5). A module's singletons
outlive its main: turning it off destroys the main, not them.

## 3a. Module API 1.3 (1.0 built in M2; 1.1 adds the VPN slots; 1.2 the M2-review fixes; 1.3 `Api.networks`, `Api.vpnsUp` and widget presets)

The module author's whole world: `import qs.api` and `import qs.components` (the VPN
provider base type, `components/VpnProvider.qml`, since 1.1). Everything
below is API 1.0 unless marked 1.1, 1.2 or 1.3; adding anything is a minor bump, changing or removing anything a major
one (`ModuleRules.apiVersion`, the CHANGELOG's "Module API" heading). The doc comments in
`api/*.qml`, `components/ModuleSlot.qml` and `ModuleRules.slotTable` are the specification.

**How a module's file gets its handle.** The host gives the module's `main`, and the core
every object it builds from the manifest — bar widgets, popup panels, widget settings panes,
settings pages, slot contributions — the module's handle as the initial property `module`,
set before `Component.onCompleted`, when the file's root object declares it
(`property var module` — exactly: since 1.2 `property int module` or a readonly one gets nothing and
a warning in the module's status; the core reads what the root declares from the text the host
already read — a pragmatic reader that skips comments, strings and regex literals where one can
start — so a Loader is never handed a property it would warn about). Anything else — a
singleton, an object the module makes itself — calls `Api.moduleAt(Qt.resolvedUrl("."))`:
the handle of the module whose directory holds the file. A module's own assets:
`Qt.resolvedUrl("icons/x.svg")` or `module.url("icons/x.svg")`.

| `Api.` | Signature | What it does |
|---|---|---|
| `version` | string | "1.3" |
| `theme` | ThemeTokens | the theme's tokens, read-only, following the theme in use: colours (`accent`, `textPrimary`, … the core's semantic ones), `fontFamily`, `fontSize*`, `fontScale`, frozen groups (`capsule`, `popup`, `row`, `listItem`, `button`, `iconButton`, `pill`, `field`, `checkbox`, `tooltip`, `border`, `settings`), `reduceMotion`, `animationSpeed`, `scaled(w)`, `popupWidth(name, base)`, `duration(role)`, `curve(name)` |
| `slots` | [{ name, where, context, since }] | the slot table (frozen) |
| `module(id)` | → handle or null | a module's handle |
| `moduleAt(url)` | → handle or null | the handle of the module whose directory holds `url` |
| `notify(summary, options)` | | a notification (Notifier's options: body, urgency, icon, expireTime, actions, …) |
| `openUrl(url, options)` | → bool | `xdg-open` (an argv, no shell) — only a link with a scheme, and only `http:`, `https:`, `mailto:`; `file:` (and nothing else) with `{ allowFile: true }`; anything else (no scheme, a bare path, a `.desktop` file, another scheme, "-…", control characters, > 4096) refused and logged → false (`ModuleRules.openUrlProblem`; 1.2 — before, almost anything was passed on) |
| `copy(text)` | | the clipboard |
| `openSettings(pageId)` | | the settings window on a page (a core one's id or a module's) |
| `networks` | [{ id, name, kind, active }] | (1.3) the saved networks this computer joins, frozen, read-only: `id` the NetworkManager profile UUID (the key `system.vpnWithNetworks` uses), `name` the profile's name, `kind` "wifi" or "ethernet", `active` true when the profile is "activated". No hotspots, VPNs, bridges, bonds or their ports. Those active first, then the rest, each in NetworkProfiles' order; empty until the profiles are first read. A new array only when its content changes (`ModuleRules.apiNetworks`) |
| `vpnsUp` | [{ name, type, provider }] | (1.3) the VPNs up now ("activated"), frozen, read-only: `type` "wireguard", "vpn"… or "provider", `provider` a provider's `providerId`, else "". A new array only when its content changes (`ModuleRules.apiVpnsUp`). Both show every installed module the saved network names and the VPN names (modules are trusted, in-process) |

| handle (`module.`) | Signature | What it does |
|---|---|---|
| `moduleId`, `name`, `version`, `directory` | strings | who it is (QML reserves `id`) |
| `status` | object | its status, as `modules list` has it |
| `active` | bool | true while enabled and loaded — what acts follows it |
| `resumed()` | signal | (1.2) the machine woke from sleep; told only while active. Source: logind's PrepareForSleep(false), which the lock screen follows anyway, reported to the neutral `SystemSleep` singleton (it knows neither the lock nor modules); the host forwards it to the active handles |
| `manifest` | object | the checked manifest, frozen |
| `url(relative)` | → string | a file of the module as a URL |
| `settingKey(key)` | → string | "greeting" → "mod.<id>.greeting"; "" when not its own |
| `value(key)` | → value | its own setting as the profiles in effect have it (`Profiles.value`); undefined for any other key |
| `setValue(key, value)` | → "" or why not | writes its own setting the way the shell writes from outside a settings page (`Profiles.writeInEffect`: pinned global, else the profile it comes from, else Full), checked against its declaration |
| `setFact(name, value)` | → "" or why not | one of its declared facts ("ready" or "<id>.ready"), checked against its type (null: not known); only while active; pushed into `Profiles.facts` (through `ModuleLists`). Facts are for slow-changing state: each change re-resolves the profiles and every setting binding — set one when its value changes; the same value again is a no-op (1.2) |
| `facts` | object | its facts as the profiles see them |
| `store` | ModuleStore | `data`, `ready`, `get(key, fallback)`, `set(key, value)` → bool, `remove(key)`, `flush()` — a JSON object in `~/.config/h2s_shell/modules/<id>.json`. (1.2) The directory is made 700 (and a parent it has to make) by the host before any module loads; each write is synchronous and atomic, the file then 600; written a second after the last change, at `flush()`, and when the store is destroyed (module off, reload — a quit runs no JavaScript); read by a process, size-capped: a file > 1 MiB is refused, the store stays empty and is not written that session (`refusedReason`, the module's status); sets before `ready` are kept over what is read; never written while `Config.readOnly`; two shells: last writer wins |
| `notify(summary, options)` | | a notification under the module's name |
| `openSettings(page)` | | its page: "" → "<id>", "x" → "<id>.x" |
| `presetValue(type, preset, key)` | → value | (1.3) a key of a preset of one of its own widget types (WidgetPresets); the manifest's `presetDefaults` when the preset does not set it or `preset` is ""; undefined for a type not its own. Its bar widget gets `preset`, its widget settings pane `presetName` |
| `setPresetValue(type, preset, key, value)` | → "" or why not | (1.3) writes that key of an existing preset (plain JSON, a name as key; undefined removes it, back to the default); never creates a preset; the preset after the write at most 50 keys and 16 KiB. The own-type rule (here and in `presetValue`) is a convention between cooperating modules, not a security boundary: modules run in the shell's process and could reach the library anyway |
| `reportError(text)` | | a run-time failure, shown in its status |

| Types | |
|---|---|
| `SettingEditor { key; editIndex? }` | the core's SchemaSettingEditor for one of its keys: the control for its type, where the value comes from, the global pin. `editIndex`: the profile edited — a Behaviour-tab page declares `property int editIndex` and passes it; the default is the profile a change from the shell lands in |
| `SectionTitle`, `Heading`, `Hint`, `DetailRow { label; value }`, `SwitchRow { label; hint; checked; need; toggled() }` | the settings window's building blocks (thin wrappers of `panels/settings/*`, which stay where they are) |
| `CommandAction` | `run(command, done, environment)` → done({ ok, code, lines, error }); one after another |
| `CommandQuery` | a `Process`: `command`, `request()`, `done(lines)` |
| `PrivilegedAction` | `run(command, what, done, environment)` through pkexec (`elevate`, a stand-in in suites) → done({ ok, code, dismissed (126: nothing shown), refused (127: `Authentication.reportDenied(what)`), notFound (1.2), lines, error }). (1.2) `command[0]` must be an absolute path to an executable regular file, checked before pkexec is asked: else `notFound`, a plain failure with its own message (never "not authorised" — pkexec exits 127 for a program it cannot run too). A command that itself exits 126 or 127 cannot be told from pkexec's own. Other failures notified "<what> failed" unless `notifyFailures: false` |
| `ThemeTokens`, `ModuleHandle`, `ModuleStore` | what `Api.theme`, a handle and its store are |

**Settings pages.** A page (manifest `settingsPages`) is a plain Item — a `ColumnLayout` —
laid out at the page's width and scrolled by the window by its `implicitHeight` (it must not
scroll itself), built in a guard (`ModuleContribution`), with `module` and, when it declares
it, `editIndex` kept current. (1.2) A page or slot contribution whose root declares `property bool shown`
gets it, kept current: true while it is on screen (where it sits visible, its window open) — read
expensive data only while shown (`ModuleContribution`; the VPN page frame too). Its place: under a core group (`parent`: `network`; the group's
tab wins), under the Modules group (System tab; `parent: "modules"` or a parent the core does
not have), or at the end of its tab.

**Slots** (`components/ModuleSlot.qml`): `ModuleSlot { name; context; orientation; spacing }`
in a core panel builds every loaded module's contribution to `name`, each in its own guard
(`ModuleContribution`: compiled first; one that fails shows nothing and is recorded in its
module's status), with `module` and `context` = `{ slot: name, …context }` passed again only
when it changes by value (`ModuleRules.sameContext`: plain data by value, Qt objects and
functions by identity), laid out in a column (or a row); zero-size and inert with none; a
ScriptModel keyed by module + file. `Modules.slotComponent(slot, id)` hands one module's
contribution out as a Component (the same guard, forwarding a `context` set on it) and
`Modules.slotUrl(slot, id)` its URL, for core places that take one per module.

| Slot | Where | Context (besides `slot`) | Since |
|---|---|---|---|
| `network.popup.sections` | the network popup, under the VPN, Ethernet and Wi-Fi sections, above the network list (whose height counts it) | `wifiEnabled`, `wifiConnected`, `ethernetConnected` | 1.0 |
| `notifications.popup.top` | the notifications popup, above the list | `count` | 1.0 |
| `settings.general.bottom` | Settings → Behaviour → General, at the end | `editIndex` (for SettingEditor) | 1.0 |
| `network.vpn.row` | under the row of each VPN of the module's provider in the network popup (`VpnManager.extrasFor`) | `vpnId`, `entryId`, `vpn`, `provider`, `otherVpnsUp` | 1.1 |
| `network.vpn.card` | on that VPN's card in Settings → System → Network → VPN, while open | the row's + `open` | 1.1 |
| `network.vpn.page` | a page over the VPN page, from the card's "Settings…", in the core's frame (Back, title, scrolling); given `module` when it declares it (`VpnManager.pageOf`). Only for a page that is not also a settings page: a provider whose page is in `settingsPages` names it as `VpnProvider.settingsPage` instead, and "Settings…" goes there (tailscale.md §3) | the row's + `close` | 1.1 |

The three VPN slots take one contribution per provider: the one of the module whose id is the
provider's `providerId` (the convention: `VpnProvider { providerId: module.moduleId }`); a
provider that is no module's keeps its own `rowExtras`, `cardExtras`, `pageUrl`.

**Never on the lock screen**: no slot, no module object, nothing of `Modules` in
`screensaver/`, `singletons/lock/`, `Lockscreen` or `pam/` — ever (§4 item 1;
`tests/ModuleRegistriesTest.qml` checks the tree).

**Lifetime: what turning a module off stops.** The host destroys the module's `main`; the
core destroys every widget, popup, page and slot contribution built from it (a popup open on
its panel closes; a bar entry of its type stays in the section, showing nothing). Its
singletons survive (QML cannot unload them). So, the contract: **everything that acts — an
IpcHandler, a Process, a Timer, a VPN provider, a registration anywhere — lives under the
main object, or binds to `module.active`** (a singleton's timer: `running: module.active`);
a singleton resets what it must on `activeChanged`. On again, a new main is made next to the
singletons' old state. A module's IPC targets are `<id>` or `<id>.<name>`. The `good` fixture
follows all of it, and `ModuleRegistriesTest` checks that nothing of it acts while it is off.

**The registries** (§1's table, as built): `WidgetRegistry.entries` = `coreEntries` + the
modules' (`moduleOf(type)`, `popupModule(content)`; `file://` URLs accepted);
`WidgetPresets.defaults` = `coreDefaults` + `presetDefaults`; `SettingsSchema.entries` =
`coreEntries` + `settingEntries` (popup-mode entries follow the registry; `coreDefaults` is
what a new config's Full spells out, so a module's defaults are never frozen into it);
`ProfileRules.factTypes` = `coreFactTypes` + the modules'; `Profiles.facts` = the modules'
`factValues` under the core's and the simulated ones; `SettingsWindow.pages` = `corePages`
merged (`ModuleRules.mergeSettingsPages`); `Popup` loads a module's panel by URL from the
registry (created from `Qt.callLater` like every panel); the panel warm-up in `shell.qml`
compiles modules' panels too; the bar section editor offers modules' types and names a type
that is gone "(not installed)". With no module, each is the core's list itself.

**The VPN slots (built, API 1.1)** (`VpnManager`, the VPN branch's one place): the three VPN
slots are ordinary slots — `extrasFor` asks `Modules.slotComponent(slot, providerId)` and
`pageOf` asks `Modules.slotUrl(slots.page, providerId)` first, falling back to the provider's
own `rowExtras` / `cardExtras` / `pageUrl` (the stand-in provider, any provider that is not a
module's) — with the convention that a module's provider's `providerId` is its module's id
(`VpnProvider { providerId: module.moduleId }`), and three rows in `ModuleRules.slotTable`.
The page frame (`VpnProviderPageFrame`) loads the page by URL with
`Modules.initialProperties`, so a page that declares `module` gets its handle like any other
file built from a manifest. VpnExtras needs no change: the Component forwards the `context`
it sets. `tests/ModuleRegistriesTest.qml` checks it with the `vpn-slots` fixture, and the other way — a provider whose page is its module's settings page (`settingsPage`, no page slot) — with the `vpn-page` fixture.

## 4. Safety

Enforced:
1. No extension point in `screensaver/`, `singletons/lock/`, `Lockscreen`, `pam/` (checked by
   `ModuleRegistriesTest` from the tree, following the components those files build, transitively:
   `tests/lock-closure.sh`, a pragmatic walk of instantiated type names through `import qs.…`
   lines — singletons used by name and Loader sources are not followed).
2. Settings keys forced into `mod.<id>.*`, facts into `<id>.*`: a module cannot touch
   `lockscreen.*` or any core key.
3. Facts arrive as checked plain values; a module cannot break `Profiles`.
4. Every module file is loaded dynamically inside a guard; errors land in a status.
5. After two quick crashes the launcher starts the shell without modules, with a banner.
   Built (M1, the banner not yet): `supervise` counts deaths within 30 s of starting, in a
   row; from two on, the next start gets `H2S_SHELL_SAFE_MODE=1` (logged), and the host
   reads the manifests but loads nothing (state `safe-mode`). A start that lives 30 s ends
   it — unless it then ends with status 255: the launcher sees the process, not Quickshell's
   in-place crash relaunch, and 255 is Quickshell giving up on a crash within 10 s of a
   (re)start, so it counts as quick. The variable is never inherited (a `--restart` from a safe-mode shell starts normally).
   The shell's own counter (M2, §3 "the start guard"): two of Quickshell's in-place relaunches
   after a crash in a row, neither living 30 s, put it in safe mode too — what the launcher
   cannot see (`launch.sh -d` included). `modules list` says which one (`safeModeReason`).
6. A lock-bed test: a broken and a busy module installed — the lock still locks and
   unlocks.
   Built (M1) with the broken fixtures (`tests/lock/tests/modules.sh`); a busy one is not
   there yet. A hung one (M2 review): `modules-hung` — every read of the module's
   files hangs (a stand-in `head` on the file check's PATH); the lock locks and unlocks while it
   is pending, and it is `failed` after the deadline.

Convention only (QML has no sandbox): a load-time check warns about a module whose files
import anything outside an allowlist (`QtQuick*`, `Quickshell`, `Quickshell.Io`,
`qs.api`, `qs.components`, its own directory) — a warning in its status, by the owner's
decision (§7), not a refusal. Built (M1): `QtQml*` is allowed too; the files checked are
those the manifest and the module's `qmldir` name; a quoted import is resolved from the
importing file (`tests/` importing ".." is the module's own); `qs.tests` is allowed only in
the manifest's `tests` (the running shell has no `qs.tests`). It guards against mistakes, not malice.

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
- **M2 — the API, the registries and slots.** Done: `qs.api` 1.0 (§3a: the facade, the
  handle injected as `module`, the per-module store, facts, the settings building blocks,
  command helpers with pkexec); WidgetRegistry, WidgetPresets, SettingsSchema, profile facts,
  settings pages, popups and the panel warm-up take modules' entries, reactively;
  `ModuleSlot` and three slots; `presetDefaults` in the manifest; the file check, the start
  guard, check deadlines and the `module.active` contract (from the M1 review);
  `modules setEnabled` over IPC. Fixtures `broken-slot` and `link-escape`; suites
  `ModuleRegistriesTest`, the `good` fixture's own (`GoodApiTest`), the lock-bed `modules`
  test with the `good` widget in the bar.
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
    modules pinned by the system flake; a module installed both ways: the Nix one wins
    (its paths go into the wrapper's `H2S_SHELL_MODULE_PATH`, searched before
    `~/.local/share/h2s-shell/modules`; set, not prefixed — the shell's environment, which a
    `--restart` from inside it inherits, carries the previous generation's value).
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
