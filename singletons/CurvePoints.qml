pragma Singleton

import Quickshell

// Editing a curve's points, as the Curves page does: pure functions over the points in
// Qt's form — per segment c1x, c1y, c2x, c2y, endX, endY, the last end being (1,1) — each
// returning new points rather than changing the ones given.
//
// Each point is known by the index of its x. Within segment s (at offset 6s): the first
// handle (+0), the second handle (+2) and the end (+4). The end of every segment but the
// last is a joint; the start, (0,0), and the last end, (1,1), stay put.
Singleton {
    id: root

    function segmentCount(points) {
        return points.length / 6;
    }

    function point(points, index) {
        return index < 0 ? { x: 0, y: 0 } : { x: points[index], y: points[index + 1] };
    }

    function isJoint(points, index) {
        return index % 6 === 4 && index < points.length - 2;
    }

    function segmentOf(index) {
        return Math.floor(index / 6);
    }

    // Where segment s starts and ends: the x range its handles keep within
    function segmentStart(points, segment) {
        return point(points, segment * 6 - 2);
    }

    function segmentEnd(points, segment) {
        return point(points, segment * 6 + 4);
    }

    // Where segment s is at its parameter t
    function pointAt(points, segment, t) {
        const p0 = segmentStart(points, segment), p1 = point(points, segment * 6);
        const p2 = point(points, segment * 6 + 2), p3 = point(points, segment * 6 + 4);
        const u = 1 - t;
        return {
            x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
            y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
        };
    }

    function _round(value) {
        return Math.round(value * 1000) / 1000;
    }

    function _clamp(value, low, high) {
        return Math.max(low, Math.min(high, value));
    }

    // For each joint, whether its handles already line up (a smooth joint, no corner)
    function smoothJoints(points) {
        const smooth = [];
        for (let joint = 0; joint < segmentCount(points) - 1; joint++) {
            const at = point(points, joint * 6 + 4), before = point(points, joint * 6 + 2), after = point(points, joint * 6 + 6);
            const cross = (at.x - before.x) * (after.y - at.y) - (at.y - before.y) * (after.x - at.x);
            const dot = (at.x - before.x) * (after.x - at.x) + (at.y - before.y) * (after.y - at.y);
            smooth.push(Math.abs(cross) < 0.002 && dot >= 0);
        }
        return smooth;
    }

    // Places the handle at `otherIndex` in line with the one at `movedIndex` across the
    // joint at `jointIndex`, keeping its length — shortened if it would leave its segment.
    // Changes `points`: for the functions below, on their own copy.
    function _alignHandle(points, jointIndex, movedIndex, otherIndex) {
        const joint = point(points, jointIndex), moved = point(points, movedIndex), other = point(points, otherIndex);
        const dx = joint.x - moved.x, dy = joint.y - moved.y;
        const length = Math.hypot(dx, dy);
        if (length < 1e-6)
            return;
        let reach = Math.hypot(other.x - joint.x, other.y - joint.y);
        const ux = dx / length, uy = dy / length;
        const segment = segmentOf(otherIndex);
        const low = segmentStart(points, segment).x, high = segmentEnd(points, segment).x;
        if (ux > 1e-6)
            reach = Math.min(reach, (high - joint.x) / ux);
        else if (ux < -1e-6)
            reach = Math.min(reach, (low - joint.x) / ux);
        points[otherIndex] = _round(joint.x + ux * reach);
        points[otherIndex + 1] = _round(joint.y + uy * reach);
    }

    // The point at `index` moved to (x, y), y kept within [yLow, yHigh], time moving
    // forward: a joint stays between its neighbours and takes its handles along; a handle
    // stays within its segment, and at a smooth joint (`smooth`, by joint) turns the one
    // across from it
    function moved(points, smooth, index, x, y, yLow, yHigh) {
        const result = points.slice();
        y = _clamp(y, yLow, yHigh);
        const segment = segmentOf(index);
        if (isJoint(result, index)) {
            const low = segmentStart(result, segment).x + 0.01;
            const high = segmentEnd(result, segment + 1).x - 0.01;
            x = _clamp(x, low, high);
            const dx = x - result[index], dy = y - result[index + 1];
            result[index] = _round(x);
            result[index + 1] = _round(y);
            // The handles on either side come along, then keep within their segments
            for (const handle of [index - 2, index + 2]) {
                const handleSegment = segmentOf(handle);
                result[handle] = _round(_clamp(result[handle] + dx, segmentStart(result, handleSegment).x, segmentEnd(result, handleSegment).x));
                result[handle + 1] = _round(result[handle + 1] + dy);
            }
        } else if (index % 6 !== 4) {
            result[index] = _round(_clamp(x, segmentStart(result, segment).x, segmentEnd(result, segment).x));
            result[index + 1] = _round(y);
            // The joint this handle belongs to, and the handle across it
            const first = index % 6 === 0;
            const joint = first ? index - 2 : index + 2;
            if (isJoint(result, joint) && smooth[segmentOf(joint)])
                _alignHandle(result, joint, index, first ? joint - 2 : joint + 2);
        }
        return result;
    }

    // The joint at `jointIndex` made smooth: the handle after it turned in line with the
    // one before
    function smoothed(points, jointIndex) {
        const result = points.slice();
        _alignHandle(result, jointIndex, jointIndex - 2, jointIndex + 2);
        return result;
    }

    // Segment `segment` split at its parameter t into two that draw the same curve
    // (de Casteljau); the new joint is at `segment * 6 + 4`
    function split(points, segment, t) {
        const result = points.slice();
        const start = segmentStart(result, segment);
        const c1 = point(result, segment * 6), c2 = point(result, segment * 6 + 2), end = point(result, segment * 6 + 4);
        const lerp = (a, b) => ({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t });
        const a = lerp(start, c1), b = lerp(c1, c2), c = lerp(c2, end);
        const ab = lerp(a, b), bc = lerp(b, c), middle = lerp(ab, bc);
        // No Array.flatMap in QML's JavaScript
        const values = [];
        for (const each of [a, ab, middle, bc, c, end])
            values.push(_round(each.x), _round(each.y));
        result.splice(segment * 6, 6, ...values);
        return result;
    }

    // The joint at `jointIndex` removed, its two segments joined into one: the first keeps
    // its first handle, the second its second handle and end
    function withoutJoint(points, jointIndex) {
        const result = points.slice();
        result.splice(jointIndex - 2, 6);
        return result;
    }

    // How far from the middle (0.5) the points reach up or down
    function reach(points) {
        let farthest = 0;
        for (let i = 1; i < points.length; i += 2)
            farthest = Math.max(farthest, Math.abs(points[i] - 0.5));
        return farthest;
    }
}
