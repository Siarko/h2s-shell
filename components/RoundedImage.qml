import QtQuick
import QtQuick.Effects

// An image cropped to fill its size, with rounded corners — through a mask, as
// Quickshell 0.3 has no clipping rectangle (the music panel's cover does the same).
Item {
    id: root

    property alias source: _image.source
    property alias sourceSize: _image.sourceSize
    property alias status: _image.status
    property real radius: 0

    Image {
        id: _image
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    MultiEffect {
        source: _image
        anchors.fill: parent
        maskEnabled: true
        maskSource: _mask
        maskSpreadAtMin: 1
        maskThresholdMin: 0.5
    }

    Item {
        id: _mask
        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: root.radius
        }
    }
}
