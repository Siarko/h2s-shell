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

        // The bar frame on screen, in a 100 × 50 box: a piece 10 along, 5 across, 20 × 8
        {
            const piece = { along: 10, across: 5, alongLength: 20, acrossLength: 8 };
            const placedAt = (placed, x, y, width, height) => placed.x === x && placed.y === y
                && placed.width === width && placed.height === height;
            assert(placedAt(BarGeometry.fromBarFrame("top", piece, 100, 50), 10, 5, 20, 8), "frame, top: as given");
            assert(placedAt(BarGeometry.fromBarFrame("bottom", piece, 100, 50), 10, 37, 20, 8), "frame, bottom: across from the box's bottom");
            assert(placedAt(BarGeometry.fromBarFrame("left", piece, 100, 50), 5, 10, 8, 20), "frame, left: along runs down");
            assert(placedAt(BarGeometry.fromBarFrame("right", piece, 100, 50), 87, 10, 8, 20), "frame, right: across from the box's right");

            // The matrix puts the frame's corners where fromBarFrame puts the rectangle's
            for (const edge of BarGeometry.edges) {
                const matrix = BarGeometry.frameMatrix(edge, 100, 50);
                const map = (along, across) => ({ x: matrix[0] * along + matrix[1] * across + matrix[3],
                                                  y: matrix[4] * along + matrix[5] * across + matrix[7] });
                const first = map(10, 5), last = map(30, 13);
                const placed = BarGeometry.fromBarFrame(edge, piece, 100, 50);
                assert(Math.min(first.x, last.x) === placed.x && Math.min(first.y, last.y) === placed.y
                    && Math.abs(first.x - last.x) === placed.width && Math.abs(first.y - last.y) === placed.height,
                    "frameMatrix agrees with fromBarFrame: " + edge);
            }
        }

        // A popup rounded away from the bar, at the ends curving into it
        assert(_corners(BarGeometry.popupCorners("top", true, false, 9), 0, 0, 9, 0), "popup at the top: bottom corners, start only");
        assert(_corners(BarGeometry.popupCorners("bottom", true, true, 9), 9, 9, 0, 0), "popup at the bottom: top corners");
        assert(_corners(BarGeometry.popupCorners("left", true, true, 9), 0, 9, 0, 9), "popup by a left bar: right corners");
        assert(_corners(BarGeometry.popupCorners("right", false, true, 9), 0, 0, 9, 0), "popup by a right bar: the end is the bottom left");
    }
}
