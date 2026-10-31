import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons
import qs.singletons.network

// A network in the Wi-Fi list: signal, name, band and security; clicked, it opens a row
// to connect — with a password field for a secured network not yet saved — or to forget
// a saved one.
//
// Whether it is open, its password and whether that shows are the panel's, kept under
// the network's SSID, and come in through `expanded`, `passwordText` and `showPassword`:
// a delegate is reused for another network when the list is rebuilt (each scan, a
// connection), and state kept here moved to whichever network took its place.
Rectangle {
    id: root

    required property var modelData
    required property int index

    property bool expanded: false
    property string passwordText: ""
    property bool showPassword: false

    // The header clicked: open or close this row
    signal toggleRequested
    signal passwordEdited(string text)
    signal revealToggled

    readonly property string ssid: modelData.ssid
    // The field follows the password kept for this row's network: when the row is given
    // another network, it shows that one's. Not on ssidChanged — that can run before
    // passwordText has followed the new SSID, and put the old network's password in the
    // new one's field, so a typed password stayed with the place in the list.
    onPasswordTextChanged: if (pwInput.text !== passwordText) pwInput.text = passwordText
    readonly property bool isSaved: WifiManager.savedSsids.includes(modelData.ssid)
    readonly property bool needsPassword: modelData.security !== "--" && modelData.security !== "" && !isSaved

    function _signalColor(signal) {
        if (signal >= 75) return Theme.accent
        if (signal >= 50) return Theme.warning
        if (signal >= 25) return Theme.textMuted
        return Theme.textDisabled
    }

    // The info row, and with it the action row when open: as tall as they are
    height: expanded ? _networkColumn.implicitHeight : _infoRow.height
    radius: Theme.row.radius
    color: modelData.inUse ? Theme.accentTint : Theme.surface
    clip: true

    Behavior on height {
        NumberAnimation { duration: Theme.duration("expand"); easing: Theme.curve("expand") }
    }

    Column {
        id: _networkColumn
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: Theme.row.horizontalPadding
            rightMargin: Theme.row.horizontalPadding
        }
        spacing: 4

        // Main info row — always click to expand
        Item {
            id: _infoRow
            width: parent.width
            height: Math.max(36, _infoContent.implicitHeight + 8)

            RowLayout {
                id: _infoContent
                anchors.fill: parent
                spacing: 6

                Rectangle {
                    width: 8
                    height: 8
                    radius: width / 2
                    Layout.alignment: Qt.AlignVCenter
                    color: root._signalColor(root.modelData.signal)
                }

                Text {
                    text: root.modelData.ssid
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBodyLarge
                    color: root.modelData.inUse ? Theme.accent : Theme.textPrimary
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                SignalBars {
                    strength: root.modelData.signal
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textSecondary
                }

                Text {
                    visible: root.modelData.band !== "" && root.modelData.band !== undefined
                    text: root.modelData.band ?? ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXSmall
                    color: (root.modelData.band === "5G") ? Theme.accent : Theme.textMuted
                }

                Text {
                    visible: root.modelData.security !== "--" && root.modelData.security !== ""
                    text: root.modelData.security !== "--" ? root.modelData.security : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXSmall
                    color: Theme.textMuted
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleRequested()
            }
        }

        // Action row (revealed when expanded)
        Item {
            width: parent.width
            height: Math.max(36, _actionContent.implicitHeight + 8)

            RowLayout {
                id: _actionContent
                anchors.fill: parent
                spacing: 6

                // Password field — only for unsaved secured networks
                InputField {
                    id: pwInput
                    visible: root.needsPassword
                    Layout.fillWidth: true
                    fieldColor: Theme.popupBackground
                    outlined: true
                    placeholder: "Password"
                    password: true
                    // Shown or not per network, kept by the panel (see above)
                    ownsReveal: false
                    revealed: root.showPassword
                    onRevealToggled: root.revealToggled()
                    onTextEdited: root.passwordEdited(text)
                }

                // Spacer for saved/open networks (no password field)
                Item {
                    visible: !root.needsPassword
                    Layout.fillWidth: true
                }

                // Error label for wrong password
                Text {
                    visible: WifiManager.connectFailed && WifiManager.failedSsid === root.modelData.ssid
                    text: "Wrong password"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.warning
                    Layout.alignment: Qt.AlignVCenter
                }

                // Connect / Cancel button
                SmallButton {
                    visible: !root.modelData.inUse
                    readonly property bool _busy: WifiManager.connecting && WifiManager.connectingTo === root.modelData.ssid
                    label: _busy ? "Cancel" : "Connect"
                    kind: _busy ? "cancel" : "save"
                    onClicked: {
                        if (_busy)
                            WifiManager.cancelConnect()
                        else
                            WifiManager.connectToWifi(root.modelData.ssid, root.needsPassword ? root.passwordText : "")
                    }
                }

                // Forget button — only for saved networks
                // Asks first, like every delete (DeleteButton)
                DeleteButton {
                    visible: root.isSaved
                    label: "Forget"
                    confirmLabel: "Forget?"
                    fontSize: Theme.fontSizeBody
                    cancelTip: "Keep the network"
                    onConfirmed: WifiManager.forgetNetwork(root.modelData.ssid)
                }
            }
        }
    }
}
