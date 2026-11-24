pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.helper

// The shell's helper program (helper/, h2s-helper): where scripts/launch.sh found it
// (H2S_SHELL_HELPER; empty when there is none) and whether it answers in the protocol this
// shell speaks. Read once at start; a shell started without the launcher has none. The
// features that use it check `available`.
Singleton {
    id: root

    // None in an isolated process (Isolation)
    readonly property string path: Isolation.active ? "" : (Quickshell.env("H2S_SHELL_HELPER") ?? "")
    // "missing" | "checking" | "ready" | "outdated" | "failed"
    readonly property string state: _read.state
    readonly property string version: _read.version
    readonly property bool available: state === "ready"

    property HelperVersionRead _read: HelperVersionRead {
        path: root.path
    }
}
