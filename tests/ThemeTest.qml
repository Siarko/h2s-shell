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
        // --- where values come from ---
        const origins = ThemeRules.origins(chain.chain, { wallpaper: { surface: "#101010" } });
        assertEqual(JSON.stringify(origins.colors.accent), JSON.stringify({ theme: "wallpaper", palette: false }), "a value set by the theme itself");
        assertEqual(JSON.stringify(origins.colors.surface), JSON.stringify({ theme: "wallpaper", palette: true }),
            "a value from its palette, over what it extends");
        assertEqual(ThemeRules.origins(chain.chain, {}).colors.surface.theme, "default", "a value from the theme it extends");
        assertEqual(origins.fonts.family, undefined, "a value set nowhere is built in");
        for (const entry of ThemeRules.colorTokens)
            assert(entry.token in Theme.builtin.colors, "the colour " + entry.token + " is a built-in token");
        assertEqual(ThemeRules.colorTokens.length, Object.keys(Theme.builtin.colors).length, "and every built-in colour is listed");

        // --- drafts ---
        const file = { extends: "default", colors: { accent: "#111111", surface: "#222222" }, bar: { barHeight: 30 } };
        const draft = { colors: { accent: "#ff0000", surface: null, error: "#00ff00" } };
        const drafted = ThemeRules.applyDraft(file, draft);
        assertEqual(drafted.colors.accent, "#ff0000", "a draft changes a value");
        assert(!("surface" in drafted.colors), "a null in a draft removes the value");
        assertEqual(drafted.colors.error, "#00ff00", "and adds one the file did not have");
        assertEqual(drafted.bar.barHeight, 30, "what the draft does not touch follows the file");
        assertEqual(file.colors.surface, "#222222", "the inputs are not modified");
        assert(!("colors" in ThemeRules.applyDraft({ colors: { a: "#1" } }, { colors: { a: null } })), "a group left empty goes");
        const resetInFile = ThemeRules.draftWith({}, file, "colors", "surface", null);
        assertEqual(resetInFile.colors.surface, null, "resetting a value the file sets drafts its removal");
        const resetDraftOnly = ThemeRules.draftWith(draft, file, "colors", "error", null);
        assert(!("error" in resetDraftOnly.colors), "resetting a value only the draft sets drops it from the draft");
        assertEqual(JSON.stringify(ThemeRules.draftWith({ colors: { error: "#0" } }, file, "colors", "error", null)), "{}",
            "and an emptied draft is empty");
        assertEqual(JSON.stringify(ThemeRules.draftWithout(draft, "colors", "surface")),
            JSON.stringify({ colors: { accent: "#ff0000", error: "#00ff00" } }), "undoing one change keeps the others");
        assertEqual(JSON.stringify(ThemeRules.draftWithout({ colors: { a: null } }, "colors", "a")), "{}", "and undoing the last empties the draft");
        assertEqual(draft.colors.surface, null, "undoing does not modify the input");
        const split = ThemeRules.splitDraft({ colors: { a: "#1" }, fonts: { b: 2 } }, ["colors"]);
        assertEqual(JSON.stringify(split.taken), JSON.stringify({ colors: { a: "#1" } }), "a draft splits by group");
        assertEqual(JSON.stringify(split.rest), JSON.stringify({ fonts: { b: 2 } }), "leaving the rest");
        assertEqual(Object.keys(ThemeRules.splitDraft({ colors: {}, fonts: {} }).rest).length, 0, "no groups: all of it");

        // --- managing themes ---
        assert(ThemeRules.validThemeName("Power save"), "a theme name may have spaces inside");
        assert(!ThemeRules.validThemeName("a/b") && !ThemeRules.validThemeName(".hidden") && !ThemeRules.validThemeName(" x"),
            "but no slash, no leading dot, no spaces at its ends");
        const family = { base: { extends: "root", colors: {} }, child: { extends: "base" }, other: { extends: "child" }, alone: {} };
        const renamedFamily = ThemeRules.renameExtends(family, "base", "core");
        assertEqual(JSON.stringify(Object.keys(renamedFamily)), JSON.stringify(["child"]), "renaming re-points only the themes extending it");
        assertEqual(renamedFamily.child.extends, "core", "at the new name");
        assertEqual(family.child.extends, "base", "the inputs are not modified");
        assertEqual(ThemeRules.withoutExtends(family, "base").child.extends, "root", "deleting hands its parent to the themes extending it");
        assertEqual(ThemeRules.withoutExtends(family, "alone").child, undefined, "and leaves the others");
        assertEqual(ThemeRules.withoutExtends({ a: {}, b: { extends: "a" } }, "a").b.extends, "default", "a parent of nothing hands over the default");
        const retargeted = ThemeRules.retargetTheme([{ name: "Full", set: { "appearance.theme": "x" } }, { name: "Quiet", set: {} }],
            { "appearance.theme": "x" }, "x", "y");
        assertEqual(retargeted.profiles[0].set["appearance.theme"], "y", "profiles using a theme follow it");
        assertEqual(retargeted.globals["appearance.theme"], "y", "and so does a pinned global");
        assertEqual(JSON.stringify(retargeted.changed), JSON.stringify(["Full", "global"]), "naming what changed");
        assertEqual(retargeted.profiles[1].set["appearance.theme"], undefined, "a profile without its own theme is left alone");
        const readFamily = name => family[name] ?? null;
        assert(ThemeRules.extendsCycle("base", "other", readFamily), "extending a descendant is a cycle");
        assert(ThemeRules.extendsCycle("base", "base", readFamily), "and so is extending itself");
        assert(!ThemeRules.extendsCycle("other", "alone", readFamily), "an unrelated theme is fine");

        // --- curves ---
        const library = { snappy: [0.2, 0.9, 0.1, 1.0], twoStep: [0.1, 0.5, 0.2, 0.6, 0.5, 0.5, 0.6, 0.6, 0.9, 1, 1, 1],
            backwards: [1.2, 0, 0.5, 1], short: [0.1, 0.2, 0.3], OutQuad: [0, 0, 1, 1] };
        assertEqual(ThemeRules.curveEasing("OutBack", library).easing.type, Easing.OutBack, "a Qt curve by its name");
        assertEqual(ThemeRules.curveEasing("OutQuad", library).easing.type, Easing.OutQuad, "a Qt name wins over a library entry");
        const snappy = ThemeRules.curveEasing("snappy", library);
        assertEqual(snappy.easing.type, Easing.BezierSpline, "a library curve is a Bézier spline");
        assertEqual(JSON.stringify(snappy.easing.bezierCurve), JSON.stringify([0.2, 0.9, 0.1, 1, 1, 1]), "one segment gets its end");
        assertEqual(snappy.error, "", "and resolves without error");
        assertEqual(ThemeRules.curveEasing("twoStep", library).easing.bezierCurve.length, 12, "several segments are kept");
        const missing = ThemeRules.curveEasing("nope", library);
        assertEqual(missing.easing.type, Easing.OutQuad, "an unknown curve falls back");
        assert(missing.error.includes("not found"), "and is reported");
        assert(ThemeRules.curveEasing("backwards", library).error.includes("not a valid"), "time cannot run backwards");
        assert(ThemeRules.curveEasing("short", library).error.includes("not a valid"), "points come in whole segments");
        assert(ThemeRules.curveEasing("Bezier", library).error !== "", "Bezier is not a curve by itself");
        assert(!ThemeRules.validCurveName("InOutCubic"), "a library curve cannot take a Qt curve's name");
        assert(!ThemeRules.validCurveName(" snappy"), "nor stray spaces");
        assert(ThemeRules.validCurveName("snappy"), "a plain name is fine");
        const themesWithCurves = { b: { curves: { pop: "snappy", hover: "OutQuad" } }, a: { curves: { enter: "snappy" } }, c: {} };
        assertEqual(JSON.stringify(ThemeRules.curveUsages(themesWithCurves, "snappy")),
            JSON.stringify([{ theme: "a", role: "enter" }, { theme: "b", role: "pop" }]), "a curve's usages, by theme and role");
        const renamed = ThemeRules.renameCurveIn(themesWithCurves, "snappy", "quick");
        assertEqual(JSON.stringify(Object.keys(renamed).sort()), JSON.stringify(["a", "b"]), "renaming changes only the themes using it");
        assertEqual(renamed.b.curves.pop, "quick", "pointing them at the new name");
        assertEqual(renamed.b.curves.hover, "OutQuad", "other roles stay");
        assertEqual(themesWithCurves.b.curves.pop, "snappy", "the inputs are not modified");
        for (const name in ThemeRules.qtCurveApproximations)
            assert(ThemeRules.isQtCurve(name) && ThemeRules.curvePoints(ThemeRules.qtCurveApproximations[name]) !== null,
                "the copy of " + name + " is a valid curve");

        // --- animation ---
        assertEqual(Theme.curve("no such role").type, Easing.OutQuad, "a role without a curve eases out");
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
