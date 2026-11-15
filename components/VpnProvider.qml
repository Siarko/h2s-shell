import QtQuick
import qs.singletons.network

// A VPN provider: VPNs that are not NetworkManager's — the first is the Tailscale module —
// listed, shown and switched by the shell beside NetworkManager's (VpnManager). The
// contract, as built, is in docs/plans/tailscale.md §3; this comment is its short form.
//
// A provider extends this type and declares it inside the module's own objects:
//
//     import qs.components
//     VpnProvider {
//         providerId: "tailscale"; typeName: "Tailscale"; glyph: "󰖂"
//         entries: [{ id: "default", name: "Tailscale · example.ts.net", state: "activated",
//                     attention: null, detail: { server: "…", iface: "tailscale0", addresses: [ … ] } }]
//         ready: true
//         function connect(entryId) { … }   function disconnect(entryId) { … }
//         function attend(entryId) { … }
//     }
//
// It registers itself with VpnManager when made and leaves when destroyed (a module
// disabled at run time). Everything it reports is checked (NetworkRules
// .vpnProviderEntries): a wrong entry is dropped and logged, never shown.
//
// The core reads (bindings: keep them as properties, change them by assignment):
//   providerId  string, constant — a lower-case letter, then up to 31 of a–z 0–9 - _ (no
//               colon). The core addresses an entry as "<providerId>:<entry id>", which no
//               NetworkManager UUID can be. A second provider with a taken id is refused.
//   kind        string — what sort of thing it is ("mesh", "vpn"); informative only
//   typeName    string — the VPN's type as the cards and the editor's picker show it
//   glyph       string — a Nerd Font glyph for its rows and, when only it is up, the bar
//   entries     [{ id, name, state, attention, detail, active }]:
//                 id        1–64 of letters, digits, . _ ~ - ; unique within the provider
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
//                 detail    { server, servers [], iface, interfaceName, addresses [], dns [] }
//                           — the shape of VpnManager.details for NetworkManager's VPNs (see
//                           NetworkRules.vpnDetails); all optional. `iface` is the interface
//                           while up (cards' speed and data, the overview's VPN devices).
//                 active    optional bool, default: state !== ""
//   ready       bool — the entries have been read at least once. Until then an entry missing
//               from them is not taken as gone (the setting "VPN with a network" keeps it);
//               once ready, an entry missing is gone for good and leaves that setting.
//   busy        bool — an operation runs: the buttons wait (as NetworkProfiles.connecting)
//   canChange   bool — false: changes ask for an administrator (pkexec): buttons carry the
//               privileged mark
//   lockdownNote string — what to say when the shell's "block traffic outside a VPN" is on
//               while this VPN is up or coming up ("" for the shell's own sentence). The
//               blocking does not support provider VPNs (tailscale.md §8).
//   rowExtras   Component or null — slot "network.vpn.row": under the entry's row in the
//               network popup (an exit-node chooser)
//   cardExtras  Component or null — slot "network.vpn.card": on the entry's card in
//               Settings → System → Network → VPN, while the card is open
//   pageUrl     string ("" none) — slot "network.vpn.page": a page of the provider's own,
//               opened over the VPN page from the entry's card ("Settings…")
//   A contribution's root item may declare `property var context`; the core sets it to
//   { slot, vpnId, entryId, vpn } (the card's adds `open`; the page's adds `close`, a
//   function that goes back to the VPN page). See VpnManager.slots.
//
// The core calls (always with an entry id the provider reported; inside a guard — a throw
// is logged, not passed on):
//   connect(entryId), disconnect(entryId), attend(entryId)
//
// The provider emits:
//   failed(entryId, what, reason) — an operation failed: a one-off notification
//               "<what> failed" with `reason` as its body, as NetworkManager's failures are.
//               Not for a password prompt the user cancelled.
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
    property string pageUrl: ""

    signal failed(string entryId, string what, string reason)

    function connect(entryId) {
    }

    function disconnect(entryId) {
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
