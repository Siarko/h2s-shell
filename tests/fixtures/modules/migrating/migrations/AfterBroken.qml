import QtQuick

// Overlaps the broken one: skipped in the run it fails in, run at the next on its reset scope
QtObject {
    readonly property string summary: "The broken level is a text"

    function migrate(part, context) {
        for (const set of part.settings.profiles.map(profile => profile.set).concat([part.settings.globals]))
            if (typeof set["mod.migrating.broken.level"] === "number")
                set["mod.migrating.broken.level"] = String(set["mod.migrating.broken.level"]);
        return part;
    }
}
