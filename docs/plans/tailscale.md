# Tailscale: a VPN with extras, as the first module

Written 2026-11-15. A plan; §3 (the core's provider seam, stage M3) is built and describes the code. Depends on [modules.md](modules.md).

"Observed" = seen on the owner's machine with read-only commands (tailscaled 1.104.4,
NixOS `services.tailscale.enable = true`); "source" = Tailscale's or nixpkgs' code or
docs; "assumed" is marked. Redacted fixtures and a stand-in CLI from the analysis are
to be moved into the module's repository (they are in the session scratch directory).

## 1. Facts

- The daemon's socket is world-connectable; any user may READ: `tailscale status
  --json`, `debug prefs` (keys zeroed), `exit-node list`, and the event stream.
- CHANGING anything needs root or the operator setting. This user is not the operator:
  every `set`/`up`/`down`, and even `switch --list`, is denied with a fixed message.
- `tailscale up` with ANY flag insists on repeating every non-default setting (this
  machine has one: accept-routes) or resets them. So: changes only through
  `tailscale set`; connect with bare `up`, log in with bare `login`.
- `status --json` is officially not a stable format; tolerate missing fields.
- Live changes: the LocalAPI's `watch-ipn-bus` over the unix socket prints one JSON
  object per line and needs only read access (source). Not a promised interface.
- NetworkManager shows `tailscale0` as an external `tun` device; its UUID is not a
  stable identity.
- DNS here: with MagicDNS on, `/etc/resolv.conf` holds only Tailscale's resolver.
- The shell's kill switch today lets traffic INTO `tailscale0` out, but drops
  tailscaled's own packets on the physical link: with blocking on, Tailscale cannot
  connect. tailscaled marks its sockets (`0x80000/0xff0000`; observed in the ip rules).

## 2. Scope

**Version 1**
- One entry "Tailscale · <tailnet>" among the VPNs: bar, popup row, overview, VPN page.
- States: connecting / connected (tailnet only, or via an exit node) / off, plus a
  lasting "needs attention" with its action: log in, waiting for approval, key
  expired, service not running, become operator. Health and key-expiry warnings.
- Connect, disconnect; log in (URL, open in browser, copy), log out.
- "Become operator" once (pkexec, answered by the shell's polkit agent; on NixOS the
  declarative line is shown too), with a plain warning of what an operator may do.
- Exit node: choose, none, the suggested one; "allow the local network".
- A Tailscale page: accept routes, accept DNS, shields up; the devices (online, direct
  or relayed, owner, OS, last seen, traffic; copy address or name).
- Live state from one long-running reader of the event stream, used as a trigger to
  re-read, with a slow fallback poll.
- Kill switch: the root script lets tailscaled's marked traffic out (core, §4); the
  page says what "blocked outside a VPN" means without an exit node.
- "Bring it up with this network" includes Tailscale.

**Version 2**: an exit node per network; Mullvad nodes grouped; accounts; hostname;
advertising routes or an exit node; the SSH server switch; Taildrop; ping and ssh from
a device row; diagnostics; a helper for DNS when two VPNs are up.

**Not planned**: serve/funnel, tailnet lock, cert, the web client, `tailscale update`
(the package is NixOS's), metrics, admin-console work.

## 3. The provider seam (core, stage M3 of modules.md) — the contract as built

Built 2026-11-15 on branch `vpn-providers`, revised after its review the same day (the
user's "VPN with a network" never pruned for a provider; who asked a connect; per-entry
status and busy; the provider in slot contexts; the page's frame). With no provider
registered the shell behaves exactly as before (the existing Network suite passes
unchanged; `VpnManager.vpns` is then the very list NetworkManager's profiles give). Code:
`components/VpnProvider.qml` (the base type; its comment is the short form of this
section), `singletons/network/VpnManager.qml` (registry, merged model, dispatch),
`NetworkRules.qml` (the pure parts), `panels/settings/VpnProviderPageFrame.qml` (the
page's frame), tests in `tests/VpnProvidersTest.qml` with the stand-in
`tests/FakeVpnProvider.qml` (and its page, `tests/FakeVpnProviderPage.qml`).

### The provider

A provider extends `VpnProvider` (`import qs.components` — one of the two imports a module
may use) and is declared inside the module's own objects. It registers itself with
`VpnManager` when made and unregisters when destroyed (a module disabled at run time).
`VpnManager.registerProvider(object) → bool` / `unregisterProvider(id, object)` exist for
an object of the same shape made otherwise.

| Member | Type | Who | Meaning |
|---|---|---|---|
| `providerId` | string, constant | core reads | `^[a-z][a-z0-9_-]{0,31}$`, no colon, not a prototype name. A second provider with a taken id is refused (`registered` false); a refused one going away never takes the registered one with it. |
| `kind` | string | informative | "vpn", "mesh"… |
| `typeName` | string | core reads | the VPN's type on its card, the editor's picker tooltip, the page's title (≤ 60 chars) |
| `glyph` | string | core reads | Nerd Font glyph for its rows; the bar's when only its VPNs are up |
| `entries` | list | core reads | see below |
| `ready` | bool (default false) | core reads | the entries have been read **successfully** at least once. Informative: the core deletes nothing on its word (see "VPN with a network") |
| `busy` | bool | core reads | an operation runs: the buttons of all its entries are disabled (as `NetworkProfiles.connecting` for NetworkManager's); one entry's: its `busy` |
| `canChange` | bool (default true) | core reads | false: changes need an administrator — its buttons carry `PrivilegedMark` ("auth") |
| `lockdownNote` | string | core reads | its own sentence for the kill switch note ("" the shell's) |
| `rowExtras` | Component or null | core instantiates | slot `network.vpn.row` |
| `cardExtras` | Component or null | core instantiates | slot `network.vpn.card` |
| `settingsPage` | string ("" none) | core reads | the id of the provider's own page among the settings window's pages — for a module the id its manifest's `settingsPages` declares (`<module id>` or `<module id>.<name>`, what `Api.openSettings` takes). The card's "Settings…" goes there (`Shell.openSettings`: the page list selects it) and no framed copy opens. An id the window does not have (wrong, or the page dropped) falls back to `pageUrl` / the page slot (below) |
| `pageUrl` | string | core loads | slot `network.vpn.page`, inside the core's frame (below) — only for a provider whose page has no entry in the settings window's list (no known `settingsPage`) |
| `connect(entryId, request)` | function | core calls | bring the entry up; `request` `{ origin }` (below) |
| `disconnect(entryId, request)` | function | core calls | take it down; `request` as for connect |
| `attend(entryId)` | function | core calls | perform the entry's attention action (log in, approve, start the service, become operator…) — always the user's doing (a button) |
| `failed(entryId, what, reason)` | signal | provider emits | an operation failed: the core shows the notification "<what> failed" with `reason` as its body — the route NetworkManager's failures take (NetworkRules.vpnFailureNotice). Not for a prompt the user dismissed (below). |
| `autoRegister`, `registered` | bool | — | registration on completion (default true); whether it was taken |

The core calls `connect`/`disconnect`/`attend` only with an id the provider currently
reports, inside a guard: a throw is logged and shown as a failure notification. Properties
are read through bindings — keep them properties and change them by assignment (a new
array for `entries`), so the views follow.

**Who asked — `request.origin`.** `connect` and `disconnect` get `{ origin: "user" |
"network" }` (a fresh object each call; the core sends nothing else, and `VpnManager.connect
(id, request)` takes anything other than "network" as "user"):

- `"user"` — a button in the popup or on the card: the provider may prompt for a password
  (pkexec) and may open a browser (log in).
- `"network"` — "VPN with a network": a network came up (connect) or went (disconnect),
  nobody is necessarily at the screen. The provider must **never prompt** and **never open
  a browser**. When it cannot go on without the user it sets the entry's `attention`
  (state back to ""), and the core holds the entry down — not retried until the networks
  change — exactly as for attention reached after being asked.
- `attend` has no request: it is always the user's.

**Cancelled is not failed.** A privileged prompt the user dismissed is not a failure:
`pkexec` exits **126** when the prompt was dismissed or the password refused — show
nothing, emit nothing, put the entry's state back to "" and clear `busy`. It exits **127**
when no authentication agent answered — emit `failed(entryId, what, "No authentication
agent answered.")`. (The core's own handling: `singletons/network/VpnLockdown.qml`
`_fail`, `singletons/Authentication.qml`.)

### Entries

`entries`: `[{ id, name, state, attention, detail, active, status, busy }]`, at most 64,
checked by `NetworkRules.vpnProviderEntries` (only own properties are read; a getter that
throws counts as missing). Dropped and logged (`VpnManager.providerProblems`, a warning
when it changes):

- an entry that is not an object; `id` not `^[A-Za-z0-9._~-]{1,64}$` or a prototype name
  (`__proto__`, `constructor`…), or repeated (the first wins); `name` not text; `state` not
  one of `"activating" | "activated" | "deactivating" | ""` (missing = "").

Reset to the default and logged: `attention` not null or `{ reason: non-empty text, action:
text }` → null; `detail` not an object → empty; `active` not a bool → `state !== ""`;
`status` not text → ""; `busy` not a bool → false. An empty name shows the id.

**A provider keeps reporting its entry in every state** — logged out, stopped, the daemon
not running, its status unreadable: the entry is there, with `attention` saying what is
wrong. Never an empty list for "I don't know". An entry not reported is shown nowhere and,
in "VPN with a network", is *not available* (kept, never removed by the shell).

- **`state`** is NetworkManager's vocabulary: the rows and cards say Connecting… /
  Connected / Disconnecting… / Off from it, and "VPN with a network" follows it.
- **`attention`** `{ reason, action }`: a LASTING state that needs the user, not a one-off
  failure — `reason` one plain sentence ("Log in to Tailscale to connect"), `action` a short
  button label ("Log in"; "" none). The popup row and the card show the sentence in the
  warning colour; the action's button calls `attend(id)`. While the entry has attention
  and is not active, the action replaces Connect (no Connect at all if it has no action);
  while active, Disconnect stays and the action sits beside the sentence. The shell never
  connects an entry with attention by itself (below). **Never for transient states**
  ("starting", "reconnecting", "waiting for the daemon to answer" — those are `state` and
  `status`). The core is robust against a brief one only right after asking (below).
- **`status`** (optional, ≤ 80 chars, default ""): one short line shown with the state —
  in the popup row under the name (a second line, muted, elided; a row without one keeps its
  one-line height), on the card in its subtitle after the state: "Tailnet
  only", "Via <exit node>", "Starting…".
- **`busy`** (optional bool, default false): an operation runs for this entry; its buttons
  are disabled while it or the provider's `busy` is true (`VpnManager.busyFor`).
- **`detail`** has the shape `VpnManager.details` has for NetworkManager's VPNs
  (`NetworkRules.vpnDetails`): `{ server, servers [], iface, interfaceName, addresses [],
  dns [] }`, all optional, normalised by `vpnProviderDetail` (`service` is always ""). The
  card shows server, interface, addresses, DNS and, from `iface`, speed and data moved;
  the overview counts `iface` among the VPNs' devices.

### Ids

The core addresses an entry as `"<providerId>:<entryId>"` (`NetworkRules.vpnId`,
`vpnIdParts`). NetworkManager's UUIDs are hexadecimal digits and dashes, so the colon keeps
the two apart for good; `VpnManager.connect/disconnect/attend` dispatch on it: an id with a
colon goes to its provider (nothing happens if the provider or the entry is not there, or
the id is malformed), any other id is a NetworkManager UUID on the unchanged path.

### What the core does with it (each consumer)

- `VpnManager`: `vpns` = NetworkManager's then the providers' (`mergedVpns`: those up first,
  then most recently used — providers have no "last used" —, ties in registration order).
  A provider's entry appears as `{ uuid: "<p>:<id>", name, type: "provider", kind: "vpn",
  state, active, device: "", autoconnect: false, priority: 0, lastUsed: 0, provider,
  entryId, typeName, glyph, attention, status, busy }`. `activeVpns`, `activeType`
  (unchanged values), `activeGlyph` (new: WireGuard's / the provider's own / padlock),
  `details` (merged; `nmDetails` NetworkManager's alone), `interfaceNames` (merged;
  `nmInterfaceNames`), `interfaceOf`, `typeName`, `glyphOf`, `busyFor`, `needFor`,
  `providerOf`, `extrasFor`, `settingsPageOf`, `pageOf`, `openSettingsPageOf`, `contextFor`, `unavailableVpnIds`, `labelOf`.
- Popup (`panels/network/VpnSection.qml`): header glyph, a row per VPN with its glyph,
  name, status, privileged mark, Connect/Disconnect/attention button (disabled while
  `busyFor`); under a provider's row the attention sentence, the kill switch note (while
  up or connecting) and the row extras. Rows are keyed by id: a re-read or a reorder keeps
  the row and its extras (an open chooser is not torn down).
- Bar (`widgets/NetworkWidget.qml`): the VPN glyph from `activeGlyph`.
- Overview (`NetworkOverview`): the VPN line names every VPN up; a provider's `iface` is a
  VPN device.
- VPN page (`NetworkVpnSettings.qml` + `NetworkProfileCard.qml`, not forked: `external`,
  `editable`, `deletable`, `busy`, `need`, `canUse`, `notice`, `noticeAction`): a provider's
  card has no editor, no delete, no autoconnect; it connects through the provider (origin
  "user"), shows the status in its subtitle, the attention and the kill switch note
  (whenever blocking is on), the card extras, and "Settings…" when the provider has a page:
  to its own settings page when it names one the settings window has (`settingsPage`,
  `VpnManager.settingsPageOf` → `openSettingsPageOf` → `Shell.openSettings`; the left list
  selects it, under Network beside VPN for a module page with `"parent": "network"`), else
  the framed page (`pageOf`), else no button. One place for the page: never both. "Has" is
  `Shell.settingsPageIds`, the ids the settings window publishes (its `pages`, modules'
  included), so a module turned off takes the way there with it.
- Connection editor's "Connect a VPN with it": provider entries are selectable pills; the
  not available ones as removable pills (below).
- Kill switch (`VpnLockdown`): NetworkManager's VPNs only (below).

### Slots

Names in `VpnManager.slots`. A contribution's root item may declare `property var context`;
the core sets it (`VpnManager.contextFor`) and sets it again only when its value changes
(`NetworkRules.sameVpnContext`: a re-read that changed another entry does not touch it):

| Slot | Where | Context |
|---|---|---|
| `network.vpn.row` | under the VPN's row in the network popup (an exit-node chooser) | `{ slot, vpnId, entryId, vpn, provider }` |
| `network.vpn.card` | on the VPN's card in Settings → System → Network → VPN, while open | `{ slot, vpnId, entryId, vpn, provider, open }` |
| `network.vpn.page` | a page over the VPN page, opened from the card's "Settings…" — the fallback for a provider without a known `settingsPage` | `{ slot, vpnId, entryId, vpn, provider, close }` (`close()` returns) |

`vpn` is the merged entry above; `provider` the provider object itself, so a contribution
calls the provider's own functions and reads its own state without a singleton of its own.
Each is built in a Loader (`components/VpnExtras.qml`; the page's in
`VpnProviderPageFrame`): one that fails to build shows nothing. Since module API 1.1 they are
slots of the module host: `VpnManager.extrasFor` / `pageOf` ask `Modules.slotComponent` /
`slotUrl` for the module whose id is the provider's `providerId` (a module's provider uses its
module id), then fall back to the provider's own `rowExtras`, `cardExtras`, `pageUrl` (the
stand-in provider); the frame hands a module's page its `module` handle. Contexts carry
`otherVpnsUp` too (the names of the other VPNs up).

**The page's frame** (`panels/settings/VpnProviderPageFrame.qml`) is the core's, framed as
the connection editor is: "‹ Back" (= `close()`), a title — the provider's `typeName` · the
entry's name — and a scrolling area with the settings pages' margins. The provider's page
is a plain item (a `ColumnLayout`), laid out at the frame's width and scrolled by its
`implicitHeight`; it must not scroll itself nor draw its own Back or title. When the entry
leaves the list (provider gone, entry missing from a read) the page closes, and it does not
reopen by itself when the id comes back.

Building blocks for a page: from `qs.components` — `SmallButton`, `DeleteButton`,
`ToggleSwitch`, `Pill`, `Dropdown`, `InputField`, `PrivilegedMark`, `HoverTip`, `Checkbox`
and the rest there. The settings pages' own `Heading`, `SectionTitle`, `Hint`, `DetailRow`
and `SwitchRow` live in `panels/settings/` (`SchemaSettingEditor` too, which is tied to the
settings schema) and are not part of the module API yet. **Open question for the manager**:
move the generic five (`Heading`, `SectionTitle`, `Hint`, `DetailRow`, `SwitchRow` — small,
depending only on `qs.singletons` and `qs.components`) to `components/` so `qs.components`
suffices, at the module API stage (M1/M2)? It is a rename plus `import qs.components` in
some 40 settings files and `panels/widget_settings/`, not done now so as not to churn files
other work is touching. Until then a module copies the look or imports
`qs.panels.settings` (works, but not promised).

### "VPN with a network" (`system.vpnWithNetworks`)

- Provider ids are stored as `"<p>:<id>"` beside UUIDs. `prunedVpnMapping(mapping,
  profiles)` **never removes a provider id**, whatever its provider says and whether it is
  there at all: a provider logged out, stopped, unreadable for one read, `ready` too early,
  or an entry id changing must not delete the user's setting. Ids that can be neither a
  UUID nor a provider's are removed, and so are NetworkManager UUIDs whose profile is gone
  (as before).
- **Not available** — one definition, `NetworkRules.unavailableVpnIds(ids, vpns)`: a
  provider id in the mapping that is not in `VpnManager.vpns` now, whatever the reason
  (provider not registered, not ready, logged out, the entry missing from a read).
  `VpnManager.unavailableVpnIds` applies it to the mapping. The network's editor starts
  from `editorVpnIds(stored, vpns)` — NetworkManager's VPNs still there and **every**
  provider id stored — shows each not available one as a picked pill "<provider> · <id>
  (not available)" that the user can unpick, and writes `vpnsToWrite(stored, original,
  edited)`: the user's picks plus every provider id stored that the user did not take out,
  so it never writes a list missing an id the user did not remove. Unpicking and saving is
  the only way such an id leaves the setting.
- `vpnWithNetworkPlan(..., providerVpns)` drives provider entries through the same states
  (pending → seen up; still down after 90 s → held down until the networks change; taken
  down by hand → held down; brought up by the shell → taken down with its network), and
  asks with origin "network". Not considered before NetworkManager's profiles are read. An
  entry with `attention` is never asked to connect; one that reached attention after being
  asked is held down like a failure once `vpnAttentionGraceMs` (20 s) have passed since it
  was asked — attention inside that window is waited out (still pending), so activating →
  a brief attention → activated is not held down and stays the shell's to take down with
  its network. Limit: attention reached from up (brought up, seen up, then down with
  attention) is held down at once — another reason a provider must not use attention for
  transient states. One that needed the user before it was ever asked is asked once the
  attention is gone. A provider registered late is followed when it arrives; one
  unregistered while up is left alone, its memory kept while the mapping names it (pending
  or held-down memory of an id neither known nor mapped is dropped, and the 30 s re-check
  runs only for pending VPNs that are there).

### The kill switch does not support provider VPNs (§8)

`VpnLockdown`'s interfaces and servers come from NetworkManager's VPNs only
(`nmInterfaceNames`, `nmDetails`); `scripts/h2s-vpn-lockdown` is unchanged. While blocking
is on or about to be (`VpnLockdown.blocking`: always, or on the network up), the VPN page
states it on every provider VPN's card, connected or not (`VpnLockdown.noteFor(vpn,
true)`); the popup's row says it only while that VPN is up or connecting. One sentence
(`lockdownNote`, else the shell's: "<type> is not let through by the blocking of traffic
outside a VPN: it cannot reach its servers or its peers, so it may not connect or carry
traffic.").

What the script does to such traffic today (version 3, read from its `ruleset`): output to
`tailscale*` interfaces is accepted (`virtual_names`), so packets into the tunnel pass the
filter — but the daemon's own packets (WireGuard to peers, DERP relays, the coordination
server) leave on the physical link and are dropped, except DNS (port 53, any address),
replies to connections that came in, peers on the local network when "Allow the local
network" is on, and traffic routed into another VPN's interface (`wg*`, `tun*`…, accepted)
— a NetworkManager full-tunnel VPN that is up can carry Tailscale only when its default route
is in the main table (OpenVPN-style): tailscaled's own packets carry fwmark 0x80000 and are
routed by the main table (ip rule priority 5210), so with a NetworkManager WireGuard full
tunnel that uses its own policy table they leave on the physical link and are dropped (from
reading, untested). So with blocking on and
no other VPN up, Tailscale cannot connect, and a running one stops carrying traffic beyond
the local network.

### What a provider must guarantee

- `providerId` constant; entry ids stable for the same VPN (they are stored in settings).
- Its entry reported in every state (logged out, stopped, unreadable → with `attention`),
  never an empty list for "don't know".
- `state` truthful and prompt: "activating" from the moment it acts, back to "" (with
  `failed` emitted, or `attention` set) when it gives up — "VPN with a network" reads a
  silent "" after 90 s as a failure. A dismissed prompt (pkexec 126): back to "", nothing
  emitted.
- On origin "network": no prompt, no browser — `attention` instead.
- `attention` only for lasting conditions, cleared when they end; never for transient
  states; one-off errors go through `failed`.
- `busy` (provider's or entry's) true only while an operation runs; `ready` true once the
  entries have been read successfully.
- Never block the event loop in `connect`/`disconnect`/`attend` (run processes).

### By hand: the stand-in provider

`H2S_FAKE_VPN_PROVIDER=1` in the shell's environment makes `VpnManager.start()` load
`tests/FakeVpnProvider.qml` (by its file URL) with IPC target `fakevpn`: `list`, `add <id>
<name>`, `remove`, `state <id> <state>`, `attention <id> <reason> <action>`, `clear <id>`,
`status <id> <text>`, `busy <id> <bool>`, `needsPrompt <bool>`, `failNext <reason>`,
`slow <ms>`, `canChange <bool>`, `note <text>`, `extras <bool>`, `page <bool>`, `garbage`.
Without the variable nothing of it exists. (The switch stays in `VpnManager` for now: the
shell has no entry point of its own for development, and `tests/` ships with the package
anyway; moving it is for the module host, which will load modules by file URL the same
way.)

## 4. The kill switch (core, security-relevant)

`scripts/h2s-vpn-lockdown` gains one checked option: accept output carrying the mark
`0x80000/0xff0000` (only a process with CAP_NET_ADMIN can set a mark). Script version
goes up, so installed copies show as outdated and the NixOS copy must be renewed. Its
own review, with the question: can anything but tailscaled obtain that mark.
Advertising routes or an exit node under blocking needs the forward chain too — v2.

## 5. Testing

- `TailscaleRules` (pure): state and attention from status + prefs, exit nodes, devices,
  key-expiry warning, error kinds from stderr, a digest of an event line, what the kill
  switch needs, and the command for a change (always `set`).
- A stand-in `tailscale` (and `curl` for the stream) replaying redacted fixtures, behind
  a tools seam like the lock's: running, stopped, starting, needs-login (URL, then
  success), needs-approval, logged out, key expiring/expired, exit node, exit node
  offline, health warnings, daemon not running, not operator (every change denied),
  become-operator through a stand-in pkexec, the stream dying and returning, resume.
- The real daemon is touched only by the owner. Agents may run read-only commands
  only, and never `up`, `down`, `set`, `login`, `switch <id>`, `logout`. (Step 2: the
  owner allowed `netcheck`, `ping` and GETs on the LocalAPI for research.)

## 6. Stages (after M0–M2 of modules.md; M3 can run beside them)

- **T0** — the module's repository: manifest, stand-ins, fixtures, the rules and their
  suite. No UI.
- **T1** — read-only: the entry through the seam, states and attention, the page with
  settings shown and the devices. Nothing changes Tailscale yet.
- **T2** — actions: connect/disconnect, exit node, the switches, become operator,
  log in/out.
- **T3** — the kill switch option and "VPN with a network".
- **T4** — on the real machine, once, with a checklist; then packaging for NixOS.

## 7. Questions for the owner (suggested answer after the arrow)

1. What matters most: picking an exit node, or reaching the tailnet's devices? → Both
   in v1, the exit node prominent in the popup.
2. Several tailnets or accounts in use? → No; switching waits for v2.
3. May the shell offer to make the user the Tailscale operator (nearly root over
   Tailscale: SSH server, advertising routes, DNS)? → Yes, once, with the warning; the
   declarative NixOS line shown beside it.
4. Does "block traffic outside a VPN" count Tailscale without an exit node as a VPN?
   → Yes: the tailnet passes, the internet is blocked — said plainly on the page.
5. Live updates through the LocalAPI stream (not a promised interface), or polling?
   → The stream, with a 60 s fallback poll, behind one singleton.
6. Tailscale's entry: among the VPNs from the first version (needs the seam first), or
   a widget and page of its own first? → Among the VPNs: that is what "like a regular
   VPN" means; it costs stage M3 up front.
7. The kill switch change in v1? → Yes: without it Tailscale and blocking cannot be on
   together.

## 8. Decisions (the owner's, 2026-11-15) — these override §2, §4 and §7 where they differ

- **Among the VPNs from the first version**; a bar widget of its own comes later.
- **Privileges**: Tailscale's changes need root, so the module asks for it — every
  change that is denied goes through `pkexec tailscale …`, answered by the shell's
  polkit agent, with the button marked as privileged. "Become operator" stays as an
  offer on the page (one prompt instead of one per change), not a precondition.
- **The kill switch is not supported**: Tailscale's way of working is at odds with it,
  and `scripts/h2s-vpn-lockdown` is not changed for it. The VPN page says so when both
  are on (§4 is dropped; stage T3's script work with it). "Bring it up with this
  network" stays.
- **Scope: as much of Tailscale as possible, ideally all of it.** The "not planned"
  list of §2 is dropped except where the system owns the thing (`tailscale update` on
  NixOS: shown, not run). Order of delivery:
  1. the entry among the VPNs, states and attention, connect/disconnect, log in/out,
     exit nodes (choose, none, suggested, Mullvad grouped, allow LAN), accept routes,
     accept DNS, shields up, the devices list with copy;
     **Built 2026-11-15** (module 0.2.0 in h2s-shell-tailscale, on module API 1.1 here): the
     live client (one curl on the LocalAPI bus as a trigger for coalesced re-reads of
     `status --json` + `debug prefs`, backoff, 60 s poll, a re-read after sleep), the provider,
     the three slots (exit-node chooser under the row, the card's extras, the page — also
     a settings page under Network), pkexec on denial for the user's clicks only, become
     operator with the NixOS line, facts `tailscale.connected` / `tailscale.exitNode`; suites
     against stand-ins and a lock-bed test (the test bed takes tests from another directory:
     `LOCKTEST_EXTRA_TESTS`). Still missing from step 1: nothing of the list, but verified only
     against stand-ins — the owner's check on the real daemon (T4) is open; a `tailscale login`
     run through pkexec runs as root and cannot be ended by the shell (cancel and the 10-minute
     limit stop waiting for it only); the key-expiry warning is shown, re-auth before expiry is
     step 2; the devices' traffic is polled every 3 s while the page is open (there is no
     "page visible" signal in the API).
  2. accounts and tailnets (switch, add, remove), hostname, key expiry and re-auth,
     health, update notice, diagnostics (netcheck, DERP, ping a device);
     **Built 2026-11-16** (module 0.3.0, still on module API 1.2 — no core change): the page's
     Accounts (the account in use from status/prefs; the list `switch --list --json` only on
     request — root or the operator only, so through pkexec, kept in memory, updated in place
     after a switch or removal; switch, `switch remove <id>` with the delete button but never
     the account in use, add = a bare `login`, `set --nickname=`); a personal tailnet named by
     its MagicDNS suffix on the card and the page, the e-mail address only as the account;
     This device (`set --hostname=` checked as one DNS label, the system's name back,
     addresses to copy — `Api.copy` exists —, online and home relay, the key's expiry, a
     warning from 14 days and on the entry's status line within 7, the admin console linked —
     no "Renew", see below); Diagnostics, collapsed and run on request (`version
     --json`, `netcheck --format=json` with region names from `debug derp-map`, `dns status
     --json`, every health warning with its title, the update notice, "Copy diagnostics"
     without keys or links; no `bugreport`); ping from a device row (`ping --c=1
     --timeout=3s`). Facts relied on, observed read-only on 1.104.4: the profiles LocalAPI is
     403 for a non-operator; `switch remove <id>` exists; netcheck's JSON follows a "# Warning"
     line; `dns status --json`'s shape. **Established by the review from 1.104.4's source**
     (cmd/tailscale/cli/login.go, up.go; ipn/ipnlocal/profiles.go): a bare `login` ALWAYS
     calls SwitchToEmptyProfile first, before any URL — the connection drops for the whole
     browser wait; the same account is then merged into its old profile (findMatchingProfiles)
     with login's default prefs (exit node, accept-routes, hostname, advertised routes,
     shields-up, SSH, nickname, operator lost); another account becomes a new profile;
     cancelling leaves the daemon on the unpersisted empty profile, logged out, and `switch
     <id>` restores the old one with its prefs. Hence: no "Renew" (removed after the review);
     "Add account" says it disconnects; after a login from a logged-in profile that did not
     finish, the next read decides (no login → "Switch back"); beside an expired key's "Log in"
     the page says logging in again resets the settings. Not verified: whether `set
     --hostname` itself rejects what the module refuses (dots). Open: the owner's check on the
     real machine (T4).
     **Backlog (step 2)**: non-destructive re-auth — POST /localapi/v0/login-interactive as
     root; open question how the auth URL reaches the user (BrowseToURL goes to the initiating
     actor's watcher; check whether status's AuthURL carries it); needs a real-machine check.
     Snapshot the prefs before a same-account login (an expired key's "Log in") and offer to
     re-apply them with `tailscale set` afterwards.
  3. sharing this computer: advertise an exit node and routes, the SSH server, the web
     client switch; ssh into a device from its row;
     **Built 2026-11-16** (module 0.4.0, still module API 1.2; one core change, to the module test
     runner: each asynchronous suite its own `TestCase.timeLimitMs`, 20 s default, capped at 60 s —
     the live suite declares 45 s): the page's
     Sharing (exit node `set --advertise-exit-node=`, subnet routes `set --advertise-routes=<the
     whole list>` checked first — address/prefix, no host bits, no /0, no duplicate, a warning in
     100.64.0.0/10 —, each with its approval, the web interface `--webclient` with its link; under
     "More": `--advertise-connector`, `--snat-subnet-routes`, `--stateful-filtering`,
     `--relay-server-port`, `--report-posture`, the netfilter mode and the tags read only) and SSH
     (`set --ssh=`, the ACL page linked, off with the reason without the tailnet's SSH capability);
     a device row with `sshHostKeys` copies `ssh <MagicDNS name>`; About: `--update-check`,
     `--auto-update` (off with the reason on NixOS). **From 1.104.4's source**: the exit node and
     the routes are one preference; `set` with one of the two flags keeps the other half
     (cli/set.go calcAdvertiseRoutesForSet), so the module never sends both; using and offering an
     exit node at once is refused by the daemon (ipnlocal checkExitNodePrefsLocked) — refused
     before it runs, "Stop using it" offered; approval = the route in status's Self.AllowedIPs
     (PrimaryRoutes: served now; ExitNodeOption: both /0 approved); `--advertise-tags` is a flag of
     `up` only (not offered; shown read only); there is no `--posture-checking` (it is
     `--report-posture`); auto-update is refused on NixOS (clientupdate: updateNixos is not an
     auto-updater); the lose-ssh confirmation of `set --ssh` asks only inside an SSH session over
     Tailscale (SSH_CLIENT; pkexec clears it). IP forwarding is read from /proc (a seam for the
     two paths: H2S_TAILSCALE_FORWARDING_DIR) when something is offered and the page is shown or
     after offering; the warning gives `services.tailscale.useRoutingFeatures = "server"` (option
     checked in nixpkgs) or the sysctls; nothing is written. No terminal is opened from a device
     row: the core has no terminal setting or launch API (a possible later addition). Fixed with
     it (owner's report): a name set while disconnected is shown as set, with "the tailnet shows it
     after connecting" while status still has the old one. Verified: the module's suites (the
     rules on redacted fixtures, the live side against the stand-ins — whose `set` follows set.go's
     composition and refusals) and the lock-bed test (a route and the exit node offered through
     pkexec, waiting for approval, approved by the stand-in's admin, the forwarding warning from
     the bed's fake /proc, SSH on, a rename while off). Open: the owner's check on the real daemon
     (T4) — approval and forwarding as the real control plane reports them. After the review: a
     route edit is an intent (add X / remove X) planned from prefs read again under the
     operation lock, before the plain run and before the pkexec retry; refused while prefs are
     unread, not re-read since the last operation, or cut at 256; a profile changed since the
     click aborts ("Changed meanwhile"); once pkexec's dialog is up its argv is fixed (a change made
     elsewhere during the dialog is overwritten);
  4. Taildrop: send to a device, receive with a notification and a folder;
     **Built 2026-11-16, revised after its security review** (module 0.5.0, still module API 1.2 —
     no core change: QtQuick.Dialogs is importable by modules, `module.notify` takes actions, "Open
     folder" is `Api.openUrl(file:, { allowFile: true })` on the folder). **Privileges, from
     1.104.4's source**: the LocalAPI's `file-put` and `files/` need write access — root or the
     profile's operator (feature/taildrop/localapi.go `!h.PermitWrite` → 403; ipn/ipnauth
     IsReadonlyConn); `file-targets` and the bus need read only; the CLI opens and writes the files
     with the caller's uid (cli/file.go); received files wait in /var/lib/tailscale/files/…, root's.
     **Decision: Taildrop is the operator's, run as the user, never through pkexec.** A root send was
     built and rejected in review: paths are not canonical and root opens them long after any
     user-side check, so a swapped file or parent link makes root read and send what the user cannot;
     no cheap check closes that race. A root `file get` leaves root's files in the user's folder.
     Not the operator: one line and "Let this user manage Tailscale without a password";
     "Stop being the operator" is `set --operator=`. Built: sending (`file cp -- <paths…> <IPv4>:`
     outside the change lock — the entry is not busy; Disconnect, logout, account switches and
     unload kill it; Cancel kills it; stopped after 2 minutes without OutgoingFiles progress, 6 h
     at most; a `find -P` only for messages), targets from status's TaildropTarget; arrivals from
     IncomingFiles (Done) and FilesWaiting (on every non-initial message — local.go sendToLocked),
     a notification, "Files received" on the entry; saving by the operator (GET `files/<name>` with
     curl into a staging dir in a user-owned non-link folder, rename into place, then DELETE; names
     re-sanitised — tailscaled allows a leading "." and "-"); auto-save per arrival, never
     "overwrite", no retry of a left file until the next arrival or a manual Save. With it:
     `_runChange` refuses a second change while one runs. Verified: rules on synthetic fixtures,
     the live side against the stand-ins (a refused non-operator, send, Disconnect ending a send,
     cancel, a stall, the race, the operator's save with adversarial names, a linked folder,
     auto-save without loops), the lock-bed test. Not known from the bus: the sender. Open: the
     owner's check on the real daemon (T4) — the 403 for non-operators, the bus's file fields as
     sent, and the file/folder dialogs by click (pasted paths and drops work without them);
  5. serve and funnel (list, add, remove), certificates for the machine's name,
     tailnet lock status, an exit node per network;
     **Built 2026-11-16** (module 0.6.0, module API 1.3 — one core addition: `Api.networks` (NetworkManager's
     saved Wi-Fi and Ethernet profiles `{ id (UUID, the key of system.vpnWithNetworks), name, kind, active }`,
     hotspots and ports left out) and `Api.vpnsUp` (`{ name, type, provider }` of the VPNs up), pure parts
     `ModuleRules.apiNetworks` / `apiVpnsUp`, tested in ModuleRulesTest; a module may not read the network
     singletons, and there is no per-network settings slot). **Established from 1.104.4's source**: the
     serve config is readable by any user (ipn/localapi/serve.go GET: PermitRead; observed `serve status
     --json` → `{}`, `lock status --json` readable, both unprivileged), writable by root or the operator
     (403 "serve config denied"); a config holding a Path handler or a unix socket needs root or a
     sudo-capable operator; tailscaled itself (root) opens served files at request time, following links
     (ipnlocal serveFileOrDirectory) — so **path serving is not offered** (existing path entries are listed
     and removable); the CLI does read-modify-write with the config's ETag, `serve` sets a handler with
     Funnel off for its host:port and `funnel` with Funnel on (cli/serve_v2.go applyFunnel), so Funnel per
     entry = the entry's own handler sent again; `serve` with HTTPS on a node without the `https`
     capability enters enableFeatureInteractive (prints a link, may wait) — refused before it runs; Funnel
     needs the `https` and `funnel` node attributes and a port in `https://tailscale.com/cap/funnel-ports
     ?ports=…` (the CLI checks only 443 — the module checks the real port), and is refused under shields up
     (ipnlocal setServeConfigLocked); the cert LocalAPI needs write access (root, operator) or
     TS_PERMIT_CERT_UID and the CLI writes the files itself (cert 0644, key 0600, atomically) — so
     **certificates are the operator's, as the user**, into `<data home>/h2s-shell/tailscale/certs` (700),
     the domain only status's CertDomains entry equal to this node's MagicDNS name; `lock status --json` is
     tslockjsonv1 (schema "1"); locked out = enabled, keys present, NodeKeySigned false. Built: the page's
     Serve (collapsed; read when open on screen and after changes; add a local port over HTTPS 443/8443/10000
     with an optional path, a TCP forward, Funnel per entry, remove, stop all; every change an intent
     planned from prefs and the config read again under the change lock, before the plain run and before
     the pkexec retry; preconditions with the admin console's link), Certificates (collapsed; end date via
     openssl when installed), Tailnet lock (status; locked out → the entry's attention while connected,
     "Open admin console"), Exit node by network (a table in the module's store keyed by the network's id;
     acted on once per set of marked networks up — a manual choice afterwards stays; operator only, origin
     "network", never a prompt; a conflict between two networks does nothing), a line when another VPN is up
     beside the exit node (the API says which VPNs are up, not whether one is a full tunnel). `errorKind`
     takes the daemon's "must be root, or be an operator and able to run 'sudo tailscale'" as denied (a
     config holding a path set by root: the retry through pkexec re-posts it; the module adds no path).
     Verified: the rules on synthetic fixtures in the real shapes (ServeTest), the live side against the
     stand-ins (ServeLiveTest: share through pkexec with the module's argv, Funnel on, HTTPS off refused
     before anything runs, the operator's certificate with modes 700/644/600 and none for others, locked
     out → attention, exit node set by network as the operator and not otherwise), the lock-bed test (see
     the module's CHANGELOG). Not observed (the real daemon here: Stopped, no CertDomains, no `https`
     capability): a real HTTPS share, Funnel, a certificate, an enabled lock — the owner's check (T4).
     **Backlog (step 5)**: certificate renewal (the daemon renews its cache when asked; a timer per
     certificate, or on resume, would rewrite the files); path serving only if Tailscale ever serves paths
     with the configuring user's rights; tailnet lock administration (init, sign, add/remove keys,
     disable) stays out; Funnel over TCP; telling a full-tunnel VPN from a split one (needs each VPN's
     never-default / allowed IPs through the API);
  6. a bar widget and popup of its own.
- Several tailnets: supported in step 2 rather than assumed away.
