pragma Singleton

import Quickshell
import qs.singletons

// Network settings' rules — pure, tested in tests/NetworkTest.qml: what is a valid
// hostname or address, and NetworkManager's global DNS in and out of its D-Bus form.
Singleton {
    id: root

    // RFC 1123: labels of letters, digits and hyphens, not starting or ending with a hyphen,
    // at most 63 long, at most 253 in all
    function isHostname(text: string): bool {
        const name = String(text ?? "");
        if (name.length === 0 || name.length > 253)
            return false;
        return name.split(".").every(label => /^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(label));
    }

    // Addresses are AddressRules' (one reader for the shell and the modules' Api.address):
    // no leading zeros in IPv4, no zone in IPv6
    function isIpv4(text: string): bool {
        return AddressRules.isIpv4(String(text ?? ""));
    }

    function isIpv6(text: string): bool {
        return AddressRules.isIpv6(String(text ?? ""));
    }

    function isIpAddress(text: string): bool {
        return AddressRules.isIp(String(text ?? ""));
    }

    // Addresses typed in one field, split by commas, spaces or semicolons → { list, bad }:
    // the valid ones in order without repeats, and the ones that are not addresses
    function parseServers(text: string): var {
        const list = [];
        const bad = [];
        for (const item of String(text ?? "").split(/[\s,;]+/)) {
            if (item === "")
                continue;
            if (!isIpAddress(item))
                bad.push(item);
            else if (!list.includes(item))
                list.push(item);
        }
        return { list: list, bad: bad };
    }

    // `busctl --json=short get-property … GlobalDnsConfiguration`'s data → { servers,
    // searches }: the servers for every domain ("*"), and the search domains
    function globalDnsFrom(data): var {
        const servers = data?.domains?.data?.["*"]?.data?.servers?.data ?? [];
        const searches = data?.searches?.data ?? [];
        return { servers: servers.slice(), searches: searches.slice() };
    }

    // busctl's arguments setting the global DNS to `servers` for every domain (none:
    // cleared, each connection's DNS applies again)
    function globalDnsArguments(servers): var {
        const list = servers ?? [];
        if (list.length === 0)
            return ["a{sv}", "0"];
        return ["a{sv}", "1", "domains", "a{sv}", "1", "*", "a{sv}", "1", "servers", "as", String(list.length)].concat(list);
    }

    // An address for NetworkManager's connectivity check: http(s), a host, nothing that
    // could break out of its line in the configuration file (spaces, quotes, newlines)
    function isConnectivityUri(text: string): bool {
        return /^https?:\/\/[A-Za-z0-9.-]+(:\d+)?(\/[^\s"'\\]*)?$/.test(String(text ?? ""));
    }

    // Whether Enter in a network's password field in the network popup connects, as the
    // Connect button beside it would: that button is there (the network not in use) and
    // says Connect (the network not connecting now — it is Cancel then), and a password is
    // typed (Enter on an empty field does nothing)
    function wifiEnterConnects(password: string, inUse: bool, connectingThis: bool): bool {
        return String(password ?? "") !== "" && !inUse && !connectingThis;
    }

    // A Wi-Fi password NetworkManager takes for `security` (key management): WPA2/WPA3
    // personal 8–63 characters (or 64 hexadecimal digits, the key itself); others are not
    // checked here
    function isWifiPassword(text: string, security: string): bool {
        const password = String(text ?? "");
        if (security !== "wpa-psk" && security !== "sae")
            return password.length > 0;
        return (password.length >= 8 && password.length <= 63) || /^[0-9A-Fa-f]{64}$/.test(password);
    }

    // The same for a network in range, its security as the scan names it ("WPA2",
    // "WPA1 WPA2", "WPA3", "WPA2 802.1X", "WEP"): WPA personal is checked as above;
    // enterprise (802.1X) and WEP are not
    function wifiScanPassword(text: string, scanSecurity: string): bool {
        const words = String(scanSecurity ?? "").split(/\s+/);
        const personal = words.some(word => /^WPA\d?$/.test(word)) && !words.includes("802.1X");
        return isWifiPassword(text, personal ? "wpa-psk" : "");
    }

    // A speed in Mb/s as a person reads it: "2.5 Gb/s", "866 Mb/s"; "" when unknown
    function speedText(megabits: real): string {
        if (!(megabits > 0))
            return "";
        if (megabits >= 1000)
            return (Math.round(megabits / 100) / 10) + " Gb/s";
        return Math.round(megabits) + " Mb/s";
    }

    // ── The connection editor ── (System → Network → a profile → Edit connection)

    // The fields the editor reads, for `nmcli -t -f … connection show uuid X`; nmcli leaves
    // out the fields of other kinds of connection, so one list does for every profile
    readonly property var editorFields: [
        "connection.id", "connection.autoconnect", "connection.autoconnect-priority", "connection.metered",
        "connection.permissions",
        "ipv4.method", "ipv4.addresses", "ipv4.gateway", "ipv4.dns", "ipv4.dns-search", "ipv4.ignore-auto-dns",
        "ipv4.never-default", "ipv4.route-metric", "ipv4.may-fail", "ipv4.shared-dhcp-range", "ipv4.shared-dhcp-lease-time",
        "ipv6.method", "ipv6.addresses", "ipv6.gateway", "ipv6.dns", "ipv6.ignore-auto-dns", "ipv6.ip6-privacy",
        "ipv6.never-default", "ipv6.route-metric", "ipv6.may-fail",
        "802-11-wireless.ssid", "802-11-wireless.band", "802-11-wireless.cloned-mac-address", "802-11-wireless.hidden",
        "802-11-wireless.mode", "802-11-wireless-security.key-mgmt",
        "connection.interface-name", "wireguard.listen-port", "wireguard.mtu",
        "802-3-ethernet.cloned-mac-address", "802-3-ethernet.mtu"
    ]

    function _list(text) {
        return String(text ?? "").split(/[,\s]+/).filter(item => item !== "");
    }

    // One profile's block (Nmcli.records) → what the editor edits: { name, autoconnect,
    // priority, metered ("auto" | "yes" | "no"), onlyMe, ipv4: { method, addresses [CIDR],
    // gateway, dns [], dnsSearch [], ignoreAutoDns, neverDefault, routeMetric (-1 automatic),
    // mayFail, rangeStart, rangeEnd, leaseTime (seconds, 0 default) — the last three for the
    // "shared" method, this computer as the router }, ipv6: { … no range, privacy ("-1"
    // default, "0" off, "1" prefer public, "2" prefer temporary) }, wifi: { ssid, band ("" | "a" | "bg"),
    // mode ("infrastructure", or "ap": a hotspot), security (key-mgmt, "" open), password
    // ("" here: a hotspot's is read apart, NetworkProfiles.readSettings),
    // mac, hidden } or null, ethernet: { mac, mtu (0 automatic) } or null }
    function settingsFrom(block) {
        const value = key => block?.[key] ?? "";
        const metered = value("connection.metered");
        const routing = family => ({
            neverDefault: value(family + ".never-default") === "yes",
            routeMetric: /^-?\d+$/.test(value(family + ".route-metric")) ? parseInt(value(family + ".route-metric")) : -1,
            mayFail: value(family + ".may-fail") !== "no"
        });
        const range = value("ipv4.shared-dhcp-range").split(",");
        return {
            name: value("connection.id"),
            autoconnect: value("connection.autoconnect") !== "no",
            priority: parseInt(value("connection.autoconnect-priority")) || 0,
            metered: metered === "yes" ? "yes" : metered === "no" ? "no" : "auto",
            onlyMe: value("connection.permissions") !== "",
            ipv4: Object.assign({
                method: value("ipv4.method") || "auto", addresses: _list(value("ipv4.addresses")),
                gateway: value("ipv4.gateway"), dns: _list(value("ipv4.dns")),
                dnsSearch: _list(value("ipv4.dns-search")), ignoreAutoDns: value("ipv4.ignore-auto-dns") === "yes",
                rangeStart: range.length === 2 ? range[0].trim() : "", rangeEnd: range.length === 2 ? range[1].trim() : "",
                leaseTime: parseInt(value("ipv4.shared-dhcp-lease-time")) || 0
            }, routing("ipv4")),
            ipv6: Object.assign({
                method: value("ipv6.method") || "auto", addresses: _list(value("ipv6.addresses")),
                gateway: value("ipv6.gateway"), dns: _list(value("ipv6.dns")),
                ignoreAutoDns: value("ipv6.ignore-auto-dns") === "yes",
                privacy: (/^-?\d/.exec(value("ipv6.ip6-privacy")) ? String(parseInt(value("ipv6.ip6-privacy"))) : "-1")
            }, routing("ipv6")),
            wifi: "802-11-wireless.ssid" in (block ?? {}) ? {
                ssid: value("802-11-wireless.ssid"), band: value("802-11-wireless.band"),
                mac: value("802-11-wireless.cloned-mac-address"), hidden: value("802-11-wireless.hidden") === "yes",
                mode: value("802-11-wireless.mode") || "infrastructure",
                security: value("802-11-wireless-security.key-mgmt"), password: ""
            } : null,
            // The private key and peers are secrets, read apart (NetworkProfiles.readSettings)
            wireguard: "wireguard.listen-port" in (block ?? {}) ? {
                iface: value("connection.interface-name"), privateKey: "",
                listenPort: parseInt(value("wireguard.listen-port")) || 0, mtu: parseInt(value("wireguard.mtu")) || 0,
                peers: []
            } : null,
            ethernet: "802-3-ethernet.mtu" in (block ?? {}) ? {
                mac: value("802-3-ethernet.cloned-mac-address"),
                mtu: parseInt(value("802-3-ethernet.mtu")) || 0
            } : null
        };
    }

    // "192.168.1.5/24" (prefix optional: a host)
    function isCidr4(text) {
        return AddressRules.parseCidr(String(text ?? ""))?.family === 4;
    }

    function isCidr6(text) {
        return AddressRules.parseCidr(String(text ?? ""))?.family === 6;
    }

    function _ipv4Number(address) {
        return address.split(".").reduce((number, part) => number * 256 + Number(part), 0);
    }

    // Whether an IPv4 address lies in one of `cidrs`' networks
    function inSubnet4(address, cidrs) {
        const text = String(address ?? "");
        if (!AddressRules.isIpv4(text))
            return false;
        return (cidrs ?? []).some(cidr => AddressRules.contains(String(cidr), text));
    }

    // A MAC address, or one of NetworkManager's words for it ("" its default)
    function isMacSetting(text) {
        const value = String(text ?? "");
        return value === "" || ["preserve", "permanent", "random", "stable"].includes(value)
            || /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(value);
    }

    // What is wrong in the edited settings: { field: message }, fields as nmcli names them;
    // empty when all is well
    function editorErrors(settings) {
        const errors = {};
        if (String(settings.name ?? "").trim() === "")
            errors["connection.id"] = "A name is needed.";
        const ip = (family, isCidr, isAddress) => {
            const config = settings[family];
            if (config.method === "manual" && config.addresses.length === 0)
                errors[family + ".addresses"] = "Manual needs at least one address.";
            const bad = config.addresses.filter(address => !isCidr(address));
            if (bad.length > 0)
                errors[family + ".addresses"] = "Not an address with its prefix: " + bad.join(", ");
            const badDns = config.dns.filter(server => !isAddress(server));
            if (badDns.length > 0)
                errors[family + ".dns"] = "Not an " + (family === "ipv4" ? "IPv4" : "IPv6") + " address: " + badDns.join(", ");
        };
        ip("ipv4", isCidr4, isIpv4);
        ip("ipv6", isCidr6, isIpv6);
        for (const family of ["ipv4", "ipv6"]) {
            const metric = settings[family].routeMetric;
            if (metric !== -1 && !(Number.isInteger(metric) && metric >= 0 && metric <= 4294967295))
                errors[family + ".route-metric"] = "A whole number from 0, or automatic.";
        }
        if (settings.ipv4.method === "shared") {
            const addresses = settings.ipv4.addresses;
            if (addresses.length > 1)
                errors["ipv4.addresses"] = "One address: this computer's on the shared network.";
            else if (addresses.length === 1 && !errors["ipv4.addresses"]
                     && !(String(addresses[0]).includes("/") && Number(String(addresses[0]).split("/")[1]) <= 30))
                errors["ipv4.addresses"] = "With a prefix of 30 or less, as 10.42.0.1/24: it sets the network handed out.";
            const start = settings.ipv4.rangeStart, end = settings.ipv4.rangeEnd;
            if ((start === "") !== (end === ""))
                errors["ipv4.shared-dhcp-range"] = "Both ends of the range, or neither.";
            else if (start !== "" && (!isIpv4(start) || !isIpv4(end)))
                errors["ipv4.shared-dhcp-range"] = "Two IPv4 addresses.";
            else if (start !== "" && _ipv4Number(start) > _ipv4Number(end))
                errors["ipv4.shared-dhcp-range"] = "The first address comes after the last.";
            else if (start !== "" && addresses.length === 0)
                errors["ipv4.shared-dhcp-range"] = "Set this computer's address too: the range must lie in its network.";
            else if (start !== "" && !errors["ipv4.addresses"] && !(inSubnet4(start, addresses) && inSubnet4(end, addresses)))
                errors["ipv4.shared-dhcp-range"] = "Outside this computer's network (" + addresses[0] + ").";
            const lease = settings.ipv4.leaseTime;
            if (lease !== 0 && !(Number.isInteger(lease) && lease >= 120 && lease <= 31536000))
                errors["ipv4.shared-dhcp-lease-time"] = "From 2 minutes to a year, or the default.";
        }
        const gateway4 = settings.ipv4.gateway;
        if (gateway4 !== "" && !isIpv4(gateway4))
            errors["ipv4.gateway"] = "Not an IPv4 address.";
        else if (gateway4 !== "" && settings.ipv4.method === "manual" && !errors["ipv4.addresses"] && !inSubnet4(gateway4, settings.ipv4.addresses))
            errors["ipv4.gateway"] = "Outside the addresses' network.";
        if (settings.ipv6.gateway !== "" && !isIpv6(settings.ipv6.gateway))
            errors["ipv6.gateway"] = "Not an IPv6 address.";
        if (settings.wifi) {
            if (settings.wifi.ssid === "" || settings.wifi.ssid.length > 32)
                errors["802-11-wireless.ssid"] = "1 to 32 characters.";
            if (!isMacSetting(settings.wifi.mac))
                errors["802-11-wireless.cloned-mac-address"] = "A MAC address like 12:34:56:78:9A:BC.";
            // null: the saved one could not be read — kept as it is, so nothing to check
            if (isHotspot(settings) && ["wpa-psk", "sae"].includes(settings.wifi.security) && settings.wifi.password !== null
                    && !isWifiPassword(settings.wifi.password, settings.wifi.security))
                errors["802-11-wireless-security.psk"] = "8 to 63 characters.";
        }
        if (settings.ethernet) {
            if (!isMacSetting(settings.ethernet.mac))
                errors["802-3-ethernet.cloned-mac-address"] = "A MAC address like 12:34:56:78:9A:BC.";
            const mtu = settings.ethernet.mtu;
            if (mtu !== 0 && (mtu < 68 || mtu > 9000))
                errors["802-3-ethernet.mtu"] = "68 to 9000, or automatic.";
        }
        if (settings.wireguard)
            Object.assign(errors, _wireguardErrors(settings.wireguard));
        return errors;
    }

    // What changed, as `nmcli connection modify` takes it: [[property, value], …] — lists
    // joined with commas, yes/no, "" to clear. Addresses and a gateway only go with the
    // manual method — IPv4 addresses with "shared" too, this computer's own there: changing
    // to another method clears them (NetworkManager refuses them with some methods); so does leaving
    // "shared" its range and lease time.
    // `user` names who "only me" is.
    function editorChanges(original, edited, user) {
        const changes = [];
        const put = (property, before, after) => {
            if (String(before) !== String(after))
                changes.push([property, String(after)]);
        };
        const yesNo = flag => flag ? "yes" : "no";
        put("connection.id", original.name, edited.name.trim());
        put("connection.autoconnect", yesNo(original.autoconnect), yesNo(edited.autoconnect));
        put("connection.autoconnect-priority", original.priority, edited.priority);
        const meter = value => value === "auto" ? "unknown" : value;
        put("connection.metered", meter(original.metered), meter(edited.metered));
        put("connection.permissions", original.onlyMe ? "user:" + user : "", edited.onlyMe ? "user:" + user : "");
        for (const family of ["ipv4", "ipv6"]) {
            const before = original[family], after = edited[family];
            put(family + ".method", before.method, after.method);
            // Cleared only when the method changes to one without them: a DHCP profile may
            // carry extra fixed addresses of its own, which the editor leaves alone
            const manual = after.method === "manual";
            const ownAddresses = manual || (family === "ipv4" && after.method === "shared");
            const sameMethod = after.method === before.method;
            put(family + ".addresses", before.addresses.join(","), ownAddresses || sameMethod ? after.addresses.join(",") : "");
            put(family + ".gateway", before.gateway, manual || sameMethod ? after.gateway : "");
            put(family + ".dns", before.dns.join(","), after.dns.join(","));
            put(family + ".ignore-auto-dns", yesNo(before.ignoreAutoDns), yesNo(after.ignoreAutoDns));
            put(family + ".never-default", yesNo(before.neverDefault), yesNo(after.neverDefault));
            put(family + ".route-metric", before.routeMetric, after.routeMetric);
            put(family + ".may-fail", yesNo(before.mayFail), yesNo(after.mayFail));
        }
        const shared = edited.ipv4.method === "shared";
        const rangeOf = config => config.rangeStart !== "" ? config.rangeStart + "," + config.rangeEnd : "";
        put("ipv4.shared-dhcp-range", rangeOf(original.ipv4), shared ? rangeOf(edited.ipv4) : "");
        put("ipv4.shared-dhcp-lease-time", original.ipv4.leaseTime, shared ? edited.ipv4.leaseTime : 0);
        put("ipv4.dns-search", original.ipv4.dnsSearch.join(","), edited.ipv4.dnsSearch.join(","));
        put("ipv6.ip6-privacy", original.ipv6.privacy, edited.ipv6.privacy);
        if (original.wifi && edited.wifi) {
            put("802-11-wireless.ssid", original.wifi.ssid, edited.wifi.ssid);
            put("802-11-wireless.band", original.wifi.band, edited.wifi.band);
            put("802-11-wireless.cloned-mac-address", original.wifi.mac, edited.wifi.mac);
            put("802-11-wireless.hidden", yesNo(original.wifi.hidden), yesNo(edited.wifi.hidden));
            put("802-11-wireless.mode", original.wifi.mode, edited.wifi.mode);
            // A hotspot's security and password are the editor's (a network's are the
            // page's): open takes the whole security setting away
            if (isHotspot(edited) && original.wifi.security !== edited.wifi.security) {
                if (edited.wifi.security === "") {
                    if (original.wifi.security !== "")
                        changes.push(["remove", "802-11-wireless-security"]);
                } else {
                    changes.push(["802-11-wireless-security.key-mgmt", edited.wifi.security]);
                    // WPA2 with AES only: TKIP is refused by many phones
                    if (edited.wifi.security === "wpa-psk")
                        changes.push(["802-11-wireless-security.proto", "rsn"], ["802-11-wireless-security.pairwise", "ccmp"],
                            ["802-11-wireless-security.group", "ccmp"]);
                }
            }
            if (isHotspot(edited) && edited.wifi.security !== "" && edited.wifi.password !== null
                    && (original.wifi.password !== edited.wifi.password || original.wifi.security !== edited.wifi.security))
                changes.push(["802-11-wireless-security.psk", edited.wifi.password]);
        }
        if (original.ethernet && edited.ethernet) {
            put("802-3-ethernet.cloned-mac-address", original.ethernet.mac, edited.ethernet.mac);
            put("802-3-ethernet.mtu", original.ethernet.mtu, edited.ethernet.mtu);
        }
        if (original.wireguard && edited.wireguard) {
            const before = original.wireguard, after = edited.wireguard;
            put("connection.interface-name", before.iface, after.iface);
            put("wireguard.listen-port", before.listenPort, after.listenPort);
            put("wireguard.mtu", before.mtu, after.mtu);
            // null: could not be read — kept as it is
            if (after.privateKey !== null && after.privateKey !== before.privateKey)
                changes.push(["wireguard.private-key", after.privateKey]);
            if (after.peers !== null && wireguardPeersText(after.peers) !== wireguardPeersText(before.peers ?? []))
                changes.push(["wireguard.peers", wireguardPeersText(after.peers)]);
        }
        return changes;
    }

    // ── Hotspots ── (a Wi-Fi profile in access-point mode, this computer the router)

    function isHotspot(settings) {
        return settings?.wifi?.mode === "ap";
    }

    // A password easy to read out and type: no 0/O, 1/l/I; `random` returns [0, 1)
    function hotspotPassword(random) {
        const letters = "abcdefghijkmnpqrstuvwxyz23456789";
        let password = "";
        for (let i = 0; i < 12; i++)
            password += letters[Math.floor(random() * letters.length)];
        return password;
    }

    // A new Wi-Fi profile as NetworkManager makes one: what a new hotspot's settings are
    // compared with, so `nmcli connection add` gets what differs (editorChanges)
    function blankWifi() {
        return settingsFrom({ "connection.id": "", "connection.autoconnect": "yes", "connection.autoconnect-priority": "0",
            "connection.metered": "unknown", "connection.permissions": "", "ipv4.method": "auto", "ipv6.method": "auto",
            "ipv6.ip6-privacy": "-1", "802-11-wireless.ssid": "", "802-11-wireless.mode": "infrastructure" });
    }

    // A new hotspot: named after the computer, 2.4 GHz and WPA2 (they work with every
    // device; Intel cards often may not send on 5 GHz), started by hand, IPv6 left alone
    function hotspotTemplate(hostname, password) {
        const settings = blankWifi();
        const name = String(hostname ?? "").trim() || "Hotspot";
        settings.name = name + " hotspot";
        settings.autoconnect = false;
        settings.ipv4.method = "shared";
        settings.ipv6.method = "ignore";
        Object.assign(settings.wifi, { ssid: name, band: "bg", mode: "ap", security: "wpa-psk", password: password });
        return settings;
    }

    // ── Writing ── one `nmcli connection modify` (or `add`) with every change, secrets
    // too: atomic, and a value goes in exactly as typed. (A secret is on nmcli's command
    // line for the moment it runs — what `ps` shows other users of the computer; nmcli's
    // editor on its input hid it, but cut a password's spaces at its ends, made a save two
    // steps, and its failures had to be read from translated text — decided 2026-11-12.)
    // { command, environment } for CommandAction.run.
    function modifyCommand(uuid, changes) {
        const command = ["nmcli", "connection", "modify", "uuid", uuid];
        for (const change of changes)
            command.push(change[0], String(change[1]));
        return { command: command, environment: {} };
    }

    // A new profile from the editor's settings: `nmcli connection add type <type> …`;
    // nmcli prints "Connection 'X' (<uuid>) successfully added."
    function createCommand(settings, user) {
        const wireguard = settings?.wireguard ? true : false;
        const command = ["nmcli", "connection", "add", "type", wireguard ? "wireguard" : "wifi"];
        for (const change of editorChanges(wireguard ? blankWireguard() : blankWifi(), settings, user))
            if (change[0] !== "remove")
                command.push(change[0], String(change[1]));
        return { command: command, environment: {} };
    }

    // The devices on a hotspot from `ip -j neigh show dev <device>`: { clients: [{ address,
    // mac }], seen: { mac: time } } — a device counts while the kernel has heard from it
    // (REACHABLE, DELAY, PROBE) and for `window` ms after (STALE: an idle phone is still
    // on), not once it left: a STALE entry stays in the table for hours. `seen` is the last
    // call's, `now` the time (ms). IPv4 first.
    function hotspotClients(json, seen, now, window) {
        let entries = [];
        try {
            entries = JSON.parse(json || "[]");
        } catch (error) {
            return { clients: [], seen: seen ?? {} };
        }
        const lastSeen = Object.assign({}, seen ?? {});
        const byMac = {};
        const clients = [];
        for (const entry of entries) {
            const states = entry.state ?? [];
            if (!entry.lladdr)
                continue;
            if (["REACHABLE", "DELAY", "PROBE", "PERMANENT"].some(state => states.includes(state)))
                lastSeen[entry.lladdr] = now;
            if (!(entry.lladdr in lastSeen) || now - lastSeen[entry.lladdr] > window)
                continue;
            if (byMac[entry.lladdr]) {
                if (isIpv4(entry.dst) && !isIpv4(byMac[entry.lladdr].address))
                    byMac[entry.lladdr].address = entry.dst;
                continue;
            }
            byMac[entry.lladdr] = { address: entry.dst, mac: entry.lladdr };
            clients.push(byMac[entry.lladdr]);
        }
        return { clients: clients, seen: lastSeen };
    }

    // ── VPNs ──

    // The plugins NetworkManager has, from their `.name` files (one text, files one after
    // another): [{ name ("openvpn"), service ("org.freedesktop.NetworkManager.openvpn") }]
    function vpnPlugins(text) {
        const plugins = [];
        let current = null;
        let section = "";
        for (const rawLine of String(text ?? "").split("\n")) {
            const line = rawLine.trim();
            const header = /^\[(.*)\]$/.exec(line);
            if (header) {
                section = header[1];
                if (section === "VPN Connection") {
                    current = { name: "", service: "" };
                    plugins.push(current);
                }
                continue;
            }
            const pair = /^([^=]+)=(.*)$/.exec(line);
            if (!pair || !current || section !== "VPN Connection")
                continue;
            if (pair[1].trim() === "name")
                current.name = pair[2].trim();
            else if (pair[1].trim() === "service")
                current.service = pair[2].trim();
        }
        return plugins.filter(plugin => plugin.name !== "" && plugin.service !== "")
            .filter((plugin, index, list) => list.findIndex(other => other.name === plugin.name) === index);
    }

    // A plugin's VPN as a person names it, by the plugin's name or its service
    function vpnTypeName(nameOrService) {
        const name = String(nameOrService ?? "").replace(/^org\.freedesktop\.NetworkManager\./, "");
        const names = {
            "wireguard": "WireGuard", "openvpn": "OpenVPN", "openconnect": "OpenConnect", "vpnc": "Cisco IPsec (vpnc)",
            "strongswan": "IPsec (strongSwan)", "libreswan": "IPsec (Libreswan)", "l2tp": "L2TP", "pptp": "PPTP",
            "fortisslvpn": "Fortinet SSL", "sstp": "SSTP", "iodine": "iodine"
        };
        return names[name] ?? (name || "VPN");
    }

    // What a reading by LatestQuery (or CommandRunner) came to: "" when it worked, else why
    // not, in a few words for the log. Output cut short is a failure: the rest is unknown
    function readProblem(result, program) {
        const name = String(program ?? "the command");
        if (result === null || typeof result !== "object")
            return name + " gave no answer";
        if (result.ok === true && result.truncated !== true)
            return "";
        if (result.failedToStart === true)
            return name + " could not be started";
        if (result.timedOut === true)
            return name + " did not answer";
        if (result.truncated === true)
            return "too much output from " + name;
        const first = String(result.stderr ?? "").trim().split("\n")[0].replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, 200);
        return name + " failed (" + result.code + ")" + (first !== "" ? ": " + first : "");
    }

    // The field nmcli refused in `-f` ("Error: invalid field 'wireguard.peer-routes'; allowed
    // fields: …"), or "" when its stderr says no such thing — an empty answer or another
    // error is not a refused field
    function rejectedField(stderr) {
        return /invalid field '([A-Za-z0-9_.-]{1,80})'/.exec(String(stderr ?? ""))?.[1] ?? "";
    }

    // The fields VpnManager asks of its VPN profiles (vpnDetails reads them), less the ones
    // in `rejected` that an older nmcli may not know (vpnDetailOptionalFields): such a field
    // refused fails the whole query, so it is asked again without it
    readonly property var vpnDetailOptionalFields: ["wireguard.peers", "wireguard.peer-routes", "ipv6.method"]
    function vpnDetailFields(rejected) {
        const dropped = (Array.isArray(rejected) ? rejected : []).filter(field => vpnDetailOptionalFields.includes(field));
        return ["connection.uuid", "connection.interface-name", "vpn.service-type", "vpn.data", "wireguard.peers", "wireguard.peer-routes",
                "ipv4.never-default", "ipv6.never-default", "ipv6.method", "GENERAL.STATE", "GENERAL.IP-IFACE", "IP4.ADDRESS", "IP6.ADDRESS",
                "IP4.DNS", "IP6.DNS", "IP4.GATEWAY", "IP6.GATEWAY", "IP4.ROUTE", "IP6.ROUTE"].filter(field => !dropped.includes(field));
    }

    // The fields IpManager asks of every device for Api.localNetworks, the same way:
    // GENERAL.IP-IFACE (a modem's IP runs on another interface than its device) may be
    // refused by an old nmcli, and is asked again without
    readonly property var deviceAddressOptionalFields: ["GENERAL.IP-IFACE"]
    function deviceAddressFields(rejected) {
        const dropped = (Array.isArray(rejected) ? rejected : []).filter(field => deviceAddressOptionalFields.includes(field));
        return ["GENERAL.DEVICE", "GENERAL.TYPE", "GENERAL.IP-IFACE", "IP4.ADDRESS", "IP6.ADDRESS"].filter(field => !dropped.includes(field));
    }

    // The IPv6 addresses' flags from `ip -j -6 address show` → { "<interface> <address>":
    // { temporary, deprecated } } (the address canonical), or null when the text is not
    // that JSON. Deprecated: the kernel's flag, or no preferred lifetime left — a privacy
    // address replaced by a newer one, kept only for the connections still using it
    function ipv6AddressFlags(text) {
        let links = null;
        try {
            links = JSON.parse(String(text ?? ""));
        } catch (error) {
            return null;
        }
        if (!Array.isArray(links))
            return null;
        const flags = {};
        for (const link of links) {
            if (link === null || typeof link !== "object" || typeof link.ifname !== "string" || !Array.isArray(link.addr_info))
                continue;
            for (const info of link.addr_info) {
                if (info === null || typeof info !== "object" || info.family !== "inet6" || typeof info.local !== "string")
                    continue;
                const address = AddressRules.parseCidr(info.local);
                if (address === null)
                    continue;
                flags[link.ifname + " " + address.address] = {
                    temporary: info.temporary === true,
                    deprecated: info.deprecated === true || info.preferred_life_time === 0
                };
            }
        }
        return flags;
    }

    // The VPN profiles' details from `nmcli -t -f <vpnDetailFields> connection show uuid A
    // uuid B…` blocks (Nmcli.records): { uuid: { service ("" for WireGuard), server (host,
    // or host:port; "" unknown), iface, addresses [], dns [], neverDefault4, neverDefault6,
    // ipv6Disabled, allowedIps [] (null: the peers not read), peerRoutes, gateways [],
    // routes [], up } } — iface, addresses, dns, gateways and routes only while it is
    // active. `up` only when NetworkManager says "activated": while it is still activating
    // the DNS servers, gateways and routes are not all set yet. A plugin's server is in vpn.data ("remote = host:1194, …" for
    // OpenVPN, "gateway = …" for most), WireGuard's in its first peer's endpoint. `iface` is
    // the tunnel's own (tun0): a plugin VPN's profile names the link under it as its device.
    function vpnDetails(blocks) {
        const details = {};
        for (const block of blocks ?? []) {
            const uuid = block["connection.uuid"];
            if (!uuid)
                continue;
            const data = {};
            // "key = value, key = value" — a value may hold ", " itself (OpenVPN's several
            // remotes): split only where a key follows
            for (const item of String(block["vpn.data"] ?? "").split(/,\s+(?=[\w -]+?\s*=)/)) {
                const pair = /^\s*([^=]+?)\s*=\s*(.*)$/.exec(item);
                if (pair)
                    data[pair[1]] = pair[2].trim();
            }
            // Peers come one after another, ", " between them; each its endpoint
            const endpoints = [];
            const endpointPattern = /endpoint=([^\s,;]+)/g;
            let match;
            while ((match = endpointPattern.exec(String(block["wireguard.peers"] ?? ""))) !== null)
                endpoints.push(match[1]);
            const servers = endpoints.length > 0 ? endpoints
                : (data["remote"] ?? data["gateway"] ?? data["IPSec gateway"] ?? data["address"] ?? "").split(/[,\s]+/).filter(item => item !== "");
            const server = servers[0] ?? "";
            const list = key => [].concat(block[key] ?? []).filter(item => item !== "");
            // "yes" / "no"; anything else (the field not read) unknown
            const flag = key => block[key] === "yes" ? true : block[key] === "no" ? false : null;
            // An active route: "dst = 10.0.0.0/24, nh = 0.0.0.0, mt = 50" → its destination
            const destinations = key => list(key).map(route => /(?:^|,)\s*dst\s*=\s*([^,\s]+)/.exec(route)?.[1] ?? "")
                .filter(destination => destination !== "");
            const allowedIps = [];
            const allowedPattern = /allowed-ips=([^\s,]+)/g;
            while ((match = allowedPattern.exec(String(block["wireguard.peers"] ?? ""))) !== null)
                allowedIps.push(...match[1].split(";").filter(address => address !== ""));
            details[uuid] = {
                service: block["vpn.service-type"] ?? "", server: server ?? "", servers: servers,
                iface: block["GENERAL.IP-IFACE"] ?? "", interfaceName: block["connection.interface-name"] ?? "",
                addresses: list("IP4.ADDRESS").concat(list("IP6.ADDRESS")), dns: list("IP4.DNS").concat(list("IP6.DNS")),
                // What decides whether it takes all traffic, which networks it carries and
                // whether it brings DNS servers (ModuleRules.vpnRouting): the profile's
                // never-default per family, whether IPv6 is off, WireGuard's peers'
                // allowed-ips and whether they become routes (peerRoutes; null: not read),
                // and while up its gateways and routes. `up` NetworkManager says the
                // connection is "activated": the last ones were read whole
                neverDefault4: flag("ipv4.never-default"), neverDefault6: flag("ipv6.never-default"),
                ipv6Disabled: block["ipv6.method"] === "disabled" ? true : typeof block["ipv6.method"] === "string" && block["ipv6.method"] !== "" ? false : null,
                allowedIps: Object.prototype.hasOwnProperty.call(block, "wireguard.peers") ? allowedIps : null,
                peerRoutes: flag("wireguard.peer-routes"),
                gateways: [block["IP4.GATEWAY"] ?? "", block["IP6.GATEWAY"] ?? ""].filter(gateway => gateway !== "" && gateway !== "--"),
                routes: destinations("IP4.ROUTE").concat(destinations("IP6.ROUTE")),
                up: block["GENERAL.STATE"] === "activated"
            };
        }
        return details;
    }

    // The kinds of VPN file the shell imports: WireGuard is NetworkManager's own, the rest
    // need its plugin for the kind (`name` as `nmcli connection import type` takes it).
    // A `.conf` is WireGuard's unless chosen otherwise.
    readonly property var vpnImportKinds: [
        { name: "wireguard", label: "WireGuard", files: ["conf"], builtIn: true },
        { name: "openvpn", label: "OpenVPN", files: ["ovpn", "conf"], builtIn: false },
        { name: "vpnc", label: "Cisco IPsec (vpnc)", files: ["pcf"], builtIn: false }
    ]

    // Whether a kind can be imported now: WireGuard always, a plugin's kind with its plugin
    function canImport(name, plugins) {
        const kind = vpnImportKinds.find(entry => entry.name === name);
        return (kind?.builtIn ?? false) || (plugins ?? []).some(plugin => plugin.name === name);
    }

    // The kind of VPN a file is imported as, by its ending (the first kind there is for it,
    // vpnImportKinds), else the only plugin with no known file of its own; "" when the
    // user has to say
    function importTypeOf(path, plugins) {
        const lower = String(path ?? "").toLowerCase();
        const kind = vpnImportKinds.find(entry => entry.files.some(ending => lower.endsWith("." + ending)) && canImport(entry.name, plugins));
        if (kind)
            return kind.name;
        const others = (plugins ?? []).filter(plugin => !vpnImportKinds.some(entry => entry.name === plugin.name));
        return others.length === 1 ? others[0].name : "";
    }

    // A WireGuard file's profile: its name (the file's, without ".conf") and its interface
    // — NetworkManager takes the interface from the file's name, which must be one: 15
    // characters at most, letters, digits, "-", "_" (else "wg0")
    function wireguardImportNames(path) {
        const base = String(path ?? "").split("/").pop().replace(/\.conf$/i, "");
        const iface = base.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 15);
        return { name: base || "WireGuard", iface: iface || "wg0" };
    }

    // ── WireGuard ──

    // A WireGuard key: 32 bytes in base64 — 43 characters and "="
    function isWireguardKey(text) {
        return /^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw480]=$/.test(String(text ?? ""));
    }

    // "host:port", "1.2.3.4:port" or "[v6]:port"
    function isEndpoint(text) {
        const match = /^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+):(\d{1,5})$/.exec(String(text ?? ""));
        return !!match && Number(match[2]) > 0 && Number(match[2]) <= 65535
            && (!match[1].startsWith("[") || isIpv6(match[1].slice(1, -1)));
    }

    // `wireguard.peers` as nmcli prints it (read with -s and --escape no): peers one after
    // another, ", " between them, each its public key and then key=value pairs →
    // [{ publicKey, allowedIps [], endpoint, presharedKey, keepalive }]
    function wireguardPeers(text) {
        const peers = [];
        for (const item of String(text ?? "").split(/,\s+/)) {
            const tokens = item.trim().split(/\s+/).filter(token => token !== "");
            if (tokens.length === 0)
                continue;
            const peer = { publicKey: tokens[0], allowedIps: [], endpoint: "", presharedKey: "", keepalive: 0 };
            for (const token of tokens.slice(1)) {
                const at = token.indexOf("=");
                if (at < 0)
                    continue;
                const key = token.slice(0, at), value = token.slice(at + 1);
                if (key === "allowed-ips")
                    peer.allowedIps = value.split(";").filter(address => address !== "");
                else if (key === "endpoint")
                    peer.endpoint = value;
                else if (key === "preshared-key")
                    peer.presharedKey = value;
                else if (key === "persistent-keepalive")
                    peer.keepalive = parseInt(value) || 0;
            }
            peers.push(peer);
        }
        return peers;
    }

    // The peers as `wireguard.peers` takes them; a preshared key stored with the profile
    function wireguardPeersText(peers) {
        return (peers ?? []).map(peer => [peer.publicKey]
            .concat(peer.allowedIps.length > 0 ? ["allowed-ips=" + peer.allowedIps.join(";")] : [])
            .concat(peer.endpoint !== "" ? ["endpoint=" + peer.endpoint] : [])
            .concat(peer.presharedKey !== "" ? ["preshared-key=" + peer.presharedKey, "preshared-key-flags=0"] : [])
            .concat(peer.keepalive > 0 ? ["persistent-keepalive=" + peer.keepalive] : [])
            .join(" ")).join(", ");
    }

    function _wireguardErrors(wireguard) {
        const errors = {};
        if (!/^[A-Za-z0-9_-]{1,15}$/.test(wireguard.iface))
            errors["connection.interface-name"] = "1 to 15 letters, digits, - or _.";
        if (wireguard.privateKey !== null && !isWireguardKey(wireguard.privateKey))
            errors["wireguard.private-key"] = wireguard.privateKey === "" ? "A key is needed: generate one, or paste the provider's."
                : "Not a WireGuard key (44 characters of base64).";
        if (wireguard.listenPort < 0 || wireguard.listenPort > 65535)
            errors["wireguard.listen-port"] = "0 to 65535, or automatic.";
        if (wireguard.mtu !== 0 && (wireguard.mtu < 576 || wireguard.mtu > 9000))
            errors["wireguard.mtu"] = "576 to 9000, or automatic.";
        (wireguard.peers ?? []).forEach((peer, index) => {
            const field = name => "wireguard.peers." + index + "." + name;
            if (!isWireguardKey(peer.publicKey))
                errors[field("publicKey")] = "The server's public key (44 characters of base64).";
            const badIps = peer.allowedIps.filter(address => !isCidr4(address) && !isCidr6(address));
            if (badIps.length > 0)
                errors[field("allowedIps")] = "Not an address with its prefix: " + badIps.join(", ");
            if (peer.endpoint !== "" && !isEndpoint(peer.endpoint))
                errors[field("endpoint")] = "A host and port: vpn.example.com:51820, or [2001:db8::1]:51820.";
            if (peer.presharedKey !== "" && !isWireguardKey(peer.presharedKey))
                errors[field("presharedKey")] = "Not a WireGuard key (44 characters of base64).";
            if (peer.keepalive < 0 || peer.keepalive > 65535)
                errors[field("keepalive")] = "0 to 65535 seconds.";
        });
        return errors;
    }

    // A new WireGuard profile as compared with: methods "" so the new one's are always
    // written (NetworkManager's own defaults for one differ between versions)
    function blankWireguard() {
        const settings = settingsFrom({ "connection.id": "", "connection.autoconnect": "yes", "connection.autoconnect-priority": "0",
            "connection.metered": "unknown", "connection.permissions": "", "ipv6.ip6-privacy": "-1",
            "connection.interface-name": "", "wireguard.listen-port": "0", "wireguard.mtu": "0" });
        settings.ipv4.method = "";
        settings.ipv6.method = "";
        return settings;
    }

    // A new WireGuard profile: off until connected by hand, an address to fill in (the
    // provider's), IPv6 off, one peer sending all traffic through; the interface the first
    // of wg0, wg1… no profile has
    function wireguardTemplate(usedInterfaces) {
        const settings = blankWireguard();
        let number = 0;
        while ((usedInterfaces ?? []).includes("wg" + number))
            number++;
        settings.name = "WireGuard";
        settings.autoconnect = false;
        settings.ipv4.method = "manual";
        settings.ipv6.method = "disabled";
        settings.wireguard.iface = "wg" + number;
        settings.wireguard.peers = [{ publicKey: "", allowedIps: ["0.0.0.0/0", "::/0"], endpoint: "", presharedKey: "", keepalive: 0 }];
        return settings;
    }

    // ── A VPN with a network ── what the shell does when the profiles or the mapping
    // change (NetworkManager's connection.secondaries takes no WireGuard, and takes the
    // network down when the VPN fails). A VPN is wanted while some network it is linked to
    // in `mapping` ({ networkUuid: [vpnUuid…] }) is up; wanted and down, it is brought up,
    // unless taken down by hand; wanted by none, and brought up by the shell, it is taken
    // down once its networks are fully down (while one is still deactivating NetworkManager
    // takes a plugin VPN down itself). `memory` ({ broughtUp: { vpn: true }, pending: { vpn:
    // ms }, heldDown: { vpn: key } }) is kept between calls and across restarts:
    //   pending  — asked to connect at that time, not seen up yet: still down then is not
    //              "by hand" (the list can be read before NetworkManager says activating);
    //              still down 90 s later, it failed — held down, not retried in a loop
    //   heldDown — went down while wanted, not by the shell: left down until the networks
    //              wanting it change (`key`, the ones up then)
    // `now` the time in ms.
    // `providerVpns` (optional): the VPNs of providers (VpnManager, "<provider>:<id>"), in
    // the same shape ({ uuid, state, attention }) — considered only once the profiles are
    // read (with none, nothing is known of the networks: a VPN would look unwanted and be
    // taken down). A VPN that needs the user (`attention` set: log in, approve…) is never
    // asked to connect; one that went there after being asked (or after being brought up) is
    // held down like a failure, so it is not retried in a loop — tried again only when the
    // networks change. Attention within vpnAttentionGraceMs of being asked is waited out
    // (still pending): a provider passing through it on its way up (activating → attention
    // → activated) is not held down; one still needing the user after that is. (Attention
    // reached from up — brought up, then down with attention — is held down at once; a
    // provider must not use attention for transient states.) One that needed the user
    // before it was ever asked is asked once the attention is gone. A VPN of a provider that
    // is not there (a module disabled, not loaded yet) is left alone, its memory kept while
    // the mapping still names it (pending and held-down memory of an id neither known nor in
    // the mapping is dropped).
    // → { connect [], disconnect [], memory }
    function vpnWithNetworkPlan(profiles, mapping, memory, now, providerVpns) {
        const states = {};
        const attention = {};
        const known = (profiles ?? []).length > 0 ? (profiles ?? []).concat(providerVpns ?? []) : [];
        for (const profile of known) {
            states[profile.uuid] = profile.state ?? "";
            attention[profile.uuid] = !!profile.attention;
        }
        const broughtUp = Object.assign({}, memory?.broughtUp ?? {});
        const pending = Object.assign({}, memory?.pending ?? {});
        const heldDown = Object.assign({}, memory?.heldDown ?? {});
        const vpns = [];
        for (const network in mapping ?? {})
            for (const vpn of mapping[network] ?? [])
                if (!vpns.includes(vpn))
                    vpns.push(vpn);
        for (const vpn of Object.keys(broughtUp))
            if (!vpns.includes(vpn))
                vpns.push(vpn);
        const connect = [];
        const disconnect = [];
        // Memory of what is neither known nor wanted any more: nothing would ever settle it
        // (and the 30 s re-check would run for it for ever)
        for (const vpn of Object.keys(pending).concat(Object.keys(heldDown)))
            if (!(vpn in states) && !vpns.includes(vpn)) {
                delete pending[vpn];
                delete heldDown[vpn];
            }
        for (const vpn of vpns) {
            if (!(vpn in states))
                continue;
            const linked = Object.keys(mapping ?? {}).filter(network => (mapping[network] ?? []).includes(vpn));
            const upNetworks = linked.filter(network => states[network] === "activated").sort();
            const settling = linked.some(network => states[network] === "deactivating" || states[network] === "activating");
            const key = upNetworks.join(" ");
            const state = states[vpn];
            const vpnUp = state === "activated" || state === "activating";
            if (vpnUp)
                delete pending[vpn];
            if (vpn in heldDown && heldDown[vpn] !== key)
                delete heldDown[vpn];
            if (upNetworks.length > 0) {
                if (state !== "")
                    continue;
                if (attention[vpn]) {
                    // Asked moments ago: perhaps passing through on its way up — waited out
                    if (vpn in pending && now - pending[vpn] < vpnAttentionGraceMs)
                        continue;
                    // Asked to connect and now waiting for the user: a failure, held down
                    if (vpn in pending || broughtUp[vpn]) {
                        delete pending[vpn];
                        delete broughtUp[vpn];
                        heldDown[vpn] = key;
                    }
                    continue;
                }
                if (vpn in pending) {
                    if (now - pending[vpn] > 90000) {
                        delete pending[vpn];
                        delete broughtUp[vpn];
                        heldDown[vpn] = key;
                    }
                    continue;
                }
                if (broughtUp[vpn]) {
                    // Brought up, seen up, now down without the shell: by hand
                    delete broughtUp[vpn];
                    heldDown[vpn] = key;
                    continue;
                }
                if (vpn in heldDown)
                    continue;
                connect.push(vpn);
                broughtUp[vpn] = true;
                pending[vpn] = now;
            } else {
                delete pending[vpn];
                if (!broughtUp[vpn])
                    continue;
                if (state === "")
                    delete broughtUp[vpn];
                else if (state === "activated" && !settling) {
                    disconnect.push(vpn);
                    delete broughtUp[vpn];
                }
            }
        }
        return { connect: connect, disconnect: disconnect, memory: { broughtUp: broughtUp, pending: pending, heldDown: heldDown } };
    }

    // How long attention right after being asked is taken as passing (vpnWithNetworkPlan)
    readonly property int vpnAttentionGraceMs: 20000

    // The mapping without profiles that are gone; `profiles` empty (not read yet): as it is.
    // A provider's VPN ("<provider>:<id>") is NEVER removed here, whatever its provider says
    // and whether it is there at all: a provider logged out, stopped, unreadable for one
    // read, ready too early or renaming an entry must not make the shell delete the user's
    // setting. One its provider does not report now is "not available" (unavailableVpnIds):
    // kept, shown as such in the network's editor, removed only by the user there.
    // An id that can be neither a UUID nor a provider's (vpnIdParts) is removed.
    function prunedVpnMapping(mapping, profiles) {
        if ((profiles ?? []).length === 0)
            return mapping ?? {};
        const uuids = profiles.map(profile => profile.uuid);
        const keeps = vpn => {
            const parts = vpnIdParts(vpn);
            return parts !== null && (parts.provider !== "" || uuids.includes(vpn));
        };
        const pruned = {};
        for (const network in mapping ?? {}) {
            if (!uuids.includes(network))
                continue;
            const vpns = (mapping[network] ?? []).filter(keeps);
            if (vpns.length > 0)
                pruned[network] = vpns;
        }
        return pruned;
    }

    function _vpnIdsOf(vpns) {
        return (vpns ?? []).map(vpn => typeof vpn === "string" ? vpn : vpn?.uuid);
    }

    // The one definition of "not available": the provider VPNs among `ids` (a list, or a
    // mapping { network: [id…] }) that are not among `vpns` now (VpnManager.vpns, or their
    // ids) — whatever the reason: provider not registered, not ready, logged out, the entry
    // missing from one read. [id…], each once, in their order.
    function unavailableVpnIds(ids, vpns) {
        const all = Array.isArray(ids) ? ids
            : Object.keys(ids ?? {}).reduce((list, network) => list.concat(ids[network] ?? []), []);
        const present = _vpnIdsOf(vpns);
        const found = [];
        for (const vpn of all) {
            const parts = vpnIdParts(vpn);
            if (parts !== null && parts.provider !== "" && !present.includes(vpn) && !found.includes(vpn))
                found.push(vpn);
        }
        return found;
    }

    // The network editor's starting list for "VPN with a network", from the stored one:
    // NetworkManager's VPNs still there (one deleted would stay picked, unseen and
    // unremovable) and EVERY provider VPN, available or not (the editor shows the not
    // available ones as removable pills)
    function editorVpnIds(stored, vpns) {
        const present = _vpnIdsOf(vpns);
        const kept = [];
        for (const vpn of stored ?? []) {
            const parts = vpnIdParts(vpn);
            if (parts !== null && (parts.provider !== "" || present.includes(vpn)) && !kept.includes(vpn))
                kept.push(vpn);
        }
        return kept;
    }

    // What the network editor writes for "VPN with a network": the user's picks (`edited`),
    // plus every provider VPN of the value stored now (`stored`) that the user did not take
    // out — taken out: in the list the editor started from (`original`), not in `edited`. A
    // provider id the editor did not show is never lost.
    function vpnsToWrite(stored, original, edited) {
        const picks = edited ?? [];
        const result = picks.filter((vpn, index) => picks.indexOf(vpn) === index);
        const removed = (original ?? []).filter(vpn => !picks.includes(vpn));
        for (const vpn of stored ?? []) {
            const parts = vpnIdParts(vpn);
            if (parts !== null && parts.provider !== "" && !removed.includes(vpn) && !result.includes(vpn))
                result.push(vpn);
        }
        return result;
    }

    // ── VPN providers ── a VPN supplied by an object rather than NetworkManager (the
    // contract: components/VpnProvider.qml; notes/plans/tailscale.md §3). Its entries are
    // addressed as "<providerId>:<entryId>" — NetworkManager's UUIDs are hexadecimal digits
    // and dashes, so the colon keeps the two apart for good.

    // A provider's id: a lower-case letter, then up to 31 of lower-case letters, digits,
    // "-" and "_" — no colon, nothing an object's prototype knows
    function isVpnProviderId(text) {
        return typeof text === "string" && /^[a-z][a-z0-9_-]{0,31}$/.test(text) && !_prototypeKeys.includes(text);
    }

    // An entry's id within its provider: 1 to 64 of letters, digits, ".", "_", "~", "-"
    function isVpnEntryId(text) {
        return typeof text === "string" && /^[A-Za-z0-9._~-]{1,64}$/.test(text) && !_prototypeKeys.includes(text);
    }

    readonly property var _prototypeKeys: ["__proto__", "constructor", "prototype", "hasOwnProperty", "toString", "valueOf",
        "__defineGetter__", "__defineSetter__", "__lookupGetter__", "__lookupSetter__", "isPrototypeOf", "propertyIsEnumerable",
        "toLocaleString"]

    function vpnId(providerId, entryId) {
        return providerId + ":" + entryId;
    }

    // A VPN's id taken apart: { provider: "", entry: uuid } for NetworkManager's (no colon),
    // { provider, entry } for a provider's; null when it can be neither
    function vpnIdParts(id) {
        if (typeof id !== "string" || id === "")
            return null;
        const colon = id.indexOf(":");
        if (colon < 0)
            return _prototypeKeys.includes(id) ? null : { provider: "", entry: id };
        const provider = id.slice(0, colon), entry = id.slice(colon + 1);
        return isVpnProviderId(provider) && isVpnEntryId(entry) ? { provider: provider, entry: entry } : null;
    }

    readonly property var vpnStates: ["", "activating", "activated", "deactivating"]

    function _string(value, most) {
        return typeof value === "string" ? value.slice(0, most ?? 500) : "";
    }

    function _strings(value) {
        return Array.isArray(value) ? value.filter(item => typeof item === "string").slice(0, 64).map(item => item.slice(0, 200)) : [];
    }

    // A provider's `detail` in the shape vpnDetails gives NetworkManager's VPNs, so the views
    // read both alike: { service "", server, servers [], iface, interfaceName, addresses [],
    // dns [] } — anything else dropped, missing fields empty
    function vpnProviderDetail(detail) {
        const source = detail !== null && typeof detail === "object" && !Array.isArray(detail) ? detail : {};
        const read = key => Object.prototype.hasOwnProperty.call(source, key) ? source[key] : undefined;
        const server = _string(read("server"), 200);
        const servers = _strings(read("servers"));
        return {
            service: "", server: server, servers: servers.length > 0 ? servers : (server !== "" ? [server] : []),
            iface: /^[A-Za-z0-9_.-]{1,15}$/.test(_string(read("iface"))) ? read("iface") : "",
            interfaceName: /^[A-Za-z0-9_.-]{1,15}$/.test(_string(read("interfaceName"))) ? read("interfaceName") : "",
            addresses: _strings(read("addresses")), dns: _strings(read("dns"))
        };
    }

    // What a provider reports as its entries, checked: { entries, problems } — `entries`
    // [{ id, name, state, attention, detail, active, status, busy, fullTunnel, setsDns, routes }]
    // in the provider's order, `problems` sentences for the log. An entry whose id, name or
    // state is wrong (not an object; id not isVpnEntryId, or repeated; name not a string;
    // state not one of vpnStates) is dropped. A wrong optional field is set to its default
    // and reported: attention (null, or { reason: a non-empty string, action: a string, ""
    // none }), detail (vpnProviderDetail), active (a bool; else whether state is not ""),
    // status (text, at most 80; else ""), busy (a bool; else false), fullTunnel, setsDns and
    // routes (ModuleRules.vpnRoutingFields: null where absent or wrong — unknown).
    function vpnProviderEntries(providerId, raw) {
        const entries = [];
        const problems = [];
        const name = String(providerId);
        let list = raw;
        if (!Array.isArray(list)) {
            if (list !== undefined && list !== null)
                problems.push(name + ": entries is not a list");
            list = [];
        }
        const seen = {};
        list.slice(0, 64).forEach((entry, index) => {
            const where = name + ": entry " + index;
            if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
                problems.push(where + " is not an object");
                return;
            }
            const read = key => {
                try {
                    return Object.prototype.hasOwnProperty.call(entry, key) ? entry[key] : undefined;
                } catch (error) {
                    return undefined;
                }
            };
            const id = read("id");
            if (!isVpnEntryId(id)) {
                problems.push(where + ": id " + JSON.stringify(String(id)).slice(0, 80) + " is not 1–64 letters, digits, . _ ~ -");
                return;
            }
            if (seen[id] === true) {
                problems.push(where + ": id " + id + " repeated");
                return;
            }
            const entryName = read("name");
            if (typeof entryName !== "string") {
                problems.push(where + " (" + id + "): name is not text");
                return;
            }
            const state = read("state") ?? "";
            if (!vpnStates.includes(state)) {
                problems.push(where + " (" + id + "): state " + JSON.stringify(String(state)).slice(0, 40) + " is not one of activating, activated, deactivating, \"\"");
                return;
            }
            seen[id] = true;
            let attention = read("attention") ?? null;
            if (attention !== null) {
                const reason = typeof attention === "object" ? attention.reason : undefined;
                const action = typeof attention === "object" ? (attention.action ?? "") : undefined;
                if (typeof reason !== "string" || reason.trim() === "" || typeof action !== "string") {
                    problems.push(where + " (" + id + "): attention is not { reason, action }");
                    attention = null;
                } else {
                    attention = { reason: reason.slice(0, 300), action: action.slice(0, 40) };
                }
            }
            const rawDetail = read("detail");
            if (rawDetail !== undefined && rawDetail !== null && (typeof rawDetail !== "object" || Array.isArray(rawDetail)))
                problems.push(where + " (" + id + "): detail is not an object");
            let active = read("active");
            if (active !== undefined && typeof active !== "boolean")
                problems.push(where + " (" + id + "): active is not true or false");
            if (typeof active !== "boolean")
                active = state !== "";
            const status = read("status");
            if (status !== undefined && status !== null && typeof status !== "string")
                problems.push(where + " (" + id + "): status is not text");
            const entryBusy = read("busy");
            if (entryBusy !== undefined && entryBusy !== null && typeof entryBusy !== "boolean")
                problems.push(where + " (" + id + "): busy is not true or false");
            const routing = ModuleRules.vpnRoutingFields({ fullTunnel: read("fullTunnel"), setsDns: read("setsDns"), routes: read("routes") });
            routing.problems.forEach(problem => problems.push(where + " (" + id + "): " + problem));
            entries.push({
                id: id, name: entryName.trim().slice(0, 200) || id, state: state, attention: attention,
                detail: vpnProviderDetail(rawDetail), active: active,
                status: typeof status === "string" ? status.trim().slice(0, 80) : "", busy: entryBusy === true,
                fullTunnel: routing.fields.fullTunnel, setsDns: routing.fields.setsDns, routes: routing.fields.routes
            });
        });
        if (list.length > 64)
            problems.push(name + ": more than 64 entries, the rest left out");
        return { entries: entries, problems: problems };
    }

    // One provider's entries as VPNs in the shape of NetworkManager's ({ uuid, name, type,
    // kind, state, active, … }), so the views and vpnWithNetworkPlan take both: `uuid` is the
    // id "<provider>:<entry>", `type` "provider", plus provider, entryId, typeName, glyph,
    // attention, status, busy, fullTunnel, setsDns, routes. `read` { providerId, typeName, glyph, entries (vpnProviderEntries') }
    function vpnProviderVpns(read) {
        return (read?.entries ?? []).map(entry => ({
            uuid: vpnId(read.providerId, entry.id), name: entry.name, type: "provider", kind: "vpn",
            state: entry.state, active: entry.active, device: "", autoconnect: false, priority: 0, lastUsed: 0,
            provider: read.providerId, entryId: entry.id, typeName: read.typeName || "VPN", glyph: read.glyph || "",
            attention: entry.attention, status: entry.status ?? "", busy: entry.busy === true,
            fullTunnel: entry.fullTunnel ?? null, setsDns: entry.setsDns ?? null, routes: entry.routes ?? null
        }));
    }

    // NetworkManager's VPNs and the providers' in one list: those up first, then the most
    // recently used; ties keep their order — NetworkManager's first, then each provider's
    // in the order the providers were registered, entries in the provider's order
    function mergedVpns(nmVpns, providerVpns) {
        return (nmVpns ?? []).concat(providerVpns ?? [])
            .map((vpn, index) => ({ vpn: vpn, index: index }))
            .sort((a, b) => (b.vpn.active - a.vpn.active) || ((b.vpn.lastUsed ?? 0) - (a.vpn.lastUsed ?? 0)) || (a.index - b.index))
            .map(item => item.vpn);
    }

    // The glyph for the VPNs up (the bar, the popup's header): WireGuard's when every one is
    // WireGuard (and with none), one provider's own when every one is that provider's and it
    // has one, else the padlock
    function activeVpnGlyph(activeVpns) {
        const list = activeVpns ?? [];
        if (list.every(vpn => vpn.type === "wireguard"))
            return "󰒃";
        const glyph = list[0]?.glyph ?? "";
        if (glyph !== "" && list.every(vpn => vpn.provider !== undefined && vpn.provider === list[0].provider))
            return glyph;
        return "󰌾";
    }

    // A VPN's own glyph: WireGuard's, a provider's own, else the padlock
    function vpnGlyph(vpn) {
        return vpn?.type === "wireguard" ? "󰒃" : (vpn?.glyph || "󰌾");
    }

    // A provider's failure as a notification, as NetworkManager's are (NetworkProfiles):
    // { title "<what> failed", body: the reason }
    function vpnFailureNotice(what, reason) {
        const doing = _string(what, 200).trim() || "A VPN action";
        return { title: doing + " failed", body: _string(reason, 500).trim() || "It did not say why." };
    }

    // The kill switch does not cover provider VPNs (the owner's decision, tailscale.md §8):
    // the sentence saying so while blocking is on and the VPN is up or coming up ("" when
    // there is nothing to say). `note` the provider's own wording (its lockdownNote), else
    // the shell's. `whateverState` true: whenever blocking is on, up or not — the VPN page's
    // card states the limit always; the popup's row only while it matters.
    function lockdownProviderNote(blocking, vpn, note, whateverState) {
        if (!blocking || typeof vpn?.provider !== "string" || vpn.provider === "")
            return "";
        if (whateverState !== true && vpn.state !== "activating" && vpn.state !== "activated")
            return "";
        const own = _string(note, 300).trim();
        return own !== "" ? own : (vpn.typeName || "This VPN") + " is not let through while traffic outside a VPN is blocked: "
            + "it may not connect or carry traffic.";
    }

    // Whether two slot contexts (VpnExtras, the provider's page) say the same, so a
    // provider re-read that changed nothing for this entry does not poke its contribution:
    // the same keys; objects that are not plain data (the provider) the same object;
    // functions (close) alike as functions; the rest the same as JSON
    function sameVpnContext(a, b) {
        if (a === b)
            return true;
        if (a === null || b === null || typeof a !== "object" || typeof b !== "object")
            return false;
        const keys = Object.keys(a);
        if (keys.length !== Object.keys(b).length)
            return false;
        for (const key of keys) {
            if (!Object.prototype.hasOwnProperty.call(b, key))
                return false;
            const left = a[key], right = b[key];
            if (left === right)
                continue;
            if (typeof left === "function" || typeof right === "function") {
                if (typeof left !== typeof right)
                    return false;
                continue;
            }
            if (key === "provider")
                return false;
            try {
                if (JSON.stringify(left) !== JSON.stringify(right))
                    return false;
            } catch (error) {
                return false;
            }
        }
        return true;
    }

    // ── Only through the VPN (a kill switch) ── notes/plans/network.md, VPN stage 7

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
        return isIpv6(text) ? text : text.split(":")[0];
    }

    // `getent ahosts` run per host, each line "host address": { host: [addresses] }
    function addressesByHost(lines) {
        const found = {};
        for (const line of lines ?? []) {
            const parts = String(line).trim().split(/\s+/);
            if (parts.length < 2 || !isIpAddress(parts[1]))
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
        return isIpv4(address) && !/(^|\.)0\d/.test(address) || isIpv6(address) && !String(address).includes(".");
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
