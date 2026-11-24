import QtQuick
import Quickshell
import qs.api
import qs.singletons
import qs.singletons.network

// The module API's lists (api/Api.qml, "Lists"): each list function returns a new copy at
// each call, the caller's own — a push, an index write, a sort or a write into a row on one
// copy reaches neither the next call nor the shared property — and a binding calling one is
// evaluated again on a real change of its list, not on a re-read that found the same. The
// network singletons hold stand-in rows meanwhile (written, all in one synchronous run, so
// no reading of the real system lands between a change and its check); a stand-in VPN
// provider gives the VPN up.
TestCase {
    id: suite
    suiteName: "ApiLists"
    // It writes NetworkProfiles', IpManager's and VpnManager's state, which other suites read
    ownProcess: true

    // name: the function; property: the shared list it copies; nested: a list inside a row
    readonly property var _lists: [
        { name: "listSlots", property: "slots", nested: "" },
        { name: "listAnchors", property: "anchors", nested: "placements" },
        { name: "listNetworks", property: "networks", nested: "" },
        { name: "listVpnsUp", property: "vpnsUp", nested: "routes" },
        { name: "listLocalNetworks", property: "localNetworks", nested: "" }
    ]

    function _profile(uuid, name) {
        return { uuid: uuid, name: name, type: "802-3-ethernet", kind: "ethernet", autoconnect: true, priority: 0,
                 lastUsed: 1, active: false, port: "", device: "", state: "" };
    }

    function _entry(id, name, routes) {
        return { id: id, name: name, state: "activated", attention: null, fullTunnel: false, setsDns: false, routes: routes,
                 detail: { server: "relay.example.net", iface: "", addresses: [], dns: [] } };
    }

    function _device(name, addresses) {
        return { device: name, type: "ethernet", ipIface: "", ipv4: addresses, ipv6: [] };
    }

    property Component _providerComponent: Component {
        FakeVpnProvider {
            providerId: "apilists"
        }
    }

    // Calls each function in bindings, counting the evaluations after the first
    property Component _watcherComponent: Component {
        QtObject {
            property var slots: Api.listSlots()
            property var anchors: Api.listAnchors()
            property var networks: Api.listNetworks()
            property var vpnsUp: Api.listVpnsUp()
            property var localNetworks: Api.listLocalNetworks()
            property var runs: ({ slots: 0, anchors: 0, networks: 0, vpnsUp: 0, localNetworks: 0 })
            function _ran(key) {
                const next = Object.assign({}, runs);
                next[key]++;
                runs = next;
            }
            onSlotsChanged: _ran("slots")
            onAnchorsChanged: _ran("anchors")
            onNetworksChanged: _ran("networks")
            onVpnsUpChanged: _ran("vpnsUp")
            onLocalNetworksChanged: _ran("localNetworks")
        }
    }

    // A view of the networks the way a module builds one: a ScriptModel of keys from the call
    property Component _viewComponent: Component {
        Item {
            readonly property alias count: repeater.count
            ScriptModel {
                id: keys
                values: Api.listNetworks().map(network => network.id)
            }
            Repeater {
                id: repeater
                model: keys
                delegate: Item {}
            }
        }
    }

    // Each function: a new list at each call, the caller's to change, nothing of it shared
    function _copies() {
        for (const list of _lists) {
            try {
                _copy(list);
            } catch (error) {
                fail(list.name + ": threw: " + error);
            }
        }
    }

    function _copy(list) {
        const shared = JSON.stringify(Api[list.property]);
        const first = Api[list.name]();
        const second = Api[list.name]();
        assert(Array.isArray(first) && first.length > 0, list.name + ": a list, with the stand-in rows");
        assertEqual(JSON.stringify(first), shared, list.name + ": the rows of Api." + list.property);
        assert(first !== second, list.name + ": two calls, two lists");
        assert(first[0] !== second[0], list.name + ": … and two rows");
        assert(!Object.isFrozen(first) && !Object.isFrozen(first[0]), list.name + ": not frozen, the caller's");
        if (list.nested !== "") {
            assert(Array.isArray(first[0][list.nested]) && first[0][list.nested] !== second[0][list.nested],
                   list.name + ": the " + list.nested + " in a row, a new list at each call");
            assert(first[0][list.nested] === first[0][list.nested], list.name + ": … plain inside the copy (one list per read)");
        }
        // Each write on its own: one the engine refuses (a frozen row, in strict mode)
        // must not keep the others from being tried
        const writes = [() => first[0][list.nested].push("made-up"), () => { first[0].madeUp = true; },
                        () => first.push({ name: "made-up" }), () => first.reverse(),
                        () => first.sort((a, b) => String(b.name).localeCompare(String(a.name))), () => { first[0] = "changed"; }];
        for (const write of list.nested === "" ? writes.slice(1) : writes) {
            try {
                write();
            } catch (error) {}
        }
        assertEqual(first.length, second.length + 1, list.name + ": a push sticks in the caller's own copy");
        assertEqual(JSON.stringify(Api[list.name]()), shared, list.name + ": a push, a sort, an index write and writes into a row — not in the next call");
        assertEqual(JSON.stringify(second), shared, list.name + ": … nor in a copy taken before");
        assertEqual(JSON.stringify(Api[list.property]), shared, list.name + ": … nor in Api." + list.property);
    }

    // The evaluations since `base`, by binding
    function _since(watcher, base) {
        const runs = {};
        for (const key of Object.keys(watcher.runs))
            runs[key] = watcher.runs[key] - base[key];
        return JSON.stringify(runs);
    }

    // Bindings calling the functions: evaluated again on a real change of their list only
    function _bindings(provider) {
        const watcher = _watcherComponent.createObject(suite);
        const view = _viewComponent.createObject(suite);
        // Counted from here: what the property's first value signalled is not a re-evaluation
        const base = Object.assign({}, watcher.runs);
        assertEqual(JSON.stringify([watcher.networks.length, watcher.vpnsUp.length, watcher.localNetworks.length, view.count]), "[2,1,1,2]",
                    "bindings and a view on the calls: the stand-in rows");

        // A real change of the networks: one evaluation of that binding, none of the others
        NetworkProfiles.profiles = [_profile("apilists-a", "A"), _profile("apilists-b", "B"), _profile("apilists-c", "C")];
        assertEqual(_since(watcher, base), JSON.stringify({ slots: 0, anchors: 0, networks: 1, vpnsUp: 0, localNetworks: 0 }),
                    "a network added: the networks' binding evaluated once, no other");
        assertEqual(watcher.networks.length, 3, "… with the new list");
        assertEqual(view.count, 3, "a Repeater over a ScriptModel of the call's keys follows it");

        // The same networks read again (new objects, the same content): nothing evaluated
        NetworkProfiles.profiles = JSON.parse(JSON.stringify(NetworkProfiles.profiles));
        NetworkProfiles.wifi = ({});
        assertEqual(watcher.runs.networks - base.networks, 1, "the profiles read again, unchanged: the networks' binding not evaluated");

        // A VPN comes up: the VPNs' binding only (the local networks are recomputed — the
        // VPNs' interfaces count there — but come out the same)
        provider.entries = [_entry("one", "One", ["10.8.0.0/24"]), _entry("two", "Two", ["10.9.0.0/24"])];
        assertEqual(_since(watcher, base), JSON.stringify({ slots: 0, anchors: 0, networks: 1, vpnsUp: 1, localNetworks: 0 }),
                    "a VPN up: the VPNs' binding evaluated once, no other");
        assertEqual(watcher.vpnsUp.length, 2, "… with the new list");
        provider.entries = JSON.parse(JSON.stringify(provider.entries));
        assertEqual(watcher.runs.vpnsUp - base.vpnsUp, 1, "the entries reported again, unchanged: not evaluated");

        // An address added: the local networks' binding only
        IpManager._reading.devices = [_device("eth-apilists", ["10.1.2.3/24", "10.1.3.4/24"])];
        assertEqual(_since(watcher, base), JSON.stringify({ slots: 0, anchors: 0, networks: 1, vpnsUp: 1, localNetworks: 1 }),
                    "an address added: the local networks' binding evaluated once, no other");
        assertEqual(watcher.localNetworks.length, 2, "… with the new list");
        IpManager._reading.devices = JSON.parse(JSON.stringify(IpManager._reading.devices));
        assertEqual(watcher.runs.localNetworks - base.localNetworks, 1, "the devices read again, unchanged: not evaluated");

        // A change made in one binding's copy is that binding's alone
        watcher.networks.push({ id: "made-up" });
        assertEqual(Api.listNetworks().length, 3, "a push on a bound copy: not in the next call");

        view.destroy();
        watcher.destroy();
    }

    function run() {
        const held = {
            profiles: NetworkProfiles.profiles, wifi: NetworkProfiles.wifi, listRead: NetworkProfiles.listRead,
            devices: IpManager._reading.devices, devicesRead: IpManager._reading.devicesRead
        };
        NetworkProfiles.listRead = true;
        NetworkProfiles.wifi = ({});
        NetworkProfiles.profiles = [_profile("apilists-a", "A"), _profile("apilists-b", "B")];
        IpManager._reading.devicesRead = true;
        IpManager._reading.devices = [_device("eth-apilists", ["10.1.2.3/24"])];
        const provider = _providerComponent.createObject(suite);
        provider.entries = [_entry("one", "One", ["10.8.0.0/24"])];
        try {
            _copies();
            _bindings(provider);
        } catch (error) {
            fail("threw: " + error);
        }
        provider.destroy();
        NetworkProfiles.profiles = held.profiles;
        NetworkProfiles.wifi = held.wifi;
        NetworkProfiles.listRead = held.listRead;
        IpManager._reading.devices = held.devices;
        IpManager._reading.devicesRead = held.devicesRead;
    }
}
