import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

Item {
    id: root
    property string title: ""
    property var model: []
    property string section: ""
    property var widgetProfiles: []

    signal listChanged(var newList)
    signal widgetSettingsClicked(int index)
    signal profileListChanged(var newProfiles)

    Layout.fillWidth: true
    implicitHeight: _outer.implicitHeight

    Component.onCompleted: {
        _rowList.workingList = model ? model.slice() : []
        _rowList.workingProfiles = widgetProfiles ? widgetProfiles.slice() : []
    }
    onModelChanged: if (!_rowList.dragging) _rowList.workingList = model ? model.slice() : []
    onWidgetProfilesChanged: if (!_rowList.dragging) _rowList.workingProfiles = widgetProfiles ? widgetProfiles.slice() : []

    function displayName(type) {
        return WidgetRegistry.displayName(type)
    }

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

                    // Ghost sibling of ListView — exposed via _rowList.ghost so delegates can reach it
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

                        // All state here — delegates reach it via _row._lv (captured ListView.view)
                        property var workingList: []
                        property var workingProfiles: []
                        property bool dragging: false
                        property int dragIndex: -1
                        property int dropIndex: -1
                        property Item ghost: _dragGhost
                        property var expandedSet: ({})

                        function toggleExpanded(idx) {
                            var s = Object.assign({}, expandedSet)
                            if (s[idx]) delete s[idx]; else s[idx] = true
                            expandedSet = s
                        }

                        // Proxy functions called from delegate JS handlers via _row._lv
                        function notifyListChanged(list) { root.listChanged(list) }
                        function notifyProfilesChanged(profs) { root.profileListChanged(profs) }
                        function notifySettingsClicked(idx) {
                            root.widgetSettingsClicked(idx)
                            toggleExpanded(idx)
                        }
                        function getDisplayName(type) { return root.displayName(type) }

                        delegate: Item {
                            id: _row
                            required property string modelData
                            required property int index

                            // Capture ListView.view on the delegate root — the ONE place it's set.
                            // Children access state via _row._lv (delegate's own id, always reachable).
                            property var _lv: ListView.view
                            property bool _expanded: _row._lv.expandedSet[_row.index] === true

                            width: _rowList.width
                            height: _expanded ? 32 + _pane.implicitHeight : 32
                            clip: true

                            Behavior on height {
                                NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                            }

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
                                                var profs = _row._lv.workingProfiles.slice()
                                                var movedProf = profs.splice(from, 1)[0] || ""
                                                profs.splice(adjTo, 0, movedProf)
                                                _row._lv.workingProfiles = profs
                                                _row._lv.notifyProfilesChanged(profs)
                                            }
                                            _row._lv.dragIndex = -1
                                            _row._lv.dropIndex = -1
                                        }
                                    }
                                }

                                Text {
                                    text: _row._lv.getDisplayName(_row.modelData)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeBody
                                    color: Theme.textPrimary
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    width: 24
                                    height: 24
                                    radius: 4
                                    color: _gearHover.containsMouse ? Theme.cellHover : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "⚙"
                                        font.pixelSize: Theme.fontSizeBodyLarge
                                        color: _row._expanded ? Theme.sliderAccent : Theme.textSecondary
                                    }

                                    MouseArea {
                                        id: _gearHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: _row._lv.notifySettingsClicked(_row.index)
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
                                            var profs = _row._lv.workingProfiles.slice()
                                            profs.splice(_row.index, 1)
                                            _row._lv.workingProfiles = profs
                                            _row._lv.notifyProfilesChanged(profs)
                                        }
                                    }
                                }
                            }

                            WidgetSettingsPane {
                                id: _pane
                                anchors {
                                    top: parent.top
                                    topMargin: 32
                                    left: parent.left
                                    right: parent.right
                                    leftMargin: 4
                                    rightMargin: 4
                                }
                                visible: _row._expanded
                                widgetType: _row.modelData
                                currentProfile: _row._lv.workingProfiles[_row.index] || ""
                                onProfileAssigned: function(newName) {
                                    var profs = _row._lv.workingProfiles.slice()
                                    while (profs.length <= _row.index) profs.push("")
                                    profs[_row.index] = newName
                                    _row._lv.workingProfiles = profs
                                    _row._lv.notifyProfilesChanged(profs)
                                }
                            }
                        }
                    }
                }

                // Divider
                Rectangle {
                    width: parent.width
                    height: 1
                    color: Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.2)
                }

                // Add row
                Item {
                    width: _container.width
                    height: 32

                    Text {
                        anchors.centerIn: parent
                        text: "＋ Add widget"
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

                // Inline add-picker
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

                        // Called via parent.parent.parent from Repeater delegate handlers
                        function addWidget(type) {
                            var list = [..._rowList.workingList, type]
                            _rowList.workingList = list
                            _rowList.notifyListChanged(list)
                            var profs = [..._rowList.workingProfiles, ""]
                            _rowList.workingProfiles = profs
                            _rowList.notifyProfilesChanged(profs)
                            _picker.visible = false
                        }

                        Repeater {
                            // ScriptModel, never the bare array — see "The Repeater crash"
                            // in docs/ARCHITECTURE.md
                            model: ScriptModel {
                                values: WidgetRegistry.types.filter(t => !_rowList.workingList.includes(t))
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
                                        text: root.displayName(modelData)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.textPrimary
                                    }

                                    MouseArea {
                                        id: _pickerItemHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        // parent = Rectangle, parent.parent = Item (delegate), parent.parent.parent = _pickerCol
                                        onClicked: parent.parent.parent.addWidget(modelData)
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
