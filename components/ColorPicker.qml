import QtQuick
import qs.singletons

// Picks a colour: saturation and brightness in the square, hue and opacity in the bars
// beside it, or typed as hex (#rrggbb, or #aarrggbb with opacity). Works in hue,
// saturation and value, kept apart from `color`, so the hue survives a trip through grey
// or black. `edited` fires while dragging, `committed` once a drag ends or a hex is typed.
Item {
    id: root

    // The colour shown; set from outside, it moves the controls unless one is being dragged
    property color color: Qt.hsva(0, 0, 1, 1)
    signal edited(color color)
    signal committed(color color)

    property real _hue: 0
    property real _saturation: 0
    property real _value: 1
    property real _alpha: 1
    // A control is being dragged: changes of `color` from outside do not move it then
    property bool _dragging: false

    implicitWidth: 300
    implicitHeight: 150

    function _setFrom(value) {
        // A grey has no hue of its own, black no saturation: keep the ones there were
        if (value.hsvSaturation > 0 && value.hsvValue > 0)
            _hue = Math.max(0, value.hsvHue);
        if (value.hsvValue > 0)
            _saturation = value.hsvSaturation;
        _value = value.hsvValue;
        _alpha = value.a;
    }

    function _fromColor() {
        if (!_dragging)
            _setFrom(color);
    }
    onColorChanged: _fromColor()
    Component.onCompleted: _fromColor()

    readonly property color _picked: Qt.hsva(_hue, _saturation, _value, _alpha)

    function _emitEdited() {
        edited(_picked);
    }

    // The hex form: #rrggbb when opaque, #aarrggbb otherwise
    function hexOf(value) {
        return String(value);
    }

    Row {
        spacing: 10

        // ── Saturation across, brightness up ──
        Item {
            id: _square
            width: 150
            height: 150

            // White to the pure hue, then darkened towards black: the HSV model itself, not
            // colours of the look
            Rectangle {
                anchors.fill: parent
                radius: 4
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.hsva(0, 0, 1, 1) }
                    GradientStop { position: 1; color: Qt.hsva(root._hue, 1, 1, 1) }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: 4
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.hsva(0, 0, 0, 0) }
                    GradientStop { position: 1; color: Qt.hsva(0, 0, 0, 1) }
                }
            }
            Rectangle {
                x: root._saturation * _square.width - width / 2
                y: (1 - root._value) * _square.height - height / 2
                width: 12
                height: 12
                radius: 6
                color: "transparent"
                border.width: 2
                border.color: root._value > 0.5 ? Theme.markOnLight : Theme.markOnDark
            }

            MouseArea {
                anchors.fill: parent
                preventStealing: true
                function pick(mouse) {
                    root._saturation = Math.max(0, Math.min(1, mouse.x / width));
                    root._value = Math.max(0, Math.min(1, 1 - mouse.y / height));
                    root._emitEdited();
                }
                onPressed: mouse => { root._dragging = true; pick(mouse) }
                onPositionChanged: mouse => pick(mouse)
                onReleased: { root._dragging = false; root.committed(root._picked) }
                // A press taken away (the window hidden mid-drag) must not leave the picker
                // ignoring changes from outside
                onCanceled: root._dragging = false
            }
        }

        // ── Hue, top to bottom ──
        Item {
            id: _hueBar
            width: 16
            height: 150

            Rectangle {
                anchors.fill: parent
                radius: 4
                gradient: Gradient {
                    GradientStop { position: 0 / 6; color: Qt.hsva(0, 1, 1, 1) }
                    GradientStop { position: 1 / 6; color: Qt.hsva(1 / 6, 1, 1, 1) }
                    GradientStop { position: 2 / 6; color: Qt.hsva(2 / 6, 1, 1, 1) }
                    GradientStop { position: 3 / 6; color: Qt.hsva(3 / 6, 1, 1, 1) }
                    GradientStop { position: 4 / 6; color: Qt.hsva(4 / 6, 1, 1, 1) }
                    GradientStop { position: 5 / 6; color: Qt.hsva(5 / 6, 1, 1, 1) }
                    GradientStop { position: 6 / 6; color: Qt.hsva(0, 1, 1, 1) }
                }
            }
            Rectangle {
                x: -2
                y: root._hue * _hueBar.height - height / 2
                width: _hueBar.width + 4
                height: 4
                radius: 2
                color: Theme.markOnDark
                border.width: 1
                border.color: Theme.markOnLight
            }

            MouseArea {
                anchors.fill: parent
                preventStealing: true
                function pick(mouse) {
                    root._hue = Math.max(0, Math.min(0.999, mouse.y / height));
                    root._emitEdited();
                }
                onPressed: mouse => { root._dragging = true; pick(mouse) }
                onPositionChanged: mouse => pick(mouse)
                onReleased: { root._dragging = false; root.committed(root._picked) }
                // A press taken away (the window hidden mid-drag) must not leave the picker
                // ignoring changes from outside
                onCanceled: root._dragging = false
            }
        }

        // ── Opacity, top to bottom ──
        Item {
            id: _alphaBar
            width: 16
            height: 150

            Checkerboard {
                anchors.fill: parent
            }
            Rectangle {
                anchors.fill: parent
                radius: 4
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.hsva(root._hue, root._saturation, root._value, 1) }
                    GradientStop { position: 1; color: Qt.hsva(root._hue, root._saturation, root._value, 0) }
                }
            }
            Rectangle {
                x: -2
                y: (1 - root._alpha) * _alphaBar.height - height / 2
                width: _alphaBar.width + 4
                height: 4
                radius: 2
                color: Theme.markOnDark
                border.width: 1
                border.color: Theme.markOnLight
            }

            MouseArea {
                anchors.fill: parent
                preventStealing: true
                function pick(mouse) {
                    root._alpha = Math.round(Math.max(0, Math.min(1, 1 - mouse.y / height)) * 100) / 100;
                    root._emitEdited();
                }
                onPressed: mouse => { root._dragging = true; pick(mouse) }
                onPositionChanged: mouse => pick(mouse)
                onReleased: { root._dragging = false; root.committed(root._picked) }
                // A press taken away (the window hidden mid-drag) must not leave the picker
                // ignoring changes from outside
                onCanceled: root._dragging = false
            }
        }

        // ── Before and after, and the hex ──
        Column {
            spacing: 8
            // Wide enough for the longest hex (#aarrggbb) and its padding
            width: Math.max(90, Math.ceil(_widestHex.advanceWidth) + 18)

            TextMetrics {
                id: _widestHex
                font: _hexInput.input.font
                text: "#88888888"
            }

            Rectangle {
                width: parent.width
                height: 40
                radius: 6
                color: root._picked
                border.width: 1
                border.color: Theme.outline
            }

            InputField {
                id: _hexInput
                width: parent.width
                readonly property bool valid: /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(text)
                problem: !valid && !editing
                text: root.hexOf(root._picked)
                input.maximumLength: 9
                onEditingFinished: {
                    // Only a different colour: focus merely leaving must not turn an
                    // inherited colour into one set here. Compared as hex text:
                    // Qt.colorEqual tells an HSV colour from the same colour in RGB.
                    const typed = String(Qt.color(text)).toLowerCase();
                    if (valid && typed !== root.hexOf(root._picked).toLowerCase()
                            && typed !== root.hexOf(root.color).toLowerCase()) {
                        root._setFrom(Qt.color(text));
                        root.committed(root._picked);
                    }
                    text = Qt.binding(() => root.hexOf(root._picked));
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Opacity " + Math.round(root._alpha * 100) + "%"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }
        }
    }
}
