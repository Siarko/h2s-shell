import QtQuick
import qs.singletons
import qs.singletons.network

// The views whose lists are keyed (components/KeyedModel.qml), with new objects at every
// read as their sources give them: a delegate stays with its item through inserts, removals
// and reorders, shows that item's current data, and keeps its own state (what is typed).
// The sources are the singletons' plain properties, set here and put back after; nothing
// reaches NetworkManager.
TestCase {
    id: suite
    suiteName: "KeyedViews"

    function _find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        const children = item.children ?? [];
        for (let i = 0; i < children.length; i++) {
            const found = _find(children[i], name);
            if (found)
                return found;
        }
        return null;
    }

    function _findAll(item, name, into) {
        const list = into ?? [];
        if (!item)
            return list;
        if (item.objectName === name)
            list.push(item);
        const children = item.children ?? [];
        for (let i = 0; i < children.length; i++)
            _findAll(children[i], name, list);
        return list;
    }

    function _create(file, properties) {
        const component = Qt.createComponent(Qt.resolvedUrl(file), Component.PreferSynchronous);
        if (component.status !== Component.Ready) {
            fail(file + " did not load: " + component.errorString());
            return null;
        }
        return component.createObject(suite, properties ?? {});
    }

    // --- Settings → Wi-Fi: the saved networks ---
    function _wifiProfiles(names, active) {
        return names.map((name, index) => ({
            uuid: "uuid-" + name, name: name, type: "802-11-wireless", kind: "wifi", autoconnect: true,
            priority: 0, lastUsed: 100 - index, active: name === active, port: "", device: name === active ? "wlan0" : ""
        }));
    }

    function _wifiDetails(names) {
        const details = {};
        for (const name of names)
            details["uuid-" + name] = { ssid: name, security: "wpa-psk", hidden: false, mode: "infrastructure" };
        return details;
    }

    function _savedCards(page) {
        const cards = {};
        for (const card of _findAll(page, "savedNetwork"))
            cards[card.network.uuid] = card;
        return cards;
    }

    // The singletons' lists as they were before a check, put back after it however it ends
    // (a check that stops early, or throws, included): later suites see them untouched
    function _withSources(check) {
        const savedProfiles = NetworkProfiles.profiles;
        const savedWifi = NetworkProfiles.wifi;
        const savedNetworks = WifiManager.wifiNetworks;
        let view = null;
        try {
            check(created => view = created);
        } finally {
            if (view)
                view.destroy();
            NetworkProfiles.profiles = savedProfiles;
            NetworkProfiles.wifi = savedWifi;
            WifiManager.wifiNetworks = savedNetworks;
        }
    }

    function _savedNetworks(keep) {
        const names = ["Home", "Cafe", "Office"];
        NetworkProfiles.wifi = _wifiDetails(names);
        NetworkProfiles.profiles = _wifiProfiles(names, "");
        const page = keep(_create("../panels/settings/NetworkWifiSettings.qml"));
        if (!page)
            return;
        const before = _savedCards(page);
        assertEqual(Object.keys(before).length, 3, "Wi-Fi: a card per saved network");
        const office = before["uuid-Office"];
        const officePassword = _find(office, "wifiPassword");
        officePassword.text = "typed for office";

        // Cafe forgotten elsewhere: a new read, new objects
        NetworkProfiles.profiles = _wifiProfiles(["Home", "Office"], "");
        let after = _savedCards(page);
        assert(Object.keys(after).length === 2 && after["uuid-Home"] === before["uuid-Home"] && after["uuid-Office"] === office,
               "Wi-Fi: a network before it removed — Office keeps its card");
        assert(office.network.ssid === "Office" && office.title.startsWith("Office"), "… which shows Office");
        assertEqual(officePassword.text, "typed for office", "… with the password typed into it");

        // Office connects: it goes to the top, with new data
        NetworkProfiles.profiles = _wifiProfiles(["Home", "Office"], "Office");
        after = _savedCards(page);
        assert(after["uuid-Office"] === office && office.network.active === true && office.subtitle.startsWith("Connected"),
               "Wi-Fi: a network that connects moves to the top in its card, shown connected (not a stale \"not active\")");
        assertEqual(officePassword.text, "typed for office", "… still with its typed password");
        assert(!after["uuid-Home"].subtitle.startsWith("Connected") && _find(after["uuid-Home"], "wifiPassword").text === "",
               "… and Home's card shows Home, with nothing typed");

        // A new network saved before the others
        NetworkProfiles.wifi = _wifiDetails(["Home", "Office", "Airport"]);
        NetworkProfiles.profiles = _wifiProfiles(["Airport", "Home", "Office"], "Office");
        after = _savedCards(page);
        assert(after["uuid-Office"] === office && after["uuid-Airport"] !== undefined && _find(after["uuid-Airport"], "wifiPassword").text === "",
               "Wi-Fi: one added — a new card for it, Office's kept");

        // Enter in a card's password field: what Save does, only while Save can be pressed.
        // The writes go to a stand-in, never to NetworkManager
        const writes = [];
        page.profiles = { busy: false, setWifiPassword: (uuid, password, done) => writes.push(uuid + "=" + password) };
        const save = _find(office, "wifiPasswordSave");
        officePassword.text = "";
        officePassword.input.accepted();
        assert(!save.available && writes.length === 0, "Wi-Fi: Enter in an empty password field saves nothing (Save is not available)");
        officePassword.text = "short";
        officePassword.input.accepted();
        assert(!save.available && writes.length === 0, "… nor with a password NetworkManager would refuse");
        officePassword.text = "a long enough secret";
        assert(save.available, "… a good one makes Save available");
        officePassword.input.accepted();
        assertEqual(writes.join(" "), "uuid-Office=a long enough secret", "… and Enter saves it, as Save does");
        page.profiles = { busy: true, setWifiPassword: (uuid, password, done) => writes.push(uuid + "=" + password) };
        officePassword.input.accepted();
        assert(!save.available && writes.length === 1, "… not while the profiles are busy");
        page.profiles = NetworkProfiles;
        officePassword.text = "";
    }

    // --- The network popup: the networks in range ---
    function _scan(entries) {
        return entries.map(entry => ({ ssid: entry[0], signal: entry[1], security: "WPA2", band: "5G", inUse: entry[2] ?? false }));
    }

    function _rowsBySsid(list) {
        const rows = {};
        for (let i = 0; i < list.count; i++) {
            const row = list.itemAtIndex(i);
            if (row)
                rows[row.ssid] = row;
        }
        return rows;
    }

    function _networksInRange(keep) {
        WifiManager.wifiNetworks = _scan([["Home", 80], ["Cafe", 60], ["Office", 40]]);
        const view = keep(_create("../panels/network/WifiNetworkList.qml", { width: 300, maximumHeight: 600 }));
        if (!view)
            return;
        const list = _find(view, "wifiNetworks");
        list.height = 500;
        list.forceLayout();
        const before = _rowsBySsid(list);
        assertEqual(Object.keys(before).length, 3, "Wi-Fi list: a row per network");

        WifiManager.wifiNetworks = _scan([["Home", 80], ["Office", 45]]);
        list.forceLayout();
        let after = _rowsBySsid(list);
        assert(after["Home"] === before["Home"] && after["Office"] === before["Office"],
               "Wi-Fi list: a network gone from the middle — the others keep their rows");
        assertEqual(after["Office"].network.signal, 45, "… with their new signal");

        WifiManager.wifiNetworks = _scan([["Office", 90, true], ["Home", 70]]);
        list.forceLayout();
        after = _rowsBySsid(list);
        assert(after["Office"] === before["Office"] && after["Office"].network.inUse === true && after["Office"].network.signal === 90,
               "Wi-Fi list: re-sorted by signal — the row moves with its network and shows it in use (not stale)");
        assert(list.itemAtIndex(0) === before["Office"], "… at the top");

        // Each row's context (1.32): its network as the saved networks' cards give it — Home
        // saved, Office not — following the row through new reads, re-sorts and a profile
        // saved; outside the popup the row is no place
        NetworkProfiles.wifi = _wifiDetails(["Home"]);
        NetworkProfiles.profiles = _wifiProfiles(["Home"], "");
        after = _rowsBySsid(list);
        assertEqual(JSON.stringify([after["Office"].context, after["Home"].context]),
                    JSON.stringify([{ networkId: "", name: "Office", kind: "wifi", active: false, ssid: "Office" }, { networkId: "uuid-Home", name: "Home", kind: "wifi", active: false, ssid: "Home" }]),
                    "Wi-Fi list: a row's context — a network not saved by its SSID, a saved one by its profile");
        assert(after["Office"].path === "" && after["Office"].nameLine.titleRegion.path === "", "… in a list with no row name and no popup: no place");
        WifiManager.wifiNetworks = _scan([["Home", 95], ["Office", 30]]);
        list.forceLayout();
        NetworkProfiles.wifi = _wifiDetails(["Home", "Office"]);
        NetworkProfiles.profiles = _wifiProfiles(["Home", "Office"], "Office");
        after = _rowsBySsid(list);
        assert(after["Office"] === before["Office"] && after["Home"] === before["Home"] && list.itemAtIndex(0) === before["Home"],
               "… re-sorted again: the same rows");
        assertEqual(JSON.stringify([after["Office"].context, after["Home"].context]),
                    JSON.stringify([{ networkId: "uuid-Office", name: "Office", kind: "wifi", active: false, ssid: "Office" }, { networkId: "uuid-Home", name: "Home", kind: "wifi", active: false, ssid: "Home" }]),
                    "… each with its own network's context, Office's now by its profile");
        assert(after["Office"].isSaved && after["Home"].isSaved, "… both saved for the row too: no password asked, Forget offered");
        // "Saved" is one rule for the row and its context (ModuleRules.savedWifiSsids): Office's
        // profile a hotspot, Home's details not read yet (just saved) — neither row offers
        // Forget, neither context has a profile
        const hotspotDetails = _wifiDetails(["Office"]);
        hotspotDetails["uuid-Office"].mode = "ap";
        NetworkProfiles.wifi = hotspotDetails;
        assertEqual([after["Office"], after["Home"]].map(row => row.isSaved + " " + row.context.networkId + " " + (_find(row, "wifiForget")?.visible ?? "none")).join(", "),
                    "false  false, false  false",
                    "a hotspot's SSID, a profile whose details are not read: not saved — no Forget, no profile in the context");
        // Details left from a profile gone: not saved either
        NetworkProfiles.wifi = _wifiDetails(["Home", "Office"]);
        NetworkProfiles.profiles = _wifiProfiles(["Home"], "");
        assertEqual([after["Office"], after["Home"]].map(row => row.isSaved + " " + row.context.networkId).join(", "), "false , true uuid-Home",
                    "details of a profile gone: not saved for the row nor its context; Home saved for both");
        NetworkProfiles.profiles = _wifiProfiles(["Home", "Office"], "Office");
        // A name with a line break: one line all the same
        WifiManager.wifiNetworks = _scan([["Home", 95], ["Office", 30], ["Two\nlines", 20]]);
        list.forceLayout();
        const twoLines = _rowsBySsid(list)["Two\nlines"];
        assert(twoLines && twoLines.nameLine.lineCount === 1 && twoLines.context.ssid === "Two lines" && twoLines.context.name === "Two lines",
               "an SSID with a line break: its name on one line (" + twoLines?.nameLine.lineCount + "), its context's ssid and name too");
        WifiManager.wifiNetworks = _scan([["Office", 90, true], ["Home", 70]]);
        list.forceLayout();
        after = _rowsBySsid(list);

        // Enter in a network's password field: what Connect does, while it says Connect and
        // can be pressed, and a password is typed. The connects go to a stand-in, never to
        // NetworkManager. Opened and typed into as the panel does (it keeps both per SSID)
        const home = after["Home"];
        const office = after["Office"];
        const asked = [];
        const standIn = { connecting: false, connectingTo: "", savedSsids: [], connectToWifi: (ssid, password) => asked.push(ssid + "=" + password),
            cancelConnect: () => asked.push("cancel"), forgetNetwork: ssid => asked.push("forget " + ssid) };
        home.wifi = standIn;
        home.toggleRequested();
        assert(home.expanded, "Wi-Fi list: a row opened");
        const field = _find(home, "wifiPasswordField");
        const connect = _find(home, "wifiConnect");
        const problem = _find(home, "wifiRowProblem");
        assert(home.needsPassword && field !== null && field.visible, "Wi-Fi list: a secured network not saved has a password field");
        field.input.accepted();
        assertEqual(asked.length, 0, "Enter with the field empty: nothing");
        home.passwordEdited("abc");
        assert(field.text === "abc" && !connect.available && problem.visible && problem.text === "8 to 63 characters.",
               "a WPA password too short: Connect not available, a hint says why (" + problem.text + ")");
        field.input.accepted();
        connect.clicked();
        assertEqual(asked.length, 0, "… neither Enter nor Connect connects with it");
        home.passwordEdited("a long enough secret");
        assert(field.text === "a long enough secret" && connect.available && !problem.visible, "… a password long enough: Connect available, no hint");
        office.toggleRequested();
        assert(!home.expanded && office.expanded, "another network opened: this row closes");
        field.input.accepted();
        assertEqual(asked.length, 0, "… Enter in its field (still focused, only clipped) connects nothing");
        home.toggleRequested();
        field.input.accepted();
        assertEqual(asked.join(" "), "Home=a long enough secret", "opened again, Enter connects with it, as Connect does");
        home.wifi = Object.assign({}, standIn, { connecting: true, connectingTo: "Home" });
        assertEqual(connect.label, "Cancel", "… while it connects the button is Cancel");
        field.input.accepted();
        assertEqual(asked.length, 1, "… and Enter neither connects again nor cancels");

        // The rest of what the row reads and does goes through the same property
        home.wifi = Object.assign({}, standIn, { connectFailed: true, failedSsid: "Home", failedKind: "password" });
        assert(problem.visible && problem.text === "Wrong password", "why connecting failed, from the Wi-Fi it is given (" + problem.text + ")");
        home.wifi = Object.assign({}, standIn, { savedSsids: ["Home"] });
        assert(home.isSaved && !field.visible, "saved, as the Wi-Fi it is given says: no password field");
        const forget = _find(home, "wifiForget");
        forget.confirmed();
        assertEqual(asked[asked.length - 1], "forget Home", "… and Forget goes to it");
        home.wifi = WifiManager;
        home.toggleRequested();
        home.passwordEdited("");
    }

    // --- An editable list in a card (components/ReorderList.qml): the bar's sections, the
    // hardware sources ---
    property Component _reorderContent: Component {
        Item {
            objectName: "reorderContent"
            property var value
            property int index
            // What a person typed into the row, say
            property string typed: ""
        }
    }

    function _reorderRows(list) {
        const rows = [];
        for (let i = 0; i < list.count; i++)
            rows.push(list.itemAtIndex(i));
        return rows;
    }

    function _reorderList() {
        const view = _create("../components/ReorderList.qml", { width: 300, items: ["clock", "tray", "clock", "battery"], rowContent: _reorderContent });
        if (!view)
            return;
        try {
            const list = _find(view, "reorderRows");
            list.forceLayout();
            assert(list.model instanceof QtObject && !Array.isArray(list.model), "ReorderList: the rows' model is a ScriptModel, not the bare array");
            let rows = _reorderRows(list);
            assertEqual(rows.map(row => row?.value).join(","), "clock,tray,clock,battery", "ReorderList: a row per item, a repeated one twice");
            assertEqual(_findAll(view, "reorderContent").map(content => content.value + content.index).sort().join(","),
                        "battery3,clock0,clock2,tray1", "… each row's content given its value and index");
            const battery = rows[3];
            const secondClock = rows[2];
            const tray = rows[1];
            _find(battery, "reorderContent").typed = "kept";
            const moves = [];
            view.moved.connect((from, to) => moves.push(from + ">" + to));

            // The battery dragged to the top, as a drop does
            list.dragIndex = 3;
            list.dropIndex = 0;
            list.dragging = true;
            view._drop();
            assertEqual(moves.join(" "), "3>0", "ReorderList: a drop says moved(from, to)");
            rows = _reorderRows(list);
            assertEqual(rows.map(row => row?.value).join(","), "battery,clock,tray,clock", "… the rows in the new order at once");
            assert(rows[0] === battery && rows[3] === secondClock, "… the moved row and the others keep their delegates");
            assertEqual(_find(battery, "reorderContent").typed + _find(battery, "reorderContent").index, "kept0", "… the moved row's content with its state, at its new index");

            // The owner's new list comes back: nothing changes
            view.items = ["battery", "clock", "tray", "clock"];
            assert(_reorderRows(list)[0] === battery, "ReorderList: the owner's list after the move keeps the rows");

            // A row removed: the others stay
            const removals = [];
            view.removed.connect(index => removals.push(index));
            view._remove(1);
            rows = _reorderRows(list);
            assertEqual(removals.join(" ") + " " + rows.map(row => row?.value).join(","), "1 battery,tray,clock", "ReorderList: a row removed");
            // (A repeated value is keyed by its count, so the clock left is now the first and
            // takes that row: the same value either way)
            assert(rows[0] === battery && rows[1] === tray, "… the others keep their delegates");
        } finally {
            view.destroy();
        }
    }

    function run() {
        _reorderList();
        _withSources(keep => _savedNetworks(keep));
        _withSources(keep => _networksInRange(keep));
        // The restore itself: a check that throws half-way still leaves the lists as they were
        const before = NetworkProfiles.profiles;
        try {
            _withSources(() => {
                NetworkProfiles.profiles = [{ uuid: "stand-in" }];
                throw new Error("stopped early");
            });
        } catch (error) {
        }
        assert(NetworkProfiles.profiles === before, "a check that stops early: the sources are put back");
    }
}
