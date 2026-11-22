import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Reads whether the session is locked, as the compositor or logind says (no locker named):
// on Hyprland `hyprctl -j locked`, and logind's LockedHint for the session (a property read:
// no polkit, nothing changed), decided by LockIoRules.sleepLockState. One read at a time;
// start() while one runs is dropped (the running one answers). A read that fails is
// "unknown". gdbus waits at most a second for logind.
//
// `gdbus` is the one on PATH, or `toolDirectory`/gdbus (H2S_LOCK_TOOLS, the lock test bed's
// seam: its stand-in answers the hint, the real system bus being cut off there). `hyprctl`
// is the one on PATH (in the test bed: the bed's own Hyprland) unless a suite names another.
Scope {
    id: root

    // After each read, with its outcome (also in `outcome`)
    signal read(string outcome)

    property string toolDirectory: ""
    property string sessionPath: ""
    property bool onHyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "") !== ""
    property string hyprctl: "hyprctl"
    // The last read's outcome: "locked" | "unlocked" | "unknown"
    property string outcome: "unknown"
    // Reads answered so far
    property int reads: 0
    readonly property bool running: _query.running

    function start() {
        if (_query.running)
            return;
        _query.command = ["sh", "-c",
            "if [ \"$1\" = yes ] && answer=$(\"$2\" -j locked 2> /dev/null); then\n"
            + "    printf 'compositor %s\\n' \"$(printf '%s' \"$answer\" | tr '\\n' ' ')\"\n"
            + "fi\n"
            + "if [ -n \"$4\" ] && answer=$(\"$3\" call --system --timeout 1 --dest org.freedesktop.login1 --object-path \"$4\" "
            + "--method org.freedesktop.DBus.Properties.Get org.freedesktop.login1.Session LockedHint 2> /dev/null); then\n"
            + "    printf 'hint %s\\n' \"$(printf '%s' \"$answer\" | tr '\\n' ' ')\"\n"
            + "fi\n"
            + "exit 0",
            "sh", root.onHyprland ? "yes" : "no", root.hyprctl,
            root.toolDirectory !== "" ? root.toolDirectory + "/gdbus" : "gdbus", root.sessionPath];
        _query.running = true;
    }

    Process {
        id: _query
        property string _output: ""
        stdout: StdioCollector {
            onStreamFinished: _query._output = text
        }
        onRunningChanged: {
            if (running)
                return;
            const outcome = LockIoRules.sleepLockState(_output);
            _output = "";
            root.outcome = outcome;
            root.reads++;
            root.read(outcome);
        }
    }
}
