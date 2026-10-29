import QtQuick
import QtQuick.Layouts
import qs.singletons

// Dictation settings, edited in the profile picked in the settings window. The socket
// path and the debug log are always global; the wake mode section is a read-only view
// of the daemon's own config.
Flickable {
    id: root

    // The profile being edited, picked in the settings window
    property int editIndex: -1

    // Whether the edited profile shows the preview, for greying out what depends on it
    readonly property bool _previewOn: ("stt.previewEnabled" in Profiles.effectiveGlobals
        ? Profiles.effectiveGlobals["stt.previewEnabled"]
        : (Profiles.profiles[editIndex]?.set?.["stt.previewEnabled"]
           ?? Profiles.inheritedValue(editIndex, "stt.previewEnabled"))) === true

    anchors.fill: parent
    contentHeight: col.implicitHeight
    clip: true

    ColumnLayout {
        id: col
        anchors {
            fill: parent
            margins: 14
        }
        spacing: 0

        Text {
            text: "Dictation"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.bottomMargin: 8
        }

        // ── Widget ────────────────────────────────────────────────────────

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 4
            color: Theme.textDim
            opacity: 0.3
        }

        Text {
            text: "Widget"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.topMargin: 10
            Layout.bottomMargin: 4
        }

        SchemaSettingEditor { key: "stt.previewEnabled"; editIndex: root.editIndex }
        SchemaSettingEditor { key: "stt.previewWidth"; editIndex: root.editIndex; available: root._previewOn }
        SchemaSettingEditor { key: "stt.finalLingerMs"; editIndex: root.editIndex; available: root._previewOn }
        SchemaSettingEditor { key: "stt.showPending"; editIndex: root.editIndex }

        // ── Music ─────────────────────────────────────────────────────────

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 10
            color: Theme.textDim
            opacity: 0.3
        }

        Text {
            text: "Music"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.topMargin: 10
            Layout.bottomMargin: 4
        }

        SchemaSettingEditor { key: "stt.pauseMusicWhileDictating"; editIndex: root.editIndex }

        // ── Connection ────────────────────────────────────────────────────

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 10
            color: Theme.textDim
            opacity: 0.3
        }

        Text {
            text: "Connection"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.topMargin: 10
            Layout.bottomMargin: 4
        }

        SchemaSettingEditor { key: "stt.socketPath"; editIndex: root.editIndex }
        SchemaSettingEditor { key: "stt.debug"; editIndex: root.editIndex }

        // ── Wake mode ─────────────────────────────────────────────────────
        // Owned by the daemon (~/.config/ptt/config.toml) and editable from the CLI,
        // so this is a live view of the last wake_config event, not shell config.

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 10
            color: Theme.textDim
            opacity: 0.3
        }

        Text {
            text: "Wake mode"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.topMargin: 10
            Layout.bottomMargin: 4
        }

        SettingInfoRow {
            label: "Daemon"
            value: Stt.connected ? "connected" : "not running"
            valueColor: Stt.connected ? Theme.sliderAccent : Theme.textDim
        }

        SettingInfoRow {
            label: "Whisper server"
            value: Stt.connected ? Stt.server : "—"
            valueColor: Stt.server === "error" ? Theme.textError
                      : Stt.server === "ready" ? Theme.sliderAccent
                      : Theme.textSecondary
        }

        SettingInfoRow {
            label: "Wake listening"
            value: Stt.wake ? "yes" : "no"
            valueColor: Stt.wake ? Theme.sliderAccent : Theme.textSecondary
        }

        SettingInfoRow {
            label: "Enabled at daemon start"
            value: Stt.wakeOnStart ? "yes" : "no"
        }

        SettingInfoRow {
            label: "Start phrases"
            value: Stt.startPhrases.length > 0 ? Stt.startPhrases.join(", ") : "—"
        }

        SettingInfoRow {
            label: "Stop phrases"
            value: Stt.stopPhrases.length > 0 ? Stt.stopPhrases.join(", ") : "—"
        }

        Text {
            text: "Read-only. Change with: ptt wake phrases start add \"…\", "
                + "ptt wake autostart on|off"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textTertiary
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.topMargin: 6
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
