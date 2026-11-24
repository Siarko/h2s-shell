pragma Singleton

import Quickshell
import QtQuick
import qs.distributions.nixos

// The shell's one reading of the system's NixOS configuration, its root step's writer,
// Create of the shell's file and the build with the shell's settings, for Settings → System →
// NixOS. Made on first use: only the page shown on NixOS uses it, and nothing here reads or
// runs before the page asks.
Singleton {
    id: root

    readonly property NixosConfiguration configuration: NixosConfiguration {}
    readonly property NixosApply writer: NixosApply {}
    readonly property NixosCreate creator: NixosCreate {
        writer: root.writer
    }
    readonly property NixosBuild builder: NixosBuild {}
}
