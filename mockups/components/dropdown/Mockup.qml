import QtQuick
import qs.singletons
import qs.components
import qs.mockups.kit

// Dropdown in its states, 180 px wide, in a settings column. Each cell is an overlay host
// (objectName "overlayHost"): an open list floats inside the cell, as it would inside a
// popup's panel, not over the whole window. The closed states show two dropdowns, a plain
// choice and one whose options have colour dots:
//   closed           the current choice
//   placeholder      no `value`: the placeholder "Choose", dimmed
//   hover            drawn as under the pointer (the dropdown's `shownLit`)
//   focus            drawn as with the keyboard (its `shownFocused`): the keyboard's ring
//   open             `open: true`: the list, the picked option tinted; the dropdown opens
//                    with the keys on it, so it is ringed too
//   groups           options with `group` (a title over each group's first) and `color`
//   disabled-option  an option with `disabled: true`: dimmed, the keys pass it by
//   current          the keys moved off the picked option: opened on "Every 5 minutes",
//                    then the list's `highlight` on the next one, as Down puts it there; the
//                    dropdown with the keyboard
//   long-label       a label longer than the button: cut
// On screen a click outside an open list closes it, as anywhere; a click on the button
// opens it again.
MockupWindow {
    id: root

    pointerStates: ["hover"]
    keyboardStates: ["focus", "current"]

    readonly property var _intervals: [
        { value: 1, label: "Every minute" },
        { value: 5, label: "Every 5 minutes" },
        { value: 15, label: "Every 15 minutes" },
        { value: 60, label: "Every hour" }
    ]
    readonly property var _calendars: [
        { value: "personal", label: "Personal", color: Theme.accent, group: "Mine" },
        { value: "work", label: "Work", color: Theme.warning, group: "Mine" },
        { value: "family", label: "Family", color: Theme.success, group: "Shared with me" },
        { value: "holidays", label: "Holidays in Poland", color: Theme.error, group: "Shared with me" }
    ]
    readonly property var _plainCalendars: _calendars.map(option => ({ value: option.value, label: option.label, color: option.color }))
    readonly property var _long: [
        { value: "long", label: "Every 15 minutes while on battery power" }
    ]
    readonly property var _longCalendar: [
        { value: "long", label: "Holidays and observances in Poland", color: Theme.error }
    ]
    readonly property var _withDisabled: [
        { value: "wifi", label: "Wi-Fi" },
        { value: "ethernet", label: "Ethernet" },
        { value: "mobile", label: "Mobile broadband", disabled: true },
        { value: "vpn", label: "VPN" }
    ]
    readonly property var _closed: ["closed", "hover", "focus", "long-label"]
    readonly property var _opened: ["open", "groups", "disabled-option", "current"]

    // The dropdowns of a cell: options, value, open
    function _dropdowns(name) {
        switch (name) {
        case "placeholder": return [{ options: _intervals, value: undefined }];
        case "long-label": return [{ options: _long, value: "long" }, { options: _longCalendar, value: "long" }];
        case "open": return [{ options: _intervals, value: 5 }];
        case "groups": return [{ options: _calendars, value: "work" }];
        case "disabled-option": return [{ options: _withDisabled, value: "wifi" }];
        case "current": return [{ options: _intervals, value: 5 }];
        default: return [{ options: _intervals, value: 5 }, { options: _plainCalendars, value: "work" }];
        }
    }

    // The keys put on the entry with that text in the list open in `host`, through the list's
    // own contract (its entries are the items with `floatingEntry`), as a key press puts them:
    // no text or colour changes after the list is shown, only the entry's ring and light
    function _highlight(host, text) {
        const find = (item, wanted) => {
            for (const child of item.children) {
                if (wanted(child))
                    return child;
                const inside = find(child, wanted);
                if (inside)
                    return inside;
            }
            return null;
        };
        const list = find(host, item => item.floatingList === true);
        list.highlight(find(list, item => item.floatingEntry === true && item.floatingEntryText === text));
    }

    StateGrid {
        cellWidth: 212
        cellHeight: 16 + 26 + 2 + 150 + 16
        cellsPerRow: 5

        Repeater {
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]
                // A closed state needs no room for a list
                height: root._opened.includes(name) ? 210 : root._dropdowns(name).length === 1 ? 58 : 92

                Item {
                    id: host
                    objectName: "overlayHost"
                    anchors.fill: parent

                    Column {
                        x: 16
                        y: 16
                        spacing: 8

                        Repeater {
                            model: root._dropdowns(cell.name).length
                            Dropdown {
                                required property int index
                                readonly property var spec: root._dropdowns(cell.name)[index]
                                width: 180
                                options: spec.options
                                value: spec.value
                                open: root._opened.includes(cell.name) && cell.name !== "current"
                                shownLit: cell.name === "hover"
                                shownFocused: cell.name === "focus" || cell.name === "current"
                                // Shown once it is in the window: the kit makes the window after
                                // the cells, and an open list whose anchor moves to another
                                // window closes (FloatingList)
                                visible: Window.window !== null
                                // Opened (on the picked option, as every opening is), then the
                                // keys moved on to the next one
                                onVisibleChanged: if (visible && cell.name === "current") {
                                    open = true;
                                    Qt.callLater(() => root._highlight(host, "Every 15 minutes"));
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
