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

            onScrolled: delta => {
                if (Audio.sink?.audio) {
                    const amount = Audio.sink.audio.volume + delta * 0.01;
                    Audio.sink.audio.volume = Math.max(0, amount);
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    text: Audio.volume + "%"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    color: Audio.muted ? Theme.textDim : Audio.volume > 100 ? Theme.textWarning : Theme.textPrimary
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: Audio.muted ? "󰖁" : "󰕾"
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    color: Audio.muted ? Theme.textDim : Theme.textPrimary
                    anchors.verticalCenter: parent.verticalCenter
                }
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
