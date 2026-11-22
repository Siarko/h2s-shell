pragma Singleton

import Quickshell
import QtQuick

// Development mode — pure, checked by tests/DevRulesTest.qml. In development mode the shell
// reloads itself when one of its files changes (Quickshell.watchFiles); otherwise a file
// written in its folder (an update, a module install, an editor) leaves the running shell as
// it is, and only a restart loads it. Lockscreen applies it: it owns watchFiles, which is
// also off while the screen is locked.
Singleton {
    id: root

    // Whether the shell runs in development mode, from H2S_SHELL_DEV (`variable`: the
    // developer's, "1" on, "0" off) and H2S_SHELL_DEV_FLAG (`flag`: the launcher's, "1" when
    // it was started with --dev). The variable, when it says "1" or "0", decides over the
    // flag — `H2S_SHELL_DEV=0 launch.sh --dev` is off; anything else in it (unset, empty,
    // another word) leaves it to the flag. Off unless one of them says on.
    function devMode(variable, flag) {
        const said = String(variable ?? "").trim();
        if (said === "1")
            return true;
        if (said === "0")
            return false;
        return String(flag ?? "").trim() === "1";
    }

    // Quickshell.watchFiles for development mode `dev` and a screen that is `locked` or not:
    // never while locked (a reload then is the lock's recovery path, not one to take at every
    // file written while the owner is away), else only in development mode
    function watchFiles(dev, locked) {
        return dev === true && locked !== true;
    }
}
