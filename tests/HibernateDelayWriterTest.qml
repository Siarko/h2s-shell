import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.io

// The Hibernate section's Apply (singletons/io/HibernateDelayWriter.qml), its command run
// for real — the fixed script HibernateRules.applyArgv gives — but through a stand-in for the
// shell's runs as administrator: the suite's `start` runs the words as the user, into a
// scratch directory, and answers as PrivilegedRuns would. Never pkexec, never /etc: the
// writer's `start` and `directory` are the suite's before anything is applied. The drop-in
// written, written again, read back as sleep.conf's delay; a prompt dismissed; a failure; a
// delay refused before any run; one write at a time. Asynchronous.
TestCase {
    id: suite
    suiteName: "HibernateDelayWriter"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-hibernate-delay-test-" + Date.now()

    property var _writer: null
    // What the stand-in was handed: [{ what, argv }]
    property var _runs: []
    // How the stand-in answers the next run: "run" (runs it), "dismissed"
    property string _answer: "run"
    property var _applied: null
    property string _file: ""
    property string _modes: ""
    property bool _ready: false

    property Component _writerComponent: Component {
        HibernateDelayWriter {}
    }

    // The stand-in for PrivilegedRuns.startShell: the words run as the user (no pkexec), with
    // the most open umask a caller could hand on (pkexec keeps the caller's)
    // The words as PrivilegedRuns.startShell runs them after pkexec: under the shell's
    // trusted timeout, with its limit
    function _underTimeout(argv) {
        const words = PrivilegedRules.shellArgv(CommandTools.timeout, Array.from(argv));
        assert(words !== null, "the shell's trusted timeout is known: " + CommandTools.timeout);
        return words === null ? Array.from(argv) : words.slice(1);
    }

    function _start(request, done) {
        _runs.push({ what: request.what, argv: Array.from(request.argv) });
        if (_answer === "dismissed") {
            Qt.callLater(() => done({ ok: false, code: 126, stdout: "", stderr: "", dismissed: true, refused: false, cancelled: false,
                                      blocked: "", error: "" }));
            return;
        }
        const process = _shell.createObject(suite, { command: ["sh", "-c", "umask 000; exec \"$@\"", "sh"].concat(suite._underTimeout(request.argv)), done: null, read: null });
        process.finished.connect((code, stdout, stderr) => done({ ok: code === 0, code: code, stdout: stdout, stderr: stderr, dismissed: false,
                                                                  refused: false, cancelled: false, blocked: "", error: "" }));
        process.running = true;
    }

    property var _steps: []

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
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
            } catch (error) {}
            if (!ready && waited < 10000)
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
        _writer?.destroy();
        _sh("rm -rf \"$1\"", [_scratch], () => suite.finish());
    }

    function _readFile() {
        _file = "";
        _sh("cat \"$1/systemd/sleep.conf.d/h2s-shell.conf\" 2> /dev/null || echo '(none)'", [_scratch], null, text => suite._file = text);
    }

    function runAsync() {
        _then("the scratch directory is there, the shell's timeout looked up", () => _ready && CommandTools.known, () => {
            _writer = _writerComponent.createObject(suite, { directory: _scratch + "/systemd/sleep.conf.d", start: suite._start });
            _writer.applied.connect((seconds, ok, quiet, error) => suite._applied = { seconds: seconds, ok: ok, quiet: quiet, error: error });
            assertEqual(_writerComponent.createObject(suite).directory, "/etc/systemd/sleep.conf.d", "by default: the system's drop-in directory");
            assert(!_writer.apply(59), "a delay under a minute: not started");
            assert(!_writer.apply(7200.5), "… nor one that is not whole seconds");
            assertEqual(_runs.length, 0, "… nothing run");
            assert(_writer.apply(10800), "3 h: started");
            assert(_writer.busy, "… busy");
            assert(!_writer.apply(7200), "… a second while it runs: not started");
        });
        _then("the first write answered", () => _applied !== null, () => {
            assertEqual(JSON.stringify(_applied), JSON.stringify({ seconds: 10800, ok: true, quiet: false, error: "" }), "written");
            assert(!_writer.busy, "… no longer busy");
            assertEqual(_runs.length, 1, "… one run");
            assertEqual(_runs[0].argv[0], "/bin/sh", "… the system's shell, the first word handed to the runs as administrator");
            assertEqual(JSON.stringify(_runs[0].argv.slice(3)), JSON.stringify(["sh", "10800", _scratch + "/systemd/sleep.conf.d"]),
                        "… the delay and the directory as arguments");
            assertEqual(_runs[0].argv[2], HibernateRules.applyScript, "… the fixed script");
            assert(!_runs[0].argv.includes("pkexec"), "… no pkexec in the stand-in's words");
            _readFile();
        });
        _then("the drop-in read", () => _file !== "", () => {
            assertEqual(_file, HibernateRules.dropInText(10800), "the drop-in as the rules say");
            _modes = "";
            _sh("stat -c %a \"$1/systemd\" \"$1/systemd/sleep.conf.d\" \"$1/systemd/sleep.conf.d/h2s-shell.conf\"", [_scratch], null, text => suite._modes = text.trim().split("\n").join(" "));
            assertEqual(JSON.stringify(HibernateRules.hibernateDelay(_file)), JSON.stringify({ state: "set", seconds: 10800, file: "" }),
                        "… read back as sleep.conf's delay");
        });
        _then("the modes read", () => _modes !== "", () => {
            assertEqual(_modes, "755 755 644", "under umask 000: the directories it made 755, the drop-in 644 (writable by root alone)");
            _applied = null;
            assert(_writer.apply(7200), "2 h: started");
        });
        _then("the second write answered", () => _applied !== null, () => {
            assertEqual(_applied.ok, true, "written again");
            _readFile();
        });
        _then("the drop-in read again", () => _file !== "", () => {
            assertEqual(_file, HibernateRules.dropInText(7200), "… replaced whole");
            _sh("ls -a \"$1/systemd/sleep.conf.d\"", [_scratch], null, text => suite._file = "ls:" + text.split("\n").filter(name => name !== "").join(" "));
            _file = "";
        });
        _then("the directory listed", () => _file !== "", () => {
            assertEqual(_file, "ls:. .. h2s-shell.conf", "… no temporary file left beside it");
            _applied = null;
            _answer = "dismissed";
            assert(_writer.apply(3600), "1 h: started");
        });
        _then("the dismissed write answered", () => _applied !== null, () => {
            assertEqual(JSON.stringify(_applied), JSON.stringify({ seconds: 3600, ok: false, quiet: true, error: "" }),
                        "the prompt dismissed: not written, quietly");
            _readFile();
        });
        _then("the drop-in read after the dismissal", () => _file !== "", () => {
            assertEqual(_file, HibernateRules.dropInText(7200), "… the drop-in untouched");
            _answer = "run";
            _applied = null;
            _ready = false;
            // A plain file where the directory should be: the write fails
            _sh("set -e; rm -rf \"$1/systemd/sleep.conf.d\"; touch \"$1/systemd/sleep.conf.d\"", [_scratch], () => {
                suite.assert(suite._writer.apply(1800), "30 min: started");
                suite._ready = true;
            });
        });
        _then("the failing write answered", () => _ready && _applied !== null, () => {
            assertEqual(_applied.ok + " " + _applied.quiet, "false false", "a write that fails: not written, and said");
            assert(_applied.error !== "", "… with the reason: " + _applied.error);
        });
        _clock.start();
        _sh("mkdir -p \"$1\"", [_scratch], code => {
            suite.assertEqual(code, 0, "the scratch directory made");
            suite._ready = true;
        });
    }

    function _sh(script, args, done, read) {
        const process = _shell.createObject(suite, { command: ["sh", "-c", script, "sh"].concat(args), done: done, read: read ?? null });
        process.running = true;
    }

    property Component _shell: Component {
        Process {
            id: _process
            signal finished(int code, string stdout, string stderr)
            property var done: null
            property var read: null
            property bool _exited: false
            property bool _finished: false
            property bool _errorFinished: false
            property int _code: -1
            property string _stdout: ""
            property string _stderr: ""
            function _over() {
                if (!(_exited && _finished && _errorFinished))
                    return;
                _process.finished(_code, _stdout, _stderr);
                _process.destroy();
            }
            stdout: StdioCollector {
                onStreamFinished: {
                    _process._stdout = text;
                    _process.read?.(text);
                    _process._finished = true;
                    _process._over();
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    _process._stderr = text;
                    _process._errorFinished = true;
                    _process._over();
                }
            }
            onExited: code => {
                _process._code = code;
                _process.done?.(code);
                _process._exited = true;
                _process._over();
            }
        }
    }
}
