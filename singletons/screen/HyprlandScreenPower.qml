import QtQuick
import qs.singletons
import qs.singletons.io

// Monitors and their power on Hyprland (the shell's one instance is ScreenPower's): reads
// `hyprctl -j monitors` (connector, make, model, serial, `dpmsStatus`) and turns one
// monitor off or on through `hyprctl dispatch` (MonitorRules.hyprlandDpms). The program is a
// property, so a suite points it at a stand-in (tests/ScreenPowerReadingTest.qml).
//
// A failed or unreadable reading leaves the monitors as last read with their power
// "unknown"; a failed dispatch is reported and followed by a reading, like every action, so
// `monitors` says what the compositor has, not what was asked. Problems are logged when the
// outcome changes, not at every attempt.
QtObject {
    id: root

    property string hyprctl: "hyprctl"

    // [{ connector, id, make, model, serial, builtIn, power: "on" | "off" | "unknown" }]
    property var monitors: []
    // Identities two connected monitors shared (MonitorRules.identities)
    property var twins: []
    // The last reading worked
    property bool monitorsRead: false
    // Why the last reading or the last action did not work; "" when it did
    property string readProblem: ""
    property string actionProblem: ""

    // An action ended: the id it was asked for, the power asked, and whether the compositor
    // took it ("" problem)
    signal actionDone(string id, bool on, string problem)

    function read() {
        _query.request();
    }

    // Turns the monitor with this id (from `monitors`) off or on. An id the last reading
    // does not have is refused, never guessed: Hyprland turns every monitor off for a
    // connector it does not know.
    function setPower(id, on) {
        const monitor = monitors.find(entry => entry.id === id);
        const expression = monitor ? MonitorRules.hyprlandDpms(monitor.connector, on) : "";
        if (expression === "") {
            _actionOutcome(id, on, "no connected monitor " + JSON.stringify(String(id).slice(0, 120)));
            return;
        }
        _runner.start([hyprctl, "dispatch", expression], {
            timeoutMs: 10000,
            maxOutputBytes: 4096,
            done: result => {
                root._actionOutcome(id, on, MonitorRules.dispatchProblem(result));
                root.read();
            }
        });
    }

    function _actionOutcome(id, on, problem) {
        if (problem !== actionProblem)
            console.warn("ScreenPower: " + (problem === "" ? "monitors can be turned off and on again" : "a monitor could not be turned " + (on ? "on" : "off") + ": " + problem));
        actionProblem = problem;
        actionDone(id, on, problem);
    }

    property LatestQuery _query: LatestQuery {
        command: [root.hyprctl, "-j", "monitors"]
        timeoutMs: 10000
        onAnswered: (lines, result) => {
            let problem = MonitorRules.readProblem(result);
            const answer = problem === "" ? MonitorRules.hyprlandMonitors(lines.join("\n")) : null;
            if (problem === "" && answer === null)
                problem = "hyprctl gave no readable answer";
            if (problem !== root.readProblem)
                console.warn("ScreenPower: " + (problem === "" ? "the monitors are read again" : "the monitors' power could not be read: " + problem));
            root.readProblem = problem;
            if (answer === null) {
                root.monitors = MonitorRules.unknownPower(root.monitors);
                root.monitorsRead = false;
                return;
            }
            root.monitors = answer.monitors;
            root.twins = answer.twins;
            root.monitorsRead = true;
        }
    }

    property CommandRunner _runner: CommandRunner {}
}
