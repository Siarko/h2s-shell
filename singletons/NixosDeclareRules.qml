pragma Singleton

import Quickshell
import QtQuick

// A setting the shell keeps in its file in the system's NixOS configuration (IntegrationRules'
// mode "declare"; distributions/nixos/NixosDeclare.qml does the I/O; tests/NixosDeclareTest.qml):
// what is in force for it, read from the configuration's reading (NixosConfigRules.reading:
// /etc/h2s-shell/settings.json as published by the running system), and the candidate an
// Apply hands the rebuild — the shell's file with that one key changed. Pure.
//
// The configuration may set the same thing itself, past the shell's option (the system's
// own systemd option): its line wins (the NixOS module defines the shell's value below it)
// and the shell shows it, never offering to apply over it. The published file says which
// won: `settings` holds the file's value as taken in, `system` what the system's option
// merged to; when they differ, or the file gives none, the setting is the configuration's own.
Singleton {
    id: root

    // The key's path in the shell's file (the module's option path under programs.h2s-shell)
    readonly property var paths: ({ "sleep.hibernateDelay": ["idle", "hibernateDelay"] })

    readonly property var texts: ({
        notConnected: "The shell's file is not in your NixOS configuration yet.",
        file: "The shell's file could not be read.",
        value: "Not a value for this setting.",
        unavailable: "Not supported on this distribution.",
        noFlow: "Open Settings to apply it."
    })

    function refusal(code) {
        return { code, text: texts[code] ?? texts.value };
    }

    // A delay as the module takes it (seconds, or a systemd time span) → whole seconds, or null
    function seconds(value) {
        if (typeof value === "number")
            return Number.isInteger(value) && value > 0 ? value : null;
        return typeof value === "string" ? HibernateRules.timeSpan(value) : null;
    }

    function _at(object, path) {
        let value = object;
        for (const name of path) {
            if (value === null || typeof value !== "object" || Array.isArray(value) || !Object.prototype.hasOwnProperty.call(value, name))
                return undefined;
            value = value[name];
        }
        return value;
    }

    // What is in force for `kind` by a configuration's reading → IntegrationRules' readInForce
    // answer: the shell's own file in force (`from` its path), the configuration's own setting
    // (`from` and `elsewhere` the configuration's folder; `afterOwn`: the shell cannot win over
    // it), systemd's default (none set), or unknown (not connected, or a module that does not
    // publish what the system merged)
    function inForce(reading, kind) {
        const unknown = IntegrationRules.inForceUnknown();
        const path = Object.prototype.hasOwnProperty.call(paths, kind) ? paths[kind] : null;
        if (path === null || reading?.state !== "connected")
            return unknown;
        const published = reading.publishedSettings;
        const merged = _at(published?.system, path);
        if (merged === undefined)
            return unknown;
        if (merged === null)
            return Object.assign(unknown, { state: "default" });
        const value = seconds(merged);
        if (value === null)
            return unknown;
        const fileValue = seconds(_at(published?.settings, path));
        if (fileValue === value)
            return Object.assign(unknown, { state: "set", value, from: String(reading.file?.path ?? "") });
        const folder = String(reading.configuration?.folder ?? "");
        return Object.assign(unknown, { state: "set", value, from: folder, elsewhere: folder, afterOwn: folder !== "" });
    }

    // The shell's file with `kind` set to `value` → { request (NixosRebuild.announce's: key,
    // value, text, reading, previous { value, text }), refusal (null, or { code, text }) }.
    // The file keeps its other keys and their order; the value goes in as the module takes it
    function request(reading, kind, value) {
        const path = Object.prototype.hasOwnProperty.call(paths, kind) ? paths[kind] : null;
        if (path === null)
            return { request: null, refusal: refusal("unavailable") };
        if (!IntegrationRules.validValue(kind, value))
            return { request: null, refusal: refusal("value") };
        if (reading?.state !== "connected")
            return { request: null, refusal: refusal("notConnected") };
        if (reading.file?.state !== "present" || typeof reading.file.text !== "string")
            return { request: null, refusal: refusal("file") };
        let file;
        try {
            file = JSON.parse(reading.file.text);
        } catch (error) {
            file = null;
        }
        if (file === null || typeof file !== "object" || Array.isArray(file))
            return { request: null, refusal: refusal("file") };
        const before = _at(file, path);
        const changed = JSON.parse(JSON.stringify(file));
        let node = changed;
        for (const name of path.slice(0, -1)) {
            if (node[name] === undefined)
                node[name] = {};
            if (node[name] === null || typeof node[name] !== "object" || Array.isArray(node[name]))
                return { request: null, refusal: refusal("file") };
            node = node[name];
        }
        node[path[path.length - 1]] = value;
        return {
            request: { key: kind, value, text: JSON.stringify(changed, null, 2) + "\n", reading,
                       previous: { value: before === undefined ? null : before, text: reading.file.text } },
            refusal: null
        };
    }
}
