import QtQuick
import qs.distributions
import qs.singletons

// NixOS: /etc is generated from the system's configuration, so nothing is written there
// unasked; a setting the system's configuration has an option for is the line to copy into
// it, the option named in its hint. NetworkManager's connectivity check address may still be
// written to its file when the user asks ("anyway": outside the system's configuration, which
// the page says), by EtcFiles, without Undo. The PAM rules are the shell's module options
// to copy; NixOS's libpam finds only its own modules by bare name.
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
                                     hint: "On NixOS it is the option " + ConnectivityRules.nixosOption + "." },
        "pam.rules": { mode: "copy", option: "programs.h2s-shell.pam", hint: "On NixOS it is the option programs.h2s-shell.pam.",
                       facts: { bareModules: "libpam" },
                       texts: {
                           where: "the NixOS module",
                           pending: "The rows below take effect after nixos-rebuild switch.",
                           copyTitle: "Add to your NixOS configuration",
                           after: "After nixos-rebuild switch this page shows the new rules.",
                           systemRow: "NixOS's rules",
                           modulePath: "Needs the module's full path on NixOS."
                       } }
    })
    files: EtcFiles {
        start: root.start
        base: root.base
    }
}
