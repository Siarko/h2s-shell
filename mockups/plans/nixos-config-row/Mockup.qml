import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons
import qs.components
import qs.panels.settings
import qs.mockups.kit

// Plan: where the NixOS page shows the configuration's folder, as the owner decided it and
// as the real page (NixosSettings) now draws it: under the status, always, the folder (or the
// folders looked in while none is found) with Select directory, the page's one folder button;
// no Configuration fact. Three readings: not connected, found (not in force), connected. The
// last scene, nixos-config-row-live, is the real page working on stand-ins: Select directory
// opens a stand-in folder picker, Look again reads again (a short "Looking…" first), and the
// buttons beside the page switch between the three readings. Stand-in data as in
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
            : { configuration: { found: false }, state: "notConnected", facts: [], searched: [folder === "" ? "/etc/nixos" : folder] };
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

    // ---- The static scenes: the real page, as decided ----
    Column {
        visible: !root.live
        x: 16
        y: 8
        spacing: 8
        Caption { text: "The page as decided (the real NixosSettings)" }
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

    // ---- The live scene: the proposal on its own stand-ins ----
    Row {
        visible: root.live
        x: 16
        y: 8
        spacing: 16

        Column {
            spacing: 8
            Caption { text: "Live: the real page on stand-ins" }
            Rectangle {
                width: root.pageWidth
                height: root.pageHeight
                color: Theme.popupBackground
                clip: true
                Loader {
                    anchors.fill: parent
                    // Made when the scene opens, so the page reads on being shown
                    active: root.live
                    sourceComponent: NixosSettings {
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
