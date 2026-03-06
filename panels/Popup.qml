import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.components
import qs.singletons

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
        const mapped = element.mapToItem(null, 0, 0);
        popupLoader.popupPosition = mapped.x;
        popupLoader.popupWidth = element.width;
        popupLoader.closing = false;
        popupLoader.active = true;
        popupLoader.opened();
    }

    // Popup window positioned at the top-left, offset by popupPosition
    PanelWindow {
        id: popup

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
        property int totalWidth: contentWidth + (paddingSide * 2) + panelRadius * 2
        property bool roundingLeft: clipWrapper.x > 0
        property bool roundingRight: clipWrapper.x < popup.screen.width - popup.totalWidth

        implicitWidth: popup.screen.width
        implicitHeight: popup.screen.height

        property bool showPopup: false
        Component.onCompleted: popup.showPopup = true

        focusable: hoverHandler.hovered

        margins.top: 0
        margins.left: 0
        color: "transparent"

        mask: Region {
            item: clipWrapper
        }

        // Clip wrapper — animates height; the window itself never resizes
        Item {
            id: clipWrapper
            x: {
                var raw = popupLoader.popupPosition + (popupLoader.popupWidth / 2) - (popup.totalWidth / 2);
                var maxLeft = popup.screen.width - popup.totalWidth;
                return Math.max(0, Math.min(raw, maxLeft));
            }
            width: popup.totalWidth
            height: popup.showPopup && !popupLoader.closing ? popup.popupHeight : 0
            clip: true

            Behavior on x {
                enabled: popup.showPopup
                NumberAnimation {
                    duration: 100
                    easing.type: Easing.OutQuad
                }
            }

            Behavior on height {
                enabled: true
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
                width: popup.totalWidth
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

                    readonly property var _componentMap: ({
                            "tray-menu": trayMenuComponent,
                            "power": powerMenuComponent,
                            "notifications": notificationsComponent,
                            "sound": soundComponent,
                            "music": musicComponent,
                            "bluetooth": bluetoothComponent,
                            "calendar": calendarComponent,
                            "network": networkComponent
                        })

                    Loader {
                        id: contentLoader
                        anchors.centerIn: parent
                        sourceComponent: content._componentMap[popupLoader.contentType] ?? calendarComponent
                    }

                    Component {
                        id: trayMenuComponent
                        TrayMenu {
                            onCloseRequested: popupLoader.close()
                        }
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
                            onCloseRequested: popupLoader.close()
                        }
                    }

                    Component {
                        id: soundComponent
                        SoundPanel {}
                    }

                    Component {
                        id: musicComponent
                        MusicPanel {}
                    }

                    Component {
                        id: bluetoothComponent
                        BluetoothPanel {}
                    }

                    Component {
                        id: networkComponent
                        NetworkPanel {}
                    }
                }
            }

            // Close the popup when the mouse leaves the visible area
            HoverHandler {
                id: hoverHandler
                onHoveredChanged: {
                    if (!hovered && !popupLoader.persistent)
                        popupLoader.close();
                }
            }
        }
    }
}
