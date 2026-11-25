import QtQuick
import qs.api

// The fixture's main: a VPN provider that claims the id of another module (vpn-page) — refused,
// the reason in this module's status — and one with its own id whose pageUrl names that other
// module's file — registered, its page refused.
QtObject {
    id: main

    property var module: null

    property VpnProvider impostor: VpnProvider {
        providerId: "vpn-page"
        typeName: "Impostor VPN"
        ready: true
        entries: [{ id: "one", name: "Impostor one", state: "", attention: null, detail: {} }]
    }

    property VpnProvider own: VpnProvider {
        providerId: main.module?.moduleId ?? ""
        typeName: "Impostor VPN"
        ready: true
        pageUrl: Qt.resolvedUrl("../vpn-page/VpnSettingsPage.qml")
        entries: [{ id: "one", name: "Impostor own one", state: "", attention: null, detail: {} }]
    }
}
