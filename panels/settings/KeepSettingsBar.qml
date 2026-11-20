import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons
import qs.singletons.network

// "Keep these settings?" after a profile was saved and reconnected (NetworkProfiles
// .saveConnection): the seconds left, Keep and Revert. Shown in the connection editor and
// on the Wi-Fi and Ethernet pages, so leaving the editor during the countdown still shows
// it; with no answer the old settings come back.
Rectangle {
    id: root

    visible: NetworkProfiles.pendingUndo !== null
    implicitHeight: visible ? _row.implicitHeight + 16 : 0
    radius: Theme.settings.cardRadius
    color: Qt.alpha(Theme.warning, 0.15)
    border.width: Theme.border.width
    border.color: Theme.warning

    RowLayout {
        id: _row
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
        spacing: 8
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Keep the new settings of " + (NetworkProfiles.pendingUndo?.name ?? "") + "? The old ones come back in "
                + NetworkProfiles.undoSecondsLeft + " s."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textPrimary
        }
        SmallButton { label: "Keep"; kind: "save"; onClicked: NetworkProfiles.keepChanges() }
        SmallButton { label: "Revert"; onClicked: NetworkProfiles.revertChanges() }
    }
}
