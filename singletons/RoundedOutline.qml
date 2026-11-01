pragma Singleton

import Quickshell

// Points on the outline of a rounded square — from square corners to a circle — for
// drawing around one (the music visualiser around the cover, docs/TODO.md 11.3).
// Pure functions: no I/O, so the test suite checks them.
Singleton {
    id: root

    // The point a fraction (0–1) of the way round the outline, clockwise from the top
    // centre, of a square `half` from its centre to each side with corners of `radius`
    // (0 – half), turned clockwise by `angle` degrees. Returns { x, y, nx, ny }: the point
    // relative to the centre and its outward normal. Positions are spaced by length along
    // the outline, so evenly spaced fractions are evenly spaced on it.
    function point(fraction, half, radius, angle) {
        const corner = Math.max(0, Math.min(radius, half));
        const side = 2 * (half - corner);
        const arc = Math.PI * corner / 2;
        const total = 4 * side + 4 * arc;
        let result;
        if (total <= 0) {
            result = { x: 0, y: 0, nx: 0, ny: -1 };
        } else {
            // From the top centre: half a side, then corner, side, corner, … ; the distance
            // starts at the top side's left end so each quarter is a side and then a corner
            let distance = (((fraction % 1) + 1) % 1 * total + side / 2) % total;
            result = null;
            for (let quarter = 0; quarter < 4 && result === null; quarter++) {
                // The quarter's side runs along `direction`, with the outward normal to its left
                const direction = [[1, 0], [0, 1], [-1, 0], [0, -1]][quarter];
                const normal = [direction[1], -direction[0]];
                // The side's start: the corner centre before it, pushed out along the normal
                const before = [[-1, -1], [1, -1], [1, 1], [-1, 1]][quarter];
                const startX = before[0] * (half - corner) + normal[0] * corner;
                const startY = before[1] * (half - corner) + normal[1] * corner;
                if (distance <= side) {
                    result = { x: startX + direction[0] * distance, y: startY + direction[1] * distance, nx: normal[0], ny: normal[1] };
                    break;
                }
                distance -= side;
                if (distance <= arc && corner > 0) {
                    const after = [[1, -1], [1, 1], [-1, 1], [-1, -1]][quarter];
                    const centreX = after[0] * (half - corner), centreY = after[1] * (half - corner);
                    const startAngle = Math.atan2(normal[1], normal[0]);
                    const turn = startAngle + distance / corner;
                    result = { x: centreX + corner * Math.cos(turn), y: centreY + corner * Math.sin(turn), nx: Math.cos(turn), ny: Math.sin(turn) };
                    break;
                }
                distance -= arc;
            }
            if (result === null)
                result = { x: 0, y: -half, nx: 0, ny: -1 };
        }
        if (!angle)
            return result;
        const radians = angle * Math.PI / 180;
        const cos = Math.cos(radians), sin = Math.sin(radians);
        return {
            x: result.x * cos - result.y * sin, y: result.x * sin + result.y * cos,
            nx: result.nx * cos - result.ny * sin, ny: result.nx * sin + result.ny * cos
        };
    }

    // The same point, but for a band that keeps its place on screen while the shape turns:
    // the fraction is taken back by the turn, so the bass stays at the bottom
    function screenPoint(fraction, half, radius, angle) {
        return point(fraction - (angle ?? 0) / 360, half, radius, angle);
    }
}
