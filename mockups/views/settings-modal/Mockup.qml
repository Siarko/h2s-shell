import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import qs.singletons
import qs.components
import qs.mockups.kit

// The Settings window's modal (SettingsModal) over a stand-in area of the window, one
// question per state, its spec passed in through the modal's own properties. The questions
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
//   focus-button     enable-module after Tab: the keyboard on the first button (its ring;
//                    with every state on screen the ring is drawn without the keyboard)
//   short-window     remove-password in a window too short for it (200 px): the middle is
//                    cut and scrolls, the header and the buttons stay
// Each state has a cell (the kit's StateGrid stacks them: on one another while shooting, one
// under another on screen), a stand-in of the window's area. While shooting and for one
// state, one area and its modal take each state's question in turn, placed on the state's
// cell, and the modal opens anew (open false, then true), as the host does for each question:
// the keyboard goes to the panel and the checkboxes start unchecked. (A modal made anew for
// each state draws its text a pixel apart from one reused: the glyph cache fills in another
// order.) With every state on screen at once, each cell has an area and a modal of its own
// (the grid lets only the cell under the pointer take input).
MockupWindow {
    id: root

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
    readonly property var spec: specs[current] ?? {}
    keyboardStates: ["focus-button"]

    readonly property var changeLines: ["Plays from the files' folder too", "Shows the cover in the popup",
                                        "Remembers the volume per player", "Fixes a stall after a suspend"]

    // The question opened anew for the state, then the keyboard and the checkboxes it needs,
    // once the modal has opened (its focus taken) with the state's spec
    onCurrentChanged: {
        area.modal.open = false;
        area.modal.open = true;
        Qt.callLater(_settle, current);
    }
    function _settle(name) {
        if (name !== current)
            return;
        if (name === "remove-checked")
            area.modal.values = { data: true };
        if (name === "focus-button")
            keys.keyClick(Qt.Key_Tab);
    }

    // The control Tab gives the keyboard to from the modal's panel (where the keyboard is
    // when it opens), as FocusTrap.cycle finds it: drawn with the keyboard's ring
    // (SmallButton.shownFocused)
    function _ringFirst(modal) {
        const panel = Array.prototype.find.call(modal.children, child => child.toString().startsWith("QQuickFocusScope"));
        const inside = item => {
            for (let up = item; up; up = up.parent)
                if (up === panel)
                    return true;
            return false;
        };
        let item = panel;
        for (let step = 0; panel && step < 1000; step++) {
            item = item.nextItemInFocusChain(true);
            if (!item || item === panel)
                return;
            if (inside(item) && item.visible && item.enabled) {
                if (item.shownFocused !== undefined)
                    item.shownFocused = true;
                return;
            }
        }
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
    component Area: Item {
        id: areaItem
        property alias modal: _modal
        property var spec: ({})

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
            id: _modal
            x: 0
            y: 0
            width: parent.width
            height: parent.height
            kind: areaItem.spec.kind ?? "info"
            title: areaItem.spec.title ?? ""
            body: areaItem.spec.body ?? []
            checks: areaItem.spec.checks ?? []
            content: areaItem.spec.content ?? null
            buttons: areaItem.spec.buttons ?? []
            cancelLabel: areaItem.spec.cancelLabel ?? ""
            size: areaItem.spec.size ?? "m"
        }
    }

    StateGrid {
        id: grid
        cellWidth: 600
        cellHeight: 440
        stacked: true

        Repeater {
            id: _cells
            model: root.names.length

            StateCell {
                id: cell
                required property int index
                name: root.names[index]
                height: name === "short-window" ? 200 : 440

                // Every state's question at once, the ticked box drawn ticked
                Loader {
                    anchors.fill: parent
                    active: root.layout === "all"
                    sourceComponent: Area {
                        spec: root.specs[cell.name] ?? {}
                        Component.onCompleted: Qt.callLater(() => {
                            modal.open = true;
                            if (cell.name === "remove-checked")
                                modal.values = { data: true };
                            // The ring Tab gives the first button, drawn without the keyboard:
                            // one item has it at a time, and every cell is shown
                            if (cell.name === "focus-button")
                                Qt.callLater(() => root._ringFirst(modal));
                        })
                    }
                }
            }
        }

        // The one area while shooting and for one state, on the state's cell
        Area {
            id: area
            x: grid.currentCell ? grid.currentCell.x : 0
            y: grid.currentCell ? grid.currentCell.y : 0
            width: grid.cellWidth
            height: grid.currentCell ? grid.currentCell.height : grid.cellHeight
            visible: root.layout === "shot" || root.layout === "one"
            spec: root.spec
        }
    }
}
