pragma Singleton

import Quickshell
import QtQuick

// Pure functions behind Theme: resolving a theme file's `extends` chain and layering the
// result over the built-in theme. No I/O — the caller passes a function that reads a theme
// by name — so tests/ThemeTest.qml exercises them with made-up themes.
// See docs/plans/themes.md.
//
// A theme file:
//   {
//     "extends":    "<theme name>",          optional; the built-in theme otherwise
//     "colorsFrom": "<path>",                 optional; a palette file, e.g. from matugen
//     "colors":     { "<token>": "#rrggbb" }, optional
//     "fonts":      { "<token>": … },         optional
//     "bar":        { "<token>": <number> }   optional; geometry, see barTokens
//   }
// Every group is partial: what a theme leaves out comes from what it extends.
Singleton {
    id: root

    // Groups of tokens a theme file may set
    readonly property var groups: ["colors", "fonts", "bar"]

    // The bar's geometry: sizes in pixels, corner radii in percent of half the bar's height
    readonly property var barTokens: ["barHeight", "reservedSpace", "topOffset", "leftMargin", "rightMargin",
        "leftPadding", "rightPadding", "radiusTopLeft", "radiusTopRight", "radiusBottomLeft", "radiusBottomRight"]

    // The chain for `name`, the theme itself first and its ancestors after it, each
    // { name, theme }. `readTheme(name)` returns the parsed file or null when there is
    // none. Stops at a missing theme (reported, the rest of the chain still applies) and
    // at a cycle (reported, the theme seen again is not applied twice).
    // Returns { chain: [{ name, theme }], errors: [string] }.
    function chainFor(name, readTheme, maxDepth) {
        const chain = [];
        const errors = [];
        const seen = [];
        let current = name;
        const limit = maxDepth ?? 16;
        while (current && current !== "") {
            if (seen.includes(current)) {
                errors.push("Theme \"" + current + "\" extends itself through " + seen.join(" → "));
                break;
            }
            if (seen.length >= limit) {
                errors.push("Theme chain longer than " + limit + ": " + seen.join(" → "));
                break;
            }
            seen.push(current);
            const theme = readTheme(current);
            if (theme === null || theme === undefined) {
                // The default theme may simply not exist: that is the built-in theme
                if (current !== "default")
                    errors.push("Theme \"" + current + "\" not found");
                break;
            }
            chain.push({ name: current, theme: theme });
            current = typeof theme.extends === "string" ? theme.extends : "";
        }
        return { chain: chain, errors: errors };
    }

    // The built-in values overlaid by the chain, ancestors first, so the theme itself has
    // the last word. Within one theme, its palette file (`colorsFrom`, passed in
    // `palettes[name]`) comes before its own colours, so a theme can adjust a generated
    // palette. Tokens the built-in theme does not know are ignored. Inputs are not
    // modified. Returns { group: { token: value } } for every group.
    function resolve(builtin, chain, palettes) {
        const result = {};
        for (const group of groups)
            result[group] = Object.assign({}, builtin[group] ?? {});
        for (let i = chain.length - 1; i >= 0; i--) {
            const entry = chain[i];
            const layers = [];
            if (palettes?.[entry.name])
                layers.push({ group: "colors", values: palettes[entry.name] });
            for (const group of groups)
                layers.push({ group: group, values: entry.theme[group] });
            for (const layer of layers) {
                for (const token in layer.values ?? {}) {
                    if (token in result[layer.group])
                        result[layer.group][token] = layer.values[token];
                }
            }
        }
        return result;
    }

    // A file name for a theme named after `wanted` that `exists(name)` does not report
    // taken: the name itself, else "<name> 2", "<name> 3", …
    function freeName(wanted, exists) {
        const base = wanted.replace(/[\/]/g, "-").trim() || "Theme";
        let name = base;
        for (let i = 2; exists(name); i++)
            name = base + " " + i;
        return name;
    }

    // Moves the bar geometry from profiles into themes, once (docs/plans/themes.md, stage
    // 3), so the bar looks the same in every profile afterwards. Each profile that sets
    // any `bar.layout.*` gets a theme named after it holding those values, extending the
    // theme of the nearest profile before it that got one ("default" for the first), and
    // picks it with `appearance.theme` — the same layering profiles had. Geometry pinned
    // as global goes into every such theme (and gives the first profile one if none has
    // its own). `legacyLayout`: the `bar.layout` section of a config from before profiles
    // whose values never reached a profile, or undefined; it counts as the first profile's.
    // Inputs are not modified.
    // Returns { profiles, globals, themes: [{ name, theme }] }.
    function themesFromBarLayout(profiles, globals, legacyLayout, exists) {
        const newProfiles = JSON.parse(JSON.stringify(profiles ?? []));
        const newGlobals = Object.assign({}, globals ?? {});
        const take = set => {
            const values = {};
            for (const token of barTokens) {
                if (set && ("bar.layout." + token) in set) {
                    values[token] = set["bar.layout." + token];
                    delete set["bar.layout." + token];
                }
            }
            return values;
        };
        const pinned = take(newGlobals);
        const themes = [];
        const taken = name => exists(name) || themes.some(entry => entry.name === name);
        let parent = "default";
        newProfiles.forEach((profile, index) => {
            profile.set = profile.set ?? {};
            const own = take(profile.set);
            if (index === 0 && legacyLayout) {
                for (const token of barTokens) {
                    if (!(token in own) && legacyLayout[token] !== undefined)
                        own[token] = legacyLayout[token];
                }
            }
            const needed = Object.keys(own).length > 0 || (index === 0 && Object.keys(pinned).length > 0);
            if (!needed)
                return;
            const name = freeName(profile.name ?? "Theme", taken);
            themes.push({ name: name, theme: { extends: parent, bar: Object.assign(own, pinned) } });
            profile.set["appearance.theme"] = name;
            parent = name;
        });
        return { profiles: newProfiles, globals: newGlobals, themes: themes };
    }
}
