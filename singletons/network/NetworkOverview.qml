pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.io
import qs.singletons.network

// What System → Network → Overview shows and changes: NetworkManager's devices with their
// details, the radios, networking itself, the hostname, a global DNS and the connectivity
// check. Read only while a page shows it (watch/unwatch), and again
// when NetworkEvents reports a change. Changes go through CommandAction, one after another;
// one refused for want of rights goes to Authentication (the polkit prompt), another
// failure to a notification.
Singleton {
    id: root

    // Pages open that show this: kept fresh while there is one. A count, not a switch: a
    // page opening comes before the one it replaces is destroyed, and that one's "off"
    // used to stop the new page's updates
    property int _watchers: 0
    readonly property bool watching: _watchers > 0

    function watch(): void {
        _watchers++;
    }

    function unwatch(): void {
        _watchers = Math.max(0, _watchers - 1);
    }

    // Nmcli.devices — every device NetworkManager knows
    property var devices: []
    // The radios: hardware present and switched on (`nmcli radio all`); networking at all
    property bool wifiHardware: true
    property bool wifiEnabled: true
    property bool modemHardware: false
    property bool modemEnabled: false
    property bool networkingEnabled: true
    property string hostname: ""
    // A global DNS, overriding every connection's; empty: none
    property var globalDns: []
    property bool connectivityCheckAvailable: false
    property bool connectivityCheckEnabled: false
    // The address it fetches (NetworkManager's [connectivity] uri); "" when none is set —
    // then there is no check, and "online" is NetworkManager's guess from the routes
    property string connectivityCheckUri: ""
    // "full", "limited", "portal", "none", "unknown"
    property string connectivity: ""
    // The Wi-Fi access point in use: { rate (Mb/s), channel, frequency (MHz), signal, security }
    property var wifiLink: null

    readonly property bool busy: _action.busy

    // What polkit answers for each of NetworkManager's actions (`nmcli general
    // permissions`): { "org.freedesktop.NetworkManager.<action>": "yes" | "auth" | "no" }.
    // "auth" asks for an administrator's password: the page marks it (PrivilegedMark).
    property var permissions: ({})
    // NixOS keeps /etc declarative: written files there are outside the system's own
    // configuration, so the page offers the line for configuration.nix instead
    // (Distribution: false until it has answered, as until any check has)
    readonly property bool isNixos: Distribution.id === "nixos"

    // polkit's answer for one of NetworkManager's actions ("settings.modify.hostname")
    function need(action: string): string {
        return permissions["org.freedesktop.NetworkManager." + action] ?? "";
    }

    // Devices the Overview lists first: real links, and the interfaces of the VPNs up; the
    // rest (bridges, Docker's, loopback, Wi-Fi P2P) under "Other"
    readonly property var vpnProfiles: VpnManager.vpns
    readonly property var activeVpns: VpnManager.activeVpns
    // A VPN's device: its tunnel's interface (VpnManager.interfaceOf)
    function isVpnDevice(device): bool {
        return activeVpns.some(vpn => VpnManager.interfaceOf(vpn) !== "" && VpnManager.interfaceOf(vpn) === device.device);
    }
    readonly property var mainDevices: devices.filter(device =>
        (["wifi", "ethernet", "modem"].includes(device.kind) && device.state !== 10) || isVpnDevice(device))
    readonly property var otherDevices: devices.filter(device => !mainDevices.includes(device) && device.kind !== "loopback" && device.type !== "wifi-p2p")

    // One line per kind of connection, for the top of the Overview: { kind, label, text,
    // good (connected), shown }
    readonly property var summary: {
        const ofKind = kind => devices.filter(device => device.kind === kind && device.state !== 10);
        const wifi = ofKind("wifi");
        const wired = ofKind("ethernet");
        const modems = ofKind("modem");
        const connected = list => list.find(device => device.state === 100) ?? null;
        const wifiUp = connected(wifi);
        const wiredUp = connected(wired);
        const modemUp = connected(modems);
        return [
            { kind: "wifi", label: "Wi-Fi", shown: wifiHardware && wifi.length > 0, good: wifiUp !== null,
              text: !wifiEnabled ? "Off"
                  : NetworkProfiles.activeHotspot ? "Hotspot on: " + NetworkProfiles.activeHotspot.ssid
                  : wifiUp ? "Connected to " + wifiUp.connection : "Not connected" },
            { kind: "ethernet", label: "Ethernet", shown: wired.length > 0, good: wiredUp !== null,
              text: wiredUp ? "Connected" + (wiredUp.speed > 0 ? " · " + NetworkRules.speedText(wiredUp.speed) : "")
                  : wired.some(device => device.state === 20) ? "Cable unplugged" : "Not connected" },
            { kind: "vpn", label: "VPN", shown: true, good: activeVpns.length > 0,
              text: activeVpns.length > 0 ? activeVpns.map(profile => profile.name).join(", ")
                  : vpnProfiles.length > 0 ? "Off" : "None set up" },
            { kind: "modem", label: "Mobile broadband", shown: true, good: modemUp !== null,
              text: modems.length === 0 ? "No modem connected" : !modemEnabled ? "Off"
                  : modemUp ? "Connected to " + modemUp.connection : modems[0].stateText }
        ].filter(line => line.shown);
    }

    // Airplane: every radio off — Wi-Fi, mobile broadband, Bluetooth
    readonly property bool airplane: !wifiEnabled && (!modemHardware || !modemEnabled)
        && !(BluetoothPower.adapter?.enabled ?? false)

    function refresh(): void {
        _permissions.request();
        _devices.request();
        _radios.request();
        _networking.request();
        _hostname.request();
        _bus.request();
        _wifiAccessPoint.request();
        _connectivity.request();
    }

    onWatchingChanged: if (watching) refresh()

    Connections {
        target: NetworkEvents
        enabled: root.watching
        function onChanged() {
            root.refresh();
        }
    }

    // ── Reading ──
    CommandQuery {
        id: _permissions
        command: ["nmcli", "-t", "general", "permissions"]
        onDone: lines => {
            const answers = {};
            for (const line of lines) {
                const parts = Nmcli.splitTerse(line);
                if (parts.length >= 2)
                    answers[parts[0]] = parts[1];
            }
            root.permissions = answers;
        }
    }

    CommandQuery {
        id: _devices
        command: ["nmcli", "-t", "-f", "all", "device", "show"]
        onDone: lines => root.devices = Nmcli.devices(lines)
    }

    // "WIFI-HW:WIFI:WWAN-HW:WWAN", each enabled / disabled / missing
    CommandQuery {
        id: _radios
        command: ["nmcli", "-t", "radio", "all"]
        onDone: lines => {
            const parts = Nmcli.splitTerse(lines[0] ?? "");
            root.wifiHardware = parts[0] !== "missing";
            root.wifiEnabled = parts[1] === "enabled";
            root.modemHardware = parts[2] !== undefined && parts[2] !== "missing";
            root.modemEnabled = parts[3] === "enabled";
        }
    }

    CommandQuery {
        id: _networking
        command: ["nmcli", "networking"]
        onDone: lines => root.networkingEnabled = (lines[0] ?? "").trim() === "enabled"
    }

    CommandQuery {
        id: _connectivity
        command: ["nmcli", "networking", "connectivity"]
        onDone: lines => root.connectivity = (lines[0] ?? "").trim()
    }

    CommandQuery {
        id: _hostname
        command: ["nmcli", "general", "hostname"]
        onDone: lines => root.hostname = (lines[0] ?? "").trim()
    }

    // One line of JSON per property, in this order
    CommandQuery {
        id: _bus
        command: ["busctl", "--json=short", "get-property", "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
            "org.freedesktop.NetworkManager", "ConnectivityCheckAvailable", "ConnectivityCheckEnabled", "GlobalDnsConfiguration",
            "ConnectivityCheckUri"]
        onDone: lines => {
            try {
                root.connectivityCheckAvailable = JSON.parse(lines[0]).data === true;
                root.connectivityCheckEnabled = JSON.parse(lines[1]).data === true;
                root.globalDns = NetworkRules.globalDnsFrom(JSON.parse(lines[2]).data).servers;
                root.connectivityCheckUri = JSON.parse(lines[3]).data ?? "";
            } catch (error) {
                console.warn("NetworkOverview: cannot read NetworkManager's properties:", error);
            }
        }
    }

    CommandQuery {
        id: _wifiAccessPoint
        command: ["nmcli", "-t", "-f", "IN-USE,RATE,CHAN,FREQ,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "no"]
        onDone: lines => {
            const used = lines.map(line => Nmcli.splitTerse(line)).find(parts => parts[0] === "*");
            root.wifiLink = used ? {
                rate: parseInt(used[1]) || 0, channel: parseInt(used[2]) || 0,
                frequency: parseInt(used[3]) || 0, signal: parseInt(used[4]) || 0, security: used[5] ?? ""
            } : null;
        }
    }

    // ── A hotspot's devices ── the neighbours its interface heard from lately (`ip neigh`,
    // no rights needed; NetworkManager's lease file is root's), counted for a while after
    // they were last heard from: every 5 s while a page or the popup shows them and a
    // hotspot is on. No names — those are only in the lease file.
    readonly property string hotspotDevice: NetworkProfiles.activeHotspot?.device ?? ""
    property var hotspotClients: []
    // When each device was last heard from, by MAC (NetworkRules.hotspotClients)
    property var _clientsSeen: ({})
    // The network popup's hold on the devices, apart from watch(): it needs only them
    property int _clientHolders: 0

    function holdHotspotClients(): void {
        _clientHolders++;
    }

    function releaseHotspotClients(): void {
        _clientHolders = Math.max(0, _clientHolders - 1);
    }

    onHotspotDeviceChanged: {
        hotspotClients = [];
        _clientsSeen = {};
    }

    CommandQuery {
        id: _hotspotClients
        command: ["ip", "-j", "neigh", "show", "dev", root.hotspotDevice]
        onDone: lines => {
            if (root.hotspotDevice === "") {
                root.hotspotClients = [];
                return;
            }
            // An idle phone stays on for 5 minutes after it was last heard from
            const result = NetworkRules.hotspotClients(lines.join(""), root._clientsSeen, Date.now(), 300000);
            root._clientsSeen = result.seen;
            root.hotspotClients = result.clients;
        }
    }

    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: (root.watching || root._clientHolders > 0) && root.hotspotDevice !== ""
        onTriggered: _hotspotClients.request()
    }

    // ── Changing ──
    CommandAction {
        id: _action
    }

    // Runs `command`; on failure says so — `what` names the change ("Changing the hostname")
    function _change(what, command) {
        _action.run(command, result => {
            if (!result.ok) {
                if (Nmcli.errorKind(result.error) === "auth" || /not authorized|access denied|interactive authentication required/i.test(result.error))
                    Authentication.reportDenied(what);
                else
                    Notifier.send(what + " failed", { body: Nmcli.errorMessage(result.error) || ("Exit code " + result.code) });
            }
            root.refresh();
        });
    }

    function setWifi(on: bool): void {
        _change(on ? "Turning Wi-Fi on" : "Turning Wi-Fi off", ["nmcli", "radio", "wifi", on ? "on" : "off"]);
    }

    function setModem(on: bool): void {
        _change(on ? "Turning mobile broadband on" : "Turning mobile broadband off", ["nmcli", "radio", "wwan", on ? "on" : "off"]);
    }

    // Every connection down, or up again
    function setNetworking(on: bool): void {
        _change(on ? "Turning networking on" : "Turning networking off", ["nmcli", "networking", on ? "on" : "off"]);
    }

    // The radios as they were before airplane mode, to put back
    property var _beforeAirplane: null

    function setAirplane(on: bool): void {
        if (on) {
            _beforeAirplane = { wifi: wifiEnabled, modem: modemEnabled, bluetooth: BluetoothPower.adapter?.enabled ?? false };
            _change("Turning airplane mode on", ["nmcli", "radio", "all", "off"]);
            BluetoothPower.setEnabled(false);
            return;
        }
        const before = _beforeAirplane ?? { wifi: true, modem: true, bluetooth: true };
        _beforeAirplane = null;
        setWifi(before.wifi);
        if (modemHardware)
            setModem(before.modem);
        if (before.bluetooth)
            BluetoothPower.setEnabled(true);
    }

    // Asks for an administrator where polkit says so (the host: "auth")
    function setHostname(name: string): void {
        if (!NetworkRules.isHostname(name))
            return;
        _change("Changing the hostname", ["nmcli", "general", "hostname", name]);
    }

    // Servers for every domain, over each connection's; none clears it
    function setGlobalDns(servers): void {
        _change(servers.length > 0 ? "Setting the global DNS" : "Clearing the global DNS",
            ["busctl", "set-property", "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
             "org.freedesktop.NetworkManager", "GlobalDnsConfiguration"].concat(NetworkRules.globalDnsArguments(servers)));
    }

    // The connectivity check's address lives in NetworkManager's configuration, which only
    // root writes (the D-Bus property is read-only). One pkexec run — one password prompt —
    // writes our own file in conf.d (named to come after a distribution's, e.g. Arch's
    // 20-connectivity.conf) or removes it for the distribution's address, then has
    // NetworkManager read its configuration again. The address is checked first
    // (NetworkRules.isConnectivityUri) and handed in as an argument, never pasted into the
    // script. On NixOS this is a file outside the system's own configuration.
    readonly property string connectivityConfigFile: "/etc/NetworkManager/conf.d/90-h2s-connectivity.conf"

    function setConnectivityUri(uri: string): void {
        if (uri !== "" && !NetworkRules.isConnectivityUri(uri))
            return;
        const script = "set -e; mkdir -p \"$(dirname \"$2\")\";"
            + " if [ -n \"$1\" ]; then printf '%s\\n' '# Written by h2s-shell (Settings > System > Network)' '[connectivity]' \"uri=$1\" > \"$2\";"
            + " else rm -f \"$2\"; fi; nmcli general reload conf";
        const what = uri !== "" ? "Setting the connectivity check's address" : "Going back to the default connectivity check";
        _action.run(["pkexec", "sh", "-c", script, "sh", uri, connectivityConfigFile], result => {
            // pkexec: 126 cancelled or refused, 127 no agent answered
            if (result.code === 127)
                Authentication.reportDenied(what);
            else if (!result.ok && result.code !== 126)
                Notifier.send(what + " failed", { body: Nmcli.errorMessage(result.error) || ("Exit code " + result.code) });
            root.refresh();
        });
    }

    function setConnectivityCheck(on: bool): void {
        _change(on ? "Turning the connectivity check on" : "Turning the connectivity check off",
            ["busctl", "set-property", "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
             "org.freedesktop.NetworkManager", "ConnectivityCheckEnabled", "b", on ? "true" : "false"]);
    }
}
