import QtQuick
import qs.distributions
import qs.singletons

// NixOS: /etc is generated from the system's configuration, so nothing is written there; a
// setting the shell's NixOS module has an option for is the line to copy into the
// configuration
Integration {
    distribution: "nixos"
    table: ({
        "sleep.hibernateDelay": { mode: "copy", option: HibernateRules.nixosOption }
    })
}
