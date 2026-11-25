import QtQuick
import qs.components
import qs.mockups.kit

// The runners' fixture mockup that loads: two states of a real component, cropped to it
MockupWindow {
    id: root
    contentWidth: 200
    contentHeight: 80
    subject: button

    SmallButton {
        id: button
        x: 20
        y: 20
        label: "Fixture"
        checked: root.current === "checked"
    }
}
