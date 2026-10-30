import QtQuick
import qs.singletons

// Draggable vertical slider. Bottom = 0, top = maxValue.
// Emits moved(newValue) on drag and scroll; caller is responsible for
// applying the value (e.g. setting Audio.sink.audio.volume).
Item {
    id: slider

    property real value: 0
    property real maxValue: 1.5
    // Fill switches from sliderAccent to textWarning above this value
    property real warningThreshold: 1.0
    property real step: 0.02

    signal moved(real newValue)

    // The value as drawn: it follows changes from elsewhere (volume keys, another app)
    // smoothly, and the pointer at once while dragging
    property real _shownValue: value
    Behavior on _shownValue {
        enabled: !dragArea.pressed
        NumberAnimation { duration: Theme.duration("value"); easing: Theme.curve("value") }
    }
    readonly property real normalized: Math.min(_shownValue / maxValue, 1.0)
    // Leave 6 px at top + bottom so the thumb can overhang the track ends
    readonly property real trackH: height - 12
    readonly property real fillH: normalized * trackH
    // Y-offset on the track where warningThreshold sits
    readonly property real markPos: trackH * (warningThreshold / maxValue)

    // Track background
    Rectangle {
        x: (parent.width - width) / 2
        y: 6
        width: 6
        height: slider.trackH
        radius: width / 2
        color: Theme.textDisabled

        // Normal fill (0 – warningThreshold)
        Rectangle {
            id: normalFill
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.min(slider.fillH, slider.markPos)
            radius: parent.radius
            color: Theme.accent
        }

        // Over fill (warningThreshold – maxValue), stacked above normal fill
        Rectangle {
            anchors.bottom: normalFill.top
            width: parent.width
            height: Math.max(0, slider.fillH - slider.markPos)
            radius: parent.radius
            color: Theme.warning
        }
    }

    // Thumb
    Rectangle {
        x: (parent.width - width) / 2
        y: 6 + slider.trackH - slider.fillH - height / 2
        width: 12
        height: 12
        radius: width / 2
        color: dragArea.pressed ? Theme.textSecondary : Theme.textPrimary
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        onPressed: mouse => setVal(mouse.y)
        onPositionChanged: mouse => { if (pressed) setVal(mouse.y) }
        onWheel: event => {
            var delta = event.angleDelta.y / 120 * slider.step
            slider.moved(Math.max(0, Math.min(slider.maxValue, slider.value + delta)))
        }

        function setVal(mouseY) {
            var frac = 1.0 - Math.max(0, Math.min(1, (mouseY - 6) / slider.trackH))
            slider.moved(frac * slider.maxValue)
        }
    }
}
