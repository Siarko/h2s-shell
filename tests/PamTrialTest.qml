import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.io

// The trial (singletons/io/PamTrial.qml) run for real: pam-files.sh (a copy with the test
// bed's seams.sh beside it) reads the stand-in directories, scripts/pam-trial-stage.sh
// stages under a private scratch directory, and Quickshell's PamContext runs libpam on the
// staged copy. Never the real /etc/pam.d, pam_unix or pam_faillock: the candidates are
// PamEditRules.build's texts with each module the shell writes swapped for a stand-in of
// the same shape, one line for one line, the controls untouched —
//   pam_unix.so      → pam_exec with expose_authtok and a script accepting one password
//                      (it asks "Password:" when no password was given yet, as pam_unix)
//   pam_faillock.so  → pam_exec with a counter script: preauth fails at 3, authfail counts
//                      and fails, authsucc resets (pam_faillock's shape)
//   pam_fprintd.so   → pam_exec with a script that passes or fails as the test says, or
//                      pam_debug answering PAM_IGNORE
//   pam_permit.so, pam_deny.so → libpam's own, by absolute path
// and an Arch-shaped system-auth of the same stand-ins. The module directory is the one of
// the libpam this Quickshell has loaded (its maps), as the lock bed takes it. Covered: the
// staged files and their modes, PAM's question and messages, the counted pattern (a
// lockout closes the service, a pass does not reset), both closing lines, the bracketed
// required/requisite against a module answering ignore, polkit's own file, a cancel.
// pam_exec fails with PAM_SYSTEM_ERR where pam_unix fails with PAM_AUTH_ERR: no control the
// shell writes tells the two apart, so the verdicts are the same. Asynchronous.
TestCase {
    id: suite
    suiteName: "PamTrial"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-pam-trial-test-" + Date.now()
    readonly property string _password: "trial-pass-42"

    property var _trial: null
    property bool _ready: false
    // The module directory (found at the start) and the last scenario's readings
    property string _modules: ""
    property var _after: ({})

    property Component _trialComponent: Component {
        PamTrial {}
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
            if (!ready && waited < 20000)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready) {
                suite.fail("timed out waiting: " + step.description);
                // The rest waits on what did not come: stop here
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
        _trial?.destroy();
        _trial = null;
        _sh("chmod -R u+rwx \"$1\" 2> /dev/null; rm -rf \"$1\"", [_scratch], () => suite.finish());
    }

    function _sh(script, args, done) {
        _runner.start(["sh", "-c", script, "sh"].concat(args), { timeoutMs: 30000, done: result => done(result) });
    }

    property CommandRunner _runner: CommandRunner {}

    // Waits (a deadline only) for the directory $1 to be gone: "gone" or "there"
    readonly property string _goneScript: "for i in $(seq 300); do [ -e \"$1\" ] || break; sleep 0.05; done; [ -e \"$1\" ] && echo there || echo gone"

    // scripts/pam-trial-stage.sh ($1) under the scratch directory ($2): each case "ok <what>"
    // or "bad <what>"
    readonly property string _refusalScript: [
        "stage=$1 s=$2 p=$2/run",
        "check() { label=$1; shift; if \"$@\"; then echo \"ok $label\"; else echo \"bad $label\"; fi; }",
        "refused() { \"$stage\" \"$@\" 2> /dev/null && return 1; return 0; }",
        "mkdir -p \"$s/other/h2s-pam-trial.ABCDEFGH\"; ln -s \"$s/other/h2s-pam-trial.ABCDEFGH\" \"$p/h2s-pam-trial.Linked12\"; ln -s \"$p\" \"$s/runlink\"",
        "check 'staged' \"$stage\" stage \"$p\" \"$p/h2s-pam-trial.Okay1234\" a 'x' > /dev/null",
        "check '… its file, 0600, in a 0700 directory' test \"$(stat -c %a \"$p/h2s-pam-trial.Okay1234\") $(stat -c %a \"$p/h2s-pam-trial.Okay1234/a\") $(cat \"$p/h2s-pam-trial.Okay1234/a\")\" = '700 600 x'",
        "check 'a directory already there: refused' refused stage \"$p\" \"$p/h2s-pam-trial.Okay1234\" b 'y'",
        "check '… and left as it was' test -e \"$p/h2s-pam-trial.Okay1234/a\" -a ! -e \"$p/h2s-pam-trial.Okay1234/b\"",
        "check 'remove through .. into another directory: refused' refused remove \"$p\" \"$p/../other/h2s-pam-trial.ABCDEFGH\"",
        "check 'remove of a directory elsewhere: refused' refused remove \"$p\" \"$s/other/h2s-pam-trial.ABCDEFGH\"",
        "check 'remove through a link: refused' refused remove \"$p\" \"$p/h2s-pam-trial.Linked12\"",
        "check '… the other directory still there' test -d \"$s/other/h2s-pam-trial.ABCDEFGH\" -a -L \"$p/h2s-pam-trial.Linked12\"",
        "check 'a parent with a trailing slash: refused' refused remove \"$p/\" \"$p//h2s-pam-trial.Okay1234\"",
        "check 'a parent with //: refused' refused remove \"$s//run\" \"$s//run/h2s-pam-trial.Okay1234\"",
        "check 'a parent with /./: refused' refused remove \"$s/./run\" \"$s/./run/h2s-pam-trial.Okay1234\"",
        "check 'a parent with /..: refused' refused remove \"$s/other/../run\" \"$s/other/../run/h2s-pam-trial.Okay1234\"",
        "check 'a relative parent: refused' refused remove run run/h2s-pam-trial.Okay1234",
        "check 'a parent that is a link: refused' refused stage \"$s/runlink\" \"$s/runlink/h2s-pam-trial.Viaa1234\" a 'x'",
        "check 'a name with a slash: refused' refused stage \"$p\" \"$p/h2s-pam-trial.Name1234\" '../x' 'x'",
        "check 'a dot-file name: refused' refused stage \"$p\" \"$p/h2s-pam-trial.Name1234\" '.x' 'x'",
        "check 'a name given twice: refused' refused stage \"$p\" \"$p/h2s-pam-trial.Name1234\" a 'x' a 'y'",
        "check 'a control character in a text: refused' refused stage \"$p\" \"$p/h2s-pam-trial.Name1234\" a \"$(printf 'x\\001')\"",
        "check 'a directory name not the staging one: refused' refused stage \"$p\" \"$p/h2s-pam-trial.short\" a 'x'",
        "check '… none of the refused made a directory' test ! -e \"$p/h2s-pam-trial.Name1234\" -a ! -e \"$s/runlink/h2s-pam-trial.Viaa1234\" -a ! -e \"$p/h2s-pam-trial.short\"",
        "check 'removed' \"$stage\" remove \"$p\" \"$p/h2s-pam-trial.Okay1234\"",
        "check '… gone' test ! -e \"$p/h2s-pam-trial.Okay1234\"",
        "check 'removed again: no error' \"$stage\" remove \"$p\" \"$p/h2s-pam-trial.Okay1234\"",
        "rm -f \"$p/h2s-pam-trial.Linked12\" \"$s/runlink\""
    ].join("\n")

    // ---- Candidates ----

    readonly property string _sudo: "#%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n"
    readonly property string _vendorPolkit: "#%PAM-1.0\n\nauth       include      system-auth\naccount    include      system-auth\n"
        + "password   include      system-auth\nsession    include      system-auth\n"

    function _row(id, method, control, details) {
        return { id: id, method: method, control: control, details: details ?? {} };
    }

    function _facts(service) {
        return {
            system: "arch", service: service, fingerprint: "ready", securityKey: "ready",
            faillockPresent: true, faillock: { deny: 3, failInterval: 900, unlockTime: 600 },
            otherService: [_row("o1", "password", "sufficient", { counted: false }), PamRuleRules.fixedRow()],
            vendorText: _vendorPolkit
        };
    }

    // PamEditRules' text for the rows, its modules swapped for the stand-ins (`finger`:
    // "exec" or "ignore"), the controls as written
    function _candidate(service, rows, finger) {
        const built = PamEditRules.build(service === "sudo" ? _sudo : null, rows, _facts(service));
        if (!built.ok) {
            fail("the rows were refused: " + JSON.stringify(built.refusals));
            return "";
        }
        const modules = _modules, bin = _scratch + "/bin";
        const swaps = {
            "pam_unix.so": () => modules + "/pam_exec.so quiet expose_authtok " + bin + "/check-password.sh",
            "pam_faillock.so": args => modules + "/pam_exec.so quiet " + bin + "/counter.sh " + args.trim().split(/\s+/)[0],
            "pam_fprintd.so": () => finger === "ignore" ? modules + "/pam_debug.so auth=ignore" : modules + "/pam_exec.so " + bin + "/finger.sh",
            "pam_permit.so": () => modules + "/pam_permit.so",
            "pam_deny.so": () => modules + "/pam_deny.so"
        };
        return built.text.split("\n").map(line => {
            const match = line.match(/^(-?auth\s+(?:\[[^\]]*\]|\S+))\s+(\S+)(.*)$/);
            return match && swaps[match[2]] ? match[1] + " " + swaps[match[2]](match[3]) : line;
        }).join("\n");
    }

    // ---- One trial ----
    // spec: { label, service, text, finger ("ok" / "no"), count (pam_faillock's stand-in
    // before), answer (the password typed at the prompt; null: none expected), cancel (at
    // the prompt), atPrompt (a check while the prompt is up, with the staged directory's
    // listing), check (after: the state and _after { count, log, staged }) }
    function _scenario(spec) {
        const textOf = () => typeof spec.text === "function" ? spec.text() : spec.text;
        _then(spec.label + ": the stand-ins set", () => _ready, () => {
            _ready = false;
            _sh("printf '%s\\n' \"$2\" > \"$1/finger\"; printf '%s\\n' \"$3\" > \"$1/count\"; : > \"$1/log\"",
                [_scratch, spec.finger ?? "no", String(spec.count ?? 0)], result => {
                suite.assertEqual(result.code, 0, spec.label + ": stand-ins set");
                suite._trial.start(spec.service ?? "sudo", textOf());
                suite._ready = true;
            });
        });
        const ended = () => ["passed", "failed", "cancelled"].includes(_trial.state.phase);
        _then(spec.label + ": a question or the end", () => _ready && (ended() || (_trial.state.phase === "running" && _trial.state.prompt !== null)), () => {
            if (ended()) {
                assert(spec.answer === null || spec.answer === undefined, spec.label + ": no question, as expected");
                return;
            }
            assert(spec.answer !== null && spec.answer !== undefined || spec.cancel === true, spec.label + ": a question, as expected");
            assertEqual(_trial.state.prompt.visible, false, spec.label + ": the password is asked hidden");
            const act = () => {
                if (spec.cancel === true)
                {
                    const trial = suite._trial.state.trial;
                    suite._trial.cancel(trial);
                    // A late answer to the question cancelled: goes nowhere
                    suite._trial.respond(trial, suite._password);
                }
                else
                    suite._trial.respond(suite._trial.state.trial, spec.answer ?? "");
            };
            if (!spec.atPrompt) {
                act();
                return;
            }
            _ready = false;
            const directory = _trial.state.staging;
            _sh("cd \"$1\" && stat -c '%a' . && for f in *; do printf '%s %s\\n' \"$f\" \"$(stat -c %a \"$f\")\"; done && printf '%s' \"$2\" | cmp -s - \"$3\" && echo same",
                [directory, textOf(), spec.service ?? "sudo"], result => {
                spec.atPrompt(result.stdout.split("\n"));
                act();
                suite._ready = true;
            });
        });
        _then(spec.label + ": the end", () => _ready && ended(), () => {
            _ready = false;
            // The staging directory goes when the trial ends: wait for that (a deadline only)
            _sh("for i in $(seq 200); do [ -z \"$(ls -A \"$1/run\")\" ] && break; sleep 0.05; done; "
                + "echo \"count $(cat \"$1/count\")\"; echo \"staged $(ls -A \"$1/run\" | tr '\\n' ' ')\"; sed 's/^/log /' \"$1/log\"",
                [_scratch], result => {
                const lines = result.stdout.split("\n");
                suite._after = {
                    count: Number((lines.find(line => line.startsWith("count ")) ?? "").slice(6)),
                    staged: (lines.find(line => line.startsWith("staged ")) ?? "").slice(7).trim(),
                    log: lines.filter(line => line.startsWith("log ")).map(line => line.slice(4)).join(",")
                };
                suite.assertEqual(suite._after.staged, "", spec.label + ": the staging directory removed");
                spec.check(suite._trial.state, suite._after);
                suite._ready = true;
            });
        });
    }

    function runAsync() {
        const fixed = PamRuleRules.fixedRow();
        const fingerprint = control => _row("f", "fingerprint", control, { timeout: 10, tries: 3 });
        const password = (control, counted) => _row("p", "password", control, { counted: counted === true });
        const outcome = (state, label, expected) => assertEqual(state.phase, expected, label);
        let fingerFirst = "";

        _then("the module directory and the stand-ins", () => _ready, () => {
            _trial = _trialComponent.createObject(suite, {
                filesCommand: [_scratch + "/tree/scripts/pam-files.sh"],
                stagingParent: _scratch + "/run",
                environment: {
                    H2S_LOCK_SYSTEM_PAM_DIR: _scratch + "/etc",
                    H2S_LOCK_VENDOR_PAM_DIR: _scratch + "/usr",
                    H2S_LOCK_FAILLOCK_CONF: _scratch + "/faillock.conf"
                }
            });
            fingerFirst = _candidate("sudo", [fingerprint("sufficient"), fixed], "exec");
            assert(fingerFirst.includes("-auth sufficient " + _modules + "/pam_exec.so "), "the reader row written as -auth sufficient, swapped");
        });

        // A sufficient reader above the system's lines (the include followed and staged)
        _scenario({
            label: "reader no, right password", text: () => fingerFirst, finger: "no", answer: _password,
            atPrompt: lines => {
                assertEqual(lines[0], "700", "the staging directory is the user's alone");
                assert(lines.includes("sudo 600") && lines.includes("system-auth 600"), "the candidate and the included system-auth staged, 0600: " + lines.join("|"));
                assert(lines.includes("same"), "the staged sudo is the candidate byte for byte");
            },
            check: (state, after) => {
                outcome(state, "a reader that fails, then the right password: passed", "passed");
                assertEqual(after.log, "finger no,preauth 0,right,authsucc 0", "… through the include: preauth, the password, authsucc");
                assert(state.messages.some(message => message.error && message.text.includes("finger.sh")), "PAM's message about the reader reported: " + JSON.stringify(state.messages));
            }
        });
        _scenario({
            label: "reader ok", text: () => fingerFirst, finger: "ok", answer: null,
            check: (state, after) => {
                outcome(state, "the reader passing: passed, no password asked", "passed");
                assertEqual(after.log, "finger ok", "… the system's lines not run");
            }
        });
        _scenario({
            label: "reader no, wrong password", text: () => fingerFirst, finger: "no", answer: "wrong",
            check: (state, after) => {
                outcome(state, "a wrong password: failed", "failed");
                // pam_exec's failure is PAM_SYSTEM_ERR, which Quickshell reports as an error
                assert(state.reason === "failed" || state.reason === "error", "… PAM's result as the reason: " + state.reason);
                assertEqual(after.count, 1, "… the system's pam_faillock counted it");
            }
        });
        _scenario({
            label: "cancel", text: () => fingerFirst, finger: "no", cancel: true,
            check: (state, after) => {
                outcome(state, "cancelled at the question", "cancelled");
                assert(!after.log.includes("right") && !after.log.includes("wrong"), "… no password checked, the answer given after the cancel included");
            }
        });

        // The staging script's refusals, run as it is
        _then("the staging script's refusals", () => _ready, () => {
            _ready = false;
            _sh(_refusalScript, [Quickshell.shellDir + "/scripts/pam-trial-stage.sh", _scratch], result => {
                const lines = result.stdout.split("\n").filter(line => line !== "");
                suite.assert(lines.length >= 15, "the staging script's cases ran: " + lines.length);
                for (const line of lines)
                    suite.assert(line.startsWith("ok "), "the staging script: " + line);
                suite._ready = true;
            });
        });

        // Destroyed mid-trial: while PAM asks, and while the staging run is held
        let doomed = null, doomedDirectory = "";
        _then("a trial to destroy, at its question", () => _ready, () => {
            doomed = _trialComponent.createObject(suite, {
                filesCommand: [_scratch + "/tree/scripts/pam-files.sh"],
                stageCommand: [_scratch + "/held-stage"],
                stagingParent: _scratch + "/run",
                environment: _trial.environment
            });
            _ready = false;
            _sh("printf 'no\\n' > \"$1/finger\"; printf '0\\n' > \"$1/count\"", [_scratch], () => {
                doomed.start("sudo", fingerFirst);
                suite._ready = true;
            });
        });
        _then("the doomed trial asks", () => _ready && doomed.state.phase === "running" && doomed.state.prompt !== null, () => {
            doomedDirectory = doomed.state.staging;
            assert(doomedDirectory.startsWith(_scratch + "/run/h2s-pam-trial."), "the doomed trial's staging directory: " + doomedDirectory);
            doomed.destroy();
            doomed = null;
            _ready = false;
            _sh(_goneScript, [doomedDirectory], result => {
                suite.assertEqual(result.stdout.trim(), "gone", "destroyed while PAM asks: the staging directory removed");
                suite._ready = true;
            });
        });
        _then("a trial to destroy while staging", () => _ready, () => {
            doomed = _trialComponent.createObject(suite, {
                filesCommand: [_scratch + "/tree/scripts/pam-files.sh"],
                stageCommand: [_scratch + "/held-stage"],
                stagingParent: _scratch + "/run",
                environment: _trial.environment
            });
            _ready = false;
            _sh("touch \"$1/hold\"", [_scratch], () => {
                doomed.start("sudo", fingerFirst);
                suite._ready = true;
            });
        });
        _then("the doomed trial staging", () => _ready && doomed.state.phase === "staging", () => {
            doomedDirectory = doomed.state.staging;
            _ready = false;
            // The directory is made; the reply is held
            _sh("for i in $(seq 400); do [ -d \"$1\" ] && break; sleep 0.05; done; [ -d \"$1\" ] && echo made", [doomedDirectory], result => {
                suite.assertEqual(result.stdout.trim(), "made", "the held staging run made its directory");
                suite.assertEqual(doomed.state.phase, "staging", "… its reply not taken yet");
                doomed.destroy();
                doomed = null;
                suite._sh("rm -f \"$2/hold\"; " + suite._goneScript, [doomedDirectory, suite._scratch], gone => {
                    suite.assertEqual(gone.stdout.trim(), "gone", "destroyed while staging: the staging directory removed");
                    suite._ready = true;
                });
            });
        });

        // The counted pattern
        let counted = "", countedRequired = "";
        _then("counted candidates", () => _ready, () => {
            counted = _candidate("sudo", [password("sufficient", true), fixed]);
            countedRequired = _candidate("sudo", [password("required", true), fixed]);
            assert(counted.includes("[success=done default=ignore] " + _modules + "/pam_exec.so quiet expose_authtok"), "the counted sufficient pattern, swapped");
        });
        _scenario({
            label: "counted, right", text: () => counted, count: 1, answer: _password,
            check: (state, after) => {
                outcome(state, "counted sufficient, the right password: passed", "passed");
                assertEqual(after.log, "preauth 1,right", "… at once, the system's lines not run");
                assertEqual(after.count, 1, "… a pass through the row does not reset the count");
            }
        });
        _scenario({
            label: "counted, wrong", text: () => counted, count: 0, answer: "wrong",
            check: (state, after) => {
                outcome(state, "counted sufficient, a wrong password: failed", "failed");
                assertEqual(after.log, "preauth 0,wrong,authfail 1,preauth 1,wrong,authfail 2", "… counted by the row and by the system's lines, asked once");
                assertEqual(after.count, 2, "… two counted");
            }
        });
        _scenario({
            label: "counted, locked out", text: () => counted, count: 3, answer: _password,
            check: (state, after) => {
                outcome(state, "counted sufficient while locked out, the right password: failed (the lockout closes the service)", "failed");
                assertEqual(after.log, "preauth locked 3,right,authfail locked 3,preauth locked 3,right,authsucc locked 3",
                            "… the row's pass does not end a stack already failed: on through the system's lines, nothing counted or reset");
                assertEqual(after.count, 3, "… still locked out");
            }
        });
        _scenario({
            label: "counted required, right", text: () => countedRequired, count: 1, answer: _password,
            check: (state, after) => {
                outcome(state, "counted required, the right password: passed", "passed");
                assertEqual(after.log, "preauth 1,right,preauth 1,right,authsucc 1", "… on through the system's lines, the password given once");
                assertEqual(after.count, 0, "… the system's authsucc reset the count");
            }
        });
        _scenario({
            label: "counted required, wrong", text: () => countedRequired, count: 0, answer: "wrong",
            check: (state, after) => {
                outcome(state, "counted required, a wrong password: failed", "failed");
                assertEqual(after.count, 2, "… counted by the row and by the system's lines");
            }
        });

        // The closing lines (no fixed row)
        let deny = "", permit = "", ignoreRequired = "", ignoreRequisite = "", plainRequired = "", countedAlone = "";
        _then("candidates without the fixed row", () => _ready, () => {
            deny = _candidate("sudo", [fingerprint("sufficient"), password("sufficient")], "exec");
            permit = _candidate("sudo", [password("required"), fingerprint("required")], "exec");
            countedAlone = _candidate("sudo", [password("sufficient", true)]);
            ignoreRequired = _candidate("sudo", [password("required"), fingerprint("required")], "ignore");
            ignoreRequisite = _candidate("sudo", [password("required"), fingerprint("requisite")], "ignore");
            assert(deny.includes("auth requisite " + _modules + "/pam_deny.so"), "sufficient rows only: closed by requisite pam_deny");
            assert(permit.includes("auth [default=done] " + _modules + "/pam_permit.so\nauth requisite " + _modules + "/pam_deny.so\n"),
                   "required rows: closed by [default=done] pam_permit, then requisite pam_deny");
            assert(countedAlone.includes("pam_faillock") === false && countedAlone.includes("counter.sh authfail\nauth requisite " + _modules + "/pam_deny.so\n"),
                   "a counted sufficient row alone: closed by requisite pam_deny");
            assert(ignoreRequired.includes("auth [success=ok new_authtok_reqd=ok ignore=bad default=bad] " + _modules + "/pam_debug.so auth=ignore"),
                   "a required reader written in the bracket form");
            assert(ignoreRequisite.includes("[success=ok new_authtok_reqd=ok ignore=die default=die] " + _modules + "/pam_debug.so"), "… a requisite one too");
            // What the bracket form is for: the plain word takes PAM_IGNORE as no answer
            plainRequired = ignoreRequired.replace("[success=ok new_authtok_reqd=ok ignore=bad default=bad] " + _modules + "/pam_debug.so",
                                                   "required " + _modules + "/pam_debug.so");
        });
        _scenario({
            label: "deny closing, wrong", text: () => deny, finger: "no", answer: "wrong",
            check: (state, after) => {
                outcome(state, "requisite pam_deny closing, reader and password failing: failed", "failed");
                assertEqual(after.log, "finger no,wrong", "… ended at pam_deny: the system's lines below never reached");
            }
        });
        _scenario({
            label: "deny closing, right", text: () => deny, finger: "no", answer: _password,
            check: state => outcome(state, "requisite pam_deny closing, the right password: passed", "passed")
        });
        _scenario({
            label: "permit closing, both pass", text: () => permit, finger: "ok", answer: _password,
            check: (state, after) => {
                outcome(state, "[default=done] pam_permit closing, both required rows passing: passed", "passed");
                assertEqual(after.log, "right,finger ok", "… both run, the system's lines not");
            }
        });
        _scenario({
            label: "permit closing, reader fails", text: () => permit, finger: "no", answer: _password,
            check: (state, after) => {
                outcome(state, "… the required reader failing: failed, the closing keeps the failure", "failed");
                assertEqual(after.log, "right,finger no", "… ended at the closing pam_deny: the system's lines below never reached");
            }
        });
        _scenario({
            label: "permit closing, wrong password", text: () => permit, finger: "ok", answer: "wrong",
            check: (state, after) => {
                outcome(state, "… a wrong password with the reader passing: failed", "failed");
                assertEqual(after.log, "wrong,finger ok", "… required: the next row still runs; the system's lines below never reached");
                assertEqual(after.count, 0, "… the system's pam_faillock untouched");
            }
        });
        _scenario({
            label: "counted alone, locked out", text: () => countedAlone, count: 3, answer: _password,
            check: (state, after) => {
                outcome(state, "a counted sufficient row alone while locked out, the right password: failed", "failed");
                assertEqual(after.log, "preauth locked 3,right,authfail locked 3", "… ended at the closing pam_deny: the system's lines below never reached");
                assertEqual(after.count, 3, "… still locked out");
            }
        });
        _scenario({
            label: "required reader answering ignore", text: () => ignoreRequired, answer: _password,
            check: state => outcome(state, "a required reader answering PAM_IGNORE: failed (ignore=bad)", "failed")
        });
        _scenario({
            label: "requisite reader answering ignore", text: () => ignoreRequisite, answer: _password,
            check: state => outcome(state, "a requisite reader answering PAM_IGNORE: failed (ignore=die)", "failed")
        });
        _scenario({
            label: "plain required answering ignore", text: () => plainRequired, answer: _password,
            check: state => outcome(state, "the plain word `required` with PAM_IGNORE lets in through the closing permit: why it is not written so", "passed")
        });

        // polkit-1: the shell's own file over the vendor one
        let polkit = "";
        _then("polkit's candidate", () => _ready, () => {
            polkit = _candidate("polkit-1", [fingerprint("sufficient"), fixed], "exec");
            assert(polkit.startsWith(PamEditRules.writtenMarker + " "), "polkit-1: a file of the shell's own");
        });
        _scenario({
            label: "polkit", service: "polkit-1", text: () => polkit, finger: "no", answer: _password,
            atPrompt: lines => {
                assertEqual(lines.slice(1).filter(line => line !== "" && line !== "same").join(","), "polkit-1 600,system-auth 600",
                            "polkit-1 and the system-auth its auth lines include staged");
                assert(lines.includes("same"), "the staged polkit-1 is the candidate byte for byte");
            },
            check: (state, after) => {
                outcome(state, "polkit-1, reader failing, right password: passed", "passed");
                assertEqual(after.log, "finger no,preauth 0,right,authsucc 0", "… through the include");
            }
        });

        // The last scenario's checks come from a command: wait for them before the end
        _then("the last scenario checked", () => _ready, () => {});
        _clock.start();
        const bash = "$(command -v bash)";
        _sh([
            "set -e; s=$1; repo=$2; mkdir -p \"$s/tree/scripts\" \"$s/bin\" \"$s/etc\" \"$s/usr\"; mkdir -m 700 \"$s/run\"",
            "cp \"$repo/scripts/pam-files.sh\" \"$s/tree/scripts/\"; cp \"$repo/tests/lock/seams/seams.sh\" \"$s/tree/scripts/seams.sh\"",
            // The staging script, its reply held while the file "hold" exists (staging only)
            "printf '#!/bin/sh\\n\"%s/scripts/pam-trial-stage.sh\" \"$@\"\\ncode=$?\\n[ \"$1\" = stage ] && while [ -e \"%s/hold\" ]; do sleep 0.05; done\\nexit $code\\n' \"$repo\" \"$s\" > \"$s/held-stage\"; chmod +x \"$s/held-stage\"",
            // The libpam this Quickshell loaded, from the maps of the nearest ancestor that has it
            "m=${LOCKTEST_PAM_MODULES:-}; pid=$$",
            "while [ -z \"$m\" ] && [ \"$pid\" -gt 1 ]; do lib=$(sed -n 's|.* \\(/.*/libpam\\.so\\.0[.0-9]*\\)$|\\1|p' \"/proc/$pid/maps\" 2> /dev/null | head -n 1);"
            + " [ -n \"$lib\" ] && m=$(dirname \"$lib\")/security; pid=$(awk '{ print $4 }' \"/proc/$pid/stat\"); done",
            "for module in pam_exec pam_debug pam_permit pam_deny; do [ -e \"$m/$module.so\" ] || { echo \"no $module.so in '$m'\" >&2; exit 3; }; done",
            "case \"$m$s\" in *[!A-Za-z0-9._/+-]*) echo \"a path PAM cannot hold: $m $s\" >&2; exit 3 ;; esac",
            "b=" + bash,
            // pam_exec gives no PATH: builtins only
            "printf '#!%s\\nIFS= read -r -d \"\" token || true\\nif [ \"$token\" = \"%s\" ]; then echo right >> %s/log; exit 0; fi\\necho wrong >> %s/log\\nexit 1\\n' \"$b\" \"$3\" \"$s\" \"$s\" > \"$s/bin/check-password.sh\"",
            // pam_faillock's shape: a user already locked out is neither counted nor reset
            "printf '#!%s\\nread -r count < %s/count\\nif [ \"$count\" -ge 3 ]; then echo \"$1 locked $count\" >> %s/log; exit 1; fi\\ncase $1 in\\n"
            + "preauth) echo \"preauth $count\" >> %s/log ;;\\n"
            + "authfail) count=$((count + 1)); echo $count > %s/count; echo \"authfail $count\" >> %s/log; exit 1 ;;\\n"
            + "authsucc) echo \"authsucc $count\" >> %s/log; echo 0 > %s/count ;;\\n*) exit 1 ;;\\nesac\\n' \"$b\" \"$s\" \"$s\" \"$s\" \"$s\" \"$s\" \"$s\" \"$s\" > \"$s/bin/counter.sh\"",
            "printf '#!%s\\nread -r answer < %s/finger\\necho \"finger $answer\" >> %s/log\\n[ \"$answer\" = ok ]\\n' \"$b\" \"$s\" \"$s\" > \"$s/bin/finger.sh\"",
            "chmod +x \"$s/bin/\"*.sh",
            // Arch's shape: sudo in /etc/pam.d, polkit-1 only in the vendor directory, system-auth of stand-ins
            "printf '#%%PAM-1.0\\nauth\\t\\tinclude\\t\\tsystem-auth\\naccount\\t\\tinclude\\t\\tsystem-auth\\nsession\\t\\tinclude\\t\\tsystem-auth\\n' > \"$s/etc/sudo\"",
            "printf '#%%PAM-1.0\\n\\nauth       include      system-auth\\naccount    include      system-auth\\npassword   include      system-auth\\nsession    include      system-auth\\n' > \"$s/usr/polkit-1\"",
            "printf '%s\\n' '#%PAM-1.0' \"auth required $m/pam_exec.so quiet $s/bin/counter.sh preauth\""
            + " \"auth [success=1 default=bad] $m/pam_exec.so quiet expose_authtok $s/bin/check-password.sh\""
            + " \"auth [default=die] $m/pam_exec.so quiet $s/bin/counter.sh authfail\" \"auth optional $m/pam_permit.so\""
            + " \"auth required $m/pam_exec.so quiet $s/bin/counter.sh authsucc\" \"account required $m/pam_permit.so\" > \"$s/etc/system-auth\"",
            "printf 'deny = 3\\n' > \"$s/faillock.conf\"",
            "printf '%s' \"$m\""
        ].join("\n"), [_scratch, Quickshell.shellDir, _password], result => {
            suite.assertEqual(result.code, 0, "the stand-ins are made (" + result.stderr + ")");
            suite._modules = result.stdout.trim();
            suite._ready = result.code === 0;
        });
    }
}
