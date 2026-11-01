import QtQuick
import QtQuick.Effects
import qs.singletons

// The music visualiser drawn from `bars` (levels 0–1), in the style the active profile
// picks ("waveform", "bars", "dots", "glow", "glowEven"), in one of three shapes:
// - along the width, mirrored about the middle;
// - `vertical`: down the height, mirrored about the centre line, bars growing from the
//   left edge or, `fromRight`, from the right;
// - `edge` "bottom", "left" or "right": along that edge, growing inward only (the music
//   panel's own edges); bars are given along it, left to right or top to bottom;
// - `around`: round a cover in the middle (a square `coverHalf` from its centre to each
//   side, corners of `coverRadius`, turned by `coverAngle`), the bars given clockwise from
//   the top centre. The bands keep their places on screen as the cover turns.
// In the theme's visualiser colour; around the cover, `colors` (from it, CoverColors) when
// given, running round it — the first at the top, the next down both sides alike.
// Glow is the waveform's shape filled and blurred into light, reaching as far as each
// band; even glow is the same with every band at `bass`. Repaints whenever its bars change.
Item {
    id: root

    property var bars: []
    property bool vertical: false
    property bool fromRight: false
    property string style: "waveform"
    property real bass: 0

    property string edge: ""
    property bool around: false
    property var colors: []
    readonly property bool _multicolor: around && colors.length > 0
    onColorsChanged: _canvas.requestPaint()
    property real coverHalf: 60
    property real coverRadius: 20
    property real coverAngle: 0

    readonly property bool _glow: style === "glow" || style === "glowEven"
    // What is drawn: even glow has every band at the bass's level
    readonly property var _levels: style === "glowEven" ? bars.map(() => bass) : bars

    on_LevelsChanged: _canvas.requestPaint()
    onStyleChanged: _canvas.requestPaint()
    onCoverAngleChanged: if (around) _canvas.requestPaint()
    onCoverRadiusChanged: _canvas.requestPaint()
    onVisibleChanged: if (visible) _canvas.requestPaint()

    // Past the item by a margin, so a glow is not cut off at its edges; the drawing is
    // moved in by the same margin, so the shapes sit where the item is
    readonly property int _margin: 48

    Canvas {
        id: _canvas
        anchors.fill: parent
        anchors.margins: -root._margin

        // As glow, the drawn shape is blurred into light
        layer.enabled: root._glow
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 48
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            ctx.translate(root._margin, root._margin);
            const w = root.width, h = root.height;
            const levels = root._levels;
            if (root._glow) {
                // Light: the shape at full, two thirds and a third of each band's reach, each
                // faint — brightest near its source, fading outward — then blurred
                for (const scale of [1, 0.66, 0.33]) {
                    const scaled = levels.map(level => level * scale);
                    if (root.around)
                        root._drawAround(ctx, scaled, w, h);
                    else if (root.edge !== "")
                        root._drawEdge(ctx, scaled, w, h, true);
                    else
                        root._drawWaveform(ctx, scaled, w, h, root.vertical, true);
                }
            } else if (root.around)
                root._drawAround(ctx, levels, w, h);
            else if (root.edge !== "")
                root._drawEdge(ctx, levels, w, h, false);
            else if (root.style === "waveform")
                root._drawWaveform(ctx, levels, w, h, root.vertical, false);
            else if (root.style === "bars")
                root._drawBars(ctx, levels, w, h, root.vertical, root.fromRight);
            else if (root.style === "dots")
                root._drawDots(ctx, levels, w, h, root.vertical);
        }
    }

    // What to paint with at `alpha`: the theme's colour, or round the cover its colours as
    // a gradient about its centre, the same down the left as down the right
    function _paint(ctx, alpha, centreX, centreY) {
        if (!_multicolor) {
            const c = Theme.visualizer;
            return Qt.rgba(c.r, c.g, c.b, alpha);
        }
        const list = colors.map(color => {
            const c = Qt.color(color);
            return Qt.rgba(c.r, c.g, c.b, alpha);
        });
        if (list.length === 1)
            return list[0];
        // From the top, round to the bottom and back: first, …, last, …, first
        const stops = list.concat(list.slice(0, -1).reverse());
        const gradient = ctx.createConicalGradient(centreX, centreY, Math.PI / 2);
        for (let i = 0; i < stops.length; i++)
            gradient.addColorStop(i / (stops.length - 1), stops[i]);
        return gradient;
    }

    // A shape filled: soft as a waveform, with its line; faint layers as the source of a glow
    function _fill(ctx, glow) {
        const centreX = width / 2, centreY = height / 2;
        ctx.fillStyle = _paint(ctx, glow ? 0.35 : 0.18, centreX, centreY);
        ctx.fill();
        if (glow)
            return;
        ctx.strokeStyle = _paint(ctx, 0.6, centreX, centreY);
        ctx.lineWidth = 1.5;
        ctx.stroke();
    }

    function _drawWaveform(ctx, bars, w, h, vertical, glow) {
        if (bars.length < 2)
            return;

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

        _fill(ctx, glow);
    }

    // fromRight: bars anchor to the right edge and grow left
    function _drawBars(ctx, bars, w, h, vertical, fromRight) {
        if (bars.length === 0)
            return;
        var c = Theme.visualizer;
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
        var c = Theme.visualizer;
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

    // Along an edge, growing inward: a point `along` (0–1) the edge, `across` (0–1) of the
    // way in from it
    function _edgePoint(along, across, w, h) {
        if (edge === "bottom")
            return { x: along * w, y: h - across * h };
        if (edge === "left")
            return { x: across * w, y: along * h };
        return { x: w - across * w, y: along * h };
    }

    function _drawEdge(ctx, bars, w, h, glow) {
        const n = bars.length;
        if (n === 0)
            return;
        const c = Theme.visualizer;
        const at = (along, across) => _edgePoint(along, across, w, h);

        if (style === "bars" && !glow) {
            // A gap of 2 px between bars, as in the other layouts
            const length = edge === "bottom" ? w : h;
            const gap = 2 / Math.max(1, length);
            const size = (1 - (n - 1) * gap) / n;
            ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.7);
            for (let i = 0; i < n; i++) {
                const start = i * (size + gap), end = start + size;
                const corners = [at(start, 0), at(end, 0), at(end, bars[i]), at(start, bars[i])];
                ctx.beginPath();
                ctx.moveTo(corners[0].x, corners[0].y);
                for (let k = 1; k < 4; k++)
                    ctx.lineTo(corners[k].x, corners[k].y);
                ctx.closePath();
                ctx.fill();
            }
            return;
        }

        const step = 1 / (n > 1 ? n - 1 : 1);
        if (style === "dots" && !glow) {
            ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.9);
            for (let i = 0; i < n; i++) {
                // Off the edge by a dot's size, so a silent band still shows
                const p = at(i * step, 0.04 + bars[i] * 0.85);
                ctx.beginPath();
                ctx.arc(p.x, p.y, 2.5, 0, Math.PI * 2);
                ctx.fill();
            }
            return;
        }

        // Waveform and glow: a line through the bands, closed along the edge
        if (n < 2)
            return;
        const start = at(0, 0);
        ctx.beginPath();
        ctx.moveTo(start.x, start.y);
        for (let i = 0; i < n - 1; i++) {
            const control = at(i * step, bars[i] * 0.85);
            const next = at((i + 0.5) * step, (bars[i] + bars[i + 1]) / 2 * 0.85);
            ctx.quadraticCurveTo(control.x, control.y, next.x, next.y);
        }
        const last = at(1, bars[n - 1] * 0.85);
        ctx.lineTo(last.x, last.y);
        const end = at(1, 0);
        ctx.lineTo(end.x, end.y);
        ctx.closePath();
        _fill(ctx, glow);
    }

    // Round the cover: rays out from its edge (bars), dots, or a closed wave — filled soft,
    // or as the source of a glow
    function _drawAround(ctx, bars, w, h) {
        const n = bars.length;
        if (n === 0)
            return;
        const centreX = w / 2, centreY = h / 2;
        // A little off the cover's edge; an outline pushed out evenly keeps its corners'
        // centres, so the radius grows by the gap too
        const gap = 4;
        const half = coverHalf + gap;
        const radius = Math.min(half, coverRadius + gap);
        const reach = Math.max(4, (Math.min(w, h) / 2 - half) * 0.9);
        const at = t => RoundedOutline.screenPoint(t, half, radius, coverAngle);

        if (style === "bars") {
            const perimeter = 8 * (half - radius) + 2 * Math.PI * radius;
            ctx.strokeStyle = _paint(ctx, 0.75, centreX, centreY);
            ctx.lineWidth = Math.max(1.5, perimeter / n * 0.45);
            ctx.lineCap = "round";
            for (let i = 0; i < n; i++) {
                const p = at((i + 0.5) / n);
                const length = 3 + bars[i] * reach;
                ctx.beginPath();
                ctx.moveTo(centreX + p.x, centreY + p.y);
                ctx.lineTo(centreX + p.x + p.nx * length, centreY + p.y + p.ny * length);
                ctx.stroke();
            }
            return;
        }

        if (style === "dots") {
            ctx.fillStyle = _paint(ctx, 0.9, centreX, centreY);
            for (let i = 0; i < n; i++) {
                const p = at((i + 0.5) / n);
                const distance = 4 + bars[i] * reach * 0.85;
                ctx.beginPath();
                ctx.arc(centreX + p.x + p.nx * distance, centreY + p.y + p.ny * distance, 2.5, 0, Math.PI * 2);
                ctx.fill();
            }
            return;
        }

        // Waveform and glow: a closed line through the bands, eased between them
        const steps = Math.max(120, n * 6);
        ctx.beginPath();
        for (let k = 0; k <= steps; k++) {
            const t = k / steps;
            const position = t * n - 0.5;
            const first = ((Math.floor(position) % n) + n) % n;
            const second = (first + 1) % n;
            const blend = (1 - Math.cos((position - Math.floor(position)) * Math.PI)) / 2;
            const level = bars[first] * (1 - blend) + bars[second] * blend;
            const p = at(t);
            const distance = 2 + level * reach * 0.8;
            const x = centreX + p.x + p.nx * distance, y = centreY + p.y + p.ny * distance;
            if (k === 0)
                ctx.moveTo(x, y);
            else
                ctx.lineTo(x, y);
        }
        ctx.closePath();
        _fill(ctx, _glow);
    }
}
