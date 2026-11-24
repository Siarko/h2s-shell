import QtQuick
import Quickshell
import Quickshell.Io
import qs.distributions.arch
import qs.distributions.nixos
import qs.singletons
import qs.singletons.io

// A change kind made through a distribution's integration (singletons/io/IntegrationChange.qml),
// as the Hibernate section's Apply and Undo make it: Arch's integration with its EtcFiles' root
// step run for real (scripts/root/etc-files.sh, the text as the shell reads it) through a
// stand-in for the shell's runs as administrator — the words run as the user, under a scratch
// base; never pkexec, never /etc — and its readInForce's merged reading a stand-in that prints
// the scratch drop-in under the system's path, as `systemd-analyze cat-config` does. Covered:
// the capability; what is in force read (none, then the shell's own); Apply with the file as
// read, busy meanwhile, a second refused; the reading again after it; Undo of it, and none
// left after; a prompt dismissed (quiet, nothing to undo); NixOS's copy refused before any run;
// a reading's answer that comes after a later reading's dropped.
// Asynchronous.
TestCase {
    id: suite
    suiteName: "IntegrationChange"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-integration-change-test-" + Date.now()
    readonly property string _kind: "sleep.hibernateDelay"
    readonly property string _path: EtcFilesRules.files[_kind]

    property var _arch: null
    property var _change: null
    property var _nixosChange: null
    property var _runs: []
    property var _finished: []
    // How the stand-in answers the next run: "run" or "dismissed"
    property string _answer: "run"
    property bool _ready: false
    property string _shellOutput: ""

    property Component _archComponent: Component {
        ArchIntegration {}
    }
    property Component _nixosComponent: Component {
        NixosIntegration {}
    }
    property Component _changeComponent: Component {
        IntegrationChange {}
    }

    // The words as PrivilegedRuns.startShell runs them after pkexec: under the shell's
    // trusted timeout, as the user
    function _start(request, done) {
        _runs = _runs.concat([request.what]);
        if (_answer === "dismissed") {
            Qt.callLater(() => done({ ok: false, code: 126, stdout: "", stderr: "", dismissed: true, refused: false, cancelled: false, blocked: "", error: "" }));
            return;
        }
        const words = PrivilegedRules.shellArgv(CommandTools.timeout, Array.from(request.argv));
        _exec(words === null ? Array.from(request.argv) : words.slice(1), (code, stdout, stderr) =>
            done({ ok: code === 0, code, stdout, stderr, dismissed: false, refused: false, cancelled: false, blocked: "", error: "" }));
    }

    function _inForceIs(state, fileState) {
        return _change.inForce !== null && _change.inForce.state === state && _change.inForce.file?.state === fileState;
    }

    function runAsync() {
        _then("the scratch tree made, the shell's timeout looked up", () => _ready && CommandTools.known, () => {
            const merged = ["sh", "-c", "printf '# %s\\n' \"$1\"; cat -- \"$0\" 2> /dev/null; true", _scratch + _path, _path];
            _arch = _archComponent.createObject(suite, { start: suite._start, base: _scratch, inForceCommands: { [_kind]: merged } });
            _change = _changeComponent.createObject(suite, { kind: _kind, integration: _arch });
            _change.finished.connect((mode, outcome) => suite._finished = suite._finished.concat([{ mode, outcome }]));
            assertEqual([_change.capability.mode, _change.capability.undo].join(" "), "apply true", "Arch's capability: applied, with Undo");
            assertEqual(_change.inForce, null, "nothing read yet");
            assert(!_change.undoable && _change.busy === "", "… nothing to undo, nothing running");
            assertEqual(_change.undo().refusal?.code, "noUndo", "Undo before a change: refused");
            const defaultChange = _changeComponent.createObject(suite, { kind: _kind });
            assert(defaultChange.integration === Distribution, "by default: the system's integration, through Distribution");
            defaultChange.destroy();
            _change.read();
        });
        _then("what is in force read: no file", () => _inForceIs("default", "absent"), () => {
            assertEqual(_change.inForce.elsewhere, "", "… set nowhere else");
            const started = _change.apply(10800, { current: _change.inForce.file, replace: false });
            assert(started.started, "Apply: started");
            assertEqual(_change.busy, "apply", "… busy while it runs");
            assertEqual(_change.inForce, null, "… what was read dropped while it runs");
            assertEqual(_change.apply(7200, {}).refusal?.code, "busy", "… a second meanwhile: refused");
            assertEqual(_change.undo().refusal?.code, "busy", "… Undo meanwhile: refused");
        });
        _then("the Apply answered", () => _finished.length === 1, () => {
            assertEqual(_finished[0].mode + " " + _finished[0].outcome.ok, "apply true", "applied: " + JSON.stringify(_finished[0].outcome));
            assert(_change.busy === "" && _change.undoable, "… done, Undo possible");
            assertEqual(_runs.join("|"), "Change the time before hibernating", "… one run, the prompt's reason");
        });
        _then("read again after it: the shell's own file in force", () => _inForceIs("set", "text"), () => {
            assertEqual(_change.inForce.value + " " + _change.inForce.from + " " + _change.inForce.file.ours, "10800 " + _path + " true",
                        "the delay written, from the shell's own file, exactly its text");
            assertEqual(_change.inForce.elsewhere, "", "… not set elsewhere");
            assert(_change.undo().started, "Undo: started");
            assertEqual(_change.busy, "undo", "… busy while it runs");
            assertEqual(_change.inForce, null, "… what was read dropped while it runs");
        });
        _then("the Undo answered", () => _finished.length === 2, () => {
            assertEqual(_finished[1].mode + " " + _finished[1].outcome.ok, "undo true", "put back: " + JSON.stringify(_finished[1].outcome));
            assert(!_change.undoable, "… nothing more to undo");
        });
        _then("read again after it: no file", () => _inForceIs("default", "absent"), () => {
            _answer = "dismissed";
            assert(_change.apply(7200, { current: _change.inForce.file }).started, "Apply again: started");
        });
        _then("the prompt dismissed", () => _finished.length === 3, () => {
            assertEqual(_finished[2].outcome.ok + " " + _finished[2].outcome.quiet, "false true", "dismissed: not ok, quiet");
            assert(!_change.undoable && _change.busy === "", "… nothing to undo, not busy");
            _nixosChange = _changeComponent.createObject(suite, { kind: _kind, integration: _nixosComponent.createObject(suite) });
            const runs = _runs.length;
            assertEqual(_nixosChange.capability.mode, "copy", "NixOS's capability: the option to copy");
            assertEqual(_nixosChange.apply(10800, {}).refusal?.code, "mode", "… Apply refused");
            assert(_nixosChange.busy === "" && _runs.length === runs, "… nothing run, not busy");
            // Late answers lose: an integration whose readings answer when the suite says
            const pending = [];
            const held = _changeComponent.createObject(suite, { kind: _kind, integration: {
                capability: kind => IntegrationRules.unknownCapability(),
                readInForce: (kind, done) => pending.push(done)
            } });
            held.read();
            held.read();
            pending[1]({ state: "set", value: 7200 });
            pending[0]({ state: "set", value: 3600 });
            assertEqual(held.inForce?.value, 7200, "two readings: the later one's answer kept, the earlier one's dropped");
            held.destroy();
            _sh("ls -A \"$1/etc/systemd/sleep.conf.d\"");
        });
        _then("the folder looked at", () => _shellOutput !== "", () => {
            assertEqual(_shellOutput, "[0]", "after Undo: no file left in the drop-in folder");
        });
        _clock.start();
        _sh("set -e; umask 022; mkdir -p \"$1/etc/systemd\"", code => suite._ready = code === 0);
    }

    function _sh(script, done) {
        _shellOutput = "";
        _exec(["sh", "-c", script, "sh", _scratch], (code, stdout) => {
            suite._shellOutput = "[" + code + "]" + stdout;
            done?.(code, stdout);
        });
    }

    // ---- A tiny scheduler: each step waits for its condition (or its deadline), then runs ----
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
            if (!ready) {
                suite.fail("timed out waiting: " + step.description);
                suite._steps = [];
                return;
            }
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    function _end() {
        _change?.destroy();
        _nixosChange?.destroy();
        _arch?.destroy();
        _exec(["rm", "-rf", "--", _scratch], () => suite.finish());
    }

    function _exec(command, done) {
        const process = _shell.createObject(suite, { command: command });
        process.finished.connect((code, stdout, stderr) => done?.(code, stdout, stderr));
        process.running = true;
    }

    property Component _shell: Component {
        Process {
            id: _process
            signal finished(int code, string stdout, string stderr)
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
                _process._exited = true;
                _process._over();
            }
        }
    }
}
