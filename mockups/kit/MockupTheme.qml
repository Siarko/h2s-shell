pragma Singleton

import Quickshell
import qs.singletons

// The theme the mockups are shown in, on a screen: Theme.preview, the settings window's
// preview (saved nowhere), set from H2S_MOCKUP_THEME by the entry, from the gallery's
// drop-down, and over IPC (`ipc call mockup theme <name>`). Shots never take one: the
// baselines are always drawn in the theme a private home has, the built-in one.
Singleton {
    // Set by the entry while shooting: no theme is taken then
    property bool shooting: false

    // The name of the theme shown: the previewed one, else the profile's
    readonly property string inForce: Theme.themeName

    // The themes there are: "default" and every theme file
    readonly property var names: ["default"].concat(Theme.themeNames.filter(name => name !== "default"))

    // Shows the mockups in `name` ("" only answers): the name in force, or why not
    function apply(name) {
        if (name === "")
            return inForce;
        if (shooting)
            return "not while shooting: the shots are always drawn in the built-in theme";
        if (!Theme.themeExists(name))
            return "no theme '" + name + "'; the themes: " + names.join(", ");
        Theme.preview = name;
        return name;
    }
}
