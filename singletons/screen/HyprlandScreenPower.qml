import QtQuick
import qs.singletons
import qs.singletons.io

// Monitors and their power on Hyprland (the shell's one instance is ScreenPower's): reads
// `hyprctl -j monitors` (connector, make, model, serial, `dpmsStatus`) and turns one
// monitor off or on through `hyprctl dispatch` (MonitorRules.hyprlandDpms). The program is a
// property, so a suite points it at a stand-in (tests/ScreenPowerReadingTest.qml).
//
// Hyprland turns every monitor off for a connector it does not know, so a dispatch never
// names a connector from an old list: each action reads the monitors itself and dispatches
// only from that answer, and only when no monitor event and no other reading started in
// between (`_generation`). Then it reads again: that reading says whether the action worked
// (Hyprland answers "ok" whatever it did), and a monitor it turned off by mistake is turned
// back on. One action at a time; a newer request for a monitor supersedes the older.
//
// A failed or unreadable reading leaves the monitors as last read with their power
// "unknown". Problems are logged when the outcome changes, not at every attempt.
QtObject {
    id: root

    property string hyprctl: "hyprctl"

    // [{ connector, id, base, make, model, serial, builtIn, power: "on" | "off" | "unknown" }]
    property var monitors: []
    // Identities seen as twins while the shell runs (MonitorRules.identities): a twin left
    // alone keeps its id
    property var twins: []
    // The last reading worked
    property bool monitorsRead: false
    // Why the last reading or the last action did not work; "" when it did
    property string readProblem: ""
    property string actionProblem: ""
    // An action is under way (its readings or its dispatch)
    readonly property bool acting: _action !== null

    // An action ended: the id it was asked for, the power asked, and "" when the reading
    // after it has that monitor at that power, else the problem
    signal actionDone(string id, bool on, string problem)

    function read() {
        _generation += 1;
        _readStamp += 1;
        _queryStamp = _readStamp;
        _query.request();
    }

    // Hyprland added or removed a monitor: an action's reading under way may name one that
    // is gone
    function monitorEvent() {
        _generation += 1;
    }

    // Turns the monitor with this id off or on (answered by actionDone)
    function setPower(id, on) {
        _sequence += 1;
        _requests = _requests.filter(request => request.id !== id).concat([{ id: id, on: on === true, sequence: _sequence }]);
        _next();
    }

    property int _generation: 0
    // Readings in the order they started: an answer from a reading older than the one
    // published is not published (late answers lose)
    property int _readStamp: 0
    property int _queryStamp: 0
    property int _publishedStamp: 0
    property int _sequence: 0
    // Requests waiting, oldest first: { id, on, sequence }
    property var _requests: []
    // The action under way: { id, on, sequence }
    property var _action: null

    function _superseded(action) {
        return _requests.some(request => request.id === action.id && request.sequence > action.sequence);
    }

    function _next() {
        if (_action !== null || _requests.length === 0)
            return;
        const action = _requests[0];
        _action = action;
        _requests = _requests.slice(1);
        const generation = _generation;
        _readOnce(answer => {
            if (root._superseded(action))
                return root._finish(action, "a newer request came");
            if (answer === null)
                return root._finish(action, "the monitors could not be read");
            if (generation !== root._generation)
                return root._finish(action, "the monitors changed while it was asked");
            const monitor = answer.monitors.find(entry => entry.id === action.id);
            const expression = monitor ? MonitorRules.hyprlandDpms(monitor.connector, action.on) : "";
            if (expression === "")
                return root._finish(action, "no connected monitor " + JSON.stringify(String(action.id).slice(0, 120)));
            root._runner.start([root.hyprctl, "dispatch", expression], {
                timeoutMs: 10000,
                maxOutputBytes: 4096,
                done: result => {
                    const problem = MonitorRules.dispatchProblem(result);
                    root._readOnce(after => root._recover(answer.monitors, after, monitor.connector, final => {
                        root._finish(action, problem !== "" ? problem
                                     : root._superseded(action) ? "a newer request came"
                                     : MonitorRules.actionProblem(final?.monitors ?? null, action.id, action.on));
                    }));
                }
            });
        });
    }

    function _finish(action, problem) {
        if (problem !== actionProblem)
            console.warn("ScreenPower: " + (problem === "" ? "monitors can be turned off and on again" : "a monitor could not be turned " + (action.on ? "on" : "off") + ": " + problem));
        actionProblem = problem;
        _action = null;
        actionDone(action.id, action.on, problem);
        _next();
    }

    // Part of the action: monitors it turned off besides its own (on before, off in the
    // reading after) are turned back on, each by a connector of that reading — whatever
    // changed meanwhile, since a target unplugged under the action is exactly when Hyprland
    // turns every monitor off. Then `done` gets the state the action leaves: a reading made
    // after those dispatches, or `after` when none was needed.
    function _recover(before, after, targetConnector, done) {
        const connectors = after === null ? [] : MonitorRules.turnedOffBesides(before, after.monitors, targetConnector);
        if (connectors.length === 0)
            return done(after);
        let waiting = connectors.length;
        for (const connector of connectors) {
            console.warn("ScreenPower: " + connector + " went off with another monitor's action: turned back on");
            _runner.start([hyprctl, "dispatch", MonitorRules.hyprlandDpms(connector, true)], {
                timeoutMs: 10000,
                maxOutputBytes: 4096,
                done: result => {
                    waiting -= 1;
                    if (waiting === 0)
                        root._readOnce(done);
                }
            });
        }
    }

    // One reading of the action's own, published, then handed to `done` (null when it failed)
    function _readOnce(done) {
        _readStamp += 1;
        const stamp = _readStamp;
        const lines = [];
        _runner.start([hyprctl, "-j", "monitors"], {
            timeoutMs: 10000,
            maxOutputBytes: 262144,
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => done(root._publish(lines, result, stamp))
        });
    }

    // A reading's answer → the monitors it gave, published unless a newer reading already
    // was; null when it failed
    function _publish(lines, result, stamp) {
        let problem = MonitorRules.readProblem(result);
        const answer = problem === "" ? MonitorRules.hyprlandMonitors(lines.join("\n"), twins) : null;
        if (problem === "" && answer === null)
            problem = "hyprctl gave no readable answer";
        if (stamp < _publishedStamp)
            return answer;
        _publishedStamp = stamp;
        if (problem !== readProblem)
            console.warn("ScreenPower: " + (problem === "" ? "the monitors are read again" : "the monitors' power could not be read: " + problem));
        readProblem = problem;
        if (answer === null) {
            monitors = MonitorRules.unknownPower(monitors);
            monitorsRead = false;
            return null;
        }
        monitors = answer.monitors;
        twins = twins.concat(answer.twins.filter(base => !twins.includes(base)));
        monitorsRead = true;
        return answer;
    }

    property LatestQuery _query: LatestQuery {
        command: [root.hyprctl, "-j", "monitors"]
        timeoutMs: 10000
        onAnswered: (lines, result) => root._publish(lines, result, root._queryStamp)
    }

    property CommandRunner _runner: CommandRunner {}
}
