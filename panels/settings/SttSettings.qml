import QtQuick
import QtQuick.Layouts
import qs.singletons

Flickable {
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

        SettingBool {
            label: "Show recognized text"
            value: Config.stt.previewEnabled
            onValueChanged: Config.stt.previewEnabled = value
        }

        SettingSlider {
            label: "Preview width"
            tooltip: "How far the widget slides open while dictation is running. "
                   + "At rest it collapses back to just the microphone icon."
            tooltipIcon: true
            disabled: !Config.stt.previewEnabled
            from: 0
            to: 600
            suffix: "px"
            value: Config.stt.previewWidth
            onValueEdited: newValue => Config.stt.previewWidth = newValue
        }

        SettingIntInput {
            label: "Keep typed text visible for"
            disabled: !Config.stt.previewEnabled
            from: 0
            suffix: "ms"
            value: Config.stt.finalLingerMs
            onValueEdited: newValue => Config.stt.finalLingerMs = newValue
        }

        SettingBool {
            label: "Show pending fragment counter"
            value: Config.stt.showPending
            onValueChanged: Config.stt.showPending = value
        }

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

        SettingBool {
            label: "Pause while dictating"
            value: Config.stt.pauseMusicWhileDictating
            onValueChanged: Config.stt.pauseMusicWhileDictating = value
        }

        Text {
            text: "Speaker output reaches the microphone and gets transcribed. Only a "
                + "pause the shell applied is resumed afterwards."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textTertiary
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

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

        SettingInputRow {
            label: "Socket path"
            inputWidthPercent: 50
            value: Config.stt.socketPath
            onValueChanged: Config.stt.socketPath = value
        }

        Text {
            text: "Leave empty to use $XDG_RUNTIME_DIR/ptt/ctl.sock"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textTertiary
            Layout.bottomMargin: 6
        }

        SettingBool {
            label: "Debug log"
            value: Config.stt.debug
            onValueChanged: Config.stt.debug = value
        }

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
