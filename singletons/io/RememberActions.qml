import QtQuick
import qs.singletons

// Install, Remove and Undo of the remembered authorization as the Settings section asks
// for them: each request built only from what `admin` read (RememberedAdmin's facts and
// texts, never anything editable) and the setting, run by `installer` (RememberInstall),
// and what the last run left — kept here, outside the page, so that a run finishing while
// the page is closed still leaves its Undo and its note. After every run, done or not, the
// files are read again. The shell's one instance is RememberedAdmin.actions; a suite makes
// its own with stand-ins.
QtObject {
    id: root

    // RememberedAdmin, or a stand-in: facts, files, refresh()
    property var admin: null
    // RememberInstall, or one with a suite's start and paths
    property QtObject installer: null

    readonly property bool busy: installer?.busy === true
    // What the last Install or Remove left for Undo (RememberViewRules.lastWriteOf), null for none
    property var lastWrite: null
    // What the last run said
    property string note: ""

    // The run under way: { mode, files (the texts it was asked with) }
    property var _pending: null

    function request(minutes, replace) {
        return {
            facts: admin?.facts ?? null, minutes: minutes, rule: admin?.files?.rule, confs: admin?.files?.confs ?? {},
            replace: RememberInstallRules.replacing(replace)
        };
    }

    // What a request would change: RememberInstall.plan's answer
    function plan(mode, minutes, replace) {
        if (!installer || !admin?.files || !admin?.facts)
            return { refusal: RememberInstallRules.refusal("unread"), rule: false, conf: false };
        return installer.plan(mode, request(minutes, replace));
    }

    // `replace` { rule, conf }: the files changed by hand the question named
    function install(minutes, replace) {
        if (busy) {
            note = RememberInstallRules.refusal("busy").text;
            return;
        }
        if (!admin?.files || !admin?.facts) {
            note = RememberInstallRules.refusal("unread").text;
            return;
        }
        const files = admin.files;
        _started("install", installer.install(request(minutes, replace)), files);
    }

    function remove(replace) {
        if (busy) {
            note = RememberInstallRules.refusal("busy").text;
            return;
        }
        if (!admin?.files || !admin?.facts) {
            note = RememberInstallRules.refusal("unread").text;
            return;
        }
        const files = admin.files;
        _started("remove", installer.remove(request(undefined, replace)), files);
    }

    function undo() {
        if (busy) {
            note = RememberInstallRules.refusal("busy").text;
            return;
        }
        if (!lastWrite)
            return;
        _started("undo", installer.undo({ stamp: lastWrite.stamp, rule: lastWrite.after.rule, conf: lastWrite.after.conf }), admin?.files ?? null);
    }

    function _started(mode, started, files) {
        if (started?.started === true) {
            note = "";
            _pending = { mode, files };
        } else {
            note = started?.refusal?.text ?? "";
        }
    }

    property Connections _finished: Connections {
        target: root.installer
        ignoreUnknownSignals: true
        function onFinished(outcome) {
            const pending = root._pending;
            if (!pending)
                return;
            root._pending = null;
            if (pending.mode === "undo") {
                if (outcome.ok)
                    root.lastWrite = null;
            } else if (outcome.ok) {
                root.lastWrite = RememberViewRules.lastWriteOf(pending.mode, outcome, pending.files);
            }
            root.note = RememberViewRules.runNote(outcome);
            // Done or not, the files are read again: a run cut short may have changed them
            root.admin?.refresh();
        }
    }
}
