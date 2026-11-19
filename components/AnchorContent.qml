import QtQuick
import QtQuick.Layouts
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
// module and file stay, whatever comes and goes before it (a KeyedModel of
// ModuleMergeRules.contributionKey).
//
// `stacked`: each element at its own width on the host's right edge, at most `maxElementWidth`
// wide — a card's buttons (SettingsCard's `actions`); otherwise each is as wide as the host.
// On a place whose row `takes` an element (a SmallButton), another is refused
// (ModuleContribution). `elementProperties` are given to each element that declares them (the
// stack's button size).
Item {
    id: root

    // The block it stands in, and the placement it is
    property var block: null
    property string placement: ""
    property real spacing: 4
    // Whether it shows its elements at all: false builds none and destroys those built (a
    // card's region while the card is closed)
    property bool active: true
    // Each element at its own width on the right edge, at most maxElementWidth (a card's
    // stacked buttons), instead of as wide as the host
    property bool stacked: false
    property real maxElementWidth: Infinity
    // Given to each element that declares them ({ size: "m" })
    property var elementProperties: ({})

    readonly property string path: block?.path ?? ""
    readonly property var host: block?.host ?? null
    // The provider module an own-provider place shows (the block's)
    readonly property string scopeId: block?.scopeId ?? ""
    // [{ module, at, place, component, context, key }], in the one order: none unless the
    // block is of its row's kind and has this placement (ModuleRules.anchorBlockFits)
    readonly property var _row: host && path !== "" ? ModuleRules.anchorRow(host.anchorTable, path) : null
    readonly property var contributions: active && _row && placement !== ""
        && ModuleRules.anchorBlockFits(_row, block.kind, block.placements, placement)
        ? host.anchorContent(path, placement, scopeId) : []
    // What an element here must be ("" anything): the row's
    readonly property string takes: typeof _row?.takes === "string" ? _row.takes : ""
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

    KeyedModel { id: _contributions; values: root.contributions; keyProp: "key" }

    visible: count > 0
    implicitWidth: count > 0 && _loader.item ? _loader.item.implicitWidth : 0
    implicitHeight: count > 0 && _loader.item ? _loader.item.implicitHeight : 0

    Loader {
        id: _loader
        width: root.width
        active: root.count > 0
        sourceComponent: root.stacked ? _stack : _column
    }

    // The contributions' keys — "The Repeater crash" in docs/ARCHITECTURE.md: an element is
    // the same delegate while its module and file stay
    Component {
        id: _column

        Column {
            property alias repeater: _repeater
            width: root.width
            spacing: root.spacing

            Repeater {
                id: _repeater
                model: _contributions.model

                ModuleContribution {
                    required property string modelData
                    readonly property var contribution: _contributions.byKey[modelData] ?? ({})
                    host: root.host
                    moduleId: contribution.module ?? ""
                    url: contribution.component ?? ""
                    anchor: root.path
                    placement: root.placement
                    takes: root.takes
                    properties: root.elementProperties
                    context: Object.assign({}, root.block?.context ?? {}, contribution.context ?? {}, { anchor: root.path, placement: root.placement })
                    width: root.width
                }
            }
        }
    }

    // Stacked: a layout, not a positioner — it gives each element a whole width, so its edges
    // stand on whole pixels, as the card's own buttons do
    Component {
        id: _stack

        ColumnLayout {
            property alias repeater: _repeater
            width: root.width
            spacing: root.spacing

            Repeater {
                id: _repeater
                model: _contributions.model

                ModuleContribution {
                    required property string modelData
                    readonly property var contribution: _contributions.byKey[modelData] ?? ({})
                    host: root.host
                    moduleId: contribution.module ?? ""
                    url: contribution.component ?? ""
                    anchor: root.path
                    placement: root.placement
                    takes: root.takes
                    properties: root.elementProperties
                    context: Object.assign({}, root.block?.context ?? {}, contribution.context ?? {}, { anchor: root.path, placement: root.placement })
                    Layout.alignment: Qt.AlignRight
                    Layout.maximumWidth: root.maxElementWidth
                }
            }
        }
    }
}
