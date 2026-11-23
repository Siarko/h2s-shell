import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.hud
import qs.singletons

// System → Modules → Installed: every module as a card,
// enabled ones first, then the ones turned off, each group by name
// (ModuleInstallRules.listOrder); a copy shadowed by another of its id shows inside the
// winner's card, never as a card of its own. Closed, a card shows the module's icon and name —
// in the accent while it is on, muted while off, its line then ending "· Off" — its marks
// (warnings, deprecated API uses: a count with a tip, no click), a pill only for a state worth
// attention (ModuleInstallRules.pillOf; it takes no click either) and the main button. Opened:
// the description, errors, warnings and deprecations, where it comes from, the API, whether it
// runs administrator actions, its dependencies, programs and data directory.
//
// The main button is ModuleInstallRules.actionsFor's: its label and what it does are one
// decision. "Enable" on a module that is not part of h2s-shell asks the confirmation in the
// Settings modal; "Disable" asks on the button ("Disable?"), or in the modal when running
// modules need it (they are disabled with it). Every question carries the module's id and
// directory and acts only while they still hold. "Remove" (for what the user's modules folder
// holds) asks in a danger modal what the installer's removalPreview says it deletes, with the
// data box and the dependencies left alone unchecked, then calls the installer's remove.
// "Check all" and a card's "Check for updates" run the updater's check — "Checking 2 of 3…",
// "Checking…" on the card being checked, then its result under the name; "Update to x" queues
// the update the check downloaded (updater.update). State and I/O are the host's, the
// installer's and the updater's (singletons/ModuleHost.qml, ModuleInstaller.qml,
// ModuleUpdater.qml): this page reads them and calls them.
Item {
    id: root

    anchors.fill: parent

    // The module host shown (a suite gives a stand-in): statuses, icons, apiVersion,
    // dataDirectories, manifestOf(directory), status(id), setEnabled(id, on), confirm(id, directory)
    property var host: Modules.host
    // The installer (removalPreview(id, directory, done), remove(id, directory, options),
    // jobNumber, finished(result)) and the updater (check(id), update(id), checks, checking,
    // checkingId, checkingIndex, checkingTotal, approvals, queue, automatic)
    property var installer: Modules.installer
    property var updater: Modules.updater
    // Where a question that needs more than a button's word is asked (SettingsModalHost)
    property var modalHost: null
    // The file chooser "Choose folder…" opens (FileChooser) and where it starts
    property var chooser: FileChooser
    property string home: SystemFacts.home ?? ""

    // The install the page started (its job number): one waiting at its preview goes with the
    // page or when the window hides — nobody is left to answer it
    property int _installJob: 0
    readonly property bool _windowShown: Window.window?.visible ?? false
    on_WindowShownChanged: if (!_windowShown) _dropPreview()
    Component.onDestruction: _dropPreview()
    function _dropPreview() {
        if (_installJob !== 0)
            installer?.cancelPreview(_installJob);
    }

    // The side panel: the changelogs of an install's chain ({ title, sections })
    property var _panel: null
    // … closed with the preview it belongs to
    readonly property bool _previewShown: _install.preview !== null
    on_PreviewShownChanged: if (!_previewShown) _panel = null

    // What the installer recorded of the modules it installed (readInstalled's { ok, records,
    // found }), read at the start and after each job — the versions kept, a refused one
    property var _installed: ({ ok: false, records: { modules: {} }, found: {} })
    // Late answers lose: only the answer to the last read started is taken (a read started
    // during a job must not overwrite the one after it)
    property int _readGeneration: 0
    function _readInstalled() {
        const generation = ++_readGeneration;
        installer?.readInstalled?.(read => {
            if (generation === root._readGeneration)
                root._installed = read;
        });
    }
    Component.onCompleted: _followOpenRequest()
    // The modules installed, read each time the page shows (one added or removed meanwhile)
    PageShown {
        onBecameShown: root._readInstalled()
    }
    // A card's open part: "versions" or "backups" (by id), the list it shows
    property var _shownList: ({})
    function _toggleList(id, list) {
        const next = Object.assign({}, _shownList);
        next[id] = next[id] === list ? "" : list;
        _shownList = next;
        if (list === "backups")
            installer?.refreshBackups?.(id);
    }

    // A notification of the updater clicked (updater.openRequest): the restart offer, or the
    // changelogs of the modules it names in the side panel
    Connections {
        target: root.updater
        function onOpenRequested(request) {
            root._followOpenRequest();
        }
    }
    function _followOpenRequest() {
        const request = updater?.openRequest;
        if (!request)
            return;
        updater.openRequest = null;
        if (request.show === "changelog")
            _showChangelogs((request.ids ?? []).filter(id => updater.changelogs?.[id]));
        else if (request.show === "restart")
            Qt.callLater(() => _queueView.restartButton.forceActiveFocus());
    }
    // The updater's changelogs of `ids` in the side panel
    function _showChangelogs(ids) {
        const sections = ids.map(id => {
            const log = updater?.changelogs?.[id] ?? {};
            return { key: id, title: ApiElementRules.oneLine(String(log.name || nameOf(id)), 60) + " " + (log.from ? log.from + " → " : "") + (log.to ?? ""),
                     text: String(log.text ?? "No changelog") };
        });
        if (sections.length > 0)
            _panel = { title: "What's new", sections: sections };
    }

    // Restore: asked in the modal, then said in an informing one
    property var _restoring: null
    function _askRestore(id, backup) {
        const status = statusById[id];
        if (!status || !modalHost)
            return;
        const subject = { id: id, directory: status.directory, backup: backup.name };
        _ask(Object.assign(ModuleUpdateRules.restoreQuestion(nameOf(id), backup, status.version), { subject: subject }), answer => {
            root._asked = null;
            if (answer.cancelled || answer.button !== "restore" || !root._current(answer.subject))
                return;
            const refused = root.installer.restore(answer.subject.id, answer.subject.backup);
            if (refused !== "")
                root._setProblem(answer.subject.id, refused);
            else
                root._restoring = { job: root.installer.jobNumber, id: answer.subject.id, version: backup.version };
        });
    }
    Connections {
        target: root.installer
        function onFinished(result) {
            root._readInstalled();
            if (!root._restoring || result?.job !== root._restoring.job)
                return;
            const restoring = root._restoring;
            root._restoring = null;
            if (result.ok)
                root._ask(ModuleUpdateRules.restoredInfo(root.nameOf(restoring.id), restoring.version), () => root._asked = null);
            else
                root._setProblem(restoring.id, "Could not be restored: " + String(result.message ?? ""));
        }
    }

    // The updates found and downloaded that are not queued or waiting: "Update all (n)"
    readonly property var _updatable: _counted.filter(status => {
        const check = updater?.checks?.[status.id];
        return check?.outcome === "available" && check.downloading !== true && (check.downloadedDir ?? "") !== ""
            && !updater?.approvals?.[status.id] && !_queued.includes(status.id);
    }).map(status => status.id)

    // The card open, by module id
    property string openId: ""
    // A refused action's reason, by module id: shown on its card until the next action there
    property var problems: ({})
    // The subject of the question open in the modal, if this page asked it
    property var _asked: null
    // The remove this page started: { job, id } — its outcome is said on the card
    property var _removing: null
    // Whether "Check all" ran: its summary stays under the title until the next; the results
    // there when it started (an entry the run did not replace is not its result), and why it
    // did not start
    property bool _checkedAll: false
    property var _checksBefore: ({})
    property string _checkAllRefusal: ""

    // The updater's check results of the modules installed from a repository, for "Check
    // all"'s summary
    readonly property var _checkResults: _counted.filter(status => status.source === "repository")
        .map(status => root.updater?.checks?.[status.id])
        .filter(check => check !== undefined && check !== null && !Object.values(root._checksBefore).includes(check))
    // Ids with a row of the update queue that has not ended (no second "Update" for them)
    readonly property var _queued: (updater?.queue?.rows ?? []).filter(row => !["done", "failed", "notFinished"].includes(row.phase)).map(row => row.id)

    Connections {
        target: root.installer
        function onFinished(result) {
            if (!root._removing || result?.job !== root._removing.job)
                return;
            const id = root._removing.id;
            root._removing = null;
            if (result.ok !== true)
                root._setProblem(id, "Could not be removed: " + String(result.message ?? ""));
        }
    }

    readonly property var statuses: host?.statuses ?? []
    readonly property var _counted: statuses.filter(status => status?.state !== "duplicate")
    readonly property var statusById: {
        const byId = {};
        for (const status of _counted)
            if (typeof status?.id === "string" && !(status.id in byId))
                byId[status.id] = status;
        return byId;
    }
    // The copies of each id that another copy shadows
    readonly property var duplicatesById: {
        const byId = {};
        for (const status of statuses.filter(status => status?.state === "duplicate"))
            byId[status.id] = (byId[status.id] ?? []).concat([status]);
        return byId;
    }
    // The modules as the dependency rules read them: with their manifests' uses (null when
    // unknown — such a module may need any other)
    readonly property var dependencyModules: _counted.map(status => ({
        id: status.id, name: status.name, state: status.state, enabled: status.enabled,
        uses: root.host?.manifestOf?.(status.directory)?.uses ?? null
    }))

    // A module's name as it stands in a line: one line, capped
    function nameOf(id) {
        const status = statusById[id];
        return ApiElementRules.oneLine(status?.name || id, ModuleDependencyRules.maxNameLength);
    }

    // The marks' looks: the icon and the colour of each kind (ModuleInstallRules.marks)
    readonly property var _markLooks: ({ warning: { icon: "", tone: "warning" }, deprecation: { icon: "", tone: "textMuted" } })
    // A text from outside in a card's opened part: on one line, capped
    readonly property int _lineCap: 500

    function _setProblem(id, text) {
        const next = Object.assign({}, problems);
        if (text === "")
            delete next[id];
        else
            next[id] = ApiElementRules.oneLine(text, 200);
        problems = next;
    }

    // The status of the module a question was about, while it is still that module (the same
    // directory); null once it went or changed
    function _current(subject) {
        const status = statusById[subject?.id ?? ""] ?? null;
        return status && status.directory === subject.directory ? status : null;
    }

    // An action of actionsFor, from its card
    function act(action, status) {
        if (!action || !status)
            return;
        _setProblem(action.subject.id, "");
        if (action.effect === "enable") {
            if (action.asks === "confirmation")
                _askConfirmation(action.subject, status);
            else if (action.asks === "none")
                _enable(action.subject);
        } else if (action.effect === "disable") {
            if (action.asks === "modal")
                _askDisable(action.subject, status);
            else
                _disable(action.subject, []);
        } else if (action.effect === "remove") {
            _askRemove(action.subject);
        } else if (action.effect === "update") {
            const refused = updater?.update(action.subject.id, action.version) ?? "No updater";
            if (refused !== "")
                _setProblem(action.subject.id, refused);
        } else if (action.effect === "check") {
            _check(action.subject.id);
        }
    }

    // `id` "" — every module installed from a repository
    function _check(id) {
        const before = updater?.checks ?? {};
        const refused = updater?.check(id) ?? "No updater";
        if (id === "") {
            _checkedAll = refused === "";
            _checksBefore = before;
            _checkAllRefusal = ApiElementRules.oneLine(refused, 200);
        } else if (refused !== "") {
            _setProblem(id, refused);
        }
    }

    // Remove: what it deletes is read first (the installer's preview), then asked
    function _askRemove(subject) {
        if (!installer || !modalHost)
            return;
        installer.removalPreview(subject.id, subject.directory, preview => {
            if (!root._current(subject))
                return;
            const question = ModuleInstallRules.removeQuestion(preview);
            if (!question) {
                root._setProblem(subject.id, "Cannot be removed: " + String(preview?.reason ?? ""));
                return;
            }
            root._ask(Object.assign(question, { subject: { id: subject.id, directory: subject.directory, planKey: String(preview.key ?? "") } }), answer => {
                root._asked = null;
                if (answer.cancelled || answer.button !== "remove" || !root._current(answer.subject))
                    return;
                const options = Object.assign(ModuleInstallRules.removeOptions(answer.values), { planKey: answer.subject.planKey });
                const refused = root.installer.remove(answer.subject.id, answer.subject.directory, options);
                if (refused !== "")
                    root._setProblem(answer.subject.id, refused);
                else
                    root._removing = { job: root.installer.jobNumber, id: answer.subject.id };
            });
        });
    }

    function _enable(subject) {
        if (!_current(subject))
            return;
        if (!host.setEnabled(subject.id, true))
            _setProblem(subject.id, "Could not be enabled");
    }

    // `dependents` in ModuleDependencyRules.disableOrder's order: each before what it needs,
    // so none is left running without its provider. One that cannot be turned off stops it:
    // those already turned off go back on, last first, and the card says so
    function _disable(subject, dependents) {
        if (!_current(subject))
            return;
        const done = [];
        for (const id of dependents.concat([subject.id])) {
            if (!host.setEnabled(id, false)) {
                for (const back of done.reverse())
                    host.setEnabled(back, true);
                _setProblem(subject.id, id === subject.id ? "Could not be disabled" : "Could not be disabled: " + nameOf(id) + " could not be turned off");
                return;
            }
            done.push(id);
        }
    }

    function _ask(spec, onAnswer) {
        if (!modalHost)
            return;
        if (modalHost.ask(spec, onAnswer) === "")
            _asked = spec.subject;
    }

    function _askConfirmation(subject, status) {
        _ask(Object.assign(ModuleInstallRules.confirmationQuestion(nameOf(subject.id)), { subject: subject }), answer => {
            root._asked = null;
            if (answer.cancelled || answer.button !== "enable" || !root._current(answer.subject))
                return;
            const refused = root.host.confirm(answer.subject.id, answer.subject.directory);
            if (refused !== "")
                root._setProblem(answer.subject.id, refused);
        });
    }

    function _askDisable(subject, status) {
        const plan = ModuleDependencyRules.disableList(subject.id, dependencyModules);
        const question = ModuleInstallRules.disableQuestion(nameOf(subject.id), plan.disabled.map(nameOf), plan.unknown.map(nameOf));
        const order = ModuleDependencyRules.disableOrder(plan.disabled, dependencyModules);
        _ask(Object.assign(question, { subject: { id: subject.id, directory: subject.directory, dependents: order } }), answer => {
            root._asked = null;
            if (answer.cancelled || answer.button !== "disable" || !root._current(answer.subject))
                return;
            root._disable(answer.subject, answer.subject.dependents);
        });
    }

    KeyedModel { id: _cards; values: ModuleInstallRules.listOrder(root.statuses) }

    // In safe mode, the banner at the top of the page (SafeModeBanner: why, "Load modules")
    Component {
        id: _safeModeBanner
        Item {
            implicitHeight: _banner.implicitHeight + 16
            SafeModeBanner {
                id: _banner
                objectName: "safeModeBanner"
                width: parent.width
                onPage: true
                host: root.host
            }
        }
    }

    SettingsPage {
        anchors.fill: parent
        title: "Modules"
        banner: root.host?.safeMode ? _safeModeBanner : null

        ModuleInstallSection {
            id: _install
            divider: false
            Layout.fillWidth: true
            visible: !(root.host?.safeMode ?? false)
            installer: root.installer
            chooser: root.chooser
            home: root.home
            onChangelogsRequested: (title, sections) => root._panel = { title: title, sections: sections }
            onJobChanged: root._installJob = job
        }

        ModuleUpdateQueue {
            id: _queueView
            divider: _install.visible
            Layout.fillWidth: true
            updater: root.updater
            onRestartRequested: Modules.restartShell()
            onReviewRequested: id => root.openId = id
        }

        SettingsSection {
            anchor: "installed"
            title: "Installed"
            divider: _install.visible || _queueView.visible
            spacing: 6
            Layout.fillWidth: true

            buttons: [
                Text {
                    objectName: "checkAllLine"
                    visible: text !== ""
                    text: root.updater?.checking && root.updater.checkingTotal > 0
                        ? ModuleInstallRules.checkingText(root.updater.checkingIndex, root.updater.checkingTotal)
                        : root._checkAllRefusal !== "" ? root._checkAllRefusal
                        : root._checkedAll ? ModuleInstallRules.checkSummaryText(root._checkResults) : ""
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: root._checkAllRefusal !== "" && !(root.updater?.checking ?? false) ? Theme.error : Theme.textMuted
                },
                SmallButton {
                    objectName: "checkAll"
                    visible: !(root.host?.safeMode ?? false)
                    label: root.updater?.checking ? "Checking…" : "Check all"
                    available: !!root.updater && !root.updater.checking
                    onClicked: root._check("")
                },
                SmallButton {
                    objectName: "updateAll"
                    visible: root._updatable.length > 0 && !(root.updater?.automatic ?? false) && !(root.host?.safeMode ?? false)
                    label: "Update all (" + root._updatable.length + ")"
                    kind: "saveChange"
                    onClicked: {
                        const refused = root.updater.updateAll(root._updatable);
                        root._checkAllRefusal = refused !== "" ? ApiElementRules.oneLine(refused, 200) : "";
                    }
                }
            ]

            // How updates come: by hand, or by themselves once a day
            SchemaSettingEditor {
                objectName: "autoUpdateRow"
                key: "modules.autoUpdate"
                editIndex: 0
                Layout.fillWidth: true
            }

            Text {
                visible: _cards.count === 0
                Layout.fillWidth: true
                text: "No modules found"
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }

            Repeater {
                model: _cards.model
                delegate: SettingsCard {
                    id: card

                    required property string modelData
                    readonly property var status: root.statusById[modelData] ?? ({ id: modelData, state: "" })
                    readonly property bool on: ModuleInstallRules.isOn(status)
                    readonly property var dependencies: ModuleDependencyRules.cardDependencies(modelData, root.dependencyModules)
                    readonly property var disabling: ModuleDependencyRules.disableList(modelData, root.dependencyModules)
                    readonly property var pill: ModuleInstallRules.pillOf(status, { shellApi: root.host?.apiVersion ?? "", missingModule: dependencies.missing })
                    readonly property var check: root.updater?.checks?.[modelData] ?? null
                    readonly property var approval: root.updater?.approvals?.[modelData] ?? null
                    readonly property var updatePill: ModuleInstallRules.updatePillOf(check, approval)
                    readonly property var checkLine: ModuleInstallRules.checkLineOf(check, root.updater?.checking === true && root.updater.checkingId === modelData)
                    // Remove is offered from the status's place in the modules folder; what it
                    // deletes the installer reads on disk
                    readonly property var actions: ModuleInstallRules.actionsFor(status, { source: status.source ?? "", entry: status.entry ?? "" }, {
                        runningDependents: disabling.disabled.concat(disabling.unknown).map(id => root.nameOf(id)),
                        needsConfirmation: (status.confirmation ?? []).length > 0,
                        // Downloaded and not queued or waiting for approval: "Update to x"
                        update: check?.outcome === "available" && check.downloading !== true && (check.downloadedDir ?? "") !== ""
                                && approval === null && !root._queued.includes(modelData) ? { version: check.version, downloaded: true } : null,
                        autoUpdate: root.updater?.automatic === true
                    })
                    readonly property var updateAction: actions.row.find(action => action.effect === "update") ?? null
                    readonly property var removeAction: actions.row.find(action => action.effect === "remove") ?? null
                    readonly property var checkAction: actions.opened.find(action => action.effect === "check") ?? null
                    // The main button: Enable or Disable (the held-for-approval's Enable asks in
                    // the consent box, which comes with updates)
                    readonly property var main: actions.row.find(action => action.effect === "enable" || action.effect === "disable") ?? null
                    readonly property var manifest: root.host?.manifestOf?.(status.directory ?? "") ?? null
                    // The versions kept and on the server ("Switch version…"), the refused one
                    readonly property var record: root._installed.records?.modules?.[modelData] ?? null
                    readonly property var versions: record ? ModuleUpdateRules.versionList(record, root.updater?.listings?.[modelData]?.tags ?? [],
                                                                                         root.updater?.listings?.[modelData]?.head ?? null)
                                                           : ({ ok: false, kept: [], tags: [], more: 0, head: null })
                    readonly property var refusedVersion: versions.kept.find(entry => entry.state === "notFinished") ?? null
                    readonly property var consent: approval ? ModuleUpdateRules.consentBox(approval, root.nameOf(modelData), status.version) : null
                    readonly property var changelog: root.updater?.changelogs?.[modelData] ?? null
                    readonly property var backups: root.installer?.backupLists?.[modelData]?.backups ?? []
                    readonly property string shownList: root._shownList[modelData] ?? ""
                    // What a question is about: when it changes, the question goes
                    readonly property string subjectKey: [status.directory, status.state, status.enabled, disabling.disabled.join(","),
                                                          refusedVersion?.dir ?? ""].join("|")
                    onSubjectKeyChanged: {
                        _disableButton.asking = false;
                        _deleteNewButton.asking = false;
                        if (root._asked && root._asked.id === modelData)
                            root.modalHost?.withdraw(root._asked);
                    }

                    anchor: "card"
                    Layout.fillWidth: true
                    title: root.nameOf(modelData)
                    subtitle: ModuleInstallRules.cardSubtitle(status)
                    detail: checkLine.text
                    detailColor: Theme[checkLine.tone]
                    titleColor: on ? Theme.accent : Theme.textMuted
                    titleBold: on
                    open: root.openId === modelData
                    notice: root.problems[modelData] ?? ""
                    context: ({ moduleId: modelData })
                    onToggleRequested: root.openId = open ? "" : modelData

                    leading: ModuleIcon {
                        moduleId: card.modelData
                        host: root.host
                        color: card.titleColor
                    }

                    // Marks: a count each, its tip on hover; no click
                    titleItems: Repeater {
                        model: _marks.model
                        Item {
                            id: _mark

                            required property string modelData
                            readonly property var mark: _marks.byKey[modelData] ?? ({ kind: "", count: 0, tip: "" })
                            readonly property var look: root._markLooks[mark.kind] ?? { icon: "", tone: "textMuted" }
                            objectName: "mark"
                            implicitWidth: _markRow.implicitWidth
                            implicitHeight: _markRow.implicitHeight

                            Row {
                                id: _markRow
                                spacing: 3

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: _mark.look.icon
                                    textFormat: Text.PlainText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme[_mark.look.tone]
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String(_mark.mark.count)
                                    textFormat: Text.PlainText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme[_mark.look.tone]
                                }
                            }

                            // A mark takes no click: it stops here, short of the header that
                            // opens the card
                            PointerArea {
                                centred: false
                                anchors.fill: parent
                                cursorShape: Qt.ArrowCursor
                            }
                            HoverHandler { id: _markHover }
                            HoverTip {
                                target: _mark
                                shown: _markHover.hovered
                                text: _mark.mark.tip
                            }
                        }
                    }
                    KeyedModel { id: _marks; values: ModuleInstallRules.marks(card.status); keyProp: "kind" }

                    primary: [
                        StatusPill {
                            objectName: "statePill"
                            visible: card.pill !== null
                            expandable: false
                            label: card.pill?.label ?? ""
                            kind: card.pill?.kind ?? "muted"
                        },
                        StatusPill {
                            objectName: "updatePill"
                            visible: card.updatePill !== null
                            expandable: false
                            label: card.updatePill?.label ?? ""
                            kind: card.updatePill?.kind ?? "muted"
                        },
                        SmallButton {
                            objectName: "updateButton"
                            visible: card.updateAction !== null
                            label: card.updateAction?.label ?? ""
                            kind: "saveChange"
                            onClicked: root.act(card.updateAction, card.status)
                        },
                        SmallButton {
                            objectName: "mainButton"
                            visible: card.main !== null && card.main.asks !== "button" && card.main.asks !== "approval"
                            label: card.main?.label ?? ""
                            kind: card.main?.effect === "disable" ? "warning" : card.main?.asks === "confirmation" ? "save" : "normal"
                            onClicked: root.act(card.main, card.status)
                        },
                        DeleteButton {
                            id: _disableButton
                            objectName: "disableButton"
                            visible: card.main !== null && card.main.asks === "button"
                            kind: "warning"
                            label: card.main?.label ?? ""
                            confirmLabel: "Disable?"
                            fontSize: Theme.fontSizeBody
                            onConfirmed: root.act(card.main, card.status)
                        }
                    ]
                    lastButtons: SmallButton {
                        objectName: "removeButton"
                        visible: card.removeAction !== null
                        label: card.removeAction?.label ?? ""
                        kind: "delete"
                        available: root._removing === null
                        onClicked: root.act(card.removeAction, card.status)
                    }

                    // ---- Opened ----

                    // The consent box: the update waits for the user's approval, keyed to the
                    // version directory it was asked about
                    Rectangle {
                        objectName: "consentBox"
                        visible: card.consent !== null
                        Layout.fillWidth: true
                        implicitHeight: visible ? _consentColumn.implicitHeight + 24 : 0
                        radius: Theme.settings.cardRadius
                        color: Qt.alpha(Theme.warning, 0.10)
                        border.width: Theme.border.width
                        border.color: Theme.warning
                        ColumnLayout {
                            id: _consentColumn
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 6
                            // Each reason's line, the first bold, and its detail under it
                            KeyedModel {
                                id: _consentLines
                                values: [].concat(...(card.consent?.lines ?? []).map((line, index) =>
                                    [{ key: index + "t", text: line.text, strong: index === 0 }].concat(line.detail ? [{ key: index + "d", text: line.detail, strong: false }] : [])))
                                keyProp: "key"
                            }
                            Repeater {
                                model: _consentLines.model
                                Text {
                                    required property string modelData
                                    readonly property var line: _consentLines.byKey[modelData] ?? ({ text: "", strong: false })
                                    objectName: "consentLine"
                                    Layout.fillWidth: true
                                    text: line.text
                                    textFormat: Text.PlainText
                                    wrapMode: Text.Wrap
                                    font.family: Theme.fontFamily
                                    font.pixelSize: line.strong ? Theme.fontSizeBody : Theme.fontSizeSmall
                                    font.bold: line.strong
                                    color: line.strong ? Theme.textPrimary : Theme.textSecondary
                                }
                            }
                            Text {
                                visible: !!card.consent?.trust
                                Layout.fillWidth: true
                                text: card.consent?.trust ? card.consent.trust.title + " " + card.consent.trust.text : ""
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.textSecondary
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                SmallButton {
                                    objectName: "consentUpdate"
                                    label: card.consent?.updateLabel ?? ""
                                    kind: "save"
                                    onClicked: {
                                        const refused = root.updater.approve(card.modelData, card.consent.subject.dir);
                                        if (refused !== "")
                                            root._setProblem(card.modelData, refused);
                                    }
                                }
                                SmallButton {
                                    objectName: "consentKeep"
                                    label: card.consent?.keepLabel ?? ""
                                    kind: "cancel"
                                    onClicked: {
                                        const refused = root.updater.refuse(card.modelData, card.consent.subject.dir);
                                        if (refused !== "")
                                            root._setProblem(card.modelData, refused);
                                    }
                                }
                                SmallButton {
                                    visible: card.changelog !== null
                                    label: "What's new"
                                    onClicked: root._showChangelogs([card.modelData])
                                }
                            }
                        }
                    }

                    // A refused update: the old version runs; the new one can be deleted
                    Rectangle {
                        objectName: "notFinishedBox"
                        visible: card.refusedVersion !== null && card.consent === null
                        readonly property var words: ModuleUpdateRules.notFinishedText(card.refusedVersion?.version ?? "", card.status.version ?? "")
                        Layout.fillWidth: true
                        implicitHeight: visible ? _notFinishedColumn.implicitHeight + 24 : 0
                        radius: Theme.settings.cardRadius
                        color: Qt.alpha(Theme.warning, 0.10)
                        border.width: Theme.border.width
                        border.color: Theme.warning
                        ColumnLayout {
                            id: _notFinishedColumn
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 6
                            Text {
                                objectName: "notFinishedTitle"
                                Layout.fillWidth: true
                                text: parent.parent.words.title
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.warning
                            }
                            Text {
                                Layout.fillWidth: true
                                text: parent.parent.words.detail
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.textSecondary
                            }
                            DeleteButton {
                                id: _deleteNewButton
                                objectName: "deleteNewVersion"
                                label: parent.parent.words.deleteLabel
                                confirmLabel: parent.parent.words.deleteQuestion
                                fontSize: Theme.fontSizeBody
                                onConfirmed: {
                                    const refused = root.installer.deleteVersion(card.modelData, card.refusedVersion.dir);
                                    if (refused !== "")
                                        root._setProblem(card.modelData, refused);
                                }
                            }
                        }
                    }

                    Text {
                        visible: text !== ""
                        Layout.fillWidth: true
                        text: ApiElementRules.oneLine(card.status.description ?? "", root._lineCap)
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textSecondary
                    }

                    // Errors, warnings and deprecations, one per line, as written
                    Repeater {
                        model: _lines.model
                        RowLayout {
                            id: _line

                            required property string modelData
                            readonly property var line: _lines.byKey[modelData] ?? ({ kind: "muted", text: "" })
                            readonly property string tone: line.kind === "danger" ? "error" : line.kind === "warning" ? "warning" : "textMuted"
                            objectName: "statusLine"
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                Layout.alignment: Qt.AlignTop
                                text: _line.line.kind === "danger" ? "" : _line.line.kind === "warning" ? "" : ""
                                textFormat: Text.PlainText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme[_line.tone]
                            }
                            Text {
                                objectName: "statusLineText"
                                Layout.fillWidth: true
                                text: _line.line.text
                                textFormat: Text.PlainText
                                wrapMode: Text.WrapAnywhere
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme[_line.tone]
                            }
                        }
                    }
                    KeyedModel {
                        id: _lines
                        values: [].concat((card.status.errors ?? []).map(text => ({ kind: "danger", text: text })),
                                          (card.status.warnings ?? []).map(text => ({ kind: "warning", text: text })),
                                          (card.status.deprecations ?? []).map(text => ({ kind: "muted", text: text })))
                                  .map((line, index) => ({ key: String(index), kind: line.kind, text: ApiElementRules.oneLine(String(line.text ?? ""), root._lineCap) }))
                        keyProp: "key"
                    }

                    DetailRow {
                        label: "Source"
                        value: [card.status.sourceLabel ?? "", card.status.directory ?? ""].filter(part => part !== "").join("\n")
                    }
                    DetailRow {
                        label: "Replaces"
                        value: [ModuleInstallRules.replacesText(card.status.replaces ?? [])]
                            .concat((root.duplicatesById[card.modelData] ?? []).map(copy => copy.directory ?? ""))
                            .filter(part => part !== "").join("\n")
                    }
                    DetailRow {
                        label: "Installed for"
                        value: card.status.installedFor ? root.nameOf(card.status.installedFor) : ""
                    }
                    DetailRow {
                        label: "API"
                        value: (card.status.api ? "asks for " + card.status.api + " · " : "") + "this shell has " + (root.host?.apiVersion ?? "")
                    }
                    DetailRow {
                        label: "Administrator"
                        value: card.manifest?.privileged
                            ? "asks for your password to: " + ApiElementRules.oneLine(String(card.manifest.privileged.why ?? ""), 200)
                            : "never asks"
                    }
                    DetailRow { label: "Needs"; value: card.dependencies.needs.join("\n") }
                    DetailRow { label: "Can use"; value: card.dependencies.canUse.join("\n") }
                    DetailRow { label: "Used by"; value: card.dependencies.usedBy.join(", ") }
                    DetailRow {
                        label: "Programs"
                        value: Array.from(new Set((card.manifest?.programs ?? []).concat(card.manifest?.optionalPrograms ?? [])))
                            .map(name => name + ((card.status.missingPrograms ?? []).includes(name) ? " — not found" : "")).join(", ")
                    }
                    DetailRow {
                        label: "Setup"
                        value: (card.status.setupHints ?? []).map(hint => ApiElementRules.oneLine(String(hint ?? ""), root._lineCap)).join("\n")
                    }
                    DetailRow {
                        label: "Data"
                        value: root.host?.dataDirectories?.[card.modelData] ?? ""
                    }

                    // The opened card's buttons
                    // Switch version: the kept versions (instant), the server's tags and branch
                    // head (downloaded when chosen)
                    Rectangle {
                        objectName: "versionList"
                        visible: card.shownList === "versions"
                        Layout.fillWidth: true
                        implicitHeight: visible ? _versionColumn.implicitHeight + 16 : 0
                        radius: Theme.settings.cardRadius
                        color: Theme.surfaceSunken
                        KeyedModel {
                            id: _versionRows
                            values: card.versions.kept.concat(card.versions.tags, card.versions.head ? [card.versions.head] : [])
                                .map(entry => Object.assign({ key: entry.kind + ":" + (entry.dir || entry.ref) }, entry))
                            keyProp: "key"
                        }
                        ColumnLayout {
                            id: _versionColumn
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            spacing: 4
                            Text {
                                text: "Switch version — settings and data stay, backed up first"
                                textFormat: Text.PlainText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.textMuted
                            }
                            Repeater {
                                model: _versionRows.model
                                RowLayout {
                                    id: _versionRow
                                    required property string modelData
                                    readonly property var entry: _versionRows.byKey[modelData] ?? ({ kind: "", label: "", state: "" })
                                    objectName: "versionRow"
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        objectName: "versionLabel"
                                        Layout.fillWidth: true
                                        text: _versionRow.entry.label + (_versionRow.entry.kind === "kept" ? "" : " — from the server, downloaded when chosen")
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: _versionRow.entry.state === "active"
                                        color: _versionRow.entry.state === "active" ? Theme.textPrimary : Theme.textSecondary
                                    }
                                    SmallButton {
                                        objectName: "versionButton"
                                        visible: _versionRow.entry.state !== "active" && _versionRow.entry.state !== "notFinished"
                                        label: _versionRow.entry.kind === "kept" ? "Switch" : "Download"
                                        available: !(root.installer?.busy ?? true)
                                        onClicked: {
                                            const entry = _versionRow.entry;
                                            const refused = entry.kind === "kept" ? root.installer.switchVersion(card.modelData, entry.dir)
                                                                                  : root.installer.fetchUpdate(card.modelData, entry.ref);
                                            if (refused !== "")
                                                root._setProblem(card.modelData, refused);
                                        }
                                    }
                                }
                            }
                            Text {
                                visible: card.versions.more > 0
                                text: card.versions.more + " older tags not listed"
                                textFormat: Text.PlainText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.textMuted
                            }
                        }
                    }

                    // Configuration backups: one before every update or switch
                    Rectangle {
                        objectName: "backupList"
                        visible: card.shownList === "backups"
                        Layout.fillWidth: true
                        implicitHeight: visible ? _backupColumn.implicitHeight + 16 : 0
                        radius: Theme.settings.cardRadius
                        color: Theme.surfaceSunken
                        KeyedModel { id: _backupRows; values: card.backups; keyProp: "name" }
                        ColumnLayout {
                            id: _backupColumn
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            spacing: 4
                            Text {
                                text: card.backups.length > 0 ? "Settings backups — one before every update or switch" : "No backups yet"
                                textFormat: Text.PlainText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.textMuted
                            }
                            Repeater {
                                model: _backupRows.model
                                RowLayout {
                                    id: _backupRow
                                    required property string modelData
                                    readonly property var backup: _backupRows.byKey[modelData] ?? ({ name: "", version: "" })
                                    objectName: "backupRow"
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        Layout.preferredWidth: 90
                                        text: _backupRow.backup.version
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.textPrimary
                                    }
                                    Text {
                                        objectName: "backupText"
                                        Layout.fillWidth: true
                                        text: ModuleUpdateRules.backupRowText(_backupRow.backup)
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.textSecondary
                                    }
                                    SmallButton {
                                        objectName: "restoreButton"
                                        label: "Restore"
                                        available: !(root.installer?.busy ?? true)
                                        onClicked: root._askRestore(card.modelData, _backupRow.backup)
                                    }
                                }
                            }
                        }
                    }

                    Flow {
                        visible: card.checkAction !== null || card.changelog !== null || card.record !== null
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 6
                        SmallButton {
                            objectName: "whatsNewButton"
                            visible: card.changelog !== null
                            label: "What's new"
                            onClicked: root._showChangelogs([card.modelData])
                        }
                        SmallButton {
                            objectName: "switchVersionButton"
                            visible: card.record !== null
                            label: "Switch version…"
                            checked: card.shownList === "versions"
                            onClicked: root._toggleList(card.modelData, "versions")
                        }
                        SmallButton {
                            objectName: "backupsButton"
                            visible: card.record !== null
                            label: "Backups…"
                            checked: card.shownList === "backups"
                            onClicked: root._toggleList(card.modelData, "backups")
                        }
                        SmallButton {
                            objectName: "checkButton"
                            label: root.updater?.checking === true && root.updater.checkingId === card.modelData ? "Checking…" : (card.checkAction?.label ?? "")
                            visible: card.checkAction !== null
                            available: !!root.updater && !root.updater.checking
                            onClicked: root.act(card.checkAction, card.status)
                        }
                    }
                }
            }
        }
    }

    // "What's new": each changelog of the chain, plain text, in the standard side panel
    KeyedModel { id: _panelSections; values: root._panel?.sections ?? []; keyProp: "key" }
    Component {
        id: _changelogComp
        ColumnLayout {
            spacing: 12
            Repeater {
                model: _panelSections.model
                ColumnLayout {
                    id: _section
                    required property string modelData
                    readonly property var section: _panelSections.byKey[modelData] ?? ({ title: "", text: "" })
                    objectName: "changelogSection"
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: _section.section.title
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        font.bold: true
                        color: Theme.textPrimary
                    }
                    Text {
                        objectName: "changelogText"
                        Layout.fillWidth: true
                        text: _section.section.text
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textSecondary
                    }
                }
            }
        }
    }
    SideDrawer {
        id: _drawer
        objectName: "changelogPanel"
        anchors.fill: parent
        open: root._panel !== null
        title: root._panel?.title ?? ""
        content: _changelogComp
        onRequested: event => root._panel = null
    }
}
