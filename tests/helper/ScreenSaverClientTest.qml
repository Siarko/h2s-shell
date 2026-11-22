import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.helper
import qs.tests

// The shell's side of `h2s-helper screensaver` (singletons/helper/ScreenSaverClient.qml)
// against the real helper, on tests/run-helper.sh's private bus (never the session's): the
// name taken and said, an app (the test client, helper/tests/client.cpp) inhibiting with
// markup in its reason — a holder, plain text —, SimulateUserActivity heard, SetActive(true)
// answered with what the shell says (SetActive(false) not asked), the helper killed and its
// successor taking over the app's request,
// the screensaver's state answering GetActive and sent as ActiveChanged on both paths,
// GetSessionIdleTime answered from the shell, UnInhibit, an app leaving the bus with a
// cookie, the name left free and taken again as `own` changes, a second helper finding the
// name taken (by whom) and getting it when the first stops, and a stopped client's helper
// gone. Each step waits on its condition.
TestCase {
    id: suite
    suiteName: "ScreenSaverClient"
    asynchronous: true

    readonly property string _helper: Quickshell.env("H2S_TEST_HELPER") ?? ""
    readonly property string _clientProgram: Quickshell.env("H2S_TEST_CLIENT") ?? ""

    property var _first: null
    property var _second: null
    property var _activities: 0
    property var _setActive: []
    property bool _setActiveTakes: true
    property int _heldCookie: 0
    property var _lines: []
    property var _steps: []
    property var _step: null
    property int _waited: 0
    property int _cookie: 0

    property Component _clientComponent: Component {
        ScreenSaverClient {
            idleSeconds: () => 42.6
            setActive: () => {
                suite._setActive = suite._setActive.concat([suite._setActiveTakes]);
                return suite._setActiveTakes;
            }
        }
    }

    property Process _app: Process {
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => suite._lines = suite._lines.concat([data])
        }
    }

    function _tell(line) {
        _app.write(line + "\n");
    }

    function _heard(line) {
        return _lines.includes(line);
    }

    function runAsync() {
        if (_helper === "" || _clientProgram === "") {
            fail("no helper or test client given (H2S_TEST_HELPER, H2S_TEST_CLIENT: run tests/run-helper.sh)");
            finish();
            return;
        }
        _first = _clientComponent.createObject(suite, { path: _helper });
        _first.activity.connect(() => suite._activities += 1);
        _steps = [
            { what: "the helper runs and owns the name", until: () => _first.state === "running" && _first.name.owned === true },
            { what: "no holders at first", until: () => _first.holders.length === 0 },
            { what: "an app on the bus", run: () => { _app.command = [_clientProgram]; _app.running = true; }, until: () => _heard("ready") },
            { what: "it watches ActiveChanged", run: () => _tell("watch"), until: () => _heard("watching") },
            { what: "it inhibits: one holder, its app and reason as plain text",
              run: () => _tell("inhibit\tmpv\t<b>film</b>"),
              until: () => _first.holders.length === 1 && _first.holders[0].app === "mpv" && _first.holders[0].reason === "<b>film</b>" },
            { what: "… with the cookie the app was handed",
              until: () => _lines.some(line => line === "cookie " + _first.holders[0]?.cookie) },
            { what: "SimulateUserActivity: heard", run: () => _tell("activity"), until: () => _activities === 1 },
            { what: "SetActive(true): asked of the shell, its answer (taken) the app's", run: () => _tell("setactive\ttrue"),
              until: () => _setActive.join(",") === "true" && _heard("setactive true") },
            { what: "SetActive(true) where it does not take (locked): false to the app",
              run: () => { _setActiveTakes = false; _lines = []; _tell("setactive\ttrue"); },
              until: () => _setActive.join(",") === "true,false" && _heard("setactive false") },
            { what: "SetActive(false): false, the shell not asked", run: () => { _lines = []; _tell("setactive\tfalse"); _tell("active"); },
              until: () => _heard("setactive false") && _heard("active false") && _setActive.length === 2 },
            { what: "GetActive before the shell said: false", run: () => { _lines = _lines.filter(line => !line.startsWith("active")); _tell("active"); }, until: () => _heard("active false") },
            { what: "the screensaver active: ActiveChanged on /org/freedesktop/ScreenSaver",
              run: () => { _first.activeSinceMs = Date.now() - 5000; _first.active = true; },
              until: () => _heard("ActiveChanged /org/freedesktop/ScreenSaver true") },
            { what: "… and on /ScreenSaver", until: () => _heard("ActiveChanged /ScreenSaver true") },
            { what: "GetActive: true", run: () => _tell("active"), until: () => _heard("active true") },
            { what: "GetActiveTime: from when the shell said",
              run: () => _tell("activetime"),
              until: () => _lines.some(line => /^activetime ([4-9]|1[0-9])$/.test(line)) },
            { what: "GetSessionIdleTime: the shell's answer, in whole seconds", run: () => _tell("idle"), until: () => _heard("idle 42") },
            { what: "inactive again: ActiveChanged false", run: () => { _first.active = false; },
              until: () => _heard("ActiveChanged /org/freedesktop/ScreenSaver false") },
            { what: "UnInhibit: no holders", run: () => _tell("uninhibit\t" + _first.holders[0].cookie), until: () => _first.holders.length === 0 },
            { what: "inhibits again", run: () => _tell("inhibit\tplayer\twatching"), until: () => _first.holders.length === 1 },
            { what: "the helper killed: its holders gone while none runs",
              run: () => { _heldCookie = _first.holders[0].cookie; _first._process.signal(9); },
              until: () => _first.state === "failed" && _first.holders.length === 0 },
            { what: "… started again, it takes over the app's request, same cookie",
              until: () => _first.state === "running" && _first.holders.length === 1 && _first.holders[0].cookie === _heldCookie
                           && _first.holders[0].app === "player" },
            { what: "… which the app can still give back", run: () => _tell("uninhibit\t" + _heldCookie), until: () => _first.holders.length === 0 },
            { what: "inhibits once more", run: () => _tell("inhibit\tplayer\twatching"), until: () => _first.holders.length === 1 },
            { what: "the app leaves the bus holding it: its cookie dropped",
              run: () => { _app.running = false; }, until: () => !_app.running && _first.holders.length === 0 },
            { what: "idle off in the shell (own: false): the name left free",
              run: () => { _first.own = false; },
              until: () => _first.name.released === true && HelperRules.serviceStatus("ready", _first.state, _first.name).state === "released" },
            { what: "… taken again (own: true)", run: () => { _first.own = true; },
              until: () => _first.name.owned === true && _first.name.released === false },
            { what: "a second helper: the name held by the first, said by its process name",
              run: () => { _second = _clientComponent.createObject(suite, { path: _helper }); },
              until: () => _second.state === "running" && _second.name.owned === false && _second.name.owner === "h2s-helper" },
            { what: "… the page's line names it",
              until: () => HelperRules.serviceStatus("ready", _second.state, _second.name).line.startsWith("h2s-helper answers apps") },
            { what: "the first stopped: off, its helper gone, and the second gets the name",
              run: () => { _first.path = ""; },
              until: () => _first.state === "off" && _second.name.owned === true },
            { what: "the second stopped: off", run: () => { _second.path = ""; }, until: () => _second.state === "off" && !_second._process.running }
        ];
        _next();
    }

    function _next() {
        _step = _steps.shift() ?? null;
        if (_step === null) {
            _first?.destroy();
            _second?.destroy();
            finish();
            return;
        }
        _waited = 0;
        try {
            _step.run?.();
        } catch (error) {
            fail(_step.what + ": threw " + error);
        }
        _clock.start();
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        onTriggered: {
            suite._waited += interval;
            let reached = false;
            try {
                reached = suite._step.until();
            } catch (error) {
                reached = false;
            }
            if (!reached && suite._waited < 5000)
                return;
            stop();
            suite.assert(reached, suite._step.what);
            if (!reached) {
                console.log("  (the app said: " + JSON.stringify(suite._lines) + ")");
                suite._steps = [];
            }
            suite._next();
        }
    }
}
