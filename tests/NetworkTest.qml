import QtQuick
import qs.singletons
import qs.singletons.network

// Parsers for nmcli output and sysfs counters. Loading these singletons starts their
// usual nmcli polling; those results arrive after the synchronous assertions below.
TestCase {
    suiteName: "Network"

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
        {
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
        }

        // --- WifiManager._processSaved ---
        {
            WifiManager._processSaved([
                "Home\\:5G:802-11-wireless",
                "Wired connection 1:802-3-ethernet"
            ]);
            assertEqual(JSON.stringify(WifiManager.savedSsids), JSON.stringify(["Home:5G"]),
                "saved networks: wifi only, escaped colon kept");
        }

        // --- VpnManager._processVpn ---
        {
            VpnManager._processVpn([
                "work\\:vpn:wireguard:activated",
                "home:vpn:",
                "Wired connection 1:802-3-ethernet:activated"
            ]);
            assertEqual(VpnManager.vpnConnections.length, 2, "vpn: only VPN types are listed");
            assertEqual(VpnManager.vpnConnections[0].name, "work:vpn", "vpn: escaped colon in a name");
            assertEqual(VpnManager.activeVpn, "work:vpn", "vpn: active connection");
            assertEqual(VpnManager.activeVpnType, "wireguard", "vpn: active type");
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
            _link._update(1000, 500);
            assertEqual(_link.rxSpeed, 0, "link speed: the first read is only a baseline");
            _link._update(5000, 2500);
            assertEqual(_link.rxSpeed, 2000, "link speed: rx bytes per second");
            assertEqual(_link.txSpeed, 1000, "link speed: tx bytes per second");
            _link._update(100, 100);
            assert(_link.rxSpeed === 0 && _link.txSpeed === 0, "link speed: a counter reset never goes negative");
        }
    }
}
