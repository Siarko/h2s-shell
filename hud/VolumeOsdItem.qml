import QtQuick
import QtQuick.Layouts
import qs.singletons

// Self-contained volume OSD. Slides in from the right edge at screen center
// whenever Audio.volume or Audio.muted changes, then auto-dismisses after 2 s.
Item {
    id: root

    required property int screenWidth
    required property int screenHeight

    readonly property int cardWidth: 50
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
        duration: 250
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: slideOut
        target: root
        property: "x"
        to: root.screenWidth
        duration: 200
        easing.type: Easing.InCubic
    }

    Timer {
        id: autoCloseTimer
        interval: 2000
        onTriggered: slideOut.start()
    }

    Rectangle {
        width: root.cardWidth
        height: root.cardHeight
        topLeftRadius: 6
        bottomLeftRadius: 6
        color: Theme.cellDefault

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
                font.pixelSize: 18
                color: Audio.muted ? Theme.textDim : Theme.textPrimary
            }

            // Volume label
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Audio.volume + "%"
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                color: Audio.volume > 100 ? Theme.textWarning : Theme.textPrimary
            }

            // Vertical slider
            Item {
                id: sliderItem
                Layout.fillWidth: true
                Layout.fillHeight: true

                readonly property real maxVolume: 1.5
                readonly property real rawVolume: Audio.volume / 100.0
                // Clamp to 1.0 so the fill never exceeds the track
                readonly property real normalized: Math.min(rawVolume / maxVolume, 1.0)
                // Leave 6 px top + 6 px bottom for the thumb to overhang
                readonly property real trackH: height - 12
                readonly property real fillH: normalized * trackH
                // Y-offset on the track where 100% volume sits
                readonly property real markPos: trackH * (1.0 / maxVolume)

                // Track background
                Rectangle {
                    id: trackBg
                    x: (parent.width - width) / 2
                    y: 6
                    width: 6
                    height: sliderItem.trackH
                    radius: 3
                    color: Theme.textDim

                    // Normal fill (0 – 100%)
                    Rectangle {
                        id: normalFill
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.min(sliderItem.fillH, sliderItem.markPos)
                        radius: parent.radius
                        color: Theme.sliderAccent
                    }

                    // Over fill (>100%), stacked above the normal fill
                    Rectangle {
                        anchors.bottom: normalFill.top
                        width: parent.width
                        height: Math.max(0, sliderItem.fillH - sliderItem.markPos)
                        radius: parent.radius
                        color: Theme.textWarning
                    }
                }

                // Thumb
                Rectangle {
                    x: (parent.width - width) / 2
                    y: 6 + sliderItem.trackH - sliderItem.fillH - height / 2
                    width: 12
                    height: 12
                    radius: 6
                    color: dragArea.pressed ? Theme.textSecondary : Theme.textPrimary
                }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor

                    onPressed: mouse => setVol(mouse.y)
                    onPositionChanged: mouse => {
                        if (pressed)
                            setVol(mouse.y);
                    }
                    onWheel: event => {
                        if (!Audio.sink?.audio)
                            return;
                        var delta = event.angleDelta.y / 120 * 0.02;
                        Audio.sink.audio.volume = Math.max(0, Math.min(sliderItem.maxVolume, Audio.sink.audio.volume + delta));
                    }

                    function setVol(mouseY) {
                        if (!Audio.sink?.audio)
                            return;
                        // mouseY within the track (y=6 … y=6+trackH)
                        var frac = 1.0 - Math.max(0, Math.min(1, (mouseY - 6) / sliderItem.trackH));
                        Audio.sink.audio.volume = frac * sliderItem.maxVolume;
                    }
                }
            }
        }
    }
}
