import QtQuick

// The fixture's main: a count of its Title elements that stand now, by
// "<anchor>|<networkId>|<name>" (`live`, made and gone tell it) — so the suite sees each
// element follow its row and go with it — and the clicks its Clicker elements took, by the
// row's SSID (`clicks`)
QtObject {
    property var module: null
    property var live: ({})
    property var clicks: ({})

    function clicked(ssid) {
        const counts = Object.assign({}, clicks);
        counts[ssid] = (counts[ssid] ?? 0) + 1;
        clicks = counts;
    }

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
