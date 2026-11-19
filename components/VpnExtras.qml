import QtQuick
import qs.singletons.network

// A VPN provider's own Component under a VPN's row in the network popup (`place` "row") or on
// its card (`place` "card": VpnManager.ownExtrasOf — the provider's rowExtras / cardExtras, a
// provider that is no module's), made inside a Loader — one that fails to build shows nothing
// and breaks nothing. A module's elements come through the anchor hosts of the row and the
// card instead. Its root item gets `context` (the VPN's, as the view's block gives it: {
// vpnId, entryId, vpn, provider, otherVpnsUp, otherVpns }, with `extra` — { open } on the
// card) when it declares that property — passed again only when it says something new
// (NetworkRules.sameVpnContext), so a provider re-read that changed another entry does not
// poke this one.
Loader {
    id: root

    property string place: ""
    // The VPN (VpnManager.vpns' entry)
    property var vpn: null
    // The VPN's context, as its block gives it to the anchor hosts
    property var vpnContext: ({})
    // More context for this place ({ open } on the card)
    property var extra: ({})

    readonly property var context: Object.assign({}, vpnContext ?? {}, extra ?? {})

    // Looked up once per change of what it depends on; `active` follows this property, not
    // `sourceComponent` (bound to that, it was reported as a binding loop)
    readonly property Component _component: VpnManager.ownExtrasOf(place, vpn)
    sourceComponent: _component
    active: _component !== null
    visible: status === Loader.Ready && item !== null

    // What the item was last given
    property var _passed: null

    onLoaded: {
        _passed = null;
        _pass();
    }
    onContextChanged: _pass()

    function _pass() {
        if (item === null || NetworkRules.sameVpnContext(_passed, context))
            return;
        try {
            if ("context" in item) {
                item.context = context;
                _passed = context;
            }
        } catch (error) {
            // No such property: it takes no context
        }
    }
}
