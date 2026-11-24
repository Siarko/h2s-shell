pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.io

// The PAM stacks as this machine has them, read only: polkit-1 and sudo (from the
// distribution's PAM directories: /etc/pam.d, then libpam's vendor directory where it has
// one), the lock's configs, pam_faillock's settings, and what the machine offers (NixOS or
// not, a fingerprint and a security key ready — the methods script's answers). Read by the shell's one
// PamStackReader, decided by PamStackRules; nothing is written, nothing asks for root.
// Read once when first used (so that the first prompt words itself by the stack) and again
// at each refresh() — Authentication refreshes when a prompt opens, Settings when its page
// is shown; the methods script (it asks fprintd) only when refresh(true) asks for it. Until
// the first reading every stack is unknown (null).
Singleton {
    id: root

    // PamStackReader.reading, or null before the first
    readonly property var reading: _reader.reading
    // PamStackRules.stack of polkit-1 and of sudo, or null before the first reading
    readonly property var polkit: reading?.services?.["polkit-1"] ?? null
    readonly property var sudo: reading?.services?.sudo ?? null
    // { method: stack } of the configs the lock uses
    readonly property var lock: reading?.lock ?? ({})
    // { nixos (true / false / null), moduleDirectories (the distribution's PAM module
    // directories), fingerprint, securityKey ("ready" / "absent" / "unknown"), u2f (what the
    // machine's pam_u2f settings let a key line do: { lock, rows, conf }, each
    // PamStackRules.u2fOptions' or null; absent before the first reading) }
    readonly property var facts: reading?.facts ?? ({ nixos: null, moduleDirectories: [], fingerprint: "unknown", securityKey: "unknown" })
    // { service: pam_faillock's settings or null }, the PAM folders read in order, and every
    // file read ({ path: { text } | { absent } | { unreadable } })
    readonly property var faillock: reading?.faillock ?? ({})
    readonly property var directories: reading?.directories ?? []
    readonly property var files: reading?.files ?? ({})

    function refresh(withMethods) {
        _reader.refresh(withMethods === true);
    }

    PamStackReader {
        id: _reader
    }

    Component.onCompleted: _reader.refresh(false)
}
