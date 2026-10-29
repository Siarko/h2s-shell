import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

Item {
    id: root
    implicitWidth: 280
    implicitHeight: _col.implicitHeight

    property var _expandedId: null

    // Which sources the popup lists and their labels: a profile setting
    readonly property var _popupSetting: Profiles.value("widgets.hardware.popup") ?? ({})
    readonly property var _customLabels: _popupSetting.labels ?? {}

    // Source ids as configured — labels are stored under these, which for the ids from
    // before multi-GPU support ("gpu") differ from the source's own sourceId
    readonly property var _popupKeys: _popupSetting.sources ?? Hardware.sourceIds

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

                height: isExpanded ? root._rowH + root._graphAreaH : root._rowH
                Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

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

                        HistoryChart {
                            anchors {
                                fill: parent
                                topMargin: 8
                                bottomMargin: 8
                                leftMargin: 12
                                rightMargin: 12
                            }
                            active: _row.isExpanded
                            series: [{ history: _row.modelData.history, color: Theme.sliderAccent }]
                            minValue: _row.modelData.minValue
                            maxValue: _row.modelData.maxValue
                        }
                    }
                }
            }
        }
    }
}
