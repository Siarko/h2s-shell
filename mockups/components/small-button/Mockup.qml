import QtQuick
import QtTest
import Quickshell
import qs.singletons
import qs.components
import qs.mockups.kit

// SmallButton in every kind ThemeRules.buttonLook names, in each look it draws. Each state
// shows one column of every kind, one row each; a state is named
// <look>[-<pointer>]-<kind>, the pointer and the kind naming the one button it is about:
//   rest                    no pointer, no keyboard
//   disabled                `available: false`
//   checked                 `checked: true` (a toggle that is on: the plain kinds take the
//                           accent)
//   hover-<kind>            the pointer over that kind's button (a simulated pointer move)
//   checked-hover-normal    checked, the pointer over the normal button (accentHover)
//   disabled-hover-normal   not available, the pointer over the normal button (no light)
//   focus-<kind>            that kind's button has the keyboard (the ring inside it)
//   pressed-<kind>          pressed on that kind's button, then the pointer moved off it
//                           with the button held: pressed, not under the pointer
// The pointer is simulated with QtTest's events: each state puts it where the state needs
// it before its frames are waited for, so the look depends on the state, never on time.
// Every state has a cell of its own, all of them shown side by side while shooting, the shot
// cropped to the state's cell, and the pointer, when no button is to be under it, parked on
// a strip below the cells: no button is shown or hidden as the states go by, so none
// is ever under a pointer left where an earlier state put it (Qt Quick sends hover again at
// the pointer's place as items change under it). On screen only the state's cell is shown.
// A pressed button is never released: a release would make the look linger for a moment
// (PointerArea.linger), so the pressed states come last, each with its own column.
// "asking" is DeleteButton's state (the first click of a button that asks), not
// SmallButton's: it is not drawn here.
MockupWindow {
    id: root

    readonly property var kinds: ["normal", "save", "saveChange", "action", "cancel", "delete", "warning", "success"]
    readonly property var pressedKinds: ["normal", "save", "delete"]
    names: ["rest", "disabled", "checked"]
        .concat(kinds.map(kind => "hover-" + kind))
        .concat(["checked-hover-normal", "disabled-hover-normal"])
        .concat(kinds.map(kind => "focus-" + kind))
        .concat(pressedKinds.map(kind => "pressed-" + kind))

    // A state's name taken apart: { state (the look), pointer ("hover", "pressed" or ""), kind ("" for
    // none) }
    function _parse(name) {
        const parts = name.split("-");
        if (parts.length === 3)
            return { state: parts[0], pointer: parts[1], kind: parts[2] };
        const pointerStates = ["hover", "pressed"];
        return { state: parts[0], pointer: pointerStates.includes(parts[0]) ? parts[0] : "", kind: parts[1] ?? "" };
    }

    // A cell: the widest button (saveChange) and the column of eight, each 24 px tall, 8 px
    // apart, with 12 px round them; while shooting, the cells in rows of six
    readonly property int cellWidth: 140
    readonly property int cellHeight: 8 * 24 + 7 * 8 + 2 * 12
    readonly property int cellsPerRow: 6
    contentWidth: shooting ? cellsPerRow * cellWidth : cellWidth
    readonly property int gridHeight: Math.ceil(names.length / cellsPerRow) * cellHeight
    contentHeight: shooting ? gridHeight + away.height : cellHeight
    subject: _cells.itemAt(Array.prototype.indexOf.call(names, current)) ?? content_

    function _button(name, kind) {
        const cell = _cells.itemAt(Array.prototype.indexOf.call(names, name));
        return cell ? cell.column.children[kinds.indexOf(kind)] : null;
    }

    // The pointer and the keyboard for the state, before its frames are waited for
    onCurrentChanged: _placePointer(current)
    function _placePointer(name) {
        const parsed = _parse(name);
        const button = parsed.kind !== "" ? _button(name, parsed.kind) : null;
        if (parsed.pointer === "hover" && button)
            pointer.mouseMove(button, button.width / 2, button.height / 2);
        else if (parsed.pointer === "pressed" && button) {
            pointer.mouseMove(button, button.width / 2, button.height / 2);
            pointer.mousePress(button, button.width / 2, button.height / 2);
            // Off the button (and its larger pointer target) with the button held
            pointer.mouseMove(away, away.width / 2, away.height / 2, -1, Qt.LeftButton);
        }
        else
            pointer.mouseMove(away, away.width / 2, away.height / 2);
        if (parsed.state === "focus" && button)
            button.forceActiveFocus();
        else
            away.forceActiveFocus();
    }

    TestCase {
        id: pointer
        when: false
    }

    Item {
        id: content_
        anchors.fill: parent

        // Where the pointer rests off every cell (and the keyboard focus off every button)
        Item {
            id: away
            y: root.gridHeight
            width: parent.width
            height: 8
        }

        Repeater {
            id: _cells
            model: root.names.length
            Item {
                id: cell
                required property int index
                readonly property string cellState: root._parse(root.names[index]).state
                property alias column: _column
                x: root.shooting ? (index % root.cellsPerRow) * root.cellWidth : 0
                y: root.shooting ? Math.floor(index / root.cellsPerRow) * root.cellHeight : 0
                width: root.cellWidth
                height: root.cellHeight
                visible: root.shooting || root.names[index] === root.current

                Column {
                    id: _column
                    x: 12
                    y: 12
                    spacing: 8

                    Repeater {
                        model: ScriptModel { values: root.kinds }
                        SmallButton {
                            required property string modelData
                            label: modelData
                            kind: modelData
                            available: cell.cellState !== "disabled"
                            checked: cell.cellState === "checked"
                        }
                    }
                }
            }
        }
    }
}
