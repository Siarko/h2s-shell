import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.singletons.network

// The VPN provider seam (notes/plans/tailscale.md §3): the pure rules in NetworkRules, and
// VpnManager's registry driven with the stand-in provider (FakeVpnProvider.qml). Nothing
// here reaches NetworkManager: only provider ids ("fake:…") are connected, and the unit
// runner gives nmcli no bus. Asynchronous for the parts that need the event loop: a
// provider destroyed while registered, a slow operation finishing on its timer.
//
// The rule for every suite that registers providers: use provider ids no other suite uses
// (this one: "vpt" and "vpt-…"). Asynchronous suites run side by side on one VpnManager, and
// a taken id is refused — two suites both using "fake" break each other. And wait on
// conditions (a step's `until`, with a generous deadline), never on a fixed delay.
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
        return _fakeComponent.createObject(suite, Object.assign({ providerId: "vpt" }, properties ?? {}));
    }

    function _vpn(id) {
        return VpnManager.vpns.find(vpn => vpn.uuid === id) ?? null;
    }

    // Steps run one after another on the event loop: each once its `until` holds (checked
    // every 10 ms; none: at once), or after a deadline of 3 s — then it runs anyway and its
    // assertions say what is missing (the steps are at the end of the file)
    readonly property int _deadlineMs: 3000
    property double _stepStarted: 0
    property Timer _stepTimer: Timer {
        interval: 10
        onTriggered: suite._poll()
    }

    function _poll() {
        const step = _steps[0];
        if (step === undefined) {
            finish();
            return;
        }
        let ready = true;
        try {
            ready = step.until === undefined || step.until() === true;
        } catch (error) {
            ready = false;
        }
        if (!ready && Date.now() - _stepStarted < _deadlineMs) {
            _stepTimer.restart();
            return;
        }
        if (!ready)
            console.warn("VpnProviders: a step's condition did not come within " + _deadlineMs + " ms");
        _steps.shift();
        try {
            step.run();
        } catch (error) {
            fail("step threw: " + error);
        }
        _stepStarted = Date.now();
        _stepTimer.restart();
    }

    function runAsync() {
        _pure();
        _registry();
        _stepStarted = Date.now();
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

        // --- VPN with a network: provider ids are never pruned by the shell ---
        const profile = (uuid, kind, state) => ({ uuid: uuid, kind: kind, state: state });
        const profiles = [profile("wired", "ethernet", "activated"), profile("nmvpn", "vpn", "")];
        const mapping = { wired: ["nmvpn", "fake:one", "fake:gone", "away:x", "slow:y", "bad:a:b", "deleted"] };
        assertEqual(JSON.stringify(rules.prunedVpnMapping(mapping, profiles)),
                    JSON.stringify({ wired: ["nmvpn", "fake:one", "fake:gone", "away:x", "slow:y"] }),
                    "pruning: every provider id kept — reported, missing from its provider, provider absent or not ready; garbage and deleted UUIDs removed");
        // The reviewer's probe P1: Tailscale logged out (or one read failed) — ready, nothing reported
        assertEqual(JSON.stringify(rules.prunedVpnMapping({ wired: ["tailscale:default"] }, profiles, { tailscale: { ready: true, entries: [] } })),
                    JSON.stringify({ wired: ["tailscale:default"] }), "pruning: a ready provider reporting no entry — the user's setting kept");
        assertEqual(JSON.stringify(rules.prunedVpnMapping(mapping, [])), JSON.stringify(mapping), "pruning: nothing before the profiles are read");
        assertEqual(JSON.stringify(rules.prunedVpnMapping({ wired: ["deleted", "bad:a:b"] }, profiles)), JSON.stringify({}),
                    "pruning: a network left with no VPN leaves the setting");

        // --- "not available": one definition — a provider id not among the VPNs now ---
        const vpnsNow = [{ uuid: "nmvpn" }, { uuid: "fake:one" }];
        assertEqual(JSON.stringify(rules.unavailableVpnIds(mapping, vpnsNow)), JSON.stringify(["fake:gone", "away:x", "slow:y"]),
                    "not available: whatever the reason — entry missing, provider absent, provider not ready");
        // Probe P1b: a provider registered but not ready reports nothing — its id is not available
        assertEqual(JSON.stringify(rules.unavailableVpnIds(["tailscale:default", "nmvpn", "tailscale:default"], [])), JSON.stringify(["tailscale:default"]),
                    "not available: from a list too, each once; NetworkManager's UUIDs never");

        // --- the network editor: what it starts from and what it writes ---
        assertEqual(JSON.stringify(rules.editorVpnIds(["nmvpn", "deleted", "fake:one", "fake:gone", "bad:a:b", "fake:one"], vpnsNow)),
                    JSON.stringify(["nmvpn", "fake:one", "fake:gone"]),
                    "editor: starts with NetworkManager's VPNs there and EVERY provider id, available or not");
        const stored = ["nmvpn", "fake:gone"];
        const original = rules.editorVpnIds(stored, vpnsNow);
        assertEqual(JSON.stringify(rules.vpnsToWrite(stored, original, ["fake:gone", "other"])), JSON.stringify(["fake:gone", "other"]),
                    "editor saves: another pick changed — the not available id is still written");
        assertEqual(JSON.stringify(rules.vpnsToWrite(stored, ["nmvpn"], ["other"])), JSON.stringify(["other", "fake:gone"]),
                    "editor saves: a provider id the editor never showed is never lost");
        assertEqual(JSON.stringify(rules.vpnsToWrite(stored, original, ["nmvpn"])), JSON.stringify(["nmvpn"]),
                    "editor saves: the user took the not available id out — gone");
        assertEqual(JSON.stringify(rules.vpnsToWrite(["nmvpn", "late:x"], ["nmvpn"], [])), JSON.stringify(["late:x"]),
                    "editor saves: a provider id stored after the editor opened is kept; NetworkManager's taken out");

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
        const grace = rules.vpnAttentionGraceMs;
        const passing = plan("activated", entry("", { reason: "Log in", action: "Log in" }), start.memory, 3000);
        assert(passing.connect.length === 0 && !("fake:one" in passing.memory.heldDown) && passing.memory.pending["fake:one"] === 1000,
               "plan: needing the user moments after being asked — waited out, still pending, not held down");
        const through = plan("activated", entry("activated"), passing.memory, 6000);
        assert(!("fake:one" in through.memory.heldDown) && through.memory.broughtUp["fake:one"] && !("fake:one" in through.memory.pending),
               "plan: activating → attention for a moment → activated — not a failure, still the shell's to take down");
        assertEqual(plan("", entry("activated"), through.memory, 7000).disconnect.join(), "fake:one",
                    "plan: … and taken down with its network");
        const needsLogin = plan("activated", entry("", { reason: "Log in", action: "Log in" }), start.memory, 1000 + grace + 1);
        assert(needsLogin.connect.length === 0 && needsLogin.memory.heldDown["fake:one"] === "wired" && !("fake:one" in needsLogin.memory.pending),
               "plan: asked, then still needing the user after the grace — held down, not retried");
        const loggedIn = plan("activated", entry(""), needsLogin.memory, 1000 + grace + 1000);
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
        const stale = plan("activated", [], { pending: { "fake:one": 10, "old:x": 10 }, heldDown: { "old:y": "wired" }, broughtUp: {} }, 5000);
        assert(stale.memory.pending["fake:one"] === 10 && !("old:x" in stale.memory.pending) && !("old:y" in stale.memory.heldDown),
               "plan: memory of an id neither there nor in the mapping dropped; of one still mapped, its provider away, kept");

        // --- the kill switch's note ---
        const providerUp = Object.assign({}, providerVpns[1]);
        assert(rules.lockdownProviderNote(true, providerUp, "").indexOf("Fake VPN") === 0, "lockdown note: blocking, a provider VPN up — the shell's sentence");
        assertEqual(rules.lockdownProviderNote(true, providerUp, "Tailscale cannot connect while traffic outside a VPN is blocked"),
                    "Tailscale cannot connect while traffic outside a VPN is blocked", "lockdown note: the provider's wording");
        assert(rules.lockdownProviderNote(true, Object.assign({}, providerUp, { state: "activating" }), "") !== "", "lockdown note: while connecting too");
        assert(rules.lockdownProviderNote(false, providerUp, "x") === "" && rules.lockdownProviderNote(true, providerVpns[0], "x") === ""
               && rules.lockdownProviderNote(true, nm[0], "x") === "", "lockdown note: none when not blocking, when off, for NetworkManager's");
        assert(rules.lockdownProviderNote(true, providerVpns[0], "", true).indexOf("Fake VPN") === 0
               && rules.lockdownProviderNote(false, providerVpns[0], "", true) === "" && rules.lockdownProviderNote(true, nm[1], "", true) === "",
               "lockdown note: on the VPN page's card whenever blocking is on, connected or not; never when not blocking, nor for NetworkManager's");

        // --- an entry's status line and busy ---
        const extra = rules.vpnProviderEntries("p", [
            { id: "s1", name: "a", state: "activated", status: "  Via exit-1  ", busy: true },
            { id: "s2", name: "b", state: "", status: 5, busy: "yes" },
            { id: "s3", name: "c", state: "", status: "x".repeat(200) },
            { id: "s4", name: "d", state: "" }
        ]);
        const extraById = id => extra.entries.find(item => item.id === id);
        assert(extraById("s1").status === "Via exit-1" && extraById("s1").busy === true, "entries: status (trimmed) and busy");
        assert(extraById("s2").status === "" && extraById("s2").busy === false && extra.problems.length === 2,
               "entries: a status that is not text, a busy that is not a bool — defaults, reported");
        assert(extraById("s3").status.length === 80 && extraById("s4").status === "" && extraById("s4").busy === false,
               "entries: status at most 80; both optional");
        const extraVpns = rules.vpnProviderVpns({ providerId: "p", typeName: "P", glyph: "", entries: extra.entries });
        assert(extraVpns[0].status === "Via exit-1" && extraVpns[0].busy === true && extraVpns[3].status === "", "merged: status and busy carried");

        // --- slot contexts compared by value ---
        const owner = { providerId: "p" };
        const contextA = { slot: "network.vpn.row", vpnId: "p:a", entryId: "a", vpn: { uuid: "p:a", state: "" }, provider: owner, close: () => 1 };
        assert(rules.sameVpnContext(contextA, Object.assign({}, contextA, { vpn: { uuid: "p:a", state: "" }, close: () => 2 })),
               "context: a re-read saying the same — the same (functions alike, data by value)");
        assert(!rules.sameVpnContext(contextA, Object.assign({}, contextA, { vpn: { uuid: "p:a", state: "activated" } }))
               && !rules.sameVpnContext(contextA, Object.assign({}, contextA, { provider: { providerId: "p" } }))
               && !rules.sameVpnContext(contextA, Object.assign({}, contextA, { open: true })) && !rules.sameVpnContext(null, contextA),
               "context: a changed entry, another provider object, a key more — different");
    }

    property var _fakeOne: null

    function _registry() {
        // With no provider, VpnManager's lists are NetworkManager's own — the same objects
        assert(VpnManager.vpns === VpnManager.nmVpns && VpnManager.details === VpnManager.nmDetails,
               "registry: no provider — the VPNs and details are NetworkManager's, untouched");

        // A provider made from the public type (qs.api's VpnProvider, module API 1.7)
        const made = Qt.createQmlObject("import QtQuick\nimport qs.api\nVpnProvider {\n    property var calls: []\n"
            + "    providerId: \"vpt-api\"; typeName: \"Api VPN\"; ready: true\n"
            + "    entries: [{ id: \"one\", name: \"From the API\", state: \"\", attention: null, detail: {} }]\n"
            + "    function connect(entryId, request) { calls = calls.concat([\"connect \" + entryId + \" \" + request.origin]); }\n}", suite, "ApiVpnProvider.qml");
        assert(made.registered && VpnManager.providerOf("vpt-api:one") !== null, "registry: a provider made from qs.api registers itself");
        assertEqual(_vpn("vpt-api:one")?.name + " / " + VpnManager.typeName(_vpn("vpt-api:one")), "From the API / Api VPN", "… its entry among the VPNs, with its type name");
        VpnManager.connect("vpt-api:one", { origin: "user" });
        assertEqual(made.calls.join(), "connect one user", "… and connect reaches its function");
        made.destroy();

        const fake = _fake();
        _fakeOne = fake;
        assert(fake !== null && fake.registered, "registry: a provider registers itself");
        fake.add("one", "One");
        fake.add("two", "Two");
        assert(_vpn("vpt:one") !== null && _vpn("vpt:two") !== null && _vpn("vpt:one").name === "One",
               "registry: its entries among the VPNs, by <provider>:<entry>");
        assertEqual(VpnManager.typeName(_vpn("vpt:one")), "Fake VPN", "registry: its type name");

        const twin = _fake();
        assert(twin !== null && !twin.registered, "registry: a second provider with a taken id is refused");
        twin.add("three", "Three");
        assert(_vpn("vpt:three") === null, "registry: the refused one's entries are not shown");
        assert(!VpnManager.registerProvider({ providerId: "Bad:Id" }) && !VpnManager.registerProvider(null)
               && !VpnManager.registerProvider({}), "registry: no valid id — refused");

        // Garbage among the entries: dropped and reported, the rest shown
        fake.entries = fake.entries.concat([null, { id: "x:y", name: "colon", state: "" }, { id: "z", name: "z", state: "broken" }]);
        assert(VpnManager.vpns.filter(vpn => vpn.provider === "vpt").length === 2 && (VpnManager.providerProblems["vpt"] ?? []).length === 3,
               "registry: wrong entries dropped and reported");
        fake.entries = fake.entries.filter(entry => entry !== null && entry.id !== "x:y" && entry.id !== "z");
        assert(VpnManager.providerProblems["vpt"] === undefined, "registry: problems gone with the garbage");

        // Dispatch by the id
        VpnManager.connect("vpt:one");
        assert(fake.calls.length === 1 && fake.calls[0][0] === "connect" && fake.calls[0][1] === "one", "dispatch: connect reaches the provider with its entry id");
        assert(_vpn("vpt:one").state === "activated" && VpnManager.activeVpns.some(vpn => vpn.uuid === "vpt:one"),
               "dispatch: its state through the merged list");
        if (VpnManager.nmVpns.filter(vpn => vpn.state === "activated").length === 0)
            assertEqual(VpnManager.activeGlyph, "󰖂", "dispatch: only it up — its glyph in the bar");
        assert(VpnManager.interfaceOf(_vpn("vpt:one")) === "fake0" && VpnManager.details["vpt:one"].addresses[0] === "100.64.0.2/32",
               "dispatch: its interface and addresses as NetworkManager's details are read");
        VpnManager.disconnect("vpt:one");
        assert(fake.calls[1][0] === "disconnect" && _vpn("vpt:one").state === "", "dispatch: disconnect");
        VpnManager.connect("vpt:nosuch");
        VpnManager.connect("vpt-other:one");
        VpnManager.connect("vpt:a:b");
        VpnManager.attend("vpt:nosuch");
        assertEqual(fake.calls.length, 2, "dispatch: an entry it does not report, another provider, a malformed id — nothing called");
        assert(fake.calls[0][2] === "user" && fake.calls[1][2] === "user", "origin: a button's connect and disconnect say \"user\"");

        // Who asked: "VPN with a network" says "network"; a provider must not prompt then
        VpnManager._applyPlan({ connect: ["vpt:one"], disconnect: [] });
        assert(fake.calls[2][0] === "connect" && fake.calls[2][2] === "network", "origin: the plan's connect says \"network\"");
        VpnManager._applyPlan({ connect: [], disconnect: ["vpt:one"] });
        assert(fake.calls[3][0] === "disconnect" && fake.calls[3][2] === "network", "origin: the plan's disconnect says \"network\"");
        fake.needsPrompt = true;
        VpnManager._applyPlan({ connect: ["vpt:one"], disconnect: [] });
        assert(fake.prompts.length === 0 && _vpn("vpt:one").state === "" && _vpn("vpt:one").attention !== null,
               "origin: asked by a network, a connect that needs a password does not prompt — attention instead");
        fake.clearAttention("one");
        VpnManager.connect("vpt:one", { origin: "nonsense" });
        assert(fake.calls[5][2] === "user" && fake.prompts.join() === "one" && _vpn("vpt:one").state === "activated",
               "origin: asked by the user (an unknown origin is the core's \"user\"), it may prompt");
        fake.needsPrompt = false;
        VpnManager.disconnect("vpt:one");
        assert(VpnManager.providerOf("vpt:one") !== null && VpnManager.providerOf("2f0c8d0e-1111-4222-8333-944455556666") === null,
               "dispatch: a UUID is NetworkManager's");

        // busy and canChange
        fake.slowMs = 5000;
        VpnManager.connect("vpt:two");
        assert(VpnManager.busyFor(_vpn("vpt:two")) && _vpn("vpt:two").state === "activating", "busy: an operation running — its buttons wait");
        fake._finish();
        assert(!VpnManager.busyFor(_vpn("vpt:two")) && _vpn("vpt:two").state === "activated", "busy: done");
        fake.slowMs = 0;
        VpnManager.disconnect("vpt:two");
        assertEqual(VpnManager.needFor(_vpn("vpt:two")), "", "canChange: true — no mark");
        fake.canChange = false;
        assertEqual(VpnManager.needFor(_vpn("vpt:two")), "auth", "canChange: false — the privileged mark");
        fake.canChange = true;
        assertEqual(VpnManager.needFor({ uuid: "u", type: "wireguard" }), "", "canChange: NetworkManager's VPNs unmarked, as before");
        assertEqual(VpnManager.busyFor({ uuid: "u", type: "wireguard" }), NetworkProfiles.connecting, "busy: NetworkManager's as before");
        fake.setBusy("two", true);
        assert(VpnManager.busyFor(_vpn("vpt:two")) && !VpnManager.busyFor(_vpn("vpt:one")) && _vpn("vpt:two").busy === true,
               "busy: one entry's own — its buttons wait, the others' do not");
        fake.setBusy("two", false);
        assert(!VpnManager.busyFor(_vpn("vpt:two")), "busy: the entry's done");
        fake.setStatus("one", "Via exit-1");
        assertEqual(_vpn("vpt:one").status, "Via exit-1", "status: an entry's line through the merged list");
        fake.setStatus("one", "");

        // Failure → a notification with the reason
        fake.failNext = "the daemon is not running";
        VpnManager.connect("vpt:one");
        assert(VpnManager.lastProviderNotice !== null && VpnManager.lastProviderNotice.title === "Connecting One failed"
               && VpnManager.lastProviderNotice.body === "the daemon is not running", "failure: the provider's signal becomes a notification");

        // Attention: shown, its action dispatched, cleared by the provider
        fake.attentionOnConnect = { reason: "Log in to continue", action: "Log in" };
        VpnManager.connect("vpt:one");
        assert(_vpn("vpt:one").attention !== null && _vpn("vpt:one").attention.action === "Log in" && _vpn("vpt:one").state === "",
               "attention: on the entry");
        VpnManager.attend("vpt:one");
        assert(fake.calls[fake.calls.length - 1][0] === "attend" && _vpn("vpt:one").attention === null, "attention: its action reaches the provider");

        // Connect or the action: one rule for the row and the card, and connect() keeps it
        assert(VpnManager.canConnect(_vpn("vpt:one")) && !VpnManager.attendsInstead(_vpn("vpt:one"))
               && VpnManager.primaryLabel(_vpn("vpt:one")) === "Connect", "primary: nothing needs the user — Connect");
        assert(VpnManager.canConnect({ uuid: "u", type: "wireguard", state: "", active: false })
               && VpnManager.primaryLabel({ uuid: "u", type: "wireguard", state: "activated", active: true }) === "Disconnect"
               && !VpnManager.canConnect(null), "primary: NetworkManager's as before; no VPN — no Connect");
        const callsBefore = fake.calls.length;
        fake.setAttention("one", "Waiting for approval", "");
        assert(!VpnManager.canConnect(_vpn("vpt:one")) && !VpnManager.attendsInstead(_vpn("vpt:one"))
               && VpnManager.primaryLabel(_vpn("vpt:one")) === "", "primary: needing the user, no action — no button");
        VpnManager.connect("vpt:one");
        VpnManager._applyPlan({ connect: ["vpt:one"], disconnect: [] });
        assertEqual(fake.calls.length, callsBefore, "primary: needing the user — connect refuses, whoever asks");
        fake.setAttention("one", "Log in to continue", "Log in");
        assert(!VpnManager.canConnect(_vpn("vpt:one")) && VpnManager.attendsInstead(_vpn("vpt:one"))
               && VpnManager.primaryLabel(_vpn("vpt:one")) === "Log in", "primary: needing the user, an action — the action in place of Connect");
        VpnManager.connect("vpt:one");
        assertEqual(fake.calls.length, callsBefore, "primary: an action to offer — still no connect");
        fake.clearAttention("one");
        fake.setState("two", "activated");
        fake.setAttention("two", "Key expires soon", "");
        assert(VpnManager.primaryLabel(_vpn("vpt:two")) === "Disconnect" && !VpnManager.attendsInstead(_vpn("vpt:two")),
               "primary: up and needing the user — still Disconnect");
        fake.clearAttention("two");
        fake.setState("two", "");

        // The provider kinds among a network's VPNs: what the blocking does not let through
        assertEqual(JSON.stringify(VpnManager.providerKindsAmong(["vpt:one", "2f0c8d0e-1111-4222-8333-944455556666", "vpt:two", "away:x", "vpt:a:b"])),
                    JSON.stringify(["Fake VPN", ""]), "kinds: each provider once, by its type name, \"\" for one away; none for NetworkManager's");
        assertEqual(VpnManager.providerKindsAmong([]).length + VpnManager.providerKindsAmong(undefined).length, 0, "kinds: none picked — none");

        // Slots
        assert(VpnManager.extrasFor(VpnManager.slots.row, _vpn("vpt:one")) === null, "slots: none offered — none");
        fake.withExtras = true;
        assert(VpnManager.extrasFor(VpnManager.slots.row, _vpn("vpt:one")) !== null && VpnManager.extrasFor(VpnManager.slots.card, _vpn("vpt:one")) !== null
               && VpnManager.extrasFor(VpnManager.slots.page, _vpn("vpt:one")) === null, "slots: the row's and the card's");
        assert(VpnManager.extrasFor(VpnManager.slots.row, { uuid: "u", type: "wireguard" }) === null, "slots: none for NetworkManager's");
        assert(VpnManager.slots.row === "network.vpn.row" && VpnManager.slots.card === "network.vpn.card" && VpnManager.slots.page === "network.vpn.page",
               "slots: their names");
        const rowContext = VpnManager.contextFor(VpnManager.slots.row, _vpn("vpt:one"));
        const pageContext = VpnManager.contextFor(VpnManager.slots.page, _vpn("vpt:one"), { close: () => {} });
        assert(rowContext.provider === fake && rowContext.vpnId === "vpt:one" && rowContext.entryId === "one" && rowContext.slot === "network.vpn.row"
               && pageContext.provider === fake && typeof pageContext.close === "function",
               "slots: a contribution's context carries the provider object itself");
        assert(VpnManager.contextFor(VpnManager.slots.row, { uuid: "u", type: "wireguard" }).provider === null, "slots: no provider for NetworkManager's");
        fake.withExtras = false;

        // The card's "Settings…": the provider's own settings page when the settings window has
        // it (settingsPage → navigate), else the framed page (pageUrl / the page slot), else
        // none. Synchronous, so the suite running beside it (ModuleRegistries' settings
        // window publishes its ids) cannot see the ids this sets.
        const savedPageIds = Shell.settingsPageIds;
        Shell.settingsPageIds = ["general", "network_vpn", "vpt-page"];
        const opened = [];
        const onOpen = pageId => opened.push(pageId);
        Shell.openSettings.connect(onOpen);
        assert(VpnManager.settingsPageOf(_vpn("vpt:one")) === "" && VpnManager.pageOf(_vpn("vpt:one")) === "",
               "settings page: neither declared — no settings page, no framed page (no button)");
        fake.withPage = true;
        assert(VpnManager.settingsPageOf(_vpn("vpt:one")) === "" && VpnManager.pageOf(_vpn("vpt:one")).endsWith("/tests/FakeVpnProviderPage.qml"),
               "settings page: a page but no settingsPage — the framed page");
        assert(!VpnManager.openSettingsPageOf(_vpn("vpt:one")) && opened.length === 0, "… Settings… does not navigate (the card opens the frame)");
        fake.settingsPage = "vpt-page";
        assertEqual(VpnManager.settingsPageOf(_vpn("vpt:one")), "vpt-page", "settings page: declared and in the window's list — that page");
        assertEqual(VpnManager.pageOf(_vpn("vpt:one")), "", "… and no framed copy of it");
        assert(VpnManager.openSettingsPageOf(_vpn("vpt:one")) && opened.join(",") === "vpt-page",
               "… Settings… goes there through Shell.openSettings (Api.openSettings' path): " + opened.join(","));
        fake.settingsPage = "vpt-nowhere";
        assert(VpnManager.settingsPageOf(_vpn("vpt:one")) === "" && VpnManager.pageOf(_vpn("vpt:one")).endsWith("/tests/FakeVpnProviderPage.qml"),
               "settings page: an id the window does not have — falls back to the framed page");
        assert(!VpnManager.openSettingsPageOf(_vpn("vpt:one")) && opened.length === 1, "… and does not navigate");
        fake.withPage = false;
        assertEqual(VpnManager.pageOf(_vpn("vpt:one")), "", "… nor a page: nothing");
        fake.settingsPage = "vpt-page";
        Shell.settingsPageIds = ["general"];
        assertEqual(VpnManager.settingsPageOf(_vpn("vpt:one")), "", "settings page: the page left the window's list (its module off) — not offered");
        assertEqual(VpnManager.settingsPageOf({ uuid: "u", type: "wireguard" }), "", "settings page: none for NetworkManager's");
        Shell.openSettings.disconnect(onOpen);
        fake.settingsPage = "";
        Shell.settingsPageIds = savedPageIds;

        // The kill switch does not take provider VPNs in
        assert(VpnLockdown.vpnInterfaces.indexOf("fake0") < 0 && JSON.stringify(VpnManager.nmDetails).indexOf("vpt:") < 0,
               "lockdown: the provider's interface and details never reach the blocking");
        assertEqual(VpnLockdown.noteFor({ uuid: "u", type: "wireguard", state: "activated" }), "", "lockdown note: none for NetworkManager's");

        // Hostile providers: properties that throw, a connect that throws
        const thrower = { providerId: "vpt-thrower" };
        Object.defineProperty(thrower, "entries", { get: () => { throw new Error("boom"); } });
        assert(VpnManager.registerProvider(thrower), "hostile: a plain object of the shape registers");
        assert((VpnManager.providerProblems["vpt-thrower"] ?? []).join(" ").indexOf("threw") >= 0 && _vpn("vpt:one") !== null,
               "hostile: entries that throw — none of its shown, reported, the others unaffected");
        VpnManager.unregisterProvider("vpt-thrower");
        const breaking = { providerId: "vpt-breaking", entries: [{ id: "b", name: "B", state: "" }], connect: () => { throw new Error("no"); } };
        VpnManager.registerProvider(breaking);
        VpnManager.connect("vpt-breaking:b");
        assert(VpnManager.lastProviderNotice.title === "Connecting B failed" && VpnManager.lastProviderNotice.body.indexOf("no") >= 0,
               "hostile: a connect that throws — logged and said as a failure");
        VpnManager.unregisterProvider("vpt-breaking");
        assert(_vpn("vpt-breaking:b") === null, "hostile: unregistered — gone");

        // Unregistering while connected: its VPN leaves the list
        fake.setState("two", "activated");
        const second = _fake({ providerId: "vpt-second" });
        second.add("s", "S");
        second.setState("s", "activated");
        assert(_vpn("vpt-second:s") !== null, "unregister: registered");
        VpnManager.unregisterProvider("vpt-second", second);
        assert(_vpn("vpt-second:s") === null && _vpn("vpt:two") !== null, "unregister: its VPN gone while connected, the others stay");
        second.destroy();
        twin.destroy();

        // Loaded as the shell loads it with H2S_FAKE_VPN_PROVIDER=1: by a file URL — it
        // reaches the same VpnManager
        const byUrl = Qt.createComponent(VpnManager.fakeProviderUrl);
        const loaded = byUrl.status === Component.Ready ? byUrl.createObject(suite, { providerId: "vpt-byurl" }) : null;
        assert(loaded !== null && loaded.registered, "by URL: the stand-in loads by its file URL and registers");
        if (loaded !== null) {
            loaded.add("u", "U");
            assert(_vpn("vpt-byurl:u") !== null, "by URL: the same VpnManager sees its entries");
            VpnManager.unregisterProvider("vpt-byurl", loaded);
            loaded.destroy();
        }
        assert(VpnManager._fakeProvider === null, "by URL: without H2S_FAKE_VPN_PROVIDER nothing is loaded by itself");
    }

    property var _section: null
    property var _card: null

    function _make(file, properties, parent) {
        const component = Qt.createComponent(file);
        if (component.status !== Component.Ready) {
            fail(file + " does not compile: " + component.errorString());
            return null;
        }
        return component.createObject(parent ?? null, properties);
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

    property var _frame: null
    property var _holder: null
    property var _rowOne: null
    property var _extrasOne: null
    property int _contextSets: 0

    // The popup's row of a VPN and its extras' Loader
    function _row(id) {
        let found = null;
        const walk = node => {
            if (!node || found !== null)
                return;
            if (node.modelData !== undefined && node.modelData?.uuid === id && node.lockdownNote !== undefined) {
                found = node;
                return;
            }
            for (const child of node.children ?? [])
                walk(child);
        };
        walk(_section);
        return found;
    }

    // The first item under `item` (itself included) with that objectName, or null
    function _named(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (const child of item.children ?? []) {
            const found = _named(child, name);
            if (found !== null)
                return found;
        }
        return null;
    }

    function _extrasOf(row) {
        let found = null;
        const walk = node => {
            if (!node || found !== null)
                return;
            if (node.slot !== undefined && node.extra !== undefined && node.item !== undefined) {
                found = node;
                return;
            }
            for (const child of node.children ?? [])
                walk(child);
        };
        walk(row);
        return found;
    }

    // The parts that need the event loop: each step waits for its condition (`until`)
    property var _steps: [
        { until: () => suite._vpn("vpt-api:one") === null, run: () => {
            assert(suite._vpn("vpt-api:one") === null && VpnManager.providerOf("vpt-api:one") === null, "destroyed: the provider made from qs.api left with its VPN");
        } },
        { run: () => {
            assert(suite._vpn("vpt:one") !== null, "destroyed: the refused twin going away leaves the registered one");
            suite._fakeOne.slowMs = 20;
            VpnManager.connect("vpt:two");
        } },
        { until: () => suite._vpn("vpt:two").state === "activated" && !VpnManager.busyFor(suite._vpn("vpt:two")), run: () => {
            assert(suite._vpn("vpt:two").state === "activated" && !VpnManager.busyFor(suite._vpn("vpt:two")),
                   "slow: the operation finished on its own time");
            // The views built with a provider's VPNs (a binding error would print a TypeError,
            // which fails the run): the popup's section, a card, a provider's page in its frame
            suite._fakeOne.slowMs = 0;
            suite._fakeOne.withExtras = true;
            suite._fakeOne.withPage = true;
            suite._fakeOne.canChange = false;
            suite._fakeOne.setAttention("one", "Log in to continue", "Log in");
            suite._fakeOne.setStatus("one", "Via exit-1");
            suite._section = suite._make("../panels/network/VpnSection.qml", { width: 300 });
            suite._card = suite._make("../panels/settings/NetworkProfileCard.qml", { width: 300, external: true, editable: false,
                deletable: false, profile: suite._vpn("vpt:two"), notice: "A note", noticeAction: "Do it", need: "auth" });
            // In a holder, as on the VPN page (anchored in an item)
            suite._holder = Qt.createQmlObject("import QtQuick; Item { width: 300; height: 400 }", suite);
            suite._frame = suite._make("../panels/settings/VpnProviderPageFrame.qml", { width: 300, height: 400, vpnId: "vpt:one" }, suite._holder);
            // The owner's part: Back, close() or the VPN gone clear the id
            suite._frame.closed.connect(() => suite._frame.vpnId = "");
        } },
        { until: () => suite._texts(suite._section).some(text => text.indexOf("Fake row extras for one") === 0) && suite._frame.shown, run: () => {
            const texts = suite._texts(suite._section);
            assert(texts.includes("One") && texts.includes("Two") && texts.includes("Log in to continue") && texts.includes("Log in"),
                   "views: the popup's rows, the attention line and its action");
            assert(texts.some(text => text.indexOf("Fake row extras for one") === 0), "views: the row's extras, given their context");
            assert(texts.includes("Via exit-1"), "views: the entry's status line on its row");
            // Two lines with a status: the name, the status under it; one line, as tall as
            // before (36, a NetworkManager VPN's row: the same delegate, no status), without
            const rowWith = suite._named(suite._row("vpt:one"), "vpnRow");
            const nameWith = suite._named(rowWith, "vpnName");
            const statusWith = suite._named(rowWith, "vpnStatus");
            assert(nameWith !== null && statusWith !== null && nameWith.text === "One" && statusWith.text === "Via exit-1" && statusWith.visible,
                   "row: the name and the status, two Text items");
            // In no window nothing polishes: lay the two lines out as a shown popup does
            nameWith.parent.forceLayout();
            suite._named(suite._row("vpt:two"), "vpnName").parent.forceLayout();
            assert(statusWith.mapToItem(rowWith, 0, 0).y >= nameWith.mapToItem(rowWith, 0, nameWith.height).y && statusWith.x === nameWith.x,
                   "row: the status under the name, aligned with it");
            assert(statusWith.elide === Text.ElideRight && statusWith.maximumLineCount === 1, "row: a long status elides, never wraps");
            const rowWithout = suite._named(suite._row("vpt:two"), "vpnRow");
            assert(rowWithout !== null && !suite._named(rowWithout, "vpnStatus").visible, "row: no status — no second line");
            assertEqual(rowWithout.height, 36, "row: no status — the one-line height it always had");
            assert(rowWith.height > rowWithout.height && rowWith.height >= nameWith.height + statusWith.height,
                   "row: with a status — taller, holding both lines (" + rowWith.height + ")");
            assert(suite._texts(suite._card).includes("A note") && suite._texts(suite._card).includes("Disconnect"),
                   "views: a provider's card — its notice, its button");
            // Its "Settings…", opened: a button (SmallButton) under the primary one, on its
            // right edge; the text block stops short of the buttons
            const card = suite._card;
            const primary = suite._named(card, "profilePrimary");
            const settings = suite._named(card, "profileSettings");
            assert(primary !== null && settings !== null && !settings.visible, "card: closed — no Settings…");
            let settingsAsked = 0;
            card.settingsRequested.connect(() => settingsAsked++);
            card.hasSettings = true;
            card.open = true;
            assert(settings.visible && settings.label === "Settings…" && settings.kind === "normal" && typeof settings.clicked === "function"
                   && settings.radius === Theme.button.radius, "card: opened — Settings… is a SmallButton (the shell's normal button)");
            assert(!suite._named(card, "profileEdit").visible && !suite._named(card, "profileForget").visible,
                   "card: external — no Edit connection…, no Forget");
            settings.clicked();
            assertEqual(settingsAsked, 1, "card: Settings… emits settingsRequested");
            // Where it sits, by structure — in no window nothing polishes, so the geometry
            // is checked on screen (the Tailscale module's lock-bed test): the primary
            // button's slot and Settings… in one column right of the text block, Settings…
            // after the slot and right-aligned, the primary anchored right in its slot
            const actions = settings.parent;
            const slot = primary.parent.parent;
            const stack = Array.from(actions.children);
            assert(slot.parent === actions && stack.indexOf(slot) >= 0 && stack.indexOf(slot) < stack.indexOf(settings),
                   "card: Settings… in the primary button's column, under it");
            assert((settings.Layout.alignment & Qt.AlignRight) && (slot.Layout.alignment & Qt.AlignRight)
                   && primary.parent.anchors.right === slot.right, "card: Settings… on the primary button's right edge");
            const header = actions.parent;
            const titleBlock = Array.from(header.children).find(child => child !== actions && child.Layout.fillWidth);
            assert(titleBlock !== undefined && Array.from(header.children).indexOf(titleBlock) < Array.from(header.children).indexOf(actions),
                   "card: the text block on the left, filling the rest (it elides, never runs under the buttons)");
            assert(card.color !== Theme.surface, "card: opened, not Theme.surface — its buttons (Theme.surface) stay visible as buttons");
            // Busy, or no primary button at all: the slot keeps its height, Settings… stays put
            const slotHeight = slot.implicitHeight;
            card.busy = true;
            assertEqual(slot.implicitHeight, slotHeight, "card: busy — the primary's slot keeps its height (Settings… does not move)");
            card.busy = false;
            card.canUse = false;
            card.profile = Object.assign({}, card.profile, { active: false });
            assert(!primary.visible && slot.implicitHeight === slotHeight, "card: no primary button — its slot keeps the text block's height");
            card.profile = suite._vpn("vpt:two");
            card.canUse = true;
            card.open = false;
            // A NetworkManager profile's (Wi-Fi, Ethernet, a VPN of its own): Edit connection…
            // and Forget, buttons in the same column, under the primary one
            const own = suite._make("../panels/settings/NetworkProfileCard.qml", { width: 300, open: true,
                profile: { uuid: "x", name: "Home", active: false, autoconnect: false, priority: 0, device: "" } });
            const edit = suite._named(own, "profileEdit");
            const forget = suite._named(own, "profileForget");
            const ownStack = Array.from(edit.parent.children);
            assert(edit.visible && forget.visible && !suite._named(own, "profileSettings").visible && forget.parent === edit.parent
                   && ownStack.indexOf(suite._named(own, "profilePrimary").parent.parent) < ownStack.indexOf(edit)
                   && ownStack.indexOf(edit) < ownStack.indexOf(forget) && (forget.Layout.alignment & Qt.AlignRight),
                   "card: a NetworkManager profile — Edit connection… then Forget, right-aligned under the primary");
            own.destroy();
            suite._rowOne = suite._row("vpt:one");
            suite._extrasOne = suite._extrasOf(suite._rowOne);
            assert(suite._extrasOne?.item?.context?.provider === suite._fakeOne, "views: the row's extras get the provider object in their context");
            // The page in the core's frame: title, Back, the page with its context
            assert(suite._frame.shown && suite._frame.title === "Fake VPN · One" && suite._texts(suite._frame).includes("‹ Back"),
                   "page: in the core's frame — its title and Back (" + suite._frame.title + ")");
            assert(suite._texts(suite._frame).includes("Fake page for one of vpt") && typeof suite._frame.page?.context?.close === "function",
                   "page: the provider's page given its context (provider, close): " + JSON.stringify(suite._texts(suite._frame)));
            // Another entry changes; this row's extras are not poked (the probe's P2)
            suite._extrasOne.item.contextChanged.connect(() => suite._contextSets++);
            suite._fakeOne.entries = suite._fakeOne.entries.slice();
            suite._fakeOne.setStatus("two", "Tailnet only");
        } },
        { until: () => suite._texts(suite._section).includes("Tailnet only"), run: () => {
            assertEqual(suite._contextSets, 0, "extras: a re-read that changed another entry does not reassign this one's context");
            assert(suite._row("vpt:one") === suite._rowOne, "rows: the same row after a re-read");
            // A provider's words are shown as they are, never read as markup
            suite._fakeOne.setStatus("two", "a <b>b</b> <address>");
            // The list reorders: one up (first), two down
            suite._fakeOne.setState("two", "");
            suite._fakeOne.setState("one", "activated");
        } },
        { until: () => VpnManager.vpns.findIndex(vpn => vpn.uuid === "vpt:one") < VpnManager.vpns.findIndex(vpn => vpn.uuid === "vpt:two")
                       && suite._contextSets > 0, run: () => {
            const markupStatus = suite._named(suite._row("vpt:two"), "vpnStatus");
            assert(markupStatus !== null && markupStatus.text === "a <b>b</b> <address>" && markupStatus.textFormat === Text.PlainText
                   && suite._named(suite._row("vpt:two"), "vpnName").textFormat === Text.PlainText,
                   "row: a status that looks like markup shown verbatim, as plain text");
            const row = suite._row("vpt:one");
            assert(row === suite._rowOne && suite._extrasOf(row)?.item === suite._extrasOne.item,
                   "rows: the list reordered — the same row and the same extras (an open chooser is not torn down)");
            // The page closes when its VPN goes, and does not reopen when it comes back
            suite._fakeOne.remove("one");
        } },
        { until: () => suite._frame.vpnId === "", run: () => {
            assert(!suite._frame.shown, "page: its VPN gone — closed");
            suite._fakeOne.add("one", "One");
        } },
        { until: () => suite._vpn("vpt:one") !== null, run: () => {
            assert(!suite._frame.shown && suite._frame.vpnId === "", "page: the VPN back — the page does not reopen by itself");
            suite._card.destroy();
            suite._holder.destroy();
            suite._fakeOne.destroy();
        } },
        { until: () => VpnManager.vpns.every(vpn => vpn.provider !== "vpt") && suite._row("vpt:one") === null && suite._row("vpt:two") === null, run: () => {
            assert(VpnManager.vpns.every(vpn => vpn.provider !== "vpt") && VpnManager.providerVpns.length === 0,
                   "destroyed while registered (a module disabled): its VPNs gone, nothing else breaks");
            assert(VpnManager.vpns === VpnManager.nmVpns && VpnManager.details === VpnManager.nmDetails,
                   "destroyed: no provider left — NetworkManager's lists as they were");
            // The provider went while its row's extras were on screen (the probe's P3)
            assert(suite._row("vpt:one") === null && suite._row("vpt:two") === null, "destroyed: the popup's rows of its VPNs gone with it");
            suite._section.destroy();
        } }
    ]
}
