pragma Singleton

import Quickshell
import QtQuick

// Hibernation, what can be read of it without root and the one thing written: pure. The
// reasons it is not possible (the swap tables, the kernel's lockdown, a resume device), the
// system's delay before a sleep turns into hibernation (sleep.conf's HibernateDelaySec, as
// `systemd-analyze cat-config` prints it), and the drop-in the Hibernate section's Apply
// writes through the shell's runs as administrator (singletons/io/HibernateDelayWriter.qml).
Singleton {
    id: root

    // The drop-in the shell owns, in the directory systemd reads sleep.conf's drop-ins from
    readonly property string dropInDirectory: "/etc/systemd/sleep.conf.d"
    readonly property string dropInName: "h2s-shell.conf"
    // The delays the Apply writes (seconds): the Hibernate section's times
    readonly property var delayRange: ({ minimum: 60, maximum: 86400 })
    // The NixOS module's option for the delay (/etc is generated there: nothing is written)
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

    // The file that keeps the shell's drop-in from taking effect, or "": after the shell
    // wrote `written` (seconds; anything else: no write), the delay read back is another,
    // set (or unset) last by a file that is not the shell's own drop-in — one sorting after
    // it, or in another directory systemd reads. Apply cannot win against it
    function delayOverride(delay, written) {
        if (!Number.isInteger(written) || written <= 0)
            return "";
        if (delay?.state !== "set" && delay?.state !== "unset")
            return "";
        if (delay.state === "set" && delay.seconds === written)
            return "";
        const file = typeof delay.file === "string" ? delay.file : "";
        return file !== "" && file !== dropInDirectory + "/" + dropInName ? file : "";
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

    // The line under the times while they differ: the time picked (`picked`, seconds) and
    // what the system does now — the picked time takes effect only after Apply —, then by
    // system: Apply where /etc is the machine's own (`nixos` false), the option on NixOS
    // (true), neither while that was not read (null); with `override` (delayOverride's
    // file), the file that wins over Apply
    function delayLine(delay, nixos, durationOf, override, picked) {
        const label = typeof durationOf === "function" ? durationOf : seconds => seconds + " s";
        const now = "Picked " + label(picked) + "; "
            + (delay?.state === "set" ? "the system now hibernates after " + label(delay.seconds) + "."
               : delay?.state === "unset" ? "the system's delay is not set (systemd's default)."
               : "the system's delay could not be read.");
        if (nixos === true)
            return now + " On NixOS it is the option " + nixosOption + ".";
        if (typeof override === "string" && override !== "")
            return now + " " + override + " sets it after the shell's own file, so Apply cannot change it.";
        return nixos === false ? now + " Apply to change it." : now;
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

    // The root step of the Apply: scripts/root/hibernate-delay.sh (`scriptFiles`), a file in
    // the shell's tree the shell reads and hands as text to the system's /bin/sh — never run by
    // path. The drop-in's place is fixed in it, under the folder its first argument names ("" for
    // the system, the only one it takes as root; a suite's stand-in: a scratch folder); the
    // delay is its second. It checks both, writes the drop-in beside its place and renames it
    // there (never half a file), and says what it wrote.
    readonly property var scriptFiles: ["hibernate-delay.sh"]

    // `base`: "" or a plain absolute path; `scripts`: the texts of scriptFiles as read →
    // [shell, "-c", script, "sh", base, seconds], or null for a delay outside delayRange, a base
    // that is neither, or a script not read
    function applyArgv(shell, seconds, base, scripts) {
        if (typeof shell !== "string" || !shell.startsWith("/"))
            return null;
        if (!Number.isInteger(seconds) || seconds < delayRange.minimum || seconds > delayRange.maximum)
            return null;
        if (base !== "" && !RootScriptRules.plainPath(base))
            return null;
        const script = RootScriptRules.script(scripts);
        if (script === "")
            return null;
        return [shell, "-c", script, "sh", base, String(seconds)];
    }

    // The drop-in's text as the script writes it
    function dropInText(seconds) {
        return "# Written by h2s-shell: Settings, When away, Hibernate\n[Sleep]\nHibernateDelaySec=" + seconds + "\n";
    }

    // The run's answer (PrivilegedRules' result: ok, dismissed, refused, stdout, stderr,
    // error) → { ok, quiet, error }: ok only when it ran and said it wrote this delay; quiet
    // for a prompt dismissed or a run refused or cancelled (the queue and the prompt said so,
    // or the user chose it); `error` for the log and the notice
    function applyOutcome(result, seconds) {
        if (result?.ok === true && String(result.stdout ?? "").trim().split("\n").pop() === "written " + seconds)
            return { ok: true, quiet: false, error: "" };
        if (result?.dismissed === true || result?.refused === true || result?.cancelled === true || (result?.blocked ?? "") !== "")
            return { ok: false, quiet: true, error: "" };
        const said = String(result?.error || String(result?.stderr ?? "").trim().split("\n").pop() || "").replace(/[\u0000-\u001f\u007f]+/g, " ").trim();
        return { ok: false, quiet: false, error: said !== "" ? said.slice(0, 200) : "exit code " + (result?.code ?? -1) };
    }
}
