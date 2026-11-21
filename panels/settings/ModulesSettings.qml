import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// System → Modules → Installed (notes/plans/modules-management.md §4): every module as a card,
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
// directory and acts only while they still hold. State and I/O are the host's
// (singletons/ModuleHost.qml): this page reads its statuses and calls setEnabled and confirm.
Item {
    id: root

    anchors.fill: parent

    // The module host shown (a suite gives a stand-in): statuses, icons, apiVersion,
    // dataDirectories, manifestOf(directory), status(id), setEnabled(id, on), confirm(id, directory)
    property var host: Modules.host
    // Where a question that needs more than a button's word is asked (SettingsModalHost)
    property var modalHost: null

    // The card open, by module id
    property string openId: ""
    // A refused action's reason, by module id: shown on its card until the next action there
    property var problems: ({})
    // The subject of the question open in the modal, if this page asked it
    property var _asked: null

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
        }
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

    SettingsPage {
        anchors.fill: parent
        title: "Modules"

        SettingsSection {
            anchor: "installed"
            title: "Installed"
            topMargin: 0
            spacing: 6
            Layout.fillWidth: true

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
                    readonly property var actions: ModuleInstallRules.actionsFor(status, { source: status.source ?? "" }, {
                        runningDependents: disabling.disabled.concat(disabling.unknown).map(id => root.nameOf(id)),
                        needsConfirmation: (status.confirmation ?? []).length > 0
                    })
                    // The main button: Enable or Disable (the held-for-approval's Enable asks in
                    // the consent box, which comes with updates)
                    readonly property var main: actions.row.find(action => action.effect === "enable" || action.effect === "disable") ?? null
                    readonly property var manifest: root.host?.manifestOf?.(status.directory ?? "") ?? null
                    // What a question is about: when it changes, the question goes
                    readonly property string subjectKey: [status.directory, status.state, status.enabled, disabling.disabled.join(",")].join("|")
                    onSubjectKeyChanged: {
                        _disableButton.asking = false;
                        if (root._asked && root._asked.id === modelData)
                            root.modalHost?.withdraw(root._asked);
                    }

                    anchor: "card"
                    Layout.fillWidth: true
                    title: root.nameOf(modelData)
                    subtitle: ModuleInstallRules.cardSubtitle(status)
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

                    // ---- Opened ----

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
                }
            }
        }
    }
}
