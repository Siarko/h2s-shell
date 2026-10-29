import QtQuick
import qs.singletons

// History graph with 5m/15m/30m/1h scale buttons, for one or more series drawn over each
// other. A series is { history, color }, history being History.append samples
// ({ t, v, dt }) as the hardware sources and LinkSpeed keep them. Where sampling was
// paused the line breaks rather than bridging the gap as if there were data. Bind `series` to an expression that reads the histories:
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
    // A quick wave across the graph when a sample arrives (the "graphs.heartbeat"
    // setting): it brightens the line and the fill under it as it passes, right to left
    property bool heartbeat: Profiles.value("graphs.heartbeat")
    // 0 → 1 while the wave travels; 1 when idle
    property real _pulse: 1
    // Newest sample time across the series, so only a new sample starts a wave
    property double _newestSample: 0
    property int scaleSecs: 300

    spacing: 6

    onSeriesChanged: {
        var newest = 0
        for (var i = 0; i < (series ?? []).length; i++) {
            var history = series[i].history ?? []
            if (history.length > 0)
                newest = Math.max(newest, history[history.length - 1].t)
        }
        // Not on the first data the graph sees, which is the whole history at once
        if (newest > _newestSample && _newestSample > 0 && heartbeat && active && !Theme.reduceMotion)
            _wave.restart()
        _newestSample = newest
        _repaint()
    }
    on_PulseChanged: if (active) _canvas.requestPaint()

    NumberAnimation {
        id: _wave
        target: root
        property: "_pulse"
        from: 0
        to: 1
        duration: Theme.duration("heartbeat")
        easing.type: Theme.easing("heartbeat")
    }
    onActiveChanged: _repaint()
    onScaleSecsChanged: _repaint()
    onWidthChanged: _repaint()

    // Splits samples into runs of continuous sampling. Two samples belong to one run unless
    // the time between them is well over the interval either was taken at — then sampling
    // was paused. Taking the larger of the two keeps a rate change from looking like a gap.
    function _runs(points) {
        var runs = []
        var current = []
        for (var i = 0; i < points.length; i++) {
            var previous = current[current.length - 1]
            if (previous && previous.dt && points[i].dt
                    && points[i].t - previous.t > 2.5 * Math.max(previous.dt, points[i].dt)) {
                runs.push(current)
                current = []
            }
            current.push(points[i])
        }
        if (current.length > 0)
            runs.push(current)
        return runs
    }

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
                    ? Theme.accent
                    : Theme.fill

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
                runs: root._runs((serie.history ?? []).filter(point => point.t >= startT))
            }))

            var top = root.maxValue
            if (isNaN(top)) {
                top = root.minValue
                for (var s = 0; s < visible.length; s++)
                    for (var r = 0; r < visible[s].runs.length; r++)
                        for (var p = 0; p < visible[s].runs[r].length; p++)
                            top = Math.max(top, visible[s].runs[r][p].v)
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
            ctx.fillStyle = rgba(Theme.surface, 0.6)
            ctx.fillRect(0, 0, width, height)

            // Grid lines at 25%, 50%, 75%
            ctx.strokeStyle = rgba(Theme.textDisabled, 0.2)
            ctx.lineWidth = 1
            for (var g = 1; g < 4; g++) {
                var gy = height * g / 4
                ctx.beginPath()
                ctx.moveTo(0, gy)
                ctx.lineTo(width, gy)
                ctx.stroke()
            }

            function tracePath(points, closed) {
                ctx.beginPath()
                ctx.moveTo(xOf(points[0]), yOf(points[0]))
                for (var j = 1; j < points.length; j++)
                    ctx.lineTo(xOf(points[j]), yOf(points[j]))
                if (closed) {
                    ctx.lineTo(xOf(points[points.length - 1]), height)
                    ctx.lineTo(xOf(points[0]), height)
                    ctx.closePath()
                }
            }

            // One continuous run of samples: the fill under it, then its line. The fill is
            // fainter with several series, so they stay readable where they overlap.
            var fillAlpha = visible.length > 1 ? 0.08 : 0.15
            function drawRun(points, color) {
                tracePath(points, true)
                ctx.fillStyle = rgba(color, fillAlpha)
                ctx.fill()

                tracePath(points, false)
                ctx.strokeStyle = rgba(color, 0.9)
                ctx.lineWidth = 1.5
                ctx.stroke()
            }

            // The heartbeat: a band of light centred on waveX, drawn over each run in a
            // lighter shade of its own colour, so with several series the waves of each
            // line up into one. It fades as it travels.
            var waveX = width * (1 - root._pulse)
            var waveHalf = width * 0.12
            var waveStrength = 1 - root._pulse
            function waveGradient(color, peakAlpha) {
                var gradient = ctx.createLinearGradient(waveX - waveHalf, 0, waveX + waveHalf, 0)
                var light = Qt.lighter(color, 1.6)
                gradient.addColorStop(0, rgba(light, 0))
                gradient.addColorStop(0.5, rgba(light, peakAlpha * waveStrength))
                gradient.addColorStop(1, rgba(light, 0))
                return gradient
            }
            function drawWave(points, color) {
                tracePath(points, true)
                ctx.fillStyle = waveGradient(color, fillAlpha * 2.5)
                ctx.fill()

                tracePath(points, false)
                ctx.strokeStyle = waveGradient(color, 1)
                ctx.lineWidth = 2.5
                ctx.stroke()
            }

            var waving = root.heartbeat && root._pulse < 1

            // The wave also crosses the background, full height, in a muted tone, so it
            // reads as one wave over the whole graph — including where there is no data
            // yet, or a pause. Drawn under the lines; the coloured part goes on top.
            if (waving) {
                var backgroundWave = ctx.createLinearGradient(waveX - waveHalf, 0, waveX + waveHalf, 0)
                backgroundWave.addColorStop(0, rgba(Theme.textDisabled, 0))
                backgroundWave.addColorStop(0.5, rgba(Theme.textDisabled, 0.12 * waveStrength))
                backgroundWave.addColorStop(1, rgba(Theme.textDisabled, 0))
                ctx.fillStyle = backgroundWave
                ctx.fillRect(Math.max(0, waveX - waveHalf), 0, waveHalf * 2, height)
            }

            for (var i = 0; i < visible.length; i++) {
                for (var run = 0; run < visible[i].runs.length; run++) {
                    if (visible[i].runs[run].length < 2)
                        continue
                    drawRun(visible[i].runs[run], visible[i].color)
                    if (waving)
                        drawWave(visible[i].runs[run], visible[i].color)
                }
            }

            if (root.formatPeak && isNaN(root.maxValue)) {
                ctx.fillStyle = rgba(Theme.textDisabled, 0.9)
                ctx.font = Theme.fontSizeSmall + "px '" + Theme.fontFamily + "'"
                ctx.textBaseline = "top"
                ctx.fillText(root.formatPeak(top), 4, 3)
            }
        }
    }
}
