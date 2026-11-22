import QtQuick
import Quickshell
import qs.singletons

// The notice that modules wait for confirmation (singletons/ModuleWaitingNotice.qml) on a
// module host of its own that confirms (confirmations on, every fixture placed by hand) and a
// stand-in notifier that records what is sent and lets the suite dismiss a notification or
// press its action: a held module raises one notification, its action asks for Settings →
// Modules and leaves it there, a changed set replaces it, a dismissal holds until the set
// changes, safe mode closes it, and confirming the last module closes it. Changes the
// acknowledgements and the modules turned off through Config, as other suites do: in a
// process of its own.
TestCase {
    id: suite
    suiteName: "ModuleWaitingNotice"
    asynchronous: true
    ownProcess: true

    readonly property string fixtures: Quickshell.shellDir + "/tests/fixtures/modules"

    property ModuleHost host: ModuleHost {
        logStates: false
        confirmations: true
    }

    // The stand-in notifier: each notification sent, with a handle the suite can dismiss or
    // press an action of, as the server would tell it
    property var sent: []
    property QtObject notifier: QtObject {
        function send(summary, options) {
            const handle = {
                open: true, id: 0, summary: summary, options: options,
                close() { this.open = false; },
                dismiss() {
                    this.open = false;
                    options.onDismissed?.();
                },
                press(actionId) {
                    (options.actions ?? []).find(action => action.id === actionId)?.onTriggered?.();
                }
            };
            suite.sent = suite.sent.concat([handle]);
            return handle;
        }
    }
    property int openRequests: 0
    property var notice: null
    property Component _noticeComponent: Component {
        ModuleWaitingNotice {
            server: null
            logging: false
        }
    }

    property string _savedAcknowledged: ""
    property var _savedDisabled: []
    property var _savedEnabled: []
    property bool _saved: false
    property int _loads: 0
    property var _steps: []

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
        finish();
    }

    // ---- Helpers ----

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

    function _last() {
        return sent[sent.length - 1] ?? null;
    }

    function runAsync() {
        _then("the config is read", () => Config.ready, () => {
            _savedAcknowledged = Config.acknowledgedModulesText;
            _savedDisabled = host._plainList(Config.disabledModules);
            _savedEnabled = host._plainList(Config.enabledModules);
            _saved = true;
            Config.disabledModules = [];
            Config.enabledModules = [];
            // Written and empty: every module placed by hand is new
            Config.setAcknowledgedModules({});
            notice = _noticeComponent.createObject(suite, { host: host, notifier: notifier });
            notice.openRequested.connect(() => suite.openRequests++);
            _load(["icon-none"]);
            assertEqual(sent.length, 0, "nothing raised while the modules are still being found");
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
            assertEqual(first?.options.handle, true, "… with a handle, so its dismissal comes back");
            first.press("default");
            assertEqual(openRequests, 1, "Open Modules asks for Settings → Modules");
            assert(first.open, "… and leaves the notification there");
            assertEqual(host.status("icon-none")?.state, "unconfirmed", "… confirming nothing");
            // Another module, held for approval: the acknowledged author differs
            const parent = host.status("icon-none").directory.replace(/\/[^/]*$/, "");
            Config.setAcknowledgedModules({ "icon-glyph": { source: "user", address: parent + "/icon-glyph", author: "Someone", privileged: false } });
            _load(["icon-none", "icon-glyph"]);
        });
        _then("a second module held", _loaded, () => {
            assertEqual(host.status("icon-glyph")?.state, "approval", "the second fixture waits for approval");
            assertEqual(sent.length, 2, "the changed set raised a new notification");
            assert(!sent[0].open, "… the first closed: one notification, not a stack");
            assertEqual(_last().summary, "2 modules are off", "… titled by the count");
            assertEqual(_last().options.body, "Glyph fixture, None fixture wait for your confirmation.", "… naming both");
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
            _load(["icon-none", "icon-glyph"], { safeMode: true });
        });
        _then("safe mode", () => _loaded() && host.status("icon-glyph")?.state === "safe-mode", () => {
            assert(!_last().open, "safe mode: the notification closed (nothing is held there)");
            assertEqual(sent.length, 3, "… and none raised");
            _load(["icon-none", "icon-glyph"]);
        });
        _then("out of safe mode", () => _loaded() && host.status("icon-glyph")?.state === "approval", () => {
            assertEqual(sent.length, 4, "out of safe mode: raised again");
            assertEqual(host.confirm("icon-glyph"), "", "the last one confirmed");
        });
        _then("no module waits", () => host.status("icon-glyph")?.state === "loaded" && !_last().open, () => {
            assertEqual(sent.length, 4, "confirming the last one closed the notification, none raised");
            assert(sent.every(handle => !handle.open), "… nothing left open");
        });
        _clock.start();
    }
}
