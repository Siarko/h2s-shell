import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.distributions.arch
import qs.distributions.generic
import qs.distributions.nixos
import qs.singletons
import qs.singletons.io
import qs.panels.settings

// The sign-in rules section (panels/settings/PamRulesSection.qml) under clicks, and the page
// rules it draws (PamRuleViewRules): what is in force as steps, the split switch and its
// question, a check shown, the generated file, Apply through a trial and the writes, Undo, a
// file changed by hand and Replace, the NixOS options to copy, the lock screen's switches — each
// as the distribution integration (Arch's, NixOS's, the generic one) says the rules are made.
//
// Stand-ins only: the stacks are read by the suite from scratch folders (PamStackRules on
// their texts), the trial is a stand-in that passes for one password, and the writes are
// Arch's integration's PamApply, its real root step run as the user on the scratch folders (as tests/PamApplyTest.qml
// runs it). Never /etc, PAM, pkexec or the shell's settings. Opens a small window for a
// moment, an ordinary one that takes the keyboard, in the runner's headless compositor.
TestCase {
    id: suite
    suiteName: "PamRulesPage"
    asynchronous: true
    // Its window takes the keyboard, as other suites' do
    ownProcess: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-pam-page-test-" + Date.now()
    property int _owner: -1
    readonly property var _paths: ({ system: _scratch + "/etc/pam.d", vendor: _scratch + "/usr/lib/pam.d", backups: _scratch + "/var/lib/h2s-shell/pam-backup" })

    readonly property string _systemAuth: "auth required pam_faillock.so preauth\nauth [success=1 default=bad] pam_unix.so try_first_pass\n"
        + "auth [default=die] pam_faillock.so authfail\nauth optional pam_permit.so\naccount required pam_unix.so\n"
    readonly property string _sudo: "#%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n"
    readonly property string _handSudo: "#%PAM-1.0\nauth sufficient pam_u2f.so cue authfile=/etc/u2f_mappings\nauth\t\tinclude\t\tsystem-auth\n"
        + "account\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n"
    readonly property string _handSudo2: "#%PAM-1.0\nauth sufficient pam_u2f.so cue authfile=/etc/other\nauth\t\tinclude\t\tsystem-auth\n"
        + "account\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n"
    readonly property string _vendorPolkit: "#%PAM-1.0\n\nauth       include      system-auth\naccount    include      system-auth\n"
        + "password   include      system-auth\nsession    include      system-auth\n"
    readonly property string _password: "secret"

    property bool _nixos: false
    // Facts laid over the reading's (the machine's pam_u2f settings)
    property var _extraFacts: ({})
    // What the stand-in reading says of a security key
    property string _securityKey: "absent"
    property var _settings: ({ "lockscreen.offerFingerprint": true, "lockscreen.offerSecurityKey": true })
    property var _writes: []
    property string _copied: ""
    property var _runs: []

    // The stacks, read from the scratch folders on refresh()
    property QtObject _stacks: QtObject {
        property var reading: null
        readonly property var facts: reading?.facts ?? ({ nixos: null, fingerprint: "unknown", securityKey: "unknown" })
        readonly property var sudo: reading?.services?.sudo ?? null
        readonly property var polkit: reading?.services?.["polkit-1"] ?? null
        readonly property var faillock: reading?.faillock ?? ({})
        readonly property var directories: reading?.directories ?? []
        readonly property var files: reading?.files ?? ({})
        property int refreshes: 0
        property int methodsAsked: 0
        function refresh(withMethods) {
            refreshes++;
            if (withMethods === true)
                methodsAsked++;
            suite._read();
        }
    }

    // The trial: passes for the password, as PamTrialRules leaves a passed trial
    property QtObject _trial: QtObject {
        property var state: PamTrialRules.initialState()
        property int starts: 0
        // The next start fails at once, inside start(), as a file the rules include not read
        property bool failInStart: false
        function start(service, text) {
            starts++;
            if (failInStart) {
                state = Object.assign(PamTrialRules.initialState(), { phase: "failed", trial: state.trial + 1, service, candidate: text,
                                                                      reason: "unread", reasonText: PamTrialRules.texts.unread });
                return;
            }
            state = Object.assign(PamTrialRules.initialState(), {
                phase: "running", trial: state.trial + 1, service, candidate: text,
                messages: [{ text: "Touch the reader or type your password", error: false }],
                prompt: { text: "Password:", visible: false }
            });
        }
        function respond(trial, text) {
            if (trial !== state.trial || state.phase !== "running")
                return;
            if (text !== suite._password) {
                state = Object.assign({}, state, { phase: "failed", prompt: null, reason: "failed",
                                                   reasonText: PamTrialRules.texts.failed, pamReason: "Authentication failure" });
                return;
            }
            const directories = [suite._paths.system, suite._paths.vendor];
            const answers = {};
            answers[suite._paths.system + "/system-auth"] = { text: suite._systemAuth };
            const step = PamTrialRules.stagingStep(state.service, state.candidate, answers, directories, false);
            state = Object.assign({}, state, { phase: "passed", prompt: null, directories, answers, stack: step.stack });
        }
        function cancel(trial) {
            if (trial === state.trial)
                state = Object.assign({}, state, { phase: "cancelled", prompt: null });
        }
    }

    // The integrations the section asks: Arch's with its runs going to the stand-in under the
    // scratch base, NixOS's, the generic one; `_integration` the one in use
    property ArchIntegration _archIntegration: ArchIntegration {
        start: (request, done) => suite._start(request, done)
        base: suite._scratch
    }
    property var _integration: null
    property NixosIntegration _nixosIntegration: NixosIntegration {}
    property GenericIntegration _genericIntegration: GenericIntegration {}

    // The stand-in for the shell's runs as administrator: the words run as the user
    // How the next run ends: "" (it runs), "refuse" (the root step refuses: the file changed),
    // "refuse2" (the next but one refuses)
    property string _failNext: ""
    // The next run held until `_held` is called (a write under way)
    property bool _holdNext: false
    property var _held: null
    function _start(request, done) {
        _runs = _runs.concat([request.what]);
        if (_holdNext) {
            _holdNext = false;
            _held = () => {
                suite._held = null;
                suite._start(request, done);
                suite._runs = suite._runs.slice(0, -1);
            };
            return;
        }
        if (_failNext === "refuse2") {
            _failNext = "refuse";
        } else if (_failNext === "refuse") {
            _failNext = "";
            Qt.callLater(() => done({ ok: false, code: 3, stdout: "", stderr: "refused changed", dismissed: false, refused: false, cancelled: false, blocked: "", error: "" }));
            return;
        }
        _exec(["sh", "-c", "umask 022; exec \"$@\"", "sh"].concat(request.argv), (code, stdout, stderr) =>
            done({ ok: code === 0, code, stdout, stderr, dismissed: false, refused: false, cancelled: false, blocked: "", error: "" }));
    }

    property var _window: FloatingWindow {
        title: "h2s-tests pam rules page"
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
            name: "PamRulesPageDriver"
        }
    }

    property Component _sectionComponent: Component {
        PamRulesSection {
            width: 840
            stacks: suite._stacks
            trial: suite._trial
            integration: suite._integration
            modalHost: host
            settingValue: key => suite._settings[key]
            writeSetting: (key, value) => {
                suite._writes = suite._writes.concat([key + "=" + value]);
                suite._settings = Object.assign({}, suite._settings, { [key]: value });
            }
            copyText: text => suite._copied = text
        }
    }

    // ── Reading the scratch folders as PamStacks would ──

    property int _reads: 0
    function _read() {
        const paths = [_paths.system + "/sudo", _paths.system + "/polkit-1", _paths.system + "/system-auth", _paths.vendor + "/polkit-1"];
        _exec(["sh", "-c", "for f; do if [ -e \"$f\" ]; then printf 'T%s\\n' \"$(base64 -w0 < \"$f\")\"; else echo A; fi; done", "sh"].concat(paths),
              (code, stdout) => {
            const lines = stdout.trim().split("\n");
            const answers = {};
            paths.forEach((path, i) => {
                const line = lines[i] ?? "A";
                answers[path] = line.startsWith("T") ? { text: Qt.atob(line.slice(1)) } : { absent: true };
            });
            const directories = suite._nixos ? [suite._paths.system] : [suite._paths.system, suite._paths.vendor];
            const step = PamStackRules.readingStep({ services: ["polkit-1", "sudo"], lock: {}, directories, faillockPath: "" }, answers, true);
            suite._stacks.reading = {
                services: step.services, lock: {}, faillock: step.faillock,
                facts: Object.assign({ nixos: suite._nixos, fingerprint: "ready", securityKey: suite._securityKey }, suite._extraFacts),
                directories, files: answers
            };
            suite._reads++;
        });
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
        return _find(area.Window.window?.contentItem ?? _window.contentItem, name);
    }

    function _visible(item) {
        for (let at = item; at; at = at.parent) {
            if (!at.visible)
                return false;
        }
        return item !== null;
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

    // Scrolls the page so that `item` is in view, then clicks it at (x, its middle)
    function _clickItem(item, x) {
        if (!item || !_visible(item))
            return false;
        _settle(item);
        const inPage = item.mapToItem(page.contentItem, 0, 0);
        if (!host.open)
            page.contentY = Math.max(0, Math.min(inPage.y - 200, page.contentHeight - page.height));
        _settle(item);
        driver.mouseClick(item, x ?? item.width / 2, item.height / 2);
        return true;
    }

    function _click(name, x) {
        return _clickItem(_item(name), x);
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

    function _type(text) {
        for (const character of text) {
            const code = character.toUpperCase().charCodeAt(0);
            driver.keyClick(code >= 65 && code <= 90 ? Qt.Key_A + code - 65 : code);
        }
    }

    function _steps(title) {
        const row = _item("summary:" + title);
        if (!row)
            return "(none)";
        return _all(row, "step:fingerprint").concat(_all(row, "step:password"), _all(row, "step:securityKey"))
            .sort((first, second) => first.mapToItem(row, 0, 0).x - second.mapToItem(row, 0, 0).x)
            .map(step => step.method).join(">");
    }

    function _texts(name) {
        return _all(_item("section") ?? _sectionHolder, name).filter(item => _visible(item)).map(item => item.text);
    }

    property var _fileText: ({})
    function _readFile(path) {
        _fileText = Object.assign({}, _fileText, { [path]: undefined });
        _exec(["sh", "-c", "if [ -e \"$1\" ]; then cat \"$1\"; else printf '(none)'; fi", "sh", path],
              (code, stdout) => suite._fileText = Object.assign({}, suite._fileText, { [path]: stdout }));
        _until(() => _fileText[path] !== undefined);
        return _fileText[path];
    }

    function _write(path, text) {
        let done = false;
        _exec(["sh", "-c", "printf '%s' \"$2\" > \"$1\"", "sh", path, text], () => done = true);
        return _until(() => done);
    }

    function _reread() {
        const before = _reads;
        _stacks.refresh(false);
        return _until(() => _reads > before);
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
            _window.visible = false;
            let removed = false;
            _exec(["rm", "-rf", "--", _scratch], () => removed = true);
            _until(() => removed);
        }
        finish();
    }

    function _rules() {
        const rules = PamRuleViewRules;
        const stack = lines => ({ known: true, lines: lines.map(name => ({ moduleName: name })) });
        assertEqual(rules.stepsOf(stack(["pam_fprintd.so", "pam_faillock.so", "pam_unix.so", "pam_faillock.so", "pam_permit.so"])).join(">"),
                    "fingerprint>password", "stepsOf: the methods asked, in order; other modules no step");
        assertEqual(rules.stepsOf(stack(["pam_unix.so", "pam_unix.so", "pam_u2f.so"])).join(">"), "password>securityKey", "… twice in a row once");
        assertEqual(rules.stepsOf({ known: false, lines: [] }) + " " + rules.stepsOf(null), "null null", "… a stack not known: null");
        const one = rules.summaryRows(stack(["pam_unix.so"]), stack(["pam_unix.so"]));
        assertEqual(one.map(row => row.title + ":" + row.steps.join(">")).join(" | "), "sudo and administrator prompts:password", "summaryRows: the same: one row");
        const two = rules.summaryRows(stack(["pam_fprintd.so", "pam_unix.so"]), { known: false });
        assertEqual(two.map(row => row.title + ":" + (row.steps === null ? "not known" : row.steps.join(">"))).join(" | "),
                    "sudo:fingerprint>password | Administrator prompts:not known", "… different or not known: two rows");
        assertEqual(rules.computerHas({ fingerprint: "ready", securityKey: "absent" }), "a finger enrolled · no security key registered", "computerHas");
        assertEqual(rules.computerHas({}), "fingerprint not known · security key not known", "… not known");
        const said = (integration, directory) => {
            const texts = rules.modeTexts(integration.capability("pam.rules"), integration.details("pam.rules").texts, directory);
            return [texts.label, texts.where, texts.pending, texts.copyTitle, texts.after, texts.reason].join(" | ");
        };
        assertEqual(said(_nixosIntegration, "/etc/pam.d"), "Set through | the NixOS module | The rows below take effect after nixos-rebuild switch. | "
                    + "Add to your NixOS configuration | After nixos-rebuild switch this page shows the new rules. | ", "modeTexts: NixOS's integration's words");
        assertEqual(said(_archIntegration, "/etc/pam.d"), "Written to | /etc/pam.d/sudo and /etc/pam.d/polkit-1 | The rows below are not in force until Apply. |  |  | ",
                    "… Arch: the files, Apply");
        assertEqual(said(_genericIntegration, "/etc/pam.d"), " |  |  |  |  | " + IntegrationRules.unsupported, "… elsewhere: why not");
        assertEqual(rules.modeTexts(IntegrationRules.unknownCapability(), {}, "").reason, IntegrationRules.unknown, "… while the system is not known: so");
        assertEqual(rules.modeTexts(_archIntegration.capability("pam.rules"), {}, "/x").where + " | " + rules.modeTexts(_archIntegration.capability("pam.rules"), {}, "").where,
                    "/x/sudo and /x/polkit-1 | /etc/pam.d/sudo and /etc/pam.d/polkit-1", "… the folder read, else /etc/pam.d");
        const given = rules.serviceFacts({ writes: true, bareModules: "libpam", texts: { systemRow: "r" } }, "sudo", null, null, [], undefined, false);
        assertEqual(JSON.stringify([given.writes, given.bareModules, given.texts]), JSON.stringify([true, "libpam", { systemRow: "r" }]),
                    "serviceFacts: the integration's writes, bare modules and words");
        const plain = rules.serviceFacts({ writes: 1, bareModules: 2, texts: null }, "sudo", null, null, [], undefined, false);
        assertEqual(JSON.stringify([plain.writes, plain.bareModules, plain.texts]), JSON.stringify([false, "", {}]), "… none given (or not of their kind): none");
        assertEqual(JSON.stringify(rules.serviceFacts({ texts: "x" }, "sudo", null, null, [], undefined, false).texts), "{}", "… words that are no object: none");

        const files = rules.filesOf({ "/e/sudo": { text: "s" }, "/e/polkit-1": { absent: true }, "/v/polkit-1": { unreadable: true } }, ["/e", "/v"]);
        assertEqual(JSON.stringify([files.sudo, files.polkit, files.vendorPolkit]), JSON.stringify(["s", null, undefined]), "filesOf: a text, none there, not read");
        assertEqual(rules.inForceOf(undefined, "sudo", "v", { writes: true }).known, false, "inForceOf: a file not read is not known");
        assertEqual(rules.inForceOf(null, "polkit-1", undefined, { writes: true }).known, false, "… polkit's own file not read: not known");
        assertEqual(rules.inForceOf(null, "polkit-1", _vendorPolkit, { writes: true }).rows.map(row => row.id).join(","), "system", "… no polkit-1 of ours: the fixed row");
        assert(rules.inForceOf(_handSudo, "sudo", _vendorPolkit, { writes: true }).changed, "… a hand-made line: changed by hand");
        assertEqual(rules.inForceOf(_handSudo, "sudo", undefined, { writes: false }).changed, false, "… where the shell writes no file: never changed by hand");
        assertEqual(JSON.stringify(rules.inForceOf(_handSudo, "sudo", undefined, { writes: false })),
                    JSON.stringify({ known: true, changed: false, reasons: [], rows: [PamRuleRules.fixedRow()], adopted: null, vendorChanged: false }),
                    "… known: the fixed row alone, polkit's own file not changed");

        const fixed = PamRuleRules.fixedRow();
        const finger = { id: "r1", method: "fingerprint", control: "sufficient", details: { timeout: 10, tries: 3 } };
        const editor = rules.editorFrom([finger, fixed], [fixed]);
        assertEqual(editor.split, true, "editorFrom: different lists: split");
        assertEqual(rules.editorFrom([fixed], null).split, false, "… a list not known: the fixed row, one list");
        assert(rules.pending({ split: false, shared: [finger, fixed] }, [fixed], [fixed]), "pending: rows that differ");
        assert(!rules.pending({ split: false, shared: [fixed] }, [fixed], [fixed]), "… the same: none");
        const off = rules.splitToggled(editor);
        assertEqual(off.ask + " " + off.editor.split + " " + off.editor.shared.length, "true false 2", "splitToggled: off with different lists asks, sudo's serve both");
        const on = rules.splitToggled({ split: false, shared: [finger, fixed] });
        assertEqual(on.ask + " " + on.editor.sudo.length + " " + on.editor.polkit.length, "false 2 2", "… on: both start as the shared list");
        assertEqual(rules.splitToggled({ split: true, sudo: [fixed], polkit: [fixed] }).ask, false, "… off with the same lists: no question");

        const facts = service => ({ writes: true, service, fingerprint: "ready", securityKey: "absent", faillockPresent: true,
                                    otherService: [finger, fixed], vendorText: _vendorPolkit });
        const queue = rules.applyQueue({ "sudo": { rows: [finger, fixed], currentText: _sudo, facts: facts("sudo") },
                                         "polkit-1": { rows: [finger, fixed], currentText: null, facts: facts("polkit-1") } });
        assertEqual(queue.items.map(item => item.service).join(",") + " " + queue.refusals.length, "sudo,polkit-1 0", "applyQueue: both, sudo first");
        assert(queue.items[0].text.indexOf("pam_fprintd.so") > 0, "… the candidate's text");
        const same = rules.applyQueue({ "sudo": { rows: [fixed], currentText: _sudo, facts: facts("sudo") },
                                        "polkit-1": { rows: [fixed], currentText: null, facts: facts("polkit-1") } });
        assertEqual(same.items.length, 0, "… nothing that differs: nothing");
        const refused = rules.applyQueue({ "sudo": { rows: [Object.assign({}, finger, { control: "bogus" }), fixed], currentText: _sudo, facts: facts("sudo") } });
        assertEqual(refused.items.length + " " + refused.refusals[0].service, "0 sudo", "… a refused build: its refusal, nothing written");
        const risky = rules.applyQueue({ "sudo": { rows: [finger], currentText: _sudo, facts: Object.assign(facts("sudo"), { otherService: [finger] }) },
                                         "polkit-1": { rows: [finger, fixed], currentText: null, facts: facts("polkit-1") } });
        assertEqual(risky.items.map(item => item.service).join(",") + " " + risky.refusals.length + " " + risky.risks.map(item => item.service + ":" + item.code).join(","),
                    "sudo,polkit-1 0 sudo:R5", "… a risk: written, the risk with its service");
        assertEqual(rules.applyQueue({ "sudo": { rows: [finger], currentText: _sudo, facts: Object.assign(facts("sudo"), { otherService: [finger] }) } })
                        .risks.length, 1, "… (a risk alone)");
        assertEqual(rules.applyQueue({ "sudo": { rows: [fixed], currentText: _sudo, facts: Object.assign(facts("sudo"), { otherService: [finger] }) },
                                       "polkit-1": { rows: [finger], currentText: null, facts: Object.assign(facts("polkit-1"), { otherService: [finger] }) } })
                        .risks.map(item => item.service + ":" + item.code).join(","), "polkit-1:R5", "… only the risks of a service written");

        // --- the risk question ---
        assertEqual(rules.riskQuestion([], {}), null, "riskQuestion: no risk, no question");
        const heading = kind => PamRuleRules.riskHeadings[kind];
        let question = rules.riskQuestion([{ service: "sudo", code: "R9", row: 0, text: "x" }, { service: "polkit-1", code: "R9", row: 0, text: "x" }], { files: "k" });
        assertEqual(JSON.stringify([question.kind, question.title, question.body, question.buttons, question.subject]),
                    JSON.stringify(["danger", "Save anyway?", [heading("unsafe") + ": a line lets anyone in without a password."],
                                    [{ id: "save", label: "Save anyway", kind: "delete" }], { files: "k" }]),
                    "… a line that lets anyone in, in both: named once, no lockout line, keyed to the files");
        const reasons = { R1: "no row can let you in", R2: "a row must pass, but its reader is not ready", R3: "there are no rows" };
        for (const code of ["R1", "R2", "R3"]) {
            question = rules.riskQuestion([{ service: "sudo", code, row: -1, text: "x" }]);
            assertEqual(JSON.stringify(question.body), JSON.stringify([heading("lockout") + ": " + reasons[code] + " (sudo).", { text: rules.lockoutText, strong: true }]),
                        "… " + code + " in sudo only: the service after the reason, then the lockout");
        }
        question = rules.riskQuestion([{ service: "sudo", code: "R5", row: -1, text: "x" }]);
        assertEqual(JSON.stringify(question.body), JSON.stringify([heading("loss") + ": neither sudo nor administrator prompts keep a password, so if the reader breaks, both are closed.",
                                                                   { text: rules.lockoutText, strong: true }]), "… R5: about both, no service named; the lockout line");
        question = rules.riskQuestion([{ service: "polkit-1", code: "R1", row: 2, text: "x" }, { service: "polkit-1", code: "R1", row: -1, text: "y" }]);
        assertEqual(JSON.stringify(question.body.slice(0, 2)), JSON.stringify([heading("lockout") + ": a line refuses everyone (administrator prompts).",
                                                                               heading("lockout") + ": no row can let you in (administrator prompts)."]),
                    "… a line refusing everyone and no way in: two lines, administrator prompts named");
        question = rules.riskQuestion([{ service: "sudo", code: "R1", row: 0, text: "x" }]);
        assertEqual(question.body[0], heading("lockout") + ": a line refuses everyone (sudo).", "… the first row refusing everyone: a line, not the list");
        question = rules.riskQuestion([{ service: "sudo", code: "R7x", row: -1, text: "Something else." }]);
        assertEqual(question.body.join(" "), "Something else.", "… a risk without its own words: the check's text");
        assert(rules.queueKey(risky) !== rules.queueKey(Object.assign({}, risky, { risks: risky.risks.concat([{ service: "sudo", code: "R2", row: 0 }]) })),
               "queueKey: a risk more is another answer");
        assert(rules.queueKey(risky) !== rules.queueKey(Object.assign({}, risky, { items: risky.items.slice(1) })), "… other files too");
        assertEqual(rules.queueKey(risky), rules.queueKey(JSON.parse(JSON.stringify(risky))), "… the same queue, the same key");
        assertEqual(rules.rowState({ refusals: [], risks: [{ id: "r1" }], warnings: [{ id: "r1" }] }, "r1"), "risky", "rowState: a risk over a warning");
        assertEqual(rules.rowState({ refusals: [{ id: "r1" }], risks: [{ id: "r1" }], warnings: [] }, "r1"), "refused", "… a refusal over a risk");

        const directories = ["/s", "/v"];
        const answers = { "/s/system-auth": { text: _systemAuth } };
        const sudoText = queue.items[0].text;
        const passed = { phase: "passed", service: "sudo", candidate: sudoText, directories, answers,
                         stack: PamTrialRules.stagingStep("sudo", sudoText, answers, directories, false).stack };
        assert(rules.trialCovers(passed, "sudo", sudoText), "trialCovers: its own candidate");
        assert(!rules.trialCovers(passed, "sudo", sudoText + "\n# x"), "… another text: no");
        assert(rules.trialCovers(passed, "polkit-1", queue.items[1].text), "… the other service with the same auth lines");
        assert(!rules.trialCovers(Object.assign({}, passed, { phase: "failed" }), "sudo", sudoText), "… a trial that did not pass: no");
        assertEqual(rules.progress(0, 2, "sudo") + " | " + rules.progress(1, 2, "polkit-1") + " | " + rules.progress(0, 1, "polkit-1"),
                    "1 of 2: sudo | 2 of 2: administrator prompts | administrator prompts", "progress");

        const preview = rules.previewLines(sudoText);
        assertEqual(preview.filter(line => line.kind === "marker").length, 2, "previewLines: the block's two markers");
        assert(preview.some(line => line.kind === "ours" && line.text.indexOf("pam_fprintd") >= 0), "… our line");
        assert(preview.some(line => line.kind === "system" && line.text.indexOf("system-auth") >= 0), "… the system's lines");
        const counted = rules.previewLines("# BEGIN h2s-shell x\nauth required pam_faillock.so preauth\nauth [success=done default=ignore] pam_unix.so try_first_pass\n# END h2s-shell");
        assertEqual(counted.map(line => line.kind).join(","), "marker,counted,counted,marker", "… the counted lines");
        const hand = rules.handLines(_handSudo, [{ line: 2, text: "A security key line outside the shell's block." }]);
        assertEqual(hand.map(line => line.marked ? "x" : "-").join(""), "-x---", "handLines: the reason's line marked");
        assertEqual(JSON.stringify(rules.applyButton(true, false, false, false)), JSON.stringify({ available: true, tooltip: "Tries the new rules first, then asks the administrator password" }),
                    "applyButton: changes, no refusal");
        assertEqual([rules.applyButton(false, false, false, false).available, rules.applyButton(true, true, false, false).available,
                     rules.applyButton(true, false, true, false).available, rules.applyButton(false, false, false, true).available].join(" "),
                    "false false false true", "… nothing changed, refused, busy: off; a Replace counts as a change");
        const unlock = rules.unlockRows({ fingerprint: "ready", securityKey: "absent" }, { "lockscreen.offerFingerprint": false });
        assertEqual(unlock.map(row => row.method + ":" + row.checked + ":" + row.available).join(" "),
                    "password:true:false fingerprint:false:true securityKey:false:false", "unlockRows: the password always, a missing key off");
        assertEqual(unlock[2].hint, "No key registered — it needs pam_u2f and a registered key. From this system's packages: pam_u2f, for security keys.",
                    "… with its reason and what it needs: the system not known, the neutral hint");
        const arch = { label: "Arch Linux", packages: { fprintd: { package: "fprintd" }, pamU2f: { package: "pam-u2f" } } };
        const none = { fingerprint: "absent", securityKey: "absent" };
        assertEqual(rules.unlockRows(none, {}, arch).slice(1).map(row => row.hint).join(" | "),
                    "No finger enrolled — it needs fprintd and an enrolled finger. On Arch Linux: the package fprintd. | "
                    + "No key registered — it needs pam_u2f and a registered key. On Arch Linux: the package pam-u2f.",
                    "… on Arch: the package names");
        const nixos = { label: "NixOS", packages: { fprintd: { option: "services.fprintd.enable" }, pamU2f: { option: "security.pam.u2f.enable" } } };
        assertEqual(rules.unlockRows(none, {}, nixos).slice(1).map(row => row.hint).join(" | "),
                    "No finger enrolled — it needs fprintd and an enrolled finger. On NixOS: the option services.fprintd.enable. | "
                    + "No key registered — it needs pam_u2f and a registered key. On NixOS: the option security.pam.u2f.enable.",
                    "… on NixOS: the options");
        assertEqual(rules.unlockRows({ fingerprint: "ready", securityKey: "unknown" }, {}, arch).slice(1).map(row => row.hint).join(" | "),
                    "A finger is enrolled | Not known on this computer", "… there, or not known: no package named");
        const u2fRead = { rows: { known: true, alwaysok: true, nouserok: false, touchOff: false }, conf: null, lock: null };
        const sudoFacts = rules.serviceFacts({ writes: false, fingerprint: "ready", securityKey: "ready", u2f: u2fRead }, "sudo", null, null, [], undefined, false);
        assertEqual(sudoFacts.u2f, u2fRead, "serviceFacts: the system's pam_u2f settings handed to the checks");
        assert(PamRuleRules.codes(PamRuleRules.check([{ id: "r1", method: "securityKey", control: "sufficient", details: { pin: false, cue: true } }, PamRuleRules.fixedRow()], sudoFacts)).includes("W15"),
               "… so an own key row with the system's alwaysok is warned about");
        assertEqual(unlock[2].warning + "|" + unlock[1].warning, "|", "… no warning without a key");
        const lockWith = more => ({ securityKey: "ready", u2f: { lock: Object.assign({ known: true, alwaysok: false, nouserok: false, touchOff: false }, more) } });
        const keyWarning = facts => rules.unlockRows(facts, {})[2].warning;
        assertEqual(keyWarning(lockWith({ alwaysok: true })), "Unlocks without a key: the system's pam_u2f settings have alwaysok.", "unlockRows: alwaysok said");
        assertEqual(keyWarning(lockWith({ touchOff: true })),
                    "May unlock without a touch while a key is plugged in: the system's pam_u2f settings have userpresence=0.", "… the touch turned off said");
        assertEqual(keyWarning(lockWith({ interactive: true })),
                    "The key will not work here: the system's pam_u2f settings have interactive, and the lock screen cannot answer its Enter prompt.",
                    "… interactive left in (pam_u2f.conf, which no argument turns off): the key will not work");
        assertEqual(keyWarning(lockWith({ interactiveDropped: true })), "interactive is off for the lock screen: it cannot answer the Enter prompt.",
                    "… interactive left out by the module: said");
        assertEqual(keyWarning(lockWith({ alwaysok: true, interactiveDropped: true })),
                    "Unlocks without a key: the system's pam_u2f settings have alwaysok. interactive is off for the lock screen: it cannot answer the Enter prompt.",
                    "… every point at once");
        assertEqual(keyWarning(lockWith({ known: false })),
                    "The system's pam_u2f settings could not be read: it may unlock without a key or a touch.", "… settings not read said");
        assertEqual(keyWarning(lockWith({ nouserok: true })) + "|" + keyWarning(lockWith({})) + "|" + keyWarning({ securityKey: "ready" }), "||",
                    "… nouserok (the one line must pass), clean settings, nothing read yet: none");
        assertEqual(rules.unlockRows({ securityKey: "absent", u2f: lockWith({ alwaysok: true }).u2f }, {})[2].warning, "", "… no key registered: none");
        assertEqual(rules.savedSpec([{ service: "sudo", backup: "sudo.1" }, { service: "polkit-1", backup: "polkit-1.1" }], "/b").body[1],
                    "Backups: /b/sudo.1, /b/polkit-1.1", "savedSpec: the backups named");
        const ok = service => ({ ok: true, service, backup: service + ".1" });
        assertEqual(rules.stoppedSpec([], "", "sudo", "", "/b").spec, null, "stoppedSpec: a prompt dismissed, nothing written: nothing said");
        assertEqual(rules.stoppedSpec([], "Bad\nthing", "sudo", "unchanged", "/b").spec.body.join(" | "), "Bad thing | Nothing was changed.",
                    "… a reason, nothing written: not saved, the reason on one line");
        const half = rules.stoppedSpec([ok("sudo")], "The file changed since it was read: read it again.", "polkit-1", "unchanged", "/b");
        assertEqual(half.spec.title + " | " + half.spec.body.join(" | ") + " | " + half.changed,
                    "Saved in part | The file changed since it was read: read it again. | Written: sudo. Not written: administrator prompts. | Undo puts back /b/sudo.1. | true",
                    "… one written: saved in part, what Undo puts back");
        assertEqual(rules.stoppedSpec([ok("sudo")], "", "polkit-1", "", "/b").spec.body[0], "The administrator password was not given.", "… the second prompt dismissed");
        assertEqual(rules.stoppedSpec([], "x", "sudo", "done", "/b").spec.body[1], "sudo: the file was written, but the run did not say so. Read it again.", "… a run that did not say: written");
        assertEqual(rules.stoppedSpec([], "x", "sudo", "other", "/b").spec.body[1], "sudo: the file changed in another way. Read it again.", "… another change");
        assertEqual(rules.stoppedSpec([], "x", "polkit-1", "unknown", "/b").spec.body[1], "administrator prompts: the file could not be read again.", "… not read");
        const undoFailed = rules.undoFailedSpec("refused", [ok("sudo")]);
        assertEqual(undoFailed.title + " | " + undoFailed.body.join(" | ") + " | " + undoFailed.buttons[0].id, "Not undone | refused | Still with the new rules: sudo. | again",
                    "undoFailedSpec: what is left, Try again");
        assertEqual(rules.replaceSpec("sudo", "/b", { own: 1, raw: 0, hash: "abc" }).subject.hash, "abc", "replaceSpec: keyed to the text shown");
        assertEqual(rules.replaceSpec("sudo", "/b", { own: 1, raw: 1 }).body[1],
                    "Taken in as 2 rows; 1 line the editor does not make itself stays a raw line, as written.", "replaceSpec: what is taken in");
    }

    function _run() {
        let ready = false;
        _exec(["id", "-u"], (code, stdout) => {
            suite._owner = parseInt(stdout.trim(), 10);
            suite._exec(["sh", "-c", "set -e; umask 022; mkdir -p \"$1/etc/pam.d\" \"$1/usr/lib/pam.d\"; printf '%s' \"$2\" > \"$1/etc/pam.d/sudo\"; printf '%s' \"$3\" > \"$1/etc/pam.d/system-auth\"; "
                         + "printf '%s' \"$4\" > \"$1/usr/lib/pam.d/polkit-1\"", "sh", suite._scratch, suite._sudo, suite._systemAuth, suite._vendorPolkit], () => ready = true);
        });
        assert(_until(() => ready), "the scratch folders made");
        _integration = _archIntegration;
        assert(_reread(), "the stacks read");

        _window.visible = true;
        assert(_until(() => _window.visible && host.Window.active && driver.waitShown()), "the window shows and has the keyboard");
        _sectionHolder._section = _sectionComponent.createObject(_sectionHolder, { objectName: "section" });
        const section = _sectionHolder._section;
        assert(section !== null, "the section built");
        assert(_until(() => section.editor !== null), "… its editor from what is in force");
        assert(_stacks.methodsAsked === 1, "… it reads the stacks when shown, with what the computer has");

        // --- the summary ---
        assert(_until(() => _steps("sudo and administrator prompts") === "password"), "in force: one row for both, the password");
        assert(_texts("pendingLine").length === 0, "… nothing pending");

        // --- a check: the fixed row removed ---
        assert(_click("remove:system"), "the fixed row's × clicked");
        assert(_until(() => _modalTitle() === "Remove the system's password?") && _modalClick("modalButton:0"), "… removed");
        assert(_until(() => _texts("refusal").length > 0), "a risk shown in red under the list");
        assert(_texts("refusal").some(text => text === PamRuleRules.riskText("R3")), "… no rows");
        assert(_item("apply").available, "… Apply stays on: a risk is asked about, not refused");

        // --- Apply with a risk: the question first, cancel writes nothing, the trial after it ---
        const startsRisk = _trial.starts;
        assert(_click("apply"), "Apply with no rows");
        assert(_until(() => _modalTitle() === "Save anyway?"), "… the risk question first");
        const riskLines = _all(host.modal, "modalLine").map(line => line.text);
        assert(riskLines.includes(PamRuleRules.riskText("R3")) && riskLines.includes(PamRuleViewRules.lockoutText),
               "… it names the risk, and that sudo may become unreachable: " + riskLines.join(" | "));
        assert(_modalClick("modalButton:1") && _until(() => !host.open), "… cancelled");
        assertEqual(_trial.starts + " " + _runs.length + " " + section._busy, startsRisk + " 0 false", "… nothing tried, nothing written");
        // The rows change while it is asked: the answer no longer stands for them
        assert(_click("apply") && _until(() => _modalTitle() === "Save anyway?"), "Apply again: asked again");
        section._setRows("shared", [{ id: "r9", method: "raw", control: "", details: { text: "auth sufficient pam_permit.so" } }]);
        assert(_modalClick("modalButton:0") && _until(() => !host.open), "… Save anyway, for rows no longer there");
        assertEqual(_trial.starts + " " + _runs.length + " " + section._busy, startsRisk + " 0 false", "… nothing tried, nothing written");
        assertEqual(section.notice, "Not saved: the rules changed while the question was open.", "… said under the buttons");
        section._setRows("shared", []);
        // Busy by the time the answer comes: nothing starts
        assert(_click("apply") && _until(() => _modalTitle() === "Save anyway?"), "asked again");
        section._flow = Object.assign(section._idleFlow(), { phase: "undoing" });
        assert(_modalClick("modalButton:0") && _until(() => !host.open), "… Save anyway while busy");
        assertEqual(_trial.starts + " " + _runs.length, startsRisk + " 0", "… nothing tried, nothing written");
        section._flow = section._idleFlow();
        assert(_click("apply") && _until(() => _modalTitle() === "Save anyway?"), "asked again");
        assert(_modalClick("modalButton:0"), "… Save anyway");
        assert(_until(() => _modalTitle() === "Try the new rules"), "… then the trial, as before every write");
        assertEqual(_trial.starts + " " + _runs.length, (startsRisk + 1) + " 0", "… tried, nothing written yet");
        assert(_modalClick("modalButton:0") && _until(() => !section._busy), "the trial cancelled");
        assertEqual(_runs.length, 0, "… nothing written");
        host.cancel("window");
        assert(_until(() => !host.open), "(closed)");
        assert(_click("reset"), "Reset");
        assert(_until(() => _texts("refusal").length === 0 && !section.changed), "… back to what is in force");

        // --- a row added: pending ---
        assert(_click("addRow"), "Add a row");
        assert(_until(() => _visible(_item("add:fingerprint"))) && _click("add:fingerprint"), "… the fingerprint");
        assert(_until(() => section.changed && _texts("pendingLine").length === 1), "the orange line: not in force until Apply");
        assert(_item("apply").available, "… Apply on");

        // --- the split ---
        assert(_click("splitSwitch", _item("splitSwitch").width - 12), "the split switched on");
        assert(_until(() => _item("list:sudo") !== null && _item("list:polkit-1") !== null), "… two lists");
        const polkitList = _item("list:polkit-1");
        polkitList.edited(PamRuleRules.removeRow(polkitList._rows, "r1", false));
        assert(_until(() => section.editor.polkit.length === 1), "(the polkit list changed)");
        assert(_click("splitSwitch", _item("splitSwitch").width - 12), "switched off");
        assert(_until(() => _modalTitle() === "Use sudo's rules for both?"), "… the lists differ: asked");
        assert(_modalClick("modalButton:1") && _until(() => !host.open), "… cancelled");
        assert(section.editor.split, "… still two lists");
        assert(_click("splitSwitch", _item("splitSwitch").width - 12) && _until(() => host.open), "switched off again");
        assert(_modalClick("modalButton:0"), "… Use sudo's");
        assert(_until(() => !section.editor.split && _item("list:shared") !== null), "… one list, sudo's");
        assertEqual(section.editor.shared.map(row => row.id).join(","), "r1,system", "… with sudo's rows");

        // --- the file ---
        assert(_click("showFile"), "Show file");
        assert(_until(() => _item("preview:sudo") !== null), "… the generated file");
        const preview = _item("preview:sudo");
        assert(_all(preview, "fileLine:ours").length === 1 && _all(preview, "fileLine:system").length > 0, "… our line accented, the system's muted");
        assert(_click("showFile") && _until(() => _item("preview:sudo") === null), "… hidden again");

        // --- Apply: a trial that fails ---
        assert(_click("apply"), "Apply");
        assert(_until(() => _modalTitle() === "Try the new rules"), "the trial's modal");
        assert(_until(() => _visible(_find(host.modal, "trialField"))), "… PAM's question, the field");
        assert(_item("list:shared").readOnly, "… the list read-only meanwhile");
        assertEqual(_find(host.modal, "trialPrompt").text + " | " + _find(host.modal, "trialMessage").text, "Password: | Touch the reader or type your password",
                    "… its question and message");
        assert(_find(host.modal, "trialMessage").textFormat === Text.PlainText && _find(host.modal, "trialMessage").maximumLineCount === 1, "… as plain text, on one line");
        assert(_until(() => _find(host.modal, "trialField").editing), "… the field has the keyboard");
        _type("nope");
        driver.keyClick(Qt.Key_Return);
        assert(_until(() => _modalTitle() === "Not saved"), "a wrong password: not saved");
        assert(_runs.length === 0, "… nothing run as administrator");
        assert(_modalClick("modalButton:0"), "Try again");

        // --- … and one that passes: both services written ---
        assert(_until(() => _modalTitle() === "Try the new rules" && _find(host.modal, "trialField")?.editing === true), "the trial again");
        _holdNext = true;
        _type(_password);
        driver.keyClick(Qt.Key_Return);
        assert(_until(() => _held !== null), "passed: sudo's write under way");
        assert(_archIntegration.busy && section._busy, "… the integration busy while it runs (its writer's run), the page too");
        _held();
        assert(_until(() => _modalTitle() === "Saved", 15000), "passed: written, said");
        assert(_until(() => !_archIntegration.busy), "… the integration no longer busy");
        assertEqual(_trial.starts, startsRisk + 3, "… one trial stood for both services (the risk's and the failed one before)");
        assertEqual(_runs.join(" | "), "Change the sign-in rules for sudo | Change the sign-in rules for administrator prompts", "… sudo, then administrator prompts");
        assert(_readFile(_paths.system + "/sudo").indexOf("pam_fprintd.so") > 0, "… sudo's file has the fingerprint");
        assert(_readFile(_paths.system + "/polkit-1").indexOf("# Written by h2s-shell") === 0, "… polkit's file of the shell's own");
        assert(_modalClick("modalButton:0") && _until(() => !host.open), "OK");
        assert(_until(() => _steps("sudo and administrator prompts") === "fingerprint>password"), "in force now: fingerprint, then password");
        assert(_until(() => !section.changed), "… nothing pending");

        // --- Undo ---
        assert(_until(() => _visible(_item("undo"))), "Undo offered");
        assert(_click("undo"), "Undo");
        assert(_until(() => _steps("sudo and administrator prompts") === "password", 15000), "the old files back: the password alone");
        assertEqual(_readFile(_paths.system + "/polkit-1"), "(none)", "… polkit's file of the shell's gone");
        assert(!_visible(_item("undo")), "… Undo done");
        assert(_until(() => !section.changed), "… the editor follows what is in force");

        // --- a second write that stops: saved in part ---
        assert(_click("addRow") && _until(() => _visible(_item("add:fingerprint"))) && _click("add:fingerprint"), "the fingerprint added again");
        assert(_until(() => _item("apply").available) && _click("apply"), "Apply");
        assert(_until(() => _modalTitle() === "Try the new rules" && _find(host.modal, "trialField")?.editing === true), "the trial");
        const startsHeld = _trial.starts;
        section.apply();
        assertEqual(_trial.starts, startsHeld, "a second Apply while one runs: nothing");
        assert(_reread(), "a reading lands during the trial");
        assert(section.changed && section.editor.shared.length === 2 && _modalTitle() === "Try the new rules", "… the rows and the trial kept");
        _failNext = "refuse2";
        _type(_password);
        driver.keyClick(Qt.Key_Return);
        assert(_until(() => _modalTitle() === "Saved in part", 15000), "polkit refused after sudo: saved in part");
        const partial = _all(host.modal, "modalLine").map(line => line.text);
        assert(partial.some(text => text === "Written: sudo. Not written: administrator prompts."), "… what was written and what not: " + partial.join(" | "));
        assert(partial.some(text => text.startsWith("Undo puts back " + _paths.backups + "/sudo.")), "… what Undo puts back");
        assert(_modalClick("modalButton:0") && _until(() => !host.open), "OK");
        assert(_until(() => _visible(_item("undo")) && section.lastWrite.length === 1), "Undo offered for sudo");
        assert(_until(() => section.editor.split && _texts("warning").some(text => text === PamRuleRules.texts.W8)), "… the lists left different: said");

        // --- an Undo that fails, then again ---
        _failNext = "refuse";
        assert(_click("undo"), "Undo");
        assert(_until(() => _modalTitle() === "Not undone"), "refused: not undone");
        assertEqual(section.lastWrite.length, 1, "… still to undo");
        assert(_modalClick("modalButton:0"), "Try again");
        assert(_until(() => !_visible(_item("undo")) && section.lastWrite.length === 0, 15000), "… undone");
        assertEqual(_readFile(_paths.system + "/sudo"), _sudo, "… sudo's old file back");
        assert(_until(() => !_texts("warning").some(text => text === PamRuleRules.texts.W8)), "… the lists' warning gone");
        // The reading after Undo taken, its editor (one list again) built: a click before it
        // could land on a list about to be replaced
        assert(_until(() => !section._resetOnReading && section.editor?.split === false && _item("list:shared") !== null), "… the editor from what is in force again");

        // --- the trial's modal refused: another question open ---
        assert(_click("addRow") && _until(() => _visible(_item("add:fingerprint"))) && _click("add:fingerprint"), "the fingerprint added again");
        assert(_until(() => section.changed), "(pending)");
        assertEqual(host.ask({ title: "Another question" }, () => {}), "", "another question open");
        const startsBefore = _trial.starts;
        section.apply();
        assertEqual(_trial.starts + " " + section._busy, startsBefore + " false", "Apply: no trial without its field, nothing held");
        assert(section.notice.indexOf("another question is open") >= 0, "… said under the buttons");
        host.cancel("window");
        assert(_until(() => !host.open), "(closed)");

        // --- a trial that fails as it starts ---
        _trial.failInStart = true;
        assert(_click("apply"), "Apply");
        assert(_until(() => _modalTitle() === "Not saved"), "a trial failing at once: not saved");
        assert(_all(host.modal, "modalLine").some(line => line.text === PamTrialRules.texts.unread), "… its reason");
        assert(!section._busy, "… nothing held");
        _trial.failInStart = false;
        assert(_modalClick("modalButton:1") && _until(() => !host.open), "(closed)");
        assert(_click("reset") && _until(() => !section.changed), "(reset)");

        // --- changed by hand ---
        assert(_write(_paths.system + "/sudo", _handSudo) && _reread(), "sudo changed by hand");
        assert(_until(() => _item("hand:sudo") !== null), "… shown as changed outside the shell");
        assert(_item("list:shared").readOnly, "… the list read-only");
        assert(_all(_item("hand:sudo"), "fileLine:marked").length === 1, "… the offending line marked");
        assert(_click("replace:sudo"), "Replace…");
        assert(_until(() => _modalTitle() === "Replace /etc/pam.d/sudo?"), "… asked");
        assert(_write(_paths.system + "/sudo", _handSudo2) && _reread(), "the file changed again while asked");
        assert(_modalClick("modalButton:0") && _until(() => !host.open), "… Replace");
        driver.wait(50);
        assert(_item("hand:sudo") !== null && Object.keys(section.replacing).length === 0, "… not what was shown: nothing taken in");
        assert(_click("replace:sudo") && _until(() => _modalTitle() === "Replace /etc/pam.d/sudo?"), "Replace… again");
        assert(_modalClick("modalButton:0"), "… Replace");
        assert(_until(() => _item("hand:sudo") === null && !_item("list:sudo")?.readOnly), "taken in: the list editable");
        assert(section.editor.sudo.some(row => row.method === "raw"), "… the key line a raw row");
        assert(section.changed && _texts("pendingLine").length === 1, "… pending until Apply");

        // --- NixOS ---
        _nixos = true;
        _integration = _nixosIntegration;
        assert(_reread(), "read as NixOS");
        assert(_until(() => _visible(_item("optionsSnippet"))), "the module's options shown");
        assert(_until(() => Object.keys(section.replacing).length === 0 && !section.changed), "… the file taken in gone with its rows: nothing to replace there");
        assert(!_visible(_item("apply")), "… no Apply");
        const startsNixos = _trial.starts;
        section.apply();
        assertEqual(_trial.starts, startsNixos, "… nor does apply() try anything there");
        assert(_click("addRow") && _until(() => _visible(_item("add:fingerprint"))) && _click("add:fingerprint"), "a fingerprint row added");
        assert(_until(() => _item("snippetText").text.indexOf("method = \"fingerprint\"") > 0), "… in the options");
        assert(_click("copy") && _until(() => _copied.indexOf("programs.h2s-shell.pam") === 0), "Copy");
        assertEqual(_item("copy").label, "Copied", "… said");
        assert(_texts("pendingLine")[0].indexOf("nixos-rebuild") >= 0, "… in force after a rebuild");
        assertEqual(_item("writtenTo").text, "the NixOS module", "… set through the module");
        const nixosList = _item("list:shared");
        assertEqual(nixosList.facts.texts?.systemRow, "NixOS's rules", "… the list handed the integration's words for the system's row");
        assertEqual(PamRuleViewRules.chips(PamRuleRules.fixedRow(), Object.assign({}, nixosList.facts, { faillockPresent: false })).join(","), "NixOS's rules",
                    "… its chip where the system's rules do not count (here they do: faillock's numbers)");
        section._setRows("shared", [{ id: "r9", method: "raw", control: "", details: { text: "auth sufficient pam_ldap.so" } }].concat(section.editor.shared));
        assert(_until(() => _texts("refusal").includes("Needs the module's full path on NixOS.")), "… a bare module libpam would not find: the integration's refusal");
        assert(_until(() => _item("snippetText").text === "No snippet while a check refuses the rows."), "… nothing to copy");
        section._reset();

        // --- a distribution the shell has no integration for ---
        _nixos = false;
        _integration = _genericIntegration;
        assert(_reread(), "read on another distribution");
        assert(_until(() => _visible(_item("unavailable"))), "why nothing is changed here shown");
        assertEqual(_item("unavailable").text, IntegrationRules.unsupported, "… not supported");
        assert(!_visible(_item("apply")) && !_visible(_item("optionsSnippet")) && !_visible(_item("splitSwitch")) && _item("list:shared") === null,
               "… no Apply, nothing to copy, no lists");
        assert(!_visible(_item("writtenTo")), "… nowhere the rules would go");
        const startsGeneric = _trial.starts;
        section.apply();
        assertEqual(_trial.starts, startsGeneric, "… nor does apply() try anything");

        // --- back on Arch: the editor follows what is in force as Arch reads it ---
        const fingerSudo = PamEditRules.build(_sudo, [{ id: "r1", method: "fingerprint", control: "sufficient", details: { timeout: 10, tries: 3 } },
                                                      PamRuleRules.fixedRow()], Object.assign(section.factsFor("sudo"), { writes: true }));
        assert(fingerSudo.ok && _write(_paths.system + "/sudo", fingerSudo.text) && _reread(), "the shell's fingerprint rules in sudo's file, read on the other distribution");
        assert(_until(() => section.editor !== null && section.editor.shared.length === 1), "… there: the fixed row alone");
        _integration = _archIntegration;
        assert(_until(() => section.editor.sudo?.some(row => row.method === "fingerprint") === true), "Arch again: the fingerprint row in force in the editor");
        assert(!section.changed && _texts("pendingLine").length === 0, "… nothing pending (Apply would not drop it)");

        // --- the lock screen's switches ---
        const fingerprint = _item("unlock:fingerprint");
        assert(fingerprint.checked && fingerprint.enabled, "unlock: the fingerprint on");
        assert(!_item("unlock:securityKey").enabled && !_item("unlock:securityKey").checked, "… no key: off, dimmed");
        assert(!_item("unlock:password").enabled && _item("unlock:password").checked, "… the password always on");
        assert(_clickItem(fingerprint, fingerprint.width - 12), "the fingerprint switched");
        assert(_until(() => _writes.join(",") === "lockscreen.offerFingerprint=false"), "… the setting written");
        assert(_until(() => !_item("unlock:fingerprint").checked), "… shown off");
        assert(_clickItem(_item("unlock:securityKey"), _item("unlock:securityKey").width - 12), "the dimmed key clicked");
        // Its switch said toggled anyway (a keyboard, a module): a method the computer lacks is not offered
        _item("unlock:securityKey").toggled();
        driver.wait(50);
        assertEqual(_writes.length, 1, "… nothing written");
        assert(!_visible(_item("unlockWarning:securityKey")), "… no warning under it");

        // --- the key switch's warning: the system's pam_u2f settings ---
        const lockSettings = more => ({ securityKey: "ready", u2f: { lock: Object.assign({ known: true, alwaysok: false, nouserok: false, touchOff: false }, more), rows: null, conf: null } });
        _extraFacts = lockSettings({ alwaysok: true });
        assert(_reread() && _until(() => _item("unlock:securityKey").enabled), "a key registered, the system's settings with alwaysok");
        assert(_until(() => _visible(_item("unlockWarning:securityKey"))), "… a warning under the key switch");
        assertEqual(_item("unlockWarning:securityKey").text, "Unlocks without a key: the system's pam_u2f settings have alwaysok.", "… its text");
        assert(_item("unlockWarning:securityKey").textFormat === Text.PlainText, "… as plain text");
        _extraFacts = lockSettings({ nouserok: true });
        assert(_reread() && _until(() => !_visible(_item("unlockWarning:securityKey"))), "nouserok alone: no warning (the lock's one line must pass)");
        _extraFacts = ({});

        // --- the window closed and opened again: what the computer has is read again ---
        const asked = _stacks.methodsAsked;
        _window.visible = false;
        assert(_until(() => !section._shown), "the window hidden, the page kept");
        assertEqual(_stacks.methodsAsked, asked, "… nothing read while hidden");
        _securityKey = "ready";
        const reads = _reads;
        _window.visible = true;
        assert(_until(() => section._shown && _stacks.methodsAsked === asked + 1), "shown again: read, with what the computer has");
        assert(_until(() => _reads > reads && _item("unlock:securityKey").enabled), "… the key registered meanwhile: its switch available");
        driver.wait(50);
        assertEqual(_stacks.methodsAsked, asked + 1, "… read once for the showing");

        // --- shown again while a write runs: the read made up when it ends ---
        _window.visible = false;
        assert(_until(() => !section._shown), "the window hidden again");
        _securityKey = "absent";
        // (a write under way, as Apply's: the flow's own state)
        section._flow = Object.assign(section._idleFlow(), { phase: "writing" });
        _window.visible = true;
        assert(_until(() => section._shown), "shown while the write runs");
        driver.wait(50);
        assertEqual(_stacks.methodsAsked, asked + 1, "… not read meanwhile");
        section._flow = section._idleFlow();
        assert(_until(() => _stacks.methodsAsked === asked + 2), "the write over: read, with what the computer has");
        assert(_until(() => !_item("unlock:securityKey").enabled), "… the key gone meanwhile: its switch off");
    }

    // ── Processes ──

    function _exec(command, done) {
        const process = _shell.createObject(suite, { command: command });
        process.finished.connect((code, stdout, stderr) => done?.(code, stdout, stderr));
        process.running = true;
    }

    property Component _shell: Component {
        Process {
            id: _process
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
                _process.finished(_code, _stdout, _stderr);
                _process.destroy();
            }
            stdout: StdioCollector {
                onStreamFinished: {
                    _process._stdout = text;
                    _process._finished = true;
                    _process._over();
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    _process._stderr = text;
                    _process._errorFinished = true;
                    _process._over();
                }
            }
            onExited: code => {
                _process._code = code;
                _process._exited = true;
                _process._over();
            }
        }
    }
}
