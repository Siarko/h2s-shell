pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Decides which DRM card the GPU sources read from.
//
// A machine with an APU plus a dedicated card exposes several amdgpu nodes, and
// card0 is typically the integrated one. Its "VRAM" is a small carve-out of
// system RAM, so reading card0 reports a few MB against a ~2 GB budget instead
// of the real card's usage.
//
// Preference order: a card that reports a VRAM vendor (only populated for real
// dedicated memory chips, never for an APU carve-out), largest first; failing
// that, simply the card with the most VRAM.
Singleton {
    id: root

    // Sysfs device directory of the chosen card, e.g. /sys/class/drm/card1/device.
    // Empty until detection finishes; GPU sources stay idle while it is.
    property string path: ""

    // False once detection ran and found no amdgpu node to read.
    property bool available: true

    Component.onCompleted: _detect.running = true

    Process {
        id: _detect
        command: ["sh", "-c",
            "best=''; bestsize=0; vbest=''; vbestsize=0;" +
            "for d in /sys/class/drm/card[0-9]*/device; do" +
            " [ -r \"$d/mem_info_vram_total\" ] || continue;" +
            " size=$(cat \"$d/mem_info_vram_total\" 2>/dev/null);" +
            " case \"$size\" in ''|*[!0-9]*) continue;; esac;" +
            " if [ \"$size\" -gt \"$bestsize\" ]; then bestsize=$size; best=$d; fi;" +
            " if [ -r \"$d/mem_info_vram_vendor\" ] && [ \"$size\" -gt \"$vbestsize\" ];" +
            " then vbestsize=$size; vbest=$d; fi;" +
            "done;" +
            "if [ -n \"$vbest\" ]; then printf '%s\\n' \"$vbest\";" +
            "elif [ -n \"$best\" ]; then printf '%s\\n' \"$best\"; fi"]

        property string _buf: ""

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { _detect._buf += data }
        }

        onRunningChanged: {
            if (!running) {
                var found = _detect._buf.trim()
                if (found !== "")
                    root.path = found
                else
                    root.available = false
                _detect._buf = ""
            }
        }
    }
}
