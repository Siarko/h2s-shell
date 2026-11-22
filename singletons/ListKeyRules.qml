pragma Singleton

import Quickshell
import QtQuick

// A list of JS objects as a list of string keys and a map from key to object — what
// components/KeyedModel.qml gives a Repeater. Pure, so tests/ListKeyRulesTest.qml checks
// every case.
//
// Why keys: Quickshell's ScriptModel (0.3.2) diffs its values by identity. Strings compare
// strictly equal, so inserts, removals and moves of keys go to the right rows. Objects that
// are built anew on each read (a refetch, a rescan, a re-sort) do not: with `objectProp` or
// the default structural comparison it overwrites rows by position after the first changed
// one, so a delegate ends up showing — and acting on — another item. The delegate looks its
// item up by key instead.
Singleton {
    id: root

    // The key of `value`: its `keyProp` property, or `keyFunction(value)` when a function is
    // given, else the value itself; null and undefined become "" (made unique like any repeat)
    function keyOf(value, keyProp, keyFunction): string {
        const key = typeof keyFunction === "function" ? keyFunction(value)
            : (value !== null && typeof value === "object" && keyProp) ? value[keyProp]
            : value;
        return key === null || key === undefined ? "" : String(key);
    }

    // `values` (a list or array-like; anything else is empty) → { keys: [string], byKey:
    // { key: value } }, keys in the list's order. A key seen again is made unique by its count ("a", "a#2",
    // "a#3"): ScriptModel takes each key once, and both items still show. byKey has no
    // prototype, so a key like "constructor" finds only an item.
    function keyed(values, keyProp, keyFunction): var {
        const list = Array.isArray(values) ? values
            : (values !== null && typeof values === "object" && typeof values.length === "number") ? Array.prototype.slice.call(values) : [];
        const keys = [];
        const byKey = Object.create(null);
        const seen = Object.create(null);
        for (const value of list) {
            const base = root.keyOf(value, keyProp, keyFunction);
            seen[base] = (seen[base] ?? 0) + 1;
            let key = seen[base] === 1 ? base : base + "#" + seen[base];
            // "a#2" may be a real key too: count on until the key is free
            while (key in byKey)
                key = base + "#" + (++seen[base]);
            keys.push(key);
            byKey[key] = value;
        }
        return { keys: keys, byKey: byKey };
    }

    // Both maps in one, `newer` winning: what delegates read while the rows change, so that
    // a row going and a row coming both find their item
    function union(older, newer): var {
        const merged = Object.create(null);
        for (const key in (older ?? {}))
            merged[key] = older[key];
        for (const key in (newer ?? {}))
            merged[key] = newer[key];
        return merged;
    }
}
