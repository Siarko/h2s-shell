import QtQuick
import qs.singletons

// The failed settings update told and answered (MigrationNotice holds the shell's one; a
// suite one on stand-ins): once the start's migration runs are done
// (MigrationNoticeRules.notice on their reports), one critical notification without timeout,
// plain text, whose click opens Settings at the failure's entry
// (panels/settings/MigrationFailureEntry.qml); its buttons Keep defaults and Restore previous
// settings (a failed whole-config migration: Start with default settings). A successful run
// sends nothing; the test runner neither. The questions are the entry's (`asked`): the
// notification's button opens Settings and asks there. Restore (restore()) and Start with
// default settings (startWithDefaults()) write through a ConfigRestore, then restart the
// shell — only once the runs are done (a run's write would land over the restore), and only
// while the shell can restart (else config.json would be replaced under a shell that goes on
// with the old settings). A restart refused after all leaves saving held, and the entry back
// with the problem and Restart shell (retryRestart()).
QtObject {
    id: root

    // The last runs' reports, { load, afterSeed } (Config.migrationReports)
    property var reports: ({ load: null, afterSeed: null })
    // The session saves nothing (Config.saveBlocked)
    property bool saveBlocked: false
    // The test runner (Config.readOnly): nothing sent, nothing written
    property bool testRunner: false
    property string version: Version.number
    // The migrations, for the parts' words (Migrations.all())
    property var registry: []
    // config.json (Config.path)
    property string configPath: ""
    // Notifier, or a stand-in: send(summary, options) → a handle (open, close())
    property var notifier: Notifier
    // Called before config.json is replaced: what is pending is saved, nothing after
    // (Config.holdSaves)
    property var holdSaves: () => {}
    // … and saving again when nothing was replaced (Config.releaseSaves)
    property var releaseSaves: () => {}
    // Restarts the shell → whether it started (Modules.restartShell)
    property var restartShell: () => false
    // Whether the shell can restart now: not while the session is locked (Modules.canRestartShell)
    property var canRestart: () => true
    // A migration run goes on (Config.migrationBusy)
    property bool busy: false
    // Shows the Settings window (Shell.showSettings)
    property var openSettings: () => {}
    // How long after the load phase's report the notice waits for the after-seed phase's
    // before it is sent all the same (a seam: the suites shorten it)
    property int settleMs: 5000
    // Lines go to the log (the suites turn it off)
    property bool logging: true

    // A question is wanted on the entry: "restore" or "defaults"
    signal asked(string what)

    readonly property var current: MigrationNoticeRules.notice(reports, saveBlocked, version, registry)
    // What the entry shows: the failure, until Keep defaults or a restore started; a session
    // that saves nothing until it ends
    readonly property bool entryShown: _settled && current.kind !== ""
        && (restartPending || (!_acting && (current.kind === "readOnly" || _keptKey !== current.key)))
    readonly property bool canRestore: current.kind === "reset" && current.backup !== "" && !testRunner
    // Why the last restore or start with defaults did not finish ("" none)
    readonly property string problem: _problem
    // config.json was replaced but the shell did not restart: saving stays held until it does
    readonly property bool restartPending: _restartPending

    property string _keptKey: ""
    property string _sentKey: ""
    property bool _acting: false
    property bool _restartPending: false
    property string _problem: ""
    property var _handle: null
    property bool _settled: false

    readonly property bool _loadDone: reports?.load !== null && reports?.load !== undefined
    readonly property bool _afterSeedDone: reports?.afterSeed !== null && reports?.afterSeed !== undefined

    on_LoadDoneChanged: {
        if (_loadDone)
            _settle.restart();
    }
    on_AfterSeedDoneChanged: {
        if (_afterSeedDone)
            _settled = true;
    }
    on_SettledChanged: Qt.callLater(_evaluate)
    onCurrentChanged: Qt.callLater(_evaluate)
    Component.onCompleted: {
        if (_afterSeedDone)
            _settled = true;
        else if (_loadDone)
            _settle.restart();
    }

    property Timer _settle: Timer {
        interval: root.settleMs
        onTriggered: root._settled = true
    }

    function _log(line) {
        if (logging)
            console.info("[Migrations] " + line);
    }

    function _evaluate() {
        const notice = current;
        if (!_settled || testRunner)
            return;
        const wanted = notice.kind !== "" && entryShown;
        if (!wanted) {
            _withdraw();
            return;
        }
        if (_sentKey === notice.key)
            return;
        _withdraw();
        _sentKey = notice.key;
        const actions = [{ id: "default", label: "Open Settings", onTriggered: () => root.openSettings() }];
        if (notice.kind === "reset") {
            actions.push({ id: "keep", label: "Keep defaults", onTriggered: () => root.keepDefaults(notice.key) });
            if (canRestore)
                actions.push({ id: "restore", label: "Restore previous settings", onTriggered: () => root._ask("restore") });
        } else if (notice.startDefaults) {
            actions.push({ id: "defaults", label: "Start with default settings", onTriggered: () => root._ask("defaults") });
        }
        _handle = notifier.send(notice.summary, {
            body: notice.body, format: "plain", urgency: "critical", expireTime: 0, handle: true, actions: actions
        });
        _log("told the user: " + notice.summary + (notice.parts.length > 0 ? " (" + notice.parts.join(", ") + ")" : ""));
    }

    function _withdraw() {
        const handle = _handle;
        _handle = null;
        if (handle && handle.open)
            handle.close();
    }

    function _ask(what) {
        openSettings();
        // Once the window shows: a question asked on a hidden window is cancelled at once
        Qt.callLater(() => root.asked(what));
    }

    // Keep defaults: the notice and the entry go; the defaults stay. `key`: the notice it
    // answers (a newer one is not dismissed by an old answer)
    function keepDefaults(key) {
        if (current.kind !== "reset" || (typeof key === "string" && key !== "" && key !== current.key))
            return false;
        _keptKey = current.key;
        _withdraw();
        _log("defaults kept");
        return true;
    }

    // Restore previous settings (after the entry's question, or IPC): the current config
    // backed up, the backup from before the run written with the failed migrations held, the
    // shell restarted. `key`: the notice it answers ("" the current one). → "" started, else why not
    function restore(key) {
        const notice = current;
        if (typeof key === "string" && key !== "" && key !== notice.key)
            return "The failure asked about is not the current one";
        if (notice.kind !== "reset")
            return "No failed settings update to restore from";
        if (!canRestore)
            return "No backup from before the update";
        return _act(() => _restorer.restore(notice.backup, notice.held, root._written),
                    "restoring the settings from " + notice.backup + ", holding " + notice.held.join(", "));
    }

    // Start with default settings (a session that saves nothing): the current config backed
    // up, a new one with the defaults written, the shell restarted. → "" started, else why not
    function startWithDefaults(key) {
        const notice = current;
        if (typeof key === "string" && key !== "" && key !== notice.key)
            return "The failure asked about is not the current one";
        if (notice.kind !== "readOnly" || !notice.startDefaults)
            return "No failed whole-settings update";
        if (testRunner)
            return "Not under the test runner";
        return _act(() => _restorer.startWithDefaults(root.registry, root._written), "starting with default settings");
    }

    function _act(start, line) {
        if (_acting || _restorer.running || _restartPending)
            return "Already under way";
        if (!_settled || busy)
            return "The settings update is still running";
        if (!canRestart())
            return "The shell cannot restart now";
        _problem = "";
        holdSaves();
        _acting = true;
        if (!start()) {
            _acting = false;
            releaseSaves();
            return "Could not start";
        }
        _withdraw();
        _log(line);
        return "";
    }

    function _written(result) {
        if (!result.ok) {
            _acting = false;
            releaseSaves();
            _problem = result.problem;
            console.warn("[Migrations] " + result.problem + ": nothing restored");
            return;
        }
        if (result.backup !== "")
            _log("the settings replaced were backed up: " + result.backup);
        _restart();
    }

    function _restart() {
        if (restartShell()) {
            _problem = "";
            return;
        }
        // config.json holds the restored settings: saving the running ones would undo it
        _restartPending = true;
        _problem = "Restart the shell to finish. Changes are not saved until then.";
        console.warn("[Migrations] the shell could not restart itself: restart it to finish");
    }

    // Restart shell, on the entry after a restart that was refused. → "" restarted, else why not
    function retryRestart() {
        if (!_restartPending)
            return "Nothing to finish";
        if (!canRestart())
            return "The shell cannot restart now";
        _restart();
        return "";
    }

    property ConfigRestore _restorer: ConfigRestore {
        configPath: root.configPath
        readOnly: root.testRunner
        version: root.version
    }
}
