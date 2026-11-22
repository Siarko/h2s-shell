import QtQuick
import Quickshell
import QtQuick.Layouts
import qs.components
import qs.singletons

// One command entry on the "When away" page: a compact line — its number, its moment (greyed
// when it can no longer come), its two commands cut short, Edit and Remove — and, while
// edited, its moment (Screens dark, Locked, Before sleep), for "Screens dark" the monitors it
// waits for as chips with their dark times (one that never goes dark greyed, not waited
// for), and its two commands. The page writes: `edited(entry)` gives the whole entry.
Rectangle {
    id: root

    // Its place in the list, from 1
    property int number: 0
    // The entry as kept (IdleRules.commandEntry)
    property var entry: ({ id: "", moment: "dark", monitors: null, go: "", back: "" })
    // Its moment as the line says it: { text, greyed } (AwayViewRules.commandMoment)
    property var moment: ({ text: "", greyed: false })
    // The connected monitors as chips: [{ id, ticked, dark, at }] (AwayViewRules.commandChips),
    // and their names (monitor id → name)
    property var chips: []
    property var names: ({})
    property bool editing: false
    // The list is inherited in the edited profile: shown dimmed, a change makes it the
    // profile's own
    property bool dimmed: false
    signal edited(var entry)
    signal removed()
    signal editToggled()
    // A chip clicked: the page works out the monitors the entry names then
    signal chipClicked(string id)

    readonly property var _moments: [
        { value: "dark", label: "Screens dark" },
        { value: "lock", label: "Locked" },
        { value: "sleep", label: "Before sleep" }
    ]

    function _with(field, value) {
        const changed = Object.assign({}, entry);
        changed[field] = value;
        edited(changed);
    }

    Layout.fillWidth: true
    implicitHeight: _column.implicitHeight + 12
    radius: Theme.settings.cardRadius
    color: "transparent"
    border.width: Theme.border.width
    border.color: editing ? Theme.accent : Theme.outline

    // A command's field: saved when editing finishes, back to the kept one when focus leaves
    component CommandField: InputField {
        id: _field
        property string kept: ""
        signal saved(string command)
        Layout.fillWidth: true
        outlined: true
        placeholder: "A command"
        text: kept
        opacity: root.dimmed && !editing ? 0.5 : 1
        onEditingFinished: {
            if (text !== kept)
                saved(text);
        }
        onEditingChanged: {
            if (!editing)
                text = Qt.binding(() => _field.kept);
        }
    }

    component Label: Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textMuted
    }

    ColumnLayout {
        id: _column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6; leftMargin: 10; rightMargin: 8 }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "▸" + root.number
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                color: Theme.textPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    objectName: "commandMoment"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: root.moment.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: root.moment.greyed ? Theme.textMuted : Theme.textPrimary
                }
                Text {
                    objectName: "commandLine"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: AwayViewRules.commandLine(root.entry)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textMuted
                }
            }
            SmallButton {
                objectName: "commandEdit"
                label: root.editing ? "Done" : "Edit"
                fontSize: Theme.fontSizeSmall
                onClicked: root.editToggled()
            }
            DeleteButton {
                objectName: "commandRemove"
                label: "Remove"
                confirmLabel: "Remove?"
                onConfirmed: root.removed()
            }
        }

        Reveal {
            objectName: "commandEditor"
            open: root.editing
            spacing: 6

            Label { text: "When"; font.bold: true }
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: ScriptModel { values: root._moments.map(option => option.value) }

                    Pill {
                        required property string modelData
                        objectName: "commandMomentChoice"
                        label: root._moments.find(option => option.value === modelData).label
                        picked: root.entry.moment === modelData
                        size: "m"
                        fontSize: Theme.fontSizeBody
                        opacity: picked && root.dimmed ? 0.5 : 1
                        onClicked: {
                            if (!picked)
                                root._with("moment", modelData);
                        }
                    }
                }
            }

            // Screens dark: the monitors it waits for
            Reveal {
                open: root.entry.moment === "dark"
                spacing: 4
                Label { text: "Waits for"; Layout.topMargin: 4 }
                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: ScriptModel { values: root.chips.map(chip => chip.id) }

                        Pill {
                            required property string modelData
                            readonly property var chip: root.chips.find(item => item.id === modelData) ?? { ticked: false, dark: false, at: -1 }
                            objectName: "commandChip"
                            label: (chip.ticked ? "✓ " : "") + (root.names[modelData] ?? modelData)
                                + (chip.dark ? " · " + Format.duration(chip.at) : "")
                            picked: chip.ticked
                            size: "m"
                            fontSize: Theme.fontSizeBody
                            opacity: !chip.dark ? 0.35 : picked && root.dimmed ? 0.5 : 1
                            tooltip: chip.dark ? "" : "Never goes dark: not waited for"
                            onClicked: {
                                if (chip.dark)
                                    root.chipClicked(modelData);
                            }
                        }
                    }
                }
                Label {
                    objectName: "commandNeverDark"
                    readonly property var never: root.chips.filter(chip => !chip.dark).map(chip => root.names[chip.id] ?? chip.id)
                    visible: never.length > 0
                    text: never.join(", ") + (never.length > 1 ? " never go dark: not waited for." : " never goes dark: not waited for.")
                }
            }

            Label {
                Layout.topMargin: 4
                text: root.entry.moment === "lock" ? "When it locks" : root.entry.moment === "sleep" ? "Before the computer sleeps" : "When those screens are dark"
            }
            CommandField {
                objectName: "commandGo"
                kept: root.entry.go
                onSaved: command => root._with("go", command)
            }
            Label {
                text: root.entry.moment === "lock" ? "When you unlock" : root.entry.moment === "sleep" ? "When it wakes" : "When you come back"
            }
            CommandField {
                objectName: "commandBack"
                Layout.bottomMargin: 4
                kept: root.entry.back
                onSaved: command => root._with("back", command)
            }
        }
    }
}
