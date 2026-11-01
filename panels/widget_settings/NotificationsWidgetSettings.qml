import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// The notifications widget's preset: the count badge on the bell, and how the bell rings
// when a notification comes (NotificationsWidget).
Item {
    id: root
    property string presetName: ""
    property string widgetType: "notifications"

    implicitHeight: _col.implicitHeight

    readonly property bool _badge: WidgetPresets.value(widgetType, presetName, "badge") !== false
    readonly property string _animation: WidgetPresets.value(widgetType, presetName, "animation") ?? "once"

    readonly property var _animations: [
        { value: "off", label: "Off" },
        { value: "once", label: "Once" },
        { value: "untilOpened", label: "Until opened" },
        { value: "untilCleared", label: "Until cleared" }
    ]

    component Label: Text {
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textSecondary
        Layout.preferredWidth: 80
        // A label longer than the column (a larger font) is cut, not run into the control
        elide: Text.ElideRight
    }

    Column {
        id: _col
        width: parent.width
        topPadding: 4
        spacing: 6

        // The count on the bell
        RowLayout {
            width: _col.width
            spacing: 8

            Label { text: "Count" }

            Text {
                Layout.fillWidth: true
                text: "A badge on the bell with how many notifications wait"
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }

            ToggleSwitch {
                checked: root._badge
                onToggled: WidgetPresets.set(root.widgetType, root.presetName, "badge", !root._badge)
            }
        }

        // How the bell rings
        RowLayout {
            width: _col.width
            spacing: 8

            Label { text: "Animation" }

            Flow {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    // ScriptModel, never the bare array (CLAUDE.md)
                    model: ScriptModel { values: root._animations }

                    Pill {
                        required property var modelData
                        label: modelData.label
                        picked: modelData.value === root._animation
                        fontSize: Theme.fontSizeBody
                        minimumHeight: 26
                        onClicked: WidgetPresets.set(root.widgetType, root.presetName, "animation", modelData.value)
                    }
                }
            }
        }

        Text {
            width: _col.width
            text: root._animation === "untilOpened"
                ? "The bell rings for each new notification, and again every few seconds until the panel is opened."
                : root._animation === "untilCleared"
                ? "The bell rings for each new notification, and again every few seconds while any is left in the panel."
                : root._animation === "once" ? "The bell rings once for each new notification."
                : "The bell does not ring."
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textMuted
        }
    }
}
