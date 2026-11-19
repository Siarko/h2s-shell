import QtQuick
import Quickshell
import qs.singletons

// A list of JS objects for a Repeater or ListView, keyed: `model` is a ScriptModel of string
// keys, and a delegate looks its item up by key (its modelData):
//
//     KeyedModel { id: _networks; values: root._saved; keyProp: "uuid" }
//     Repeater {
//         model: _networks.model
//         delegate: Card {
//             required property string modelData
//             readonly property var network: _networks.byKey[modelData] ?? null
//         }
//     }
//
// Rows are inserted, removed and moved by key, so a delegate stays with its item for its
// whole life (its state — typed text, an open form — with it), and a changed item reaches
// it through the binding. ScriptModel given the objects themselves gets this wrong when they
// are built anew on each read (ListKeyRules says why). The Repeater-crash rule holds: the
// view's model is one ScriptModel, never reassigned.
QtObject {
    id: root

    // The items, in order
    property var values: []
    // The property of an item that is its key — or `keyOf`, a function of the item, when the
    // key is not one property. Neither: the value itself (strings, numbers).
    property string keyProp: ""
    property var keyOf: null

    // The current keys, in order, and the item of each
    property var keys: []
    property var byKey: Object.create(null)
    readonly property int count: keys.length

    readonly property ScriptModel model: ScriptModel { values: root.keys }

    function _update() {
        const next = ListKeyRules.keyed(values, keyProp, keyOf);
        // While the rows change, every key old and new finds its item: a delegate being
        // created reads the new map, one being removed still finds its old item
        byKey = ListKeyRules.union(byKey, next.byKey);
        keys = next.keys;
        byKey = next.byKey;
    }

    onValuesChanged: _update()
    onKeyPropChanged: _update()
    onKeyOfChanged: _update()
    Component.onCompleted: _update()
}
