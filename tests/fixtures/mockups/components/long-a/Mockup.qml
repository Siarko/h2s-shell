import QtQuick
import qs.singletons
import qs.mockups.kit

// The runners' tall fixture component: four cells of 500 px one under another on screen, so
// that the gallery's section grows far beyond its placeholder when it is built
MockupWindow {
    id: root

    StateGrid {
        cellWidth: 200
        cellHeight: 500
        stacked: true

        Repeater {
            model: root.names.length
            StateCell {
                required property int index
                name: root.names[index]

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 8
                    color: Theme.surface
                }
            }
        }
    }
}
