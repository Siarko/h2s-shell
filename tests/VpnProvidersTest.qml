import QtQuick
import qs.singletons
import qs.singletons.network

// The VPN provider seam (docs/plans/tailscale.md §3): the pure rules in NetworkRules, and
// VpnManager's registry driven with the stand-in provider (FakeVpnProvider.qml). Nothing
// here reaches NetworkManager: only provider ids ("fake:…") are connected, and the unit
// runner gives nmcli no bus. Asynchronous for the parts that need the event loop: a
// provider destroyed while registered, a slow operation finishing on its timer.
TestCase {
    id: suite

    suiteName: "VpnProviders"
    asynchronous: true

    readonly property var rules: NetworkRules
    property var _fakeComponent: Qt.createComponent("FakeVpnProvider.qml")

    function _fake(properties) {
        if (_fakeComponent.status !== Component.Ready) {
            fail("FakeVpnProvider does not compile: " + _fakeComponent.errorString());
            return null;
        }
        return _fakeComponent.createObject(suite, properties ?? {});
    }

    function _vpn(id) {
        return VpnManager.vpns.find(vpn => vpn.uuid === id) ?? null;
    }

    // Steps run one after another on the event loop, `wait` ms apart
    // (the steps are at the end of the file)
    property Timer _stepTimer: Timer {
        interval: 30
        onTriggered: suite._next()
    }

    function _next() {
        const step = _steps.shift();
        if (step === undefined) {
            finish();
            return;
        }
        try {
            step.run();
        } catch (error) {
            fail("step threw: " + error);
        }
        _stepTimer.interval = _steps.length > 0 ? (_steps[0].wait ?? 30) : 1;
        _stepTimer.restart();
    }

    function runAsync() {
        _pure();
        _registry();
        _stepTimer.interval = _steps[0].wait ?? 30;
        _stepTimer.restart();
    }

    function _pure() {
        // --- ids ---
        assert(rules.isVpnProviderId("tailscale") && rules.isVpnProviderId("my-vpn_2"), "ids: a provider id");
        assert(!rules.isVpnProviderId("Tail") && !rules.isVpnProviderId("a:b") && !rules.isVpnProviderId("") && !rules.isVpnProviderId(5)
               && !rules.isVpnProviderId("__proto__") && !rules.isVpnProviderId("constructor") && !rules.isVpnProviderId("a".repeat(33))
               && !rules.isVpnProviderId("1abc"), "ids: no capitals, colon, digits first, prototype names, too long");
        assertEqual(JSON.stringify(rules.vpnIdParts("2f0c8d0e-1111-4222-8333-944455556666")),
                    JSON.stringify({ provider: "", entry: "2f0c8d0e-1111-4222-8333-944455556666" }), "ids: a NetworkManager UUID is its own");
        assertEqual(JSON.stringify(rules.vpnIdParts("tailscale:default")), JSON.stringify({ provider: "tailscale", entry: "default" }),
                    "ids: <provider>:<entry>");
        assert(rules.vpnIdParts("tailscale:a:b") === null && rules.vpnIdParts(":x") === null && rules.vpnIdParts("x:") === null
               && rules.vpnIdParts("__proto__") === null && rules.vpnIdParts("tailscale:__proto__") === null && rules.vpnIdParts(7) === null
               && rules.vpnIdParts("") === null, "ids: a second colon, empty halves, prototype names, not text — none");
        assertEqual(rules.vpnId("fake", "one"), "fake:one", "ids: made from the two");

        // --- entries checked ---
        const notList = rules.vpnProviderEntries("p", "nonsense");
        assert(notList.entries.length === 0 && notList.problems.length === 1, "entries: not a list — none, reported");
        const none = rules.vpnProviderEntries("p", undefined);
        assert(none.entries.length === 0 && none.problems.length === 0, "entries: none given — none, nothing to report");
        const throwing = { id: "t", state: "" };
        Object.defineProperty(throwing, "name", { get: () => { throw new Error("boom"); }, enumerable: true });
        const hostile = rules.vpnProviderEntries("p", [
            null, 7, [], "text",
            { id: "a:b", name: "colon", state: "" },
            { id: "__proto__", name: "proto", state: "" },
            { id: "constructor", name: "ctor", state: "" },
            { id: "", name: "empty", state: "" },
            Object.create({ id: "inherited", name: "inherited", state: "" }),
            JSON.parse('{"id":"json","name":"from JSON","__proto__":{"state":"activated"}}'),
            { id: "good", name: "  Good  ", state: "activated" },
            { id: "good", name: "again", state: "" },
            { id: "badname", name: 5, state: "" },
            { id: "badstate", name: "x", state: "up" },
            throwing,
            { id: "att1", name: "a", state: "", attention: { reason: "", action: "" } },
            { id: "att2", name: "a", state: "", attention: "log in" },
            { id: "att3", name: "a", state: "", attention: { reason: "Log in to Tailscale", action: 5 } },
            { id: "att4", name: "a", state: "", attention: { reason: "Log in to Tailscale", action: "Log in" } },
            { id: "att5", name: "a", state: "", attention: { reason: "Waiting for approval" } },
            { id: "det", name: "d", state: "", detail: [1, 2] },
            { id: "act", name: "", state: "activating", active: "yes" }
        ]);
        const ids = hostile.entries.map(entry => entry.id);
        assertEqual(ids.join(","), "json,good,att1,att2,att3,att4,att5,det,act",
                    "entries: wrong shapes, colons, prototype names, inherited fields, repeats, a throwing getter — dropped");
        assert(hostile.problems.length >= 13, "entries: each drop and each reset reported (" + hostile.problems.length + ")");
        const byId = id => hostile.entries.find(entry => entry.id === id);
        assert(byId("json").state === "" && !byId("json").active, "entries: a \"__proto__\" key in JSON changes nothing");
        assert(byId("good").name === "Good" && byId("good").active === true && byId("good").attention === null,
               "entries: the first of a repeated id kept, name trimmed, active from the state");
        assert(byId("att1").attention === null && byId("att2").attention === null && byId("att3").attention === null,
               "entries: attention of a wrong shape — none");
        assert(byId("att4").attention.reason === "Log in to Tailscale" && byId("att4").attention.action === "Log in"
               && byId("att5").attention.action === "", "entries: attention { reason, action }, the action optional");
        assert(byId("det").detail.servers.length === 0 && byId("det").detail.service === "" && byId("act").active === true
               && byId("act").name === "act", "entries: a wrong detail — empty; a wrong active — from the state; no name — its id");
        const detail = rules.vpnProviderDetail({ server: "relay.example", iface: "tailscale0", addresses: ["100.64.0.1", 5],
            dns: "nope", interfaceName: "bad name!", extra: "dropped" });
        assertEqual(JSON.stringify(detail), JSON.stringify({ service: "", server: "relay.example", servers: ["relay.example"], iface: "tailscale0",
            interfaceName: "", addresses: ["100.64.0.1"], dns: [] }), "detail: the shape of NetworkManager's details, the rest dropped");
        const many = [];
        for (let i = 0; i < 70; i++)
            many.push({ id: "e" + i, name: "e", state: "" });
        assertEqual(rules.vpnProviderEntries("p", many).entries.length, 64, "entries: at most 64");

        // --- one list ---
        const read = { providerId: "fake", typeName: "Fake VPN", glyph: "G",
            entries: rules.vpnProviderEntries("fake", [{ id: "a", name: "A", state: "" }, { id: "b", name: "B", state: "activated" }]).entries };
        const providerVpns = rules.vpnProviderVpns(read);
        assert(providerVpns[1].uuid === "fake:b" && providerVpns[1].type === "provider" && providerVpns[1].kind === "vpn"
               && providerVpns[1].provider === "fake" && providerVpns[1].entryId === "b" && providerVpns[1].typeName === "Fake VPN"
               && providerVpns[1].active && providerVpns[1].attention === null, "merged: a provider's entry as a VPN, by <provider>:<entry>");
        const nm = [{ uuid: "w", type: "wireguard", active: true, lastUsed: 5, state: "activated" },
                    { uuid: "o", type: "vpn", active: false, lastUsed: 9, state: "" }];
        assertEqual(rules.mergedVpns(nm, providerVpns).map(vpn => vpn.uuid).join(" "), "w fake:b o fake:a",
                    "merged: those up first, then the most recently used; ties keep NetworkManager's first");
        assertEqual(rules.mergedVpns(nm, []).map(vpn => vpn.uuid).join(" "), "w o", "merged: no provider — NetworkManager's as they were");
        assert(rules.activeVpnGlyph([]) === "󰒃" && rules.activeVpnGlyph([nm[0]]) === "󰒃" && rules.activeVpnGlyph([providerVpns[1]]) === "G"
               && rules.activeVpnGlyph([nm[0], providerVpns[1]]) === "󰌾" && rules.activeVpnGlyph([{ type: "vpn" }]) === "󰌾"
               && rules.activeVpnGlyph([Object.assign({}, providerVpns[1], { glyph: "" })]) === "󰌾",
               "merged: the bar's glyph — WireGuard's, the provider's own when only it is up, else the padlock");
        assert(rules.vpnGlyph(nm[0]) === "󰒃" && rules.vpnGlyph(nm[1]) === "󰌾" && rules.vpnGlyph(providerVpns[0]) === "G", "merged: a row's glyph");

        // --- failures ---
        assertEqual(JSON.stringify(rules.vpnFailureNotice("Connecting Tailscale", "not logged in")),
                    JSON.stringify({ title: "Connecting Tailscale failed", body: "not logged in" }), "failure: a notification with the reason");
        assertEqual(JSON.stringify(rules.vpnFailureNotice("", 5)), JSON.stringify({ title: "A VPN action failed", body: "It did not say why." }),
                    "failure: nothing said — still a notification");

        // --- VPN with a network: the setting kept while a provider is away ---
        const profile = (uuid, kind, state) => ({ uuid: uuid, kind: kind, state: state });
        const profiles = [profile("wired", "ethernet", "activated"), profile("nmvpn", "vpn", "")];
        const mapping = { wired: ["nmvpn", "fake:one", "fake:gone", "away:x", "slow:y", "bad:a:b", "deleted"] };
        const providers = { fake: { ready: true, entries: ["one"] }, slow: { ready: false, entries: [] } };
        assertEqual(JSON.stringify(rules.prunedVpnMapping(mapping, profiles, providers)),
                    JSON.stringify({ wired: ["nmvpn", "fake:one", "away:x", "slow:y"] }),
                    "pruning: an entry there kept, one its ready provider no longer has removed, an absent or unready provider's kept, garbage removed");
        assertEqual(JSON.stringify(rules.dormantVpnIds(mapping, providers)), JSON.stringify(["away:x"]),
                    "pruning: the absent provider's entry is dormant");
        assertEqual(JSON.stringify(rules.prunedVpnMapping(mapping, profiles)), JSON.stringify({ wired: ["nmvpn", "fake:one", "fake:gone", "away:x", "slow:y"] }),
                    "pruning: with no provider registered every provider id is kept (dormant)");
        assertEqual(JSON.stringify(rules.prunedVpnMapping(mapping, [], providers)), JSON.stringify(mapping), "pruning: nothing before the profiles are read");
        assertEqual(JSON.stringify(rules.prunedVpnMapping({ wired: ["fake:gone"] }, profiles, providers)), JSON.stringify({}),
                    "pruning: a network left with no VPN leaves the setting");

        // --- VPN with a network: a provider's VPN through the same states ---
        const map = { wired: ["fake:one"] };
        const up = state => [profile("wired", "ethernet", state)];
        const entry = (state, attention) => [{ uuid: "fake:one", state: state, attention: attention ?? null }];
        const plan = (networkState, entryList, memory, now) => rules.vpnWithNetworkPlan(up(networkState), map, memory, now, entryList);
        const start = plan("activated", entry(""), {}, 1000);
        assert(start.connect.join() === "fake:one" && start.memory.pending["fake:one"] === 1000 && start.memory.broughtUp["fake:one"],
               "plan: a network up brings the provider's VPN up, pending");
        const seen = plan("activated", entry("activated"), start.memory, 2000);
        assert(!("fake:one" in seen.memory.pending) && seen.memory.broughtUp["fake:one"], "plan: seen up");
        const gone = plan("", entry("activated"), seen.memory, 3000);
        assert(gone.disconnect.join() === "fake:one" && !gone.memory.broughtUp["fake:one"], "plan: the network gone — taken down");
        const failed = plan("activated", entry(""), start.memory, 100000);
        assert(failed.connect.length === 0 && failed.memory.heldDown["fake:one"] === "wired", "plan: still down after 90 s — failed, held down");
        const needsLogin = plan("activated", entry("", { reason: "Log in", action: "Log in" }), start.memory, 3000);
        assert(needsLogin.connect.length === 0 && needsLogin.memory.heldDown["fake:one"] === "wired" && !("fake:one" in needsLogin.memory.pending),
               "plan: asked, then needing the user — held down, not retried");
        const loggedIn = plan("activated", entry(""), needsLogin.memory, 4000);
        assertEqual(loggedIn.connect.length, 0, "plan: the attention gone after a hold — still held until the networks change (no loop)");
        let memory = {};
        let asked = 0;
        for (let i = 0; i < 20; i++) {
            const step = plan("activated", entry("", { reason: "Key expired", action: "Log in" }), memory, 1000 + i * 100000);
            asked += step.connect.length;
            memory = step.memory;
        }
        assertEqual(asked, 0, "plan: needing the user from the start — never asked, however long");
        const cleared = plan("activated", entry(""), memory, 3000000);
        assertEqual(cleared.connect.join(), "fake:one", "plan: needing the user from the start, then not — asked once");
        const notRead = rules.vpnWithNetworkPlan([], map, seen.memory, 5000, entry("activated"));
        assert(notRead.disconnect.length === 0 && notRead.connect.length === 0 && notRead.memory.broughtUp["fake:one"],
               "plan: the profiles not read yet — the provider's VPN left alone");
        const late1 = plan("activated", [], {}, 1000);
        assert(late1.connect.length === 0 && Object.keys(late1.memory.pending).length === 0, "plan: provider not registered yet — nothing done");
        const late2 = plan("activated", entry(""), late1.memory, 2000);
        assertEqual(late2.connect.join(), "fake:one", "plan: provider registered after the network came up — brought up then");
        const away = plan("", [], seen.memory, 3000);
        assert(away.disconnect.length === 0 && away.memory.broughtUp["fake:one"], "plan: provider unregistered while up — nothing done, memory kept");
        const back = plan("", entry("activated"), away.memory, 4000);
        assertEqual(back.disconnect.join(), "fake:one", "plan: it comes back up while its network is gone — taken down as brought up by the shell");

        // --- the kill switch's note ---
        const providerUp = Object.assign({}, providerVpns[1]);
        assert(rules.lockdownProviderNote(true, providerUp, "").indexOf("Fake VPN") === 0, "lockdown note: blocking, a provider VPN up — the shell's sentence");
        assertEqual(rules.lockdownProviderNote(true, providerUp, "Tailscale cannot connect while traffic outside a VPN is blocked"),
                    "Tailscale cannot connect while traffic outside a VPN is blocked", "lockdown note: the provider's wording");
        assert(rules.lockdownProviderNote(true, Object.assign({}, providerUp, { state: "activating" }), "") !== "", "lockdown note: while connecting too");
        assert(rules.lockdownProviderNote(false, providerUp, "x") === "" && rules.lockdownProviderNote(true, providerVpns[0], "x") === ""
               && rules.lockdownProviderNote(true, nm[0], "x") === "", "lockdown note: none when not blocking, when off, for NetworkManager's");
    }

    property var _fakeOne: null

    function _registry() {
        // With no provider, VpnManager's lists are NetworkManager's own — the same objects
        assert(VpnManager.vpns === VpnManager.nmVpns && VpnManager.details === VpnManager.nmDetails,
               "registry: no provider — the VPNs and details are NetworkManager's, untouched");

        const fake = _fake();
        _fakeOne = fake;
        assert(fake !== null && fake.registered, "registry: a provider registers itself");
        fake.add("one", "One");
        fake.add("two", "Two");
        assert(_vpn("fake:one") !== null && _vpn("fake:two") !== null && _vpn("fake:one").name === "One",
               "registry: its entries among the VPNs, by <provider>:<entry>");
        assertEqual(VpnManager.typeName(_vpn("fake:one")), "Fake VPN", "registry: its type name");

        const twin = _fake();
        assert(twin !== null && !twin.registered, "registry: a second provider with a taken id is refused");
        twin.add("three", "Three");
        assert(_vpn("fake:three") === null, "registry: the refused one's entries are not shown");
        assert(!VpnManager.registerProvider({ providerId: "Bad:Id" }) && !VpnManager.registerProvider(null)
               && !VpnManager.registerProvider({}), "registry: no valid id — refused");

        // Garbage among the entries: dropped and reported, the rest shown
        fake.entries = fake.entries.concat([null, { id: "x:y", name: "colon", state: "" }, { id: "z", name: "z", state: "broken" }]);
        assert(VpnManager.vpns.filter(vpn => vpn.provider === "fake").length === 2 && (VpnManager.providerProblems["fake"] ?? []).length === 3,
               "registry: wrong entries dropped and reported");
        fake.entries = fake.entries.filter(entry => entry !== null && entry.id !== "x:y" && entry.id !== "z");
        assert(VpnManager.providerProblems["fake"] === undefined, "registry: problems gone with the garbage");

        // Dispatch by the id
        VpnManager.connect("fake:one");
        assert(fake.calls.length === 1 && fake.calls[0][0] === "connect" && fake.calls[0][1] === "one", "dispatch: connect reaches the provider with its entry id");
        assert(_vpn("fake:one").state === "activated" && VpnManager.activeVpns.some(vpn => vpn.uuid === "fake:one"),
               "dispatch: its state through the merged list");
        if (VpnManager.nmVpns.filter(vpn => vpn.state === "activated").length === 0)
            assertEqual(VpnManager.activeGlyph, "󰖂", "dispatch: only it up — its glyph in the bar");
        assert(VpnManager.interfaceOf(_vpn("fake:one")) === "fake0" && VpnManager.details["fake:one"].addresses[0] === "100.64.0.2/32",
               "dispatch: its interface and addresses as NetworkManager's details are read");
        VpnManager.disconnect("fake:one");
        assert(fake.calls[1][0] === "disconnect" && _vpn("fake:one").state === "", "dispatch: disconnect");
        VpnManager.connect("fake:nosuch");
        VpnManager.connect("other:one");
        VpnManager.connect("fake:a:b");
        VpnManager.attend("fake:nosuch");
        assertEqual(fake.calls.length, 2, "dispatch: an entry it does not report, another provider, a malformed id — nothing called");
        assert(VpnManager.providerOf("fake:one") !== null && VpnManager.providerOf("2f0c8d0e-1111-4222-8333-944455556666") === null,
               "dispatch: a UUID is NetworkManager's");

        // busy and canChange
        fake.slowMs = 5000;
        VpnManager.connect("fake:two");
        assert(VpnManager.busyFor(_vpn("fake:two")) && _vpn("fake:two").state === "activating", "busy: an operation running — its buttons wait");
        fake._finish();
        assert(!VpnManager.busyFor(_vpn("fake:two")) && _vpn("fake:two").state === "activated", "busy: done");
        fake.slowMs = 0;
        VpnManager.disconnect("fake:two");
        assertEqual(VpnManager.needFor(_vpn("fake:two")), "", "canChange: true — no mark");
        fake.canChange = false;
        assertEqual(VpnManager.needFor(_vpn("fake:two")), "auth", "canChange: false — the privileged mark");
        fake.canChange = true;
        assertEqual(VpnManager.needFor({ uuid: "u", type: "wireguard" }), "", "canChange: NetworkManager's VPNs unmarked, as before");
        assertEqual(VpnManager.busyFor({ uuid: "u", type: "wireguard" }), NetworkProfiles.connecting, "busy: NetworkManager's as before");

        // Failure → a notification with the reason
        fake.failNext = "the daemon is not running";
        VpnManager.connect("fake:one");
        assert(VpnManager.lastProviderNotice !== null && VpnManager.lastProviderNotice.title === "Connecting One failed"
               && VpnManager.lastProviderNotice.body === "the daemon is not running", "failure: the provider's signal becomes a notification");

        // Attention: shown, its action dispatched, cleared by the provider
        fake.attentionOnConnect = { reason: "Log in to continue", action: "Log in" };
        VpnManager.connect("fake:one");
        assert(_vpn("fake:one").attention !== null && _vpn("fake:one").attention.action === "Log in" && _vpn("fake:one").state === "",
               "attention: on the entry");
        VpnManager.attend("fake:one");
        assert(fake.calls[fake.calls.length - 1][0] === "attend" && _vpn("fake:one").attention === null, "attention: its action reaches the provider");

        // Slots
        assert(VpnManager.extrasFor(VpnManager.slots.row, _vpn("fake:one")) === null, "slots: none offered — none");
        fake.withExtras = true;
        assert(VpnManager.extrasFor(VpnManager.slots.row, _vpn("fake:one")) !== null && VpnManager.extrasFor(VpnManager.slots.card, _vpn("fake:one")) !== null
               && VpnManager.extrasFor(VpnManager.slots.page, _vpn("fake:one")) === null, "slots: the row's and the card's");
        assert(VpnManager.extrasFor(VpnManager.slots.row, { uuid: "u", type: "wireguard" }) === null, "slots: none for NetworkManager's");
        assert(VpnManager.slots.row === "network.vpn.row" && VpnManager.slots.card === "network.vpn.card" && VpnManager.slots.page === "network.vpn.page",
               "slots: their names");
        fake.withExtras = false;

        // The kill switch does not take provider VPNs in
        assert(VpnLockdown.vpnInterfaces.indexOf("fake0") < 0 && JSON.stringify(VpnManager.nmDetails).indexOf("fake:") < 0,
               "lockdown: the provider's interface and details never reach the blocking");
        assertEqual(VpnLockdown.noteFor({ uuid: "u", type: "wireguard", state: "activated" }), "", "lockdown note: none for NetworkManager's");

        // Hostile providers: properties that throw, a connect that throws
        const thrower = { providerId: "thrower" };
        Object.defineProperty(thrower, "entries", { get: () => { throw new Error("boom"); } });
        assert(VpnManager.registerProvider(thrower), "hostile: a plain object of the shape registers");
        assert((VpnManager.providerProblems["thrower"] ?? []).join(" ").indexOf("threw") >= 0 && _vpn("fake:one") !== null,
               "hostile: entries that throw — none of its shown, reported, the others unaffected");
        VpnManager.unregisterProvider("thrower");
        const breaking = { providerId: "breaking", entries: [{ id: "b", name: "B", state: "" }], connect: () => { throw new Error("no"); } };
        VpnManager.registerProvider(breaking);
        VpnManager.connect("breaking:b");
        assert(VpnManager.lastProviderNotice.title === "Connecting B failed" && VpnManager.lastProviderNotice.body.indexOf("no") >= 0,
               "hostile: a connect that throws — logged and said as a failure");
        VpnManager.unregisterProvider("breaking");
        assert(_vpn("breaking:b") === null, "hostile: unregistered — gone");

        // Unregistering while connected: its VPN leaves the list
        fake.setState("two", "activated");
        const second = _fake({ providerId: "second" });
        second.add("s", "S");
        second.setState("s", "activated");
        assert(_vpn("second:s") !== null, "unregister: registered");
        VpnManager.unregisterProvider("second", second);
        assert(_vpn("second:s") === null && _vpn("fake:two") !== null, "unregister: its VPN gone while connected, the others stay");
        second.destroy();
        twin.destroy();

        // Loaded as the shell loads it with H2S_FAKE_VPN_PROVIDER=1: by a file URL — it
        // reaches the same VpnManager
        const byUrl = Qt.createComponent(VpnManager.fakeProviderUrl);
        const loaded = byUrl.status === Component.Ready ? byUrl.createObject(suite, { providerId: "byurl" }) : null;
        assert(loaded !== null && loaded.registered, "by URL: the stand-in loads by its file URL and registers");
        if (loaded !== null) {
            loaded.add("u", "U");
            assert(_vpn("byurl:u") !== null, "by URL: the same VpnManager sees its entries");
            VpnManager.unregisterProvider("byurl", loaded);
            loaded.destroy();
        }
        assert(VpnManager._fakeProvider === null, "by URL: without H2S_FAKE_VPN_PROVIDER nothing is loaded by itself");
    }

    property var _section: null
    property var _card: null

    function _make(file, properties) {
        const component = Qt.createComponent(file);
        if (component.status !== Component.Ready) {
            fail(file + " does not compile: " + component.errorString());
            return null;
        }
        return component.createObject(null, properties);
    }

    // Every visible text under an item, its own included
    function _texts(item) {
        const found = [];
        const walk = node => {
            if (!node || node.visible === false)
                return;
            if (typeof node.text === "string" && node.text !== "")
                found.push(node.text);
            for (const child of node.children ?? [])
                walk(child);
        };
        walk(item);
        return found;
    }

    // The parts that need the event loop
    property var _steps: [
        { wait: 30, run: () => {
            assert(suite._vpn("fake:one") !== null, "destroyed: the refused twin going away leaves the registered one");
            suite._fakeOne.slowMs = 20;
            VpnManager.connect("fake:two");
        } },
        { wait: 120, run: () => {
            assert(suite._vpn("fake:two").state === "activated" && !VpnManager.busyFor(suite._vpn("fake:two")),
                   "slow: the operation finished on its own time");
            // The views built with a provider's VPNs (a binding error would print a TypeError,
            // which fails the run): the popup's section and a card
            suite._fakeOne.slowMs = 0;
            suite._fakeOne.withExtras = true;
            suite._fakeOne.canChange = false;
            suite._fakeOne.setAttention("one", "Log in to continue", "Log in");
            suite._section = suite._make("../panels/network/VpnSection.qml", { width: 300 });
            suite._card = suite._make("../panels/settings/NetworkProfileCard.qml", { width: 300, external: true, editable: false,
                deletable: false, profile: suite._vpn("fake:two"), notice: "A note", noticeAction: "Do it", need: "auth" });
        } },
        { wait: 60, run: () => {
            const texts = suite._texts(suite._section);
            assert(texts.includes("One") && texts.includes("Two") && texts.includes("Log in to continue") && texts.includes("Log in"),
                   "views: the popup's rows, the attention line and its action");
            assert(texts.some(text => text.indexOf("Fake row extras for one") === 0), "views: the row's extras, given their context");
            assert(suite._texts(suite._card).includes("A note") && suite._texts(suite._card).includes("Disconnect"),
                   "views: a provider's card — its notice, its button");
            suite._section.destroy();
            suite._card.destroy();
            suite._fakeOne.destroy();
        } },
        { wait: 50, run: () => {
            assert(VpnManager.vpns.every(vpn => vpn.provider !== "fake") && VpnManager.providerVpns.length === 0,
                   "destroyed while registered (a module disabled): its VPNs gone, nothing else breaks");
            assert(VpnManager.vpns === VpnManager.nmVpns && VpnManager.details === VpnManager.nmDetails,
                   "destroyed: no provider left — NetworkManager's lists as they were");
        } }
    ]
}
