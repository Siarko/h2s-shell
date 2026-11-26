import QtQuick
import qs.singletons

// An on/off switch: a track filled with the accent when on, and a knob sliding to that
// side. Reports a click with `toggled`; the owner changes `checked` (it follows the value
// it shows, which may change elsewhere). Small by default, as in the settings; popups use
// a larger one (width 44, height 24). Every size and place draws the same colours: the off
// track is the theme's switchOff, which stands out from the popup, settings and card
// backgrounds alike, so no caller picks one for its background.
Rectangle {
    id: root

    property bool checked: false
    signal toggled

    // The track's colour now: by `checked`, lighter under the pointer
    readonly property color trackColor: _area.lit
        ? (checked ? Theme.accentHover : Theme.switchOffHover)
        : (checked ? Theme.accent : Theme.switchOff)
    // The knob: light or dark, whichever stands out from the track it is on
    readonly property color knobColor: ThemeRules.switchKnob(trackColor, [Theme.textPrimary, Theme.popupBackground])

    implicitWidth: 36
    implicitHeight: 20
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    // Not enabled, it is dimmed as a button that is not available
    opacity: enabled ? 1 : 0.35
    color: trackColor
    Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }

    Rectangle {
        x: root.checked ? root.width - width - 2 : 2
        anchors.verticalCenter: parent.verticalCenter
        width: root.height - 4
        height: width
        radius: width / 2
        color: root.knobColor
        Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }
        Behavior on x { NumberAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }
    }

    // At least Theme.target.minSize round it: a 24 px switch is small for a finger
    PointerArea {
        id: _area
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
