import QtQuick
import qs.api

// The fixture's element on a popup row's name line: taller than the line (the place gives it
// the line's height), counting the contexts it is handed, telling its main when it is made
// and when it goes
Rectangle {
    id: title

    property var module: null
    property var context: null
    property int contextChanges: 0
    property var _main: null
    property string _key: ""

    objectName: "anchors-popup-rows:Title"
    implicitWidth: 24
    implicitHeight: 40
    radius: 4
    color: Api.theme.accent

    onContextChanged: contextChanges++
    Component.onCompleted: {
        _key = (context?.anchor ?? "") + "|" + (context?.networkId ?? "") + "|" + (context?.name ?? "");
        _main = module?.main ?? null;
        _main?.made(_key);
    }
    Component.onDestruction: {
        try {
            _main?.gone(_key);
        } catch (error) {
            // Its main went first (the module unloaded)
        }
    }
}
