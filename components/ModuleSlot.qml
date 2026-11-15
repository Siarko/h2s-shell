import QtQuick
import Quickshell
import qs.singletons

// A place in a core panel where modules may put content (docs/plans/modules.md, "Module API
// 1.0"; the names the core offers and each one's context: ModuleRules.slotTable — never on the
// lock screen):
//
//   ModuleSlot { name: "network.popup.sections"; context: ({ wifiEnabled: … }); width: parent.width }
//
// Every loaded module's contribution to `name` (its manifest's slots) is built in a guard of
// its own (ModuleContribution: one that fails shows nothing and is recorded in its module's
// status), gets the module's handle as `module` and `{ slot: name, …context }` as `context`
// (again only when that changes by value), and is laid out in a column (orientation
// Qt.Horizontal: a row). With no contribution the slot has no size and builds nothing; a module
// turned off takes its contribution with it, turned on brings it back.
Item {
    id: root

    property string name: ""
    property var context: ({})
    property int orientation: Qt.Vertical
    property real spacing: 4
    // The host whose modules fill it (the shell's; the suites give their own)
    property var host: Modules.host

    // [{ module, slot, component }], in module order
    readonly property var contributions: host && name !== "" ? host.slotContributions(name) : []
    readonly property int count: contributions.length
    // The contributions built now (Items), for the core's tests
    readonly property var items: {
        const built = [];
        for (let i = 0; i < _repeater.count; i++) {
            const item = _repeater.itemAt(i);
            if (item)
                built.push(item);
        }
        return built;
    }

    readonly property var _model: contributions.map(entry => Object.assign({ key: ModuleRules.contributionKey(entry) }, entry))
    readonly property var _context: Object.assign({}, context ?? {}, { slot: name })

    visible: count > 0
    implicitWidth: count > 0 ? _grid.implicitWidth : 0
    implicitHeight: count > 0 ? _grid.implicitHeight : 0

    Grid {
        id: _grid
        width: root.orientation === Qt.Vertical ? root.width : implicitWidth
        columns: root.orientation === Qt.Horizontal ? Math.max(1, root.count) : 1
        spacing: root.spacing

        Repeater {
            id: _repeater
            // ScriptModel, never the bare array — "The Repeater crash" in docs/ARCHITECTURE.md;
            // a contribution is the same delegate while its module and file stay
            model: ScriptModel {
                objectProp: "key"
                values: root._model
            }

            ModuleContribution {
                required property var modelData
                host: root.host
                moduleId: modelData.module
                url: modelData.component
                slot: root.name
                context: root._context
                width: root.orientation === Qt.Vertical ? _grid.width : implicitWidth
            }
        }
    }
}
