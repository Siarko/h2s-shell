import QtQuick
import qs.components
import Quickshell
import qs.singletons

// The Curves page's graph: time across, progress up. Draws the curve being edited with its
// handles, the curve compared with, and where the preview has got on each; the points are
// dragged, and the view pans and zooms — drag the background to move it, scroll to zoom
// at the pointer, double-click off the curve to fit the curve again. Double-clicking the
// curve asks for a new point there. The points stay the page's: this reports what was done
// to them (pointPressed, pointDragged, splitRequested).
Item {
    id: root

    // The curve's points in Qt's form (CurvePoints)
    property var points: []
    property int selectedPoint: 0
    // Easings for drawing: the draft's, and the compared curve's (null for none)
    property var draftEasing: null
    property var compareEasing: null
    // Where the preview is, 0 to 1
    property real previewTime: 0

    signal pointPressed(int index)
    // The point at `index` dragged to (x, y), in the curve's units
    signal pointDragged(int index, real x, real y)
    signal splitRequested(int segment, real t)

    // The view: the curve's point at the graph's centre, and how much it shows — at zoom 1
    // y from -0.5 to 1.5 around the centre, with the unit square filling the width; at 2
    // twice as much each way
    property real zoom: 1
    property real centerX: 0.5
    property real centerY: 0.5
    readonly property real minZoom: 0.05
    readonly property real maxZoom: 10
    // The visible range of y, which a dragged point stays within
    readonly property real visibleYMin: fromY(height)
    readonly property real visibleYMax: fromY(0)

    // Pixels per unit of x and of y
    readonly property real _xScale: (width - 24) / zoom
    readonly property real _yScale: height / 2 / zoom
    function toX(value) { return width / 2 + (value - centerX) * _xScale }
    function toY(value) { return height / 2 - (value - centerY) * _yScale }
    function fromX(position) { return centerX + (position - width / 2) / _xScale }
    function fromY(position) { return centerY - (position - height / 2) / _yScale }

    function _clamp(value, low, high) { return Math.max(low, Math.min(high, value)) }

    // The whole curve in view, the unit square centred
    function fit() {
        zoom = Math.min(maxZoom, Math.max(1, Math.ceil((CurvePoints.reach(points) + 0.2) * 10) / 10));
        centerX = 0.5;
        centerY = 0.5;
    }

    function _setCenter(x, y) {
        centerX = _clamp(x, -0.5, 1.5);
        centerY = _clamp(y, 0.5 - maxZoom, 0.5 + maxZoom);
    }

    // Zooms by `factor`, keeping the curve's point under the pointer where it is
    function _zoomAt(position, factor) {
        const valueX = fromX(position.x), valueY = fromY(position.y);
        zoom = _clamp(zoom * factor, minZoom, maxZoom);
        _setCenter(valueX - (position.x - width / 2) / _xScale, valueY + (position.y - height / 2) / _yScale);
    }

    // Where on the curve a pixel position is, within `tolerance` pixels: { segment, t }, or
    // null
    function _hitCurve(position, tolerance) {
        let best = null;
        for (let segment = 0; segment < CurvePoints.segmentCount(points); segment++) {
            for (let i = 0; i <= 100; i++) {
                const t = i / 100;
                const at = CurvePoints.pointAt(points, segment, t);
                const distance = Math.hypot(toX(at.x) - position.x, toY(at.y) - position.y);
                if (distance <= tolerance && (best === null || distance < best.distance))
                    best = { segment: segment, t: t, distance: distance };
            }
        }
        return best;
    }

    // Samples an easing for drawing (from onPaint, never a binding: it sets the sampler):
    // an animation's easing can be evaluated at any point
    NumberAnimation { id: _sampler }

    function _sample(easing, progress) {
        _sampler.easing = easing;
        return _sampler.easing.valueForProgress(progress);
    }

    clip: true

    // The background: dragged, the view moves; scrolled, it zooms; double-clicked, a new
    // point on the curve or the curve fitted again
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
        // Keeps the drag: otherwise the settings page's Flickable takes it and scrolls
        preventStealing: true
        property point _pressedAt
        property real _pressedCenterX
        property real _pressedCenterY

        onPressed: mouse => {
            _pressedAt = Qt.point(mouse.x, mouse.y);
            _pressedCenterX = root.centerX;
            _pressedCenterY = root.centerY;
        }
        onPositionChanged: mouse => {
            if (pressed)
                root._setCenter(_pressedCenterX - (mouse.x - _pressedAt.x) / root._xScale,
                                _pressedCenterY + (mouse.y - _pressedAt.y) / root._yScale);
        }
        onWheel: wheel => root._zoomAt(Qt.point(wheel.x, wheel.y), Math.pow(1.15, -wheel.angleDelta.y / 120))
        onDoubleClicked: mouse => {
            const hit = root._hitCurve(Qt.point(mouse.x, mouse.y), 8);
            if (hit !== null && hit.t > 0.02 && hit.t < 0.98)
                root.splitRequested(hit.segment, hit.t);
            else
                root.fit();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.settings.cardRadius
        color: Theme.surfaceSunken
    }

    Canvas {
        id: _canvas
        anchors.fill: parent
        // Redrawn whenever what it shows changes
        property var _watch: [root.points, root.compareEasing, root.zoom, root.centerX, root.centerY,
            root.selectedPoint, Theme.accent, Theme.textMuted]
        on_WatchChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const g = root;
            // The unit square and the linear diagonal
            ctx.strokeStyle = Theme.divider;
            ctx.lineWidth = 1;
            ctx.strokeRect(g.toX(0), g.toY(1), g.toX(1) - g.toX(0), g.toY(0) - g.toY(1));
            ctx.beginPath();
            ctx.moveTo(g.toX(0), g.toY(0));
            ctx.lineTo(g.toX(1), g.toY(1));
            ctx.stroke();

            if (root.compareEasing) {
                ctx.strokeStyle = Theme.textMuted;
                ctx.lineWidth = 1.5;
                ctx.beginPath();
                const steps = 120;
                for (let i = 0; i <= steps; i++) {
                    const t = i / steps;
                    const x = g.toX(t);
                    const y = g.toY(root._sample(root.compareEasing, t));
                    if (i === 0)
                        ctx.moveTo(x, y);
                    else
                        ctx.lineTo(x, y);
                }
                ctx.stroke();
            }

            // Each handle's line, from the point it belongs to
            const p = root.points;
            const segments = CurvePoints.segmentCount(p);
            ctx.strokeStyle = Theme.textMuted;
            ctx.lineWidth = 1;
            ctx.beginPath();
            for (let segment = 0; segment < segments; segment++) {
                const start = CurvePoints.segmentStart(p, segment);
                ctx.moveTo(g.toX(start.x), g.toY(start.y));
                ctx.lineTo(g.toX(p[segment * 6]), g.toY(p[segment * 6 + 1]));
                ctx.moveTo(g.toX(p[segment * 6 + 4]), g.toY(p[segment * 6 + 5]));
                ctx.lineTo(g.toX(p[segment * 6 + 2]), g.toY(p[segment * 6 + 3]));
            }
            ctx.stroke();
            // The curve itself, drawn as the Béziers it is made of
            ctx.strokeStyle = Theme.accent;
            ctx.lineWidth = 2.5;
            ctx.beginPath();
            ctx.moveTo(g.toX(0), g.toY(0));
            for (let segment = 0; segment < segments; segment++) {
                const o = segment * 6;
                ctx.bezierCurveTo(g.toX(p[o]), g.toY(p[o + 1]), g.toX(p[o + 2]), g.toY(p[o + 3]), g.toX(p[o + 4]), g.toY(p[o + 5]));
            }
            ctx.stroke();
        }
    }

    // The points, dragged: round handles, square joints (the ends of segments but the
    // last); pressing one selects it for the numbers beside
    Repeater {
        model: ScriptModel {
            values: root.points.map((value, index) => index)
                .filter(index => index % 2 === 0 && (index % 6 !== 4 || CurvePoints.isJoint(root.points, index)))
        }
        Rectangle {
            id: _handle
            required property int modelData
            readonly property bool joint: CurvePoints.isJoint(root.points, modelData)
            readonly property bool picked: root.selectedPoint === modelData
            width: joint ? 12 : 14
            height: width
            radius: joint ? 3 : 7
            x: root.toX(root.points[modelData] ?? 0) - width / 2
            y: root.toY(root.points[modelData + 1] ?? 0) - height / 2
            color: joint ? Theme.textPrimary
                : (_handleArea.pressed || _handleArea.lit ? Theme.accentHover : Theme.accent)
            border.width: Theme.border.selectedWidth
            border.color: picked ? Theme.warning : (joint ? Theme.accent : Theme.popupBackground)
            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

            PointerArea {
                id: _handleArea
                reach: 6
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true
                onPressed: root.pointPressed(_handle.modelData)
                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    const position = mapToItem(root, mouse.x, mouse.y);
                    root.pointDragged(_handle.modelData, root.fromX(position.x), root.fromY(position.y));
                }
            }
        }
    }

    // The preview's moment on each curve: where time is across, and how far the animation
    // has got up
    NumberAnimation { id: _draftSampler; easing: root.draftEasing }
    NumberAnimation { id: _compareSampler; easing: root.compareEasing ?? root.draftEasing }

    Rectangle {
        visible: root.compareEasing !== null
        width: 10
        height: 10
        radius: 5
        color: Theme.textMuted
        x: root.toX(root.previewTime) - width / 2
        y: root.toY(_compareSampler.easing.valueForProgress(root.previewTime)) - height / 2
    }

    Rectangle {
        width: 10
        height: 10
        radius: 5
        color: Theme.textPrimary
        border.width: Theme.border.selectedWidth
        border.color: Theme.accent
        x: root.toX(root.previewTime) - width / 2
        y: root.toY(_draftSampler.easing.valueForProgress(root.previewTime)) - height / 2
    }
}
