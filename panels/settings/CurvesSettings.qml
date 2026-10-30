import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

// The curves library (~/.config/h2s_shell/curves.json): named cubic Béziers that themes
// use for their animation roles, alongside Qt's own curves. Shared by every theme and
// profile. A curve is edited as a draft — the graph, the numbers and the preview follow
// it — and written on Save. Assigning curves to roles comes with the Animations page
// (docs/plans/themes.md, stages 5 and 6).
Flickable {
    id: root

    anchors.fill: parent
    contentHeight: _column.implicitHeight + 28
    clip: true

    // The library curve being edited; "" for a new one not saved yet
    property string selected: ""
    // The draft: its name and points in Qt's form — per segment c1x, c1y, c2x, c2y, endX,
    // endY, the last end being (1,1). Saved as [x1, y1, x2, y2] when it is one segment.
    property string draftName: ""
    property var draftPoints: [0.25, 0.1, 0.25, 1, 1, 1]
    // For each joint between segments, whether its two handles stay in line (no corner).
    // Not saved: read back from the points when a curve is opened.
    property var draftSmooth: []
    // The point selected on the graph, by the index of its x in draftPoints
    property int selectedPoint: 0

    readonly property int _segments: draftPoints.length / 6
    readonly property var _names: Object.keys(Theme.curveLibrary).sort()
    readonly property bool _dirty: draftName !== selected
        || JSON.stringify(draftPoints) !== JSON.stringify(ThemeRules.curvePoints(Theme.curveLibrary[selected]))
    readonly property string _nameProblem: {
        if (!ThemeRules.validCurveName(draftName))
            return draftName.trim() === "" ? "Give the curve a name" : "Not a name a curve can have: it is one of Qt's curves, or has spaces at its ends";
        if (draftName !== selected && _names.includes(draftName))
            return "There is already a curve with this name";
        return "";
    }
    readonly property var _usages: (Theme.revision, Theme.curveUsages(selected))

    // The graph's zoom: 1 shows y from -0.5 to 1.5 with the unit square filling the width;
    // 2 shows twice as much each way, around the square's centre. Scrolling zooms; opening
    // a curve or typing a number zooms out as far as its points need.
    property real _zoom: 1
    readonly property real _minZoom: 0.5
    readonly property real _maxZoom: 10
    // The visible range of y, which a dragged point stays within
    readonly property real _yMin: 0.5 - _zoom
    readonly property real _yMax: 0.5 + _zoom

    function _fitRange() {
        let reach = 0;
        for (let i = 1; i < draftPoints.length; i += 2)
            reach = Math.max(reach, Math.abs(draftPoints[i] - 0.5));
        _zoom = Math.min(_maxZoom, Math.max(1, Math.ceil((reach + 0.2) * 10) / 10));
    }

    // A curve to compare with in the graph and the preview: a library or Qt curve name
    property string compareWith: ""
    property int previewDuration: 800

    function _open(points) {
        draftPoints = ThemeRules.curvePoints(points) ?? [0.25, 0.1, 0.25, 1, 1, 1];
        // A joint is smooth when its handles already line up
        const smooth = [];
        for (let joint = 0; joint < _segments - 1; joint++) {
            const at = _point(joint * 6 + 4), before = _point(joint * 6 + 2), after = _point(joint * 6 + 6);
            const cross = (at.x - before.x) * (after.y - at.y) - (at.y - before.y) * (after.x - at.x);
            const dot = (at.x - before.x) * (after.x - at.x) + (at.y - before.y) * (after.y - at.y);
            smooth.push(Math.abs(cross) < 0.002 && dot >= 0);
        }
        draftSmooth = smooth;
        selectedPoint = 0;
        _fitRange();
    }

    function edit(name) {
        selected = name;
        draftName = name;
        _open(Theme.curveLibrary[name]);
    }

    function newCurve(points, baseName) {
        selected = "";
        draftName = ThemeRules.freeName(baseName, name => _names.includes(name) || !ThemeRules.validCurveName(name));
        _open(points);
    }

    function save() {
        if (_nameProblem !== "")
            return;
        if (selected !== "" && draftName !== selected)
            Theme.renameCurve(selected, draftName);
        Theme.writeCurve(draftName, _segments === 1 ? draftPoints.slice(0, 4) : draftPoints);
        selected = draftName;
    }

    // ---- Points ----
    // Each point is known by the index of its x in draftPoints. Within segment s (at
    // offset 6s): the first handle (+0), the second handle (+2) and the end (+4). The end
    // of every segment but the last is a joint; the last end, (1,1), and the start, (0,0),
    // stay put.
    function _point(index, points) {
        const from = points ?? draftPoints;
        return index < 0 ? { x: 0, y: 0 } : { x: from[index], y: from[index + 1] };
    }
    function isJoint(index) { return index % 6 === 4 && index < draftPoints.length - 2 }
    function _segmentOf(index) { return Math.floor(index / 6) }
    // The x range a handle of segment s keeps within: from its start to its end
    function _segmentStart(segment, points) { return _point(segment * 6 - 2, points) }
    function _segmentEnd(segment, points) { return _point(segment * 6 + 4, points) }

    function _round(value) { return Math.round(value * 1000) / 1000 }
    function _clamp(value, low, high) { return Math.max(low, Math.min(high, value)) }

    // Places the handle at `otherIndex` in line with the one at `movedIndex` across the
    // joint at `jointIndex`, keeping its length — shortened if it would leave its segment
    function _alignHandle(points, jointIndex, movedIndex, otherIndex) {
        const joint = _point(jointIndex, points), moved = _point(movedIndex, points), other = _point(otherIndex, points);
        const dx = joint.x - moved.x, dy = joint.y - moved.y;
        const length = Math.hypot(dx, dy);
        if (length < 1e-6)
            return;
        let reach = Math.hypot(other.x - joint.x, other.y - joint.y);
        const ux = dx / length, uy = dy / length;
        const segment = _segmentOf(otherIndex);
        const low = _segmentStart(segment, points).x, high = _segmentEnd(segment, points).x;
        if (ux > 1e-6)
            reach = Math.min(reach, (high - joint.x) / ux);
        else if (ux < -1e-6)
            reach = Math.min(reach, (low - joint.x) / ux);
        points[otherIndex] = _round(joint.x + ux * reach);
        points[otherIndex + 1] = _round(joint.y + uy * reach);
    }

    // Moves the point at `index` to (x, y), keeping time moving forward: a joint stays
    // between its neighbours and takes its handles along; a handle stays within its
    // segment, and at a smooth joint turns the one across from it. y is limited to the
    // visible range when dragged, and to what the graph can zoom out to when typed.
    function movePoint(index, x, y, typed) {
        const points = draftPoints.slice();
        const yLimit = typed ? _maxZoom - 0.2 : _zoom;
        y = _clamp(y, 0.5 - yLimit, 0.5 + yLimit);
        const segment = _segmentOf(index);
        if (isJoint(index)) {
            const low = _segmentStart(segment, points).x + 0.01;
            const high = _segmentEnd(segment + 1, points).x - 0.01;
            x = _clamp(x, low, high);
            const dx = x - points[index], dy = y - points[index + 1];
            points[index] = _round(x);
            points[index + 1] = _round(y);
            // The handles on either side come along, then keep within their segments
            for (const handle of [index - 2, index + 2]) {
                const handleSegment = _segmentOf(handle);
                points[handle] = _round(_clamp(points[handle] + dx, _segmentStart(handleSegment, points).x, _segmentEnd(handleSegment, points).x));
                points[handle + 1] = _round(points[handle + 1] + dy);
            }
        } else if (index % 6 !== 4) {
            points[index] = _round(_clamp(x, _segmentStart(segment, points).x, _segmentEnd(segment, points).x));
            points[index + 1] = _round(y);
            // The joint this handle belongs to, and the handle across it
            const first = index % 6 === 0;
            const joint = first ? index - 2 : index + 2;
            if (isJoint(joint) && draftSmooth[_segmentOf(joint)])
                _alignHandle(points, joint, index, first ? joint - 2 : joint + 2);
        }
        draftPoints = points;
        if (typed)
            _fitRange();
    }

    function setSmooth(jointIndex, smooth) {
        const flags = draftSmooth.slice();
        flags[_segmentOf(jointIndex)] = smooth;
        draftSmooth = flags;
        if (smooth) {
            const points = draftPoints.slice();
            _alignHandle(points, jointIndex, jointIndex - 2, jointIndex + 2);
            draftPoints = points;
        }
    }

    // Splits segment `segment` at its parameter t into two that draw the same curve
    // (de Casteljau); the new joint is smooth, as the split leaves it
    function splitSegment(segment, t) {
        const points = draftPoints.slice();
        const start = _segmentStart(segment, points);
        const c1 = _point(segment * 6, points), c2 = _point(segment * 6 + 2, points), end = _point(segment * 6 + 4, points);
        const lerp = (a, b) => ({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t });
        const a = lerp(start, c1), b = lerp(c1, c2), c = lerp(c2, end);
        const ab = lerp(a, b), bc = lerp(b, c), middle = lerp(ab, bc);
        // No Array.flatMap in QML's JavaScript
        const values = [];
        for (const point of [a, ab, middle, bc, c, end])
            values.push(_round(point.x), _round(point.y));
        points.splice(segment * 6, 6, ...values);
        draftPoints = points;
        const flags = draftSmooth.slice();
        flags.splice(segment, 0, true);
        draftSmooth = flags;
        selectedPoint = segment * 6 + 4;
    }

    // Removes the joint at `jointIndex`, joining its two segments into one: the first
    // keeps its first handle, the second its second handle and end
    function removeJoint(jointIndex) {
        if (!isJoint(jointIndex))
            return;
        const points = draftPoints.slice();
        points.splice(jointIndex - 2, 6);
        draftPoints = points;
        const flags = draftSmooth.slice();
        flags.splice(_segmentOf(jointIndex), 1);
        draftSmooth = flags;
        selectedPoint = Math.max(0, jointIndex - 4);
    }

    // Where on the curve a pixel position (in the graph) is, within `tolerance` pixels:
    // { segment, t }, or null
    function _hitCurve(position, tolerance) {
        let best = null;
        for (let segment = 0; segment < _segments; segment++) {
            const p0 = _segmentStart(segment), p1 = _point(segment * 6), p2 = _point(segment * 6 + 2), p3 = _point(segment * 6 + 4);
            for (let i = 0; i <= 100; i++) {
                const t = i / 100, u = 1 - t;
                const x = u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x;
                const y = u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y;
                const distance = Math.hypot(_graph.toX(x) - position.x, _graph.toY(y) - position.y);
                if (distance <= tolerance && (best === null || distance < best.distance))
                    best = { segment: segment, t: t, distance: distance };
            }
        }
        return best;
    }

    // The easing for the draft, and for the curve compared with
    readonly property var _draftEasing: ({ type: Easing.BezierSpline, bezierCurve: draftPoints })
    readonly property var _compareEasing: compareWith === "" ? null
        : ThemeRules.curveEasing(compareWith, Theme.curveLibrary).easing

    Component.onCompleted: {
        if (_names.length > 0)
            edit(_names[0]);
        else
            newCurve(ThemeRules.qtCurveApproximations.OutCubic, "curve");
    }

    component SmallButton: Rectangle {
        property string label
        property bool available: true
        property bool primary: false
        signal clicked

        width: _label.implicitWidth + 14
        height: 24
        radius: 6
        opacity: available ? 1 : 0.35
        color: primary
            ? (_area.containsMouse && available ? Theme.accentHover : Theme.accent)
            : (_area.containsMouse && available ? Theme.surfaceHover : Theme.surface)
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

        Text {
            id: _label
            anchors.centerIn: parent
            text: parent.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: parent.primary ? Theme.onAccent : Theme.textSecondary
        }

        MouseArea {
            id: _area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: parent.available ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (parent.available) parent.clicked()
        }
    }

    component Pill: Rectangle {
        property string label
        property bool picked: false
        signal clicked

        width: _pillLabel.implicitWidth + 14
        height: 22
        radius: 6
        color: picked ? Theme.accent : (_pillArea.containsMouse ? Theme.surfaceHover : Theme.surfaceHoverClear)
        border.width: picked ? 0 : 1
        border.color: Theme.outline
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

        Text {
            id: _pillLabel
            anchors.centerIn: parent
            text: parent.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: parent.picked ? Theme.onAccent : Theme.textSecondary
        }

        MouseArea {
            id: _pillArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component Heading: Text {
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeHeading
        font.bold: true
        color: Theme.textSecondary
    }

    component Hint: Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textMuted
    }

    // Samples an easing for drawing (from onPaint, never a binding: it sets the sampler):
    // an animation's easing can be evaluated at any point
    NumberAnimation { id: _sampler }

    function _sample(easing, progress) {
        _sampler.easing = easing;
        return _sampler.easing.valueForProgress(progress);
    }

    ColumnLayout {
        id: _column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 14
        }
        spacing: 10

        Heading { text: "Curves" }
        Hint {
            text: "Animation curves of your own, shared by every theme. A theme picks a curve for each animation role by name; "
                + "Qt's curves (OutQuad, OutBack, …) are always there. Saved in " + Theme.curvesPath.replace(Quickshell.env("HOME"), "~") + "."
        }

        // ── The library ──
        Flow {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                // ScriptModel, never the bare array — see "The Repeater crash"
                model: ScriptModel { values: root._names }
                Pill {
                    required property string modelData
                    label: modelData
                    picked: modelData === root.selected
                    onClicked: root.edit(modelData)
                }
            }

            SmallButton {
                label: "+ New"
                onClicked: root.newCurve([0.25, 0.1, 0.25, 1], "curve")
            }
        }

        Hint {
            visible: root._names.length === 0
            text: "No curves yet. Start from a blank one, or from a copy of one of Qt's below."
        }

        // Start from one of Qt's curves
        Text {
            text: "Copy of a Qt curve"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textSecondary
        }
        Flow {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: ScriptModel { values: Object.keys(ThemeRules.qtCurveApproximations) }
                Pill {
                    required property string modelData
                    label: modelData
                    onClicked: root.newCurve(ThemeRules.qtCurveApproximations[modelData], "my" + modelData)
                }
            }
        }
        Hint { text: "A copy is a close approximation as a Bézier curve, not the exact Qt curve. Bounce and elastic curves cannot be copied." }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider; Layout.topMargin: 4; Layout.bottomMargin: 4 }

        // ── The draft ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: root.selected === "" ? "New curve" : "Name"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBodyLarge
                color: Theme.textPrimary
            }

            Rectangle {
                Layout.fillWidth: true
                height: 28
                radius: 6
                color: Theme.surface
                border.width: 1
                border.color: _nameInput.activeFocus ? Theme.accent : Theme.surfaceHoverClear
                Behavior on border.color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }

                TextInput {
                    id: _nameInput
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.draftName
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textPrimary
                    selectByMouse: true
                    clip: true
                    onTextEdited: root.draftName = text
                }
            }
        }

        Text {
            visible: root._nameProblem !== ""
            text: root._nameProblem
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            // ── The graph: time across, progress up ──
            Item {
                id: _graph
                Layout.preferredWidth: 260
                Layout.preferredHeight: 260

                // The unit square, inside the room left for overshoot
                // Pixels per unit of x and of y, zoomed; the unit square's centre stays put
                readonly property real _xScale: (width - 24) / root._zoom
                readonly property real _yScale: height / 2 / root._zoom
                readonly property real _size: _xScale
                function toX(value) { return width / 2 + (value - 0.5) * _xScale }
                function toY(value) { return height / 2 - (value - 0.5) * _yScale }
                function fromX(position) { return 0.5 + (position - width / 2) / _xScale }
                function fromY(position) { return 0.5 - (position - height / 2) / _yScale }
                clip: true

                // Scroll to zoom; double-click to fit the curve again
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onWheel: wheel => {
                        const factor = Math.pow(1.15, -wheel.angleDelta.y / 120);
                        root._zoom = Math.max(root._minZoom, Math.min(root._maxZoom, root._zoom * factor));
                    }
                    // On the curve: a new point there; elsewhere: fit the curve again
                    onDoubleClicked: mouse => {
                        const hit = root._hitCurve(Qt.point(mouse.x, mouse.y), 8);
                        if (hit !== null && hit.t > 0.02 && hit.t < 0.98)
                            root.splitSegment(hit.segment, hit.t);
                        else
                            root._fitRange();
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: Theme.surfaceSunken
                }

                Canvas {
                    id: _canvas
                    anchors.fill: parent
                    // Redrawn whenever what it shows changes
                    property var _watch: [root.draftPoints, root._compareEasing, root._zoom, root.selectedPoint, Theme.accent, Theme.textMuted]
                    on_WatchChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const g = _graph;
                        // The unit square and the linear diagonal
                        ctx.strokeStyle = Theme.divider;
                        ctx.lineWidth = 1;
                        ctx.strokeRect(g.toX(0), g.toY(1), g._size, g.toY(0) - g.toY(1));
                        ctx.beginPath();
                        ctx.moveTo(g.toX(0), g.toY(0));
                        ctx.lineTo(g.toX(1), g.toY(1));
                        ctx.stroke();

                        const drawCurve = (easing, color, width) => {
                            ctx.strokeStyle = color;
                            ctx.lineWidth = width;
                            ctx.beginPath();
                            const steps = 120;
                            for (let i = 0; i <= steps; i++) {
                                const t = i / steps;
                                const x = g.toX(t);
                                const y = g.toY(root._sample(easing, t));
                                if (i === 0)
                                    ctx.moveTo(x, y);
                                else
                                    ctx.lineTo(x, y);
                            }
                            ctx.stroke();
                        };
                        if (root._compareEasing)
                            drawCurve(root._compareEasing, Theme.textMuted, 1.5);

                        // Each handle's line, from the point it belongs to
                        const p = root.draftPoints;
                        ctx.strokeStyle = Theme.textMuted;
                        ctx.lineWidth = 1;
                        ctx.beginPath();
                        for (let segment = 0; segment < root._segments; segment++) {
                            const start = root._segmentStart(segment);
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
                        for (let segment = 0; segment < root._segments; segment++) {
                            const o = segment * 6;
                            ctx.bezierCurveTo(g.toX(p[o]), g.toY(p[o + 1]), g.toX(p[o + 2]), g.toY(p[o + 3]), g.toX(p[o + 4]), g.toY(p[o + 5]));
                        }
                        ctx.stroke();
                    }
                }

                // The points, dragged: round handles, square joints (the ends of segments
                // but the last); clicking one selects it for the numbers beside
                Repeater {
                    model: ScriptModel {
                        values: root.draftPoints.map((value, index) => index)
                            .filter(index => index % 2 === 0 && (index % 6 !== 4 || root.isJoint(index)))
                    }
                    Rectangle {
                        id: _handle
                        required property int modelData
                        readonly property bool joint: root.isJoint(modelData)
                        readonly property bool picked: root.selectedPoint === modelData
                        width: joint ? 12 : 14
                        height: width
                        radius: joint ? 3 : 7
                        x: _graph.toX(root.draftPoints[modelData] ?? 0) - width / 2
                        y: _graph.toY(root.draftPoints[modelData + 1] ?? 0) - height / 2
                        color: joint ? Theme.textPrimary
                            : (_handleArea.pressed || _handleArea.containsMouse ? Theme.accentHover : Theme.accent)
                        border.width: 2
                        border.color: picked ? Theme.warning : (joint ? Theme.accent : Theme.popupBackground)
                        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                        MouseArea {
                            id: _handleArea
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            preventStealing: true
                            onPressed: root.selectedPoint = _handle.modelData
                            onPositionChanged: mouse => {
                                if (!pressed)
                                    return;
                                const point = mapToItem(_graph, mouse.x, mouse.y);
                                root.movePoint(_handle.modelData, _graph.fromX(point.x), _graph.fromY(point.y), false);
                            }
                        }
                    }
                }
                // The preview's moment on each curve: where time is across, and how far
                // the animation has got up
                NumberAnimation { id: _draftSampler; easing: root._draftEasing }
                NumberAnimation { id: _compareSampler; easing: root._compareEasing ?? root._draftEasing }

                Rectangle {
                    visible: root._compareEasing !== null
                    width: 10
                    height: 10
                    radius: 5
                    color: Theme.textMuted
                    x: _graph.toX(_preview.time) - width / 2
                    y: _graph.toY(_compareSampler.easing.valueForProgress(_preview.time)) - height / 2
                }

                Rectangle {
                    width: 10
                    height: 10
                    radius: 5
                    color: Theme.textPrimary
                    border.width: 2
                    border.color: Theme.accent
                    x: _graph.toX(_preview.time) - width / 2
                    y: _graph.toY(_draftSampler.easing.valueForProgress(_preview.time)) - height / 2
                }
            }

            // ── The selected point, and what to compare with ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 8

                readonly property int _index: Math.min(root.selectedPoint, root.draftPoints.length - 2)
                readonly property bool _joint: root.isJoint(_index)

                Text {
                    text: (parent._joint ? "Point between segments " + (root._segmentOf(parent._index) + 1) + " and " + (root._segmentOf(parent._index) + 2)
                        : "Handle " + (parent._index % 6 === 0 ? "1" : "2") + (root._segments > 1 ? " of segment " + (root._segmentOf(parent._index) + 1) : ""))
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                }

                RowLayout {
                    id: _coordinates
                    readonly property int _index: parent._index
                    spacing: 6

                    Repeater {
                        model: ["x", "y"]
                        RowLayout {
                            id: _coordinate
                            required property string modelData
                            required property int index
                            spacing: 3

                            Text {
                                text: _coordinate.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.textMuted
                            }

                            Rectangle {
                                width: 60
                                height: 24
                                radius: 5
                                color: Theme.surface
                                border.width: 1
                                border.color: _coordinateInput.activeFocus ? Theme.accent : Theme.surfaceHoverClear

                                TextInput {
                                    id: _coordinateInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    readonly property real _value: root.draftPoints[_coordinates._index + _coordinate.index] ?? 0
                                    text: _value.toFixed(3)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeBody
                                    color: Theme.textPrimary
                                    selectByMouse: true
                                    validator: DoubleValidator { decimals: 3 }
                                    onEditingFinished: {
                                        const value = parseFloat(text.replace(",", "."));
                                        if (!isNaN(value)) {
                                            const point = root._point(_coordinates._index);
                                            if (_coordinate.index === 0)
                                                root.movePoint(_coordinates._index, value, point.y, true);
                                            else
                                                root.movePoint(_coordinates._index, point.x, value, true);
                                        }
                                        text = Qt.binding(() => _value.toFixed(3));
                                    }
                                }
                            }
                        }
                    }
                }

                // A joint: whether its handles stay in line, and removing it
                Row {
                    visible: parent._joint
                    spacing: 6
                    Pill {
                        label: "Smooth"
                        picked: root.draftSmooth[root._segmentOf(parent.parent._index)] ?? false
                        onClicked: root.setSmooth(parent.parent._index, !picked)
                    }
                    SmallButton {
                        label: "Remove point"
                        onClicked: root.removeJoint(parent.parent._index)
                    }
                }

                Hint {
                    text: "x is time and only moves forward; y may go past 0 and 1 to overshoot. Click a point to select it. "
                        + "Double-click the curve to add a point there, elsewhere to fit the curve. Scroll over the graph to zoom. "
                        + "A smooth point keeps its two handles in line, so the curve has no corner there."
                }

                Text {
                    Layout.topMargin: 6
                    text: "Compare with"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: ScriptModel {
                            values: ["none", "Linear", "OutQuad", "OutCubic", "InOutQuad", "OutBack"]
                                .concat(root._names.filter(name => name !== root.selected))
                        }
                        Pill {
                            required property string modelData
                            label: modelData
                            picked: (modelData === "none" ? "" : modelData) === root.compareWith
                            onClicked: root.compareWith = modelData === "none" ? "" : modelData
                        }
                    }
                }
            }
        }

        // ── Preview: a square moving with the curve, and one with the compared curve ──
        Heading { text: "Preview"; Layout.topMargin: 6 }

        Item {
            id: _preview
            Layout.fillWidth: true
            Layout.preferredHeight: root._compareEasing ? 64 : 32
            // Time, 0 to 1 at a steady pace, over and over: each square applies its curve,
            // and the dots on the graph follow the same moment
            property real time: 0

            SequentialAnimation {
                running: root.visible
                loops: Animation.Infinite
                // Restarts with a new duration
                property var _restartOn: root.previewDuration
                on_RestartOnChanged: if (running) restart()
                PropertyAction { target: _preview; property: "time"; value: 0 }
                PauseAnimation { duration: 300 }
                NumberAnimation {
                    target: _preview
                    property: "time"
                    from: 0
                    to: 1
                    duration: root.previewDuration
                }
                PauseAnimation { duration: 500 }
            }

            component Track: Item {
                property var easing
                property color squareColor
                width: _preview.width
                height: 28

                // Its own sampler, bound rather than set: setting the shared one from a
                // binding made the binding loop
                NumberAnimation { id: _trackSampler; easing: parent.easing ?? root._draftEasing }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 2
                    color: Theme.track
                }
                Rectangle {
                    width: 24
                    height: 24
                    radius: 5
                    anchors.verticalCenter: parent.verticalCenter
                    color: parent.squareColor
                    // Overshoot carries it past the ends, as the animation would
                    x: _trackSampler.easing.valueForProgress(_preview.time) * (parent.width - width)
                }
            }

            Column {
                spacing: 8
                Track { easing: root._draftEasing; squareColor: Theme.accent }
                Track {
                    visible: root._compareEasing !== null
                    easing: root._compareEasing ?? root._draftEasing
                    squareColor: Theme.textMuted
                }
            }
        }

        SettingSlider {
            Layout.fillWidth: true
            label: "Preview duration"
            from: 100
            to: 3000
            suffix: " ms"
            value: root.previewDuration
            onValueEdited: newValue => root.previewDuration = newValue
        }

        // ── Save, revert, delete, and where it is used ──
        Row {
            Layout.topMargin: 6
            spacing: 6

            SmallButton {
                label: root.selected === "" ? "Save" : (root.draftName !== root.selected ? "Save and rename" : "Save")
                primary: true
                available: root._dirty && root._nameProblem === ""
                onClicked: root.save()
            }
            SmallButton {
                label: "Revert"
                available: root._dirty && root.selected !== ""
                onClicked: root.edit(root.selected)
            }
            SmallButton {
                label: root.selected === "" ? "Discard" : "Delete"
                available: root.selected !== "" || root._names.length > 0
                onClicked: {
                    if (root.selected !== "")
                        Theme.deleteCurve(root.selected);
                    const rest = root._names.filter(name => name !== root.selected);
                    if (rest.length > 0)
                        root.edit(rest[0]);
                    else
                        root.newCurve([0.25, 0.1, 0.25, 1], "curve");
                }
            }
        }

        Hint {
            text: root.selected === "" ? "Not saved yet."
                : root._usages.length === 0 ? "Not used by any theme."
                : "Used by " + root._usages.map(usage => usage.theme + " (" + usage.role + ")").join(", ")
                    + ". Renaming updates them; deleting leaves them with " + ThemeRules.fallbackCurve + "."
        }
    }
}
