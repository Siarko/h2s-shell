pragma Singleton

import Quickshell

// Plain data handed to readers that must not change it for one another — pure, tested in
// tests/ReadOnlyRulesTest.qml.
//
// Object.freeze does not protect a list in this engine: a frozen (or sealed, or
// non-extensible) list still takes push(x), list[i] = x on an index it has, and sort(),
// silently, in strict mode too, and stays "frozen" (Object.isFrozen). A frozen object's
// properties are protected. So a list is never kept where two readers reach the same one:
// in an object, a list (or an object, which may hold one) is a getter that returns a new
// copy at each read. A list given to copy() itself is frozen, but shared by whoever holds
// that one value: hand that out only where each reader gets its own (a function's answer).
Singleton {
    // Plain data (what JSON gives: texts, numbers, true/false, null, lists, objects) → the
    // same data, read-only: a text, number, true/false or null as it is; a list a new frozen
    // list of its items, each read-only; an object a new frozen object with the same keys in
    // the same order, a text, number, true/false or null kept as a value, a list or object a
    // getter returning a new read-only copy of it at each read. Anything JSON cannot carry
    // (a function, undefined, a cycle) → null
    function copy(value) {
        let text;
        try {
            text = JSON.stringify(value);
        } catch (error) {
            return null;
        }
        return text === undefined ? null : _shown(JSON.parse(text));
    }

    // `value` came from JSON.parse: nothing else holds it
    function _shown(value) {
        if (value === null || typeof value !== "object")
            return value;
        if (Array.isArray(value))
            return Object.freeze(value.map(item => _shown(item)));
        const shown = {};
        for (const key of Object.keys(value)) {
            const item = value[key];
            if (item === null || typeof item !== "object") {
                // defineProperty: an own "__proto__" key from JSON stays a key
                Object.defineProperty(shown, key, { value: item, enumerable: true });
            } else {
                const text = JSON.stringify(item);
                Object.defineProperty(shown, key, { enumerable: true, get: () => _shown(JSON.parse(text)) });
            }
        }
        return Object.freeze(shown);
    }
}
