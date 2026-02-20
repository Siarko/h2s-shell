import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.hud
import qs.singletons

// Generic full-screen overlay for transient HUD components (toasts, OSD, etc.).
// Transparent and click-through everywhere except active HUD cards.
PanelWindow {
    id: hud
    required property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "hud"

    anchors {
        top: true
        left: true
    }
    implicitWidth: hud.screen.width
    implicitHeight: hud.screen.height
    margins { top: 0; left: 0 }
    color: "transparent"

    // Input passthrough: only forward clicks to visible HUD card areas.
    // notifItem.x starts at screenWidth (off-screen) so the region covers nothing
    // until the toast slides in, at which point it covers the card exactly.
    mask: Region {
        item: notifItem
    }

    NotificationHudItem {
        id: notifItem
        screenWidth: hud.implicitWidth
        screenModelData: hud.modelData
    }
}
