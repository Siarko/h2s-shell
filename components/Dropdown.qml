import QtQuick
import Quickshell
import qs.singletons

// A choice among `options` — [{ value, label, color? }], `color` drawing a dot before the
// label — shown as a button with the current one, opening a FloatingList of them over the
// content. `picked` reports the choice; the owner sets `value`.
Rectangle {
    id: root

    property var options: []
    property var value
    property string placeholder: "Choose"
    property bool open: false
    property int fontSize: Theme.fontSizeBody
    signal picked(var value)

    readonly property var _current: options.find(option => option.value === value) ?? null

    implicitWidth: 120
    implicitHeight: Math.max(26, _label.implicitHeight + 8)
    radius: Theme.dropdown.radius
    color: Theme.popupBackground
    border.width: Theme.border.width
    border.color: open ? Theme.accent : (_area.lit ? Theme.textMuted : Theme.outline)
    Behavior on border.color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

    // A colour dot, when the option has a colour
    component Dot: Rectangle {
        width: 10
        height: 10
        radius: width / 2
    }

    Row {
        anchors { left: parent.left; right: _arrow.left; leftMargin: Theme.field.horizontalPadding; rightMargin: 4; verticalCenter: parent.verticalCenter }
        spacing: 6

        Dot {
            visible: root._current?.color !== undefined
            anchors.verticalCenter: parent.verticalCenter
            color: root._current?.color ?? "transparent"
        }
        Text {
            id: _label
            width: parent.width - (root._current?.color !== undefined ? 16 : 0)
            text: root._current?.label ?? root.placeholder
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: root.fontSize
            color: root._current ? Theme.textSecondary : Theme.textDisabled
        }
    }

    Text {
        id: _arrow
        anchors { right: parent.right; rightMargin: Theme.field.horizontalPadding; verticalCenter: parent.verticalCenter }
        text: root.open ? "▴" : "▾"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeXSmall
        color: Theme.textMuted
    }

    PointerArea {
        id: _area
        cursorShape: Qt.PointingHandCursor
        onClicked: root.open = !root.open
    }

    FloatingList {
        anchorItem: root
        open: root.open
        onClosed: root.open = false

        Repeater {
            // ScriptModel, never the bare array — see "The Repeater crash"; the options can
            // be live (the account's calendars)
            model: ScriptModel { values: root.options }

            Rectangle {
                required property var modelData
                readonly property bool picked: modelData.value === root.value
                width: parent.width
                height: Math.max(24, _optionLabel.implicitHeight + 6)
                radius: Theme.listItem.radius
                color: picked ? Theme.accentTint : (_optionArea.lit ? Theme.surfaceHover : Theme.surfaceHoverClear)
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                Row {
                    anchors { left: parent.left; right: parent.right; leftMargin: 6; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    spacing: 6

                    Dot {
                        visible: modelData.color !== undefined
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData.color ?? "transparent"
                    }
                    Text {
                        id: _optionLabel
                        width: parent.width - (modelData.color !== undefined ? 16 : 0)
                        text: modelData.label
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: root.fontSize
                        color: parent.parent.picked ? Theme.textPrimary : Theme.textSecondary
                    }
                }

                PointerArea {
                    id: _optionArea
                    centred: false
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.open = false;
                        root.picked(modelData.value);
                    }
                }
            }
        }
    }
}
