import QtQuick
import QtQuick.Layouts
import qs.api

// The fixture's provider page (network.vpn.page): a plain column in the core's frame; it
// declares `module`, so the frame hands it the module's handle
ColumnLayout {
    objectName: "vpnSlotsPage"
    property var module: null
    property var context: null
    Hint {
        text: "Page of " + (parent.context?.vpnId ?? "?") + " by " + (parent.module?.moduleId ?? "?")
    }
}
