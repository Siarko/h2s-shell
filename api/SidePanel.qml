import QtQuick
import qs.singletons

// The public side panel (module API 1.34): a panel sliding in from the right over a
// module's settings page, the page dimmed beside it — a fixed title line with Close, and
// its content below, scrolled by the panel.
//
//   SidePanel { id: files; title: "Taildrop"; size: "l"; ColumnLayout { … } }
//   SmallButton { label: "Files…"; onClicked: files.open = true }
//
// `open`: the owner sets it true; the panel sets it false when it closes itself, and says
// why with closed(reason) — "close" (its Close button), "outside" (a click on the dimmed
// page), "escape", "replaced" (another SidePanel opened), "page" (the page changed, the
// window closed, the module went away), "lock" (the session locked). The owner setting it
// false closes it without a reason. Its one child is its content (`content`, a Component):
// built when it opens, destroyed when it has closed, laid out at the panel's inner width —
// it must not scroll itself. One is open per page frame. Anywhere in a module's page tree;
// elsewhere (a popup panel, an anchor, the bar) it does not open: `open` goes back to false,
// logged once. It takes no room where it is written.
//
// The panel itself lives in the page frame (components/ModulePageFrame.qml, its
// SidePanelHost), found by walking up from here: what is declared here is all a module can
// rely on.
Item {
    id: root

    property bool open: false
    property string title
    property string size: "m"
    default property Component content
    signal closed(string reason)

    // Not laid out: a layout skips a hidden item, and the panel shows in the page frame
    visible: false
    width: 0
    height: 0

    // The side of it a module does not see: the host it is open in (null while closed, or
    // once that host is gone), and what the host calls to close it
    QtObject {
        id: _panel

        property Item host: null

        function checkSize() {
            if (!ApiElementRules.sidePanelSize(root.size).known)
                ApiElements.unknown("SidePanel", "size", root.size, ApiElementRules.sizeDefault);
        }

        function opened() {
            if (host)
                return;
            const found = ApiElements.sidePanelHostAbove(root);
            const refusal = found ? found.show(root, reason => _panel.closedBy(reason)) : ApiElementRules.sidePanelRefusal(false, false);
            if (refusal !== "") {
                ApiElements.once("SidePanel.open:" + refusal, "[Api] SidePanel: not opened, " + refusal);
                root.open = false;
                return;
            }
            host = found;
        }

        // The owner set `open` false
        function shut() {
            if (!host)
                return;
            const was = host;
            host = null;
            was.hide(root);
        }

        // The host closes it: why (a word of ApiElementRules.sidePanelReasons)
        function closedBy(reason) {
            if (!host)
                return;
            host = null;
            root.open = false;
            root.closed(reason);
        }

        // Destroyed while open (its page or module gone)
        function gone() {
            if (!root.open || !host)
                return;
            const was = host;
            host = null;
            was.release(root);
            root.open = false;
            root.closed(ApiElementRules.sidePanelReasons.pageGone);
        }
    }

    onSizeChanged: _panel.checkSize()
    onOpenChanged: open ? _panel.opened() : _panel.shut()
    Component.onCompleted: {
        _panel.checkSize();
        if (open)
            _panel.opened();
    }
    Component.onDestruction: _panel.gone()
}
