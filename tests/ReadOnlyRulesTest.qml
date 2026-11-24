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

        // Through a Loader's initial properties, as a module's element gets its context
        // (components/ModuleContribution.qml): the rows and the lists inside them arrive
        const context = { otherVpns: ReadOnlyRules.copy([{ name: "Office", routes: ["10.0.0.0/8", "0.0.0.0/0"] }]) };
        const loader = Qt.createQmlObject("import QtQuick\nLoader {}", suite, "ReadOnlyLoader.qml");
        loader.setSource(Qt.resolvedUrl("fixtures/modules/anchors-vpn-a/Row.qml"), { context: context });
        const given = loader.item?.context?.otherVpns ?? null;
        assertEqual(JSON.stringify(given), "[{\"name\":\"Office\",\"routes\":[\"10.0.0.0/8\",\"0.0.0.0/0\"]}]",
                    "through Loader.setSource's initial properties: the rows and their lists arrive");
        assert(Array.isArray(given) && Array.isArray(given?.[0]?.routes) && given[0].routes.includes("0.0.0.0/0"), "… as lists, as a module reads them");
        assertEqual(_tryChanges(() => loader.item.context.otherVpns[0].routes), "[\"10.0.0.0/8\",\"0.0.0.0/0\"]",
                    "… and a change to the element's list does not stay at the next read");
        assertEqual(JSON.stringify(context.otherVpns[0].routes), "[\"10.0.0.0/8\",\"0.0.0.0/0\"]", "… nor in the context given");
        loader.destroy();

        // context(): an element's context — its lists a new copy at each read, the rest as it is
        const live = Qt.createQmlObject("import QtQuick\nQtObject { property int calls: 0 }", suite, "ReadOnlyLive.qml");
        const close = () => 1;
        const vpn = { uuid: "vpt:office", name: "Office", active: true, status: undefined, attention: { reason: "r", action: "" }, routes: ["10.0.0.0/8"] };
        const vpnText = JSON.stringify(vpn);
        const withLive = { name: "x", act: close, routes: ["10.0.0.0/8"] };
        const liveList = [live, "text"];
        const givenContext = { anchor: "a.b", otherVpnsUp: ["Work", "Home"], otherVpns: ReadOnlyRules.copy([{ name: "Work", routes: ["10.0.0.0/8"] }]),
                        provider: live, close: close, vpn: vpn, withLive: withLive, liveList: liveList, count: 2, open: true, none: null };
        const givenText = JSON.stringify([givenContext.otherVpnsUp, givenContext.otherVpns]);
        const shownContext = ReadOnlyRules.context(givenContext);
        assertEqual(Object.keys(shownContext).join(","), Object.keys(givenContext).join(","), "context: the same keys in the same order");
        assert(Object.isFrozen(shownContext) && shownContext !== givenContext, "… a new frozen object");
        assert(shownContext.otherVpnsUp !== shownContext.otherVpnsUp && shownContext.otherVpnsUp !== givenContext.otherVpnsUp
               && shownContext.otherVpns !== givenContext.otherVpns, "… a list in it a new copy at each read, never the one given");
        assert(Array.isArray(shownContext.otherVpnsUp) && Object.isFrozen(shownContext.otherVpns) && shownContext.otherVpns[0].routes !== shownContext.otherVpns[0].routes,
               "… a list, read-only, a row's lists a new copy at each read too");
        assertEqual(_tryChanges(() => shownContext.otherVpnsUp), "[\"Work\",\"Home\"]", "… push, index writes, sort: the next read is as it was");
        assertEqual(_tryChanges(() => shownContext.otherVpns), "[{\"name\":\"Work\",\"routes\":[\"10.0.0.0/8\"]}]", "… a list of rows too");
        assertEqual(JSON.stringify([givenContext.otherVpnsUp, givenContext.otherVpns]), givenText, "… the lists given unchanged");
        assert(shownContext.provider === live && shownContext.close === close
               && shownContext.anchor === "a.b" && shownContext.count === 2 && shownContext.open === true && shownContext.none === null,
               "… anything else as it is: a live object, a function, a text, number, true/false, null");
        // An object of plain data (a VPN's row): a new read-only copy at each read, its lists too
        assert(shownContext.vpn !== vpn && shownContext.vpn !== shownContext.vpn && Object.isFrozen(shownContext.vpn)
               && JSON.stringify(shownContext.vpn) === vpnText, "… an object of plain data: a new frozen copy at each read, the same data");
        for (const write of [() => { shownContext.vpn.active = false; }, () => { shownContext.vpn.name = "Evil"; }, () => { shownContext.vpn.extra = 1; }]) {
            try {
                write();
            } catch (error) {}
        }
        assertEqual(_tryChanges(() => shownContext.vpn.routes), "[\"10.0.0.0/8\"]", "… its lists: push, index writes, sort do not stay");
        assertEqual(JSON.stringify(shownContext.vpn) + " " + JSON.stringify(vpn), vpnText + " " + vpnText, "… a write into it stays neither in it nor in the row given");
        // A list or {} object holding a function or a live object: never handed out itself —
        // a copy of what JSON carries at each read, named among the lossy keys (warned of once)
        assertEqual(ReadOnlyRules.lossyContextKeys(givenContext).join(","), "withLive,liveList", "lossyContextKeys: the list and the object holding a live thing");
        assertEqual(ReadOnlyRules.lossyContextKeys({ vpn: vpn, provider: live, close: close, list: ["a"] }).length, 0, "… none for plain data, a live object or a function");
        const lossyObject = shownContext.withLive;
        assert(lossyObject !== withLive && lossyObject !== shownContext.withLive && Object.isFrozen(lossyObject) && lossyObject.act === undefined
               && JSON.stringify(lossyObject) === "{\"name\":\"x\",\"routes\":[\"10.0.0.0/8\"]}", "… an object holding a function: a frozen copy without it, new at each read");
        try {
            lossyObject.routes.push("Evil");
        } catch (error) {}
        assert(shownContext.withLive.routes.length === 1 && withLive.routes.length === 1 && withLive.act === close, "… a push into it: not at the next read, nor in the object given");
        const liveShown = shownContext.liveList;
        assert(liveShown !== shownContext.liveList && liveShown !== liveList && Object.isFrozen(liveShown) && liveShown[0] !== live && liveShown[1] === "text",
               "… a list holding a live object: a frozen copy at each read, the live object not in it");
        try {
            liveShown.push("Evil");
        } catch (error) {}
        assert(shownContext.liveList.length === 2 && liveList.length === 2 && liveList[0] === live, "… a push into one: not at the next read, nor in the list given");
        for (const write of [() => { shownContext.anchor = "x"; }, () => { shownContext.otherVpnsUp = []; }, () => { shownContext.extra = 1; }]) {
            try {
                write();
            } catch (error) {}
        }
        assert(shownContext.anchor === "a.b" && shownContext.otherVpnsUp.length === 2 && !("extra" in shownContext), "… its keys hold");
        const other = ReadOnlyRules.context(givenContext);
        try {
            other.otherVpnsUp.push("Evil");
        } catch (error) {}
        assert(other.otherVpnsUp.length === 2 && shownContext.otherVpnsUp.length === 2, "two contexts made of one: neither sees a change to the other's list");
        assert(ReadOnlyRules.context(null) === null && ReadOnlyRules.context("t") === "t" && ReadOnlyRules.context(givenContext.otherVpnsUp) === givenContext.otherVpnsUp,
               "context: null, a text or a list → itself");
        live.destroy();

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
