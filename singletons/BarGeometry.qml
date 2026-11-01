pragma Singleton

import Quickshell

// The bar's geometry at any screen edge (docs/plans/bar-position.md). The theme's bar
// tokens are relative to the bar's edge: `topOffset` is the gap to the screen's edge, the
// left and right margins and paddings are the bar's start and end, the `Top*` corners are
// the ones at the screen's edge and the `Bottom*` ones face the desktop. These turn them
// into what is drawn. Pure functions: no I/O, so the test suite checks them.
Singleton {
    id: root

    readonly property var edges: ["top", "bottom", "left", "right"]

    // The edge the bar's desktop side faces: where its border goes, where popups open from
    function desktopEdge(edge) {
        return ({ top: "bottom", bottom: "top", left: "right", right: "left" })[edge] ?? "bottom";
    }

    function isVertical(edge) {
        return edge === "left" || edge === "right";
    }

    // A corner token (percent of half the bar's thickness) in pixels
    function radius(percent, barHeight) {
        return (percent ?? 0) / 100 * ((barHeight ?? 0) / 2);
    }

    // The bar's corners on screen, in pixels, from the theme's `bar` values:
    // { topLeft, topRight, bottomLeft, bottomRight }. The start of a vertical bar is its
    // top end.
    function corners(edge, bar) {
        const atScreenStart = radius(bar.radiusTopLeft, bar.barHeight);
        const atScreenEnd = radius(bar.radiusTopRight, bar.barHeight);
        const atDesktopStart = radius(bar.radiusBottomLeft, bar.barHeight);
        const atDesktopEnd = radius(bar.radiusBottomRight, bar.barHeight);
        switch (edge) {
        case "bottom":
            return { topLeft: atDesktopStart, topRight: atDesktopEnd, bottomLeft: atScreenStart, bottomRight: atScreenEnd };
        case "left":
            return { topLeft: atScreenStart, topRight: atDesktopStart, bottomLeft: atScreenEnd, bottomRight: atDesktopEnd };
        case "right":
            return { topLeft: atDesktopStart, topRight: atScreenStart, bottomLeft: atDesktopEnd, bottomRight: atScreenEnd };
        default:
            return { topLeft: atScreenStart, topRight: atScreenEnd, bottomLeft: atDesktopStart, bottomRight: atDesktopEnd };
        }
    }

    // A popup's window margin from the bar's edge: windows there start where the bar's
    // reserved space ends, and a popup joins the bar's desktop side, which may be short of
    // that (an offset and a bar thinner than the space) — then the margin is negative
    function popupMargin(bar) {
        return (bar.topOffset ?? 0) + (bar.barHeight ?? 0) - (bar.reservedSpace ?? 0);
    }

    // The most a popup's content can take across the screen from the bar — the screen's
    // `length` that way, less the bar, the popup's `paddings` and a `gap` kept at the far
    // edge
    function popupContentLength(length, bar, paddings, gap) {
        return length - (bar.topOffset ?? 0) - (bar.barHeight ?? 0) - paddings - gap;
    }
}
