import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.io

// Install, Remove and Undo of the remembered authorization (singletons/io/RememberInstall.qml),
// the root step run for real — scripts/root/replace-lib.sh and remember-install.sh, the text
// handed over exactly the two files joined — but through a stand-in for the shell's runs as
// administrator: the suite's `start` runs the words as the user, under a scratch base holding
// polkit's rules folder, /etc/polkit-1 and the backups, with a stand-in systemctl that records
// its words. Never pkexec, never /etc, /usr or /var:
// the component's `start` and `paths` are the suite's before anything runs, and the system's
// runner is refused scratch places. Covered: Install (the rule, backups of no files, modes, no
// temp file), Install again when the setting grows (the conf, polkitd told), its Undo, Remove
// and its Undo, polkitd not told (a failing systemctl), refused when a file changed by hand,
// is a link, the folders are not the owner's or others may write in them, another run holds
// the lock, the file built has not the sha256 the shell computed, the arguments (facts,
// seconds) are not valid, a backup is not there, an Undo after the files changed or of a run
// whose record says other files; the script's templates against RememberRules' texts byte for
// byte, its fixed names and bound against RememberRules' and the schema's; a script that
// cannot be read refused before any run; as root (a stand-in `id`) only the system's places; a
// prompt dismissed; a queue that throws; one run at a time. Asynchronous.
TestCase {
    id: suite
    suiteName: "RememberInstall"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-remember-install-test-" + Date.now()
    // The folders must be their owner's: the one running (the user here; a stand-in `id` says
    // another)
    property int _owner: -1
    // The script's places under the scratch base
    readonly property var _paths: ({ rules: _scratch + "/usr/share/polkit-1/rules.d", conf: _scratch + "/etc/polkit-1", backups: _scratch + "/var/lib/h2s-shell/polkit-backup",
                                     systemctl: _scratch + "/usr/bin/systemctl" })
    // replace-lib.sh and remember-install.sh joined, as the suite reads the files itself
    property string _script: ""
    readonly property var _facts: ({ user: "alex", timeout: "/usr/bin/timeout", program: "/usr/bin/timeout" })
    readonly property var _nixFacts: ({ user: "bob.smith-2$", timeout: "/run/current-system/sw/bin/timeout",
                                        program: "/nix/store/0abc-coreutils-full-9.11/bin/coreutils" })
    readonly property string _rule: RememberRules.ruleText(_facts)
    readonly property string _conf15: RememberRules.confText(900)
    readonly property string _vendorConf: "[Polkitd]\n# ExpirationSeconds=300\n"

    property var _install: null
    property var _runs: []
    // How the stand-in answers the next run: "run", "dismissed", "hold" (runs it once
    // released), "lost" (runs it, its output and exit lost)
    property string _answer: "run"
    property var _held: null
    property var _outcome: null
    property var _read: null
    property var _direct: null
    property bool _ready: false
    property bool _holder: false
    property var _installed: null
    property var _grown: null
    property var _removed: null

    property Component _installComponent: Component {
        RememberInstall {}
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
            done({ ok: answer === "lost" ? false : code === 0, code: answer === "lost" ? -1 : code,
                   stdout: answer === "lost" ? "" : stdout, stderr: answer === "lost" ? "" : stderr,
                   dismissed: false, refused: false, cancelled: false, blocked: "", error: "" }));
        if (answer === "hold")
            _held = go;
        else
            go();
    }

    // The request as the reader would give it, from the files as they are now (_read)
    function _request(minutes, more) {
        const confs = { "/usr/share/polkit-1/polkitd.conf": _vendorConf };
        confs[RememberRules.confPath] = _read.conf ?? undefined;
        return Object.assign({ facts: _facts, minutes: minutes, rule: _read.rule ?? undefined, confs: confs }, more ?? {});
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
        _install?.destroy();
        // A holder still waiting is let go before the folder goes
        _exec(["sh", "-c", "touch \"$1/release\" 2> /dev/null; rm -rf -- \"$1\"", "sh", _scratch], () => suite.finish());
    }

    // Reads the scratch folders: the two files (null for none), the listings, the modes, the
    // backups and the stand-in systemctl's words
    function _look() {
        _read = null;
        const script = "cd \"$1\"; for f in usr/share/polkit-1/rules.d/40-h2s-shell.rules etc/polkit-1/polkitd.conf; do printf '%s\\n' \"== $f\"; "
            + "if [ -e \"$f\" ] || [ -L \"$f\" ]; then cat \"$f\"; printf '\\n.\\n'; else printf '(none)\\n'; fi; done; "
            + "printf '== modes\\n'; for f in usr/share/polkit-1/rules.d/40-h2s-shell.rules etc/polkit-1/polkitd.conf var/lib/h2s-shell/polkit-backup; do [ -e \"$f\" ] && stat -c \"$f %a\" \"$f\"; done; "
            + "printf '== listing\\n'; ls -A usr/share/polkit-1/rules.d; ls -A etc/polkit-1; printf '== backups\\n'; ls -A var/lib/h2s-shell/polkit-backup 2> /dev/null; "
            + "printf '== backup modes\\n'; for f in var/lib/h2s-shell/polkit-backup/*; do [ -e \"$f\" ] && stat -c '%a' \"$f\"; done; "
            + "printf '== systemctl\\n'; cat systemctl.log 2> /dev/null; true";
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
                const lines = sections[key];
                if (lines[0] === "(none)")
                    return null;
                // The file, then the line break and "." printed after it
                return lines.slice(0, lines.lastIndexOf(".")).join("\n");
            };
            const lines = key => sections[key].filter(line => line !== "");
            suite._read = {
                rule: file("usr/share/polkit-1/rules.d/40-h2s-shell.rules"), conf: file("etc/polkit-1/polkitd.conf"),
                modes: lines("modes"), listing: lines("listing").filter(line => !line.endsWith(":")),
                backups: lines("backups").filter(line => line !== ".lock"), backupModes: lines("backup modes"), systemctl: lines("systemctl")
            };
        });
    }

    function _backupText(name, done) {
        _exec(["cat", "--", _paths.backups + "/" + name], (code, stdout) => done(code === 0 ? stdout : null));
    }

    // The root step's apply words: each file's op, current and sha256, the facts (null: none), the seconds
    function _apply(ruleOp, ruleCurrent, ruleWant, confOp, confCurrent, confWant, facts, seconds) {
        return ["apply", ruleOp, ruleCurrent, ruleWant, confOp, confCurrent, confWant,
                facts?.user ?? "-", facts?.timeout ?? "-", facts?.program ?? "-", seconds];
    }

    // The script run directly as the user with the given words after its base (_scratch unless
    // given); `id`: what a stand-in `id` says (none: the system's)
    function _runDirect(words, id, base) {
        _direct = null;
        const wrapper = "d=$1; n=$2; t=$3; shift 3; "
            + "if [ -n \"$n\" ]; then mkdir -p \"$d/id-$n\" && printf '#!/bin/sh\\necho %s\\n' \"$n\" > \"$d/id-$n/id\" && chmod +x \"$d/id-$n/id\" && PATH=\"$d/id-$n:$PATH\"; fi; "
            + "exec sh -c \"$t\" sh \"$@\"";
        _exec(["sh", "-c", wrapper, "sh", _scratch, id === undefined || id === null ? "" : String(id), _script, base ?? _scratch].concat(words),
              (code, stdout, stderr) => suite._direct = { code: code, stdout: stdout, stderr: stderr.trim() });
    }

    function _shell(script, done) {
        _ready = false;
        _exec(["sh", "-c", script, "sh", _scratch], code => {
            suite.assertEqual(code, 0, "set up: " + script);
            suite._ready = true;
            done?.();
        });
    }

    function runAsync() {
        const rules = RememberInstallRules;
        const sha = PamEditRules.sha256;
        _then("the scratch folders are there, the script read, the shell's timeout looked up", () => _ready && _script !== "" && CommandTools.known, () => _look());
        _then("read before anything", () => _read !== null, () => {
            assertEqual(_read.rule + " " + _read.conf, "null null", "nothing installed yet");
            // The names, markers and bound fixed in the script: RememberRules' and the schema's
            for (const line of ["rule_name='" + rules.ruleName + "'; conf_name='" + rules.confName + "'; max_seconds=" + (rules.maxMinutes * 60) + "\n",
                                "rule_marker='" + RememberRules.ruleMarker + "'; conf_marker='" + RememberRules.confMarker + "'; action='" + RememberRules.execAction + "'\n",
                                "rules=$base" + rules.livePaths.rules + "; conf=$base" + rules.livePaths.conf + "; backups=$base" + rules.livePaths.backups + "\n",
                                "systemctl=$base" + rules.livePaths.systemctl + "\n"])
                assert(_script.includes("\n" + line), "the script fixes: " + line.trim());
            const unread = _installComponent.createObject(suite, { start: suite._start, paths: _paths, scriptsDirectory: _scratch + "/none" });
            assertEqual(JSON.stringify(unread.install(_request(5))), JSON.stringify({ started: false, refusal: rules.refusal("script") }),
                        "the script's files not there: refused, with its reason");
            unread.destroy();
            // The system's runner never gets scratch places, a stand-in never the system's
            const system = _installComponent.createObject(suite, { paths: _paths });
            assertEqual(system.install(_request(5)).refusal?.code, "paths", "the system's runner with scratch places: refused");
            system.destroy();
            const standIn = _installComponent.createObject(suite, { start: suite._start });
            assertEqual(JSON.stringify(standIn.paths), JSON.stringify(rules.livePaths), "by default: the system's places");
            assertEqual(standIn.install(_request(5)).refusal?.code, "paths", "a stand-in with the system's places: refused");
            standIn.destroy();
            assertEqual(_runs.length, 0, "… nothing run");
            const throwing = _installComponent.createObject(suite, { start: () => { throw new Error("no queue"); }, paths: _paths });
            assertEqual(throwing.install(_request(5)).refusal?.code + " " + throwing.busy, "start false", "a queue that throws: not started, not left busy");
            throwing.destroy();

            _install = _installComponent.createObject(suite, { start: suite._start, paths: _paths });
            _install.finished.connect(outcome => suite._outcome = outcome);
            assertEqual(JSON.stringify(_install.install(_request(5))), JSON.stringify({ started: true, refusal: null }), "Install: started");
            assertEqual(_runs[0].what, "Remember the administrator password", "… the run's purpose");
            assertEqual(_runs[0].argv[0], "/bin/sh", "… the system's shell");
            assertEqual(_runs[0].argv[2], _script, "… the script: replace-lib.sh and remember-install.sh joined, exactly as the files have them");
            assertEqual(_runs[0].argv[4], _scratch, "… the base its first argument");
        });
        _then("installed", () => _outcome !== null, () => {
            assertEqual([_outcome.ok, _outcome.kind, _outcome.rule, _outcome.conf, _outcome.reload].join(" "), "true applied " + sha(_rule) + " absent none",
                        "the rule in force, no conf, polkitd not told");
            assert(rules.validStamp(_outcome.stamp), "… a stamp: " + _outcome.stamp);
            _installed = _outcome;
            _look();
        });
        _then("read after Install", () => _read !== null, () => {
            assertEqual(_read.rule, _rule, "the rule's bytes in the rules folder");
            assertEqual(_read.modes.join(" "), "usr/share/polkit-1/rules.d/40-h2s-shell.rules 644 var/lib/h2s-shell/polkit-backup 700", "under umask 000: the rule 644, the backups 700");
            assertEqual(_read.listing.join(" "), "40-h2s-shell.rules", "no temporary file left in either folder");
            assertEqual(_read.backups.sort().join(" "), "40-h2s-shell.rules." + _installed.stamp + ".absent polkitd.conf." + _installed.stamp + ".absent run." + _installed.stamp,
                        "both files recorded as absent, and what the run left, under one stamp");
            assertEqual(_read.backupModes.join(" "), "600 600 600", "… 600 each");
            assertEqual(_read.systemctl.length, 0, "systemctl not run");
            _outcome = null;
            assert(_install.install(_request(15)).started, "Install again, 15 min: started");
        });
        _then("installed again", () => _outcome !== null, () => {
            assertEqual([_outcome.ok, _outcome.rule, _outcome.conf, _outcome.reload].join(" "), "true " + sha(_rule) + " " + sha(_conf15) + " hup",
                        "the setting grew: the conf written, polkitd told");
            assert(_outcome.stamp !== _installed.stamp, "… a stamp of its own: " + _outcome.stamp);
            _grown = _outcome;
            _look();
        });
        _then("read after Install again", () => _read !== null, () => {
            assertEqual(_read.conf, _conf15, "the conf's bytes in the conf folder");
            assert(_read.modes.includes("etc/polkit-1/polkitd.conf 644"), "… 644");
            assertEqual(_read.systemctl.join("|"), "kill -s HUP --kill-whom=main polkit.service", "polkitd's main process sent SIGHUP");
            assertEqual(_read.backups.filter(name => name.includes(_grown.stamp)).sort().join(" "),
                        "40-h2s-shell.rules." + _grown.stamp + " polkitd.conf." + _grown.stamp + ".absent run." + _grown.stamp,
                        "the rule kept as it was, the conf recorded as absent");
            assertEqual(_read.backups.length, 6, "every backup kept");
            _read = null;
            _backupText("40-h2s-shell.rules." + _grown.stamp, text => _backupText("run." + _grown.stamp, record => suite._read = { backup: text, record: record }));
        });
        _then("the rule's backup read", () => _read !== null, () => {
            assertEqual(_read.backup, _rule, "the backup: the rule as it was");
            assertEqual(_read.record, sha(_rule) + " " + sha(_conf15), "the record: what the run left");
            _outcome = null;
            assert(_install.undo({ stamp: _grown.stamp, rule: _grown.rule, conf: _grown.conf }).started, "Undo of Install again: started");
            assertEqual(_runs[_runs.length - 1].what, "Undo the change to the remembered administrator password", "… the run's purpose");
        });
        _then("undone", () => _outcome !== null, () => {
            assertEqual([_outcome.ok, _outcome.kind, _outcome.rule, _outcome.conf, _outcome.reload].join(" "), "true restored " + sha(_rule) + " absent hup",
                        "restored: the rule as it was, no conf, polkitd told");
            _look();
        });
        _then("read after Undo", () => _read !== null, () => {
            assertEqual(_read.rule + "|" + _read.conf, _rule + "|null", "the rule there, the conf gone");
            assertEqual(_read.backups.length + " " + _read.listing.join(" "), "9 40-h2s-shell.rules", "two more backups and a record, no temporary file");
            _outcome = null;
            assert(_install.remove(_request(5)).started, "Remove: started");
            assertEqual(_runs[_runs.length - 1].what, "Stop remembering the administrator password", "… the run's purpose");
        });
        _then("removed", () => _outcome !== null, () => {
            assertEqual([_outcome.ok, _outcome.kind, _outcome.rule, _outcome.conf, _outcome.reload].join(" "), "true applied absent absent none", "removed: nothing in force");
            _removed = _outcome;
            _outcome = null;
            assert(_install.undo({ stamp: _removed.stamp, rule: _removed.rule, conf: _removed.conf }).started, "Undo of Remove: started");
        });
        _then("Remove undone", () => _outcome !== null, () => {
            assertEqual([_outcome.ok, _outcome.rule, _outcome.conf, _outcome.reload].join(" "), "true " + sha(_rule) + " absent none", "the rule back, polkitd not told");
            // An Undo of an older run, after the files changed since
            _outcome = null;
            assert(_install.undo({ stamp: _grown.stamp, rule: _grown.rule, conf: _grown.conf }).started, "Undo of a run whose files changed since: started");
        });
        _then("the stale Undo answered", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.refused + " " + _outcome.files, "false changed other", "refused: the conf is not what that run left (the files read again are not what it assumed)");
            _look();
        });
        // Changed by hand
        _then("read before the hand edit", () => _read !== null, () => {
            const before = _request(15);
            // The outcome dropped before the edit: the next step must not take the one before
            // (the edit never takes less than a few of the clock's ticks, so that it would fail
            // every run)
            _outcome = null;
            _shell("sleep 0.1; printf '// mine\\n' >> \"$1/usr/share/polkit-1/rules.d/40-h2s-shell.rules\"", () => {
                suite.assert(suite._install.install(before).started, "Install from a reading taken before a hand edit: started");
            });
        });
        _then("refused for the hand edit", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.refused + " " + _outcome.files, "false changed other", "refused: changed since it was read; the files read again");
            _look();
        });
        _then("read after the hand edit", () => _read !== null, () => {
            assertEqual(_read.rule, _rule + "// mine\n", "… left as the hand made it");
            assertEqual(_install.install(_request(15)).refusal?.code, "changed", "read again: changed outside the shell, not started");
            _outcome = null;
            assert(_install.install(_request(15, { replace: { rule: true, conf: true } })).started, "Replace: started");
        });
        _then("replaced", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.rule + " " + _outcome.conf, "true " + sha(_rule) + " " + sha(_conf15), "replaced: ours in force");
            _shell("cd \"$1/etc/polkit-1\" && mv polkitd.conf real.conf && ln -s real.conf polkitd.conf");
        });
        // A link
        _then("the conf a link", () => _ready, () => {
            _outcome = null;
            assert(_install.remove({ facts: _facts, rule: _rule, confs: { "/etc/polkit-1/polkitd.conf": _conf15 } }).started, "Remove with the conf a link: started");
        });
        _then("refused for the link", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.refused, "false link", "a link: refused");
            _shell("cd \"$1/etc/polkit-1\" && rm polkitd.conf && mv real.conf polkitd.conf");
        });
        // polkitd not told
        _then("the conf back", () => _ready, () => _shell("touch \"$1/systemctl.fail\"", () => suite._look()));
        _then("systemctl failing", () => _ready && _read !== null, () => {
            _outcome = null;
            assert(_install.install(_request(20)).started, "Install again, 20 min, systemctl failing: started");
        });
        _then("installed without polkitd told", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.conf + " " + _outcome.reload, "true " + sha(RememberRules.confText(1200)) + " nohup",
                        "written, said that polkitd was not told");
            _shell("rm \"$1/systemctl.fail\"", () => suite._look());
        });
        // A prompt dismissed
        _then("systemctl back", () => _ready && _read !== null, () => {
            _answer = "dismissed";
            _outcome = null;
            assert(_install.remove(_request(5)).started, "dismissed: started");
        });
        _then("the dismissal answered", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.quiet, "false true", "a prompt dismissed: nothing done, quietly");
            // One run at a time
            _answer = "hold";
            _outcome = null;
            assert(_install.remove(_request(5)).started, "held: started");
            assert(_install.busy, "… busy");
            assertEqual(_install.install(_request(5)).refusal?.code, "busy", "… a second while it runs: not started");
            _held();
        });
        _then("the held run answered", () => _outcome !== null, () => {
            assert(_outcome.ok && !_install.busy, "the held Remove done, no longer busy");
            assertEqual(_outcome.files, "done", "… nothing read again");
            const removed = _outcome;
            _answer = "lost";
            _outcome = null;
            assert(_install.undo({ stamp: removed.stamp, rule: removed.rule, conf: removed.conf }).started, "an Undo whose answer is lost: started");
        });
        _then("the lost Undo answered", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.files, "false other", "its answer lost: not ok, the files read again are not as before");
            _answer = "run";
            _look();
        });
        // The root step's own checks
        _then("read before the direct runs", () => _read !== null, () => {
            _runDirect(_apply("write", sha(_read.rule), sha("something else"), "keep", sha(_read.conf), "-", _facts, "-"));
        });
        _then("the wrong hash answered", () => _direct !== null, () => {
            assertEqual(_direct.code + " " + _direct.stderr, "3 refused hash", "a rule built that has not the sha256 the shell computed: refused");
            // The files are as given, but not what that run recorded it left
            _runDirect(["undo", _removed.stamp, sha(_read.rule), sha(_read.conf)]);
        });
        _then("an Undo of a run that left other files", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused changed", "the files not what the stamp's run left: refused");
            _runDirect(_apply("keep", sha(_read.rule), "-", "keep", sha(_read.conf), "-", null, "-"));
        });
        _then("nothing to do", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "both kept: refused");
            _runDirect(_apply("move", sha(_read.rule), "-", "keep", sha(_read.conf), "-", null, "-"));
        });
        _then("an unknown op", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "an operation not on the list: refused");
            _runDirect(_apply("remove", "absent", "-", "keep", sha(_read.conf), "-", null, "-"));
        });
        _then("removing nothing", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "a removal of no file: refused");
            _runDirect(["apply", "keep", sha(_read.rule), "-", "remove", sha(_read.conf), "-", "alex", "-", "-", "-"]);
        });
        _then("a kept rule with a user", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "facts for a rule kept: refused");
            _runDirect(_apply("keep", sha(_read.rule), "-", "write", sha(_read.conf), sha(RememberRules.confText(3601)), null, "3601"));
        });
        _then("seconds past the bound", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "a length past the setting's longest: refused");
            _runDirect(_apply("keep", sha(_read.rule), "-", "write", sha(_read.conf), sha(RememberRules.confText(60)), null, "060"));
        });
        _then("seconds with a leading zero", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "seconds not as the shell writes them: refused");
            _runDirect(_apply("write", sha(_read.rule), sha(_rule), "keep", sha(_read.conf), "-", Object.assign({}, _facts, { user: "al\"ex" }), "-"));
        });
        _then("a user with a quote", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "a user name the rule cannot carry: refused");
            _runDirect(_apply("write", sha(_read.rule), sha(_rule), "keep", sha(_read.conf), "-", Object.assign({}, _facts, { program: "/usr/bin/x\");polkit.addRule(" }), "-"));
        });
        _then("a program that would break out of the rule", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "a path with a quote: refused");
            _runDirect(_apply("write", sha(_read.rule), sha(_rule), "keep", sha(_read.conf), "-", Object.assign({}, _facts, { timeout: "/usr/bin/time out" }), "-"));
        });
        _then("a path with a space", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "a path with a space: refused");
            _runDirect(["undo", "20261123T101500Z/../../x", "absent", "absent"]);
        });
        _then("a stamp that is a path", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "a stamp that is a path: refused");
            _runDirect(["undo", "20201123T101500Z", sha(_read.rule), sha(_read.conf)]);
        });
        _then("a backup that is not there", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused nobackup", "a stamp with no backups: refused");
            _runDirect(["reinstall"]);
        });
        // The script's templates against RememberRules' texts, for a multi-call binary
        _then("an unknown mode", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused arguments", "a mode not on the list: refused");
            _runDirect(_apply("write", sha(_read.rule), sha(RememberRules.ruleText(_nixFacts)), "write", sha(_read.conf), sha(RememberRules.confText(120)), _nixFacts, "120"));
        });
        _then("the multi-call rule written", () => _direct !== null, () => {
            assertEqual(_direct.code + " " + _direct.stdout.trim().split(" ")[0], "0 applied", "a NixOS-like program and 120 s: written");
            _look();
        });
        _then("read after the multi-call rule", () => _read !== null, () => {
            assertEqual(_read.rule, RememberRules.ruleText(_nixFacts), "the script's rule: RememberRules.ruleText byte for byte");
            assertEqual(_read.conf, RememberRules.confText(120), "the script's conf: RememberRules.confText byte for byte");
            _look();
        });
        _then("read after the direct runs", () => _read !== null, () => {
            assertEqual(_read.listing.join(" "), "40-h2s-shell.rules polkitd.conf", "no temporary file left after the refusals");
            _runDirect(["undo", "20201123T101500Z", "absent", "absent"], _owner + 1);
        });
        _then("folders of another owner", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused owner", "folders that are not the owner's: refused");
            _direct = null;
            _exec(["chmod", "g+w", "--", _paths.conf], () => suite._runDirect(["undo", "20201123T101500Z", "absent", "absent"]));
        });
        _then("a conf folder others may write in", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused owner", "a conf folder the group may write in: refused");
            _direct = null;
            _exec(["sh", "-c", "chmod g-w -- \"$1\" && chmod o+w -- \"$2\"", "sh", _paths.conf, _paths.rules], () => suite._runDirect(["undo", "20201123T101500Z", "absent", "absent"]));
        });
        _then("a rules folder anyone may write in", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused owner", "a rules folder anyone may write in: refused");
            _direct = null;
            _exec(["sh", "-c", "chmod o-w -- \"$1\" && mv -- \"$1\" \"$1.away\"", "sh", _paths.rules], () => suite._runDirect(["undo", "20201123T101500Z", "absent", "absent"]));
        });
        _then("no rules folder", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused system", "polkit's rules folder missing: refused");
            _direct = null;
            _exec(["mv", "--", _paths.rules + ".away", _paths.rules], () => suite._runDirect(["undo", "20201123T101500Z", "absent", "absent"]));
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
            _outcome = null;
            assert(_install.remove(_request(5)).started, "Remove while another run holds the lock: started");
        });
        _then("refused while held", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.refused + " " + _outcome.files, "false busy unchanged", "another run holds the lock: refused, not waited for");
            _exec(["touch", "--", _scratch + "/release"]);
        });
        _then("the holder ended", () => _holder, () => {
            _runDirect(["undo", "20201123T101500Z", "absent", "absent"]);
        });
        _then("the lock free", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused nobackup", "the lock free again: past it");
            // The places: as root (a stand-in `id` saying 0) only the system's
            _runDirect(["undo", "20201123T101500Z", "absent", "absent"], 0);
        });
        _then("a scratch base as root", () => _direct !== null, () => {
            assertEqual(_direct.code + " " + _direct.stderr, "3 refused paths", "as root, places under a scratch folder: refused");
            _runDirect(["undo", "20201123T101500Z", "absent", "absent"], null, "");
        });
        _then("the system's places as the user", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused paths", "as the user, the system's places: refused");
            _runDirect(["undo", "20201123T101500Z", "absent", "absent"], null, "/usr/local");
        });
        _then("a base under /usr", () => _direct !== null, () => {
            assertEqual(_direct.stderr, "refused paths", "as the user, a base under /usr: refused");
        });
        _clock.start();
        _exec(["id", "-u"], (code, stdout) => {
            suite._owner = parseInt(stdout.trim(), 10);
            suite._makeFolders();
        });
    }

    function _makeFolders() {
        _exec(["cat", "--", Quickshell.shellDir + "/scripts/root/replace-lib.sh", Quickshell.shellDir + "/scripts/root/remember-install.sh"],
              (code, stdout) => suite._script = code === 0 ? stdout : "");
        // The stand-in systemctl: records its words, fails while systemctl.fail is there
        const systemctl = "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"" + _scratch + "/systemctl.log\"\n[ ! -e \"" + _scratch + "/systemctl.fail\" ]\n";
        _exec(["sh", "-c", "set -e; umask 022; mkdir -p \"$1/usr/share/polkit-1/rules.d\" \"$1/etc/polkit-1\" \"$1/usr/bin\"; printf '%s' \"$2\" > \"$1/usr/bin/systemctl\"; chmod 755 \"$1/usr/bin/systemctl\"",
               "sh", _scratch, systemctl], code => {
            suite.assertEqual(code, 0, "the scratch folders made");
            suite._ready = true;
        });
    }

    function _exec(command, done) {
        const process = _process.createObject(suite, { command: command });
        process.finished.connect((code, stdout, stderr) => done?.(code, stdout, stderr));
        process.running = true;
    }

    property Component _process: Component {
        Process {
            id: _run
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
                _run.finished(_code, _stdout, _stderr);
                _run.destroy();
            }
            stdout: StdioCollector {
                onStreamFinished: {
                    _run._stdout = text;
                    _run._finished = true;
                    _run._over();
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    _run._stderr = text;
                    _run._errorFinished = true;
                    _run._over();
                }
            }
            onExited: code => {
                _run._code = code;
                _run._exited = true;
                _run._over();
            }
        }
    }
}
