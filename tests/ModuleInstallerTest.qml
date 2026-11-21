import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.io

// The module installer (singletons/ModuleInstaller.qml) on stand-ins made in a private
// temporary directory (tests/fixtures/installer/setup.sh): local bare git repositories reached
// by file://, folders, a hand-placed folder and a hand-made link in the user root, and a
// stand-in `git` first on the installer's PATH that logs every command line and can hang,
// refuse, report a download too large or print progress. Its own module host, with
// confirmations on, searches with the launcher's own search (scripts/launch.sh
// --discover-modules) in that directory's data home. Covered: a tagged install with progress,
// an update, a switch back, an update that does not start and goes back, deleting a version,
// a chain of two, a missing dependency, a failure on the second of a chain (taken back, a
// link on the way untouched), a module that fails the check, an id placed by hand, folders
// (a clean one kept off, one with a link out), git hanging, refusing and too large, removing
// a hand-made link (its target untouched), a hand-placed folder, a chain with the dependency
// installed for it, a module with its data; and that nothing named a non-file address.
// Runs after the suites that turn modules off through Config (AnchorsTest and those before
// it), since this one does too.
TestCase {
    id: suite
    suiteName: "ModuleInstaller"
    asynchronous: true
    timeLimitMs: 240000

    property var after: null

    // Made once the suites before are done: nothing of this suite exists while they run
    property ModuleHost host: null
    property ModuleInstaller installer: null
    property Component _hostComponent: Component {
        ModuleHost {
            logStates: false
            confirmations: true
        }
    }
    property Component _installerComponent: Component {
        ModuleInstaller {
            loadTimeoutMs: 20000
            downloadTimeoutMs: 20000
            onProgressChanged: {
                if (progress !== null)
                    suite._progressSeen = suite._progressSeen.concat([progress]);
            }
        }
    }
    property CommandRunner runner: CommandRunner {}

    property string temp: ""
    property var commits: ({})
    property var _out: null
    property var _state: null
    property var _progressSeen: []
    property var _steps: []
    property string _savedAcknowledged: ""
    property var _savedDisabled: []
    property var _savedEnabled: []
    property bool _saved: false
    property string _savedProfiles: ""
    property real _largeStarted: 0

    // ---- A tiny scheduler: each step waits for its condition (or its deadline), then runs ----

    function _then(description, condition, action, timeoutMs) {
        _steps.push({ description: description, condition: condition, action: action, deadline: timeoutMs ?? 30000 });
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
            } catch (error) {
                ready = false;
            }
            if (!ready && waited < step.deadline)
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

    function _end() {
        if (_saved)
            assertEqual(Config.profiles + "|" + Config.globals, _savedProfiles, "the profiles and globals untouched (a removal with data of a module without settings)");
        if (_saved) {
            Config.setAcknowledgedModulesText(_savedAcknowledged);
            Config.disabledModules = _savedDisabled;
            Config.enabledModules = _savedEnabled;
        }
        host?.unload();
        if (temp.startsWith("/") && temp.includes("h2s-installer.")) {
            runner.start(["rm", "-rf", "--", temp], { timeoutMs: 30000, done: () => suite.finish() });
            return;
        }
        finish();
    }

    // ---- Helpers ----

    function _sh(script, args) {
        _out = null;
        runner.start(["sh", "-c", script, "sh"].concat(args ?? []), {
            timeoutMs: 30000,
            done: result => suite._out = { ok: result.ok, lines: result.stdout === "" ? [] : result.stdout.split("\n") }
        });
    }

    function _data() {
        return temp + "/data/h2s-shell";
    }

    // The user root, the versions, the staging place and the record, as they are on disk
    readonly property string stateScript: "D=$1/data/h2s-shell; "
        + "for e in \"$D\"/modules/* \"$D\"/modules/.[!.]*; do { [ -e \"$e\" ] || [ -L \"$e\" ]; } || continue; "
        + "if [ -L \"$e\" ]; then printf 'link\\t%s\\t%s\\n' \"${e##*/}\" \"$(readlink -- \"$e\")\"; else printf 'dir\\t%s\\n' \"${e##*/}\"; fi; done; "
        + "[ -d \"$D/module-versions\" ] && find \"$D/module-versions\" -mindepth 1 -maxdepth 2 -printf 'version\\t%P\\n' | sort; "
        + "n=0; [ -d \"$D/module-staging\" ] && n=$(ls -A \"$D/module-staging\" | wc -l); printf 'staging\\t%s\\n' \"$n\"; "
        + "[ -f \"$D/module-sources.json\" ] && printf 'record\\t%s\\n' \"$(tr -d '\\n' < \"$D/module-sources.json\")\"; "
        + "[ -d \"$D/module-versions\" ] && find \"$D/module-versions\" -name .git -printf 'git\\t%P\\n'; true"

    function _parseState(lines) {
        const state = { links: {}, dirs: [], versions: [], staging: -1, record: null, gitDirs: [] };
        for (const line of lines) {
            const fields = line.split("\t");
            if (fields[0] === "link")
                state.links[fields[1]] = fields[2];
            else if (fields[0] === "dir")
                state.dirs.push(fields[1]);
            else if (fields[0] === "version")
                state.versions.push(fields[1]);
            else if (fields[0] === "staging")
                state.staging = Number(fields[1]);
            else if (fields[0] === "git")
                state.gitDirs.push(fields[1]);
            else if (fields[0] === "record") {
                try {
                    state.record = JSON.parse(line.slice(7));
                } catch (error) {
                    state.record = "unreadable";
                }
            }
        }
        return state;
    }

    // Reads the disk, then checks it
    function _check(description, check) {
        _then(description + ": the disk is read", () => true, () => _sh(stateScript, [temp]));
        _then(description + ": the disk was read", () => _out !== null, () => {
            _state = _parseState(_out.lines);
            check(_state);
        });
    }

    function _idle() {
        return !installer.busy && host.settled && !host.discovering;
    }

    // Starts a job when everything is idle, and checks how it ended
    function _job(description, start, check, timeoutMs) {
        _then(description + ": nothing runs", _idle, () => {
            const why = start();
            assertEqual(why, "", description + ": started");
        });
        _then(description + ": done", () => !installer.busy, () => check(installer.lastResult ?? {}), timeoutMs ?? 60000);
    }

    function _mode(mode) {
        _then("the stand-in git: " + (mode || "the real one"), () => true, () => _sh("printf '%s' \"$2\" > \"$1/fake/mode\"", [temp, mode]));
        _then("the stand-in git's mode is set", () => _out !== null, () => {});
    }

    // Waits until no stand-in git and none of its sleeps is left (a git that outlived its
    // reader would be one); then checks so
    function _noneLeft(description) {
        _then(description + ": the processes are looked for", () => true, () => _sh(
            "for i in $(seq 1 50); do pgrep -f \"$1/[n]aps/sleep|$1/[f]ake/git\" > /dev/null || exit 0; sleep 0.2; done; "
            + "pgrep -af \"$1/[n]aps/sleep|$1/[f]ake/git\"; exit 1", [temp]));
        _then(description + ": the processes were looked for", () => _out !== null, () =>
              assert(_out.ok, description + ": no stand-in git or its sleep left (" + _out.lines.join("; ") + ")"));
    }

    function _url(name, ref) {
        return "file://" + temp + "/repos/" + name + ".git" + (ref ? "#" + ref : "");
    }

    function _short(ref) {
        return String(commits[ref] ?? "").slice(0, 7);
    }

    function _status(id) {
        return host.status(id);
    }

    // ---- The run ----

    function runAsync() {
        _then("the config is read", () => Config.ready, () => {
            host = _hostComponent.createObject(suite);
            installer = _installerComponent.createObject(suite, { host: host });
            _savedAcknowledged = Config.acknowledgedModulesText;
            _savedDisabled = host._plainList(Config.disabledModules);
            _savedEnabled = host._plainList(Config.enabledModules);
            _saved = true;
            _savedProfiles = Config.profiles + "|" + Config.globals;
            // A list written (empty): what is new asks, nothing is acknowledged as a baseline
            Config.setAcknowledgedModules({});
            Config.disabledModules = [];
            Config.enabledModules = [];
            _sh("bash \"$1\"", [Quickshell.shellDir + "/tests/fixtures/installer/setup.sh"]);
        }, 120000);
        _then("the stand-ins are made", () => _out !== null, () => {
            assert(_out.ok, "the stand-ins are made (git on PATH, a temporary directory)");
            temp = _out.ok ? _out.lines[_out.lines.length - 1] : "";
            if (temp === "") {
                _steps = [];
                return;
            }
            _sh("for r in v1.0.0 main broken; do git -C \"$1/repos/alpha.git\" rev-parse \"$r^{commit}\"; done", [temp]);
        });
        _then("the commits are read", () => _out !== null, () => {
            commits = { "v1.0.0": _out.lines[0], "main": _out.lines[1], "broken": _out.lines[2] };
            assert(/^[0-9a-f]{40}$/.test(commits["v1.0.0"]) && /^[0-9a-f]{40}$/.test(commits.broken), "the fixture's commits");
            host.sourcePlaces = ModuleInstallRules.sourcePlaces({ dataHome: temp + "/data", moduleDataDirs: "", builtin: "" });
            host.discoveryCommand = ["bash", Quickshell.shellDir + "/scripts/launch.sh", "--discover-modules"];
            host.discoveryEnvironment = { XDG_DATA_HOME: temp + "/data", H2S_SHELL_MODULE_PATH: "", H2S_SHELL_MODULE_DATA_DIRS: "",
                                          H2S_SHELL_BUILTIN_MODULES: "" };
            installer.dataHome = temp + "/data";
            installer.configHome = temp + "/config";
            installer.home = temp;
            installer.environment = { PATH: temp + "/fake:" + (Quickshell.env("PATH") ?? ""), GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null" };
            assertEqual(host.rediscover(), "", "the host searches the temporary data home");
        });
        _then("the hand-placed modules are loaded", () => host.loadCount > 0 && _idle(), () => {
            assertEqual(_status("handmade")?.source + " " + _status("linked")?.source, "user user", "a folder and a link placed by hand: the user's");
            _refusals();
        });
        _installs();
        _versions();
        _chains();
        _linkFailure();
        _refused();
        _folders();
        _standIns();
        _removals();
        _job("a commit by its id", () => installer.install(_url("alpha", commits["v1.0.0"]), {}), result =>
             assert(result.ok, "alpha at a full commit id: fetched by id (" + result.message + ")"));
        _check("a commit by its id", state => {
            assertEqual(state.record?.alpha?.ref + " " + state.record?.alpha?.active, commits["v1.0.0"] + " 1.0.0-" + _short("v1.0.0"),
                        "the record keeps the commit as its ref, the version named by it");
            assertEqual(state.gitDirs.length + state.staging, 0, "… no .git kept, staging emptied");
        });
        _then("nothing runs", _idle, () => _sh("cat \"$1/git.log\"", [temp]));
        _then("the git log is read", () => _out !== null, () => {
            const lines = _out.lines.filter(line => line !== "");
            assert(lines.length >= 10, "the stand-in git was run (" + lines.length + " command lines)");
            const addresses = [].concat(...lines.map(line => line.split(" ").filter(word => /^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(word) || /^[^\/\s]+@[^\/\s]+:/.test(word))));
            assert(addresses.length >= 8, "… with addresses (" + addresses.length + ")");
            assertEqual(addresses.filter(address => !address.startsWith("file:///")).join(" "), "", "nothing ran named a non-file address: the network is never touched");
            assert(lines.every(line => line.includes("core.hooksPath=/dev/null")), "… and every git command ran without hooks");
            assert(lines.filter(line => line.includes(" clone ")).every(line => line.includes("--no-recurse-submodules") && line.includes("protocol.allow=never")),
                   "… every clone without submodules, only the listed protocols");
        });
        // Nothing ticks while the suites before run (their layout checks poll on timers of
        // their own): the clock starts when they are done
        if (after === null || after.done)
            _clock.start();
    }

    property Connections _afterDone: Connections {
        target: suite.after
        function onDoneChanged() {
            if (suite.after.done && suite.selected && suite._steps.length > 0 && !suite._clock.running)
                suite._clock.start();
        }
    }

    // Refused at once, nothing started
    function _refusals() {
        assert(installer.install("ext::sh -c touch% /tmp/x", {}) !== "", "a transport that runs commands: refused at once");
        assertEqual(installer.install("", {}), "No address or folder given", "nothing given: refused");
        assert(installer.install("/a/../b", {}) !== "", "a folder path with \"..\": refused");
        assert(installer.remove("nothere", "/x", {}).startsWith("No module"), "remove: no such module");
        assert(installer.remove("handmade", temp + "/elsewhere", {}).startsWith("The module changed"), "remove: another directory than the module's (the subject): refused");
        host.locked = true;
        assertEqual(installer.install(_url("alpha"), {}), "Refused while the session is locked", "locked: nothing installs");
        assertEqual(installer.remove("handmade", _data() + "/modules/handmade", {}), "Refused while the session is locked", "… nothing is removed");
        assertEqual(installer.switchVersion("alpha", "x") + "|" + installer.deleteVersion("alpha", "x"),
                    "Refused while the session is locked|Refused while the session is locked", "… no version switched or deleted");
        host.locked = false;
        assertEqual(installer.busy, false, "… and no job started");
    }

    function _installs() {
        _mode("progress");
        _then("alpha at its tag: nothing runs", _idle, () => {
            _progressSeen = [];
            assertEqual(installer.install(_url("alpha", "v1.0.0"), {}), "", "alpha at its tag: started");
            assert(installer.busy, "… a job runs");
            assertEqual(installer.install(_url("beta"), {}), "Another module job is running", "… a second one is refused meanwhile");
        });
        _then("alpha at its tag: done", () => !installer.busy, () => {
            const result = installer.lastResult;
            assert(result?.ok === true, "alpha at its tag: installed (" + result?.message + ")");
            assertEqual(JSON.stringify(result?.ids), JSON.stringify(["alpha"]), "… the module it was about");
            const read = _progressSeen.find(each => each.percent === 50);
            assertEqual(read ? read.phase + " " + read.bytes + " " + read.rate : "none", "receiving 1048576 2097152", "… git's progress read while it downloaded");
            assert(_progressSeen.some(each => each.percent === 25), "… each redraw on its own (git ends them with a carriage return, not a line break)");
        }, 60000);
        _mode("");
        _check("alpha at its tag", state => {
            const dir = "1.0.0-" + _short("v1.0.0");
            assertEqual(state.links.alpha, _data() + "/module-versions/alpha/" + dir, "the link in the user root leads to the version's directory");
            assert(state.versions.includes("alpha/" + dir), "… the version's directory");
            assertEqual(state.staging, 0, "… nothing left in staging");
            assertEqual(state.gitDirs.length, 0, "… no .git kept in a version");
            const entry = state.record?.alpha;
            assertEqual(entry?.kind + " " + entry?.address + " " + entry?.ref + " " + entry?.active,
                        "repository " + _url("alpha") + " v1.0.0 " + dir, "… the record: the address, the ref, the active version");
            assertEqual(entry?.versions?.[0]?.commit, commits["v1.0.0"], "… with its commit");
        });
        _then("alpha starts", () => _status("alpha")?.state === "loaded", () => {
            assertEqual(_status("alpha").source + " " + _status("alpha").version, "repository 1.0.0", "installed and turned on: the shell's own, loaded");
            assert(ModuleRules.has(host.acknowledgements, "alpha"), "… acknowledged (the install was the confirmation)");
        });

        _job("alpha updated to main", () => installer.install(_url("alpha"), {}), result => {
            assert(result.ok, "alpha updated to main's head (" + result.message + ")");
            assert(result.message.includes("updated alpha"), "… said as an update");
        });
        _check("alpha updated", state => {
            const dir = "1.1.0-" + _short("main");
            assertEqual(state.links.alpha, _data() + "/module-versions/alpha/" + dir, "the link moved to the new version");
            assert(state.versions.includes("alpha/1.0.0-" + _short("v1.0.0")), "… the version before is kept");
            assertEqual(state.record?.alpha?.active + " " + state.record?.alpha?.versions?.length + " " + state.record?.alpha?.ref, dir + " 2 ",
                        "… the record: the new one active, two kept, no ref (the default branch)");
        });
        _then("alpha 1.1.0 runs", () => _status("alpha")?.version === "1.1.0" && _status("alpha")?.state === "loaded",
              () => assert(true, "the updated module loaded without a restart, still on"));
    }

    function _versions() {
        const old = () => "1.0.0-" + _short("v1.0.0");
        _job("switch back", () => installer.switchVersion("alpha", old()), result => assert(result.ok, "switched back to 1.0.0 (" + result.message + ")"));
        _check("switched", state => {
            assertEqual(state.links.alpha, _data() + "/module-versions/alpha/" + old(), "the link leads to the kept version");
            assertEqual(state.record?.alpha?.active, old(), "… the record says so");
        });
        _then("alpha 1.0.0 runs", () => _status("alpha")?.version === "1.0.0" && _status("alpha")?.state === "loaded", () => assert(true, "… and it runs"));
        _job("switch to the active one", () => installer.switchVersion("alpha", old()), result =>
             assert(!result.ok && result.message.includes("already the active"), "switching to the active version: refused (" + result.message + ")"));
        _job("switch to one not kept", () => installer.switchVersion("alpha", "9.9.9-0000000"), result =>
             assert(!result.ok && result.message.includes("not a kept version"), "… to one not kept: refused"));

        _job("an update that does not start", () => installer.install(_url("alpha", "broken"), {}), result => {
            assert(result.ok, "the update to 1.2.0 installed (" + result.message + ")");
            assert(result.message.includes("did not start") && result.message.includes("back to " + old()), "… it did not start: back to the version before, said so");
        });
        _check("back on a failed start", state => {
            assertEqual(state.links.alpha, _data() + "/module-versions/alpha/" + old(), "the link is back on the version before");
            assertEqual(state.record?.alpha?.active, old(), "… the record too");
            assert(state.versions.includes("alpha/1.2.0-" + _short("broken")), "… the failed version kept (at most three)");
            assertEqual(state.versions.filter(each => each.startsWith("alpha/")).length, 3, "… three versions");
        });
        _then("alpha 1.0.0 runs again", () => _status("alpha")?.version === "1.0.0" && _status("alpha")?.state === "loaded", () => assert(true, "… and it runs again"));

        _job("delete a kept version", () => installer.deleteVersion("alpha", "1.1.0-" + _short("main")), result => assert(result.ok, "a kept version deleted (" + result.message + ")"));
        _check("a version deleted", state => {
            assert(!state.versions.includes("alpha/1.1.0-" + _short("main")), "its directory is gone");
            assertEqual((state.record?.alpha?.versions ?? []).map(each => each.dir).includes("1.1.0-" + _short("main")), false, "… and its record entry");
        });
        _job("delete the active version", () => installer.deleteVersion("alpha", old()), result =>
             assert(!result.ok && result.message.includes("active"), "the active version cannot be deleted"));
    }

    function _chains() {
        _job("a chain of two", () => installer.install(_url("beta"), {}), result => {
            assert(result.ok, "beta installed with gamma (" + result.message + ")");
            assertEqual(JSON.stringify(result.ids), JSON.stringify(["gamma", "beta"]), "… the provider first");
        });
        _check("a chain of two", state => {
            assert(state.links.beta !== undefined && state.links.gamma !== undefined, "both linked");
            assertEqual(state.record?.gamma?.installedFor + "|" + state.record?.beta?.installedFor, "beta|", "… gamma recorded as installed for beta");
            assertEqual(state.record?.gamma?.address, _url("gamma"), "… from the source beta names");
        });
        _then("the chain runs", () => _status("beta")?.state === "loaded" && _status("gamma")?.state === "loaded",
              () => assertEqual(_status("gamma").installedFor, "beta", "both loaded; gamma's status says whom it was installed for"));

        _job("a missing dependency", () => installer.install(_url("delta"), {}), result =>
             assert(!result.ok && result.message.includes("Needs nothere"), "a dependency with no source: not installed, said why (" + result.message + ")"));
        _check("a missing dependency", state => {
            assert(state.links.delta === undefined && !state.versions.some(each => each.startsWith("delta")), "nothing of it moved in");
            assertEqual(state.staging, 0, "… staging emptied");
        });

        _then("a link where the second module goes", _idle, () => _sh("ln -s \"$1/elsewhere\" \"$1/data/h2s-shell/module-versions/rho\"", [temp]));
        _then("the link is made", () => _out !== null, () => assert(_out.ok, "module-versions/rho made a link elsewhere"));
        _job("a failure on the second", () => installer.install(_url("rho"), {}), result =>
             assert(!result.ok && result.message.includes("rho"), "the second of the chain could not move in: nothing installed (" + result.message + ")"));
        _check("taken back", state => {
            assert(state.links.pi === undefined && state.links.rho === undefined, "no link of either: the first was taken back");
            assertEqual(state.versions.filter(each => each.startsWith("pi")).join(","), "", "… pi's version deleted, its directory too");
            assertEqual(state.staging, 0, "… staging emptied");
            assert(state.record?.pi === undefined && state.record?.rho === undefined, "… the record unchanged");
        });
        _then("the link's target is read", () => true, () => _sh("cat \"$1/elsewhere/marker\"; ls -A \"$1/elsewhere\" | wc -l; rm -f \"$1/data/h2s-shell/module-versions/rho\"", [temp]));
        _then("the link's target was read", () => _out !== null, () =>
              assertEqual(_out.lines.slice(0, 2).join(" ").trim(), "keep 1", "… what the link led to is untouched"));
    }

    // A failure once the record names the new versions: the links cannot be made (the user
    // root not writable), so everything goes back — versions, staging, the record's entries
    function _linkFailure() {
        _then("the user root made read-only", _idle, () => _sh("chmod 555 \"$1/data/h2s-shell/modules\"", [temp]));
        _then("the user root is read-only", () => _out !== null, () => assert(_out.ok, "the user root made read-only"));
        _job("links that cannot be made", () => installer.install(_url("rho"), {}), result =>
             assert(!result.ok && result.message.includes("its link could not be made"), "a link that cannot be made: nothing installed (" + result.message + ")"));
        _then("the user root writable again", () => true, () => _sh("chmod 755 \"$1/data/h2s-shell/modules\"", [temp]));
        _then("the user root is writable", () => _out !== null, () => {});
        _check("taken back after the record", state => {
            assert(state.record !== null && state.record !== "unreadable", "the record is there and reads");
            assert(state.record?.pi === undefined && state.record?.rho === undefined, "… the entries written before the links taken out again");
            assertEqual(state.versions.filter(each => each.startsWith("pi") || each.startsWith("rho")).join(","), "", "… the versions deleted");
            assertEqual(state.staging, 0, "… staging emptied");
            assert(state.record?.alpha !== undefined, "… the other entries as they were");
        });
    }

    function _refused() {
        _job("a module that fails the check", () => installer.install(_url("bad"), {}), result =>
             assert(!result.ok && result.message.includes("module.json"), "a manifest that fails the host's rules: not installed (" + result.message + ")"));
        _job("an id placed by hand", () => installer.install(_url("taken"), {}), result =>
             assert(!result.ok && result.message.includes("not installed by the shell"), "an id held by a folder placed by hand: never replaced (" + result.message + ")"));
        _job("an id held under another name", () => installer.install(_url("zeta"), {}), result =>
             assert(!result.ok && result.message.includes("as aaa"), "an id a hand-placed folder of another name holds: refused, naming it (" + result.message + ")"));
        _then("zeta is not acknowledged", _idle, () => {
            assert(!ModuleRules.has(host.acknowledgements, "zeta"), "… the hand-placed module of that id is not acknowledged");
            assert(_status("zeta")?.state !== "loaded", "… nor turned on (" + _status("zeta")?.state + ")");
        });
        _check("refused ones", state => {
            assertEqual(state.dirs.join(","), "aaa,handmade", "the hand-placed folders are still there");
            assert(!state.versions.some(each => each.startsWith("bad") || each.startsWith("handmade") || each.startsWith("zeta")), "… nothing of them moved in");
            assertEqual(state.staging, 0, "… staging emptied");
        });
    }

    function _folders() {
        _job("a folder with a link out", () => installer.install(temp + "/folders/leaky", {}), result =>
             assert(!result.ok && result.message.includes("a link leads out of the module"), "a folder holding a link out: refused (" + result.message + ")"));
        // Without confirmations a new module would load at once: kept off must keep it off
        _then("confirmations off", _idle, () => host.confirmations = false);
        _job("a folder, kept off", () => installer.install(temp + "/folders/clean/", { enable: false }), result =>
             assert(result.ok && result.message.includes("kept off"), "a folder copied, kept off (" + result.message + ")"));
        _check("a folder", state => {
            const entry = state.record?.folded;
            assertEqual(entry?.kind + " " + entry?.address, "folder " + temp + "/folders/clean", "the record: a folder, its path");
            assert(/^0\.3\.0-\d{14}$/.test(entry?.active ?? ""), "… its version directory named by the time: " + entry?.active);
            assertEqual(state.staging, 0, "… staging emptied");
        });
        _then("the folder module is there, off", () => _idle() && _status("folded") !== null, () => {
            assertEqual(_status("folded").source, "folder", "the copy is the shell's own (folder)");
            assertEqual(_status("folded").state, "disabled", "… off, with confirmations off too");
            assert(host._plainList(Config.disabledModules).includes("folded"), "… in the list of modules turned off");
            assert(!ModuleRules.has(host.acknowledgements, "folded"), "… not acknowledged");
            host.confirmations = true;
        });
    }

    function _standIns() {
        _mode("refuse");
        _job("git refuses", () => installer.install(_url("gamma"), {}), result =>
             assert(!result.ok && result.message.endsWith("repos/gamma: download failed — git: repository 'stand-in' not found"),
                    "a refusing server: said in one line (" + result.message + ")"));
        _mode("large");
        _then("too large: nothing runs", _idle, () => {
            suite._largeStarted = Date.now();
            assertEqual(installer.install(_url("gamma"), {}), "", "too large: started");
        });
        _then("too large: done", () => !installer.busy, () => {
            const result = installer.lastResult;
            assert(!result.ok && result.message.includes("larger than 100 MiB"), "a download git reports past the cap: stopped (" + result.message + ")");
            assert(Date.now() - suite._largeStarted < 15000, "… while it runs, from a progress line redrawn without a line break — not at the time limit");
        }, 60000);
        _noneLeft("a download cancelled");
        _mode("grow");
        _then("a small cap", () => true, () => {
            installer.maxDownloadBytes = 256 * 1024;
            installer.measureIntervalMs = 100;
        });
        _job("a download that grows past the cap", () => installer.install(_url("gamma"), {}), result =>
             assert(!result.ok && result.message.includes("larger than 256 KiB"), "a download measured while git writes it: stopped past the cap (" + result.message + ")"));
        _mode("bigfile");
        _then("measured rarely", () => true, () => installer.measureIntervalMs = 60000);
        _job("one file past the cap", () => installer.install(_url("gamma"), {}), result =>
             assert(!result.ok && result.message.includes("larger than 256 KiB"), "a single file past the cap: stopped by the file size limit at once (" + result.message + ")"));
        _then("the cap back", () => true, () => {
            installer.maxDownloadBytes = ModuleInstallRules.maxDownloadBytes;
            installer.measureIntervalMs = 1000;
        });
        _mode("hang");
        _then("a short time limit", () => true, () => installer.downloadTimeoutMs = 2000);
        _then("git hangs: nothing runs", _idle, () => {
            assertEqual(installer.install(_url("gamma"), {}), "", "git hangs: started");
            // While it hangs: the stand-in's sleep runs under its own name, as every program
            // the stand-ins start must (a multi-call coreutils picks its tool by that name)
            _sh("for i in $(seq 1 50); do for p in $(pgrep -f \"$1/[n]aps/sleep 30\"); do "
                + "a=$(tr '\\0' '\\n' < /proc/$p/cmdline | head -n 1); [ \"${a##*/}\" = sleep ] && { echo \"$a\"; exit 0; }; done; sleep 0.1; done; exit 1", [temp]);
        });
        _then("git hangs: its sleep is looked at", () => _out !== null, () =>
              assert(_out.ok, "… the stand-in's sleep started as \"sleep\" (" + _out.lines.join(" ") + ")"));
        _then("git hangs: done", () => !installer.busy, () => {
            const result = installer.lastResult;
            assert(!result.ok && result.message.includes("did not answer within 2 s"), "a server that never answers: stopped at the limit (" + result.message + ")");
        }, 60000);
        _noneLeft("a download past its time limit");
        _then("the time limit back", () => true, () => installer.downloadTimeoutMs = 20000);
        _mode("");
        _check("the stand-ins", state => assertEqual(state.staging, 0, "nothing left in staging after any of them"));
    }

    // What Remove would delete, read without a job: the question's words
    property var _preview: null
    property string _handKey: ""
    function _previewOf(description, id, directory, check) {
        _then(description + ": preview asked", _idle, () => {
            suite._preview = null;
            installer.removalPreview(id, directory(), preview => suite._preview = preview);
            assert(!installer.busy, description + ": no job for a preview");
        });
        _then(description + ": preview read", () => _preview !== null, () => check(_preview));
    }

    function _removals() {
        _previewOf("a hand-made link", "linked", () => temp + "/outside/linked", preview => {
            assert(preview.ok, "preview of a link (" + preview.reason + ")");
            assertEqual(preview.title + "|" + preview.lines[0], "Remove " + _status("linked").name + "?|Not installed by the shell.", "… its title, not installed by the shell");
            assert(preview.lines[1].startsWith("Deletes only the link;") && preview.lines[1].endsWith("stays."), "… only the link (" + preview.lines[1] + ")");
        });
        _previewOf("a hand-placed folder", "handmade", () => _data() + "/modules/handmade", preview => {
            assert(preview.ok && preview.lines[1].startsWith("Deletes the folder "), "preview of a folder: the folder deleted (" + preview.lines.join(" | ") + ")");
            assert(typeof preview.key === "string" && preview.key !== "", "… with the key of its plan");
            suite._handKey = preview.key;
        });
        _job("a stale plan", () => installer.remove("handmade", _data() + "/modules/handmade", { planKey: "stale" }), result =>
             assert(!result.ok && result.message === "The module changed", "remove with a plan key that no longer holds: refused (" + result.message + ")"));
        _previewOf("another directory", "handmade", () => temp + "/elsewhere", preview =>
                   assert(!preview.ok && preview.reason === "The module changed", "preview: another directory than the module's refused"));
        _previewOf("the chain", "beta", () => _status("beta").directory, preview => {
            assert(preview.ok && preview.lines[0].startsWith("Deletes "), "preview of an installed module: its versions (" + preview.lines.join(" | ") + ")");
            assertEqual(preview.orphans.map(each => each.id).join(","), "gamma", "… the dependency installed for it alone offered");
            assert(preview.orphans[0].label.startsWith("Also remove Gamma (installed for "), "… with its label (" + preview.orphans[0].label + ")");
        });
        _job("a hand-made link", () => installer.remove("linked", temp + "/outside/linked", {}), result => assert(result.ok, "a link placed by hand removed (" + result.message + ")"));
        _job("a hand-placed folder", () => installer.remove("handmade", _data() + "/modules/handmade", { planKey: suite._handKey }), result => assert(result.ok, "a folder placed by hand removed (" + result.message + ")"));
        _then("the link's target is read", _idle, () => _sh("cat \"$1/outside/linked/module.json\" > /dev/null && echo there", [temp]));
        _then("the link's target was read", () => _out !== null, () => assertEqual(_out.lines[0], "there", "the link's target is untouched"));
        _check("hand-placed ones removed", state => {
            assertEqual(state.links.linked + " " + state.dirs.join(","), "undefined aaa", "the link and the folder are gone (the other hand-placed one stays)");
        });

        _job("the chain without its dependency", () => installer.remove("beta", _status("beta").directory, {}), result => {
            assert(result.ok, "beta removed (" + result.message + ")");
            assert(result.message.includes("used by nothing else: Gamma"), "… gamma offered, not removed");
        });
        _then("gamma stays", () => _idle() && _status("beta") === null, () => assert(_status("gamma") !== null, "gamma stays without being chosen"));
        _then("beta again", _idle, () => assertEqual(installer.install(_url("beta"), {}), "", "beta installed again"));
        _then("beta is back", () => _idle() && _status("beta")?.state === "loaded", () => {});
        _job("the chain with its dependency", () => installer.remove("beta", _status("beta").directory, { alsoRemove: ["gamma"] }), result => {
            assert(result.ok, "beta removed with gamma (" + result.message + ")");
            assertEqual(JSON.stringify(result.ids), JSON.stringify(["beta", "gamma"]), "… both");
        });
        _check("the chain removed", state => {
            assert(state.links.beta === undefined && state.links.gamma === undefined, "both links gone");
            assert(!state.versions.some(each => each.startsWith("beta") || each.startsWith("gamma")), "… every version");
            assert(state.record?.beta === undefined && state.record?.gamma === undefined, "… their records");
        });

        _then("a run cut off", _idle, () => _sh("V=$1/data/h2s-shell/module-versions/alpha; a=$(readlink \"$1/data/h2s-shell/modules/alpha\"); "
                                                + "cp -R \"$a\" \"$V/9.9.9-abcdef0\" && ln -s \"$V/9.9.9-abcdef0\" \"$1/data/h2s-shell/modules/.alpha.link.999\" "
                                                + "&& ln -sfn \"$V/9.9.9-abcdef0\" \"$1/data/h2s-shell/modules/alpha\"", [temp]));
        _then("the cut-off state is made", () => _out !== null, () => {
            assert(_out.ok, "alpha linked to a version the record does not list, a temporary link left (a run cut off)");
            assertEqual(installer.tidy(), "", "the start's tidying runs");
        });
        _then("tidied", () => !installer.busy, () => assert(installer.lastResult?.ok && installer.lastResult.message.includes("put right"), "… and puts the record right (" + installer.lastResult?.message + ")"));
        _check("tidied", state => {
            assertEqual(state.record?.alpha?.active, "9.9.9-abcdef0", "the linked version listed and active: alpha stays the shell's");
            assertEqual(Object.keys(state.links).filter(name => name.startsWith(".")).length, 0, "… the temporary link gone");
            assertEqual(host.rediscover(), "", "the host loads what is there now");
        });
        _then("alpha is loaded from the version linked", () => _idle() && _status("alpha")?.directory.endsWith("/9.9.9-abcdef0"),
              () => assertEqual(_status("alpha").source, "repository", "… still the shell's own"));
        _then("alpha has data", _idle, () => _sh("mkdir -p \"$1/data/h2s-shell/module-data/alpha\" \"$1/config/h2s_shell/modules\" && touch \"$1/data/h2s-shell/module-data/alpha/x\" && printf '{}' > \"$1/config/h2s_shell/modules/alpha.json\" && printf '{}' > \"$1/config/h2s_shell/modules/alphax.json\"", [temp]));
        _then("alpha's data is made", () => _out !== null, () => assert(_out.ok, "alpha's data directory and store made"));
        _job("a module with its data", () => installer.remove("alpha", _status("alpha").directory, { withData: true }), result =>
             assert(result.ok && result.message.includes("with its data"), "alpha removed with its data (" + result.message + ")"));
        _check("alpha removed", state => {
            assert(state.links.alpha === undefined && !state.versions.some(each => each.startsWith("alpha")), "its link and every kept version gone");
            assertEqual(state.record?.alpha, undefined, "… its record");
            assert(!ModuleRules.has(host.acknowledgements, "alpha"), "… its acknowledgement: installed again, it asks again");
        });
        _then("alpha's data is read", () => true, () => _sh("ls -A \"$1/data/h2s-shell/module-data\" \"$1/config/h2s_shell/modules\"", [temp]));
        _then("alpha's data was read", () => _out !== null, () =>
              assert(!_out.lines.includes("alpha") && !_out.lines.includes("alpha.json"), "… its data directory and its store's file gone"));
        _then("alphax's store is looked at", () => true, () => assertEqual(_out.lines.includes("alphax.json"), true, "… a store of a similar id (alphax.json) untouched"));
    }
}
