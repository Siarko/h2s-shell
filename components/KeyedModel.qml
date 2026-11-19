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

    // The current keys, in order, and the item of each. byKey also holds, until the next
    // change, the items the last change removed: a view may keep a removed delegate a
    // moment (a ListView until its next layout), and its bindings still find their item.
    property var keys: []
    property var byKey: Object.create(null)
    readonly property int count: keys.length

    readonly property ScriptModel model: ScriptModel { values: root.keys }

    // The items of the current keys only
    property var _current: Object.create(null)

    function _update() {
        const next = ListKeyRules.keyed(values, keyProp, keyOf);
        // Set before the keys: a delegate created for a new key finds its item at once
        byKey = ListKeyRules.union(_current, next.byKey);
        _current = next.byKey;
        keys = next.keys;
    }

    onValuesChanged: _update()
    onKeyPropChanged: _update()
    onKeyOfChanged: _update()
    Component.onCompleted: _update()
}
