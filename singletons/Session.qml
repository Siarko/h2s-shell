pragma Singleton

import Quickshell

// Ending the session — shutdown, restart, logout — through the shell's scripts
// (scripts/*.sh, edited for the machine: the logout one depends on how Hyprland is
// configured). Started detached, so the popup closing, or the shell going, does not stop
// them half way.
Singleton {
    function _run(script) {
        Quickshell.execDetached(["bash", Quickshell.shellDir + "/scripts/" + script]);
    }

    function shutdown() {
        _run("shutdown.sh");
    }

    function restart() {
        _run("restart.sh");
    }

    function logout() {
        _run("logout.sh");
    }
}
