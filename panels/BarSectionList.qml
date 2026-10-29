import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons
import qs.components

// The widgets of one bar section: reorder by dragging, add, remove, and per entry its
// popup mode and widget preset. Edits come back whole through `edited`, so the owner
// stores the section as one value.
Item {
    id: root
    property string title: ""
    // [{ type, preset }]
    property var entries: []
    property string section: ""
    // The shell profile being edited, picked in the settings window
    property int editIndex: -1

    signal edited(var newEntries)

    Layout.fillWidth: true
    implicitHeight: _outer.implicitHeight

    // Scrolls the settings page while a row is dragged near its edge
    DragAutoScroll {
        id: _autoScroll
        item: _rowList
        onScrolled: _rowList.trackPointer(sceneY)
    }

    function _load() {
        _rowList.workingList = (entries ?? []).map(entry => entry.type)
        _rowList.workingPresets = (entries ?? []).map(entry => entry.preset ?? "")
    }
    Component.onCompleted: _load()
    onEntriesChanged: if (!_rowList.dragging) _load()

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
            color: Theme.surfaceSunken
            radius: 6
            border.color: Theme.divider
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
                        property var workingPresets: []
                        property bool dragging: false
                        property int dragIndex: -1
                        property int dropIndex: -1
                        property Item ghost: _dragGhost

                        // Where the dragged row would drop, and where its ghost is drawn,
                        // for a pointer at sceneY — called on pointer moves and on every
                        // auto-scroll step, when the list moves under a still pointer
                        function trackPointer(sceneY) {
                            const listY = mapFromItem(null, 0, sceneY).y
                            // Rows differ in height — one with its settings open is taller —
                            // so the drop slot comes from the rows' real positions: before
                            // the first row whose 32 px header the pointer is above the
                            // middle of
                            let slot = workingList.length
                            for (let i = 0; i < count; i++) {
                                const row = itemAtIndex(i)
                                if (row && listY < row.y + 16) {
                                    slot = i
                                    break
                                }
                            }
                            dropIndex = slot
                            ghost.y = Math.max(0, Math.min(contentHeight - 32, listY - 16))
                        }
                        property var expandedSet: ({})

                        function toggleExpanded(idx) {
                            var s = Object.assign({}, expandedSet)
                            if (s[idx]) delete s[idx]; else s[idx] = true
                            expandedSet = s
                        }

                        // Proxy functions called from delegate JS handlers via _row._lv
                        // Both arrays at once: types and their presets are one entry each
                        function commit(list, presets) {
                            workingList = list
                            workingPresets = presets
                            root.edited(list.map((type, index) => ({ type: type, preset: presets[index] || "" })))
                        }
                        function notifySettingsClicked(idx) {
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
                                color: Theme.accent
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
                                color: Theme.accent
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
                                        color: _handleArea.containsMouse ? Theme.textSecondary : Theme.textDisabled
                                    }

                                    MouseArea {
                                        id: _handleArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.SizeVerCursor
                                        // Keeps the drag from the settings page's Flickable
                                        preventStealing: true

                                        onPositionChanged: {
                                            if (_row._lv.dragging) {
                                                const sceneY = mapToItem(null, 0, mouseY).y
                                                _row._lv.trackPointer(sceneY)
                                                _autoScroll.update(sceneY)
                                            }
                                        }
                                        onPressed: {
                                            _row._lv.dragIndex = _row.index
                                            _row._lv.dropIndex = _row.index
                                            _row._lv.dragging = true
                                            _row._lv.ghost.visible = true
                                            _row._lv.ghost.y = _row.y
                                            _autoScroll.begin()
                                        }
                                        onReleased: {
                                            _autoScroll.end()
                                            _row._lv.ghost.visible = false
                                            _row._lv.dragging = false
                                            var from = _row._lv.dragIndex
                                            var to = _row._lv.dropIndex
                                            if (to !== from && to !== from + 1) {
                                                var list = _row._lv.workingList.slice()
                                                var moved = list.splice(from, 1)[0]
                                                var adjTo = to > from ? to - 1 : to
                                                list.splice(adjTo, 0, moved)
                                                var presets = _row._lv.workingPresets.slice()
                                                var movedPreset = presets.splice(from, 1)[0] || ""
                                                presets.splice(adjTo, 0, movedPreset)
                                                _row._lv.commit(list, presets)
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

                                // Only for widgets with something to set: a popup mode or presets
                                // (not the settings button or the tray)
                                Rectangle {
                                    visible: WidgetRegistry.hasPopupMode(_row.modelData) || WidgetRegistry.hasPresets(_row.modelData)
                                    width: 24
                                    height: 24
                                    radius: 4
                                    color: _gearHover.containsMouse ? Theme.surfaceHover : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "⚙"
                                        font.pixelSize: Theme.fontSizeBodyLarge
                                        color: _row._expanded ? Theme.accent : Theme.textSecondary
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
                                    color: _removeHover.containsMouse ? Theme.surfaceHover : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "×"
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.textDisabled
                                    }

                                    MouseArea {
                                        id: _removeHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var list = _row._lv.workingList.slice()
                                            list.splice(_row.index, 1)
                                            var presets = _row._lv.workingPresets.slice()
                                            presets.splice(_row.index, 1)
                                            _row._lv.commit(list, presets)
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
                                editIndex: root.editIndex
                                currentPreset: _row._lv.workingPresets[_row.index] || ""
                                onPresetAssigned: function(newName) {
                                    var presets = _row._lv.workingPresets.slice()
                                    while (presets.length <= _row.index) presets.push("")
                                    presets[_row.index] = newName
                                    _row._lv.commit(_row._lv.workingList.slice(), presets)
                                }
                            }
                        }
                    }
                }

                // Divider
                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.divider
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
                    color: Theme.surfaceSunken
                    radius: 6
                    z: 10

                    Column {
                        id: _pickerCol
                        width: parent.width
                        topPadding: 4
                        bottomPadding: 4

                        // Called via parent.parent.parent from Repeater delegate handlers
                        function addWidget(type) {
                            _rowList.commit([..._rowList.workingList, type], [..._rowList.workingPresets, ""])
                            _picker.visible = false
                        }

                        Repeater {
                            // ScriptModel, never the bare array — see "The Repeater crash"
                            // in docs/ARCHITECTURE.md
                            model: ScriptModel {
                                // Once per section, except widgets that can repeat with
                                // different presets (two clocks, two hardware capsules)
                                values: WidgetRegistry.types.filter(t => !_rowList.workingList.includes(t)
                                                                        || WidgetRegistry.allowsMultiple(t))
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
                                    color: _pickerItemHover.containsMouse ? Theme.surfaceHover : "transparent"

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
