import QtQuick
import qs.api

// The fixture's main: a VPN provider with its module id, which is the id the shell keeps for
// its stand-in provider — refused, the reason in this module's status.
QtObject {
    id: main

    property var module: null

    property VpnProvider provider: VpnProvider {
        providerId: main.module?.moduleId ?? ""
        typeName: "Reserved VPN"
        ready: true
        entries: [{ id: "one", name: "Reserved one", state: "", attention: null, detail: {} }]
    }
}
