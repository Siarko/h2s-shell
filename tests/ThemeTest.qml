import QtQuick
import qs.singletons

TestCase {
    suiteName: "Theme"
    // Theme.duration at the theme's durations
    animations: true

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
        {
            const followed = ThemeRules.resolve(Theme.builtin, chain.chain, {});
            assertEqual(followed.colors.visualizer, followed.colors.accent, "a follower unset takes its leader's colour");
            const own = ThemeRules.resolve(Theme.builtin, [{ name: "x", theme: { colors: { visualizer: "#123456" } } }], {});
            assertEqual(own.colors.visualizer, "#123456", "and its own once a theme sets it");
            assertEqual(origins.colors.visualizer?.follows, "accent", "its origin says whom it follows");
            assertEqual(Theme.builtin.colors.visualizer, "", "the built-in value stays empty");
        }
        for (const entry of ThemeRules.colorTokens)
            assert(entry.token in Theme.builtin.colors, "the colour " + entry.token + " is a built-in token");
        assertEqual(ThemeRules.colorTokens.length, Object.keys(Theme.builtin.colors).length, "and every built-in colour is listed");
        for (const entry of ThemeRules.fontTokens) {
            assert(entry.token in Theme.builtin.fonts, "the font size " + entry.token + " is a built-in token");
            const size = Theme.builtin.fonts[entry.token];
            assert(size >= entry.from && size <= entry.to, "and its slider reaches today's " + size + " px");
        }
        assertEqual(ThemeRules.fontTokens.length + 1, Object.keys(Theme.builtin.fonts).length, "every built-in size is listed, besides the family");
        assertEqual(JSON.stringify(ThemeRules.animationRoles.map(entry => entry.role).sort()),
            JSON.stringify(Object.keys(Theme.builtin.durations).sort()), "the Animations page lists every role");
        assertEqual(JSON.stringify([].concat(...ThemeRules.animationRoles.map(entry => entry.curves)).sort()),
            JSON.stringify(Object.keys(Theme.builtin.curves).sort()), "and every curve token, with its role");
        for (const entry of ThemeRules.animationRoles)
            assert(Theme.builtin.durations[entry.role] <= entry.to, "the slider for " + entry.role + " reaches the built-in duration");
        const waveRole = ThemeRules.animationRoles.find(entry => entry.role === "progressWave");
        const travelRole = ThemeRules.animationRoles.find(entry => entry.role === "progressWaveTravel");
        assert(waveRole !== undefined && waveRole.curves.length === 0, "the time between the progress bars' waves is a role on the Animations page, without a curve");
        assert(travelRole !== undefined && travelRole.curves.join() === "progressWave", "… and one wave's crossing, with the wave's curve");
        assertEqual(Theme.builtin.durations.progressWave + " " + Theme.builtin.durations.progressWaveTravel + " " + Theme.builtin.curves.progressWave,
                    "300 1200 Linear", "… a new wave every 300 ms, each crossing in 1200 ms at an even pace");
        assertEqual(Theme.duration("progressWaveTravel"), Theme.builtin.durations.progressWaveTravel, "the theme hands out the crossing time");
        for (const name of ThemeRules.qtCurveNames)
            assert(ThemeRules.isQtCurve(name), name + " is one of Qt's curves");
        for (const group of ThemeRules.shapeGroups)
            assert(Object.keys(Theme.builtin[group] ?? {}).length > 0, "the shape group " + group + " has built-in tokens");
        for (const group of ThemeRules.shapeGroups) {
            const shown = (ThemeRules.shapeTokenInfo[group] ?? []).map(entry => entry.token).sort();
            assertEqual(JSON.stringify(shown), JSON.stringify(Object.keys(Theme.builtin[group]).sort()),
                "the Appearance pages show every token of " + group);
            for (const entry of ThemeRules.shapeTokenInfo[group] ?? [])
                assert(Theme.builtin[group][entry.token] >= entry.from && Theme.builtin[group][entry.token] <= entry.to,
                    "the slider for " + group + "." + entry.token + " reaches the built-in value");
        }
        for (const token of ThemeRules.barTokens)
            assert(token in Theme.builtin.bar, "the bar token " + token + " is built in");
        assertEqual(Theme.button.radius, Theme.builtin.button.radius, "a shape group reads as Theme.<group>.<token>");
        assertEqual(Theme.warningButton.radius, Theme.builtin.warningButton.radius, "buttons that warn have a group of their own");
        assertEqual(Theme.successButton.radius, Theme.builtin.successButton.radius, "and buttons for a good outcome");

        // --- a pill's height by size ---
        assertEqual(JSON.stringify([Theme.builtin.pill.minHeight, Theme.builtin.pill.mediumHeight, Theme.builtin.pill.largeHeight]), "[22,26,30]",
            "the pills' three built-in heights");
        const pill = { minHeight: 10, mediumHeight: 20, largeHeight: 40 };
        assertEqual(ThemeRules.pillHeight(pill, "s"), 10, "a small pill takes the theme's small height");
        assertEqual(ThemeRules.pillHeight(pill, "m"), 20, "a medium one the medium height");
        assertEqual(ThemeRules.pillHeight(pill, "l"), 40, "a large one the large height");
        assertEqual(ThemeRules.pillHeight(pill, "xl"), 10, "a size that does not exist is small");
        assertEqual(ThemeRules.pillHeight(pill, "toString"), 10, "… a word every object knows included");
        assertEqual(ThemeRules.pillHeight(pill, undefined), 10, "and so is no size");

        // --- a button's look by kind and state ---
        const look = (kind, state) => {
            const found = ThemeRules.buttonLook(kind, state);
            return found.group + " " + found.fill + " " + found.label + " " + (found.border === "" ? "-" : found.border);
        };
        const hot = { hot: true };
        const asking = { asking: true };
        assertEqual(look("normal", {}), "button surface textSecondary -", "a plain button: the surface, no border");
        assertEqual(look("normal", hot), "button surfaceHover textSecondary -", "… lighter under the pointer");
        assertEqual(look("cancel", {}), "cancelButton surface textSecondary -", "a cancel button: as plain, its own shape");
        assertEqual(look("save", {}), "saveButton confirm textPrimary -", "a button that confirms: filled, no border");
        assertEqual(look("save", hot), "saveButton confirmHover textPrimary -", "… its hover colour under the pointer");
        assertEqual(look("saveChange", {}), "saveButton confirmSecondary textPrimary -", "confirming a change: the second confirm colour");
        assertEqual(look("saveChange", hot), "saveButton confirmSecondaryHover textPrimary -", "… and its hover colour");
        assertEqual(look("delete", {}), "deleteButton surface textSecondary error", "a button that stops or removes: plain with a red border");
        assertEqual(look("delete", hot), "deleteButton error textPrimary error", "… filled red under the pointer");
        assertEqual(look("warning", {}), "warningButton surface textSecondary warning", "a button that warns: a border in the warning colour");
        assertEqual(look("warning", hot), "warningButton warning textPrimary warning", "… filled with it under the pointer");
        assertEqual(look("success", {}), "successButton surface textSecondary success", "a good outcome: a border in the success colour");
        assertEqual(look("success", hot), "successButton success textPrimary success", "… filled with it under the pointer");
        assertEqual(look("action", {}), "button accent onAccent -", "an app's action: filled with the accent, its label in the colour on it, no border");
        assertEqual(look("action", hot), "button accentHover onAccent -", "… the accent's hover colour under the pointer");
        assertEqual(look("action", { checked: true }), "button accent onAccent -", "… checked changes nothing");
        assertEqual(look("action", asking), "button surface accent accent", "asking, an action: plain, the question and a border in the accent");
        assertEqual(look("action", { asking: true, hot: true }), "button surfaceHover accent accent", "… lighter under the pointer, never filled");
        assertEqual(look("normal", { checked: true }), "button accent onAccent -", "a toggle that is on: the accent");
        assertEqual(look("normal", { checked: true, hot: true }), "button accentHover onAccent -", "… its hover colour under the pointer");
        assertEqual(look("delete", { checked: true }), "deleteButton surface textSecondary error", "a kind with a tone keeps its look when checked");
        assertEqual(look("primry", {}), "button surface textSecondary -", "a word that is no kind shows as a plain button");
        assertEqual(look("delete", undefined), "deleteButton surface textSecondary error", "no state given: at rest");
        assertEqual(look("delete", asking), "deleteButton surface error error", "asking, a delete: plain, the question and a border in red");
        assertEqual(look("delete", { asking: true, hot: true }), "deleteButton surfaceHover error error", "… lighter under the pointer, never filled");
        assertEqual(look("warning", asking), "warningButton surface warning warning", "asking, a warning: in the warning colour");
        assertEqual(look("success", asking), "successButton surface success success", "asking, a good outcome: in the success colour");
        assertEqual(look("save", asking), "saveButton surface confirm confirm", "asking before turning something on: in the confirm colour");
        assertEqual(look("normal", asking), "button surface textPrimary outline", "asking, a plain button: bright text, the ordinary outline");
        assertEqual(ThemeRules.buttonLook("delete", { focused: true }).ring, "textSecondary", "with the keyboard: a ring in the colour a focused checkbox takes");
        assertEqual(look("delete", { focused: true }), "deleteButton surface textSecondary error", "… the kind's colours kept");
        assertEqual(ThemeRules.buttonLook("save", { asking: true, focused: true }).ring, "textSecondary", "… asking too");
        assertEqual(ThemeRules.buttonLook("save", {}).ring + "|" + ThemeRules.buttonLook("save", undefined).ring, "|", "without it: no ring");
        for (const kind of ["normal", "cancel", "save", "saveChange", "delete", "warning", "success", "action"])
            for (const state of [{}, hot, asking, { checked: true }, { checked: true, hot: true }, { asking: true, hot: true }]) {
                const found = ThemeRules.buttonLook(kind, state);
                assert(ThemeRules.shapeGroups.includes(found.group) && Theme[found.group].radius >= 0
                    && [found.fill, found.label].concat(found.border === "" ? [] : [found.border]).every(name => Theme[name] !== undefined),
                    "the look of " + kind + " " + JSON.stringify(state) + " names a shape group and colours the theme has");
            }
        // The Settings modal's looks: each kind's colour and icon, an unknown kind as info
        const modalLook = kind => { const found = ThemeRules.modalLook(kind); return [found.kind, found.border, found.tone, found.titleColor].join(" "); };
        assertEqual(modalLook("danger"), "danger error error textPrimary", "modalLook: danger wears the error colour");
        assertEqual(modalLook("warning"), "warning warning warning textPrimary", "… warning the warning colour");
        assertEqual(modalLook("success"), "success success success textPrimary", "… success the success colour");
        assertEqual(modalLook("info"), "info accent accent textPrimary", "… info the accent");
        for (const odd of ["delete", "", undefined, null, 3, "toString", "__proto__"])
            assertEqual(modalLook(odd), "info accent accent textPrimary", "… " + JSON.stringify(odd) + " is no kind: info");
        assertEqual(new Set(ThemeRules.modalKinds.map(kind => ThemeRules.modalLook(kind).icon)).size, 4, "… each kind its own icon");
        for (const kind of ThemeRules.modalKinds) {
            const found = ThemeRules.modalLook(kind);
            assert([found.border, found.tone, found.titleColor].every(name => Theme[name] !== undefined) && found.icon !== "",
                "the look of a " + kind + " modal names colours the theme has, and an icon");
        }
        assertEqual(Theme.builtin.colors.modalDim, "#8c000000", "the modal's dimming is built in: black at 55 %");
        assert(Math.abs(Theme.modalDim.a - 0.55) < 0.01 && Theme.modalDim.r === 0 && Theme.modalDim.g === 0 && Theme.modalDim.b === 0,
            "… and so the theme hands it out");
        assert(!Qt.colorEqual(Theme.modalDim, Theme.scrim) && Theme.scrim.a === 1, "… never the scrim, which is opaque");
        assertEqual(ThemeRules.colorTokens.find(entry => entry.token === "modalDim")?.group, "Backgrounds", "… a colour of its own, under Backgrounds");
        assertEqual(JSON.stringify(Object.keys(Theme.modal).sort()), JSON.stringify(["borderWidth", "padding", "radius", "spacing", "widthMedium", "widthSmall"]),
            "the modal's sizes are a theme group: Theme.modal");
        assertEqual(JSON.stringify(ThemeRules.barTokenInfo.map(entry => entry.token)), JSON.stringify(ThemeRules.barTokens),
            "the Bar shape page lists every geometry token, in order");
        for (const entry of ThemeRules.barTokenInfo)
            assert(Theme.builtin.bar[entry.token] >= entry.from && Theme.builtin.bar[entry.token] <= entry.to,
                "the slider for " + entry.token + " reaches the built-in value");

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
        assertEqual(JSON.stringify(ThemeRules.applyDraft({}, { colors: { a: "#1" } })), JSON.stringify({ colors: { a: "#1" } }), "a group of one token stays");
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
        // A deleted theme's backup: <name>.json.bak-<stamp>, parsed back to the theme it holds
        const backupName = ThemeRules.themeBackupName("Power save", "2026-11-26T09:05:07.042Z");
        assertEqual(backupName, "Power save.json.bak-2026-11-26T09-05-07-042Z", "a theme backup is named after the theme and the time");
        assertEqual(ThemeRules.themeBackupName("a/b", "2026-11-26T09:05:07.042Z") + "|" + ThemeRules.themeBackupName(".x", "2026-11-26T09:05:07.042Z")
                    + "|" + ThemeRules.themeBackupName("dark", "yesterday") + "|" + ThemeRules.themeBackupName("dark", "2026-11-26T09:05:07Z"),
                    "|||", "no backup name for a name that is no theme's, or a time that is not one");
        const parsedBackup = ThemeRules.parseThemeBackupName(backupName);
        assertEqual(parsedBackup.ok + "|" + parsedBackup.theme + "|" + parsedBackup.time, "true|Power save|" + Date.UTC(2026, 10, 26, 9, 5, 7, 42),
                    "a theme backup's name gives back its theme and time");
        assertEqual(ThemeRules.parseThemeBackupName("/somewhere/dark.json.bak-2026-11-26T09-05-07-042Z").theme, "dark", "a path: its last part");
        assertEqual(ThemeRules.parseThemeBackupName("x.json.bak-2026-11-26T09-05-07-042Z.json.bak-2026-11-26T09-05-07-043Z").theme,
                    "x.json.bak-2026-11-26T09-05-07-042Z", "the stamp is the name's end");
        for (const other of ["dark.json", "dark.json.bak-2026-11-26T09-05-07-042Z.part", ".dark.json.bak-2026-11-26T09-05-07-042Z",
                             ".json.bak-2026-11-26T09-05-07-042Z", "dark.json.bak-2026-11-26T09-05-07Z", "dark.json.bak-2026-11-26T09-05-07-042Zx",
                             " dark.json.bak-2026-11-26T09-05-07-042Z", "", null, 42])
            assertEqual(JSON.stringify(ThemeRules.parseThemeBackupName(other)), JSON.stringify({ ok: false, theme: "", time: 0 }),
                        "not a theme backup: " + JSON.stringify(other));
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
        const savedInstant = Theme.instantAnimations;
        Theme.instantAnimations = true;
        assert(["expand", "hover", "fade", "no such role"].every(role => Theme.duration(role) === 1), "instant animations (the unit runner's): every role 1 ms, colours too");
        assertEqual(Theme.duration("spin") + " " + Theme.duration("progressWaveTravel"), Theme.builtin.durations.spin + " " + Theme.builtin.durations.progressWaveTravel, "… but a looping one keeps its time");
        Theme.instantAnimations = false;
        assert(Theme.duration("hover") > 1, "… and back at the theme's durations");
        Theme.instantAnimations = savedInstant;

        const toDefault = ThemeRules.chainFor("wallpaper", name => name === "wallpaper" ? { extends: "default" } : null);
        assertEqual(toDefault.errors.length, 0, "extending a default theme that has no file is not an error");

        // --- bar geometry moves from profiles into themes (the registered migration) ---
        const barLayout = Migrations.all().find(migration => migration.migrationId === "theme.barLayout");
        // → { document, records, ok } of one run on profiles, globals, the old bar section and theme files
        const moveBar = (profiles, globals, legacy, files, records) => {
            const document = { raw: legacy === undefined ? {} : { bar: { layout: legacy } }, profiles: profiles, globals: globals, presets: {}, files: files ?? {} };
            return MigrationRules.applyOne(barLayout, document, {}, records ?? []);
        };
        const profiles = [
            { name: "Full", when: {}, set: { "bar.layout.barHeight": 40, "bar.layout.rightPadding": 5, "polling.x": 1 } },
            { name: "Quiet", when: {}, set: {} },
            { name: "Power/save", when: {}, set: { "bar.layout.leftMargin": 300 } }
        ];
        const moved = moveBar(profiles, { "general.debug": true }, undefined, { "themes/Full.json": { extends: "default" } });
        assert(moved.ok, "bar geometry migration: runs inside its scope" + (moved.ok ? "" : ": " + moved.error));
        assertEqual(JSON.stringify(Object.keys(moved.document.files)), JSON.stringify(["themes/Full.json", "themes/Full 2.json", "themes/Power-save.json"]),
            "a theme per profile with geometry, under a free file name");
        assertEqual(JSON.stringify(moved.document.files["themes/Full 2.json"]), JSON.stringify({ extends: "default", bar: { barHeight: 40, rightPadding: 5 } }),
            "holding the profile's geometry, over the default theme");
        assertEqual(JSON.stringify(moved.document.files["themes/Full.json"]), JSON.stringify({ extends: "default" }), "an existing theme file is left as it is");
        assertEqual(moved.document.files["themes/Power-save.json"].extends, "Full 2", "a later profile's theme extends the one before it");
        assertEqual(moved.document.profiles[0].set["appearance.theme"], "Full 2", "the profile picks its theme");
        assertEqual(moved.document.profiles[1].set["appearance.theme"], undefined, "a profile without geometry keeps inheriting");
        assert(!("bar.layout.barHeight" in moved.document.profiles[0].set), "the geometry leaves the profile");
        assertEqual(moved.document.profiles[0].set["polling.x"], 1, "other settings stay");
        assertEqual(profiles[0].set["bar.layout.barHeight"], 40, "the inputs are not modified");
        assertEqual(moved.document.globals["general.debug"], true, "other globals stay");

        const pinnedMove = moveBar([{ name: "Full", set: {} }, { name: "B", set: { "bar.layout.topOffset": 3 } }],
            { "bar.layout.barHeight": 30 }, undefined);
        assertEqual(Object.keys(pinnedMove.document.files).length, 2, "pinned geometry gives the first profile a theme");
        assertEqual(pinnedMove.document.files["themes/B.json"].bar.barHeight, 30, "and goes into every theme, as it applied everywhere");
        assert(!("bar.layout.barHeight" in pinnedMove.document.globals), "and leaves the globals");

        const legacyMove = moveBar([{ name: "Full", set: { "bar.layout.topOffset": 1 } }], {}, { barHeight: 33, topOffset: 9 });
        assertEqual(legacyMove.document.files["themes/Full.json"].bar.barHeight, 33, "geometry from before profiles goes to the first profile's theme");
        assertEqual(legacyMove.document.files["themes/Full.json"].bar.topOffset, 1, "under what the profile set itself");
        assertEqual(legacyMove.document.raw.bar.layout.barHeight, 33, "the old section stays in the file");
        const copiedBefore = moveBar([{ name: "Full", set: {} }], {}, { barHeight: 33 }, {}, ["bar.layout.barHeight", "bar.left"]);
        assertEqual(Object.keys(copiedBefore.document.files).length, 0, "geometry from before profiles that reached a profile already (marked): not again");
        assertEqual(JSON.stringify(copiedBefore.records), JSON.stringify(["bar.layout.barHeight", "bar.left"]), "the markers it reads stay as they were");
        assertEqual(Object.keys(moveBar([{ name: "Full", set: {} }], {}, undefined).document.files).length, 0,
            "no geometry anywhere: no themes");

        // A file name has at most 255 bytes: a long profile name gives a shorter theme name,
        // still one of its own, the profile keeping its name
        const utf8Bytes = text => encodeURIComponent(text).replace(/%[0-9A-F]{2}/g, "x").length;
        assertEqual(utf8Bytes("\u{1F600}a\u00e9"), 7, "(the byte count: 4 + 1 + 2)");
        const longName = "\u{1F600}".repeat(75);
        const otherLongName = "\u{1F600}".repeat(74) + "\u{1F601}";
        const longMove = moveBar([{ name: longName, set: { "bar.layout.barHeight": 30 } }, { name: otherLongName, set: { "bar.layout.barHeight": 31 } },
                                  { name: longName + "x", set: { "bar.layout.barHeight": 32 } }], {}, undefined);
        assert(longMove.ok, "a 300-byte profile name: migrated" + (longMove.ok ? "" : ": " + longMove.error));
        const longThemes = longMove.document.profiles.map(profile => profile.set["appearance.theme"]);
        assert(longThemes.every(name => typeof name === "string" && utf8Bytes(name + ".json") <= 255),
               "a 300-byte profile name: each theme file name within 255 bytes (" + longThemes.map(name => utf8Bytes(String(name) + ".json")).join(", ") + ")");
        assertEqual(new Set(longThemes).size, 3, "… each of its own, though they start alike");
        assert(longThemes[0] !== longThemes[1] && !longThemes[1].endsWith(" 2"), "… apart by what follows their start, not by a number");
        assert(longThemes.every(name => ("themes/" + name + ".json") in longMove.document.files), "… the file the profile picks");
        assertEqual(longMove.document.profiles[0].name, longName, "… the profile keeps its name");
        assert(longThemes[0].startsWith("\u{1F600}".repeat(40)), "… the theme named after its start");

        // --- keys a theme file shares with every object's prototype ---
        // Theme files can come from others: "__proto__", "constructor" or "toString" as a key
        // is a token like any other, never a property every object has
        {
            const hostile = '{ "__proto__": { "injected": "#bad000" }, "constructor": "#bad001", "toString": "#bad002", "hasOwnProperty": "#bad003", "accent": "#abcdef" }';
            const plainProto = Object.getPrototypeOf({});
            const unknownIgnored = (colors, where) => {
                assert(Object.getPrototypeOf(colors) === plainProto, where + ": the colours keep their prototype");
                assertEqual(colors.injected, undefined, where + ": nothing comes in through \"__proto__\"");
                for (const key of ["__proto__", "constructor", "toString", "hasOwnProperty"])
                    assert(!Object.prototype.hasOwnProperty.call(colors, key), where + ": \"" + key + "\" is not a known token, ignored");
                assertEqual(typeof colors.toString, "function", where + ": toString is still the object's");
            };
            const hostileTheme = [{ name: "x", theme: { colors: JSON.parse(hostile), fonts: JSON.parse(hostile) } }];
            const layered = ThemeRules.resolve(Theme.builtin, hostileTheme, {});
            unknownIgnored(layered.colors, "a theme's colours");
            unknownIgnored(layered.fonts, "a theme's fonts");
            assertEqual(layered.colors.accent, "#abcdef", "the known token beside them applies");
            assertEqual(layered.colors.visualizer, "#abcdef", "and a follower still follows it");
            const fromPalette = ThemeRules.resolve(Theme.builtin, [{ name: "x", theme: {} }], { x: JSON.parse(hostile) });
            unknownIgnored(fromPalette.colors, "a palette file");
            assertEqual(fromPalette.colors.accent, "#abcdef", "a palette's known token applies");
            assertEqual(ThemeRules.resolve(Theme.builtin, [{ name: "constructor", theme: {} }], {}).colors.accent, Theme.builtin.colors.accent,
                "a theme named \"constructor\" without a palette takes none");
            // A follower's leader set through "__proto__" is not seen as set
            const followerProto = ThemeRules.resolve(Theme.builtin, [{ name: "x", theme: { colors: JSON.parse('{ "__proto__": { "visualizer": "#bad004" } }') } }], {});
            assertEqual(followerProto.colors.visualizer, Theme.builtin.colors.accent, "a follower set only through \"__proto__\" still follows");

            const hostileOrigins = ThemeRules.origins(hostileTheme, { x: JSON.parse(hostile) });
            assert(Object.getPrototypeOf(hostileOrigins.colors) === plainProto, "origins: the colours keep their prototype");
            assertEqual(hostileOrigins.colors.injected, undefined, "origins: nothing comes in through \"__proto__\"");
            assertEqual(hostileOrigins.colors.accent?.theme, "x", "origins: the known token is the theme's");
            assertEqual(hostileOrigins.colors.visualizer?.follows, "accent", "origins: a follower nothing sets follows");
            // Theme marks a draft's tokens on what origins returns, so its entries stay writable
            hostileOrigins.colors.accent = { theme: "y", palette: false, draft: true };
            assertEqual(hostileOrigins.colors.accent.theme, "y", "origins: an entry can be overwritten");
            const protoOrigins = ThemeRules.origins([{ name: "x", theme: { colors: JSON.parse('{ "__proto__": { "visualizer": 1 } }') } }], {});
            assertEqual(protoOrigins.colors.visualizer?.follows, "accent", "origins: a follower set only through \"__proto__\" still follows");

            const hostileDraft = JSON.parse('{ "__proto__": { "colors": { "injected": "#bad005" } }, "colors": ' + hostile + ' }');
            const draftedHostile = ThemeRules.applyDraft(JSON.parse('{ "__proto__": { "x": 1 }, "colors": { "surface": "#111111" } }'), hostileDraft);
            assert(Object.getPrototypeOf(draftedHostile) === plainProto, "applyDraft: the theme keeps its prototype");
            assert(Object.getPrototypeOf(draftedHostile.colors) === plainProto, "applyDraft: its colours keep their prototype");
            assertEqual(draftedHostile.colors.injected, undefined, "applyDraft: nothing comes in through \"__proto__\"");
            assertEqual(draftedHostile.colors.accent, "#abcdef", "applyDraft: the draft's tokens apply");
            assertEqual(draftedHostile.colors.surface, "#111111", "applyDraft: the file's stay");
            assertEqual(JSON.stringify(ThemeRules.draftWith({}, {}, "colors", "constructor", null)), "{}",
                "draftWith: resetting \"constructor\" the file does not set drops it");
            assertEqual(JSON.stringify(ThemeRules.draftWith({}, {}, "colors", "toString", null)), "{}",
                "draftWith: resetting \"toString\" the file does not set drops it");
            const withProto = ThemeRules.draftWith({}, {}, "__proto__", "x", "#1");
            assert(Object.getPrototypeOf(withProto) === plainProto, "draftWith: the draft keeps its prototype");
            assertEqual(JSON.stringify(ThemeRules.draftWithout(JSON.parse('{ "colors": { "a": "#1" } }'), "__proto__", "a")), JSON.stringify({ colors: { a: "#1" } }),
                "draftWithout: a group named \"__proto__\" is not found");
            const splitHostile = ThemeRules.splitDraft(hostileDraft);
            assert(Object.getPrototypeOf(splitHostile.taken) === plainProto, "splitDraft: the part taken keeps its prototype");
            assertEqual(splitHostile.taken.colors?.accent, "#abcdef", "splitDraft: and holds the draft's groups");
            const themesHostile = { child: JSON.parse('{ "__proto__": { "x": 1 }, "extends": "base" }') };
            const renamedHostile = ThemeRules.renameExtends(themesHostile, "base", "core");
            assert(Object.getPrototypeOf(renamedHostile.child) === plainProto, "renameExtends: the theme keeps its prototype");
            assertEqual(renamedHostile.child.extends, "core", "renameExtends: re-pointed");
            assertEqual(renamedHostile.child.x, undefined, "renameExtends: nothing comes in through \"__proto__\"");
            const curvesHostile = { a: JSON.parse('{ "__proto__": { "x": 1 }, "curves": { "hover": "snappy" } }') };
            const renamedCurve = ThemeRules.renameCurveIn(curvesHostile, "snappy", "quick");
            assert(Object.getPrototypeOf(renamedCurve.a) === plainProto, "renameCurveIn: the theme keeps its prototype");
            assertEqual(renamedCurve.a.curves.hover, "quick", "renameCurveIn: re-pointed");
            const retargetedHostile = ThemeRules.retargetTheme([], JSON.parse('{ "__proto__": { "x": 1 }, "appearance.theme": "a" }'), "a", "b");
            assert(Object.getPrototypeOf(retargetedHostile.globals) === plainProto, "retargetTheme: the globals keep their prototype");
            assertEqual(retargetedHostile.globals["appearance.theme"], "b", "retargetTheme: re-pointed");
            assertEqual(ThemeRules.withoutExtends({ b: { extends: "toString" } }, "toString").b.extends, "default",
                "withoutExtends: a removed theme named \"toString\" that is not there hands over the default");
            assertEqual(JSON.stringify(ThemeRules.draftWith(JSON.parse('{ "colors": null }'), {}, "colors", "accent", "#1")), JSON.stringify({ colors: { accent: "#1" } }),
                "draftWith: a hand-edited draft's group that is null is taken as empty");
            assertEqual(JSON.stringify(ThemeRules.draftWith(JSON.parse('{ "colors": 5 }'), {}, "colors", "accent", "#1")), JSON.stringify({ colors: { accent: "#1" } }),
                "draftWith: … and one that is a number");
            // The curves library: names are the user's, and may be any of these
            const library = JSON.parse('{ "__proto__": [0, 0, 1, 1], "snappy": [0.2, 0, 0, 1], "toString": [0.5, 0, 0.5, 1] }');
            const renamedLibrary = ThemeRules.libraryWithRename(library, "__proto__", "linearish");
            assertEqual(JSON.stringify(Object.keys(renamedLibrary ?? {})), JSON.stringify(["linearish", "snappy", "toString"]),
                "libraryWithRename: a curve named \"__proto__\" renamed in its place");
            assert(renamedLibrary !== null && Object.getPrototypeOf(renamedLibrary) === plainProto, "libraryWithRename: the library keeps its prototype");
            const toProto = ThemeRules.libraryWithRename(JSON.parse('{ "snappy": [0.2, 0, 0, 1] }'), "snappy", "__proto__");
            assertEqual(JSON.stringify(ThemeRules.ownValue(toProto, "__proto__")), "[0.2,0,0,1]", "libraryWithRename: renamed to \"__proto__\": kept as that name");
            assert(toProto !== null && Object.getPrototypeOf(toProto) === plainProto, "… the library keeps its prototype");
            assertEqual(ThemeRules.libraryWithRename({ snappy: [0.2, 0, 0, 1] }, "constructor", "x"), null, "libraryWithRename: \"constructor\" is not in the library");
            assertEqual(JSON.stringify(ThemeRules.libraryWithRename({ snappy: [0.2, 0, 0, 1] }, "snappy", "toString")), JSON.stringify({ toString: [0.2, 0, 0, 1] }),
                "libraryWithRename: \"toString\" is a free name");
            assertEqual(ThemeRules.libraryWithRename(library, "snappy", "toString"), null, "libraryWithRename: a name the library has is taken");
            const constructorLook = ThemeRules.buttonLook("constructor", {});
            assertEqual(JSON.stringify([constructorLook.group, constructorLook.fill, constructorLook.border]), JSON.stringify(["button", "surface", ""]),
                "buttonLook: a kind named \"constructor\" is plain");
            assertEqual(ThemeRules.buttonLook("toString", { asking: true }).label, "textPrimary", "buttonLook: \"toString\" asking is plain");
        }

        assertEqual(ThemeRules.freeName("Power/save", name => false), "Power-save", "freeName: the name, a \"/\" made \"-\"");
        assertEqual(ThemeRules.freeName("Ease", name => name === "Ease"), "Ease 2", "freeName: taken, the next number");
        assertEqual(ThemeRules.freeName("Ease", name => name === "Ease" || name === "Ease 2"), "Ease 3", "freeName: the first number free");
        assertEqual(ThemeRules.freeName("  ", name => false), "Theme", "freeName: an empty name: \"Theme\"");
    }
}
