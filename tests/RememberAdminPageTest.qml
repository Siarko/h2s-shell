import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.singletons
import qs.singletons.io
import qs.panels.settings

// The section "Remember the password" (panels/settings/RememberAdminSection.qml) under
// clicks, and the page rules it draws (RememberViewRules): Install through a run, Install
// again when the setting grows, its Undo, Remove and its Undo, a run that fails read again, a
// rules file changed by hand with Read again, Remove's and Replace's questions keyed to the
// text shown, the countdown while something is kept (gated on the window), Forget now and a
// forget that failed, the NixOS line and Copy.
//
// Stand-ins only: what is installed is read by the suite's stand-in for RememberedAdmin from
// scratch folders (RememberRules.state on their texts), and the runs are RememberInstall's
// real root step run as the user on those folders with a stand-in systemctl (as
// tests/RememberInstallTest.qml runs it). Never pkexec, polkit, /etc, /usr or the shell's
// settings. Opens a small window for a moment in the runner's headless compositor.
TestCase {
    id: suite
    suiteName: "RememberAdminPage"
    asynchronous: true
    // Its window takes the keyboard, as other suites' do
    ownProcess: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-remember-page-test-" + Date.now()
    property int _owner: -1
    readonly property var _paths: ({ rules: _scratch + "/rules.d", conf: _scratch + "/polkit-1", backups: _scratch + "/lib/polkit-backup",
                                     systemctl: _scratch + "/bin/systemctl", owner: _owner })
    readonly property var _facts: ({ user: "alex", timeout: "/usr/bin/timeout", program: "/usr/bin/timeout" })
    property string _copied: ""
    property var _runs: []
    // How the next run ends: "" (it runs), "refuse" (the root step refuses: the file changed)
    property string _failNext: ""

    // The stand-in for RememberedAdmin: the files read from the scratch folders
    property QtObject _admin: QtObject {
        property var installed: null
        property string system: ""
        property var facts: null
        property var files: null
        property var kept: ({ known: true, reason: "", entries: [], latest: null, earliest: null })
        property var remembered: Object.freeze({ kept: false, untilMs: 0 })
        property string forgetOutcome: ""
        property string forgetReason: ""
        property real forgetAtMs: 0
        property real lastObtainedMs: 0
        property bool failForget: false
        property bool nixos: false
        property int refreshes: 0
        property int forgets: 0
        property int viewers: 0
        function refresh() {
            suite._readFiles();
        }
        function forget() {
            forgets++;
            forgetAtMs = Date.now();
            forgetReason = "forget";
            if (failForget) {
                forgetOutcome = "failed";
                return;
            }
            forgetOutcome = "forgotten";
            remembered = Object.freeze({ kept: false, untilMs: 0 });
        }
        function showCountdown() {
            viewers++;
        }
        function hideCountdown() {
            viewers--;
        }
    }

    function _readFiles() {
        if (_admin.nixos) {
            _admin.refreshes++;
            return;
        }
        const paths = [_paths.rules + "/" + RememberInstallRules.ruleName, _paths.conf + "/" + RememberInstallRules.confName];
        _exec(["sh", "-c", "for f; do if [ -e \"$f\" ]; then printf 'T%s\\n' \"$(base64 -w0 < \"$f\")\"; else echo A; fi; done", "sh"].concat(paths),
              (code, stdout) => {
            const lines = stdout.trim().split("\n");
            const text = i => (lines[i] ?? "A").startsWith("T") ? Qt.atob(lines[i].slice(1)) : undefined;
            const confs = { [RememberRules.confPath]: text(1) };
            const facts = Object.assign({ system: "arch" }, suite._facts);
            suite._admin.system = "arch";
            suite._admin.facts = suite._facts;
            suite._admin.files = { rule: text(0), confs };
            suite._admin.installed = RememberRules.state({ rule: text(0), confs }, facts);
            suite._admin.refreshes++;
        });
    }

    property var _installer: null
    property Component _installerComponent: Component {
        RememberInstall {}
    }

    // The stand-in for the shell's runs as administrator: the words run as the user
    function _start(request, done) {
        _runs = _runs.concat([request.what]);
        if (_failNext === "refuse") {
            _failNext = "";
            Qt.callLater(() => done({ ok: false, code: 3, stdout: "", stderr: "refused changed", dismissed: false, refused: false, cancelled: false, blocked: "", error: "" }));
            return;
        }
        _exec(["sh", "-c", "umask 022; exec \"$@\"", "sh"].concat(request.argv), (code, stdout, stderr) =>
            done({ ok: code === 0, code, stdout, stderr, dismissed: false, refused: false, cancelled: false, blocked: "", error: "" }));
    }

    property var _window: FloatingWindow {
        title: "h2s-tests remember page"
        visible: false
        implicitWidth: 900
        implicitHeight: 900
        color: Theme.popupBackground

        Item {
            id: area
            anchors.fill: parent

            Flickable {
                id: page
                anchors.fill: parent
                contentWidth: width
                contentHeight: _sectionHolder.implicitHeight + 40
                boundsBehavior: Flickable.StopAtBounds

                Item {
                    id: _sectionHolder
                    x: 20
                    y: 20
                    width: 840
                    implicitHeight: _section ? _section.implicitHeight : 0
                    property Item _section: null
                }
            }

            SettingsModalHost {
                id: host
                anchors.fill: parent
            }
        }

        WindowDriver {
            id: driver
            name: "RememberAdminPageDriver"
        }
    }

    property Component _sectionComponent: Component {
        RememberAdminSection {
            width: 840
            admin: suite._admin
            installer: suite._installer
            modalHost: host
            settingShown: false
            minutes: 5
            copyText: text => suite._copied = text
        }
    }

    // ── Helpers ──

    function _until(condition, limitMs = 8000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    function _find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (const child of item.children) {
            const found = _find(child, name);
            if (found)
                return found;
        }
        return null;
    }

    function _all(item, name, found = []) {
        if (!item)
            return found;
        if (item.objectName === name)
            found.push(item);
        for (const child of item.children)
            _all(child, name, found);
        return found;
    }

    function _item(name) {
        return _find(_sectionHolder, name);
    }

    function _visible(item) {
        for (let at = item; at; at = at.parent) {
            if (!at.visible)
                return false;
        }
        return item !== null;
    }

    function _shown(name) {
        return _visible(_item(name));
    }

    function _text(name) {
        const item = _item(name);
        return _visible(item) ? item.text : "(hidden)";
    }

    function _settle(item) {
        let last = "", same = 0;
        for (let waited = 0; waited < 3000 && same < 3; waited += 16) {
            const place = item.mapToItem(area, 0, 0);
            const now = place.x + "," + place.y + "," + item.width + "," + item.height;
            same = now === last ? same + 1 : 0;
            last = now;
            driver.wait(16);
        }
    }

    function _click(name) {
        const item = _item(name);
        if (!item || !_visible(item))
            return false;
        _settle(item);
        const inPage = item.mapToItem(page.contentItem, 0, 0);
        if (!host.open)
            page.contentY = Math.max(0, Math.min(inPage.y - 200, page.contentHeight - page.height));
        _settle(item);
        driver.mouseClick(item, item.width / 2, item.height / 2);
        return true;
    }

    function _modalClick(name) {
        const item = _find(host.modal, name);
        if (!item || !_visible(item))
            return false;
        _settle(item);
        driver.mouseClick(item, item.width / 2, item.height / 2);
        return true;
    }

    function _modalTitle() {
        return host.open ? (_find(host.modal, "modalTitle")?.text ?? "") : "";
    }

    function _write(path, text) {
        let done = false;
        _exec(["sh", "-c", "printf '%s' \"$2\" > \"$1\"", "sh", path, text], () => done = true);
        return _until(() => done);
    }

    function _systemctlCalls() {
        let calls = null;
        _exec(["sh", "-c", "cat \"$1/systemctl.log\" 2> /dev/null; true", "sh", _scratch], (code, stdout) => calls = stdout.trim());
        _until(() => calls !== null);
        return calls === "" ? 0 : calls.split("\n").length;
    }

    // A run clicked, its end and the files read again
    function _runAndRead(name) {
        const runs = _runs.length, reads = _admin.refreshes;
        return _click(name) && _until(() => _runs.length > runs && _admin.refreshes > reads && !_installer.busy);
    }

    // ── The run ──

    function runAsync() {
        try {
            _rules();
            _run();
        } finally {
            if (host.open)
                host.cancel("window");
            _sectionHolder._section?.destroy();
            _installer?.destroy();
            _window.visible = false;
            let removed = false;
            _exec(["rm", "-rf", "--", _scratch], () => removed = true);
            _until(() => removed);
        }
        finish();
    }

    function _rules() {
        const rules = RememberViewRules;
        assertEqual([rules.durationText(300), rules.durationText(900), rules.durationText(90), rules.durationText(30)].join(" | "),
                    "5 min | 15 min | 90 s | 30 s", "durationText: whole minutes, else seconds");
        assertEqual([rules.leftText(240000, 0), rules.leftText(61000, 0), rules.leftText(59000, 0), rules.leftText(0, 10)].join(" | "),
                    "4 min | 2 min | 59 s | 1 s", "leftText: minutes rounded up, under a minute in seconds, at least 1 s");
        const ours = { rule: "ours", conf: "none", seconds: 300, secondsSource: "", secondsReason: "default" };
        assertEqual(rules.settingHint(ours, 3, "arch").text,
                    "Shorter than the system's 5 min: the shell forgets after 3 min. That also forgets other programs' passwords in this session.",
                    "settingHint: shorter");
        assertEqual(rules.settingHint(ours, 15, "nixos").text,
                    "Longer than the system's 5 min: the system's length changes for every program. Copy the new line and switch.", "… longer, NixOS");
        assert(rules.settingHint(ours, 15, "arch").warning, "… longer: a warning");
        assertEqual(rules.settingHint(ours, 5, "arch").text, "As long as the system keeps it.", "… the same");
        assertEqual(rules.settingHint(Object.assign({}, ours, { seconds: -1 }), 5, "arch").text, "The system's length is not known.", "… not known");
        assertEqual(rules.settingHint(null, 5, "arch").text, "Used once the rule is installed.", "… nothing read: as not installed");
        assertEqual(rules.systemLine({ seconds: -1, secondsSource: "/run/polkit-1/polkitd.conf", secondsReason: "unreadable" }, "arch"),
                    "Not known: /run/polkit-1/polkitd.conf could not be read", "systemLine: a conf not read");
        assertEqual(rules.systemLine({ seconds: 600, secondsSource: RememberRules.confPath, secondsReason: "file", conf: "changed" }, "arch"),
                    "10 min — /etc/polkit-1/polkitd.conf, not written by the shell", "… a conf not the shell's");
        assertEqual(rules.systemLine({ seconds: 600, secondsSource: RememberRules.confPath, secondsReason: "file", conf: "system" }, "nixos"),
                    "10 min — /etc/polkit-1/polkitd.conf, from the NixOS module", "… NixOS");
        assertEqual(rules.ruleLine({ rule: "unknown" }).tone + " " + rules.ruleLine(null).text, "warning Reading…", "ruleLine: not known, not read");

        // The shell's conf no longer needed: Install again removes it
        const conf15 = RememberRules.confText(900);
        const withConf = { rule: RememberRules.ruleText(_facts), confs: { [RememberRules.confPath]: conf15 } };
        const oursConf = { rule: "ours", conf: "ours", seconds: 900 };
        assertEqual(rules.actions(oursConf, "arch", withConf, 5, false, null).install.label + " " + rules.actions(oursConf, "arch", withConf, 5, false, null).install.shown,
                    "Install again true", "actions: the shell's conf not needed any more: Install again");
        assert(!rules.actions(oursConf, "arch", withConf, 15, false, null).install.shown, "… needed as it is: no Install");
        assert(!rules.actions(Object.assign({}, oursConf, { conf: "changed" }), "arch", withConf, 20, false, null).install.shown,
               "… a conf not the shell's in the way: left to Replace…");
        assert(rules.actions({ rule: "changed" }, "arch", withConf, 5, false, null).remove.asks, "… Remove of a file changed by hand asks");
        const nixActions = rules.actions(ours, "nixos", withConf, 5, false, { stamp: "20261123T100000Z" });
        assert(!nixActions.install.shown && !nixActions.remove.shown && !nixActions.undo.shown, "… NixOS: no buttons");
        assert(!rules.actions(ours, "arch", withConf, 5, true, null).available, "… a run under way: none available");

        const now = 1000000;
        const forgot = { outcome: "forgotten", reason: "lock", atMs: now - 1000 };
        const known = { known: true, entries: [] };
        const nothing = Object.freeze({ kept: false, untilMs: 0 });
        assertEqual(rules.keptRow(nothing, known, forgot, now - 60000, now, "14:02").text, "Forgotten when the screen locked at 14:02.",
                    "keptRow: forgotten at lock");
        assertEqual(rules.keptRow(nothing, known, forgot, now - 500, now, "14:02").text, "Nothing remembered now.",
                    "… obtained again after the forget: the forget is old");
        assertEqual(rules.keptRow(nothing, known, forgot, 0, now, "14:02").text, "Nothing remembered now.", "… nothing ever kept: no lock line");
        assertEqual(rules.keptRow(nothing, { known: false }, null, 0, now, "").text, "Not known what is remembered now.", "… a list not known: never \"nothing\"");
        assert(rules.keptRow(nothing, { known: false }, null, 0, now, "").forgetShown, "… Forget now offered then");
        assertEqual(rules.keptRow(Object.freeze({ kept: true, untilMs: now - 1 }), known, null, 0, now, "").text, "Nothing remembered now.",
                    "… a kept time passed: not kept");

        const hand = rules.handRule(RememberRules.ruleText(_facts).replace("});", "    if (subject.isInGroup(\"wheel\"))\n        return polkit.Result.YES;\n});"), _facts);
        assertEqual(hand.lines.filter(line => line.marked).length + " " + hand.caption, "2 Two lines were added outside the shell.",
                    "handRule: the added lines marked, counted");
        assertEqual(rules.handRule(RememberRules.ruleText(_facts), _facts).caption, "Changed outside the shell.", "… none added");

        const files = { rule: "a", confs: {} };
        const shown = rules.replaceSpec({ rule: rules.currentOf("a"), conf: null }, "/b");
        assertEqual(shown.title, "Replace /usr/share/polkit-1/rules.d/40-h2s-shell.rules?", "replaceSpec: names the file");
        assert(rules.subjectHolds(shown.subject, files), "subjectHolds: the text shown");
        assert(!rules.subjectHolds(shown.subject, { rule: "b", confs: {} }), "… changed since: no");
        assert(!rules.subjectHolds({ rule: null, conf: null }, files), "… nothing shown: no");

        const lastWrite = rules.lastWriteOf("install", { ok: true, stamp: "20261123T100200Z", rule: "f".repeat(64), conf: "absent" }, { rule: undefined, confs: {} });
        assertEqual(rules.backupCaption(lastWrite, { backups: "/b" }), "Undo puts back /b/40-h2s-shell.rules.20261123T100200Z.absent",
                    "backupCaption: the changed file's backup, absent");
        assertEqual(rules.lastWriteOf("install", { ok: false, stamp: "20261123T100200Z" }, null), null, "lastWriteOf: a run that failed: nothing to undo");
    }

    function _run() {
        let ready = false;
        const systemctl = "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"" + _scratch + "/systemctl.log\"\n";
        _exec(["id", "-u"], (code, stdout) => {
            suite._owner = parseInt(stdout.trim(), 10);
            suite._exec(["sh", "-c", "set -e; umask 022; mkdir -p \"$1/rules.d\" \"$1/polkit-1\" \"$1/bin\" \"$1/lib\"; printf '%s' \"$2\" > \"$1/bin/systemctl\"; chmod 755 \"$1/bin/systemctl\"",
                         "sh", suite._scratch, systemctl], () => ready = true);
        });
        assert(_until(() => ready), "the scratch folders made");
        _installer = _installerComponent.createObject(suite, { start: suite._start, paths: suite._paths });

        _window.visible = true;
        assert(_until(() => _window.visible && host.Window.active && driver.waitShown()), "the window shows and has the keyboard");
        _sectionHolder._section = _sectionComponent.createObject(_sectionHolder, { objectName: "section" });
        const section = _sectionHolder._section;
        assert(section !== null, "the section built");
        assert(_until(() => _admin.installed !== null), "… it reads what is installed when shown");

        // --- not installed ---
        assertEqual(_text("remember:ruleLine"), "Not installed: every root run asks for the password.", "not installed");
        assertEqual(_text("remember:settingHint"), "Used once the rule is installed.", "… the setting's hint");
        assertEqual(_item("remember:install").label + " " + _shown("remember:install") + " " + _shown("remember:remove") + " " + _shown("remember:undo"),
                    "Install true false false", "… Install only");
        assertEqual(_text("remember:caption"), "Backups go to " + _paths.backups, "… where backups go");
        assertEqual(_text("remember:writtenTo"), RememberRules.rulePath, "… written to the rules file");
        assertEqual(_text("remember:systemLine"), "5 min — polkit's default (no polkitd.conf)", "… the system's length");
        assert(!_shown("remember:keptLine"), "… nothing about what is kept");

        // --- Install ---
        assert(_runAndRead("remember:install"), "Install: one run, then read again");
        assertEqual(_runs[0], RememberInstallRules.what("install"), "… the run says what it is for");
        assert(_until(() => _text("remember:ruleLine") === "Installed"), "installed");
        assertEqual(_shown("remember:install") + " " + _shown("remember:remove") + " " + _shown("remember:undo"), "false true true", "… Remove and Undo");
        assert(/^Undo puts back .*\/40-h2s-shell\.rules\.\d{8}T\d{6}Z(-\d)?\.absent$/.test(_text("remember:caption")), "… what Undo puts back: " + _text("remember:caption"));
        assertEqual(_text("remember:keptLine"), "Nothing remembered now.", "… nothing kept");
        assertEqual(_text("remember:settingHint"), "As long as the system keeps it.", "… the setting as long as the system's");
        assertEqual(_systemctlCalls(), 0, "… polkitd not told: no conf changed");

        // --- the setting grows: Install again ---
        section.minutes = 15;
        assert(_until(() => _shown("remember:install") && _item("remember:install").label === "Install again"), "15 min: Install again");
        assert(_text("remember:settingHint").startsWith("Longer than the system's 5 min"), "… the hint says so");
        assertEqual(_text("remember:writtenTo"), RememberRules.rulePath + ", " + RememberRules.confPath, "… the conf written too");
        assert(_runAndRead("remember:install"), "Install again");
        assert(_until(() => _text("remember:systemLine") === "15 min — /etc/polkit-1/polkitd.conf, written by the shell"), "the system keeps it 15 min");
        assert(!_shown("remember:install"), "… nothing more to install");
        assert(/^Undo puts back .*\/polkitd\.conf\.\S+\.absent$/.test(_text("remember:caption")), "… Undo puts back the conf only: " + _text("remember:caption"));
        assertEqual(_systemctlCalls(), 1, "… polkitd told");

        // --- Undo ---
        assert(_runAndRead("remember:undo"), "Undo");
        assert(_until(() => _text("remember:systemLine") === "5 min — polkit's default (no polkitd.conf)"), "… the conf gone again");
        assertEqual(_text("remember:ruleLine") + " " + _shown("remember:undo"), "Installed false", "… the rule stays, nothing more to undo");
        section.minutes = 5;

        // --- Remove, and its Undo ---
        assert(_runAndRead("remember:remove"), "Remove");
        assert(_until(() => _text("remember:ruleLine") === "Not installed: every root run asks for the password."), "… removed");
        assert(/^Removed\. Undo puts back .*\/40-h2s-shell\.rules\.\S+[0-9Z]$/.test(_text("remember:caption")), "… what Undo puts back: " + _text("remember:caption"));
        assert(_runAndRead("remember:undo"), "Undo of Remove");
        assert(_until(() => _text("remember:ruleLine") === "Installed"), "… installed again");

        // --- a run that fails: the files read again, its reason said ---
        _failNext = "refuse";
        assert(_runAndRead("remember:remove"), "Remove, refused by the root step");
        assertEqual(_text("remember:note"), RememberInstallRules.texts.changed, "… its reason under the buttons");
        assertEqual(_text("remember:ruleLine"), "Installed", "… still installed");

        // --- changed by hand ---
        const handText = RememberRules.ruleText(_facts).replace("});", "    if (subject.isInGroup(\"wheel\"))\n        return polkit.Result.YES;\n});");
        assert(_write(_paths.rules + "/" + RememberInstallRules.ruleName, handText), "(a wheel line added by hand)");
        assertEqual(_text("remember:ruleLine"), "Installed", "not seen before it is read");
        const reads = _admin.refreshes;
        section.admin.refresh();
        assert(_until(() => _admin.refreshes > reads && _text("remember:ruleLine") === "Changed outside the shell. Not replaced unless you choose to."),
               "read: changed outside the shell");
        assert(_until(() => _shown("remember:hand:rule")), "… the file shown");
        assertEqual(_all(_item("remember:hand:rule"), "remember:marked").length, 2, "… its two added lines marked");
        assert(_text("remember:handCaption").endsWith("Two lines were added outside the shell."), "… and counted");
        assert(!_shown("remember:install"), "… no Install: Replace… instead");
        // Remove asks first
        assert(_click("remember:remove") && _until(() => _modalTitle() === "Remove " + RememberRules.rulePath + "?"), "Remove asks first");
        assert(_modalClick("modalButton:1") && _until(() => !host.open), "… cancelled");
        // Replace…, keyed to the text shown: changed again before the answer, nothing replaced
        assert(_click("remember:replace") && _until(() => _modalTitle() === "Replace " + RememberRules.rulePath + "?"), "Replace… asks");
        assert(_write(_paths.rules + "/" + RememberInstallRules.ruleName, handText + "// more\n"), "(changed again meanwhile)");
        const before = _admin.refreshes;
        _admin.refresh();
        assert(_until(() => _admin.refreshes > before), "(read again)");
        const runs = _runs.length;
        assert(_modalClick("modalButton:0") && _until(() => !host.open), "… Replace");
        assertEqual(_runs.length + " " + _text("remember:note"), runs + " The file changed since it was shown: nothing replaced.",
                    "… the text shown is gone: nothing run");
        assert(_click("remember:readAgain"), "Read again");
        assert(_click("remember:replace") && _until(() => host.open), "Replace… again");
        const replaceReads = _admin.refreshes;
        assert(_modalClick("modalButton:0") && _until(() => _runs.length > runs && _admin.refreshes > replaceReads && !_installer.busy), "… Replace: one run");
        assert(_until(() => _text("remember:ruleLine") === "Installed"), "… the shell's rule in its place");
        assert(!_shown("remember:hand:rule"), "… the file no longer shown");

        // --- something kept: the countdown, Forget now ---
        const markBefore = _item("remember:mark").kept;
        _admin.lastObtainedMs = Date.now() - 1000;
        _admin.remembered = Object.freeze({ kept: true, untilMs: Date.now() + 240000 });
        assert(_until(() => _text("remember:keptLine") === "Remembered, 4 min left"), "kept: the time left");
        assertEqual(markBefore + " " + _item("remember:mark").kept, "false true", "… the section's mark open");
        assert(_shown("remember:forget"), "… Forget now");
        assertEqual(_admin.viewers, 1, "… the list read once a second while shown");
        _admin.remembered = Object.freeze({ kept: true, untilMs: Date.now() + 5500 });
        assert(_until(() => /^Remembered, \d s left$/.test(_text("remember:keptLine"))), "… under a minute in seconds");
        const first = _text("remember:keptLine");
        assert(_until(() => _text("remember:keptLine") !== first && _text("remember:keptLine").startsWith("Remembered,")), "… counting down: " + first + " → " + _text("remember:keptLine"));
        _window.visible = false;
        assert(_until(() => _admin.viewers === 0), "the window hidden: the countdown stops");
        _window.visible = true;
        assert(_until(() => _window.visible && driver.waitShown() && _admin.viewers === 1), "… shown again: it goes on");
        _admin.remembered = Object.freeze({ kept: true, untilMs: Date.now() + 240000 });
        assert(_click("remember:forget") && _until(() => _admin.forgets === 1), "Forget now: forgotten at once, no question");
        assert(!host.open, "… nothing asked");
        assert(_until(() => _text("remember:keptLine") === "Forgotten. The next root run asks again."), "… the row says so");
        assertEqual(_admin.viewers, 0, "… no countdown any more");
        assert(!_shown("remember:problem"), "… no problem");

        // --- a forget that failed ---
        _admin.lastObtainedMs = Date.now();
        _admin.remembered = Object.freeze({ kept: true, untilMs: Date.now() + 240000 });
        _admin.failForget = true;
        assert(_until(() => _shown("remember:forget")) && _click("remember:forget") && _until(() => _admin.forgets === 2), "Forget now, failing");
        assert(_until(() => _text("remember:problem") === "Could not forget."), "… could not forget");
        assertEqual(_text("remember:keptLine"), "Remembered, 4 min left", "… still kept");
        _admin.remembered = Object.freeze({ kept: false, untilMs: 0 });

        // --- NixOS: the line to copy ---
        _admin.nixos = true;
        _admin.system = "nixos";
        _admin.installed = { rule: "none", conf: "system", seconds: 300, secondsSource: "", secondsReason: "default" };
        assert(_until(() => _shown("remember:nixLine")), "NixOS: the configuration line");
        assertEqual(_text("remember:nixLine"), RememberRules.nixLine("alex", 5), "… built from the user and the setting");
        assertEqual(_shown("remember:install") + " " + _shown("remember:remove") + " " + _shown("remember:caption"), "false false false", "… no Install, Remove or backups");
        assertEqual(_text("remember:nixCaption"), "After nixos-rebuild switch this page shows the rule.", "… its rebuild line");
        assertEqual(_text("remember:writtenTo"), "the NixOS module (programs.h2s-shell.polkit.rememberAdmin)", "… set through the module");
        assertEqual(_text("remember:systemLine"), "5 min — polkit's default", "… polkit's default");
        assert(_click("remember:copy") && _until(() => _copied === RememberRules.nixLine("alex", 5)), "Copy");
        assertEqual(_item("remember:copy").label, "Copied", "… said");
        _admin.installed = { rule: "ours", conf: "system", seconds: 300, secondsSource: "", secondsReason: "default" };
        section.minutes = 15;
        assert(_until(() => _text("remember:nixLine") === RememberRules.nixLine("alex", 15)), "15 min: the line's minutes change");
        assertEqual(_text("remember:nixCaption"), "The line changed: copy it, then nixos-rebuild switch.", "… copy it and switch");
        assertEqual(_item("remember:copy").label, "Copy", "… to be copied again");
    }

    function _exec(command, done) {
        const process = _process.createObject(suite, { command: command });
        process.finished.connect((code, stdout, stderr) => done?.(code, stdout, stderr));
        process.running = true;
    }

    property Component _process: Component {
        Process {
            id: _run
            signal finished(int code, string stdout, string stderr)
            property bool _exited: false
            property bool _finished: false
            property bool _errorFinished: false
            property int _code: -1
            property string _stdout: ""
            property string _stderr: ""
            function _over() {
                if (!(_exited && _finished && _errorFinished))
                    return;
                _run.finished(_code, _stdout, _stderr);
                _run.destroy();
            }
            stdout: StdioCollector {
                onStreamFinished: {
                    _run._stdout = text;
                    _run._finished = true;
                    _run._over();
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    _run._stderr = text;
                    _run._errorFinished = true;
                    _run._over();
                }
            }
            onExited: code => {
                _run._code = code;
                _run._exited = true;
                _run._over();
            }
        }
    }
}
