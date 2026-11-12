import QtQuick
import qs.singletons

// What a wallpaper fit does, shown on a small screen (Wallpaper settings): an image of
// other proportions than the screen shows up in the middle, a little smaller than its own
// size, and moves to where the fit puts it — Fill grows past the screen (the cut-off parts stay as a faint ghost outside),
// Fit grows to the screen's edge with the background colour beside, Centre keeps its size
// in the middle, Tile repeats it from the corner. Played in a loop; with reduced motion it
// shows where the image ends up.
Item {
    id: root

    // "cover", "contain", "centre", "tile" (wallpaper.fit)
    property string fit: "cover"
    // The background colour around the image
    property color background: "#000000"
    // An image to show as the wallpaper (absolute path), or "" for a drawn landscape
    property string image: ""
    // The screen's proportions, width / height
    property real aspect: 16 / 10
    // Off: still, the image where the fit puts it
    property bool playing: true

    implicitWidth: 300
    implicitHeight: Math.round(_screenWidth / aspect) + 2 * _margin

    // Room beside the screen for the parts Fill cuts off: an image 2.2 wide to a screen
    // 1.6 wide sticks out by under a fifth of the screen on each side
    readonly property real _margin: 2
    readonly property real _screenWidth: width / 1.4
    readonly property real _screenX: (width - _screenWidth) / 2
    readonly property real _screenHeight: _screenWidth / aspect
    // The image's own shape and size: wider than the screen, smaller than it
    readonly property real _imageAspect: 2.2
    readonly property real _naturalWidth: (fit === "tile" ? 0.36 : 0.62) * _screenWidth
    readonly property real _naturalHeight: _naturalWidth / _imageAspect

    // Where the fit puts the image, in the screen's coordinates
    readonly property rect _fitted: {
        const width = _naturalWidth, height = _naturalHeight;
        if (fit === "cover" || fit === "contain") {
            const scale = fit === "cover" ? Math.max(_screenWidth / width, _screenHeight / height)
                                          : Math.min(_screenWidth / width, _screenHeight / height);
            return Qt.rect((_screenWidth - width * scale) / 2, (_screenHeight - height * scale) / 2, width * scale, height * scale);
        }
        if (fit === "tile")
            return Qt.rect(0, 0, width, height);
        return Qt.rect((_screenWidth - width) / 2, (_screenHeight - height) / 2, width, height);
    }
    // Where it shows up: in the middle, a little smaller than its own size
    readonly property rect _start: Qt.rect((_screenWidth - _naturalWidth * 0.8) / 2, (_screenHeight - _naturalHeight * 0.8) / 2,
                                           _naturalWidth * 0.8, _naturalHeight * 0.8)

    // 0 → 1: from coming in to fitted
    property real _progress: Theme.reduceMotion || !playing ? 1 : 0
    readonly property rect _now: Qt.rect(
        _start.x + (_fitted.x - _start.x) * _progress,
        _start.y + (_fitted.y - _start.y) * _progress,
        _start.width + (_fitted.width - _start.width) * _progress,
        _start.height + (_fitted.height - _start.height) * _progress)

    // Starts over when the fit changes, so the new one is seen from the beginning
    onFitChanged: if (_loop.running) _loop.restart()

    SequentialAnimation {
        id: _loop
        running: root.playing && root.visible && !Theme.reduceMotion
        // Stopped mid-loop (reduced motion turned on, say): shown where it ends up
        onRunningChanged: if (!running) { root._progress = 1; _picture.opacity = 1; }
        loops: Animation.Infinite

        PropertyAction { target: root; property: "_progress"; value: 0 }
        NumberAnimation { target: _picture; property: "opacity"; from: 0; to: 1; duration: 250 }
        PauseAnimation { duration: 450 }
        NumberAnimation { target: root; property: "_progress"; from: 0; to: 1; duration: 1000; easing.type: Easing.InOutCubic }
        PauseAnimation { duration: 1800 }
        NumberAnimation { target: _picture; property: "opacity"; to: 0; duration: 300 }
    }

    // The picture itself: the wallpaper cut to the image's shape, or a drawn landscape
    component Picture: Item {
        Image {
            anchors.fill: parent
            visible: root.image !== ""
            source: root.image === "" ? "" : "file://" + root.image.split("/").map(encodeURIComponent).join("/")
            sourceSize: Qt.size(root._screenWidth * 2, root._screenWidth * 2 / root._imageAspect)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }
        Item {
            anchors.fill: parent
            visible: root.image === ""
            clip: true
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.4) }
                    GradientStop { position: 1; color: Theme.accent }
                }
            }
            Rectangle {
                x: parent.width * 0.68
                y: parent.height * 0.18
                width: parent.height * 0.32
                height: width
                radius: width / 2
                color: Theme.warning
            }
            Rectangle {
                width: parent.width
                height: parent.height * 0.3
                anchors.bottom: parent.bottom
                color: Qt.darker(Theme.accent, 1.8)
            }
        }
    }

    // The parts outside the screen, faintly: what Fill cuts off
    Picture {
        id: _ghost
        x: root._screenX + root._now.x
        y: root._margin + root._now.y
        width: root._now.width
        height: root._now.height
        opacity: _picture.opacity * 0.22
        visible: root.fit !== "tile"
    }

    // The screen
    Rectangle {
        id: _screen
        x: root._screenX
        y: root._margin
        width: root._screenWidth
        height: root._screenHeight
        color: root.background
        clip: true

        Item {
            id: _picture
            anchors.fill: parent

            Picture {
                x: root._now.x
                y: root._now.y
                width: root._now.width
                height: root._now.height
            }

            // Tile: the copies, coming in once the first is in its corner
            Repeater {
                // Never below 0: the sizes are 0 for a moment while the page lays out
                model: root.fit === "tile" && root._naturalWidth > 0
                    ? Math.max(0, Math.ceil(root._screenWidth / root._naturalWidth) * Math.ceil(root._screenHeight / root._naturalHeight) - 1) : 0

                Picture {
                    required property int index
                    readonly property int _columns: Math.ceil(root._screenWidth / root._naturalWidth)
                    x: ((index + 1) % _columns) * root._naturalWidth
                    y: Math.floor((index + 1) / _columns) * root._naturalHeight
                    width: root._naturalWidth
                    height: root._naturalHeight
                    opacity: Math.max(0, Math.min(1, root._progress * 3 - 2 - index * 0.04))
                }
            }
        }
    }

    // The screen's edge, over everything
    Rectangle {
        x: root._screenX
        y: root._margin
        width: root._screenWidth
        height: root._screenHeight
        color: "transparent"
        radius: 3
        border.width: Theme.border.selectedWidth
        border.color: Theme.textSecondary
    }
}
