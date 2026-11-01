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

    // Things laid out by the bar — along it, and across it away from its desktop side —
    // put on screen. The bar frame of a box `width` × `height` whose side against the bar
    // is at `across` 0: `along` runs left to right on a horizontal bar, top to bottom on a
    // vertical one.

    // A rectangle { along, across, alongLength, acrossLength } of the frame, on screen:
    // { x, y, width, height } in the box
    function fromBarFrame(edge, frameRect, width, height) {
        const along = frameRect.along ?? 0, across = frameRect.across ?? 0;
        const alongLength = frameRect.alongLength ?? 0, acrossLength = frameRect.acrossLength ?? 0;
        switch (edge) {
        case "bottom":
            return { x: along, y: height - across - acrossLength, width: alongLength, height: acrossLength };
        case "left":
            return { x: across, y: along, width: acrossLength, height: alongLength };
        case "right":
            return { x: width - across - acrossLength, y: along, width: acrossLength, height: alongLength };
        default:
            return { x: along, y: across, width: alongLength, height: acrossLength };
        }
    }

    // The same as a transform, for an item drawn in the frame (as for a bar at the top:
    // x along, y across) and put in the box at 0, 0 — shapes only, since it may turn them
    // over. A row-major 4 × 4 matrix, for Qt.matrix4x4.
    function frameMatrix(edge, width, height) {
        switch (edge) {
        case "bottom":
            return [1, 0, 0, 0,  0, -1, 0, height,  0, 0, 1, 0,  0, 0, 0, 1];
        case "left":
            return [0, 1, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1];
        case "right":
            return [0, -1, 0, width,  1, 0, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1];
        default:
            return [1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1];
        }
    }

    // A popup's corners on screen: rounded on its side away from the bar, at the ends that
    // curve into the bar (`start`, `end`: true) — { topLeft, topRight, bottomLeft,
    // bottomRight }
    function popupCorners(edge, start, end, radius) {
        const atStart = start ? radius : 0, atEnd = end ? radius : 0;
        switch (edge) {
        case "bottom":
            return { topLeft: atStart, topRight: atEnd, bottomLeft: 0, bottomRight: 0 };
        case "left":
            return { topLeft: 0, topRight: atStart, bottomLeft: 0, bottomRight: atEnd };
        case "right":
            return { topLeft: atStart, topRight: 0, bottomLeft: atEnd, bottomRight: 0 };
        default:
            return { topLeft: 0, topRight: 0, bottomLeft: atStart, bottomRight: atEnd };
        }
    }
}
