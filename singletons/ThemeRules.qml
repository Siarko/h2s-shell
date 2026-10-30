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
//     "bar":        { "<token>": <number> },  optional; geometry, see barTokens
//     "durations":  { "<role>": <ms> },       optional; animation roles, see Theme
//     "curves":     { "<role>": "<curve>" }   optional; a Qt easing name ("OutQuad", …) or
//                                             the name of a curve in the curves library
//   }
//
// The curves library, ~/.config/h2s_shell/curves.json, shared by every theme:
//   { "<name>": [x1, y1, x2, y2] }            a cubic Bézier from (0,0) to (1,1)
// or, for several segments, Qt's own form: [c1x, c1y, c2x, c2y, endX, endY, …], the last
// end being (1,1).
// Every group is partial: what a theme leaves out comes from what it extends.
Singleton {
    id: root

    // Groups of tokens a theme file may set
    readonly property var groups: ["colors", "fonts", "bar", "durations", "curves"]

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

    // ---- What the Appearance pages show ----

    // The base colours a theme sets, by group, with what each is for (the transparent
    // variants are derived in Theme, not set)
    readonly property var colorTokens: [
        { group: "Backgrounds", token: "barBackground", label: "Bar", hint: "The bar" },
        { group: "Backgrounds", token: "popupBackground", label: "Popup", hint: "Popups and their curved corners" },
        { group: "Backgrounds", token: "surface", label: "Surface", hint: "An element: bar cell, card, field, row" },
        { group: "Backgrounds", token: "surfaceHover", label: "Surface, hovered", hint: "An element under the pointer, or whose popup is open" },
        { group: "Backgrounds", token: "scrim", label: "Scrim", hint: "Behind the screensaver and the lock screen" },
        { group: "Accent", token: "accent", label: "Accent", hint: "Selection, active state, progress, graphs" },
        { group: "Accent", token: "accentHover", label: "Accent, hovered", hint: "The accent under the pointer" },
        { group: "Accent", token: "accentDark", label: "Accent, dark", hint: "Filled accent: focused workspace, code buttons" },
        { group: "Accent", token: "onAccent", label: "On accent", hint: "Text and icons on the accent" },
        { group: "Accent", token: "accentSecondary", label: "Second accent", hint: "A second series or highlight: upload, sidebar selection" },
        { group: "Text", token: "textPrimary", label: "Primary", hint: "Labels, headings, the clock" },
        { group: "Text", token: "textSecondary", label: "Secondary", hint: "Secondary labels, body text" },
        { group: "Text", token: "textMuted", label: "Muted", hint: "Timestamps, links, empty states" },
        { group: "Text", token: "textDisabled", label: "Disabled", hint: "Disabled, other-month days, faint icons; dividers and faint fills derive from it" },
        { group: "Status", token: "error", label: "Error", hint: "Errors, destructive actions" },
        { group: "Status", token: "warning", label: "Warning", hint: "Warnings, volume above 100%" },
        { group: "Status", token: "success", label: "Success", hint: "Connected, done" },
        { group: "Workspaces", token: "workspaceActive", label: "Active", hint: "A workspace that is active but not focused (focused uses the dark accent)" },
        { group: "Workspaces", token: "workspaceSpecial", label: "Special", hint: "A shown special (scratchpad) workspace" },
        { group: "Calendar", token: "calendarToday", label: "Today", hint: "The circle behind today's date" },
        { group: "Buttons", token: "confirm", label: "Confirm", hint: "Confirming: add an event" },
        { group: "Buttons", token: "confirmHover", label: "Confirm, hovered", hint: "A confirm button under the pointer" },
        { group: "Buttons", token: "confirmSecondary", label: "Confirm a change", hint: "Confirming a change: save an edited event" },
        { group: "Buttons", token: "confirmSecondaryHover", label: "Confirm a change, hovered", hint: "A confirm-a-change button under the pointer" }
    ]

    // The bar's geometry tokens (barTokens) as the Bar shape page shows them: label, use,
    // slider range and unit
    readonly property var barTokenInfo: [
        { token: "barHeight", group: "Size", label: "Bar height", hint: "Excluding the reserved space and top offset", from: 10, to: 80, suffix: " px" },
        { token: "reservedSpace", group: "Size", label: "Reserved space", hint: "Kept free for the bar at the top of the screen: its height and offset", from: 10, to: 80, suffix: " px" },
        { token: "topOffset", group: "Size", label: "Top offset", hint: "Between the bar and the top of the screen", from: 0, to: 80, suffix: " px" },
        { token: "leftMargin", group: "Size", label: "Left margin", hint: "Between the bar and the screen's left edge", from: 0, to: 300, suffix: " px" },
        { token: "rightMargin", group: "Size", label: "Right margin", hint: "Between the bar and the screen's right edge", from: 0, to: 300, suffix: " px" },
        { token: "leftPadding", group: "Size", label: "Left padding", hint: "Inside the bar, before its first widget", from: 0, to: 300, suffix: " px" },
        { token: "rightPadding", group: "Size", label: "Right padding", hint: "Inside the bar, after its last widget", from: 0, to: 300, suffix: " px" },
        { token: "radiusTopLeft", group: "Corners", label: "Top left", hint: "In percent of half the bar's height", from: 0, to: 100, suffix: "%" },
        { token: "radiusTopRight", group: "Corners", label: "Top right", hint: "In percent of half the bar's height", from: 0, to: 100, suffix: "%" },
        { token: "radiusBottomLeft", group: "Corners", label: "Bottom left", hint: "In percent of half the bar's height", from: 0, to: 100, suffix: "%" },
        { token: "radiusBottomRight", group: "Corners", label: "Bottom right", hint: "In percent of half the bar's height", from: 0, to: 100, suffix: "%" }
    ]

    // The font tokens: the family, and the sizes in pixels with what each is for and the
    // range its slider offers
    readonly property var fontTokens: [
        { token: "sizeTiny", label: "Tiny", hint: "The smallest form labels", from: 6, to: 30 },
        { token: "sizeXSmall", label: "Extra small", hint: "Very small secondary labels", from: 6, to: 30 },
        { token: "sizeSmall", label: "Small", hint: "Metadata, times, captions, hints", from: 6, to: 30 },
        { token: "sizeBody", label: "Body", hint: "Most text: rows, fields, buttons", from: 6, to: 30 },
        { token: "sizeBodyLarge", label: "Body, large", hint: "Larger labels: settings names, volume", from: 6, to: 30 },
        { token: "sizeMedium", label: "Medium", hint: "Subheadings, small icons", from: 6, to: 36 },
        { token: "sizeSection", label: "Section", hint: "Section icons, calendar headers, the bell", from: 8, to: 40 },
        { token: "sizeHeading", label: "Heading", hint: "Settings headings, most bar icons", from: 8, to: 40 },
        { token: "sizeTitle", label: "Title", hint: "Panel titles, large bar icons (clock, power, settings)", from: 8, to: 48 },
        { token: "sizeDisplay", label: "Display", hint: "Calendar events", from: 8, to: 48 },
        { token: "sizeLargeDisplay", label: "Large display", hint: "Music panel headers", from: 8, to: 60 },
        { token: "sizeXXLargeDisplay", label: "Extra large display", hint: "The music track's name", from: 10, to: 72 },
        { token: "sizeHero", label: "Hero", hint: "The empty notifications icon", from: 16, to: 96 }
    ]

    // Where each resolved value comes from: { group: { token: { theme, palette } } } for
    // what the chain sets — `theme` the name of the theme that has the last word, `palette`
    // true when it comes from that theme's palette file. A token absent here is built in.
    function origins(chain, palettes) {
        const result = {};
        for (const group of groups)
            result[group] = {};
        for (let i = chain.length - 1; i >= 0; i--) {
            const entry = chain[i];
            for (const token in palettes?.[entry.name] ?? {})
                result.colors[token] = { theme: entry.name, palette: true };
            for (const group of groups) {
                for (const token in entry.theme[group] ?? {})
                    result[group][token] = { theme: entry.name, palette: false };
            }
        }
        return result;
    }

    // ---- Drafts: changes made in the settings, not saved yet ----
    // A draft is part of a theme file, { group: { token: value } }, kept in a file of its
    // own; null as a value means the token is removed from the theme (a reset). It is laid
    // over the theme file, so what the draft does not touch follows the file.

    // The theme file `theme` with `draft` laid over it. Inputs are not modified.
    function applyDraft(theme, draft) {
        const result = JSON.parse(JSON.stringify(theme ?? {}));
        for (const group in draft ?? {}) {
            const values = Object.assign({}, result[group] ?? {});
            for (const token in draft[group]) {
                if (draft[group][token] === null)
                    delete values[token];
                else
                    values[token] = draft[group][token];
            }
            if (Object.keys(values).length > 0)
                result[group] = values;
            else
                delete result[group];
        }
        return result;
    }

    // `draft` with one token changed to `value`, or, with `value` null, reset: removed from
    // the theme if `theme` sets it, else dropped from the draft. Empty groups go.
    function draftWith(draft, theme, group, token, value) {
        const result = JSON.parse(JSON.stringify(draft ?? {}));
        result[group] = result[group] ?? {};
        if (value === null && !(token in (theme?.[group] ?? {})))
            delete result[group][token];
        else
            result[group][token] = value;
        if (Object.keys(result[group]).length === 0)
            delete result[group];
        return result;
    }

    // `draft` without its change to one token: back to what the theme file has
    function draftWithout(draft, group, token) {
        const result = JSON.parse(JSON.stringify(draft ?? {}));
        if (result[group]) {
            delete result[group][token];
            if (Object.keys(result[group]).length === 0)
                delete result[group];
        }
        return result;
    }

    // The part of `draft` in `groups` (all when not given), and the rest:
    // { taken, rest } — each a draft, possibly empty
    function splitDraft(draft, groups) {
        const taken = {};
        const rest = {};
        for (const group in draft ?? {}) {
            if (!groups || groups.includes(group))
                taken[group] = draft[group];
            else
                rest[group] = draft[group];
        }
        return { taken: taken, rest: rest };
    }

    // ---- Managing themes ----

    // Whether `name` may name a theme file: not empty, no spaces at its ends, no slash,
    // not hidden
    function validThemeName(name) {
        return typeof name === "string" && name.trim() !== "" && name === name.trim()
            && !name.includes("/") && !name.startsWith(".");
    }

    // The themes (`{ name: parsed file }`) that extend `oldName`, pointed at `newName`:
    // only those that changed. Inputs are not modified.
    function renameExtends(themes, oldName, newName) {
        const changed = {};
        for (const name in themes ?? {}) {
            if (themes[name]?.extends === oldName)
                changed[name] = Object.assign({}, themes[name], { extends: newName });
        }
        return changed;
    }

    // The themes that extend `removed`, extending what it extended instead (the default
    // theme when it extended nothing): only those that changed
    function withoutExtends(themes, removed) {
        const parent = typeof themes?.[removed]?.extends === "string" ? themes[removed].extends : "default";
        return renameExtends(themes, removed, parent);
    }

    // Profiles and pinned globals with `appearance.theme` set to `oldName` set to
    // `newName` instead. Inputs are not modified.
    // Returns { profiles, globals, changed: [profile names, "global" for the pin] }.
    function retargetTheme(profiles, globals, oldName, newName) {
        const newProfiles = JSON.parse(JSON.stringify(profiles ?? []));
        const newGlobals = Object.assign({}, globals ?? {});
        const changed = [];
        for (const profile of newProfiles) {
            if (profile.set?.["appearance.theme"] === oldName) {
                profile.set["appearance.theme"] = newName;
                changed.push(profile.name);
            }
        }
        if (newGlobals["appearance.theme"] === oldName) {
            newGlobals["appearance.theme"] = newName;
            changed.push("global");
        }
        return { profiles: newProfiles, globals: newGlobals, changed: changed };
    }

    // Whether `name` extending `base` would make a cycle: `base`'s chain reaches `name`
    function extendsCycle(name, base, readTheme) {
        if (name === base)
            return true;
        return chainFor(base, readTheme).chain.some(entry => entry.name === name);
    }

    // ---- Curves ----

    // The easing to fall back on for a curve that cannot be found
    readonly property string fallbackCurve: "OutQuad"

    // Whether `name` is one of Qt's easing curves ("OutQuad", "Linear", …)
    function isQtCurve(name) {
        return typeof name === "string" && /^[A-Z]/.test(name) && typeof Easing[name] === "number"
            && name !== "BezierSpline" && name !== "Bezier";
    }

    // A library curve's points in Qt's form (6 numbers per segment, ending at 1,1), or
    // null when they are not a curve: 4 numbers are one segment, its end added
    function curvePoints(points) {
        if (!Array.isArray(points) || points.some(value => typeof value !== "number" || !isFinite(value)))
            return null;
        const full = points.length === 4 ? points.concat([1, 1]) : points;
        if (full.length === 0 || full.length % 6 !== 0)
            return null;
        if (full[full.length - 2] !== 1 || full[full.length - 1] !== 1)
            return null;
        // Time only moves forward: every control point's x within 0–1
        for (let i = 0; i < full.length; i += 2) {
            if (full[i] < 0 || full[i] > 1)
                return null;
        }
        return full;
    }

    // The easing for a curve name, as a value an animation's `easing` takes: a Qt curve,
    // or a library curve as a Bézier spline. Unknown names and broken curves fall back.
    // Returns { easing, error } — error is "" when the name resolved.
    function curveEasing(name, library) {
        if (isQtCurve(name))
            return { easing: { type: Easing[name] }, error: "" };
        const points = library && Object.prototype.hasOwnProperty.call(library, name) ? curvePoints(library[name]) : null;
        if (points !== null)
            return { easing: { type: Easing.BezierSpline, bezierCurve: points }, error: "" };
        const why = library && Object.prototype.hasOwnProperty.call(library, name)
            ? "Curve \"" + name + "\" is not a valid curve"
            : "Curve \"" + name + "\" not found";
        return { easing: { type: Easing[fallbackCurve] }, error: why };
    }

    // Qt's curves as one cubic Bézier each, to start a library curve from: close
    // approximations (easings.net), not exact. Bounce and elastic curves have none.
    readonly property var qtCurveApproximations: ({
        Linear: [0, 0, 1, 1],
        InSine: [0.12, 0, 0.39, 0], OutSine: [0.61, 1, 0.88, 1], InOutSine: [0.37, 0, 0.63, 1],
        InQuad: [0.11, 0, 0.5, 0], OutQuad: [0.5, 1, 0.89, 1], InOutQuad: [0.45, 0, 0.55, 1],
        InCubic: [0.32, 0, 0.67, 0], OutCubic: [0.33, 1, 0.68, 1], InOutCubic: [0.65, 0, 0.35, 1],
        InQuart: [0.5, 0, 0.75, 0], OutQuart: [0.25, 1, 0.5, 1], InOutQuart: [0.76, 0, 0.24, 1],
        InQuint: [0.64, 0, 0.78, 0], OutQuint: [0.22, 1, 0.36, 1], InOutQuint: [0.83, 0, 0.17, 1],
        InExpo: [0.7, 0, 0.84, 0], OutExpo: [0.16, 1, 0.3, 1], InOutExpo: [0.87, 0, 0.13, 1],
        InCirc: [0.55, 0, 1, 0.45], OutCirc: [0, 0.55, 0.45, 1], InOutCirc: [0.85, 0, 0.15, 1],
        InBack: [0.36, 0, 0.66, -0.56], OutBack: [0.34, 1.56, 0.64, 1], InOutBack: [0.68, -0.6, 0.32, 1.6]
    })

    // Where the curve `name` is used: [{ theme, role }] over `themes` ({ name: parsed
    // theme file }), by each theme's own `curves` (what it inherits is counted where it
    // is set)
    function curveUsages(themes, name) {
        const usages = [];
        for (const theme of Object.keys(themes ?? {}).sort()) {
            const curves = themes[theme]?.curves ?? {};
            for (const role in curves) {
                if (curves[role] === name)
                    usages.push({ theme: theme, role: role });
            }
        }
        return usages;
    }

    // `themes` with every reference to the curve `oldName` pointing at `newName`: only
    // the themes that changed, { name: new theme }. Inputs are not modified.
    function renameCurveIn(themes, oldName, newName) {
        const changed = {};
        for (const theme in themes ?? {}) {
            const curves = themes[theme]?.curves;
            if (!curves || !Object.values(curves).includes(oldName))
                continue;
            const copy = JSON.parse(JSON.stringify(themes[theme]));
            for (const role in copy.curves) {
                if (copy.curves[role] === oldName)
                    copy.curves[role] = newName;
            }
            changed[theme] = copy;
        }
        return changed;
    }

    // Whether `name` may name a library curve: not empty, not a Qt curve's name
    function validCurveName(name) {
        return typeof name === "string" && name.trim() !== "" && name === name.trim()
            && !isQtCurve(name) && name !== "BezierSpline" && name !== "Bezier";
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
