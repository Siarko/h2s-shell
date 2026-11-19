import QtQuick
import qs.singletons
import qs.singletons.io

// Every device's addresses, for Api.localNetworks (the shell's one instance is IpManager's):
// a reading is the devices (`nmcli device show`), then their IPv6 addresses' flags
// (`ip -j -6 address show`). read() while a reading runs drops the answer under way and
// starts again (LatestQuery), so what is published is always from a reading started after
// the last read(). The programs are properties, so a suite points them at stand-ins
// (tests/DeviceAddressReadingTest.qml).
QtObject {
    id: root

    property string nmcli: "nmcli"
    property string ip: "ip"

    // Nmcli.devices: { device, ipIface, type, kind, ipv4 [], ipv6 [] }, the addresses with
    // their prefix; [] while not read
    property var devices: []
    // The last reading worked: a failed one (no nmcli, NetworkManager not running) leaves
    // `devices` empty and this false — unknown, never "no network"
    property bool devicesRead: false
    // The IPv6 addresses' flags (NetworkRules.ipv6AddressFlags), read after the devices, or
    // null when `ip` could not tell them: every global address is kept then
    property var ipv6Flags: null

    function read() {
        _devicesQuery.command = [nmcli, "-t", "-f", NetworkRules.deviceAddressFields(_rejectedFields).join(","), "device", "show"];
        _devicesQuery.request();
    }

    property var _rejectedFields: []
    property var _pendingDevices: []
    property string _devicesProblem: ""
    property string _flagsProblem: ""

    // Properties rather than ids, so a suite can see whether a step is running
    property LatestQuery _devicesQuery: LatestQuery {
        timeoutMs: 15000
        onAnswered: (lines, result) => {
            const problem = NetworkRules.readProblem(result, "nmcli");
            const refused = problem === "" ? "" : NetworkRules.rejectedField(result.stderr);
            if (refused !== "" && NetworkRules.deviceAddressOptionalFields.includes(refused) && !root._rejectedFields.includes(refused)) {
                console.warn("IpManager: this nmcli does not know " + refused + ": the devices are read without it");
                root._rejectedFields = root._rejectedFields.concat([refused]);
                root.read();
                return;
            }
            // Logged when the outcome changes, not on every reading
            if (problem !== root._devicesProblem)
                console.warn("IpManager: the devices' addresses " + (problem === "" ? "are read again" : "could not be read: " + problem));
            root._devicesProblem = problem;
            if (problem !== "") {
                root.devices = [];
                root.devicesRead = false;
                return;
            }
            root._pendingDevices = Nmcli.devices(lines);
            root._flagsQuery.request();
        }
    }

    property LatestQuery _flagsQuery: LatestQuery {
        command: [root.ip, "-j", "-6", "address", "show"]
        timeoutMs: 15000
        onAnswered: (lines, result) => {
            // A newer reading of the devices is under way: it asks for the flags again
            if (root._devicesQuery.running)
                return;
            const problem = NetworkRules.readProblem(result, "ip");
            const flags = problem === "" ? NetworkRules.ipv6AddressFlags(lines.join("\n")) : null;
            const flagsProblem = problem !== "" ? problem : flags === null ? "ip gave no readable answer" : "";
            if (flagsProblem !== root._flagsProblem)
                console.warn("IpManager: the IPv6 addresses' flags " + (flagsProblem === "" ? "are read again" : "could not be read, every address kept: " + flagsProblem));
            root._flagsProblem = flagsProblem;
            root.ipv6Flags = flags;
            root.devices = root._pendingDevices;
            root.devicesRead = true;
        }
    }
}
