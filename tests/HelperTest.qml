import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.helper

// The shell's side of its helper program: what HelperRules makes of `h2s-helper --version`
// (ready, out of date, failed in each way, text from outside capped on one line), and the
// reading itself (singletons/helper/HelperVersionRead.qml) run for real against stand-ins
// (tests/fixtures/helper: a helper of this protocol, of another, one that fails, one that
// says something else, one with markup in its version) and a path that is not there. The
// real helper is tests/run-helper.sh's. And the shell's Helper here, started without the
// launcher: no helper. Asynchronous: each reading is a process.
TestCase {
    id: suite
    suiteName: "Helper"
    asynchronous: true

    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/helper"

    function _rules() {
        const read = HelperRules.readVersion;
        const ok = stdout => ({ ok: true, code: 0, stdout: stdout, timedOut: false, failedToStart: false, truncated: false });
        const current = "{\"version\":\"2.0.0\",\"protocol\":" + HelperRules.protocol + "}";

        assertEqual(JSON.stringify(read(ok(current))), JSON.stringify({ state: "ready", version: "2.0.0", problem: "" }),
                    "this protocol: ready, with its version");
        assertEqual(read(ok("\n" + current + "\n\n")).state, "ready", "… blank lines around it do not matter");
        const old = read(ok("{\"version\":\"1.0.0\",\"protocol\":" + (HelperRules.protocol + 1) + "}"));
        assertEqual(old.state, "outdated", "another protocol: out of date");
        assertEqual(old.version, "1.0.0", "… its version kept");
        assert(old.problem.indexOf(String(HelperRules.protocol + 1)) >= 0, "… the problem names its protocol");

        assertEqual(read(null).state, "failed", "no result: failed");
        assertEqual(read({ failedToStart: true }).problem, "could not be started", "not started: failed, said so");
        assertEqual(read({ timedOut: true }).problem, "did not answer", "timed out: failed, said so");
        assertEqual(read({ ok: true, truncated: true, stdout: current }).state, "failed", "too much output: failed");
        assertEqual(read({ ok: false, code: 3, stdout: current }).problem, "failed (3)", "a non-zero status: failed, whatever it printed");
        for (const stdout of ["", "h2s-helper 2.0.0", "[1]", "null", "{\"version\":2,\"protocol\":1}",
                              "{\"version\":\"2\",\"protocol\":\"1\"}", "{\"version\":\"2\",\"protocol\":1.5}",
                              current + "\n" + current])
            assertEqual(read(ok(stdout)).state, "failed", "not the protocol's answer (" + JSON.stringify(stdout) + "): failed");
        const odd = read(ok("{\"version\":\"<b>" + "v".repeat(100) + "</b>\\nnext\",\"protocol\":" + HelperRules.protocol + "}"));
        assertEqual(odd.version.length, 40, "a version from outside is capped");
        assertEqual(odd.version.indexOf("\n"), -1, "… and on one line");

        assertEqual(HelperRules.logLine("", { state: "missing" }), "", "no helper: the launcher said so, nothing more");
        assertEqual(HelperRules.logLine("/x/h2s-helper", { state: "ready" }), "", "ready: nothing to say");
        assert(HelperRules.logLine("/x/h2s-helper", old).indexOf("out of date") >= 0, "out of date: said");
        assert(HelperRules.logLine("/x/h2s-helper", read(null)).indexOf("/x/h2s-helper") >= 0, "failed: said, with its path");

        _serviceRules();
    }

    // `h2s-helper screensaver`'s lines, and what the page says of the interface
    function _serviceRules() {
        const line = HelperRules.readServiceLine;
        assertEqual(JSON.stringify(line("{\"event\":\"ready\",\"protocol\":2}")), JSON.stringify({ event: "ready", protocol: 2 }),
                    "service: ready, with its protocol");
        assertEqual(JSON.stringify(line("{\"event\":\"name\",\"owned\":true}")), JSON.stringify({ event: "name", owned: true, owner: "", released: false }),
                    "service: the name owned");
        assertEqual(JSON.stringify(line("{\"event\":\"name\",\"released\":true}")),
                    JSON.stringify({ event: "name", owned: false, owner: "", released: true }),
                    "service: the name released (the shell's own: false): not owned");
        const taken = line("{\"event\":\"name\",\"owned\":false,\"owner\":\"<b>kde</b>\\n" + "x".repeat(80) + "\"}");
        assertEqual(taken.owned, false, "service: the name held by another");
        assertEqual(taken.owner.length, HelperRules.maxOwnerLength, "… its owner's name capped");
        assert(taken.owner.startsWith("<b>kde</b> x"), "… on one line, markup kept as text");
        const holders = line(JSON.stringify({ event: "inhibitors", list: [
            { app: "mpv", reason: "r".repeat(500), cookie: 9, caller: ":1.42" },
            { app: "<i>firefox</i>\tbrowser\nnext", reason: "video", cookie: 3, caller: "org.example; rm" },
            { app: "no cookie", reason: "" }, { app: "zero", reason: "", cookie: 0 }, "junk", null] }));
        assertEqual(holders.list.map(holder => holder.cookie).join(","), "3,9", "service: the holders, by cookie, the unreadable ones left out");
        assertEqual(holders.list[0].app, "<i>firefox</i> browser next", "… an app's name on one line, as text");
        assertEqual(holders.list[1].reason.length, HelperRules.maxReasonLength, "… a reason capped");
        assertEqual(holders.list[1].caller, ":1.42", "… the caller's unique bus name kept");
        assertEqual(holders.list[0].caller, "", "… what is not a unique name dropped");
        assertEqual(line(JSON.stringify({ event: "inhibitors", list: Array.from({ length: 100 }, (unused, i) => ({ app: "a", reason: "", cookie: i + 1 })) })).list.length,
                    HelperRules.maxHolders, "… at most maxHolders kept");
        assertEqual(line("{\"event\":\"activity\"}").event, "activity", "service: activity");
        assertEqual(line("{\"event\":\"askIdle\",\"id\":4}").id, 4, "service: the idle time asked, with the ask's id");
        assertEqual(line("{\"event\":\"setActive\",\"id\":5}").id, 5, "service: SetActive(true), with the ask's id");
        assertEqual(line("{\"event\":\"error\",\"message\":\"no bus\"}").message, "no bus", "service: an error, with its message");
        for (const odd of ["", "junk", "[]", "null", "{\"event\":\"what\"}", "{\"event\":\"ready\"}", "{\"event\":\"name\"}",
                           "{\"event\":\"inhibitors\",\"list\":{}}", "{\"event\":\"setActive\"}", "{\"event\":\"askIdle\",\"id\":0}",
                           "{\"event\":\"setActive\",\"id\":\"1\"}"])
            assertEqual(line(odd), null, "service: not a line of the protocol (" + odd + "): null");

        assertEqual(JSON.stringify(HelperRules.activeMessage(true, 1700000000500)), JSON.stringify({ active: true, since: 1700000000 }),
                    "service: active, since in whole seconds");
        assertEqual(JSON.stringify(HelperRules.activeMessage(false, 1700000000500)), JSON.stringify({ active: false, since: 0 }),
                    "… inactive: no time");
        assertEqual(JSON.stringify(HelperRules.idleMessage(4, 12.7)), JSON.stringify({ answer: 4, idleSeconds: 12 }),
                    "service: the idle time in whole seconds, answering its ask");
        assertEqual(HelperRules.idleMessage(4, -3).idleSeconds, 0, "… never negative");
        assertEqual(HelperRules.idleMessage(4, "junk").idleSeconds, 0, "… 0 when not a number");
        assertEqual(JSON.stringify(HelperRules.setActiveMessage(5, true)), JSON.stringify({ answer: 5, taken: true }),
                    "service: SetActive answered: taken");
        assertEqual(HelperRules.setActiveMessage(5, undefined).taken, false, "… anything but true: not taken");
        assertEqual(JSON.stringify(HelperRules.adoptMessage([{ app: "mpv", reason: "r", cookie: 9, caller: ":1.4" },
                                                             { app: "x", reason: "", cookie: 3, caller: "" }, null])),
                    JSON.stringify({ adopt: [{ caller: ":1.4", app: "mpv", reason: "r", cookie: 9 }] }),
                    "service: the holders handed to the next helper, those with a caller");
        assertEqual(HelperRules.adoptMessage([]), null, "… none: nothing to send");
        assertEqual(HelperRules.adoptMessage(undefined), null, "… nor for no list");

        const wants = HelperRules.wantsScreenSaverName;
        const values = changes => Object.assign({ screensaverEnabled: false, screensaverTimeout: 300, screenOffEnabled: false,
                                                  screenOffTimeout: 600, lockscreenEnabled: false, lockAfter: 600,
                                                  lockedScreenOffTimeout: 60 }, changes);
        const resolved = (changes, power) => IdleRules.config(values(changes), [{ id: "m", base: "m", connector: "DP-1" }], power);
        assertEqual(wants(resolved({}, true)), false, "name: every idle stage off: left free (an idle daemon may own it)");
        assertEqual(wants(resolved({ screensaverEnabled: true }, true)), true, "name: the screensaver on: asked for");
        assertEqual(wants(resolved({ screenOffEnabled: true }, true)), true, "… screens off on, with power control: asked for");
        assertEqual(wants(resolved({ screenOffEnabled: true }, false)), true,
                    "… screens off switched on without power control (the screensaver at its time): asked for");
        assertEqual(wants(resolved({ perMonitor: true, monitorIdle: { m: { screensaverEnabled: true } } }, true)), true,
                    "… only one monitor's own screensaver on: asked for");
        assertEqual(wants(resolved({ perMonitor: true, monitorIdle: { m: { screenOffEnabled: true } } }, true)), true,
                    "… only one monitor's own screen-off on: asked for");
        assertEqual(wants(resolved({ lockscreenEnabled: true }, false)), true, "… the idle lock on: asked for");
        assertEqual(wants(IdleRules.config(values({ sleepEnabled: true }), [], true, "yes")), true, "… the sleep on: asked for");
        assertEqual(wants(IdleRules.config(values({ sleepEnabled: true }), [], true, "challenge")), false,
                    "… the sleep switched on where logind will not let the shell sleep: not a stage, left free");
        assertEqual(wants(IdleRules.config(values({ hibernateEnabled: true }), [], true, "na", "yes", "na")), true,
                    "… the hibernation on, sleep off: asked for");
        assertEqual(wants(IdleRules.config(values({ hibernateEnabled: true }), [], true, "na", "challenge", "na")), false,
                    "… the hibernation switched on where logind will not let the shell hibernate: left free");
        assertEqual(wants(resolved({ lockedScreenOffTimeout: 30, lockOnSleep: true }, true)), false,
                    "… the lock screen's screen-off and the lock before sleep do not count (requests are ignored while locked)");
        assertEqual(wants({ saverAfter: "300", lockAfter: -1 }), false, "… only a positive number of seconds is a stage");
        assertEqual(wants(null), false, "… no config: left free");
        assertEqual(JSON.stringify(HelperRules.ownMessage(true)), JSON.stringify({ own: true }), "name: the word to the helper: own");
        assertEqual(JSON.stringify(HelperRules.ownMessage(undefined)), JSON.stringify({ own: false }), "… anything but true: release");

        const status = HelperRules.serviceStatus;
        assertEqual(JSON.stringify(status("missing", "off", { owned: null })), JSON.stringify({ state: "notBuilt", line: "Not built" }),
                    "status: no helper: not built");
        assertEqual(status("outdated", "off", { owned: null }).state, "outdated", "status: an old helper: out of date");
        assertEqual(status("ready", "outdated", { owned: null }).state, "outdated", "… also when it says so itself");
        assertEqual(status("ready", "failed", { owned: null }).state, "failed", "status: a helper that ended: failed");
        assertEqual(status("checking", "off", { owned: null }).state, "starting", "status: the helper being checked: starting");
        assertEqual(status("ready", "running", { owned: null }).state, "starting", "status: running, the name not known yet: starting");
        assertEqual(JSON.stringify(status("ready", "running", { owned: true, owner: "" })), JSON.stringify({ state: "answering", line: "" }),
                    "status: the name owned: answering");
        const held = status("ready", "running", { owned: false, owner: "ksmserver" });
        assertEqual(held.state, "taken", "status: held by another: taken");
        assertEqual(held.line, "ksmserver answers apps that ask to keep the screen on. Stop it to let the shell do it.",
                    "… the line names it");
        const released = status("ready", "running", { owned: false, owner: "", released: true });
        assertEqual(released.state, "released", "status: left free by the shell: released");
        assertEqual(released.line, "Left to other programs while idle is off", "… the line says why");
        assert(status("ready", "running", { owned: false, owner: "" }).line.startsWith("Another program answers"),
               "… or says another program when its name is not known");
    }

    // ---- The readings, one after another --------------------------------------------------
    property var _cases: [
        { program: "ready", state: "ready", version: "2.0.0" },
        { program: "outdated", state: "outdated", version: "1.9.0" },
        { program: "fails", state: "failed", version: "" },
        { program: "garbage", state: "failed", version: "" },
        { program: "markup", state: "ready", version: ("<b>" + "v".repeat(100)).slice(0, 40) },
        { program: "not-there", state: "failed", version: "" }
    ]
    property var _reader: null
    property var _case: null
    property int _waited: 0

    property Component _readerComponent: Component {
        HelperVersionRead {}
    }

    function runAsync() {
        try {
            _rules();
        } catch (error) {
            fail("the rules threw: " + error);
        }
        assertEqual(Helper.path, "", "the shell started without the launcher has no helper");
        assertEqual(Helper.state, "missing", "… its state says so");
        assert(!Helper.available, "… and it is not available");
        _next();
    }

    function _next() {
        _reader?.destroy();
        _reader = null;
        _case = _cases.shift() ?? null;
        if (_case === null) {
            finish();
            return;
        }
        _waited = 0;
        _reader = _readerComponent.createObject(suite, { path: _fixtures + "/" + _case.program });
        _clock.start();
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        onTriggered: {
            const reader = suite._reader;
            suite._waited += interval;
            if (reader.state === "checking" && suite._waited < 10000)
                return;
            stop();
            const name = suite._case.program;
            suite.assertEqual(reader.state, suite._case.state, name + ": " + suite._case.state);
            suite.assertEqual(reader.version, suite._case.version, name + ": its version");
            if (suite._case.state === "failed")
                suite.assert(reader.problem !== "", name + ": the problem is said");
            suite._next();
        }
    }
}
