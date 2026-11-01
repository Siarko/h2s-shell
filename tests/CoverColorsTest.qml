import QtQuick
import qs.singletons

// A cover's colours: which are picked, in what order, and how they are adjusted
TestCase {
    suiteName: "CoverColors"

    // RGBA bytes: `amount` pixels of each [r, g, b(, a)]
    function _pixels(parts) {
        const out = [];
        for (const part of parts) {
            for (let i = 0; i < part.amount; i++)
                out.push(part.color[0], part.color[1], part.color[2], part.color[3] ?? 255);
        }
        return out;
    }

    function _hue(hex) {
        const value = parseInt(hex.slice(1), 16);
        return CoverColors._hsl(value >> 16, (value >> 8) & 255, value & 255);
    }

    function run() {
        assertEqual(JSON.stringify(CoverColors.palette([], 3)), "[]", "no pixels: no colours");
        assertEqual(JSON.stringify(CoverColors.palette(_pixels([{ color: [128, 128, 128], amount: 50 }, { color: [10, 10, 10], amount: 50 }]), 3)),
            "[]", "a grey cover: no colours, the theme's stays");

        {
            const colors = CoverColors.palette(_pixels([
                { color: [200, 30, 30], amount: 60 },   // red, most
                { color: [30, 60, 200], amount: 30 },   // blue
                { color: [40, 180, 60], amount: 15 }    // green, least
            ]), 3);
            assertEqual(colors.length, 3, "three distinct colours: three");
            const hues = colors.map(color => _hue(color)[0]);
            assert(hues[0] < 15 || hues[0] > 345, "the most present first (red): " + colors[0]);
            assert(hues[1] > 210 && hues[1] < 240, "then blue: " + colors[1]);
            assert(hues[2] > 110 && hues[2] < 140, "then green: " + colors[2]);
            assertEqual(CoverColors.palette(_pixels([{ color: [200, 30, 30], amount: 60 }, { color: [30, 60, 200], amount: 30 }]), 3).length,
                2, "two colours: two");
            assertEqual(CoverColors.palette(_pixels([{ color: [200, 30, 30], amount: 60 }, { color: [30, 60, 200], amount: 30 }]), 1).length,
                1, "no more than asked for");
        }

        {
            const colors = CoverColors.palette(_pixels([{ color: [200, 30, 30], amount: 50 }, { color: [210, 70, 20], amount: 50 }]), 3);
            assertEqual(colors.length, 1, "neighbouring hues are one colour");
        }

        {
            const colors = CoverColors.palette(_pixels([
                { color: [128, 128, 128], amount: 500 },    // a large grey background
                { color: [220, 200, 20], amount: 20 }       // a small yellow patch
            ]), 3);
            assertEqual(colors.length, 1, "a small colourful patch on grey is found");
        }

        {
            const colors = CoverColors.palette(_pixels([{ color: [200, 30, 30], amount: 100 }, { color: [30, 60, 200], amount: 3 }]), 3);
            assertEqual(colors.length, 1, "a stray few pixels do not count");
        }

        {
            const colors = CoverColors.palette(_pixels([{ color: [200, 30, 30, 0], amount: 100 }, { color: [30, 60, 200], amount: 10 }]), 3);
            assertEqual(colors.length, 1, "transparent pixels are skipped");
        }

        {
            const dark = _hue(CoverColors.palette(_pixels([{ color: [70, 10, 10], amount: 50 }]), 3)[0]);
            assert(dark[2] >= 0.49, "a dark colour is brightened to show on a dark popup");
            const dull = _hue(CoverColors.palette(_pixels([{ color: [160, 100, 100], amount: 50 }]), 3)[0]);
            assert(dull[1] >= 0.44, "a dull one is saturated");
        }

        // --- remembered palettes ---
        assertEqual(CoverColors.recall("test-cover-a"), null, "a cover never read: nothing remembered");
        CoverColors.remember("test-cover-a", ["#ff0000"]);
        assertEqual(JSON.stringify(CoverColors.recall("test-cover-a")), JSON.stringify(["#ff0000"]), "a palette read is remembered");
        for (let i = 0; i < 60; i++)
            CoverColors.remember("test-cover-n" + i, []);
        assertEqual(CoverColors.recall("test-cover-a"), null, "only the last 50 are kept");
        assertEqual(JSON.stringify(CoverColors.recall("test-cover-n59")), "[]", "and a grey cover's empty palette counts");
    }
}
