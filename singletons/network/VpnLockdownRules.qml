pragma Singleton

import Quickshell

// Only through the VPN (a kill switch) — pure, tested in tests/NetworkTest.qml: what
// VpnLockdown blocks, the arguments it hands scripts/h2s-vpn-lockdown, how it reads the
// answer and what it does next.
Singleton {
    id: root

    // Whether the blocking should be on: always, or while a network it is set for is up
    function lockdownWanted(profiles, always, networks) {
        if (always)
            return true;
        return (profiles ?? []).some(profile => (networks ?? []).includes(profile.uuid) && profile.state === "activated");
    }

    // A server's host from "host:port", "[v6]:port", OpenVPN's "host:port:proto" or a bare host
    // — and from a URL (OpenConnect's gateway "https://vpn.example.com/group"), "host::udp"
    function serverHost(server) {
        let text = String(server ?? "").trim().replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").replace(/^[^@/]*@/, "");
        const bracket = /^\[([^\]]+)\]/.exec(text);
        if (bracket)
            return bracket[1];
        text = text.split("/")[0];
        return NetworkRules.isIpv6(text) ? text : text.split(":")[0];
    }

    // `getent ahosts` run per host, each line "host address": { host: [addresses] }
    function addressesByHost(lines) {
        const found = {};
        for (const line of lines ?? []) {
            const parts = String(line).trim().split(/\s+/);
            if (parts.length < 2 || !NetworkRules.isIpAddress(parts[1]))
                continue;
            found[parts[0]] = found[parts[0]] ?? [];
            if (!found[parts[0]].includes(parts[1]))
                found[parts[0]].push(parts[1]);
        }
        return found;
    }

    // The blocking's rules are built by scripts/h2s-vpn-lockdown (run as root), never here:
    // one place, and a polkit rule can let it run without a password because it takes no
    // rules from its caller. These are its arguments: ["on", lan "0"|"1", interfaces,
    // addresses] — lists comma-separated, "-" for none; `options` { vpnInterfaces [],
    // servers [addresses], allowLan }. Its `status` prints "on " and the same three.
    // Only what the script takes (it refuses anything else, and does nothing then): names
    // of letters, digits, "-" and "_"; IPv6 in lower case, without an IPv4 tail
    // An address the script takes: IPv4 without leading zeros, IPv6 without an IPv4 tail
    function isLockdownAddress(address) {
        return NetworkRules.isIpv4(address) && !/(^|\.)0\d/.test(address) || NetworkRules.isIpv6(address) && !String(address).includes(".");
    }

    // The most the script takes (it refuses more, and does nothing then)
    readonly property int lockdownMostInterfaces: 32
    readonly property int lockdownMostAddresses: 256

    function lockdownArguments(options) {
        const interfaces = Array.from(new Set((options?.vpnInterfaces ?? []).filter(name => /^[A-Za-z0-9_-]{1,15}$/.test(name))))
            .sort().slice(0, lockdownMostInterfaces);
        const addresses = Array.from(new Set((options?.servers ?? []).filter(isLockdownAddress)
            .map(address => address.toLowerCase()))).sort().slice(0, lockdownMostAddresses);
        return ["on", options?.allowLan ? "1" : "0", interfaces.length > 0 ? interfaces.join(",") : "-",
                addresses.length > 0 ? addresses.join(",") : "-"];
    }

    // What `status` prints for those arguments
    function lockdownStatusOf(argumentsList) {
        return "on " + argumentsList.slice(1).join(" ");
    }

    // `status`'s lines read: { status ("on …" or "off"), rules (the version of the script that
    // switched it on; 0 when it does not say: a version before 4) }
    function lockdownStatusReply(lines) {
        const status = String((lines ?? [])[0] ?? "off").trim() || "off";
        const rulesLine = (lines ?? []).map(line => String(line).trim()).find(line => /^rules [0-9]{1,6}$/.test(line));
        return { status: status, rules: status.startsWith("on") && rulesLine ? parseInt(rulesLine.slice(6)) : 0 };
    }

    // The rules loaded are the ones wanted: the same arguments, switched on by a script at
    // least as new as the shell's copy (older rules are switched on again by themselves only
    // when no password is needed: lockdownNextStep)
    function lockdownCurrent(status, rulesVersion, expectedStatus, scriptVersion) {
        return status === expectedStatus && (rulesVersion ?? 0) >= (scriptVersion ?? 0);
    }

    // What the blocking does next (VpnLockdown._follow), from `facts` { ready (the settings,
    // the script check, the boot and the VPNs' details read), busy (a switch or a lookup
    // running), passwordFree, askedAtStart, force ("Apply again"), wanted, nftFound, status,
    // rulesVersion, expectedStatus, scriptVersion, refused, hosts }:
    //   "wait"    not ready, or busy: asked again when that ends (nothing is used up)
    //   "ask"     the installed script's status first (once, after it became password-free)
    //   "no-nft"  wanted, but nftables is missing
    //   "keep"    nothing to switch (rules from an older script with the same arguments
    //             included while a password would be needed: never asked for by itself)
    //   "refused" refused before for these very rules: said, not asked again by itself
    //   "on", "off" switch; "idle" off and not wanted
    function lockdownNextStep(facts) {
        if (!facts.ready || facts.busy)
            return "wait";
        if (facts.passwordFree && !facts.askedAtStart && !facts.force)
            return "ask";
        if (facts.wanted) {
            if (!facts.nftFound)
                return "no-nft";
            if (!facts.force && lockdownCurrent(facts.status, facts.rulesVersion, facts.expectedStatus, facts.scriptVersion))
                return "keep";
            // The same arguments, loaded by an older script: switched on again only without a
            // password; with one they stay until the user asks ("Apply again", "Install again…")
            if (!facts.force && !facts.passwordFree && facts.status === facts.expectedStatus)
                return "keep";
            if (!facts.force && facts.refused === facts.expectedStatus + facts.hosts)
                return "refused";
            return "on";
        }
        if (String(facts.status ?? "").startsWith("on"))
            return !facts.force && facts.refused === "off" ? "keep" : "off";
        return "idle";
    }

    // The polkit rule letting `user` run the script at `programs` (quoted paths, or Nix
    // expressions) without a password — only in their own, active, local session
    function lockdownPolkitRule(user, programs) {
        const name = String(user ?? "").replace(/[^a-z0-9_-]/gi, "");
        return "// Written by h2s-shell (Settings > System > Network > VPN > Password-free blocking).\n"
            + "// Lets " + name + " run h2s-vpn-lockdown, which only switches the shell's VPN blocking, without a password.\n"
            + "polkit.addRule(function (action, subject) {\n"
            + "    if (action.id == \"org.freedesktop.policykit.exec\" && subject.user == \"" + name + "\" && subject.local && subject.active\n"
            + "        && (" + programs.map(program => "action.lookup(\"program\") == " + program).join("\n            || ") + "))\n"
            + "        return polkit.Result.YES;\n"
            + "});\n";
    }

    // A NixOS module for the same: the script as a package (its text inside, so the module
    // stands alone), nftables, and the polkit rule — to save as a file and import
    function lockdownNixosModule(script, user) {
        // Inside a Nix two-apostrophe string, two apostrophes are written as three, and a
        // dollar with a brace gets two apostrophes before it
        const twoQuotes = "''";
        const escaped = String(script ?? "").split(twoQuotes).join(twoQuotes + "'").split("${").join(twoQuotes + "${");
        const rule = lockdownPolkitRule(user, ['"/run/current-system/sw/bin/h2s-vpn-lockdown"', '"${lockdown}/bin/h2s-vpn-lockdown"']);
        const indent = (text, spaces) => text.split("\n").map(line => line === "" ? "" : spaces + line).join("\n");
        return "# h2s-shell: password-free \"Only through the VPN\" (Settings > System > Network > VPN).\n"
            + "# Save as /etc/nixos/h2s-vpn-lockdown.nix, add ./h2s-vpn-lockdown.nix to imports, rebuild.\n"
            + "{ pkgs, ... }:\n"
            + "let\n"
            + "  lockdown = pkgs.writeShellScriptBin \"h2s-vpn-lockdown\" " + twoQuotes + "\n"
            + indent(escaped, "    ") + (escaped.endsWith("\n") ? "" : "\n")
            + "  " + twoQuotes + ";\n"
            + "in {\n"
            + "  environment.systemPackages = [ lockdown pkgs.nftables ];\n"
            + "  security.polkit.extraConfig = " + twoQuotes + "\n"
            + indent(rule, "    ")
            + "  " + twoQuotes + ";\n"
            + "}\n";
    }
}
