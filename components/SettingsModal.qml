import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

// A question over the Settings window that needs more than a button's word: a list of what
// else it affects, a checkbox, an explanation. A centred panel with an opaque background and
// a border in its kind's colour (ThemeRules.modalLook: "danger", "warning", "success",
// "info"), a header with the kind's icon, the title and "×", the body's lines, its checkboxes
// and optional content, and a row of buttons; behind it the area it fills dimmed with
// Theme.modalDim, every click and the wheel stopped there. Sizes from Theme.modal.
//
// Text from outside the shell may stand in the title, the body and the labels: each is drawn
// as plain text, on one line cut at a length (ApiElementRules.modalBody, oneLine) and wrapped
// at the panel's width. The buttons are ApiElementRules.modalButtons': always one cancel,
// last; with none of its own the one button informs.
//
// It never closes itself: a button reports `answered(index)` (an index into `buttonList`),
// "×" `requested("closeButton")`, Escape `requested("escape")`; the owner sets `open`
// (SettingsModalHost). While open it holds the keyboard — Escape reaches it before any
// shortcut behind it (a side panel's) —, Tab and Shift+Tab cycle through its controls, and
// the keyboard taken from it is taken back; on closing it goes back to the item that had it.
// `values` holds the checkboxes' states by key, all unchecked each time it opens.
Item {
    id: root

    property bool open: false
    property string kind: "info"
    property string title: ""
    // Lines: strings, or { text, strong }
    property var body: []
    // Checkboxes: [{ key, label }]
    property var checks: []
    // Optional content under the checkboxes (a list, say), built while open; laid out at
    // the panel's inner width. When its item has a `values` object, the host adds it to the
    // answer's.
    property Component content: null
    // Buttons: [{ id, label, kind, cancel }] (ApiElementRules.modalButtons)
    property var buttons: []
    property string cancelLabel: ""
    // "s" or "m" (Theme.modal's widths)
    property string size: "m"

    signal answered(int index)
    signal requested(string event)

    readonly property var look: ThemeRules.modalLook(kind)
    readonly property var _buttons: ApiElementRules.modalButtons(buttons, cancelLabel)
    readonly property var buttonList: _buttons.buttons
    readonly property bool informing: _buttons.informing
    readonly property var _body: ApiElementRules.modalBody(body)
    readonly property var _checks: ApiElementRules.modalChecks(checks)
    property var values: ({})

    readonly property Item panel: _panel
    readonly property Item contentItem: _content.item

    visible: open

    onOpenChanged: {
        if (open) {
            values = {};
            _trap.take();
        } else {
            _trap.giveBack();
        }
    }

    function _isInside(item) {
        return _trap.isInside(item);
    }

    // The keyboard stays inside while open: Tab cycles there, and a click or tap that takes it
    // out (or Qt's own Tab from a control inside) brings it back
    FocusTrap {
        id: _trap
        scope: _panel
        active: root.open && root.visible
        holdsFocus: true
    }

    function _toggle(key) {
        const next = Object.assign({}, values);
        next[key] = !(values[key] === true);
        values = next;
    }

    // ── The dimmed area: takes every click, hover and wheel, so nothing behind reacts ──
    Rectangle {
        anchors.fill: parent
        color: Theme.modalDim
    }
    MouseArea {
        objectName: "modalBlocker"
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onPressed: _panel.forceActiveFocus()
        onWheel: wheel => wheel.accepted = true
    }

    FocusScope {
        id: _panel
        anchors.centerIn: parent
        width: ApiElementRules.modalWidth(root.size, root.width, Theme.modal)
        height: Math.min(_column.implicitHeight + 2 * Theme.modal.padding, Math.max(0, root.height - 2 * Theme.modal.padding))

        // Escape is the modal's while it has the keyboard, not a shortcut's behind it
        Keys.onShortcutOverride: event => event.accepted = event.key === Qt.Key_Escape
        Keys.onEscapePressed: root.requested("escape")

        Rectangle {
            anchors.fill: parent
            radius: Theme.modal.radius
            color: Theme.popupBackground
            border.width: Theme.modal.borderWidth
            border.color: Theme[root.look.border]
        }

        // Clicks and the wheel on the panel stay on it
        MouseArea {
            anchors.fill: parent
            onPressed: _panel.forceActiveFocus()
            onWheel: wheel => wheel.accepted = true
        }

        ColumnLayout {
            id: _column
            anchors.fill: parent
            anchors.margins: Theme.modal.padding
            spacing: Theme.modal.spacing

            // ── The header: icon, title, × ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.modal.spacing
                Text {
                    Layout.alignment: Qt.AlignTop
                    text: root.look.icon
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSection
                    color: Theme[root.look.tone]
                }
                Text {
                    objectName: "modalTitle"
                    Layout.fillWidth: true
                    text: ApiElementRules.oneLine(root.title, ApiElementRules.modalTitleCap)
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                    color: Theme[root.look.titleColor]
                }
                Text {
                    objectName: "modalClose"
                    Layout.alignment: Qt.AlignTop
                    text: "×"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSection
                    color: _close.lit ? Theme.textPrimary : Theme.textSecondary
                    PointerArea {
                        id: _close
                        reach: 4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.requested("closeButton")
                    }
                }
            }

            // ── The body, checkboxes and content, scrolled when the window is short ──
            Flickable {
                id: _scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: _middle.implicitHeight
                visible: root._body.length > 0 || root._checks.length > 0 || root.content !== null
                contentWidth: width
                contentHeight: _middle.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                clip: interactive

                ColumnLayout {
                    id: _middle
                    width: _scroller.width
                    spacing: Theme.modal.spacing

                    Repeater {
                        model: ScriptModel { values: root._body.map((line, index) => String(index)) }
                        Text {
                            required property string modelData
                            readonly property var line: root._body[Number(modelData)] ?? { text: "", strong: false }
                            objectName: "modalLine"
                            Layout.fillWidth: true
                            text: line.text
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: line.strong
                            color: line.strong ? Theme.textPrimary : Theme.textSecondary
                        }
                    }

                    Repeater {
                        model: ScriptModel { values: root._checks.map(check => check.key) }
                        Checkbox {
                            required property string modelData
                            objectName: "modalCheck:" + modelData
                            Layout.fillWidth: true
                            label: root._checks.find(check => check.key === modelData)?.label ?? ""
                            checked: root.values[modelData] === true
                            onToggled: root._toggle(modelData)
                        }
                    }

                    Loader {
                        id: _content
                        Layout.fillWidth: true
                        active: root.open && root.content !== null
                        visible: active
                        sourceComponent: root.content
                    }
                }
            }

            // ── The buttons, the cancel last ──
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Theme.modal.spacing / 2
                Repeater {
                    model: ScriptModel { values: root.buttonList.map((button, index) => String(index)) }
                    SmallButton {
                        required property string modelData
                        readonly property var button: root.buttonList[Number(modelData)] ?? { label: "", kind: "normal" }
                        objectName: "modalButton:" + modelData
                        label: button.label
                        kind: button.kind
                        onClicked: root.answered(Number(modelData))
                    }
                }
            }
        }
    }
}
