import QtQuick
import qs.mockups.kit

// A fixture mockup that loads and steps through its scenes, with a QML warning from its own
// file on the way: a load-only run must fail it
MockupWindow {
    scenes: ["first"]
    contentWidth: 100
    contentHeight: 50

    Text {
        text: undefined
    }
}
