# Plan: network management in the System tab (TODO 11.37)

Requested 2026-11-12. The network popup connects to Wi-Fi and VPNs and nothing more;
NetworkManager holds everything else, so it belongs in Settings → System (the rule of
11.36: what a system service holds is edited there, no profile).

## What exists (2026-11-12)

- `singletons/NetworkManager.qml` (device status), `singletons/network/` —
  `WifiManager` (scan, connect, hidden, forget, radio), `VpnManager` (list, up/down, one
  active tracked), `EthernetManager` (device connect/disconnect), `IpManager` (first IPv4
  address and DNS per device), `NetworkEvents` (`nmcli monitor`, debounced), `Nmcli` (pure:
  `splitTerse`, `wifiNetworks`, `savedWifi`; tested in tests/NetworkTest.qml).
- Found while planning, to fix on the way:
  - **errors never reach the shell**: nmcli writes them to stderr (checked: `Error: unknown
    connection …`, exit 10, stdout empty) and no network Process reads stderr or the exit
    code — "Wrong password" in the popup almost certainly never shows; a failed connect
    waits out the 30 s timeout;
  - **profiles matched by name**, not by UUID or SSID: a profile named otherwise than its
    SSID breaks "saved" and "forget";
  - only one active VPN tracked; an action while another runs is dropped silently.
- Permissions (`nmcli general permissions`): on both machines a user may modify system
  connections without a password; on the host, global DNS and the hostname need polkit
  ("auth") — the shell's prompt (11.35) answers.
- VPN plugins: none installed on either machine; WireGuard works without one (built into
  NetworkManager). OpenVPN, OpenConnect, etc. need `networkmanager-openvpn` & co.

## All the settings, by page (System → Network → …)

### Overview
- Devices: Wi-Fi, Ethernet, others NetworkManager manages — state, connection, MAC,
  driver, link speed (Mbps), addresses (IPv4/IPv6), gateway, DNS in use.
- Switches: Wi-Fi radio; networking on/off; airplane mode (`nmcli radio all off`).
- Global: hostname (polkit), global DNS servers overriding connections' (polkit),
  connectivity check on/off.

### Wi-Fi
- Saved networks: name, SSID, security, autoconnect, priority, last used, in range now.
  Actions: forget, autoconnect, priority (order of preference), change password, show
  password (asks NetworkManager for the secret), open the connection editor.
- Connect to a hidden network (SSID, security, password) — exists in the popup; here too.
- Hotspots (done 2026-11-12): NetworkManager's own — a Wi-Fi profile with
  `802-11-wireless.mode ap` and `ipv4.method shared`, as many as wanted, each turned on and
  off like any connection. Their own section on the Wi-Fi page, cards like the saved
  networks'; the editor makes and edits them (security WPA2 / WPA3 / open and the password
  there; no priority, metered or IPv6). Decided: on one card, turning on asks first when it
  would drop the network in use with nothing else to share ("Leaves X: no internet to
  share. Turn on?"); the devices on it from `ip neigh` (the lease file is root's on Arch),
  count and list; defaults 2.4 GHz, WPA2 (Intel cards often may not send on 5 GHz, WPA3
  shuts older phones out). Turned off by `connection down`, so the saved network comes back.
- Later: sharing a network or a hotspot as a QR code (needs `qrencode`; on NixOS
  `pkgs.qrencode`).

### Ethernet
- Wired profiles: the same list and editor; which one a device uses.

### VPN
Decided with the user (2026-11-12), in stages:
1. The base: VPNs by UUID (VpnManager from NetworkProfiles), several up at once; the
   popup's section follows (each its own Connect / Disconnect, "Connecting…").
2. The page System → Network → VPN: cards like the saved networks' with the status
   (interface, address, server, speed, data sent), connect / disconnect, edit, delete;
   "Add VPN": a new WireGuard, or importing a `.conf` / `.ovpn` / another plugin's file
   (the portal's file dialog, as the wallpaper's Browse); missing plugins named, with what
   they are for — no install line (installing differs between systems).
3. WireGuard's editor: private key (Generate with `wg genkey` / `wg pubkey` when
   wireguard-tools is there, else a note that it is missing and what for; pasting always
   works), the public key to copy, addresses, DNS, MTU, listen port, peers (public key,
   preshared key, endpoint, allowed IPs with "All traffic", keepalive); the shared
   sections of the connection editor. Not our own X25519: a weak key from a randomness
   bug would go unnoticed, and `wg` is audited.
4. OpenVPN's editor: gateway, port, protocol, how it signs in, user and password,
   certificates as files; the rest of an imported profile left as it is. Other plugin
   VPNs: import, connect, delete only.
5. Passwords and one-time codes asked at connecting: the shell is no NetworkManager
   secret agent, so it asks itself and hands them to `nmcli connection up … passwd-file`
   through a file in `$XDG_RUNTIME_DIR` (mode 600, removed at once).
6. A VPN with a network: "Connect a VPN with it" in a Wi-Fi or wired profile's editor
   (`connection.secondaries`); the VPN page lists the networks it comes up with.
7. Only through the VPN (a kill switch): nftables rules, root through pkexec, at odds with
   NixOS's declarative firewall — researched first (the VPN server must stay reachable,
   sleep and resume), the options put to the user before any code.
Status of WireGuard's handshake is `wg show`'s, root only: not shown.

### The connection editor (any profile)
- General: name, autoconnect, priority, metered (yes/no/automatic), available to all
  users or only me (`connection.permissions`).
- IPv4: method (automatic DHCP / manual / link-local / be the router / off);
  manual addresses (CIDR), gateway; DNS servers and search domains; ignore the DNS DHCP
  gives; only for its own network (never-default), route metric, require IPv4 (may-fail);
  as the router: this computer's address (sets the network), the range handed out
  (`ipv4.shared-dhcp-range`), the lease time — the devices' gateway and DNS server is this
  computer, so neither is a field; routes (later).
- IPv6: the same (automatic / DHCP only / manual / link-local / ignore / off), privacy
  extensions.
- Wi-Fi only: SSID, security and password, MAC address (keep / random / stable per
  network), band, hidden.
- Ethernet only: MAC address (keep / random / stable), MTU.

## How

- Through `nmcli` (as today; 5.2 chose it over D-Bus): reading a profile
  `nmcli -t -s -g <fields> connection show uuid <uuid>`, changing it
  `nmcli connection modify uuid <uuid> <prop> <value> …` — all of one save in one call, so
  a profile never stands half-changed. Profiles always by UUID.
- An active connection's changes apply when it reconnects: "Save" and "Save and
  reconnect".
- **Not cutting the branch you sit on**: changing the connection in use (the Framework's
  only link is Wi-Fi) can lose it. After "Save and reconnect" on the active connection, a
  "Keep these settings?" countdown (20 s): not confirmed → the old settings back and
  reconnected (as display settings do).
- Errors: every network command reads stderr and its exit code; messages mapped to plain
  words ("not authorized" → `Authentication.reportDenied`, secrets missing, unknown
  connection); a failed action says so where it was asked (and the popup's "Wrong
  password" finally works).
- Validation as pure rules with tests (`NetworkRules`): IPv4/IPv6 addresses and CIDR,
  gateways inside the subnet, DNS lists, WireGuard keys, priorities.
- Not here: NetworkManager's secret agent (WPA-Enterprise and VPN passwords asked at
  connect time) — a later item, like the polkit agent.

## Stages (proposed)

1. Foundations: errors from stderr and exit codes, profiles by UUID, a profile list with
   types (fixes the popup's "saved" and "forget" on the way); sub-pages in the settings'
   page list, and Network with them.
2. Overview tab: devices, details, switches, global settings. — the first version.
3. Wi-Fi page: saved networks, their actions, hidden network.
4. The connection editor (general, IPv4/IPv6, Wi-Fi/Ethernet extras) with the
   keep-settings countdown.
5. VPN page: list, WireGuard import/create/edit, plugin VPNs' import, VPN with a network.
6. Later: QR code, routes, profile hooks (Behaviour: Power save turning Wi-Fi
   off, joining a VPN).

## Decided (2026-11-12)

- **Layout: "Network" in the System tab's sidebar unfolds into its pages, under it**
  (instead of a second row of tabs, which takes width the Framework's screen lacks):
  Overview, Wi-Fi, Ethernet, VPN, Modem (mobile broadband, through ModemManager)… indented
  below "Network". The list is open while any of its pages is, and folds away when another
  page opens — no separate toggle; ▾/▸ only shows the state. Clicking "Network" opens its
  first page, Overview. The selection mark moves to the sub-page; the parent is lit more
  faintly. A device kind's page shows when the computer has such a device (VPN always);
  each comes with its stage. A general mechanism of the page list (pages with a parent),
  for other groups later.
- **The connection editor opens as its own view** in the page, with Back and the profile's
  name as the title; Save / Save and reconnect at the bottom.
- **First version: the Overview tab with the global settings** — devices and their
  details, the Wi-Fi / networking / airplane switches, hostname, global DNS, connectivity
  check — together with the foundations (stage 1). The other tabs follow, stage by stage.
- **The Overview leads to the pages** (the user, 2026-11-12): once a kind of connection has
  its page, clicking its device card — and its line in the summary at the top — opens it
  (Ethernet → the Ethernet page, Wi-Fi → Wi-Fi, an active VPN → VPN, a modem → Modem).
  Added with each page's stage.
- **The Overview itself** (after the user's review): a line per kind of connection at the
  top (Wi-Fi, Ethernet, VPN, mobile broadband), only the airplane-mode and networking
  switches (a kind's own switch lives on its page), short descriptions, a lock
  (PrivilegedMark, the theme's `privileged` colour) where polkit asks for a password, and
  on NixOS the line for configuration.nix instead of writing NetworkManager's file.
- **"Keep these settings?" countdown, 20 s**, after saving the connection in use and
  reconnecting; not confirmed → the old settings back and reconnected.

## Progress

- 2026-11-12: stages 1–2. `CommandAction` (stderr, exit code, a queue), `Nmcli.records`,
  `profiles`, `wifiSsids`, `devices`, `errorKind`/`errorMessage`, `NetworkRules`
  (hostname, IPv4/IPv6, server lists, global DNS to and from D-Bus, speeds), all tested;
  `NetworkProfiles` (by UUID); the popup's saved networks by SSID, forget by UUID, real
  error messages; sub-pages in the settings' page list; `NetworkOverview` and its page.
  Seen on the host and the Framework; the global DNS's busctl form set and cleared on the
  Framework. Found on the way: blank lines between nmcli's blocks come glued to the next
  line's start, so `records` trims.
- 2026-11-12: stage 3, the Wi-Fi page. `Nmcli.wifiDetails` (SSID, key management, hidden)
  and `securityName`, `NetworkRules.isWifiPassword`, `Format.ago` (tested); NetworkProfiles
  changes profiles by UUID (connect, disconnect, autoconnect, priority, password, forget)
  and reads a secret for "show password"; `SwitchRow` and `DetailRow` shared by the pages;
  pages with `shown` (Wi-Fi only with a Wi-Fi device); the Overview's card and summary
  line lead to the page. The connection editor (IP, DNS) is stage 4.
- 2026-11-12: the Ethernet page (between the Wi-Fi page and the editor, the user's order):
  device cards with "Cable unplugged", wired profiles with use / disconnect in the Wi-Fi
  page's colours, autoconnect, priority, forget. Connecting is the profiles' only.
  NetworkManager's own wired profiles come with priority −999.
- 2026-11-12, after a code review: "Disconnect" takes the device down (`nmcli device
  disconnect`) — `connection down` only blocks that one profile, and NetworkManager brings
  up another that connects automatically on the same device at once (the earlier note
  here, "the same action twice", was wrong). "Use" runs on the device the page offers
  (`ifname`), only one ready to connect (a cable in, by its carrier, not NetworkManager's
  "unavailable", which also means no firmware); bridge and bond ports and profiles of
  devices that are not real wired ones are left out; "Never used" for a profile never
  connected; the Overview's links follow the sidebar's test for a page. The saved
  profile's card is shared by the Wi-Fi and Ethernet pages (`NetworkProfileCard`, its
  hover from PointerArea.lit), and so is the section title. Next: the connection editor.
- 2026-11-12, after a review of the Wi-Fi page: pages hold NetworkOverview with
  watch/unwatch and the scan with WifiManager.holdScan/releaseScan (counts: a page opening
  comes before the one it replaces is destroyed, and the popup and the page stopped each
  other's scan); a secret read with `--escape no`; the password field written, not bound
  (typing was overwritten, the eye broke after a save); connecting has its own queue and a
  secret's read none, and `busy` lasts until the list is read again; the hidden network is
  the popup's own form (HiddenNetworkRow, now checking the password).
- 2026-11-12: stage 4, the connection editor — general, IPv4, IPv6, DNS, Wi-Fi and Ethernet
  extras; `NetworkRules.settingsFrom`, `editorErrors`, `editorChanges` (tested); one
  `nmcli connection modify`; "Save and reconnect" with a 20 s "Keep these settings?" whose
  revert is the same changes the other way. Checked end to end on a throwaway profile
  (read, changed, read back, reverted, deleted). Left for later: routes, 802.1X, a new
  profile from the editor.
- 2026-11-12: every option explained (hover, and the picked one's under the pills — touch);
  list fields say how to write several. "Share to other computers" became "Be the router"
  (the user asked "I'm DNS"; it is DHCP, gateway, DNS and NAT, so the router it is), with
  its address, range and lease time; never-default, route metric and may-fail for both
  families.
- 2026-11-12: VPN stage 1 — VpnManager from NetworkProfiles by UUID (the profile list now
  reads STATE: activating / activated / deactivating), several up at once; the popup's
  rows each connect or disconnect their own VPN, failures reported. Checked on a throwaway
  WireGuard profile routed to a test subnet only (connected, disconnected, deleted).
- 2026-11-12: VPN stage 2 — the VPN page (cards, status while up, import, missing plugins
  named; the Overview links to it). Found while testing: NetworkManager brings an imported
  WireGuard profile up at once (autoconnect) — imported now from a copy in
  $XDG_RUNTIME_DIR named for a valid interface, made manual and taken down at once.
  Editing is the general editor until stage 3.
- 2026-11-12: review fixes for VPN stages 1–2 — a plugin VPN's tunnel interface, addresses
  and DNS read from the active connection (GENERAL.IP-IFACE: its profile names the link
  under it); the popup's Connect blocked while connecting; the Overview counts VPNs from
  VpnManager; several peers' endpoint; older nmcli without wireguard.peers; details read
  only when the VPNs change; WireGuard import through `mktemp -d`; plugin files read one
  by one; "Forgetting …" kept in messages.
- 2026-11-12: VPN stage 3 — WireGuard's editor and "New WireGuard"; keys by `wg genkey` /
  `wg pubkey` (the private key on its input). Tried and dropped after review: writing
  secrets through `nmcli connection edit` on its input, to keep them out of `ps` — its
  `set` cuts a password's spaces at its ends, a save became two steps (modify, then the
  secrets), and its failures had to be read from translated text. Decided with the user:
  one `nmcli connection modify` / `add` with the secrets, atomic and exact; a secret shows
  in `ps` to other users only while nmcli runs. Review fixes: an empty private key told
  from one not read, a WireGuard profile's other IPv4/IPv6 method kept visible, the public
  key worked out again once `wg` is found and never for a stale key, the clipboard by
  Quickshell.clipboardText, `wg` looked for once. Checked: a hotspot (password with spaces
  at its ends) and a WireGuard profile made, read back, a peer changed with its preshared
  key kept, both deleted; the user's "ua" read without a change.
- 2026-11-12: VPN stage 6 — found: NetworkManager's connection.secondaries refuses
  WireGuard ("is not a VPN connection profile"; plugin VPNs only), and takes the network
  down when the VPN fails. Decided with the user: the shell does it itself for every VPN
  (`system.vpnWithNetworks` { network: [vpn] }, VpnManager following NetworkProfiles'
  states; a network up at the shell's start counts; only VPNs it brought up go down with
  the network; one taken down by hand is left). Only while the shell runs. Checked on two
  throwaway WireGuard profiles (one as the network): up brought the VPN up, down took it
  down; deleted.
- 2026-11-12: review fixes for stage 6 — a wanted state instead of transitions
  (`vpnWithNetworkPlan`): a VPN linked to several networks stays while any is up; "pending"
  after asking to connect, so an early read is not taken for "by hand", and a connection
  still down after 90 s is held down, not retried; taken down only once its networks are
  fully down (a plugin VPN goes with its network by itself); what the shell brought up and
  what was held down remembered in Config (`network.vpnMemory`); started from shell.qml and
  followed on a change of the setting; gone profiles pruned from it. Editor: the VPNs picked
  written only after the profile's save went through, a failed save keeps the form,
  "Save and reconnect" only for the profile's own changes. Checked on two throwaway
  WireGuard profiles: up, down by hand (left down), network down and up (brought up),
  network down (taken down).
- 2026-11-12: VPN stage 7 — only through the VPN. Researched: the host runs no firewall
  (nft 1.1.7), the Framework NixOS's (iptables-nft) without nft on its PATH. Options put to
  the user: a table of our own through pkexec, rules for the system's configuration,
  NetworkManager routes (never-default), a "soft" switch. Decided: our own nftables table
  (`inet h2s_vpn_lockdown`, beside NixOS's firewall), with "Allow the local network", on
  always (the VPN page) or on the networks chosen (their editors; each switch between such
  networks asks for the password). Out: loopback, the WireGuard profiles' interfaces as set
  plus tun*/tap*/ppp*/vpn*/wg*, virtual interfaces (docker*, br-*, veth*…), the servers'
  addresses (found by getent before loading; the last ones kept when none is found), DHCP,
  DHCPv6, IPv6 ND; forward only into or out of a VPN, between virtual interfaces, or within
  the local network. Loaded atomically (the table deleted and made in one `nft -f`), only
  when the rules or the servers change, 3 s after the last change; nothing done until the
  VPNs' details are read (or every start would ask). Checked: the ruleset loads and
  replaces itself in an unprivileged namespace (`unshare -rn`), and blocks there as meant —
  dummy interfaces: the internet blocked, the server, the local network and the VPN let
  through, everything again once deleted. Not tried on the live system: it asks for the
  password and blocks the traffic.
- 2026-11-12: review fixes for stage 7 — DNS let out (decided with the user: a VPN set by
  its server's name must find it; the names asked without a VPN are seen by the network);
  a refused deletion no longer asks again every 3 s; OpenVPN's host:port:proto and every
  remote / every peer's endpoint; servers resolved per host, one not found keeps its
  addresses; no second load while getent runs; working with no VPN profile at all
  (wg-quick); nft looked for in root's own places inside root's shell, never from the
  user's PATH; "Apply again" through the same checks; the network list read through its
  text, written through VpnLockdown, gone profiles pruned; the per-network gap said on the
  page.
- 2026-11-12: password-free blocking (the user: "the password will be a nuisance"; "the
  script must not be a hidden trick: its state, install and remove in the shell"). The
  rules moved into `scripts/h2s-vpn-lockdown` (POSIX sh, readable; `on <lan> <interfaces>
  <addresses>` / `off` / `status` / `version`), which checks its arguments and builds the
  rules itself — so a polkit rule may let the user run it without a password: the most
  they can do is switch this blocking. Not installed, the shell runs its own copy through
  `pkexec sh` (a password each time). "Install…" (one password) copies it to
  /usr/local/libexec/h2s-vpn-lockdown/ with a readable copy of its rule beside it, and the
  rule to /etc/polkit-1/rules.d/49-h2s-vpn-lockdown.rules (that folder is root's to read on
  Arch, hence the copy); "Remove…" deletes both. NixOS: a module to save and import (the
  script inside as writeShellScriptBin, nftables, polkit.extraConfig; its rule checked in
  /etc/static). The page shows the state (installed / outdated / rule missing / a password
  still asked for — seen by the shell's own agent while the installed script runs), and
  the script and rule in full. Installed, the table's `status` is asked every 30 s and the
  blocking loaded again if a firewall reload dropped it. Checked: the script in an
  unprivileged namespace (on, status, off, bad interface / address / lan refused); the
  NixOS module parsed, its package built and run (version), its rule evaluated, on the
  Framework without installing it. Not tried: installing on the host (asks for the
  password).
- 2026-11-12: review of the password-free script — its argument check passed a line break
  (grep matches any line), so with the rule installed any nftables text could be loaded
  as root. Rebuilt with one job and nothing from outside reaching the rules as it came
  (the user: "nothing strange may be injected to get any result"): set -f (tun* in a loop
  could have become file names), C locale, a fixed PATH and IFS (written with printf: a
  trailing blank was lost on the way once); every argument checked against its allowed
  characters with `case`, then its shape, and rebuilt — IPv4 from four numbers 0–255
  without leading zeros, IPv6 from hex digits and colons (eight groups of four at most,
  one "::", lower case), names of letters, digits, "-", "_", 15 at most; one bad argument
  and nothing is done; the rules from fixed text with the rebuilt values only. The state
  in /run/h2s-vpn-lockdown.state (root's, gone at a reboot like the table; the table's
  comment held the lists and nftables allows 128 characters there), `status` "on …" only
  while the table is there too. Replies to what came in let out (ct established/related;
  a hotspot's DHCP replies). Also: installing keeps polkit's 0750 rules folder as it is; a
  refused switch either way leaves "Apply again" on the page and is said, not shown as
  "About to block"; the memory read only once Config has loaded; "Other VPN servers" for
  VPNs outside NetworkManager; the script's text and NixOS's module from VpnLockdown;
  dead code gone. Checked in an unprivileged namespace with its own /run: valid calls
  round-trip through `status`, a dropped table reads "off", 20 injection attempts refused
  (line break with include, ; " $( ) space * , leading zeros, 256, five numbers, IPv6 with
  a dot, two "::", long group, long name, empty item, bad lan, extra arguments), files
  named tun0-… in the working folder not expanded into the rules.
- 2026-11-12: the next review — a refusal now expires when the blocking is wanted or not
  again (a missed prompt left it stuck on); at most 256 addresses and 32 interfaces (the
  script's limits, the rest left out and said); no NetworkManager profile at all still
  lets it run (the list read once, empty too); only replies get out by conntrack (`ct
  direction reply`: a flow opened before the blocking, or left by a VPN that went down,
  is cut); every $(…) in the script checked by hand (bash outside POSIX mode, as NixOS
  runs it, does not stop inside one — tested under bash: a bad item among good ones still
  refuses all); a server's host from a URL or host::udp; "a password still asked" only
  from pkexec's question while the installed script switches; the status asked at the
  start, after network events and every 5 minutes (not every 30 s: each is a journal
  line); "Other VPN servers" checked as the script checks.
