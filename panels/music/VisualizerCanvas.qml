import QtQuick
import qs.singletons

// The music visualiser drawn from `bars` (levels 0–1), in the style the active profile
// picks ("waveform", "bars", "dots"): along the width, mirrored about the middle, or —
// `vertical` — down the height, mirrored about the centre line, with bars growing from
// the left edge or, `fromRight`, from the right. Repaints whenever its bars change.
Canvas {
    id: root

    property var bars: []
    property bool vertical: false
    property bool fromRight: false
    property string style: "waveform"

    onBarsChanged: requestPaint()
    onStyleChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        if (style === "waveform")
            _drawWaveform(ctx, bars, width, height, vertical);
        else if (style === "bars")
            _drawBars(ctx, bars, width, height, vertical, fromRight);
        else if (style === "dots")
            _drawDots(ctx, bars, width, height, vertical);
    }

    function _drawWaveform(ctx, bars, w, h, vertical) {
        if (bars.length < 2)
            return;
        var c = Theme.accent;

        if (!vertical) {
            var cx = w / (bars.length - 1);
            var amp = h / 2 * 0.85;
            ctx.beginPath();
            ctx.moveTo(0, h / 2);
            for (var i = 0; i < bars.length - 1; i++) {
                var x0 = i * cx, x1 = (i + 1) * cx;
                var y0 = h / 2 - bars[i] * amp;
                var y1 = h / 2 - bars[i + 1] * amp;
                ctx.quadraticCurveTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
            }
            ctx.lineTo(w, h / 2);
            for (var j = bars.length - 2; j >= 0; j--) {
                var x0b = j * cx, x1b = (j + 1) * cx;
                var y0b = h / 2 + bars[j] * amp;
                var y1b = h / 2 + bars[j + 1] * amp;
                ctx.quadraticCurveTo(x1b, y1b, (x0b + x1b) / 2, (y0b + y1b) / 2);
            }
            ctx.closePath();
        } else {
            // axes swapped: center is vertical line at w/2, curves go left/right
            var cy = h / (bars.length - 1);
            var amp = w / 2 * 0.85;
            ctx.beginPath();
            ctx.moveTo(w / 2, 0);
            for (var i = 0; i < bars.length - 1; i++) {
                var y0 = i * cy, y1 = (i + 1) * cy;
                var x0 = w / 2 - bars[i] * amp;
                var x1 = w / 2 - bars[i + 1] * amp;
                ctx.quadraticCurveTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
            }
            ctx.lineTo(w / 2, h);
            for (var j = bars.length - 2; j >= 0; j--) {
                var y0b = j * cy, y1b = (j + 1) * cy;
                var x0b = w / 2 + bars[j] * amp;
                var x1b = w / 2 + bars[j + 1] * amp;
                ctx.quadraticCurveTo(x1b, y1b, (x0b + x1b) / 2, (y0b + y1b) / 2);
            }
            ctx.closePath();
        }

        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.18);
        ctx.fill();
        ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.6);
        ctx.lineWidth = 1.5;
        ctx.stroke();
    }

    // fromRight: bars anchor to the right edge and grow left
    function _drawBars(ctx, bars, w, h, vertical, fromRight) {
        if (bars.length === 0)
            return;
        var c = Theme.accent;
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.7);

        var n = bars.length;
        if (vertical) {
            var barH = (h - (n - 1) * 2) / n;
            for (var i = 0; i < n; i++) {
                var y = i * (barH + 2);
                var barLen = w * bars[i];
                if (fromRight) {
                    ctx.fillRect(w - barLen, y, barLen, barH);
                } else {
                    ctx.fillRect(0, y, barLen, barH);
                }
            }
        } else {
            var barW = (w - (n - 1) * 2) / n;
            for (var i = 0; i < n; i++) {
                var x = i * (barW + 2);
                var barH = h / 2 * bars[i];
                ctx.fillRect(x, h / 2, barW, barH);
                ctx.fillRect(x, h / 2, barW, -barH);
            }
        }
    }

    function _drawDots(ctx, bars, w, h, vertical) {
        if (bars.length === 0)
            return;
        var c = Theme.accent;
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.9);

        var n = bars.length;
        var r = 2.5;
        if (!vertical) {
            var cx = w / (n > 1 ? n - 1 : 1);
            var amp = h / 2 * 0.85;
            for (var i = 0; i < n; i++) {
                var x = i * cx;
                var dy = bars[i] * amp;
                ctx.beginPath();
                ctx.arc(x, h / 2 - dy, r, 0, Math.PI * 2);
                ctx.fill();
                ctx.beginPath();
                ctx.arc(x, h / 2 + dy, r, 0, Math.PI * 2);
                ctx.fill();
            }
        } else {
            var cy = h / (n > 1 ? n - 1 : 1);
            var amp = w / 2 * 0.85;
            for (var i = 0; i < n; i++) {
                var y = i * cy;
                var dx = bars[i] * amp;
                ctx.beginPath();
                ctx.arc(w / 2 - dx, y, r, 0, Math.PI * 2);
                ctx.fill();
                ctx.beginPath();
                ctx.arc(w / 2 + dx, y, r, 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }
}
