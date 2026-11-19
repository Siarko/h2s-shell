import QtQuick
import Quickshell
import qs.components
import qs.singletons

// The settings window's page list for the tab that is open, with a mark on the selected
// page and ✎ on pages where the theme edited has unsaved changes (a page's `draftGroups`).
// Pages are the window's (SettingsWindow.pages); clicking one asks with `pageClicked`.
//
// A page with `group: true` is a heading for the pages naming it as their `parent`: they
// show under it, indented, while one of them is open, and fold away when another page
// opens — no toggle of their own; ▾/▸ only shows which. The window opens a group's first
// page when the group is clicked. A page's `shown` function hides it while it returns false.
Item {
    id: root

    property var pages: []
    property string selectedPage: ""
    property string tab: "behaviour"
    // The theme the Appearance pages edit, for their ✎
    property string editTheme: ""

    signal pageClicked(string pageId)

    implicitHeight: _column.implicitHeight

    function _pageIndex(id) {
        return pages.findIndex(page => page.id === id);
    }

    function _tabOf(id) {
        return pages[_pageIndex(id)]?.tab;
    }

    function _parentOf(id) {
        return pages[_pageIndex(id)]?.parent ?? "";
    }

    // The group whose pages show: the open page's parent
    readonly property string _openGroup: _parentOf(selectedPage)

    // The mark slides from the page before only when the page changes within a tab: it
    // sits at the page plus an offset that animates to nothing. Anything else that moves
    // the list (the picker above it growing, a change of tab) moves the mark with it at
    // once, the mark being part of the list.
    property string _previousPage: selectedPage
    property real _markOffset: 0

    onSelectedPageChanged: {
        _slideMark(_previousPage, selectedPage);
        _previousPage = selectedPage;
    }

    function _rowOf(id) {
        return _rows.itemAt(_pageIndex(id))?.row ?? null;
    }

    function _slideMark(from, to) {
        const fromRow = _rowOf(from);
        const toRow = _rowOf(to);
        _markSlide.stop();
        // Into or out of a group the list itself changes height: the mark goes at once
        if (!fromRow || !toRow || _tabOf(from) !== _tabOf(to) || _parentOf(from) !== _parentOf(to)) {
            _markOffset = 0;
            return;
        }
        _markOffset = fromRow.mapToItem(root, 0, 0).y - toRow.mapToItem(root, 0, 0).y;
        _markSlide.start();
    }

    NumberAnimation {
        id: _markSlide
        target: root
        property: "_markOffset"
        to: 0
        duration: Theme.duration("slide")
        easing: Theme.curve("slide")
    }

    // One mark for the whole list, so it slides from the old page to the new one; drawn
    // under the rows
    Rectangle {
        readonly property Item target: _rows.count > root._pageIndex(root.selectedPage) ? root._rowOf(root.selectedPage) : null
        // Followed through the row's own position and its delegate's, both of which move
        readonly property real _targetY: target ? target.y + target.parent.y : 0
        visible: target !== null && target.parent.visible
        y: _targetY + root._markOffset
        width: root.width
        height: target?.height ?? 0
        radius: Theme.settings.sidebarItemRadius
        color: Theme.accentSecondaryTint
        border.width: Theme.border.width
        border.color: Theme.accent
    }

    Column {
        id: _column
        width: parent.width
        spacing: 4

        // Keyed by the page's id (modules' pages come and go) — "The Repeater crash" in
        // docs/ARCHITECTURE.md: a page keeps its row while its id stays
        KeyedModel { id: _pagesModel; values: root.pages; keyProp: "id" }

        Repeater {
            id: _rows
            model: _pagesModel.model

            // A page's row, with room above it for a separator when it has one
            Item {
                id: _delegate
                required property string modelData
                readonly property var page: _pagesModel.byKey[modelData] ?? ({})
                required property int index
                readonly property bool selected: page.id === root.selectedPage
                readonly property Item row: _row
                readonly property bool _child: !!page.parent
                // A group with one of its pages open: lit faintly, the page itself marked
                readonly property bool _groupOpen: !!page.group && root._openGroup === page.id
                // Only the pages of the tab that is open; a group's pages only while it is open
                // A page with `shown` only while it says so (a device the computer has)
                visible: page.tab === root.tab && (!_child || root._openGroup === page.parent)
                    && (page.shown ? page.shown() : true)
                width: _column.width
                height: _row.y + _row.height

                Rectangle {
                    visible: !!_delegate.page.separatorBefore
                    y: 5
                    width: parent.width
                    height: 1
                    color: Theme.textDisabled
                    opacity: 0.3
                }

                Rectangle {
                    id: _row
                    y: _delegate.page.separatorBefore ? 13 : 0
                    width: parent.width
                    height: _delegate._child ? 30 : 34
                    radius: Theme.settings.sidebarItemRadius
                    // The selected one is marked by the sliding mark above
                    color: (_rowArea.lit && !_delegate.selected) || _delegate._groupOpen
                        ? Theme.fillSubtle : Qt.alpha(Theme.fillSubtle, 0)
                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                    // ✎: the theme edited has unsaved changes on this page. On its own at the
                    // right, so cutting a long name never hides it.
                    // A group: open or folded
                    Text {
                        visible: !!_delegate.page.group
                        anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 10 }
                        text: _delegate._groupOpen ? "▾" : "▸"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textMuted
                    }

                    Text {
                        id: _changedMark
                        visible: (Theme.drafts, (_delegate.page.draftGroups ?? []).some(group => Theme.hasDraft(root.editTheme, group)))
                        anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 8 }
                        text: "✎"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBodyLarge
                        color: Theme.warning
                    }

                    Text {
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            leftMargin: _delegate._child ? 24 : 10
                            right: _changedMark.visible ? _changedMark.left : parent.right
                            rightMargin: 6
                        }
                        // A name wider than the sidebar (a larger font) is cut
                        elide: Text.ElideRight
                        text: _delegate.page.label
                        // A module names its page: never read as markup
                        textFormat: Text.PlainText
                        maximumLineCount: 1
                        font.family: Theme.fontFamily
                        font.pixelSize: _delegate._child ? Theme.fontSizeBody : Theme.fontSizeBodyLarge
                        color: _delegate.selected || _delegate._groupOpen ? Theme.textPrimary : Theme.textSecondary
                        Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }
                    }

                    PointerArea {
                        id: _rowArea
                        centred: false
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pageClicked(_delegate.page.id)
                    }
                }
            }
        }
    }
}
