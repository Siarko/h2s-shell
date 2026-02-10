import Quickshell
import QtQuick
import QtQuick.Shapes

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

        property int panelRadius: 20

        implicitWidth: rect.width
        implicitHeight: rect.height

        margins.top: 0
        margins.left: popupLoader.popupPosition - panelRadius
        color: "transparent"

        Rectangle {
            id: rect
            anchors.fill: parent
            implicitWidth: popupLoader.popupWidth + popup.panelRadius * 2
            height: 400
            color: 'transparent'

            Rectangle {
                id: leftCurve
                anchors.top: parent.top
                anchors.left: parent.left

                implicitWidth: popup.panelRadius
                implicitHeight: popup.panelRadius
                color: "transparent"

                Shape {
                    width: parent.width
                    height: parent.height
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: 0
                        fillColor: "#4d4d4d"

                        startX: 0
                        startY: 0

                        PathArc {
                            x: popup.panelRadius
                            y: popup.panelRadius
                            radiusX: popup.panelRadius
                            radiusY: popup.panelRadius
                            direction: PathArc.Clockwise
                        }
                        PathLine {
                            x: popup.panelRadius
                            y: 0
                        }
                    }
                }
            }

            Rectangle {
                id: rightCurve
                anchors.top: parent.top
                anchors.right: parent.right

                implicitWidth: popup.panelRadius
                implicitHeight: popup.panelRadius
                color: "transparent"

                Shape {
                    width: parent.width
                    height: parent.height
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: 0
                        fillColor: "#4d4d4d"

                        startX: 0
                        startY: popup.panelRadius

                        PathArc {
                            x: popup.panelRadius
                            y: 0
                            radiusX: popup.panelRadius
                            radiusY: popup.panelRadius
                            direction: PathArc.Clockwise
                        }
                        PathLine {
                            x: 0
                            y: 0
                        }
                        PathLine {
                            x: 0
                            y: popup.panelRadius
                        }
                    }
                }
            }

            Rectangle {
                id: content
                anchors.top: parent.top
                anchors.left: leftCurve.right
                anchors.right: rightCurve.left
                implicitHeight: rect.height

                bottomLeftRadius: popup.panelRadius
                bottomRightRadius: popup.panelRadius

                color: "#4d4d4d"
            }

            // Close the popup when the mouse leaves its area
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true

                onExited: popupLoader.active = false
            }
        }
    }
}
