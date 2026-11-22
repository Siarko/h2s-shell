import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Runs cava for the music visualiser (Visualizer) while `active`, handing each line it
// prints to `levels`. A run that exits — a crash, a library gone — is tried again with a
// backoff (CavaRules.retryDelay); one that could not be started (no cava) is tried again
// only when asked (requestRestart, or `active` turned on again), so nothing is printed at
// each try (CavaRules.retries). A run counts as running once it has given levels for
// `healthyMs`: one that prints a frame and dies stays failed. The outcome is logged when it
// changes, not at each try (CavaRules.logLine). Where it stands is readable (`state`,
// `problem`) for a view of the shell's status. The program is a property, so a suite points
// it at a stand-in (tests/CavaReadingTest.qml).
QtObject {
    id: root

    property string program: "cava"
    property string configPath: ""
    property bool active: false
    // The first retry after this, doubled at each failure in a row up to the most
    property int retryMs: 2000
    property int retryMostMs: 60000
    // How long a run gives levels before it counts as running: the failures start over
    // and "runs again" is logged then
    property int healthyMs: 5000

    // "stopped" (not active), "starting" (started, not running yet), "running" (it has
    // given levels for a while), "failed" (the last run ended; tried again after a while,
    // or when asked if it could not be started)
    readonly property string state: _state
    // Why the last run ended, while it is "failed"; else ""
    readonly property string problem: _problem
    // Failed runs in a row
    readonly property int failures: _failures
    // Runs started
    readonly property int runs: _runsStarted

    signal levels(string line)
    // A line was logged (the outcome changed)
    signal logged(string line)

    property string _state: "stopped"
    property string _problem: ""
    property int _failures: 0
    property int _runsStarted: 0
    // The outcome last logged: "" while fine
    property string _loggedProblem: ""
    // Each run's number: a line or an end from a run that is no longer current is dropped
    property int _run: 0
    property QtObject _current: null
    // Runs left behind by a restart that have ended since (their ends dropped)
    property int _oldRunsEnded: 0
    property bool _restartQueued: false

    onActiveChanged: requestRestart()
    onConfigPathChanged: if (active) requestRestart()

    // Starts cava afresh while active (stopping the run there is), else stops it — once,
    // however often it is asked in one turn
    function requestRestart() {
        if (_restartQueued)
            return;
        _restartQueued = true;
        Qt.callLater(root._queuedRestart);
    }

    function _queuedRestart() {
        _restartQueued = false;
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

    // The current run is asked to end; it goes once it has (_ended)
    function _stop() {
        const current = _current;
        _current = null;
        _run += 1;
        _healthy.stop();
        if (current !== null)
            current.process.running = false;
    }

    function _start() {
        _runsStarted += 1;
        _run += 1;
        _current = _runComponent.createObject(root, { run: _run });
        _current.process.command = [program, "-p", configPath];
        _current.process.running = true;
    }

    function _line(run, line) {
        if (run !== _run)
            return;
        if (!_current.sawLevels) {
            _current.sawLevels = true;
            _healthy.interval = healthyMs;
            _healthy.restart();
        }
        levels(line);
    }

    // The current run has given levels for a while
    function _isHealthy() {
        if (_current === null || !active)
            return;
        _state = "running";
        _failures = 0;
        _problem = "";
        _log("");
    }

    function _ended(run, exited, code, crashed, stderr) {
        if (run !== _run) {
            _oldRunsEnded += 1;
            return;
        }
        _current = null;
        _healthy.stop();
        if (!active)
            return;
        _failures += 1;
        _problem = CavaRules.problem(exited, code, crashed, stderr);
        _state = "failed";
        _log(_problem);
        if (CavaRules.retries(exited)) {
            _retry.interval = CavaRules.retryDelay(_failures, retryMs, retryMostMs);
            _retry.restart();
        }
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
        onTriggered: if (root.active && root._current === null) root._start()
    }

    property Timer _healthy: Timer {
        onTriggered: root._isHealthy()
    }

    property Component _runComponent: Component {
        QtObject {
            id: run
            property int run: 0
            property bool sawLevels: false
            property bool exited: false
            property int code: -1
            property bool crashed: false
            // The first few lines it printed on stderr, for the problem
            property var stderrLines: []

            function finish() {
                root._ended(run.run, exited, code, crashed, stderrLines);
                destroy();
            }

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
                // Ended, started or not: handled after the exit status, when there is one
                // (a method of the run's, so nothing is called if the run is gone by then),
                // then the run goes
                onRunningChanged: if (!running) Qt.callLater(run.finish)
            }
        }
    }
}
