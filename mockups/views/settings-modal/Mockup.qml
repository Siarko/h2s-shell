import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import qs.singletons
import qs.components
import qs.mockups.kit

// The Settings window's modal (SettingsModal) over a stand-in area of the window, one
// question per scene, its spec passed in through the modal's own properties. The questions
// are the shell's own, made by its rules from stand-in names where a rule makes one:
//   informing        success, no button of its own: the one "OK" informs (size s)
//   enable-module    ModuleInstallRules.confirmationQuestion: warning, a strong line first,
//                    "Enable" (save) and "Cancel"
//   disable-module   ModuleInstallRules.disableQuestion: warning, what goes with it,
//                    "Disable" (warning)
//   remove-module    ModuleInstallRules.removeQuestion: danger, checkboxes, "Remove"
//                    (delete) and "Keep"
//   remove-checked   the same with its first checkbox ticked
//   remove-password  PamRuleViewRules.removeFixedQuestion: the danger confirmation, three
//                    lines of explanation
//   content-list     info, a list under the body (the modal's `content`)
//   long-text        a long title and long lines wrapping at the small panel's width
//   focus-button     enable-module after Tab: the keyboard on the first button (its ring)
//   short-window     remove-password in a window too short for it (200 px): the middle is
//                    cut and scrolls, the header and the buttons stay
// Each scene opens the modal anew (open false, then true), as the host does for each
// question: the keyboard goes to the panel and the checkboxes start unchecked.
MockupWindow {
    id: root

    scenes: ["informing", "enable-module", "disable-module", "remove-module", "remove-checked", "remove-password",
             "content-list", "long-text", "focus-button", "short-window"]

    // The stand-in removal preview (ModuleInstaller.removalPreview's answer)
    readonly property var removal: ({
        ok: true, title: "Remove Player?",
        lines: ["Not installed by the shell.", "Deletes the folder ~/.config/quickshell/modules/player.",
                "These stop working: Exit map."],
        orphans: [{ id: "clip", label: "Also remove Clipboard (installed for Player, nothing else uses it)" }]
    })

    readonly property var specs: ({
        "informing": { kind: "success", size: "s", title: "Player installed",
                       body: ["It is enabled and shows in the bar from the next start."] },
        "enable-module": ModuleInstallRules.confirmationQuestion("Weather Radar"),
        "disable-module": ModuleInstallRules.disableQuestion("Clipboard", ["Player", "Exit map"], ["Notes"]),
        "remove-module": ModuleInstallRules.removeQuestion(removal),
        "remove-checked": ModuleInstallRules.removeQuestion(removal),
        "remove-password": PamRuleViewRules.removeFixedQuestion("sudo", [], {}),
        "content-list": { kind: "info", title: "What changed in Player 1.4",
                          body: ["Since the version you have:"], content: changes,
                          buttons: [{ id: "update", label: "Update", kind: "save" }], cancelLabel: "Later" },
        "long-text": { kind: "warning", size: "s",
                       title: "Replace the fingerprint reader's rule for administrator prompts and sudo on this machine?",
                       body: [{ text: "The rule written by hand in /etc/pam.d/sudo on 2026-11-02 is replaced, and the copy kept beside it is overwritten.", strong: true },
                              "A program that asks for the administrator's password (pkexec, the package manager, the disk tool) asks for the finger first and the password after it, every time, until the rule is changed again."],
                       buttons: [{ id: "replace", label: "Replace", kind: "warning" }] },
        "focus-button": ModuleInstallRules.confirmationQuestion("Weather Radar"),
        "short-window": PamRuleViewRules.removeFixedQuestion("sudo", [], {})
    })
    readonly property var spec: specs[scene] ?? {}

    readonly property var changeLines: ["Plays from the files' folder too", "Shows the cover in the popup",
                                        "Remembers the volume per player", "Fixes a stall after a suspend"]

    contentWidth: 600
    contentHeight: 440
    subject: area

    // The question opened anew for the scene, then the keyboard and the checkboxes it needs,
    // once the modal has opened (its focus taken) with the scene's spec
    onSceneChanged: {
        modal.open = false;
        modal.open = true;
        Qt.callLater(_settle, scene);
    }
    function _settle(name) {
        if (name !== scene)
            return;
        if (name === "remove-checked")
            modal.values = { data: true };
        if (name === "focus-button")
            keys.keyClick(Qt.Key_Tab);
    }

    TestCase {
        id: keys
        when: false
    }

    property Component changes: Component {
        ColumnLayout {
            spacing: 4
            Repeater {
                model: ScriptModel { values: root.changeLines }
                Text {
                    required property string modelData
                    Layout.fillWidth: true
                    text: "• " + modelData
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textPrimary
                }
            }
        }
    }

    // A stand-in of the Settings window's area behind the modal: a page title and rows, so
    // that the dim over it shows
    Item {
        id: area
        x: 0
        y: 0
        width: parent.width
        height: root.scene === "short-window" ? 200 : parent.height

        Column {
            x: Theme.modal.padding
            y: Theme.modal.padding
            spacing: Theme.modal.spacing
            Text {
                text: "Modules"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSection
                font.bold: true
                color: Theme.textPrimary
            }
            Repeater {
                model: ["Player", "Clipboard", "Exit map", "Notes", "Weather Radar"]
                Text {
                    required property string modelData
                    text: modelData
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                }
            }
        }

        SettingsModal {
            id: modal
            x: 0
            y: 0
            width: parent.width
            height: parent.height
            kind: root.spec.kind ?? "info"
            title: root.spec.title ?? ""
            body: root.spec.body ?? []
            checks: root.spec.checks ?? []
            content: root.spec.content ?? null
            buttons: root.spec.buttons ?? []
            cancelLabel: root.spec.cancelLabel ?? ""
            size: root.spec.size ?? "m"
        }
    }
}
