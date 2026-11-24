import QtQuick
import qs.api
import qs.tests

// The lists inside what the module API hands out, from a module's side: the engine lets a
// frozen list take push and index writes, so each is a new copy at each read. A module that
// changes one changes only the copy it holds: the next read — the one any other module or
// the shell makes — is as before
TestCase {
    id: suite
    suiteName: "good: read-only lists"

    readonly property var module: Api.moduleAt(Qt.resolvedUrl("."))

    // push, an index write and sort on the list `read()` gives; → that list as read again
    function _changed(read) {
        for (const change of [list => list.push("/tmp/made-up"), list => { list[0] = "/tmp/made-up"; }, list => list.sort().reverse()]) {
            try {
                change(read());
            } catch (error) {}
        }
        return JSON.stringify(read());
    }

    // Each list: [description, read] → it changed nothing another reader sees
    function _check(lists) {
        for (const [description, read] of lists) {
            const before = JSON.stringify(read());
            assert(Array.isArray(read()) && read().length > 0, description + ": a list to try");
            assert(read() !== read(), description + ": a new copy at each read");
            assertEqual(_changed(read), before, description + ": push, an index write and sort do not stay");
        }
    }

    function run() {
        ModuleTestKit.setNetworks({ vpnsUp: [{ name: "Office", type: "vpn", fullTunnel: false, setsDns: true, routes: ["10.1.2.3/8", "192.168.5.0/24"] }] });
        const anchor = Api.listAnchors().findIndex(row => row.placements.length > 0);
        _check([
            ["listVpnsUp()'s routes", () => Api.listVpnsUp()[0].routes],
            ["listAnchors()' placements", () => Api.listAnchors()[anchor].placements],
            ["module.manifest's optionalPrograms", () => module.manifest.optionalPrograms],
            ["module.manifest's widgets", () => module.manifest.widgets],
            ["module.manifest's privileged programs", () => module.manifest.privileged.programs]
        ]);
        // Api.system.distribution's facts: GoodApiTest (they need the distribution files read)
        ModuleTestKit.clearRecords();
    }
}
