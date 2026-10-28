import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

Item {
    id: root
    property string title: ""
    property var model: []
    property string labelsKey: "_labels"

    signal listChanged(var newList)

    Layout.fillWidth: true
    implicitHeight: _outer.implicitHeight

    readonly property var _allSourceIds: Hardware.sourceIds

    function _getLabel(sourceId) {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data["hardware"]?.[labelsKey]?.[sourceId] ?? ""
    }

    function _setLabel(sourceId, label) {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        if (!data["hardware"]) data["hardware"] = {}
        if (!data["hardware"][labelsKey]) data["hardware"][labelsKey] = {}
        if (label === "")
            delete data["hardware"][labelsKey][sourceId]
        else
            data["hardware"][labelsKey][sourceId] = label
        Config.widgetProfiles = JSON.stringify(data)
    }

    Component.onCompleted: _rowList.workingList = model ? model.slice() : []
    onModelChanged: if (!_rowList.dragging) _rowList.workingList = model ? model.slice() : []

    Column {
        id: _outer
        width: parent.width
        spacing: 0

        Text {
            text: root.title
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            font.bold: true
            color: Theme.textSecondary
            bottomPadding: 6
        }

        Rectangle {
            width: parent.width
            height: _container.implicitHeight
            color: Qt.rgba(0, 0, 0, 0.15)
            radius: 6
            border.color: Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.2)
            border.width: 1
            clip: true

            Column {
                id: _container
                width: parent.width
                topPadding: 4
                bottomPadding: 4

                Item {
                    width: parent.width
                    height: _rowList.contentHeight

                    Item {
                        id: _dragGhost
                        width: parent.width
                        height: 32
                        visible: false
                    }

                    ListView {
                        id: _rowList
                        width: parent.width
                        height: contentHeight
                        interactive: false
                        model: workingList

                        property var workingList: []
                        property bool dragging: false
                        property int dragIndex: -1
                        property int dropIndex: -1
                        property Item ghost: _dragGhost

                        function notifyListChanged(list) { root.listChanged(list) }

                        delegate: Item {
                            id: _row
                            required property string modelData
                            required property int index

                            property var _lv: ListView.view

                            width: _rowList.width
                            height: 32

                            // Drop indicator above this row
                            Rectangle {
                                anchors.top: parent.top
                                anchors.topMargin: -1
                                width: parent.width - 16
                                anchors.horizontalCenter: parent.horizontalCenter
                                height: 2
                                radius: 1
                                color: Theme.sliderAccent
                                visible: _row._lv.dragging
                                         && _row._lv.dropIndex === _row.index
                                         && _row._lv.dragIndex !== _row.index
                                         && _row._lv.dragIndex !== _row.index - 1
                                z: 10
                            }

                            // Drop indicator below last row
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: -1
                                width: parent.width - 16
                                anchors.horizontalCenter: parent.horizontalCenter
                                height: 2
                                radius: 1
                                color: Theme.sliderAccent
                                visible: _row._lv.dragging
                                         && _row.index === _row._lv.workingList.length - 1
                                         && _row._lv.dropIndex === _row._lv.workingList.length
                                         && _row._lv.dragIndex !== _row._lv.workingList.length - 1
                                z: 10
                            }

                            opacity: _row._lv.dragging && _row._lv.dragIndex === _row.index ? 0.35 : 1.0

                            RowLayout {
                                anchors {
                                    top: parent.top
                                    left: parent.left
                                    right: parent.right
                                    leftMargin: 4
                                    rightMargin: 4
                                }
                                height: 32
                                spacing: 2

                                Item {
                                    width: 20
                                    height: 32

                                    Text {
                                        anchors.centerIn: parent
                                        text: "⠿"
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: _handleArea.containsMouse ? Theme.textSecondary : Theme.textDim
                                    }

                                    MouseArea {
                                        id: _handleArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.SizeVerCursor
                                        drag.target: _row._lv.ghost
                                        drag.axis: Drag.YAxis
                                        drag.minimumY: 0
                                        drag.maximumY: _rowList.contentHeight

                                        onPositionChanged: {
                                            if (_row._lv.dragging) {
                                                var listY = mapToItem(_row._lv, 0, mouseY).y
                                                _row._lv.dropIndex = Math.min(
                                                    _row._lv.workingList.length,
                                                    Math.max(0, Math.round(listY / 32)))
                                            }
                                        }
                                        onPressed: {
                                            _row._lv.dragIndex = _row.index
                                            _row._lv.dropIndex = _row.index
                                            _row._lv.dragging = true
                                            _row._lv.ghost.visible = true
                                            _row._lv.ghost.y = _row.index * 32
                                        }
                                        onReleased: {
                                            _row._lv.ghost.visible = false
                                            _row._lv.dragging = false
                                            var from = _row._lv.dragIndex
                                            var to = _row._lv.dropIndex
                                            if (to !== from && to !== from + 1) {
                                                var list = _row._lv.workingList.slice()
                                                var moved = list.splice(from, 1)[0]
                                                var adjTo = to > from ? to - 1 : to
                                                list.splice(adjTo, 0, moved)
                                                _row._lv.workingList = list
                                                _row._lv.notifyListChanged(list)
                                            }
                                            _row._lv.dragIndex = -1
                                            _row._lv.dropIndex = -1
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    height: 22
                                    radius: 3
                                    color: _labelInput.activeFocus
                                        ? Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.15)
                                        : _labelHover.containsMouse
                                            ? Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.08)
                                            : "transparent"

                                    Text {
                                        anchors { fill: parent; leftMargin: 4 }
                                        verticalAlignment: Text.AlignVCenter
                                        text: Hardware.sourceForId(_row.modelData)?.label ?? _row.modelData
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.textDim
                                        visible: _labelInput.text === "" && !_labelInput.activeFocus
                                    }

                                    TextInput {
                                        id: _labelInput
                                        anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                                        verticalAlignment: Text.AlignVCenter
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.textPrimary
                                        selectByMouse: true
                                        clip: true

                                        Component.onCompleted: text = root._getLabel(_row.modelData)

                                        Connections {
                                            target: Config
                                            function onWidgetProfilesChanged() {
                                                if (!_labelInput.activeFocus)
                                                    _labelInput.text = root._getLabel(_row.modelData)
                                            }
                                        }

                                        // Whitespace alone is kept as a single space: it is
                                        // how a label is left blank, while an empty field
                                        // goes back to the default label
                                        onEditingFinished: root._setLabel(_row.modelData,
                                            text !== "" && text.trim() === "" ? " " : text.trim())
                                    }

                                    MouseArea {
                                        id: _labelHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.IBeamCursor
                                        onClicked: _labelInput.forceActiveFocus()
                                        enabled: !_labelInput.activeFocus
                                    }
                                }

                                Rectangle {
                                    width: 24
                                    height: 24
                                    radius: 4
                                    color: _removeHover.containsMouse ? Theme.cellHover : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "×"
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.textDim
                                    }

                                    MouseArea {
                                        id: _removeHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var list = _row._lv.workingList.slice()
                                            list.splice(_row.index, 1)
                                            _row._lv.workingList = list
                                            _row._lv.notifyListChanged(list)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.2)
                }

                Item {
                    width: _container.width
                    height: 32

                    Text {
                        anchors.centerIn: parent
                        text: "＋ Add source"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: _picker.visible = !_picker.visible
                    }
                }

                Rectangle {
                    id: _picker
                    visible: false
                    width: parent.width
                    implicitHeight: _pickerCol.implicitHeight + 8
                    color: Qt.rgba(0, 0, 0, 0.25)
                    radius: 6
                    z: 10

                    Column {
                        id: _pickerCol
                        width: parent.width
                        topPadding: 4
                        bottomPadding: 4

                        function addSource(sourceId) {
                            var list = [..._rowList.workingList, sourceId]
                            _rowList.workingList = list
                            _rowList.notifyListChanged(list)
                            _picker.visible = false
                        }

                        Repeater {
                            // ScriptModel, never the bare array — see "The Repeater crash".
                            // Compared by source, not id: "gpu" in an older config is the
                            // same source as its "gpu@<slot>".
                            model: ScriptModel {
                                values: root._allSourceIds.filter(id =>
                                    !_rowList.workingList.some(listed => Hardware.sourceForId(listed) === Hardware.sourceForId(id)) &&
                                    (Hardware.sourceForId(id)?.available ?? false))
                            }

                            Item {
                                required property string modelData
                                width: _pickerCol.width
                                height: 28

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    radius: 4
                                    color: _pickerItemHover.containsMouse ? Theme.cellHover : "transparent"

                                    Text {
                                        anchors {
                                            verticalCenter: parent.verticalCenter
                                            left: parent.left
                                            leftMargin: 8
                                        }
                                        text: Hardware.sourceForId(modelData)?.label ?? modelData
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.textPrimary
                                    }

                                    MouseArea {
                                        id: _pickerItemHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: parent.parent.parent.addSource(modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
