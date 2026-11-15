import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.network

// The Wi-Fi networks in range (WifiManager), each a WifiNetworkRow to connect to or forget
// — shared by the network popup and Settings → System → Network → Wi-Fi, so both behave the
// same. Which row is open, the passwords typed and whether the open one shows are kept here,
// by SSID (see WifiNetworkRow). As tall as its rows, up to `maximumHeight`, then it scrolls.
Item {
    id: root

    property real maximumHeight: Infinity

    // The network row that is open, by SSID; the passwords typed, by SSID; whether the
    // open row shows its password
    property string _expandedSsid: ""
    property var _passwords: ({})
    property bool _showPassword: false

    function _toggleNetwork(ssid) {
        _expandedSsid = _expandedSsid === ssid ? "" : ssid;
        _showPassword = false;
    }

    function _setPassword(ssid, text) {
        const passwords = Object.assign({}, _passwords);
        passwords[ssid] = text;
        _passwords = passwords;
    }

    implicitHeight: WifiManager.wifiNetworks.length === 0 ? _empty.implicitHeight : _list.height

    ListView {
        id: _list
        width: parent.width
        height: Math.min(contentHeight, Math.max(80, root.maximumHeight))
        clip: true
        // Keyed by "ssid", as WifiManager rebuilds wifiNetworks fresh on every scan (see
        // VpnSection for why)
        model: ScriptModel {
            objectProp: "ssid"
            values: WifiManager.wifiNetworks
        }
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        // A network found by a scan fades in, and the list makes room for it; rows
        // re-sorted by signal slide to their new place
        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.duration("enter"); easing: Theme.curve("enter") }
        }
        displaced: Transition {
            NumberAnimation { property: "y"; duration: Theme.duration("move"); easing: Theme.curve("move") }
            NumberAnimation { property: "opacity"; to: 1; duration: Theme.duration("enter") }
        }
        move: Transition {
            NumberAnimation { property: "y"; duration: Theme.duration("move"); easing: Theme.curve("move") }
        }

        delegate: WifiNetworkRow {
            width: _list.width
            expanded: root._expandedSsid === ssid
            passwordText: root._passwords[ssid] ?? ""
            showPassword: expanded && root._showPassword
            onToggleRequested: root._toggleNetwork(ssid)
            onPasswordEdited: text => root._setPassword(ssid, text)
            onRevealToggled: root._showPassword = !root._showPassword
        }
    }

    Text {
        id: _empty
        visible: WifiManager.wifiNetworks.length === 0
        width: parent.width
        text: "No networks found"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBodyLarge
        color: Theme.textMuted
        horizontalAlignment: Text.AlignHCenter
    }
}
