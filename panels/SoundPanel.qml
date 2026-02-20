import QtQuick
import Quickshell.Services.Pipewire
import qs.components
import qs.singletons

// Sound management popup with output/input volume sliders and device selectors
Item {
    id: root
    implicitWidth: 300
    implicitHeight: col.implicitHeight

    PwObjectTracker {
        id: nodeTracker
        objects: Audio.nodes
    }

    Column {
        id: col
        width: parent.implicitWidth
        spacing: 4

        AudioChannelRow { isSink: true;  width: parent.width }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.textDim
        }

        AudioChannelRow { isSink: false; width: parent.width }
    }
}
