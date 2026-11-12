import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// System → Authentication: whether the shell is the session's polkit agent — the prompt
// for an administrator's password when a program needs one (Authentication,
// docs/plans/polkit.md) — and what answers such requests now.
Flickable {
    id: root

    anchors.fill: parent
    contentWidth: width
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
    flickableDirection: Flickable.VerticalFlick
    clip: true

    readonly property string _state: Authentication.state
    readonly property string _others: Authentication.otherAgents.join(", ")

    ColumnLayout {
        id: _column
        x: Theme.settings.pageMargin
        y: Theme.settings.pageMargin
        width: root.width - 2 * Theme.settings.pageMargin
        spacing: 0

        Heading {
            text: "Authentication"
            Layout.bottomMargin: 4
        }
        Hint {
            Layout.bottomMargin: 10
            text: "When a program needs an administrator's rights — NetworkManager for a system connection, systemd, pkexec, an installer — polkit asks the session's authentication agent to ask you for the password. Without an agent, such requests are refused."
        }

        // What answers now
        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 12
            implicitHeight: _status.implicitHeight + 20
            radius: Theme.settings.cardRadius
            color: Theme.fillSubtle
            border.width: Theme.border.width
            border.color: root._state === "none" || root._state === "blocked" || root._state === "conflict" ? Theme.warning : Theme.outline

            RowLayout {
                id: _status
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 4
                    implicitWidth: 10
                    implicitHeight: 10
                    radius: 5
                    color: root._state === "active" || root._state === "other" ? Theme.success
                        : root._state === "deciding" ? Theme.textMuted : Theme.warning
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textPrimary
                    text: root._state === "active" ? "The shell answers password requests."
                        : root._state === "conflict" ? "The shell answers password requests. " + root._others + " is running too, but cannot register while the shell's prompt is on: keep one of them."
                        : root._state === "blocked" ? "The shell's prompt is on but could not start: another agent holds the session" + (root._others !== "" ? " (" + root._others + ")" : "") + "."
                        : root._state === "other" ? "Another agent answers password requests: " + (root._others !== "" ? root._others : "one the shell does not know by name") + "."
                        : root._state === "none" ? "No agent answers: requests for an administrator's password are refused."
                        : "Deciding at the first start whether the shell's prompt is needed…"
                }

                SmallButton {
                    visible: root._state === "none"
                    label: "Turn on"
                    onClicked: Authentication.setOn(true)
                }
                SmallButton {
                    visible: root._state === "conflict" || root._state === "blocked"
                    label: "Turn the shell's off"
                    onClicked: Authentication.setOn(false)
                }
            }
        }

        SchemaSettingEditor { key: "system.polkitAgent"; editIndex: 0; Layout.fillWidth: true }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 8

            SmallButton {
                label: "Try the prompt"
                available: root._state === "active" && !Authentication.tryingPrompt
                tooltip: Authentication.tryingPrompt ? "The prompt is open"
                    : root._state === "active" ? "Runs pkexec true: asks for the password, then does nothing"
                    : "The shell's prompt is not the one answering"
                onClicked: Authentication.tryPrompt()
            }
            Hint { text: "Asks for the password and does nothing with it." }
        }
    }
}
