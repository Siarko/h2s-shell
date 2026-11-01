import QtQuick
import qs.singletons

// The bar at each screen edge: its desktop side, its corners from edge-relative tokens,
// where its popups join it and how far they may reach
TestCase {
    suiteName: "BarGeometry"

    // Every corner different, so a corner landing in the wrong place shows
    readonly property var _bar: ({ barHeight: 40, reservedSpace: 48, topOffset: 4,
        radiusTopLeft: 10, radiusTopRight: 20, radiusBottomLeft: 30, radiusBottomRight: 40 })

    function _corners(result, topLeft, topRight, bottomLeft, bottomRight) {
        return result.topLeft === topLeft && result.topRight === topRight
            && result.bottomLeft === bottomLeft && result.bottomRight === bottomRight;
    }

    function run() {
        assert(BarGeometry.desktopEdge("top") === "bottom", "top bar faces the desktop below");
        assert(BarGeometry.desktopEdge("bottom") === "top", "bottom bar faces the desktop above");
        assert(BarGeometry.desktopEdge("left") === "right", "left bar faces right");
        assert(BarGeometry.desktopEdge("right") === "left", "right bar faces left");
        assert(BarGeometry.desktopEdge("nonsense") === "bottom", "an unknown edge is the top's");

        assert(!BarGeometry.isVertical("top") && !BarGeometry.isVertical("bottom"), "top and bottom are horizontal");
        assert(BarGeometry.isVertical("left") && BarGeometry.isVertical("right"), "left and right are vertical");

        assert(BarGeometry.radius(50, 40) === 10, "a corner is percent of half the thickness");
        assert(BarGeometry.radius(undefined, 40) === 0, "no corner token is square");

        // 10% → 2, 20% → 4, 30% → 6, 40% → 8 px of the 20 px half
        assert(_corners(BarGeometry.corners("top", _bar), 2, 4, 6, 8), "top: corners as named");
        assert(_corners(BarGeometry.corners("bottom", _bar), 6, 8, 2, 4), "bottom: mirrored, screen side below");
        assert(_corners(BarGeometry.corners("left", _bar), 2, 6, 4, 8), "left: screen side left, start at the top");
        assert(_corners(BarGeometry.corners("right", _bar), 6, 2, 8, 4), "right: screen side right, start at the top");

        assert(BarGeometry.popupMargin(_bar) === -4, "popup joins the bar 4 px inside its reserved space");
        assert(BarGeometry.popupMargin({ barHeight: 40, reservedSpace: 40, topOffset: 0 }) === 0,
            "a bar filling its space: popups start where windows do");

        assert(BarGeometry.popupContentLength(1440, _bar, 20, 16) === 1440 - 4 - 40 - 20 - 16,
            "content reaches to the gap at the far edge");
    }
}
