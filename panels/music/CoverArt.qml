import QtQuick
import QtQuick.Effects
import qs.singletons

// The music panel's cover row: the cover (rounded, turning while playing), a stand-in when
// the player gives none, and the visualiser around it — in the cover's own colours when
// wanted (CoverColors). The rest of the visualiser layouts are PanelVisualizer's.
Item {
    id: root

    property string visualizerLayout: "horizontal"
    property string visualizerStyle: "waveform"
    property bool showVisualizer: false
    readonly property bool _around: visualizerLayout === "around"

    // A cover already loaded when the panel opens: no change of status will come
    Component.onCompleted: Qt.callLater(_sampleCover)

    // The cover: 0 % square, 100 % a circle; turning while playing, in degrees a second
    // (below 0 anticlockwise)
    readonly property int _coverSize: 120
    readonly property real _coverRadius: (Profiles.value("media.coverRounding") ?? 33) / 100 * _coverSize / 2
    readonly property real _coverSpeed: Profiles.value("media.coverRotation") ?? 0
    property real _coverAngle: 0
    // Paused, it stops where it is; turned back off, it comes to rest upright
    FrameAnimation {
        running: root._coverSpeed !== 0 && Music.playing && !Theme.reduceMotion && root.visible
        onTriggered: root._coverAngle = (root._coverAngle + root._coverSpeed * frameTime) % 360
    }
    on_CoverSpeedChanged: if (_coverSpeed === 0) _coverAngle = 0

    // Around the cover, optionally in the cover's own colours (CoverColors), found each time
    // a cover loads; none (a grey cover, none yet) leaves the theme's colour
    readonly property bool _coverColors: Profiles.value("media.coverColors") ?? false
    property var _coverPalette: []

    // Reads the shown cover's colours — whenever a cover may have changed: it loaded, the
    // track changed (a player may reuse the cover's address), the setting was turned on.
    // What was read before for this cover shows at once. A Canvas asked to paint before its
    // window can draw (a popup's content is made before the popup shows) never paints, so
    // the read is asked again until it has really happened.
    readonly property string _coverKey: Music.artUrl + "\n" + Music.title
    property bool _samplePending: false
    property int _sampleTries: 0
    // Whether the shown cover's colours are known (read, or remembered)
    property bool _paletteKnown: false

    // Around a cover being read, with its colours wanted, the visualiser waits unseen —
    // not in the theme's colour first — and fades in once they are known (or found to be
    // none). Hidden at once, shown by a quick fade.
    readonly property bool _waitsForColors: _coverColors && _around && Music.artUrl !== "" && !_paletteKnown
    property real _aroundOpacity: _waitsForColors ? 0 : 1
    on_WaitsForColorsChanged: {
        if (_waitsForColors) {
            _aroundFade.stop();
            _aroundOpacity = 0;
        } else {
            _aroundFade.restart();
        }
    }
    NumberAnimation {
        id: _aroundFade
        target: root
        property: "_aroundOpacity"
        to: 1
        duration: Theme.duration("fade")
        easing: Theme.curve("fade")
    }

    function _sampleCover() {
        if (image.status !== Image.Ready) {
            _coverPalette = [];
            _paletteKnown = false;
            _samplePending = false;
            return;
        }
        const known = CoverColors.recall(_coverKey);
        if (known !== null) {
            _coverPalette = known;
            _paletteKnown = true;
        }
        _samplePending = true;
        _sampleTries = 0;
        _coverSample.requestPaint();
    }

    Timer {
        interval: 200
        repeat: true
        running: root._samplePending
        onTriggered: {
            // Ten seconds at most: a cover that never draws is left alone
            if (++root._sampleTries > 50)
                root._samplePending = false;
            else
                _coverSample.requestPaint();
        }
    }
    on_CoverColorsChanged: if (_coverColors) _sampleCover()
    Connections {
        target: Music
        function onTitleChanged() { _resample.restart() }
    }
    // After the new cover has had a moment to load
    Timer {
        id: _resample
        interval: 300
        onTriggered: root._sampleCover()
    }

    // Around the cover: room for the visualiser on every side
    height: root._around ? root._coverSize + 90 : root._coverSize
    // Vertical and around: whenever there's a player (the visualiser needs its
    // place without art too). Horizontal: only with art (as it always was).
    visible: root.visualizerLayout.startsWith("horizontal") ? Music.artUrl !== "" : Music.hasPlayer

    VisualizerCanvas {
        anchors.fill: parent
        visible: root._around && root.showVisualizer
        opacity: root._aroundOpacity
        around: true
        style: root.visualizerStyle
        bass: Visualizer.bass
        coverHalf: root._coverSize / 2
        coverRadius: root._coverRadius
        coverAngle: root._coverAngle
        colors: root._coverColors ? root._coverPalette : []
        // Clockwise from the top: the right channel treble to bass down the right,
        // the left bass to treble up the left — bass meeting at the bottom
        bars: Visualizer.rightBars.slice().reverse().concat(Visualizer.leftBars.slice().reverse())
    }

    // The cover drawn small, to read its colours from (CoverColors). Under the cover,
    // never inside it: a Canvas that is not shown does not paint, and the cover is
    // transparent while it fades in — just when it is read.
    Canvas {
        id: _coverSample
        anchors.centerIn: parent
        width: 24
        height: 24
        onAvailableChanged: if (available && root._samplePending) requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (image.status !== Image.Ready)
                return;
            ctx.drawImage(image, 0, 0, width, height);
            const pixels = ctx.getImageData(0, 0, width, height).data;
            // Nothing drawn (every pixel transparent): not read yet, ask again
            let drawn = false;
            for (let i = 3; i < pixels.length && !drawn; i += 4)
                drawn = pixels[i] > 0;
            if (!drawn)
                return;
            root._coverPalette = CoverColors.palette(pixels, 3);
            CoverColors.remember(root._coverKey, root._coverPalette);
            root._paletteKnown = true;
            root._samplePending = false;
        }
    }

    // No cover from the player: a stand-in for the visualiser to go round
    Rectangle {
        anchors.centerIn: parent
        width: root._coverSize
        height: root._coverSize
        radius: root._coverRadius
        rotation: root._coverAngle
        visible: root._around && Music.artUrl === ""
        color: Theme.surfaceSunken

        Text {
            anchors.centerIn: parent
            text: "󰝚"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXXLargeDisplay
            color: Theme.textMuted
        }
    }

    // Album art (centered, always 120×120)
    Rectangle {
        id: _art
        anchors.centerIn: parent
        width: root._coverSize
        height: root._coverSize
        rotation: root._coverAngle
        // Only a frame: the cover's rounding comes from its mask below
        color: "transparent"
        clip: true
        visible: Music.artUrl !== ""
        // A new track's cover fades in once it has loaded
        opacity: image.status === Image.Ready ? 1 : 0
        Connections {
            target: image
            function onStatusChanged() {
                if (image.status === Image.Ready)
                    _artFadeIn.restart();
                else
                    _art.opacity = 0;
                root._sampleCover();
            }
        }

        NumberAnimation {
            id: _artFadeIn
            target: _art
            from: 0
            property: "opacity"
            to: 1
            duration: Theme.duration("fade")
            easing: Theme.curve("fade")
        }

        MultiEffect {
            source: image
            anchors.fill: image
            maskEnabled: true
            maskSource: mask
            maskSpreadAtMin: 1
            maskThresholdMin: 0.5
        }

        Image {
            id: image
            anchors.fill: parent
            source: Music.artUrl
            fillMode: Image.PreserveAspectCrop
            visible: false
        }

        Item {
            id: mask
            anchors.fill: image
            layer.enabled: true
            visible: false

            Rectangle {
                anchors.fill: parent
                radius: root._coverRadius
            }
        }
    }
}
