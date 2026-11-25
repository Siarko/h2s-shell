import QtQuick
import Quickshell.Io
import qs.components
import qs.mockups.kit

// A fixture plan for tests/run-mockups-selftest.sh's real pointer: its first scene holds a
// list open as a plan holds a menu open (bound to the scene), dismissed by a press outside
// it until the scene is entered again. The list's press catcher covers the whole window:
// the kit's scene buttons must still take a press above it, while the list and a button's
// tooltip are drawn over them.
MockupWindow {
    id: root
    contentWidth: 300
    contentHeight: 200

    property bool dismissed: false
    onCurrentChanged: dismissed = false
    // The scene's own button pressed again opens its list again
    onChosen: dismissed = false

    Rectangle {
        id: anchor
        x: 10; y: 10
        width: 120; height: 24
        color: "grey"
        visible: root.current === "open"
    }
    FloatingList {
        id: heldList
        anchorItem: anchor
        open: root.current === "open" && !root.dismissed
        onClosed: root.dismissed = true
        Text { text: "An option" }
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

    // A spot in the content away from the list
    Item {
        id: spot
        x: 250; y: 170
        width: 1; height: 1
    }

    IpcHandler {
        target: "probe"

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

        // The spot outside the list, in window coordinates
        function outside(): string {
            const at = spot.mapToItem(null, 0, 0);
            return Math.round(at.x) + "," + Math.round(at.y);
        }
    }
}
