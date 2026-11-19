import QtQuick
import qs.api
import qs.singletons

// The names Api.theme offers (api/ThemeTokens.qml) are part of the module API: a module's
// own elements take every colour and type size from them. The lists below are that promise,
// so a token removed or renamed fails here, and one added fails until it is listed (a token
// added is a minor version of the API). Each colour and type size is the core theme's value
// of the same name.
TestCase {
    suiteName: "ApiThemeTokens"

    readonly property var colours: ["barBackground", "popupBackground", "surface", "surfaceHover", "surfaceHoverClear", "surfaceSunken", "overlay", "scrim", "accent", "accentHover", "accentTint", "accentDark", "onAccent", "accentSecondary", "accentSecondaryTint", "textPrimary", "textSecondary", "textMuted", "textDisabled", "selection", "selectedText", "divider", "outline", "fill", "fillSubtle", "track", "error", "errorTint", "errorMuted", "warning", "privileged", "success", "capsuleBorder", "popupBorder"]

    readonly property var typeSizes: ["fontSizeTiny", "fontSizeXSmall", "fontSizeSmall", "fontSizeBody", "fontSizeBodyLarge", "fontSizeMedium", "fontSizeSection", "fontSizeHeading", "fontSizeTitle", "fontSizeDisplay"]

    // Frozen copies of the theme's groups
    readonly property var groups: ["capsule", "popup", "row", "listItem", "button", "iconButton", "pill", "field", "checkbox", "tooltip", "progress", "border", "settings"]

    // Plain values that are neither a colour nor a type size
    readonly property var values: ["fontFamily", "fontScale", "reduceMotion", "animationSpeed"]

    readonly property var functions: ["scaled", "popupWidth", "duration", "curve"]

    // What the object offers a module: its properties and functions, without what every
    // QtObject has, the change signals and the private helpers
    function offered(tokens) {
        const properties = [];
        const callables = [];
        for (const name in tokens) {
            if (name === "objectName" || name.startsWith("_") || /Changed$/.test(name))
                continue;
            if (typeof tokens[name] === "function")
                callables.push(name);
            else
                properties.push(name);
        }
        return {
            properties: properties.sort(),
            functions: callables.sort()
        };
    }

    function sameNames(actual, expected, what) {
        const missing = expected.filter(name => !actual.includes(name));
        const unlisted = actual.filter(name => !expected.includes(name));
        assertEqual(missing.join(" "), "", what + ": none removed or renamed");
        assertEqual(unlisted.join(" "), "", what + ": none added without being listed here");
    }

    function run() {
        const tokens = Api.theme;
        const names = offered(tokens);
        const listed = colours.concat(typeSizes, groups, values);
        assertEqual(new Set(listed).size, listed.length, "no name is listed twice");
        assert(names.properties.length > 0 && names.functions.length > 0, "the names of Api.theme can be read");
        sameNames(names.properties, listed.slice().sort(), "the tokens");
        sameNames(names.functions, functions.slice().sort(), "the functions");

        for (const name of colours) {
            assert(Theme[name] !== undefined && Qt.colorEqual(tokens[name], Theme[name]), "colour " + name + " is the theme's");
            assert(String(tokens[name]).startsWith("#"), "colour " + name + " is a colour");
        }
        for (const name of typeSizes) {
            assert(typeof tokens[name] === "number" && tokens[name] > 0 && tokens[name] === Theme[name], "type size " + name + " is the theme's");
        }
        for (const name of values)
            assert(tokens[name] !== undefined && tokens[name] === Theme[name], name + " is the theme's");
        for (const name of groups) {
            const group = tokens[name];
            assert(group !== null && typeof group === "object" && Object.isFrozen(group), "group " + name + " is a frozen object");
            assertEqual(JSON.stringify(Object.keys(group).sort()), JSON.stringify(Object.keys(Theme[name] ?? {}).sort()), "group " + name + " has the theme's entries");
        }
    }
}
