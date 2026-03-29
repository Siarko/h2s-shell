import QtQuick
import QtQuick.Layouts
import qs.singletons

// Seekable progress bar with time labels, modeled after VolumeSlider
Item {
    id: seekBar
    Layout.fillWidth: true
    Layout.preferredHeight: 30

    property real position: 0   // current position in seconds
    property real duration: 0   // total duration in seconds
    property bool canSeek: false
    signal seeked(real position)

    property real _fraction: duration > 0 ? Math.min(1, position / duration) : 0

    function _formatTime(seconds) {
        var s = Math.floor(seconds);
        var m = Math.floor(s / 60);
        s = s % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    RowLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            text: seekBar._formatTime(seekBar.position)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textSecondary
            Layout.preferredWidth: 32
            horizontalAlignment: Text.AlignRight
        }

        Item {
            id: track
            Layout.fillWidth: true
            Layout.preferredHeight: 20

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                radius: 2
                color: seekArea.containsMouse && seekBar.canSeek ? Theme.textSecondary : Theme.textDim

                Rectangle {
                    width: seekBar._fraction * parent.width
                    height: parent.height
                    radius: 2
                    color: seekArea.containsMouse && seekBar.canSeek ? Theme.sliderAccentHover : Theme.sliderAccent
                }
            }

            Rectangle {
                x: seekBar._fraction * (track.width - width)
                anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14; radius: 7
                color: seekArea.pressed ? Theme.textSecondary : Theme.textPrimary
                visible: seekBar.canSeek
            }

            MouseArea {
                id: seekArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: seekBar.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: seekBar.canSeek
                onPressed: mouse => update(mouse.x)
                onPositionChanged: mouse => { if (pressed) update(mouse.x); }

                function update(mouseX) {
                    var frac = Math.max(0, Math.min(1, mouseX / width));
                    seekBar.seeked(frac * seekBar.duration);
                }
            }
        }

        Text {
            text: seekBar._formatTime(seekBar.duration)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textSecondary
            Layout.preferredWidth: 32
        }
    }
}
