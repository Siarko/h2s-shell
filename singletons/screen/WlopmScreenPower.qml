import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.io

// Monitors and their power through `wlopm` (the wlr-output-power-management client), where
// the shell does not run under Hyprland; the same interface as HyprlandScreenPower. Reads
// `wlopm --json` (each output's connector and power; the model and serial from the screen
// Qt knows by that name: `screens`) and turns one monitor off or on with `wlopm --off
// <connector>` / `--on` (MonitorRules.wlopmCommand), argv only. The program is a property,
// so a suite points it at a stand-in (tests/WlopmScreenPowerReadingTest.qml).
//
// Whether the program is there is what its readings say (`program`): one that cannot be
// started is "missing", any other answer has it "found". An action reads the monitors
// itself and runs the command only for a connector of that answer — wlopm takes `*` for
// every output — and only when no screen change and no other reading started in between
// (`_generation`). Then it reads again: that reading says whether the action worked. One
// action at a time; a newer request for a monitor supersedes the older.
//
// A failed or unreadable reading leaves the monitors as last read with their power
// "unknown". Problems are logged when the outcome changes, not at every attempt.
QtObject {
    id: root

    property string wlopm: "wlopm"
    // How long one run of it may take
    property int timeoutMs: 10000
    // The screens Qt knows, [{ name, model, serialNumber }]: where a monitor's id comes from
    property var screens: Quickshell.screens.map(screen => ({ name: screen.name, model: screen.model, serialNumber: screen.serialNumber }))

    // "unknown" until a reading answers; then "found", or "missing" when wlopm could not be
    // started
    property string program: "unknown"
    // [{ connector, id, base, make, model, serial, builtIn, power: "on" | "off" | "unknown" }]
    property var monitors: []
    // Identities seen as twins while the shell runs (MonitorRules.identities)
    property var twins: []
    // The last reading worked
    property bool monitorsRead: false
    // Why the last reading or the last action did not work; "" when it did
    property string readProblem: ""
    property string actionProblem: ""
    // An action is under way (its readings or its command)
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

    // The screens changed: an action's reading under way may name an output that is gone
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
            const command = monitor ? MonitorRules.wlopmCommand(root.wlopm, monitor.connector, action.on) : [];
            if (command.length === 0)
                return root._finish(action, "no connected monitor " + JSON.stringify(String(action.id).slice(0, 120)));
            root._runner.start(command, {
                timeoutMs: root.timeoutMs,
                maxOutputBytes: 4096,
                done: result => {
                    const problem = MonitorRules.dispatchProblem(result, "wlopm");
                    root._readOnce(after => {
                        root._finish(action, problem !== "" ? problem
                                     : root._superseded(action) ? "a newer request came"
                                     : MonitorRules.actionProblem(after?.monitors ?? null, action.id, action.on));
                    });
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

    // One reading of the action's own, published, then handed to `done` (null when it failed)
    function _readOnce(done) {
        _readStamp += 1;
        const stamp = _readStamp;
        const lines = [];
        _runner.start([wlopm, "--json"], {
            timeoutMs: root.timeoutMs,
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
        const found = result?.failedToStart === true ? "missing" : "found";
        if (found !== program) {
            if (found === "missing")
                console.warn("ScreenPower: wlopm could not be started: monitors cannot be turned off here");
            program = found;
        }
        let problem = MonitorRules.readProblem(result, "wlopm");
        const answer = problem === "" ? MonitorRules.wlopmMonitors(lines.join("\n"), Array.from(screens ?? []), twins) : null;
        if (problem === "" && answer === null)
            problem = "wlopm gave no readable answer";
        if (stamp < _publishedStamp)
            return answer;
        _publishedStamp = stamp;
        if (problem !== readProblem && found === "found")
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
        command: [root.wlopm, "--json"]
        timeoutMs: root.timeoutMs
        onAnswered: (lines, result) => root._publish(lines, result, root._queryStamp)
    }

    property CommandRunner _runner: CommandRunner {}
}
