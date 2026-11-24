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
// a reading's answer that comes after a later reading's dropped. Then the connectivity check's
// address the same way, its reading the real scripts/nm-config-files.sh on the scratch tree:
// set in NetworkManager.conf (read before the shell's file), Save, NetworkManager told to read
// its configuration again (a stand-in nmcli under the scratch base), Undo; and NixOS's file
// written only when asked anyway.
// Asynchronous.
TestCase {
    id: suite
    suiteName: "IntegrationChange"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-integration-change-test-" + Date.now()
    readonly property string _kind: "sleep.hibernateDelay"
    // A reading's answer held past its object's end
    property var _late: null
    readonly property string _path: EtcFilesRules.files[_kind]

    property var _arch: null
    property var _change: null
    property var _nixosChange: null
    property var _uriChange: null
    property var _anywayChange: null
    readonly property string _uriKind: "network.connectivityUri"
    readonly property string _address: "http://a.example/check"
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
            _arch = _archComponent.createObject(suite, { start: suite._start, base: _scratch, inForceCommands: {
                [_kind]: merged, [_uriKind]: [Quickshell.shellDir + "/scripts/nm-config-files.sh", _scratch] } });
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
            held.read();
            _late = pending[2];
            held.destroy();
        });
        _then("the object with a reading under way gone", () => _late !== null, () => {
            // Its answer comes after it is gone: dropped, nothing thrown
            _late({ state: "set", value: 60 });
            _late = null;
            _sh("ls -A \"$1/etc/systemd/sleep.conf.d\"");
        });
        _then("the folder looked at", () => _shellOutput !== "", () => {
            assertEqual(_shellOutput, "[0]", "after Undo: no file left in the drop-in folder");
            _finished = [];
            _answer = "run";
            _uriChange = _changeComponent.createObject(suite, { kind: _uriKind, integration: _arch });
            _uriChange.finished.connect((mode, outcome) => suite._finished = suite._finished.concat([{ mode, outcome }]));
            _uriChange.read();
        });
        const uriRead = (state, fileState) => () => _uriChange.inForce !== null && _uriChange.inForce.state === state && _uriChange.inForce.file?.state === fileState;
        const main = "/etc/NetworkManager/NetworkManager.conf";
        _then("the address read: set in NetworkManager.conf", uriRead("set", "absent"), () => {
            assertEqual([_uriChange.inForce.value, _uriChange.inForce.elsewhere, _uriChange.inForce.afterOwn].join(" "), "http://mine/ " + main + " false",
                        "set in NetworkManager.conf, over the package's default, read before the shell's file");
            assert(_uriChange.apply(_address, { current: _uriChange.inForce.file, replace: false }).started, "Save: started");
        });
        _then("the Save answered", () => _finished.length === 1, () => {
            assertEqual(_finished[0].mode + " " + _finished[0].outcome.ok, "apply true", "saved: " + JSON.stringify(_finished[0].outcome));
            assertEqual(_runs[_runs.length - 1], "Change the connectivity check's address", "… the prompt's reason");
            assertEqual(JSON.stringify(_finished[0].outcome.warnings), "[]", "… NetworkManager told: no warning");
        });
        _then("read again: the shell's own file in force", () => uriRead("set", "text")() && _uriChange.inForce.from !== main, () => {
            assertEqual([_uriChange.inForce.value, _uriChange.inForce.from, _uriChange.inForce.elsewhere, _uriChange.inForce.file.ours].join(" "),
                        _address + " " + EtcFilesRules.files[_uriKind] + "  true", "the address from the shell's file, exactly its text, nothing elsewhere");
            assertEqual(JSON.stringify(_uriChange.inForce.shadowed), JSON.stringify({ from: main, value: "http://mine/" }),
                        "… the user's address in NetworkManager.conf it overrides, told");
            _sh("cat \"$1/nmcli.log\"");
        });
        _then("NetworkManager's stand-in looked at", () => _shellOutput !== "", () => {
            assertEqual(_shellOutput, "[0]general reload conf\n", "NetworkManager told to read its configuration again, once");
            assert(_uriChange.undo().started, "Undo: started");
        });
        _then("the Undo answered", () => _finished.length === 2, () => {
            assertEqual(_finished[1].mode + " " + _finished[1].outcome.ok, "undo true", "put back: " + JSON.stringify(_finished[1].outcome));
        });
        _then("read again: NetworkManager.conf's address", () => uriRead("set", "absent")() && _uriChange.inForce.elsewhere === main, () => {
            _sh("cat \"$1/nmcli.log\"; printf '#!/bin/sh\\nexit 1\\n' > \"$1/usr/bin/nmcli\"");
        });
        _then("NetworkManager's stand-in looked at again", () => _shellOutput !== "", () => {
            assertEqual(_shellOutput, "[0]general reload conf\ngeneral reload conf\n", "… and again after Undo");
            _anywayChange = _changeComponent.createObject(suite, { kind: _uriKind, integration: _nixosComponent.createObject(suite, {
                start: suite._start, base: _scratch, inForceCommands: { [_uriKind]: [Quickshell.shellDir + "/scripts/nm-config-files.sh", _scratch] } }) });
            _anywayChange.finished.connect((mode, outcome) => suite._finished = suite._finished.concat([{ mode, outcome }]));
            const runs = _runs.length;
            assertEqual(_anywayChange.apply(_address, {}).refusal?.code, "mode", "NixOS: not written unasked");
            assertEqual(_runs.length, runs, "… nothing run");
            _anywayChange.read();
        });
        _then("NixOS's reading", () => _anywayChange.inForce !== null && _anywayChange.inForce.file?.state === "absent", () => {
            assert(_anywayChange.apply(_address, { current: _anywayChange.inForce.file, anyway: true }).started, "NixOS: written when asked anyway");
        });
        _then("the write answered", () => _finished.length === 3, () => {
            assertEqual(_finished[2].outcome.ok, true, "written: " + JSON.stringify(_finished[2].outcome));
            assertEqual(JSON.stringify(_finished[2].outcome.warnings), JSON.stringify(["NetworkManager did not read its configuration again"]),
                        "… NetworkManager's nmcli failing: a warning in the outcome");
            assertEqual(_anywayChange.undo().refusal?.code, "mode", "… no Undo of it");
            _sh("cat \"$1/etc/NetworkManager/conf.d/90-h2s-connectivity.conf\"; rm \"$1/usr/bin/nmcli\"");
        });
        _then("the file looked at", () => _shellOutput !== "", () => {
            assertEqual(_shellOutput, "[0]" + ConnectivityRules.text(_address), "… the shell's file for the address");
        });
        _then("NixOS's reading again", () => _anywayChange.inForce !== null && _anywayChange.inForce.file?.state === "text", () => {
            assert(_anywayChange.apply("", { current: _anywayChange.inForce.file, anyway: true }).started, "NixOS: the file removed when asked");
        });
        _then("the removal answered", () => _finished.length === 4, () => {
            assertEqual(_finished[3].outcome.ok + " " + _finished[3].outcome.mode, "true remove", "removed: " + JSON.stringify(_finished[3].outcome));
            assertEqual(JSON.stringify(_finished[3].outcome.warnings), JSON.stringify(["no nmcli: NetworkManager did not read its configuration again"]),
                        "… no nmcli at all: that warning");
        });
        _clock.start();
        _sh("set -e; umask 022; mkdir -p \"$1/etc/systemd\" \"$1/etc/NetworkManager\" \"$1/usr/lib/NetworkManager/conf.d\" \"$1/usr/bin\";"
            + " printf '[connectivity]\\nuri=http://ping.example/\\n' > \"$1/usr/lib/NetworkManager/conf.d/20-connectivity.conf\";"
            + " printf '[connectivity]\\nuri=http://mine/\\n' > \"$1/etc/NetworkManager/NetworkManager.conf\";"
            + " printf '#!/bin/sh\\nprintf \"%%s\\\\n\" \"$*\" >> \"%s/nmcli.log\"\\n' \"$1\" > \"$1/usr/bin/nmcli\"; chmod 755 \"$1/usr/bin/nmcli\"",
            code => suite._ready = code === 0);
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
        _uriChange?.destroy();
        _anywayChange?.destroy();
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
