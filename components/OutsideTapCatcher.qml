import QtQuick
import Quickshell
import Quickshell.Wayland

// A transparent layer over a screen that catches taps outside a popup opened by touch —
// holes where the popup and the bar are, so taps there reach them. Replaces Hyprland's
// focus grab, which an on-screen keyboard's panel (another program's window) always broke,
// and which handed the keyboard round by the mouse cursor (docs/plans/touch.md).
//
// No keyboard interactivity, and on the "top" layer: an on-screen keyboard (layer
// "overlay") lies above it, so typing on it never reaches here; and with the mouse cursor
// over it, a layer appearing (the keyboard's panel) gives Hyprland nothing to hand the
// keyboard to. A tap here does not reach the window beneath, as on Android.
PanelWindow {
    id: root

    // Holes, in the screen's logical pixels
    property rect popupHole: Qt.rect(0, 0, 0, 0)
    property rect barHole: Qt.rect(0, 0, 0, 0)

    signal tapped

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "h2s-outside-tap"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        item: _area
        Region {
            x: root.popupHole.x
            y: root.popupHole.y
            width: root.popupHole.width
            height: root.popupHole.height
            intersection: Intersection.Subtract
        }
        Region {
            x: root.barHole.x
            y: root.barHole.y
            width: root.barHole.width
            height: root.barHole.height
            intersection: Intersection.Subtract
        }
    }

    MouseArea {
        id: _area
        anchors.fill: parent
        onPressed: root.tapped()
    }
}
