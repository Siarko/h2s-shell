import QtQuick
import Quickshell
import qs.api
import qs.tests
import qs.singletons
import qs.distributions.nixos

// The shell's NixOS rebuild end to end (distributions/nixos/NixosRebuild.qml), in module test
// mode, with the real build (NixosBuild) and the real root step (NixosApply) on stand-ins:
// the user's build runs the stand-in nix of tests/fixtures/nixos-build/ (behind a gate the
// suite opens, so the build can be held running), a build as root and the root run run the
// real scripts/root/ through PrivilegedRuns.startShell on the fixture's stand-in pkexec as
// the user under a scratch base, with the stand-ins of tests/fixtures/nixos-apply/. Never the
// real nix, pkexec, store or profile. Clicks come from the event loop (Qt.callLater), as in
// the shell. Covered: a build as the user, the screen locked while it runs: it goes on to
// built, the notification sent, nothing asked as root; the notification's action only opens
// the page and panel; Create busy meanwhile; Apply now on a system the root step cannot name:
// back to built, said; Close lets the built system go; a failed build asks nothing; Cancel;
// a configuration only root can build: the Build click builds as root, Apply now's prompt
// dismissed (back to built, quiet), Apply now: the root run, applied, the file written; Undo
// through the same chain puts the file before back; exit 4 (applied with errors); the
// configuration changed since the build.
TestCase {
    id: suite
    suiteName: "NixosRebuild"
    asynchronous: true
    timeLimitMs: 120000

    readonly property var module: Api.moduleAt(Qt.resolvedUrl(".."))
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-nixos-rebuild-test-" + Date.now()
    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/nixos-build"
    readonly property string _applyFixtures: Quickshell.shellDir + "/tests/fixtures/nixos-apply"
    readonly property string _folder: _scratch + "/etc/nixos"
    readonly property string _private: _scratch + "/run/h2s-shell-nixos-build"
    readonly property string _first: "{\"version\":1}\n"
    readonly property string _second: "{\"version\":1,\"idle\":{\"hibernateDelay\":\"3h\"}}"
    readonly property string _third: "{\"version\":1,\"idle\":{\"hibernateDelay\":\"2h\"}}"
    readonly property string _out: _scratch + "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-nixos-system-test"
    readonly property string _drv: _scratch + "/nix/store/zyxwvsrqpnmlkjihgfdcba9876543210-nixos-system-test.drv"
    readonly property string _realOut: "/nix/store/aayigsnwrdbys1xrj2c6fsxg78nvj3n4-nixos-system-nixos-26.05.20261101.9bb5222"
    readonly property var _paths: ({ bin: _scratch + NixosApplyRules.livePaths.bin, profile: _scratch + NixosApplyRules.livePaths.profile,
                                     store: _scratch + NixosApplyRules.livePaths.store, backups: _scratch + NixosApplyRules.livePaths.backups })

    property var _steps: []
    property var _state: null
    property bool _ready: false
    property int _opened: 0
    // The run's clock: each read one second later
    property int _ticks: 0
    property real _builtAt: 0

    property NixosBuild builder: NixosBuild {
        paths: suite._paths
    }
    property NixosApply writer: NixosApply {
        paths: suite._paths
    }
    property NixosRebuild rebuild: NixosRebuild {
        builder: suite.builder
        writer: suite.writer
        clock: () => ++suite._ticks * 1000
        onOpened: suite._opened++
    }
    property NixosCreate creator: NixosCreate {
        writer: suite.writer
        rebuild: suite.rebuild
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

    function _shell(script, done) {
        runner.start(["sh", "-c", script, "sh", _scratch], { timeoutMs: 20000, done: result => done?.(result.code, String(result.stdout ?? "")) });
    }

    function _asked() {
        return !ModuleTestKit.privilegedIdle || PrivilegedRuns.count > 0;
    }

    function _builtNotices() {
        return ModuleTestKit.notified.filter(entry => entry.kind === "show" && entry.summary === NixosRebuildRules.texts.built);
    }

    // The configuration as the shell would have read it: a root-owned flake without git (built
    // as the user), or (`rootOnly`) in a repository that is neither the user's nor root's, so
    // that only root can build it; the shell's file holding `current`
    function _reading(current, rootOnly) {
        return {
            configuration: { found: true, folder: _folder, entry: "flake.nix", type: "flake" },
            real: _folder, rootWrites: true, host: "laptop",
            git: rootOnly ? "present" : "absent", gitAccess: "", gitKnowsFile: rootOnly ? "tracked" : "",
            file: { path: _folder + "/h2s-shell.json", state: "present", sha256: PamEditRules.sha256(current) }
        };
    }

    function _request(current, text, rootOnly) {
        return { key: "idle.hibernateDelay", value: text === _third ? "2h" : "3h", text, reading: _reading(current, rootOnly),
                 previous: { value: null, text: current } };
    }

    // The file and the stand-ins' record, read after a run
    function _look() {
        _state = null;
        _shell("cd \"$1\"; printf '== file\\n'; cat etc/nixos/h2s-shell.json; printf '\\n== calls\\n'; cat log/calls; printf '== private\\n'; "
               + "ls -A run/h2s-shell-nixos-build 2> /dev/null || echo '(none)'; true", (code, stdout) => {
            const at = name => stdout.indexOf("== " + name + "\n") + name.length + 4;
            suite._state = {
                file: stdout.slice(at("file"), stdout.indexOf("\n== calls\n")),
                calls: stdout.slice(at("calls"), stdout.indexOf("== private\n")).split("\n").filter(line => line !== ""),
                privateFolder: stdout.slice(at("private")).trim()
            };
        });
    }

    // A round trip through a process: anything the last event started has had its turn
    function _settle() {
        _ready = false;
        _shell("true", () => suite._ready = true);
    }

    function _reset(mode, setup) {
        _ready = false;
        _shell("set -e; cd \"$1\"; : > log/calls; rm -f ctl/pids ctl/gate; echo " + mode + " > ctl/mode; : > ctl/build.err; echo 0 > ctl/build.code; "
               + ": > ctl/eval.err; echo 0 > ctl/eval.code; echo 0 > ctl/switch.code; echo 0 > ctl/nix-env.code; : > ctl/nix-env.touch; "
               + "echo 0 > ctl/valid.code; echo 3 > ctl/active.code; echo 0 > ctl/systemd-run.code; "
               + "printf '[{\"drvPath\":\"%s\",\"outputs\":{\"out\":\"%s\"}}]\\n' '" + _drv + "' '" + _out + "' > ctl/build.out; "
               + "printf '%s %s\\n' '" + _drv + "' '" + _out + "' > ctl/eval.out; " + (setup ?? ""), code => {
            suite.assertEqual(code, 0, "the stand-ins reset");
            suite._ready = true;
        });
    }

    function runAsync() {
        assert(Api.testMode, "test mode is on");
        const tree = "set -e; umask 022; S=$1; mkdir -p \"$S/etc/nixos\" \"$S/run/current-system/sw/bin\" \"$S/nix/var/nix/profiles\" \"$4/bin\" \"$S/ctl\" \"$S/log\" \"$S/bin\" \"$S/run\"; "
            + "for t in nix nix-env nix-store systemctl systemd-run; do cp \"$3/$t\" \"$S/run/current-system/sw/bin/\"; done; cp \"$3/switch-to-configuration\" \"$4/bin/\"; "
            + "cp \"$2/nix\" \"$S/bin/nix-standin\"; printf '%s' \"$2\" > \"$S/ctl/fixtures\"; "
            // The user's nix behind a gate: while ctl/gate is there the build is held running
            + "printf '#!/bin/sh\\nwhile [ -e \"$(dirname \"$0\")/../ctl/gate\" ]; do sleep 0.05; done\\nexec \"$(dirname \"$0\")/nix-standin\" \"$@\"\\n' > \"$S/bin/nix\"; "
            + "chmod +x \"$S/bin/nix\"; : > \"$S/etc/nixos/flake.nix\"; printf '%s' \"$5\" > \"$S/etc/nixos/h2s-shell.json\"; "
            + "ln -s /nowhere \"$S/nix/var/nix/profiles/system-1-link\"; ln -s system-1-link \"$S/nix/var/nix/profiles/system\"; "
            + "printf 'export NIX_PATH=\"nixpkgs=/nix/store/abc-source\"\\n' > \"$S/etc/set-environment\"";
        runner.start(["sh", "-c", tree, "sh", _scratch, _fixtures, _applyFixtures, _out, _first], { timeoutMs: 20000, done: result => {
            suite.assertEqual(result.code, 0, "the scratch tree made");
            suite._ready = true;
        } });
        _then("the stand-ins known, the tree made, the shell's timeout looked up",
              () => module?.programsReady === true && _path("pkexec") !== "" && _ready && CommandTools.known, () => {
            builder.testPkexec = _path("pkexec");
            builder.testNix = _scratch + "/bin/nix";
            builder.testScratch = _private;
            builder.testSetEnvironment = _scratch + "/etc/set-environment";
            writer.testPkexec = _path("pkexec");
            assert(!builder.live && !writer.live, "the stand-ins' places");
            ModuleTestKit.clearRecords();
            _lockedBuild();
        });
        _clock.start();
    }

    // A build as the user while the screen locks: it goes on to built; the notification; its
    // action only opens; nothing asked as root
    function _lockedBuild() {
        _reset("build", "touch ctl/gate");
        _then("reset", () => _ready, () => {
            assertEqual(JSON.stringify(rebuild.announce(_request(_first, _second, false))), JSON.stringify({ taken: true, refusal: null }), "announce: taken");
            assertEqual(rebuild.phase, "announced", "… announced, nothing runs");
            assert(creator.busy, "… Create shows busy meanwhile");
            assertEqual(rebuild.announce(_request(_first, _third, false)).refusal.code, "running", "… a second Apply: busy");
            assertEqual(rebuild.state.asRoot, false, "… built as the user");
            assertEqual(rebuild.build().taken, true, "the Build click: taken");
        });
        _then("the build runs", () => rebuild.phase === "building" && builder.busy, () => {
            ModuleTestKit.setSessionLocked(true);
            _shell("rm -f \"$1/ctl/gate\"", null);
        });
        _then("built while locked", () => rebuild.phase === "built" && !builder.busy, () => {
            ModuleTestKit.setSessionLocked(false);
            assertEqual(rebuild.state.subject.outPath, _realOut, "built: the system built, keyed");
            assert(rebuild.times.started > 0 && rebuild.times.built > rebuild.times.started && rebuild.times.ended === 0,
                   "… the times: started building, built, not ended");
            assertEqual(builder.held, _realOut, "… held for Apply now");
            assertEqual(_builtNotices().length, 1, "… the notification: " + NixosRebuildRules.texts.built);
            assertEqual(JSON.stringify(_builtNotices()[0].actions), JSON.stringify(["Open"]), "… its one action");
            assert(!_asked(), "a lock, a build, its end, the notification: nothing asked as root");
            assertEqual(ModuleTestKit.pressNotificationAction(_builtNotices()[0].handle, "default"), "", "the notification's action pressed");
        });
        _then("the page opened", () => _opened === 1, () => {
            assertEqual(rebuild.phase + "|" + rebuild.state.error, "built|", "the action only opened: still waiting for Apply now");
            assert(!_asked(), "… nothing asked as root");
            // The system built as the user is in the real store's place: the stand-in root step
            // cannot name it, so the root run is refused before any prompt
            Qt.callLater(rebuild.applyNow, rebuild.state.subject.drvPath);
        });
        _then("Apply now answered", () => rebuild.state.error !== "", () => {
            assertEqual(rebuild.phase + "|" + rebuild.state.error, "built|" + NixosApplyRules.texts.built, "a root run not started: back to built, said");
            assert(!_asked(), "… nothing asked");
            assertEqual(rebuild.close().taken, true, "Close: the built system no longer wanted");
            assertEqual(rebuild.phase, "idle", "… idle");
            assert(!creator.busy, "… Create no longer busy");
        });
        _then("let go", () => builder.held === "" && !builder.busy, () => _look());
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.privateFolder, "(none)", "Close: the private folder and its GC root gone");
            _failedBuild();
        });
    }

    // A failed build: said, no notification, no prompt
    function _failedBuild() {
        ModuleTestKit.clearRecords();
        _reset("fail");
        _then("reset", () => _ready, () => {
            rebuild.announce(_request(_first, _second, false));
            rebuild.build();
        });
        _then("the build failed", () => rebuild.phase === "failed" && !builder.busy, () => {
            assertEqual(rebuild.state.outcome.reason + "|" + rebuild.state.outcome.error, "untracked|" + NixBuildRules.texts.untracked, "failed: said why");
            assertEqual(_builtNotices().length, 0, "… no notification");
            assert(!_asked(), "… nothing asked");
            assertEqual(rebuild.applyNow(rebuild.state.subject.drvPath).refusal.code, "notNow", "… Apply now refused");
            _cancelled();
        });
    }

    // Cancel: the build stops, nothing kept, nothing told
    function _cancelled() {
        _reset("hang");
        _then("reset", () => _ready, () => {
            rebuild.announce(_request(_first, _second, false));
            rebuild.build();
        });
        _then("the build waits", () => builder.cancellable && builder.progress.lines.includes("waiting"), () => {
            assertEqual(rebuild.cancel().taken, true, "Cancel: taken");
            assertEqual(rebuild.phase, "cancelled", "… cancelled");
        });
        _then("the build ended", () => !builder.busy, () => {
            assertEqual(rebuild.phase, "cancelled", "the build's own answer after the cancel changed nothing");
            assertEqual(_builtNotices().length, 0, "… no notification");
            assert(!_asked(), "… nothing asked");
            _rootBuildApplied();
        });
    }

    // Only root can build it: the Build click builds as root; Apply now's prompt dismissed is
    // quiet; Apply now: the root run, applied
    function _rootBuildApplied() {
        _reset("build", "mkdir -p etc/nixos/.git");
        _then("reset", () => _ready, () => {
            rebuild.announce(_request(_first, _second, true));
            assertEqual(rebuild.state.asRoot, true, "a repository only root may open: the build as root (the mark on Build)");
            assert(!_asked(), "… announcing asks nothing");
            Qt.callLater(rebuild.build);
        });
        _then("built by root", () => rebuild.phase === "built" && !builder.busy, () => {
            assertEqual(rebuild.state.subject.drvPath + " " + rebuild.state.subject.outPath, _drv + " " + _out, "built by the root step: keyed");
            _builtAt = rebuild.times.built;
            assertEqual(_builtNotices().length, 1, "… the notification");
            _opened = 0;
            assertEqual(ModuleTestKit.pressNotificationAction(_builtNotices()[0].handle, "default"), "", "its action pressed");
        });
        _then("the page opened", () => _opened === 1, () => _settle());
        _then("settled", () => _ready, () => {
            assert(rebuild.phase === "built" && !_asked() && !writer.busy, "the action only opened: no root run, nothing asked");
            writer.testShell = _path("dismiss");
            Qt.callLater(rebuild.applyNow, _drv);
        });
        _then("the dismissed prompt answered", () => rebuild.phase === "built" && !writer.busy && ModuleTestKit.privilegedIdle, () => {
            writer.testShell = "";
            assertEqual(rebuild.state.error, "", "a dismissed prompt: quiet, back to built");
            assertEqual(rebuild.times.built, _builtAt, "… the build's time kept");
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.file, _first, "… nothing written");
            Qt.callLater(rebuild.applyNow, _drv);
        });
        _then("the root run going", () => rebuild.phase === "switching" || rebuild.phase === "applied", () => {});
        _then("applied", () => rebuild.phase === "applied" && !writer.busy && !builder.busy, () => {
            assertEqual(rebuild.state.outcome.generation, 2, "applied: generation 2");
            assert(rebuild.times.built === _builtAt && rebuild.times.ended > rebuild.times.built, "… the run's end timed after its build");
            assert(rebuild.lines.includes("activating the configuration..."), "… the root run's lines kept");
            assert(!creator.busy, "… Create free again");
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.file, _second, "applied: the file holds the candidate");
            assert(_state.calls.some(line => /^switch /.test(line)), "… switched");
            assertEqual(_state.privateFolder, "(none)", "… the built system let go");
            _undo();
        });
    }

    // Undo: the file before through the same chain
    function _undo() {
        _reset("build");
        _then("reset", () => _ready, () => {
            // The file holds what the Apply wrote: the Undo is keyed to it as read now
            assertEqual(rebuild.undo(_reading(_second, true)).taken, true, "Undo: taken");
            assertEqual(rebuild.phase, "announced", "… announced (the Undo modal), nothing runs");
            assertEqual(rebuild.state.subject.undo + " " + rebuild.state.subject.text, "true " + _first, "… the file before as the candidate");
            assertEqual(rebuild.state.subject.sha256, PamEditRules.sha256(_second), "… keyed to the file as read now");
            Qt.callLater(rebuild.build);
        });
        _then("built", () => rebuild.phase === "built" && !builder.busy, () => Qt.callLater(rebuild.applyNow, _drv));
        _then("applied", () => rebuild.phase === "applied" && !writer.busy && !builder.busy, () => _look());
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.file, _first, "undone: the file before back");
            _withErrors();
        });
    }

    // Exit 4: applied, some services did not start
    function _withErrors() {
        _reset("build", "echo 4 > ctl/switch.code");
        _then("reset", () => _ready, () => {
            rebuild.announce(_request(_first, _third, true));
            Qt.callLater(rebuild.build);
        });
        _then("built", () => rebuild.phase === "built" && !builder.busy, () => Qt.callLater(rebuild.applyNow, _drv));
        _then("answered", () => rebuild.phase === "appliedWithErrors" && !writer.busy && !builder.busy, () => {
            assertEqual(rebuild.state.outcome.error, NixosApplyRules.texts.appliedWithErrors, "exit 4: applied with errors, said");
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.file, _third, "… the file written");
            _changed();
        });
    }

    // The configuration changed since the build: nothing written, nothing switched
    function _changed() {
        _reset("build");
        _then("reset", () => _ready, () => {
            rebuild.announce(_request(_third, _second, true));
            Qt.callLater(rebuild.build);
        });
        _then("built", () => rebuild.phase === "built" && !builder.busy, () => {
            _ready = false;
            _shell("printf '%s %s\\n' \"$1/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-nixos-system-test.drv\" '" + _out + "' > \"$1/ctl/eval.out\"",
                   code => suite._ready = code === 0);
        });
        _then("the configuration changed", () => _ready, () => Qt.callLater(rebuild.applyNow, _drv));
        _then("answered", () => rebuild.phase === "changed" && !writer.busy && !builder.busy, () => {
            assertEqual(rebuild.state.outcome.error, NixosApplyRules.texts.changed, "changed since the build: said, build again");
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.file, _third, "changed: the file as it was");
            assertEqual(_state.calls.filter(line => /^(nix-env -p|systemd-run|switch) /.test(line)).length, 0, "changed: nothing set or switched: " + _state.calls.join(" | "));
            rebuild.close();
            _cleanUp();
        });
    }

    function _cleanUp() {
        _ready = false;
        runner.start(["rm", "-rf", "--", _scratch], { timeoutMs: 20000, done: () => suite._ready = true });
        _then("the scratch folder removed", () => _ready, () => {});
    }
}
