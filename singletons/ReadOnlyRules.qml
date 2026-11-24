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

    // An object of plain data beside live things — what a module's element gets as `context`
    // (a provider's object, a close function, the VPN's row and lists) → a new frozen object
    // with the same keys in the same order, so the elements at one place, and the view that
    // gave it, never share a value one of them could change:
    //   - plain data (a list, or an object made of {} and lists, texts, finite numbers,
    //     true/false and null all the way down): a getter that returns a new read-only copy
    //     (copy's) at each read;
    //   - a list or {} object holding anything else (a function, a live object): the same, a
    //     copy of what JSON carries (the rest left out; null when JSON cannot carry it at
    //     all), and a warning in the log, once per key — never the value itself;
    //   - anything else (a live object, a function, a text, number, true/false, null): as it is.
    // Not an object (or a list) → itself
    function context(value) {
        if (value === null || typeof value !== "object" || Array.isArray(value))
            return value;
        const shown = {};
        const lossy = lossyContextKeys(value);
        for (const key of Object.keys(value)) {
            const item = value[key];
            if (_dataShaped(item)) {
                if (lossy.includes(key) && !_warnedKeys.includes(key)) {
                    _warnedKeys = _warnedKeys.concat([key]);
                    console.warn("[ReadOnlyRules] a context's " + JSON.stringify(key)
                                 + " holds what JSON cannot carry (a function or a live object): handed out as a copy without it");
                }
                let text = null;
                try {
                    text = JSON.stringify(item) ?? null;
                } catch (error) {}
                Object.defineProperty(shown, key, { enumerable: true, get: () => text === null ? null : _shown(JSON.parse(text)) });
            } else {
                Object.defineProperty(shown, key, { enumerable: true, value: item });
            }
        }
        return Object.freeze(shown);
    }

    // The keys of a context (context()) whose list or {} object holds what JSON cannot carry
    // whole: handed out as a lossy copy
    function lossyContextKeys(value) {
        if (value === null || typeof value !== "object" || Array.isArray(value))
            return [];
        return Object.keys(value).filter(key => _dataShaped(value[key]) && !_plainData(value[key], 0));
    }

    // The keys warned of once (context())
    property var _warnedKeys: []

    // A list, or an object made directly of {} (not a live object: a QObject reads as one)
    function _dataShaped(value) {
        return value !== null && typeof value === "object" && !Qt.isQtObject(value)
            && (Array.isArray(value) || Object.getPrototypeOf(value) === Object.prototype);
    }

    // Data JSON carries as it is: texts, finite numbers, true/false, null, and lists and
    // objects made directly of {} (no class, no QObject) holding only such data (undefined in
    // an object, which JSON leaves out, reads the same). A cycle or a deep nesting is not
    function _plainData(value, depth) {
        if (depth > 64)
            return false;
        if (value === null || typeof value === "string" || typeof value === "boolean")
            return true;
        if (typeof value === "number")
            return Number.isFinite(value);
        if (typeof value !== "object")
            return false;
        if (Array.isArray(value))
            return value.every(item => _plainData(item, depth + 1));
        // A QObject reads as an object of {} here: it is live, never data
        if (Qt.isQtObject(value) || Object.getPrototypeOf(value) !== Object.prototype)
            return false;
        return Object.keys(value).every(key => value[key] === undefined || _plainData(value[key], depth + 1));
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
