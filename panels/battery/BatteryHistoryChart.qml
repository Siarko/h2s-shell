import QtQuick
import qs.singletons

// The battery's history, as Android shows it: the charge over the chosen span, the stretches
// spent on the charger shaded behind it, and the power drawn beneath. From UPower's record
// (BatteryHistory); the charge comes as a point at each percent it changes, so the line
// runs on flat from the last one to now.
Column {
    id: root

    property var charge: []
    property var rate: []
    // Seconds shown, back from now
    property int span: 24 * 3600
    // Paints only while true
    property bool active: true

    property double _now: Date.now() / 1000
    readonly property double _start: _now - span

    spacing: 4

    function _x(time, width) {
        return (time - root._start) / root.span * width;
    }

    function _repaint() {
        if (!active)
            return;
        root._now = Date.now() / 1000;
        _chargeCanvas.requestPaint();
        _rateCanvas.requestPaint();
    }
    onChargeChanged: _repaint()
    onRateChanged: _repaint()
    onSpanChanged: _repaint()
    onActiveChanged: _repaint()
    onWidthChanged: _repaint()

    // The newest stretch reaches now as time goes on
    Timer {
        interval: 60000
        repeat: true
        running: root.active
        onTriggered: root._repaint()
    }

    // ---- The charge ----
    Item {
        width: root.width
        height: 90

        Canvas {
            id: _chargeCanvas
            anchors.fill: parent
            onPaint: {
                const context = getContext("2d");
                context.reset();
                const width = this.width;
                const height = this.height;
                const points = root.charge.filter(point => point.t >= root._start - 1);

                // The grid: empty, half, full
                context.strokeStyle = Qt.alpha(Theme.textDisabled, 0.35);
                context.lineWidth = 1;
                for (const level of [0, 0.5, 1]) {
                    const y = Math.round(height - level * (height - 1)) - 0.5;
                    context.beginPath();
                    context.moveTo(0, y);
                    context.lineTo(width, y);
                    context.stroke();
                }
                if (points.length === 0)
                    return;

                // On the charger: from each point charging to the next one (or to now)
                context.fillStyle = Qt.alpha(Theme.warning, 0.18);
                for (let i = 0; i < points.length; i++) {
                    if (!BatteryRules.isCharging(points[i].state))
                        continue;
                    const from = Math.max(0, root._x(points[i].t, width));
                    const to = root._x(i + 1 < points.length ? points[i + 1].t : root._now, width);
                    context.fillRect(from, 0, Math.max(1, to - from), height);
                }

                // The line, run on flat to now, and the area under it
                const y = value => height - value / 100 * (height - 2) - 1;
                context.beginPath();
                context.moveTo(Math.max(0, root._x(points[0].t, width)), y(points[0].v));
                for (const point of points)
                    context.lineTo(root._x(point.t, width), y(point.v));
                context.lineTo(width, y(points[points.length - 1].v));
                context.strokeStyle = Theme.accent;
                context.lineWidth = 2;
                context.stroke();
                context.lineTo(width, height);
                context.lineTo(Math.max(0, root._x(points[0].t, width)), height);
                context.closePath();
                context.fillStyle = Qt.alpha(Theme.accent, 0.15);
                context.fill();
            }
        }

        Text {
            anchors { top: parent.top; left: parent.left; leftMargin: 2 }
            text: "100%"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeTiny
            color: Theme.textMuted
        }
        Text {
            anchors { bottom: parent.bottom; left: parent.left; leftMargin: 2; bottomMargin: 1 }
            text: "0%"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeTiny
            color: Theme.textMuted
        }
        Text {
            visible: root.charge.length === 0
            anchors.centerIn: parent
            text: "No history yet"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textMuted
        }
    }

    // ---- The power drawn ----
    Item {
        id: _rateBox
        width: root.width
        height: 50

        readonly property var _points: root.rate.filter(point => point.t >= root._start - 1 && point.v > 0)
        readonly property real _peak: _points.reduce((peak, point) => Math.max(peak, point.v), 0)
        // The scale: the peak with some room, never less than a watt
        readonly property real _scale: Math.max(1, _peak * 1.15)

        Canvas {
            id: _rateCanvas
            anchors.fill: parent
            onPaint: {
                const context = getContext("2d");
                context.reset();
                const width = this.width;
                const height = this.height;
                const points = _rateBox._points;
                context.strokeStyle = Qt.alpha(Theme.textDisabled, 0.35);
                context.lineWidth = 1;
                context.beginPath();
                context.moveTo(0, height - 0.5);
                context.lineTo(width, height - 0.5);
                context.stroke();
                if (points.length === 0)
                    return;

                const y = value => height - value / _rateBox._scale * (height - 2) - 1;
                // A gap longer than this (asleep, switched off) breaks the line
                const gap = 15 * 60;
                context.strokeStyle = Theme.textSecondary;
                context.lineWidth = 1.5;
                context.beginPath();
                for (let i = 0; i < points.length; i++) {
                    const x = root._x(points[i].t, width);
                    if (i === 0 || points[i].t - points[i - 1].t > gap)
                        context.moveTo(x, y(points[i].v));
                    else
                        context.lineTo(x, y(points[i].v));
                }
                context.stroke();
            }
        }

        Text {
            visible: _rateBox._peak > 0
            anchors { top: parent.top; left: parent.left; leftMargin: 2 }
            text: "peak " + _rateBox._peak.toFixed(1) + " W"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeTiny
            color: Theme.textMuted
        }
    }

    // ---- Time ----
    Item {
        width: root.width
        height: _startLabel.implicitHeight

        function _clock(seconds) {
            return Qt.formatDateTime(new Date(seconds * 1000), root.span > 2 * 24 * 3600 ? "ddd hh:mm" : "hh:mm");
        }

        Text {
            id: _startLabel
            anchors.left: parent.left
            text: parent._clock(root._start)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeTiny
            color: Theme.textMuted
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent._clock(root._start + root.span / 2)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeTiny
            color: Theme.textMuted
        }
        Text {
            anchors.right: parent.right
            text: "now"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeTiny
            color: Theme.textMuted
        }
    }
}
