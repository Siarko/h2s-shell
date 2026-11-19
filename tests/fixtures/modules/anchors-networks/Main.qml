import QtQuick

// The fixture's main: a count of its elements that stand now, by
// "<anchor>|<networkId>" (`live`, made and gone tell it) — so the suite sees each element
// follow its network and go with it
QtObject {
    id: main

    property var module: null
    property var live: ({})

    function made(key) {
        const counts = Object.assign({}, live);
        counts[key] = (counts[key] ?? 0) + 1;
        live = counts;
    }

    function gone(key) {
        const counts = Object.assign({}, live);
        counts[key] = (counts[key] ?? 0) - 1;
        if (counts[key] <= 0)
            delete counts[key];
        live = counts;
    }
}
