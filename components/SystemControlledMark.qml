import QtQuick
import qs.singletons

// Marks a setting the system's configuration sets itself, so the shell cannot change it: the
// NixOS logo, its tooltip saying so. It stands beside the setting's control, which is shown
// disabled; the row itself carries no explanation. Hidden while `shown` is false.
Text {
    id: root

    property bool shown: true
    // Drawn with its tooltip open, as under the pointer (a mockup's preview)
    property bool shownLit: false
    readonly property string tip: "This setting is controlled by your system configuration"

    visible: shown
    // Nerd Font: the NixOS logo
    text: ""
    font.family: Theme.fontFamily
    // NixOS's own brand colour (its logo's light blue), fixed: the logo is NixOS's, not the
    // theme's. A thin black outline keeps it readable on light surfaces
    readonly property color nixosBlue: "#7ebae4"
    readonly property color outline: "#000000"

    // A size up from the text beside it; never dimmed with the disabled control it stands
    // beside
    font.pixelSize: Theme.fontSizeBodyLarge
    color: nixosBlue
    style: Text.Outline
    styleColor: outline

    MouseArea {
        id: _area
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    HoverTip {
        objectName: "systemControlledTip"
        target: root
        shown: root.visible && (_area.containsMouse || root.shownLit)
        delay: root.shownLit ? 0 : 500
        text: root.tip
    }
}
