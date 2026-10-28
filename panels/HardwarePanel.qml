import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

Item {
    id: root
    implicitWidth: 280
    implicitHeight: _col.implicitHeight

    property var _expandedId: null

    readonly property var _customLabels: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data["hardware"]?.["_popupLabels"] ?? {}
    }

    // Source ids as configured — labels are stored under these, which for the ids from
    // before multi-GPU support ("gpu") differ from the source's own sourceId
    readonly property var _popupKeys: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data["hardware"]?.["_popup"] ?? Hardware.sourceIds
    }

    readonly property var _popupSources: {
        var result = []
        for (var i = 0; i < _popupKeys.length; i++) {
            var src = Hardware.sourceForId(_popupKeys[i])
            if (src && src.available) result.push(src)
        }
        return result
    }

    function _labelFor(source) {
        var key = _popupKeys.find(k => Hardware.sourceForId(k) === source) ?? source.sourceId
        return Hardware.displayLabel(_customLabels, key)
    }

    readonly property int _rowH: 36
    readonly property int _graphAreaH: 126  // 8 top + 24 buttons + 6 spacing + 80 canvas + 8 bottom

    Column {
        id: _col
        width: parent.implicitWidth
        topPadding: 8
        bottomPadding: 8
        spacing: 0

        Repeater {
            // ScriptModel, never the bare array — see "The Repeater crash" in
            // docs/ARCHITECTURE.md. The sources are singletons, so identity is stable.
            model: ScriptModel {
                values: root._popupSources
            }

            delegate: Item {
                id: _row
                required property var modelData
                required property int index

                width: _col.width
                clip: true

                property bool isExpanded: root._expandedId === modelData.sourceId
                property int scaleSecs: 300

                height: isExpanded ? root._rowH + root._graphAreaH : root._rowH
                Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

                onIsExpandedChanged: {
                    if (isExpanded) Qt.callLater(() => _canvas.requestPaint())
                }
                onScaleSecsChanged: Qt.callLater(() => _canvas.requestPaint())

                // Listen for new data and repaint when visible
                Connections {
                    target: _row.modelData
                    function onHistoryChanged() {
                        if (_row.isExpanded) _canvas.requestPaint()
                    }
                }

                Column {
                    width: parent.width
                    spacing: 0

                    // ── Metric row ──────────────────────────────────────────
                    Item {
                        width: parent.width
                        height: root._rowH

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            spacing: 8

                            Text {
                                text: root._labelFor(_row.modelData)
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textSecondary
                                Layout.preferredWidth: 72
                            }

                            // Middle: progress bar + subtitle stacked vertically
                            Column {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 3

                                Rectangle {
                                    visible: _row.modelData.showProgressBar
                                    width: parent.width
                                    height: visible ? 4 : 0
                                    radius: 2
                                    color: Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.25)

                                    Rectangle {
                                        width: parent.width * Math.max(0, Math.min(1,
                                            (_row.modelData.value - _row.modelData.minValue) /
                                            Math.max(1, _row.modelData.maxValue - _row.modelData.minValue)))
                                        height: parent.height
                                        radius: parent.radius
                                        color: Theme.sliderAccent
                                        Behavior on width { NumberAnimation { duration: 400 } }
                                    }
                                }

                                Text {
                                    visible: _row.modelData.subtitle !== ""
                                    width: parent.width
                                    height: visible ? implicitHeight : 0
                                    text: _row.modelData.subtitle
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.textDim
                                }
                            }

                            Text {
                                text: Math.round(_row.modelData.value) + _row.modelData.unit
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textPrimary
                                horizontalAlignment: Text.AlignRight
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._expandedId = (_row.isExpanded ? null : _row.modelData.sourceId)
                        }
                    }

                    // ── Graph area (always in DOM, clipped by parent) ──────
                    Item {
                        width: parent.width
                        height: root._graphAreaH

                        Column {
                            anchors {
                                fill: parent
                                topMargin: 8
                                bottomMargin: 8
                                leftMargin: 12
                                rightMargin: 12
                            }
                            spacing: 6

                            // Scale buttons
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
                                        required property int index

                                        width: 32
                                        height: 24
                                        radius: 4
                                        color: _row.scaleSecs === modelData.secs
                                            ? Theme.sliderAccent
                                            : Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.15)

                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.modelData.label
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: _row.scaleSecs === parent.modelData.secs
                                                ? Theme.popupBackground
                                                : Theme.textSecondary
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: _row.scaleSecs = parent.modelData.secs
                                        }
                                    }
                                }
                            }

                            // Canvas graph
                            Canvas {
                                id: _canvas
                                width: parent.width
                                height: 80

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    var src = _row.modelData
                                    var pts = src.history
                                    if (!pts || pts.length < 2) return

                                    var now       = Date.now()
                                    var windowMs  = _row.scaleSecs * 1000
                                    var filtered  = []
                                    for (var i = 0; i < pts.length; i++) {
                                        if (pts[i].t >= now - windowMs) filtered.push(pts[i])
                                    }
                                    if (filtered.length < 2) return

                                    // The x axis is the selected window ending now, not the span of
                                    // the samples — otherwise a history shorter than the window is
                                    // stretched across the full width and the scale buttons do
                                    // nothing until it fills up
                                    var range    = Math.max(1, src.maxValue - src.minValue)
                                    var startT   = now - windowMs
                                    var timeSpan = windowMs

                                    function rgba(c, a) {
                                        return "rgba(" + Math.round(c.r*255) + "," + Math.round(c.g*255) + "," + Math.round(c.b*255) + "," + a + ")"
                                    }
                                    function xOf(pt) { return (pt.t - startT) / timeSpan * width }
                                    function yOf(pt) {
                                        return height - Math.max(0, Math.min(1, (pt.v - src.minValue) / range)) * (height - 2) - 1
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

                                    var ac = Theme.sliderAccent

                                    // Fill under line
                                    ctx.beginPath()
                                    ctx.moveTo(xOf(filtered[0]), yOf(filtered[0]))
                                    for (var j = 1; j < filtered.length; j++)
                                        ctx.lineTo(xOf(filtered[j]), yOf(filtered[j]))
                                    ctx.lineTo(xOf(filtered[filtered.length - 1]), height)
                                    ctx.lineTo(xOf(filtered[0]), height)
                                    ctx.closePath()
                                    ctx.fillStyle = rgba(ac, 0.15)
                                    ctx.fill()

                                    // Line
                                    ctx.beginPath()
                                    ctx.strokeStyle = rgba(ac, 0.9)
                                    ctx.lineWidth = 1.5
                                    ctx.moveTo(xOf(filtered[0]), yOf(filtered[0]))
                                    for (var k = 1; k < filtered.length; k++)
                                        ctx.lineTo(xOf(filtered[k]), yOf(filtered[k]))
                                    ctx.stroke()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
