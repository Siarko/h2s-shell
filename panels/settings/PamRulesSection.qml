import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.io

// System → Authentication → Sign-in rules: how sudo and administrator prompts (polkit) ask
// who you are, and under it the lock screen's ways to unlock. At the top what is in force, as
// steps (PamStacks' stacks), what the computer has and where the rules go; the switch for
// separate rules per service; a PamRuleList per list with its checks (PamRuleRules.check);
// What can be done with them is the distribution integration's capability of "pam.rules":
// where the shell applies them (Arch), Apply (a trial of the new rules as the user, PamTrial,
// then one write as administrator per service through the integration), Reset, Undo, "Show
// file" (the plan's files); a file changed outside the shell is shown read-only with "Read
// again" and "Replace…". Where the system's configuration sets them (NixOS): the plan's
// options to paste. Elsewhere, or while the system is not known: the reason, nothing to edit.
// Decisions are PamRuleViewRules'; nothing here reads a file itself, and nothing asks for a
// password without a click.
ColumnLayout {
    id: root

    // The I/O, handed in by a suite as stand-ins: PamStacks (reading, facts, sudo, polkit,
    // faillock, directories, files, refresh), a trial (start, respond, cancel, state) and the
    // distribution's integration (capability, details, plan, apply, undo, busy; facts, where it
    // has them, for how this system gets a missing package)
    property var stacks: PamStacks
    property var trial: _ownTrial
    property var integration: Distribution
    // Where questions are asked (SettingsModalHost)
    property var modalHost: null
    // The lock screen's settings, read and written
    property var settingValue: key => Profiles.value(key)
    property var writeSetting: (key, value) => Profiles.writeSetting(0, key, value)
    property var copyText: text => {
        Quickshell.clipboardText = text;
    }

    Layout.fillWidth: true
    spacing: 6

    PamTrial {
        id: _ownTrial
        moduleDirectories: root.stacks?.facts?.moduleDirectories ?? []
        onLogLine: (level, message) => level === "warning" ? console.warn("[PamRules] " + message) : console.log("[PamRules] " + message)
    }
    // How this system makes the rules, and the integration's words and facts for them
    readonly property var capability: integration?.capability("pam.rules") ?? IntegrationRules.unknownCapability()
    readonly property string mode: capability.mode
    readonly property var _details: integration?.details("pam.rules") ?? ({ texts: {}, facts: {} })
    readonly property var _modeTexts: PamRuleViewRules.modeTexts(capability, _details.texts, stacks?.directories?.[0])
    readonly property var _base: Object.assign({}, stacks?.facts ?? {}, {
        writes: mode === "apply",
        bareModules: typeof _details.facts?.bareModules === "string" ? _details.facts.bareModules : "",
        texts: _details.texts
    })
    readonly property var _files: PamRuleViewRules.filesOf(stacks?.files, stacks?.directories)
    readonly property var _machine: ({ writes: _base.writes, bareModules: _base.bareModules, texts: _base.texts,
                                       moduleDirectories: _base.moduleDirectories ?? [], fingerprint: _base.fingerprint, securityKey: _base.securityKey })
    readonly property var _inForce: ({
        "sudo": PamRuleViewRules.inForceOf(_files.sudo, "sudo", _files.vendorPolkit, _machine),
        "polkit-1": PamRuleViewRules.inForceOf(_files.polkit, "polkit-1", _files.vendorPolkit, _machine)
    })

    // The editor's lists ({ split, shared, sudo, polkit }), null before the first reading;
    // set from what is in force at the first reading, on Reset and after a write
    property var editor: null
    // A service whose hand-made file was taken in (Replace): { service: adopt's hash }
    property var replacing: ({})
    property bool showFile: false
    property bool copied: false
    readonly property var _lists: editor ? PamRuleRules.listsFor(editor) : ({ "sudo": [], "polkit-1": [] })
    readonly property bool changed: editor !== null
        && (PamRuleViewRules.pending(editor, _inForce["sudo"].rows, _inForce["polkit-1"].rows) || Object.keys(replacing).length > 0)
    // The user changed the editor since it was last set from what is in force
    property bool _edited: false

    function _reset() {
        replacing = ({});
        editor = PamRuleViewRules.editorFrom(_inForce["sudo"].rows, _inForce["polkit-1"].rows);
        copied = false;
        _edited = false;
    }

    // The system's way changed (known at last): an editor the user has not touched follows
    // what is in force as this way reads it — once the bindings that read it under the new
    // way (_base, _machine, _inForce) have settled, which the change notice may come before
    onModeChanged: Qt.callLater(root._followMode)
    function _followMode() {
        if (editor !== null && !_edited && !_busy)
            _reset();
    }

    // What the change would be (the integration's plan): the files to write where the shell
    // applies the rules, the options to copy where the system's configuration sets them
    readonly property var _plan: editor === null || mode === "unavailable" ? null : integration?.plan("pam.rules", {
        split: editor.split === true,
        "sudo": { rows: _lists["sudo"], facts: factsFor("sudo"), currentText: _files.sudo },
        "polkit-1": { rows: _lists["polkit-1"], facts: factsFor("polkit-1"), currentText: _files.polkit }
    }) ?? null
    readonly property var _preview: _plan?.preview ?? null
    readonly property string _backups: typeof _preview?.backups === "string" ? _preview.backups : ""
    // A service's file as the plan would write it: its text, "" removed, null none
    function _plannedText(service) {
        const file = (_preview?.files ?? []).find(item => String(item?.path ?? "").endsWith("/" + service));
        return file === undefined ? null : file.text;
    }

    // A reading came: the editor follows what is in force unless it holds changes
    property var _lastReading: null
    readonly property var _reading: stacks?.reading ?? null
    on_ReadingChanged: _takeReading()
    Component.onCompleted: _takeReading()
    // What is in force and what the computer has, read each time the page shows (a key
    // registered while the window was hidden); a showing while a flow runs is made up when it
    // ends, if the page is still shown
    readonly property bool _shown: _pageShown.shown
    property bool _refreshDue: false
    PageShown {
        id: _pageShown
        onBecameShown: root._readShown()
    }
    on_BusyChanged: if (!_busy && _refreshDue && _shown) _readShown()
    function _readShown() {
        _refreshDue = _busy;
        if (!_busy)
            stacks?.refresh(true);
    }
    function _takeReading() {
        if (_reading === null || _reading === _lastReading)
            return;
        _lastReading = _reading;
        // A file taken in by Replace that is no longer the hand-made one (written, changed
        // again, or a system where the shell writes none): its rows go with it
        const staleReplace = Object.keys(replacing).some(service => !_inForce[service].changed);
        if (editor === null || !changed || _resetOnReading || staleReplace) {
            _resetOnReading = false;
            _reset();
        }
    }
    property bool _resetOnReading: false

    // The facts a service's rows are checked and built with
    function factsFor(service) {
        const other = _lists[PamRuleRules.otherService(service)];
        const stack = service === "sudo" ? stacks?.sudo : stacks?.polkit;
        const facts = PamRuleViewRules.serviceFacts(_base, service, stack, stacks?.faillock?.[service], other,
                                                    _files.vendorPolkit, _inForce[service].changed && replacing[service] === undefined);
        if (replacing[service] !== undefined)
            facts.replace = replacing[service];
        facts.sharedApplyStopped = sharedStopped;
        return facts;
    }

    // The lists shown: one shared, or one per service
    readonly property var _listKeys: editor?.split === true ? ["sudo", "polkit-1"] : ["shared"]
    function _serviceOf(key) {
        return key === "shared" ? "sudo" : key;
    }
    function _titleOf(key) {
        return key === "shared" ? "sudo and administrator prompts" : key === "sudo" ? "sudo" : "Administrator prompts (polkit)";
    }
    function _rowsOf(key) {
        return key === "shared" ? (editor?.shared ?? []) : key === "sudo" ? (editor?.sudo ?? []) : (editor?.polkit ?? []);
    }
    // `rows` came through a signal: a sequence of maps, made plain lists and objects again
    // for PamRuleRules (which takes only arrays for lists)
    function _setRows(key, given) {
        const rows = JSON.parse(JSON.stringify(Array.from(given ?? [])));
        const next = Object.assign({}, editor);
        if (key === "shared")
            next.shared = rows;
        else if (key === "sudo")
            next.sudo = rows;
        else
            next.polkit = rows;
        editor = next;
        copied = false;
        _edited = true;
    }
    // A list is read-only while a file it writes was changed by hand and not taken in
    function _handOf(key) {
        const services = key === "shared" ? ["sudo", "polkit-1"] : [key];
        return services.some(service => _inForce[service].changed && replacing[service] === undefined);
    }
    function _checkOf(key) {
        const service = _serviceOf(key);
        return PamRuleRules.check(_rowsOf(key), factsFor(service));
    }
    readonly property bool refused: editor !== null && _listKeys.some(key => _checkOf(key).refusals.length > 0)

    // ── Split ──

    function toggleSplit() {
        if (!editor || _busy)
            return;
        const toggled = PamRuleViewRules.splitToggled(editor);
        if (!toggled.ask) {
            editor = toggled.editor;
            _edited = true;
            return;
        }
        _ask(PamRuleViewRules.joinSpec, answer => {
            if (!answer.cancelled && answer.button === "join") {
                root.editor = PamRuleViewRules.splitToggled(root.editor).editor;
                root._edited = true;
            }
        });
    }

    function _ask(spec, onAnswer) {
        if (!modalHost)
            return false;
        return modalHost.ask(spec, onAnswer) === "";
    }

    // ── Replace ──

    function askReplace(service) {
        const state = _inForce[service];
        if (!state.changed || !state.adopted)
            return;
        _ask(PamRuleViewRules.replaceSpec(service, _backups, state.adopted), answer => {
            if (answer.cancelled || answer.button !== "replace")
                return;
            // The file changed since the question was asked: what it showed is not what is there
            const now = root._inForce[answer.subject.service];
            if (!now.adopted || now.adopted.hash !== answer.subject.hash)
                return;
            root.replacing = Object.assign({}, root.replacing, { [answer.subject.service]: now.adopted.hash });
            const next = Object.assign({}, root.editor);
            const adoptedRows = now.adopted.rows;
            if (next.split !== true) {
                // One list for both: the hand-made file's rows serve both, as it was in force
                next.split = !PamRuleRules.sameRows(adoptedRows, root._lists[PamRuleRules.otherService(answer.subject.service)]);
                next.shared = adoptedRows;
                next.sudo = answer.subject.service === "sudo" ? adoptedRows : root._lists["sudo"];
                next.polkit = answer.subject.service === "polkit-1" ? adoptedRows : root._lists["polkit-1"];
            } else if (answer.subject.service === "sudo") {
                next.sudo = adoptedRows;
            } else {
                next.polkit = adoptedRows;
            }
            root.editor = next;
            root._edited = true;
        });
    }

    // ── Apply: a trial, then one write per service ──

    // { phase ("" | "trial" | "writing" | "undoing"), items, index, question (the trial's
    // modal, by a number of this page's), trialId, passed (the passed trial's state),
    // outcomes, shared (one list for both services) }
    property var _flow: _idleFlow()
    function _idleFlow() {
        return { phase: "", items: [], index: 0, question: 0, trialId: -1, passed: null, outcomes: [], shared: false };
    }
    readonly property bool _busy: _flow.phase !== "" || (integration?.busy === true)
    // What the last Apply wrote and Undo has not put back: its outcomes
    property var lastWrite: []
    property string status: ""
    // Why the last Apply or Undo stopped without its modal (another question was open)
    property string notice: ""
    // A shared Apply stopped between the two services: the lists differ until Apply again (W8)
    property bool sharedStopped: false
    property int _questions: 0

    // A page closed while a write runs drops its outcome: the run goes on as administrator,
    // and the page reads what is in force again when it shows next (PageShown).
    function apply() {
        if (_busy || !editor || mode !== "apply")
            return;
        notice = "";
        const queue = _applyQueue();
        if (queue.refusals.length > 0) {
            _ask(PamRuleViewRules.notSavedSpec(queue.refusals[0].text), () => {});
            return;
        }
        if (queue.items.length === 0)
            return;
        // Rows that may let anyone in or lock the user out are written only once confirmed;
        // the answer acts on the files it was asked about, and the trial still comes first
        const question = PamRuleViewRules.riskQuestion(queue.risks, { files: _queueKey(queue) });
        if (question === null) {
            _startApply(queue);
            return;
        }
        if (!_ask(question, answer => {
            if (answer.cancelled || answer.button !== "save" || root._busy || !root.editor || root.mode !== "apply")
                return;
            const now = root._applyQueue();
            if (now.refusals.length === 0 && root._queueKey(now) === answer.subject.files)
                root._startApply(now);
        }))
            notice = "Not saved: another question is open.";
    }

    function _applyQueue() {
        const inputs = {};
        for (const service of PamRuleRules.services)
            inputs[service] = { rows: _lists[service], currentText: service === "sudo" ? _files.sudo : _files.polkit, facts: factsFor(service) };
        return PamRuleViewRules.applyQueue(inputs);
    }

    function _queueKey(queue) {
        return JSON.stringify(queue.items.map(item => [item.service, item.text]));
    }

    function _startApply(queue) {
        _flow = Object.assign(_idleFlow(), { phase: "trial", items: queue.items, shared: editor.split !== true });
        _next();
    }

    function _next() {
        const item = _flow.items[_flow.index];
        if (!item) {
            _finishWrites();
            return;
        }
        if (PamRuleViewRules.trialCovers(_flow.passed, item.service, item.text)) {
            _write(item);
            return;
        }
        // The question first: a trial no field answers would keep PAM waiting
        const question = ++_questions;
        _flow = Object.assign({}, _flow, { phase: "trial", question, trialId: -1 });
        const asked = _ask(Object.assign(PamRuleViewRules.trialSpec(_flow.index, _flow.items.length, item.service),
                                         { content: _trialContent, subject: { question } }), answer => {
            if (answer.reason === "subject")
                return;
            if (root._flow.phase === "trial" && root._flow.question === answer.subject.question) {
                root.trial.cancel(root._flow.trialId);
                // Cancelled: said only when something was written before
                root._stop(root._flow.outcomes.length > 0 ? "The trial was cancelled." : "", item.service, "", true);
            }
        });
        if (!asked) {
            _stop("The trial could not be shown: another question is open.", item.service, "", false);
            return;
        }
        trial.start(item.service, item.text);
        _flow = Object.assign({}, _flow, { trialId: trial.state?.trial ?? 0 });
        // A trial that ended inside start() (a file not read, a refusal) is taken now
        _takeTrial();
    }

    // The trial's outcome, as PamTrial reports it
    readonly property var _trialState: trial?.state ?? null
    on_TrialStateChanged: _takeTrial()
    function _takeTrial() {
        const state = _trialState;
        if (_flow.phase !== "trial" || !state || state.trial !== _flow.trialId)
            return;
        if (state.phase === "passed") {
            modalHost?.withdraw({ question: _flow.question });
            _flow = Object.assign({}, _flow, { passed: state });
            _write(_flow.items[_flow.index]);
        } else if (state.phase === "failed") {
            modalHost?.withdraw({ question: _flow.question });
            _stop(state.pamReason !== "" ? state.reasonText + " " + state.pamReason : state.reasonText, state.service, "", true);
        }
    }

    function _write(item) {
        _flow = Object.assign({}, _flow, { phase: "writing" });
        status = "Saving " + PamRuleViewRules.progress(_flow.index, _flow.items.length, item.service) + "…";
        const started = integration.apply("pam.rules", { service: item.service, built: item.built, currentText: item.currentText,
                                                         vendorText: item.vendorText, trial: _flow.passed },
                                          { done: outcome => root?._written(outcome) });
        if (!started.started)
            _stop(started.refusal?.text ?? "", item.service, "", true);
    }

    function _written(outcome) {
        if (_flow.phase === "undoing") {
            _undone(outcome);
            return;
        }
        if (_flow.phase !== "writing")
            return;
        if (!outcome.ok) {
            _stop(outcome.quiet ? "" : outcome.error, outcome.service, outcome.file ?? "", true);
            return;
        }
        const outcomes = _flow.outcomes.concat([outcome]);
        _flow = Object.assign({}, _flow, { outcomes, index: _flow.index + 1 });
        _next();
    }

    function _finishWrites() {
        const outcomes = _flow.outcomes;
        _endFlow();
        lastWrite = outcomes;
        sharedStopped = false;
        _ask(PamRuleViewRules.savedSpec(outcomes, _backups), () => {});
        _refreshAfter();
    }

    // An Apply that stopped at `service`: what was written stays (Undo puts it back), a shared
    // list stopped half way says so (W8), the modal says what changed — or, when it cannot
    // be shown, the line under the buttons
    function _stop(reason, service, file, canAsk) {
        const outcomes = _flow.outcomes;
        const shared = _flow.shared;
        _endFlow();
        if (outcomes.length > 0)
            lastWrite = outcomes;
        if (shared && outcomes.length > 0)
            sharedStopped = true;
        const said = PamRuleViewRules.stoppedSpec(outcomes, reason, service, file, _backups);
        if (said.spec !== null) {
            const retry = said.spec.buttons?.some(button => button.id === "again") === true;
            if (!canAsk || !_ask(said.spec, answer => {
                if (retry && !answer.cancelled && answer.button === "again")
                    root.apply();
            }))
                notice = said.spec.body.join(" ");
        }
        if (outcomes.length > 0 || said.changed)
            _refreshAfter();
    }

    function _endFlow() {
        _flow = _idleFlow();
        status = "";
    }

    // What is in force is read again; the editor follows it
    function _refreshAfter() {
        _resetOnReading = true;
        stacks?.refresh(false);
    }

    // ── Undo: the last write's backups put back, the last service first ──

    function undo() {
        if (_busy || lastWrite.length === 0)
            return;
        notice = "";
        _flow = Object.assign(_idleFlow(), { phase: "undoing", items: lastWrite.slice().reverse() });
        _undoNext();
    }

    function _undoNext() {
        const outcome = _flow.items[_flow.index];
        if (!outcome) {
            _endFlow();
            sharedStopped = false;
            _refreshAfter();
            return;
        }
        status = "Undoing " + PamRuleViewRules.progress(_flow.index, _flow.items.length, outcome.service) + "…";
        const started = integration.undo("pam.rules", { from: outcome, done: answer => root?._written(answer) });
        if (!started.started)
            _undoStopped(started.refusal?.text ?? "");
    }

    function _undone(outcome) {
        if (!outcome.ok) {
            if (outcome.quiet) {
                _endFlow();
                _refreshAfter();
            } else {
                _undoStopped(outcome.error);
            }
            return;
        }
        // Put back: no longer to undo
        const done = _flow.items[_flow.index];
        lastWrite = lastWrite.filter(item => item.backup !== done.backup);
        _flow = Object.assign({}, _flow, { index: _flow.index + 1 });
        _undoNext();
    }

    function _undoStopped(reason) {
        _endFlow();
        const spec = PamRuleViewRules.undoFailedSpec(reason, lastWrite);
        if (!_ask(spec, answer => {
            if (!answer.cancelled && answer.button === "again")
                root.undo();
        }))
            notice = spec.body.join(" ");
        _refreshAfter();
    }

    // ── Pieces ──

    component Caption: Text {
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }

    // A check's line: its icon and text in its kind's colour
    component CheckLine: RowLayout {
        property string text: ""
        property bool refusal: false
        Layout.fillWidth: true
        spacing: 6
        Text {
            text: parent.refusal ? String.fromCodePoint(0xF057) : String.fromCodePoint(0xF071)
            color: parent.refusal ? Theme.error : Theme.warning
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.alignment: Qt.AlignTop
        }
        Caption {
            objectName: parent.refusal ? "refusal" : "warning"
            Layout.fillWidth: true
            text: parent.text
            color: parent.refusal ? Theme.error : Theme.warning
        }
    }

    // A step of what is in force: the method's icon and name
    component StepChip: Rectangle {
        property string method: ""
        objectName: "step:" + method
        implicitWidth: _stepRow.implicitWidth + 16
        implicitHeight: _stepRow.implicitHeight + 6
        radius: height / 2
        color: Theme.surface
        border.width: Theme.border.width
        border.color: Theme.outline
        Row {
            id: _stepRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                text: PamRuleViewRules.icon(parent.parent.method)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
            }
            Text {
                text: PamRuleViewRules.stepLabels[parent.parent.method] ?? ""
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textPrimary
            }
        }
    }

    // A file's lines, read-only: [{ text, kind }] or [{ text, marked }]
    component FileBox: Rectangle {
        id: _fileBox
        property string title: ""
        property var lines: []
        Layout.fillWidth: true
        implicitHeight: _fileColumn.implicitHeight + 20
        radius: Theme.settings.cardRadius
        color: Theme.surfaceSunken
        border.width: Theme.border.width
        border.color: Theme.divider
        ColumnLayout {
            id: _fileColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 2
            Caption { text: _fileBox.title; Layout.bottomMargin: 4; Layout.fillWidth: true }
            Repeater {
                model: ScriptModel { values: (_fileBox.lines ?? []).map((line, i) => String(i)) }
                RowLayout {
                    id: _fileLine
                    required property string modelData
                    readonly property var line: _fileBox.lines[Number(modelData)] ?? ({ text: "" })
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        objectName: "fileLine:" + (_fileLine.line.kind ?? (_fileLine.line.marked ? "marked" : "plain"))
                        Layout.fillWidth: true
                        text: _fileLine.line.text
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: _fileLine.line.marked ? Theme.error
                            : _fileLine.line.kind === "ours" || _fileLine.line.kind === "counted" ? Theme.accent
                            : _fileLine.line.kind === "marker" ? Theme.textMuted
                            : _fileLine.line.kind === "system" ? Theme.textDisabled : Theme.textSecondary
                    }
                    Caption { visible: _fileLine.line.kind === "counted"; text: "counted"; wrapMode: Text.NoWrap }
                    Caption { visible: _fileLine.line.marked === true; text: _fileLine.line.reason ?? ""; color: Theme.error; wrapMode: Text.NoWrap }
                }
            }
        }
    }

    // The trial's content in its modal: PAM's messages, its question and the field
    property Component _trialContent: Component {
        ColumnLayout {
            id: _trialView
            readonly property var state: root.trial?.state ?? ({ messages: [], prompt: null })
            spacing: 8
            Repeater {
                model: ScriptModel { values: (_trialView.state.messages ?? []).map((message, i) => String(i)) }
                Text {
                    required property string modelData
                    readonly property var message: _trialView.state.messages[Number(modelData)] ?? ({ text: "" })
                    objectName: "trialMessage"
                    Layout.fillWidth: true
                    text: message.text
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: message.error ? Theme.error : Theme.textPrimary
                }
            }
            Text {
                objectName: "trialPrompt"
                visible: _trialView.state.prompt !== null
                Layout.fillWidth: true
                text: _trialView.state.prompt?.text ?? ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
            }
            InputField {
                id: _answer
                objectName: "trialField"
                visible: _trialView.state.prompt !== null
                Layout.fillWidth: true
                password: _trialView.state.prompt?.visible !== true
                onAccepted: {
                    const text = _answer.text;
                    _answer.text = "";
                    root.trial.respond(_trialView.state.trial, text);
                }
                // The trial began with the user's click on Apply: the field takes the keyboard
                onVisibleChanged: if (visible && !editing) focusAll()
                Component.onCompleted: Qt.callLater(() => {
                    if (_answer.visible && !_answer.editing)
                        _answer.focusAll();
                })
            }
            Caption {
                visible: _trialView.state.prompt === null && (_trialView.state.phase === "reading" || _trialView.state.phase === "staging" || _trialView.state.phase === "running")
                text: "Waiting for PAM…"
            }
        }
    }

    // ── The view ──

    SectionTitle {
        Layout.fillWidth: true
        Layout.topMargin: 12
        text: "Sign-in rules"
    }
    Hint {
        text: "How sudo and administrator prompts (polkit) ask who you are. Rows are tried from the top."
    }

    // What is in force, what this computer has, where the rules go
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: _facts.implicitHeight + 20
        radius: Theme.settings.cardRadius
        color: Theme.fillSubtle
        border.width: Theme.border.width
        border.color: Theme.outline
        GridLayout {
            id: _facts
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; leftMargin: 12; rightMargin: 12 }
            columns: 2
            columnSpacing: 16
            rowSpacing: 6
            Caption { text: "In force now"; Layout.alignment: Qt.AlignTop | Qt.AlignLeft; Layout.topMargin: 3; wrapMode: Text.NoWrap }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: ScriptModel { values: PamRuleViewRules.summaryRows(root.stacks?.sudo, root.stacks?.polkit).map(row => row.title) }
                    RowLayout {
                        id: _summaryRow
                        required property string modelData
                        readonly property var steps: PamRuleViewRules.summaryRows(root.stacks?.sudo, root.stacks?.polkit)
                                                         .find(row => row.title === modelData)?.steps ?? null
                        objectName: "summary:" + modelData
                        spacing: 6
                        Text {
                            text: _summaryRow.modelData + ":"
                            textFormat: Text.PlainText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textPrimary
                        }
                        Repeater {
                            model: ScriptModel { values: (_summaryRow.steps ?? []).map((step, i) => i + ":" + step) }
                            Row {
                                required property string modelData
                                readonly property int position: Number(modelData.split(":")[0])
                                spacing: 6
                                Text {
                                    visible: parent.position > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "→"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeBody
                                    color: Theme.textMuted
                                }
                                StepChip { method: parent.modelData.split(":")[1] }
                            }
                        }
                        Caption {
                            visible: _summaryRow.steps === null || _summaryRow.steps.length === 0
                            objectName: "summaryUnknown"
                            text: _summaryRow.steps === null ? "not known" : "no method the shell knows"
                        }
                    }
                }
                Caption {
                    objectName: "pendingLine"
                    visible: root.changed
                    Layout.fillWidth: true
                    color: Theme.warning
                    text: root._modeTexts.pending
                }
            }
            Caption { text: "This computer has"; Layout.alignment: Qt.AlignTop | Qt.AlignLeft; wrapMode: Text.NoWrap }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: PamRuleViewRules.computerHas(root._base)
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
            }
            Caption {
                visible: root._modeTexts.label !== ""
                text: root._modeTexts.label
                Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                wrapMode: Text.NoWrap
            }
            Caption {
                objectName: "writtenTo"
                visible: root._modeTexts.label !== ""
                Layout.fillWidth: true
                text: root._modeTexts.where
            }
        }
    }

    SwitchRow {
        objectName: "splitSwitch"
        Layout.topMargin: 6
        visible: root.editor !== null && root.mode !== "unavailable"
        label: "Separate rules for administrator prompts"
        hint: "Off: one list for sudo and administrator prompts."
        checked: root.editor?.split === true
        onToggled: root.toggleSplit()
    }

    // A file changed outside the shell: shown, its lines marked, taken in only on Replace
    Repeater {
        model: ScriptModel {
            values: PamRuleRules.services.filter(service => root._inForce[service].changed && root.replacing[service] === undefined)
        }
        Rectangle {
            id: _hand
            required property string modelData
            readonly property var state: root._inForce[modelData]
            objectName: "hand:" + modelData
            Layout.fillWidth: true
            implicitHeight: _handColumn.implicitHeight + 24
            radius: Theme.settings.cardRadius
            color: Theme.errorTint
            border.width: Theme.border.width
            border.color: Theme.error
            ColumnLayout {
                id: _handColumn
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    CheckLine {
                        refusal: true
                        text: "Changed outside the shell: " + (_hand.state.reasons?.[0]?.text ?? "")
                    }
                    SmallButton {
                        objectName: "readAgain:" + _hand.modelData
                        label: "Read again"
                        fontSize: Theme.fontSizeSmall
                        onClicked: root.stacks?.refresh(false)
                    }
                    SmallButton {
                        objectName: "replace:" + _hand.modelData
                        label: "Replace…"
                        kind: "warning"
                        fontSize: Theme.fontSizeSmall
                        available: root.mode === "apply" && _hand.state.adopted !== null
                        onClicked: root.askReplace(_hand.modelData)
                    }
                }
                FileBox {
                    title: (root.stacks?.directories?.[0] ?? "/etc/pam.d") + "/" + _hand.modelData
                    lines: PamRuleViewRules.handLines(_hand.modelData === "sudo" ? root._files.sudo : root._files.polkit, _hand.state.reasons)
                }
                Caption { text: "Taken in as rows — what Replace would put in the editor:"; Layout.fillWidth: true }
                PamRuleList {
                    Layout.fillWidth: true
                    readOnly: true
                    title: _hand.modelData
                    rows: _hand.state.adopted?.rows ?? []
                    facts: root.factsFor(_hand.modelData)
                    distributionFacts: root.integration?.facts ?? null
                }
            }
        }
    }

    // The lists, each with its checks
    Repeater {
        model: ScriptModel { values: root.editor !== null && root.mode !== "unavailable" ? root._listKeys : [] }
        ColumnLayout {
            id: _listBlock
            required property string modelData
            readonly property string service: root._serviceOf(modelData)
            readonly property var result: root._checkOf(modelData)
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 6
            Text {
                text: root._titleOf(_listBlock.modelData)
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                color: Theme.textPrimary
            }
            PamRuleList {
                objectName: "list:" + _listBlock.modelData
                Layout.fillWidth: true
                title: root._titleOf(_listBlock.modelData)
                rows: root._rowsOf(_listBlock.modelData)
                facts: root.factsFor(_listBlock.service)
                distributionFacts: root.integration?.facts ?? null
                result: _listBlock.result
                modalHost: root.modalHost
                readOnly: root._handOf(_listBlock.modelData) || root._busy
                onEdited: rows => root._setRows(_listBlock.modelData, rows)
            }
            Repeater {
                // Refusals and risks alike in red: a risk is saved only once confirmed
                model: ScriptModel { values: _listBlock.result.refusals.concat(_listBlock.result.risks ?? []).map(item => item.text).filter((text, i, all) => all.indexOf(text) === i) }
                CheckLine { required property string modelData; refusal: true; text: modelData }
            }
            Repeater {
                model: ScriptModel { values: _listBlock.result.warnings.map(item => item.text).filter((text, i, all) => all.indexOf(text) === i) }
                CheckLine { required property string modelData; refusal: false; text: modelData }
            }
        }
    }

    // Nothing to change here: why
    Caption {
        objectName: "unavailable"
        visible: root.mode === "unavailable"
        Layout.fillWidth: true
        Layout.topMargin: 8
        text: root._modeTexts.reason
    }

    // Where the shell applies the rules: Apply, Reset, Undo, the file
    RowLayout {
        visible: root.mode === "apply" && root.editor !== null
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 6
        SmallButton {
            readonly property var look: PamRuleViewRules.applyButton(root.changed, root.refused, root._busy, false)
            objectName: "apply"
            label: "Apply"
            kind: "save"
            available: look.available
            tooltip: look.tooltip
            onClicked: if (available) root.apply()
        }
        SmallButton {
            objectName: "reset"
            label: "Reset"
            kind: "cancel"
            available: root.changed && !root._busy
            onClicked: if (available) root._reset()
        }
        SmallButton {
            objectName: "undo"
            visible: root.lastWrite.length > 0
            label: "Undo"
            available: !root._busy
            tooltip: "Puts back " + root.lastWrite.map(outcome => outcome.backup).join(", ") + " (asks the administrator password)"
            onClicked: if (available) root.undo()
        }
        Item { Layout.fillWidth: true }
        SmallButton {
            objectName: "showFile"
            label: "Show file"
            checked: root.showFile
            onClicked: root.showFile = !root.showFile
        }
    }
    Caption {
        objectName: "status"
        visible: root.mode === "apply" && root.editor !== null
        Layout.fillWidth: true
        color: root.status === "" && root.notice !== "" ? Theme.warning : Theme.textMuted
        text: root.status !== "" ? root.status
            : root.notice !== "" ? root.notice
            : root.lastWrite.length > 0 ? "Undo puts back " + root.lastWrite.map(outcome => root._backups + "/" + outcome.backup).join(", ")
            : "Backups go to " + root._backups
    }

    // The generated files, read-only
    Repeater {
        model: ScriptModel { values: root.showFile && root.mode === "apply" && root.editor !== null ? (root.editor.split ? ["sudo", "polkit-1"] : ["sudo"]) : [] }
        FileBox {
            required property string modelData
            readonly property var planned: root._plannedText(modelData)
            objectName: "preview:" + modelData
            Layout.topMargin: 4
            title: (root.stacks?.directories?.[0] ?? "/etc/pam.d") + "/" + modelData + " — generated, read-only"
                   + (modelData === "sudo" && !root.editor.split ? " (administrator prompts: the same lines)" : "")
            lines: typeof planned === "string" && planned !== "" ? PamRuleViewRules.previewLines(planned)
                 : planned === "" ? [{ text: "polkit's own file, as it comes", kind: "system" }]
                 : [{ text: "No file while a check refuses the rows.", kind: "marker" }]
        }
    }

    // Where the system's configuration sets the rules: the options to paste
    Rectangle {
        readonly property string snippet: root.mode === "copy" && typeof root._preview?.snippet === "string" ? root._preview.snippet : ""
        objectName: "optionsSnippet"
        visible: root.mode === "copy" && root.editor !== null
        Layout.fillWidth: true
        Layout.topMargin: 8
        implicitHeight: _nixColumn.implicitHeight + 20
        radius: Theme.settings.cardRadius
        color: Theme.surfaceSunken
        border.width: Theme.border.width
        border.color: Theme.divider
        ColumnLayout {
            id: _nixColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                Caption { text: root._modeTexts.copyTitle; Layout.fillWidth: true }
                SmallButton {
                    objectName: "copy"
                    label: root.copied ? "Copied" : "Copy"
                    fontSize: Theme.fontSizeSmall
                    available: parent.parent.parent.snippet !== ""
                    onClicked: {
                        root.copyText(parent.parent.parent.snippet);
                        root.copied = true;
                    }
                }
            }
            Text {
                objectName: "snippetText"
                Layout.fillWidth: true
                text: parent.parent.snippet !== "" ? parent.parent.snippet : "No snippet while a check refuses the rows."
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: parent.parent.snippet !== "" ? Theme.textPrimary : Theme.textMuted
            }
        }
    }
    Caption {
        visible: root.mode === "copy" && root.editor !== null && text !== ""
        Layout.fillWidth: true
        text: root._modeTexts.after
    }

    // The lock screen's ways to unlock: the shell's own settings, changed at once
    SectionTitle {
        Layout.fillWidth: true
        Layout.topMargin: 18
        text: "Unlocking the lock screen"
    }
    Hint {
        Layout.bottomMargin: 6
        text: "Which ways the lock screen offers. Changed at once, no password needed."
    }
    Repeater {
        model: ScriptModel { values: ["", "lockscreen.offerFingerprint", "lockscreen.offerSecurityKey"] }
        ColumnLayout {
            id: _unlock
            required property string modelData
            readonly property var row: PamRuleViewRules.unlockRows(root._base, {
                "lockscreen.offerFingerprint": root.settingValue("lockscreen.offerFingerprint"),
                "lockscreen.offerSecurityKey": root.settingValue("lockscreen.offerSecurityKey")
            }, root.integration?.facts ?? null).find(item => item.key === modelData)
            Layout.fillWidth: true
            spacing: 0
            SwitchRow {
                objectName: "unlock:" + _unlock.row.method
                label: PamRuleViewRules.icon(_unlock.row.method) + "  " + _unlock.row.label
                hint: _unlock.row.hint
                checked: _unlock.row.checked
                enabled: _unlock.row.available
                opacity: _unlock.row.available ? 1 : 0.6
                onToggled: if (_unlock.row.available) root.writeSetting(_unlock.row.key, !_unlock.row.checked)
            }
            // What the system's settings let this way do without a key or a touch
            Text {
                objectName: "unlockWarning:" + _unlock.row.method
                visible: _unlock.row.warning !== ""
                Layout.fillWidth: true
                Layout.bottomMargin: 6
                wrapMode: Text.WordWrap
                text: _unlock.row.warning
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
            }
        }
    }
}
