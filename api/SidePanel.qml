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
// logged once. It takes no room where it is written. closed("page") for a page or module
// going runs while the page is torn down: other items of the page may already be gone, so a
// handler only sets the module's own state.
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

    // What it is open in, and what closes it, is kept by ApiElements, not on this item: a
    // module reaches nothing of the frame through it
    onSizeChanged: ApiElements.sidePanelCheckSize(root)
    onOpenChanged: open ? ApiElements.sidePanelOpened(root) : ApiElements.sidePanelShut(root)
    Component.onCompleted: {
        ApiElements.sidePanelCheckSize(root);
        // An `open` given at creation is looked at now, with the panel among its parents
        ApiElements.sidePanelCompleted(root);
    }
    Component.onDestruction: ApiElements.sidePanelGone(root)
}
