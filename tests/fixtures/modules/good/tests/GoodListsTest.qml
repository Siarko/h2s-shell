import QtQuick
import qs.api
import qs.tests

// The module API's lists from a module's side (API 1.42): reader A changes the list a
// list…() call gave it — push, an index write, sort — and reader B sees the rows as given:
// through a second call, through a property bound to the call in another object, and
// through the old property every module shares. A binding on the call follows the rows
TestCase {
    id: suite
    suiteName: "good: lists"

    // Each list function, and the old property it replaces: read by name, as the shell-wide
    // value a change would reach — what is checked, not a use of it
    readonly property var _lists: [["listNetworks", "networks"], ["listLocalNetworks", "localNetworks"], ["listVpnsUp", "vpnsUp"],
                                   ["listSlots", "slots"], ["listAnchors", "anchors"]]

    // Reader B's bindings, in an object of its own
    readonly property QtObject readerB: QtObject {
        property var listNetworks: Api.listNetworks()
        property var listLocalNetworks: Api.listLocalNetworks()
        property var listVpnsUp: Api.listVpnsUp()
        property var listSlots: Api.listSlots()
        property var listAnchors: Api.listAnchors()
    }

    // What reader A does to the list it holds. Sort orders the rows by their text, the other
    // way round if that order is the one they have, so that it moves them
    readonly property var _changes: [
        ["push", list => list.push({ name: "made-up" })],
        ["an index write", list => { list[0] = { name: "made-up" }; }],
        ["sort", list => {
            const before = JSON.stringify(list);
            const text = row => JSON.stringify(row);
            list.sort((a, b) => text(b).localeCompare(text(a)));
            if (JSON.stringify(list) === before)
                list.sort((a, b) => text(a).localeCompare(text(b)));
        }]
    ]

    function run() {
        assertEqual(JSON.stringify(ModuleTestKit.setNetworks({
            networks: [{ id: "u-home", name: "Home", kind: "wifi", active: true },
                       { id: "u-work", name: "Work", kind: "ethernet", active: false }],
            localNetworks: [{ device: "wlan0", kind: "wifi", address: "192.168.1.23/24" },
                            { device: "wlan0", kind: "wifi", address: "2001:db8::17/64" }],
            vpnsUp: [{ name: "Office", type: "vpn", fullTunnel: false, setsDns: true, routes: ["10.1.2.3/8"] },
                     { name: "Mesh", type: "provider", provider: "mesh" }]
        })), "[]", "setNetworks: two rows in each network list");

        const given = {};
        for (const [name, old] of _lists) {
            given[name] = JSON.stringify(Api[name]());
            assert(Api[name]().length >= 2 && given[name] === JSON.stringify(Api[old]), name + "(): rows to change, the old Api." + old + "'s");
            assertEqual(JSON.stringify(readerB[name]), given[name], name + "(): reader B's bound property has them");
            for (const [change, apply] of _changes) {
                const mine = Api[name]();
                try {
                    apply(mine);
                } catch (error) {
                    assert(false, name + "(), " + change + ": reader A's change ran — " + error);
                }
                assert(JSON.stringify(mine) !== given[name], name + "(), " + change + ": reader A's list changed");
                assertEqual(JSON.stringify(Api[name]()), given[name], name + "(), " + change + ": not in a second call");
                assertEqual(JSON.stringify(readerB[name]), given[name], name + "(), " + change + ": not in reader B's bound property");
                assertEqual(JSON.stringify(Api[old]), given[name], name + "(), " + change + ": not in Api." + old);
            }
        }

        // The rows change: reader B's bindings on the network lists follow, the tables stay
        ModuleTestKit.setNetworks({
            networks: [{ id: "u-cafe", name: "Cafe", kind: "wifi", active: true }],
            localNetworks: [{ device: "eth0", kind: "ethernet", address: "10.0.0.5/24" }],
            vpnsUp: [{ name: "Home VPN", type: "vpn", fullTunnel: true, setsDns: false, routes: [] }]
        });
        for (const [name, old] of _lists.slice(0, 3)) {
            assert(JSON.stringify(readerB[name]) !== given[name] && Api[name]().length === 1, name + "(): new rows after setNetworks");
            assertEqual(JSON.stringify(readerB[name]), JSON.stringify(Api[name]()), name + "(): reader B's bound property follows");
        }
        for (const [name, old] of _lists.slice(3))
            assertEqual(JSON.stringify(readerB[name]), given[name], name + "(): reader B's bound property as before");
        ModuleTestKit.clearRecords();
        assertEqual([readerB.listNetworks.length, readerB.listLocalNetworks.length, readerB.listVpnsUp.length].join(" "), "0 0 0",
                    "clearRecords(): reader B's bound properties follow to none");
    }
}
