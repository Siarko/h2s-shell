import QtQuick
import QtTest
import Quickshell.Io
import qs.components
import qs.mockups.kit

// A fixture plan whose first scene holds a list open (bound open, as a plan shows an open
// menu) and whose second scene has a button: once the first scene is hidden, its list and
// the press catcher that closes it must not stay over the window and take the clicks
MockupWindow {
    id: root
    contentWidth: 300
    contentHeight: 200

    property int clicks: 0

    Item {
        anchors.fill: parent
        visible: root.current === "open"
        Rectangle {
            id: anchor
            x: 10; y: 10
            width: 120; height: 24
            color: "grey"
        }
        FloatingList {
            anchorItem: anchor
            open: true
            Text { text: "An option" }
        }
    }

    Item {
        anchors.fill: parent
        visible: root.current === "button"
        Rectangle {
            id: button
            x: 10; y: 60
            width: 120; height: 40
            color: "steelblue"
            MouseArea {
                anchors.fill: parent
                onClicked: root.clicks++
            }
        }
    }

    TestCase {
        id: pointer
        when: false
    }

    // The probe the run-mockups self-test drives: a scene shown, then a click on the button
    IpcHandler {
        target: "probe"

        function scene(name: string): string {
            root.current = name;
            return root.current;
        }

        function click(): string {
            if (!button.visible)
                return "hidden";
            pointer.mouseClick(button, button.width / 2, button.height / 2);
            return "clicks " + root.clicks;
        }
    }
}
