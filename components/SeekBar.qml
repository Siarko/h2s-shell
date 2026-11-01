import QtQuick
import QtQuick.Layouts
import qs.singletons

// Seekable progress bar with time labels, modeled after VolumeSlider
Item {
    id: seekBar
    Layout.fillWidth: true
    Layout.preferredHeight: 30
    // Its height outside a layout too: the music panel stacks it in a Column, which reads
    // no Layout properties — with only those it was 0 tall there, and never seen
    implicitHeight: 30

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

    // Both times as wide as the longest the track can show (its length, every digit an
    // 8), so the track keeps its width as the position counts up
    readonly property real _timeWidth: Math.ceil(_widestTime.advanceWidth)
    TextMetrics {
        id: _widestTime
        font: _positionText.font
        text: seekBar._formatTime(Math.max(seekBar.duration, 600)).replace(/[0-9]/g, "8")
    }

    RowLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            id: _positionText
            text: seekBar._formatTime(seekBar.position)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textSecondary
            Layout.preferredWidth: seekBar._timeWidth
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
                radius: height / 2
                color: seekArea.containsMouse && seekBar.canSeek ? Theme.textSecondary : Theme.textDisabled
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                Rectangle {
                    width: seekBar._fraction * parent.width
                    height: parent.height
                    radius: height / 2
                    color: seekArea.containsMouse && seekBar.canSeek ? Theme.accentHover : Theme.accent
                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                }
            }

            Rectangle {
                x: seekBar._fraction * (track.width - width)
                anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14; radius: 7
                color: seekArea.pressed ? Theme.textSecondary : Theme.textPrimary
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
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
            Layout.preferredWidth: seekBar._timeWidth
        }
    }
}
