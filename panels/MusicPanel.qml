import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import qs.components
import qs.singletons
import qs.panels.music
import QtQuick.Effects

// The music popup: players to pick from, the cover, the track, seeking, transport, and the
// visualiser (Visualizer's levels, drawn by VisualizerCanvas) beside them, below them or
// around the cover
Item {
    id: root
    implicitWidth: Theme.popupWidth("music", 320)
    implicitHeight: col.implicitHeight

    // Cava runs only while the panel is open (Visualizer)
    Component.onCompleted: {
        Visualizer.addViewer();
        // A cover already loaded when the panel opens: no change of status will come
        Qt.callLater(_sampleCover);
    }
    Component.onDestruction: Visualizer.removeViewer()

    // From the active profile
    readonly property string visualizerStyle: Profiles.value("media.visualizerStyle") ?? "waveform"
    readonly property string visualizerLayout: Profiles.value("media.visualizerLayout") ?? "horizontal"
    readonly property bool _showVisualizer: Music.hasPlayer && visualizerStyle !== "none"
    readonly property bool _around: visualizerLayout === "around"

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

    // Glued to the popup's edges: the bottom ("horizontalBottom") or both sides
    // ("verticalSides"), growing inward only. Past the panel by the popup's padding, to its
    // very edge, and cut to the popup's shape — its bottom corners are rounded (or not, by
    // the screen's edge), read from the popup's background, the "overlayHost".
    readonly property bool _onEdges: visualizerLayout === "horizontalBottom" || visualizerLayout === "verticalSides"
    readonly property Item _popupBackground: {
        for (let item = parent; item; item = item.parent) {
            if (item.objectName === "overlayHost")
                return item;
        }
        return null;
    }
    readonly property int _padding: Theme.popup.contentPadding

    Item {
        id: _edges
        anchors {
            fill: parent
            leftMargin: -root._padding
            rightMargin: -root._padding
            topMargin: -root._padding
            bottomMargin: -root._padding
        }
        visible: root._onEdges && root._showVisualizer
        layer.enabled: visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: _edgeMask
            maskSpreadAtMin: 1
            maskThresholdMin: 0.5
        }

        // Up from the bottom: both channels, bass at both ends, as the centred strip
        VisualizerCanvas {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 56
            visible: root.visualizerLayout === "horizontalBottom"
            edge: "bottom"
            style: root.visualizerStyle
            bass: Visualizer.bass
            bars: Visualizer.leftBars.slice().reverse().concat(Visualizer.rightBars.slice().reverse())
        }

        // In from each side: a channel each, treble at the top, as the centred columns
        VisualizerCanvas {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 72
            visible: root.visualizerLayout === "verticalSides"
            edge: "left"
            style: root.visualizerStyle
            bass: Visualizer.bass
            bars: Visualizer.leftBars
        }

        VisualizerCanvas {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 72
            visible: root.visualizerLayout === "verticalSides"
            edge: "right"
            style: root.visualizerStyle
            bass: Visualizer.bass
            bars: Visualizer.rightBars.slice().reverse()
        }
    }

    // The popup's shape, for the mask
    Item {
        id: _edgeMask
        anchors.fill: _edges
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent
            bottomLeftRadius: root._popupBackground?.bottomLeftRadius ?? Theme.popup.radius
            bottomRightRadius: root._popupBackground?.bottomRightRadius ?? Theme.popup.radius
        }
    }

    // Vertical layout: a channel down each side, spanning the panel's height, bars growing
    // inward from the edge, the two in the same order top to bottom. Cava sends the
    // channels in opposite orders (mirrored, for one strip), so the right is turned round.
    VisualizerCanvas {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: 100
        visible: root.visualizerLayout === "vertical" && root._showVisualizer
        vertical: true
        style: root.visualizerStyle
        bass: Visualizer.bass
        bars: Visualizer.leftBars
    }

    VisualizerCanvas {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 100
        visible: root.visualizerLayout === "vertical" && root._showVisualizer
        vertical: true
        fromRight: true
        style: root.visualizerStyle
        bass: Visualizer.bass
        bars: Visualizer.rightBars.slice().reverse()
    }

    Column {
        id: col
        width: parent.implicitWidth
        spacing: 8

        // Player switcher list — hidden when 0 or 1 player
        Item {
            width: parent.width
            implicitHeight: playerList.implicitHeight
            visible: Music.players.values.length > 1

            Column {
                id: playerList
                width: parent.width
                spacing: 2

                Repeater {
                    // ScriptModel, never the bare array — see "The Repeater crash" in
                    // docs/ARCHITECTURE.md
                    model: ScriptModel {
                        values: Music.players.values
                    }

                    delegate: Text {
                        required property MprisPlayer modelData
                        width: parent.width
                        leftPadding: 8
                        text: "• " + (modelData.identity || modelData.desktopEntry || "Player")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        font.bold: modelData === Music.activePlayer
                        color: modelData === Music.activePlayer ? Theme.accent : Theme.textSecondary
                        elide: Text.ElideRight

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Music.selectPlayer(modelData)
                        }
                    }
                }
            }

            CustomMouseArea {
                anchors.fill: parent
                z: -1
                onScrollNotchY: direction => {
                    let players = Music.players.values;
                    let index = players.indexOf(Music.activePlayer);
                    let next = Math.max(0, Math.min(players.length - 1, index - direction));
                    Music.selectPlayer(players[next]);
                }
            }
        }

        // Album art row
        Item {
            id: _artRow
            width: parent.width
            // Around the cover: room for the visualiser on every side
            height: root._around ? root._coverSize + 90 : root._coverSize
            // Vertical and around: whenever there's a player (the visualiser needs its
            // place without art too). Horizontal: only with art (as it always was).
            visible: root.visualizerLayout.startsWith("horizontal") ? Music.artUrl !== "" : Music.hasPlayer

            VisualizerCanvas {
                anchors.fill: parent
                visible: root._around && root._showVisualizer
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

        // Track info; a new track's title and artist fade in
        Column {
            id: _trackInfo
            width: parent.width
            spacing: 2

            Connections {
                target: Music
                function onTitleChanged() { _trackFadeIn.restart() }
            }
            NumberAnimation {
                id: _trackFadeIn
                target: _trackInfo
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.duration("fade")
                easing: Theme.curve("fade")
            }

            Text {
                width: parent.width
                text: Music.hasPlayer ? (Music.title || "Unknown") : "No media"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
                color: Theme.textPrimary
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: Music.artist
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                visible: Music.artist !== ""
            }
        }

        // Seek bar
        SeekBar {
            width: parent.width
            position: Music.position
            duration: Music.length
            canSeek: Music.canSeek
            onSeeked: pos => Music.setPosition(pos)
            visible: Music.hasPlayer
        }

        // Transport controls
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 20
            visible: Music.hasPlayer

            // Previous
            Text {
                text: "󰒮"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLargeDisplay
                color: !Music.canPrev ? Theme.textDisabled : prevArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    id: prevArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Music.canPrev ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: Music.previous()
                }
            }

            // Play/Pause
            Text {
                text: Music.playing ? "󰏤" : "󰐊"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXXLargeDisplay
                color: playArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    id: playArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Music.togglePlay()
                }
            }

            // Next
            Text {
                text: "󰒭"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLargeDisplay
                color: !Music.canNext ? Theme.textDisabled : nextArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    id: nextArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Music.canNext ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: Music.next()
                }
            }
        }

        // Horizontal layout: both channels in one strip, bass at both ends and treble
        // meeting in the middle — cava's own stereo order the other way round, each channel
        // turned so it stays on its side
        VisualizerCanvas {
            width: parent.width
            height: 36
            visible: root.visualizerLayout === "horizontal" && root._showVisualizer
            style: root.visualizerStyle
            bass: Visualizer.bass
            bars: Visualizer.leftBars.slice().reverse().concat(Visualizer.rightBars.slice().reverse())
        }
    }
}
