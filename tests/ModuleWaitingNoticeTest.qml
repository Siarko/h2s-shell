import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.io

// The notice that modules wait for confirmation (singletons/ModuleWaitingNotice.qml) on a
// module host of its own that confirms (confirmations on, every fixture placed by hand), a
// stand-in notifier (handles the suite can press, dismiss, leave without an id for a while, or
// see give up as with another notification daemon) and a stand-in notification server (what
// it holds, dismiss(), actionInvoked). Covered: a held module raises one notification, its
// action asks for Settings → Modules and leaves it there; a load still being checked (held by
// a `head` on the file check's PATH that waits for the suite) keeps it and raises nothing; a
// second notice reading the first's state, as after a reload, raises nothing for the same set,
// and the first's notification, left behind, still opens the page and is closed by its hint
// when the set changes; a click on the new one opens the page before its handle knows its id;
// a dismissal holds until the set changes; safe mode closes it with any left behind; with
// another daemon it is sent plainly and its action still works; confirming the last module
// closes it. Changes the acknowledgements and the modules turned off through Config, as other
// suites do: in a process of its own.
TestCase {
    id: suite
    suiteName: "ModuleWaitingNotice"
    asynchronous: true
    ownProcess: true

    readonly property string fixtures: Quickshell.shellDir + "/tests/fixtures/modules"

    property ModuleHost host: ModuleHost {
        logStates: false
        confirmations: true
        checkTimeoutMs: 30000
    }
    property CommandRunner runner: CommandRunner {}

    // ---- The stand-in notification server: what it holds, by id ----
    property QtObject server: QtObject {
        property var notifications: ({ values: [] })
        signal actionInvoked(int id, string actionId)
        // The ids dismissed through it
        property var dismissed: []

        function add(id, hints) {
            const entry = {
                id: id, hints: hints ?? {},
                dismiss() {
                    suite.server.dismissed = suite.server.dismissed.concat([id]);
                    suite.server.remove(id);
                }
            };
            notifications = { values: notifications.values.concat([entry]) };
        }
        function remove(id) {
            notifications = { values: notifications.values.filter(entry => entry.id !== id) };
        }
        function holds(id) {
            return notifications.values.some(entry => entry.id === id);
        }
    }

    // ---- The stand-in notifier ----
    property Component _handleComponent: Component {
        QtObject {
            property bool open: true
            property int id: 0
            property int serverId: 0
            property string state: "running"
            property string summary: ""
            property var options: ({})
            function close() {
                open = false;
                state = "closed";
                suite.server.remove(serverId);
            }
            function dismiss() {
                close();
            }
            function press(actionId) {
                (options.actions ?? []).find(action => action.id === actionId)?.onTriggered?.();
            }
        }
    }
    // Another notification daemon owns the name: a handle gives up ("unknown")
    property bool foreign: false
    // A handle learns its id only later (the server's answer on its way)
    property bool idLater: false
    property int _nextId: 500
    // Everything sent, in order: handles, and plain sends ({ plain: true, summary, options, press })
    property var sent: []
    property QtObject notifier: QtObject {
        function send(summary, options) {
            if (options?.handle !== true) {
                const plain = { plain: true, summary: summary, options: options,
                                press(actionId) { (options.actions ?? []).find(action => action.id === actionId)?.onTriggered?.(); } };
                suite.sent = suite.sent.concat([plain]);
                return undefined;
            }
            const serverId = ++suite._nextId;
            const handle = suite._handleComponent.createObject(suite, {
                summary: summary, options: options, serverId: serverId, id: suite.idLater ? 0 : serverId,
                state: suite.foreign ? "starting" : "running"
            });
            if (suite.foreign) {
                Qt.callLater(() => {
                    handle.open = false;
                    handle.state = "unknown";
                });
            } else {
                suite.server.add(serverId, options.hints);
            }
            suite.sent = suite.sent.concat([handle]);
            return handle;
        }
    }

    // Where the notices keep their state: handed from one to the next, as a reload would
    property QtObject store: QtObject {
        property string stateText: ""
    }
    property int openRequests: 0
    property var notice: null
    property Component _noticeComponent: Component {
        ModuleWaitingNotice {
            logging: false
        }
    }

    function _newNotice() {
        notice = _noticeComponent.createObject(suite, { host: host, notifier: notifier, server: server, store: store });
        notice.openRequested.connect(() => suite.openRequests++);
    }

    property string _savedAcknowledged: ""
    property var _savedDisabled: []
    property var _savedEnabled: []
    property bool _saved: false
    property int _loads: 0
    property var _steps: []
    property string temp: ""
    property bool _ran: false

    // ---- The scheduler: each step waits for its condition (or its deadline), then runs ----

    function _then(description, condition, action, timeoutMs) {
        _steps.push({ description: description, condition: condition, action: action, deadline: timeoutMs ?? 10000 });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite._end();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {
                ready = false;
            }
            if (!ready && waited < step.deadline)
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

    function _end() {
        host.unload();
        notice?.destroy();
        if (_saved) {
            Config.setAcknowledgedModulesText(_savedAcknowledged);
            Config.disabledModules = _savedDisabled;
            Config.enabledModules = _savedEnabled;
        }
        if (temp !== "")
            runner.start(["rm", "-rf", "--", temp], { done: () => suite.finish() });
        else
            finish();
    }

    // ---- Helpers ----

    function _sh(script, args, done) {
        _ran = false;
        runner.start(["sh", "-c", script, "sh"].concat(args ?? []), {
            done: result => {
                suite._ran = true;
                done?.(result);
            }
        });
    }

    function _load(names, options) {
        _loads = host.loadCount + 1;
        host.load(names.map(name => fixtures + "/" + name), options ?? {});
    }

    // The load asked for has settled, and the notice has had its turn (it looks a moment later)
    property int _settledTicks: 0
    function _loaded() {
        if (host.loadCount !== _loads || !host.settled) {
            _settledTicks = 0;
            return false;
        }
        return ++_settledTicks > 3;
    }

    // A few turns of the clock have passed (the notice looks a moment after a change)
    property int _ticks: 0
    function _later() {
        return ++_ticks > 4;
    }

    function _last() {
        return sent[sent.length - 1] ?? null;
    }

    function _hinted() {
        return server.notifications.values.filter(entry => typeof entry.hints?.["x-h2s-modules-waiting"] === "string").map(entry => entry.id);
    }

    function runAsync() {
        // The file check's PATH starts with a `head` that waits while "hold" exists
        _sh("t=$(mktemp -d) && mkdir \"$t/bin\" && printf '%s\\n' '#!/bin/sh' "
            + "'while [ -e \"$(dirname \"$0\")/../hold\" ]; do sleep 0.05; done' 'PATH=${PATH#*:} exec head \"$@\"' > \"$t/bin/head\" "
            + "&& chmod +x \"$t/bin/head\" && printf %s \"$t\"", [], result => suite.temp = String(result.stdout ?? "").trim());
        _then("the config is read and the seam made", () => Config.ready && _ran && temp !== "", () => {
            host.checkEnvironment = { PATH: temp + "/bin:" + (Quickshell.env("PATH") ?? "") };
            _savedAcknowledged = Config.acknowledgedModulesText;
            _savedDisabled = host._plainList(Config.disabledModules);
            _savedEnabled = host._plainList(Config.enabledModules);
            _saved = true;
            Config.disabledModules = [];
            Config.enabledModules = [];
            // Written and empty: every module placed by hand is new
            Config.setAcknowledgedModules({});
            _newNotice();
            _load(["icon-none"]);
        });
        _then("one module held", _loaded, () => {
            assertEqual(host.status("icon-none")?.state, "unconfirmed", "the fixture waits for confirmation");
            assertEqual(sent.length, 1, "one notification raised");
            const first = _last();
            assertEqual(first?.summary, "None fixture is off", "… titled by the module's name");
            assertEqual(first?.options.body, "It is new and not part of h2s-shell. Confirm it to turn it on.", "… saying why");
            assertEqual(first?.options.format, "plain", "… as plain text");
            assertEqual((first?.options.actions ?? []).map(action => action.label).join(","), "Open Modules", "… with one action, Open Modules");
            assertEqual(first?.options.hints?.resident, true, "… resident: it stays after its action");
            assertEqual(first?.options.handle, true, "… with a handle, so the shell can close it");
            assertEqual(notice.shownBy, "shell", "… shown by the shell's own server");
            first.press("default");
            assertEqual(openRequests, 1, "Open Modules asks for Settings → Modules");
            assert(first.open, "… and leaves the notification there");
            assertEqual(host.status("icon-none")?.state, "unconfirmed", "… confirming nothing");
            // The same set loaded again, its check held: the statuses are pending meanwhile
            _sh("touch \"$1/hold\"", [temp], () => suite._load(["icon-none"]));
            _ticks = 0;
        });
        _then("a load held while its files are checked", () => _ran && host.loadCount === _loads && !host.settled && _later(), () => {
            assert(host.statuses.length > 0 && host.statuses.every(status => status.state === "pending"), "the module is pending while its files are checked");
            assertEqual(sent.length, 1, "while modules are being found again, nothing is raised");
            assert(sent[0].open, "… and the notification shown stays");
            _sh("rm -f \"$1/hold\"", [temp]);
        });
        _then("the held load settles", () => _ran && _loaded(), () => {
            assertEqual(sent.length, 1, "settled with the same set: nothing raised again");
            assert(sent[0].open, "… the notification still shown");
            // As after a reload: a new notice, the state the last one kept, its notification left behind
            notice.destroy();
            notice = null;
            _newNotice();
            _ticks = 0;
        });
        _then("a second notice with the first's state", () => _later(), () => {
            assertEqual(sent.length, 1, "a reload with the same set raises nothing");
            server.actionInvoked(sent[0].serverId, "default");
            assertEqual(openRequests, 2, "the notification left behind: its Open Modules still opens the page");
            // Another module, held for approval: the acknowledged author differs. Its handle
            // learns its id late
            const parent = host.status("icon-none").directory.replace(/\/[^/]*$/, "");
            Config.setAcknowledgedModules({ "icon-glyph": { source: "user", address: parent + "/icon-glyph", author: "Someone", privileged: false } });
            idLater = true;
            _load(["icon-none", "icon-glyph"]);
        });
        _then("a second module held", _loaded, () => {
            idLater = false;
            assertEqual(host.status("icon-glyph")?.state, "approval", "the second fixture waits for approval");
            assertEqual(sent.length, 2, "the changed set raised a new notification");
            assert(server.dismissed.includes(sent[0].serverId), "… the one left behind closed by its hint: one notification, not a stack");
            assertEqual(JSON.stringify(_hinted()), JSON.stringify([sent[1].serverId]), "… the new one alone on the server");
            assertEqual(_last().summary, "2 modules are off", "… titled by the count");
            assertEqual(_last().options.body, "Glyph fixture, None fixture wait for your confirmation.", "… naming both");
            server.actionInvoked(sent[1].serverId, "default");
            assertEqual(openRequests, 3, "a click on it before its handle knows its id: the page opens");
            _last().dismiss();
            _load(["icon-none", "icon-glyph"]);
        });
        _then("the same set loaded again after a dismissal", _loaded, () => {
            assertEqual(sent.length, 2, "dismissed: not raised again for the same set");
            assertEqual(host.confirm("icon-none"), "", "one confirmed");
        });
        _then("the set changes after the dismissal", () => host.status("icon-none")?.state === "loaded" && sent.length === 3, () => {
            assertEqual(_last().summary, "Glyph fixture is off", "a changed set is told again: the module still waiting");
            assertEqual(_last().options.body, "It now names another author. Approve it to turn it on.", "… why it waits");
            // One an earlier run left
            server.add(999, { "x-h2s-modules-waiting": "1" });
            _load(["icon-none", "icon-glyph"], { safeMode: true });
        });
        _then("safe mode", () => _loaded() && host.status("icon-glyph")?.state === "safe-mode", () => {
            assert(!_last().open, "safe mode: the notification closed (nothing is held there)");
            assert(server.dismissed.includes(999), "… and the one an earlier run left, by its hint");
            assertEqual(_hinted().length, 0, "… none left on the server");
            assertEqual(sent.length, 3, "… and none raised");
            foreign = true;
            _load(["icon-none", "icon-glyph"]);
        });
        _then("out of safe mode, another daemon", () => _loaded() && host.status("icon-glyph")?.state === "approval" && sent.length === 5, () => {
            assertEqual(sent[3].state, "unknown", "with another notification daemon the handle gives up");
            const plain = sent[4];
            assert(plain.plain === true && plain.options.handle !== true, "… and it is sent again plainly");
            assertEqual(plain.summary, "Glyph fixture is off", "… with its words");
            assertEqual((plain.options.actions ?? []).map(action => action.label).join(","), "Open Modules", "… and its action");
            assertEqual(notice.shownBy, "other", "… shown by another daemon");
            plain.press("default");
            assertEqual(openRequests, 4, "its Open Modules opens the page");
            assertEqual(host.confirm("icon-glyph"), "", "the last one confirmed");
        });
        _then("no module waits", () => host.status("icon-glyph")?.state === "loaded" && notice.shownBy === "", () => {
            assertEqual(sent.length, 5, "none waiting: nothing raised");
            assertEqual(_hinted().length, 0, "… nothing of the shell's left on its server");
            foreign = false;
        });
        _clock.start();
    }
}
