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

    signal confirmed
    // The first click, for owners that track which item is being asked about
    signal askingStarted

    readonly property var _look: ThemeRules.buttonLook(kind, { hot: _area.lit && available, asking: asking })
    readonly property var _shape: Theme[_look.group]

    spacing: 0

    Rectangle {
        id: _button
        implicitWidth: _label.implicitWidth + 2 * Theme.button.horizontalPadding
        // As tall as the label needs, never less than the theme's button height
        implicitHeight: Math.max(Theme.button.minHeight, _label.implicitHeight + 2 * Theme.button.verticalPadding)
        width: implicitWidth
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
            text: root.asking ? root.confirmLabel : root.label
            textFormat: Text.PlainText
            // One line: a label or question with line breaks does not make the button taller
            maximumLineCount: 1
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: root.fontSize
            color: Theme[root._look.label]
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

        PointerArea {
            id: _area
            cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (!root.available)
                    return;
                if (root.asking) {
                    root.asking = false;
                    root.confirmed();
                } else {
                    root.asking = true;
                    root.askingStarted();
                }
            }
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
        width: _button.height
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
