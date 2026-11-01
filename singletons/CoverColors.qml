pragma Singleton

import Quickshell

// The few colours a cover is made of, for the music visualiser around it (docs/TODO.md
// 11.3). The music panel samples the cover's pixels; palette() is a pure function the test
// suite checks; recall() and remember() keep what was found, for a panel opened again.
//
// Pixels are grouped by hue (12 groups of 30°), each counting by how colourful it is —
// saturated, neither near black nor near white — so a small bright patch outweighs a large
// dull background. The heaviest groups, at least 60° apart, give the colours, each the
// average of its pixels, made bright and saturated enough to show on a dark popup. A grey
// cover gives none: the theme's colour stays.
Singleton {
    id: root

    readonly property int _hueGroups: 12

    // Palettes already read, by cover (its address and the track: a player may write each
    // track's cover to the same file), so a panel opened again has them at once
    property var _remembered: ({})
    property var _rememberedOrder: []

    function recall(key) {
        return _remembered[key] ?? null;
    }

    function remember(key, colors) {
        if (!(key in _remembered))
            _rememberedOrder.push(key);
        _remembered[key] = colors;
        // The last 50 covers are plenty
        while (_rememberedOrder.length > 50)
            delete _remembered[_rememberedOrder.shift()];
    }

    // [h 0–360, s 0–1, l 0–1] of an RGB colour (0–255 each)
    function _hsl(red, green, blue) {
        const redShare = red / 255, greenShare = green / 255, blueShare = blue / 255;
        const max = Math.max(redShare, greenShare, blueShare), min = Math.min(redShare, greenShare, blueShare);
        const lightness = (max + min) / 2;
        if (max === min)
            return [0, 0, lightness];
        const delta = max - min;
        const saturation = lightness > 0.5 ? delta / (2 - max - min) : delta / (max + min);
        let hue;
        if (max === redShare)
            hue = (greenShare - blueShare) / delta + (greenShare < blueShare ? 6 : 0);
        else if (max === greenShare)
            hue = (blueShare - redShare) / delta + 2;
        else
            hue = (redShare - greenShare) / delta + 4;
        return [hue * 60, saturation, lightness];
    }

    function _hex(hue, saturation, lightness) {
        const chroma = saturation * Math.min(lightness, 1 - lightness);
        const channel = part => {
            const offset = (part + hue / 30) % 12;
            const value = lightness - chroma * Math.max(-1, Math.min(offset - 3, 9 - offset, 1));
            return Math.round(value * 255).toString(16).padStart(2, "0");
        };
        return "#" + channel(0) + channel(8) + channel(4);
    }

    // Up to `count` colours ("#rrggbb", the most present first) of `pixels`: RGBA bytes in
    // a row, as a canvas' getImageData gives them
    function palette(pixels, count) {
        const groups = [];
        for (let i = 0; i < _hueGroups; i++)
            groups.push({ weight: 0, red: 0, green: 0, blue: 0, index: i });
        for (let i = 0; i + 3 < pixels.length; i += 4) {
            if (pixels[i + 3] < 128)
                continue;
            const red = pixels[i], green = pixels[i + 1], blue = pixels[i + 2];
            const [hue, saturation, lightness] = _hsl(red, green, blue);
            if (saturation < 0.2 || lightness < 0.12 || lightness > 0.92)
                continue;
            const weight = saturation * (1 - Math.abs(lightness - 0.5) * 1.2);
            const group = groups[Math.floor(hue / 30) % _hueGroups];
            group.weight += weight;
            group.red += red * weight;
            group.green += green * weight;
            group.blue += blue * weight;
        }
        const sorted = groups.filter(group => group.weight > 0).sort((a, b) => b.weight - a.weight);
        if (sorted.length === 0)
            return [];
        const picked = [];
        for (const group of sorted) {
            if (picked.length >= count)
                break;
            // Too little to count: a stray pixel's hue
            if (group.weight < sorted[0].weight * 0.08)
                break;
            // A neighbour of one taken is the same colour, a little shifted
            const near = picked.some(other => {
                const distance = Math.abs(other.index - group.index);
                return Math.min(distance, _hueGroups - distance) < 2;
            });
            if (!near)
                picked.push(group);
        }
        return picked.map(group => {
            const [hue, saturation, lightness] = _hsl(group.red / group.weight, group.green / group.weight, group.blue / group.weight);
            return _hex(hue, Math.max(saturation, 0.45), Math.max(0.5, Math.min(lightness, 0.72)));
        });
    }
}
