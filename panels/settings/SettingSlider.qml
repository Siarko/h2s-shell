import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.components

RowLayout {
    id: slider
    property string label
    property int value
    property int from: 0
    property int to: 100
    property string suffix: ""
    property int lockedFrom: from   // thumb cannot go below this; region shown as locked
    // Optional resting value inside the range (0 on a −360…360 speed, say): the fill runs
    // from it to the value, either way, and a tick marks it. Unset, the fill runs from the
    // start (or lockedFrom).
    property var neutral: undefined
    property bool disabled: false   // fully disables interaction
    property real sliderRatio: 0.5  // 0.0–1.0; fraction of row width given to slider track
    property string tooltip: ""     // optional hover tooltip text; empty = no tooltip
    property bool tooltipIcon: false // if true, show ⓘ icon next to label; tooltip triggers on icon hover only
    signal valueEdited(int newValue)

    Layout.fillWidth: true
    Layout.preferredHeight: 36
    opacity: slider.disabled ? 0.35 : 1.0

    function nudge(delta) {
        var val = Math.max(from, Math.min(to, value + delta));
        if (val < slider.lockedFrom) {
            return;
        }
        slider.valueEdited(val);
    }

    RowLayout {
        spacing: 4
        visible: slider.sliderRatio < 1.0
        Layout.fillWidth: slider.sliderRatio < 1.0
        Layout.preferredWidth: (1 - slider.sliderRatio) * 1000
        Text {
            id: _infoIcon
            text: "󰋽 "
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: _iconHover.hovered ? Theme.textPrimary : Theme.textSecondary
            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
            visible: slider.tooltipIcon && slider.tooltip !== ""

            HoverHandler {
                id: _iconHover
            }
        }

        Text {
            text: slider.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: Theme.textPrimary
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredWidth: slider.sliderRatio * 1000
        Layout.preferredHeight: 20

        readonly property real _pos: (slider.value - slider.from) / Math.max(1, slider.to - slider.from)
        readonly property real _lockedPos: (Math.max(slider.from, Math.min(slider.lockedFrom, slider.to)) - slider.from) / Math.max(1, slider.to - slider.from)
        readonly property bool _hasNeutral: typeof slider.neutral === "number"
        // Where the fill starts: the neutral value, or the end of the locked region
        readonly property real _fillStart: _hasNeutral
            ? Math.max(_lockedPos, (Math.max(slider.from, Math.min(slider.neutral, slider.to)) - slider.from) / Math.max(1, slider.to - slider.from))
            : _lockedPos

        // Base track
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: height / 2
            color: _trackArea.containsMouse ? Theme.textSecondary : Theme.textDisabled
            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

            // Locked region overlay (from → lockedFrom)
            Rectangle {
                width: parent.parent._lockedPos * parent.width
                height: parent.height
                radius: height / 2
                color: Theme.accentTint
                visible: parent.parent._lockedPos > 0
            }

            // Fill: from its start (neutral or lockedFrom) to the value, whichever side
            Rectangle {
                x: Math.min(parent.parent._fillStart, parent.parent._pos) * parent.width
                width: Math.abs(parent.parent._pos - parent.parent._fillStart) * parent.width
                height: parent.height
                radius: height / 2
                color: _trackArea.containsMouse ? Theme.accentHover : Theme.accent
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
            }
        }

        // The neutral value's tick, across the track
        Rectangle {
            visible: parent._hasNeutral
            x: Math.round(parent._fillStart * parent.width - width / 2)
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: 10
            radius: 1
            color: Theme.textSecondary
        }

        // Thumb
        Rectangle {
            x: parent._pos * (parent.width - width)
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: width / 2
            color: _trackArea.pressed ? Theme.textSecondary : Theme.textPrimary
            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
        }

        CustomMouseArea {
            id: _trackArea
            anchors.fill: parent
            enabled: !slider.disabled
            hoverEnabled: true
            // Keeps the drag once started: otherwise vertical movement hands it to the
            // settings page's Flickable, which scrolls instead
            preventStealing: true
            cursorShape: Qt.PointingHandCursor

            onPressed: mouse => update(mouse.x)
            onPositionChanged: mouse => {
                if (pressed)
                    update(mouse.x);
            }
            onScrollNotchY: direction => slider.nudge(direction)

            function update(mouseX) {
                var pos = Math.max(parent._lockedPos, Math.min(1, mouseX / width));
                slider.valueEdited(Math.round(slider.from + pos * (slider.to - slider.from)));
            }
        }
    }

    Text {
        id: _valueText
        text: slider.value + slider.suffix
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textSecondary
        horizontalAlignment: Text.AlignRight
        // As wide as the widest value it can show, so the slider does not jump as it changes
        Layout.preferredWidth: Math.ceil(_widestValue.advanceWidth)
    }

    TextMetrics {
        id: _widestValue
        font: _valueText.font
        text: (String(slider.to).length >= String(slider.from).length ? slider.to : slider.from) + slider.suffix
    }

    // The tooltip, over the ⓘ icon when there is one, else over the whole row
    HoverHandler {
        id: _hoverHandler
        enabled: !slider.tooltipIcon
    }

    HoverTip {
        target: slider.tooltipIcon ? _infoIcon : slider
        shown: slider.tooltip !== "" && (slider.tooltipIcon ? _iconHover.hovered : _hoverHandler.hovered)
        text: slider.tooltip
        delay: 1000
        maxWidth: 200
    }
}
