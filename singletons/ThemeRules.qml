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
//     "fonts":      { "<token>": … }          optional
//   }
// Every group is partial: what a theme leaves out comes from what it extends.
Singleton {
    id: root

    // Groups of tokens a theme file may set
    readonly property var groups: ["colors", "fonts"]

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
                if (current !== "default" || seen.length > 1)
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
}
