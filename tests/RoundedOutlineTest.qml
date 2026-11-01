import QtQuick
import qs.singletons

// Points on a rounded square's outline: where they fall, their normals, the turn
TestCase {
    suiteName: "RoundedOutline"

    function _near(a, b) {
        return Math.abs(a - b) < 0.001;
    }

    function _at(p, x, y, nx, ny) {
        return _near(p.x, x) && _near(p.y, y) && _near(p.nx, nx) && _near(p.ny, ny);
    }

    function run() {
        // A square (no rounding), half 10
        assert(_at(RoundedOutline.point(0, 10, 0, 0), 0, -10, 0, -1), "square: 0 is the top centre, normal up");
        assert(_at(RoundedOutline.point(0.25, 10, 0, 0), 10, 0, 1, 0), "square: a quarter round is the right centre");
        assert(_at(RoundedOutline.point(0.5, 10, 0, 0), 0, 10, 0, 1), "square: half round is the bottom centre");
        assert(_at(RoundedOutline.point(0.75, 10, 0, 0), -10, 0, -1, 0), "square: three quarters is the left centre");
        assert(_at(RoundedOutline.point(1, 10, 0, 0), 0, -10, 0, -1), "square: 1 is back at the top");
        assert(_at(RoundedOutline.point(-0.25, 10, 0, 0), -10, 0, -1, 0), "square: a negative fraction wraps");
        assert(_near(RoundedOutline.point(0.125, 10, 0, 0).x, 10) && _near(RoundedOutline.point(0.125, 10, 0, 0).y, -10),
            "square: an eighth is the top right corner");

        // A circle (radius = half)
        {
            const p = RoundedOutline.point(0.125, 10, 10, 0);
            const d = Math.SQRT1_2;
            assert(_at(p, 10 * d, -10 * d, d, -d), "circle: an eighth is at 45°, normal outward");
            assert(_at(RoundedOutline.point(0.5, 10, 10, 0), 0, 10, 0, 1), "circle: half round is the bottom");
        }

        // A rounded square: the corner's middle on its arc
        {
            const p = RoundedOutline.point(0.125, 10, 4, 0);
            const d = Math.SQRT1_2;
            assert(_at(p, 6 + 4 * d, -6 - 4 * d, d, -d), "rounded: an eighth is the corner arc's middle");
            assert(_at(RoundedOutline.point(0.25, 10, 4, 0), 10, 0, 1, 0), "rounded: sides still meet the centres");
        }
        assert(_at(RoundedOutline.point(0.25, 10, 99, 0), 10, 0, 1, 0), "a radius past half is a circle");

        // Turned
        assert(_at(RoundedOutline.point(0, 10, 0, 90), 10, 0, 1, 0), "turned 90°: the top centre goes to the right");
        assert(_at(RoundedOutline.screenPoint(0, 10, 0, 90), 0, -10, 0, -1), "screenPoint: a band keeps its place as the shape turns");
        assert(_at(RoundedOutline.screenPoint(0.5, 10, 10, 37), 0, 10, 0, 1), "screenPoint: on a circle, exactly");
    }
}
