import QtQuick
import Quickshell
import qs.api
import qs.tests
import qs.singletons
import qs.distributions.nixos

// The shell's NixOS root step end to end (distributions/nixos/NixosApply.qml): the real
// PrivilegedRuns.startShell with the fixture's stand-in pkexec as its testPkexec (module test
// mode only), the real root step (scripts/root/, read at the click) run by it as the user
// under a scratch base, with the stand-in nix, nix-env, nix-store, systemctl, systemd-run and
// switch-to-configuration of tests/fixtures/nixos-apply/. Never the real pkexec, profile,
// store or /etc. The writer is asked from the event loop (Qt.callLater), as a click in the
// shell asks it: a call with a module's file on its stack is refused before the queue.
// Covered: a refusal before any run; while locked: quiet, nothing run; a dismissed prompt:
// quiet, nothing changed; Apply: its lines handed on as they come and in order, under the
// 30 minutes, applied with the backup and generation, one run at a time; the configuration
// changed since the build; a failed activation and its Undo (restore).
TestCase {
    id: suite
    suiteName: "NixosApply"
    asynchronous: true
    timeLimitMs: 60000

    readonly property var module: Api.moduleAt(Qt.resolvedUrl(".."))
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-nixos-apply-writer-test-" + Date.now()
    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/nixos-apply"
    readonly property string _folder: _scratch + "/etc/nixos"
    readonly property string _out: _scratch + "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-nixos-system-test"
    readonly property string _drv: _scratch + "/nix/store/zyxwvsrqpnmlkjihgfdcba9876543210-nixos-system-test.drv"
    readonly property string _first: "{\"version\":1}\n"
    readonly property string _second: "{\"version\":1,\"idle\":{\"hibernateDelay\":\"3h\"}}"
    readonly property string _third: "{\"version\":1,\"idle\":{\"hibernateDelay\":\"2h\"}}"

    property var _steps: []
    property var _record: null
    property var _state: null
    property bool _ready: false

    property NixosApply writer: NixosApply {
        paths: ({ bin: suite._scratch + NixosApplyRules.livePaths.bin, profile: suite._scratch + NixosApplyRules.livePaths.profile,
                  store: suite._scratch + NixosApplyRules.livePaths.store, backups: suite._scratch + NixosApplyRules.livePaths.backups })
    }
    property CommandRunner runner: CommandRunner {}

    function _then(description, condition, action) {
        _steps.push({ description, condition, action });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite.finish();
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
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    function _path(name) {
        return module?.programs?.[name]?.path ?? "";
    }

    function _sha(text) {
        return PamEditRules.sha256(text);
    }

    // A shell command in the scratch base ($1); `done(code, stdout)`
    function _shell(script, done) {
        runner.start(["sh", "-c", script, "sh", _scratch], { timeoutMs: 20000, done: result => done?.(result.code, String(result.stdout ?? "")) });
    }

    // The configuration as the shell would have read it: a root-owned flake with the shell's
    // file holding `current`
    function _reading(current) {
        return {
            configuration: { found: true, folder: _folder, entry: "flake.nix", type: "flake" },
            rootWrites: true, host: "laptop",
            file: { path: _folder + "/h2s-shell.json", state: "present", sha256: _sha(current) }
        };
    }

    // Asks the writer from the event loop; its outcome and lines in _record
    function _ask(method, first, more) {
        _record = { lines: [], outcome: null, outcomes: 0 };
        const handlers = Object.assign({
            done: outcome => {
                suite._record.outcome = outcome;
                suite._record.outcomes++;
            },
            onLine: (line, stream) => suite._record.lines.push([stream, line])
        }, more ?? {});
        if (method === "undo")
            Qt.callLater(writer.undo, handlers);
        else
            Qt.callLater(writer.apply, first, handlers);
    }

    // The file, the stand-ins' record and the profile, read after a run
    function _look() {
        _state = null;
        _shell("cd \"$1\"; printf '== file\\n'; cat etc/nixos/h2s-shell.json; printf '\\n== calls\\n'; cat log/calls; printf '== profile\\n'; readlink nix/var/nix/profiles/system",
               (code, stdout) => {
            const at = name => stdout.indexOf("== " + name + "\n") + name.length + 4;
            suite._state = {
                file: stdout.slice(at("file"), stdout.indexOf("\n== calls\n")),
                calls: stdout.slice(at("calls"), stdout.indexOf("== profile\n")).split("\n").filter(line => line !== "").map(line => line.split(" ")[0]),
                profile: stdout.slice(at("profile")).trim()
            };
        });
    }

    // Every case starts from the stand-ins' answers for success and an empty record
    function _reset(setup) {
        _ready = false;
        _shell("set -e; cd \"$1\"; : > log/calls; : > ctl/eval.err; echo 0 > ctl/eval.code; echo 0 > ctl/switch.code; echo 0 > ctl/nix-env.code; "
               + ": > ctl/nix-env.touch; echo 0 > ctl/valid.code; echo 3 > ctl/active.code; echo 0 > ctl/systemd-run.code; "
               + "printf '%s %s\\n' '" + _drv + "' '" + _out + "' > ctl/eval.out; " + (setup ?? ""), code => {
            suite.assertEqual(code, 0, "the stand-ins reset");
            suite._ready = true;
        });
    }

    function _apply(current, json) {
        return { op: "apply", reading: _reading(current), candidate: { text: json, drvPath: _drv, outPath: _out } };
    }

    function runAsync() {
        assert(Api.testMode, "test mode is on");
        const tree = "set -e; umask 022; S=$1; F=$2; mkdir -p \"$S/etc/nixos\" \"$S/run/current-system/sw/bin\" \"$S/nix/var/nix/profiles\" \"$S/ctl\" \"$S/log\" \"$3/bin\"; "
            + "for t in nix nix-env nix-store systemctl systemd-run; do cp \"$F/$t\" \"$S/run/current-system/sw/bin/\"; done; cp \"$F/switch-to-configuration\" \"$3/bin/\"; "
            + ": > \"$S/etc/nixos/flake.nix\"; printf '%s' \"$4\" > \"$S/etc/nixos/h2s-shell.json\"; "
            + "ln -s /nowhere \"$S/nix/var/nix/profiles/system-1-link\"; ln -s system-1-link \"$S/nix/var/nix/profiles/system\"";
        runner.start(["sh", "-c", tree, "sh", _scratch, _fixtures, _out, _first], { timeoutMs: 20000, done: result => {
            suite.assertEqual(result.code, 0, "the scratch tree made");
            suite._ready = true;
        } });
        _then("the stand-ins known, the tree made, the shell's timeout looked up",
              () => module?.programsReady === true && _path("pkexec") !== "" && _ready && CommandTools.known, () => {
            writer.testPkexec = _path("pkexec");
            // Refused before a run: no prompt, nothing queued
            const refused = writer.apply({ op: "apply", reading: _reading(_first), candidate: { text: _second, drvPath: _out, outPath: _out } }, {});
            assertEqual(JSON.stringify(refused), JSON.stringify({ started: false, refusal: NixosApplyRules.refusal("built") }), "a refusal before any run, said at once");
            assert(!writer.busy && ModuleTestKit.privilegedIdle, "… nothing queued");
            _locked();
        });
        _clock.start();
    }

    // While locked: quiet, nothing run, nothing changed
    function _locked() {
        _reset();
        _then("reset", () => _ready, () => {
            ModuleTestKit.setSessionLocked(true);
            _ask("apply", _apply(_first, _second));
        });
        _then("the locked run is answered", () => _record.outcome !== null && !writer.busy, () => {
            ModuleTestKit.setSessionLocked(false);
            const outcome = _record.outcome;
            assert(outcome.quiet && !outcome.ok && outcome.kind === "" && outcome.nothingChanged && outcome.error === "",
                   "while locked: quiet, nothing changed: " + JSON.stringify(outcome));
            assertEqual(_record.lines.length, 0, "… no line");
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.file, _first, "locked: the file as it was");
            assertEqual(_state.calls.length, 0, "locked: nothing ran");
            _dismissed();
        });
    }

    // A dismissed prompt: quiet, nothing changed
    function _dismissed() {
        _reset();
        _then("reset", () => _ready, () => {
            writer.shell = _path("dismiss");
            _ask("apply", _apply(_first, _second));
        });
        _then("the dismissed run is answered", () => _record.outcome !== null && !writer.busy, () => {
            writer.shell = "/bin/sh";
            const outcome = _record.outcome;
            assert(outcome.quiet && !outcome.ok && outcome.kind === "" && outcome.nothingChanged && outcome.error === "",
                   "dismissed: quiet, nothing changed: " + JSON.stringify(outcome));
            assertEqual(ModuleTestKit.notified.filter(entry => entry.summary.endsWith(" failed")).length, 0, "… no failure told");
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.file, _first, "dismissed: the file as it was");
            assertEqual(_state.calls.length, 0, "dismissed: nothing ran");
            _applied();
        });
    }

    // Apply: the lines as they come, in order; applied; one run at a time
    function _applied() {
        _reset();
        let second = null;
        _then("reset", () => _ready, () => _ask("apply", _apply(_first, _second)));
        _then("the run started", () => writer.busy, () => {
            second = writer.apply(_apply(_first, _third), {});
        });
        _then("the run is answered", () => _record.outcome !== null && !writer.busy, () => {
            assertEqual(JSON.stringify(second), JSON.stringify({ started: false, refusal: NixosApplyRules.refusal("running") }), "one run at a time");
            const outcome = _record.outcome;
            assert(outcome.ok && outcome.kind === "applied" && outcome.generation === 2 && NixosApplyRules.validBackup(outcome.backup)
                   && outcome.sha256 === _sha(_second) && outcome.folder === _folder, "applied: generation 2, a backup, the candidate: " + JSON.stringify(outcome));
            assertEqual(_record.outcomes, 1, "… answered once");
            const errors = _record.lines.filter(entry => entry[0] === "stderr").map(entry => entry[1]);
            const limit = errors.indexOf("pkexec:-k");
            assertEqual(errors.slice(limit, limit + 3).join(" "), "pkexec:-k pkexec:3 pkexec:1800", "the stand-in pkexec handed 30 minutes, the prompt shows it");
            assertEqual(errors[limit + 3], "pkexec:/bin/sh", "… then the shell, the root step's text after it");
            const activating = errors.indexOf("activating the configuration...");
            assert(limit >= 0 && activating > limit, "the activation's line handed on after pkexec's words: " + activating);
            assertEqual(errors[errors.length - 1], "applied 2 " + outcome.backup, "… and the root step's last line last");
            assertEqual(JSON.stringify(_record.lines.filter(entry => entry[0] === "stdout")), JSON.stringify([["stdout", "applied 2 " + outcome.backup]]),
                        "its last line on stdout too");
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.file, _second, "applied: the file holds the candidate");
            assertEqual(_state.calls.join(","), "nix,nix-vars,nix-home,nix-candidate,nix-store,systemctl,nix-env,systemd-run,switch", "applied: evaluated, set, switched");
            assertEqual(_state.profile, "system-2-link", "applied: the profile at the new generation");
            _changed();
        });
    }

    // The configuration changed since the build: nothing written, nothing switched
    function _changed() {
        _reset("printf '%s %s\\n' \"$1/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-nixos-system-test.drv\" '" + _out + "' > ctl/eval.out");
        _then("reset", () => _ready, () => _ask("apply", _apply(_second, _third)));
        _then("the run is answered", () => _record.outcome !== null && !writer.busy, () => {
            const outcome = _record.outcome;
            assert(!outcome.ok && outcome.kind === "changed" && outcome.nothingChanged && outcome.error === NixosApplyRules.texts.changed,
                   "changed since the build: said so, nothing changed: " + JSON.stringify(outcome));
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.file, _second, "changed: the file as it was");
            assertEqual(_state.calls.filter(name => ["nix-env", "systemd-run", "switch"].includes(name)).length, 0, "changed: nothing set or switched");
            _failedThenUndo();
        });
    }

    // A failed activation keeps the file; Undo puts the one before back
    function _failedThenUndo() {
        let failed = null;
        _reset("echo 1 > ctl/switch.code");
        _then("reset", () => _ready, () => _ask("apply", _apply(_second, _third)));
        _then("the failed run is answered", () => _record.outcome !== null && !writer.busy, () => {
            failed = _record.outcome;
            assert(!failed.ok && failed.kind === "failed" && failed.generation === 3 && !failed.nothingChanged && failed.sha256 === _sha(_third)
                   && failed.error === NixosApplyRules.texts.failed, "a failed activation: failed, maybe partly changed: " + JSON.stringify(failed));
            _ask("undo", null, { from: failed, reading: _reading(_third) });
        });
        _then("the undo is answered", () => _record.outcome !== null && !writer.busy, () => {
            const outcome = _record.outcome;
            assert(outcome.ok && outcome.kind === "restored" && outcome.op === "restore" && outcome.sha256 === _sha(_second) && NixosApplyRules.validBackup(outcome.backup),
                   "undo: the file before back: " + JSON.stringify(outcome));
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.file, _second, "undo: the file holds what it held before the Apply");
            _cleanUp();
        });
    }

    function _cleanUp() {
        _ready = false;
        runner.start(["rm", "-rf", "--", _scratch], { timeoutMs: 20000, done: () => suite._ready = true });
        _then("the scratch folder removed", () => _ready, () => {});
    }
}
