import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// Editor for one SettingsSchema key as set in one profile — the one picked in the
// settings window. The control follows the schema type: pills for intervals and enums,
// a switch for bools, a text field for strings, a number field or a slider for numbers,
// a list of fields for a list of texts. It says where the shown value comes from — set here, inherited from
// the profiles above, overridden right now by a later active profile, or global — and
// offers to drop this profile's own value. The pin makes the setting global: the same in
// every profile, whichever is being edited (docs/plans/global-profiles.md).
Item {
    id: root

    required property string key
    // Index of the edited profile in Profiles.profiles
    required property int editIndex
    // False greys the editor out and ignores input, e.g. a timeout while its feature is off
    property bool available: true
    // Replaces the schema label where the page knows better, e.g. "Lock after screensaver"
    property string label: ""
    // A slider's upper bound when it depends on other settings; the schema's otherwise
    property var maximum: undefined
    // Replaces the plain write when an edit has to adjust other settings too, e.g. bar
    // height pushing the reserved space up; gets the new value
    property var editHook: null

    readonly property var _profile: Profiles.profiles[editIndex] ?? null
    // The value this profile sets, or undefined when it inherits
    readonly property var ownValue: _profile?.set?.[key]
    // What applies at this profile's place when it sets nothing
    readonly property var inheritedValue: Profiles.inheritedValue(editIndex, key)
    // The profile it comes from, or "" for the default
    readonly property string inheritedFrom: Profiles.inheritedFrom(editIndex, key)
    // A later active profile that currently overrides this key, or ""
    readonly property string overriddenBy: {
        const setter = Profiles.setBy(key);
        return Profiles.profiles.findIndex(profile => profile.name === setter) > editIndex ? setter : "";
    }

    // Pinned as global, by the user or always by the schema: one value for every profile
    readonly property bool global: key in Profiles.effectiveGlobals
    readonly property bool systemGlobal: entry?.global === true

    function edited(newValue) {
        if (editHook)
            editHook(newValue);
        else
            Profiles.writeSetting(editIndex, key, newValue);
    }

    function reset() {
        Profiles.clearOverride(editIndex, key);
    }

    readonly property var entry: SettingsSchema.entry(key)
    readonly property bool inherits: ownValue === undefined
    readonly property var shownValue: global ? Profiles.effectiveGlobals[key] : (inherits ? inheritedValue : ownValue)
    // Shown dimmed: the value is not this profile's own
    readonly property bool _dimmed: inherits && !global

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
    opacity: available ? 1 : 0.35
    enabled: available

    Column {
        id: _column
        width: root.width
        spacing: 6

        RowLayout {
            width: parent.width
            spacing: 8

            Text {
                text: root.label !== "" ? root.label : (root.entry?.label ?? root.key)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBodyLarge
                color: Theme.textPrimary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                text: root.systemGlobal
                    ? "always global"
                    : root.global
                    ? (root.inherits ? "global" : "global — this profile's value is ignored")
                    : root.overriddenBy !== ""
                        ? "now set by " + root.overriddenBy
                        : (root.inherits ? (root.inheritedFrom !== "" ? "inherited from " + root.inheritedFrom : "default") : "")
                visible: text !== ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: root.global || root.overriddenBy !== "" ? Theme.sliderAccent : Theme.textDim
            }

            // Pin as global, or unpin; profile values are kept either way
            Rectangle {
                id: _pin
                width: 20
                height: 20
                radius: 4
                color: _pinArea.containsMouse ? Theme.cellHover : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "󰐃"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    color: root.global ? Theme.sliderAccent : Theme.textDim
                    opacity: root.global || _pinArea.containsMouse ? (root.systemGlobal ? 0.6 : 1) : 0.5
                }

                MouseArea {
                    id: _pinArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.systemGlobal ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: {
                        if (root.systemGlobal)
                            return;
                        if (root.global)
                            Profiles.unpinGlobal(root.key);
                        else
                            Profiles.pinGlobal(root.key);
                    }
                }

                HoverTip {
                    target: _pin
                    shown: _pinArea.containsMouse
                    text: root.systemGlobal
                        ? "Always global: this setting is never per profile, so it has one value whichever profile is being edited."
                        : root.global
                        ? "Global: the same value in every profile, whichever profile is being edited. Click to make it per profile again — the profiles' own values come back."
                        : "Pin as global: one value for every profile, which no profile changes. The profiles' own values are kept and come back when unpinned."
                }
            }

            // Drop this profile's value, so the key falls through to the profiles above
            Rectangle {
                id: _reset
                visible: !root.inherits && !root.global
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

                HoverTip {
                    target: _reset
                    shown: _resetArea.containsMouse
                    text: "Stop setting this in " + (root._profile?.name ?? "this profile")
                        + ": it then follows the profiles above it, or the default."
                }
            }

            // Bool: a switch on the header row
            Rectangle {
                visible: root.entry?.type === "bool"
                width: 36
                height: 20
                radius: 10
                opacity: root._dimmed ? 0.5 : 1
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

        Text {
            visible: (root.entry?.hint ?? "") !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.entry?.hint ?? ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textTertiary
        }

        // Number: a whole number within the schema's range, with its unit
        Row {
            visible: root.entry?.type === "number"
            spacing: 6

            Rectangle {
                width: 90
                height: 26
                radius: 6
                color: Theme.cellDefault
                border.width: _numberInput.activeFocus && !_numberInput.acceptableInput ? 1 : 0
                border.color: Theme.textError

                TextInput {
                    id: _numberInput
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    text: root.shownValue ?? ""
                    opacity: root._dimmed && !activeFocus ? 0.5 : 1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: acceptableInput ? Theme.textPrimary : Theme.textError
                    verticalAlignment: TextInput.AlignVCenter
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: root.entry?.min ?? 0; top: root.entry?.max ?? 2147483647 }
                    onEditingFinished: {
                        if (acceptableInput && parseInt(text) !== root.shownValue)
                            root.edited(parseInt(text));
                    }
                    onActiveFocusChanged: if (!activeFocus) text = Qt.binding(() => root.shownValue ?? "")
                }
            }

            Text {
                visible: (root.entry?.suffix ?? "") !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: root.entry?.suffix ?? ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
            }
        }

        // Slider: a bounded whole number, dragged
        SettingSlider {
            visible: root.entry?.type === "slider"
            width: parent.width
            label: ""
            sliderRatio: 1.0
            from: root.entry?.min ?? 0
            to: root.maximum ?? root.entry?.max ?? 100
            suffix: root.entry?.suffix ?? ""
            // Only a slider's own value: the hidden slider of another type would be handed
            // a string or a list
            value: root.entry?.type === "slider" ? (root.shownValue ?? 0) : 0
            opacity: root._dimmed ? 0.5 : 1
            onValueEdited: newValue => root.edited(newValue)
        }

        // List of texts: one field per entry, saved as a whole list when one is edited,
        // removed or added — editing an inherited list copies it into this profile
        Column {
            id: _listEditor
            visible: root.entry?.type === "stringList"
            width: parent.width
            spacing: 4
            opacity: root._dimmed ? 0.6 : 1

            readonly property var items: Array.isArray(root.shownValue) ? root.shownValue : []

            function replaced(index, text) {
                const list = items.slice();
                if (text === null)
                    list.splice(index, 1);
                else
                    list[index] = text;
                root.edited(list);
            }

            Repeater {
                // ScriptModel, never a bare array — see "The Repeater crash"
                model: ScriptModel {
                    values: _listEditor.items.map((text, index) => ({ text: text, index: index }))
                }

                Row {
                    id: _listRow
                    required property var modelData
                    width: _listEditor.width
                    spacing: 4

                    Rectangle {
                        width: _listRow.width - 28
                        height: 26
                        radius: 6
                        color: Theme.cellDefault

                        TextInput {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            text: _listRow.modelData.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textPrimary
                            verticalAlignment: TextInput.AlignVCenter
                            selectByMouse: true
                            clip: true
                            onEditingFinished: {
                                if (text !== _listRow.modelData.text)
                                    _listEditor.replaced(_listRow.modelData.index, text);
                            }
                        }
                    }

                    Rectangle {
                        width: 24
                        height: 26
                        radius: 4
                        color: _removeArea.containsMouse ? Theme.cellHover : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.textDim
                        }

                        MouseArea {
                            id: _removeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: _listEditor.replaced(_listRow.modelData.index, null)
                        }
                    }
                }
            }

            Rectangle {
                width: _addText.implicitWidth + 16
                height: 24
                radius: 6
                color: _addArea.containsMouse ? Theme.cellHover : Theme.cellDefault

                Text {
                    id: _addText
                    anchors.centerIn: parent
                    text: "+ Add"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                }

                MouseArea {
                    id: _addArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.edited(_listEditor.items.concat([""]))
                }
            }
        }

        // Text: saved when editing finishes; an inherited value is shown dimmed
        Rectangle {
            visible: root.entry?.type === "string"
            width: parent.width
            height: 26
            radius: 6
            color: Theme.cellDefault

            TextInput {
                id: _textInput
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                text: root.shownValue ?? ""
                opacity: root._dimmed && !activeFocus ? 0.5 : 1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textPrimary
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                clip: true
                onEditingFinished: {
                    if (text !== root.shownValue)
                        root.edited(text);
                }
                // Back to the stored value when focus leaves without a change being saved
                onActiveFocusChanged: if (!activeFocus) text = Qt.binding(() => root.shownValue ?? "")
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
                    opacity: selected && root._dimmed ? 0.5 : 1
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
