import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// Settings → Modules, "Add a module": one
// field for a repository address or a folder, "Choose folder…" (the shell's file chooser,
// singletons/FileChooser.qml, in folder mode) and "Install". The install runs in the
// installer with `preview`: its downloads one row each — a bar (the shared ProgressBar, waving
// while git reports numbers) and the percent and speed —, then the preview: what the module
// is and where it comes from, its API, administrator actions and programs, the chain (what it
// also installs, updates, finds installed, can use, and what cannot be had), what it replaces,
// where it goes, the statement for every module new to the modules folder, "What's new"
// (the changelogs, in the page's side panel) and the choice: "Install and enable" / "Install,
// keep off", or "Install anyway" when a dependency cannot be had, and "Cancel" (the downloads
// are deleted). A failure says what happened and why, on one line. Only the job this section
// started is shown; its answers are keyed to its number.
SettingsSection {
    id: root

    // The installer (install(source, { preview }), proceed(job, options), cancelPreview(job),
    // cancelDownload(job), jobNumber, busy, phase, steps, preview, finished(result))
    property var installer: null
    // The file chooser (choose(handle, options, done, home)) and where it starts
    property var chooser: FileChooser
    property string home: ""
    // "What's new": the changelogs to show in the page's side panel
    signal changelogsRequested(string title, var sections)

    // The install this section started (its job number, 0 none) and how the last one ended
    property int job: 0
    property string error: ""
    readonly property bool mine: job !== 0 && (installer?.busy ?? false) && installer.jobNumber === job
    readonly property string phase: mine ? (installer.phase ?? "") : ""
    readonly property var preview: mine && phase === "preview" && installer.preview?.job === job ? installer.preview : null
    readonly property alias field: _field

    anchor: "add"
    title: "Add a module"
    topMargin: 0
    spacing: 6

    function start() {
        error = "";
        const refused = installer?.install(_field.text.trim(), { preview: true }) ?? "No installer";
        if (refused !== "") {
            error = ApiElementRules.oneLine(refused, 300);
            return;
        }
        job = installer.jobNumber;
    }

    function chooseFolder() {
        chooser?.choose({ moduleId: "settings", name: "Settings", active: true },
                        { mode: "folder", title: "A module's folder" }, result => {
            if (result.paths.length > 0)
                _field.text = result.paths[0];
            else if (result.error !== "")
                root.error = ApiElementRules.oneLine(result.error, 300);
        }, home);
    }

    function decide(choice) {
        if (!preview)
            return;
        if (choice === "cancel") {
            installer.cancelPreview(job);
            return;
        }
        const refused = installer.proceed(job, { enable: choice !== "keepOff", anyway: choice === "anyway" });
        if (refused !== "")
            error = ApiElementRules.oneLine(refused, 300);
    }

    Connections {
        target: root.installer
        function onFinished(result) {
            if (result?.job !== root.job || root.job === 0)
                return;
            root.job = 0;
            root.error = result.ok ? "" : ModuleInstallRules.installErrorText(result);
            if (result.ok)
                _field.text = "";
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        InputField {
            id: _field
            objectName: "installField"
            Layout.fillWidth: true
            placeholder: "Repository address or folder"
            problem: root.error !== ""
            onAccepted: if (_install.available) root.start()
            // A changed address is a new try: the old error goes
            onTextChanged: root.error = ""
        }
        SmallButton {
            objectName: "chooseFolder"
            label: "Choose folder…"
            available: !root.mine
            onClicked: root.chooseFolder()
        }
        SmallButton {
            id: _install
            objectName: "installButton"
            label: "Install"
            kind: "save"
            available: _field.text.trim() !== "" && !(root.installer?.busy ?? true)
            onClicked: root.start()
        }
    }

    // What went wrong, on one line
    Text {
        objectName: "installError"
        visible: text !== ""
        Layout.fillWidth: true
        text: root.error
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.error
    }

    // The steps: downloading and verifying each module of the chain, then installing
    RowLayout {
        visible: root.mine && root.phase !== "preview"
        Layout.fillWidth: true
        Layout.topMargin: 4
        Text {
            objectName: "installPhase"
            Layout.fillWidth: true
            text: ({ downloading: "Downloading", verifying: "Verifying", installing: "Installing", loading: "Installing" })[root.phase] ?? "Preparing"
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            font.bold: true
            color: Theme.textPrimary
        }
        SmallButton {
            objectName: "cancelDownload"
            visible: root.phase === "downloading"
            label: "Cancel"
            kind: "cancel"
            onClicked: root.installer.cancelDownload(root.job)
        }
    }
    KeyedModel { id: _steps; values: root.mine ? (root.installer.steps ?? []) : []; keyProp: "key" }
    Repeater {
        model: _steps.model
        RowLayout {
            id: _stepRow
            required property string modelData
            readonly property var step: _steps.byKey[modelData] ?? ({ label: "", state: "", percent: null, rate: null })
            objectName: "installStep"
            visible: root.phase !== "preview"
            Layout.fillWidth: true
            spacing: 10
            Text {
                Layout.preferredWidth: Math.round(root.width * 0.3)
                text: _stepRow.step.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textPrimary
            }
            ProgressBar {
                objectName: "stepBar"
                Layout.fillWidth: true
                value: _stepRow.step.state === "downloading" ? (_stepRow.step.percent === null ? -1 : _stepRow.step.percent / 100)
                     : _stepRow.step.state === "verifying" ? -1 : _stepRow.step.state === "failed" ? 0 : 1
                wave: _stepRow.step.state === "downloading" && _stepRow.step.percent !== null
                tone: _stepRow.step.state === "failed" ? "error" : _stepRow.step.state === "verified" ? "success" : "accent"
            }
            Text {
                objectName: "stepText"
                Layout.preferredWidth: Math.round(root.width * 0.22)
                horizontalAlignment: Text.AlignRight
                text: ModuleInstallRules.stepText(_stepRow.step, _stepRow.step.rate ? Format.rate(_stepRow.step.rate) : "")
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: _stepRow.step.state === "failed" ? Theme.error : _stepRow.step.state === "verified" ? Theme.success : Theme.textSecondary
            }
        }
    }

    // The preview: nothing changes until a button is clicked
    Rectangle {
        objectName: "installPreview"
        visible: root.preview !== null
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: visible ? _previewColumn.implicitHeight + 16 : 0
        radius: Theme.settings.cardRadius
        color: "transparent"
        border.width: Theme.border.width
        border.color: Theme.outline

        ColumnLayout {
            id: _previewColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 4

            RowLayout {
                spacing: 8
                Text {
                    text: root.preview?.icon ?? ""
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.accent
                }
                Text {
                    objectName: "previewName"
                    text: root.preview?.name ?? ""
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    color: Theme.textPrimary
                }
                Text {
                    text: [root.preview?.id ?? "", root.preview?.version ?? ""].filter(part => part !== "").join(" · ")
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textMuted
                }
            }
            Text {
                visible: text !== ""
                Layout.fillWidth: true
                text: root.preview?.description ?? ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
            }
            DetailRow { label: "Source"; value: (root.preview?.source ?? []).join("\n") }
            DetailRow { label: "Author"; value: root.preview?.author ?? "" }
            DetailRow { label: "API"; value: root.preview?.api ?? "" }
            DetailRow { label: "Administrator"; value: root.preview?.privileged ?? "" }
            DetailRow {
                label: "Programs"
                value: (root.preview?.programs ?? []).map(program => program.name + (program.found ? " — found" : " — not found")).join(", ")
            }
            DetailRow { label: "Also installs"; value: (root.preview?.alsoInstalls ?? []).join("\n") }
            DetailRow { label: "Updates"; value: (root.preview?.updates ?? []).join("\n") }
            DetailRow { label: "Already there"; value: (root.preview?.already ?? []).join("\n") }
            DetailRow { label: "Can use"; value: (root.preview?.canUse ?? []).join("\n") }
            DetailRow { label: "Replaces"; value: root.preview?.replaces ?? "" }

            // What cannot be had, one line each
            Repeater {
                model: ScriptModel { values: root.preview?.blocking ?? [] }
                RowLayout {
                    required property string modelData
                    objectName: "previewBlocking"
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        Layout.alignment: Qt.AlignTop
                        text: ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.warning
                    }
                    Text {
                        Layout.fillWidth: true
                        text: parent.modelData
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.warning
                    }
                }
            }
            // What would stop working
            Repeater {
                model: ScriptModel { values: root.preview?.breaks ?? [] }
                Text {
                    required property string modelData
                    objectName: "previewBreak"
                    Layout.fillWidth: true
                    text: "\uf071 " + modelData
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.warning
                }
            }
            Text {
                visible: text !== ""
                Layout.fillWidth: true
                text: root.preview?.anywayText ?? ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
            }
            DetailRow { label: "Goes to"; value: root.preview?.goesTo ?? "" }

            SmallButton {
                objectName: "whatsNew"
                Layout.topMargin: 2
                label: "What's new"
                onClicked: root.changelogsRequested("What's new", root.preview?.changelogs ?? [])
            }

            // The statement and the choice
            Rectangle {
                objectName: "trustBox"
                Layout.fillWidth: true
                Layout.topMargin: 6
                implicitHeight: _trustColumn.implicitHeight + 24
                radius: Theme.settings.cardRadius
                color: Qt.alpha(Theme.warning, 0.10)
                border.width: Theme.border.width
                border.color: Theme.warning

                ColumnLayout {
                    id: _trustColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8
                    Text {
                        objectName: "trustTitle"
                        visible: root.preview?.trust !== null && root.preview?.trust !== undefined
                        Layout.fillWidth: true
                        text: root.preview?.trust?.title ?? ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        font.bold: true
                        color: Theme.textPrimary
                    }
                    Text {
                        visible: text !== ""
                        Layout.fillWidth: true
                        text: root.preview?.trust?.text ?? ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textSecondary
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        SmallButton {
                            objectName: "installEnable"
                            visible: root.preview?.choice === "ready"
                            label: "Install and enable"
                            kind: "save"
                            onClicked: root.decide("enable")
                        }
                        SmallButton {
                            objectName: "installKeepOff"
                            visible: root.preview?.choice === "ready"
                            label: "Install, keep off"
                            onClicked: root.decide("keepOff")
                        }
                        SmallButton {
                            objectName: "installAnyway"
                            visible: root.preview?.choice === "anyway"
                            label: "Install anyway"
                            kind: "warning"
                            onClicked: root.decide("anyway")
                        }
                        SmallButton {
                            objectName: "installCancel"
                            label: "Cancel"
                            kind: "cancel"
                            onClicked: root.decide("cancel")
                        }
                    }
                }
            }
        }
    }
}
