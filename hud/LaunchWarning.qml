import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

// A banner under the bar when the shell was not started through scripts/launch.sh: the
// icon theme setting cannot apply then (Quickshell reads the theme only at launch, from
// QS_ICON_THEME, which the script sets). It says so and how to start the shell instead,
// and does not restart anything itself — a restart would drop whatever arguments the
// shell was started with. Closed with ×, for this run of the shell.
Rectangle {
    id: root

    visible: !IconThemes.launchedByScript && !IconThemes.launchWarningDismissed

    implicitWidth: Math.min(640, (parent?.width ?? 640) - 2 * Theme.osdToast.screenGap)
    implicitHeight: _content.implicitHeight + 2 * Theme.osdToast.padding
    radius: Theme.osdToast.radius
    color: Theme.surface
    border.width: Theme.border.selectedWidth
    border.color: Theme.warning

    RowLayout {
        id: _content
        anchors.fill: parent
        anchors.margins: Theme.osdToast.padding
        spacing: 10

        Text {
            Layout.alignment: Qt.AlignTop
            text: "󰀦"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSection
            color: Theme.warning
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: "The shell was started without scripts/launch.sh"
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
                color: Theme.textPrimary
            }

            Text {
                Layout.fillWidth: true
                text: "Quickshell reads the icon theme only when it starts, from QS_ICON_THEME, and the script "
                    + "sets that from Settings → General → Icon theme. Started directly (qs, qs -c default), "
                    + "the shell has no icon theme: the setting does nothing and icons such as warnings may be "
                    + "missing. Start it with " + Quickshell.shellDir + "/scripts/launch.sh — Hyprland's autostart "
                    + "does — or restart it with launch.sh --restart."
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
            }
        }

        Text {
            Layout.alignment: Qt.AlignTop
            text: "×"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSection
            color: _closeArea.containsMouse ? Theme.textPrimary : Theme.textSecondary

            MouseArea {
                id: _closeArea
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: IconThemes.launchWarningDismissed = true
            }
        }
    }
}
