pragma Singleton

import Quickshell

// Points on the outline of a rounded square — from square corners to a circle — for
// drawing around one (the music visualiser around the cover, docs/TODO.md 11.3).
// Pure functions: no I/O, so the test suite checks them.
Singleton {
    id: root

    // The point a fraction `t` (0–1) of the way round the outline, clockwise from the top
    // centre, of a square `half` from its centre to each side with corners of `radius`
    // (0 – half), turned clockwise by `angle` degrees. Returns { x, y, nx, ny }: the point
    // relative to the centre and its outward normal. Positions are spaced by length along
    // the outline, so evenly spaced fractions are evenly spaced on it.
    function point(t, half, radius, angle) {
        const r = Math.max(0, Math.min(radius, half));
        const side = 2 * (half - r);
        const arc = Math.PI * r / 2;
        const total = 4 * side + 4 * arc;
        let p;
        if (total <= 0) {
            p = { x: 0, y: 0, nx: 0, ny: -1 };
        } else {
            // From the top centre: half a side, then corner, side, corner, … ; s starts at
            // the top side's left end so each quarter is a side and then a corner
            let s = (((t % 1) + 1) % 1 * total + side / 2) % total;
            p = null;
            for (let quarter = 0; quarter < 4 && p === null; quarter++) {
                // The quarter's side runs along `direction`, with the outward normal to its left
                const direction = [[1, 0], [0, 1], [-1, 0], [0, -1]][quarter];
                const normal = [direction[1], -direction[0]];
                // The side's start: the corner centre before it, pushed out along the normal
                const before = [[-1, -1], [1, -1], [1, 1], [-1, 1]][quarter];
                const startX = before[0] * (half - r) + normal[0] * r;
                const startY = before[1] * (half - r) + normal[1] * r;
                if (s <= side) {
                    p = { x: startX + direction[0] * s, y: startY + direction[1] * s, nx: normal[0], ny: normal[1] };
                    break;
                }
                s -= side;
                if (s <= arc && r > 0) {
                    const after = [[1, -1], [1, 1], [-1, 1], [-1, -1]][quarter];
                    const centreX = after[0] * (half - r), centreY = after[1] * (half - r);
                    const startAngle = Math.atan2(normal[1], normal[0]);
                    const a = startAngle + s / r;
                    p = { x: centreX + r * Math.cos(a), y: centreY + r * Math.sin(a), nx: Math.cos(a), ny: Math.sin(a) };
                    break;
                }
                s -= arc;
            }
            if (p === null)
                p = { x: 0, y: -half, nx: 0, ny: -1 };
        }
        if (!angle)
            return p;
        const radians = angle * Math.PI / 180;
        const cos = Math.cos(radians), sin = Math.sin(radians);
        return {
            x: p.x * cos - p.y * sin, y: p.x * sin + p.y * cos,
            nx: p.nx * cos - p.ny * sin, ny: p.nx * sin + p.ny * cos
        };
    }

    // The same point, but for a band that keeps its place on screen while the shape turns:
    // the fraction is taken back by the turn, so the bass stays at the bottom
    function screenPoint(t, half, radius, angle) {
        return point(t - (angle ?? 0) / 360, half, radius, angle);
    }
}
