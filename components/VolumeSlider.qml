import QtQuick
import QtQuick.Layouts
import qs.singletons

// Draggable volume slider built from basic QtQuick primitives
Item {
    id: slider
    Layout.fillWidth: true
    Layout.preferredHeight: 20

    property real value: 0
    property real maxValue: 1.5
    property color fillColor: Theme.accent
    property color fillColorHover: Theme.accentHover
    signal moved(real volume)

    property real step: 0.02
    // The value as drawn: it follows changes from elsewhere (volume keys, another app)
    // smoothly, and the pointer at once while dragging
    property real _shownValue: value
    Behavior on _shownValue {
        enabled: !sliderArea.pressed
        NumberAnimation { duration: Theme.duration("value"); easing.type: Theme.easing("value") }
    }
    property real _position: Math.min(1, _shownValue / maxValue)
    activeFocusOnTab: true

    function nudge(delta) {
        var vol = Math.max(0, Math.min(maxValue, value + delta));
        slider.moved(vol);
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: sliderArea.containsMouse ? Theme.textSecondary : Theme.textDisabled
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing.type: Theme.easing("hover") } }

        Rectangle {
            width: slider._position * parent.width
            height: parent.height
            radius: 2
            color: sliderArea.containsMouse ? slider.fillColorHover : slider.fillColor
        }
    }

    Rectangle {
        x: slider._position * (slider.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: 14; height: 14; radius: 7
        color: sliderArea.pressed ? Theme.textSecondary : Theme.textPrimary
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing.type: Theme.easing("hover") } }
    }

    MouseArea {
        id: sliderArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => { slider.forceActiveFocus(); update(mouse.x); }
        onPositionChanged: mouse => { if (pressed) update(mouse.x); }
        onWheel: event => slider.nudge(event.angleDelta.y / 120 * slider.step)

        function update(mouseX) {
            var pos = Math.max(0, Math.min(1, mouseX / width));
            slider.moved(pos * slider.maxValue);
        }
    }

    Keys.onLeftPressed: nudge(-step)
    Keys.onRightPressed: nudge(step)
}
