import QtQuick
import qs.singletons

// History graph with 5m/15m/30m/1h scale buttons, for one or more series drawn over each
// other. A series is { history: [{ t, v }], color }, history being what the hardware
// sources and LinkSpeed keep. Bind `series` to an expression that reads the histories:
// each new sample then reassigns it, which repaints.
Column {
    id: root

    property var series: []
    property real minValue: 0
    // NaN scales the y axis to the highest value in the visible window
    property real maxValue: NaN
    // With a set maxValue the scale is known; for an auto-scaled one, a function turning
    // the peak into text for the corner, e.g. a speed formatter
    property var formatPeak: null
    // Paints only while true, so a collapsed graph costs nothing
    property bool active: true
    property int graphHeight: 80
    property int scaleSecs: 300

    spacing: 6

    onSeriesChanged: _repaint()
    onActiveChanged: _repaint()
    onScaleSecsChanged: _repaint()
    onWidthChanged: _repaint()

    function _repaint() {
        if (active)
            Qt.callLater(_canvas.requestPaint);
    }

    Row {
        spacing: 4

        Repeater {
            model: [
                {label: "5m",  secs: 300},
                {label: "15m", secs: 900},
                {label: "30m", secs: 1800},
                {label: "1h",  secs: 3600}
            ]

            Rectangle {
                required property var modelData

                width: 32
                height: 24
                radius: 4
                color: root.scaleSecs === modelData.secs
                    ? Theme.sliderAccent
                    : Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.15)

                Text {
                    anchors.centerIn: parent
                    text: parent.modelData.label
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.scaleSecs === parent.modelData.secs
                        ? Theme.popupBackground
                        : Theme.textSecondary
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.scaleSecs = parent.modelData.secs
                }
            }
        }
    }

    Canvas {
        id: _canvas
        width: parent.width
        height: root.graphHeight

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            // The x axis is the selected window ending now, not the span of the samples —
            // otherwise a history shorter than the window is stretched across the full
            // width and the scale buttons do nothing until it fills up
            var now = Date.now()
            var windowMs = root.scaleSecs * 1000
            var startT = now - windowMs
            var visible = (root.series ?? []).map(serie => ({
                color: serie.color,
                points: (serie.history ?? []).filter(point => point.t >= startT)
            }))

            var top = root.maxValue
            if (isNaN(top)) {
                top = root.minValue
                for (var s = 0; s < visible.length; s++)
                    for (var p = 0; p < visible[s].points.length; p++)
                        top = Math.max(top, visible[s].points[p].v)
            }
            var range = Math.max(top - root.minValue, 1e-9)

            function rgba(c, a) {
                return "rgba(" + Math.round(c.r*255) + "," + Math.round(c.g*255) + "," + Math.round(c.b*255) + "," + a + ")"
            }
            function xOf(pt) { return (pt.t - startT) / windowMs * width }
            function yOf(pt) {
                return height - Math.max(0, Math.min(1, (pt.v - root.minValue) / range)) * (height - 2) - 1
            }

            // Background
            ctx.fillStyle = rgba(Theme.cellDefault, 0.6)
            ctx.fillRect(0, 0, width, height)

            // Grid lines at 25%, 50%, 75%
            ctx.strokeStyle = rgba(Theme.textDim, 0.2)
            ctx.lineWidth = 1
            for (var g = 1; g < 4; g++) {
                var gy = height * g / 4
                ctx.beginPath()
                ctx.moveTo(0, gy)
                ctx.lineTo(width, gy)
                ctx.stroke()
            }

            for (var i = 0; i < visible.length; i++) {
                var points = visible[i].points
                if (points.length < 2) continue
                var color = visible[i].color

                // Fill under line; fainter with several series, so they stay readable
                // where they overlap
                ctx.beginPath()
                ctx.moveTo(xOf(points[0]), yOf(points[0]))
                for (var j = 1; j < points.length; j++)
                    ctx.lineTo(xOf(points[j]), yOf(points[j]))
                ctx.lineTo(xOf(points[points.length - 1]), height)
                ctx.lineTo(xOf(points[0]), height)
                ctx.closePath()
                ctx.fillStyle = rgba(color, visible.length > 1 ? 0.08 : 0.15)
                ctx.fill()

                // Line
                ctx.beginPath()
                ctx.strokeStyle = rgba(color, 0.9)
                ctx.lineWidth = 1.5
                ctx.moveTo(xOf(points[0]), yOf(points[0]))
                for (var k = 1; k < points.length; k++)
                    ctx.lineTo(xOf(points[k]), yOf(points[k]))
                ctx.stroke()
            }

            if (root.formatPeak && isNaN(root.maxValue)) {
                ctx.fillStyle = rgba(Theme.textDim, 0.9)
                ctx.font = Theme.fontSizeSmall + "px '" + Theme.fontFamily + "'"
                ctx.textBaseline = "top"
                ctx.fillText(root.formatPeak(top), 4, 3)
            }
        }
    }
}
