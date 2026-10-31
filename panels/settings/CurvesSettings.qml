import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// The curves library (~/.config/h2s_shell/curves.json): named cubic Béziers that themes
// use for their animation roles, alongside Qt's own curves. Shared by every theme and
// profile. A curve is edited as a draft — the graph, the numbers and the preview follow
// it — and written on Save. Assigning curves to roles comes with the Animations page
// (docs/plans/themes.md, stages 5 and 6).
Flickable {
    id: root

    anchors.fill: parent
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
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
    // A question to delete never carries over to another curve
    onSelectedChanged: _deleteButton.asking = false

    readonly property int _segments: CurvePoints.segmentCount(draftPoints)
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
    readonly property var _usages: (Theme.revision, ThemeFiles.curveUsages(selected))

    // A curve to compare with in the graph and the preview: a library or Qt curve name
    property string compareWith: ""
    property int previewDuration: 800

    function _open(points) {
        draftPoints = ThemeRules.curvePoints(points) ?? [0.25, 0.1, 0.25, 1, 1, 1];
        // A joint is smooth when its handles already line up
        draftSmooth = CurvePoints.smoothJoints(draftPoints);
        selectedPoint = 0;
        _graph.fit();
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
            ThemeFiles.renameCurve(selected, draftName);
        ThemeFiles.writeCurve(draftName, _segments === 1 ? draftPoints.slice(0, 4) : draftPoints);
        selected = draftName;
    }

    // ---- Points (CurvePoints) ----
    // Moves the point at `index` to (x, y). Dragged, y stays within what the graph shows;
    // typed, within what it can zoom out to — and the view fits the curve again if the
    // point lands out of sight.
    function movePoint(index, x, y, typed) {
        const yLimit = _graph.maxZoom - 0.2;
        draftPoints = typed
            ? CurvePoints.moved(draftPoints, draftSmooth, index, x, y, 0.5 - yLimit, 0.5 + yLimit)
            : CurvePoints.moved(draftPoints, draftSmooth, index, x, y, _graph.visibleYMin, _graph.visibleYMax);
        const moved = CurvePoints.point(draftPoints, index);
        if (typed && (moved.y < _graph.visibleYMin || moved.y > _graph.visibleYMax
                || _graph.toX(moved.x) < 0 || _graph.toX(moved.x) > _graph.width))
            _graph.fit();
    }

    function setSmooth(jointIndex, smooth) {
        const flags = draftSmooth.slice();
        flags[CurvePoints.segmentOf(jointIndex)] = smooth;
        draftSmooth = flags;
        if (smooth)
            draftPoints = CurvePoints.smoothed(draftPoints, jointIndex);
    }

    // The new joint is smooth, as the split leaves it
    function splitSegment(segment, t) {
        draftPoints = CurvePoints.split(draftPoints, segment, t);
        const flags = draftSmooth.slice();
        flags.splice(segment, 0, true);
        draftSmooth = flags;
        selectedPoint = segment * 6 + 4;
    }

    function removeJoint(jointIndex) {
        if (!CurvePoints.isJoint(draftPoints, jointIndex))
            return;
        draftPoints = CurvePoints.withoutJoint(draftPoints, jointIndex);
        const flags = draftSmooth.slice();
        flags.splice(CurvePoints.segmentOf(jointIndex), 1);
        draftSmooth = flags;
        selectedPoint = Math.max(0, jointIndex - 4);
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

    ColumnLayout {
        id: _column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Theme.settings.pageMargin
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

            InputField {
                id: _nameInput
                Layout.fillWidth: true
                text: root.draftName
                onTextEdited: root.draftName = text
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
            CurveGraph {
                id: _graph
                Layout.preferredWidth: 260
                Layout.preferredHeight: 260
                points: root.draftPoints
                selectedPoint: root.selectedPoint
                draftEasing: root._draftEasing
                compareEasing: root._compareEasing
                previewTime: _preview.time
                onPointPressed: index => root.selectedPoint = index
                onPointDragged: (index, x, y) => root.movePoint(index, x, y, false)
                onSplitRequested: (segment, t) => root.splitSegment(segment, t)
            }

            // ── The selected point, and what to compare with ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 8

                readonly property int _index: Math.min(root.selectedPoint, root.draftPoints.length - 2)
                readonly property bool _joint: CurvePoints.isJoint(root.draftPoints, _index)

                Text {
                    text: (parent._joint ? "Point between segments " + (CurvePoints.segmentOf(parent._index) + 1) + " and " + (CurvePoints.segmentOf(parent._index) + 2)
                        : "Handle " + (parent._index % 6 === 0 ? "1" : "2") + (root._segments > 1 ? " of segment " + (CurvePoints.segmentOf(parent._index) + 1) : ""))
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

                            InputField {
                                id: _coordinateInput
                                // Wide enough for "-8.888" and its padding
                                width: Math.max(60, Math.ceil(_widestCoordinate.advanceWidth) + 18)

                                TextMetrics {
                                    id: _widestCoordinate
                                    font: _coordinateInput.input.font
                                    text: "-8.888"
                                }

                                readonly property real _value: root.draftPoints[_coordinates._index + _coordinate.index] ?? 0
                                text: _value.toFixed(3)
                                input.validator: DoubleValidator { decimals: 3 }
                                onEditingFinished: {
                                    const value = parseFloat(text.replace(",", "."));
                                    if (!isNaN(value)) {
                                        const point = CurvePoints.point(root.draftPoints, _coordinates._index);
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

                // A joint: whether its handles stay in line, and removing it
                Row {
                    visible: parent._joint
                    spacing: 6
                    Pill {
                        label: "Smooth"
                        picked: root.draftSmooth[CurvePoints.segmentOf(parent.parent._index)] ?? false
                        onClicked: root.setSmooth(parent.parent._index, !picked)
                    }
                    SmallButton {
                        label: "Remove point"
                        onClicked: root.removeJoint(parent.parent._index)
                    }
                }

                Hint {
                    text: "x is time and only moves forward; y may go past 0 and 1 to overshoot. Click a point to select it. "
                        + "Double-click the curve to add a point there, elsewhere to fit the curve. Drag the background to move "
                        + "around, scroll to zoom in at the pointer. "
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

        CurvePreview {
            id: _preview
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            draftEasing: root._draftEasing
            compareEasing: root._compareEasing
            duration: root.previewDuration
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
                kind: "save"
                available: root._dirty && root._nameProblem === ""
                onClicked: root.save()
            }
            SmallButton {
                label: "Revert"
                available: root._dirty && root.selected !== ""
                onClicked: root.edit(root.selected)
            }
            // A new curve is only discarded; a saved one is deleted, asking first
            SmallButton {
                visible: root.selected === ""
                label: "Discard"
                available: root._names.length > 0
                onClicked: root.edit(root._names[0])
            }
            DeleteButton {
                id: _deleteButton
                visible: root.selected !== ""
                fontSize: Theme.fontSizeBody
                confirmLabel: root._usages.length > 0 ? "Delete? Used by " + root._usages.length : "Delete?"
                cancelTip: "Cancel — keep the curve"
                onConfirmed: {
                    const deleted = root.selected;
                    ThemeFiles.deleteCurve(deleted);
                    const rest = root._names.filter(name => name !== deleted);
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
