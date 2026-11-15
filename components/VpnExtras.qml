import QtQuick
import qs.singletons.network

// A VPN provider's contribution to one of the VPN slots (VpnManager.slots: the popup row's,
// the card's), made inside a Loader — one that fails to build shows nothing and breaks
// nothing. Its root item gets `context` ({ slot, vpnId, entryId, vpn } and `extra`) when it
// declares that property. Where the component comes from is VpnManager.extrasFor's
// business: the provider's own property today, the module host's slot registry later.
Loader {
    id: root

    property string slot: ""
    // The VPN (VpnManager.vpns' entry)
    property var vpn: null
    // More context for this slot ({ open } on the card)
    property var extra: ({})

    readonly property var context: Object.assign({ slot: slot, vpnId: vpn?.uuid ?? "", entryId: vpn?.entryId ?? "", vpn: vpn }, extra)

    sourceComponent: VpnManager.extrasFor(slot, vpn)
    active: sourceComponent !== null
    visible: status === Loader.Ready && item !== null

    onLoaded: _pass()
    onContextChanged: _pass()

    function _pass() {
        if (item === null)
            return;
        try {
            if ("context" in item)
                item.context = context;
        } catch (error) {
            // No such property: it takes no context
        }
    }
}
