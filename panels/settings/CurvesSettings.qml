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
    // The draft: its name and points [x1, y1, x2, y2]
    property string draftName: ""
    property var draftPoints: [0.25, 0.1, 0.25, 1]
    // A curve of several segments can only be edited in the file
    readonly property bool _multiSegment: selected !== "" && (Theme.curveLibrary[selected]?.length ?? 4) > 4

    readonly property var _names: Object.keys(Theme.curveLibrary).sort()
    readonly property bool _dirty: draftName !== selected
        || JSON.stringify(draftPoints) !== JSON.stringify(Theme.curveLibrary[selected] ?? null)
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
        const reach = Math.max(Math.abs(draftPoints[1] - 0.5), Math.abs(draftPoints[3] - 0.5)) + 0.2;
        _zoom = Math.min(_maxZoom, Math.max(1, Math.ceil(reach * 10) / 10));
    }

    // A curve to compare with in the graph and the preview: a library or Qt curve name
    property string compareWith: ""
    property int previewDuration: 800

    function edit(name) {
        selected = name;
        draftName = name;
        const points = Theme.curveLibrary[name];
        draftPoints = points ? points.slice(0, 4) : [0.25, 0.1, 0.25, 1];
        _fitRange();
    }

    function newCurve(points, baseName) {
        selected = "";
        draftName = ThemeRules.freeName(baseName, name => _names.includes(name) || !ThemeRules.validCurveName(name));
        draftPoints = points.slice();
        _fitRange();
    }

    function save() {
        if (_nameProblem !== "" || _multiSegment)
            return;
        if (selected !== "" && draftName !== selected)
            Theme.renameCurve(selected, draftName);
        Theme.writeCurve(draftName, draftPoints);
        selected = draftName;
    }

    // x is time and stays within 0–1; y may overshoot — dragged, within the visible
    // range; typed, as far as the graph can zoom out, which it then does
    function setPoint(index, value, typed) {
        const points = draftPoints.slice();
        const yMin = typed ? 0.5 - _maxZoom + 0.2 : _yMin;
        const yMax = typed ? 0.5 + _maxZoom - 0.2 : _yMax;
        points[index] = index % 2 === 0
            ? Math.max(0, Math.min(1, value))
            : Math.max(yMin, Math.min(yMax, value));
        points[index] = Math.round(points[index] * 100) / 100;
        draftPoints = points;
        if (typed)
            _fitRange();
    }

    // The easing for the draft, and for the curve compared with
    readonly property var _draftEasing: ({ type: Easing.BezierSpline,
        bezierCurve: _multiSegment ? Theme.curveLibrary[selected] : draftPoints.concat([1, 1]) })
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

        Hint {
            visible: root._multiSegment
            text: "This curve has several segments; it can only be edited in the file."
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            // ── The graph: time across, progress up ──
            Item {
                id: _graph
                Layout.preferredWidth: 260
                Layout.preferredHeight: 260
                enabled: !root._multiSegment
                opacity: enabled ? 1 : 0.5

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
                    onDoubleClicked: root._fitRange()
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
                    property var _watch: [root.draftPoints, root._compareEasing, root._zoom, Theme.accent, Theme.textMuted]
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

                        if (root._multiSegment) {
                            drawCurve({ type: Easing.BezierSpline, bezierCurve: Theme.curveLibrary[root.selected] }, Theme.accent, 2.5);
                            return;
                        }
                        // The control points' handles
                        const p = root.draftPoints;
                        ctx.strokeStyle = Theme.textMuted;
                        ctx.lineWidth = 1;
                        ctx.beginPath();
                        ctx.moveTo(g.toX(0), g.toY(0));
                        ctx.lineTo(g.toX(p[0]), g.toY(p[1]));
                        ctx.moveTo(g.toX(1), g.toY(1));
                        ctx.lineTo(g.toX(p[2]), g.toY(p[3]));
                        ctx.stroke();
                        // The curve itself, drawn as the Bézier it is
                        ctx.strokeStyle = Theme.accent;
                        ctx.lineWidth = 2.5;
                        ctx.beginPath();
                        ctx.moveTo(g.toX(0), g.toY(0));
                        ctx.bezierCurveTo(g.toX(p[0]), g.toY(p[1]), g.toX(p[2]), g.toY(p[3]), g.toX(1), g.toY(1));
                        ctx.stroke();
                    }
                }

                // The two control points, dragged
                Repeater {
                    model: root._multiSegment ? 0 : 2
                    Rectangle {
                        id: _handle
                        required property int index
                        readonly property int _xIndex: index * 2
                        width: 14
                        height: 14
                        radius: 7
                        x: _graph.toX(root.draftPoints[_xIndex]) - width / 2
                        y: _graph.toY(root.draftPoints[_xIndex + 1]) - height / 2
                        color: _handleArea.pressed || _handleArea.containsMouse ? Theme.accentHover : Theme.accent
                        border.width: 2
                        border.color: Theme.popupBackground
                        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                        MouseArea {
                            id: _handleArea
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            preventStealing: true
                            onPositionChanged: mouse => {
                                if (!pressed)
                                    return;
                                const point = mapToItem(_graph, mouse.x, mouse.y);
                                root.setPoint(_handle._xIndex, _graph.fromX(point.x));
                                root.setPoint(_handle._xIndex + 1, _graph.fromY(point.y));
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

            // ── Numbers, and what to compare with ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 8
                enabled: !root._multiSegment

                Repeater {
                    model: ["First point", "Second point"]
                    RowLayout {
                        required property string modelData
                        required property int index
                        spacing: 6

                        Text {
                            Layout.preferredWidth: 90
                            text: modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textSecondary
                        }

                        Repeater {
                            model: ["x", "y"]
                            RowLayout {
                                id: _coordinate
                                required property string modelData
                                required property int index
                                readonly property int _pointIndex: parent.index * 2 + index
                                spacing: 3

                                Text {
                                    text: _coordinate.modelData
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.textMuted
                                }

                                Rectangle {
                                    width: 52
                                    height: 24
                                    radius: 5
                                    color: Theme.surface
                                    border.width: 1
                                    border.color: _coordinateInput.activeFocus ? Theme.accent : Theme.surfaceHoverClear

                                    TextInput {
                                        id: _coordinateInput
                                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: root.draftPoints[_coordinate._pointIndex].toFixed(2)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.textPrimary
                                        selectByMouse: true
                                        validator: DoubleValidator { decimals: 3 }
                                        onEditingFinished: {
                                            const value = parseFloat(text.replace(",", "."));
                                            if (!isNaN(value))
                                                root.setPoint(_coordinate._pointIndex, value, true);
                                            text = Qt.binding(() => root.draftPoints[_coordinate._pointIndex].toFixed(2));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Hint {
                    text: "x is time and stays between 0 and 1; y may go past 0 and 1 to overshoot. Scroll over the graph to zoom, double-click it to fit the curve."
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
                available: root._dirty && root._nameProblem === "" && !root._multiSegment
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
