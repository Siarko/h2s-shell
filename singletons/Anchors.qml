pragma Singleton

import Quickshell
import QtQuick

// The anchor blocks standing now (components/AnchorBlock.qml), by path: { path: how many }.
// Each addressable block adds itself when it is built or its path changes, and goes when it
// is destroyed. Nothing in the running shell reads it: tests/AnchorsTest.qml compares it with
// ModuleRules.anchorTable, so a view that stops building a published place is caught. Plain:
// no other singleton, nothing of the module system.
Singleton {
    // A new object on each change, so a binding follows it
    property var live: ({})

    function add(path) {
        if (typeof path !== "string" || path === "")
            return;
        const next = Object.assign({}, live);
        next[path] = (next[path] ?? 0) + 1;
        live = next;
    }

    function remove(path) {
        if (typeof path !== "string" || !Object.prototype.hasOwnProperty.call(live, path))
            return;
        const next = Object.assign({}, live);
        if (next[path] > 1)
            next[path] -= 1;
        else
            delete next[path];
        live = next;
    }
}
