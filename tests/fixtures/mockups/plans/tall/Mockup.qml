import QtQuick
import qs.singletons
import qs.mockups.kit

// A fixture plan taller than any screen, with an item reaching above its content:
// on screen the scene buttons stay inside the window, above the content
MockupWindow {
    id: root
    names: ["first", "second", "third"]
    contentWidth: 300
    contentHeight: 4000

    Rectangle {
        y: -40
        width: root.contentWidth
        height: root.contentHeight + 40
        color: Theme.surface
    }
}
