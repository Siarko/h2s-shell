import QtQuick
import Quickshell
import Quickshell.Io
import qs.distributions
import qs.distributions.arch
import qs.singletons
import qs.singletons.io
import qs.singletons.network

// Install, Remove and Undo of the VPN blocking's script and polkit rule on Arch
// (distributions/arch/VpnLockdownInstall.qml), the root step run for real —
// scripts/root/replace-lib.sh and vpn-lockdown-install.sh, the text handed over exactly the
// two files joined — through a stand-in for the shell's runs as administrator: the suite's
// `start` runs the words as the user, under a scratch base holding /usr/local, polkit's rules
// folder and the backups. The files are read as the page reads them (scripts/pam-files.sh,
// VpnLockdownRules.filesRead). Never pkexec, never /etc, /usr or /var. Covered: Install (the
// script and the rule byte for byte, their modes, backups of no files, no temp file), Install
// again with nothing to change (refused before a run), Remove and its Undo, a rule not written
// by the shell (refused unless replaced; replaced, kept as a backup), a hand edit after the
// reading (refused, the files read again), the root step's own refusals (a script text that
// is not the shell's, a user it cannot name, as root under a scratch base), a script file that
// cannot be read, the system's runner with scratch places; and scripts/vpn-lockdown-check.sh on
// stand-in files (installed, unsafe, a rule for this user, nft). Asynchronous.
TestCase {
    id: suite
    suiteName: "VpnLockdownInstall"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-vpn-lockdown-install-test-" + Date.now()
    readonly property var _paths: ({ script: _scratch + VpnLockdownInstallRules.livePaths.script, rule: _scratch + VpnLockdownInstallRules.livePaths.rule,
                                     backups: _scratch + VpnLockdownInstallRules.livePaths.backups })
    property string _script: ""
    property string _shellScript: ""
    readonly property string _rule: VpnLockdownInstallRules.ruleText("alex", _paths.script)

    property var _install: null
    property var _runs: []
    property var _outcome: null
    property var _current: null
    property var _direct: null
    property var _look: null
    property var _check: null
    property bool _ready: false
    property var _installed: null
    property var _removed: null
    property int _uid: -1

    property Component _installComponent: Component {
        VpnLockdownInstall {}
    }

    function _underTimeout(argv) {
        const words = PrivilegedRules.shellArgv(CommandTools.timeout, Array.from(argv));
        assert(words !== null, "the shell's trusted timeout is known: " + CommandTools.timeout);
        return words === null ? Array.from(argv) : words.slice(1);
    }

    // The stand-in for PrivilegedRuns.startShell: the words run as the user, with the most
    // open umask a caller could hand on
    function _start(request, done) {
        _runs.push({ what: request.what, argv: Array.from(request.argv) });
        _exec(["sh", "-c", "umask 000; exec \"$@\"", "sh"].concat(suite._underTimeout(request.argv)), (code, stdout, stderr) =>
            done({ ok: code === 0, code: code, stdout: stdout, stderr: stderr, dismissed: false, refused: false, cancelled: false, blocked: "", error: "" }));
    }

    // The two files as the page reads them
    function _read() {
        _current = null;
        const lines = [];
        _exec([Quickshell.shellDir + "/scripts/pam-files.sh", _paths.script, _paths.rule], (code, stdout) => {
            const answers = PamStackRules.filesAnswer(stdout.split("\n"), { ok: code === 0 }, [_paths.script, _paths.rule]).answers;
            suite._current = VpnLockdownRules.filesRead(answers[_paths.script], answers[_paths.rule]);
        });
    }

    function _request(op, more) {
        return Object.assign({ op: op, user: "alex", script: _shellScript, current: _current, replace: {} }, more ?? {});
    }

    // Modes, the folders' listings and the backups
    function _lookAround() {
        _look = null;
        const script = "cd \"$1\"; printf '== modes\\n'; stat -c '%n %a' usr/local/libexec/h2s-vpn-lockdown usr/share/polkit-1/rules.d/49-h2s-vpn-lockdown.rules var/lib/h2s-shell/vpn-lockdown-backup 2> /dev/null; "
            + "printf '== listing\\n'; ls -A usr/local/libexec usr/share/polkit-1/rules.d; printf '== backups\\n'; ls -A var/lib/h2s-shell/vpn-lockdown-backup 2> /dev/null; true";
        _exec(["sh", "-c", script, "sh", _scratch], (code, stdout) => {
            const sections = {};
            let name = "";
            for (const line of stdout.split("\n")) {
                if (line.startsWith("== ")) {
                    name = line.slice(3);
                    sections[name] = [];
                } else if (name !== "" && line !== "" && !line.endsWith(":")) {
                    sections[name].push(line);
                }
            }
            suite._look = { modes: sections.modes, listing: sections.listing, backups: sections.backups.filter(entry => entry !== ".lock") };
        });
    }

    // The root step run directly as the user, its words after the base; `id`: what a
    // stand-in `id` says (none: the system's)
    function _runDirect(words, id) {
        _direct = null;
        const wrapper = "d=$1; n=$2; t=$3; shift 3; "
            + "if [ -n \"$n\" ]; then mkdir -p \"$d/id-$n\" && printf '#!/bin/sh\\necho %s\\n' \"$n\" > \"$d/id-$n/id\" && chmod +x \"$d/id-$n/id\" && PATH=\"$d/id-$n:$PATH\"; fi; "
            + "exec sh -c \"$t\" sh \"$@\"";
        _exec(["sh", "-c", wrapper, "sh", _scratch, id === undefined || id === null ? "" : String(id), _script, _scratch].concat(words),
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

    function _runCheck(owner, user) {
        _check = null;
        _exec([Quickshell.shellDir + "/scripts/vpn-lockdown-check.sh", String(owner), Quickshell.shellDir + "/scripts/h2s-vpn-lockdown", _paths.script,
               _scratch + "/usr/share/polkit-1/rules.d", user, _scratch + "/no/nft", _scratch + "/usr/bin/nft"],
              (code, stdout) => suite._check = VpnLockdownRules.checkReply(stdout.split("\n")));
    }

    function runAsync() {
        const rules = VpnLockdownInstallRules;
        const sha = PamEditRules.sha256;
        _then("the scratch folders made, the scripts read, the shell's timeout looked up", () => _ready && _script !== "" && _shellScript !== "" && CommandTools.known, () => _read());
        _then("read before anything", () => _current !== null, () => {
            assertEqual(JSON.stringify(_current), JSON.stringify({}), "nothing installed yet: both absent");
            assert(rules.validScript(_shellScript), "the shell's script is one the root step takes");
            // The places, the names and the marker fixed in the root step: the rules'
            for (const line of ["local_dir=$base/usr/local; libexec=$local_dir/libexec; rules=$base/usr/share/polkit-1/rules.d\n",
                                "backups=$base" + rules.livePaths.backups + "\n",
                                "rule_marker='" + rules.ruleMarker + "'\n"])
                assert(_script.includes("\n" + line), "the root step fixes: " + line.trim());
            assertEqual(rules.livePaths.script.slice(0, rules.livePaths.script.lastIndexOf("/")) + " " + rules.livePaths.rule.slice(0, rules.livePaths.rule.lastIndexOf("/")),
                        "/usr/local/libexec /usr/share/polkit-1/rules.d", "… the same folders as the rules' places");
            const unread = _installComponent.createObject(suite, { start: suite._start, paths: _paths, scriptsDirectory: _scratch + "/none" });
            assertEqual(JSON.stringify(unread.apply(_request("install"))), JSON.stringify({ started: false, refusal: rules.refusal("script") }),
                        "the root step's files not there: refused, with its reason");
            unread.destroy();
            const system = _installComponent.createObject(suite, { paths: _paths });
            assertEqual(system.apply(_request("install")).refusal?.code, "paths", "the system's runner with scratch places: refused");
            system.destroy();
            const standIn = _installComponent.createObject(suite, { start: suite._start });
            assertEqual(standIn.apply(_request("install")).refusal?.code, "paths", "a stand-in with the system's places: refused");
            standIn.destroy();
            assertEqual(_runs.length, 0, "… nothing run");

            _install = _installComponent.createObject(suite, { start: suite._start, paths: _paths });
            _install.finished.connect(outcome => suite._outcome = outcome);
            assertEqual(JSON.stringify(_install.apply(_request("install"))), JSON.stringify({ started: true, refusal: null }), "Install: started");
            assertEqual(_runs[0].what, "Install the VPN blocking's script", "… the run's purpose");
            assertEqual(_runs[0].argv[0] + " " + _runs[0].argv[1], "/bin/sh -c", "… the system's shell");
            assertEqual(_runs[0].argv[2], _script, "… the root step: replace-lib.sh and vpn-lockdown-install.sh joined, exactly as the files have them");
            assertEqual(_runs[0].argv[4], _scratch, "… the base its first argument");
            assertEqual(_runs[0].argv[_runs[0].argv.length - 1], _shellScript, "… the script's text its last, shown with the command");
        });
        _then("installed", () => _outcome !== null, () => {
            assertEqual([_outcome.ok, _outcome.op, _outcome.kind, _outcome.script, _outcome.rule].join(" "), "true install applied " + sha(_shellScript) + " " + sha(_rule),
                        "the script and the rule in place");
            _installed = _outcome;
            _read();
        });
        _then("read after Install", () => _current !== null, () => {
            assertEqual(_current.script, _shellScript, "the script's bytes, the shell's");
            assertEqual(_current.rule, _rule, "the rule's bytes, the shell's template for this user and the script's place");
            assertEqual(JSON.stringify(rules.states(_request("install"), _paths)), JSON.stringify({ script: "ours", rule: "ours" }), "… both the shell's, as Install writes them");
            assertEqual(rules.offer(rules.states(_request("install"), _paths)).install, null, "… nothing more to install");
            assertEqual(JSON.stringify(_install.apply(_request("install"))), JSON.stringify({ started: false, refusal: rules.refusal("unchanged") }),
                        "Install again with nothing to change: refused before a run");
            _lookAround();
        });
        _then("looked after Install", () => _look !== null, () => {
            assertEqual(_look.modes.join(" | "), "usr/local/libexec/h2s-vpn-lockdown 755 | usr/share/polkit-1/rules.d/49-h2s-vpn-lockdown.rules 644 | var/lib/h2s-shell/vpn-lockdown-backup 700",
                        "under umask 000: the script 755, the rule 644, the backups 700");
            assertEqual(_look.listing.join(" "), "h2s-vpn-lockdown 49-h2s-vpn-lockdown.rules", "no temporary file left");
            const stamp = _installed.stamp;
            assertEqual(_look.backups.sort().join(" "), "49-h2s-vpn-lockdown.rules." + stamp + ".absent h2s-vpn-lockdown." + stamp + ".absent run." + stamp,
                        "both recorded as absent, and what the run left, under one stamp");
            _runCheck(_uid, "alex");
        });
        _then("checked as installed", () => _check !== null, () => {
            assertEqual(JSON.stringify(_check), JSON.stringify({ script: _check.script, installed: _check.script, installedFound: true, unsafe: false, rule: true, nft: true }),
                        "the check: installed (held by its owner), the rule for this user, nft at its second place");
            assert(_check.script > 0, "… the shell's copy's version read: " + _check.script);
            _runCheck(_uid, "bob");
        });
        _then("checked for another user", () => _check !== null, () => {
            assertEqual(_check.rule + " " + _check.installedFound, "false true", "the check: no rule for another user");
            _runCheck(0, "alex");
        });
        _then("checked for another owner", () => _check !== null, () => {
            assertEqual(_check.installedFound + " " + _check.unsafe, "false true", "the check: a script not root's alone — unsafe, never counted installed");
            _shell("chmod 775 \"$1/usr/local/libexec/h2s-vpn-lockdown\"", () => suite._runCheck(suite._uid, "alex"));
        });
        _then("checked writable by its group", () => _check !== null && _ready, () => {
            assertEqual(_check.installedFound + " " + _check.unsafe, "false true", "the check: a script others may write — unsafe");
            _shell("chmod 755 \"$1/usr/local/libexec/h2s-vpn-lockdown\"", () => {
                suite._outcome = null;
                suite.assert(suite._install.apply(suite._request("remove")).started, "Remove: started");
            });
        });
        _then("removed", () => _outcome !== null, () => {
            assertEqual([_outcome.ok, _outcome.op, _outcome.script, _outcome.rule].join(" "), "true remove absent absent", "removed: neither there");
            assertEqual(_runs[_runs.length - 1].argv.slice(-2).join(" "), "- -", "… no user, no script text handed over");
            _removed = _outcome;
            _outcome = null;
            assert(_install.undo({ from: _removed }).started, "Undo of Remove: started");
            assertEqual(_runs[_runs.length - 1].what, "Undo the change to the VPN blocking's script", "… the run's purpose");
        });
        _then("Remove undone", () => _outcome !== null, () => {
            assertEqual([_outcome.ok, _outcome.kind, _outcome.script, _outcome.rule].join(" "), "true restored " + sha(_shellScript) + " " + sha(_rule), "both back");
            _read();
        });
        _then("read after Undo", () => _current !== null, () => {
            assertEqual(_current.script + "|" + _current.rule, _shellScript + "|" + _rule, "the same bytes back");
            const before = _request("remove");
            _shell("printf '// mine\\n' >> \"$1/usr/share/polkit-1/rules.d/49-h2s-vpn-lockdown.rules\"", () => {
                suite._outcome = null;
                suite.assert(suite._install.apply(before).started, "Remove from a reading taken before a hand edit: started");
            });
        });
        _then("refused for the hand edit", () => _outcome !== null, () => {
            assertEqual(_outcome.ok + " " + _outcome.refused + " " + _outcome.files, "false changed other", "refused: changed since it was read; the files read again are not what it assumed");
            _shell("printf '// my own rule\\n' > \"$1/usr/share/polkit-1/rules.d/49-h2s-vpn-lockdown.rules\"", () => suite._read());
        });
        _then("a rule not the shell's read", () => _current !== null && _ready, () => {
            const found = rules.states(_request("install"), _paths);
            assertEqual(found.script + " " + found.rule, "ours changed", "the rule: not written by the shell");
            assertEqual(JSON.stringify(rules.offer(found)), JSON.stringify({ install: { label: "Replace…", asks: true, replace: { script: false, rule: true } }, remove: true }),
                        "… offered as Replace, after a question, naming only the rule");
            const runs = _runs.length;
            assertEqual(_install.apply(_request("install")).refusal?.code, "changed", "Install without replacing it: refused before a run");
            assertEqual(_install.apply(_request("remove")).started, true, "Remove: started — the shell's script goes, the rule stays");
            assertEqual(_runs.length, runs + 1, "… one run");
            _outcome = null;
        });
        _then("the shell's script removed, the rule kept", () => _outcome !== null, () => {
            assertEqual([_outcome.ok, _outcome.script, _outcome.rule].join(" "), "true absent " + sha("// my own rule\n"), "the script gone, the user's rule kept");
            _read();
        });
        _then("read before Replace", () => _current !== null, () => {
            _outcome = null;
            assert(_install.apply(_request("install", { replace: rules.offer(rules.states(_request("install"), _paths)).install.replace })).started, "Replace: started");
        });
        _then("replaced", () => _outcome !== null, () => {
            assertEqual([_outcome.ok, _outcome.script, _outcome.rule].join(" "), "true " + sha(_shellScript) + " " + sha(_rule), "the shell's script and rule in place");
            _exec(["cat", "--", _paths.backups + "/49-h2s-vpn-lockdown.rules." + _outcome.stamp], (code, stdout) => suite._direct = { stdout: stdout });
        });
        _then("the user's rule kept", () => _direct !== null, () => {
            assertEqual(_direct.stdout, "// my own rule\n", "the user's rule kept as the backup");
            // The root step's own refusals, run directly
            const shaRule = sha(_rule), shaScript = sha(_shellScript);
            _runDirect(["apply", "write", shaScript, sha("echo evil\n"), "keep", shaRule, "-", "-", "echo evil\n"]);
        });
        _then("a script text not the shell's", () => _direct !== null, () => {
            assertEqual(_direct.code + " " + _direct.stderr, "3 refused arguments", "a script text that does not start as the shell's: refused");
            _runDirect(["apply", "keep", sha(_shellScript), "-", "write", sha(_rule), sha(VpnLockdownRules.lockdownPolkitRule("a", ['"' + _paths.script + '"'])), "a\" || true", "-"]);
        });
        _then("a user the rule cannot name", () => _direct !== null, () => {
            assertEqual(_direct.code + " " + _direct.stderr, "3 refused arguments", "a user with a quote: refused");
            _runDirect(["apply", "keep", sha(_shellScript), "-", "write", sha(_rule), sha("x"), "alex", "-"]);
        });
        _then("a rule not the one computed", () => _direct !== null, () => {
            assertEqual(_direct.code + " " + _direct.stderr, "3 refused hash", "the rule built has not the sha256 handed in: refused");
            _runDirect(["apply", "remove", sha(_shellScript), "-", "keep", sha(_rule), "-", "-", "-"], 0);
        });
        _then("a scratch base as root", () => _direct !== null, () => {
            assertEqual(_direct.code + " " + _direct.stderr, "3 refused paths", "as root, places under a scratch folder: refused");
            _lookAround();
        });
        _then("nothing left behind", () => _look !== null, () => {
            assertEqual(_look.listing.join(" "), "h2s-vpn-lockdown 49-h2s-vpn-lockdown.rules", "the refusals left no temporary file");
        });
        _clock.start();
        _exec(["id", "-u"], (code, stdout) => {
            suite._uid = parseInt(stdout.trim(), 10);
            suite._makeFolders();
        });
    }

    function _makeFolders() {
        _exec(["cat", "--", Quickshell.shellDir + "/scripts/root/replace-lib.sh", Quickshell.shellDir + "/scripts/root/vpn-lockdown-install.sh"],
              (code, stdout) => suite._script = code === 0 ? stdout : "");
        _exec(["cat", "--", Quickshell.shellDir + "/scripts/h2s-vpn-lockdown"], (code, stdout) => suite._shellScript = code === 0 ? stdout : "");
        _exec(["sh", "-c", "set -e; umask 022; mkdir -p \"$1/usr/local\" \"$1/usr/share/polkit-1/rules.d\" \"$1/usr/bin\" \"$1/var/lib/h2s-shell\"; printf '#!/bin/sh\\n' > \"$1/usr/bin/nft\"; chmod 755 \"$1/usr/bin/nft\"",
               "sh", _scratch], code => {
            suite.assertEqual(code, 0, "the scratch folders made");
            suite._ready = true;
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
        _install?.destroy();
        _exec(["rm", "-rf", "--", _scratch], () => suite.finish());
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
