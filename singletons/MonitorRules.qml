pragma Singleton

import Quickshell
import QtQuick

// Which monitor is which, and what the compositor says of its power — pure, so
// tests/MonitorRulesTest.qml checks every case without a compositor. `ScreenPower` (I/O)
// reads the monitors and hands the answers here.
//
// A monitor's id is `make|model|serial`, never its connector: a cable moved to another
// port keeps the monitor's settings. The id is also the key of its override in the
// `monitorBlanking` setting ({ id: way }). Two connected monitors with one id — twins with
// no serial, or with the same placeholder serial — are told apart by their connector
// (`make|model|serial|connector`), and reported, so a view can say why.
Singleton {
    id: root

    // Connectors of a laptop's own panel
    readonly property var builtInPrefixes: Object.freeze(["eDP-", "LVDS-", "DSI-"])

    // The backend that turns monitors off, from what the environment offers:
    // { hyprland: bool } → "hyprland" | "none"
    function backend(environment) {
        return environment?.hyprland === true ? "hyprland" : "none";
    }

    // A connector name as Hyprland gives it ("DP-2", "HDMI-A-1", "eDP-1"): the only names
    // ever put into a dispatch, which is a Lua expression
    function validConnector(connector) {
        return typeof connector === "string" && /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/.test(connector);
    }

    function isBuiltIn(connector) {
        const name = String(connector ?? "");
        return builtInPrefixes.some(prefix => name.startsWith(prefix));
    }

    // An id's field: text from outside the shell, on one line, without the separator,
    // length-capped
    function _field(value) {
        if (typeof value !== "string")
            return "";
        return value.replace(/[\u0000-\u001f\u007f|]/g, " ").replace(/\s+/g, " ").trim().slice(0, 80);
    }

    // The id of one monitor { make, model, serial }, before twins are told apart:
    // "Samsung Electric Company|C27JG5x|H4ZMC00268"; "make|model|" without a serial
    function identity(monitor) {
        return _field(monitor?.make) + "|" + _field(monitor?.model) + "|" + _field(monitor?.serial);
    }

    // Every connected monitor's id ([{ connector, make, model, serial }]) →
    // { ids: { connector: id }, twins: [identity…] } — `twins` the identities that two or
    // more monitors shared, each listed once, in the order first met. A twin's id takes its
    // connector, whatever the order the monitors came in.
    function identities(monitors) {
        const counts = {};
        const order = [];
        for (const monitor of monitors ?? []) {
            const base = identity(monitor);
            if (counts[base] === undefined) {
                counts[base] = 0;
                order.push(base);
            }
            counts[base] += 1;
        }
        const ids = {};
        for (const monitor of monitors ?? []) {
            const base = identity(monitor);
            ids[monitor.connector] = counts[base] > 1 ? base + "|" + monitor.connector : base;
        }
        return { ids: ids, twins: order.filter(base => counts[base] > 1) };
    }

    // Hyprland's `dpmsStatus` → "on" | "off" | "unknown": only a boolean is an answer
    function power(dpmsStatus) {
        return dpmsStatus === true ? "on" : dpmsStatus === false ? "off" : "unknown";
    }

    // `hyprctl -j monitors` → { monitors: [{ connector, id, make, model, serial, builtIn,
    // power }], twins } or null when the text is not such an answer (not JSON, not a list).
    // Disabled outputs and mirrors are left out: neither is a screen of its own. An entry
    // without a usable connector is left out too: nothing could be asked of it.
    function hyprlandMonitors(text) {
        let parsed;
        try {
            parsed = JSON.parse(String(text ?? ""));
        } catch (error) {
            return null;
        }
        if (!Array.isArray(parsed))
            return null;
        const seen = {};
        const kept = [];
        for (const entry of parsed) {
            if (entry === null || typeof entry !== "object" || !validConnector(entry.name) || seen[entry.name])
                continue;
            if (entry.disabled === true)
                continue;
            if (typeof entry.mirrorOf === "string" && entry.mirrorOf !== "" && entry.mirrorOf !== "none")
                continue;
            seen[entry.name] = true;
            kept.push({
                connector: entry.name,
                make: _field(entry.make),
                model: _field(entry.model),
                serial: _field(entry.serial),
                builtIn: isBuiltIn(entry.name),
                power: power(entry.dpmsStatus)
            });
        }
        const named = identities(kept);
        return {
            monitors: kept.map(monitor => Object.assign({ id: named.ids[monitor.connector] }, monitor)),
            twins: named.twins
        };
    }

    // The monitors as last read, after a reading that failed: still listed, their power
    // unknown — a monitor is never taken to be off when that could not be read
    function unknownPower(monitors) {
        return (monitors ?? []).map(monitor => Object.assign({}, monitor, { power: "unknown" }));
    }

    // The Hyprland dispatch that turns one monitor off or on, or "" when the connector is
    // not one to put into it. Hyprland turns every monitor off for a name it does not know,
    // so the caller asks only for a connector of its last reading.
    function hyprlandDpms(connector, on) {
        if (!validConnector(connector))
            return "";
        return "hl.dsp.dpms({ action = \"" + (on === true ? "enable" : "disable") + "\", monitor = \"" + connector + "\" })";
    }

    // What `hyprctl -j monitors` answered, as far as the run goes (CommandRunner's result)
    // → "" when it ran and said everything, else the problem
    function readProblem(result) {
        if (result === null || typeof result !== "object")
            return "hyprctl gave no answer";
        if (result.failedToStart === true)
            return "hyprctl could not be started";
        if (result.timedOut === true)
            return "hyprctl did not answer";
        if (result.truncated === true)
            return "too much output from hyprctl";
        if (result.ok === true)
            return "";
        return "hyprctl failed (" + result.code + ")" + _said(result.stderr);
    }

    // The first line of what a command said, for a log line
    function _said(text) {
        const first = String(text ?? "").trim().split("\n")[0].replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, 200);
        return first !== "" ? ": " + first : "";
    }

    // What `hyprctl dispatch` answered → "" when it worked, else the problem. The result is
    // CommandRunner's; a dispatch that worked prints "ok".
    function dispatchProblem(result) {
        if (result === null || typeof result !== "object")
            return "hyprctl gave no answer";
        if (result.failedToStart === true)
            return "hyprctl could not be started";
        if (result.timedOut === true)
            return "hyprctl did not answer";
        const output = String(result.stdout ?? "").trim();
        if (result.ok === true && output === "ok")
            return "";
        return "hyprctl dispatch failed" + (result.ok === true ? "" : " (" + result.code + ")")
            + _said(output !== "" ? output : result.stderr);
    }

    // The way an id's override names in `monitorBlanking`, or "" when it has none (or the
    // map is not one)
    function overrideFor(monitorBlanking, id) {
        if (monitorBlanking === null || typeof monitorBlanking !== "object" || Array.isArray(monitorBlanking))
            return "";
        const way = monitorBlanking[id];
        return typeof way === "string" ? way : "";
    }

    // The ids of overrides whose monitors are not connected, sorted: kept, and listed to be
    // forgotten
    function notConnected(monitorBlanking, connectedIds) {
        if (monitorBlanking === null || typeof monitorBlanking !== "object" || Array.isArray(monitorBlanking))
            return [];
        const connected = connectedIds ?? [];
        return Object.keys(monitorBlanking).filter(id => !connected.includes(id)).sort();
    }
}
