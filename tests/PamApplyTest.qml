import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.io

// Apply and Undo (singletons/io/PamApply.qml), the root step run for real — the fixed script
// PamApplyRules.applyScript — but through a stand-in for the shell's runs as administrator:
// the suite's `start` runs the words as the user, on scratch folders standing for the PAM
// folder, the vendor folder and the backups. Never pkexec, never /etc: the PamApply's
// `start` and `paths` are the suite's before anything runs, and the system's runner is
// refused scratch places. Covered: sudo written (its backup, modes, no temp file left),
// refused when an included file or the file itself changed since, for a link, for bytes
// that are not the candidate's, for arguments that are not a service, a name or a backup;
// Undo; polkit written where there was none, its Undo (a backup of no file), removed back
// to the vendor file, refused when the vendor file changed; a prompt dismissed; one run at
// a time. Asynchronous.
TestCase {
    id: suite
    suiteName: "PamApply"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-pam-apply-test-" + Date.now()
    // The folders must be their owner's: the user's here (the script's owner seam)
    property int _owner: -1
    readonly property var _paths: ({ system: _scratch + "/pam.d", vendor: _scratch + "/vendor", backups: _scratch + "/lib/pam-backup", owner: _owner })

    readonly property string _systemAuth: "auth required pam_faillock.so preauth\nauth [success=1 default=bad] pam_unix.so try_first_pass\n"
        + "auth [default=die] pam_faillock.so authfail\nauth optional pam_permit.so\naccount required pam_unix.so\n"
    readonly property string _sudo: "#%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n"
    readonly property string _vendorPolkit: "#%PAM-1.0\n\nauth       include      system-auth\naccount    include      system-auth\n"
        + "password   include      system-auth\nsession    include      system-auth\n"

    property var _apply: null
    property var _runs: []
    // How the stand-in answers the next run: "run" (runs it), "dismissed", "hold" (runs it
    // once released), "lost" (runs it, its output and exit lost), "noStdout" (runs it, its
    // stdout lost: as a closed stdout, the run ends with an error)
    property string _answer: "run"
    property var _held: null
    property var _outcome: null
    property var _read: null
    property bool _ready: false

    property Component _applyComponent: Component {
        PamApply {}
    }

    // The stand-in for PrivilegedRuns.startShell: the words run as the user (no pkexec), with
    // the most open umask a caller could hand on
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
            Qt.callLater(() => done({ ok: false, code: 126, stdout: "", stderr: "", dismissed: true, refused: false, cancelled: false, blocked: "", error: "" }));
            return;
        }
        const answer = _answer;
        const go = () => _exec(["sh", "-c", "umask 000; exec \"$@\"", "sh"].concat(suite._underTimeout(request.argv)), (code, stdout, stderr) =>
            done({ ok: answer === "run" || answer === "hold" ? code === 0 : false,
                   code: answer === "lost" ? -1 : answer === "noStdout" ? 141 : code,
                   stdout: answer === "lost" || answer === "noStdout" ? "" : stdout, stderr: answer === "lost" ? "" : stderr,
                   dismissed: false, refused: false, cancelled: false, blocked: "", error: "" }));
        if (_answer === "hold")
            _held = go;
        else
            go();
    }

    function _row(id, control) {
        return { id: id, method: "fingerprint", control: control ?? "sufficient", details: { timeout: 10, tries: 3 } };
    }

    function _facts(service) {
        return { system: "arch", service: service, fingerprint: "ready", securityKey: "ready", faillockPresent: true,
                 faillock: { deny: 3, failInterval: 900, unlockTime: 600 },
                 otherService: [{ id: "o1", method: "password", control: "sufficient", details: { counted: false } }, PamRuleRules.fixedRow()],
                 vendorText: _vendorPolkit };
    }

    // A trial as PamTrialRules leaves it once PAM let the user in, having read `answers`
    function _passed(service, text, answers) {
        const directories = [_paths.system, _paths.vendor];
        const step = PamTrialRules.stagingStep(service, text, answers, directories, false);
        return Object.assign(PamTrialRules.initialState(), {
            phase: "passed", trial: 1, service: service, candidate: text, directories: directories, answers: answers, stack: step.stack
        });
    }

    function _answers() {
        const answers = {};
        answers[_paths.system + "/system-auth"] = { text: _systemAuth };
        return answers;
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
        _apply?.destroy();
        _exec(["rm", "-rf", "--", _scratch], () => suite.finish());
    }

    // Reads the scratch folders: each file's text (or "(none)"), the listings and modes
    function _look() {
        _read = null;
        const script = "cd \"$1\"; for f in pam.d/sudo pam.d/polkit-1; do printf '%s\\n' \"== $f\"; if [ -e \"$f\" ] || [ -L \"$f\" ]; then cat \"$f\"; else printf '(none)'; fi; printf '\\n'; done; "
            + "printf '== modes\\n'; stat -c '%a' pam.d/sudo lib/pam-backup 2> /dev/null; "
            + "printf '== pam.d\\n'; ls -A pam.d; printf '== backups\\n'; ls -A lib/pam-backup 2> /dev/null; "
            + "printf '== backup modes\\n'; for f in lib/pam-backup/*; do [ -e \"$f\" ] && stat -c '%a' \"$f\"; done; true";
        _exec(["sh", "-c", script, "sh", _scratch], (code, stdout) => {
            const sections = {};
            let name = "";
            for (const line of stdout.split("\n")) {
                if (line.startsWith("== ")) {
                    name = line.slice(3);
                    sections[name] = [];
                } else if (name !== "") {
                    sections[name].push(line);
                }
            }
            const file = key => {
                const text = sections[key].join("\n");
                // The line break printed after each file is the one before the next header
                return text === "(none)" ? null : text;
            };
            suite._read = {
                sudo: file("pam.d/sudo"), polkit: file("pam.d/polkit-1"),
                modes: sections["modes"].filter(line => line !== ""),
                listing: sections["pam.d"].filter(line => line !== ""),
                backups: sections["backups"].filter(line => line !== "" && line !== ".lock"),
                backupModes: sections["backup modes"].filter(line => line !== "")
            };
        });
    }

    function _backupText(name, done) {
        _exec(["cat", "--", _paths.backups + "/" + name], (code, stdout) => done(code === 0 ? stdout : null));
    }

    function _write(path, text, done) {
        _exec(["sh", "-c", "printf '%s' \"$2\" > \"$1\"", "sh", path, text], code => done(code));
    }

    property var _sudoBuilt: null
    property var _sudoOutcome: null
    property var _polkitBuilt: null
    property var _direct: null
    property bool _holder: false

    // The script run directly with the given words (its argument checks)
    function _runDirect(words, paths) {
        _direct = null;
        _exec(["sh", "-c", PamApplyRules.applyScript(paths ?? _paths), "sh"].concat(words), (code, stdout, stderr) => suite._direct = { code: code, stdout: stdout, stderr: stderr.trim() });
    }

    function runAsync() {
        const edit = PamEditRules;
        const fixed = PamRuleRules.fixedRow();
        _sudoBuilt = edit.build(_sudo, [_row("r1"), fixed], _facts("sudo"));
        _then("the scratch folders are there, the shell's timeout looked up", () => _ready && CommandTools.known, () => {
            assert(_sudoBuilt.ok, "the sudo fixture builds");
            // The system's runner never gets scratch places, a stand-in never the system's
            const system = _applyComponent.createObject(suite, { paths: _paths });
            const request = { service: "sudo", built: _sudoBuilt, currentText: _sudo, trial: _passed("sudo", _sudoBuilt.text, _answers()) };
            assertEqual(system.apply(request).refusal?.code, "paths", "the system's runner with scratch places: refused");
            system.destroy();
            const standIn = _applyComponent.createObject(suite, { start: suite._start });
            assertEqual(JSON.stringify(standIn.paths), JSON.stringify(PamApplyRules.livePaths), "by default: the system's places");
            assertEqual(standIn.apply(Object.assign({}, request, { trial: Object.assign({}, request.trial, { directories: [PamApplyRules.livePaths.system, PamApplyRules.livePaths.vendor] }) })).refusal?.code,
                        "paths", "a stand-in with the system's places: refused");
            standIn.destroy();
            assertEqual(_runs.length, 0, "… nothing run");

            _apply = _applyComponent.createObject(suite, { start: suite._start, paths: _paths });
            _apply.finished.connect(outcome => suite._outcome = outcome);
            const started = _apply.apply(request);
            assertEqual(JSON.stringify(started), JSON.stringify({ started: true, refusal: null }), "sudo's new rules: started");
            assertEqual(_runs[0].what, "Change the sign-in rules for sudo", "… the run's purpose");
            assertEqual(_runs[0].argv[0], "/bin/sh", "… the system's shell");
        });
        _then("sudo written", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.kind + " " + _outcome.sha256, "true written " + edit.sha256(_sudoBuilt.text), "written, its hash in force");
            assert(PamApplyRules.validBackup("sudo", _outcome.backup) && !_outcome.backup.endsWith(".absent"), "… a backup of sudo: " + _outcome.backup);
            _sudoOutcome = _outcome;
            _look();
        });
        _then("the folders read after the write", () => _read !== null, () => {
            assertEqual(_read.sudo, _sudoBuilt.text, "the candidate's bytes in the PAM folder");
            assert(PamApplyRules.inForce(_read.sudo, _sudoOutcome), "… in force as the reply says");
            assertEqual(_read.modes.join(" "), "644 700", "under umask 000: the file 644, the backups 700");
            assertEqual(_read.listing.join(" "), "sudo system-auth", "no temporary file left in the PAM folder");
            assertEqual(_read.backups.join(" ") + " " + _read.backupModes.join(" "), _sudoOutcome.backup + " 600", "one backup, 600, no temporary file");
            _read = null;
            _backupText(_sudoOutcome.backup, text => suite._read = { backup: text });
        });
        _then("the backup read", () => _read !== null, () => {
            assertEqual(_read.backup, _sudo, "the backup: the file as it was");
            _ready = false;
            _write(_paths.system + "/system-auth", _systemAuth + "# changed\n", () => suite._ready = true);
        });
        // A trial made before system-auth changed: the root step sees the change
        const other = edit.build(_sudoBuilt.text, [_row("r1", "required"), fixed], _facts("sudo"));
        _then("system-auth changed", () => _ready, () => {
            _outcome = null;
            assert(_apply.apply({ service: "sudo", built: other, currentText: _sudoBuilt.text, trial: _passed("sudo", other.text, _answers()) }).started,
                   "rules tried before an included file changed: started");
        });
        _then("refused for the included file", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.refused, "false included", "refused: an included file changed since the trial");
            assertEqual(_outcome.file, "unchanged", "… the file read again: as before");
            _look();
        });
        _then("read after the included refusal", () => _read !== null, () => {
            assertEqual(_read.sudo, _sudoBuilt.text, "… sudo untouched");
            assertEqual(_read.backups.length + " " + _read.listing.join(" "), "1 sudo system-auth", "… no backup made, no temporary file left");
            _ready = false;
            _write(_paths.system + "/system-auth", _systemAuth, () => suite._ready = true);
        });
        _then("system-auth back", () => _ready, () => {
            _outcome = null;
            // The shell read sudo before the first write: the file changed since
            assert(_apply.apply({ service: "sudo", built: other, currentText: _sudo, trial: _passed("sudo", other.text, _answers()) }).started,
                   "built from the file as it was before: started");
        });
        _then("refused for the file", () => _outcome !== null, () => {
            assertEqual(_outcome.refused, "changed", "refused: the file changed since it was read");
            // Bytes that are not the candidate's
            _runDirect(["write", "sudo", edit.sha256("something else"), edit.sha256(_sudoBuilt.text), other.text, "system-auth", edit.sha256(_systemAuth)]);
        });
        _then("the wrong hash answered", () => _direct !== null, () => {
            assertEqual(_direct.code + " " + _direct.stderr, "3 refused hash", "bytes that are not the candidate's: refused");
            _look();
        });
        _then("read after the hash refusal", () => _read !== null, () => {
            assertEqual(_read.sudo + "|" + _read.backups.length + "|" + _read.listing.join(" "), _sudoBuilt.text + "|1|sudo system-auth",
                        "… nothing written, no backup, no temporary file");
            _runDirect(["write", "login", edit.sha256(other.text), "absent", other.text]);
        });
        _then("a service not on the list", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "a service not on the list: refused");
            _runDirect(["write", "sudo", edit.sha256(other.text), edit.sha256(_sudoBuilt.text), other.text, "../system-auth", edit.sha256(_systemAuth)]);
        });
        _then("an included path", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "an included name that is a path: refused");
            _runDirect(["undo", "sudo", "sudo.20261123T101500Z/../../x", edit.sha256(_sudoBuilt.text)]);
        });
        _then("a backup path", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "a backup that is a path: refused");
            _runDirect(["undo", "sudo", "polkit-1.20261123T101500Z", edit.sha256(_sudoBuilt.text)]);
        });
        _then("another service's backup", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "another service's backup: refused");
            _runDirect(["undo", "sudo", "sudo.20261123T101500Z", edit.sha256(_sudoBuilt.text)]);
        });
        _then("a backup that is not there", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused nobackup", "a backup that is not there: refused");
            _runDirect(["remove", "sudo", edit.sha256(_sudo), edit.sha256(_sudoBuilt.text)]);
        });
        _then("sudo removed", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "a removal of sudo: refused");
            _outcome = null;
            assert(_apply.undo({ service: "sudo", backup: _sudoOutcome.backup, currentSha256: _sudoOutcome.sha256 }).started, "Undo: started");
            assertEqual(_runs[_runs.length - 1].what, "Undo the change to the sign-in rules for sudo", "… the run's purpose");
        });
        _then("undone", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.kind + " " + _outcome.sha256, "true restored " + edit.sha256(_sudo), "restored: the old file's hash");
            assert(_outcome.backup !== _sudoOutcome.backup, "… the written file kept as a backup of its own: " + _outcome.backup);
            _look();
        });
        _then("read after Undo", () => _read !== null, () => {
            assertEqual(_read.sudo, _sudo, "sudo as it was");
            assertEqual(_read.modes[0], "644", "… 644");
            assertEqual(_read.backups.length + " " + _read.listing.join(" "), "2 sudo system-auth", "two backups, no temporary file");
            _ready = false;
            _exec(["sh", "-c", "cd \"$1\" && mv sudo sudo.real && ln -s sudo.real sudo", "sh", _paths.system], () => suite._ready = true);
        });
        _then("sudo a link", () => _ready, () => {
            _outcome = null;
            assert(_apply.apply({ service: "sudo", built: _sudoBuilt, currentText: _sudo, trial: _passed("sudo", _sudoBuilt.text, _answers()) }).started,
                   "sudo a link: started");
        });
        _then("refused for the link", () => _outcome !== null, () => {
            assertEqual(_outcome.refused, "link", "a link: refused");
            _ready = false;
            _exec(["sh", "-c", "cd \"$1\" && rm sudo && mv sudo.real sudo", "sh", _paths.system], () => suite._ready = true);
        });
        // polkit: our file where there was none, under sudo's trial (one trial, a shared list)
        _then("sudo back", () => _ready, () => {
            _polkitBuilt = edit.build(null, [_row("r1"), fixed], _facts("polkit-1"));
            _outcome = null;
            assert(_apply.apply({ service: "polkit-1", built: _polkitBuilt, currentText: null, vendorText: _vendorPolkit,
                                  trial: _passed("sudo", _sudoBuilt.text, _answers()) }).started, "polkit under sudo's trial: started");
            assertEqual(_runs[_runs.length - 1].what, "Change the sign-in rules for administrator prompts", "… the run's purpose");
        });
        _then("polkit written", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.sha256, "true " + edit.sha256(_polkitBuilt.text), "polkit written");
            assert(_outcome.backup.startsWith("polkit-1.") && _outcome.backup.endsWith(".absent"), "… its backup: there was none (" + _outcome.backup + ")");
            const written = _outcome;
            _outcome = null;
            assert(_apply.undo({ service: "polkit-1", backup: written.backup, currentSha256: written.sha256 }).started, "its Undo: started");
        });
        _then("polkit undone", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.sha256, "true absent", "Undo of a backup of no file: our file removed");
            _look();
        });
        _then("read after polkit's Undo", () => _read !== null, () => {
            assertEqual(_read.polkit, null, "no polkit-1 in the PAM folder");
            _outcome = null;
            assert(_apply.apply({ service: "polkit-1", built: _polkitBuilt, currentText: null, vendorText: _vendorPolkit,
                                  trial: _passed("polkit-1", _polkitBuilt.text, _answers()) }).started, "polkit again: started");
        });
        _then("polkit written again", () => _outcome !== null, () => {
            assert(_outcome.ok, "polkit written again");
            // Its own trial of the vendor file: the removal
            const removal = edit.build(_polkitBuilt.text, [fixed], _facts("polkit-1"));
            assert(removal.ok && removal.remove, "back to the system's rows: a removal");
            _outcome = null;
            assertEqual(_apply.apply({ service: "polkit-1", built: removal, currentText: _polkitBuilt.text, vendorText: _vendorPolkit,
                                       trial: _passed("polkit-1", _polkitBuilt.text, _answers()) }).refusal?.code, "notTried",
                        "a removal after a trial of our file, not the vendor's: not started");
            assert(_apply.apply({ service: "polkit-1", built: removal, currentText: _polkitBuilt.text, vendorText: _vendorPolkit,
                                  trial: _passed("polkit-1", _vendorPolkit, _answers()) }).started, "the removal after a trial of the vendor file: started");
        });
        _then("polkit removed", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.kind + " " + _outcome.sha256, "true removed absent", "removed: the vendor file in force");
            const removed = _outcome;
            _read = null;
            _backupText(removed.backup, text => suite._read = { backup: text });
        });
        _then("the removal's backup read", () => _read !== null, () => {
            assertEqual(_read.backup, _polkitBuilt.text, "the removal's backup: our file");
            _look();
        });
        _then("read after the removal", () => _read !== null, () => {
            assertEqual(_read.polkit, null, "no polkit-1 in the PAM folder");
            _runDirect(["remove", "polkit-1", edit.sha256(_vendorPolkit + "#\n"), edit.sha256(_polkitBuilt.text)]);
        });
        _then("the vendor file other", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused vendor", "a removal when the vendor file is not the one tried: refused");
            // A prompt dismissed
            _answer = "dismissed";
            _outcome = null;
            assert(_apply.apply({ service: "sudo", built: _sudoBuilt, currentText: _sudo, trial: _passed("sudo", _sudoBuilt.text, _answers()) }).started,
                   "dismissed: started");
        });
        _then("the dismissal answered", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.quiet, "false true", "a prompt dismissed: not written, quietly");
            // One run at a time
            _answer = "hold";
            _outcome = null;
            const request = { service: "sudo", built: _sudoBuilt, currentText: _sudo, trial: _passed("sudo", _sudoBuilt.text, _answers()) };
            assert(_apply.apply(request).started, "held: started");
            assert(_apply.busy, "… busy");
            assertEqual(_apply.apply(request).refusal?.code, "busy", "… a second while it runs: not started");
            _held();
        });
        _then("the held run answered", () => _outcome !== null, () => {
            assert(_outcome.ok && !_apply.busy, "the held run written, no longer busy");
            assertEqual(_outcome.file, "done", "… done, nothing read again");
            const held = _outcome;
            _answer = "lost";
            _outcome = null;
            assert(_apply.undo({ service: "sudo", backup: held.backup, currentSha256: held.sha256 }).started, "an Undo whose answer is lost: started");
        });
        _then("the lost Undo answered", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.file, "false other", "its answer lost: not ok, the file read again is not as before");
            _outcome = null;
            assert(_apply.apply({ service: "sudo", built: _sudoBuilt, currentText: _sudo, trial: _passed("sudo", _sudoBuilt.text, _answers()) }).started,
                   "an Apply whose answer is lost: started");
        });
        _then("the lost Apply answered", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.file, "false done", "its answer lost: not ok, the file read again is the one asked for");
            _answer = "noStdout";
            _outcome = null;
            assert(_apply.apply({ service: "sudo", built: other, currentText: _sudoBuilt.text, trial: _passed("sudo", other.text, _answers()) }).started,
                   "an Apply whose stdout is lost: started");
        });
        _then("the Apply without stdout answered", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.kind + " " + _outcome.sha256, "true written " + edit.sha256(other.text),
                        "stdout lost: done, said on stderr");
            assert(PamApplyRules.validBackup("sudo", _outcome.backup), "… with its backup");
            _answer = "run";
            _runDirect(["undo", "sudo", "sudo.20261123T101500Z", "absent"], Object.assign({}, _paths, { owner: _owner + 1 }));
        });
        _then("folders of another owner", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused owner", "folders that are not the owner's: refused");
            _direct = null;
            _exec(["chmod", "g+w", "--", _paths.system], () => suite._runDirect(["undo", "sudo", "sudo.20261123T101500Z", "absent"]));
        });
        _then("a PAM folder others may write in", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused owner", "a PAM folder the group may write in: refused");
            _direct = null;
            _exec(["sh", "-c", "chmod g-w -- \"$1\" && chmod o+w -- \"$2\"", "sh", _paths.system, _scratch + "/lib"], () => suite._runDirect(["undo", "sudo", "sudo.20261123T101500Z", "absent"]));
        });
        _then("a backups' parent anyone may write in", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused owner", "the backups' folder's parent writable by anyone: refused");
            _direct = null;
            _exec(["chmod", "o-w", "--", _scratch + "/lib"], () => suite._runDirect(["undo", "sudo", "sudo.20261123T101500Z", "absent"]));
        });
        _then("the folders back", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused nobackup", "the folders as they were: past the owner check");
            // Another run holds the lock
            _ready = false;
            _holder = false;
            _exec(["flock", _paths.backups + "/.lock", "sh", "-c", "touch \"$1/held\"; while [ ! -e \"$1/release\" ]; do sleep 0.05; done", "sh", _scratch],
                  () => suite._holder = true);
            _exec(["sh", "-c", "while [ ! -e \"$1/held\" ]; do sleep 0.05; done", "sh", _scratch], () => suite._ready = true);
        });
        _then("the lock held", () => _ready, () => {
            _runDirect(["undo", "sudo", "sudo.20261123T101500Z", "absent"]);
        });
        _then("refused while held", () => _direct !== null, () => {
            assertEqual(_direct.code + " " + _direct.stderr, "3 refused busy", "another run holds the lock: refused, not waited for");
            _exec(["touch", "--", _scratch + "/release"]);
        });
        _then("the holder ended", () => _holder, () => {
            _runDirect(["undo", "sudo", "sudo.20261123T101500Z", "absent"]);
        });
        _then("the lock free", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused nobackup", "the lock free again: past it");
        });
        _clock.start();
        _exec(["id", "-u"], (code, stdout) => {
            suite._owner = parseInt(stdout.trim(), 10);
            suite._makeFolders();
        });
    }

    function _makeFolders() {
        _exec(["sh", "-c", "set -e; umask 022; mkdir -p \"$1/pam.d\" \"$1/vendor\"; printf '%s' \"$2\" > \"$1/pam.d/sudo\"; printf '%s' \"$3\" > \"$1/pam.d/system-auth\"; "
               + "printf '%s' \"$4\" > \"$1/vendor/polkit-1\"", "sh", _scratch, _sudo, _systemAuth, _vendorPolkit], code => {
            suite.assertEqual(code, 0, "the scratch folders made");
            suite._ready = true;
        });
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
