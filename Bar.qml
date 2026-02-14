import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

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
    color: "#4b4b4b"
    // color: 'black'

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
            cellColor: "#3b3b3b"
            Layout.preferredWidth: 30
            onHover: s => {
                if (s) {
                    popupLoader.open(this, false, "power");
                }
            }

            Text {
                text: "⏻"
                font.pixelSize: 20
                color: "white"
                anchors.centerIn: parent
            }
        }
        Cell {
            cellColor: "#3b3b3b"
            onHover: s => {
                if (s) {
                    popupLoader.open(this, false, "calendar");
                }
            }
        }
        Cell {
            cellColor: "green"
            onPlonked: {
                popupLoader.open(this, false, "calendar");
            }
        }
        Cell {
            cellColor: "gray"
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
                color: "white"
                anchors.centerIn: parent
            }
        }

        Cell {
            cellColor: "#3b3b3b"
            Layout.preferredWidth: 100
            onHover: s => {
                if (s) {
                    popupLoader.open(this);
                }
            }

            Text {
                text: Time.time
                font.pixelSize: 20
                color: "white"
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
