import Quickshell
import QtQuick

// Lazily-loaded popup panel that appears below a triggering element.
// Matches the width and horizontal position of the element that triggered it.
LazyLoader {
    id: popupLoader
    active: false

    // Horizontal offset and width inherited from the triggering element
    required property int popupPosition
    required property int popupWidth
    // Emitted when the popup becomes visible, used for cross-screen coordination
    signal opened

    // Toggle popup for the given element.
    // If the same element triggers again, toggle or apply explicit state.
    // If a different element triggers, reposition and open.
    function toggle(element, state = null) {
        if (element.x == popupLoader.popupPosition) {
            if (state !== null) {
                popupLoader.active = state;
            } else {
                popupLoader.active = !popupLoader.active;
            }
        } else {
            popupLoader.popupPosition = element.x;
            popupLoader.popupWidth = element.width;
            popupLoader.active = true;
        }
        if (popupLoader.active) {
            popupLoader.opened();
        }
    }

    // Popup window positioned at the top-left, offset by popupPosition
    PanelWindow {
        id: popup

        anchors {
            top: true
            left: true
        }

        implicitWidth: rect.width
        implicitHeight: rect.height

        margins.top: 0
        margins.left: popupLoader.popupPosition
        color: "transparent"

        Rectangle {
            id: rect
            anchors.fill: parent
            implicitWidth: popupLoader.popupWidth
            height: 400
            color: '#4b4b4b'

            // Close the popup when the mouse leaves its area
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true

                onExited: popupLoader.active = false
            }
        }
    }
}
