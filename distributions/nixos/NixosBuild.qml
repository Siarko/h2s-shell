import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.io

// The build of a NixOS system with the shell's settings (NixBuildRules decides; this only
// runs): the user's configuration with only the shell's file replaced by the candidate, built
// as the user without a password — nix run directly (never through a shell) inside the shell's
// trusted `timeout`, which leads a process group of its own: Cancel ends that group, and with
// the nix client the daemon stops its build (where the shell found no trusted `timeout`, the
// command runner starts nix bare and Cancel signals nix alone). The candidate and the GC root that keeps the
// built system until Apply now live in a private folder of the user's under XDG_RUNTIME_DIR
// (scripts/nixos-build-files.sh), made anew for each build and removed by release() (after a
// failed or cancelled build at once). One build at a time; limit 2 hours.
//
// A configuration the user cannot build (NixBuildRules.needsRootBefore, or a build that failed
// with reason "needsRoot") is built by the root step's `build` (scripts/root/, read at the
// click and run as text through PrivilegedRuns.startShell) — only when the caller passes
// `asRoot`, which only the click on the build button carries; it cannot be cancelled, root's
// own GC root holds what it built (the root step passes on only nix's progress), and the
// user's own GC root for it is made right after it.
//
// The test seams take effect only in module test mode (a fixture suite's): `testPkexec` (as
// NixosApply's), and with it `testShell`, `testScriptsDirectory`, `testNix`, `testScratch` and
// `testSetEnvironment` (the system's /etc/set-environment). Anywhere else: the system's nix
// (/run/current-system/sw/bin/nix, the one the root step runs), $XDG_RUNTIME_DIR, /bin/sh, the
// shell's own scripts/root/ and NixosApplyRules.livePaths.
QtObject {
    id: root

    // Each change of `progress`, and the end of each build (NixBuildRules.outcome's)
    signal progressed(var progress)
    signal finished(var outcome)

    property string testPkexec: ""
    property string testShell: ""
    property string testScriptsDirectory: ""
    property string testNix: ""
    property string testScratch: ""
    property string testSetEnvironment: ""
    property var paths: NixosApplyRules.livePaths
    property var filesCommand: [Quickshell.shellDir + "/scripts/nixos-build-files.sh"]

    readonly property bool live: !(Modules.host.testMode && testPkexec !== "")
    readonly property string shell: !live && testShell !== "" ? testShell : "/bin/sh"
    readonly property string scriptsDirectory: !live && testScriptsDirectory !== "" ? testScriptsDirectory
        : Quickshell.shellDir + "/" + RootScriptRules.directory
    readonly property string nix: !live && testNix !== "" ? testNix : NixosApplyRules.livePaths.bin + "/nix"
    readonly property string scratch: !live && testScratch !== "" ? testScratch
        : (Quickshell.env("XDG_RUNTIME_DIR") ?? "") !== "" ? Quickshell.env("XDG_RUNTIME_DIR") + "/h2s-shell-nixos-build" : ""
    readonly property string setEnvironment: !live && testSetEnvironment !== "" ? testSetEnvironment : "/etc/set-environment"

    readonly property bool busy: _phase !== ""
    // The user's build is running (Cancel can stop it)
    readonly property bool cancellable: _phase === "building" && _handle !== null
    // NixBuildRules.progress of the build running or last ended
    readonly property var progress: NixBuildRules.progress(_state)
    // The out path whose GC root the private folder holds ("" none)
    readonly property string held: _held

    // "" idle, "preparing", "building", "holding" (the user's GC root for a root build),
    // "removing"
    property string _phase: ""
    property var _state: NixBuildRules.fresh()
    property var _handle: null
    property string _held: ""
    // Counts the builds: an answer of an earlier one (or one after a cancel) loses
    property int _run: 0
    property bool _cancelled: false

    // `request` { reading (NixosConfigRules.reading's, git asked), candidate (the shell's file
    // as it would be), asRoot (true only from the click on the build button, which then
    // carries the privileged mark) }; `handlers` { done (outcome → nothing, once), onProgress
    // (progress → nothing) } → { started, refusal (null or { code, text }) }
    function build(request, handlers) {
        if (busy)
            return { started: false, refusal: NixBuildRules.refusal("running") };
        const run = ++_run;
        _cancelled = false;
        if (request?.asRoot === true)
            return _buildAsRoot(run, request, handlers);
        const expression = NixBuildRules.expression(_readText(scriptsDirectory + "/" + NixBuildRules.toplevelFile));
        const plan = NixBuildRules.plan({
            reading: request?.reading, candidate: request?.candidate, expression, nixpkgs: NixBuildRules.systemNixpkgs(_readText(setEnvironment)),
            nix, scratch, home: Quickshell.env("HOME") ?? "",
            xdg: {
                XDG_CONFIG_HOME: Quickshell.env("XDG_CONFIG_HOME") ?? "", XDG_CACHE_HOME: Quickshell.env("XDG_CACHE_HOME") ?? "",
                XDG_DATA_HOME: Quickshell.env("XDG_DATA_HOME") ?? "", XDG_STATE_HOME: Quickshell.env("XDG_STATE_HOME") ?? ""
            }
        });
        if (plan.refusal !== null)
            return { started: false, refusal: plan.refusal };
        _begin(run, "preparing");
        _runner.start(filesCommand.concat(["prepare", scratch, request.candidate, plan.files.gitconfig]), {
            timeoutMs: 20000,
            maxOutputBytes: 4096,
            done: result => {
                if (!root._current(run))
                    return;
                if (root._cancelled || result.ok !== true || String(result.stdout).trim() !== "prepared") {
                    root._end(run, NixBuildRules.outcome(root._cancelled ? { cancelled: true } : { failedToStart: true }, root._state, NixosApplyRules.livePaths.store), handlers);
                    return;
                }
                root._startNix(run, plan, handlers);
            }
        });
        return { started: true, refusal: null };
    }

    // Stops the user's build: its process group ends; nothing it still prints counts. The
    // answer comes through `done` as cancelled. A root build cannot be stopped.
    function cancel() {
        if (_phase === "preparing") {
            _cancelled = true;
            return true;
        }
        if (!cancellable)
            return false;
        _cancelled = true;
        _handle.cancel();
        return true;
    }

    // Takes the private folder away, and with it the GC root of what was built (after Apply
    // now, or when the built system is no longer wanted). `done(ok)` once.
    function release(done) {
        if (busy) {
            done?.(false);
            return false;
        }
        _remove(++_run, ok => done?.(ok));
        return true;
    }

    function _current(run) {
        return run === _run;
    }

    function _begin(run, phase) {
        _phase = phase;
        _held = "";
        _handle = null;
        _state = NixBuildRules.fresh();
        progressed(progress);
    }

    function _startNix(run, plan, handlers) {
        _phase = "building";
        _handle = _runner.start(plan.argv, {
            environment: plan.environment,
            timeoutMs: NixBuildRules.timeoutMs,
            killAfterMs: 5000,
            maxOutputBytes: 65536,
            onLine: (line, stream) => {
                if (!root._current(run) || root._cancelled)
                    return;
                root._advance(line, stream, handlers);
            },
            done: result => {
                if (!root._current(run))
                    return;
                root._handle = null;
                // The user's nix builds into the system's store, whatever the root step's places
                const outcome = NixBuildRules.outcome(root._cancelled ? Object.assign({}, result, { cancelled: true }) : result, root._state,
                                                      NixosApplyRules.livePaths.store);
                if (outcome.ok)
                    root._held = outcome.outPath;
                root._end(run, outcome, handlers);
            }
        });
    }

    function _advance(line, stream, handlers) {
        const next = NixBuildRules.step(_state, line, stream);
        if (next === _state)
            return;
        _state = next;
        progressed(progress);
        _call(handlers?.onProgress, progress);
    }

    function _buildAsRoot(run, request, handlers) {
        const plan = NixBuildRules.rootPlan({ reading: request?.reading, candidate: request?.candidate }, paths, live,
                                            _scripts.read(), shell);
        if (plan.refusal !== null)
            return { started: false, refusal: plan.refusal };
        if (scratch === "")
            return { started: false, refusal: NixBuildRules.refusal("scratch") };
        _begin(run, "building");
        const startRequest = {
            what: plan.what,
            argv: plan.argv,
            timeoutMs: NixBuildRules.rootTimeoutMs,
            onLine: (line, stream) => {
                if (root._current(run))
                    root._advance(line, stream, handlers);
            }
        };
        if (!live)
            startRequest.testPkexec = testPkexec;
        PrivilegedRuns.startShell(startRequest, result => {
            if (!root._current(run))
                return;
            const outcome = NixBuildRules.rootOutcome(result, root._state, plan.expected);
            if (!outcome.ok) {
                root._end(run, outcome, handlers);
                return;
            }
            root._hold(run, request, outcome, handlers);
        });
        return { started: true, refusal: null };
    }

    // The user's own GC root for what the root step built, in a private folder made anew
    function _hold(run, request, outcome, handlers) {
        _phase = "holding";
        const failed = () => root._end(run, Object.assign({}, outcome, { ok: false, kind: "failed", reason: "hold", error: NixBuildRules.texts.hold }), handlers);
        _runner.start(filesCommand.concat(["prepare", scratch, request.candidate, ""]), {
            timeoutMs: 20000,
            maxOutputBytes: 4096,
            done: prepared => {
                if (!root._current(run))
                    return;
                if (prepared.ok !== true) {
                    failed();
                    return;
                }
                root._runner.start(NixBuildRules.holdArgv(root.nix, root.scratch + "/result", outcome.outPath), {
                    timeoutMs: 120000,
                    maxOutputBytes: 4096,
                    done: result => {
                        if (!root._current(run))
                            return;
                        if (result.ok !== true) {
                            failed();
                            return;
                        }
                        root._held = outcome.outPath;
                        root._end(run, outcome, handlers);
                    }
                });
            }
        });
    }

    // A build ended: what it left goes unless it built
    function _end(run, outcome, handlers) {
        const finish = () => {
            if (!root._current(run))
                return;
            root._phase = "";
            root._call(handlers?.done, outcome);
            root.finished(outcome);
        };
        if (outcome.ok) {
            finish();
            return;
        }
        _phase = "removing";
        _remove(run, finish);
    }

    function _remove(run, done) {
        const before = _phase;
        if (scratch === "") {
            done(false);
            return;
        }
        if (before === "")
            _phase = "removing";
        _runner.start(filesCommand.concat(["remove", scratch]), {
            timeoutMs: 20000,
            maxOutputBytes: 4096,
            done: result => {
                const ok = result.ok === true && String(result.stdout).trim() === "removed";
                if (root._current(run)) {
                    if (ok)
                        root._held = "";
                    if (before === "")
                        root._phase = "";
                }
                done(ok);
            }
        });
    }

    function _call(callback, value) {
        if (typeof callback !== "function")
            return;
        try {
            callback(value);
        } catch (error) {
            console.warn("[NixosBuild] a handler threw: " + String(error).slice(0, 300));
        }
    }

    // A small file read as it is now ("" missing or unreadable)
    function _readText(path) {
        if (path === "")
            return "";
        const view = _view.createObject(root, { path });
        const text = String(view.text() ?? "");
        view.destroy();
        return text;
    }

    property Component _view: Component {
        FileView {
            blockAllReads: true
            printErrors: false
        }
    }

    property RootScriptFiles _scripts: RootScriptFiles {
        names: NixosApplyRules.scriptFiles
        directory: root.scriptsDirectory
    }

    property CommandRunner _runner: CommandRunner {}
}
