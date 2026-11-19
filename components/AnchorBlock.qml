import QtQuick
import qs.singletons

// The base of the shared blocks views are built from (SettingsPage, SettingsSection,
// SettingsCard and its region, PopupSection, PopupRow, and the settings row to come): a place
// modules can address. A view's author writes only `anchor` — what the block holds ("saved",
// "vpns"), never where it stands — and the block's path follows from where it stands
// (ModuleRules.anchorBlockPaths): the nearest enclosing block's path plus its own name, found
// by walking up `parent` — a binding, so a block moved under another parent has the new path.
// The view's root takes the base its window or popup gives: the first item up the parents
// with a string `anchorBase` ("settings.general", "popup.network"). A card's region (kind
// "region": SettingsCard's `settings`) is named by the region, right under a block named
// "card", and nothing inside it is addressable. A block with no anchor adds no level and is
// addressable only as the view's root — a block of a root kind (ModuleRules.anchorRootKinds:
// a SettingsPage, a PopupSection) right at the base; a section with no anchor straight under
// a plain item is not. Never on the lock screen (tests/lock-closure.sh).
//
// On a place whose row's scope is "own-provider" (a VPN provider's card or row), a host shows
// only the elements of the module `scopeId` names — the provider's module, which the view
// sets on the item's block; the blocks inside it take it. With no scopeId such a place shows
// nothing.
//
// A kind lays itself out and puts its hosts where its placements go: an AnchorContent with
// `block` and `placement` each — `before` and `after` outside the block, `prepend` and
// `append` first and last of its content, under its frame. A host builds something only while
// the module host lists elements for its path and placement, only paths in the anchor table
// take any (ModuleRules.anchorTable; the host's own in a suite), and only on a block of the
// row's kind with that placement among its `placements` (ModuleRules.anchorBlockFits).
//
// Each addressable block reports itself to Anchors (path → count) while it stands, from when
// it is complete (a path seen while it is being built is not reported).
Item {
    id: root

    // The block's name ("" none)
    property string anchor: ""
    // What its elements get as `context`, besides { anchor: its path, placement }
    property var context: ({})
    // The module host whose elements it shows: the enclosing block's, else the shell's (a
    // suite gives its own to the view's root)
    property var host: _place.block?.host ?? Modules.host
    // The provider module whose elements an own-provider place shows ("" none): the
    // enclosing block's unless the view sets it
    property string scopeId: _place.block?.scopeId ?? ""
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
    readonly property var _paths: ModuleRules.anchorBlockPaths(_place.path, _place.base, anchor, kind)
    property string _reported: ""
    property bool _completed: false

    function _report() {
        if (!_completed || path === _reported)
            return;
        Anchors.remove(_reported);
        _reported = path;
        Anchors.add(path);
    }

    onPathChanged: _report()
    Component.onCompleted: {
        _completed = true;
        _report();
    }
    // At the engine's end the singleton may be gone before the block
    Component.onDestruction: Anchors?.remove(_reported)
}
