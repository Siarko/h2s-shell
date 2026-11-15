import QtQuick
import QtQuick.Layouts
import qs.api

// The fixture's settings page (System → Network), the provider's own page
ColumnLayout {
    objectName: "vpnSettingsPage"
    property var module: null
    Hint {
        text: "Page VPN settings by " + (parent.module?.moduleId ?? "?")
    }
}
