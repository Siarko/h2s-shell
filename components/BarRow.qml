import QtQuick
import qs.singletons

// Items one after another along the bar: a row on a bar across the screen, a column on a
// bar at a side (BarLayout), centred across it. Children are placed by the grid, so they
// set no anchors of their own.
Grid {
    id: root
    readonly property bool vertical: BarLayout.vertical
    // As many columns as items laid out, for a row: the grid places only visible children
    // of some size (a Repeater, a hidden icon, an icon growing in from nothing take no
    // place), and a column more than that left an empty one and a gap more, the row wider
    // than a Row. Columns alone, not rows and columns swapped together, which left a moment
    // with one of each as the bar turned, too few for the children.
    readonly property int _placed: children.filter(child => child.visible && child.width > 0 && child.height > 0).length
    columns: vertical ? 1 : Math.max(1, _placed)
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter
}
