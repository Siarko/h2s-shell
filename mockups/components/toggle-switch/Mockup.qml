import QtQuick
import qs.singletons
import qs.components
import qs.mockups.kit

// ToggleSwitch in its states, each scene the settings' small switch and the popups' larger
// one (width 44, height 24, off in Theme.textDisabled) side by side:
//   off, on                     `checked` false, true
//   disabled-off, disabled-on   not `enabled`: dimmed
// The switch has no look of its own under the pointer or with the keyboard: it takes no
// keyboard focus, and its pointer area only gives the cursor and the click.
MockupWindow {
    id: root

    scenes: ["off", "on", "disabled-off", "disabled-on"]
    readonly property bool on: scene === "on" || scene === "disabled-on"
    readonly property bool disabled: scene.startsWith("disabled-")

    contentWidth: 124
    contentHeight: 48
    subject: content_

    Item {
        id: content_
        anchors.fill: parent

        Row {
            anchors.centerIn: parent
            spacing: 20

            ToggleSwitch {
                anchors.verticalCenter: parent.verticalCenter
                checked: root.on
                enabled: !root.disabled
            }
            ToggleSwitch {
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 24
                offColor: Theme.textDisabled
                checked: root.on
                enabled: !root.disabled
            }
        }
    }
}
