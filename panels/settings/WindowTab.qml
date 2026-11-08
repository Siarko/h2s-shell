import QtQuick
import qs.components
import qs.singletons

// A tab at the top of the settings window: what the window edits
Rectangle {
    property string label
    property bool picked: false
    signal clicked

    width: _tabLabel.implicitWidth + 2 * Theme.settings.tabHorizontalPadding
    height: 28
    radius: Theme.settings.tabRadius
    color: picked ? Theme.accentSecondaryTint : (_tabArea.lit ? Theme.fillSubtle : Qt.alpha(Theme.fillSubtle, 0))
    border.width: picked ? Theme.border.width : 0
    border.color: Theme.accent
    Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }

    Text {
        id: _tabLabel
        anchors.centerIn: parent
        text: parent.label
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBodyLarge
        font.bold: parent.picked
        color: parent.picked ? Theme.textPrimary : Theme.textSecondary
    }

    PointerArea {
        id: _tabArea
        centred: false
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: parent.clicked()
    }
}
