import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// System → NixOS, listed only on NixOS: the system's NixOS configuration as the shell reads
// it (Nixos.configuration) — where it is, its facts one per line, whether the shell's file is
// in force — and the one-time setup that connects it: Create of the shell's file
// (Nixos.creator: the password asked only at that click, for a root-owned configuration), the
// line to add once, with Copy. A configuration in the user's own folder shows its warning
// once. What is shown for which reading is NixosViewRules'. Read when the page shows and on
// "Look again"; Change… picks another folder.
Flickable {
    id: root

    anchors.fill: parent
    contentWidth: width
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
    flickableDirection: Flickable.VerticalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    // The I/O, handed in by a suite as stand-ins: the reading (read, current, revision, busy,
    // choose, acknowledgeHome) and Create (create, busy)
    property var configuration: Nixos.configuration
    property var creator: Nixos.creator
    // The window's way to the rebuild (NixosRebuildFlow): the run's line, Show, Undo
    property var flow: null
    property var copyText: text => {
        Quickshell.clipboardText = text;
    }
    // A folder chooser: `done` gets FileChooser's result ({ paths, cancelled, … })
    property var chooseFolder: (startDirectory, done) => FileChooser.choose({ moduleId: "settings", active: true, name: "Settings" },
        { mode: "folder", title: NixosViewRules.texts.chooserTitle, startDirectory: startDirectory }, done, Quickshell.env("HOME") ?? "/")

    readonly property var reading: (configuration?.revision, configuration?.current() ?? null)
    readonly property var view: NixosViewRules.view(reading, configuration?.busy === true || creator?.busy === true)
    readonly property var _rebuild: flow?.rebuild ?? null
    readonly property var _rebuildState: _rebuild?.state ?? NixosRebuildRules.initial()
    // The run's clock: once a second while a build counts and the page shows
    property real _now: _rebuild?.clock?.() ?? 0
    readonly property bool _counting: NixosRebuildViewRules.counting(_rebuildState) && root.visible && (root.Window.window?.visible ?? false)
    on_CountingChanged: if (_counting) _now = _rebuild?.clock?.() ?? 0
    Timer {
        interval: 1000
        repeat: true
        running: root._counting
        onTriggered: root._now = root._rebuild?.clock?.() ?? 0
    }
    readonly property var rebuildLine: NixosRebuildViewRules.pageLine(_rebuildState, _rebuild?.times ?? null, _now)
    readonly property bool undoOffered: NixosRebuildViewRules.canUndo(_rebuildState)
    // What the last Create said ("" nothing)
    property string createNote: ""
    property bool copied: false

    PageShown {
        onBecameShown: root.lookAgain()
    }

    function lookAgain() {
        root.configuration?.read();
    }

    function create() {
        const shown = reading;
        createNote = "";
        const started = creator?.create(shown, outcome => {
            if (outcome.ok)
                root.lookAgain();
            else if (!outcome.quiet)
                root.createNote = outcome.error;
        });
        if (started && !started.started)
            createNote = started.refusal?.text ?? "";
    }

    function change() {
        const start = reading?.configuration?.found ? reading.configuration.folder : "";
        chooseFolder(start, result => {
            const folder = result?.paths?.[0] ?? "";
            if (result?.cancelled || folder === "")
                return;
            root.configuration?.choose(folder, "");
            root.lookAgain();
        });
    }

    function useHome() {
        const real = reading?.real ?? "";
        if (real === "")
            return;
        root.configuration?.acknowledgeHome(real);
        root.lookAgain();
    }

    function copyLine() {
        copyText(view.setup.line);
        copied = true;
    }

    function _tone(tone) {
        return tone === "success" ? Theme.success : tone === "warning" ? Theme.warning : tone === "error" ? Theme.error
            : tone === "accent" ? Theme.accent : tone === "privileged" ? Theme.privileged : Theme.textMuted;
    }

    component Label: Text {
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textPrimary
        wrapMode: Text.WordWrap
    }

    ColumnLayout {
        id: _column
        x: Theme.settings.pageMargin
        y: Theme.settings.pageMargin
        width: root.width - 2 * Theme.settings.pageMargin
        spacing: 0

        Heading {
            text: "NixOS"
            Layout.bottomMargin: 4
        }

        SectionTitle {
            Layout.fillWidth: true
            divider: false
            text: NixosViewRules.texts.title
            SmallButton {
                objectName: "nixos:change"
                visible: root.view.change
                label: "Change…"
                fontSize: Theme.fontSizeSmall
                onClicked: root.change()
            }
        }
        Hint {
            objectName: "nixos:intro"
            text: NixosViewRules.texts.intro
        }

        // The state and the facts
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 10
            implicitHeight: _facts.implicitHeight + 20
            radius: Theme.settings.cardRadius
            color: Theme.fillSubtle
            border.width: Theme.border.width
            border.color: root.view.status.tone === "warning" ? Theme.warning : Theme.outline

            ColumnLayout {
                id: _facts
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; leftMargin: 12; rightMargin: 12 }
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 5
                        implicitWidth: 10
                        implicitHeight: 10
                        radius: 5
                        color: root._tone(root.view.status.tone)
                    }
                    Label {
                        objectName: "nixos:status"
                        Layout.fillWidth: true
                        text: root.view.status.text
                    }
                    SmallButton {
                        objectName: "nixos:chooseFolder"
                        visible: root.view.chooseFolder
                        label: "Choose folder…"
                        fontSize: Theme.fontSizeSmall
                        onClicked: root.change()
                    }
                    SmallButton {
                        objectName: "nixos:lookAgain"
                        visible: root.view.lookAgain.shown
                        available: root.view.lookAgain.available
                        label: "Look again"
                        fontSize: Theme.fontSizeSmall
                        onClicked: root.lookAgain()
                    }
                }
                Hint {
                    objectName: "nixos:caption"
                    visible: text !== ""
                    text: root.view.caption
                }
                // One fact per line
                GridLayout {
                    visible: root.view.facts.length > 0
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 16
                    rowSpacing: 6
                    Repeater {
                        model: ScriptModel {
                            values: root.view.facts.reduce((keys, row) => keys.concat(["name:" + row.name, "value:" + row.name]), [])
                        }
                        Text {
                            required property string modelData
                            readonly property bool isName: modelData.startsWith("name:")
                            readonly property string factName: modelData.slice(modelData.indexOf(":") + 1)
                            objectName: isName ? "" : "nixos:fact:" + factName
                            Layout.fillWidth: !isName
                            Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                            Layout.topMargin: isName ? 2 : 0
                            textFormat: Text.PlainText
                            font.family: Theme.fontFamily
                            font.pixelSize: isName ? Theme.fontSizeSmall : Theme.fontSizeBody
                            color: isName ? Theme.textMuted : Theme.textPrimary
                            wrapMode: isName ? Text.NoWrap : Text.WrapAnywhere
                            text: isName ? factName : (root.view.facts.find(row => row.name === factName)?.value ?? "")
                        }
                    }
                }
                Hint {
                    objectName: "nixos:generations"
                    visible: root.view.generationsShown
                    text: NixosViewRules.texts.generations
                }
            }
        }

        // The home folder's warning, once
        Rectangle {
            objectName: "nixos:home"
            visible: root.view.home
            Layout.fillWidth: true
            Layout.topMargin: 8
            implicitHeight: _home.implicitHeight + 20
            radius: Theme.settings.cardRadius
            color: Qt.alpha(Theme.warning, 0.12)
            border.width: Theme.border.width
            border.color: Theme.warning

            ColumnLayout {
                id: _home
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 6
                Label {
                    Layout.fillWidth: true
                    text: String.fromCodePoint(0xF071) + "  " + NixosViewRules.texts.homeTitle
                }
                Hint {
                    text: NixosViewRules.texts.homeBody
                }
                RowLayout {
                    spacing: 6
                    SmallButton {
                        objectName: "nixos:useIt"
                        label: "Use it"
                        kind: "save"
                        fontSize: Theme.fontSizeSmall
                        onClicked: root.useHome()
                    }
                    SmallButton {
                        objectName: "nixos:chooseAnother"
                        label: "Choose another…"
                        fontSize: Theme.fontSizeSmall
                        onClicked: root.change()
                    }
                }
            }
        }

        // The one-time setup
        ColumnLayout {
            objectName: "nixos:setup"
            visible: root.view.setup.shown
            Layout.fillWidth: true
            Layout.topMargin: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: "1."; Layout.alignment: Qt.AlignTop }
                Label {
                    objectName: "nixos:createStep"
                    Layout.fillWidth: true
                    text: root.view.setup.step
                    color: root.view.setup.stepDone ? Theme.textMuted : Theme.textPrimary
                }
                PrivilegedMark {
                    objectName: "nixos:createMark"
                    visible: root.view.setup.create.shown && root.view.setup.create.privileged
                }
                SmallButton {
                    objectName: "nixos:create"
                    visible: root.view.setup.create.shown
                    available: root.view.setup.create.available
                    label: "Create"
                    kind: "save"
                    fontSize: Theme.fontSizeSmall
                    tooltip: root.view.setup.create.tooltip
                    onClicked: root.create()
                }
            }
            Hint {
                objectName: "nixos:createNote"
                visible: text !== ""
                Layout.leftMargin: 26
                color: Theme.warning
                text: root.createNote
            }
            Hint {
                objectName: "nixos:git"
                visible: root.view.setup.git
                Layout.leftMargin: 26
                text: NixosViewRules.texts.git
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: "2."; Layout.alignment: Qt.AlignTop }
                Label {
                    Layout.fillWidth: true
                    text: NixosViewRules.texts.lineStep
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 26
                implicitHeight: _line.implicitHeight + 20
                radius: Theme.settings.cardRadius
                color: Theme.surfaceSunken
                border.width: Theme.border.width
                border.color: Theme.divider
                RowLayout {
                    id: _line
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    Text {
                        objectName: "nixos:line"
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textPrimary
                        text: root.view.setup.line
                    }
                    SmallButton {
                        objectName: "nixos:copy"
                        label: root.copied ? "Copied" : "Copy"
                        fontSize: Theme.fontSizeSmall
                        onClicked: root.copyLine()
                    }
                }
            }
            Hint {
                Layout.leftMargin: 26
                objectName: "nixos:lineCaption"
                text: root.view.setup.lineCaption
            }
        }

        // The rebuild's line: where the run is, Show (the panel), Undo of the last Apply
        RowLayout {
            objectName: "nixos:rebuild"
            visible: root.flow !== null && (root.rebuildLine.shown || root.undoOffered)
            Layout.fillWidth: true
            Layout.topMargin: 14
            spacing: 8
            Rectangle {
                visible: root.rebuildLine.shown
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 5
                implicitWidth: 10
                implicitHeight: 10
                radius: 5
                color: root._tone(root.rebuildLine.tone)
            }
            Label {
                objectName: "nixos:rebuildLine"
                Layout.fillWidth: true
                text: root.rebuildLine.text
            }
            SmallButton {
                objectName: "nixos:rebuildShow"
                visible: root.rebuildLine.shown && !(root.flow?.panelOpen ?? false)
                label: "Show"
                fontSize: Theme.fontSizeSmall
                onClicked: root.flow.showPanel()
            }
            SmallButton {
                objectName: "nixos:undo"
                visible: root.undoOffered
                label: "Undo"
                fontSize: Theme.fontSizeSmall
                tooltip: "Puts back the shell's previous settings and rebuilds"
                onClicked: root.flow.undo()
            }
        }
        Hint {
            objectName: "nixos:rebuildNote"
            visible: root.flow !== null && text !== "" && !(root.flow?.panelOpen ?? false)
            color: Theme.warning
            text: root.flow?.note ?? ""
        }
    }
}
