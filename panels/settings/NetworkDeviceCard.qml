import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons
import qs.singletons.network

// A network device's card (System → Network): its kind and state, hardware, MAC, speed,
// Wi-Fi signal, addresses, gateway, DNS, IPv6, MTU — on the Overview and on its kind's page.
// With `page`, a click opens that page.
Rectangle {
    id: root
    // The device (Nmcli.devices) and the page its click opens ("": none)
    property var device: ({ device: "", kind: "", state: 0, stateText: "", connection: "", vendor: "", product: "", driver: "",
                            mac: "", speed: 0, mtu: 0, ipv4: [], gateway4: "", gateway6: "", dns: [], domains: [], ipv6: [] })
    property string page: ""

    function _kindName() {
        return device.kind === "wifi" ? "Wi-Fi" : device.kind === "ethernet" ? "Ethernet"
            : device.kind === "modem" ? "Mobile broadband"
            : NetworkOverview.isVpnDevice(device) ? "VPN" : device.type;
    }

    function _stateColor() {
        return device.state === 100 ? Theme.success : device.state >= 40 && device.state < 100 ? Theme.warning : Theme.textMuted;
    }

    readonly property bool _wifi: root.device.kind === "wifi"
    readonly property var _link: _wifi && root.device.state === 100 ? NetworkOverview.wifiLink : null
    implicitHeight: _deviceColumn.implicitHeight + 20
    radius: Theme.settings.cardRadius
    // Lit under the pointer anywhere on the card: a HoverHandler, which the selectable texts
    // inside do not take the hover from (the area under them did, and the light flickered
    // between text and background); the area's own light still shows a tap
    readonly property bool _lit: page !== "" && (_hover.hovered || _cardArea.lit)
    color: _lit ? Theme.surface : Theme.fillSubtle
    border.width: Theme.border.width
    border.color: _lit ? Theme.accent : Theme.outline

    HoverHandler {
        id: _hover
        enabled: root.page !== ""
        cursorShape: Qt.PointingHandCursor
    }

    // Under the details, so their text stays selectable
    PointerArea {
        id: _cardArea
        centred: false
        anchors.fill: parent
        enabled: root.page !== ""
        cursorShape: Qt.PointingHandCursor
        onClicked: Shell.openSettings(root.page)
    }

    ColumnLayout {
        id: _deviceColumn
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            spacing: 8
            Rectangle {
                implicitWidth: 9
                implicitHeight: 9
                radius: 4.5
                color: root._stateColor()
            }
            Text {
                text: root._kindName()
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                color: Theme.textPrimary
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.device.device + " · " + root.device.stateText
                    + (root.device.connection !== "" ? " · " + root.device.connection : "")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
            }
        }

        DetailRow {
            label: "Hardware"
            value: [root.device.vendor, root.device.product].filter(part => part !== "").join(" ")
                + (root.device.driver !== "" ? " (" + root.device.driver + ")" : "")
        }
        DetailRow { label: "MAC address"; value: root.device.mac }
        DetailRow {
            label: "Speed"
            value: root._link ? NetworkRules.speedText(root._link.rate)
                : root.device.kind === "ethernet" && root.device.state === 100
                    ? NetworkRules.speedText(root.device.speed) : ""
        }
        DetailRow {
            label: "Signal"
            value: root._link ? root._link.signal + " % · channel " + root._link.channel
                + " · " + (root._link.frequency >= 3000 ? "5 GHz" : "2.4 GHz")
                + (root._link.security !== "" ? " · " + root._link.security : "") : ""
        }
        DetailRow { label: "IPv4"; value: root.device.ipv4.join(", ") }
        DetailRow { label: "Gateway"; value: [root.device.gateway4, root.device.gateway6].filter(part => part !== "").join(", ") }
        DetailRow { label: "DNS"; value: root.device.dns.join(", ") }
        DetailRow { label: "Search domains"; value: root.device.domains.join(", ") }
        DetailRow { label: "IPv6"; value: root.device.ipv6.join(", ") }
        DetailRow { label: "MTU"; value: root.device.mtu > 0 && root.device.state === 100 ? String(root.device.mtu) : "" }
    }
}
