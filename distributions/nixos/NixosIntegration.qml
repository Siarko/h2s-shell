import QtQuick
import qs.distributions
import qs.singletons

// NixOS: /etc is generated from the system's configuration, so nothing is written there
// unasked; a setting the system's configuration has an option for is the line to copy into
// it, the option named in its hint — or, for the hibernation delay while the configuration is
// connected, kept in the shell's file there and applied by rebuilding NixOS (NixosDeclare). NetworkManager's connectivity check address may still be
// written to its file when the user asks ("anyway": outside the system's configuration, which
// the page says), by EtcFiles, without Undo. The PAM rules are the shell's module options
// to copy; NixOS's libpam finds only its own modules by bare name. The VPN blocking's script
// and polkit rule are a module to save and import.
Integration {
    id: root

    // EtcFiles' `start` (and Integration's `base`): the shell's runs as administrator and the
    // system's places, or a suite's stand-in under a scratch folder
    property var start: null

    // The system's NixOS configuration as read (NixosConfiguration) and the rebuild run
    // (NixosRebuild): the hibernation delay is kept in the shell's file while the
    // configuration is connected; null (a suite's, or before the distribution is known): copied
    property var configuration: null
    property var rebuild: null
    readonly property bool connected: configuration?.state === "connected"

    distribution: "nixos"
    table: ({
        "sleep.hibernateDelay": root.connected
            ? { mode: "declare", undo: true, inForce: true, option: HibernateRules.nixosOption,
                hint: "Kept in the shell's file in your NixOS configuration." }
            : { mode: "copy", inForce: true, option: HibernateRules.nixosOption,
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
                       } },
        "network.vpnLockdown": { mode: "copy", option: "/etc/nixos/h2s-vpn-lockdown.nix",
                                 hint: "Save this module as /etc/nixos/h2s-vpn-lockdown.nix, add it to imports and rebuild; it holds the script, nftables and the polkit rule. To remove it, take it out of imports and rebuild.",
                                 facts: { scriptPath: "/run/current-system/sw/bin/h2s-vpn-lockdown", rulePath: "",
                                          ruleDirectory: "/etc/static/polkit-1/rules.d", nftPaths: ["/run/current-system/sw/bin/nft"] } }
    })
    files: EtcFiles {
        start: root.start
        base: root.base
    }
    writers: ({ "sleep.hibernateDelay": _delay })

    property NixosDeclare _delay: NixosDeclare {
        kind: "sleep.hibernateDelay"
        configuration: root.configuration
        rebuild: root.rebuild
    }
}
