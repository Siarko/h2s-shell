import QtQuick
import qs.api

// The fixture's main: a VPN provider whose providerId is the module's id, with entries the
// suite sets (`provider.entries`), and a count of its elements that stand now, by
// "<file>|<anchor>|<vpnId>" (`live`, made and gone tell it) — so the suite sees each element
// follow its VPN and go with it
QtObject {
    id: main

    property var module: null
    property var live: ({})

    function made(key) {
        const counts = Object.assign({}, live);
        counts[key] = (counts[key] ?? 0) + 1;
        live = counts;
    }

    function gone(key) {
        const counts = Object.assign({}, live);
        counts[key] = (counts[key] ?? 0) - 1;
        if (counts[key] <= 0)
            delete counts[key];
        live = counts;
    }

    property VpnProvider provider: VpnProvider {
        providerId: main.module?.moduleId ?? ""
        typeName: "Fixture VPN B"
        glyph: "󰖂"
        ready: true
        entries: []
    }
}
