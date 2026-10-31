import QtQuick
import qs.singletons

TestCase {
    suiteName: "CurvePoints"

    readonly property var _one: [0.25, 0.1, 0.25, 1, 1, 1]

    function _near(a, b) {
        return Math.abs(a - b) < 0.003;
    }

    function run() {
        // --- what the points are ---
        const two = CurvePoints.split(_one, 0, 0.4);
        assertEqual(CurvePoints.segmentCount(_one), 1, "one segment");
        assertEqual(CurvePoints.segmentCount(two), 2, "split: two");
        assert(CurvePoints.isJoint(two, 4), "the end of the first segment is a joint");
        assert(!CurvePoints.isJoint(two, 10), "the last end is not");
        assert(!CurvePoints.isJoint(_one, 4), "nor is the end of a single segment");
        assertEqual(CurvePoints.segmentOf(8), 1, "index 8 is in the second segment");

        // --- splitting draws the same curve ---
        let same = true;
        for (let i = 0; i <= 20; i++) {
            const t = i / 20;
            const before = CurvePoints.pointAt(_one, 0, t);
            const after = t <= 0.4 ? CurvePoints.pointAt(two, 0, t / 0.4) : CurvePoints.pointAt(two, 1, (t - 0.4) / 0.6);
            same = same && _near(before.x, after.x) && _near(before.y, after.y);
        }
        assert(same, "split: the two segments trace the one");
        assertEqual(JSON.stringify(CurvePoints.smoothJoints(two)), "[true]", "split: the new joint is smooth");
        assertEqual(JSON.stringify(_one), JSON.stringify([0.25, 0.1, 0.25, 1, 1, 1]), "the points given are not changed");

        // --- removing a joint ---
        const joined = CurvePoints.withoutJoint(two, 4);
        assertEqual(joined.length, 6, "a joint removed: one segment again");
        assertEqual(joined[0] + "," + joined[1], two[0] + "," + two[1], "it keeps the first segment's first handle");
        assertEqual(joined[2] + "," + joined[3], two[8] + "," + two[9], "and the second's second handle");

        // --- moving ---
        const jointX = two[4], jointY = two[5];
        const pushed = CurvePoints.moved(two, [false], 4, 5, jointY + 0.1, -1, 2);
        assertEqual(pushed[4], 0.99, "a joint dragged past the end stops short of it");
        assert(_near(pushed[3] - two[3], 0.1) && _near(pushed[7] - two[7], 0.1), "its handles come along");
        const handle = CurvePoints.moved(two, [false], 0, 0.9, 0.5, -1, 2);
        assertEqual(handle[0], jointX, "a handle stays within its segment");
        assertEqual(CurvePoints.moved(_one, [], 0, 0.2, 5, -0.5, 1.5)[1], 1.5, "y kept within the range given");

        // --- smooth joints ---
        const corner = CurvePoints.moved(two, [false], 2, two[2], two[3] - 0.3, -1, 2);
        assertEqual(JSON.stringify(CurvePoints.smoothJoints(corner)), "[false]", "a handle moved alone makes a corner");
        assertEqual(JSON.stringify(CurvePoints.smoothJoints(CurvePoints.smoothed(corner, 4))), "[true]", "smoothed: in line again");
        const turned = CurvePoints.moved(two, [true], 2, two[2], two[3] - 0.3, -1, 2);
        assertEqual(JSON.stringify(CurvePoints.smoothJoints(turned)), "[true]", "at a smooth joint the handle across turns with it");

        // --- reach ---
        assertEqual(CurvePoints.reach([0.3, -0.4, 0.6, 1.2, 1, 1]), 0.9, "how far from 0.5 the points go");
    }
}
