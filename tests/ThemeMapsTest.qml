import QtQuick
import qs.singletons

// Theme's records keyed by a theme's name or a draft's keys (drafts, the other themes'
// values, errors and origins): a theme file or draft named "__proto__", "constructor" or
// "toString", or a draft with such a key, is a name like any other — never a property
// every object inherits, and never the record's prototype.
TestCase {
    suiteName: "ThemeMaps"
    // It sets Theme's drafts and resolves made-up themes into its records
    ownProcess: true

    function run() {
        const plainProto = Object.getPrototypeOf({});
        const savedDrafts = Theme.drafts;

        // --- drafts ---
        Theme.drafts = {};
        for (const name of ["constructor", "toString", "__proto__"]) {
            assert(!Theme.hasDraft(name), "no draft: \"" + name + "\" has none");
            assert(!Theme.hasDraft(name, "colors"), "no draft: \"" + name + "\" has none in a group");
        }
        assert(!Theme.hasDraft("x", "constructor"), "a draft's group is looked up among its own: \"constructor\"");
        Theme.drafts = JSON.parse('{ "__proto__": { "colors": { "accent": "#123456" } }, "x": { "colors": { "accent": "#1" } } }');
        assert(Theme.hasDraft("__proto__"), "a theme named \"__proto__\" with a draft has one");
        assert(Theme.hasDraft("__proto__", "colors"), "… in its group");
        assert(!Theme.hasDraft("x", "toString"), "a draft has no group \"toString\"");
        Theme.drafts = {};
        Theme._writeDraft("__proto__", { colors: { accent: "#123456" } });
        assert(Object.getPrototypeOf(Theme.drafts) === plainProto, "a draft written for \"__proto__\" keeps the record's prototype");
        assert(Theme.hasDraft("__proto__"), "… and is kept as that theme's");
        Theme._writeDraft("__proto__", {});
        assert(!Theme.hasDraft("__proto__"), "… and goes when emptied");

        // --- the other themes' values, errors and origins ---
        assertEqual(typeof Theme.valuesOf("toString"), "object", "valuesOf \"toString\" before it is resolved: values, not a function");
        assert(Array.isArray(Theme.errorsOf("constructor")), "errorsOf \"constructor\" before it is resolved: a list");
        assertEqual(typeof Theme.originsOf("constructor"), "object", "originsOf \"constructor\" before it is resolved: an object");
        Theme._resolveOther("__proto__");
        assert(Object.getPrototypeOf(Theme._otherValues) === plainProto, "resolving \"__proto__\" keeps the values' record prototype");
        assert(Object.prototype.hasOwnProperty.call(Theme._otherValues, "__proto__"), "… and records its values");
        assert(Object.prototype.hasOwnProperty.call(Theme._otherErrors, "__proto__"), "… its errors");
        assert(Object.prototype.hasOwnProperty.call(Theme._otherOrigins, "__proto__"), "… its origins");
        assert(Theme.errorsOf("__proto__").some(error => error.includes("not found")), "… which say it is not found");
        assertEqual(typeof Theme.valuesOf("__proto__").colors, "object", "valuesOf \"__proto__\": its values");

        // --- a draft's keys marked on the origins ---
        Theme.drafts = JSON.parse('{ "x": { "colors": { "__proto__": null, "constructor": "#111111", "accent": "#222222" } } }');
        const resolved = Theme._resolve("x", true);
        assert(Object.getPrototypeOf(resolved.origins.colors) === plainProto, "a draft's \"__proto__\" key keeps the origins' prototype");
        assertEqual(resolved.origins.colors.accent?.draft, true, "a draft's own token is marked as the draft's");
        assertEqual(resolved.values.colors.accent, "#222222", "and applies");

        Theme.drafts = savedDrafts;

        _pages();
    }

    // The settings pages: a theme file named "constructor" or "toString" that does not parse
    // is listed but has no parsed file — broken, not editable, no file to show
    property Item _stage: Item { width: 720; height: 1500 }
    function _pages() {
        const savedNames = Theme.themeNames;
        Theme.themeNames = savedNames.concat(["constructor", "toString"]);
        try {
            for (const page of ["ColorsSettings", "FontsSettings", "AnimationsSettings", "ShapeSettings", "BarShapeSettings",
                                "ShapeSections", "ThemesSettings"]) {
                const component = Qt.createComponent(Qt.resolvedUrl("../panels/settings/" + page + ".qml"));
                for (const name of ["constructor", "toString"]) {
                    const item = component.createObject(_stage, { themeName: name });
                    if (item === null) {
                        fail(page + " builds: " + component.errorString().trim());
                        break;
                    }
                    try {
                        if (page === "ThemesSettings") {
                            assert(item._broken, page + ": \"" + name + "\" without a parsed file is broken");
                            assertEqual(item._file, null, page + ": … and has no file");
                            assertEqual(item._extends, "default", page + ": … extends the default");
                        } else {
                            assert(!item._editable, page + ": \"" + name + "\" without a parsed file is not editable");
                        }
                    } finally {
                        item.destroy();
                    }
                }
            }
        } finally {
            Theme.themeNames = savedNames;
        }
    }
}
