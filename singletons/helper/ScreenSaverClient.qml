import QtQuick
import Quickshell.Io
import qs.singletons

// The shell's side of `h2s-helper screensaver` (helper/src/ScreenSaverService.h): runs it
// for as long as `path` names a helper, feeds it the screensaver's state, and keeps what it
// reports — whether the shell has org.freedesktop.ScreenSaver or who does, the apps keeping
// the screen on, and their SimulateUserActivity (a signal) and SetActive(true) calls (asked
// of `setActive`, whose answer goes back to the app). What any of it means is IdleRules'
// (Idle carries it there). The helper ends when this ends (its input closes); one that exits
// is started again after a growing pause, logged on a change of outcome only, and the apps'
// requests it held are handed to the next one, which keeps those whose app is still on the
// bus. The program is a property, so a suite points it at the real helper on a
// private bus (tests/helper/ScreenSaverClientTest.qml).
QtObject {
    id: root

    // The helper; "" for none (nothing runs)
    property string path: ""
    // Whether to ask for org.freedesktop.ScreenSaver (HelperRules.wantsScreenSaverName): false
    // releases it, or leaves the queue for it, and the apps' requests go
    property bool own: true
    // The screensaver's state, for GetActive, GetActiveTime and ActiveChanged
    property bool active: false
    // When it became active, ms since the epoch (0 unknown)
    property real activeSinceMs: 0
    // Seconds without input, for GetSessionIdleTime: a function, asked when an app asks
    property var idleSeconds: null
    // An app's SetActive(true): a function that acts on it and returns whether it took
    property var setActive: null

    // "off" (no helper) | "starting" | "running" (said it is ready) | "failed" (ended:
    // started again after a pause) | "outdated" (speaks another protocol: not started again)
    property string state: "off"
    // { owned: true | false | null (not known), owner: "<process name>", released: the shell
    // leaves it free (`own` false) }
    property var name: ({ owned: null, owner: "", released: false })
    // [{ app, reason, cookie, caller }]: plain, capped (HelperRules.readServiceLine)
    property var holders: []

    signal activity()

    readonly property var _restartTable: ({ minimum: 1000, maximum: 60000, healthyRun: 60000 })
    property double _startedAt: 0
    property int _delay: 0
    property string _told: ""
    // A run is being stopped to start again (the path changed): its end is not a failure,
    // and what it still says is not heard
    property bool _stopping: false
    // The holders of a helper that ended, for the next one to take over (HelperRules.adoptMessage)
    property var _lost: []

    onPathChanged: _restart()
    onOwnChanged: _sendOwn()
    onActiveChanged: _sendActive()
    onActiveSinceMsChanged: _sendActive()
    Component.onCompleted: _restart()

    function _restart() {
        _retry.stop();
        _clear();
        if (_process.running) {
            // Started again when this run has ended (_ended)
            _stopping = true;
            _process.running = false;
            return;
        }
        if (path === "")
            state = "off";
        else
            _start();
    }

    function _start() {
        _startedAt = Date.now();
        state = "starting";
        _process.command = [path, "screensaver"];
        _process.running = true;
    }

    function _clear() {
        if (holders.length > 0)
            holders = [];
        name = { owned: null, owner: "", released: false };
    }

    function _send(message) {
        if (_process.running)
            _process.write(JSON.stringify(message) + "\n");
    }

    function _sendOwn() {
        if (state !== "running")
            return;
        // Asked again: not known until the helper says (not "released" meanwhile)
        if (own && name.released === true)
            name = { owned: null, owner: "", released: false };
        _send(HelperRules.ownMessage(own));
    }

    function _sendActive() {
        if (state === "running")
            _send(HelperRules.activeMessage(active, activeSinceMs));
    }

    function _tell(level, text) {
        if (text === _told)
            return;
        _told = text;
        if (level === "warning")
            console.warn("[ScreenSaver] " + text);
        else
            console.info("[ScreenSaver] " + text);
    }

    function _line(line) {
        if (_stopping || state === "outdated")
            return;
        const message = HelperRules.readServiceLine(line);
        if (message === null) {
            _tell("warning", "the helper said something it should not: ignored");
            return;
        }
        switch (message.event) {
        case "ready":
            if (message.protocol !== HelperRules.protocol) {
                state = "outdated";
                _tell("warning", "the helper speaks protocol " + message.protocol + ", the shell " + HelperRules.protocol
                      + ": the screensaver interface is off");
                _process.running = false;
                return;
            }
            state = "running";
            _sendOwn();
            _sendActive();
            if (HelperRules.adoptMessage(_lost) !== null)
                _send(HelperRules.adoptMessage(_lost));
            _lost = [];
            break;
        case "name":
            name = { owned: message.owned, owner: message.owner, released: message.released };
            if (message.released)
                _tell("info", "org.freedesktop.ScreenSaver left free: idle is off");
            else if (message.owned)
                _tell("info", "answering org.freedesktop.ScreenSaver");
            else
                _tell("info", "org.freedesktop.ScreenSaver is held by " + (message.owner || "another program")
                      + ": waiting for it to be free");
            break;
        case "inhibitors":
            holders = message.list;
            break;
        case "activity":
            activity();
            break;
        case "setActive":
            _send(HelperRules.setActiveMessage(message.id, typeof setActive === "function" && setActive() === true));
            break;
        case "askIdle":
            _send(HelperRules.idleMessage(message.id, typeof idleSeconds === "function" ? idleSeconds() : 0));
            break;
        case "error":
            _tell("warning", "the helper: " + message.message);
            break;
        }
    }

    function _ended() {
        const held = holders;
        _clear();
        if (_stopping) {
            _stopping = false;
            _restart();
            return;
        }
        if (state === "outdated" || path === "")
            return;
        // Until the next one runs nothing holds the screen on (a helper that keeps ending
        // must not keep it on for good); the next takes them over
        if (held.length > 0)
            _lost = held;
        const ran = Date.now() - _startedAt;
        _delay = LockIoRules.restartDelay(_delay, ran, _restartTable);
        state = "failed";
        _tell("warning", "the helper ended: started again in " + Math.round(_delay / 1000) + " s"
              + (_lost.length > 0 ? ", the apps' requests to keep the screen on handed to it" : ""));
        _retry.interval = _delay;
        _retry.start();
    }

    property Process _process: Process {
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root._line(data)
        }
        onRunningChanged: {
            if (!running)
                root._ended();
        }
    }

    property Timer _retry: Timer {
        repeat: false
        onTriggered: {
            if (root.path !== "" && !root._process.running)
                root._start();
        }
    }
}
