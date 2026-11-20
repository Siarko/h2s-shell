import QtQuick
import qs.singletons.network

// A VPN provider: VPNs that are not NetworkManager's — the first is the Tailscale module —
// listed, shown and switched by the shell beside NetworkManager's (VpnManager). The
// contract, as built, is in notes/plans/tailscale.md §3; this comment is its short form.
//
// A provider extends this type and declares it inside the module's own objects:
//
//     import qs.api
//     VpnProvider {
//         providerId: "tailscale"; typeName: "Tailscale"; glyph: "󰖂"
//         entries: [{ id: "default", name: "Tailscale · example.ts.net", state: "activated",
//                     attention: null, status: "Via exit-node-1", busy: false,
//                     detail: { server: "…", iface: "tailscale0", addresses: [ … ] } }]
//         ready: true
//         function connect(entryId, request) { … }   function disconnect(entryId, request) { … }
//         function attend(entryId) { … }
//     }
//
// It registers itself with VpnManager when made and leaves when destroyed (a module
// disabled at run time). Everything it reports is checked
// (VpnProviderRules.vpnProviderEntries): a wrong entry is dropped and logged, never shown.
//
// The core reads (bindings: keep them as properties, change them by assignment):
//   providerId  string, constant — a lower-case letter, then up to 31 of a–z 0–9 - _ (no
//               colon). The core addresses an entry as "<providerId>:<entry id>", which no
//               NetworkManager UUID can be. A second provider with a taken id is refused.
//   kind        string — what sort of thing it is ("mesh", "vpn"); informative only
//   typeName    string — the VPN's type as the cards and the editor's picker show it
//   glyph       string — a Nerd Font glyph for its rows and, when only it is up, the bar
//   entries     [{ id, name, state, attention, detail, active, status, busy, fullTunnel,
//               setsDns, routes }]:
//                 id        1–64 of letters, digits, . _ ~ - ; unique within the provider;
//                           STABLE for the same VPN (it is stored in settings)
//                 name      text shown for it
//                 state     "activating" | "activated" | "deactivating" | "" (off) — the
//                           vocabulary of NetworkManager's VPNs
//                 attention null, or { reason, action }: a LASTING state that needs the user
//                           (log in, waiting for approval, key expired, service not running,
//                           become operator) — `reason` one plain sentence, `action` a short
//                           button label ("" for none). The core shows the line and the
//                           button, calls attend(id) for it, never connects an entry that has
//                           one ("VPN with a network" holds it down instead of retrying), and
//                           offers the action in place of Connect while it is not active.
//                           NEVER for a transient state ("starting", "reconnecting": that is
//                           `state` and `status`). The core waits out attention within 20 s
//                           of asking (VpnWithNetworkRules.vpnAttentionGraceMs), but attention
//                           reached from up is held down at once.
//                 detail    { server, servers [], iface, interfaceName, addresses [], dns [] }
//                           — the shape of VpnManager.details for NetworkManager's VPNs (see
//                           NetworkRules.vpnDetails); all optional. `iface` is the interface
//                           while up (cards' speed and data, the overview's VPN devices).
//                 active    optional bool, default: state !== ""
//                 status    optional text, ≤ 80 chars, default "": one short line the popup
//                           row and the card show beside the state ("Tailnet only", "Via
//                           <exit node>", "Starting…")
//                 busy      optional bool, default false: an operation runs for this entry —
//                           its buttons wait (as for the provider-wide `busy`)
//                 fullTunnel, setsDns   optional true | false | null (module API 1.16): it
//                           takes the default route; it brings DNS servers of its own while
//                           up. Absent or wrong is null — unknown, never "false"
//                 routes    optional list of networks or null (1.16): what it carries
//                           ("100.64.0.0/10", "0.0.0.0/0" for all); written canonically, a
//                           wrong one left out and logged; more than 256 networks: null
//                           (unknown), logged. These three are Api.vpnsUp's for
//                           the entry while it is up, and the other VPNs' `otherVpns`
//               A provider keeps reporting its entry in EVERY state — logged out, stopped,
//               daemon unreadable: the entry with `attention` — never an empty list for
//               "don't know". An entry it does not report is shown nowhere and, in "VPN with
//               a network", is "not available": kept, never removed by the shell.
//   ready       bool — the entries have been read successfully at least once (informative:
//               nothing is deleted on its word)
//   busy        bool — an operation runs: every entry's buttons wait (as
//               NetworkProfiles.connecting); per entry: the entry's `busy`
//   canChange   bool — false: changes ask for an administrator (pkexec): buttons carry the
//               privileged mark
//   lockdownNote string — what to say about the shell's "block traffic outside a VPN"
//               ("" for the shell's own sentence): on the VPN page's card whenever blocking
//               is on, in the popup's row while the VPN is up or coming up. The blocking does
//               not support provider VPNs (tailscale.md §8).
//   rowExtras   Component or null — under the entry's row in the network popup, for a
//               provider that is no module's (a module puts its elements there through the
//               place popup.network.connections.vpn.row, own-provider; its old slot
//               "network.vpn.row" is read as it)
//   cardExtras  Component or null — on the entry's card in Settings → System → Network →
//               VPN, while the card is open, for a provider that is no module's (a module's:
//               settings.network_vpn.vpns.card.settings; its old slot "network.vpn.card")
//   settingsPage string ("" none) — the id of the provider's own page among the settings
//               window's pages (a module: the id its manifest's `settingsPages` declares,
//               "<module id>" or "<module id>.<name>", as Api.openSettings takes it). The
//               card's "Settings…" then goes to that page (Shell.openSettings: the page list
//               selects it); no framed copy opens. While the window has no such page (a
//               wrong id, the page dropped) the core falls back to pageUrl / the page slot.
//   pageUrl     string ("" none) — slot "network.vpn.page": the fallback for a provider with
//               a page but no entry in the settings window's list — opened over the VPN page
//               from the entry's card ("Settings…"), inside the core's frame: "‹ Back", a
//               title (type · entry name) and scrolling are the core's — the page is a plain
//               Item (a ColumnLayout) laid out at the page's width, scrolled by its
//               implicitHeight; it must not scroll itself. Unused while settingsPage is
//               there. Neither: no "Settings…".
//   A contribution's root item may declare `property var context`; the core sets it to
//   { vpnId, entryId, vpn, provider, otherVpnsUp, otherVpns } — `provider` this object, to
//   call its functions and read its state; `otherVpnsUp` the other VPNs up by name,
//   `otherVpns` as Api.vpnsUp's rows — (the card's adds `open`; a module's element adds
//   `anchor` and `placement`, through an old slot `slot`; the page's adds `slot` and `close`,
//   a function that goes back to the VPN page), and again only when its value changes. See
//   VpnManager.othersUp, VpnManager.contextFor.
//
// The core calls (always with an entry id the provider reported; inside a guard — a throw
// is logged, not passed on):
//   connect(entryId, request), disconnect(entryId, request) — `request` { origin }:
//               "user" — a button: the provider may prompt (pkexec) and open a browser
//                        (log in);
//               "network" — "VPN with a network" (a network came up or went): it must NEVER
//                        prompt and NEVER open a browser — when it cannot go on without the
//                        user it sets the entry's `attention` instead, and the core holds the
//                        entry down (no retry) until the networks change.
//               An unknown origin is to be taken as "network" by a provider (the cautious
//               reading); the core only ever sends these two.
//   attend(entryId) — always the user's doing (a button): may prompt, may open a browser
//
// The provider emits:
//   failed(entryId, what, reason) — an operation failed: a one-off notification
//               "<what> failed" with `reason` as its body, as NetworkManager's failures are.
//               NOT for a privileged prompt the user dismissed: pkexec exits 126 when the
//               prompt was dismissed or the password refused — show nothing, emit nothing,
//               put the entry's state back to "" (and clear `busy`); 127 means no
//               authentication agent answered — emit failed(entryId, what, "No
//               authentication agent answered.") (as singletons/network/VpnLockdown.qml).
QtObject {
    id: root

    property string providerId: ""
    property string kind: "vpn"
    property string typeName: "VPN"
    property string glyph: ""
    property var entries: []
    property bool ready: false
    property bool busy: false
    property bool canChange: true
    property string lockdownNote: ""
    property Component rowExtras: null
    property Component cardExtras: null
    property string settingsPage: ""
    property string pageUrl: ""

    signal failed(string entryId, string what, string reason)

    function connect(entryId, request) {
    }

    function disconnect(entryId, request) {
    }

    function attend(entryId) {
    }

    // Registers with VpnManager unless told not to (a test that registers by hand)
    property bool autoRegister: true
    // Whether VpnManager took it (a taken or bad id: refused)
    readonly property bool registered: _registered
    property bool _registered: false

    Component.onCompleted: {
        if (autoRegister)
            _registered = VpnManager.registerProvider(root);
    }
    Component.onDestruction: {
        if (_registered)
            VpnManager.unregisterProvider(providerId, root);
    }
}
