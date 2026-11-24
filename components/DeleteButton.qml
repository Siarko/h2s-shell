import QtQuick
import qs.singletons

// The one way the shell deletes something from a click: the first click asks — the button
// turns into the question, `confirmLabel`, with a "×" attached that cancels — and only a
// second click deletes (`confirmed`). Nothing times out: the question stays until it is
// answered. The owner sets `asking = false` when what the button deletes changes (another
// item selected), so a question never carries over to it.
//
// `kind` is SmallButton's: before the first click the button looks as that kind does
// ("delete": a red border, red under the pointer). Asking, it is plain, with the question
// and a border around both parts in the kind's colour (ThemeRules.buttonLook) — "save"
// for a button that asks before turning something on.
//
// Given a `maximumWidth`, it is never wider, its question and "×" included: a longer label
// or question is cut with "…" — or, with `wraps`, goes on to more lines, the button growing
// taller (the "×" keeps one line's width). `fullWidth` is what it needs on one line, whatever
// the cap.
//
// Tab reaches it while it is available; Space or Enter then acts as a click (the first asks,
// the second deletes) and Escape, while it asks, cancels as the "×" does. A ring inside the
// button shows it has the keyboard. A click does not take the keyboard.
//
//   DeleteButton {
//       confirmLabel: "Delete everywhere?"
//       cancelTip: "Cancel — keep the preset"
//       onConfirmed: WidgetPresets.remove(type, name)
//   }
Row {
    id: root

    property string kind: "delete"
    property string label: "Delete"
    property string confirmLabel: "Delete?"
    property string cancelTip: "Cancel"
    property bool available: true
    property int fontSize: Theme.fontSizeSmall
    // Shown on hover when not empty, until the first click
    property string tooltip: ""
    // Whether the first click has been made and the button waits for the second
    property bool asking: false
    // The most it may be, the "×" included (a narrower place cuts the label)
    property real maximumWidth: Infinity
    // Beyond `maximumWidth`, the label or question goes on to more lines instead of being cut
    property bool wraps: false
    // As wide as it is uncut: what a wrapper asks a layout for, so that the cap does not
    // feed back into the width it is given
    readonly property real fullWidth: _button.implicitWidth + (asking ? _cancel.width : 0)

    signal confirmed
    // The first click, for owners that track which item is being asked about
    signal askingStarted

    readonly property var _look: ThemeRules.buttonLook(kind, { hot: _area.lit && available, asking: asking, focused: activeFocus })
    readonly property var _shape: Theme[_look.group]

    spacing: 0

    // A click on the button, or Space or Enter on it: asks, or acts when it asks already
    function _press() {
        if (!available)
            return;
        if (asking) {
            asking = false;
            confirmed();
        } else {
            asking = true;
            askingStarted();
        }
    }

    activeFocusOnTab: available
    Keys.onShortcutOverride: event => root._override(event)
    Keys.onPressed: event => root._key(event)

    // Escape while it asks is its own, before any shortcut (a side panel's Escape closes the
    // panel): it cancels the question. Not asking, Escape is the owner's
    function _override(event) {
        if (available && asking && event.key === Qt.Key_Escape)
            event.accepted = true;
    }

    // A key pressed while it has the keyboard: Space and Enter act as a click, Escape cancels a
    // question. Taken whole, so an owner that also handles Enter does not act a second time; a
    // held key presses once, never asking and deleting in one go
    function _key(event) {
        if (!available)
            return;
        if (event.key === Qt.Key_Escape) {
            if (!asking)
                return;
            event.accepted = true;
            asking = false;
            return;
        }
        if (![Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter].includes(event.key))
            return;
        event.accepted = true;
        if (!event.isAutoRepeat)
            _press();
    }

    Rectangle {
        id: _button
        implicitWidth: _label.implicitWidth + 2 * Theme.button.horizontalPadding
        // As tall as the label needs, never less than the theme's button height
        implicitHeight: Math.max(Theme.button.minHeight, _label.implicitHeight + 2 * Theme.button.verticalPadding)
        width: Math.min(implicitWidth, Math.max(0, root.maximumWidth - (root.asking ? _cancel.width : 0)))
        height: implicitHeight
        radius: root._shape.radius
        // Square on the side the cancel button attaches to, so the two read as one control
        topRightRadius: root.asking ? 0 : radius
        bottomRightRadius: root.asking ? 0 : radius
        opacity: root.available ? 1 : 0.35
        // Above the cancel button, which the outline reaches over
        z: 1
        color: Theme[root._look.fill]
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

        Text {
            id: _label
            anchors.centerIn: parent
            // Its own width while the button has room for it: only a narrower button elides
            width: _button.width < _button.implicitWidth ? Math.max(0, _button.width - 2 * Theme.button.horizontalPadding) : implicitWidth
            text: root.asking ? root.confirmLabel : root.label
            textFormat: Text.PlainText
            // One line unless it wraps: a label or question with line breaks does not make the
            // button taller
            wrapMode: root.wraps ? Text.Wrap : Text.NoWrap
            maximumLineCount: root.wraps ? 2147483647 : 1
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: root.fontSize
            color: Theme[root._look.label]
        }

        // One line of the label, measured: the "×" is as wide as one line is tall
        Text {
            id: _oneLine
            visible: false
            text: "X"
            font: _label.font
        }

        // The border: around the button, and around the button and its cancel button
        // while asking, as one control
        Rectangle {
            id: _outline
            visible: root._look.border !== ""
            width: parent.width + (root.asking ? _cancel.width : 0)
            height: parent.height
            radius: root._shape.radius
            color: "transparent"
            border.width: Theme.border.width
            border.color: root._look.border !== "" ? Theme[root._look.border] : "transparent"
        }

        // While it has the keyboard: a line inside the border, which keeps the kind's colour
        Rectangle {
            anchors.fill: parent
            anchors.margins: Theme.border.width
            visible: root._look.ring !== ""
            radius: Math.max(0, root._shape.radius - Theme.border.width)
            topRightRadius: root.asking ? 0 : radius
            bottomRightRadius: root.asking ? 0 : radius
            color: "transparent"
            border.width: Theme.border.width
            border.color: root._look.ring !== "" ? Theme[root._look.ring] : "transparent"
        }

        PointerArea {
            id: _area
            cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root._press()
        }

        HoverTip {
            target: parent
            shown: root.tooltip !== "" && !root.asking && _area.containsMouse
            text: root.tooltip
        }
    }

    // Cancels the question, attached to the asking button
    Rectangle {
        id: _cancel
        visible: root.asking
        // As wide as one line of the button is tall
        width: Math.max(Theme.button.minHeight, _oneLine.implicitHeight + 2 * Theme.button.verticalPadding)
        height: _button.height
        radius: root._shape.radius
        topLeftRadius: 0
        bottomLeftRadius: 0
        // Not available, it is dimmed and takes no click, as the button it belongs to
        opacity: root.available ? 1 : 0.35
        color: _cancelArea.lit && root.available ? Theme.surfaceHover : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

        Text {
            anchors.centerIn: parent
            text: "×"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.textSecondary
        }

        PointerArea {
            id: _cancelArea
            centred: false
            anchors.fill: parent
            enabled: root.available
            cursorShape: Qt.PointingHandCursor
            onClicked: root.asking = false
        }

        HoverTip {
            target: parent
            shown: _cancelArea.containsMouse
            text: root.cancelTip
        }
    }
}
