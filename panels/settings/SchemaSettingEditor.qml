import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

// Editor for one SettingsSchema key as set in one profile. The control follows the
// schema type: pills for intervals and enums, a switch for bools. It says where the shown
// value comes from — set here, inherited from the profiles above, or overridden right now
// by a later active profile — and offers to drop this profile's own value.
Item {
    id: root

    required property string key
    // The value this profile sets, or undefined when it inherits
    property var ownValue: undefined
    // What applies at this profile's place when it sets nothing
    property var inheritedValue: undefined
    // A later active profile that currently overrides this key, or ""
    property string overriddenBy: ""

    signal edited(var newValue)
    signal reset

    readonly property var entry: SettingsSchema.entry(key)
    readonly property bool inherits: ownValue === undefined
    readonly property var shownValue: inherits ? inheritedValue : ownValue

    // Interval presets; the current value is added when it is not one of them, so a value
    // written by hand still shows as selected
    readonly property var _intervalPresets: [0, 1000, 2000, 5000, 10000, 30000, 60000]

    function _intervalLabel(ms) {
        if (ms === 0)
            return "Paused";
        if (ms % 60000 === 0)
            return (ms / 60000) + " min";
        return (ms / 1000) + " s";
    }

    readonly property var _choices: {
        if (!entry)
            return [];
        if (entry.type === "interval") {
            const values = _intervalPresets.slice();
            if (typeof shownValue === "number" && !values.includes(shownValue))
                values.push(shownValue);
            values.sort((a, b) => a - b);
            return values.map(ms => ({ value: ms, label: _intervalLabel(ms) }));
        }
        if (entry.type === "enum")
            return entry.options;
        return [];
    }

    Layout.fillWidth: true
    implicitHeight: _column.implicitHeight + 10

    Column {
        id: _column
        width: root.width
        spacing: 6

        RowLayout {
            width: parent.width
            spacing: 8

            Text {
                text: root.entry?.label ?? root.key
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBodyLarge
                color: Theme.textPrimary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                text: root.overriddenBy !== ""
                    ? "now set by " + root.overriddenBy
                    : (root.inherits ? "inherited" : "")
                visible: text !== ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: root.overriddenBy !== "" ? Theme.sliderAccent : Theme.textDim
            }

            // Drop this profile's value, so the key falls through to the profiles above
            Rectangle {
                visible: !root.inherits
                width: 20
                height: 20
                radius: 4
                color: _resetArea.containsMouse ? Theme.cellHover : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.textDim
                }

                MouseArea {
                    id: _resetArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.reset()
                }
            }

            // Bool: a switch on the header row
            Rectangle {
                visible: root.entry?.type === "bool"
                width: 36
                height: 20
                radius: 10
                opacity: root.inherits ? 0.5 : 1
                color: root.shownValue === true ? Theme.sliderAccent : Theme.cellDefault

                Rectangle {
                    x: root.shownValue === true ? parent.width - width - 2 : 2
                    y: 2
                    width: 16
                    height: 16
                    radius: 8
                    color: Theme.textPrimary
                    Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.edited(root.shownValue !== true)
                }
            }
        }

        // Intervals and enums: one pill per choice; an inherited value is shown dimmed
        Flow {
            visible: root._choices.length > 0
            width: parent.width
            spacing: 4

            Repeater {
                // ScriptModel, never the bare array — see "The Repeater crash"
                model: ScriptModel {
                    values: root._choices
                }

                Rectangle {
                    required property var modelData
                    readonly property bool selected: modelData.value === root.shownValue

                    width: _pillText.implicitWidth + 16
                    height: 26
                    radius: 6
                    color: selected ? Theme.sliderAccent : "transparent"
                    opacity: selected && root.inherits ? 0.5 : 1
                    border.width: selected ? 0 : 1
                    border.color: Qt.rgba(Theme.textSecondary.r, Theme.textSecondary.g, Theme.textSecondary.b, 0.4)

                    Text {
                        id: _pillText
                        anchors.centerIn: parent
                        text: parent.modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: parent.selected ? Theme.textPrimary : Theme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.edited(parent.modelData.value)
                    }
                }
            }
        }
    }
}
