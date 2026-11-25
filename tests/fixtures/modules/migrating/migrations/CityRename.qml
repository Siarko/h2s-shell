import QtQuick

// The old "town" becomes "city", in every profile and the pinned globals; a "city" already
// set is the user's and stays
QtObject {
    readonly property string summary: "Town is now City"

    function migrate(part, context) {
        for (const set of part.settings.profiles.map(profile => profile.set).concat([part.settings.globals])) {
            if (set["mod.migrating.town"] === undefined)
                continue;
            if (set["mod.migrating.city"] === undefined)
                set["mod.migrating.city"] = set["mod.migrating.town"];
            delete set["mod.migrating.town"];
        }
        return part;
    }
}
