import QtQuick
import QtQuick.Layouts
import qs.singletons

RowLayout {
    id: _ss
    property string label
    property int value
    property int from: 0
    property int to: 100
    property string suffix: ""
    property int lockedFrom: from   // thumb cannot go below this; region shown as locked
    property bool disabled: false   // fully disables interaction
    signal valueEdited(int newValue)

    Layout.fillWidth: true
    Layout.preferredHeight: 36
    opacity: _ss.disabled ? 0.35 : 1.0

    Text {
        text: _ss.label
        font.family: Theme.fontFamily
        font.pixelSize: 13
        color: Theme.textPrimary
        Layout.fillWidth: true
    }

    Item {
        Layout.preferredWidth: 120
        Layout.preferredHeight: 20

        readonly property real _pos: (_ss.value - _ss.from) / Math.max(1, _ss.to - _ss.from)
        readonly property real _lockedPos: (Math.max(_ss.from, Math.min(_ss.lockedFrom, _ss.to)) - _ss.from) / Math.max(1, _ss.to - _ss.from)

        // Base track
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: _trackArea.containsMouse ? Theme.textSecondary : Theme.textDim

            // Locked region overlay (from → lockedFrom)
            Rectangle {
                width: parent.parent._lockedPos * parent.width
                height: parent.height
                radius: 2
                color: Qt.rgba(Theme.sliderAccent.r, Theme.sliderAccent.g, Theme.sliderAccent.b, 0.25)
                visible: parent.parent._lockedPos > 0
            }

            // Fill (lockedFrom → value)
            Rectangle {
                x: parent.parent._lockedPos * parent.width
                width: Math.max(0, (parent.parent._pos - parent.parent._lockedPos) * parent.width)
                height: parent.height
                radius: 2
                color: _trackArea.containsMouse ? Theme.sliderAccentHover : Theme.sliderAccent
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
        }

        MouseArea {
            id: _trackArea
            anchors.fill: parent
            enabled: !_ss.disabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => update(mouse.x)
            onPositionChanged: mouse => {
                if (pressed)
                    update(mouse.x);
            }

            function update(mouseX) {
                var pos = Math.max(parent._lockedPos, Math.min(1, mouseX / width));
                _ss.valueEdited(Math.round(_ss.from + pos * (_ss.to - _ss.from)));
            }
        }
    }

    Text {
        text: _ss.value + _ss.suffix
        font.family: Theme.fontFamily
        font.pixelSize: 12
        color: Theme.textSecondary
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: 36
    }
}
