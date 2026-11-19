import QtQuick
import qs.singletons

// The base of the shared blocks views are built from (SettingsPage, and the section, card,
// row and popup section to come): a place modules can address. A view's author writes only
// `anchor` — what the block holds ("saved", "vpns"), never where it stands — and the block's
// path follows from where it stands (ModuleRules.anchorBlockPaths): the nearest enclosing
// block's path plus its own name, found by walking up `parent` — a binding, so a block moved
// under another parent has the new path. The view's root takes the base its window or popup
// gives: the first item up the parents with a string `anchorBase` ("settings.general",
// "popup.network"). A block with no anchor adds no level and is addressable only as the
// view's root. Never on the lock screen (tests/lock-closure.sh).
//
// A kind lays itself out and puts its hosts where its placements go: an AnchorContent with
// `block` and `placement` each — `before` and `after` outside the block, `prepend` and
// `append` first and last of its content, under its frame. A host builds something only while
// the module host lists elements for its path and placement, and only paths in the anchor
// table take any (ModuleRules.anchorTable; the host's own in a suite).
//
// Each addressable block reports itself to Anchors (path → count) while it stands.
Item {
    id: root

    // The block's name ("" none)
    property string anchor: ""
    // What its elements get as `context`, besides { anchor: its path, placement }
    property var context: ({})
    // The module host whose elements it shows: the enclosing block's, else the shell's (a
    // suite gives its own to the view's root)
    property var host: _place.block?.host ?? Modules.host
    // The kind's, for reading: ModuleRules.anchorKinds, and the placements it has hosts for
    property string kind: ""
    property var placements: []

    readonly property bool isAnchorBlock: true
    // Its address ("" not addressable), and what the blocks inside it build on
    readonly property string path: _paths.path
    readonly property string childPath: _paths.childPath

    // The nearest enclosing block, or the base given to the view: { block, path, base }
    readonly property var _place: {
        for (let item = parent; item; item = item.parent) {
            if (item.isAnchorBlock === true)
                return { block: item, path: item.childPath, base: false };
            if (typeof item.anchorBase === "string")
                return { block: null, path: item.anchorBase, base: true };
        }
        return { block: null, path: "", base: false };
    }
    readonly property var _paths: ModuleRules.anchorBlockPaths(_place.path, _place.base, anchor)
    property string _reported: ""

    function _report() {
        if (path === _reported)
            return;
        Anchors.remove(_reported);
        _reported = path;
        Anchors.add(path);
    }

    onPathChanged: _report()
    Component.onCompleted: _report()
    Component.onDestruction: Anchors.remove(_reported)
}
