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

Built 2026-11-15 on branch `vpn-providers`. With no provider registered the shell behaves
exactly as before (the existing Network suite passes unchanged; `VpnManager.vpns` is then
the very list NetworkManager's profiles give). Code: `components/VpnProvider.qml` (the
base type; its comment is the short form of this section), `singletons/network/VpnManager
.qml` (registry, merged model, dispatch), `NetworkRules.qml` (the pure parts), tests in
`tests/VpnProvidersTest.qml` with the stand-in `tests/FakeVpnProvider.qml`.

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
| `typeName` | string | core reads | the VPN's type on its card, the editor's picker tooltip (≤ 60 chars) |
| `glyph` | string | core reads | Nerd Font glyph for its rows; the bar's when only its VPNs are up |
| `entries` | list | core reads | see below |
| `ready` | bool (default false) | core reads | the entries have been read at least once (see "VPN with a network") |
| `busy` | bool | core reads | an operation runs: its buttons are disabled (as `NetworkProfiles.connecting` for NetworkManager's) |
| `canChange` | bool (default true) | core reads | false: changes need an administrator — its buttons carry `PrivilegedMark` ("auth") |
| `lockdownNote` | string | core reads | its own sentence for the kill switch note ("" the shell's) |
| `rowExtras` | Component or null | core instantiates | slot `network.vpn.row` |
| `cardExtras` | Component or null | core instantiates | slot `network.vpn.card` |
| `pageUrl` | string | core loads | slot `network.vpn.page` |
| `connect(entryId)` | function | core calls | bring the entry up |
| `disconnect(entryId)` | function | core calls | take it down |
| `attend(entryId)` | function | core calls | perform the entry's attention action (log in, approve, start the service, become operator…) |
| `failed(entryId, what, reason)` | signal | provider emits | an operation failed: the core shows the notification "<what> failed" with `reason` as its body — the route NetworkManager's failures take (NetworkRules.vpnFailureNotice). Not for a password prompt the user cancelled. |
| `autoRegister`, `registered` | bool | — | registration on completion (default true); whether it was taken |

The core calls `connect`/`disconnect`/`attend` only with an id the provider currently
reports, inside a guard: a throw is logged and shown as a failure notification. Properties
are read through bindings — keep them properties and change them by assignment (a new
array for `entries`), so the views follow.

### Entries

`entries`: `[{ id, name, state, attention, detail, active }]`, at most 64, checked by
`NetworkRules.vpnProviderEntries` (only own properties are read; a getter that throws counts
as missing). Dropped and logged (`VpnManager.providerProblems`, a warning when it changes):

- an entry that is not an object; `id` not `^[A-Za-z0-9._~-]{1,64}$` or a prototype name
  (`__proto__`, `constructor`…), or repeated (the first wins); `name` not text; `state` not
  one of `"activating" | "activated" | "deactivating" | ""` (missing = "").

Reset to the default and logged: `attention` not null or `{ reason: non-empty text, action:
text }` → null; `detail` not an object → empty; `active` not a bool → `state !== ""`. An
empty name shows the id.

- **`state`** is NetworkManager's vocabulary: the rows and cards say Connecting… /
  Connected / Disconnecting… / Off from it, and "VPN with a network" follows it.
- **`attention`** `{ reason, action }`: a LASTING state that needs the user, not a one-off
  failure — `reason` one plain sentence ("Log in to Tailscale to connect"), `action` a short
  button label ("Log in"; "" none). The popup row and the card show the sentence in the
  warning colour; the action's button calls `attend(id)`. While the entry has attention
  and is not active, the action replaces Connect (no Connect at all if it has no action);
  while active, Disconnect stays and the action sits beside the sentence. The shell never
  connects an entry with attention by itself (below).
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
  entryId, typeName, glyph, attention }`. `activeVpns`, `activeType` (unchanged values),
  `activeGlyph` (new: WireGuard's / the provider's own / padlock), `details` (merged;
  `nmDetails` NetworkManager's alone), `interfaceNames` (merged; `nmInterfaceNames`),
  `interfaceOf`, `typeName`, `glyphOf`, `busyFor`, `needFor`, `providerOf`, `extrasFor`,
  `pageOf`, `dormantVpnIds`, `labelOf`.
- Popup (`panels/network/VpnSection.qml`): header glyph, a row per VPN with its glyph,
  privileged mark, Connect/Disconnect/attention button (disabled while `busyFor`); under a
  provider's row the attention sentence, the kill switch note and the row extras.
- Bar (`widgets/NetworkWidget.qml`): the VPN glyph from `activeGlyph`.
- Overview (`NetworkOverview`): the VPN line names every VPN up; a provider's `iface` is a
  VPN device.
- VPN page (`NetworkVpnSettings.qml` + `NetworkProfileCard.qml`, not forked: `external`,
  `editable`, `deletable`, `busy`, `need`, `canUse`, `notice`, `noticeAction`): a provider's
  card has no editor, no delete, no autoconnect; it connects through the provider, shows
  the attention and the kill switch note, the card extras, and "Settings…" when the
  provider has a page.
- Connection editor's "Connect a VPN with it": provider entries are selectable pills.
- Kill switch (`VpnLockdown`): NetworkManager's VPNs only (below).

### Slots

Names in `VpnManager.slots`. A contribution's root item may declare `property var context`;
the core sets it (and keeps it current):

| Slot | Where | Context |
|---|---|---|
| `network.vpn.row` | under the VPN's row in the network popup (an exit-node chooser) | `{ slot, vpnId, entryId, vpn }` |
| `network.vpn.card` | on the VPN's card in Settings → System → Network → VPN, while open | `{ slot, vpnId, entryId, vpn, open }` |
| `network.vpn.page` | a page over the VPN page, opened from the card's "Settings…" | `{ slot, vpnId, entryId, vpn, close }` (`close()` returns) |

`vpn` is the merged entry above. Each is built in a Loader (`components/VpnExtras.qml`;
the page's in `NetworkVpnSettings`): one that fails to build shows nothing. Today the
components come from the provider (`rowExtras`, `cardExtras`, `pageUrl`); switching to the
module host's slot registry is the one function `VpnManager.extrasFor` (and `pageOf` for
the page).

### "VPN with a network" (`system.vpnWithNetworks`)

- Provider ids are stored as `"<p>:<id>"` beside UUIDs. `prunedVpnMapping(mapping,
  profiles, providers)`: an entry of a registered, `ready` provider is kept while reported
  and **removed for good** once that provider no longer reports it (the provider says it
  no longer exists); kept while its provider is registered but not ready; **kept, dormant**
  while its provider is not registered at all — a module disabled, not loaded yet or
  uninstalled never makes the shell delete the user's setting. The network's editor shows
  a dormant entry as a picked pill "<provider> · <id> (not available)"; unpicking it and
  saving is how the user removes it. Ids that can be neither a UUID nor a provider's are
  removed.
- `vpnWithNetworkPlan(..., providerVpns)` drives provider entries through the same states
  (pending → seen up; still down after 90 s → held down until the networks change; taken
  down by hand → held down; brought up by the shell → taken down with its network). Not
  considered before NetworkManager's profiles are read. An entry with `attention` is never
  asked to connect; one that reached attention after being asked (or after being brought
  up) is held down like a failure — no retry loop; one that needed the user before it was
  ever asked is asked once the attention is gone. A provider registered late is followed
  when it arrives; one unregistered while up is left alone, its memory kept.

### The kill switch does not support provider VPNs (§8)

`VpnLockdown`'s interfaces and servers come from NetworkManager's VPNs only
(`nmInterfaceNames`, `nmDetails`); `scripts/h2s-vpn-lockdown` is unchanged. While blocking
is on or about to be (`VpnLockdown.blocking`: always, or on the network up) and a provider
VPN is up or connecting, its row and card say so in one sentence (`lockdownNote`, else the
shell's: "<type> is not let through by the blocking of traffic outside a VPN: it cannot
reach its servers or its peers, so it may not connect or carry traffic.").

What the script does to such traffic today (version 3, read from its `ruleset`): output to
`tailscale*` interfaces is accepted (`virtual_names`), so packets into the tunnel pass the
filter — but the daemon's own packets (WireGuard to peers, DERP relays, the coordination
server) leave on the physical link and are dropped, except DNS (port 53, any address),
replies to connections that came in, peers on the local network when "Allow the local
network" is on, and traffic routed into another VPN's interface (`wg*`, `tun*`…, accepted)
— a NetworkManager full-tunnel VPN that is up can carry Tailscale. So with blocking on and
no other VPN up, Tailscale cannot connect, and a running one stops carrying traffic beyond
the local network.

### What a provider must guarantee

- `providerId` constant; entry ids stable for the same VPN (they are stored in settings).
- `state` truthful and prompt: "activating" from the moment it acts, back to "" (with
  `failed` emitted, or `attention` set) when it gives up — "VPN with a network" reads a
  silent "" after 90 s as a failure.
- `attention` only for lasting conditions, cleared when they end; one-off errors go
  through `failed`.
- `busy` true only while an operation runs; `ready` true once the entries reflect reality
  (never true with a stale empty list, or settings are pruned).
- Never block the event loop in `connect`/`disconnect`/`attend` (run processes).

### By hand: the stand-in provider

`H2S_FAKE_VPN_PROVIDER=1` in the shell's environment makes `VpnManager.start()` load
`tests/FakeVpnProvider.qml` (by its file URL) with IPC target `fakevpn`: `list`, `add <id>
<name>`, `remove`, `state <id> <state>`, `attention <id> <reason> <action>`, `clear <id>`,
`failNext <reason>`, `slow <ms>`, `canChange <bool>`, `note <text>`, `extras <bool>`,
`garbage`. Without the variable nothing of it exists.

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
  only, and never `up`, `down`, `set`, `login`, `ping`, `netcheck`.

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
  2. accounts and tailnets (switch, add, remove), hostname, key expiry and re-auth,
     health, update notice, diagnostics (netcheck, DERP, ping a device);
  3. sharing this computer: advertise an exit node and routes, the SSH server, the web
     client switch; ssh into a device from its row;
  4. Taildrop: send to a device, receive with a notification and a folder;
  5. serve and funnel (list, add, remove), certificates for the machine's name,
     tailnet lock status, an exit node per network;
  6. a bar widget and popup of its own.
- Several tailnets: supported in step 2 rather than assumed away.
