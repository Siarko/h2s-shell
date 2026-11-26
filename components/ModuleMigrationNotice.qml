import QtQuick
import qs.singletons

// A module's failed settings update told and answered, beside the core's
// (components/MigrationFailureNotice.qml, whose entry it shares:
// panels/settings/MigrationFailureEntry.qml): once its run's report names a migration reset
// (MigrationNoticeRules.moduleNotice), one critical notification without timeout, plain text,
// naming the module, whose click opens Settings at the entry; its buttons Keep defaults and
// Restore previous settings. Restore puts back the module's backup taken before the run, with
// the failed migrations and those skipped after them held under the module's version
// (ModuleInstaller.restore: the current configuration backed up first, the module turned off
// and on again; the shell does not restart). Its outcome comes with the installer's
// `finished`: a failed restore brings the entry back with the problem. The test runner
// sends nothing.
QtObject {
    id: root

    // The module's id, its display name ("" when it is gone) and whether it is installed
    property string moduleId: ""
    property string moduleName: ""
    property bool present: false
    // Its last run's report (ModuleHost.migrationReports[moduleId])
    property var report: null
    // The test runner (Config.readOnly): nothing sent, nothing restored
    property bool testRunner: false
    // Notifier, or a stand-in: send(summary, options) → a handle (open, close())
    property var notifier: Notifier
    // ModuleInstaller, or a stand-in: restore(id, name, { held, version }) → "" started, and
    // finished(result) when a job ends ({ ok, action, message, ids })
    property var installer: null
    // Shows the Settings window (Shell.showSettings)
    property var openSettings: () => {}
    property bool logging: true

    // A question is wanted on the entry: "restore"
    signal asked(string what)

    readonly property var current: MigrationNoticeRules.moduleNotice(moduleId, moduleName, report, present)
    readonly property bool entryShown: current.kind !== "" && !_acting && _keptKey !== current.key
    readonly property bool canRestore: current.kind === "reset" && current.backup !== "" && !testRunner && installer !== null
    readonly property string problem: _problem
    // The entry's interface: a module restore never waits for a shell restart
    readonly property bool restartPending: false

    property string _keptKey: ""
    property string _sentKey: ""
    property bool _acting: false
    property string _actingKey: ""
    property string _problem: ""
    property var _handle: null

    onCurrentChanged: Qt.callLater(_evaluate)
    onEntryShownChanged: Qt.callLater(_evaluate)
    Component.onCompleted: Qt.callLater(_evaluate)

    function _log(line) {
        if (logging)
            console.info("[Migrations] " + moduleId + ": " + line);
    }

    function _evaluate() {
        const notice = current;
        if (testRunner)
            return;
        if (!(notice.kind !== "" && entryShown)) {
            _withdraw();
            return;
        }
        if (_sentKey === notice.key)
            return;
        _withdraw();
        _sentKey = notice.key;
        const actions = [{ id: "default", label: "Open Settings", onTriggered: () => root.openSettings() },
                         { id: "keep", label: "Keep defaults", onTriggered: () => root.keepDefaults(notice.key) }];
        if (canRestore)
            actions.push({ id: "restore", label: "Restore previous settings", onTriggered: () => root._ask("restore") });
        _handle = notifier.send(notice.summary, {
            body: notice.body, format: "plain", urgency: "critical", expireTime: 0, handle: true, actions: actions
        });
        _log("told the user: " + notice.summary + " (" + notice.parts.join(", ") + ")");
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

    // Keep defaults: the notice and the entry go; the defaults stay. `key`: the notice it answers
    function keepDefaults(key) {
        if (current.kind !== "reset" || (typeof key === "string" && key !== "" && key !== current.key))
            return false;
        _keptKey = current.key;
        _problem = "";
        _withdraw();
        _log("defaults kept");
        return true;
    }

    // Restore previous settings (after the entry's question). → "" started, else why not
    function restore(key) {
        const notice = current;
        if (typeof key === "string" && key !== "" && key !== notice.key)
            return "The failure asked about is not the current one";
        if (notice.kind !== "reset")
            return "No failed settings update to restore from";
        if (!canRestore)
            return "No backup from before the update";
        if (_acting)
            return "Already under way";
        const why = installer.restore(moduleId, notice.backup, { held: notice.held, version: notice.version });
        if (why !== "") {
            _problem = why;
            return why;
        }
        _problem = "";
        _acting = true;
        _actingKey = notice.key;
        _withdraw();
        _log("restoring its settings from " + notice.backup + ", holding " + notice.held.join(", "));
        return "";
    }

    // The entry's interface: nothing waits for a restart here
    function retryRestart() {
        return "Nothing to finish";
    }

    function startWithDefaults(key) {
        return "No failed whole-settings update";
    }

    property Connections _jobs: Connections {
        target: root.installer
        ignoreUnknownSignals: true
        function onFinished(result) {
            if (!root._acting || result?.action !== "restore" || !(result?.ids ?? []).includes(root.moduleId))
                return;
            root._acting = false;
            if (result.ok) {
                // Done: the run that follows (when it is on) reports afresh
                root._keptKey = root._actingKey;
            } else {
                root._problem = String(result.message ?? "Not restored");
            }
        }
    }
}
