import QtQuick
import Quickshell
import Quickshell.Io
import qs.distributions
import qs.singletons

// EtcFiles (distributions/EtcFiles.qml), its root step run for real — scripts/root/
// replace-lib.sh, replace-file.sh and etc-files.sh, the text handed over exactly the three
// files joined — but through a stand-in for the shell's runs as administrator: the suite's
// `start` runs the words as the user, under a scratch base holding the system's tree. Never
// pkexec, never /etc: the EtcFiles' `start` and `base` are the suite's before anything runs,
// and its reads go through the real scripts/pam-files.sh, as the user. Covered: the file read
// (none, the shell's); written where there was none (its folder made, modes, a backup of no
// file, no temporary file left), written again over the shell's own (its backup the old
// text); one run at a time; Undo of the last change; a file the shell did not write left
// alone until `replace`; a file changed since it was read refused by the root step and read
// again; removed, and that undone; a prompt dismissed; a queue that throws; a script that
// cannot be read refused before any run; the script's own checks (as root only the system's
// places, a kind it does not know, a text not the shell's, a folder others may write in, a
// link). Asynchronous.
TestCase {
    id: suite
    suiteName: "EtcFiles"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-etc-files-test-" + Date.now()
    readonly property string _kind: "sleep.hibernateDelay"
    readonly property string _file: _scratch + "/etc/systemd/sleep.conf.d/h2s-shell.conf"
    readonly property string _backups: _scratch + "/var/lib/h2s-shell/backup/sleep.hibernateDelay"
    readonly property string _first: HibernateRules.dropInText(10800)
    readonly property string _second: HibernateRules.dropInText(7200)
    readonly property string _foreign: "[Sleep]\nHibernateDelaySec=1h\n"

    property var _files: null
    property var _runs: []
    // How the stand-in answers the next run: "run", "dismissed", "throw"
    property string _answer: "run"
    property var _outcome: null
    property var _read: null
    property var _direct: null
    property string _shellOutput: ""
    property bool _ready: false
    property string _script: ""

    property Component _filesComponent: Component {
        EtcFiles {}
    }

    // The words as PrivilegedRuns.startShell runs them after pkexec: under the shell's
    // trusted timeout, as the user, with the most open umask a caller could hand on
    function _underTimeout(argv) {
        const words = PrivilegedRules.shellArgv(CommandTools.timeout, Array.from(argv));
        assert(words !== null, "the shell's trusted timeout is known: " + CommandTools.timeout);
        return words === null ? Array.from(argv) : words.slice(1);
    }

    function _start(request, done) {
        if (_answer === "throw")
            throw new Error("no queue");
        if (_answer === "answerThenThrow") {
            // Answers at once, twice, then throws
            const dismissed = { ok: false, code: 126, stdout: "", stderr: "", dismissed: true, refused: false, cancelled: false, blocked: "", error: "" };
            done(dismissed);
            done(dismissed);
            throw new Error("after answering");
        }
        _runs.push({ what: request.what, argv: Array.from(request.argv) });
        if (_answer === "dismissed") {
            Qt.callLater(() => done({ ok: false, code: 126, stdout: "", stderr: "", dismissed: true, refused: false, cancelled: false, blocked: "", error: "" }));
            return;
        }
        _exec(["sh", "-c", "umask 000; exec \"$@\"", "sh"].concat(_underTimeout(request.argv)), (code, stdout, stderr) =>
            done({ ok: code === 0, code, stdout, stderr, dismissed: false, refused: false, cancelled: false, blocked: "", error: "" }));
    }

    function _write(text, handlers) {
        _outcome = null;
        return _files.write(_kind, text, Object.assign({ done: outcome => suite._outcome = outcome }, handlers ?? {}));
    }

    function _readFile() {
        _read = null;
        _files.read(_kind, answer => suite._read = answer);
    }

    function _sh(script, done) {
        _shellOutput = "";
        _exec(["sh", "-c", script, "sh", _scratch], (code, stdout) => {
            suite._shellOutput = "[" + code + "]" + stdout;
            done?.(code, stdout);
        });
    }

    function runAsync() {
        _then("the scratch tree made, the script read, the shell's timeout looked up", () => _ready && _script !== "" && CommandTools.known, () => {
            const fresh = _filesComponent.createObject(suite);
            assertEqual(fresh.base + "|" + (fresh.start === null), "|true", "by default: the system's places, the shell's runs as administrator");
            assertEqual(fresh.scriptsDirectory, Quickshell.shellDir + "/scripts/root", "… the script from the shell's tree");
            fresh.destroy();
            const live = _filesComponent.createObject(suite, { base: _scratch });
            assertEqual(live.write(_kind, _first, {}).refusal?.code, "paths", "the shell's runs as administrator with a scratch base: refused");
            live.destroy();
            const unread = _filesComponent.createObject(suite, { base: _scratch, start: suite._start, scriptsDirectory: _scratch + "/none" });
            assertEqual(unread.write(_kind, _first, {}).refusal?.code, "script", "the script not there: refused");
            unread.destroy();
            _files = _filesComponent.createObject(suite, { base: _scratch, start: suite._start });
            assertEqual(_files.write(_kind, _foreign, {}).refusal?.code, "text", "a text the shell does not write: refused before any read");
            assertEqual(_files.write("pam.rules", _first, {}).refusal?.code, "kind", "a kind it does not know: refused");
            assertEqual(_runs.length, 0, "… nothing run");
            _readFile();
        });
        _then("the file read where there is none", () => _read !== null, () => {
            assertEqual(_read.state, "absent", "no file: absent");
            const started = _write(_first);
            assert(started.started, "written: started");
            assert(_files.busy, "… busy while it reads and runs");
            assertEqual(_write(_second).refusal?.code, "busy", "… a second meanwhile: refused");
        });
        _then("the first write answered", () => _outcome !== null, () => {
            assertEqual(_outcome.ok, true, "written: " + JSON.stringify(_outcome));
            assertEqual(_outcome.sha256, PamEditRules.sha256(_first), "… what is in force");
            assert(/^h2s-shell\.conf\.[0-9]{8}T[0-9]{6}Z\.absent$/.test(_outcome.backup), "… a backup of no file: " + _outcome.backup);
            assert(!_files.busy, "… no longer busy");
            assertEqual(_runs.length, 1, "… one run");
            assertEqual(_runs[0].what, "Change the time before hibernating", "… the prompt's reason");
            assertEqual(_runs[0].argv[2], _script, "… the script: the three files joined, exactly as the files have them");
            assertEqual(JSON.stringify(_runs[0].argv.slice(3, 9)), JSON.stringify(["sh", _scratch, "write", _kind, PamEditRules.sha256(_first), "absent"]),
                        "… the base, write, the kind, the sha256, the file as read");
            assert(!_runs[0].argv.includes("pkexec"), "… no pkexec in the stand-in's words");
            _sh("cat \"$1/etc/systemd/sleep.conf.d/h2s-shell.conf\"; stat -c %a \"$1/etc/systemd/sleep.conf.d\" \"$1/etc/systemd/sleep.conf.d/h2s-shell.conf\" "
                + "\"$1/var/lib/h2s-shell/backup/sleep.hibernateDelay\" \"$1/var/lib/h2s-shell/backup/sleep.hibernateDelay/\"*.absent; ls -A \"$1/etc/systemd/sleep.conf.d\"");
        });
        _then("the file and modes read", () => _shellOutput !== "", () => {
            assertEqual(_shellOutput, "[0]" + _first + "755\n644\n700\n600\nh2s-shell.conf\n",
                        "the text; under umask 000 its folder 755, the file 644, the backups 700 and each 600; no temporary file left");
            _readFile();
        });
        _then("the shell's file read", () => _read !== null, () => {
            assertEqual(JSON.stringify(_read), JSON.stringify({ state: "text", text: _first, sha256: PamEditRules.sha256(_first), ours: true }), "read: the shell's text");
            assert(_write(_second, { current: _read }).started, "written again, from what was read: started");
        });
        _then("the second write answered", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.sha256, "true " + PamEditRules.sha256(_second), "written again");
            assert(!_outcome.backup.endsWith(".absent"), "… its backup the old file");
            _sh("cat \"$1/var/lib/h2s-shell/backup/sleep.hibernateDelay/" + _outcome.backup + "\"");
        });
        _then("the backup read", () => _shellOutput !== "", () => {
            assertEqual(_shellOutput, "[0]" + _first, "the backup: the text it replaced");
            _outcome = null;
            assert(_files.undo(_kind, { done: outcome => suite._outcome = outcome }).started, "Undo of the last change: started");
        });
        _then("Undo answered", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.mode + " " + _outcome.sha256, "true undo " + PamEditRules.sha256(_first), "undone: the first text in force");
            assertEqual(_runs[_runs.length - 1].what, "Undo the change to the time before hibernating", "… the prompt's reason");
            _sh("cat \"$1/etc/systemd/sleep.conf.d/h2s-shell.conf\"");
        });
        _then("the file read after Undo", () => _shellOutput !== "", () => {
            assertEqual(_shellOutput, "[0]" + _first, "… the file as it was");
            // The shell's file edited by hand: the user's now
            _outcome = null;
            _sh("printf '# mine\\n' >> \"$1/etc/systemd/sleep.conf.d/h2s-shell.conf\"", () => suite._write(suite._second));
        });
        _then("a write over the shell's file edited by hand answered", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.refused + " " + _outcome.current?.ours, "false other false", "an edit of the shell's file: not replaced without asking");
            _sh("printf '%s' '" + _foreign + "' > \"$1/etc/systemd/sleep.conf.d/h2s-shell.conf\"");
        });
        _then("a file not the shell's put in place", () => _shellOutput !== "", () => {
            const before = _runs.length;
            assert(_write(_first).started, "written over a file the shell did not write: started (it reads first)");
            suite._then("… answered", () => _outcome !== null, () => {
                assertEqual(_outcome.ok + " " + _outcome.refused, "false other", "refused: never replaced without asking");
                assertEqual(_outcome.file, "unchanged", "… the file unchanged");
                assertEqual(_runs.length, before, "… nothing run");
                assert(!_files.busy, "… not busy");
                assert(_write(_first, { replace: true }).started, "with `replace` (the user told): started");
            });
            suite._then("… replaced", () => _outcome !== null, () => {
                assertEqual(_outcome.ok, true, "written over it");
                _readFile();
            });
            suite._then("… read", () => _read !== null, () => {
                assertEqual(_read.text, _first, "… the shell's text in force");
                const stale = _read;
                _outcome = null;
                _sh("printf '%s' '" + _second + "' > \"$1/etc/systemd/sleep.conf.d/h2s-shell.conf\"", () => suite._write(suite._foreignShell(), { current: stale }));
            });
            suite._then("… a write from a stale read answered", () => _outcome !== null, () => {
                assertEqual(_outcome.ok + " " + _outcome.refused, "false changed", "the file changed since it was read: refused by the root step");
                assertEqual(_outcome.error, EtcFilesRules.texts.changed, "… with its reason");
                assertEqual(_outcome.file, "other", "… read again: neither the state it expected nor the new text");
                _outcome = null;
                assert(_files.remove(_kind, { done: outcome => suite._outcome = outcome }).started, "removed: started");
            });
            suite._then("… removed", () => _outcome !== null, () => {
                assertEqual(_outcome.ok + " " + _outcome.sha256, "true absent", "removed: no file in force");
                assertEqual(_runs[_runs.length - 1].what, "Go back to the system's time before hibernating", "… the prompt's reason");
                _outcome = null;
                assert(_files.undo(_kind, { done: outcome => suite._outcome = outcome }).started, "the removal undone: started");
            });
            suite._then("… the removal undone", () => _outcome !== null, () => {
                assertEqual(_outcome.ok + " " + _outcome.sha256, "true " + PamEditRules.sha256(_second), "the file back");
                _answer = "dismissed";
                _readFile();
            });
            suite._then("… read before a dismissed run", () => _read !== null, () => {
                assert(_write(_first, { current: _read }).started, "a run whose prompt is dismissed: started");
            });
            suite._then("… the dismissed run answered", () => _outcome !== null, () => {
                assertEqual(_outcome.ok + " " + _outcome.quiet, "false true", "dismissed: quietly not written");
                assertEqual(_outcome.file, "unchanged", "… the file read again: unchanged");
                _answer = "throw";
                assertEqual(_write(_first, { current: { state: "text", text: _second, sha256: PamEditRules.sha256(_second), ours: true } }).refusal?.code, "start",
                            "a queue that throws: refused");
                assert(!_files.busy, "… not left busy");
                assertEqual(_files.run({ what: "x", argv: ["/bin/true"], reply: () => ({ ok: true }), readBack: [], done: () => {} }), "start", "… run() too");
                assert(!_files.busy, "… nor by run()");
                _answer = "answerThenThrow";
                let answers = 0;
                assertEqual(_files.run({ what: "x", argv: ["/bin/true"], reply: result => ({ ok: result.dismissed !== true }), readBack: [], done: () => answers++ }), "",
                            "a queue that answers, then throws: the answer stands");
                assertEqual(answers + " " + _files.busy, "1 false", "… taken once, not busy");
                _answer = "run";
                assertEqual(_files.run({ what: "x", argv: ["/bin/true"], reply: () => { throw new Error("bad reply"); }, readBack: [], done: () => answers++ }), "",
                            "an answer that cannot be read: started");
                suite._then("… the unreadable answer handed over", () => answers === 2, () => {
                    assert(!_files.busy, "an answer that could not be read: not left busy");
                    suite._directChecks();
                });
            });
        });
        _clock.start();
        _sh("set -e; umask 022; mkdir -p \"$1/etc/systemd\" \"$1/bin\"; printf '#!/bin/sh\\necho 0\\n' > \"$1/bin/id\"; chmod +x \"$1/bin/id\"", code => {
            suite.assertEqual(code, 0, "the scratch tree made");
            suite._ready = true;
        });
        const root = Quickshell.shellDir + "/scripts/root/";
        _exec(["cat", "--", root + "replace-lib.sh", root + "replace-file.sh", root + "etc-files.sh"], (code, stdout) => suite._script = code === 0 ? stdout : "");
    }

    // A text the shell writes, other than what is there
    function _foreignShell() {
        return HibernateRules.dropInText(3600);
    }

    // The script's own checks, run directly as the user
    function _directChecks() {
        const sum = PamEditRules.sha256(_first);
        const cases = [
            { words: [_scratch, "write", _kind, sum, "absent", _first], id: "0", want: "refused paths", why: "as root, a scratch base: refused" },
            { words: ["", "write", _kind, sum, "absent", _first], id: null, want: "refused paths", why: "as the user, the system's places: refused" },
            { words: [_scratch, "write", "pam.rules", sum, "absent", _first], id: null, want: "refused arguments", why: "a kind it does not know: refused" },
            { words: [_scratch, "write", _kind, PamEditRules.sha256(_foreign), "absent", _foreign], id: null, want: "refused arguments", why: "a text without the marker: refused" },
            { words: [_scratch, "write", _kind, sum, "absent", _first.slice(0, -1)], id: null, want: "refused arguments", why: "a text without its last line break: refused" },
            { words: [_scratch, "write", _kind, PamEditRules.sha256(_first + "# more\n"), "absent", _first + "# more\n"], id: null, want: "refused arguments",
              why: "the shell's text with a line added: refused" },
            { words: [_scratch, "write", _kind, PamEditRules.sha256(_first.replace("10800", "010800")), "absent", _first.replace("10800", "010800")], id: null,
              want: "refused arguments", why: "a value with a leading zero: refused" },
            { words: [_scratch, "write", _kind, PamEditRules.sha256(_second), PamEditRules.sha256(_second), _first], id: null, want: "refused hash",
              why: "bytes that are not the sha256 given: refused" },
            { words: (text => [_scratch, "write", "network.connectivityUri", PamEditRules.sha256(text), "absent", text])(ConnectivityRules.text("http://a/b c")), id: null,
              want: "refused arguments", why: "the connectivity check's address with a blank in the path: refused" },
            { words: (text => [_scratch, "write", "network.connectivityUri", PamEditRules.sha256(text), "absent", text])(ConnectivityRules.text("http://a/\"x")), id: null,
              want: "refused arguments", why: "the connectivity check's address with a quote: refused" },
            { words: (text => [_scratch, "write", "network.connectivityUri", PamEditRules.sha256(text), "absent", text])(ConnectivityRules.text("http://a/x'y")), id: null,
              want: "refused arguments", why: "the connectivity check's address with an apostrophe: refused" },
            { words: (text => [_scratch, "write", "network.connectivityUri", PamEditRules.sha256(text), "absent", text])(ConnectivityRules.text("http://a/x\\y")), id: null,
              want: "refused arguments", why: "the connectivity check's address with a backslash: refused" },
            { words: (text => [_scratch, "write", "network.connectivityUri", PamEditRules.sha256(text), "absent", text])(ConnectivityRules.text("http://a/x\u0001y")), id: null,
              want: "refused arguments", why: "the connectivity check's address with a control character: refused" },
            { words: (text => [_scratch, "write", "network.connectivityUri", PamEditRules.sha256(text), "absent", text])(ConnectivityRules.text("ftp://a/x")), id: null,
              want: "refused arguments", why: "the connectivity check's address with another scheme: refused" },
            { words: (text => [_scratch, "write", "network.connectivityUri", PamEditRules.sha256(text), "absent", text])(ConnectivityRules.text("http:///x")), id: null,
              want: "refused arguments", why: "the connectivity check's address with no host: refused" },
            { words: (text => [_scratch, "write", "network.connectivityUri", PamEditRules.sha256(text), "absent", text])(ConnectivityRules.text("http://a_b/x")), id: null,
              want: "refused arguments", why: "the connectivity check's address with a host with another character: refused" },
            { words: (text => [_scratch, "write", "network.connectivityUri", PamEditRules.sha256(text), "absent", text])(ConnectivityRules.text("http://a:/x")), id: null,
              want: "refused arguments", why: "the connectivity check's address with an empty port: refused" },
            { words: (text => [_scratch, "write", "network.connectivityUri", PamEditRules.sha256(text), "absent", text])(ConnectivityRules.text("http://a:8x/x")), id: null,
              want: "refused arguments", why: "the connectivity check's address with a port not a number: refused" },
            { words: (text => [_scratch, "write", "network.connectivityUri", PamEditRules.sha256(text), "absent", text])(ConnectivityRules.text("http://a/x").replace("[connectivity]", "[connectivity]\\nenabled=false")), id: null,
              want: "refused arguments", why: "the connectivity check's file with a line added: refused" },
            { words: [_scratch, "undo", _kind, "h2s-shell.conf.x", "absent"], id: null, want: "refused arguments", why: "a backup name not its own: refused" },
            { words: [_scratch, "undo", _kind, "h2s-shell.conf.20000101T000000Z", PamEditRules.sha256(_second)], id: null, want: "refused nobackup", why: "a backup not there: refused" },
            { setup: "chmod 0775 \"$1/etc/systemd\"", words: [_scratch, "write", _kind, sum, PamEditRules.sha256(_second), _first], id: null, want: "refused owner",
              why: "a folder others may write in: refused" },
            { setup: "chmod 0755 \"$1/etc/systemd\"; rm \"$1/etc/systemd/sleep.conf.d/h2s-shell.conf\"; ln -s /dev/null \"$1/etc/systemd/sleep.conf.d/h2s-shell.conf\"",
              words: [_scratch, "write", _kind, sum, "absent", _first], id: null, want: "refused link", why: "the file a link: refused" }
        ];
        const next = () => {
            const check = cases.shift();
            if (check === undefined)
                return;
            suite._then("the script's check: " + check.why, () => suite._direct !== null, () => {
                suite.assertEqual(suite._direct.code + " " + suite._direct.stderr, "3 " + check.want, check.why);
                next();
            });
            suite._direct = null;
            const run = () => suite._runDirect(check.words, check.id);
            if (check.setup !== undefined)
                suite._sh(check.setup, run);
            else
                run();
        };
        next();
    }

    function _runDirect(words, id) {
        const path = id === null ? Quickshell.env("PATH") : _scratch + "/bin:" + Quickshell.env("PATH");
        _exec(["env", "PATH=" + path, "sh", "-c", _script, "sh"].concat(words), (code, stdout, stderr) => suite._direct = { code, stdout, stderr: stderr.trim() });
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
        _files?.destroy();
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
