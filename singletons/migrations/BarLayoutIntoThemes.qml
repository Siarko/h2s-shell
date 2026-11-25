import QtQuick

// The bar's geometry moved from the profiles into themes (2.0.0), so the bar looks the same in
// every profile afterwards. Each profile that sets any `bar.layout.*` gets a theme file named
// after it (themes/<name>.json, a free name: an existing file is never written over) holding
// those values, extending the theme of the nearest profile before it that got one ("default"
// for the first), and picks it with `appearance.theme` — the same layering profiles had.
// Geometry pinned as global goes into every such theme (and gives the first profile one if none
// has its own). The `bar.layout` section of a config from before profiles counts as the first
// profile's, under what that profile sets itself — unless its values reached a profile already
// (the pre-profiles migration of older versions marked "bar.layout.barHeight" then).
//
// It runs after seeding, after 1.0.0-legacy-settings, on the document that one left: never on
// profiles read before another migration wrote them. Its id is its marker as older versions
// wrote it. The geometry tokens and the naming are frozen as they were when this moved onto the
// runner.
QtObject {
    readonly property string migrationId: "theme.barLayout"
    readonly property string since: "2.0.0"
    readonly property string summary: "The bar's geometry moved from the profiles into themes"
    // The profiles must exist (seeded before it runs)
    readonly property string phase: "afterSeed"
    readonly property string overwritesReason: "A profile that set its own bar geometry picks the theme made from it: that geometry applied over its theme before"
    // The geometry it moves, the theme it picks, the theme files it adds, and the old bar
    // section it only reads
    readonly property var scope: ["setting:bar.layout.*", "setting:appearance.theme", "file:themes/*.json", "read:raw:bar"]

    readonly property var _tokens: ["barHeight", "reservedSpace", "topOffset", "leftMargin", "rightMargin",
        "leftPadding", "rightPadding", "radiusTopLeft", "radiusTopRight", "radiusBottomLeft", "radiusBottomRight",
        "cellVerticalMargin", "widgetSpacing", "borderWidth"]
    // Written by the pre-profiles migration of older versions once the old section's geometry
    // was in a profile
    readonly property string _legacyCopied: "bar.layout.barHeight"

    // The markers older versions wrote per geometry key: read only, to tell whether the old
    // section's geometry reached a profile; never written
    function ownsRecord(entry) {
        return typeof entry === "string" && entry.startsWith("bar.layout.");
    }

    function _themePath(name) {
        return "themes/" + name + ".json";
    }

    // `wanted`, or the first of "<wanted> 2", "<wanted> 3", … not taken
    function _freeName(wanted, taken) {
        const base = wanted.replace(/[\/]/g, "-").trim() || "Theme";
        let name = base;
        for (let i = 2; taken(name); i++)
            name = base + " " + i;
        return name;
    }

    function migrate(document, context) {
        const files = document.files;
        const legacyLayout = document.records.includes(_legacyCopied) ? undefined : document.raw.bar?.layout;
        const take = set => {
            const values = {};
            for (const token of _tokens) {
                if (set && ("bar.layout." + token) in set) {
                    values[token] = set["bar.layout." + token];
                    delete set["bar.layout." + token];
                }
            }
            return values;
        };
        const pinned = take(document.globals);
        const made = [];
        const taken = name => Object.prototype.hasOwnProperty.call(files, _themePath(name)) || made.includes(name);
        let parent = "default";
        document.profiles.forEach((profile, index) => {
            profile.set = profile.set ?? {};
            const own = take(profile.set);
            if (index === 0 && legacyLayout) {
                for (const token of _tokens) {
                    if (!(token in own) && legacyLayout[token] !== undefined)
                        own[token] = legacyLayout[token];
                }
            }
            if (Object.keys(own).length === 0 && !(index === 0 && Object.keys(pinned).length > 0))
                return;
            const name = _freeName(profile.name ?? "Theme", taken);
            made.push(name);
            // A name from the user's profile: "__proto__" stays a key
            Object.defineProperty(files, _themePath(name), { value: { extends: parent, bar: Object.assign(own, pinned) },
                                                             enumerable: true, writable: true, configurable: true });
            profile.set["appearance.theme"] = name;
            parent = name;
        });
        return document;
    }
}
