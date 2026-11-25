import QtQuick
import qs.singletons
import qs.mockups.kit

// A fixture plan wider and taller than the test compositor's screen, with an item reaching
// above its content: on screen the scene buttons stay inside the window, above the
// content, and the content scrolls both ways
MockupWindow {
    id: root
    contentWidth: 2400
    contentHeight: 4000

    Rectangle {
        y: -40
        width: root.contentWidth
        height: root.contentHeight + 40
        color: Theme.surface
    }
}
