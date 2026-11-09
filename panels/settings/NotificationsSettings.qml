import QtQuick
import QtQuick.Layouts
import qs.singletons

// Notification settings, edited in the profile picked in the settings window
ColumnLayout {
    id: root

    // The profile being edited, picked in the settings window
    property int editIndex: -1

    readonly property bool _toastsOn: Profiles.editedValue(editIndex, "notifications.toasts") !== false
    readonly property bool _column: Profiles.editedValue(editIndex, "notifications.toastLayout") === "column"
    readonly property bool _elsewhere: Profiles.editedValue(editIndex, "notifications.toastFullscreen") === "elsewhere"

    anchors {
        fill: parent
        margins: Theme.settings.pageMargin
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

    SchemaSettingEditor { key: "notifications.toasts"; editIndex: root.editIndex }
    SchemaSettingEditor { key: "notifications.toastDuration"; editIndex: root.editIndex; available: root._toastsOn }
    SchemaSettingEditor { key: "notifications.toastLayout"; editIndex: root.editIndex; available: root._toastsOn }
    SchemaSettingEditor {
        key: "notifications.toastColumnSize"
        editIndex: root.editIndex
        available: root._toastsOn && root._column
    }
    SchemaSettingEditor { key: "notifications.toastScreen"; editIndex: root.editIndex; available: root._toastsOn }
    SchemaSettingEditor { key: "notifications.toastFullscreen"; editIndex: root.editIndex; available: root._toastsOn }
    SchemaSettingEditor {
        key: "notifications.toastFullscreenScreen"
        editIndex: root.editIndex
        available: root._toastsOn && root._elsewhere
    }

    Text {
        Layout.topMargin: 12
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
