pragma Singleton

import Quickshell

// Helpers for reading nmcli's terse (-t) output. Pure functions.
Singleton {
    id: root

    // Splits one line of `nmcli -t` output into its fields.
    //
    // In terse mode nmcli escapes ':' and '\' inside values with a backslash, so a plain
    // split(":") cuts an SSID like "Home:5G" in two, and joining the pieces back leaves
    // "Home\:5G" — a name that matches no network. This splits on unescaped colons only
    // and removes the escapes.
    function splitTerse(line) {
        let fields = [];
        let current = "";
        for (let i = 0; i < line.length; i++) {
            const character = line[i];
            if (character === "\\" && i + 1 < line.length) {
                current += line[i + 1];
                i++;
            } else if (character === ":") {
                fields.push(current);
                current = "";
            } else {
                current += character;
            }
        }
        fields.push(current);
        return fields;
    }

    // `nmcli -t -f SSID,SIGNAL,SECURITY,IN-USE,FREQ device wifi list`: the networks with a
    // name, each { ssid, signal, security, inUse, band ("5G", "2.4G" or "") }, and the
    // signal of the one in use — the strongest, if it is listed more than once; -1 for none
    function wifiNetworks(lines) {
        const networks = [];
        let signalInUse = -1;
        for (const rawLine of lines) {
            const line = rawLine.trim();
            if (line === "")
                continue;
            const parts = splitTerse(line);
            if (parts.length < 5)
                continue;
            const ssid = parts[0];
            if (ssid === "")
                continue;
            const signal = parseInt(parts[1]) || 0;
            const inUse = parts[3].trim() === "*";
            const frequency = parseInt(parts[4].trim()) || 0;
            const band = frequency >= 3000 ? "5G" : (frequency > 0 ? "2.4G" : "");
            if (inUse && signal > signalInUse)
                signalInUse = signal;
            // nmcli lists each access point: one network on two bands, or a mesh, is
            // several lines with one SSID. The panel keeps a row's state by SSID, so a
            // network is one entry — the strongest access point's signal and security,
            // in use if any is, with every band it is on
            const known = networks.find(network => network.ssid === ssid);
            if (!known) {
                networks.push({ ssid: ssid, signal: signal, security: parts[2].trim(), inUse: inUse, bands: band ? [band] : [] });
                continue;
            }
            if (signal > known.signal) {
                known.signal = signal;
                known.security = parts[2].trim();
            }
            known.inUse = known.inUse || inUse;
            if (band && !known.bands.includes(band))
                known.bands.push(band);
        }
        for (const network of networks) {
            network.band = network.bands.sort().join(" · ");
            delete network.bands;
        }
        return { networks: networks, signalInUse: signalInUse };
    }

    // `nmcli -t -f <fields> connection show <id>…` or `device show`: "KEY:value" lines, one
    // block per connection or device. Only the first colon separates (an IPv6 address has
    // more); numbered keys ("IP4.ADDRESS[1]", "IP4.ADDRESS[2]") gather into a list under
    // "IP4.ADDRESS". The commands that read the output drop blank lines, so a block starts
    // again where `startKey` comes back. → [{ KEY: value or [values] }]
    function records(lines, startKey) {
        const blocks = [];
        let current = null;
        for (const rawLine of lines ?? []) {
            // Trimmed: the blank line between blocks comes glued to the next line's start
            // ("\nGENERAL.DEVICE:…"), which hid the key that starts a block
            const line = String(rawLine).trim();
            const colon = line.indexOf(":");
            if (colon <= 0)
                continue;
            const fullKey = line.slice(0, colon);
            const value = line.slice(colon + 1).trim();
            const numbered = /^(.*)\[\d+\]$/.exec(fullKey);
            const key = numbered ? numbered[1] : fullKey;
            if (current === null || key === startKey && key in current) {
                current = {};
                blocks.push(current);
            }
            if (numbered) {
                if (!Array.isArray(current[key]))
                    current[key] = [];
                if (value !== "")
                    current[key].push(value);
            } else {
                current[key] = value;
            }
        }
        return blocks;
    }

    // The kind of a connection type: "wifi", "ethernet", "vpn" (WireGuard, plugin VPNs),
    // "modem" (gsm, cdma), "bridge", "loopback", or the type itself
    function kindOf(type) {
        const kinds = {
            "802-11-wireless": "wifi", "wifi": "wifi",
            "802-3-ethernet": "ethernet", "ethernet": "ethernet",
            "wireguard": "vpn", "vpn": "vpn", "openconnect": "vpn",
            "gsm": "modem", "cdma": "modem",
            "bridge": "bridge", "loopback": "loopback"
        };
        return kinds[type] ?? type;
    }

    // `nmcli -t -f UUID,NAME,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY,TIMESTAMP,ACTIVE,SLAVE,
    // STATE connection show`: the saved profiles, by UUID — names are the user's and may
    // repeat, or differ from a network's SSID. `port` is the kind of bridge or bond the
    // profile is a port of ("bridge", "bond"…), "" for an ordinary one. `state` is
    // "activating", "activated", "deactivating" or "" (not active) — `active` is true for
    // the first three.
    function profiles(lines) {
        const list = [];
        for (const line of lines ?? []) {
            const parts = splitTerse(String(line));
            if (parts.length < 8 || parts[0] === "")
                continue;
            list.push({
                uuid: parts[0], name: parts[1], type: parts[2], kind: kindOf(parts[2]),
                device: parts[3], autoconnect: parts[4] === "yes",
                priority: parseInt(parts[5]) || 0, lastUsed: parseInt(parts[6]) || 0,
                active: parts[7] === "yes", port: parts[8] ?? "",
                state: parts[9] ?? (parts[7] === "yes" ? "activated" : "")
            });
        }
        return list;
    }

    // `nmcli -t -f connection.uuid,802-11-wireless.ssid,802-11-wireless-security.key-mgmt,
    // 802-11-wireless.hidden connection show uuid A uuid B…`: { uuid: { ssid, security,
    // hidden } } — `security` NetworkManager's key management ("wpa-psk", "sae",
    // "wpa-eap", "owe"…; "" for an open network)
    function wifiDetails(lines) {
        const details = {};
        for (const block of records(lines, "connection.uuid")) {
            if (block["connection.uuid"])
                details[block["connection.uuid"]] = {
                    ssid: block["802-11-wireless.ssid"] ?? "",
                    security: block["802-11-wireless-security.key-mgmt"] ?? "",
                    hidden: block["802-11-wireless.hidden"] === "yes",
                    mode: block["802-11-wireless.mode"] || "infrastructure",
                    band: block["802-11-wireless.band"] ?? ""
                };
        }
        return details;
    }

    // A profile's 802-11-wireless.band as a person names it ("" any)
    function bandName(band) {
        return band === "a" ? "5 GHz" : band === "bg" ? "2.4 GHz" : "";
    }

    // Key management as a person names it
    function securityName(keyManagement) {
        const names = {
            "": "Open", "none": "WEP", "ieee8021x": "WEP (802.1X)", "owe": "Open, encrypted (OWE)",
            "wpa-psk": "WPA2", "sae": "WPA3", "wpa-eap": "Enterprise", "wpa-eap-suite-b-192": "Enterprise (WPA3)"
        };
        return names[keyManagement] ?? keyManagement;
    }

    // `nmcli -t -f all device show`: each device with what the Overview shows. `state` is
    // NetworkManager's number (100 connected, 30 disconnected, 20 unavailable, 10
    // unmanaged), `stateText` its words; `speed` in Mb/s, 0 unknown.
    function devices(lines) {
        const list = [];
        for (const block of records(lines, "GENERAL.DEVICE")) {
            const stateMatch = /^(\d+)\s*\((.*)\)$/.exec(block["GENERAL.STATE"] ?? "");
            const list4 = key => Array.isArray(block[key]) ? block[key] : (block[key] ? [block[key]] : []);
            list.push({
                device: block["GENERAL.DEVICE"] ?? "",
                // The interface its IP runs on, when asked for and other than the device (a
                // modem's wwan0 under cdc-wdm0, PPPoE's ppp0); "" not known
                ipIface: block["GENERAL.IP-IFACE"] ?? "",
                type: block["GENERAL.TYPE"] ?? "",
                kind: kindOf(block["GENERAL.TYPE"] ?? ""),
                mac: block["GENERAL.HWADDR"] ?? "",
                mtu: parseInt(block["GENERAL.MTU"]) || 0,
                state: stateMatch ? parseInt(stateMatch[1]) : 0,
                stateText: stateMatch ? stateMatch[2] : (block["GENERAL.STATE"] ?? ""),
                connection: block["GENERAL.CONNECTION"] ?? "",
                vendor: block["GENERAL.VENDOR"] ?? "",
                product: block["GENERAL.PRODUCT"] ?? "",
                driver: block["GENERAL.DRIVER"] ?? "",
                speed: parseInt(block["CAPABILITIES.SPEED"]) || 0,
                // A wired device's cable: "on", "off", "" when not wired or not known
                carrier: block["WIRED-PROPERTIES.CARRIER"] ?? "",
                ipv4: list4("IP4.ADDRESS"),
                gateway4: block["IP4.GATEWAY"] ?? "",
                dns: list4("IP4.DNS").concat(list4("IP6.DNS")),
                domains: list4("IP4.DOMAIN"),
                ipv6: list4("IP6.ADDRESS"),
                gateway6: block["IP6.GATEWAY"] ?? ""
            });
        }
        return list;
    }

    // What went wrong, from nmcli's stderr: "password" (secrets missing or refused),
    // "auth" (not allowed), "missing" (no such connection or device), "notFound" (no
    // network of that name in range), "other"
    function errorKind(text) {
        const message = String(text ?? "");
        if (/secrets were required|802-11-wireless-security\.psk|psk: property is invalid|wrong password/i.test(message))
            return "password";
        if (/not authorized|insufficient privileges|permission denied|not allowed/i.test(message))
            return "auth";
        if (/no network with ssid/i.test(message))
            return "notFound";
        if (/unknown connection|no such connection|unknown device|not found/i.test(message))
            return "missing";
        return "other";
    }

    // nmcli's message without its "Error: " and trailing full stop, for a person to read
    function errorMessage(text) {
        return String(text ?? "").split("\n")[0].replace(/^Error:\s*/i, "").replace(/\.\s*$/, "").trim();
    }
}
