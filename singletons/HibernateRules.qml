pragma Singleton

import Quickshell
import QtQuick

// Hibernation, what can be read of it without root and the one thing written: pure. The
// reasons it is not possible (the swap tables, the kernel's lockdown, a resume device), the
// system's delay before a sleep turns into hibernation (sleep.conf's HibernateDelaySec, as
// `systemd-analyze cat-config` prints it), the drop-in's text the Hibernate section's Apply
// writes where the distribution lets the shell apply it (IntegrationRules' kind
// "sleep.hibernateDelay", distributions/EtcFiles.qml), and what that section offers.
Singleton {
    id: root

    // The delays the Apply writes (seconds): the Hibernate section's times
    readonly property var delayRange: ({ minimum: 60, maximum: 86400 })
    // The NixOS module's option for the delay (/etc is generated there: nothing is written;
    // distributions/nixos/NixosIntegration.qml)
    readonly property string nixosOption: "programs.h2s-shell.idle.hibernateDelay"

    // ---- What is read ----

    // /proc/swaps → [{ name, type, kib, zram }], or null when it was not read (empty text, no
    // header). zram lives in memory and is lost at power-off: no place for a hibernation image
    function swaps(text) {
        const lines = String(text ?? "").split("\n").map(line => line.trim()).filter(line => line !== "");
        if (lines.length === 0 || !/^Filename\s/.test(lines[0]))
            return null;
        const list = [];
        for (const line of lines.slice(1)) {
            const fields = line.split(/\s+/);
            if (fields.length < 3 || !/^[0-9]+$/.test(fields[2]))
                continue;
            // The kernel escapes spaces in names as \040
            const name = fields[0].replace(/\\040/g, " ");
            list.push({ name: name, type: fields[1], kib: Number(fields[2]), zram: /^\/dev\/zram[0-9]+$/.test(name) });
        }
        return list;
    }

    // /proc/meminfo → the memory in use (KiB: MemTotal − MemAvailable), or -1 unread
    function memoryInUse(text) {
        const field = name => {
            const match = new RegExp("^" + name + ":\\s+([0-9]+) kB$", "m").exec(String(text ?? ""));
            return match === null ? -1 : Number(match[1]);
        };
        const total = field("MemTotal");
        const available = field("MemAvailable");
        return total < 0 || available < 0 ? -1 : Math.max(0, total - available);
    }

    // /sys/kernel/security/lockdown ("none [integrity] confidentiality": the chosen one in
    // brackets) → "none", "integrity", "confidentiality" or "unknown"
    function lockdown(text) {
        const match = /\[(none|integrity|confidentiality)\]/.exec(String(text ?? ""));
        return match === null ? "unknown" : match[1];
    }

    // Whether the kernel knows where to resume from: /sys/power/resume ("major:minor", "0:0"
    // for none) or a resume= on its command line → true, false, or "unknown" (not read).
    // systemd may still find the place by itself (an EFI variable), so this only explains a
    // logind "na" that nothing else explains
    function resumeKnown(resumeText, commandLine) {
        const device = /^\s*([0-9]+):([0-9]+)\s*$/.exec(String(resumeText ?? ""));
        if (device === null)
            return "unknown";
        if (device[1] !== "0" || device[2] !== "0")
            return true;
        return /(^|\s)resume=\S/.test(String(commandLine ?? ""));
    }

    // A systemd time span ("7200", "2h", "1h 30min", "90 min", "1.5h") → whole seconds, or
    // null when not understood (months and years, "infinity", junk)
    function timeSpan(text) {
        const units = {
            us: 1e-6, usec: 1e-6, ms: 1e-3, msec: 1e-3,
            s: 1, sec: 1, second: 1, seconds: 1,
            m: 60, min: 60, minute: 60, minutes: 60,
            h: 3600, hr: 3600, hour: 3600, hours: 3600,
            d: 86400, day: 86400, days: 86400,
            w: 604800, week: 604800, weeks: 604800
        };
        const given = String(text ?? "").trim();
        if (given === "" || given.length > 100)
            return null;
        if (/^[0-9]+(\.[0-9]+)?$/.test(given))
            return Math.round(Number(given));
        let rest = given;
        let total = 0;
        while (rest !== "") {
            const match = /^([0-9]+(?:\.[0-9]+)?)\s*([a-z]+)\s*/.exec(rest);
            if (match === null || !Object.prototype.hasOwnProperty.call(units, match[2]))
                return null;
            total += Number(match[1]) * units[match[2]];
            rest = rest.slice(match[0].length);
        }
        return Math.round(total);
    }

    // `systemd-analyze cat-config systemd/sleep.conf` (the main file and its drop-ins, in the
    // order systemd reads them, each under a `# /its/path` line) → the system's delay:
    // { state: "set", seconds, file } | { state: "unset" } (systemd's own default then: from
    // the battery, or 2 h without one; with `file` when an empty assignment there put it back)
    // | { state: "unknown" } (not read, or a value not understood). The last assignment in a
    // [Sleep] section wins; each file starts outside any section, as systemd reads it.
    // `file`: the path of the file that made the last assignment ("" before any path line),
    // one line, capped
    function hibernateDelay(text) {
        const given = String(text ?? "");
        if (given.trim() === "")
            return { state: "unknown" };
        let section = "";
        let file = "";
        let delay = { state: "unset" };
        for (const raw of given.split("\n")) {
            const line = raw.trim();
            const path = /^#\s*(\/\S.*)$/.exec(line);
            if (path !== null) {
                file = _line(path[1], 200);
                section = "";
                continue;
            }
            if (line === "" || line.startsWith("#") || line.startsWith(";"))
                continue;
            const header = /^\[([^\]]*)\]$/.exec(line);
            if (header !== null) {
                section = header[1];
                continue;
            }
            const assignment = /^HibernateDelaySec\s*=\s*(.*)$/.exec(line);
            if (section !== "Sleep" || assignment === null)
                continue;
            if (assignment[1].trim() === "") {
                delay = { state: "unset", file: file };
                continue;
            }
            const seconds = timeSpan(assignment[1]);
            delay = seconds === null ? { state: "unknown" } : { state: "set", seconds: seconds, file: file };
        }
        return delay;
    }

    // Text from outside on one line, capped
    function _line(text, length) {
        return String(text ?? "").replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim().slice(0, length);
    }

    // ---- What the page says ----

    // Why the shell cannot hibernate the computer here, as the Hibernate section's line; ""
    // where it can. `facts`: { answer (logind's CanHibernate, or CanSuspendThenHibernate with
    // sleep on: "yes", "no", "challenge", "na", else unknown), swaps (swaps()), memoryInUse
    // (KiB, -1 unread), lockdown (lockdown()), resume (resumeKnown()) }. Only logind decides
    // ("yes" or not); what was read only says why it answered "na"
    function unavailable(facts) {
        const prefix = "Not available here: ";
        switch (facts?.answer) {
        case "yes":
            return "";
        case "challenge":
            return prefix + "the system asks for a password to hibernate.";
        case "no":
            return prefix + "the system does not allow it.";
        case "na":
            break;
        default:
            return prefix + "the system did not say whether it can hibernate.";
        }
        if (facts?.lockdown === "integrity" || facts?.lockdown === "confidentiality")
            return prefix + "the kernel's lockdown (Secure Boot) forbids it.";
        const swapList = Array.isArray(facts?.swaps) ? facts.swaps : null;
        if (swapList !== null) {
            const disk = swapList.filter(swap => swap?.zram !== true);
            if (disk.length === 0)
                return prefix + "no swap space to save the session to"
                    + (swapList.length > 0 ? " (only zram, which is lost at power-off)." : ".");
            const size = disk.reduce((sum, swap) => sum + (Number(swap?.kib) || 0), 0);
            if (typeof facts?.memoryInUse === "number" && facts.memoryInUse >= 0 && size < facts.memoryInUse)
                return prefix + "the swap space is smaller than the memory in use.";
        }
        if (facts?.resume === false)
            return prefix + "the kernel has no resume device (resume=).";
        return prefix + "this computer cannot hibernate.";
    }

    // The system's delay, as the page says it (`delay`: hibernateDelay()'s)
    function delayWords(delay, durationOf) {
        const label = typeof durationOf === "function" ? durationOf : seconds => seconds + " s";
        if (delay?.state === "set")
            return label(delay.seconds);
        if (delay?.state === "unset")
            return "not set: systemd's default";
        return "not read";
    }

    // The profile's time after sleeping (seconds) differs from the system's delay: the page
    // offers Apply (or names the NixOS option). Unset and unread differ from every time
    function delayDiffers(delay, seconds) {
        return !(delay?.state === "set" && delay.seconds === seconds);
    }

    // What the Hibernate section offers under the times while sleep is on, its labels and
    // their effects in one answer. `given` { delay (hibernateDelay()'s, as last read), picked
    // (the time picked, seconds), differs (sleep on and the picked time is not the system's:
    // delayDiffers), capability (the distribution's for "sleep.hibernateDelay":
    // IntegrationRules.capability's), option (the option to set, plan's preview, where the
    // system's configuration sets it), inForce (readInForce's answer; null before one), busy
    // ("apply" or "undo" while one runs, else ""), undoable (a change of the shell's in this
    // run that Undo puts back) } → { shown, line, apply: { shown, asks, label, question,
    // available, request: { seconds, current, replace } | null }, undo: { shown, label,
    // available } }.
    //
    // By the capability's mode: "apply" offers Apply — never over a setting made in another
    // file (the user's or the system's own: named with its value, no Apply), over the
    // shell's own file changed outside it only as a question; and only once what is in
    // force was read, the shell's file as the user saw it being what the change is checked
    // against (`current`). "copy" and "declare" name the option; "unavailable" says why
    // (nothing while the distribution is not known). The line says first the time picked and
    // what the system does now — the picked time takes effect only after Apply
    function delayOffer(given, durationOf) {
        const label = typeof durationOf === "function" ? durationOf : seconds => seconds + " s";
        const capability = given?.capability ?? {};
        const busy = typeof given?.busy === "string" ? given.busy : "";
        const undoShown = capability.mode === "apply" && capability.undo === true && given?.undoable === true;
        const offer = {
            shown: given?.differs === true || undoShown,
            line: "",
            apply: { shown: false, asks: false, label: busy === "apply" ? "Applying…" : "Apply", question: "Replace?", available: busy === "",
                     request: null },
            undo: { shown: undoShown, label: "Undo", available: busy === "" }
        };
        if (given?.differs !== true)
            return offer;
        const delay = given?.delay;
        const picked = given?.picked;
        const now = "Picked " + label(picked) + "; "
            + (delay?.state === "set" ? "the system now hibernates after " + label(delay.seconds) + "."
               : delay?.state === "unset" ? "the system's delay is not set (systemd's default)."
               : "the system's delay could not be read.");
        if (capability.mode === "copy" || capability.mode === "declare") {
            offer.line = now + " On NixOS it is the option " + String(given?.option ?? "") + ".";
            return offer;
        }
        if (capability.mode !== "apply") {
            const reason = capability.known === true && typeof capability.reason === "string" ? capability.reason : "";
            offer.line = reason !== "" ? now + " " + reason : now;
            return offer;
        }
        const inForce = given?.inForce ?? null;
        const elsewhere = typeof inForce?.elsewhere === "string" ? inForce.elsewhere : "";
        if (elsewhere !== "") {
            offer.line = "Picked " + label(picked) + ". Set in " + elsewhere + ": "
                + (inForce.state === "set" ? label(inForce.value) : "systemd's default") + ".";
            return offer;
        }
        const file = inForce?.file ?? null;
        if ((inForce?.state !== "set" && inForce?.state !== "default") || file === null || typeof file !== "object"
                || (file.state !== "text" && file.state !== "absent")) {
            offer.line = now;
            return offer;
        }
        const replace = file.state === "text" && file.ours !== true;
        offer.apply.shown = true;
        offer.apply.asks = replace;
        offer.apply.request = { seconds: picked, current: file, replace };
        offer.line = now + (replace ? " " + EtcFilesRules.files["sleep.hibernateDelay"] + " was changed outside the shell: Apply replaces it."
                                    : " Apply to change it.");
        return offer;
    }

    // The hibernation as it will happen (`hibernate`: IdleRules.config's): with sleep on, the
    // system's delay when it is set — the profile's time takes effect only after Apply —;
    // otherwise as given (sleep off: the shell's own time; the delay unset or unread: the
    // profile's, nothing better known)
    function inEffect(hibernate, delay) {
        if (hibernate?.from !== "sleep" || delay?.state !== "set")
            return hibernate;
        return Object.assign({}, hibernate, { after: delay.seconds });
    }

    // ---- The Apply ----

    // The drop-in's text as the shell writes it (EtcFilesRules.shellText checks a file against it)
    function dropInText(seconds) {
        return "# Written by h2s-shell: Settings, When away, Hibernate\n[Sleep]\nHibernateDelaySec=" + seconds + "\n";
    }
}
