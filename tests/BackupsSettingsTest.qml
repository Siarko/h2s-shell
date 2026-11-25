import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.panels.settings
import qs.singletons

// System → Backups (BackupsSettings) on a stand-in list and modal host: read when it shows;
// each row's date, reason and version, a manual one's Kept, a newer writer's ⚠; a row opened
// shows the file, the newer line, what Apply would do and Apply… (none for an unreadable
// one); Apply asks the steps question keyed to the backup and what its preview holds, and
// only its answer applies; a refusal is said on the row; a row that went closes.
TestCase {
    id: suite
    suiteName: "BackupsSettings"
    asynchronous: true

    readonly property var _registry: [
        { migrationId: "2026-11-25-x-music-popup", scope: ["preset:music"], since: "2.2.0", summary: "x", scopeLabel: "music widget presets",
          migrate: doc => { throw new Error("broken"); } }
    ]

    function _text(writtenBy, records) {
        return JSON.stringify({ widgetPresets: JSON.stringify({ music: { Default: { a: 1 } } }), migratedKeys: records, writtenBy: writtenBy });
    }

    readonly property var _entries: [
        { name: "config.json.bak-2026-01-10T08-41-02-000Z-migration", text: _text("2.1.0", []) },
        { name: "config.json.bak-2026-01-05T21-30-00-000Z-manual", text: _text("2.2.0", ["2026-11-25-x-music-popup"]) },
        { name: "config.json.bak-2026-01-08T22-15-57-000Z-migration", text: _text("2.3.0", ["2026-11-25-x-music-popup"]) },
        { name: "config.json.bak-2025-12-01T11-47-09-000Z", text: "", readable: false }
    ]

    property QtObject backups: QtObject {
        property var rows: []
        property bool known: true
        property int refreshes: 0
        property var applied: []
        property string answer: ""
        function refresh() { refreshes++; }
        function preview(name) {
            const entry = suite._entries.find(each => each.name === name);
            return ConfigBackupRules.preview(suite._registry, entry?.text ?? "", "2.2.0");
        }
        function apply(name, held) {
            applied = applied.concat([name + ":" + held.join(",")]);
            return answer;
        }
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

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 820
        implicitHeight: 600
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    }

    property Component _pageComponent: Component {
        BackupsSettings {
            width: 800
            height: 580
            version: "2.2.0"
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

    function _rowOf(page, name) {
        return _named(page, "backupRow").find(row => row.row?.name === name) ?? null;
    }

    function _shown(item, name) {
        return _named(item, name).filter(each => each.visible);
    }

    property var _page: null

    // The page reads when it shows: once its window is on screen
    property Timer _wait: Timer {
        interval: 20
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval;
            if (suite.backups.refreshes === 0 && waited < 15000)
                return;
            stop();
            try {
                suite._cases(suite._page);
            } catch (error) {
                suite.fail("threw: " + error);
            }
            suite._page.destroy();
            suite.finish();
        }
    }

    function runAsync() {
        backups.rows = ConfigBackupRules.rows(_entries, "2.2.0", _registry);
        _page = _pageComponent.createObject(_window.contentItem, { backups: backups, modalHost: modalHost });
        _wait.start();
    }

    function _cases(page) {
        assertEqual(backups.refreshes, 1, "read when it shows");
        const rows = _named(page, "backupRow");
        assertEqual(rows.length, 4, "a row per backup");
        const older = _rowOf(page, _entries[0].name);
        const manual = _rowOf(page, _entries[1].name);
        const newer = _rowOf(page, _entries[2].name);
        const unreadable = _rowOf(page, _entries[3].name);
        assertEqual(_named(older, "backupDate")[0].text, ConfigBackupRules.date(_entries[0].name), "row: the date");
        assertEqual(_named(older, "backupReason")[0].text, "Before a settings update", "row: the reason");
        assertEqual(_named(older, "backupVersion")[0].text, "2.1.0", "row: the version");
        assert(_named(manual, "backupKept")[0].visible && !_named(older, "backupKept")[0].visible, "row: Kept on a manual one only");
        assertEqual(_named(newer, "backupVersion")[0].text, "⚠ 2.3.0", "row: a newer writer marked");
        assertEqual(_named(unreadable, "backupVersion")[0].text, "can't be read", "row: an unreadable one said");
        assertEqual(_shown(page, "backupFile").length + _shown(page, "backupApply").length, 0, "closed: no file, no Apply");

        page.select(_entries[0].name);
        assert(older.opened, "opened");
        assertEqual(_named(older, "backupFile")[0].text, _entries[0].name, "opened: the file's name");
        assertEqual(_named(older, "backupPreview")[0].text, "Apply: 1 settings update brings it up to 2.2.0. Fails for: music widget presets.",
                    "opened: what Apply would do");
        assert(!_named(older, "backupNewer")[0].visible, "opened: no newer line for an older one");
        assertEqual(_named(older, "backupApply")[0].tooltip, "Load this backup and restart the shell", "Apply: its tooltip");
        _named(older, "backupApply")[0].clicked();
        assertEqual(backups.applied.length, 0, "Apply: nothing before the answer");
        assertEqual(modalHost.spec?.title, "Apply the backup of " + ConfigBackupRules.date(_entries[0].name) + "?", "Apply: the question");
        assertEqual(modalHost.spec.body.slice(1).join("|"),
                    "Steps:|1. Create a new backup|2. Load the selected backup|3. Settings update to 2.2.0, skipping music widget presets|4. Restart the shell",
                    "Apply: the steps");
        const asked = modalHost.onAnswer;
        const subject = modalHost.spec.subject;
        page.select(_entries[1].name);
        asked({ button: "cancel", cancelled: true, subject: subject });
        assertEqual(backups.applied.length, 0, "Apply: cancelled, nothing applied");
        backups.answer = "The shell cannot restart now";
        asked({ button: "apply", cancelled: false, subject: subject });
        assertEqual(backups.applied.join(","), _entries[0].name + ":2026-11-25-x-music-popup", "Apply: the answer applies the backup asked about, with its holds");
        assertEqual(_named(manual, "backupProblem")[0].text, "The shell cannot restart now", "Apply refused: said");
        assertEqual(_named(manual, "backupPreview")[0].text, "Apply: No settings updates are needed.", "a current one: nothing to update");

        page.select(_entries[2].name);
        assert(_named(newer, "backupNewer")[0].visible, "newer: the one line");
        assertEqual(_named(newer, "backupNewer")[0].text, "⚠ Written by shell 2.3.0 (newer than current) — may be incompatible, expect odd behaviour", "newer: its words");
        assert(_named(newer, "backupApply")[0].visible, "newer: Apply available");
        _named(newer, "backupApply")[0].clicked();
        assertEqual(modalHost.spec?.title, "Load a backup from a newer shell?", "newer: its question");

        page.select(_entries[3].name);
        assertEqual(_named(unreadable, "backupPreview")[0].text, "Can't be read.", "unreadable: said");
        assert(!_named(unreadable, "backupApply")[0].visible, "unreadable: no Apply");
        modalHost.spec = null;
        assert(!page.askApply(), "unreadable: no question");

        backups.rows = ConfigBackupRules.rows(_entries.slice(0, 3), "2.2.0", _registry);
        assertEqual(page.selected, "", "a row that went: closed");
    }
}
