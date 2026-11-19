import QtQuick
import qs.singletons

// ListKeyRules (pure) and components/KeyedModel.qml on a real Repeater, with new objects at
// every step as a refetch gives them: a delegate stays with its item through inserts,
// removals and moves, shows that item's current data, and keeps its own state.
TestCase {
    id: suite
    suiteName: "ListKeyRules"

    function _keys(values, keyProp, keyFunction) {
        return JSON.stringify(ListKeyRules.keyed(values, keyProp, keyFunction).keys);
    }

    // A Repeater on a KeyedModel of { id, name } objects; each delegate has `item` (its
    // looked-up object), `shown` (the name it shows) and `typed` (state of its own)
    function _repeater() {
        return Qt.createQmlObject("import QtQuick\nimport qs.components\nItem {\n"
            + "    property alias list: list\n    property alias repeater: repeater\n"
            + "    KeyedModel { id: list; keyProp: \"id\" }\n"
            + "    Column { Repeater { id: repeater; model: list.model\n"
            + "        delegate: Item {\n"
            + "            required property string modelData\n"
            + "            readonly property var item: list.byKey[modelData] ?? null\n"
            + "            readonly property string shown: item.name\n"
            + "            property string typed: \"\"\n"
            + "        }\n"
            + "    } }\n"
            + "}", suite, "KeyedModelProbe.qml");
    }

    function _items(names) {
        return names.map(name => ({ id: name.toLowerCase(), name: name }));
    }

    function _delegates(view) {
        const result = [];
        for (let i = 0; i < view.repeater.count; i++)
            result.push(view.repeater.itemAt(i));
        return result;
    }

    function _shown(view) {
        return _delegates(view).map(delegate => delegate.shown).join(",");
    }

    function run() {
        // --- keys ---
        assertEqual(_keys([{ id: "a" }, { id: "b" }], "id"), "[\"a\",\"b\"]", "the key property, in order");
        assertEqual(_keys([{ id: 1 }, { id: 2 }], "id"), "[\"1\",\"2\"]", "numbers become strings");
        assertEqual(_keys(["x", "y"]), "[\"x\",\"y\"]", "no key property: the value itself");
        assertEqual(_keys([{ a: 1, b: 2 }], "", item => item.a + "/" + item.b), "[\"1/2\"]", "a key function");
        assertEqual(_keys([{ id: "a" }, { id: "a" }, { id: "a" }], "id"), "[\"a\",\"a#2\",\"a#3\"]",
                    "a repeated key is made unique by its count");
        assertEqual(_keys([{ id: "a#2" }, { id: "a" }, { id: "a" }], "id"), "[\"a#2\",\"a\",\"a#3\"]",
                    "… past a real key of that spelling");
        assertEqual(_keys([{ name: "x" }, null], "id"), "[\"\",\"#2\"]", "no key: \"\", made unique");
        assertEqual(_keys(null, "id"), "[]", "not a list: empty");
        assertEqual(_keys("abc"), "[]", "a string is not a list of its letters");
        const odd = ListKeyRules.keyed([{ id: "constructor" }, { id: "toString" }], "id");
        assertEqual(odd.byKey["constructor"]?.id, "constructor", "byKey has no prototype: \"constructor\" is an item");
        assertEqual(ListKeyRules.keyed([{ id: "a" }], "id").byKey["toString"], undefined, "… and an absent key finds nothing");
        const proto = ListKeyRules.keyed([{ id: "__proto__", name: "P" }, { id: "__proto__", name: "P2" }, { id: "constructor" }], "id");
        assertEqual(JSON.stringify(proto.keys), "[\"__proto__\",\"__proto__#2\",\"constructor\"]", "\"__proto__\" is a key like any other, made unique when repeated");
        assert(proto.byKey["__proto__"]?.name === "P" && proto.byKey["__proto__#2"]?.name === "P2" && Object.keys(proto.byKey).length === 3,
               "… and byKey holds it as an item, not as a prototype");
        const protoMerged = ListKeyRules.union(proto.byKey, ListKeyRules.keyed([{ id: "__proto__", name: "P3" }], "id").byKey);
        assert(protoMerged["__proto__"]?.name === "P3" && protoMerged["constructor"]?.id === "constructor", "union: \"__proto__\" merged as an item");
        const merged = ListKeyRules.union({ a: 1, b: 2 }, { b: 3, c: 4 });
        assertEqual(JSON.stringify([merged.a, merged.b, merged.c]), "[1,3,4]", "union: both, the newer winning");

        // --- on a Repeater, new objects at every step ---
        const view = _repeater();
        view.list.values = _items(["A", "B", "C", "D"]);
        assertEqual(_shown(view), "A,B,C,D", "the delegates show the items");
        let before = _delegates(view);
        before.forEach(delegate => delegate.typed = delegate.shown.toLowerCase());

        view.list.values = _items(["A", "C", "D"]);
        let after = _delegates(view);
        assertEqual(_shown(view), "A,C,D", "a removal in the middle: the rest show their items");
        assert(after[0] === before[0] && after[1] === before[2] && after[2] === before[3],
               "… each in its own delegate — B's delegate went, not D's");
        assertEqual(after.map(delegate => delegate.typed).join(","), "a,c,d", "… with its own state");
        assert(view.list.byKey["b"]?.name === "B", "a removed item is still found until the next change (a view may keep its delegate a moment)");

        before = after;
        view.list.values = _items(["A", "X", "C", "D"]);
        after = _delegates(view);
        assertEqual(_shown(view), "A,X,C,D", "an insert in the middle");
        assertEqual(view.list.byKey["b"], undefined, "… then it is gone");
        assert(after[0] === before[0] && after[2] === before[1] && after[3] === before[2] && after[1].typed === "",
               "… a new delegate for the new item, the others kept");

        before = after;
        view.list.values = [{ id: "d", name: "D2" }].concat(_items(["A", "X", "C"]));
        after = _delegates(view);
        assertEqual(_shown(view), "D2,A,X,C", "a move to the front with new data: the moved row shows the new data");
        assert(after[0] === before[3] && after[1] === before[0] && after[2] === before[1] && after[3] === before[2],
               "… in the same delegates");
        assertEqual(after[0].typed, "d", "… the moved delegate keeps its state");

        before = after;
        view.list.values = _items(["C", "X", "A"]);
        after = _delegates(view);
        assertEqual(_shown(view), "C,X,A", "a removal and a reorder at once");
        assert(after[0] === before[3] && after[1] === before[2] && after[2] === before[1], "… each item in its delegate");

        view.list.values = [];
        assertEqual(view.repeater.count, 0, "all gone");
        view.destroy();
    }
}
