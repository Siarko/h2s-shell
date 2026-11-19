import QtQuick
import qs.api

// The fixture's element in a VPN's opened card: says which VPN it was given, counts the
// contexts it is handed, and tells its module's main while it stands
Text {
    id: element

    property var module: null
    property var context: null
    property int contextChanges: 0
    property var _main: null
    property string _key: ""

    objectName: "anchors-vpn-a:Card"
    text: "a Card " + (context?.vpnId ?? "?")
    textFormat: Text.PlainText
    font.family: Api.theme.fontFamily
    font.pixelSize: Api.theme.fontSizeSmall
    color: Api.theme.textSecondary

    onContextChanged: contextChanges++
    Component.onCompleted: {
        _main = module?.main ?? null;
        _key = "Card|" + (context?.anchor ?? "") + "|" + (context?.vpnId ?? "");
        _main?.made(_key);
    }
    Component.onDestruction: {
        try {
            _main?.gone(_key);
        } catch (error) {
            // Its main went first (the module turned off)
        }
    }
}
