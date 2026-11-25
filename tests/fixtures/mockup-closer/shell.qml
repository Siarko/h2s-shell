import QtQuick
import Quickshell
import Quickshell.Wayland

// tests/run-mockups-selftest.sh's stand-in for the user closing a window: asks the compositor
// (its foreign toplevel management) to close every toplevel titled H2S_CLOSE_TITLE, as a
// window's close button does. Prints CLOSER-CLOSED <count> and exits 0 once one is found,
// CLOSER-NONE and exits 1 when none appears within ten seconds. Run only in the self-test's
// private headless compositor.
ShellRoot {
    id: root

    readonly property string wanted: Quickshell.env("H2S_CLOSE_TITLE") ?? ""
    property int tries: 0

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            const found = ToplevelManager.toplevels.values.filter(toplevel => toplevel.title === root.wanted);
            if (found.length > 0) {
                found.forEach(toplevel => toplevel.close());
                console.info("CLOSER-CLOSED " + found.length);
                stop();
                Qt.callLater(() => Qt.exit(0));
            } else if (++root.tries >= 200) {
                console.info("CLOSER-NONE");
                stop();
                Qt.callLater(() => Qt.exit(1));
            }
        }
    }
}
