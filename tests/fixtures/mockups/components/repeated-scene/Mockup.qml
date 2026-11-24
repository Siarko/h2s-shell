import QtQuick
import qs.mockups.kit

// A fixture mockup whose scene list names a scene twice: an error
MockupWindow {
    scenes: ["first", "second", "first"]
    contentWidth: 100
    contentHeight: 50
}
