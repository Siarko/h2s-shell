import QtQuick
import qs.singletons

TestCase {
    suiteName: "Theme"

    function run() {
        const builtin = { colors: { accent: "#44d47a", surface: "#3b3b3b" }, fonts: { family: "Mono", sizeBody: 12 }, bar: { barHeight: 36 }, durations: { expand: 150 }, curves: { expand: "OutQuad" } };
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
        // --- animation ---
        assertEqual(Theme.easing("pop"), Easing.OutBack, "a curve by its Qt name");
        assertEqual(Theme.easing("no such curve"), Easing.OutQuad, "an unknown curve eases out");
        assert(Theme.duration("expand") >= 1, "a role has a duration");
        assertEqual(Theme.duration("no such role"), 1, "an unknown role is instant, but still runs");

        const toDefault = ThemeRules.chainFor("wallpaper", name => name === "wallpaper" ? { extends: "default" } : null);
        assertEqual(toDefault.errors.length, 0, "extending a default theme that has no file is not an error");

        // --- bar geometry moves from profiles into themes ---
        const profiles = [
            { name: "Full", when: {}, set: { "bar.layout.barHeight": 40, "bar.layout.rightPadding": 5, "polling.x": 1 } },
            { name: "Quiet", when: {}, set: {} },
            { name: "Power/save", when: {}, set: { "bar.layout.leftMargin": 300 } }
        ];
        const moved = ThemeRules.themesFromBarLayout(profiles, { "general.debug": true }, undefined, name => name === "Full");
        assertEqual(JSON.stringify(moved.themes.map(entry => entry.name)), JSON.stringify(["Full 2", "Power-save"]),
            "a theme per profile with geometry, under a free file name");
        assertEqual(JSON.stringify(moved.themes[0].theme), JSON.stringify({ extends: "default", bar: { barHeight: 40, rightPadding: 5 } }),
            "holding the profile's geometry, over the default theme");
        assertEqual(moved.themes[1].theme.extends, "Full 2", "a later profile's theme extends the one before it");
        assertEqual(moved.profiles[0].set["appearance.theme"], "Full 2", "the profile picks its theme");
        assertEqual(moved.profiles[1].set["appearance.theme"], undefined, "a profile without geometry keeps inheriting");
        assert(!("bar.layout.barHeight" in moved.profiles[0].set), "the geometry leaves the profile");
        assertEqual(moved.profiles[0].set["polling.x"], 1, "other settings stay");
        assertEqual(profiles[0].set["bar.layout.barHeight"], 40, "the inputs are not modified");
        assertEqual(moved.globals["general.debug"], true, "other globals stay");

        const pinnedMove = ThemeRules.themesFromBarLayout([{ name: "Full", set: {} }, { name: "B", set: { "bar.layout.topOffset": 3 } }],
            { "bar.layout.barHeight": 30 }, undefined, name => false);
        assertEqual(pinnedMove.themes.length, 2, "pinned geometry gives the first profile a theme");
        assertEqual(pinnedMove.themes[1].theme.bar.barHeight, 30, "and goes into every theme, as it applied everywhere");
        assert(!("bar.layout.barHeight" in pinnedMove.globals), "and leaves the globals");

        const legacyMove = ThemeRules.themesFromBarLayout([{ name: "Full", set: { "bar.layout.topOffset": 1 } }], {},
            { barHeight: 33, topOffset: 9 }, name => false);
        assertEqual(legacyMove.themes[0].theme.bar.barHeight, 33, "geometry from before profiles goes to the first profile's theme");
        assertEqual(legacyMove.themes[0].theme.bar.topOffset, 1, "under what the profile set itself");
        assertEqual(ThemeRules.themesFromBarLayout([{ name: "Full", set: {} }], {}, undefined, name => false).themes.length, 0,
            "no geometry anywhere: no themes");
    }
}
