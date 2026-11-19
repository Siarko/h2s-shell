import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.network

// The reading behind IpManager's devices (singletons/network/DeviceAddressReading.qml), run
// for real against stand-ins for nmcli and ip (tests/fixtures/device-address-reading, linked
// into a scratch directory whose files they print): the devices and their IPv6 flags read,
// a reading superseded while its flags step runs, and a reading that fails. Never the real
// nmcli or ip: the programs are the stand-ins' paths from the moment the reading is made.
// Asynchronous: each step is a process.
TestCase {
    id: suite
    suiteName: "DeviceAddressReading"
    asynchronous: true

    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/device-address-reading"
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-device-address-reading-test-" + Date.now()

    property var _reading: null
    property bool _written: false
    property bool _released: false
    // What the reading published, in order, from the moment a step starts recording
    property var _published: []

    property Component _readingComponent: Component {
        DeviceAddressReading {}
    }

    // ---- A tiny scheduler: each step waits for its condition (or its deadline), then runs ----
    property var _steps: []

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite._end();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {}
            if (!ready && waited < 10000)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    function _end() {
        _reading?.destroy();
        _sh("rm -rf \"$1\"", [_scratch], () => suite.finish());
    }

    function _device(name) {
        return (_reading?.devices ?? []).find(device => device.device === name) ?? null;
    }

    function _make(nmcli, ip) {
        const reading = _readingComponent.createObject(suite, { nmcli: nmcli, ip: ip });
        reading.devicesChanged.connect(() => suite._published = suite._published.concat([reading.devices.map(device => device.device).join(",")]));
        return reading;
    }

    function runAsync() {
        _then("the stand-ins are in place", () => _written, () => {
            _reading = _make(_scratch + "/nmcli", _scratch + "/ip");
            _reading.read();
        });
        _then("the first reading came", () => _reading.devicesRead, () => {
            assertEqual(_reading.devices.map(device => device.device + ":" + device.kind).join(" "), "wlan0:wifi enp5s0:ethernet lo:loopback",
                        "every device of nmcli's answer, with its kind");
            assertEqual(JSON.stringify(_device("wlan0")?.ipv4), JSON.stringify(["192.168.1.23/24"]), "… a device's IPv4 address, with its prefix");
            assertEqual(_device("wlan0")?.ipv6?.length, 3, "… its IPv6 addresses, each");
            assertEqual(_device("wlan0")?.ipIface, "wlan0", "… the interface its IP runs on");
            assertEqual(JSON.stringify(_device("enp5s0")?.ipv4), "[]", "… none for an unplugged port");
            const flags = _reading.ipv6Flags ?? {};
            assertEqual(JSON.stringify(flags["wlan0 2001:db8:1:0:5c3a:9e1f:24b7:1d02"]), JSON.stringify({ temporary: true, deprecated: false }),
                        "the IPv6 flags read after the devices: a privacy address is temporary");
            assertEqual(JSON.stringify(flags["wlan0 2001:db8:1::a4f1"]), JSON.stringify({ temporary: false, deprecated: false }),
                        "… the stable one is not");
            // The flags step held while a newer reading's devices step is still running
            _sh("set -e; : > \"$1/ip-wait\"; cp \"$2/devices-office\" \"$1/devices\"", [_scratch, _fixtures], () => _reading.read());
        });
        _then("a second reading waits in its flags step", () => _reading._flagsQuery.running, () => {
            _sh("set -e; : > \"$1/nmcli-wait\"; cp \"$2/devices-cafe\" \"$1/devices\"", [_scratch, _fixtures], () => {
                suite._published = [];
                suite._reading.read();
                suite._sh("rm \"$1/ip-wait\"", [suite._scratch], () => suite._released = true);
            });
        });
        _then("the second reading's flags answered while a third reads the devices",
              () => _released && !_reading._flagsQuery.running && _reading._devicesQuery.running, () => {
            assertEqual(JSON.stringify(_published), "[]", "a superseded reading publishes nothing: its devices are older than the newest read()");
            assertEqual(_device("wlan0")?.ipv4?.[0], "192.168.1.23/24", "… the devices published before stay");
            _sh("rm \"$1/nmcli-wait\"", [_scratch], () => {});
        });
        _then("the third reading came", () => _device("wlan0")?.ipv4?.[0] === "172.16.5.9/22"
              && !_reading._devicesQuery.running && !_reading._flagsQuery.running, () => {
            assertEqual(JSON.stringify(_published), JSON.stringify(["wlan0"]), "the newest reading is the one published, once");
            assert(_reading.devicesRead, "… read");
            _reading.destroy();
            // A reading that cannot run nmcli: not read, no devices — unknown, never "none"
            _reading = _make(_scratch + "/no-nmcli", _scratch + "/ip");
            _reading.read();
        });
        _then("the failing reading answered", () => _reading._devicesProblem !== "", () => {
            assert(!_reading.devicesRead, "nmcli that cannot be run: not read");
            assertEqual(JSON.stringify(_reading.devices), "[]", "… no devices");
        });
        _clock.start();
        _sh("set -e; mkdir -p \"$1\"; ln -s \"$2/nmcli\" \"$2/ip\" \"$1/\"; cp \"$2/ip.json\" \"$1/\"; cp \"$2/devices-home\" \"$1/devices\"",
            [_scratch, _fixtures], code => {
                suite.assertEqual(code, 0, "the stand-ins are linked into a scratch directory");
                suite._written = true;
            });
    }

    function _sh(script, args, done) {
        const process = _shell.createObject(suite, { command: ["sh", "-c", script, "sh"].concat(args), done: done });
        process.running = true;
    }

    property Component _shell: Component {
        Process {
            id: _process
            property var done: null
            property string output: ""
            stdout: SplitParser {
                splitMarker: ""
                onRead: data => _process.output += data
            }
            onExited: code => {
                _process.done?.(code, _process.output);
                _process.destroy();
            }
        }
    }
}
