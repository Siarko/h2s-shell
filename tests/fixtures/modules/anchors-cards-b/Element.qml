import QtQuick
import qs.api

// An element in AnchorsTest's fixture section and cards: says where it stands, and tells the
// suite's tracker (in its context) when it is made, while it runs, and when it goes
Text {
    id: element

    property var module: null
    property var context: null
    property bool shown: false
    property var _tracker: null

    objectName: "anchors-cards-b:Element"
    text: "b " + (context?.anchor ?? "?") + " " + (context?.placement ?? "?") + " " + (context?.itemId ?? "")
    textFormat: Text.PlainText
    font.family: Api.theme.fontFamily
    font.pixelSize: Api.theme.fontSizeSmall
    color: Api.theme.textSecondary

    // While it exists, a beat the suite counts: none may come after it is gone
    Timer {
        interval: 40
        repeat: true
        running: true
        onTriggered: element._tracker?.beat(element.objectName, element.context)
    }

    Component.onCompleted: {
        _tracker = context?.tracker ?? null;
        _tracker?.made(objectName, context);
    }
    Component.onDestruction: _tracker?.gone(objectName, context)
}
