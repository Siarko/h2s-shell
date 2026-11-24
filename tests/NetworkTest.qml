import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.network

// Parsers for nmcli output and sysfs counters. Loading these singletons starts their
// usual nmcli polling; those results arrive after the synchronous assertions below.
// Asynchronous for one case at the end: the connection editor's save finished after its
// page is gone (the unit runner gives nmcli no bus, so every nmcli run there fails at once).
TestCase {
    id: suite
    suiteName: "Network"
    asynchronous: true

    property var _link: LinkSpeed {
        intervalMs: 2000
    }

    function run() {
        // --- Nmcli.splitTerse ---
        {
            assertEqual(JSON.stringify(Nmcli.splitTerse("a:b:c")), JSON.stringify(["a", "b", "c"]),
                "splitTerse splits plain fields");
            assertEqual(JSON.stringify(Nmcli.splitTerse("Home\\:5G:80")), JSON.stringify(["Home:5G", "80"]),
                "splitTerse keeps an escaped colon inside its field");
            assertEqual(JSON.stringify(Nmcli.splitTerse("back\\\\slash:x")), JSON.stringify(["back\\slash", "x"]),
                "splitTerse unescapes a backslash");
            assertEqual(JSON.stringify(Nmcli.splitTerse("a::b:")), JSON.stringify(["a", "", "b", ""]),
                "splitTerse keeps empty fields, including a trailing one");
        }

        // --- NetworkManager._processStatus ---
        {
            NetworkManager._processStatus([
                "veth1234:ethernet:unmanaged:",
                "enp5s0:ethernet:unavailable:",
                "enp6s0:ethernet:connected:Wired connection 1",
                "wlan0:wifi:connected:Home\\:5G",
                "lo:loopback:connected (externally):lo"
            ]);
            assertEqual(NetworkManager.ethernetDevice, "enp6s0", "status: a connected ethernet port wins over an unplugged one");
            assertEqual(NetworkManager.ethernetState, "connected", "status: ethernet state");
            assertEqual(NetworkManager.ethernetConnection, "Wired connection 1", "status: ethernet profile name");
            assertEqual(NetworkManager.wifiDevice, "wlan0", "status: wifi device");
            assert(NetworkManager.wifiAvailable, "status: wifi adapter detected");
            assertEqual(NetworkManager.activeDevice, "enp6s0", "status: active device is the first connected link");
            assertEqual(NetworkManager.activeDeviceType, "ethernet", "status: active device type");
            assert(NetworkManager.isConnected, "status: connected");

            NetworkManager._processStatus(["wlan0:wifi:connected:Home\\:5G"]);
            assertEqual(NetworkManager.activeConnection, "Home:5G", "status: escaped colon in a connection name");
            assertEqual(NetworkManager.ethernetDevice, "", "status: no ethernet device");

            NetworkManager._processStatus([]);
            assert(!NetworkManager.isConnected, "status: empty output means disconnected");
            assertEqual(NetworkManager.activeDeviceType, "none", "status: empty output resets the type");
            assert(!NetworkManager.wifiAvailable, "status: empty output means no wifi adapter");
        }

        // --- WifiManager._processWifiList ---
        // The scan's list and the connecting state are shared with the suites beside it:
        // put back as they were, however the case ends
        const savedWifi = { networks: WifiManager.wifiNetworks, signal: WifiManager.wifiSignal,
                            connecting: WifiManager.connecting, connectingTo: WifiManager.connectingTo };
        try {
            WifiManager.connecting = true;
            WifiManager.connectingTo = "Home:5G";
            WifiManager._processWifiList([
                "Home\\:5G:72:WPA2:*:5180 MHz",
                "Neighbour:40:WPA1 WPA2::2412 MHz",
                ":30:WPA2::2437 MHz"
            ]);
            const networks = WifiManager.wifiNetworks;
            assertEqual(networks.length, 2, "wifi list: hidden networks are skipped");
            assertEqual(networks[0].ssid, "Home:5G", "wifi list: escaped colon in an SSID");
            assertEqual(networks[0].signal, 72, "wifi list: signal");
            assertEqual(networks[0].security, "WPA2", "wifi list: security");
            assert(networks[0].inUse, "wifi list: network in use");
            assertEqual(networks[0].band, "5G", "wifi list: 5 GHz band");
            assertEqual(networks[1].band, "2.4G", "wifi list: 2.4 GHz band");
            assert(!networks[1].inUse, "wifi list: network not in use");
            assertEqual(WifiManager.wifiSignal, 72, "wifi list: signal of the network in use");
            assert(!WifiManager.connecting && WifiManager.connectingTo === "",
                "wifi list: connecting ends once the target is in use");
        } finally {
            WifiManager.wifiNetworks = savedWifi.networks;
            WifiManager.wifiSignal = savedWifi.signal;
            WifiManager.connecting = savedWifi.connecting;
            WifiManager.connectingTo = savedWifi.connectingTo;
        }

        // --- Nmcli.wifiNetworks: the signal in use ---
        {
            assertEqual(Nmcli.wifiNetworks(["Cafe:50:WPA2::2412 MHz"]).signalInUse, -1, "wifi list: none in use");
            assertEqual(Nmcli.wifiNetworks(["Home:40:WPA2:*:2412 MHz", "Home:81:WPA2:*:5180 MHz"]).signalInUse, 81,
                "wifi list: listed twice in use (two bands): the stronger");
            const merged = Nmcli.wifiNetworks([
                "Home:40:WPA1:*:2412 MHz", "Cafe:50:WPA2::2437 MHz", "Home:81:WPA2::5180 MHz", "Home:20:WPA2::2462 MHz"
            ]).networks;
            assertEqual(merged.length, 2, "wifi list: one SSID from several access points is one network");
            assertEqual(merged[0].ssid, "Home", "wifi list: merged network keeps its first place");
            assertEqual(merged[0].signal, 81, "wifi list: merged network: the strongest signal");
            assertEqual(merged[0].security, "WPA2", "wifi list: merged network: the strongest one's security");
            assert(merged[0].inUse, "wifi list: merged network: in use if any access point is");
            assertEqual(merged[0].band, "2.4G · 5G", "wifi list: merged network: every band");
            assertEqual(merged[1].band, "2.4G", "wifi list: single network: its band");
        }

        // --- saved networks: by SSID, from the profiles (NetworkProfiles) ---
        {
            const profiles = Nmcli.profiles([
                "u1:Home 1:802-11-wireless::yes:0:0:no",
                "u2:Wired connection 1:802-3-ethernet:enp13s0:yes:0:0:yes"
            ]);
            const ssids = Nmcli.wifiDetails(["connection.uuid:u1", "802-11-wireless.ssid:Home:5G"]);
            assert(profiles[0].kind === "wifi" && ssids[profiles[0].uuid].ssid === "Home:5G",
                   "saved networks: a profile named otherwise than its SSID still matches it");
        }

        // --- IpManager._parse ---
        {
            const parsed = IpManager._parse([
                "IP4.ADDRESS[1]:192.168.1.10/24",
                "IP4.ADDRESS[2]:10.0.0.5/8",
                "IP4.DNS[1]:1.1.1.1",
                "IP4.DNS[2]:8.8.8.8"
            ]);
            assertEqual(parsed.address, "192.168.1.10/24", "ip: first address wins");
            assertEqual(parsed.dns, "1.1.1.1, 8.8.8.8", "ip: every DNS server, in order");

            const empty = IpManager._parse(["IP4.ADDRESS[1]:--", "IP4.DNS[1]:"]);
            assertEqual(empty.address, "", "ip: '--' is no address");
            assertEqual(empty.dns, "", "ip: empty DNS is skipped");
        }

        // --- LinkSpeed._update ---
        {
            _link._update(1000, 500, 10000);
            assertEqual(_link.rxSpeed, 0, "link speed: the first read is only a baseline");
            _link._update(5000, 2500, 12000);
            assertEqual(_link.rxSpeed, 2000, "link speed: rx bytes per second");
            assertEqual(_link.txSpeed, 1000, "link speed: tx bytes per second");
            _link._update(100, 100, 14000);
            assert(_link.rxSpeed === 0 && _link.txSpeed === 0, "link speed: a counter reset never goes negative");
            assertEqual(_link.rxHistory.length, 2, "link speed: one history sample per measured tick, none for the baseline");
            assertEqual(_link.rxHistory[0].v, 2000, "link speed: history holds the rx speed");
            assertEqual(_link.txHistory[0].v, 1000, "link speed: and the tx speed separately");
            _link._update(10100, 100, 24000);
            assertEqual(_link.rxSpeed, 1000, "link speed: divides by the time elapsed, not the configured interval");
        }

        // --- Nmcli: records, profiles, devices, errors ---
        {
            const blocks = Nmcli.records([
                "connection.uuid:5b60", "connection.id:H2S 10 Pro", "802-11-wireless.ssid:H2S 10 Pro",
                "connection.uuid:fe20", "connection.id:Home: upstairs", "802-11-wireless.ssid:H2S_HEX"
            ], "connection.uuid");
            assertEqual(blocks.length, 2, "records: a block starts again where its first key comes back");
            assertEqual(blocks[1]["connection.id"], "Home: upstairs", "records: only the first colon separates");

            const details = Nmcli.wifiDetails([
                "connection.uuid:5b60", "802-11-wireless.ssid:H2S 10 Pro", "802-11-wireless-security.key-mgmt:sae", "802-11-wireless.hidden:no",
                "connection.uuid:fe20", "802-11-wireless.ssid:H2S_HEX", "802-11-wireless-security.key-mgmt:", "802-11-wireless.hidden:yes"
            ]);
            assertEqual(details["fe20"].ssid, "H2S_HEX", "wifiDetails: by UUID");
            assert(details["5b60"].security === "sae" && !details["5b60"].hidden && details["fe20"].hidden, "wifiDetails: security, hidden");
            assertEqual(Nmcli.securityName(details["5b60"].security), "WPA3", "securityName: SAE is WPA3");
            assertEqual(Nmcli.securityName(details["fe20"].security), "Open", "securityName: none set is open");

            const profiles = Nmcli.profiles([
                "5b60:H2S 10 Pro:802-11-wireless::yes:0:1731400000:no",
                "a1b2:Wired connection 1:802-3-ethernet:enp13s0:yes:-1:1731400100:yes",
                "c3d4:ua:wireguard::no:0:0:no",
                "broken"
            ]);
            assertEqual(profiles.length, 3, "profiles: a malformed line is skipped");
            assertEqual(profiles[0].kind, "wifi", "profiles: Wi-Fi's kind");
            assert(profiles[1].active && profiles[1].device === "enp13s0" && profiles[1].priority === -1,
                   "profiles: active, device, a negative priority");
            assert(profiles[2].kind === "vpn" && !profiles[2].autoconnect, "profiles: WireGuard is a VPN");
            const states = Nmcli.profiles(["v1:work\\:vpn:wireguard:wg0:no:0:0:yes::activating", "v2:home:vpn::no:0:0:no::"]);
            assert(states[0].name === "work:vpn" && states[0].state === "activating" && states[0].active && states[1].state === "" && !states[1].active,
                   "profiles: a VPN connecting, an escaped colon in its name; one not up");
            assertEqual(profiles[1].state, "activated", "profiles: an older nmcli line without STATE: active is activated");
            const ported = Nmcli.profiles(["p1:bridge-slave-eno1:802-3-ethernet:eno1:yes:0:0:yes:bridge"]);
            assertEqual(ported[0].port, "bridge", "profiles: a bridge's port is told apart");
            assertEqual(profiles[0].port, "", "profiles: an older nmcli line without the column: not a port");

            const devices = Nmcli.devices([
                "GENERAL.DEVICE:enp13s0", "GENERAL.TYPE:ethernet", "GENERAL.VENDOR:Realtek Semiconductor Co., Ltd.",
                "GENERAL.PRODUCT:RTL8126 5GbE Controller", "GENERAL.DRIVER:r8169", "GENERAL.HWADDR:34:5A:60:B5:AA:BE",
                "GENERAL.MTU:1500", "GENERAL.STATE:100 (connected)", "GENERAL.CONNECTION:Wired connection 1",
                "CAPABILITIES.SPEED:2500 Mb/s", "IP4.ADDRESS[1]:192.168.1.137/24", "IP4.GATEWAY:192.168.1.1",
                "IP4.DNS[1]:192.168.1.1", "IP4.DOMAIN[1]:lan", "IP6.ADDRESS[1]:fe80::6f33:7072:7167:c19c/64", "IP6.GATEWAY:",
                "GENERAL.DEVICE:wlp14s0", "GENERAL.TYPE:wifi", "GENERAL.STATE:30 (disconnected)", "GENERAL.CONNECTION:"
            ]);
            assertEqual(devices.length, 2, "devices: two");
            const glued = Nmcli.devices(["GENERAL.DEVICE:a", "GENERAL.STATE:100 (connected (externally))",
                                         "\nGENERAL.DEVICE:b", "GENERAL.STATE:10 (unmanaged)"]);
            assert(glued.length === 2 && glued[0].stateText === "connected (externally)" && glued[1].state === 10,
                   "devices: the blank line glued to the next block's first line still starts a block");
            const wired = devices[0];
            assert(wired.state === 100 && wired.stateText === "connected" && wired.speed === 2500,
                   "devices: state number and words, speed in Mb/s");
            assertEqual(wired.mac, "34:5A:60:B5:AA:BE", "devices: a MAC keeps its colons");
            assertEqual(Nmcli.devices(["GENERAL.DEVICE:e", "WIRED-PROPERTIES.CARRIER:off"])[0].carrier, "off", "devices: the cable out");
            assertEqual(JSON.stringify(Nmcli.devices(["GENERAL.DEVICE:cdc-wdm0", "GENERAL.TYPE:gsm", "GENERAL.IP-IFACE:wwan0", "GENERAL.DEVICE:e"])
                                       .map(device => device.ipIface)), JSON.stringify(["wwan0", ""]), "devices: the interface the IP runs on; not read — \"\"");
            assertEqual(wired.carrier, "", "devices: the cable not known");
            assertEqual(wired.ipv6[0], "fe80::6f33:7072:7167:c19c/64", "devices: an IPv6 address keeps its colons");
            assert(wired.ipv4.length === 1 && wired.dns[0] === "192.168.1.1" && wired.domains[0] === "lan", "devices: addresses, DNS, domains");
            assert(devices[1].kind === "wifi" && devices[1].ipv4.length === 0, "devices: a disconnected Wi-Fi, no addresses");

            assertEqual(Nmcli.errorKind("Error: Connection activation failed: Secrets were required, but not provided."), "password",
                        "errorKind: a wrong or missing password");
            assertEqual(Nmcli.errorKind("Error: Failed to modify connection: Insufficient privileges"), "auth", "errorKind: not allowed");
            assertEqual(Nmcli.errorKind("Error: unknown connection 'x'."), "missing", "errorKind: no such connection");
            assertEqual(Nmcli.errorKind("Error: No network with SSID 'x' found."), "notFound", "errorKind: not in range");
            assertEqual(Nmcli.errorMessage("Error: unknown connection 'x'.\nmore"), "unknown connection 'x'",
                        "errorMessage: plain words, the first line");
        }

        // --- NetworkRules ---
        {
            const rules = NetworkRules;
            assert(rules.isHostname("h2s-arch") && rules.isHostname("box.lan"), "hostname: plain and dotted");
            assert(!rules.isHostname("-box") && !rules.isHostname("box_1") && !rules.isHostname("") && !rules.isHostname("a..b"),
                   "hostname: a leading hyphen, an underscore, empty, an empty label");
            assert(!rules.isHostname("a".repeat(64)), "hostname: a label over 63");
            assert(rules.isIpv4("192.168.1.1") && !rules.isIpv4("256.1.1.1") && !rules.isIpv4("1.2.3"), "IPv4");
            assert(rules.isIpv6("2606:4700:4700::1111") && rules.isIpv6("::1") && rules.isIpv6("fe80::6f33:7072:7167:c19c"),
                   "IPv6: shortened forms");
            assert(rules.isIpv6("::ffff:192.168.1.1"), "IPv6 ending in IPv4");
            assert(!rules.isIpv6("1::2::3") && !rules.isIpv6("12345::1") && !rules.isIpv6("1:2:3:4:5:6:7"), "IPv6: two ::, a long group, too few");
            const parsed = rules.parseServers("1.1.1.1, 8.8.8.8 ;1.1.1.1  nope 2606:4700:4700::1111");
            assertEqual(JSON.stringify(parsed.list), "[\"1.1.1.1\",\"8.8.8.8\",\"2606:4700:4700::1111\"]", "servers: split, no repeats");
            assertEqual(JSON.stringify(parsed.bad), "[\"nope\"]", "servers: what is not an address");
            const dns = rules.globalDnsFrom({ searches: { type: "as", data: ["lan"] },
                domains: { type: "a{sv}", data: { "*": { type: "a{sv}", data: { servers: { type: "as", data: ["1.1.1.1"] } } } } } });
            assert(dns.servers[0] === "1.1.1.1" && dns.searches[0] === "lan", "global DNS: read from busctl's JSON");
            assertEqual(rules.globalDnsFrom({}).servers.length, 0, "global DNS: none set");
            assertEqual(rules.globalDnsArguments([]).join(" "), "a{sv} 0", "global DNS: cleared");
            assertEqual(rules.globalDnsArguments(["1.1.1.1", "9.9.9.9"]).join(" "),
                        "a{sv} 1 domains a{sv} 1 * a{sv} 1 servers as 2 1.1.1.1 9.9.9.9", "global DNS: busctl's nested form");
            assertEqual(rules.speedText(2500), "2.5 Gb/s", "speed: gigabits");
            assertEqual(rules.speedText(866), "866 Mb/s", "speed: megabits");
            assertEqual(rules.speedText(0), "", "speed: unknown");
            assert(rules.isWifiPassword("12345678", "wpa-psk") && !rules.isWifiPassword("1234567", "wpa-psk"), "Wi-Fi password: at least 8");
            assert(!rules.isWifiPassword("x".repeat(64), "sae") && rules.isWifiPassword("a".repeat(64), "sae"),
                   "Wi-Fi password: 64 characters only as the hexadecimal key");
            assert(rules.wifiEnterConnects("secret123", false, false), "Enter in the popup's password field: connects, as Connect");
            assert(!rules.wifiEnterConnects("", false, false), "… not with the field empty");
            assert(!rules.wifiEnterConnects("secret123", true, false), "… nor for the network in use (no Connect button)");
            assert(!rules.wifiEnterConnects("secret123", false, true), "… nor while it connects (the button is Cancel)");
            for (const security of ["WPA2", "WPA1 WPA2", "WPA3", "WPA2 WPA3"])
                assert(!rules.wifiScanPassword("abc", security) && rules.wifiScanPassword("12345678", security) && !rules.wifiScanPassword("", security),
                       "a network in range secured by " + security + ": a password of 8 or more");
            assert(rules.wifiScanPassword("abc", "WPA2 802.1X") && rules.wifiScanPassword("abc", "WEP") && !rules.wifiScanPassword("", "WEP"),
                   "… enterprise and WEP not checked, beyond something typed");
                        // --- the connection editor ---
            const wiredBlock = { "connection.id": "Office", "connection.autoconnect": "yes", "connection.autoconnect-priority": "-999",
                "connection.metered": "unknown", "connection.permissions": "", "ipv4.method": "manual",
                "ipv4.addresses": "192.168.10.5/24,10.0.0.2/8", "ipv4.gateway": "192.168.10.1", "ipv4.dns": "1.1.1.1,9.9.9.9",
                "ipv4.dns-search": "lan", "ipv4.ignore-auto-dns": "no", "ipv6.method": "auto", "ipv6.addresses": "",
                "ipv6.gateway": "", "ipv6.dns": "", "ipv6.ignore-auto-dns": "no", "ipv6.ip6-privacy": "-1",
                "802-3-ethernet.cloned-mac-address": "", "802-3-ethernet.mtu": "auto" };
            const wired = rules.settingsFrom(wiredBlock);
            assert(wired.name === "Office" && wired.priority === -999 && wired.metered === "auto" && !wired.onlyMe, "editor: general read");
            assertEqual(JSON.stringify(wired.ipv4.addresses), "[\"192.168.10.5/24\",\"10.0.0.2/8\"]", "editor: addresses as a list");
            assert(wired.ethernet !== null && wired.ethernet.mtu === 0 && wired.wifi === null, "editor: ethernet extras, no Wi-Fi");
            assertEqual(JSON.stringify(rules.editorErrors(wired)), "{}", "editor: valid settings, no errors");
            const unchanged = rules.editorChanges(wired, JSON.parse(JSON.stringify(wired)), "h2s");
            assertEqual(unchanged.length, 0, "editor: nothing changed, nothing sent");

            const edited = JSON.parse(JSON.stringify(wired));
            edited.ipv4.method = "auto";
            edited.onlyMe = true;
            edited.metered = "yes";
            const changes = rules.editorChanges(wired, edited, "h2s");
            const find = property => (changes.find(change => change[0] === property) ?? [null, null])[1];
            assert(find("ipv4.method") === "auto" && find("ipv4.addresses") === "" && find("ipv4.gateway") === "",
                   "editor: leaving manual clears addresses and gateway");
            assert(find("connection.permissions") === "user:h2s" && find("connection.metered") === "yes", "editor: only me, metered");
            assertEqual(find("ipv4.dns"), null, "editor: an unchanged field is not sent");

            const broken = JSON.parse(JSON.stringify(wired));
            broken.ipv4.gateway = "10.1.1.1";
            broken.ipv4.addresses = ["192.168.10.5/24"];
            broken.ipv4.dns = ["1.1.1.1", "nope"];
            broken.ethernet.mtu = 20;
            broken.name = " ";
            const errors = rules.editorErrors(broken);
            assert(errors["ipv4.gateway"] && errors["ipv4.dns"] && errors["802-3-ethernet.mtu"] && errors["connection.id"],
                   "editor: a gateway outside the network, a bad DNS, a tiny MTU, no name");
            const empty = JSON.parse(JSON.stringify(wired));
            empty.ipv4.addresses = [];
            assert(!!rules.editorErrors(empty)["ipv4.addresses"], "editor: manual with no address");
            assert(rules.inSubnet4("192.168.10.200", ["192.168.10.5/24"]) && !rules.inSubnet4("192.168.11.1", ["192.168.10.5/24"]),
                   "subnet: in and out of a /24");
            assert(rules.isCidr6("2001:db8::5/64") && !rules.isCidr6("2001:db8::5/129"), "IPv6 with a prefix");
            assert(rules.isMacSetting("random") && rules.isMacSetting("12:34:56:78:9a:BC") && !rules.isMacSetting("12:34"), "MAC settings");
            assert(wired.ipv4.routeMetric === -1 && wired.ipv4.mayFail && !wired.ipv4.neverDefault && wired.ipv4.rangeStart === "",
                   "editor: routing defaults when nmcli leaves them out");
            const routed = rules.settingsFrom(Object.assign({}, wiredBlock, { "ipv4.never-default": "yes", "ipv4.route-metric": "50",
                "ipv4.may-fail": "no", "ipv6.route-metric": "-1" }));
            assert(routed.ipv4.neverDefault && routed.ipv4.routeMetric === 50 && !routed.ipv4.mayFail && routed.ipv6.routeMetric === -1,
                   "editor: never-default, route metric, may-fail read");
            const router = rules.settingsFrom(Object.assign({}, wiredBlock, { "ipv4.method": "shared", "ipv4.addresses": "10.42.0.1/24",
                "ipv4.gateway": "", "ipv4.shared-dhcp-range": "10.42.0.100,10.42.0.200", "ipv4.shared-dhcp-lease-time": "600" }));
            assert(router.ipv4.rangeStart === "10.42.0.100" && router.ipv4.rangeEnd === "10.42.0.200" && router.ipv4.leaseTime === 600,
                   "editor: the router's range and lease time read");
            assertEqual(JSON.stringify(rules.editorErrors(router)), "{}", "editor: a valid router");
            const badRouter = JSON.parse(JSON.stringify(router));
            badRouter.ipv4.rangeEnd = "10.43.0.5";
            badRouter.ipv4.leaseTime = 30;
            const routerErrors = rules.editorErrors(badRouter);
            assert(routerErrors["ipv4.shared-dhcp-range"] && routerErrors["ipv4.shared-dhcp-lease-time"],
                   "editor: a range outside the network, a too short lease");
            const halfRange = JSON.parse(JSON.stringify(router));
            halfRange.ipv4.rangeEnd = "";
            halfRange.ipv4.addresses = ["10.42.0.1"];
            const halfErrors = rules.editorErrors(halfRange);
            assert(halfErrors["ipv4.shared-dhcp-range"] && halfErrors["ipv4.addresses"], "editor: half a range, an address without its prefix");
            const toRouter = JSON.parse(JSON.stringify(wired));
            toRouter.ipv4.method = "shared";
            toRouter.ipv4.addresses = ["10.42.0.1/24"];
            toRouter.ipv4.rangeStart = "10.42.0.10";
            toRouter.ipv4.rangeEnd = "10.42.0.20";
            const routerChanges = rules.editorChanges(wired, toRouter, "h2s");
            const findRouter = property => (routerChanges.find(change => change[0] === property) ?? [null, null])[1];
            assert(findRouter("ipv4.addresses") === "10.42.0.1/24" && findRouter("ipv4.gateway") === ""
                   && findRouter("ipv4.shared-dhcp-range") === "10.42.0.10,10.42.0.20", "editor: becoming the router keeps its address, sends the range");
            const fromRouter = JSON.parse(JSON.stringify(router));
            fromRouter.ipv4.method = "auto";
            const leaving = rules.editorChanges(router, fromRouter, "h2s");
            assert(leaving.some(change => change[0] === "ipv4.shared-dhcp-range" && change[1] === "")
                   && leaving.some(change => change[0] === "ipv4.shared-dhcp-lease-time" && change[1] === "0"), "editor: leaving the router clears its range");
            const badMetric = JSON.parse(JSON.stringify(wired));
            badMetric.ipv6.routeMetric = -5;
            assert(!!rules.editorErrors(badMetric)["ipv6.route-metric"], "editor: a negative route metric");
            // --- hotspots ---
            const password = rules.hotspotPassword(() => 0.5);
            assert(password.length === 12 && !/[01lIO]/.test(password), "hotspot: a 12-letter password, nothing to misread");
            const hotspot = rules.hotspotTemplate("framework", "secretpass");
            assert(rules.isHotspot(hotspot) && hotspot.wifi.ssid === "framework" && hotspot.wifi.band === "bg"
                   && hotspot.wifi.security === "wpa-psk" && !hotspot.autoconnect && hotspot.ipv4.method === "shared",
                   "hotspot: template — the computer's name, 2.4 GHz, WPA2, by hand, the router");
            assertEqual(JSON.stringify(rules.editorErrors(hotspot)), "{}", "hotspot: the template is valid");
            const create = rules.createCommand(hotspot, "h2s");
            const addArgs = create.command.slice(3);
            const argument = property => { const at = addArgs.indexOf(property); return at < 0 ? null : addArgs[at + 1]; };
            assert(addArgs[0] === "type" && addArgs[1] === "wifi" && argument("802-11-wireless.mode") === "ap"
                   && argument("802-11-wireless.ssid") === "framework" && argument("ipv4.method") === "shared"
                   && argument("802-11-wireless-security.key-mgmt") === "wpa-psk" && argument("802-11-wireless-security.psk") === "secretpass"
                   && argument("802-11-wireless-security.proto") === "rsn" && argument("connection.autoconnect") === "no"
                   && argument("connection.id") === "framework hotspot", "hotspot: the add command");
            const shortPassword = JSON.parse(JSON.stringify(hotspot));
            shortPassword.wifi.password = "short";
            assert(!!rules.editorErrors(shortPassword)["802-11-wireless-security.psk"], "hotspot: a too short password");
            const opened = JSON.parse(JSON.stringify(hotspot));
            opened.wifi.security = "";
            const openChanges = rules.editorChanges(hotspot, opened, "h2s");
            assert(openChanges.some(change => change[0] === "remove" && change[1] === "802-11-wireless-security")
                   && !openChanges.some(change => change[0] === "802-11-wireless-security.psk"), "hotspot: open takes the security away");
            const newPassword = JSON.parse(JSON.stringify(hotspot));
            newPassword.wifi.password = "anotherpass";
            const passwordChanges = rules.editorChanges(hotspot, newPassword, "h2s");
            assert(passwordChanges.length === 1 && passwordChanges[0][1] === "anotherpass", "hotspot: only the new password sent");
            const network = rules.settingsFrom({ "connection.id": "Home", "802-11-wireless.ssid": "Home", "802-11-wireless-security.key-mgmt": "wpa-psk" });
            assert(!rules.isHotspot(network) && rules.editorChanges(network, Object.assign(JSON.parse(JSON.stringify(network)), {}), "h2s").length === 0
                   && Object.keys(rules.editorErrors(network)).length === 0, "hotspot: a joined network's password is not the editor's");
            const neighbours = JSON.stringify([
                { dst: "10.42.0.23", dev: "wlan0", lladdr: "aa:bb:cc:00:11:22", state: ["REACHABLE"] },
                { dst: "fe80::1", dev: "wlan0", lladdr: "aa:bb:cc:00:11:22", state: ["STALE"] },
                { dst: "10.42.0.40", dev: "wlan0", state: ["FAILED"] },
                { dst: "10.42.0.41", dev: "wlan0", lladdr: "dd:ee:ff:00:11:22", state: ["STALE"] }]);
            const first = rules.hotspotClients(neighbours, {}, 1000, 300000);
            assert(first.clients.length === 1 && first.clients[0].address === "10.42.0.23",
                   "hotspot: devices heard from, IPv4 first; a STALE one never heard from left out");
            const idle = rules.hotspotClients(JSON.stringify([{ dst: "10.42.0.23", lladdr: "aa:bb:cc:00:11:22", state: ["STALE"] }]),
                first.seen, 200000, 300000);
            assertEqual(idle.clients.length, 1, "hotspot: an idle device still counts for a while");
            const gone = rules.hotspotClients(JSON.stringify([{ dst: "10.42.0.23", lladdr: "aa:bb:cc:00:11:22", state: ["STALE"] }]),
                first.seen, 400000, 300000);
            assertEqual(gone.clients.length, 0, "hotspot: a device long silent has left");
            assertEqual(rules.hotspotClients("not json", {}, 0, 1).clients.length, 0, "hotspot: unreadable neighbours, none");
            const extra = rules.settingsFrom(Object.assign({}, wiredBlock, { "ipv4.method": "auto", "ipv4.addresses": "10.0.0.5/24", "ipv4.gateway": "" }));
            const renamed = JSON.parse(JSON.stringify(extra));
            renamed.name = "Renamed";
            const renameChanges = rules.editorChanges(extra, renamed, "h2s");
            assert(renameChanges.length === 1 && renameChanges[0][0] === "connection.id", "editor: DHCP's extra addresses left alone");
            const backToManual = rules.editorChanges(Object.assign(JSON.parse(JSON.stringify(wired)), { ipv4: Object.assign({}, wired.ipv4,
                { method: "auto", addresses: [], gateway: "" }) }), wired, "h2s");
            const findBack = property => (backToManual.find(change => change[0] === property) ?? [null, null])[1];
            assert(findBack("ipv4.method") === "manual" && findBack("ipv4.addresses") === "192.168.10.5/24,10.0.0.2/8"
                   && findBack("ipv4.gateway") === "192.168.10.1", "editor: the way back to manual brings its addresses and gateway");
            const crossDns = JSON.parse(JSON.stringify(wired));
            crossDns.ipv4.dns = ["2606:4700:4700::1111"];
            crossDns.ipv6.dns = ["1.1.1.1"];
            const crossErrors = rules.editorErrors(crossDns);
            assert(crossErrors["ipv4.dns"] && crossErrors["ipv6.dns"], "editor: DNS servers of the other family refused");
            const unread = JSON.parse(JSON.stringify(hotspot));
            unread.wifi.password = null;
            const unreadBand = JSON.parse(JSON.stringify(unread));
            unreadBand.wifi.band = "a";
            assert(Object.keys(rules.editorErrors(unread)).length === 0
                   && !rules.editorChanges(unread, unreadBand, "h2s").some(change => change[0] === "802-11-wireless-security.psk"),
                   "hotspot: a password that could not be read is kept, not required");
            // --- VPNs ---
            const plugins = rules.vpnPlugins("[VPN Connection]\nname=openvpn\nservice=org.freedesktop.NetworkManager.openvpn\n"
                + "program=/usr/lib/nm-openvpn-service\n\n[libnm]\nplugin=libnm-vpn-plugin-openvpn.so\n[GNOME]\nname=ignored\n"
                + "[VPN Connection]\nname=vpnc\nservice=org.freedesktop.NetworkManager.vpnc\n"
                + "[VPN Connection]\nname=openvpn\nservice=org.freedesktop.NetworkManager.openvpn\n");
            assert(plugins.length === 2 && plugins[0].name === "openvpn" && plugins[1].name === "vpnc",
                   "vpn: plugins from their .name files, other sections ignored, each once");
            assertEqual(rules.vpnTypeName("org.freedesktop.NetworkManager.openvpn"), "OpenVPN", "vpn: a plugin's name from its service");
            const vpnDetails = rules.vpnDetails([
                { "connection.uuid": "w1", "wireguard.peers": "KEY= allowed-ips=0.0.0.0/0;::/0 endpoint=vpn.example.com:3389" },
                { "connection.uuid": "o1", "vpn.service-type": "org.freedesktop.NetworkManager.openvpn",
                  "vpn.data": "ca = /home/a/ca.crt, connection-type = tls, remote = ovpn.example.org:1194, dev = tun" }]);
            assert(vpnDetails["w1"].server === "vpn.example.com:3389" && vpnDetails["w1"].service === ""
                   && vpnDetails["o1"].server === "ovpn.example.org:1194", "vpn: the server from WireGuard's peer and OpenVPN's remote");
            const upDetails = rules.vpnDetails([
                { "connection.uuid": "w2", "wireguard.peers": "K1= allowed-ips=10.0.0.0/8 endpoint=a.example:51820, K2= endpoint=b.example:51820" },
                { "connection.uuid": "o2", "vpn.service-type": "org.freedesktop.NetworkManager.openvpn", "GENERAL.IP-IFACE": "tun0",
                  "IP4.ADDRESS": ["10.8.0.6/24"], "IP6.ADDRESS": ["fd00::6/64"], "IP4.DNS": ["10.8.0.1"] }]);
            assert(upDetails["w2"].server === "a.example:51820" && upDetails["w2"].iface === "" && upDetails["w2"].addresses.length === 0,
                   "vpn: several peers — the first's endpoint, without the comma; not up, no interface");
            assert(upDetails["o2"].iface === "tun0" && upDetails["o2"].addresses.join(" ") === "10.8.0.6/24 fd00::6/64"
                   && upDetails["o2"].dns[0] === "10.8.0.1", "vpn: while up, the tunnel's own interface, addresses and DNS");
            // What decides its routing (ModuleRules.vpnRouting)
            const routing = rules.vpnDetails([
                { "connection.uuid": "w3", "wireguard.peers": "K1= allowed-ips=10.0.0.0/8;fd00::/8 endpoint=a.example:51820, K2= allowed-ips=0.0.0.0/0",
                  "ipv4.never-default": "no", "ipv6.never-default": "yes" },
                { "connection.uuid": "o3", "vpn.service-type": "org.freedesktop.NetworkManager.openvpn", "GENERAL.STATE": "activated", "GENERAL.IP-IFACE": "tun0",
                  "IP4.GATEWAY": "10.8.0.1", "IP6.GATEWAY": "", "IP4.ROUTE": ["dst = 10.8.0.0/24, nh = 0.0.0.0, mt = 50", "dst = 0.0.0.0/0, nh = 10.8.0.1, mt = 50"],
                  "IP6.ROUTE": ["dst = fe80::/64, nh = ::, mt = 256"] },
                { "connection.uuid": "o4", "vpn.service-type": "org.freedesktop.NetworkManager.openvpn" }]);
            assertEqual(JSON.stringify([routing["w3"].allowedIps, routing["w3"].neverDefault4, routing["w3"].neverDefault6, routing["w3"].up]),
                        JSON.stringify([["10.0.0.0/8", "fd00::/8", "0.0.0.0/0"], false, true, false]),
                        "vpn: every peer's allowed-ips, never-default per family; not up");
            assertEqual(JSON.stringify([routing["o3"].gateways, routing["o3"].routes, routing["o3"].up]),
                        JSON.stringify([["10.8.0.1"], ["10.8.0.0/24", "0.0.0.0/0", "fe80::/64"], true]), "vpn: while up, its gateways and its routes' destinations");
            assertEqual(JSON.stringify([routing["o4"].allowedIps, routing["o4"].neverDefault4, routing["o4"].gateways, routing["o4"].up]),
                        JSON.stringify([null, null, [], false]), "vpn: fields not read — unknown (null), not \"no\"");
            // Up only when "activated": while activating, the active part is there but not whole
            const activating = rules.vpnDetails([
                { "connection.uuid": "o5", "vpn.service-type": "org.freedesktop.NetworkManager.openvpn", "GENERAL.STATE": "activating",
                  "GENERAL.IP-IFACE": "tun0", "IP4.ADDRESS": ["10.8.0.6/24"] }]);
            assertEqual(JSON.stringify([activating["o5"].up, activating["o5"].iface]), JSON.stringify([false, "tun0"]),
                        "vpn: GENERAL.STATE activating — not up (its DNS, gateways and routes not all set yet)");
            const wireguardSettings = rules.vpnDetails([
                { "connection.uuid": "w4", "wireguard.peers": "K1= allowed-ips=0.0.0.0/0", "wireguard.peer-routes": "no", "ipv6.method": "disabled" },
                { "connection.uuid": "w5", "wireguard.peers": "K1= allowed-ips=0.0.0.0/0", "wireguard.peer-routes": "yes", "ipv6.method": "auto" },
                { "connection.uuid": "w6", "wireguard.peers": "" }]);
            assertEqual(JSON.stringify(["w4", "w5", "w6"].map(uuid => [wireguardSettings[uuid].peerRoutes, wireguardSettings[uuid].ipv6Disabled])),
                        JSON.stringify([[false, true], [true, false], [null, null]]), "vpn: peer-routes and whether IPv6 is disabled; not read — null");
            // The fields asked, less those an older nmcli refused (only the optional ones)
            const detailFields = rules.vpnDetailFields([]);
            assert(["wireguard.peers", "wireguard.peer-routes", "ipv6.method", "GENERAL.STATE", "IP4.ROUTE"].every(field => detailFields.includes(field)),
                   "vpn: the details' fields: peers, peer-routes, IPv6 method, state, routes");
            assert(!rules.vpnDetailFields(["wireguard.peer-routes"]).includes("wireguard.peer-routes")
                   && rules.vpnDetailFields(["wireguard.peer-routes"]).includes("wireguard.peers"), "vpn: a refused field left out, the rest asked");
            assertEqual(rules.vpnDetailFields(["connection.uuid", "GENERAL.STATE"]).length, detailFields.length, "vpn: a field it needs is never left out");
            assert(rules.deviceAddressFields([]).includes("GENERAL.IP-IFACE") && !rules.deviceAddressFields(["GENERAL.IP-IFACE"]).includes("GENERAL.IP-IFACE")
                   && rules.deviceAddressFields(["GENERAL.DEVICE"]).includes("GENERAL.DEVICE"), "devices' addresses: GENERAL.IP-IFACE optional, the rest not");
            // A refused field only when nmcli says so: an empty answer turns nothing off
            assertEqual(rules.rejectedField("Error: invalid field 'wireguard.peers'; allowed fields: connection,ipv4 and GENERAL,IP4, or profile,active."),
                        "wireguard.peers", "rejectedField: the field nmcli names");
            assertEqual(JSON.stringify(["", "Error: unknown connection 'u1'.", null, "Error: invalid field ''"].map(text => rules.rejectedField(text))),
                        JSON.stringify(["", "", "", ""]), "rejectedField: an empty answer or another error — none");
            // What a reading came to
            assertEqual(rules.readProblem({ ok: true, code: 0, stderr: "", truncated: false }, "nmcli"), "", "readProblem: it worked — none");
            assertEqual(JSON.stringify([
                rules.readProblem({ ok: false, code: 8, stderr: "Error: NetworkManager is not running.\nmore" }, "nmcli"),
                rules.readProblem({ ok: false, code: -1, failedToStart: true }, "nmcli"),
                rules.readProblem({ ok: false, timedOut: true }, "ip"),
                rules.readProblem({ ok: true, code: 0, truncated: true }, "nmcli"),
                rules.readProblem(null, "nmcli")]),
                JSON.stringify(["nmcli failed (8): Error: NetworkManager is not running.", "nmcli could not be started", "ip did not answer",
                                "too much output from nmcli", "nmcli gave no answer"]),
                "readProblem: a failure, not started, no answer, cut short, nothing — each a failure, in a few words");
            // The IPv6 addresses' flags (ip -j -6 address show)
            const ipFlags = rules.ipv6AddressFlags(JSON.stringify([
                { ifindex: 2, ifname: "wlan0", addr_info: [
                    { family: "inet6", local: "2001:DB8:0:1::aaaa", prefixlen: 64, scope: "global", temporary: true, dynamic: true, preferred_life_time: 3000 },
                    { family: "inet6", local: "2001:db8:0:1::bbbb", prefixlen: 64, scope: "global", temporary: true, dynamic: true, deprecated: true, preferred_life_time: 0 },
                    { family: "inet6", local: "2001:db8:0:1::cccc", prefixlen: 64, scope: "global", temporary: true, preferred_life_time: 0 },
                    { family: "inet6", local: "2001:db8:0:1::1", prefixlen: 64, scope: "global", mngtmpaddr: true },
                    { family: "inet", local: "192.168.1.5", prefixlen: 24 }, null, { family: "inet6", local: "nonsense" }] },
                { ifname: 5 }, null]));
            assertEqual(JSON.stringify(ipFlags), JSON.stringify({
                "wlan0 2001:db8:0:1::aaaa": { temporary: true, deprecated: false }, "wlan0 2001:db8:0:1::bbbb": { temporary: true, deprecated: true },
                "wlan0 2001:db8:0:1::cccc": { temporary: true, deprecated: true }, "wlan0 2001:db8:0:1::1": { temporary: false, deprecated: false } }),
                "ipv6AddressFlags: temporary, deprecated (the flag, or no preferred lifetime left); addresses canonical; the rest skipped");
            assert(rules.ipv6AddressFlags("") === null && rules.ipv6AddressFlags("{}") === null && rules.ipv6AddressFlags("[") === null,
                   "ipv6AddressFlags: not ip's JSON list — null (not known)");
            assert(rules.importTypeOf("/x/home.conf", plugins) === "wireguard" && rules.importTypeOf("/x/a.OVPN", plugins) === "openvpn"
                   && rules.importTypeOf("/x/cisco.pcf", plugins) === "vpnc" && rules.importTypeOf("/x/a.pcf", []) === ""
                   && rules.importTypeOf("/x/a.ovpn", []) === "", "vpn: import kind by the file's ending, only with its plugin");
            assert(rules.importTypeOf("/x/a.bin", [{ name: "fortisslvpn", service: "s" }]) === "fortisslvpn",
                   "vpn: else the only plugin with no known file");
            assert(rules.canImport("wireguard", []) && !rules.canImport("openvpn", []) && rules.canImport("openvpn", plugins),
                   "vpn: WireGuard always, a plugin's kind with its plugin");
            const importNames = rules.wireguardImportNames("/home/a/My VPN (Poland) server.conf");
            assert(importNames.name === "My VPN (Poland) server" && importNames.iface === "MyVPNPolandserv"
                   && rules.wireguardImportNames("/x/ąę.conf").iface === "wg0", "vpn: a WireGuard file's profile name and a valid interface");
            // --- WireGuard ---
            const keyA = "EXLhetDmYSWNkAY1H8iTfrg3FAq08r4wq9Fsz9cB1hE=";
            const keyB = "rxygZozWStLioOLAG7N+42a9wrGderYLA9o0KEwkc1Q=";
            assert(rules.isWireguardKey(keyA) && !rules.isWireguardKey("short=") && !rules.isWireguardKey(keyA.slice(0, 42) + "B="),
                   "wireguard: a key is 32 bytes of base64");
            assert(rules.isEndpoint("vpn.example.com:51820") && rules.isEndpoint("[::1]:51831") && !rules.isEndpoint("host")
                   && !rules.isEndpoint("host:70000") && !rules.isEndpoint("[nope]:1"), "wireguard: endpoints");
            const peers = rules.wireguardPeers(keyA + " allowed-ips=10.97.97.0/24;10.96.0.0/16 endpoint=127.0.0.1:51830 preshared-key=" + keyB
                + " preshared-key-flags=0 persistent-keepalive=25, " + keyB + " endpoint=[::1]:51831");
            assert(peers.length === 2 && peers[0].allowedIps.length === 2 && peers[0].presharedKey === keyB && peers[0].keepalive === 25
                   && peers[1].endpoint === "[::1]:51831" && peers[1].allowedIps.length === 0, "wireguard: peers read, with their preshared key");
            assertEqual(rules.wireguardPeers(rules.wireguardPeersText(peers)).length, 2, "wireguard: peers written read back the same");
            assert(rules.wireguardPeersText(peers).indexOf("preshared-key-flags=0") > 0, "wireguard: a preshared key stored with the profile");
            const wgSettings = rules.settingsFrom({ "connection.id": "Work", "connection.interface-name": "wg0", "wireguard.listen-port": "0",
                "wireguard.mtu": "1420", "ipv4.method": "manual", "ipv4.addresses": "10.0.0.2/24", "ipv6.method": "disabled" });
            assert(wgSettings.wireguard !== null && wgSettings.wireguard.mtu === 1420 && wgSettings.wireguard.iface === "wg0"
                   && wgSettings.wifi === null, "wireguard: its own settings read");
            wgSettings.wireguard.privateKey = keyA;
            wgSettings.wireguard.peers = peers;
            assertEqual(JSON.stringify(rules.editorErrors(wgSettings)), "{}", "wireguard: valid settings");
            const wgBroken = JSON.parse(JSON.stringify(wgSettings));
            wgBroken.wireguard.privateKey = "";
            wgBroken.wireguard.iface = "a-much-too-long-name";
            wgBroken.wireguard.peers[0].publicKey = "x";
            wgBroken.wireguard.peers[1].endpoint = "nope";
            const wgErrors = rules.editorErrors(wgBroken);
            assert(wgErrors["wireguard.private-key"] && wgErrors["connection.interface-name"] && wgErrors["wireguard.peers.0.publicKey"]
                   && wgErrors["wireguard.peers.1.endpoint"], "wireguard: no key, a long interface, a bad peer key and endpoint");
            const wgEdited = JSON.parse(JSON.stringify(wgSettings));
            wgEdited.wireguard.peers[0].keepalive = 0;
            const wgChanges = rules.editorChanges(wgSettings, wgEdited, "h2s");
            assert(wgChanges.length === 1 && wgChanges[0][0] === "wireguard.peers" && wgChanges[0][1].indexOf("persistent-keepalive") < 0,
                   "wireguard: a peer changed — all peers written");
            const wgUnread = JSON.parse(JSON.stringify(wgSettings));
            wgUnread.wireguard.privateKey = null;
            wgUnread.wireguard.peers = null;
            const wgUnreadRenamed = JSON.parse(JSON.stringify(wgUnread));
            wgUnreadRenamed.name = "Other";
            assert(Object.keys(rules.editorErrors(wgUnread)).length === 0 && rules.editorChanges(wgUnread, wgUnreadRenamed, "h2s").length === 1,
                   "wireguard: secrets not read are kept, not required");
            const template = rules.wireguardTemplate(["wg0"]);
            assert(template.wireguard.iface === "wg1" && template.ipv4.method === "manual" && !template.autoconnect
                   && template.wireguard.peers[0].allowedIps.join(" ") === "0.0.0.0/0 ::/0", "wireguard: a new one — the next interface, all traffic");
            template.ipv4.addresses = ["10.0.0.2/24"];
            template.wireguard.privateKey = keyA;
            template.wireguard.peers[0].publicKey = keyB;
            template.wireguard.peers[0].endpoint = "vpn.example.com:51820";
            const wgCreate = rules.createCommand(template, "h2s");
            const createArgs = wgCreate.command.slice(3);
            const wgArgument = property => { const at = createArgs.indexOf(property); return at < 0 ? null : createArgs[at + 1]; };
            assert(createArgs[0] === "type" && createArgs[1] === "wireguard" && wgArgument("connection.interface-name") === "wg1"
                   && wgArgument("ipv4.method") === "manual" && wgArgument("wireguard.private-key") === keyA
                   && wgArgument("wireguard.peers").indexOf(keyB) === 0 && wgArgument("connection.autoconnect") === "no",
                   "wireguard: the add command, its key and peers with it");
            const exact = rules.modifyCommand("u1", [["connection.id", "A"], ["802-11-wireless-security.psk", " spaced pass "]]);
            assertEqual(exact.command.join("|"), "nmcli|connection|modify|uuid|u1|connection.id|A|802-11-wireless-security.psk| spaced pass ",
                   "writing: one modify, a password with its spaces as typed");
            // --- a VPN with a network ---
            const profile = (uuid, kind, state) => ({ uuid: uuid, kind: kind, state: state });
            const map = { wired: ["vpn"], wifi: ["vpn"], gone: ["vpn"] };
            const plan = (profiles, memory, now) => VpnWithNetworkRules.vpnWithNetworkPlan(profiles, map, memory, now ?? 1000);
            const start = plan([profile("wired", "ethernet", "activated"), profile("wifi", "wifi", ""), profile("vpn", "vpn", "")], {});
            assert(start.connect.join() === "vpn" && start.memory.broughtUp.vpn && start.memory.pending.vpn === 1000,
                   "vpn with a network: a network up brings its VPN up, pending until seen up");
            const early = plan([profile("wired", "ethernet", "activated"), profile("wifi", "wifi", ""), profile("vpn", "vpn", "")], start.memory, 2000);
            assert(early.connect.length === 0 && early.memory.broughtUp.vpn && !early.memory.heldDown.vpn,
                   "vpn with a network: still down right after asking — not taken for by hand, not asked again");
            const seen = plan([profile("wired", "ethernet", "activated"), profile("wifi", "wifi", "activated"), profile("vpn", "vpn", "activated")], early.memory, 3000);
            assert(!("vpn" in seen.memory.pending) && seen.memory.broughtUp.vpn, "vpn with a network: seen up");
            const cableOut = plan([profile("wired", "ethernet", ""), profile("wifi", "wifi", "activated"), profile("vpn", "vpn", "activated")], seen.memory, 4000);
            assert(cableOut.disconnect.length === 0 && cableOut.connect.length === 0,
                   "vpn with a network: one of two linked networks gone — the VPN stays for the other");
            const settling = plan([profile("wired", "ethernet", ""), profile("wifi", "wifi", "deactivating"), profile("vpn", "vpn", "activated")], seen.memory, 5000);
            assertEqual(settling.disconnect.length, 0, "vpn with a network: a network still going down — NetworkManager's turn first");
            const allGone = plan([profile("wired", "ethernet", ""), profile("wifi", "wifi", ""), profile("vpn", "vpn", "activated")], seen.memory, 6000);
            assert(allGone.disconnect.join() === "vpn" && !allGone.memory.broughtUp.vpn, "vpn with a network: no linked network up — taken down");
            const byHand = plan([profile("wired", "ethernet", "activated"), profile("wifi", "wifi", ""), profile("vpn", "vpn", "")], seen.memory, 7000);
            assert(byHand.connect.length === 0 && byHand.memory.heldDown.vpn === "wired" && !byHand.memory.broughtUp.vpn,
                   "vpn with a network: taken down by hand while wanted — held down");
            const stillHeld = plan([profile("wired", "ethernet", "activated"), profile("wifi", "wifi", ""), profile("vpn", "vpn", "")], byHand.memory, 8000);
            assertEqual(stillHeld.connect.length, 0, "vpn with a network: held down while the same networks are up");
            const reconnected = plan([profile("wired", "ethernet", ""), profile("wifi", "wifi", ""), profile("vpn", "vpn", "")], stillHeld.memory, 9000);
            const again = plan([profile("wired", "ethernet", "activated"), profile("wifi", "wifi", ""), profile("vpn", "vpn", "")], reconnected.memory, 10000);
            assertEqual(again.connect.join(), "vpn", "vpn with a network: the network back again — brought up again");
            const failed = plan([profile("wired", "ethernet", "activated"), profile("wifi", "wifi", ""), profile("vpn", "vpn", "")], start.memory, 100000);
            assert(failed.connect.length === 0 && failed.memory.heldDown.vpn === "wired", "vpn with a network: still down after 90 s — failed, not retried");
            const ownVpn = plan([profile("wired", "ethernet", ""), profile("wifi", "wifi", ""), profile("vpn", "vpn", "activated")], {}, 1000);
            assertEqual(ownVpn.disconnect.length, 0, "vpn with a network: a VPN brought up by hand stays when the networks go");
            const notRead = plan([], seen.memory, 1000);
            assert(notRead.connect.length === 0 && notRead.disconnect.length === 0 && notRead.memory.broughtUp.vpn,
                   "vpn with a network: profiles not read yet — nothing done, nothing forgotten");
            const pruned = VpnWithNetworkRules.prunedVpnMapping({ wired: ["vpn", "deleted"], gone: ["vpn"] }, [profile("wired", "ethernet", ""), profile("vpn", "vpn", "")]);
            assertEqual(JSON.stringify(pruned), JSON.stringify({ wired: ["vpn"] }), "vpn with a network: profiles that are gone leave the mapping");
            assertEqual(JSON.stringify(VpnWithNetworkRules.prunedVpnMapping(map, [])), JSON.stringify(map), "vpn with a network: nothing pruned before the profiles are read");
            // --- only through the VPN ---
            const lockProfiles = [{ uuid: "cafe", state: "activated" }, { uuid: "home", state: "" }];
            assert(VpnLockdownRules.lockdownWanted(lockProfiles, true, []) && VpnLockdownRules.lockdownWanted(lockProfiles, false, ["cafe"])
                   && !VpnLockdownRules.lockdownWanted(lockProfiles, false, ["home"]) && !VpnLockdownRules.lockdownWanted([], false, ["cafe"]),
                   "lockdown: always, or while a network it is set for is up");
            assert(VpnLockdownRules.serverHost("vpn.example.com:51820") === "vpn.example.com" && VpnLockdownRules.serverHost("[2001:db8::1]:51820") === "2001:db8::1"
                   && VpnLockdownRules.serverHost("2001:db8::1") === "2001:db8::1" && VpnLockdownRules.serverHost("1.2.3.4") === "1.2.3.4", "lockdown: a server's host");
            const lockArgs = VpnLockdownRules.lockdownArguments({ vpnInterfaces: ["wg0", "ua", "evil\"; flush", "ua", "a.b"], servers: ["2001:DB8::1", "193.0.0.1", "junk", "::ffff:1.2.3.4"], allowLan: false });
            assertEqual(lockArgs.join(" "), "on 0 ua,wg0 193.0.0.1,2001:db8::1", "lockdown: the script's arguments, checked and sorted");
            assertEqual(VpnLockdownRules.lockdownArguments({}).join(" "), "on 0 - -", "lockdown: none — a dash");
            assertEqual(VpnLockdownRules.lockdownStatusOf(lockArgs), "on 0 ua,wg0 193.0.0.1,2001:db8::1", "lockdown: the status it reports");

            // The script's status with the version of the rules loaded (4 on), none before
            assertEqual(JSON.stringify(VpnLockdownRules.lockdownStatusReply(["on 1 wg0 -", "rules 4"])), JSON.stringify({ status: "on 1 wg0 -", rules: 4 }),
                        "lockdown: status — the rules' version read");
            assert(VpnLockdownRules.lockdownStatusReply(["on 1 wg0 -"]).rules === 0 && VpnLockdownRules.lockdownStatusReply(["off", "rules 4"]).rules === 0
                   && VpnLockdownRules.lockdownStatusReply([]).status === "off" && VpnLockdownRules.lockdownStatusReply(["on 1 - -", "rules x"]).rules === 0,
                   "lockdown: status — rules from before version 4, off, nothing, garbage: version 0");
            assert(VpnLockdownRules.lockdownCurrent("on 1 - -", 4, "on 1 - -", 4) && VpnLockdownRules.lockdownCurrent("on 1 - -", 5, "on 1 - -", 4)
                   && !VpnLockdownRules.lockdownCurrent("on 1 - -", 0, "on 1 - -", 4) && !VpnLockdownRules.lockdownCurrent("on 0 - -", 4, "on 1 - -", 4),
                   "lockdown: current — the same arguments from a script at least as new");

            // Only the installed script ever runs; nothing asks for a password by itself
            const lockFacts = changes => Object.assign({ ready: true, busy: false, installed: true, passwordFree: true, askedAtStart: true, force: false,
                wanted: true, nftFound: true, status: "on 1 - -", rulesVersion: 0, expectedStatus: "on 1 - -", scriptVersion: 4,
                refused: "", hosts: "" }, changes);
            const missing = lockFacts({ installed: false, passwordFree: false });
            assertEqual(VpnLockdownRules.lockdownNextStep(Object.assign({}, missing, { status: "off" })), "missing",
                        "lockdown: wanted, nothing installed — nothing runs, nothing asks");
            assertEqual(VpnLockdownRules.lockdownNextStep(Object.assign({}, missing, { status: "off", force: true })), "missing",
                        "lockdown: … not even on a click: the shell's own copy is never run");
            assertEqual(VpnLockdownRules.lockdownNextStep(Object.assign({}, missing, { wanted: false })), "missing", "lockdown: on from before, not wanted, nothing installed — said, nothing run");
            assertEqual(VpnLockdownRules.lockdownNextStep(Object.assign({}, missing, { wanted: false, status: "off" })), "idle", "lockdown: … off and not wanted — idle");
            // Installed, but its rule does not apply (a password was asked, or no rule)
            const asks = lockFacts({ passwordFree: false, askedAtStart: false, status: "off" });
            assertEqual(VpnLockdownRules.lockdownNextStep(asks), "missing", "lockdown: installed, a password would be asked — not run by itself");
            assertEqual(VpnLockdownRules.lockdownNextStep(Object.assign({}, asks, { wanted: false, status: "on 1 - -" })), "missing", "lockdown: … nor switched off by itself");
            assertEqual(VpnLockdownRules.lockdownNextStep(Object.assign({}, asks, { force: true })), "on", "lockdown: … Apply again (a click) runs it, its question with it");
            assertEqual(VpnLockdownRules.lockdownNextStep(Object.assign({}, asks, { force: true, wanted: false, status: "on 1 - -" })), "off", "lockdown: … and switches off on a click");
            // Password-free: the status asked first, once
            assertEqual(VpnLockdownRules.lockdownNextStep(lockFacts({ askedAtStart: false })), "ask", "lockdown: password-free — its status asked first");
            assertEqual(VpnLockdownRules.lockdownNextStep(lockFacts({})), "on", "lockdown: the status says rules older than the installed script — switched on again");
            assertEqual(VpnLockdownRules.lockdownNextStep(lockFacts({ busy: true })), "wait", "lockdown: busy — waits");
            assertEqual(VpnLockdownRules.lockdownNextStep(lockFacts({ rulesVersion: 4 })), "keep", "lockdown: the installed script's rules on — kept");
            assertEqual(VpnLockdownRules.lockdownNextStep(lockFacts({ rulesVersion: 3, scriptVersion: 3 })), "keep", "lockdown: an older installed script's own rules — kept, not switched again and again");
            assertEqual(VpnLockdownRules.lockdownNextStep(lockFacts({ refused: "on 1 - -" })), "refused", "lockdown: a refusal still standing — not switched by itself");
            assertEqual(VpnLockdownRules.lockdownNextStep(lockFacts({ askedAtStart: false, rulesVersion: 4, force: true })), "on",
                        "lockdown: Apply again before the first status ask — switches, not only asks");
            assert(VpnLockdownRules.lockdownNextStep(lockFacts({ ready: false })) === "wait" && VpnLockdownRules.lockdownNextStep(lockFacts({ nftFound: false })) === "no-nft"
                   && VpnLockdownRules.lockdownNextStep(lockFacts({ wanted: false })) === "off" && VpnLockdownRules.lockdownNextStep(lockFacts({ wanted: false, refused: "off" })) === "keep"
                   && VpnLockdownRules.lockdownNextStep(lockFacts({ wanted: false, status: "off" })) === "idle",
                   "lockdown: not ready, no nftables, not wanted while on (refused before), off");
            assertEqual(VpnLockdownRules.lockdownNextStep(lockFacts({ status: "off" })), "on", "lockdown: wanted and off — switched on");
            assertEqual(VpnLockdownRules.lockdownNextStep(lockFacts({ wanted: false, refused: "off", force: true })), "off", "lockdown: Apply again while not wanted, off refused before — switched off");
            // The check's lines
            assertEqual(JSON.stringify(VpnLockdownRules.checkReply(["script 4", "installed 3", "rule yes", "nft"])),
                        JSON.stringify({ script: 4, installed: 3, installedFound: true, unsafe: false, rule: true, nft: true }), "lockdown check: all found");
            assertEqual(JSON.stringify(VpnLockdownRules.checkReply(["script 4", "installed 4", "unsafe 4", "rule yes"])),
                        JSON.stringify({ script: 4, installed: 0, installedFound: false, unsafe: true, rule: true, nft: false }), "lockdown check: a file not root's alone — never counted installed");
            assertEqual(JSON.stringify(VpnLockdownRules.checkReply(["script x", "installed 4 extra", "rule no", "nft x"])),
                        JSON.stringify({ script: 0, installed: 0, installedFound: false, unsafe: false, rule: false, nft: false }), "lockdown check: garbage — nothing found");
            assertEqual(JSON.stringify(VpnLockdownRules.checkReply(["script 4", "installed "])),
                        JSON.stringify({ script: 4, installed: 0, installedFound: true, unsafe: false, rule: false, nft: false }), "lockdown check: installed, its version not read — 0");
            assertEqual(JSON.stringify(VpnLockdownRules.filesRead({ text: "a\n" }, { absent: true })), JSON.stringify({ script: "a\n" }), "lockdown files: a text, none (undefined)");
            assertEqual(JSON.stringify(VpnLockdownRules.filesRead({ unreadable: true }, undefined)), JSON.stringify({ script: null, rule: null }), "lockdown files: unreadable, no answer — not read");
            const rule = VpnLockdownRules.lockdownPolkitRule("h2s", ['"/usr/local/libexec/h2s-vpn-lockdown/h2s-vpn-lockdown"']);
            assert(rule.indexOf('subject.user == "h2s" && subject.local && subject.active') > 0
                   && rule.indexOf('action.lookup("program") == "/usr/local/libexec/h2s-vpn-lockdown/h2s-vpn-lockdown"') > 0
                   && VpnLockdownRules.lockdownPolkitRule("h2s\"; evil", ["x"]).indexOf('subject.user == "h2sevil"') > 0, "lockdown: the polkit rule, for this user and this program only");
            const twoQuotes = "''";
            const module = VpnLockdownRules.lockdownNixosModule("echo ${1:-} " + twoQuotes + "x\n", "h2s");
            assert(module.indexOf("echo " + twoQuotes + "${1:-} " + twoQuotes + "'x") > 0 && module.indexOf("writeShellScriptBin") > 0
                   && module.indexOf("pkgs.nftables") > 0 && module.indexOf('"${lockdown}/bin/h2s-vpn-lockdown"') > 0,
                   "lockdown: NixOS's module, the script escaped inside it");
            assert(VpnLockdownRules.serverHost("ovpn.example.org:1194:udp") === "ovpn.example.org" && VpnLockdownRules.serverHost("1.2.3.4:443:tcp-client") === "1.2.3.4",
                   "lockdown: OpenVPN's host:port:proto");
            const remotes = rules.vpnDetails([{ "connection.uuid": "o3", "vpn.service-type": "org.freedesktop.NetworkManager.openvpn",
                "vpn.data": "ca = /a/ca.crt, remote = a.example:1194:udp, b.example:443:tcp, dev = tun" },
                { "connection.uuid": "w3", "wireguard.peers": "K1= endpoint=a.example:51820, K2= endpoint=[2001:db8::1]:51820" }]);
            assert(remotes["o3"].servers.join(" ") === "a.example:1194:udp b.example:443:tcp" && remotes["o3"].server === "a.example:1194:udp"
                   && remotes["w3"].servers.length === 2, "lockdown: every remote, every peer's endpoint");
            assertEqual(JSON.stringify(VpnLockdownRules.addressesByHost(["a.example 1.2.3.4", "a.example 1.2.3.4", "a.example 2001:db8::5", "b.example junk"])),
                   JSON.stringify({ "a.example": ["1.2.3.4", "2001:db8::5"] }), "lockdown: addresses by host");
            assert(VpnLockdownRules.serverHost("https://vpn.corp.example/staff") === "vpn.corp.example" && VpnLockdownRules.serverHost("vpn.example.com::udp") === "vpn.example.com"
                   && VpnLockdownRules.serverHost("https://user@[2001:db8::1]:443/x") === "2001:db8::1", "lockdown: a server's host from a URL, from host::udp");
            assert(VpnLockdownRules.isLockdownAddress("1.2.3.4") && !VpnLockdownRules.isLockdownAddress("01.2.3.4") && !VpnLockdownRules.isLockdownAddress("::ffff:1.2.3.4")
                   && VpnLockdownRules.isLockdownAddress("2001:db8::1"), "lockdown: addresses as the script takes them");
            const many = [];
            for (let i = 0; i < 300; i++)
                many.push("10." + Math.floor(i / 250) + "." + (i % 250) + ".1");
            assertEqual(VpnLockdownRules.lockdownArguments({ servers: many })[3].split(",").length, 256, "lockdown: no more addresses than the script takes");
            const wifiSettings = rules.settingsFrom({ "connection.id": "Home", "802-11-wireless.ssid": "Home", "802-11-wireless.band": "a",
                "802-11-wireless.cloned-mac-address": "stable", "802-11-wireless.hidden": "no", "ipv6.ip6-privacy": "2 (enabled, prefer temporary IP)" });
            assert(wifiSettings.wifi.band === "a" && wifiSettings.wifi.mac === "stable" && wifiSettings.ethernet === null
                   && wifiSettings.ipv6.privacy === "2", "editor: Wi-Fi extras, privacy from nmcli's words");

                        assert(rules.isConnectivityUri("http://ping.archlinux.org/nm-check.txt") && rules.isConnectivityUri("https://example.com:8443/x"),
                   "connectivity URI: http and https, a port, a path");
            assert(!rules.isConnectivityUri("ftp://x/y") && !rules.isConnectivityUri("http://x/a b")
                   && !rules.isConnectivityUri("http://x/a\nuri=evil") && !rules.isConnectivityUri("http://x/\"q"),
                   "connectivity URI: another scheme, a space, a newline, a quote");
        }
    }

    function runAsync() {
        // The saves below pin the VPN links and the kill switch as globals: put back at the
        // end, key by key
        _globalsPin.remember(["system.vpnWithNetworks", "system.vpnLockdownNetworks", "system.vpnLockdownServers"]);
        try {
            run();
        } catch (error) {
            fail("threw: " + error);
        }
        _savedAfterPageGone();
    }

    // The editor's save, its page closed before NetworkProfiles answers: the VPN linked to
    // the network and the kill-switch choice are still written. A network that is not there
    // ("a4-…"): with "Save and reconnect" and no change to the profile itself the save runs
    // `nmcli connection up` and reads the settings back — both fail here, the save counts
    // (as NetworkProfiles.saveConnection does) — so the answer comes on the event loop.
    // Notifications are recorded, not sent (the failed reconnect reports one).
    readonly property string _goneNetwork: "a4-network-gone"
    readonly property string _linkedVpn: "a4test:one"
    property bool _savedRecordOnly: false
    property GlobalsPin _globalsPin: GlobalsPin {}
    property double _saveStarted: 0
    property Timer _saveWait: Timer {
        interval: 25
        repeat: true
        onTriggered: suite._checkSaved()
    }

    function _savedAfterPageGone() {
        const component = Qt.createComponent(Quickshell.shellDir + "/panels/settings/NetworkConnectionEditor.qml");
        if (component.status !== Component.Ready) {
            fail("NetworkConnectionEditor does not compile: " + component.errorString());
            _globalsPin.restore();
            finish();
            return;
        }
        _savedRecordOnly = Notifier.recordOnly;
        Notifier.recordOnly = true;
        const editor = component.createObject(null, { uuid: _goneNetwork });
        const settings = NetworkRules.blankWifi();
        settings.name = "A4";
        editor._original = settings;
        editor._edited = JSON.parse(JSON.stringify(settings));
        editor._vpnsOriginal = [];
        editor._vpnsEdited = [_linkedVpn];
        editor._lockOriginal = false;
        editor._lockEdited = true;
        assertEqual(editor._changes.length, 0, "save after the page is gone: no change to the profile itself");
        editor._save(true);
        editor.destroy();
        _saveStarted = Date.now();
        _saveWait.start();
    }

    function _checkSaved() {
        const linked = VpnManager.vpnsWith(_goneNetwork).includes(_linkedVpn);
        const blocking = VpnLockdown.isSetFor(_goneNetwork);
        if (!(linked && blocking) && Date.now() - _saveStarted < 15000)
            return;
        _saveWait.stop();
        assert(linked, "save after the page is gone: the VPN linked to the network is written");
        assert(blocking, "save after the page is gone: the kill-switch choice is written");
        VpnManager.setVpnsWith(_goneNetwork, []);
        VpnLockdown.setFor(_goneNetwork, false);
        _olderSaveAnswersLate();
    }

    // Two saves of one profile: "Save and reconnect" with the kill switch on (its answer
    // waits for the reconnect), then a plain Save with it off and another VPN, answered at
    // once (no change to the profile itself). The older answer, coming last, writes nothing:
    // the newer choice stays.
    readonly property string _raceNetwork: "a4-network-race"
    property int _raceAnswers: 0
    property Timer _raceWait: Timer {
        interval: 25
        repeat: true
        onTriggered: suite._checkRace()
    }

    function _olderSaveAnswersLate() {
        NetworkProfiles.saved.connect(_countRace);
        const original = { name: "Race" };
        NetworkProfiles.saveConnection({ uuid: _raceNetwork, changes: [], original: original, reconnect: true,
                                         vpns: ["a4test:older"], lockdown: true });
        assert(NetworkProfiles.savesReconnecting.includes(_raceNetwork), "two saves: the reconnecting one is known (plain Save waits for it)");
        NetworkProfiles.saveConnection({ uuid: _raceNetwork, changes: [], original: original, reconnect: false,
                                         vpns: ["a4test:newer"], lockdown: false });
        assertEqual(_raceAnswers, 1, "two saves: the plain one answered at once");
        _saveStarted = Date.now();
        _raceWait.start();
    }

    function _countRace(uuid, ok) {
        if (uuid === _raceNetwork)
            _raceAnswers++;
    }

    function _checkRace() {
        if (_raceAnswers < 2 && Date.now() - _saveStarted < 15000)
            return;
        _raceWait.stop();
        NetworkProfiles.saved.disconnect(_countRace);
        assertEqual(_raceAnswers, 2, "two saves: both answered");
        assertEqual(JSON.stringify(VpnManager.vpnsWith(_raceNetwork)), JSON.stringify(["a4test:newer"]),
                    "two saves: the older one answering last does not overwrite the newer VPN link");
        assert(!VpnLockdown.isSetFor(_raceNetwork), "two saves: … nor the newer kill-switch choice");
        assert(!NetworkProfiles.savesReconnecting.includes(_raceNetwork), "two saves: none reconnecting any more");

        // "Keep these settings?" put back: the links of before, unless a newer save came since
        const newest = NetworkProfiles._saveNumbers[_raceNetwork];
        NetworkProfiles._restoreLinks(_raceNetwork, { number: newest - 1, vpns: ["a4test:older"], lockdown: true });
        assert(VpnManager.vpnsWith(_raceNetwork).includes("a4test:newer") && !VpnLockdown.isSetFor(_raceNetwork),
               "settings put back: a newer save came since — its links kept");
        NetworkProfiles._restoreLinks(_raceNetwork, { number: newest, vpns: ["a4test:before"], lockdown: true });
        assert(VpnManager.vpnsWith(_raceNetwork).includes("a4test:before") && VpnLockdown.isSetFor(_raceNetwork),
               "settings put back: the links and the kill switch of before with them");
        VpnManager.setVpnsWith(_raceNetwork, []);
        VpnLockdown.setFor(_raceNetwork, false);
        Notifier.recordOnly = _savedRecordOnly;
        _globalsPin.restore();
        finish();
    }
}
