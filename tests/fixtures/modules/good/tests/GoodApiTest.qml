import QtQuick
import qs.api
import qs.tests
import ".."

// The module API from a module's side (tests/run-modules.sh): only qs.api (and the shell's
// TestCase) — its handle, its settings, facts, store, the theme, the slot table, commands
// through the API's helpers against stand-in programs (tests/stand-in.sh, and its pkexec in
// tests/programs — the manifest's testPrograms), and module test mode as a module's suites see
// it (Api.testMode, its stand-ins, what openUrl and notify record, the file chooser's calls
// and answers: ModuleTestKit)
TestCase {
    id: suite
    suiteName: "good: the module API"
    asynchronous: true

    readonly property var module: Api.moduleAt(Qt.resolvedUrl("."))
    property var _steps: []

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite.finish();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {}
            if (!ready && waited < 8000)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    property CommandAction action: CommandAction {}
    property PrivilegedAction admin: PrivilegedAction {
        notifyFailures: false
    }
    property PrivilegedAction outsider: PrivilegedAction {
        notifyFailures: false
    }
    property CommandQuery query: CommandQuery {
        onDone: lines => suite._queried = lines
    }
    property var _queried: null
    property CommandRunner runner: CommandRunner {}
    property CommandRunner dataRunner: CommandRunner {}
    property var _dataMode: null
    property var _ran: null
    property var _ranLines: []
    property var _results: ({})
    // What module.chooseFiles answered (API 1.17), in order; the call left open when the
    // module is turned off, and the busy one
    property var _chosen: []
    property var _afterOff: null
    // A progress notification left open when the module is turned off (API 1.33)
    property var _leftOpen: null
    property var _leftOpenNumber: 0
    property var _busy: null

    // The store is read by a process (API 1.2): everything starts once it has answered
    function runAsync() {
        _then("the store is read", () => module?.store?.ready === true, () => _run());
        _clock.start();
    }

    function _run() {
        const standIn = module.directory + "/tests/stand-in.sh";
        assert(Math.abs(Date.now() - Api.minuteNow) < 61000, "the runner reset the clock GoodState left set (ModuleTestKit.setNow)");
        assert(!ModuleTestKit.chooserOpen, "… and dropped the file chooser GoodState left open");
        // --- the handle ---
        assert(module !== null, "Api.moduleAt(Qt.resolvedUrl(\".\")) finds the module's handle from any of its files");
        assertEqual(module?.moduleId + " " + module?.version + " " + module?.name, "good 1.2.3 Good fixture", "id, version, name");
        assert(module.active, "active while loaded");
        assertEqual(module.url("tests/x.qml"), "file://" + module.directory + "/tests/x.qml", "url(): a file of the module");
        assertEqual(module.manifest.widgets[0].type, "good", "its manifest, as read");
        try {
            module.manifest.id = "evil";
        } catch (error) {}
        assertEqual(module.manifest.id, "good", "… frozen: writing does nothing");
        // (1.15) its main object, shared with every view of the module
        assert(module.main !== null && module.main.module === module && module.main.goodState === GoodState,
               "module.main: its main object, given this handle");
        try {
            module.main = null;
        } catch (error) {}
        assert(module.main !== null, "… read-only");
        assertEqual(Api.moduleAt("file:///etc/passwd"), null, "a file of no module: no handle");
        // (1.19) A module's plain state, as another module sees it
        const own = Api.moduleStatus("good");
        assertEqual(JSON.stringify(own), JSON.stringify({ id: "good", name: "Good fixture", version: "1.2.3", state: "loaded", active: true }),
                    "Api.moduleStatus(id): id, name, version, state, active");
        assert(Object.isFrozen(own), "… frozen");
        assertEqual(Api.moduleStatus("no-such-module"), null, "… null for an unknown id");
        assertEqual(Api.moduleStatus(null), null, "… and for no id");

        // --- API version and slot table ---
        assertEqual(Api.version, "1.33", "Api.version");
        // (1.26) Its icon, as the shell draws it
        assertEqual(JSON.stringify(module.icon), JSON.stringify({ kind: "svg", glyph: "", url: Qt.resolvedUrl("../icon.svg").toString(), colors: "theme" }),
                    "module.icon: its SVG, by its file's URL, painted in the theme's colour");
        try {
            module.icon = null;
        } catch (error) {}
        assert(module.icon !== null && Object.isFrozen(module.icon), "… read-only, frozen");

        // --- module test mode (API 1.10): tests/run-modules.sh runs its suites in it ---
        assert(Api.testMode === true && ModuleTestKit.testMode, "Api.testMode: true under the module test runner");
        try {
            Api.testMode = false;
        } catch (error) {}
        assert(Api.testMode, "… read-only");
        assertEqual(ModuleTestKit.status("good")?.deprecations.length, 0, "a 1.10 module: no test-mode gate in its deprecations");
        // Its programs (API 1.9): pkexec, from its testPrograms in test mode, never from PATH
        assertEqual(JSON.stringify(module.programs),
                    JSON.stringify({ pkexec: { path: module.directory + "/tests/programs/pkexec", trusted: true, reason: "test stand-in" } }),
                    "programs: pkexec is the stand-in in its testPrograms, trusted as one");
        assert(module.programsReady && Object.isFrozen(module.programs), "… ready, frozen");
        assertEqual(ModuleTestKit.status("good")?.state, "loaded", "ModuleTestKit.status(id)");
        assertEqual(ModuleTestKit.status("no-such-module"), null, "… null for no module");
        assert(ModuleTestKit.widgetEntries.some(entry => entry.module === "good" && entry.type === "good"), "ModuleTestKit.widgetEntries: its widget");
        // Links and notifications: recorded, nothing opened or sent
        ModuleTestKit.clearRecords();
        assert(Api.openUrl("https://example.org/a b"), "openUrl in test mode: true");
        assert(!Api.openUrl("javascript:alert(1)"), "… a link it refuses is still refused");
        assert(Api.openUrl("file:///tmp", { allowFile: true }), "… a file: link when allowed");
        assertEqual(JSON.stringify(ModuleTestKit.opened),
                    JSON.stringify([{ url: "https://example.org/a b", allowFile: false }, { url: "file:///tmp", allowFile: true }]),
                    "ModuleTestKit.opened: what would have been opened, in order");
        Api.notify("From the API", { body: "a body", urgency: "low" });
        module.notify("From the handle", { actions: [{ id: "go", label: "Go", onTriggered: () => suite.fail("a recorded notification's action ran") }] });
        const notified = ModuleTestKit.notified;
        assertEqual(notified.map(entry => entry.summary + "|" + entry.body + "|" + entry.appName + "|" + entry.urgency).join(","),
                    "From the API|a body|H2S Shell|low,From the handle||Good fixture|", "ModuleTestKit.notified: both, with the module's name on the handle's");
        assertEqual(JSON.stringify(notified[1]?.actions), "[\"Go\"]", "… its actions' labels");
        assertEqual(notified[0]?.command?.[0], "notify-send", "… and the words notify-send would have had");
        ModuleTestKit.clearRecords();
        assertEqual(ModuleTestKit.opened.length + ModuleTestKit.notified.length, 0, "clearRecords()");
        // (1.12) format "plain": a peer's or a file's name as written, never markup
        module.notify("File <b>received</b>", { body: "a&b <i>.txt\nc.txt", format: "plain" });
        Api.notify("Line\nbreak", { body: "<", format: "plain" });
        const plain = ModuleTestKit.notified;
        assertEqual(plain.map(entry => entry.summary + "|" + entry.body + "|" + entry.appName + "|" + entry.format).join(","),
                    "File <b>received</b>|a&amp;b &lt;i&gt;.txt\nc.txt|Good fixture|plain,Line break|&lt;|H2S Shell|plain",
                    "notify, format plain: the summary one line, (1.28) the body keeping its line break, its &, < and > as entities, the summary as written");
        assertEqual(JSON.stringify(plain[0]?.command?.slice(-3)), JSON.stringify(["--", "File <b>received</b>", "a&amp;b &lt;i&gt;.txt\nc.txt"]),
                    "… and so to notify-send");
        ModuleTestKit.clearRecords();
        // A module's notification never takes the shell's own toast (category x-qs-shell)
        module.notify("Looks like the shell", { category: "x-qs-shell" });
        Api.notify("So does this", { hints: { category: "x-qs-shell" } });
        assert(ModuleTestKit.notified.length === 2 && !ModuleTestKit.notified.some(entry => entry.command.some(word => word.includes("x-qs-shell"))),
               "notify: the category x-qs-shell dropped, as an option and as a hint");
        ModuleTestKit.clearRecords();
        // (1.33) Every x-qs- hint key dropped, in a plain notification too
        module.notify("Hinted", { hints: { "x-qs-announce": "3", "\u0000x-qs-progress-state": "done", "x-other": "kept" } });
        const hinted = ModuleTestKit.notified[0]?.command ?? [];
        assert(!hinted.some(word => /x-qs-/i.test(word)) && hinted.includes("--hint=string:x-other:kept"),
               "notify: x-qs- hint keys dropped, another kept: " + JSON.stringify(hinted));
        ModuleTestKit.clearRecords();

        // --- a progress notification (API 1.33): notify returns its handle ---
        const handleRecords = number => ModuleTestKit.notified.filter(entry => entry.handle === number);
        const lastShown = () => ModuleTestKit.notified.filter(entry => entry.kind === "show").slice(-1)[0]?.handle;
        let pressed = 0;
        let dismissed = 0;
        const job = module.notify("Copying a.txt", {
            body: "to <backup>", format: "plain", progress: 0, toast: "whileRunning", expireTime: 3000,
            hints: { "x-qs-announce": "7" },
            actions: [{ id: "stop", label: "Stop", onTriggered: () => pressed++ }], onDismissed: () => dismissed++
        });
        assertEqual(module.notify("Plain", { body: "no progress" }), null, "notify without progress: null");
        assert(job !== null && job.open && job.state === "running", "notify with progress: a handle, open, running (the server answers at once in test mode)");
        assertEqual(job.id + "|" + job.wanted + "|" + job.runner, "undefined|undefined|undefined", "… nothing of how it is sent");
        const jobNumber = lastShown();
        const shown = handleRecords(jobNumber)[0];
        assertEqual(JSON.stringify([shown?.kind, shown?.summary, shown?.body, shown?.progress, shown?.state, shown?.toast, shown?.expireTime, shown?.announce, shown?.actions]),
                    JSON.stringify(["show", "Copying a.txt", "to &lt;backup&gt;", 0, "running", "whileRunning", 0, 0, ["Stop"]]),
                    "its show recorded: plain texts, whileRunning (its toast stays: 0, the module's expireTime not used), its action, no announce (the module's x-qs-announce dropped)");
        assert(job.update({ progress: 40 }), "update(): taken");
        assert(job.update({ summary: "Copying b.txt", announce: true }), "update() with announce: taken");
        const updates = handleRecords(jobNumber).filter(entry => entry.kind === "update");
        assertEqual(updates.map(entry => entry.progress + "|" + entry.summary + "|" + entry.announce).join(","), "40|Copying a.txt|0,40|Copying b.txt|1",
                    "… each update recorded: the progress, then the text with the announce count raised");
        assertEqual(ModuleTestKit.pressNotificationAction(jobNumber, "stop"), "", "ModuleTestKit.pressNotificationAction");
        assertEqual(pressed + "|" + job.open + "|" + dismissed, "1|true|0", "… its onTriggered ran, the notification stays (resident)");
        assert(ModuleTestKit.pressNotificationAction(jobNumber, "other") !== "", "… an action it does not have: refused");
        assert(job.update({ state: "done", summary: "Copied", actions: [], announce: true }), "update() to done: taken");
        const ended = handleRecords(jobNumber).slice(-1)[0];
        assertEqual([job.state, job.open, ended?.state, ended?.expireTime, ended?.announce, ended?.actions.length].join("|"), "done|true|done|-1|2|0",
                    "done: still open, its toast takes the user's time (-1), announced");
        assert(!job.update({ progress: 50 }), "after an end state update() is refused");
        job.close();
        assertEqual([job.state, job.open, dismissed, handleRecords(jobNumber).slice(-1)[0]?.kind].join("|"), "closed|false|0|close",
                    "close(): closed, recorded, no onDismissed");
        assert(ModuleTestKit.dismissNotification(jobNumber) !== "", "a closed one cannot be dismissed");
        // Dismissed by the user (through the kit), a bad toast taken as "brief"
        let secondDismissed = 0;
        const second = module.notify("Syncing", { progress: -1, toast: "forever", onDismissed: () => secondDismissed++ });
        const secondNumber = lastShown();
        assertEqual(handleRecords(secondNumber)[0]?.toast + "|" + handleRecords(secondNumber)[0]?.expireTime + "|" + handleRecords(secondNumber)[0]?.progress,
                    "brief|-1|-1", "a bad toast → brief (the user's time), a run of unknown length");
        assertEqual(ModuleTestKit.dismissNotification(secondNumber), "", "ModuleTestKit.dismissNotification");
        assertEqual([second.state, second.open, secondDismissed].join("|"), "closed|false|1", "… closed, its onDismissed once");
        const afterDismissal = ModuleTestKit.notified.length;
        assert(!second.update({ progress: 10 }), "… a later update refused");
        assertEqual(ModuleTestKit.notified.length, afterDismissal, "… and nothing recorded");
        assert(ModuleTestKit.dismissNotification(9999999) !== "" && ModuleTestKit.pressNotificationAction("x", "stop") !== "", "the kit: no such notification, refused");
        // Through Api.notify too (no module: not closed with one)
        const fromApi = Api.notify("From the API", { progress: 5 });
        assert(fromApi !== null && fromApi.open, "Api.notify with progress: a handle");
        fromApi.close();
        // Left open: closed when the module is turned off (below)
        _leftOpen = module.notify("Left open", { progress: 1 });
        _leftOpenNumber = lastShown();
        assert(_leftOpen.open, "a handle left open");
        ModuleTestKit.clearRecords();

        // --- helpers (API 1.12) ---
        assertEqual([Api.format.bytes(1610612736), Api.format.bytes(3 * 1099511627776), Api.format.rate(12.4 * 1024)].join(","), "1.5 GB,3.0 TB,12 KB/s",
                    "Api.format: bytes, terabytes, rate");
        const formatAgo = Api.format.ago;
        assertEqual(formatAgo(1731400000000 - 5 * 60000, 1731400000000) + "|" + formatAgo(0, 1731400000000), "5 min ago|never", "Api.format.ago: milliseconds, passed around");
        assert(Object.isFrozen(Api.format) && Object.isFrozen(Api.address), "Api.format and Api.address: frozen");
        assert(Api.address.isIpv4("100.64.0.4") && Api.address.isIpv6("fd7a:115c:a1e0::4") && Api.address.isIp("::1") && !Api.address.isIp("01.2.3.4"),
               "Api.address: isIpv4, isIpv6, isIp");
        assertEqual(Api.address.parseCidr("fd00:99:0:0::1/64")?.network, "fd00:99::/64", "Api.address.parseCidr");
        assert(Api.address.contains("100.64.0.0/10", "100.101.102.103") && Api.address.overlap("10.0.0.0/8", Api.address.parseCidr("10.1.0.0/16")),
               "Api.address: contains, overlap");
        assertEqual(Api.address.redact("peer 100.64.0.4 at fd7a::4."), "peer [address] at [address].", "Api.address.redact");
        assert(Api.minuteNow % 60000 === 0 && Math.abs(Date.now() - Api.minuteNow) < 61000, "Api.minuteNow: the start of this minute: " + Api.minuteNow);
        ModuleTestKit.setNow(1731400012345);
        assertEqual(Api.minuteNow, 1731399960000, "ModuleTestKit.setNow: Api.minuteNow follows, at the minute's start");
        ModuleTestKit.setNow(0);
        assert(Math.abs(Date.now() - Api.minuteNow) < 61000, "… setNow(0): the real clock again");
        ModuleTestKit.setNow(1731400012345);
        ModuleTestKit.clearRecords();
        assert(Math.abs(Date.now() - Api.minuteNow) < 61000, "… clearRecords(): the real clock again");
        assert(module.log("info", "good: logged once", "good-key") && !module.log("info", "good: logged once", "good-key"), "module.log: once per text for a key");

        // --- system facts and the data directory (API 1.13) ---
        const facts = Api.system;
        const home = ModuleTestKit.dataHome.replace(/\/\.local\/share$/, "");
        assert(home !== "" && ModuleTestKit.dataHome.endsWith("/.local/share"), "ModuleTestKit.dataHome: below the host's temporary home: " + ModuleTestKit.dataHome);
        assertEqual([facts.ready, facts.userName, facts.uid, facts.hostName].join(" "), "true tester 1000 test-host", "Api.system in test mode: the made-up defaults");
        assertEqual([facts.home, facts.configHome, facts.dataHome, facts.runtimeDirectory, facts.downloadDirectory].join(" "),
                    [home, home + "/.config", home + "/.local/share", home + "/run", home + "/Downloads"].join(" "),
                    "… its directories below the temporary home, never the user's");
        assertEqual(JSON.stringify(facts.readIpForwarding()), "{\"ipv4\":false,\"ipv6\":false}", "… readIpForwarding(): off, off");
        assert(Object.isFrozen(facts) && Object.isFrozen(facts.readIpForwarding()), "… frozen, and what readIpForwarding() returns");
        assertEqual(module.dataDirectory, ModuleTestKit.dataHome + "/h2s-shell/module-data/good", "module.dataDirectory: <dataHome>/h2s-shell/module-data/<id>");
        assertEqual(JSON.stringify(ModuleTestKit.setSystem({ userName: "carol", uid: 0, hostName: "", dataHome: "/home/carol/.local/share",
                                                             ipForwarding: { ipv4: true, ipv6: null } })), "[]", "setSystem: every field taken");
        assertEqual([Api.system.userName, Api.system.uid, "[" + Api.system.hostName + "]", Api.system.dataHome].join(" "), "carol 0 [] /home/carol/.local/share",
                    "… Api.system follows (a new object), \"\" for a fact not known");
        assert(Api.system !== facts && facts.userName === "tester", "… the object read before is unchanged");
        assertEqual(JSON.stringify(Api.system.readIpForwarding()), "{\"ipv4\":true,\"ipv6\":null}", "… readIpForwarding(): as set, null for not readable");
        assertEqual(module.dataDirectory, ModuleTestKit.dataHome + "/h2s-shell/module-data/good", "… module.dataDirectory does not move");
        const problems = ModuleTestKit.setSystem({ uid: "0", home: "relative", colour: "red" });
        assertEqual(problems.map(problem => problem.split(":")[0]).join(","), "uid,home,colour", "setSystem: the wrong fields named: " + problems.join("; "));
        assertEqual(Api.system.uid + " " + Api.system.userName, "1000 tester", "… left out; each call starts from the defaults");
        Api.system.refresh();
        assertEqual(Api.system.userName, "tester", "refresh() in test mode: nothing read");
        ModuleTestKit.setSystem({ userName: "dave" });
        ModuleTestKit.clearRecords();
        assertEqual(Api.system.userName, "tester", "clearRecords(): the default facts again");
        dataRunner.start(["stat", "-c", "%a %U", module.dataDirectory], { done: result => suite._dataMode = result });

        // --- network facts (API 1.16): in test mode the test kit's, never NetworkManager's ---
        assertEqual([Api.networksReady, Api.networks.length, Api.localNetworksReady, Api.localNetworks.length, Api.vpnsUp.length].join(" "),
                    "true 0 true 0 0", "network facts in test mode: the defaults — read, no network, no VPN");
        assertEqual(JSON.stringify(ModuleTestKit.setNetworks({
            networks: [{ id: "u-home", name: "Home\nWi-Fi", kind: "wifi", active: true }],
            localNetworks: [{ device: "wlan0", kind: "wifi", address: "192.168.1.23/24" },
                            { device: "wlan0", kind: "wifi", address: "2001:DB8::17/64" }],
            vpnsUp: [{ name: "Office", type: "vpn", fullTunnel: false, setsDns: true, routes: ["10.1.2.3/8"] },
                     { name: "Mesh", type: "provider", provider: "mesh" }]
        })), "[]", "setNetworks: every row taken");
        assertEqual(JSON.stringify(Api.networks), JSON.stringify([{ id: "u-home", name: "Home Wi-Fi", kind: "wifi", active: true }]),
                    "Api.networks follows; a name on one line");
        assertEqual(JSON.stringify(Api.localNetworks), JSON.stringify([
            { device: "wlan0", kind: "wifi", family: 4, address: "192.168.1.23", network: "192.168.1.0/24" },
            { device: "wlan0", kind: "wifi", family: 6, address: "2001:db8::17", network: "2001:db8::/64" }]),
            "Api.localNetworks: family, address and network derived as the shell does");
        assertEqual(JSON.stringify(Api.vpnsUp), JSON.stringify([
            { name: "Office", type: "vpn", provider: "", fullTunnel: false, setsDns: true, routes: ["10.0.0.0/8"] },
            { name: "Mesh", type: "provider", provider: "mesh", fullTunnel: null, setsDns: null, routes: null }]),
            "Api.vpnsUp: fullTunnel, setsDns, routes; not reported is null");
        assert(Object.isFrozen(Api.vpnsUp) && Object.isFrozen(Api.vpnsUp[0]) && Object.isFrozen(Api.vpnsUp[0].routes) && Object.isFrozen(Api.localNetworks[0]),
               "… frozen, the routes too");
        ModuleTestKit.setNetworks({ networksReady: false, localNetworksReady: false });
        assertEqual([Api.networksReady, Api.networks.length, Api.localNetworksReady].join(" "), "false 0 false", "… not read: ready false; each call from the defaults");
        const networkProblems = ModuleTestKit.setNetworks({ localNetworks: [{ device: "lo", kind: "other", address: "127.0.0.1/8" }],
                                                            vpnsUp: [{ name: "X", type: "vpn", fullTunnel: "yes" }], colour: "red" });
        assertEqual(networkProblems.length, 3, "setNetworks: a loopback address, a wrong fullTunnel and an unknown field named: " + networkProblems.join("; "));
        assertEqual(Api.localNetworks.length + " " + Api.vpnsUp[0].fullTunnel, "0 null", "… a loopback address left out, a wrong fullTunnel unknown");
        ModuleTestKit.clearRecords();
        assertEqual([Api.networksReady, Api.vpnsUp.length].join(" "), "true 0", "clearRecords(): the default network facts again");

        // --- its widget's presets (API 1.3) ---
        assertEqual(module.presetValue("good", "", "label"), "G", "presetValue: no preset, the manifest's presetDefaults");
        assertEqual(module.presetValue("clock", "", "format"), undefined, "… the core's types: nothing");
        assert(module.setPresetValue("clock", "Clock", "format", "x") !== "", "setPresetValue: refused for a type not its own");
        assert(module.setPresetValue("good", "", "label", "x") !== "", "… refused without a preset");
        assert(module.setPresetValue("good", "No such preset", "label", "x") !== "", "… refused for a preset that does not exist (it never creates one)");
        assertEqual(module.presetValue("good", "No such preset", "label"), "G", "… nothing written: still the default");
        assert(module.setPresetValue("good", "__proto__", "label", "x") !== "", "… refused for the name __proto__");
        // Writing to a preset the section editor made: tests/ModuleRegistriesTest.qml
        assert(Api.slots.some(slot => slot.name === "network.popup.sections"), "the slot table names the slots offered");

        // --- the theme, read-only ---
        assert(String(Api.theme.accent).startsWith("#"), "a colour token");
        assert(Api.theme.fontFamily !== "" && Api.theme.fontSizeBody > 0, "font family and sizes");
        assert(Api.theme.duration("enter") > 0, "durations");
        let threw = false;
        try {
            Api.theme.fontSizeBody = 99;
        } catch (error) {
            threw = true;
        }
        assert(threw || Api.theme.fontSizeBody !== 99, "a token cannot be written");
        const radius = Api.theme.row.radius;
        try {
            Api.theme.row.radius = 1234;
        } catch (error) {}
        assertEqual(Api.theme.row.radius, radius, "a group is a frozen copy");
        // Deep: nothing nested is the core's own object (API 1.2)
        const nestedOpen = group => Object.keys(group).some(key => {
            const value = group[key];
            return value !== null && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype
                && (!Object.isFrozen(value) || nestedOpen(value));
        });
        for (const name of ["capsule", "popup", "row", "settings", "border"])
            assert(Object.isFrozen(Api.theme[name]) && !nestedOpen(Api.theme[name]), "theme." + name + ": frozen all the way down");
        const easing = Api.theme.curve("enter");
        assert(easing === null || typeof easing !== "object" || Object.isFrozen(easing), "curve(): a frozen copy");

        // --- settings: its own only ---
        assertEqual(module.value("greeting"), "hello", "value(name): its setting's default");
        assertEqual(module.value("mod.good.greeting"), "hello", "value(full key)");
        assertEqual(module.value("mod.key-collision.fine"), undefined, "another module's key: undefined");
        assertEqual(module.value("lockscreen.enabled"), undefined, "a core key: undefined");
        assertEqual(module.settingKey("greeting"), "mod.good.greeting", "settingKey()");
        assert(module.setValue("greeting", 5) !== "", "setValue: a number for a text is refused");
        assert(module.setValue("undeclared", "x") !== "", "setValue: an undeclared key is refused");
        assert(module.setValue("lockscreen.enabled", false) !== "", "setValue: a core key is refused");
        assertEqual(module.setValue("greeting", "hi there"), "", "setValue: written (in the profile in effect)");
        assertEqual(module.value("greeting"), "hi there", "… and read back");
        assertEqual(module.setValue("loud", true), "", "setValue: a global setting");
        assertEqual(module.value("loud"), true, "… read back");
        module.setValue("greeting", "hello");
        module.setValue("loud", false);

        // --- facts ---
        assertEqual(module.facts["good.ready"], true, "the fact its main set");
        assert(module.setFact("level", 150) !== "", "setFact: a percent above 100 refused");
        assert(module.setFact("ready", "yes") !== "", "setFact: a text for a bool refused");
        assert(module.setFact("undeclared", 1) !== "", "setFact: an undeclared fact refused");
        assert(module.setFact("battery.percent", 1) !== "", "setFact: a core fact refused");
        assertEqual(module.setFact("level", 42), "", "setFact: a declared fact");
        assertEqual(module.facts["good.level"], 42, "… there");
        assertEqual(module.setFact("good.level", null), "", "setFact: null — not known");
        assertEqual(module.facts["good.level"], null, "… null");

        // --- its store ---
        assert(module.store.ready, "the store is read");
        assert(module.store.get("starts", 0) >= 1, "the main counted its start in the store");
        assert(module.store.set("token", { value: "abc", expires: 5 }), "set: plain JSON");
        assertEqual(module.store.get("token").value, "abc", "get");
        assertEqual(module.store.get("absent", "fallback"), "fallback", "get: a fallback");
        assert(!module.store.set("huge", "x".repeat(2 * 1024 * 1024)), "set: refused past the size limit");
        assert(module.store.remove("token") && module.store.get("token") === undefined, "remove");

        // --- commands, the shell's way ---
        action.run(["sh", standIn, "a b", "c"], result => suite._results.plain = result);
        action.run(["sh", standIn], result => suite._results.code = result, { STAND_IN_EXIT: "3" });
        // Test mode: the real pkexec is never started — not the default "pkexec", not one on
        // PATH (tests/run-modules.sh puts one there that fails the run), not through the
        // runner either; only its stand-in, module.programs.pkexec
        admin.run(["/bin/sh", standIn, "as root"], "Default pkexec", result => suite._results.defaultElevate = result);
        runner.start(["pkexec", "/bin/true"], { done: result => suite._results.runnerPkexec = result });
        action.run(["/usr/bin/pkexec", "/bin/true"], result => suite._results.actionPkexec = result);
        // … nor handed on to another program: every word of the command is looked at
        runner.start(["env", "pkexec", "/bin/true"], { done: result => suite._results.envPkexec = result });
        runner.start(["timeout", "5", "pkexec", "/bin/true"], { done: result => suite._results.timeoutPkexec = result });
        action.run(["setsid", "/run/wrappers/bin/pkexec", "/bin/true"], result => suite._results.setsidPkexec = result);
        // A 1.10 module is under the strict rule: an elevating program that is not its
        // <testPrograms>/pkexec is refused even when it is no real pkexec — the stand-in that
        // the gate lets an older module use (tests/fixtures/modules/legacy-elevate) is not its
        outsider.elevate = [String(Qt.resolvedUrl("../../../legacy-tools/pkexec")).replace(/^file:\/\//, "")];
        outsider.run(["/bin/sh", standIn, "as root"], "Another elevating program", result => suite._results.outsider = result);
        admin.elevate = [module.programs.pkexec.path];
        admin.run(["/bin/sh", standIn, "as root"], "Running the stand-in", result => suite._results.root = result);
        // The command read once: a word that changes after its first read runs as first read
        const switching = ["/bin/sh", standIn, "as root"];
        let switchReads = 0;
        Object.defineProperty(switching, 2, { get() { return ++switchReads === 1 ? "as root" : "switched"; }, enumerable: true });
        admin.run(switching, "Read once", result => suite._results.readOnce = result);
        admin.run(["/bin/sh", standIn], "Dismissing", result => suite._results.dismissed = result, { FAKE_PKEXEC_EXIT: "126" });
        admin.run(["/bin/sh", standIn], "Refusing", result => suite._results.refused = result, { FAKE_PKEXEC_EXIT: "127" });
        // API 1.2: a program that is not there, or not given by an absolute path, is notFound —
        // never shown as "not authorised" (pkexec would exit 127 for it); pkexec not asked
        admin.run(["/nonexistent/h2s-no-such-program"], "Missing", result => suite._results.missing = result, { FAKE_PKEXEC_EXIT: "127" });
        admin.run(["sh", standIn], "Relative", result => suite._results.relative = result);
        admin.run("not a list", "Nothing", result => suite._results.bad = result);
        query.command = ["sh", standIn, "queried"];
        query.request();
        // API 1.8
        runner.start(["sh", standIn, "one two", "three"], {
            timeoutMs: 5000,
            environment: { STAND_IN_EXIT: "5" },
            onLine: (line, stream) => suite._ranLines.push(stream + ":" + line),
            done: result => suite._ran = result
        });

        // --- the file chooser (API 1.17): in test mode no dialog — the call is recorded and
        // the suite answers it (ModuleTestKit) ---
        ModuleTestKit.clearRecords();
        const chooser = module.chooseFiles({ mode: "openMany", title: "Send\nfiles", startDirectory: "/srv/share/" },
                                           result => suite._chosen = suite._chosen.concat([result]));
        assert(chooser.open && ModuleTestKit.chooserOpen, "chooseFiles: open, waiting for the answer");
        assertEqual(JSON.stringify(ModuleTestKit.chooserCalls),
                    JSON.stringify([{ moduleId: "good", mode: "openMany", title: "Send files", startDirectory: "/srv/share" }]),
                    "ModuleTestKit.chooserCalls: the call as the shell took it — the title on one line, the directory without its /");
        module.chooseFiles({ mode: "folder" }, result => suite._busy = result);
        assertEqual(ModuleTestKit.chooserCalls.length, 1, "… a second call while one is open is not recorded");
        assert(ModuleTestKit.answerChooser("good", ["relative"]) !== "" && ModuleTestKit.chooserOpen, "answerChooser: a relative path refused, still open");
        assertEqual(ModuleTestKit.answerChooser("legacy-elevate", ["/srv/share/c"]), "the open chooser is module \"good\"'s, not \"legacy-elevate\"",
                    "answerChooser: another module's suite cannot answer it");
        assertEqual(ModuleTestKit.cancelChooser("legacy-elevate"), "the open chooser is module \"good\"'s, not \"legacy-elevate\"",
                    "… nor cancel it");
        const oddList = ["/srv/a"];
        Object.defineProperty(oddList, 0, { get() { throw new Error("odd"); } });
        assert(ModuleTestKit.answerChooser("good", oddList).startsWith("the answer could not be read") && ModuleTestKit.chooserOpen,
               "answerChooser: a list that throws when read is a problem, not an exception");
        assert(ModuleTestKit.answerChooser("good", ["/srv/\ud800"]).startsWith("not a path the shell takes (it holds a broken character)") && ModuleTestKit.chooserOpen,
               "answerChooser: half a character (a lone surrogate) refused, not thrown");
        assertEqual(ModuleTestKit.answerChooser("good", ["/srv/share/a b.txt", "/srv/share/c"]), "", "answerChooser: two files");
        assert(!chooser.open && !ModuleTestKit.chooserOpen, "… closed");
        assertEqual(_chosen.length + " " + (_busy === null), "0 true", "… done is called after, never inside the call");
        _then("the chooser answered", () => _chosen.length === 1 && _busy !== null, () => {
            assertEqual(JSON.stringify(_chosen[0]), JSON.stringify({ paths: ["/srv/share/a b.txt", "/srv/share/c"], cancelled: false, blocked: "", error: "" }),
                        "done: the paths, as absolute paths");
            assert(Object.isFrozen(_chosen[0]) && Object.isFrozen(_chosen[0].paths), "… frozen");
            assertEqual(JSON.stringify(_busy), JSON.stringify({ paths: [], cancelled: false, blocked: "busy", error: "" }),
                        "a second chooser while one was open: blocked busy");
            module.chooseFiles({ mode: "folder" }, result => suite._chosen = suite._chosen.concat([result]));
            assertEqual(ModuleTestKit.chooserCalls[1]?.startDirectory, Api.system.home, "no startDirectory: the home directory (Api.system.home)");
            assertEqual(ModuleTestKit.chooserCalls[1]?.title, "Good fixture", "no title: the module's name");
            assertEqual(ModuleTestKit.answerChooser("good", ["/a", "/b"]), "mode \"folder\" chooses one path, not 2", "answerChooser: two for a folder refused");
            assertEqual(ModuleTestKit.cancelChooser("good"), "", "cancelChooser()");
        });
        _then("the chooser cancelled", () => _chosen.length === 2, () => {
            assertEqual(JSON.stringify(_chosen[1]), JSON.stringify({ paths: [], cancelled: true, blocked: "", error: "" }), "cancelled");
            assertEqual(ModuleTestKit.cancelChooser("good"), "no chooser is open", "… none open now");
            ModuleTestKit.setChooserLocked(true);
            // The chooser's lock alone: a run as administrator started now is not refused
            admin.run(["/bin/sh", standIn, "as root"], "During the chooser's lock", result => suite._results.duringChooserLock = result);
            module.chooseFiles({}, result => suite._chosen = suite._chosen.concat([result]));
            assert(!ModuleTestKit.chooserOpen && ModuleTestKit.chooserCalls.length === 2, "locked: nothing opens, nothing recorded");
        });
        _then("the chooser refused while locked", () => _chosen.length === 3, () => {
            assertEqual(JSON.stringify(_chosen[2]), JSON.stringify({ paths: [], cancelled: false, blocked: "locked", error: "" }), "locked: blocked");
            ModuleTestKit.setChooserLocked(false);
            module.chooseFiles({ mode: "open" }, result => suite._chosen = suite._chosen.concat([result]));
            assert(ModuleTestKit.chooserOpen, "unlocked: it opens");
            ModuleTestKit.setChooserLocked(true);
        });
        _then("a lock closes the chooser", () => _chosen.length === 4, () => {
            assertEqual(JSON.stringify(_chosen[3]), JSON.stringify({ paths: [], cancelled: false, blocked: "locked", error: "" }),
                        "a lock while open: blocked locked, told apart from the user cancelling");
            assert(!ModuleTestKit.chooserOpen, "… closed");
            ModuleTestKit.setChooserLocked(false);
            module.chooseFiles({ mode: "save" }, result => suite._chosen = suite._chosen.concat([result]));
        });
        _then("the chooser refused a wrong mode", () => _chosen.length === 5, () => {
            assertEqual(_chosen[4].error, "mode must be one of open, openMany, folder", "a wrong mode: error, nothing opened");
            // Left open: the module is turned off below with it open
            module.chooseFiles({}, result => suite._afterOff = result);
            assert(ModuleTestKit.chooserOpen, "a chooser open while the module is turned off");
        });
        _then("the data directory is looked at", () => _dataMode !== null, () => {
            assert(_dataMode.ok && _dataMode.stdout.startsWith("700 "), "module.dataDirectory: there, mode 700: " + _dataMode.stdout);
        });
        _then("the commands answered", () => Object.keys(_results).length === 17 && _queried !== null, () => {
            assert(_results.duringChooserLock.ok && _results.duringChooserLock.lines[0] === "as root",
                   "ModuleTestKit.setChooserLocked locks the chooser alone: a run as administrator still runs: " + JSON.stringify(_results.duringChooserLock));
            assert(!_results.defaultElevate.ok && _results.defaultElevate.error.startsWith("test mode:") && !_results.defaultElevate.refused,
                   "PrivilegedAction in test mode: the default pkexec refused, nothing run: " + JSON.stringify(_results.defaultElevate));
            assert(!_results.runnerPkexec.ok && _results.runnerPkexec.error.startsWith("test mode:"),
                   "CommandRunner in test mode: a pkexec on PATH refused: " + JSON.stringify(_results.runnerPkexec));
            assert(!_results.actionPkexec.ok && _results.actionPkexec.error.startsWith("test mode:"),
                   "CommandAction in test mode: /usr/bin/pkexec refused: " + JSON.stringify(_results.actionPkexec));
            for (const name of ["envPkexec", "timeoutPkexec", "setsidPkexec"])
                assert(!_results[name].ok && _results[name].error.startsWith("test mode:"),
                       name + ": a pkexec handed to env, timeout or setsid refused: " + JSON.stringify(_results[name]));
            assert(!_results.outsider.ok && _results.outsider.error.startsWith("test mode:") && _results.outsider.code === -1,
                   "PrivilegedAction from a 1.10 module: an elevating program that is not its stand-in pkexec refused: " + JSON.stringify(_results.outsider));
            assert(_results.plain.ok && JSON.stringify(_results.plain.lines) === "[\"a b\",\"c\"]", "CommandAction: its lines, arguments kept whole");
            assertEqual(_results.code.code, 3, "CommandAction: the exit status (environment passed)");
            assert(_results.root.ok && _results.root.lines[0] === "as root", "PrivilegedAction: run through the elevating program");
            assert(_results.readOnce.ok && JSON.stringify(_results.readOnce.lines) === "[\"as root\"]",
                   "PrivilegedAction: the command read once, what was checked is what ran: " + JSON.stringify(_results.readOnce.lines));
            assert(_results.dismissed.dismissed && !_results.dismissed.ok, "PrivilegedAction: 126 is dismissed");
            assert(_results.refused.refused && !_results.refused.dismissed, "PrivilegedAction: 127 is refused");
            assert(!_results.bad.ok, "PrivilegedAction: not a command — refused, answered");
            assert(_results.missing.notFound && !_results.missing.refused && !_results.missing.dismissed && !_results.missing.ok,
                   "PrivilegedAction: a missing program is notFound, not refused: " + JSON.stringify(_results.missing));
            assert(_results.relative.notFound && !_results.relative.refused, "PrivilegedAction: a relative path is notFound (an absolute path is required)");
            assert(!_results.root.notFound && _results.refused.notFound === false, "PrivilegedAction: notFound false when the program is there");
            assertEqual(JSON.stringify(_queried), "[\"queried\"]", "CommandQuery: its lines");
        });
        _then("the runner's command answered", () => _ran !== null, () => {
            assertEqual(_ran.ok + " " + _ran.code + " " + _ran.timedOut + " " + _ran.failedToStart + " " + _ran.error, "false 5 false false ",
                        "CommandRunner: the exit status (the run's environment passed), nothing else said");
            assertEqual(_ran.stdout + "|" + _ranLines.join(), "one two\nthree|stdout:one two,stdout:three", "CommandRunner: its output, whole and line by line, arguments kept whole");
            assertEqual(runner.running, 0, "CommandRunner: no run left");
            // Last: turned off and on as `modules setEnabled` over IPC does (ModuleTestKit.setEnabled)
            assertEqual(ModuleTestKit.setEnabled("Not An Id", false), false, "ModuleTestKit.setEnabled: not a module id, refused");
            assert(ModuleTestKit.setEnabled("good", false), "ModuleTestKit.setEnabled(good, false)");
        });
        _then("it is turned off", () => !module.active && ModuleTestKit.status("good")?.state === "disabled", () => {
            assert(!ModuleTestKit.widgetEntries.some(entry => entry.module === "good"), "off: its widget is gone");
            assert(!ModuleTestKit.chooserOpen, "off: its chooser closed");
            assertEqual(ModuleTestKit.answerChooser("good", ["/srv/late"]), "no chooser is open", "… nothing left to answer");
            assertEqual(_leftOpen.state + "|" + _leftOpen.open, "closed|false", "off: its progress notification left open is closed");
            const closed = ModuleTestKit.notified.filter(entry => entry.handle === _leftOpenNumber && entry.kind === "close");
            assert(closed.length === 1 || ModuleTestKit.notified.length === 0, "… and its close recorded (unless another suite cleared the records)");
            assertEqual(module.notify("While off", { progress: 3 }), null, "off: a progress notification is not shown");
            assert(ModuleTestKit.setEnabled("good", true), "ModuleTestKit.setEnabled(good, true)");
        });
        _then("it is on again", () => module.active && ModuleTestKit.status("good")?.state === "loaded", () => {
            assert(ModuleTestKit.widgetEntries.some(entry => entry.module === "good"), "on again: its widget is back");
            assertEqual(_afterOff, null, "the chooser open when it was turned off: done never called");
            ModuleTestKit.clearRecords();
            assertEqual(ModuleTestKit.chooserCalls.length, 0, "clearRecords(): the chooser calls too");
        });
    }
}
