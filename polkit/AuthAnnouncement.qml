import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// Who asks and what for, in the polkit prompt (polkit/AuthPrompt.qml), for a request that
// is a run of the shell's queue (PrivilegedRuns.announcementFor): "Module" and
// "Authorization", one line each, and "Command", which opens on a click to the command
// handed to pkexec, whole, in a box that scrolls. The texts are PolkitRules.announcement's;
// the labels and the frame are the shell's, every value plain text on one line, so a
// module's words cannot pass for the shell's or fake a line of their own.
//
// "Command" is closed for every new announcement. The line is a PointerArea, which takes no
// keyboard focus: the password field keeps it (the prompt gives it back after a click too,
// `commandToggled`).
ColumnLayout {
    id: root

    // { module, authorization, command } or null (nothing shown)
    property var announcement: null
    property bool commandOpen: false
    signal commandToggled()

    visible: announcement !== null
    spacing: 6

    onAnnouncementChanged: commandOpen = false

    component Label: Text {
        textFormat: Text.PlainText
        color: Theme.glassTextMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
    }
    component Value: Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        maximumLineCount: 1
        elide: Text.ElideRight
        color: Theme.textPrimary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 16
        rowSpacing: 4

        Label {
            text: "Module"
        }
        Value {
            objectName: "module"
            text: root.announcement?.module ?? ""
        }
        Label {
            visible: (root.announcement?.authorization ?? "") !== ""
            text: "Authorization"
        }
        Value {
            objectName: "authorization"
            visible: text !== ""
            text: root.announcement?.authorization ?? ""
        }
    }

    // The click area goes under the line, as on a card's header
    Item {
        objectName: "commandLine"
        Layout.fillWidth: true
        implicitHeight: _commandLabel.implicitHeight

        PointerArea {
            objectName: "commandArea"
            centred: false
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.commandOpen = !root.commandOpen;
                root.commandToggled();
            }
        }
        Label {
            id: _commandLabel
            text: (root.commandOpen ? "▾" : "▸") + " Command"
        }
    }

    // The command, whole: wrapped anywhere, scrolling past a few lines
    Rectangle {
        objectName: "commandBox"
        visible: root.commandOpen
        Layout.fillWidth: true
        implicitHeight: Math.min(_command.implicitHeight, _command.font.pixelSize * 8) + 16
        radius: Theme.lock.controlRadius
        color: Theme.glass
        border.color: Theme.glassBorder
        border.width: Theme.border.width

        Flickable {
            id: _flick
            objectName: "commandScroll"
            anchors { fill: parent; margins: 8 }
            clip: true
            contentWidth: width
            contentHeight: _command.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Text {
                id: _command
                objectName: "command"
                width: _flick.width
                text: root.announcement?.command ?? ""
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
