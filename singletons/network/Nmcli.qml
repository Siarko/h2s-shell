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

    // `nmcli -t -f name,type connection show`: the names of the saved Wi-Fi profiles
    function savedWifi(lines) {
        const names = [];
        for (const line of lines) {
            const parts = splitTerse(line);
            if (parts.length >= 2 && parts[1].trim() === "802-11-wireless")
                names.push(parts[0]);
        }
        return names;
    }
}
