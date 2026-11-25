import QtQuick
import Quickshell
import qs.singletons

// A choice among `options` — [{ value, label, color?, group?, disabled? }], `color` drawing
// a dot before the label — shown as a button with the current one, opening a FloatingList
// of them over the content. `picked` reports the choice; the owner sets `value`. Options
// that follow each other with the same `group` are listed under its title; a `disabled`
// one is shown dimmed and cannot be picked (the keys pass it by).
//
// It takes the focus on Tab and on a click (a ring shows it). Space, Enter, Down or Up open
// the list on the current choice; open, the list's keys apply (FloatingList: arrows, Home,
// End, the pages, a letter), Enter or Space picks, Escape closes it — the focus stays here
// all along — and Tab closes it on the way to the next control.
Rectangle {
    id: root

    property var options: []
    property var value
    property string placeholder: "Choose"
    property bool open: false
    property int fontSize: Theme.fontSizeBody
    signal picked(var value)

    readonly property var _current: options.find(option => option.value === value) ?? null

    implicitWidth: 120
    implicitHeight: Math.max(26, _label.implicitHeight + 8)
    radius: Theme.dropdown.radius
    color: Theme.popupBackground
    border.width: Theme.border.width
    border.color: open ? Theme.accent : activeFocus ? Theme.textSecondary : (_area.lit ? Theme.textMuted : Theme.outline)
    activeFocusOnTab: true

    // Open, Escape is the list's: a side panel's or a window's Escape waits for the next one
    Keys.onShortcutOverride: event => event.accepted = open && event.key === Qt.Key_Escape
    Keys.onPressed: event => {
        const plain = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0;
        if (open) {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                open = false;
                event.accepted = false;
            } else if (event.key === Qt.Key_Space && plain) {
                event.accepted = _list.handleKey({ key: Qt.Key_Return, modifiers: event.modifiers, text: "" });
            } else {
                event.accepted = _list.handleKey(event);
            }
            return;
        }
        if (plain && [Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter, Qt.Key_Down, Qt.Key_Up].includes(event.key)) {
            open = true;
            event.accepted = true;
        }
    }
    // Opened: on the current choice
    onOpenChanged: if (open) Qt.callLater(() => _list.highlight(_list._entries().find(entry => entry.picked) ?? null))
    Behavior on border.color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

    // A colour dot, when the option has a colour
    component Dot: Rectangle {
        width: 10
        height: 10
        radius: width / 2
    }

    Row {
        anchors { left: parent.left; right: _arrow.left; leftMargin: Theme.field.horizontalPadding; rightMargin: 4; verticalCenter: parent.verticalCenter }
        spacing: 6

        Dot {
            visible: root._current?.color !== undefined
            anchors.verticalCenter: parent.verticalCenter
            color: root._current?.color ?? "transparent"
        }
        Text {
            id: _label
            width: parent.width - (root._current?.color !== undefined ? 16 : 0)
            text: root._current?.label ?? root.placeholder
            textFormat: Text.PlainText
            maximumLineCount: 1
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: root.fontSize
            color: root._current ? Theme.textSecondary : Theme.textDisabled
        }
    }

    Text {
        id: _arrow
        anchors { right: parent.right; rightMargin: Theme.field.horizontalPadding; verticalCenter: parent.verticalCenter }
        text: root.open ? "▴" : "▾"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeXSmall
        color: Theme.textMuted
    }

    PointerArea {
        id: _area
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.open = !root.open;
        }
    }

    FloatingList {
        id: _list
        anchorItem: root
        open: root.open
        onClosed: root.open = false

        // Keyed by value: the options can be live (the account's calendars), new objects
        // at each change ("The Repeater crash" in docs/ARCHITECTURE.md)
        KeyedModel { id: _optionsModel; values: root.options; keyProp: "value" }
        Repeater {
            model: _optionsModel.model

            // The group's title above its first option, then the option
            Column {
                id: _box
                required property string modelData
                readonly property var option: _optionsModel.byKey[modelData] ?? ({})
                readonly property bool groupStart: {
                    const group = option.group ?? "";
                    if (group === "")
                        return false;
                    const at = root.options.findIndex(other => other.value === option.value);
                    return at <= 0 || (root.options[at - 1].group ?? "") !== group;
                }
                // A box the Repeater lets go of while everything goes has no parent any more
                width: parent ? parent.width : 0

                FloatingListHeader {
                    visible: _box.groupStart
                    text: _box.option.group ?? ""
                }

                Rectangle {
                    id: _row
                    readonly property var option: _box.option
                    readonly property bool picked: option.value === root.value
                    readonly property bool available: option.disabled !== true
                    // An entry of the list, for its keys (FloatingList)
                    readonly property bool floatingEntry: true
                    readonly property string floatingEntryText: option.label ?? ""
                    readonly property bool floatingEntryEnabled: available
                    readonly property bool current: _list.currentItem === _row
                    function floatingActivate() {
                        if (!available)
                            return;
                        root.open = false;
                        root.picked(option.value);
                    }
                    width: _box.width
                    height: Math.max(24, _optionLabel.implicitHeight + 6)
                    radius: Theme.listItem.radius
                    color: picked ? Theme.accentTint : ((_optionArea.lit || current) && available ? Theme.surfaceHover : Theme.surfaceHoverClear)
                    // The keys' entry, also when it is the picked one
                    border.width: current ? Theme.border.width : 0
                    border.color: Theme.textSecondary
                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                    Row {
                        anchors { left: parent.left; right: parent.right; leftMargin: 6; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        opacity: _row.available ? 1 : 0.5

                        Dot {
                            visible: _row.option.color !== undefined
                            anchors.verticalCenter: parent.verticalCenter
                            color: _row.option.color ?? "transparent"
                        }
                        Text {
                            id: _optionLabel
                            width: parent.width - (_row.option.color !== undefined ? 16 : 0)
                            text: _row.option.label ?? ""
                            textFormat: Text.PlainText
                            maximumLineCount: 1
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: root.fontSize
                            color: !_row.available ? Theme.textDisabled : _row.picked ? Theme.textPrimary : Theme.textSecondary
                        }
                    }

                    PointerArea {
                        id: _optionArea
                        centred: false
                        anchors.fill: parent
                        cursorShape: _row.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: _row.floatingActivate()
                    }
                }
            }
        }
    }
}
