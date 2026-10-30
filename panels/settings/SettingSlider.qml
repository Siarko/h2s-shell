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
    property bool disabled: false   // fully disables interaction
    property real sliderRatio: 0.5  // 0.0–1.0; fraction of row width given to slider track
    property string tooltip: ""     // optional hover tooltip text; empty = no tooltip
    property bool tooltipIcon: false // if true, show ⓘ icon next to label; tooltip triggers on icon hover only
    signal valueEdited(int newValue)

    Layout.fillWidth: true
    Layout.preferredHeight: 36
    opacity: slider.disabled ? 0.35 : 1.0
    z: _tooltip.visible ? 1 : 0

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
                onHoveredChanged: {
                    if (hovered) {
                        _tooltipTimer.start();
                    } else {
                        _tooltipTimer.stop();
                        _tooltip.visible = false;
                    }
                }
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

        // Base track
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: _trackArea.containsMouse ? Theme.textSecondary : Theme.textDisabled
            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

            // Locked region overlay (from → lockedFrom)
            Rectangle {
                width: parent.parent._lockedPos * parent.width
                height: parent.height
                radius: 2
                color: Theme.accentTint
                visible: parent.parent._lockedPos > 0
            }

            // Fill (lockedFrom → value)
            Rectangle {
                x: parent.parent._lockedPos * parent.width
                width: Math.max(0, (parent.parent._pos - parent.parent._lockedPos) * parent.width)
                height: parent.height
                radius: 2
                color: _trackArea.containsMouse ? Theme.accentHover : Theme.accent
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
            }
        }

        // Thumb
        Rectangle {
            x: parent._pos * (parent.width - width)
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
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

            property real scrollBuffer: 0
            property real lastScrollAmount: 0

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

    // Tooltip — zero-size layout item so the floating Rectangle doesn't affect row geometry
    Item {
        id: _tooltipAnchor
        Layout.preferredWidth: 0
        Layout.preferredHeight: 0
        Layout.maximumWidth: 0
        Layout.maximumHeight: 0

        Rectangle {
            id: _tooltip
            visible: false
            z: 999
            width: _tooltipText.width + 16
            height: _tooltipText.contentHeight + 12
            color: Theme.surface
            border.color: Theme.textDisabled
            border.width: 1
            radius: 4

            // Unified position source: icon centre in icon mode, live cursor otherwise
            readonly property real _tipX: slider.tooltipIcon ? _infoIcon.mapToItem(slider, _infoIcon.width / 2, 0).x : _hoverHandler.point.position.x
            readonly property real _tipY: slider.tooltipIcon ? _infoIcon.mapToItem(slider, 0, 0).y : _hoverHandler.point.position.y

            // x: centered on tip, clamped so tooltip stays within the row's horizontal extent
            x: Math.max(-_tooltipAnchor.x, Math.min(slider.width - _tooltipAnchor.x - width, _tipX - _tooltipAnchor.x - width / 2))

            // y: above tip by default; flip below if that would leave the window
            y: {
                var aboveY = _tipY - _tooltipAnchor.y - height - 15;
                var sceneTop = slider.mapToItem(null, 0, _tooltipAnchor.y + aboveY).y;
                return sceneTop < 0 ? _tipY - _tooltipAnchor.y + 40 : aboveY;
            }

            Text {
                id: _tooltipText
                x: 8
                y: 6
                text: slider.tooltip
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textPrimary
                wrapMode: Text.WordWrap
                width: Math.min(implicitWidth, 200)
            }
        }
    }

    HoverHandler {
        id: _hoverHandler
        enabled: !slider.tooltipIcon
        onHoveredChanged: {
            if (hovered && slider.tooltip !== "") {
                _tooltipTimer.start();
            } else {
                _tooltipTimer.stop();
                _tooltip.visible = false;
            }
        }
    }

    Timer {
        id: _tooltipTimer
        interval: 1000
        onTriggered: _tooltip.visible = true
    }
}
