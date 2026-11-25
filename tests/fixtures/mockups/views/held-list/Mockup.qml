import QtQuick
import Quickshell.Io
import qs.singletons
import qs.components
import qs.mockups.kit

// A fixture view for tests/run-mockups-selftest.sh's real pointer in the gallery: hosted
// there, it holds a list open as a state shows an open menu, until a press outside it. The
// list's press catcher covers the whole window: the gallery's bar must still take a press.
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
