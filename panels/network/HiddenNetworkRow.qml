import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons
import qs.singletons.network

// "Connect to hidden network": a header that opens fields for the network's name and
// password, and a Connect button.
Rectangle {
    id: root

    property bool expanded: false
    property string ssidText: ""
    property string passwordText: ""

    // The header, and with it the fields when open: as tall as they are (with a little
    // room below)
    height: expanded ? _hiddenColumn.implicitHeight + 6 : _hiddenHeader.height
    radius: Theme.row.radius
    color: "transparent"
    clip: true

    Behavior on height { NumberAnimation { duration: Theme.duration("expand"); easing: Theme.curve("expand") } }

    Column {
        id: _hiddenColumn
        width: parent.width
        spacing: 4

        // Header row
        Item {
            id: _hiddenHeader
            width: parent.width
            height: Math.max(30, _hiddenHeaderContent.implicitHeight + 6)

            RowLayout {
                id: _hiddenHeaderContent
                anchors.fill: parent
                spacing: 6

                Text {
                    text: "󰀆"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textMuted
                }

                Text {
                    text: "Connect to hidden network"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    text: root.expanded ? "󰅃" : "󰅀"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textMuted
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }
        }

        // SSID input
        InputField {
            width: parent.width
            fieldColor: Theme.popupBackground
            outlined: true
            placeholder: "Network name (SSID)"
            onTextEdited: root.ssidText = text
        }

        // Password + Connect row
        RowLayout {
            width: parent.width
            spacing: 6

            InputField {
                Layout.fillWidth: true
                fieldColor: Theme.popupBackground
                outlined: true
                placeholder: "Password (optional)"
                password: true
                onTextEdited: root.passwordText = text
            }

            SmallButton {
                label: "Connect"
                kind: "save"
                available: root.ssidText !== ""
                onClicked: WifiManager.connectToHiddenWifi(root.ssidText, root.passwordText)
            }
        }
    }
}
