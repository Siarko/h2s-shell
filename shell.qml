import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Variants {
    model: Quickshell.screens

    delegate: Component {
        PanelWindow {
            id: bar
            required property var modelData

            screen: modelData
            property int popupPosition

            anchors {
                top: true
                left: true
                right: true
            }
            color: "#4b4b4b"

            implicitHeight: 40

            FlexboxLayout {
                id: flexLayout

                anchors.fill: parent

                wrap: FlexboxLayout.NoWrap
                direction: FlexboxLayout.Row
                justifyContent: FlexboxLayout.JustifySpaceAround
                alignItems: FlexboxLayout.AlignCenter
                gap: 5

                Text {
                    id: helloText
                    text: Time.time
                    font.pixelSize: 20
                    color: "white"

                    // Layout.rightMargin: 20
                    Layout.leftMargin: 20
                }

                Cell {
                    cellColor: "#3b3b3b"
                    onPlonked: c => popupLoader.toggle(this)
                    onHover: s => {
                        if (s) {
                            popupLoader.toggle(this);
                        }
                    }
                }
                Cell {
                    cellColor: "#3b3b3b"
                    onPlonked: c => popupLoader.toggle(this)
                }
                Cell {
                    cellColor: "green"
                    onPlonked: c => popupLoader.toggle(this)
                }
                Cell {
                    cellColor: "#3b3b3b"
                    onPlonked: c => popupLoader.toggle(this)
                }
            }

            LazyLoader {
                id: popupLoader
                active: false

                function toggle(element, state = null) {
                    if (element.x == bar.popupPosition) {
                        if (state !== null) {
                            popupLoader.active = state;
                        } else {
                            popupLoader.active = !popupLoader.active;
                        }
                    } else {
                        bar.popupPosition = element.x;
                        popupLoader.active = true;
                    }
                }
                PanelWindow {
                    id: popup

                    anchors {
                        top: true
                        left: true
                    }

                    implicitWidth: rect.width
                    implicitHeight: rect.height

                    margins.top: 0
                    margins.left: bar.popupPosition
                    color: "transparent"

                    Rectangle {
                        id: rect
                        anchors.fill: parent
                        implicitWidth: 500
                        height: 400
                        color: '#4b4b4b'

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true

                            onExited: popupLoader.active = false
                        }
                    }
                }
            }
        }
    }
}
