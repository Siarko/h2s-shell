import QtQuick
import qs.singletons

// Writes outside its scope (a core setting, another store key): refused, its own scope reset.
// Its import of the shell's singletons is reported (the import check reads migration files)
QtObject {
    readonly property string summary: "Something it should not do"

    function migrate(part, context) {
        part.settings.globals["bar.height"] = 99;
        part.settings.globals["mod.other.x"] = 1;
        part.store.hostile = "changed";
        part.store.keep = 2;
        return part;
    }
}
