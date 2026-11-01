pragma Singleton

import Quickshell

// Where the bar stands and how its content runs, for the bar and every widget on it:
// the same bar on every screen, so one answer for all (docs/plans/bar-position.md)
Singleton {
    id: root

    // The screen edge (bar.edge): "top", "bottom", "left" or "right"
    readonly property string edge: {
        const value = Profiles.value("bar.edge");
        return BarGeometry.edges.includes(value) ? value : "top";
    }
    // A bar at a side: widgets stack down it
    readonly property bool vertical: BarGeometry.isVertical(edge)
    // How text runs on it (bar.verticalText): "rotated" or "stacked"
    readonly property string verticalText: Profiles.value("bar.verticalText") === "stacked" ? "stacked" : "rotated"
}
