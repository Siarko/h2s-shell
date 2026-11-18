import QtQuick
import qs.api

// The fixture's main: a VPN provider (providerId = the module's id) that names its module's
// settings page as its own (settingsPage) — the shape of the Tailscale module. It goes with
// the main when the module is turned off.
QtObject {
    id: main

    property var module: null

    property VpnProvider provider: VpnProvider {
        providerId: main.module?.moduleId ?? ""
        typeName: "Page VPN"
        glyph: "󰖂"
        ready: true
        settingsPage: "vpn-page"
        entries: [{ id: "one", name: "Page VPN one", state: "", attention: null, detail: {} }]
    }
}
