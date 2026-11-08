pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The battery's history as UPower records it — the charge in percent and the power drawn
// in watts, with the state at each point (charging or not) — for the battery popup's
// graph (docs/plans/battery-popup.md, stage 2). UPower keeps it across restarts and
// serves it over D-Bus without root (GetHistory); Quickshell does not expose it, so it is
// asked with busctl, the Process idiom of ARCHITECTURE.md. Fetched on refresh() — the
// popup asks while it is open — not polled.
Singleton {
    id: root

    // The laptop battery's UPower object path, found once ("" until then, or when none)
    property string devicePath: ""
    property bool _searched: false
    // [{ t, v, state }] oldest first (BatteryRules.parseHistory)
    property var charge: []
    property var rate: []
    // How far back, in seconds
    property int span: 24 * 3600

    readonly property bool available: devicePath !== ""

    function refresh() {
        if (!root._searched) {
            _enumerate.running = true;
            return;
        }
        if (!root.available)
            return;
        _charge.command = root._historyCommand("charge", 400);
        _rate.command = root._historyCommand("rate", 800);
        _charge.running = true;
        _rate.running = true;
    }

    onSpanChanged: refresh()

    function _historyCommand(kind, points) {
        return ["busctl", "--json=short", "call", "org.freedesktop.UPower", root.devicePath,
                "org.freedesktop.UPower.Device", "GetHistory", "suu", kind, String(root.span), String(points)];
    }

    component Call: Process {
        id: _call
        property string output: ""
        signal finished(string text)
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => _call.output += data
        }
        onRunningChanged: {
            if (running)
                return;
            finished(output);
            output = "";
        }
    }

    Call {
        id: _enumerate
        command: ["busctl", "--json=short", "call", "org.freedesktop.UPower", "/org/freedesktop/UPower",
                  "org.freedesktop.UPower", "EnumerateDevices"]
        onFinished: text => {
            root.devicePath = BatteryRules.laptopBatteryPath(text);
            root._searched = true;
            root.refresh();
        }
    }

    Call {
        id: _charge
        onFinished: text => { root.charge = BatteryRules.parseHistory(text); }
    }

    Call {
        id: _rate
        onFinished: text => { root.rate = BatteryRules.parseHistory(text); }
    }
}
