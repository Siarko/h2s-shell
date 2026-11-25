import QtQuick
import QtQuick.Effects
import qs.singletons
import qs.components
import qs.mockups.kit

// The runners' fixture mockup with the shader effects the shell uses: the renderer a mockup
// runs under must draw them the same each time (tests/run-mockups.sh). States:
//   text           a real component and plain text, no effect
//   rounded-image  the shell's RoundedImage (a MultiEffect mask over an Image)
//   shadow-blur    a MultiEffect with a shadow and a blur over a rounded rectangle
//   layer-effect   an item drawn through layer.effect (a MultiEffect colorization)
// and each once more, "<state>-again": the same state drawn later in the same process
// The image is loaded from the start (an Image that is not visible still loads), so that it
// is there before its state, whatever the order of frames
MockupWindow {
    id: root
    readonly property string shown: current.replace(/-again$/, "")
    contentWidth: 240
    contentHeight: 120

    Item {
        anchors.fill: parent
        visible: root.shown === "text"

        SmallButton {
            x: 20
            y: 20
            label: "Fixture"
        }
        Text {
            x: 20
            y: 70
            text: "Text 0123 ąęł"
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
        }
    }

    RoundedImage {
        x: 20
        y: 20
        width: 160
        height: 80
        radius: 16
        visible: root.shown === "rounded-image"
        source: Qt.resolvedUrl("../../../modules/icon-image/icon.png")
    }

    Item {
        anchors.fill: parent
        visible: root.shown === "shadow-blur"

        Rectangle {
            id: card
            x: 40
            y: 30
            width: 120
            height: 50
            radius: 12
            color: Theme.accent
            visible: false
        }
        MultiEffect {
            source: card
            anchors.fill: card
            shadowEnabled: true
            shadowBlur: 0.8
            shadowHorizontalOffset: 6
            shadowVerticalOffset: 6
            blurEnabled: true
            blur: 0.3
            blurMax: 16
        }
    }

    Rectangle {
        x: 40
        y: 30
        width: 140
        height: 60
        radius: 20
        color: Theme.accent
        visible: root.shown === "layer-effect"
        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 0.7
            colorizationColor: Theme.textPrimary
            brightness: 0.2
        }

        Text {
            anchors.centerIn: parent
            text: "Layer"
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
        }
    }
}
