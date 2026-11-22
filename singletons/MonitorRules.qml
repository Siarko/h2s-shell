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
// (`make|model|serial|connector`), and reported, so a view can say why. An identity once
// seen as twins keeps the connector while the shell runs, so a twin left alone keeps its id;
// an override is found under either form (overrideFor). Off Hyprland, wlopm names outputs
// only: the model and serial are Qt's for that screen, the make empty (wlopmMonitors).
Singleton {
    id: root

    // Connectors of a laptop's own panel
    readonly property var builtInPrefixes: Object.freeze(["eDP-", "LVDS-", "DSI-"])

    // The backend that turns monitors off, from what the environment offers:
    // { hyprland: bool, wlopm: bool } → "hyprland" | "wlopm" | "none" — Hyprland's own
    // dispatch where it runs, else `wlopm` once it is found on PATH (`wlopm: true`; not yet
    // known is not found)
    function backend(environment) {
        if (environment?.hyprland === true)
            return "hyprland";
        return environment?.wlopm === true ? "wlopm" : "none";
    }

    // Why monitors cannot be turned off, for the page: { reason, hint }, both "" when they can
    function unavailable(backendName) {
        if (backendName === "hyprland" || backendName === "wlopm")
            return { reason: "", hint: "" };
        return { reason: "Not supported here", hint: "Install wlopm to turn monitors off" };
    }

    // A connector name as Hyprland gives it ("DP-2", "HDMI-A-1", "eDP-1"): the only names
    // ever put into a dispatch, which is a Lua expression
    function validConnector(connector) {
        return typeof connector === "string" && /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/.test(connector);
    }

    // An id as this file makes them, given from outside (an IPC, a settings file):
    // `make|model|serial` or a twin's `make|model|serial|connector`, each field without
    // control characters and at most 80 long (empty fields allowed: a panel may report none),
    // the connector a valid one. A bare connector name or an object key like `__proto__` is
    // no id
    function validId(id) {
        if (typeof id !== "string" || /[\u0000-\u001f\u007f]/.test(id))
            return false;
        const fields = id.split("|");
        if (fields.length !== 3 && fields.length !== 4)
            return false;
        if (fields.some(field => field.length > 80))
            return false;
        return fields.length === 3 || validConnector(fields[3]);
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
    // more monitors share, or that `knownTwins` names (seen as twins before), each listed
    // once, in the order first met. A twin's id takes its connector, whatever the order the
    // monitors came in.
    function identities(monitors, knownTwins) {
        const known = Array.isArray(knownTwins) ? knownTwins : [];
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
            ids[monitor.connector] = counts[base] > 1 || known.includes(base) ? base + "|" + monitor.connector : base;
        }
        return { ids: ids, twins: order.filter(base => counts[base] > 1 || known.includes(base)) };
    }

    // Hyprland's `dpmsStatus` → "on" | "off" | "unknown": only a boolean is an answer
    function power(dpmsStatus) {
        return dpmsStatus === true ? "on" : dpmsStatus === false ? "off" : "unknown";
    }

    // `hyprctl -j monitors` → { monitors: [{ connector, id, base, make, model, serial,
    // builtIn, power }], twins } (`base`: the identity before twins are told apart;
    // `knownTwins` as identities takes it) or null when the text is not such an answer (not JSON, not a list).
    // Disabled outputs and mirrors are left out: neither is a screen of its own. An entry
    // without a usable connector is left out too: nothing could be asked of it.
    function hyprlandMonitors(text, knownTwins) {
        let parsed;
        try {
            parsed = JSON.parse(String(text ?? ""));
        } catch (error) {
            return null;
        }
        if (!Array.isArray(parsed))
            return null;
        const seen = Object.create(null);
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
        return _named(kept, knownTwins);
    }

    // Monitors read ([{ connector, make, model, serial, builtIn, power }]) with their ids
    function _named(kept, knownTwins) {
        const named = identities(kept, knownTwins);
        return {
            monitors: kept.map(monitor => Object.assign({ id: named.ids[monitor.connector], base: identity(monitor) }, monitor)),
            twins: named.twins
        };
    }

    // wlopm's `power-mode` → "on" | "off" | "unknown"
    function wlopmPower(mode) {
        return mode === "on" ? "on" : mode === "off" ? "off" : "unknown";
    }

    // `wlopm --json` ([{ "output": "<connector>", "power-mode": "on" | "off" }], an entry
    // with "error" when its power could not be read) and the screens Qt knows
    // ([{ name, model, serialNumber }]) → the same as hyprlandMonitors, or null when the text
    // is not such an answer. wlopm gives connector names only: the model and serial come
    // from the screen of that name (Qt has no make), so an id is `|model|serial`, and twins
    // — two of one model without a serial, as Qt reports on Wayland — take their connector.
    // An entry without a usable connector is left out: nothing could be asked of it.
    function wlopmMonitors(text, screens, knownTwins) {
        let parsed;
        try {
            parsed = JSON.parse(String(text ?? ""));
        } catch (error) {
            return null;
        }
        if (!Array.isArray(parsed))
            return null;
        // No prototype: a connector named like an object key ("constructor") is a name only
        const byName = Object.create(null);
        for (const screen of Array.isArray(screens) ? screens : []) {
            if (screen !== null && typeof screen === "object" && validConnector(screen.name) && byName[screen.name] === undefined)
                byName[screen.name] = screen;
        }
        const seen = Object.create(null);
        const kept = [];
        for (const entry of parsed) {
            if (entry === null || typeof entry !== "object" || !validConnector(entry.output) || seen[entry.output])
                continue;
            seen[entry.output] = true;
            const screen = byName[entry.output] ?? null;
            kept.push({
                connector: entry.output,
                make: "",
                model: _field(screen?.model),
                serial: _field(screen?.serialNumber),
                builtIn: isBuiltIn(entry.output),
                power: entry.error !== undefined ? "unknown" : wlopmPower(entry["power-mode"])
            });
        }
        return _named(kept, knownTwins);
    }

    // The wlopm command that turns one monitor off or on, as argv, or [] when the connector
    // is not one to name: wlopm takes `*` for every output, so the caller asks only for a
    // connector of its last reading, and nothing else reaches the command
    function wlopmCommand(program, connector, on) {
        if (typeof program !== "string" || program === "" || !validConnector(connector))
            return [];
        return [program, on === true ? "--on" : "--off", connector];
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

    // What the reading (`hyprctl -j monitors`, `wlopm --json`: `program`, hyprctl when not
    // given) answered, as far as the run goes (CommandRunner's result) → "" when it ran and
    // said everything, else the problem
    function readProblem(result, program) {
        const name = program ?? "hyprctl";
        if (result === null || typeof result !== "object")
            return name + " gave no answer";
        if (result.failedToStart === true)
            return name + " could not be started";
        if (result.timedOut === true)
            return name + " did not answer";
        if (result.truncated === true)
            return "too much output from " + name;
        if (result.ok === true)
            return "";
        return name + " failed (" + result.code + ")" + _said(result.stderr);
    }

    // The first line of what a command said, for a log line
    function _said(text) {
        const first = String(text ?? "").trim().split("\n")[0].replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, 200);
        return first !== "" ? ": " + first : "";
    }

    // What `hyprctl dispatch` answered → "" when the run went through, else the problem.
    // The result is CommandRunner's. Hyprland prints "ok" even for an action it did not
    // take, so the run is all this says: whether the monitor changed is the next reading's
    // (actionProblem).
    // `program`, "hyprctl dispatch" when not given, names the command (wlopm's is "wlopm").
    function dispatchProblem(result, program) {
        const name = program ?? "hyprctl dispatch";
        const tool = name.split(" ")[0];
        if (result === null || typeof result !== "object")
            return tool + " gave no answer";
        if (result.failedToStart === true)
            return tool + " could not be started";
        if (result.timedOut === true)
            return tool + " did not answer";
        if (result.ok === true)
            return "";
        const output = String(result.stdout ?? "").trim();
        return name + " failed (" + result.code + ")" + _said(output !== "" ? output : result.stderr);
    }

    // After an action: the reading that followed it ([{ id, power }], or null when it failed)
    // → "" when the monitor's power is the one asked, else the problem
    function actionProblem(monitors, id, on) {
        if (!Array.isArray(monitors))
            return "the monitors could not be read after it";
        const monitor = monitors.find(entry => entry.id === id);
        if (!monitor)
            return "the monitor is gone";
        const wanted = on === true ? "on" : "off";
        if (monitor.power === wanted)
            return "";
        return monitor.power === "unknown" ? "its power could not be read" : "it is still " + monitor.power;
    }

    // Monitors an action turned off by mistake: on in the reading before it, off in the one
    // after, and not the one it was for → their connectors, each also in the reading after
    function turnedOffBesides(before, after, targetConnector) {
        if (!Array.isArray(before) || !Array.isArray(after))
            return [];
        return after.filter(monitor => monitor.power === "off" && monitor.connector !== targetConnector
                            && before.some(earlier => earlier.connector === monitor.connector && earlier.power === "on"))
            .map(monitor => monitor.connector);
    }

    function _isMap(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    // The keys an override of this monitor may be kept under, first the one it is saved
    // under: its id, then the other form — a twin's `base|connector` and the plain `base`
    // name one monitor, whichever it was when the override was set. A plain id string has
    // only itself.
    function overrideKeys(monitor) {
        if (typeof monitor === "string")
            return [monitor];
        const id = String(monitor?.id ?? "");
        const base = String(monitor?.base ?? id);
        const connector = String(monitor?.connector ?? "");
        const keys = [id];
        const other = id !== base ? base : connector !== "" ? base + "|" + connector : "";
        if (other !== "" && other !== id)
            keys.push(other);
        return keys;
    }

    // The way a monitor's override names in `monitorBlanking`, or "" when it has none (or
    // the map is not one). `monitor`: { id, base, connector } as read, or an id
    function overrideFor(monitorBlanking, monitor) {
        if (!_isMap(monitorBlanking))
            return "";
        for (const key of overrideKeys(monitor)) {
            const way = monitorBlanking[key];
            if (typeof way === "string")
                return way;
        }
        return "";
    }

    // The keys of overrides no connected monitor uses, sorted: kept, and listed to be
    // forgotten. `monitors`: the connected ones, as read ({ id, base, connector }) or ids
    function notConnected(monitorBlanking, monitors) {
        if (!_isMap(monitorBlanking))
            return [];
        const used = [];
        for (const monitor of monitors ?? [])
            used.push(...overrideKeys(monitor));
        return Object.keys(monitorBlanking).filter(key => !used.includes(key)).sort();
    }
}
