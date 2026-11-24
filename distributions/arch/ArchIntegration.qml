import QtQuick
import qs.distributions
import qs.singletons

// Arch: /etc is the machine's own, so the shell writes its changes there (EtcFiles), each
// kept as a backup that Undo puts back. The PAM rules are tried first (a PAM conversation
// as the user against the new file) and written one service per run by PamApply, through
// EtcFiles' run, their backups in /var/lib/h2s-shell/pam-backup.
Integration {
    id: root

    // EtcFiles' `start` and `base`: the shell's runs as administrator and the system's places,
    // or a suite's stand-in under a scratch folder
    property var start: null
    property string base: ""

    distribution: "arch"
    table: ({
        "sleep.hibernateDelay": { mode: "apply", trial: false, undo: true, inForce: true },
        "network.connectivityUri": { mode: "apply", trial: false, undo: true, inForce: true },
        "pam.rules": { mode: "apply", trial: true, undo: true, inForce: false }
    })
    files: EtcFiles {
        start: root.start
        base: root.base
    }
    writers: ({ "pam.rules": _pam })

    property PamApply _pam: PamApply {
        start: root.start
        paths: root.base === "" ? PamApplyRules.livePaths
            : { system: root.base + PamApplyRules.livePaths.system, vendor: root.base + PamApplyRules.livePaths.vendor,
                backups: root.base + PamApplyRules.livePaths.backups }
    }
}
