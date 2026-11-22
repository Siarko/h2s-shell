import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Runs cava for the music visualiser (Visualizer) while `active`, handing each line it
// prints to `levels`. A run that fails — cava missing, unable to start, exiting or
// crashing — is tried again with a backoff (CavaRules.retryDelay), and the outcome is
// logged when it changes, not at each try (CavaRules.logLine). Where it stands is
// readable (`state`, `problem`) for a view of the shell's status. The program is a
// property, so a suite points it at a stand-in (tests/CavaReadingTest.qml).
QtObject {
    id: root

    property string program: "cava"
    property string configPath: ""
    property bool active: false
    // The first retry after this, doubled at each failure in a row up to the most; a run
    // that gives levels starts it over
    property int retryMs: 2000
    property int retryMostMs: 60000

    // "stopped" (not active), "starting" (started, no levels yet), "running" (levels
    // came), "failed" (the last run ended; tried again after a while)
    readonly property string state: _state
    // Why the last run ended, while it is "failed"; else ""
    readonly property string problem: _problem
    // Failed runs in a row
    readonly property int failures: _failures

    signal levels(string line)
    // A line was logged (the outcome changed)
    signal logged(string line)

    property string _state: "stopped"
    property string _problem: ""
    property int _failures: 0
    // The outcome last logged: "" while fine
    property string _loggedProblem: ""
    // Each run's number: an end or a line from a run that is no longer current is dropped
    property int _run: 0
    property QtObject _current: null

    onActiveChanged: restart()
    onConfigPathChanged: if (active) restart()

    // Starts cava afresh while active (stopping the run there is), else stops it
    function restart() {
        _stop();
        _retry.stop();
        if (!active) {
            _state = "stopped";
            _failures = 0;
            return;
        }
        if (_state !== "failed")
            _state = "starting";
        _start();
    }

    function _stop() {
        const current = _current;
        _current = null;
        _run += 1;
        if (current !== null) {
            current.process.running = false;
            current.destroy();
        }
    }

    function _start() {
        _run += 1;
        _current = _runComponent.createObject(root, { run: _run });
        _current.process.command = [program, "-p", configPath];
        _current.process.running = true;
    }

    function _line(run, line) {
        if (run !== _run)
            return;
        if (_state !== "running") {
            _state = "running";
            _failures = 0;
            _problem = "";
            _log("");
        }
        levels(line);
    }

    function _ended(run, exited, code, crashed, stderr) {
        if (run !== _run || !active)
            return;
        const current = _current;
        _current = null;
        current?.destroy();
        _failures += 1;
        _problem = CavaRules.problem(exited, code, crashed, stderr);
        _state = "failed";
        _log(_problem);
        _retry.interval = CavaRules.retryDelay(_failures, retryMs, retryMostMs);
        _retry.restart();
    }

    function _log(problem) {
        const line = CavaRules.logLine(_loggedProblem, problem);
        _loggedProblem = problem;
        if (line === "")
            return;
        if (problem === "")
            console.log("Visualizer: " + line);
        else
            console.warn("Visualizer: " + line);
        logged(line);
    }

    property Timer _retry: Timer {
        onTriggered: if (root.active) root._start()
    }

    property Component _runComponent: Component {
        QtObject {
            id: run
            property int run: 0
            property bool exited: false
            property int code: -1
            property bool crashed: false
            // The first few lines it printed on stderr, for the problem
            property var stderrLines: []

            property Process process: Process {
                stdout: SplitParser {
                    onRead: line => root._line(run.run, line)
                }
                stderr: SplitParser {
                    onRead: line => {
                        if (run.stderrLines.length < 5)
                            run.stderrLines = run.stderrLines.concat([line]);
                    }
                }
                onExited: (exitCode, exitStatus) => {
                    run.exited = true;
                    run.code = exitCode;
                    run.crashed = exitStatus !== 0;
                }
                // Ended, started or not: after the exit status, when there is one
                // (a run no longer current may be gone by then: its number decides first)
                onRunningChanged: {
                    if (running)
                        return;
                    const number = run.run;
                    Qt.callLater(() => {
                        if (number === root._run)
                            root._ended(number, run.exited, run.code, run.crashed, run.stderrLines);
                    });
                }
            }
        }
    }
}
