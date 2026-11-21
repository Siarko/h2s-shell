import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.io

// The module updater (singletons/ModuleUpdater.qml) on stand-ins made in a private temporary
// directory (tests/fixtures/updater/setup.sh): local bare git repositories reached by file://
// (Weather and Clock follow tags, Notes its default branch, Printers 1.1.0 first asks for
// administrator rights), a stand-in `git` first on the PATH that logs every command line and
// can refuse or slow down, a fake clock for the daily run, a stand-in notifier that records
// what is sent, and a stand-in notification server. Its own module host (confirmations on,
// the launcher's own search) and installer install the modules first. Covered: a check by
// hand finding a new tag and downloading it beside the kept versions with its changelog; the
// daily run switching a queue of three by itself, one grouped restart offer and one
// notification, the one that needs consent held; a refusal remembered and not offered again,
// a newer version offered; a run while locked deferred to the unlock; an approval switching;
// the backoff after failed runs; a late answer after cancel ignored (a check, a download);
// stale restart reminders closed at start; and that nothing named a non-file address.
// Runs after ModuleInstallerTest: both change the acknowledgements and the modules turned
// off through Config.
TestCase {
    id: suite
    suiteName: "ModuleUpdater"
    asynchronous: true
    timeLimitMs: 240000

    property var after: null

    property ModuleHost host: null
    property ModuleInstaller installer: null
    property ModuleUpdater updater: null
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
        }
    }
    property Component _updaterComponent: Component {
        ModuleUpdater {
            autoCheckIntervalMs: 3600000
            checkTimeoutMs: 20000
            restartToken: "test:1"
        }
    }
    property CommandRunner runner: CommandRunner {}

    // The fake clock: a Saturday morning, moved by the suite
    property real clockMs: Date.UTC(2026, 10, 21, 9, 0, 0)
    property var written: []

    // The stand-in notifier: what is sent, and handles that record their updates
    property var sent: []
    property QtObject notifier: QtObject {
        function send(summary, options) {
            const handle = { open: true, updates: [], update(changes) { this.updates.push(changes); return true; }, close() { this.open = false; } };
            suite.sent = suite.sent.concat([{ summary: summary, options: options, handle: handle }]);
            return handle;
        }
    }

    property string temp: ""
    property var _out: null
    property var _steps: []
    property string _savedAcknowledged: ""
    property var _savedDisabled: []
    property var _savedEnabled: []
    property bool _saved: false
    property int _lsRemotes: 0
    property var _stamp: ({})

    // ---- The scheduler, as in ModuleInstallerTest: each step waits for its condition ----

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
        updater?.cancel();
        if (_saved) {
            Config.setAcknowledgedModulesText(_savedAcknowledged);
            Config.disabledModules = _savedDisabled;
            Config.enabledModules = _savedEnabled;
        }
        host?.unload();
        if (temp.startsWith("/") && temp.includes("h2s-updater.")) {
            runner.start(["rm", "-rf", "--", temp], { timeoutMs: 30000, done: () => suite.finish() });
            return;
        }
        finish();
    }

    // ---- Helpers ----

    function _sh(script, args) {
        _out = null;
        runner.start(["sh", "-c", script, "sh"].concat(args ?? []), {
            timeoutMs: 60000,
            done: result => suite._out = { ok: result.ok, lines: result.stdout === "" ? [] : result.stdout.split("\n") }
        });
    }

    // `args`: a function, read when the step runs (the temporary directory is known by then)
    function _run(description, script, args) {
        _then(description, () => true, () => _sh(script, args()));
        _then(description + ": done", () => _out !== null, () => assert(_out.ok, description));
    }

    function _data() {
        return temp + "/data/h2s-shell";
    }

    function _url(name, ref) {
        return "file://" + temp + "/repos/" + name + ".git" + (ref ? "#" + ref : "");
    }

    function _idle() {
        return !installer.busy && host.settled && !host.discovering && !updater.checking && updater._current === null
            && updater._pending.length === 0;
    }

    function _mode(mode) {
        _run("the stand-in git: " + (mode || "the real one"), "printf '%s' \"$2\" > \"$1/fake/mode\"", () => [temp, mode]);
    }

    function _publish(name, title, version, tag, extra) {
        _run("publish " + title + " " + version, "\"$1/publish\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\"", () => [temp, name, title, version, tag, extra ?? ""]);
    }

    // The record, the links and the version directories, as they are on disk
    function _disk(description, check) {
        _then(description + ": the disk is read", () => true, () => _sh(
            "D=$1/data/h2s-shell; for e in \"$D\"/modules/*; do [ -L \"$e\" ] && printf 'link\\t%s\\t%s\\n' \"${e##*/}\" \"$(readlink -- \"$e\")\"; done; "
            + "[ -d \"$D/module-versions\" ] && find \"$D/module-versions\" -mindepth 2 -maxdepth 2 -printf 'version\\t%P\\n' | sort; "
            + "n=0; [ -d \"$D/module-staging\" ] && n=$(ls -A \"$D/module-staging\" | wc -l); printf 'staging\\t%s\\n' \"$n\"; "
            + "printf 'record\\t%s\\n' \"$(tr -d '\\n' < \"$D/module-sources.json\")\"; true", [temp]));
        _then(description + ": the disk was read", () => _out !== null, () => {
            const state = { links: {}, versions: [], staging: -1, record: null };
            for (const line of _out.lines) {
                const fields = line.split("\t");
                if (fields[0] === "link")
                    state.links[fields[1]] = fields[2].split("/").pop();
                else if (fields[0] === "version")
                    state.versions.push(fields[1]);
                else if (fields[0] === "staging")
                    state.staging = Number(fields[1]);
                else if (fields[0] === "record") {
                    try {
                        state.record = JSON.parse(line.slice(7));
                    } catch (error) {
                        state.record = null;
                    }
                }
            }
            check(state);
        });
    }

    // How many ls-remote runs the stand-in logged, then `check(count)`
    function _countLsRemote(description, check) {
        _then(description + ": the git log is read", _idle, () => _sh("grep -c ' ls-remote ' \"$1/git.log\" || true", [temp]));
        _then(description + ": the git log was read", () => _out !== null, () => check(Number(_out.lines[0] ?? 0)));
    }

    function _status(id) {
        return host.status(id);
    }

    // ---- The run ----

    function runAsync() {
        _then("the config is read", () => Config.ready, () => {
            assertEqual(Profiles.value("modules.autoUpdate"), "manual", "modules.autoUpdate: by hand unless chosen");
            host = _hostComponent.createObject(suite);
            installer = _installerComponent.createObject(suite, { host: host });
            updater = _updaterComponent.createObject(suite, { host: host, installer: installer, notifier: suite.notifier,
                                                              notificationServer: null, now: () => suite.clockMs });
            updater.autoStateWritten.connect(state => suite.written = suite.written.concat([state]));
            _savedAcknowledged = Config.acknowledgedModulesText;
            _savedDisabled = host._plainList(Config.disabledModules);
            _savedEnabled = host._plainList(Config.enabledModules);
            _saved = true;
            Config.setAcknowledgedModules({});
            Config.disabledModules = [];
            Config.enabledModules = [];
            _sh("bash \"$1\"", [Quickshell.shellDir + "/tests/fixtures/updater/setup.sh"]);
        }, 120000);
        _then("the stand-ins are made", () => _out !== null, () => {
            assert(_out.ok, "the stand-ins are made (git on PATH, a temporary directory)");
            temp = _out.ok ? _out.lines[_out.lines.length - 1] : "";
            if (temp === "") {
                _steps = [];
                return;
            }
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
        _then("the host has searched", () => host.loadCount > 0 && _idle(), () => {});
        for (const each of [["wx", "v1.0.0"], ["cl", "v1.0.0"], ["nt", ""], ["pv", "v1.0.0"]]) {
            _then("install " + each[0] + ": nothing runs", _idle, () => assertEqual(installer.install(_url(each[0], each[1]), {}), "", "install " + each[0]));
            _then("install " + each[0] + ": done", () => !installer.busy, () =>
                  assert(installer.lastResult?.ok === true, each[0] + " installed (" + installer.lastResult?.message + ")"), 60000);
        }
        _then("the four modules run", () => _idle() && ["wx", "cl", "nt", "pv"].every(id => _status(id)?.state === "loaded"), () => {
            assertEqual(["wx", "cl", "nt", "pv"].map(id => _status(id).version).join(" "), "1.0.0 1.0.0 1.0.0 1.0.0", "each at 1.0.0");
            _refusals();
        });
        _checkByHand();
        _automaticRun();
        _refusal();
        _lockedRun();
        _backoff();
        _cancelled();
        _runsAfterCancelAndFailure();
        _staleReminders();
        _then("nothing runs", _idle, () => _sh("cat \"$1/git.log\"", [temp]));
        _then("the git log is read", () => _out !== null, () => {
            const lines = _out.lines.filter(line => line !== "" && !line.startsWith("answered"));
            const addresses = [].concat(...lines.map(line => line.split(" ").filter(word => /^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(word) || /^[^\/\s]+@[^\/\s]+:/.test(word))));
            assert(lines.filter(line => line.includes(" ls-remote ")).length >= 8, "the checks ran ls-remote");
            assert(addresses.length >= 8, "… with addresses (" + addresses.length + ")");
            assertEqual(addresses.filter(address => !address.startsWith("file:///")).join(" "), "", "nothing ran named a non-file address: the network is never touched");
            assert(lines.filter(line => line.includes(" ls-remote ")).every(line => line.includes("core.hooksPath=/dev/null") && line.includes("protocol.allow=never")
                                                                            && line.includes("ls-remote --symref -- file:///")),
                   "… every check without hooks, only the listed protocols, the address after \"--\"");
        });
        if (after === null || after.done)
            _clock.start();
    }

    // The modules a check named as being checked, in order
    property var _checkingIds: []
    property Connections _checkingWatch: Connections {
        target: suite.updater
        function onCheckingIdChanged() {
            if (suite.updater.checkingId !== "")
                suite._checkingIds = suite._checkingIds.concat([suite.updater.checkingId]);
        }
    }

    property Connections _afterDone: Connections {
        target: suite.after
        function onDoneChanged() {
            if (suite.after.done && suite.selected && suite._steps.length > 0 && !suite._clock.running)
                suite._clock.start();
        }
    }

    // A restart only a restart can satisfy: the host names a module whose files it cannot
    // load anew (ModuleHost.restartNeeded). A switch to a new version directory never needs
    // it with this engine, so the suite stands in for the host's finding: once Weather or
    // Clock runs at 1.1.0, the host names it
    property bool _restartStandIn: false
    property Connections _restartWatch: Connections {
        target: suite.host
        function onStatusesChanged() {
            if (!suite._restartStandIn)
                return;
            for (const id of ["wx", "cl"]) {
                const status = suite.host.status(id);
                if (status?.version === "1.1.0" && !suite.host.restartNeededIds.includes(id)) {
                    suite.host.restartNeededIds = suite.host.restartNeededIds.concat([id]);
                    suite.host.restartNeeded = suite.host.restartNeeded.concat([status.name]);
                }
            }
        }
    }

    function _refusals() {
        assertEqual(updater.update("wx"), "No update found for wx: check first", "update before a check: refused, said why");
        assert(updater.approve("pv", "x").includes("waits for no approval"), "approve with nothing waiting: refused");
        host.locked = true;
        assertEqual(updater.check("wx"), "Refused while the session is locked", "locked: no check by hand");
        assertEqual(updater.updateAll(null), "Refused while the session is locked", "… no update by hand");
        host.locked = false;
        assert(!updater.checking && updater._pending.length === 0, "… and nothing started");
    }

    function _checkByHand() {
        _then("check Weather: nothing runs", _idle, () => {
            suite._checkingIds = [];
            assertEqual(updater.check("wx"), "", "check Weather: started");
        });
        _then("check Weather: downloaded", () => _idle() && updater.checks.wx?.downloading === false && updater.changelogs.wx !== undefined, () => {
            const found = updater.checks.wx;
            assertEqual(found.outcome + " " + found.version + " " + found.ref, "available 1.1.0 v1.1.0", "a check finds the newer tag");
            assert(/^1\.1\.0-[0-9a-f]{7}$/.test(found.downloadedDir), "… and downloads it in the background (" + found.downloadedDir + ")");
            assertEqual(ModuleInstallRules.checkResultText(found), "1.1.0 available", "… the card's line");
            assertEqual(suite._checkingIds.join(",") + "|" + updater.checkingId, "wx|", "… checkingId named it while it ran, \"\" after");
            const log = updater.changelogs.wx;
            assert(log.text.includes("## 1.1.0") && !log.text.includes("## 1.0.0"), "… its changelog since the version running: " + JSON.stringify(log.text));
            assertEqual(log.from + " → " + log.to, "1.0.0 → 1.1.0", "… with the versions");
            assertEqual(_status("wx").version, "1.0.0", "… nothing switched: 1.0.0 still runs");
            assertEqual(updater.queue.rows.length, 0, "… nothing queued");
        }, 60000);
        _disk("downloaded beside", state => {
            assertEqual(state.links.wx, "1.0.0-" + state.record?.wx?.versions?.[0]?.commit?.slice(0, 7), "the link still on 1.0.0");
            assert(state.versions.some(each => /^wx\/1\.1\.0-/.test(each)), "… 1.1.0 kept beside it");
            assertEqual(state.record?.wx?.ref, "v1.0.0", "… the recorded ref unchanged");
            assertEqual(state.staging, 0, "… nothing left in staging");
        });
        _then("check Notes: nothing runs", _idle, () => assertEqual(updater.check("nt"), "", "check Notes: started"));
        _then("check Notes: done", _idle, () => {
            assertEqual(updater.checks.nt?.outcome, "current", "a branch whose head is installed: up to date");
            assertEqual(updater.update("wx", "9.9.9") + " " + updater.queue.rows.length, "The update changed 0",
                        "update of another version than the check found: refused, nothing queued");
        });
    }

    function _automaticRun() {
        _publish("nt", "Notes", "1.1.0", "no");
        _then("the daily run: nothing runs", _idle, () => {
            sent = [];
            written = [];
            _restartStandIn = true;
            updater.automatic = true;
            updater.autoStateKnown = true;
            _stamp = { at: clockMs };
        });
        _then("the daily run: the queue ended", () => _idle() && updater.queue.ended && updater.queue.rows.length === 4 && sent.length > 0, () => {
            const phases = {};
            for (const row of updater.queue.rows.slice().sort((first, second) => first.id < second.id ? -1 : 1))
                phases[row.id] = row.phase;
            assertEqual(JSON.stringify(phases), JSON.stringify({ cl: "done", nt: "done", pv: "approval", wx: "done" }),
                        "the daily run switched three by itself; the one that needs consent waits");
            assertEqual(updater.queueSummary.title + " " + updater.queueSummary.count, "Updates finished 4 of 4", "… the queue's title line");
            assertEqual(sent.length, 1, "… one notification for the whole queue");
            const note = sent[0];
            assertEqual(note.summary, "Restart needed", "… the restart merged into it");
            assert(note.options.body.includes("Modules updated: ") && note.options.body.includes("Printers: approval required.")
                   && note.options.body.includes("Restart the shell to finish updating"), "… naming the updated, the one waiting, the restart: " + note.options.body);
            assertEqual(note.options.hints["x-h2s-restart-for"], "test:1", "… the reminder names this process");
            assertEqual(note.options.format, "plain", "… plain text");
            assert(note.options.handle === true && note.options.progress === undefined && note.handle.updates.length === 0,
                   "… a plain notification with a handle, no progress bar");
            assert(updater.restartOffer !== null && updater.restartOffer.ids.slice().sort().join(",") === "cl,wx", "one restart offer, for Weather and Clock");
            assert(updater.restartOffer.text.includes("Weather") && updater.restartOffer.text.includes("Clock") && !updater.restartOffer.text.includes("Notes"),
                   "… its words: " + updater.restartOffer.text);
            assertEqual(updater.restartNeeded.slice().sort().join(","), "Clock,Weather", "restartNeeded names them");
            assertEqual(updater.approvals.pv?.reasons?.[0]?.kind, "privileged", "Printers waits: it first asks for administrator rights");
            assertEqual(_status("pv").version, "1.0.0", "… its old version keeps running");
            assertEqual(["wx", "cl", "nt"].map(id => _status(id)?.version).join(" "), "1.1.0 1.1.0 1.1.0", "the three run their new versions");
            assertEqual(written.length, 1, "the run's outcome remembered once");
            assertEqual(JSON.stringify(updater.autoState), JSON.stringify({ lastAttemptAt: _stamp.at, failures: 0, lastOutcome: "ok" }), "… ok, at the run's start");
            note.options.actions.find(action => action.id === "default").onTriggered();
            assertEqual(updater.openRequest?.show + " " + updater.openRequest?.page, "restart modules", "clicking it asks for Settings → Modules at the restart");
            _restartStandIn = false;
        }, 120000);
        _disk("switched", state => {
            assertEqual(state.links.wx.split("-")[0] + " " + state.links.cl.split("-")[0] + " " + state.links.nt.split("-")[0] + " " + state.links.pv.split("-")[0],
                        "1.1.0 1.1.0 1.1.0 1.0.0", "the links: three moved, Printers not");
            assert(state.versions.some(each => /^pv\/1\.1\.0-/.test(each)), "… Printers 1.1.0 downloaded, waiting");
            assertEqual(state.record?.pv?.active.split("-")[0], "1.0.0", "… not active");
        });
        _countLsRemote("the same day", count => {
            _lsRemotes = count;
            updater.autoTick();
        });
        _countLsRemote("the same day, asked again", count => assertEqual(count, _lsRemotes, "the run is daily: not again the same day"));
    }

    function _refusal() {
        _then("refuse Printers: nothing runs", _idle, () => {
            sent = [];
            assert(updater.refuse("pv", "1.1.0-0000000").startsWith("The update changed"), "an answer about another version: refused");
            assertEqual(updater.refuse("pv", updater.approvals.pv.dir), "", "refused, keyed to the version asked about");
        });
        _then("the refusal is remembered", _idle, () => {
            assertEqual(updater.queue.rows.find(row => row.id === "pv")?.phase, "notFinished", "the row: not finished");
            assertEqual(sent.length, 1, "the queue's end told again, once");
            assert(sent[0].options.body.includes("Printers: not finished."), "… " + sent[0].options.body);
        });
        _disk("refused", state => {
            assertEqual(state.record?.pv?.refused?.version, "1.1.0", "the record keeps the refusal");
            assertEqual(state.links.pv.split("-")[0], "1.0.0", "… 1.0.0 stays");
        });
        _then("check Printers again: nothing runs", _idle, () => assertEqual(updater.check("pv"), "", "check Printers again"));
        _then("checked Printers again", _idle, () => {
            const found = updater.checks.pv;
            assertEqual(found.outcome + " " + found.refused + " " + found.downloading, "current true false", "the refused version is not offered again, nor downloaded");
        });
        _publish("pv", "Printers", "1.2.0", "yes", "privileged");
        _then("check Printers 1.2.0: nothing runs", _idle, () => assertEqual(updater.check("pv"), "", "check Printers once more"));
        _then("checked Printers 1.2.0", () => _idle() && updater.checks.pv?.downloading === false, () =>
              assertEqual(updater.checks.pv.outcome + " " + updater.checks.pv.version, "available 1.2.0", "a newer version is offered"));
    }

    function _lockedRun() {
        _countLsRemote("before the locked day", count => {
            _lsRemotes = count;
            clockMs += ModuleUpdateRules.dayMs + 60000;
            sent = [];
            host.locked = true;
            updater.autoTick();
        });
        _countLsRemote("locked", count => {
            assertEqual(count, _lsRemotes, "a run due while locked: nothing checked");
            assertEqual(updater.autoState.lastAttemptAt, _stamp.at, "… nothing remembered: it waits");
            host.locked = false;
        });
        _then("unlocked: the run", () => _idle() && updater.autoState.lastAttemptAt === clockMs && updater.queue.ended, () => {
            assertEqual(updater.queue.rows.find(row => row.id === "pv")?.phase, "approval", "at the unlock the run goes: Printers 1.2.0 waits for approval");
            assertEqual(updater.approvals.pv?.version, "1.2.0", "… about 1.2.0");
            assert(sent.length === 1 && sent[0].options.body.includes("Printers: approval required."), "… told once");
        }, 60000);
        _countLsRemote("unlocked", count => assert(count > _lsRemotes, "… it checked"));

        // An approved update whose switch fails puts the earlier approval back
        _run("the user root made read-only", "chmod 555 \"$1/data/h2s-shell/modules\"", () => [temp]);
        _then("approve, the switch to fail", _idle, () => {
            assertEqual(host.acknowledgements.pv?.privileged, false, "before: approved without administrator rights");
            assertEqual(updater.approve("pv", updater.approvals.pv.dir), "", "approved");
        });
        _then("the switch failed", () => _idle() && updater.queue.rows.find(row => row.id === "pv")?.phase === "failed", () => {
            assertEqual(host.acknowledgements.pv?.privileged, false, "the switch failed: the earlier approval is back");
            assertEqual(_status("pv").version, "1.0.0", "… 1.0.0 still runs");
        }, 60000);
        _run("the user root writable again", "chmod 755 \"$1/data/h2s-shell/modules\"", () => [temp]);
        _then("queue Printers 1.2.0 again", _idle, () => assertEqual(updater.update("pv"), "", "queued again"));
        _then("Printers 1.2.0 waits again", () => _idle() && updater.queue.rows.find(row => row.id === "pv")?.phase === "approval", () => {
            assertEqual(updater.approvals.pv?.version, "1.2.0", "… for approval of 1.2.0");
            _stamp = { dir: updater.approvals.pv.dir, at: _stamp.at };
        });

        // While it waits, a check finds a newer version: nothing is downloaded for it, and the
        // approval switches to the version checked and judged, never another
        _publish("pv", "Printers", "1.3.0", "yes", "privileged");
        _then("check while waiting: nothing runs", _idle, () => assertEqual(updater.check("pv"), "", "check Printers while it waits"));
        _then("checked while waiting", _idle, () => {
            assertEqual(updater.checks.pv.outcome + " " + updater.checks.pv.version + " " + updater.checks.pv.downloading, "available 1.3.0 false",
                        "1.3.0 found, not downloaded while the row waits");
            assertEqual(updater.approvals.pv.dir, _stamp.dir, "… the question still about 1.2.0");
        });
        _disk("checked while waiting", state => assert(!state.versions.some(each => /^pv\/1\.3\.0-/.test(each)), "nothing of 1.3.0 on disk"));
        _then("approve Printers 1.2.0", _idle, () => assertEqual(updater.approve("pv", _stamp.dir), "", "approved"));
        _then("Printers 1.2.0 runs", () => _idle() && _status("pv")?.version === "1.2.0" && _status("pv")?.state === "loaded", () => {
            assertEqual(updater.queue.rows.find(row => row.id === "pv")?.phase, "done", "the approved update switched");
            assertEqual(host.acknowledgements.pv?.privileged, true, "… the acknowledgement now says it asks for administrator rights");
            assertEqual(host.status("pv").enabled, true, "… still on");
            // The host's finding that only a restart loads it comes after the switch was told done
            sent = [];
            host.restartNeededIds = host.restartNeededIds.concat(["pv"]);
            host.restartNeeded = host.restartNeeded.concat(["Printers"]);
        }, 60000);
        _then("a late restart finding", () => sent.length > 0, () => {
            assertEqual(sent.length + " " + sent[0].summary, "1 Restart needed", "a finding after the switch: its own restart notification");
            assert(updater.restartOffer.ids.includes("pv") && updater.restartNeeded.includes("Printers"), "… the offer and restartNeeded name it");
        });
    }

    function _backoff() {
        _mode("lsrefuse");
        _then("a failing day", _idle, () => {
            clockMs += ModuleUpdateRules.dayMs + 60000;
            _stamp = { at: clockMs };
            updater.autoTick();
        });
        _then("the failed run", () => _idle() && updater.autoState.lastAttemptAt === _stamp.at, () => {
            assertEqual(updater.autoState.failures + " " + updater.autoState.lastOutcome, "1 failed", "a run whose checks fail is remembered as failed");
            assert(updater.checks.wx.outcome === "failed" && updater.checks.wx.reason.includes("does not appear to be a git repository"),
                   "… each check says why: " + updater.checks.wx.reason);
        });
        _countLsRemote("ten minutes later", count => {
            _lsRemotes = count;
            clockMs = _stamp.at + 10 * 60000;
            updater.autoTick();
        });
        _countLsRemote("ten minutes later, asked", count => {
            assertEqual(count, _lsRemotes, "before the retry: nothing runs");
            clockMs = _stamp.at + 16 * 60000;
            updater.autoTick();
        });
        _then("the first retry", () => _idle() && updater.autoState.failures === 2, () => {
            assertEqual(updater.autoState.lastAttemptAt, _stamp.at + 16 * 60000, "the retry after 15 minutes ran, failed again");
            _stamp = { at: clockMs };
            clockMs += 20 * 60000;
            updater.autoTick();
        });
        _countLsRemote("twenty minutes after the retry", count => {
            assertEqual(updater.autoState.failures, 2, "the next waits twice as long: not after 20 minutes");
            assertEqual(updater.autoState.lastAttemptAt, _stamp.at, "… nothing ran");
        });
        _mode("");
    }

    function _cancelled() {
        _publish("cl", "Clock", "1.2.0", "yes");
        _mode("lsslow");
        _countLsRemote("before the slow check", count => _lsRemotes = count);
        _then("a slow check: nothing runs", _idle, () => {
            assertEqual(updater.check("cl"), "", "a slow check started");
            // Cancelled once its ls-remote runs (the stand-in answers 2 s later)
            _sh("for i in $(seq 1 100); do [ \"$(grep -c ' ls-remote ' \"$1/git.log\")\" -gt \"$2\" ] && exit 0; sleep 0.05; done; exit 1", [temp, String(_lsRemotes)]);
        });
        _then("the slow check runs", () => _out !== null, () => {
            assert(_out.ok, "the slow check's ls-remote started");
            updater.cancel();
            assert(!updater.checking, "cancelled: no check runs");
        });
        _then("the slow check answered", () => true, () => _sh("for i in $(seq 1 100); do grep -q '^answered ls-remote' \"$1/git.log\" && exit 0; sleep 0.1; done; exit 1", [temp]));
        _then("the slow check's answer came", () => _out !== null && _idle(), () => {
            assert(_out.ok, "the stand-in answered after the cancel");
            assert(updater.checks.cl?.version !== "1.2.0", "a check's answer after cancel is ignored (" + updater.checks.cl?.version + ")");
        });
        _mode("cloneslow");
        _then("a slow download: nothing runs", _idle, () => assertEqual(updater.check("cl"), "", "check Clock: started"));
        _then("Clock 1.2.0 downloading", () => installer.phase === "downloading", () => {
            assertEqual(updater.checks.cl?.downloading, true, "the check found 1.2.0 and downloads it");
            updater.cancel();
        });
        _then("the download stopped", _idle, () => {
            assertEqual(updater.checks.cl.downloading + " " + updater.checks.cl.downloadedDir, "false ", "cancelled: nothing downloaded, the late answer ignored");
            assert(installer.lastResult?.message.includes("cancelled"), "… the installer stopped it (" + installer.lastResult?.message + ")");
        });
        _disk("after cancel", state => {
            assert(!state.versions.some(each => /^cl\/1\.2\.0-/.test(each)), "nothing of Clock 1.2.0 moved in");
            assertEqual(state.staging, 0, "… staging emptied");
        });
        _mode("");
    }

    // A cancel during the daily run is no failure; an update that fails is not downloaded or
    // told again by the next run at the same commit
    function _runsAfterCancelAndFailure() {
        _mode("cloneslow");
        _then("a daily run to cancel", _idle, () => {
            clockMs += ModuleUpdateRules.dayMs + 60000;
            _stamp = { at: clockMs };
            updater.autoTick();
        });
        _then("its download runs", () => installer.phase === "downloading", () => updater.cancel());
        _then("the cancelled run", () => _idle() && updater.autoState.lastAttemptAt === _stamp.at, () =>
              assertEqual(updater.autoState.failures + " " + updater.autoState.lastOutcome, "0 ok", "a cancelled run counts as made, not failed"));
        _mode("clonerefuse");
        _then("a daily run that fails", _idle, () => {
            sent = [];
            clockMs += ModuleUpdateRules.dayMs + 60000;
            _stamp = { at: clockMs };
            updater.autoTick();
        });
        _then("the failing run", () => _idle() && updater.autoState.lastAttemptAt === _stamp.at && updater.queue.ended, () => {
            assertEqual(updater.autoState.failures, 1, "its downloads failed: a failed run");
            assert(sent.length === 1 && sent[0].options.body.includes("Clock: failed."), "… told once: " + sent.map(each => each.options.body).join(" / "));
        });
        _then("the clones counted", _idle, () => _sh("grep -c ' clone ' \"$1/git.log\" || true", [temp]));
        _then("the retry", () => _out !== null, () => {
            _stamp = { at: _stamp.at, clones: Number(_out.lines[0] ?? 0) };
            clockMs = _stamp.at + 16 * 60000;
            updater.autoTick();
        });
        _then("the retried run", () => _idle() && updater.autoState.lastAttemptAt === _stamp.at + 16 * 60000, () => {
            assertEqual(sent.length, 1, "the same failure is not told again");
            assertEqual(updater.autoState.failures, 0, "… the run had nothing new to try: made");
            _sh("grep -c ' clone ' \"$1/git.log\" || true", [temp]);
        });
        _then("the clones counted again", () => _out !== null, () =>
              assertEqual(Number(_out.lines[0] ?? 0), _stamp.clones, "… nor downloaded again at the same commit"));
        _mode("");
    }

    function _staleReminders() {
        _then("reminders at start", () => true, () => {
            const dismissed = [];
            const reminder = (name, hints) => ({ hints: hints, dismiss: () => dismissed.push(name) });
            const server = { notifications: { values: [reminder("old", { "x-h2s-restart-for": "old:7" }), reminder("own", { "x-h2s-restart-for": "test:1" }),
                                                       reminder("other", { urgency: 1 })] } };
            const fresh = _updaterComponent.createObject(suite, { host: host, installer: installer, notifier: suite.notifier,
                                                                  notificationServer: server, now: () => suite.clockMs });
            assertEqual(fresh.closeStaleReminders(), 1, "at start, one reminder closed");
            assertEqual(dismissed.join(","), "old", "… the one another process left; this process's own and other notifications stay");
            fresh.destroy();
        });
    }
}
