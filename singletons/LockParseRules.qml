pragma Singleton

import Quickshell
import QtQuick

// The lock's rules, what comes in as text: the methods script's lines and logind's, read
// into what LockRules takes. Pure: text in, values out.
Singleton {
    id: root

    // The methods script's output (scripts/lock-auth-methods.sh): lines of
    // `<method> TAB <config directory> TAB <config name>`, as an array or one string.
    // → { method: { directory, config } }. Anything else on a line is junk and skipped; the
    // first line for a method wins.
    function parseMethods(lines) {
        const list = typeof lines === "string" ? lines.split("\n") : Array.isArray(lines) ? lines : [];
        const found = {};
        for (const line of list) {
            if (typeof line !== "string")
                continue;
            const fields = line.replace(/\r$/, "").split("\t").map(field => field.trim());
            if (fields.length !== 3)
                continue;
            const [name, directory, config] = fields;
            if (!/^[a-z][a-z0-9_-]*$/.test(name) || !directory.startsWith("/") || !/^[^\s/]+$/.test(config))
                continue;
            if (!Object.prototype.hasOwnProperty.call(found, name))
                found[name] = { directory: directory, config: config };
        }
        return found;
    }

    // One line of `gdbus monitor --system --dest org.freedesktop.login1` → the event it
    // means, or null. Lock and Unlock count only on the shell's own session (`sessionPath`,
    // from parseSessionPath): another session's Unlock must not unlock this one.
    function parseLogind(line, sessionPath) {
        const match = /^(\/\S*): ([\w.]+) \((.*)\)$/.exec(String(line ?? "").trim());
        if (match === null)
            return null;
        const [, path, member, args] = match;
        if (member === "org.freedesktop.login1.Manager.PrepareForSleep" && path === "/org/freedesktop/login1") {
            const value = args.trim().replace(/,$/, "").trim();
            return value === "true" ? { type: "prepareForSleep" } : value === "false" ? { type: "resumed" } : null;
        }
        if (typeof sessionPath !== "string" || sessionPath === "" || path !== sessionPath)
            return null;
        if (member === "org.freedesktop.login1.Session.Lock")
            return { type: "lockRequested", source: "logind" };
        if (member === "org.freedesktop.login1.Session.Unlock")
            return { type: "unlockRequested", source: "logind" };
        return null;
    }

    // `gdbus call … Manager.GetSession` output → the session's object path, "" for an error
    // or nothing (then there is no session to listen to, and that is said once)
    function parseSessionPath(output) {
        const match = /^\(objectpath '(\/org\/freedesktop\/login1\/session\/[A-Za-z0-9_]+)',?\)$/
            .exec(String(output ?? "").trim());
        return match === null ? "" : match[1];
    }
}
