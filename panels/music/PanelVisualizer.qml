import QtQuick
import QtQuick.Effects
import qs.singletons

// The music visualiser laid over the whole panel (fill it): down each side, centred
// ("vertical"), or glued to the popup's edges ("horizontalBottom", "verticalSides"). The
// strip under the controls is the panel's, the ring round the cover CoverArt's.
Item {
    id: root

    property string visualizerLayout: "horizontal"
    property string visualizerStyle: "waveform"
    property bool showVisualizer: false

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
        visible: root._onEdges && root.showVisualizer
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
        visible: root.visualizerLayout === "vertical" && root.showVisualizer
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
        visible: root.visualizerLayout === "vertical" && root.showVisualizer
        vertical: true
        fromRight: true
        style: root.visualizerStyle
        bass: Visualizer.bass
        bars: Visualizer.rightBars.slice().reverse()
    }

}
