import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.components

// The hardware sources a capsule or the popup shows: reorder by dragging, add, remove,
// and per source a label of its own (empty for the default, a space for none).
ReorderList {
    id: root

    property var model: []
    // Labels by source id; edits come back through labelsEdited, and the owner decides
    // where they are stored (a preset for the capsule, a profile for the popup)
    property var labels: ({})

    signal listChanged(var newList)
    signal labelsEdited(var newLabels)

    items: model ?? []
    addLabel: "＋ Add source"
    // Compared by source, not id: "gpu" in an older config is the same source as its
    // "gpu@<slot>"
    addOptions: Hardware.sourceIds.filter(id =>
        !items.some(listed => Hardware.sourceForId(listed) === Hardware.sourceForId(id)) &&
        (Hardware.sourceForId(id)?.available ?? false))
    optionLabel: id => Hardware.sourceForId(id)?.label ?? id

    onMoved: (from, to) => {
        const list = (model ?? []).slice()
        list.splice(to, 0, list.splice(from, 1)[0])
        listChanged(list)
    }
    onRemoved: index => {
        const list = (model ?? []).slice()
        list.splice(index, 1)
        listChanged(list)
    }
    onAdded: id => listChanged((model ?? []).concat([id]))

    function _getLabel(sourceId) {
        return labels?.[sourceId] ?? ""
    }

    function _setLabel(sourceId, label) {
        const newLabels = Object.assign({}, labels ?? {})
        if (label === "")
            delete newLabels[sourceId]
        else
            newLabels[sourceId] = label
        labelsEdited(newLabels)
    }

    // The source's label, edited in place; its default name shows while empty
    rowContent: Item {
        id: _content
        property var value
        property int index

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            // As tall as a line of its text, never less than 22 px
            height: Math.max(22, _labelInput.implicitHeight + 6)
            radius: Theme.field.radius
            color: _labelInput.activeFocus
                ? Theme.fill
                : _labelHover.containsMouse
                    ? Theme.fillSubtle
                    : "transparent"

            Text {
                anchors { fill: parent; leftMargin: 4 }
                verticalAlignment: Text.AlignVCenter
                text: Hardware.sourceForId(_content.value)?.label ?? _content.value ?? ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textDisabled
                visible: _labelInput.text === "" && !_labelInput.activeFocus
            }

            TextInput {
                id: _labelInput
                selectionColor: Theme.selection
                selectedTextColor: Theme.selectedText
                anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                verticalAlignment: Text.AlignVCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textPrimary
                selectByMouse: true
                clip: true

                // The label follows the list and the labels, except while being typed
                readonly property string _saved: root._getLabel(_content.value)
                on_SavedChanged: if (!activeFocus) text = _saved
                Component.onCompleted: text = _saved

                // Whitespace alone is kept as a single space: it is how a label is left
                // blank, while an empty field goes back to the default label
                onEditingFinished: root._setLabel(_content.value,
                    text !== "" && text.trim() === "" ? " " : text.trim())
            }

            MouseArea {
                id: _labelHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.IBeamCursor
                onClicked: _labelInput.forceActiveFocus()
                enabled: !_labelInput.activeFocus
            }
        }
    }
}
