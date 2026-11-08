pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Whether the device is folded into a tablet — a profile condition (Profiles,
// "input.tabletMode"). The compositor owns the input devices and reads the switch, so the
// shell learns it from Hyprland: a switch binding in hyprland.lua calls the IPC below
// (README, "Tablet mode"). That needs no access to the device, but Hyprland calls it only
// when the switch flips: the shell starts as a laptop and learns otherwise at the next
// flip, or from `ipc call tablet set true`. Kept in memory only — a passing state, not
// something to write to the config (each write shows "Settings saved" while the settings
// are open). Reading the switch device directly (a udev uaccess rule) was the
// alternative (docs/plans/touch.md, 2026-11-08).
Singleton {
    id: root

    property bool active: false

    function set(on: bool) {
        root.active = on;
    }

    // h2s-shell ipc call tablet set true       (Arch: launch.sh ipc call ...)
    // h2s-shell ipc call tablet toggle
    // h2s-shell ipc call tablet status
    IpcHandler {
        target: "tablet"

        function set(on: bool): string {
            root.set(on);
            return status();
        }

        function toggle(): string {
            root.set(!root.active);
            return status();
        }

        function status(): string {
            return root.active ? "tablet" : "laptop";
        }
    }
}
