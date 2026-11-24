import QtQuick
import qs.distributions
import qs.singletons

// Arch: /etc is the machine's own, so the shell writes its changes there (EtcFiles), each
// kept as a backup that Undo puts back
Integration {
    id: root

    // EtcFiles' `start` and `base`: the shell's runs as administrator and the system's places,
    // or a suite's stand-in under a scratch folder
    property var start: null
    property string base: ""

    distribution: "arch"
    table: ({
        "sleep.hibernateDelay": { mode: "apply", trial: false, undo: true, inForce: true },
        "network.connectivityUri": { mode: "apply", trial: false, undo: true, inForce: true }
    })
    files: EtcFiles {
        start: root.start
        base: root.base
    }
}
