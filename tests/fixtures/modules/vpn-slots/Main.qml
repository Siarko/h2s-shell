import QtQuick
import qs.api
import qs.components

// The fixture's main: a VPN provider whose providerId is the module's id (the convention of
// module API 1.1), from qs.components — so its three VPN slots come from the manifest, not
// from rowExtras / cardExtras / pageUrl. It goes with the main when the module is turned off.
QtObject {
    id: main

    property var module: null

    property VpnProvider provider: VpnProvider {
        providerId: main.module?.moduleId ?? ""
        typeName: "Slot VPN"
        glyph: "󰖂"
        ready: true
        entries: [{ id: "one", name: "Slot VPN one", state: "", attention: null, detail: {} }]
    }
}
