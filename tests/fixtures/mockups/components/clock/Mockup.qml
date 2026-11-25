import QtQuick
import qs.singletons
import qs.mockups.kit

// A fixture mockup that keeps time of its own, which no state may: a Timer, a read of the
// clock, an animation of a literal duration. A load-only run must fail it
MockupWindow {
    id: root
    names: ["first"]
    contentWidth: 100
    contentHeight: 50

    Text {
        id: label
        text: new Date().toISOString()
        color: Theme.textPrimary
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
    Timer {
        interval: 1000
        running: true
        onTriggered: label.opacity = 0.5
    }
}
