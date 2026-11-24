import QtQuick
import qs.distributions
import qs.singletons

// NixOS: /etc is generated from the system's configuration, so nothing is written there
// unasked; a setting the system's configuration has an option for is the line to copy into
// it, the option named in its hint. NetworkManager's connectivity check address may still be
// written to its file when the user asks ("anyway": outside the system's configuration, which
// the page says), by EtcFiles, without Undo.
Integration {
    id: root

    // EtcFiles' `start` and `base`: the shell's runs as administrator and the system's places,
    // or a suite's stand-in under a scratch folder
    property var start: null
    property string base: ""

    distribution: "nixos"
    table: ({
        "sleep.hibernateDelay": { mode: "copy", inForce: true, option: HibernateRules.nixosOption,
                                  hint: "On NixOS it is the option " + HibernateRules.nixosOption + "." },
        "network.connectivityUri": { mode: "copy", inForce: true, anyway: true, option: ConnectivityRules.nixosOption,
                                     hint: "On NixOS it is the option " + ConnectivityRules.nixosOption + "." }
    })
    files: EtcFiles {
        start: root.start
        base: root.base
    }
}
