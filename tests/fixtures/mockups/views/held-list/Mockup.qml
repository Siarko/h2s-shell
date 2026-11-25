import QtQuick
import Quickshell.Io
import qs.singletons
import qs.components
import qs.mockups.kit

// A fixture view for tests/run-mockups-selftest.sh's real pointer in the gallery: hosted
// there, it holds a list open as a state shows an open menu, until a press outside it. The
// list's press catcher covers the whole window: the gallery's bar must still take a press,
// while the list and a section button's tooltip are drawn over it.
// Alone (shot, on screen) the list stays closed.
MockupWindow {
    id: root

    property bool dismissed: false

    StateGrid {
        cellWidth: 200
        cellHeight: 60

        StateCell {
            name: "open"

            Rectangle {
                id: anchor
                x: 8; y: 8
                width: 120; height: 24
                color: Theme.surface
            }
            FloatingList {
                id: heldList
                anchorItem: anchor
                open: root.hosted && !root.dismissed
                onClosed: root.dismissed = true
                Text { text: "An option"; color: Theme.textPrimary }
            }
        }
    }

    // Where the pointer is in the window, over everything (a passive handler takes no press)
    Item {
        parent: anchor.Window.window ? anchor.Window.window.contentItem : null
        id: hoverLayer
        z: 5000
        anchors.fill: parent ?? undefined
        HoverHandler {
            id: hover
        }
    }

    IpcHandler {
        target: "probe"
        enabled: root.hosted

        // The pointer's place in the window, "<x>,<y>", or "" while it is outside
        function pointer(): string {
            if (!hover.hovered)
                return "";
            return Math.round(hover.point.position.x) + "," + Math.round(hover.point.position.y);
        }

        // What is drawn on top in the window: the held list (where it is shown) and a
        // tooltip (where one is shown), each "top" or "under" another item of the window's
        // top item (the kit's controls layer among them)
        function stacking(): string {
            const top = anchor.Window.window.contentItem;
            const onTop = item => {
                const centre = item.mapToItem(top, item.width / 2, item.height / 2);
                const hits = Array.from(top.children).map((child, index) => ({ child: child, index: index }))
                    .filter(entry => entry.child.visible && entry.child !== hoverLayer
                        && centre.x >= entry.child.x && centre.y >= entry.child.y
                        && centre.x < entry.child.x + entry.child.width && centre.y < entry.child.y + entry.child.height)
                    .sort((a, b) => a.child.z - b.child.z || a.index - b.index);
                return hits.length > 0 && hits[hits.length - 1].child === item ? "top" : "under";
            };
            const tip = Array.from(top.children).find(child => child.visible && child.target !== undefined && typeof child.delay === "number");
            return "list " + (heldList.visible ? onTop(heldList) : "hidden") + ", tip " + (tip ? onTop(tip) : "none");
        }

        function list(): string {
            return heldList.visible ? "shown" : "hidden";
        }

        // A spot in the window away from the list and the bar: near its bottom-left corner
        function outside(): string {
            const window = anchor.Window.window;
            return window ? "40," + Math.round(window.height - 40) : "";
        }
    }
}
