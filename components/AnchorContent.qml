import QtQuick
import Quickshell
import qs.singletons

// A block's host for one placement (components/AnchorBlock.qml): the modules' elements at
// the block's path and `placement`, top to bottom in the one order (ModuleMergeRules.
// anchorContent: by module id, a module's in its manifest's order) — on an own-provider place
// only the block's `scopeId` module's; nothing on a block not of its row's kind or without
// this placement.
//
//   AnchorContent { block: root; placement: "append"; Layout.fillWidth: true }
//
// Each element is built in a guard of its own (ModuleContribution: one that fails shows
// nothing and is recorded in its module's status), gets its module's handle as `module` and
// `{ …the block's context, anchor: the path, placement }` as `context` (a slot read as an
// anchor adds `slot`) — passed again only when that changes by value. With no element the
// host has no size and builds nothing, not even its Repeater; a module turned off takes its
// elements with it, turned on brings them back; `active` false (a closed card's region) does
// the same. An element is the same delegate while its
// module and file stay (ScriptModel keyed by ModuleMergeRules.contributionKey).
Item {
    id: root

    // The block it stands in, and the placement it is
    property var block: null
    property string placement: ""
    property real spacing: 4
    // Whether it shows its elements at all: false builds none and destroys those built (a
    // card's region while the card is closed)
    property bool active: true

    readonly property string path: block?.path ?? ""
    readonly property var host: block?.host ?? null
    // The provider module an own-provider place shows (the block's)
    readonly property string scopeId: block?.scopeId ?? ""
    // [{ module, at, place, component, context, key }], in the one order: none unless the
    // block is of its row's kind and has this placement (ModuleRules.anchorBlockFits)
    readonly property var contributions: active && host && path !== "" && placement !== ""
        && ModuleRules.anchorBlockFits(ModuleRules.anchorRow(host.anchorTable, path), block.kind, block.placements, placement)
        ? host.anchorContent(path, placement, scopeId) : []
    readonly property int count: contributions.length
    // The elements built now (ModuleContribution items), and whether the list exists at all —
    // for the core's tests
    readonly property bool built: _loader.item !== null
    readonly property var items: {
        const built = [];
        const repeater = _loader.item?.repeater ?? null;
        for (let i = 0; repeater && i < repeater.count; i++) {
            const item = repeater.itemAt(i);
            if (item)
                built.push(item);
        }
        return built;
    }
    readonly property var repeaterModel: _loader.item?.repeater.model ?? null

    visible: count > 0
    implicitWidth: count > 0 && _loader.item ? _loader.item.implicitWidth : 0
    implicitHeight: count > 0 && _loader.item ? _loader.item.implicitHeight : 0

    Loader {
        id: _loader
        width: root.width
        active: root.count > 0
        sourceComponent: Column {
            property alias repeater: _repeater
            width: root.width
            spacing: root.spacing

            Repeater {
                id: _repeater
                // ScriptModel, never the bare array — "The Repeater crash" in
                // docs/ARCHITECTURE.md; an element is the same delegate while its module and
                // file stay
                model: ScriptModel {
                    objectProp: "key"
                    values: root.contributions
                }

                ModuleContribution {
                    required property var modelData
                    host: root.host
                    moduleId: modelData.module
                    url: modelData.component
                    anchor: root.path
                    placement: root.placement
                    context: Object.assign({}, root.block?.context ?? {}, modelData.context ?? {}, { anchor: root.path, placement: root.placement })
                    width: root.width
                }
            }
        }
    }
}
