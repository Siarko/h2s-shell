import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons
import qs.components
import qs.mockups.kit

// Planning mockup of HS-228: the shell's modal (SettingsModal) offered to modules through the
// API, and shown outside the Settings window — over a bar popup and over a module's side
// panel. One stage per scene (a stand-in desktop with the bar and the Tailscale popup, or a
// stand-in Settings window on the Tailscale page) with a note under it. Throwaway: the bar,
// the popup's rows, the Settings window's frame, sidebar and page, and the side panel are
// drawn here as stand-ins; the real pieces are the theme, SmallButton and SettingsModal (its
// look, sizes, dim, keys). The questions' wording is a proposal (MOCKUP.md).
// The last scene, modal-api-live, works on its own stand-in data: Save asks when a name is
// taken; the answer is shown in the note; "Lock the session" and "Close the popup" withdraw
// an open question.
MockupWindow {
    id: root

    contentWidth: 1100
    contentHeight: 790

    readonly property int stageHeight: 680
    readonly property int barHeight: 34
    readonly property rect settingsRect: Qt.rect(50, 30, 1000, 620)
    readonly property rect popupRect: Qt.rect(640, barHeight + 6, 350, 420)
    readonly property rect belowBar: Qt.rect(0, barHeight, contentWidth, stageHeight - barHeight)

    function sceneIs(...wanted) {
        return wanted.indexOf(root.current) >= 0;
    }

    readonly property bool live: current === "modal-api-live"
    readonly property bool onSettings: sceneIs("settings-today", "side-panel", "module-logout", "module-stop-all")
    readonly property bool sidePanelOpen: sceneIs("side-panel")

    // The question opened anew for each scene, once the scene's bindings have settled (a
    // handler of `current` may run before the properties bound to it are updated)
    onCurrentChanged: {
        modal.open = false;
        Qt.callLater(_enter, current);
    }
    function _enter(name) {
        if (name !== current)
            return;
        Theme.instantAnimations = !(live && !shooting);
        if (live)
            liveReset();
        modal.open = spec !== null;
    }

    // ---- The questions (proposed wording) ---------------------------------------------------

    readonly property var themeQuestion: ({
        kind: "danger", title: "Delete the theme Nord?",
        body: ["Its file is backed up first, beside it in the themes folder.",
               "Profiles that use it switch to the built-in theme."],
        buttons: [{ id: "delete", label: "Delete", kind: "delete" }], cancelLabel: "Cancel" })
    readonly property var logoutQuestion: ({
        kind: "danger", title: "Log out of Tailscale?",
        body: [{ text: "This computer leaves the tailnet example.ts.net until you log in again.", strong: true },
               "Its exit node, the routes it shares and its Serve shares stop; the account stays in the list."],
        buttons: [{ id: "logout", label: "Log out", kind: "delete" }], cancelLabel: "Cancel" })
    readonly property var stopAllQuestion: ({
        kind: "danger", title: "Stop all Serve shares?",
        body: ["These stop at once, also the ones this page does not list:"],
        items: ["https://laptop.example.ts.net → localhost:3000",
                "Funnel: https://laptop.example.ts.net:8443 → ~/public",
                "A terminal share on port 2222 (made outside the shell)"],
        buttons: [{ id: "stopAll", label: "Stop all", kind: "delete" }], cancelLabel: "Cancel" })
    function saveQuestion(names) {
        return {
            kind: "warning",
            title: names.length === 1 ? "The name " + names[0] + " is taken" : names.length + " names are taken",
            body: [names.length === 1 ? "A file of that name is already in ~/Downloads:" : "Files of these names are already in ~/Downloads:",
                   "Keep both saves the new one as “name (1)”."],
            items: names,
            buttons: [{ id: "replace", label: "Replace", kind: "warning" }, { id: "keepBoth", label: "Keep both" }],
            cancelLabel: "Cancel"
        };
    }

    readonly property var spec: {
        if (live)
            return liveSpec;
        switch (current) {
        case "settings-today": return themeQuestion;
        case "popup-inside":
        case "popup-screen": return saveQuestion(["report-2026.pdf"]);
        case "side-panel":
        case "keyboard": return saveQuestion(["report-2026.pdf", "photo-0142.jpg"]);
        case "module-logout": return logoutQuestion;
        case "module-stop-all": return stopAllQuestion;
        }
        return null;
    }

    // Where the modal's area is: the Settings window, the popup alone (option A), or the
    // screen below the bar (option B, proposed)
    readonly property rect modalRect: onSettings ? settingsRect : sceneIs("popup-inside") ? popupRect : belowBar

    readonly property var notes: ({
        "settings-today": "Today: SettingsModalHost covers the whole Settings window and holds the keyboard; one question per window. Unchanged; the new API reaches this same host from a module's settings page.",
        "popup-inside": "Option A: the dim and the panel stay inside the popup (its surface's input mask). The panel is only 314 px wide here (popup 350 − 2 × 18) instead of 380, and a short popup cuts it. Not proposed: the modal would look different per place.",
        "popup-screen": "Option B, proposed: while a question is open the popup's own full-screen surface takes the whole area below the bar (mask widened), dims it and centres the modal at its usual width. The popup stays open (no hover-close), takes the keyboard exclusively; the bar stays usable.",
        "side-panel": "A question from a side panel's content: the Settings window's host is above the page frame, so the window, the dimmed page and the side panel are all under the modal. Escape answers the modal first; the side panel stays open behind it.",
        "module-logout": "Asked by the Tailscale module through the API (module.ask): the same modal, look and keys as the shell's own. A danger kind: red border and icon; the button a delete kind.",
        "module-stop-all": "items: a plain list the module gives (here the shares that stop), drawn under the body and scrolled with it when long; a module gives text, never its own Component.",
        "keyboard": "On opening the keyboard is on the panel, no button lit (Enter does nothing). Tab: Replace, Keep both, Cancel — left to right, the cancel last; Shift+Tab back; Escape answers cancelled. Checkboxes, when given, come before the buttons.",
        "modal-api-live": ""
    })

    // ---- The live scene ---------------------------------------------------------------------

    readonly property var liveTakenNames: ["report-2026.pdf", "photo-0142.jpg"]
    property var liveFiles: []
    property var liveSpec: null
    property var liveAsked: []
    property string liveAnswer: ""
    property bool livePopupOpen: true

    function liveReset() {
        liveFiles = [{ name: "report-2026.pdf", size: "2.1 MB", saved: "" },
                     { name: "photo-0142.jpg", size: "3.4 MB", saved: "" },
                     { name: "notes.txt", size: "4 KB", saved: "" }];
        liveSpec = null;
        liveAsked = [];
        liveAnswer = "Click Save or Save all in the popup.";
        livePopupOpen = true;
    }
    function liveSave(names) {
        const waiting = names.filter(name => liveFiles.find(file => file.name === name)?.saved === "");
        const taken = waiting.filter(name => liveTakenNames.indexOf(name) >= 0);
        if (taken.length === 0) {
            liveStore(waiting, "keepBoth", []);
            liveAnswer = "No name taken: saved without a question.";
            return;
        }
        liveAsked = waiting;
        liveSpec = saveQuestion(taken);
        modal.open = true;
    }
    function liveStore(names, how, taken) {
        liveFiles = liveFiles.map(file => {
            if (names.indexOf(file.name) < 0)
                return file;
            const renamed = how === "keepBoth" && taken.indexOf(file.name) >= 0
                ? file.name.replace(/(\.[^.]*)?$/, " (1)$1") : file.name;
            return { name: file.name, size: file.size, saved: renamed };
        });
    }
    function liveFinish(answer) {
        const asked = liveAsked;
        const taken = liveSpec?.items ?? [];
        modal.open = false;
        liveSpec = null;
        liveAsked = [];
        liveAnswer = "done(" + JSON.stringify(answer) + ")";
        if (!answer.cancelled && answer.blocked === "")
            liveStore(asked, answer.button, taken);
    }
    function liveWithdraw(reason) {
        if (liveSpec !== null)
            liveFinish({ button: "cancel", cancelled: false, blocked: reason });
        if (reason === "closed")
            livePopupOpen = false;
    }

    // ---- Stand-in pieces --------------------------------------------------------------------

    component Label: Text {
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textPrimary
        elide: Text.ElideRight
    }

    // One file waiting in Taildrop's inbox, with its Save
    component FileRow: RowLayout {
        id: fileRow
        property var file: ({})
        spacing: 8
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label { Layout.fillWidth: true; text: fileRow.file.name ?? "" }
            Label {
                Layout.fillWidth: true
                text: (fileRow.file.saved ?? "") !== "" ? "Saved as " + fileRow.file.saved : (fileRow.file.size ?? "") + " · waiting"
                font.pixelSize: Theme.fontSizeSmall
                color: (fileRow.file.saved ?? "") !== "" ? Theme.success : Theme.textMuted
            }
        }
        SmallButton {
            label: "Save"
            visible: (fileRow.file.saved ?? "") === ""
            onClicked: if (root.live) root.liveSave([fileRow.file.name])
        }
    }

    readonly property var shownFiles: live ? liveFiles
        : [{ name: "report-2026.pdf", size: "2.1 MB", saved: "" }, { name: "photo-0142.jpg", size: "3.4 MB", saved: "" },
           { name: "notes.txt", size: "4 KB", saved: "" }]

    // The list under the body: the spec's `items`, as the API would draw them
    property Component itemList: Component {
        ColumnLayout {
            spacing: 4
            Repeater {
                model: ScriptModel { values: root.spec?.items ?? [] }
                Label {
                    required property string modelData
                    Layout.fillWidth: true
                    text: "• " + modelData
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }
            }
        }
    }

    // ---- The stage --------------------------------------------------------------------------

    Item {
        id: stage
        width: root.contentWidth
        height: root.stageHeight
        clip: true

        // The desktop, the bar and the Tailscale popup
        Rectangle {
            anchors.fill: parent
            visible: !root.onSettings
            color: Theme.surfaceSunken

            Rectangle {
                width: parent.width
                height: root.barHeight
                color: Theme.barBackground
                Label { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "1  2  3  4" ; color: Theme.textSecondary }
                Label { anchors.centerIn: parent; text: "Thu 15 Jan  10:30" }
                Rectangle {
                    x: root.popupRect.x + root.popupRect.width / 2 - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 74
                    height: 24
                    radius: 12
                    color: Theme.accentTint
                    Label { anchors.centerIn: parent; text: "⬡ 3"; color: Theme.textPrimary }
                }
                Label { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "▂▄▆  ⏻"; color: Theme.textSecondary }
            }

            // The popup's body
            Rectangle {
                x: root.popupRect.x
                y: root.popupRect.y
                width: root.popupRect.width
                height: root.popupRect.height
                visible: !root.live || root.livePopupOpen
                radius: 10
                color: Theme.popupBackground
                border.width: 1
                border.color: Theme.outline

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Tailscale"; font.bold: true; font.pixelSize: Theme.fontSizeMedium }
                        Item { Layout.fillWidth: true }
                        Label { text: "● Connected"; color: Theme.success; font.pixelSize: Theme.fontSizeSmall }
                    }
                    Label { Layout.fillWidth: true; text: "laptop · 100.101.4.7 · example.ts.net"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }
                    Repeater {
                        model: ["phone  · online", "nas  · online", "desktop  · idle 2 h"]
                        Label { required property string modelData; Layout.fillWidth: true; text: modelData; color: Theme.textSecondary }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }
                    RowLayout {
                        Layout.fillWidth: true
                        Label { Layout.fillWidth: true; text: "Received files"; font.bold: true }
                        SmallButton { label: "Save all"; onClicked: if (root.live) root.liveSave(root.liveFiles.map(file => file.name)) }
                    }
                    Repeater {
                        model: ScriptModel { values: root.shownFiles.map(file => file.name) }
                        FileRow {
                            required property string modelData
                            Layout.fillWidth: true
                            file: root.shownFiles.find(item => item.name === modelData) ?? {}
                        }
                    }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Layout.fillWidth: true
                        SmallButton { label: "Settings…" }
                        Item { Layout.fillWidth: true }
                        SmallButton { label: "Web console" }
                    }
                }
            }
        }

        // The Settings window on the Tailscale page
        Rectangle {
            id: settingsWindow
            x: root.settingsRect.x
            y: root.settingsRect.y
            width: root.settingsRect.width
            height: root.settingsRect.height
            visible: root.onSettings
            color: Theme.surface
            border.width: 1
            border.color: Theme.outline
            clip: true

            Rectangle {
                id: sidebar
                width: Theme.scaled(160)
                height: parent.height
                color: Theme.surfaceSunken
                Column {
                    x: 12
                    y: 16
                    spacing: 10
                    Repeater {
                        model: ["Dashboard", "Network", "   Wi-Fi", "   VPN", "   Tailscale", "Bluetooth", "Sound", "Appearance", "Modules"]
                        Label {
                            required property string modelData
                            text: modelData
                            color: modelData.trim() === "Tailscale" ? Theme.accent : Theme.textSecondary
                            font.bold: modelData.trim() === "Tailscale"
                        }
                    }
                }
            }

            ColumnLayout {
                x: sidebar.width + 24
                y: 18
                width: parent.width - sidebar.width - 48
                spacing: 12
                Label { text: "Tailscale"; font.bold: true; font.pixelSize: Theme.fontSizeSection }
                RowLayout {
                    Layout.fillWidth: true
                    Label { Layout.fillWidth: true; text: "Account   you@example.com · tailnet example.ts.net"; color: Theme.textSecondary }
                    SmallButton { label: "Log out" }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { Layout.fillWidth: true; text: "Accounts   work@example.org"; color: Theme.textSecondary }
                    SmallButton { label: "Switch" }
                    SmallButton { label: "Remove" }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }
                Label { text: "Serve and Funnel"; font.bold: true }
                RowLayout {
                    Layout.fillWidth: true
                    Label { Layout.fillWidth: true; text: "https://laptop.example.ts.net → localhost:3000"; color: Theme.textSecondary }
                    SmallButton { label: "Remove" }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { Layout.fillWidth: true; text: "Funnel  :8443 → ~/public"; color: Theme.textSecondary }
                    SmallButton { label: "Remove" }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    SmallButton { label: "Stop all" }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }
                RowLayout {
                    Layout.fillWidth: true
                    Label { Layout.fillWidth: true; text: "Taildrop   3 files waiting"; color: Theme.textSecondary }
                    SmallButton { label: "Files…" }
                }
            }

            // A module's side panel over the page, the page beside it dimmed
            Rectangle {
                x: sidebar.width
                width: parent.width - sidebar.width
                height: parent.height
                visible: root.sidePanelOpen
                color: Theme.modalDim
                opacity: 0.6
            }
            Rectangle {
                visible: root.sidePanelOpen
                x: parent.width - width
                width: 440
                height: parent.height
                color: Theme.popupBackground
                border.width: 1
                border.color: Theme.outline
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        Label { Layout.fillWidth: true; text: "Taildrop"; font.bold: true; font.pixelSize: Theme.fontSizeMedium }
                        SmallButton { label: "Close" }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }
                    Label { text: "Send"; font.bold: true }
                    Label { Layout.fillWidth: true; text: "phone   nas   desktop"; color: Theme.textSecondary }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }
                    RowLayout {
                        Layout.fillWidth: true
                        Label { Layout.fillWidth: true; text: "Waiting in the inbox"; font.bold: true }
                        SmallButton { label: "Save all" }
                    }
                    Repeater {
                        model: ScriptModel { values: root.shownFiles.map(file => file.name) }
                        FileRow {
                            required property string modelData
                            Layout.fillWidth: true
                            file: root.shownFiles.find(item => item.name === modelData) ?? {}
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }

        // The shell's modal, placed as the scene proposes
        SettingsModal {
            id: modal
            x: root.modalRect.x
            y: root.modalRect.y
            width: root.modalRect.width
            height: root.modalRect.height
            kind: root.spec?.kind ?? "info"
            title: root.spec?.title ?? ""
            body: root.spec?.body ?? []
            content: (root.spec?.items ?? []).length > 0 ? root.itemList : null
            buttons: root.spec?.buttons ?? []
            cancelLabel: root.spec?.cancelLabel ?? ""
            size: "s"
            onAnswered: index => {
                const button = buttonList[index];
                if (root.live && button)
                    root.liveFinish({ button: button.id, cancelled: button.cancel, blocked: "" });
            }
            onRequested: event => {
                if (root.live)
                    root.liveFinish({ button: "cancel", cancelled: true, blocked: "" });
            }
        }

        // The keyboard's order, step by step, beside the open question
        Rectangle {
            visible: root.sceneIs("keyboard")
            x: 24
            y: root.barHeight + 24
            width: 300
            height: _steps.implicitHeight + 28
            radius: 8
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.outline
            ColumnLayout {
                id: _steps
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 8
                Repeater {
                    model: [{ step: "Opened", lit: -1 }, { step: "Tab", lit: 0 }, { step: "Tab", lit: 1 },
                            { step: "Tab", lit: 2 }, { step: "Shift+Tab", lit: 1 }]
                    ColumnLayout {
                        required property var modelData
                        spacing: 4
                        Label { text: modelData.step + (modelData.lit < 0 ? ": nothing lit" : ""); color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                        RowLayout {
                            spacing: Theme.modal.spacing / 2
                            Repeater {
                                model: [{ label: "Replace", kind: "warning" }, { label: "Keep both", kind: "normal" }, { label: "Cancel", kind: "cancel" }]
                                SmallButton {
                                    required property var modelData
                                    required property int index
                                    label: modelData.label
                                    kind: modelData.kind
                                    shownFocused: index === parent.parent.modelData.lit
                                }
                            }
                        }
                    }
                }
                Label { text: "Escape: answered cancelled"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                Label {
                    Layout.fillWidth: true
                    text: "Replace's orange outline is its kind (warning), not the keyboard: the ring is the lighter border"
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }

    // ---- The note under the stage -----------------------------------------------------------

    Rectangle {
        y: root.stageHeight
        width: root.contentWidth
        height: root.contentHeight - root.stageHeight
        color: Theme.surface
        border.width: 1
        border.color: Theme.outline

        Label {
            visible: !root.live
            x: 16
            y: 12
            width: parent.width - 32
            text: root.notes[root.current] ?? ""
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            color: Theme.textSecondary
        }

        ColumnLayout {
            visible: root.live
            x: 16
            y: 12
            width: parent.width - 32
            spacing: 8
            RowLayout {
                spacing: 8
                SmallButton { label: "Lock the session"; onClicked: root.liveWithdraw("locked") }
                SmallButton { label: "Close the popup"; onClicked: root.liveWithdraw("closed") }
                SmallButton { label: "Reset"; onClicked: root.liveReset() }
                Label { text: "report-2026.pdf and photo-0142.jpg are taken in ~/Downloads"; color: Theme.textMuted; font.pixelSize: Theme.fontSizeSmall }
            }
            Label { Layout.fillWidth: true; text: root.liveAnswer; color: Theme.textPrimary; font.family: "monospace" }
        }
    }
}
