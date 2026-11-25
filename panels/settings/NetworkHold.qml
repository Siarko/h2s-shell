import QtQuick
import qs.singletons.network

// A network settings page's hold on what reads the system while it is on screen:
// NetworkOverview's watch, and with `scans` WifiManager's scans too. Held while `wanted`,
// let go when that turns false and when this goes.
//
//   NetworkHold { wanted: _onScreen.shown; scans: true }
//
// What is held is kept in a JavaScript object the destruction's closure holds: Qt may drop
// this object's properties and functions before its destruction runs, and the hold must
// still be let go then.
QtObject {
    id: root

    property bool wanted: false
    property bool scans: false

    readonly property var _held: ({ watch: false, scans: false })
    onWantedChanged: _apply?.(wanted, scans)
    onScansChanged: _apply?.(wanted, scans)
    // Set once built: the hold's one way in, which the destruction's closure also takes
    property var _apply: null

    Component.onCompleted: {
        const held = _held;
        const apply = (on, scans) => {
            if (on && !held.watch) {
                held.watch = true;
                NetworkOverview.watch();
            } else if (!on && held.watch) {
                held.watch = false;
                NetworkOverview.unwatch();
            }
            const scanning = on && scans;
            if (scanning && !held.scans) {
                held.scans = true;
                WifiManager.holdScan();
            } else if (!scanning && held.scans) {
                held.scans = false;
                WifiManager.releaseScan();
            }
        };
        _apply = apply;
        Component.destruction.connect(() => apply(false, false));
        apply(wanted, scans);
    }
}
