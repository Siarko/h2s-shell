import QtQuick
import QtQuick.Layouts
import qs.singletons

// Notification settings, edited in the profile picked in the settings window
ColumnLayout {
    id: root

    // The profile being edited, picked in the settings window
    property int editIndex: -1

    anchors {
        fill: parent
        margins: 14
    }
    spacing: 0

    Text {
        text: "Notifications"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeHeading
        font.bold: true
        color: Theme.textSecondary
        Layout.bottomMargin: 8
    }

    Text {
        text: "Regex patterns to extract codes (e.g. 2FA) from incoming notifications."
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textSecondary
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        Layout.bottomMargin: 10
    }

    SchemaSettingEditor {
        key: "notifications.codePatterns"
        editIndex: root.editIndex
    }

    Item {
        Layout.fillHeight: true
    }
}
