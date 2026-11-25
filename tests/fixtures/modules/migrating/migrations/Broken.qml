import QtQuick

// Fails: its scope (broken.*) is reset to defaults
QtObject {
    readonly property string summary: "Broken settings in a new shape"

    function migrate(part, context) {
        throw new Error("the broken migration broke");
    }
}
