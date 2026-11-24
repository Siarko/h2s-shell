import QtQuick
import qs.singletons

// ReadOnlyRules.copy (pure): plain data handed to several readers, none of whom can change
// what another reads — a list inside an object is a new copy at each read, since the engine
// lets a frozen list take push, index writes and sort. A changed list is undone by the next
// read; the source is never reached.
TestCase {
    id: suite
    suiteName: "ReadOnlyRules"

    // Each way the engine lets a frozen list be changed, tried on `read()`'s list; → the list
    // as read again after all of them
    function _tryChanges(read) {
        const changes = [
            list => list.push("pushed"),
            list => { list[0] = "written"; },
            list => list.sort(),
            list => list.unshift("unshifted"),
            list => list.splice(0, 1),
            list => list.reverse(),
            list => list.fill("filled"),
            list => list.pop(),
            list => { list.length = 0; }
        ];
        for (const change of changes) {
            try {
                change(read());
            } catch (error) {}
        }
        return JSON.stringify(read());
    }

    function run() {
        const source = { id: "a", label: "A", count: 2, on: true, none: null, routes: ["10.0.0.0/8", "0.0.0.0/0"],
                         nested: { paths: ["/b", "/a"] }, rows: [{ name: "x", tags: ["t2", "t1"] }] };
        const sourceText = JSON.stringify(source);
        const shown = ReadOnlyRules.copy(source);
        assertEqual(JSON.stringify(shown), sourceText, "copy: the same data, the same keys in the same order");
        assert(Object.isFrozen(shown) && Object.isFrozen(shown.routes) && Object.isFrozen(shown.nested) && Object.isFrozen(shown.nested.paths)
               && Object.isFrozen(shown.rows) && Object.isFrozen(shown.rows[0]) && Object.isFrozen(shown.rows[0].tags), "… frozen all the way down");
        assert(shown !== source && shown.routes !== source.routes, "… never the source's own objects");

        // A list inside an object: a new one at each read, so a change stays in the copy changed
        assert(shown.routes !== shown.routes && shown.nested !== shown.nested, "a list or object inside: a new copy at each read");
        assertEqual(_tryChanges(() => shown.routes), "[\"10.0.0.0/8\",\"0.0.0.0/0\"]", "… push, index writes, sort and the rest: the next read is as it was");
        assertEqual(_tryChanges(() => shown.nested.paths), "[\"/b\",\"/a\"]", "… a list inside an inner object too");
        assertEqual(_tryChanges(() => shown.rows[0].tags), "[\"t2\",\"t1\"]", "… a list inside an object inside a list");
        assertEqual(JSON.stringify(source), sourceText, "… the source unchanged");

        // A frozen object's properties hold
        for (const write of [() => { shown.id = "b"; }, () => { delete shown.label; }, () => { shown.extra = 1; }, () => { shown.routes = []; }]) {
            try {
                write();
            } catch (error) {}
        }
        assertEqual(JSON.stringify(shown), sourceText, "writing, deleting, adding or replacing a property: nothing changes");
        const descriptors = Object.getOwnPropertyNames(shown).map(key => Object.getOwnPropertyDescriptor(shown, key));
        assert(descriptors.every(descriptor => descriptor.set === undefined && !descriptor.writable && !descriptor.configurable),
               "… no setter, nothing writable or configurable");
        assertEqual(Object.keys(shown).filter(key => Object.getOwnPropertyDescriptor(shown, key).get !== undefined).join(","), "routes,nested,rows",
                    "… a getter only for a list or object; a text, number, true/false or null is a value");

        // A list given itself: a new frozen list of read-only items (shared by whoever holds it)
        const rows = ReadOnlyRules.copy([{ name: "x", routes: ["10.0.0.0/8"] }, "text", 3, null, [1, 2]]);
        assertEqual(JSON.stringify(rows), "[{\"name\":\"x\",\"routes\":[\"10.0.0.0/8\"]},\"text\",3,null,[1,2]]", "a list: the same items");
        assert(Array.isArray(rows) && Object.isFrozen(rows) && Object.isFrozen(rows[0]) && rows[0].routes !== rows[0].routes,
               "… frozen, each object read-only, its lists a new copy at each read");
        assertEqual(_tryChanges(() => rows[0].routes), "[\"10.0.0.0/8\"]", "… an item's list: changes do not stay");

        // JSON's own "__proto__" key stays a key; the prototype is untouched
        const odd = ReadOnlyRules.copy(JSON.parse("{\"__proto__\":{\"polluted\":true},\"plain\":\"__proto__\"}"));
        assert(Object.keys(odd).includes("__proto__") && odd.polluted === undefined && Object.getPrototypeOf(odd) === Object.prototype
               && ({}).polluted === undefined, "a \"__proto__\" key: kept as a key, no prototype set");
        const oddText = ReadOnlyRules.copy(JSON.parse("{\"__proto__\":\"x\"}"));
        assertEqual(Object.getOwnPropertyDescriptor(oddText, "__proto__")?.value, "x", "… with a text value too");

        // What JSON cannot carry
        assertEqual(ReadOnlyRules.copy(undefined), null, "undefined → null");
        assertEqual(ReadOnlyRules.copy(() => 1), null, "a function → null");
        const cycle = {};
        cycle.self = cycle;
        assertEqual(ReadOnlyRules.copy(cycle), null, "a cycle → null");
        assertEqual(JSON.stringify(ReadOnlyRules.copy({ f: () => 1, u: undefined, n: 1 })), "{\"n\":1}", "a function or undefined inside: left out, as JSON does");
        assertEqual([ReadOnlyRules.copy("t"), ReadOnlyRules.copy(5), ReadOnlyRules.copy(false), ReadOnlyRules.copy(null)].join("|"), "t|5|false|",
                    "a text, number, true/false or null: itself");
    }
}
