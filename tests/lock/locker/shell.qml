import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Another program's session lock, for the lock bed (tests/lock/tests/foreign-lock.sh): a
// second Quickshell that takes the session lock at its start and prints "locker: locked"
// once the compositor confirms it. It follows the file named by LOCKER_CONTROL: "unlock"
// written there lets the lock go (prints "locker: unlocked"). Nothing of the shell under
// test.
ShellRoot {
    WlSessionLock {
        id: sessionLock

        WlSessionLockSurface {
            color: "black"
        }

        onSecureChanged: {
            if (secure)
                console.info("locker: locked");
        }
    }

    // Not a declarative `locked: true`: set once, then only as the control file says
    Component.onCompleted: sessionLock.locked = true

    FileView {
        path: Quickshell.env("LOCKER_CONTROL") ?? ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (text().trim() === "unlock" && sessionLock.secure) {
                sessionLock.locked = false;
                console.info("locker: unlocked");
            }
        }
    }
}
