import QtQuick
import qs.singletons

TestCase {
    suiteName: "Theme"

    function run() {
        const builtin = { colors: { accent: "#44d47a", surface: "#3b3b3b" }, fonts: { family: "Mono", sizeBody: 12 } };
        const files = {
            "default": { colors: { surface: "#222222" } },
            "wallpaper": { extends: "default", colorsFrom: "x", colors: { accent: "#ff0000" }, fonts: { sizeBody: 14 } },
            "loopA": { extends: "loopB" },
            "loopB": { extends: "loopA" },
            "orphan": { extends: "missing", colors: { accent: "#123456" } }
        };
        const read = name => files[name] ?? null;

        // --- the chain ---
        const chain = ThemeRules.chainFor("wallpaper", read);
        assertEqual(JSON.stringify(chain.chain.map(entry => entry.name)), JSON.stringify(["wallpaper", "default"]),
            "a theme, then what it extends");
        assertEqual(chain.errors.length, 0, "no errors for a sound chain");
        assertEqual(ThemeRules.chainFor("default", name => null).errors.length, 0,
            "no default theme file is not an error: the built-in theme applies");
        assert(ThemeRules.chainFor("nope", read).errors[0].includes("not found"), "a missing theme is reported");
        const loop = ThemeRules.chainFor("loopA", read);
        assert(loop.errors[0].includes("extends itself"), "a cycle is reported");
        assertEqual(loop.chain.length, 2, "and each theme in it applies once");
        const orphan = ThemeRules.chainFor("orphan", read);
        assertEqual(orphan.chain.length, 1, "a missing parent stops the chain");
        assert(orphan.errors[0].includes("missing"), "and is reported");

        // --- layering ---
        const resolved = ThemeRules.resolve(builtin, chain.chain, {});
        assertEqual(resolved.colors.accent, "#ff0000", "the theme itself wins");
        assertEqual(resolved.colors.surface, "#222222", "what it leaves out comes from what it extends");
        assertEqual(resolved.fonts.sizeBody, 14, "fonts layer the same way");
        assertEqual(resolved.fonts.family, "Mono", "and fall back to the built-in theme");
        assertEqual(builtin.colors.accent, "#44d47a", "the built-in values are not modified");

        const withPalette = ThemeRules.resolve(builtin, chain.chain, { wallpaper: { accent: "#00ff00", surface: "#101010", unknown: "#fff" } });
        assertEqual(withPalette.colors.surface, "#101010", "a palette file sets what the theme does not");
        assertEqual(withPalette.colors.accent, "#ff0000", "the theme's own colours adjust its palette");
        assert(!("unknown" in withPalette.colors), "tokens the built-in theme does not know are ignored");

        assertEqual(JSON.stringify(ThemeRules.resolve(builtin, [], {})), JSON.stringify(builtin), "no theme: the built-in one");
    }
}
