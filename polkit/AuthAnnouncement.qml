import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// Who answers, who asks and what for, in the polkit prompt (polkit/AuthPrompt.qml): first
// "As user" (the one account's name, or a choice when several can answer), then, for a
// request that is a run of the shell's queue (PrivilegedRuns.announcementFor), "Module" (or
// "Shell" for a command of the shell's own) and "Authorization", one line each, and "Command", which opens on a click to the command
// handed to pkexec, whole, in a box that scrolls — for a module's prompt with polkit's own
// message and action id over it. What goes where is PolkitRules.promptLayout's; the texts
// are PolkitRules.announcement's; the labels and the frame are the shell's, every value
// plain text on one line, so a module's words cannot pass for the shell's or fake a line of
// their own.
//
// "Command" is closed for every new announcement. The line is a PointerArea, which takes no
// keyboard focus: the password field keeps it (the prompt gives it back after a click too,
// `commandToggled`).
ColumnLayout {
    id: root

    // { module, authorization, command } or null (no Module, Authorization or Command)
    property var announcement: null
    // The accounts that can answer, by name, and the one picked
    property var identityNames: []
    property int identityIndex: 0
    // polkit's message and action id: shown under Command for a module's prompt
    property string polkitMessage: ""
    property string actionId: ""
    property bool commandOpen: false
    signal commandToggled()
    signal identityPicked(int index)

    readonly property var layout: PolkitRules.promptLayout(announcement, identityNames.length)
    readonly property bool _polkitUnderCommand: layout.polkitMessage === "command"

    visible: layout.announced || layout.identity !== "none"
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

        // Who answers: the first row
        Label {
            visible: root.layout.identity !== "none"
            text: "As user"
        }
        Value {
            objectName: "identity"
            visible: root.layout.identity === "name"
            text: root.identityNames[0] ?? ""
        }
        Dropdown {
            objectName: "identityPicker"
            visible: root.layout.identity === "pick"
            Layout.fillWidth: true
            options: root.identityNames.map((name, index) => ({ value: index, label: name }))
            value: root.identityIndex
            onPicked: index => root.identityPicked(index)
        }

        Label {
            objectName: "askerLabel"
            visible: root.layout.announced
            // "Module", or "Shell" for a command of the shell's own (PolkitRules.announcement)
            text: root.announcement?.label ?? "Module"
        }
        // The id in brackets comes first: the name takes only the room it leaves (down to
        // none), so a long name cannot push the id out of view. Only an id too wide for the
        // whole column by itself is cut, in the middle, keeping both of its ends
        Item {
            objectName: "moduleLine"
            visible: root.layout.announced
            Layout.fillWidth: true
            implicitHeight: _moduleName.implicitHeight

            Value {
                id: _moduleName
                objectName: "module"
                width: Math.max(0, Math.min(implicitWidth, parent.width - (_moduleId.visible ? _moduleId.width : 0)))
                text: root.announcement?.moduleName ?? ""
            }
            Value {
                id: _moduleId
                objectName: "moduleId"
                x: _moduleName.width
                width: Math.max(0, Math.min(implicitWidth, parent.width))
                visible: (root.announcement?.moduleId ?? "") !== ""
                elide: Text.ElideMiddle
                text: " (" + (root.announcement?.moduleId ?? "") + ")"
            }
        }
        Label {
            visible: root.layout.announced && (root.announcement?.authorization ?? "") !== ""
            text: "Authorization"
        }
        Value {
            objectName: "authorization"
            visible: root.layout.announced && text !== ""
            text: root.announcement?.authorization ?? ""
        }
    }

    // The click area goes under the line, as on a card's header
    Item {
        objectName: "commandLine"
        visible: root.layout.announced
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

    // For a module's prompt, polkit's own words over the command: its message (which repeats
    // the command) and the action
    Text {
        objectName: "polkitMessage"
        visible: root.layout.announced && root.commandOpen && root._polkitUnderCommand && text !== ""
        Layout.fillWidth: true
        text: root.polkitMessage
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 6
        elide: Text.ElideRight
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }
    Text {
        objectName: "actionId"
        visible: root.layout.announced && root.commandOpen && root._polkitUnderCommand && text !== ""
        Layout.fillWidth: true
        text: root.actionId
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 2
        elide: Text.ElideRight
        color: Theme.glassTextMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    // The command, whole: wrapped anywhere, scrolling past a few lines; its words in their
    // order whatever their script (commandShown)
    Rectangle {
        objectName: "commandBox"
        visible: root.layout.announced && root.commandOpen
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
                text: root.announcement?.commandShown ?? ""
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
