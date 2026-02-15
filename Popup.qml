import Quickshell
import Quickshell.Wayland
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

    // True while the close animation is running; prevents immediate destruction
    property bool closing: false
    // When true, the popup stays open until explicitly toggled (click-to-close)
    property bool persistent: false
    // Which content to display in the popup ("calendar" or "power")
    property string contentType: "calendar"

    // Start the close animation instead of immediately deactivating
    function close() {
        if (popupLoader.active && !popupLoader.closing) {
            popupLoader.closing = true;
        }
    }

    // Open the popup aligned to the given element
    function open(element, persistent = false, contentType = "calendar") {
        popupLoader.persistent = persistent;
        popupLoader.contentType = contentType;
        popupLoader.popupPosition = element.x;
        popupLoader.popupWidth = element.width;
        popupLoader.closing = false;
        popupLoader.active = true;
        popupLoader.opened();
    }

    // Popup window positioned at the top-left, offset by popupPosition
    PanelWindow {
        id: popup
        WlrLayershell.namespace: "bar"

        anchors {
            top: true
            left: true
        }

        property int panelRadius: 20
        property int paddingSide: 10
        property int paddingTop: 10
        property int paddingBottom: 10
        property int contentWidth: contentLoader.item ? contentLoader.item.implicitWidth : 0
        property int contentHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0
        property int popupHeight: contentHeight + paddingTop + paddingBottom
        property bool roundingLeft: margins.left > 0
        property bool roundingRight: margins.left < popup.screen.width - popup.implicitWidth

        implicitWidth: contentWidth + (paddingSide * 2) + panelRadius * 2
        implicitHeight: popupHeight

        property bool showPopup: false
        Component.onCompleted: popup.showPopup = true

        margins.top: 0
        margins.left: {
            var raw = popupLoader.popupPosition - panelRadius + 5;
            var maxLeft = popup.screen.width - popup.implicitWidth;
            return Math.max(0, Math.min(raw, maxLeft));
        }
        color: "transparent"

        Behavior on margins.left {
            enabled: popup.showPopup
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutQuad
            }
        }

        // Clip wrapper — animates height without resizing the Wayland surface
        Item {
            id: clipWrapper
            anchors.top: parent.top
            width: parent.width
            height: popup.showPopup && !popupLoader.closing ? popup.popupHeight : 0
            clip: true

            Behavior on height {
                NumberAnimation {
                    duration: 100
                    easing.type: popupLoader.closing ? Easing.InQuad : Easing.OutQuad
                    onRunningChanged: {
                        if (!running && popupLoader.closing) {
                            popupLoader.closing = false;
                            popupLoader.active = false;
                        }
                    }
                }
            }

            Rectangle {
                id: rect
                width: parent.width
                height: popup.popupHeight
                color: "transparent"

                PopupCurve {
                    id: leftCurve
                    side: "left"
                    radius: popup.panelRadius
                    anchors.top: parent.top
                    anchors.left: parent.left
                    visible: popup.roundingLeft
                }

                PopupCurve {
                    id: rightCurve
                    side: "right"
                    radius: popup.panelRadius
                    anchors.top: parent.top
                    anchors.right: parent.right
                    visible: popup.roundingRight
                }

                Rectangle {
                    id: content
                    anchors.top: parent.top
                    anchors.left: popup.roundingLeft ? leftCurve.right : parent.left
                    anchors.right: popup.roundingRight ? rightCurve.left : parent.right
                    implicitHeight: popup.popupHeight

                    bottomLeftRadius: popup.roundingLeft ? popup.panelRadius : 0
                    bottomRightRadius: popup.roundingRight ? popup.panelRadius : 0

                    color: Theme.popupBackground

                    Loader {
                        id: contentLoader
                        anchors.centerIn: parent
                        sourceComponent: popupLoader.contentType === "power" ? powerMenuComponent : popupLoader.contentType === "notifications" ? notificationsComponent : calendarComponent
                    }

                    Component {
                        id: calendarComponent
                        Calendar {}
                    }

                    Component {
                        id: powerMenuComponent
                        PowerMenu {}
                    }

                    Component {
                        id: notificationsComponent
                        NotificationPanel {
                            screenHeight: popup.screen.height
                        }
                    }
                }
            }

            // Close the popup when the mouse leaves the visible area
            HoverHandler {
                onHoveredChanged: {
                    if (!hovered && !popupLoader.persistent)
                        popupLoader.close();
                }
            }
        }
    }
}
