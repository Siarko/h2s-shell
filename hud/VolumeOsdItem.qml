import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// Self-contained volume OSD. Slides in from the right edge at screen center
// whenever Audio.volume or Audio.muted changes, then auto-dismisses after 2 s.
Item {
    id: root

    required property int screenWidth
    required property int screenHeight

    // Wide enough for the widest volume label ("100%" already overflowed 50 px), and the
    // card's 10 px margin either side
    readonly property int cardWidth: Math.max(50, Math.ceil(_widestLabel.advanceWidth) + 20)
    TextMetrics {
        id: _widestLabel
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMedium
        font.bold: true
        text: "888%"
    }
    readonly property int cardHeight: 280
    readonly property int restX: screenWidth - cardWidth

    x: screenWidth
    y: (screenHeight - cardHeight) / 2
    width: cardWidth
    height: cardHeight

    function showOsd() {
        autoCloseTimer.restart();
        if (root.x > root.restX) {
            slideOut.stop();
            slideIn.start();
        }
    }

    Connections {
        target: Audio
        function onVolumeChanged() {
            root.showOsd();
        }
        function onMutedChanged() {
            root.showOsd();
        }
    }

    NumberAnimation {
        id: slideIn
        target: root
        property: "x"
        to: root.restX
        duration: Theme.duration("enter")
        easing: Theme.curve("enter")
    }

    NumberAnimation {
        id: slideOut
        target: root
        property: "x"
        to: root.screenWidth
        duration: Theme.duration("exit")
        easing: Theme.curve("exit")
    }

    Timer {
        id: autoCloseTimer
        interval: 2000
        onTriggered: slideOut.start()
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered)
                autoCloseTimer.stop();
            else
                autoCloseTimer.restart();
        }
    }

    Rectangle {
        width: root.cardWidth
        height: root.cardHeight
        topLeftRadius: 6
        bottomLeftRadius: 6
        color: Theme.surface

        ColumnLayout {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 10
            }
            spacing: 4

            // Mute icon
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Audio.muted ? "󰖁" : "󰕾"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeHeading
                color: Audio.muted ? Theme.textDisabled : Theme.textPrimary
            }

            // Volume label
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Audio.volume + "%"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
                color: Audio.volume > 100 ? Theme.warning : Theme.textPrimary
            }

            // Vertical slider
            VerticalSlider {
                Layout.fillWidth: true
                Layout.fillHeight: true
                value: Audio.volume / 100.0
                maxValue: 1.5
                warningThreshold: 1.0
                onMoved: newValue => {
                    if (Audio.sink?.audio)
                        Audio.sink.audio.volume = newValue;
                }
            }
        }
    }
}
