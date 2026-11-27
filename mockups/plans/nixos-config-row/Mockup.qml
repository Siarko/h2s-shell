import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons
import qs.components
import qs.panels.settings
import qs.mockups.kit

// Plan: where the NixOS page shows the configuration's folder. Today (the real page,
// NixosSettings) beside the proposal (ProposedPage below, a copy of it with one row at the top:
// "Configuration: <folder>  [Select directory] [Look again]", the Configuration fact gone
// from the table), in three readings: not connected, found (not in force), connected. The
// last scene, nixos-config-row-live, is the proposal working on stand-ins: Select directory
// opens a stand-in folder picker, Look again reads again (a short "Looking…" first), and the
// buttons under the page switch between the three readings. Stand-in data as in
// views/nixos-page. Scenes and wording: MOCKUP.md.
MockupWindow {
    id: root

    contentWidth: 2 * pageWidth + 3 * 16
    contentHeight: 40 + pageHeight + 110

    readonly property int pageWidth: 890
    readonly property int pageHeight: 700
    readonly property bool live: current === "nixos-config-row-live"
    // The reading of a static scene
    readonly property string sceneState: current.startsWith("connected") ? "connected" : current.startsWith("found") ? "found" : "notConnected"

    // ---- Stand-in data ----

    readonly property string fileBefore: JSON.stringify({ version: 1, idle: { hibernateDelay: 3600 } }, null, 2) + "\n"

    // A configuration's reading → NixosConfigRules.reading's shape, with its facts
    function reading(more) {
        const kind = more?.kind ?? "flake";
        const folder = more?.folder ?? "/srv/nixos-config";
        const state = more?.state ?? "connected";
        const fileText = state === "connected" ? fileBefore : "";
        const result = {
            configuration: { found: true, folder, entry: kind === "flake" ? "flake.nix" : "configuration.nix", type: kind },
            real: folder, owner: "root", rootWrites: true, git: kind === "flake" ? "present" : "absent",
            gitKnowsFile: kind === "flake" && state === "connected" ? "tracked" : "", host: "nixos",
            file: fileText === "" ? { path: folder + "/h2s-shell.json", state: "absent", sha256: "" }
                                  : { path: folder + "/h2s-shell.json", state: "present", sha256: PamEditRules.sha256(fileText), text: fileText },
            fileStatus: state === "connected" ? "inForce" : "notCreated",
            module: "present", published: state === "connected" ? "present" : "absent",
            publishedSettings: { system: { idle: { hibernateDelay: "1h" } }, own: { idle: { hibernateDelay: false } } },
            generations: { count: 14, current: 14 }, state, homeWarning: false
        };
        result.facts = NixosConfigRules.facts(result);
        return result;
    }

    // The stand-in folders the picker offers, and what reading each gives
    readonly property var folders: [
        { path: "/etc/nixos", says: "a classic configuration.nix, not connected yet" },
        { path: "/srv/nixos-config", says: "a flake, connected" },
        { path: "/home/alex/Documents", says: "no configuration" }
    ]
    function readingOf(folder) {
        return folder === "/etc/nixos" ? reading({ kind: "classic", folder, state: "found" })
            : folder === "/srv/nixos-config" ? reading({ folder })
            : { configuration: { found: false }, state: "notConnected", facts: [] };
    }
    function readingOfState(state) {
        return readingOf(state === "connected" ? "/srv/nixos-config" : state === "found" ? "/etc/nixos" : "");
    }

    // A reading's I/O as the page asks it (read, current, revision, busy, choose,
    // acknowledgeHome). `delayed`: a read shows "Looking…" for a moment first (the live scene)
    component StandInConfiguration: QtObject {
        id: configuration
        property var value: null
        property string folder: ""
        property int revision: 0
        property bool busy: false
        property bool delayed: false
        property bool _reading: false
        function current() {
            return _reading ? null : value;
        }
        function read() {
            if (!delayed)
                return;
            _reading = true;
            busy = true;
            revision++;
            _pause.restart();
        }
        function choose(chosen, host) {
            folder = chosen;
        }
        function acknowledgeHome(real) {
        }
        function finish() {
            value = root.readingOf(folder);
            _reading = false;
            busy = false;
            revision++;
        }
        // The read's moment: a looping role's time, which the entry does not make instant
        property SequentialAnimation _pause: SequentialAnimation {
            PauseAnimation { duration: Theme.duration("spin") }
            ScriptAction { script: configuration.finish() }
        }
    }
    readonly property QtObject creator: QtObject {
        property bool busy: false
        function create(reading, done) {
            return { started: false, refusal: { text: "Create is not part of this plan." } };
        }
    }

    StandInConfiguration {
        id: _staticConfiguration
        value: root.readingOfState(root.sceneState)
    }
    StandInConfiguration {
        id: _liveConfiguration
        // Shots are taken at once: no "Looking…" moment there
        delayed: !root.shooting
        value: root.readingOf("")
    }

    // The live scene's picker: open while the page waits for a folder
    property var _pickerDone: null
    function pickFolder(start, done) {
        _pickerDone = done;
    }
    function picked(folder) {
        const done = _pickerDone;
        _pickerDone = null;
        done?.(folder === "" ? { paths: [], cancelled: true } : { paths: [folder], cancelled: false });
    }
    function liveSwitch(state) {
        _pickerDone = null;
        _liveConfiguration.folder = state === "connected" ? "/srv/nixos-config" : state === "found" ? "/etc/nixos" : "";
        _liveConfiguration.read();
    }

    onCurrentChanged: if (!live) _pickerDone = null

    // Plan: the NixOS page with the configuration's folder on one row at the top — a copy of
    // panels/settings/NixosSettings.qml (its rebuild line left out) where "Configuration: <folder>"
    // with Select directory and Look again replaces Select directory beside the title, Choose
    // folder… and Look again in the status line, and the Configuration fact. Throwaway.
    component PageLabel: Text {
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textPrimary
        wrapMode: Text.WordWrap
    }

    component ProposedPage: Flickable {
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
        property var copyText: text => {
            Quickshell.clipboardText = text;
        }
        // A folder chooser: `done` gets FileChooser's result ({ paths, cancelled, … })
        property var chooseFolder: (startDirectory, done) => FileChooser.choose({ moduleId: "settings", active: true, name: "Settings" },
            { mode: "folder", title: NixosViewRules.texts.chooserTitle, startDirectory: startDirectory }, done, Quickshell.env("HOME") ?? "/")

        readonly property var reading: (configuration?.revision, configuration?.current() ?? null)
        readonly property var view: NixosViewRules.view(reading, configuration?.busy === true || creator?.busy === true)
        // The facts without the folder, which the row at the top shows
        readonly property var shownFacts: view.facts.filter(row => row.name !== "Configuration")
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
            }
            Hint {
                objectName: "nixos:intro"
                text: NixosViewRules.texts.intro
            }

            // The proposal: the configuration's folder, with its two buttons
            RowLayout {
                objectName: "nixos:configRow"
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 8
                Text {
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textMuted
                    text: "Configuration:"
                }
                Text {
                    objectName: "nixos:configFolder"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: root.reading?.configuration?.found ? Theme.textPrimary : Theme.textMuted
                    text: root.reading?.configuration?.found ? root.reading.configuration.folder
                        : root.view.state === "notConnected" ? "Not found" : "…"
                }
                SmallButton {
                    objectName: "nixos:selectDirectory"
                    label: "Select directory"
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
                        PageLabel {
                            objectName: "nixos:status"
                            Layout.fillWidth: true
                            text: root.view.status.text
                        }
                    }
                    Hint {
                        objectName: "nixos:caption"
                        visible: text !== ""
                        text: root.view.caption
                    }
                    // One fact per line
                    GridLayout {
                        visible: root.shownFacts.length > 0
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 16
                        rowSpacing: 6
                        Repeater {
                            model: ScriptModel {
                                values: root.shownFacts.reduce((keys, row) => keys.concat(["name:" + row.name, "value:" + row.name]), [])
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
                                text: isName ? factName : (root.shownFacts.find(row => row.name === factName)?.value ?? "")
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
                    PageLabel {
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
                    PageLabel { text: "1."; Layout.alignment: Qt.AlignTop }
                    PageLabel {
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
                    PageLabel { text: "2."; Layout.alignment: Qt.AlignTop }
                    PageLabel {
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

        }
    }

    component Caption: Text {
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.textPrimary
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.barBackground
    }

    // ---- The static scenes: today | proposal ----
    Row {
        visible: !root.live
        x: 16
        y: 8
        spacing: 16

        Column {
            spacing: 8
            Caption { text: "Today" }
            Rectangle {
                width: root.pageWidth
                height: root.pageHeight
                color: Theme.popupBackground
                clip: true
                NixosSettings {
                    configuration: _staticConfiguration
                    creator: root.creator
                    copyText: text => {}
                    chooseFolder: (start, done) => {}
                }
            }
        }
        Column {
            spacing: 8
            Caption { text: "Proposal" }
            Rectangle {
                width: root.pageWidth
                height: root.pageHeight
                color: Theme.popupBackground
                clip: true
                ProposedPage {
                    configuration: _staticConfiguration
                    creator: root.creator
                    copyText: text => {}
                    chooseFolder: (start, done) => {}
                }
            }
        }
    }

    // ---- The live scene: the proposal on its own stand-ins ----
    Row {
        visible: root.live
        x: 16
        y: 8
        spacing: 16

        Column {
            spacing: 8
            Caption { text: "Proposal, live" }
            Rectangle {
                width: root.pageWidth
                height: root.pageHeight
                color: Theme.popupBackground
                clip: true
                Loader {
                    anchors.fill: parent
                    // Made when the scene opens, so the page reads on being shown
                    active: root.live
                    sourceComponent: ProposedPage {
                        configuration: _liveConfiguration
                        creator: root.creator
                        copyText: text => {}
                        chooseFolder: (start, done) => root.pickFolder(start, done)
                    }
                }

                // The stand-in folder picker
                Rectangle {
                    visible: root._pickerDone !== null
                    anchors.fill: parent
                    color: Theme.modalDim
                    MouseArea {
                        anchors.fill: parent
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 460
                        height: _picker.implicitHeight + 32
                        radius: Theme.settings.cardRadius
                        color: Theme.surface
                        border.width: Theme.border.width
                        border.color: Theme.outline
                        ColumnLayout {
                            id: _picker
                            x: 16
                            y: 16
                            width: parent.width - 32
                            spacing: 8
                            Caption { text: "Select directory (stand-in picker)" }
                            Repeater {
                                model: root.folders.length
                                SmallButton {
                                    required property int index
                                    Layout.fillWidth: true
                                    label: root.folders[index].path + "  —  " + root.folders[index].says
                                    onClicked: root.picked(root.folders[index].path)
                                }
                            }
                            SmallButton {
                                Layout.alignment: Qt.AlignRight
                                label: "Cancel"
                                onClicked: root.picked("")
                            }
                        }
                    }
                }
            }
        }
        Column {
            spacing: 10
            width: root.pageWidth
            Caption { text: "Switch the reading" }
            Row {
                spacing: 8
                SmallButton { label: "Not connected"; onClicked: root.liveSwitch("notConnected") }
                SmallButton { label: "Found"; onClicked: root.liveSwitch("found") }
                SmallButton { label: "Connected"; onClicked: root.liveSwitch("connected") }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
                text: "Select directory opens a stand-in picker: /etc/nixos is found (not connected yet), /srv/nixos-config is connected, "
                    + "/home/alex/Documents has no configuration. Look again reads the same folder again. Create does nothing here."
            }
        }
    }

    // The note under the page
    Text {
        x: 16
        y: 40 + root.pageHeight + 12
        width: root.contentWidth - 32
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textSecondary
        text: root.descriptions[Array.prototype.indexOf.call(root.names, root.current)] ?? ""
    }
}
