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
// they outlive the row (a network that drops out of range and comes back finds them).
Rectangle {
    id: root

    // The network shown (WifiManager.wifiNetworks), looked up by the list by SSID
    property var network: ({})

    property bool expanded: false
    property string passwordText: ""
    property bool showPassword: false

    // The header clicked: open or close this row
    signal toggleRequested
    signal passwordEdited(string text)
    signal revealToggled

    readonly property string ssid: root.network.ssid ?? ""
    // The field follows the password kept for this row's network
    onPasswordTextChanged: if (pwInput.text !== passwordText) pwInput.text = passwordText
    readonly property bool isSaved: WifiManager.savedSsids.includes(root.network.ssid)
    readonly property bool needsPassword: root.network.security !== "--" && root.network.security !== "" && !isSaved

    function _signalColor(signal) {
        if (signal >= 75) return Theme.accent
        if (signal >= 50) return Theme.warning
        if (signal >= 25) return Theme.textMuted
        return Theme.textDisabled
    }

    // The info row, and with it the action row when open: as tall as they are
    height: expanded ? _networkColumn.implicitHeight : _infoRow.height
    radius: Theme.row.radius
    color: root.network.inUse ? Theme.accentTint : Theme.surface
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
                    color: root._signalColor(root.network.signal)
                }

                Text {
                    text: root.network.ssid
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBodyLarge
                    color: root.network.inUse ? Theme.accent : Theme.textPrimary
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                SignalBars {
                    strength: root.network.signal
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textSecondary
                }

                Text {
                    visible: root.network.band !== "" && root.network.band !== undefined
                    text: root.network.band ?? ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXSmall
                    color: (root.network.band === "5G") ? Theme.accent : Theme.textMuted
                }

                Text {
                    visible: root.network.security !== "--" && root.network.security !== ""
                    text: root.network.security !== "--" ? root.network.security : ""
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

                // Why connecting failed, from nmcli's error (WifiManager.failedKind)
                Text {
                    visible: WifiManager.connectFailed && WifiManager.failedSsid === root.network.ssid
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: WifiManager.failedKind === "password" ? "Wrong password"
                        : WifiManager.failedKind === "notFound" ? "The network is out of range"
                        : WifiManager.failedKind === "auth" ? "Not allowed to connect"
                        : WifiManager.failedMessage !== "" ? WifiManager.failedMessage : "Could not connect"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.warning
                    Layout.alignment: Qt.AlignVCenter
                }

                // Connect / Cancel button
                SmallButton {
                    visible: !root.network.inUse
                    readonly property bool _busy: WifiManager.connecting && WifiManager.connectingTo === root.network.ssid
                    label: _busy ? "Cancel" : "Connect"
                    kind: _busy ? "cancel" : "save"
                    onClicked: {
                        if (_busy)
                            WifiManager.cancelConnect()
                        else
                            WifiManager.connectToWifi(root.network.ssid, root.needsPassword ? root.passwordText : "")
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
                    onConfirmed: WifiManager.forgetNetwork(root.network.ssid)
                }
            }
        }
    }
}
