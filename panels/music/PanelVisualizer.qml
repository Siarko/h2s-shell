import QtQuick
import QtQuick.Effects
import qs.singletons

// The music visualiser laid over the whole panel (fill it): the strip under the controls
// ("horizontal", in the place the panel keeps for it at its bottom, `stripHeight`), a
// column down each side ("vertical"), or glued to the popup's edges ("horizontalBottom",
// "verticalSides"). The ring round the cover is CoverArt's.
//
// All of it is drawn in one layer as large as the popup's background and cut to its shape
// — its corners away from the bar rounded, or not by the screen's edge — so a glow, which
// reaches past what it is drawn from, stops at the popup's edge instead of lighting the
// desktop beside it. The background (the popup's "overlayHost") is measured, not assumed: at the bar's
// end the popup drops a curve, and the panel then sits off its centre.
Item {
    id: root

    property string visualizerLayout: "horizontal"
    property string visualizerStyle: "waveform"
    property bool showVisualizer: false
    property int stripHeight: 36

    readonly property bool _shown: showVisualizer && visualizerLayout !== "around"

    readonly property Item _popupBackground: {
        for (let item = parent; item; item = item.parent) {
            if (item.objectName === "overlayHost")
                return item;
        }
        return null;
    }
    // The background, in this item's coordinates; without one (outside a popup), the
    // panel and the popup's padding round it
    readonly property rect _background: {
        const background = _popupBackground;
        const padding = Theme.popup.contentPadding;
        // Moves and resizes of either side bring this up to date
        void (root.x + root.y + root.width + root.height + (parent?.x ?? 0) + (parent?.y ?? 0));
        if (!background)
            return Qt.rect(-padding, -padding, width + 2 * padding, height + 2 * padding);
        void (background.width + background.height);
        return background.mapToItem(root, 0, 0, background.width, background.height);
    }

    // Each channel's bars, in the orders the layouts draw them; hidden canvases get none,
    // so nothing is rebuilt for them at every frame
    readonly property var _strip: Visualizer.leftBars.slice().reverse().concat(Visualizer.rightBars.slice().reverse())
    readonly property var _left: Visualizer.leftBars
    // Cava sends the channels in opposite orders (mirrored, for one strip): turned round,
    // the right runs top to bottom as the left does
    readonly property var _right: Visualizer.rightBars.slice().reverse()

    Item {
        id: _layer
        x: root._background.x
        y: root._background.y
        width: root._background.width
        height: root._background.height
        visible: root._shown
        layer.enabled: visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: _mask
            maskSpreadAtMin: 1
            maskThresholdMin: 0.5
        }

        // Glued to the popup's edges, growing inward. Up from the bottom: both channels,
        // bass at both ends, as the centred strip
        VisualizerCanvas {
            readonly property bool shown: root.visualizerLayout === "horizontalBottom"
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 56
            visible: shown
            edge: "bottom"
            style: root.visualizerStyle
            bass: Visualizer.bass
            bars: shown && root._shown ? root._strip : []
        }

        // In from each side: a channel each, treble at the top, as the centred columns
        VisualizerCanvas {
            readonly property bool shown: root.visualizerLayout === "verticalSides"
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 72
            visible: shown
            edge: "left"
            style: root.visualizerStyle
            bass: Visualizer.bass
            bars: shown && root._shown ? root._left : []
        }

        VisualizerCanvas {
            readonly property bool shown: root.visualizerLayout === "verticalSides"
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 72
            visible: shown
            edge: "right"
            style: root.visualizerStyle
            bass: Visualizer.bass
            bars: shown && root._shown ? root._right : []
        }

        // Where the panel is in the layer, for the layouts placed by the panel
        Item {
            x: -root._background.x
            y: -root._background.y
            width: root.width
            height: root.height

            // The strip under the controls: both channels, bass at both ends and treble
            // meeting in the middle — cava's own stereo order the other way round, each
            // channel turned so it stays on its side
            VisualizerCanvas {
                readonly property bool shown: root.visualizerLayout === "horizontal"
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: root.stripHeight
                visible: shown
                style: root.visualizerStyle
                bass: Visualizer.bass
                bars: shown && root._shown ? root._strip : []
            }

            // A channel down each side, spanning the panel's height, mirrored about its
            // own middle line (bars growing in from the edge)
            VisualizerCanvas {
                readonly property bool shown: root.visualizerLayout === "vertical"
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 100
                visible: shown
                vertical: true
                style: root.visualizerStyle
                bass: Visualizer.bass
                bars: shown && root._shown ? root._left : []
            }

            VisualizerCanvas {
                readonly property bool shown: root.visualizerLayout === "vertical"
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 100
                visible: shown
                vertical: true
                fromRight: true
                style: root.visualizerStyle
                bass: Visualizer.bass
                bars: shown && root._shown ? root._right : []
            }
        }
    }

    // The popup's shape, for the mask
    Item {
        id: _mask
        anchors.fill: _layer
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent
            // Rounded where the background is: away from the bar, at either edge
            topLeftRadius: root._popupBackground?.topLeftRadius ?? 0
            topRightRadius: root._popupBackground?.topRightRadius ?? 0
            bottomLeftRadius: root._popupBackground?.bottomLeftRadius ?? Theme.popup.radius
            bottomRightRadius: root._popupBackground?.bottomRightRadius ?? Theme.popup.radius
        }
    }
}
