import QtQuick
import qs.components
import qs.singletons

// What deleting an event of a series deletes: this one, this and the ones after it, or
// the whole series — three different deletions, so a choice rather than DeleteButton's
// one question. `chosen` says which ("this", "following", "all").
Column {
    id: root

    signal chosen(string which)
    signal cancelled

    spacing: 4

    component Choice: Text {
        id: _choice
        property bool main: true
        signal clicked
        color: _area.lit ? Theme.textPrimary : (main ? Theme.accent : Theme.textSecondary)
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.bold: main

        PointerArea {
            id: _area
            cursorShape: Qt.PointingHandCursor
            onClicked: _choice.clicked()
        }
    }

    Text {
        text: "Delete:"
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    Repeater {
        model: [
            { which: "this", label: "- This event" },
            { which: "following", label: "- This and following" },
            { which: "all", label: "- All events" }
        ]
        Choice {
            required property var modelData
            text: modelData.label
            onClicked: root.chosen(modelData.which)
        }
    }

    Choice {
        main: false
        text: "- Cancel"
        onClicked: root.cancelled()
    }
}
