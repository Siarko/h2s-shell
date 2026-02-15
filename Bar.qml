import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.components
import qs.panels
import qs.singletons

// Top-anchored horizontal bar spanning the full screen width
PanelWindow {
    id: bar
    required property var modelData
    property var activeScreen: null
    signal popupOpened

    screen: modelData

    // Close this screen's popup when another screen's popup opens
    onActiveScreenChanged: {
        if (activeScreen !== bar.modelData) {
            popupLoader.close();
        }
    }

    anchors {
        top: true
        left: true
        right: true
    }
    color: Theme.barBackground

    implicitHeight: 40

    // Main horizontal layout distributing children evenly
    FlexboxLayout {
        id: flexLayout

        anchors.fill: parent
        anchors.leftMargin: 5
        anchors.rightMargin: 5

        wrap: FlexboxLayout.NoWrap
        direction: FlexboxLayout.Row
        justifyContent: FlexboxLayout.JustifySpaceAround
        alignItems: FlexboxLayout.AlignCenter
        gap: 5

        // Interactive cells — hovering opens a popup aligned to the cell
        Cell {
            cellColor: Theme.cellDefault
            Layout.preferredWidth: 30
            onHover: s => {
                if (s) {
                    popupLoader.open(this, false, "power");
                }
            }

            Text {
                text: "⏻"
                font.family: Theme.fontFamily
                font.pixelSize: 20
                color: Theme.textPrimary
                anchors.centerIn: parent
            }
        }
        Cell {
            cellColor: Theme.cellDefault
            onHover: s => {
                if (s) {
                    popupLoader.open(this, false, "calendar");
                }
            }
        }
        Cell {
            cellColor: Theme.cellAccent
            onPlonked: {
                popupLoader.open(this, false, "calendar");
            }
        }

        Cell {
            cellColor: Theme.cellDefault
            onHover: s => {
                if (s) {
                    popupLoader.open(this);
                }
            }

            Text {
                text: Time.time
                font.family: Theme.fontFamily
                font.pixelSize: 20
                color: Theme.textPrimary
                anchors.centerIn: parent
            }
        }

        Cell {
            cellColor: Theme.cellMuted
            Layout.preferredWidth: 20
            onPlonked: {
                if (popupLoader.active && popupLoader.contentType === "notifications") {
                    popupLoader.close();
                } else {
                    popupLoader.open(this, true, "notifications");
                }
            }

            Text {
                text: "󰂚"
                font.family: Theme.fontFamily
                color: Theme.textPrimary
                anchors.centerIn: parent
            }
        }
    }

    // Popup panel that appears below the hovered cell
    Popup {
        id: popupLoader
        popupPosition: 0
        popupWidth: 0
        // Notify parent so other screens close their popups
        onOpened: bar.popupOpened()
    }
}
