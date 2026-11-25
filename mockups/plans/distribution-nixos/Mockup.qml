import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons
import qs.components
import qs.panels.settings
import qs.mockups.kit

// Applying a setting on NixOS, planned: Settings → System's section "NixOS configuration"
// (where the configuration is, the host, connected or not, the one-time line), one setting
// that applies through it (the hibernation delay, from Behaviour → When away), the Settings
// modal announcing the build, the build's side panel (components/SideDrawer.qml) and the
// password step after it. The shell's real theme and components on stand-in data: nothing
// reads the system, nothing runs nix or pkexec; every button changes the stand-in state only.
//
// A plan: it runs only when named (tests/run-mockups.sh plans/distribution-nixos).
// On screen the kit's scene buttons set up a moment; from there Apply, Build, Cancel, the
// password card, Undo and Copy work on the stand-ins, and a stand-in build runs on a timer
// (never while shooting: each scene is set up whole by showScene).
MockupWindow {
    id: root
    contentWidth: 1580
    contentHeight: 1030

    readonly property var icons: ({
        warning: String.fromCodePoint(0xF071), danger: String.fromCodePoint(0xF057), success: String.fromCodePoint(0xF058),
        info: String.fromCodePoint(0xF05A), lock: String.fromCodePoint(0xF023)
    })

    // ---- Stand-in state ----

    property string link: "ready"           // "none" | "found" (the line not in force) | "ready"
    property bool homeConfig: false         // the configuration in the home folder
    property bool classic: false            // a classic configuration.nix, not a flake
    property bool homeAccepted: false       // its one-time warning answered
    property bool overridden: false         // the owner's own configuration sets the delay
    property bool fileCreated: false        // h2s-shell.json made (step 1 of the one-time setup)
    property string inForce: "1 h"
    property string picked: "3 h"
    property string previous: ""            // what Undo puts back; "" nothing to undo
    property bool undoing: false            // the run is an Undo's
    // "" | "building" | "password" | "switching" | "done" | "failed" | "errors" | "locked" | "cancelled"
    property string run: ""
    property bool drawerOpen: false
    property string modal: ""               // "" | "apply" | "undo"
    property real progress: -1
    property string phase: ""
    property int elapsed: 0                 // seconds
    property var log: []
    property bool copiedLine: false
    property bool copiedOption: false
    property int generation: 14

    readonly property var delays: ["30 min", "1 h", "3 h", "6 h"]
    // Three stand-in configurations: a flake in the home folder, a classic one at the old default
    // place, and a flake in another system folder
    readonly property string configDir: homeConfig ? "/home/alex/nixos-config" : classic ? "/etc/nixos" : "/srv/nixos-config"
    readonly property string configKind: classic ? "Classic (configuration.nix)" : "Flake"
    readonly property bool inGit: !classic
    readonly property string configFile: configDir + (classic ? "/configuration.nix" : "/hosts/" + host + ".nix")
    readonly property string host: homeConfig ? "laptop" : "nixos"
    readonly property bool running: run === "building" || run === "password" || run === "switching"
    readonly property string nixValue: ({ "30 min": "30min", "1 h": "1h", "3 h": "3h", "6 h": "6h" })[picked] ?? picked

    function duration(seconds) {
        return seconds >= 60 ? Math.floor(seconds / 60) + " min " + (seconds % 60) + " s" : seconds + " s";
    }

    // ---- The stand-in build ----

    readonly property var buildLines: [
        { at: 0.0, phase: "Copying the configuration", line: "copying " + root.configDir + " to a scratch folder" + (root.classic ? "" : " (same flake.lock)") },
        { at: -1, phase: "Evaluating", line: "building the system configuration..." },
        { at: -1, phase: "Evaluating", line: root.classic ? "evaluating <nixpkgs/nixos> with configuration.nix" : "evaluating nixosConfigurations." + root.host + ".config.system.build.toplevel" },
        { at: 0.1, phase: "Building 1 of 7", line: "these 7 derivations will be built:" },
        { at: 0.15, phase: "Building 1 of 7", line: "  /nix/store/9xq4…-h2s-shell-settings.json.drv" },
        { at: 0.3, phase: "Building 2 of 7", line: "building '/nix/store/k2mv…-unit-systemd-sleep.conf.drv'..." },
        { at: 0.45, phase: "Building 4 of 7", line: "building '/nix/store/c81a…-system-units.drv'..." },
        { at: 0.6, phase: "Building 5 of 7", line: "building '/nix/store/4fz0…-etc.drv'..." },
        { at: 0.8, phase: "Building 7 of 7", line: "building '/nix/store/a1hd…-nixos-system-nixos-25.11.drv'..." },
        { at: 1.0, phase: "Built", line: "/nix/store/a1hd…-nixos-system-nixos-25.11" }
    ]
    readonly property var switchLines: [
        "writing " + root.configDir + "/h2s-shell.json (old one kept in /var/lib/h2s-shell/nixos-backup)",
        "building the system configuration...",
        "activating the configuration...",
        "setting up /etc...",
        "restarting the following units: systemd-logind.service"
    ]
    readonly property var failLines: [
        "building the system configuration...",
        "error: attribute 'firefox-esr-115' missing",
        "       at " + root.configFile + ":88:7:",
        "           87|   environment.systemPackages = [",
        "           88|     pkgs.firefox-esr-115",
        "             |     ^",
        "           89|     htop"
    ]
    readonly property var errorLines: [
        "activating the configuration...",
        "restarting the following units: bluetooth.service, systemd-logind.service",
        "Job for bluetooth.service failed because the control process exited with error code.",
        "warning: the following units failed: bluetooth.service",
        "switch-to-configuration exited with 4"
    ]

    function linesUpTo(step) {
        return buildLines.slice(0, step + 1).map(entry => entry.line);
    }
    function setBuildStep(step) {
        const entry = buildLines[step];
        progress = entry.at;
        phase = entry.phase;
        log = linesUpTo(step);
    }

    property int _step: 0
    Timer {
        id: buildTimer
        interval: 700
        repeat: true
        running: root.run === "building" && !root.shooting && root.visible
        onTriggered: {
            root.elapsed += 9;
            root._step++;
            if (root._step >= root.buildLines.length) {
                root.run = "password";
                root.phase = "Waiting for the password";
                return;
            }
            root.setBuildStep(root._step);
        }
    }
    Timer {
        id: switchTimer
        interval: 1500
        running: root.run === "switching" && !root.shooting && root.visible
        onTriggered: root.finish("done")
    }

    function askApply() { modal = "apply"; }
    function askUndo() { modal = "undo"; }
    function startBuild() {
        undoing = modal === "undo";
        modal = "";
        run = "building";
        elapsed = 0;
        _step = 0;
        setBuildStep(0);
        drawerOpen = true;
    }
    function cancelBuild() {
        run = "cancelled";
        phase = "Cancelled";
        log = log.concat(["build stopped (cancelled)"]);
    }
    function authenticate() {
        run = "switching";
        phase = "Switching";
        progress = -1;
        log = log.concat(switchLines);
    }
    function dismissPassword() {
        run = "cancelled";
        phase = "No password: nothing changed";
    }
    function finish(outcome) {
        run = outcome;
        progress = 1;
        phase = outcome === "done" ? "Applied" : "Applied, with errors";
        generation = 15;
        if (undoing) {
            const back = previous;
            previous = "";
            inForce = back;
            picked = back;
        } else {
            previous = inForce;
            inForce = picked;
        }
    }

    // ---- Scenes ----

    // The scenes' titles, as the side column shows them: their descriptions in about.txt
    readonly property var sceneTitles: Array.prototype.slice.call(descriptions)
    readonly property int sceneIndex: Math.max(0, Array.prototype.indexOf.call(names, current))
    onCurrentChanged: showScene(Math.max(0, Array.prototype.indexOf.call(names, current)))
    readonly property var sceneNotes: [
        "Not connected: no configuration found (none in the usual places and none chosen, or the shell's NixOS module is not in it, or it lives on another machine). Every setting keeps today's line to copy — the hibernation delay below shows its option. This fallback stays for good.",
        "The configuration was found (here a classic configuration.nix at /etc/nixos, not in git, host nixos), but the shell's file is not in force yet. Two one-time steps: the shell creates h2s-shell.json (root-owned folder: asks the password), and you add one line, then nixos-rebuild switch. Until then settings still show lines to copy.",
        "OPEN QUESTION — a configuration kept in the home folder. The shell writes its file there as you, without a password. A one-time warning says what that means; \"Use it\" answers it for good. In git, also one git add: the shell never commits.",
        "Connected, the file in force (here a flake at /srv/nixos-config, in git). The section lists its facts one per line: where, the type, git, the host, the file and how many generations exist (each Apply adds one; the shell never deletes them). The setting offers Apply: picked 3 h, in force 1 h.",
        "Apply opens the Settings modal first: a build will run, as you, no password yet; it may take minutes; it can be cancelled while it builds; the password comes after.",
        "The build runs as you in the side panel: phase, a progress bar from nix's \"N of M\" lines (a moving bar while it evaluates), the elapsed time, nix's last lines, and Cancel. Closing the panel does not stop it; the page's line says it builds and reopens the panel.",
        "The build succeeded: only now the shell's password prompt (stand-in card here) asks, to write h2s-shell.json and switch. Cancelling the prompt changes nothing.",
        "After the password: the file is written (the old one backed up) and nixos-rebuild switch runs as root — seconds, the build is cached. No Cancel any more.",
        "Applied: generation 15. Undo puts back the shell's previous value (1 h) and rebuilds — your own changes since stay. Not a rollback to an older generation.",
        "The build failed (here: an error in the owner's own configuration, unrelated to the shell). nix's last lines, the copy's paths mapped back to the configuration (here a classic one at /etc/nixos). No password was asked, nothing changed.",
        "The switch ran, but a unit failed to start again (switch-to-configuration returned 4): \"Applied, with errors\" and the unit. The new values are in force; Undo is offered.",
        "The screen locked while it built: the chain stops before the password (no prompt over the lock). Nothing changed: Apply again.",
        "Cancel pressed during the build (or the password prompt dismissed): the build stops, nothing changed.",
        "The owner's configuration sets the delay itself (HibernateDelaySec = \"10min\"): it wins. The page says \"Set in your configuration: 10 min\" and offers no Apply.",
        "Undo also rebuilds, so it is announced the same way: it restores the shell's previous values, not an older generation.",
        "Undo's build: the same side panel, titled for Undo."
    ]

    function showScene(index) {
        const name = sceneTitles[index];
        buildTimer.stop();
        homeConfig = name === "In the home folder";
        classic = ["Found, line not in force", "Build failed"].includes(name);
        homeAccepted = false;
        link = name === "Not connected" ? "none" : ["Found, line not in force", "In the home folder"].includes(name) ? "found" : "ready";
        fileCreated = homeConfig;
        overridden = name === "Set in your configuration";
        copiedLine = false;
        copiedOption = false;
        undoing = name.startsWith("Undo");
        modal = name === "Apply: the announcement" ? "apply" : name === "Undo: the announcement" ? "undo" : "";
        const applied = ["Applied, Undo offered", "Applied, with errors"].includes(name) || undoing;
        inForce = applied ? "3 h" : "1 h";
        picked = "3 h";
        previous = applied ? "1 h" : "";
        generation = applied ? 15 : 14;
        elapsed = 0;
        drawerOpen = false;
        run = "";
        progress = -1;
        phase = "";
        log = [];
        if (name === "Building" || name === "Undo: building") {
            run = "building"; elapsed = 41; setBuildStep(5); drawerOpen = true;
        } else if (name === "Password after the build") {
            run = "password"; elapsed = 72; setBuildStep(buildLines.length - 1); phase = "Waiting for the password"; drawerOpen = true;
        } else if (name === "Switching") {
            run = "switching"; elapsed = 78; setBuildStep(buildLines.length - 1); log = log.concat(switchLines.slice(0, 3));
            phase = "Switching"; progress = -1; drawerOpen = true;
        } else if (name === "Applied, Undo offered") {
            run = "done"; elapsed = 81; progress = 1; phase = "Applied"; log = linesUpTo(buildLines.length - 1).concat(switchLines); drawerOpen = true;
        } else if (name === "Build failed") {
            run = "failed"; elapsed = 23; progress = 0; phase = "The build failed"; log = failLines; drawerOpen = true;
        } else if (name === "Applied, with errors") {
            run = "errors"; elapsed = 84; progress = 1; phase = "Applied, with errors"; log = errorLines; drawerOpen = true;
        } else if (name === "Locked during the build") {
            run = "locked"; elapsed = 37; setBuildStep(4); phase = "Stopped: the screen locked"; drawerOpen = false;
        } else if (name === "Cancelled") {
            run = "cancelled"; elapsed = 29; setBuildStep(3); phase = "Cancelled"; log = log.concat(["build stopped (cancelled)"]); drawerOpen = true;
        }
    }

    // ---- Small pieces ----

    component Label: Text {
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textSecondary
        wrapMode: Text.WordWrap
    }
    component Caption: Text {
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }
    component Dot: Rectangle {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 5
        implicitWidth: 10
        implicitHeight: 10
        radius: 5
    }
    // A boxed piece: code to copy, nix's output, a warning
    component Box: Rectangle {
        default property alias content: _boxColumn.data
        property color edge: Theme.divider
        Layout.fillWidth: true
        implicitHeight: _boxColumn.implicitHeight + 20
        radius: Theme.settings.cardRadius
        color: Theme.surfaceSunken
        border.width: Theme.border.width
        border.color: edge
        ColumnLayout {
            id: _boxColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 6
        }
    }
    component Code: Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textPrimary
    }
    component FactName: Caption {
        wrapMode: Text.NoWrap
        Layout.alignment: Qt.AlignTop | Qt.AlignLeft
        Layout.topMargin: 2
    }

    // ---- The side panel's content: the build ----

    Component {
        id: buildPanel
        ColumnLayout {
            spacing: 10

            // The three steps
            Repeater {
                model: ScriptModel { values: ["build", "password", "switch"] }
                RowLayout {
                    id: stepRow
                    required property string modelData
                    readonly property int order: ["build", "password", "switch"].indexOf(modelData)
                    readonly property int reached: root.run === "building" ? 0 : root.run === "password" ? 1
                                                 : root.run === "switching" ? 2 : ["done", "errors"].includes(root.run) ? 3
                                                 : 0
                    readonly property bool stopped: ["failed", "cancelled", "locked"].includes(root.run) && order === 0
                                                    || root.run === "errors" && order === 2
                    readonly property bool current: order === reached && root.running
                    readonly property bool done: order < reached
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        Layout.alignment: Qt.AlignTop
                        text: stepRow.stopped ? (root.run === "errors" ? root.icons.warning : root.icons.danger)
                            : stepRow.done ? root.icons.success : stepRow.current ? "●" : "○"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: stepRow.stopped ? (root.run === "errors" ? Theme.warning : Theme.error)
                             : stepRow.done ? Theme.success : stepRow.current ? Theme.accent : Theme.textMuted
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label {
                            Layout.fillWidth: true
                            color: stepRow.current || stepRow.stopped ? Theme.textPrimary : Theme.textSecondary
                            font.bold: stepRow.current
                            text: ({ build: "Build, as you", password: "Your password", switch: "Switch" })[stepRow.modelData]
                        }
                        Caption {
                            Layout.fillWidth: true
                            text: ({ build: "No password. Nothing changes yet.",
                                     password: "Writes the shell's file, then switches.",
                                     switch: "nixos-rebuild switch, as root. Seconds: the build is reused." })[stepRow.modelData]
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }

            // Where it is now
            RowLayout {
                Layout.fillWidth: true
                Label { Layout.fillWidth: true; color: Theme.textPrimary; text: root.phase }
                Caption { text: root.duration(root.elapsed) }
            }
            ProgressBar {
                visible: root.run === "building" || root.run === "switching"
                Layout.fillWidth: true
                value: root.progress
            }

            // The outcome
            Box {
                visible: root.run === "password"
                edge: Theme.privileged
                Label { Layout.fillWidth: true; color: Theme.textPrimary; text: "Built in " + root.duration(root.elapsed) + "." }
                Caption { Layout.fillWidth: true; text: "Type your password in the prompt to apply. Cancelling it changes nothing." }
            }
            Caption {
                visible: root.run === "switching"
                Layout.fillWidth: true
                text: "Switching. This cannot be cancelled now."
            }
            Box {
                visible: root.run === "done"
                edge: Theme.success
                Label { Layout.fillWidth: true; color: Theme.textPrimary
                        text: (root.undoing ? "Undone" : "Applied") + " in " + root.duration(root.elapsed) + ". Generation " + root.generation + " is in use." }
            }
            Box {
                visible: root.run === "errors"
                edge: Theme.warning
                color: Qt.alpha(Theme.warning, 0.12)
                Label { Layout.fillWidth: true; color: Theme.textPrimary; text: "Applied, with errors: bluetooth.service did not start again." }
                Caption { Layout.fillWidth: true; text: "The new values are in force. See journalctl -u bluetooth.service." }
            }
            Box {
                visible: root.run === "failed"
                edge: Theme.error
                color: Theme.errorTint
                Label { Layout.fillWidth: true; color: Theme.textPrimary; text: "The build failed. Nothing changed." }
                Caption { Layout.fillWidth: true; text: "Fix the error, then Apply again." }
            }
            Box {
                visible: root.run === "cancelled" || root.run === "locked"
                Label { Layout.fillWidth: true; color: Theme.textPrimary
                        text: root.run === "locked" ? "The screen locked during the build. Nothing changed." : "Cancelled. Nothing changed." }
            }

            // nix's last lines
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Caption { Layout.fillWidth: true; text: root.run === "failed" ? "nix's last lines" : "Output" }
                SmallButton { label: "Copy all"; fontSize: Theme.fontSizeSmall }
            }
            Box {
                Repeater {
                    model: ScriptModel { values: root.log.slice(-9) }
                    Code {
                        required property string modelData
                        text: modelData
                        color: modelData.startsWith("error") || modelData.startsWith("Job for") ? Theme.error
                             : modelData.startsWith("warning") ? Theme.warning : Theme.textSecondary
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6
                SmallButton { visible: root.run === "building"; label: "Cancel build"; kind: "warning"; onClicked: root.cancelBuild() }
                SmallButton { visible: root.run === "locked" || root.run === "failed" || root.run === "cancelled"; label: "Apply again"; kind: "save"
                              onClicked: root.askApply() }
                SmallButton { visible: root.previous !== "" && !root.running; label: "Undo"; onClicked: root.askUndo() }
                Item { Layout.fillWidth: true }
            }
            Caption {
                visible: root.run === "building"
                Layout.fillWidth: true
                text: "Closing this panel does not stop the build."
            }
        }
    }

    // ---- The window ----

    RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 24

        ColumnLayout {
            Layout.preferredWidth: 1060
            Layout.minimumWidth: 1060
            Layout.maximumWidth: 1060
            Layout.fillHeight: true
            spacing: 8

            Rectangle {
                id: settingsWindow
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.popupBackground
                border.color: Theme.divider
                border.width: 1
                radius: 8
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 1
                    spacing: 0

                    // The window's tabs, as the Settings window has them: System picked
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        Text {
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            text: "Settings"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                            color: Theme.textPrimary
                        }
                        Row {
                            anchors { left: parent.left; leftMargin: 180; verticalCenter: parent.verticalCenter }
                            spacing: 4
                            WindowTab { label: "Behaviour" }
                            WindowTab { label: "Appearance" }
                            WindowTab { label: "System"; picked: true }
                        }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 1
                            color: Theme.textDisabled
                            opacity: 0.3
                        }
                    }

                    // The page and what lies over it (the side panel, the modal)
                    Item {
                        id: pageArea
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        RowLayout {
                            anchors.fill: parent
                            spacing: 0

                            Rectangle {
                                Layout.preferredWidth: 170
                                Layout.fillHeight: true
                                color: Theme.surfaceSunken
                                ColumnLayout {
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                                    spacing: 6
                                    Repeater {
                                        model: ScriptModel { values: ["Authentication", "Network", "NixOS", "Modules"] }
                                        Text {
                                            required property string modelData
                                            readonly property bool current: modelData === "NixOS"
                                            text: modelData
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeBody
                                            font.bold: current
                                            color: current ? Theme.accent : Theme.textSecondary
                                        }
                                    }
                                }
                            }

                            Flickable {
                                id: pageFlick
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                contentWidth: width
                                contentHeight: pageColumn.implicitHeight + 2 * Theme.settings.pageMargin
                                clip: true

                                ColumnLayout {
                                    id: pageColumn
                                    x: Theme.settings.pageMargin
                                    y: Theme.settings.pageMargin
                                    width: pageFlick.width - 2 * Theme.settings.pageMargin
                                    spacing: 0

                                    Heading { text: "NixOS"; Layout.bottomMargin: 4 }

                                    // ---- The planned section ----
                                    SectionTitle {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 8
                                        text: "NixOS configuration"
                                        SmallButton { visible: root.link !== "none"; label: "Change…"; fontSize: Theme.fontSizeSmall }
                                    }
                                    Hint {
                                        Layout.fillWidth: true
                                        text: "The shell can keep its settings in your NixOS configuration and apply them by rebuilding NixOS. Turn that on here."
                                    }

                                    // State and facts
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 10
                                        implicitHeight: factsColumn.implicitHeight + 20
                                        radius: Theme.settings.cardRadius
                                        color: Theme.fillSubtle
                                        border.width: Theme.border.width
                                        border.color: root.link === "ready" ? Theme.outline : root.link === "found" ? Theme.warning : Theme.outline
                                        ColumnLayout {
                                            id: factsColumn
                                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; leftMargin: 12; rightMargin: 12 }
                                            spacing: 8
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                Dot { color: root.link === "ready" ? Theme.success : root.link === "found" ? Theme.warning : Theme.textMuted }
                                                Label {
                                                    Layout.fillWidth: true
                                                    color: Theme.textPrimary
                                                    text: root.link === "ready" ? "Connected"
                                                        : root.link === "found" ? "Found, not connected yet: the shell's file is not in force."
                                                        : "Not connected"
                                                }
                                                SmallButton { visible: root.link === "none"; label: "Choose folder…"; fontSize: Theme.fontSizeSmall }
                                                SmallButton { visible: root.link !== "ready"; label: "Look again"; fontSize: Theme.fontSizeSmall }
                                            }
                                            Caption {
                                                visible: root.link === "none"
                                                Layout.fillWidth: true
                                                text: "No NixOS configuration found that imports the shell's NixOS module. Built on another machine? Then keep copying the lines."
                                            }
                                            GridLayout {
                                                visible: root.link !== "none"
                                                Layout.fillWidth: true
                                                columns: 2
                                                columnSpacing: 16
                                                rowSpacing: 6
                                                FactName { text: "Configuration" }
                                                Label { Layout.fillWidth: true; color: Theme.textPrimary; text: root.configDir }
                                                FactName { text: "Type" }
                                                Label { Layout.fillWidth: true; color: Theme.textPrimary; text: root.configKind }
                                                FactName { text: "Git" }
                                                Label { Layout.fillWidth: true; color: Theme.textPrimary; text: root.inGit ? "Yes" : "No" }
                                                FactName { text: "Host" }
                                                Label { Layout.fillWidth: true; color: Theme.textPrimary; text: root.host }
                                                FactName { text: "The shell's file" }
                                                Label {
                                                    Layout.fillWidth: true
                                                    color: Theme.textPrimary
                                                    text: root.configDir + "/h2s-shell.json"
                                                }
                                                FactName { text: "File status" }
                                                Label {
                                                    Layout.fillWidth: true
                                                    color: Theme.textPrimary
                                                    text: root.link === "ready" ? "In force" : root.fileCreated ? "Created, not in force yet" : "Not created"
                                                }
                                                FactName { visible: root.link === "ready"; text: "Generations" }
                                                Label { visible: root.link === "ready"; Layout.fillWidth: true; color: Theme.textPrimary
                                                        text: String(root.generation) }
                                            }
                                            Caption {
                                                visible: root.link === "ready"
                                                Layout.fillWidth: true
                                                text: "Each Apply adds a generation. The shell never deletes them."
                                            }
                                        }
                                    }

                                    // The home folder's one-time warning (open question)
                                    Box {
                                        visible: root.homeConfig && !root.homeAccepted
                                        Layout.topMargin: 8
                                        edge: Theme.warning
                                        color: Qt.alpha(Theme.warning, 0.12)
                                        Label {
                                            Layout.fillWidth: true
                                            color: Theme.textPrimary
                                            text: root.icons.warning + "  This configuration is in your home folder."
                                        }
                                        Caption {
                                            Layout.fillWidth: true
                                            text: "Any program you run can change it, and NixOS builds it as root at every rebuild. The shell writes its file there without a password."
                                        }
                                        RowLayout {
                                            spacing: 6
                                            SmallButton { label: "Use it"; kind: "save"; fontSize: Theme.fontSizeSmall; onClicked: root.homeAccepted = true }
                                            SmallButton { label: "Choose another…"; fontSize: Theme.fontSizeSmall }
                                        }
                                    }

                                    // The one-time setup
                                    ColumnLayout {
                                        visible: root.link === "found" && (!root.homeConfig || root.homeAccepted)
                                        Layout.fillWidth: true
                                        Layout.topMargin: 10
                                        spacing: 8
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Label { text: "1."; color: Theme.textPrimary; Layout.alignment: Qt.AlignTop }
                                            Label {
                                                Layout.fillWidth: true
                                                text: root.fileCreated ? "h2s-shell.json is created." : "Create the shell's file, h2s-shell.json."
                                                color: root.fileCreated ? Theme.textMuted : Theme.textPrimary
                                            }
                                            PrivilegedMark { visible: !root.fileCreated }
                                            SmallButton { visible: !root.fileCreated; label: "Create"; kind: "save"; fontSize: Theme.fontSizeSmall
                                                          tooltip: "Asks for an administrator's password"; onClicked: root.fileCreated = true }
                                        }
                                        Caption {
                                            visible: root.homeConfig
                                            Layout.fillWidth: true
                                            Layout.leftMargin: 26
                                            text: "In git: run git add h2s-shell.json once. The shell never commits."
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Label { text: "2."; color: Theme.textPrimary; Layout.alignment: Qt.AlignTop }
                                            Label { Layout.fillWidth: true; color: Theme.textPrimary
                                                    text: "Add this line once to your configuration, then run nixos-rebuild switch." }
                                        }
                                        Box {
                                            Layout.leftMargin: 26
                                            Layout.fillWidth: true
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Code { text: "programs.h2s-shell.settingsFile = ./h2s-shell.json;" }
                                                SmallButton { label: root.copiedLine ? "Copied" : "Copy"; fontSize: Theme.fontSizeSmall; onClicked: root.copiedLine = true }
                                            }
                                        }
                                        Caption {
                                            Layout.fillWidth: true
                                            Layout.leftMargin: 26
                                            text: "In configuration.nix, or in your flake's module list. This page notices when it is in force."
                                        }
                                    }

                                    // ---- One setting that applies through it (Behaviour → When away) ----
                                    SectionTitle {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 22
                                        text: "Hibernate after"
                                    }
                                    Caption {
                                        Layout.fillWidth: true
                                        text: "From Behaviour → When away, shown here as the example of a setting applied through NixOS."
                                    }
                                    Row {
                                        Layout.topMargin: 10
                                        spacing: 6
                                        opacity: root.overridden ? 0.5 : 1
                                        Repeater {
                                            model: ScriptModel { values: root.delays }
                                            Pill {
                                                required property string modelData
                                                label: modelData
                                                size: "m"
                                                picked: root.picked === modelData
                                                onClicked: if (!root.running && !root.overridden) root.picked = modelData
                                            }
                                        }
                                    }
                                    Caption {
                                        Layout.topMargin: 6
                                        Layout.fillWidth: true
                                        visible: !root.overridden
                                        text: "In force: " + root.inForce
                                    }

                                    // Set in the owner's configuration: it wins, no Apply
                                    RowLayout {
                                        visible: root.overridden
                                        Layout.fillWidth: true
                                        Layout.topMargin: 10
                                        spacing: 8
                                        Dot { color: Theme.accent }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Label { Layout.fillWidth: true; color: Theme.textPrimary; text: "Set in your configuration: 10 min" }
                                            Caption { Layout.fillWidth: true
                                                      text: "Your own line wins. To change it here, remove it from your configuration." }
                                        }
                                    }

                                    // Connected: Apply and Undo
                                    RowLayout {
                                        visible: root.link === "ready" && !root.overridden
                                        Layout.fillWidth: true
                                        Layout.topMargin: 10
                                        spacing: 6
                                        SmallButton {
                                            label: "Apply"
                                            kind: "save"
                                            available: root.picked !== root.inForce && !root.running
                                            tooltip: "Rebuilds NixOS: a build first, then your password"
                                            onClicked: root.askApply()
                                        }
                                        SmallButton {
                                            visible: root.previous !== ""
                                            label: "Undo"
                                            available: !root.running
                                            tooltip: "Puts back the shell's previous value and rebuilds"
                                            onClicked: root.askUndo()
                                        }
                                        PrivilegedMark {}
                                        Hint {
                                            Layout.fillWidth: true
                                            text: root.running ? "" : root.previous !== "" ? "Undo puts back " + root.previous + " and rebuilds. Your own changes since stay."
                                                : "Rebuilds NixOS."
                                        }
                                    }
                                    // The run's line on the page
                                    RowLayout {
                                        visible: root.link === "ready" && root.run !== "" && !root.overridden
                                        Layout.fillWidth: true
                                        Layout.topMargin: 8
                                        spacing: 8
                                        Dot {
                                            color: ["done"].includes(root.run) ? Theme.success : root.run === "errors" ? Theme.warning
                                                 : root.run === "failed" ? Theme.error : root.running ? Theme.accent : Theme.textMuted
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            color: Theme.textPrimary
                                            text: ({
                                                building: (root.undoing ? "Undoing: building… " : "Building… ") + root.duration(root.elapsed),
                                                password: "Built. Waiting for your password.",
                                                switching: "Switching…",
                                                done: (root.undoing ? "Undone" : "Applied") + ". Generation " + root.generation + ".",
                                                errors: "Applied, with errors: bluetooth.service.",
                                                failed: "The build failed. Nothing changed.",
                                                locked: "Locked during the build. Nothing changed: Apply again.",
                                                cancelled: "Cancelled. Nothing changed."
                                            })[root.run] ?? ""
                                        }
                                        SmallButton { visible: !root.drawerOpen; label: "Show"; fontSize: Theme.fontSizeSmall; onClicked: root.drawerOpen = true }
                                    }

                                    // Not connected or not in force: today's line to copy
                                    ColumnLayout {
                                        visible: root.link !== "ready" && !root.overridden
                                        Layout.fillWidth: true
                                        Layout.topMargin: 10
                                        spacing: 6
                                        Hint { Layout.fillWidth: true; text: "On NixOS it is the option programs.h2s-shell.idle.hibernateDelay." }
                                        Box {
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Caption { Layout.fillWidth: true; text: "Add to your NixOS configuration" }
                                                SmallButton { label: root.copiedOption ? "Copied" : "Copy"; fontSize: Theme.fontSizeSmall; onClicked: root.copiedOption = true }
                                            }
                                            Code { text: "programs.h2s-shell.idle.hibernateDelay = \"" + root.nixValue + "\";" }
                                        }
                                        Caption { Layout.fillWidth: true; text: "Then run nixos-rebuild switch." }
                                    }
                                }
                            }
                        }

                        SideDrawer {
                            anchors.fill: parent
                            open: root.drawerOpen
                            title: root.undoing ? "Undo: rebuilding NixOS" : "Applying: rebuilding NixOS"
                            content: buildPanel
                            onRequested: event => root.drawerOpen = false
                        }

                        SettingsModal {
                            anchors.fill: parent
                            open: root.modal !== ""
                            kind: "info"
                            title: root.modal === "undo" ? "Undo the last Apply" : "Rebuild NixOS"
                            body: root.modal === "undo"
                                ? ["The shell's previous settings are put back and NixOS is rebuilt."]
                                : ["A new NixOS system is built first, as you. No password yet.",
                                   "This may take minutes and load the machine. You can cancel while it builds.",
                                   "When it is built, your password applies it."]
                            buttons: [{ id: "build", label: root.modal === "undo" ? "Undo and build" : "Build", kind: "save" }]
                            onAnswered: index => {
                                if (buttonList[index].id === "build")
                                    root.startBuild();
                                else
                                    root.modal = "";
                            }
                            onRequested: event => root.modal = ""
                        }
                    }
                }

                // The shell's password prompt, a stand-in card over everything (the real one is
                // polkit/AuthPrompt.qml's window)
                Rectangle {
                    visible: root.run === "password"
                    anchors.centerIn: parent
                    width: 420
                    height: promptColumn.implicitHeight + 40
                    radius: Theme.lock.controlRadius * 2
                    color: Theme.overlayOpaque
                    border.width: Theme.border.width
                    border.color: Theme.privileged
                    ColumnLayout {
                        id: promptColumn
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                        spacing: 10
                        Caption { text: "The shell's password prompt (stand-in)" }
                        Label { Layout.fillWidth: true; color: Theme.textPrimary; font.bold: true; text: root.icons.lock + "  h2s-shell: apply NixOS settings" }
                        Caption { Layout.fillWidth: true
                                  text: "Writes " + root.configDir + "/h2s-shell.json, then runs nixos-rebuild switch." }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.lock.controlHeight
                            radius: Theme.lock.controlRadius
                            color: Theme.glass
                            border.width: 1
                            border.color: Theme.glassBorderFocus
                            Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                   text: "Password"; color: Theme.glassTextMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeBody }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            SmallButton { Layout.fillWidth: true; label: "Cancel"; onClicked: root.dismissPassword() }
                            SmallButton { Layout.fillWidth: true; label: "Authenticate"; kind: "save"; onClicked: root.authenticate() }
                        }
                    }
                }
            }
        }

        // Right: what the scene shows
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 40
            spacing: 10
            Caption { text: "Scene " + (root.sceneIndex + 1) + " of " + root.sceneTitles.length + ": " + root.sceneTitles[root.sceneIndex] }
            Label { Layout.fillWidth: true; text: root.sceneNotes[root.sceneIndex] }
            Caption { Layout.topMargin: 12; Layout.fillWidth: true
                      text: "Stand-ins: three configurations — a flake at /srv/nixos-config in git, host nixos (most scenes); a classic configuration.nix at /etc/nixos, not in git (scenes 2 and 10); a flake at ~/nixos-config in git, host laptop (the home-folder scene); 14 generations; Hibernate after 3 h picked, 1 h in force; the owner's own setting 10 min." }
            Item { Layout.fillHeight: true }
        }
    }
}
