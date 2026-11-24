import QtQuick
import QtQuick.Layouts
import qs.singletons

// A panel sliding in from the right over the area it fills (a settings page), the area
// dimmed behind it: a fixed title line with Close, and its content below, scrolled. The
// content (`content`, a Component) is built when it opens and destroyed once it has slid
// out; it is laid out at the panel's inner width and must not scroll itself.
//
// It never closes itself: what the user does is reported by `requested(event)` — Close
// "closeButton", a click on the dimmed area "outsideClick", Escape "escape" — and the owner
// sets `open`. Escape first closes a dropdown's list open inside it (ApiElementRules.
// sidePanelEvent). Opening, it takes the keyboard, given back on closing to the item that had
// it; Tab stays inside it while open.
//
//   SideDrawer { anchors.fill: parent; open: shown; title: "Files"; content: filesComp
//                onRequested: event => shown = false }
Item {
    id: root

    property bool open: false
    property string title: ""
    property real panelWidth: Theme.sidePanelWidths.m
    property Component content: null
    signal requested(string event)

    // The content, built (null while closed and once it has slid out)
    readonly property Item contentItem: _content.item
    readonly property Item panel: _panel

    // The component shown: set when it opens, cleared once the panel is out of sight, so the
    // content stays while it slides out
    property Component _shown: null
    // Takes the content away at once, the panel out of sight: what it showed is going (its
    // page destroyed)
    function dropContent() {
        _shown = null;
    }

    onOpenChanged: {
        if (open) {
            _shown = content;
            _trap.take();
        } else {
            _trap.giveBack();
        }
    }
    onContentChanged: if (open) _shown = content

    function _isInside(item) {
        return _trap.isInside(item);
    }

    // Tab stays inside while open. The keyboard is not held: a Settings modal asked from the
    // panel takes it, and gives it back when it closes
    FocusTrap {
        id: _trap
        scope: _panel
        active: root.open && root.visible
    }

    // A dropdown's list open over the panel (components/FloatingList.qml, which lives in the
    // window's top item while open), anchored inside it
    function _openLists() {
        const top = Window.window?.contentItem ?? null;
        if (!top)
            return [];
        return Array.from(top.children).filter(child => child.floatingList === true && child.open === true
            && child.anchorItem && _isInside(child.anchorItem));
    }

    function _escape() {
        const lists = _openLists();
        const outcome = ApiElementRules.sidePanelEvent(open, "escape", lists.length > 0);
        if (outcome.closeList) {
            for (const list of lists)
                list.closed();
        } else if (outcome.close) {
            requested("escape");
        }
    }

    // ── The dimmed area: a click on it closes the panel; the page under it takes nothing ──
    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.open ? 0.35 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.duration("slide"); easing: Theme.curve("slide") } }
        MouseArea {
            anchors.fill: parent
            enabled: root.open
            onClicked: root.requested("outsideClick")
            onWheel: wheel => wheel.accepted = true
        }
    }

    // Escape anywhere in the window while open, whatever has the focus inside it
    Shortcut {
        sequence: "Escape"
        enabled: root.open && root.visible
        onActivated: root._escape()
    }

    // How far the panel is in, 0 (out of sight) to 1: only opening and closing move it, so the
    // area changing size moves the panel with its edge at once, never slides it
    property real _shift: open ? 1 : 0
    Behavior on _shift { NumberAnimation { duration: Theme.duration("slide"); easing: Theme.curve("slide") } }
    on_ShiftChanged: if (_shift <= 0 && !open) _shown = null

    FocusScope {
        id: _panel
        width: root.panelWidth
        height: root.height
        x: root.width - width * root._shift
        visible: root._shift > 0

        Rectangle {
            anchors.fill: parent
            color: Theme.popupBackground
            border.width: Theme.border.width
            border.color: Theme.outline
        }

        // Clicks and the wheel on the panel stay on it
        MouseArea {
            anchors.fill: parent
            onPressed: _panel.forceActiveFocus()
            onWheel: wheel => wheel.accepted = true
        }

        // ── The title line, fixed ──
        RowLayout {
            id: _titleLine
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.settings.pageMargin }
            spacing: 6
            Text {
                Layout.fillWidth: true
                text: ApiElementRules.oneLine(root.title)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                color: Theme.textPrimary
            }
            SmallButton {
                label: "Close"
                onClicked: root.requested("closeButton")
            }
        }

        // ── The content, scrolled below it ──
        Flickable {
            id: _scroller
            anchors {
                left: parent.left; right: parent.right; top: _titleLine.bottom; bottom: parent.bottom
                leftMargin: Theme.settings.pageMargin; rightMargin: Theme.settings.pageMargin; topMargin: 8
            }
            contentWidth: width
            contentHeight: _content.height + Theme.settings.pageMargin
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Loader {
                id: _content
                width: _scroller.width
                sourceComponent: root._shown
            }
        }
    }
}
