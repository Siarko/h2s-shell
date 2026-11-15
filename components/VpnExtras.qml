import QtQuick
import qs.singletons.network

// A VPN provider's contribution to one of the VPN slots (VpnManager.slots: the popup row's,
// the card's), made inside a Loader — one that fails to build shows nothing and breaks
// nothing. Its root item gets `context` (VpnManager.contextFor: { slot, vpnId, entryId, vpn,
// provider } and `extra`) when it declares that property — passed again only when it says
// something new (NetworkRules.sameVpnContext), so a provider re-read that changed another
// entry does not poke this one. Where the component comes from is VpnManager.extrasFor's
// business: the provider's own property today, the module host's slot registry later.
Loader {
    id: root

    property string slot: ""
    // The VPN (VpnManager.vpns' entry)
    property var vpn: null
    // More context for this slot ({ open } on the card)
    property var extra: ({})

    readonly property var context: VpnManager.contextFor(slot, vpn, extra)

    // Looked up once per change of what it depends on; `active` follows this property, not
    // `sourceComponent` (bound to that, it was reported as a binding loop)
    readonly property Component _component: VpnManager.extrasFor(slot, vpn)
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
