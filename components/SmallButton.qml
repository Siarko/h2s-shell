import QtQuick
import qs.singletons

// A compact button with a label. `kind` is what it does — "normal", "save" (confirms:
// the confirm colour), "saveChange" (confirms a change to something that exists: the
// second confirm colour), "action" (an app's action on its notification: the accent),
// "cancel", and three with a tone, worn as a border and filled
// under the pointer: "delete" (stops or removes: red), "warning" (goes on, but think),
// "success" (a good outcome) — so each kind can be styled on its own
// The look of each is ThemeRules.buttonLook. `checked`
// shows a toggle that is on (filled with the accent), e.g. a scan running. As tall as its
// label needs, never less than 24 px, so a larger font in a theme grows it rather than
// spilling out; made narrower than its label, the label ends in "…".
//
// Tab reaches it while it is available, and Space or Enter then acts as a click (a ring
// inside it shows it has the keyboard). A click does not take the keyboard: a field being
// typed in keeps it.
Rectangle {
    id: root

    property string label
    property bool available: true
    property string kind: "normal"
    property bool checked: false
    property int fontSize: Theme.fontSizeBody
    // Shown on hover when not empty
    property string tooltip: ""
    readonly property bool hovered: _area.containsMouse
    signal clicked

    readonly property bool _hot: _area.lit && available
    readonly property var _look: ThemeRules.buttonLook(kind, { hot: _hot, checked: checked, focused: activeFocus })
    // The theme's group for this kind of button: its own radius; padding and height are
    // the general button's
    readonly property var _shape: Theme[_look.group]

    implicitWidth: _label.implicitWidth + 2 * Theme.button.horizontalPadding
    implicitHeight: Math.max(Theme.button.minHeight, _label.implicitHeight + 2 * Theme.button.verticalPadding)
    width: implicitWidth
    height: implicitHeight
    radius: _shape.radius
    opacity: available ? 1 : 0.35
    color: Theme[_look.fill]
    border.width: _look.border !== "" ? Theme.border.width : 0
    border.color: _look.border !== "" ? Theme[_look.border] : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

    activeFocusOnTab: available
    Keys.onPressed: event => {
        if (!root.available || ![Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter].includes(event.key))
            return;
        // Taken whole, so an owner that also handles Enter does not act a second time; a held
        // key clicks once
        event.accepted = true;
        if (!event.isAutoRepeat)
            root.clicked();
    }

    // While it has the keyboard: a line inside the border, which keeps the kind's colour
    Rectangle {
        anchors.fill: parent
        anchors.margins: Theme.border.width
        visible: root._look.ring !== ""
        radius: Math.max(0, root.radius - Theme.border.width)
        color: "transparent"
        border.width: Theme.border.width
        border.color: root._look.ring !== "" ? Theme[root._look.ring] : "transparent"
    }

    Text {
        id: _label
        anchors.centerIn: parent
        // Its own width while the button has room for it: only a narrower button elides
        width: root.width < root.implicitWidth ? Math.max(0, root.width - 2 * Theme.button.horizontalPadding) : implicitWidth
        text: root.label
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        font.family: Theme.fontFamily
        font.pixelSize: root.fontSize
        color: Theme[root._look.label]
    }

    PointerArea {
        id: _area
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.available) root.clicked()
    }

    HoverTip {
        target: root
        shown: root.tooltip !== "" && _area.containsMouse
        text: root.tooltip
    }
}
