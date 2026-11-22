pragma Singleton

import Quickshell
import QtQuick

// The lock's rules, what comes in as text: the methods script's lines and logind's, read
// into what LockRules and IdleRules take. Pure: text in, values out.
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

    // logind's inhibitors (LockIoRules.parseInhibitors) and this user's uid → whether an
    // `idle` block inhibitor of this user's holds (`systemd-inhibit --what=idle`, video
    // players): { held: true | false | "unknown", holders: [{ who, why }] }. "unknown" for no
    // list or no uid — a failed or malformed read is never "free". Delay inhibitors (logind
    // has none for idle), other users' (a greeter's) and the shell's own do not count.
    // `holders`: as they may be shown — one line, capped (who 40, why 80 characters), at
    // most 5, in logind's order.
    function idleBlock(inhibitors, uid) {
        if (!Array.isArray(inhibitors) || typeof uid !== "number" || !Number.isInteger(uid) || uid < 0)
            return { held: "unknown", holders: [] };
        return _blocks(inhibitors, inhibitor => inhibitor?.uid === uid && _blocksWhat(inhibitor, "idle")
            && _line(inhibitor.who, 40).toLowerCase() !== "h2s-shell");
    }

    // logind's inhibitors → whether a `sleep` block inhibitor holds (`systemd-inhibit
    // --what=sleep`: a backup, a download), of any user — logind refuses or delays a Suspend
    // while one holds, root's too: { held: true | false | "unknown", holders: [{ who, why }] }
    // as idleBlock's. "block-weak" (systemd 257: a block its owner's own calls pass) counts:
    // the shell is not its owner. Delay inhibitors (the shell's own, UPower's) only delay a
    // sleep and do not count.
    function sleepBlock(inhibitors) {
        if (!Array.isArray(inhibitors))
            return { held: "unknown", holders: [] };
        return _blocks(inhibitors, inhibitor => _blocksWhat(inhibitor, "sleep"));
    }

    function _blocksWhat(inhibitor, what) {
        return (inhibitor?.mode === "block" || inhibitor?.mode === "block-weak") && typeof inhibitor.what === "string" && inhibitor.what.split(":").includes(what);
    }

    // One line, capped
    function _line(value, limit) {
        const text = typeof value === "string"
            ? value.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]+/g, " ").replace(/\s+/g, " ").trim() : "";
        return text.length > limit ? text.slice(0, limit - 1) + "\u2026" : text;
    }

    function _blocks(inhibitors, counts) {
        const holders = [];
        for (const inhibitor of inhibitors) {
            if (counts(inhibitor))
                holders.push({ who: _line(inhibitor.who, 40) || "an app", why: _line(inhibitor.why, 80) });
        }
        return { held: holders.length > 0, holders: holders.slice(0, 5) };
    }

    // The idle reader's whole output — `id -u`'s line, then gdbus's ListInhibitors answer —
    // → idleBlock()
    function idleBlockFromOutput(output) {
        const read = _inhibitorsRead(output);
        return idleBlock(read.inhibitors, read.uid);
    }

    // The same output → sleepBlock()
    function sleepBlockFromOutput(output) {
        return sleepBlock(_inhibitorsRead(output).inhibitors);
    }

    function _inhibitorsRead(output) {
        const text = typeof output === "string" ? output : "";
        const newline = text.indexOf("\n");
        const first = (newline < 0 ? text : text.slice(0, newline)).trim();
        return {
            uid: /^[0-9]{1,10}$/.test(first) ? Number(first) : null,
            inhibitors: newline < 0 ? null : LockIoRules.parseInhibitors(text.slice(newline + 1))
        };
    }

    // ---- What logind says of sleep (singletons/lock/LogindSleep.qml reads it) ----

    // A Can* answer as gdbus prints it (`('yes',)`) → "yes", "no", "challenge", "na", or
    // "unknown" for anything else (a failed call printed nothing)
    function canAnswer(output) {
        const match = /^\('(yes|no|challenge|na)',?\)$/.exec(String(output ?? "").trim());
        return match === null ? "unknown" : match[1];
    }

    // logind's IdleAction and IdleActionUSec properties as gdbus prints them (`(<'suspend'>,)`,
    // `(<uint64 1800000000>,)`) → { action, after (whole seconds) }, or null when either is
    // not understood. "ignore" is logind's default: it does nothing by itself
    function idleAction(actionOutput, usecOutput) {
        const action = /^\(<'([a-z-]{1,40})'>,?\)$/.exec(String(actionOutput ?? "").trim());
        const usec = /^\(<(?:uint64 )?([0-9]{1,20})>,?\)$/.exec(String(usecOutput ?? "").trim());
        if (action === null || usec === null)
            return null;
        return { action: action[1], after: Math.round(Number(usec[1]) / 1000000) };
    }

    // The sleep reader's whole output: sections headed `[CanSuspend]`, `[IdleAction]`,
    // `[IdleActionUSec]`, each with gdbus's answer (nothing where the call failed) →
    // { canSuspend: canAnswer(), idleAction: idleAction() }
    function sleepSupport(output) {
        const sections = {};
        let current = "";
        for (const line of String(output ?? "").split("\n")) {
            const header = /^\[([A-Za-z]+)\]$/.exec(line.trim());
            if (header !== null) {
                current = header[1];
                sections[current] = "";
            } else if (current !== "") {
                sections[current] += line + "\n";
            }
        }
        return {
            canSuspend: canAnswer(sections.CanSuspend),
            idleAction: idleAction(sections.IdleAction, sections.IdleActionUSec)
        };
    }

    // The sleep call's output — gdbus's answer or error, then `[exit <status>]` — → { ok,
    // error }: ok only for status 0 with logind's empty answer `()`; `error` gdbus's words on
    // one line, capped, for the log
    function suspendOutcome(output) {
        const text = String(output ?? "").trim();
        const match = /^([\s\S]*)\n?\[exit ([0-9]{1,3})\]$/.exec(text);
        if (match === null)
            return { ok: false, error: "no answer" };
        const said = match[1].replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 200);
        if (match[2] === "0" && said === "()")
            return { ok: true, error: "" };
        return { ok: false, error: said || "gdbus exited with " + match[2] };
    }
}
