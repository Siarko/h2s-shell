import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// Creates a panel instance for each connected screen
Variants {
    id: root
    model: Quickshell.screens

    // Tracks which screen currently has an open popup, so others can close theirs
    property var activeScreen: null

    delegate: Component {
        // Top-anchored horizontal bar spanning the full screen width
        PanelWindow {
            id: bar
            required property var modelData

            screen: modelData

            // Close this screen's popup when another screen's popup opens
            Connections {
                target: root
                function onActiveScreenChanged() {
                    if (root.activeScreen !== bar.modelData) {
                        popupLoader.active = false;
                    }
                }
            }

            anchors {
                top: true
                left: true
                right: true
            }
            color: "#4b4b4b"

            implicitHeight: 40

            // Main horizontal layout distributing children evenly
            FlexboxLayout {
                id: flexLayout

                anchors.fill: parent

                wrap: FlexboxLayout.NoWrap
                direction: FlexboxLayout.Row
                justifyContent: FlexboxLayout.JustifySpaceAround
                alignItems: FlexboxLayout.AlignCenter
                gap: 5

                // Live clock display
                Text {
                    id: helloText
                    text: Time.time
                    font.pixelSize: 20
                    color: "white"

                    // Layout.rightMargin: 20
                    Layout.leftMargin: 20
                }

                // Interactive cells — hovering opens a popup aligned to the cell
                Cell {
                    cellColor: "#3b3b3b"
                    onHover: s => {
                        if (s) {
                            popupLoader.toggle(this, true);
                        }
                    }
                }
                Cell {
                    cellColor: "#3b3b3b"
                    onHover: s => {
                        if (s) {
                            popupLoader.toggle(this, true);
                        }
                    }
                }
                Cell {
                    cellColor: "green"
                    onHover: s => {
                        if (s) {
                            popupLoader.toggle(this, true);
                        }
                    }
                }
                Cell {
                    cellColor: "#3b3b3b"
                    onHover: s => {
                        if (s) {
                            popupLoader.toggle(this, true);
                        }
                    }
                }
            }

            // Popup panel that appears below the hovered cell
            Popup {
                id: popupLoader
                popupPosition: 0
                popupWidth: 0
                // Notify root so other screens close their popups
                onOpened: root.activeScreen = bar.modelData
            }
        }
    }
}
