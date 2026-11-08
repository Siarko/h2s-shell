import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

// An editable list in a card: rows reordered by dragging their handle (the settings page
// scrolls when the drag nears its edge), removed with their ×, and added from a list that
// opens under "＋ Add …". What a row shows is the owner's: `rowContent` between the handle
// and the ×, and `rowDetail` under the row while `expandedRows` says so; each is given the
// row's `value` and `index`. The list itself is the owner's too: changes come back as
// moved, removed and added, and `items` follows.
Item {
    id: root

    property string title: ""
    property var items: []
    property Component rowContent: null
    property Component rowDetail: null
    // Rows showing their detail, { index: true }
    property var expandedRows: ({})
    property string addLabel: "＋ Add"
    // What the add list offers, and how each is named there
    property var addOptions: []
    property var optionLabel: value => String(value)

    // `to` is the row's index after the move
    signal moved(int from, int to)
    signal removed(int index)
    signal added(var value)

    readonly property bool dragging: _rowList.dragging

    Layout.fillWidth: true
    implicitHeight: _outer.implicitHeight

    // The rows shown: `items`, except while a row is dragged, and right after a move, before
    // the owner's new list comes back
    property var _shown: []
    Component.onCompleted: _shown = (items ?? []).slice()
    onItemsChanged: if (!_rowList.dragging) _shown = (items ?? []).slice()

    // Scrolls the settings page while a row is dragged near its edge
    DragAutoScroll {
        id: _autoScroll
        item: _rowList
        onScrolled: _rowList.trackPointer(sceneY)
    }

    // Ending a drag and removing a row change `_shown`, which rebuilds the rows — the one
    // whose handler is running too, after which nothing in it resolves. So the work is done
    // here, in the list's own scope, and a row calls these last.
    function _drop() {
        const from = _rowList.dragIndex;
        const to = _rowList.dropIndex;
        _autoScroll.end();
        _rowList.dragIndex = -1;
        _rowList.dropIndex = -1;
        _rowList.dragging = false;
        if (from < 0 || to === from || to === from + 1)
            return;
        const target = to > from ? to - 1 : to;
        const shown = _shown.slice();
        shown.splice(target, 0, shown.splice(from, 1)[0]);
        _shown = shown;
        moved(from, target);
    }

    function _remove(index) {
        const shown = _shown.slice();
        shown.splice(index, 1);
        _shown = shown;
        removed(index);
    }

    // Adding changes what the add list offers, which may rebuild the option clicked
    function _add(value) {
        _picker.open = false;
        _shown = _shown.concat([value]);
        added(value);
    }

    // A row's content and detail are given its value and index
    function _wire(item, row) {
        if (!item)
            return;
        item.value = Qt.binding(() => row.modelData);
        item.index = Qt.binding(() => row.index);
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
            radius: Theme.settings.cardRadius
            border.color: Theme.divider
            border.width: Theme.border.width
            clip: true

            Column {
                id: _container
                width: parent.width
                topPadding: 4
                bottomPadding: 4

                ListView {
                    id: _rowList
                    width: parent.width
                    height: contentHeight
                    interactive: false
                    model: root._shown

                    property bool dragging: false
                    property int dragIndex: -1
                    property int dropIndex: -1

                    // Where the dragged row would drop, for a pointer at sceneY — called on
                    // pointer moves and on every auto-scroll step, when the list moves under
                    // a still pointer. Rows differ in height — one showing its detail is
                    // taller — so the slot comes from the rows' real positions: before the
                    // first row whose 32 px header the pointer is above the middle of.
                    function trackPointer(sceneY) {
                        const listY = mapFromItem(null, 0, sceneY).y;
                        let slot = root._shown.length;
                        for (let i = 0; i < count; i++) {
                            const row = itemAtIndex(i);
                            if (row && listY < row.y + 16) {
                                slot = i;
                                break;
                            }
                        }
                        dropIndex = slot;
                    }

                    delegate: Item {
                        id: _row
                        required property var modelData
                        required property int index
                        readonly property bool _expanded: root.rowDetail !== null && root.expandedRows[index] === true

                        width: _rowList.width
                        height: _expanded ? 32 + (_detail.item?.implicitHeight ?? 0) : 32
                        clip: true
                        opacity: _rowList.dragging && _rowList.dragIndex === index ? 0.35 : 1.0

                        Behavior on height {
                            NumberAnimation { duration: Theme.duration("expand"); easing: Theme.curve("expand") }
                        }

                        // Drop indicator above this row
                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: -1
                            width: parent.width - 16
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 2
                            radius: height / 2
                            color: Theme.accent
                            visible: _rowList.dragging
                                     && _rowList.dropIndex === _row.index
                                     && _rowList.dragIndex !== _row.index
                                     && _rowList.dragIndex !== _row.index - 1
                            z: 10
                        }

                        // Drop indicator below the last row
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: -1
                            width: parent.width - 16
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 2
                            radius: height / 2
                            color: Theme.accent
                            visible: _rowList.dragging
                                     && _row.index === root._shown.length - 1
                                     && _rowList.dropIndex === root._shown.length
                                     && _rowList.dragIndex !== root._shown.length - 1
                            z: 10
                        }

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

                            // The drag handle
                            Item {
                                width: 20
                                height: 32

                                Text {
                                    font.family: Theme.fontFamily
                                    anchors.centerIn: parent
                                    text: "⠿"
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: _handleArea.lit ? Theme.textSecondary : Theme.textDisabled
                                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                                }

                                PointerArea {
                                    id: _handleArea
                                    cursorShape: Qt.SizeVerCursor
                                    // Keeps the drag from the settings page's Flickable
                                    preventStealing: true

                                    onPositionChanged: {
                                        if (_rowList.dragging) {
                                            const sceneY = mapToItem(null, 0, mouseY).y;
                                            _rowList.trackPointer(sceneY);
                                            _autoScroll.update(sceneY);
                                        }
                                    }
                                    onPressed: {
                                        _rowList.dragIndex = _row.index;
                                        _rowList.dropIndex = _row.index;
                                        _rowList.dragging = true;
                                        _autoScroll.begin();
                                    }
                                    onReleased: root._drop()
                                    // A drag taken away (the window losing the pointer) ends
                                    // as if released where it was
                                    onCanceled: root._drop()
                                }
                            }

                            Loader {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                sourceComponent: root.rowContent
                                onLoaded: root._wire(item, _row)
                            }

                            // Remove
                            Rectangle {
                                width: 24
                                height: 24
                                radius: Theme.iconButton.radius
                                color: _removeArea.lit ? Theme.surfaceHover : Theme.surfaceHoverClear
                                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                                Text {
                                    font.family: Theme.fontFamily
                                    anchors.centerIn: parent
                                    text: "×"
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.textDisabled
                                }

                                PointerArea {
                                    id: _removeArea
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root._remove(_row.index)
                                }
                            }
                        }

                        // The row's detail, under it while expanded
                        Loader {
                            id: _detail
                            anchors {
                                top: parent.top
                                topMargin: 32
                                left: parent.left
                                right: parent.right
                                leftMargin: 4
                                rightMargin: 4
                            }
                            active: root.rowDetail !== null
                            visible: _row._expanded
                            sourceComponent: root.rowDetail
                            onLoaded: root._wire(item, _row)
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
                    id: _addRow
                    width: _container.width
                    height: 32

                    Text {
                        anchors.centerIn: parent
                        text: root.addLabel
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: _picker.open = !_picker.open
                    }
                }

                // The add list, floating over what is below rather than pushing it down
                FloatingList {
                    id: _picker
                    anchorItem: _addRow
                    onClosed: open = false

                    Column {
                        id: _pickerColumn
                        width: parent.width
                        topPadding: 4
                        bottomPadding: 4

                        Repeater {
                            // ScriptModel, never the bare array — see "The Repeater crash"
                            // in docs/ARCHITECTURE.md
                            model: ScriptModel {
                                values: root.addOptions
                            }

                            Item {
                                id: _option
                                required property var modelData
                                width: _pickerColumn.width
                                height: 28

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    radius: Theme.listItem.radius
                                    color: _optionArea.lit ? Theme.surfaceHover : Theme.surfaceHoverClear
                                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                                    Text {
                                        anchors {
                                            verticalCenter: parent.verticalCenter
                                            left: parent.left
                                            leftMargin: 8
                                        }
                                        text: root.optionLabel(_option.modelData)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.textPrimary
                                    }

                                    PointerArea {
                                        id: _optionArea
                                        centred: false
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root._add(_option.modelData)
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
