import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.panels.settings
import qs.singletons

// The failed settings update's entry in Settings (MigrationFailureEntry) on a stand-in notice
// and modal host: hidden while nothing failed; the heading, "Defaults are used for:" and the
// parts as a list, all shown at once, Keep defaults and Restore previous settings…; Restore
// asks the steps question keyed to the failure, and only its answer restores; a session
// that saves nothing says so, with Start with default settings…; the notice's own `asked`
// opens the same question; a backup applied from the list whose restart was refused shows
// only the problem and Restart shell.
TestCase {
    id: suite
    suiteName: "MigrationFailureEntry"

    readonly property var _registry: [
        { migrationId: "2026-11-25-x-music-popup", scopeLabel: "music widget presets" },
        { migrationId: "2026-11-25-z-tailscale", scopeLabel: "Tailscale module settings" },
        { migrationId: "2026-11-25-w-everything", scope: ["*"], wholeScopeReason: "a test" }
    ]
    readonly property string _backup: "/c/config.json.bak-2026-01-15T10-29-03-120Z-migration"

    property QtObject notice: QtObject {
        property var reports: ({ load: null })
        property bool saveBlocked: false
        property bool testRunner: false
        readonly property var current: MigrationNoticeRules.notice(reports, saveBlocked, "2.2.0", suite._registry)
        property bool hidden: false
        readonly property bool entryShown: (current.kind !== "" || restartPending) && !hidden
        readonly property bool canRestore: current.kind === "reset" && current.backup !== ""
        property string problem: ""
        property bool restartPending: false
        property var calls: []
        function retryRestart() { calls = calls.concat(["restart"]); return ""; }
        signal asked(string what)
        function keepDefaults(key) { calls = calls.concat(["keep:" + key]); return true; }
        function restore(key) { calls = calls.concat(["restore:" + key]); return ""; }
        function startWithDefaults(key) { calls = calls.concat(["defaults:" + key]); return ""; }
    }

    property QtObject modalHost: QtObject {
        property var spec: null
        property var onAnswer: null
        function ask(spec, onAnswer) {
            this.spec = spec;
            this.onAnswer = onAnswer;
            return "";
        }
    }

    // Somewhere to be shown: an item outside a window is never visible
    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 620
        implicitHeight: 300
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    }

    property Component _entryComponent: Component {
        MigrationFailureEntry {
            width: 600
        }
    }

    function _named(item, name) {
        let found = [];
        for (const child of item.children ?? []) {
            if (child.objectName === name)
                found.push(child);
            found = found.concat(_named(child, name));
        }
        return found;
    }

    function _shown(item, name) {
        return _named(item, name).filter(each => each.visible);
    }

    function run() {
        const entry = _entryComponent.createObject(_window.contentItem, { notice: notice, modalHost: modalHost });
        try {
            _cases(entry);
        } finally {
            entry.destroy();
        }
    }

    function _cases(entry) {
        assert(!entry.visible, "nothing failed: no entry");

        notice.reports = { load: { reset: [{ id: "2026-11-25-x-music-popup", error: "x" }, { id: "2026-11-25-z-tailscale", error: "y" }], skipped: [], backup: _backup } };
        assert(entry.visible && entry.implicitHeight > 0, "failed: the entry shown");
        assertEqual(_named(entry, "migrationFailureTitle")[0].text, "Updating settings to 2.2.0 failed", "failed: the heading");
        assertEqual(_named(entry, "migrationFailureLead")[0].text, "Defaults are used for:", "failed: the lead");
        assertEqual(_named(entry, "migrationFailurePart").map(part => part.text).join("|"), "•  music widget presets|•  Tailscale module settings",
                    "failed: every part as a bullet, all shown at once");
        assert(_shown(entry, "migrationKeepDefaults").length === 1 && _shown(entry, "migrationRestore").length === 1, "failed: Keep defaults and Restore previous settings…");
        assertEqual(_named(entry, "migrationRestore")[0].label, "Restore previous settings…", "failed: the restore button asks (…)");
        assertEqual(_shown(entry, "migrationStartDefaults").length, 0, "failed: no Start with default settings");

        const key = notice.current.key;
        _named(entry, "migrationKeepDefaults")[0].clicked();
        assertEqual(notice.calls.join(","), "keep:" + key, "Keep defaults: the notice's, keyed to this failure");

        notice.calls = [];
        _named(entry, "migrationRestore")[0].clicked();
        assertEqual(notice.calls.length, 0, "Restore: nothing before the answer");
        assertEqual(modalHost.spec?.title, "Restore the settings from before the update?", "Restore: the question");
        assertEqual(modalHost.spec.body[3], "3. Settings update to 2.2.0, skipping music widget presets, Tailscale module settings", "Restore: the steps name the parts skipped");
        assertEqual(modalHost.spec.subject?.key, key, "Restore: keyed to the failure");
        modalHost.onAnswer({ button: "cancel", cancelled: true, subject: modalHost.spec.subject });
        assertEqual(notice.calls.length, 0, "Restore: cancelled, nothing restored");
        modalHost.onAnswer({ button: "restore", cancelled: false, subject: modalHost.spec.subject });
        assertEqual(notice.calls.join(","), "restore:" + key, "Restore: the answer restores the failure asked about");

        modalHost.spec = null;
        notice.asked("restore");
        assertEqual(modalHost.spec?.title, "Restore the settings from before the update?", "the notification's button: the same question on the entry");

        notice.problem = "the backup could not be read";
        assert(_shown(entry, "migrationFailureProblem").length === 1, "a restore that failed: said on the entry");
        notice.problem = "";

        notice.reports = { load: { reset: [{ id: "2026-11-25-x-music-popup", error: "x" }], skipped: [], backup: "" } };
        assertEqual(_shown(entry, "migrationRestore").length, 0, "no backup: no Restore");

        notice.restartPending = true;
        assert(_shown(entry, "migrationRestartShell").length === 1 && _shown(entry, "migrationKeepDefaults").length === 0 && _shown(entry, "migrationRestore").length === 0,
               "restart refused: only Restart shell");
        notice.calls = [];
        _named(entry, "migrationRestartShell")[0].clicked();
        assertEqual(notice.calls.join(","), "restart", "restart refused: Restart shell tries again");
        notice.restartPending = false;
        assertEqual(_shown(entry, "migrationRestartShell").length, 0, "no restart pending: no Restart shell");

        notice.calls = [];
        notice.saveBlocked = true;
        notice.reports = { load: { failure: { id: "", error: "a file could not be read" } } };
        assertEqual(_named(entry, "migrationFailureLead")[0].text, "Changes are not saved.", "saves nothing (a file): said");
        assertEqual(_shown(entry, "migrationStartDefaults").length, 0, "saves nothing (a file): no Start with default settings");
        notice.reports = { load: { failure: { id: "2026-11-25-w-everything", error: "x" } } };
        assertEqual(_named(entry, "migrationFailureLead")[0].text, "Changes are not saved.", "saves nothing: said");
        assertEqual(_named(entry, "migrationFailurePart").length, 0, "saves nothing: no parts");
        assert(_shown(entry, "migrationKeepDefaults").length === 0 && _shown(entry, "migrationStartDefaults").length === 1, "saves nothing: Start with default settings…");
        _named(entry, "migrationStartDefaults")[0].clicked();
        assertEqual(modalHost.spec?.title, "Start with default settings?", "saves nothing: its question");
        modalHost.onAnswer({ button: "defaults", cancelled: false, subject: modalHost.spec.subject });
        assertEqual(notice.calls.join(","), "defaults:" + notice.current.key, "saves nothing: the answer starts with defaults");

        notice.hidden = true;
        modalHost.spec = null;
        assert(!entry.visible && !entry.ask("defaults") && modalHost.spec === null, "answered: the entry gone, nothing asked");
        notice.hidden = false;
        notice.saveBlocked = false;
        notice.reports = { load: null };

        // A backup applied from the list, its restart refused: no failure behind it
        notice.restartPending = true;
        notice.problem = "Restart the shell to finish. Changes are not saved until then.";
        assert(entry.visible, "applied, not restarted: the entry shown");
        assert(!_named(entry, "migrationFailureTitle")[0].parent.visible && !_named(entry, "migrationFailureLead")[0].visible,
               "applied, not restarted: no failure's heading or lead");
        assert(_shown(entry, "migrationFailureProblem").length === 1 && _shown(entry, "migrationRestartShell").length === 1,
               "applied, not restarted: the problem and Restart shell");
        notice.restartPending = false;
        notice.problem = "";
    }
}
