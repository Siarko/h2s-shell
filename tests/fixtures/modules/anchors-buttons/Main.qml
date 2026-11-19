import QtQuick

// The fixture's main: its buttons that stand now, by "<name>|<anchor>|<itemId>" (`live`, made
// and gone tell it), and the clicks that reached it, in order (`clicks`)
QtObject {
    id: main

    property var module: null
    property var live: ({})
    property var clicks: []

    function _key(name, context) {
        return name + "|" + (context?.anchor ?? "") + "|" + (context?.itemId ?? "");
    }

    function made(name, context) {
        const counts = Object.assign({}, live);
        const key = _key(name, context);
        counts[key] = (counts[key] ?? 0) + 1;
        live = counts;
    }

    function gone(name, context) {
        const counts = Object.assign({}, live);
        const key = _key(name, context);
        counts[key] = (counts[key] ?? 0) - 1;
        if (counts[key] <= 0)
            delete counts[key];
        live = counts;
    }

    function clicked(name, context) {
        clicks = clicks.concat([_key(name, context)]);
    }
}
