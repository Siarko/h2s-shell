import QtQuick
import Quickshell.Io
import qs.components
import qs.mockups.kit

// A fixture plan for tests/run-mockups-selftest.sh's real pointer: its first scene holds a
// list open as a plan holds a menu open (bound to the scene), dismissed by a press outside
// it until the scene is entered again. The list's press catcher covers the whole window:
// the kit's scene buttons must still take a press above it.
MockupWindow {
    id: root
    contentWidth: 300
    contentHeight: 200

    property bool dismissed: false
    onCurrentChanged: dismissed = false

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
