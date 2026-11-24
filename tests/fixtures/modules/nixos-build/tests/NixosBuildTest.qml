import QtQuick
import Quickshell
import qs.api
import qs.tests
import qs.singletons
import qs.distributions.nixos

// The shell's NixOS build end to end (distributions/nixos/NixosBuild.qml), in module test
// mode: the user's build runs the stand-in nix of tests/fixtures/nixos-build/ (copied into a
// scratch folder: it replays a real build's lines, or fails, or waits) through the shell's
// command runner and the real scripts/nixos-build-files.sh; a build as root runs the real root
// step (scripts/root/, read at the click) through PrivilegedRuns.startShell on the fixture's
// stand-in pkexec as the user under a scratch base, with the stand-in nix of
// tests/fixtures/nixos-apply/. Never the real nix, pkexec or store. Covered: a refusal
// before anything runs; a build: its words and environment, its progress as it comes, built,
// the candidate and the GC root in the private folder (0700), nothing asked as root, one at a
// time, release() takes the folder away; a root-owned repository: a scratch HOME naming it
// safe; failures (git does not know a file; a file only root may read — said, never a prompt
// by itself), nothing left behind; Cancel: the whole process group ends, a line printed after
// the cancel loses; a build as root: only when asked (asRoot), a dismissed prompt quiet,
// refused for a configuration not root's, built by the root step and then held by the user's
// own GC root.
TestCase {
    id: suite
    suiteName: "NixosBuild"
    asynchronous: true
    timeLimitMs: 90000

    readonly property var module: Api.moduleAt(Qt.resolvedUrl(".."))
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-nixos-build-test-" + Date.now()
    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/nixos-build"
    readonly property string _applyFixtures: Quickshell.shellDir + "/tests/fixtures/nixos-apply"
    readonly property string _folder: _scratch + "/etc/nixos"
    readonly property string _private: _scratch + "/run/h2s-shell-nixos-build"
    readonly property string _candidate: "{\"version\":1,\"idle\":{\"hibernateDelay\":\"3h\"}}"
    readonly property string _rootOut: _scratch + "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-nixos-system-test"
    readonly property string _rootDrv: _scratch + "/nix/store/zyxwvsrqpnmlkjihgfdcba9876543210-nixos-system-test.drv"
    readonly property string _realOut: "/nix/store/aayigsnwrdbys1xrj2c6fsxg78nvj3n4-nixos-system-nixos-26.05.20261101.9bb5222"

    property var _steps: []
    property var _record: null
    property var _state: null
    property bool _ready: false

    property NixosBuild builder: NixosBuild {
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

    function _shell(script, done) {
        runner.start(["sh", "-c", script, "sh", _scratch], { timeoutMs: 20000, done: result => done?.(result.code, String(result.stdout ?? "")) });
    }

    // The configuration as the shell would have read it: a root-owned flake without git
    function _reading(more) {
        return Object.assign({
            configuration: { found: true, folder: _folder, entry: "flake.nix", type: "flake" },
            real: _folder, rootWrites: true, host: "laptop", git: "absent", gitAccess: "", gitKnowsFile: "",
            file: { path: _folder + "/h2s-shell.json", state: "present", sha256: "" }
        }, more ?? {});
    }

    // Asks for a build from the event loop, as a click does (a run as administrator asked with
    // a module's file on the stack is refused); its outcome and progress in _record
    function _build(request) {
        _record = { outcome: null, outcomes: 0, progress: [] };
        Qt.callLater(builder.build, request, {
            done: outcome => {
                suite._record.outcome = outcome;
                suite._record.outcomes++;
            },
            onProgress: progress => suite._record.progress.push(progress)
        });
    }

    // The stand-ins' record and the private folder, read after a run
    function _look() {
        _state = null;
        _shell("cd \"$1\"; printf '== calls\\n'; cat log/calls; printf '== private\\n'; ls -A run/h2s-shell-nixos-build 2> /dev/null || echo '(none)'; "
               + "printf '== mode\\n'; stat -c %a run/h2s-shell-nixos-build 2> /dev/null; printf '== candidate\\n'; cat run/h2s-shell-nixos-build/h2s-shell.json 2> /dev/null; "
               + "printf '\\n== link\\n'; readlink run/h2s-shell-nixos-build/result; true", (code, stdout) => {
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
            const lines = key => (sections[key] ?? []).filter(line => line !== "");
            suite._state = { calls: lines("calls"), privateFolder: lines("private"), mode: lines("mode")[0] ?? "", candidate: lines("candidate").join("\n"),
                             link: lines("link")[0] ?? "" };
        });
    }

    function _reset(mode, setup) {
        _ready = false;
        _shell("set -e; cd \"$1\"; : > log/calls; rm -f ctl/pids; echo " + mode + " > ctl/mode; : > ctl/build.err; echo 0 > ctl/build.code; "
               + "printf '[{\"drvPath\":\"%s\",\"outputs\":{\"out\":\"%s\"}}]\\n' '" + _rootDrv + "' '" + _rootOut + "' > ctl/build.out; " + (setup ?? ""), code => {
            suite.assertEqual(code, 0, "the stand-ins reset");
            suite._ready = true;
        });
    }

    function runAsync() {
        assert(Api.testMode, "test mode is on");
        const tree = "set -e; umask 022; S=$1; mkdir -p \"$S/etc/nixos\" \"$S/run/current-system/sw/bin\" \"$S/nix/store\" \"$S/ctl\" \"$S/log\" \"$S/bin\" \"$S/run\"; "
            + "for t in nix nix-env nix-store systemctl systemd-run; do cp \"$3/$t\" \"$S/run/current-system/sw/bin/\"; done; cp \"$2/nix\" \"$S/bin/nix\"; "
            + "printf '%s' \"$2\" > \"$S/ctl/fixtures\"; : > \"$S/etc/nixos/flake.nix\"; "
            + "printf 'export NIX_PATH=\"nixpkgs=/nix/store/abc-source\"\\n' > \"$S/etc/set-environment\"";
        runner.start(["sh", "-c", tree, "sh", _scratch, _fixtures, _applyFixtures], { timeoutMs: 20000, done: result => {
            suite.assertEqual(result.code, 0, "the scratch tree made");
            suite._ready = true;
        } });
        _then("the stand-ins known, the tree made, the shell's timeout looked up",
              () => module?.programsReady === true && _path("pkexec") !== "" && _ready && CommandTools.known, () => {
            assertEqual(builder.live, true, "no stand-in pkexec yet: the system's nix and places");
            assertEqual(builder.nix, "/run/current-system/sw/bin/nix", "live: the system's nix, the one the root step runs");
            builder.testPkexec = _path("pkexec");
            builder.testNix = _scratch + "/bin/nix";
            builder.testScratch = _private;
            builder.testSetEnvironment = _scratch + "/etc/set-environment";
            assertEqual(builder.live, false, "the stand-in pkexec in test mode: the stand-ins' places");
            const refused = builder.build({ reading: _reading({ git: "present", gitAccess: "user", gitKnowsFile: "untracked" }), candidate: _candidate }, {});
            assertEqual(JSON.stringify(refused), JSON.stringify({ started: false, refusal: NixBuildRules.refusal("untracked") }),
                        "git does not know the shell's file: refused before anything runs");
            assert(!builder.busy, "… nothing running");
            _built();
        });
        _clock.start();
    }

    // A build as the user: its words, its progress, built, held; release() takes it away
    function _built() {
        let askedAsRoot = false;
        _reset("build");
        _then("reset", () => _ready, () => _build({ reading: _reading(), candidate: _candidate }));
        _then("the build is answered", () => _record.outcome !== null && !builder.busy, () => {
            askedAsRoot = !ModuleTestKit.privilegedIdle || PrivilegedRuns.count > 0;
            const outcome = _record.outcome;
            assert(outcome.ok && outcome.kind === "built" && outcome.outPath === _realOut && outcome.drvPath.endsWith("-nixos-system-nixos-26.05.20261101.9bb5222.drv"),
                   "built: nix's drvPath and out path: " + JSON.stringify([outcome.kind, outcome.reason, outcome.outPath]));
            assertEqual(_record.outcomes, 1, "… answered once");
            assertEqual(builder.held, _realOut, "the built system held");
            const labels = _record.progress.map(progress => progress.label);
            assertEqual(labels[0], "Evaluating", "progress: evaluating first");
            assertEqual(labels[labels.length - 1], "Building 15 of 16", "progress: the builds counted as they came");
            assert(labels.includes("Building 3 of 16"), "progress: each build on its way");
            assertEqual(builder.progress.label, "Building 15 of 16", "the last progress kept after the end");
            assert(!askedAsRoot, "a build as the user asks nothing as root");
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.calls[0], "nix build --impure --extra-experimental-features nix-command flakes --log-format internal-json -v --json --out-link "
                        + _private + "/result --expr EXPR", "the words: nix build of the expression, its GC root in the private folder");
            assertEqual(_state.calls[1], "nix-env flake=path:" + _folder + " host=laptop candidate=" + _private + "/h2s-shell.json home="
                        + (Quickshell.env("HOME") ?? "unset") + " nixpath=unset nixconfig=unset", "the environment: the flake, the host, the candidate; no NIX_PATH or NIX_CONFIG");
            assertEqual(_state.calls[2], "nix-candidate " + _candidate, "the candidate as given");
            assertEqual(_state.mode, "700", "the private folder only the user's");
            assertEqual(_state.candidate, _candidate, "the candidate in it");
            assertEqual(_state.link, _realOut, "the GC root in it");
            _record = { released: null };
            builder.release(ok => suite._record.released = ok);
        });
        _then("released", () => _record.released !== null, () => {
            assertEqual(_record.released, true, "release: done");
            assertEqual(builder.held, "", "release: nothing held");
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(JSON.stringify(_state.privateFolder), JSON.stringify(["(none)"]), "release: the private folder and its GC root gone");
            _rootRepository();
        });
    }

    // A repository root owns: nix with a scratch HOME naming it safe
    function _rootRepository() {
        _reset("build", "mkdir -p etc/nixos/.git");
        _then("reset", () => _ready, () => _build({ reading: _reading({ git: "present", gitAccess: "root", gitKnowsFile: "tracked" }), candidate: _candidate }));
        _then("the build is answered", () => _record.outcome !== null && !builder.busy, () => {
            assert(_record.outcome.ok, "root's repository: built as the user");
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assert(_state.calls[1].startsWith("nix-env flake=git+file://" + _folder + " host=laptop candidate=" + _private + "/h2s-shell.json home=" + _private + "/home "),
                   "root's repository: git+file://, the scratch HOME: " + _state.calls[1]);
            assertEqual(_state.calls[3], "nix-gitconfig " + ((Quickshell.env("HOME") ?? "") !== "" && RootScriptRules.plainPath(Quickshell.env("HOME"))
                        ? "[include]  path = " + Quickshell.env("HOME") + "/.gitconfig " : "") + "[safe]  directory = " + _folder + " ",
                        "root's repository: its .gitconfig names the folder safe, includes the user's own");
            _record = { released: null };
            builder.release(ok => suite._record.released = ok);
        });
        _then("released", () => _record.released !== null, () => _failed());
    }

    // Failures: said, nothing left behind, never a prompt by themselves
    function _failed() {
        _reset("fail", "rm -rf etc/nixos/.git");
        _then("reset", () => _ready, () => _build({ reading: _reading(), candidate: _candidate }));
        _then("the failed build is answered", () => _record.outcome !== null && !builder.busy, () => {
            const outcome = _record.outcome;
            assert(!outcome.ok && outcome.kind === "failed" && outcome.reason === "untracked" && outcome.error === NixBuildRules.texts.untracked,
                   "git does not know a file: said: " + JSON.stringify([outcome.kind, outcome.reason]));
            assert(outcome.lines.length > 0, "… with the last lines");
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(JSON.stringify(_state.privateFolder), JSON.stringify(["(none)"]), "failed: the private folder gone");
            _reset("denied");
        });
        _then("reset", () => _ready, () => _build({ reading: _reading(), candidate: _candidate }));
        _then("the denied build is answered", () => _record.outcome !== null && !builder.busy, () => {
            const outcome = _record.outcome;
            assert(!outcome.ok && outcome.reason === "needsRoot", "a file only root may read: the build needs root: " + outcome.reason);
            assert(ModuleTestKit.privilegedIdle && PrivilegedRuns.count === 0, "… nothing asked as root by itself");
            _cancelled();
        });
    }

    // Cancel: the process group ends; a line after the cancel loses
    function _cancelled() {
        let pids = "";
        _reset("hang");
        _then("reset", () => _ready, () => _build({ reading: _reading(), candidate: _candidate }));
        _then("the build waits", () => builder.cancellable && builder.progress.lines.includes("waiting"), () => {
            _shell("cat \"$1/ctl/pids\"", (code, stdout) => pids = stdout.trim());
        });
        _then("its pids read", () => pids.split(" ").length === 2, () => {
            assertEqual(JSON.stringify(builder.build({ reading: _reading(), candidate: _candidate }, {})),
                        JSON.stringify({ started: false, refusal: NixBuildRules.refusal("running") }), "one build at a time");
            assertEqual(builder.cancel(), true, "cancel: taken");
        });
        _then("the cancelled build is answered", () => _record.outcome !== null && !builder.busy, () => {
            const outcome = _record.outcome;
            assert(!outcome.ok && outcome.kind === "cancelled", "cancelled: said: " + outcome.kind);
            assert(!builder.progress.lines.includes("late line") && !outcome.lines.includes("late line"), "a line printed after the cancel loses");
            _state = null;
            _shell("for p in " + pids + "; do kill -0 \"$p\" 2> /dev/null && echo alive; done; ls -A \"$1/run\"", (code, stdout) => suite._state = { text: stdout.trim() });
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.text.includes("alive"), false, "cancel: the stand-in nix and its child both gone (the group ended)");
            assertEqual(_state.text.includes("h2s-shell-nixos-build"), false, "cancel: the private folder gone");
            assertEqual(builder.cancel(), false, "nothing left to cancel");
            _asRoot();
        });
    }

    // A build as root: only when asked; a dismissed prompt quiet; refused for a configuration
    // not root's; built by the root step, then held by the user's own GC root
    function _asRoot() {
        _reset("build");
        _then("reset", () => _ready, () => {
            const refused = builder.build({ reading: _reading({ rootWrites: false }), candidate: _candidate, asRoot: true }, {});
            assertEqual(JSON.stringify(refused), JSON.stringify({ started: false, refusal: NixBuildRules.refusal("rootOnly") }),
                        "as root: refused for a configuration not root's alone");
            builder.testShell = _path("dismiss");
            _build({ reading: _reading(), candidate: _candidate, asRoot: true });
        });
        _then("the dismissed build is answered", () => _record.outcome !== null && !builder.busy, () => {
            builder.testShell = "";
            const outcome = _record.outcome;
            assert(outcome.quiet && !outcome.ok, "as root, dismissed: quiet: " + JSON.stringify([outcome.kind, outcome.reason]));
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.calls.length, 0, "as root, dismissed: nothing ran");
            _reset("build");
        });
        _then("reset", () => _ready, () => _build({ reading: _reading(), candidate: _candidate, asRoot: true }));
        _then("the root build is answered", () => _record.outcome !== null && !builder.busy, () => {
            const outcome = _record.outcome;
            assert(outcome.ok && outcome.kind === "built" && outcome.drvPath === _rootDrv && outcome.outPath === _rootOut,
                   "as root: built by the root step: " + JSON.stringify([outcome.kind, outcome.reason, outcome.error]));
            assertEqual(builder.held, _rootOut, "as root: held");
            assert(outcome.lines.includes("pkexec:build") && outcome.lines.includes("pkexec:" + _folder), "as root: the root step's build of the folder");
            _look();
        });
        _then("looked at", () => _state !== null, () => {
            assertEqual(_state.calls[0], "nix build --impure --extra-experimental-features nix-command flakes --log-format internal-json -v --no-link --json --expr EXPR",
                        "as root: the root step's nix build");
            assertEqual(_state.calls[_state.calls.length - 2], "nix build --extra-experimental-features nix-command flakes --out-link " + _private + "/result -- " + _rootOut,
                        "as root: then the user's own GC root for it");
            assertEqual(_state.link, _rootOut, "as root: the GC root in the private folder");
            _record = { released: null };
            builder.release(ok => suite._record.released = ok);
        });
        _then("released", () => _record.released !== null, () => _cleanUp());
    }

    function _cleanUp() {
        _ready = false;
        runner.start(["rm", "-rf", "--", _scratch], { timeoutMs: 20000, done: () => suite._ready = true });
        _then("the scratch folder removed", () => _ready, () => {});
    }
}
