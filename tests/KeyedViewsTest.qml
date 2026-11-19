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

        // Enter in a network's password field: what Connect does, while it says Connect and
        // a password is typed. The connects go to a stand-in, never to NetworkManager
        const home = after["Home"];
        const asked = [];
        const standIn = { connecting: false, connectingTo: "", savedSsids: [], connectToWifi: (ssid, password) => asked.push(ssid + "=" + password),
            cancelConnect: () => asked.push("cancel") };
        home.wifi = standIn;
        home.expanded = true;
        const field = _find(home, "wifiPasswordField");
        assert(home.needsPassword && field !== null && field.visible, "Wi-Fi list: a secured network not saved has a password field");
        field.input.accepted();
        assertEqual(asked.length, 0, "Enter with the field empty: nothing");
        home.passwordText = "a long enough secret";
        assertEqual(field.text, "a long enough secret", "… a password typed (the panel keeps it)");
        field.input.accepted();
        assertEqual(asked.join(" "), "Home=a long enough secret", "… Enter connects with it, as Connect does");
        home.wifi = Object.assign({}, standIn, { connecting: true, connectingTo: "Home" });
        assertEqual(_find(home, "wifiConnect").label, "Cancel", "… while it connects the button is Cancel");
        field.input.accepted();
        assertEqual(asked.length, 1, "… and Enter neither connects again nor cancels");
        home.wifi = WifiManager;
        home.passwordText = "";
    }

    function run() {
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
