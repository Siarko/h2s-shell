pragma Singleton

import Quickshell
import QtQuick

// The root step of applying a NixOS build (tests/NixosApplyRulesTest.qml): its words for each
// op from the configuration as read (NixosConfigRules.reading) and the candidate the user
// built, and its reply read into an outcome the page can show. Pure.
//
// The root step is scripts/root/nixos-apply.sh after replace-lib.sh and replace-file.sh
// (`scriptFiles`), files in the shell's tree that the shell reads at the click and hands as
// text to the system's /bin/sh through its runs as administrator (PrivilegedRuns.startShell):
// never run by path, every run asks the password (or passes within a remembered
// authorization). Its places are fixed in the file, under the folder its first argument
// names — "" for the system, the only one it takes as root. Its ops:
// - create: {"version":1} as the shell's file of a root-owned configuration that has none;
// - apply: a root-owned configuration — the candidate written (compare-and-swap against the
//   sha256 the shell read, a backup) and the system the user built switched to;
// - switch: a configuration of the user's — nothing written (the user wrote the file, it
//   must hold the candidate), the system the user built switched to;
// - restore: a backup of the shell's file put back (after an apply whose switch failed).
// apply and switch go on only when root's evaluation of the configuration with the
// candidate gives the drvPath and out path the user built: the configuration unchanged
// since the build. Its last line, on stderr (and stdout, but for a refusal), says what it
// did, and its exit code agrees with it; anything else is a failure whose effect is unknown,
// never "applied".
Singleton {
    id: root

    // Where the root step's places are on the system; a suite's stand-in runs use a scratch
    // folder holding the same paths
    readonly property var livePaths: ({
        bin: "/run/current-system/sw/bin",
        profile: "/nix/var/nix/profiles/system",
        store: "/nix/store",
        backups: "/var/lib/h2s-shell/nixos-backup"
    })
    readonly property var _placeNames: ["bin", "profile", "store", "backups"]

    // The root step's files in scripts/root/, joined in this order (RootScriptRules.script)
    readonly property var scriptFiles: ["replace-lib.sh", "replace-file.sh", "nixos-apply.sh"]

    // How long a run may take: an evaluation and an activation
    readonly property int timeoutMs: 30 * 60 * 1000
    // The largest candidate the root step takes, in bytes
    readonly property int maxBytes: 65536
    // What create writes
    readonly property string createdText: "{\"version\":1}\n"

    // Why a run was not started, what the root step refused (by its code), and what a run
    // that did not apply left
    readonly property var texts: ({
        // Before the run
        notFound: "No NixOS configuration was found.",
        notRoot: "The configuration is yours: the shell writes its file without a password.",
        exists: "h2s-shell.json is already there.",
        unread: "h2s-shell.json could not be read.",
        host: "The host is not a name the shell can pass on.",
        candidate: "The new settings could not be checked.",
        built: "The built system is not one the shell can name.",
        backupName: "Not a backup of h2s-shell.json.",
        otherFolder: "The configuration is another one now.",
        running: "A change to NixOS is already running.",
        script: "The shell's script for this could not be read.",
        start: "The run could not be started.",
        // By the root step
        arguments: "The request was not valid.",
        paths: "Not a place the shell may write to.",
        folder: "The configuration's folder is not there.",
        owner: "A folder of the configuration is not root's alone: nothing changed.",
        json: "The new settings are not ones the shell writes: nothing changed.",
        hash: "The file written was not the one built: nothing changed.",
        link: "h2s-shell.json is a link: nothing changed.",
        changed: "Your configuration changed since the build. Nothing changed. Build again.",
        unreadable: "h2s-shell.json could not be read: nothing changed.",
        tools: "A NixOS program is not in its place: nothing changed.",
        entry: "The configuration's file is not there: nothing changed.",
        nixpath: "The system's nixpkgs could not be found: nothing changed.",
        evaluation: "The configuration could not be evaluated: nothing changed.",
        notbuilt: "The built system is not in the store: build again.",
        profile: "The system profile could not be set: nothing changed.",
        backup: "The backup could not be made: nothing changed.",
        nobackup: "That backup is not there.",
        busy: "Another switch is running: nothing changed.",
        lock: "Another change is being saved: nothing changed.",
        write: "h2s-shell.json could not be written: nothing changed.",
        // A run that did not apply
        appliedWithErrors: "Applied, but some services did not start.",
        failed: "The switch failed: the system may be partly changed.",
        notActivated: "The switch did not start: nothing changed.",
        notRestored: "Not switched, but the previous h2s-shell.json could not be put back.",
        timedOut: "It did not end within 30 minutes: the system may have changed.",
        unclear: "Its answer could not be read: the system may have changed."
    })

    function refusal(code) {
        return { code, text: texts[code] ?? texts.arguments };
    }

    function _refused(code) {
        return { argv: null, expected: null, what: "", refusal: refusal(code) };
    }

    function isHash(value) {
        return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
    }

    // A backup of the shell's file as the root step names it
    function validBackup(name) {
        return typeof name === "string" && /^h2s-shell\.json\.[0-9]{8}T[0-9]{6}Z(-[1-9])?(\.absent)?$/.test(name);
    }

    // A flake's host as the root step takes it
    function validHost(host) {
        return typeof host === "string" && /^[A-Za-z0-9_-]{1,253}$/.test(host);
    }

    // The configuration's entry file as the root step takes it: a plain .nix name
    function validEntry(entry) {
        return typeof entry === "string" && entry.length <= 255 && /^[A-Za-z0-9_][A-Za-z0-9._-]*\.nix$/.test(entry);
    }

    // A path in `store`: <store>/<32 base-32 letters>-<name>, a .drv (`drv`) or not
    function storePath(path, store, drv) {
        if (typeof path !== "string" || !path.startsWith(store + "/"))
            return false;
        const name = path.slice(store.length + 1);
        return /^[0-9abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+._?=-]+$/.test(name) && name.endsWith(".drv") === drv;
    }

    // A text's length in UTF-8 bytes; Infinity for one that is not valid Unicode
    function byteLength(text) {
        try {
            return encodeURIComponent(text).replace(/%[0-9A-F]{2}/g, "x").length;
        } catch (error) {
            return Infinity;
        }
    }

    // Whether the places may be written: "" when they may, else "paths". `live`: the run goes
    // to the system's pkexec, so exactly livePaths; a stand-in's run is under a scratch folder
    function pathsRefusal(paths, live) {
        return RootScriptRules.placesRefusal(paths, _placeNames, livePaths, live);
    }

    // Which root step an Apply is: apply where root may write the configuration's folder,
    // switch anywhere else (an owner chain not known is the user's for writing)
    function applyOp(reading) {
        return reading?.rootWrites === true ? "apply" : "switch";
    }

    // What the prompt says the run is for, naming the folder and, for a flake, the host
    function what(op, folder, host) {
        const flake = host !== "-";
        if (op === "create")
            return "Create h2s-shell.json in " + folder;
        if (op === "restore")
            return "Put back the previous h2s-shell.json in " + folder;
        if (op === "apply")
            return "Write h2s-shell.json in " + folder + " and switch NixOS to the system built " + (flake ? "for " + host : "from it");
        return "Switch NixOS to the system built " + (flake ? "for " + host + " " : "") + "from " + folder;
    }

    // The root step's words. `request` { op ("create" | "apply" | "restore"), reading
    // (NixosConfigRules.reading's), candidate { text (the shell's file as built), sha256
    // (optional: the build's), drvPath, outPath } for apply, from (an earlier outcome: its
    // folder, backup and sha256 — what it left in the file) for restore }; `paths` the places
    // (livePaths, or a stand-in's), `live` the run goes to the system's pkexec, `scripts` the
    // texts of scriptFiles as read, `shell` the absolute shell. → { argv ([shell, "-c",
    // script, "sh", base, words…]), expected (for reply), what (for the prompt), refusal
    // (null or { code, text }) }
    function plan(request, paths, live, scripts, shell) {
        if (typeof shell !== "string" || !shell.startsWith("/"))
            return _refused("arguments");
        if (pathsRefusal(paths, live) !== "")
            return _refused("paths");
        const script = RootScriptRules.script(scripts);
        if (script === "")
            return _refused("script");
        const base = RootScriptRules.base(paths, _placeNames, livePaths);
        const reading = request?.reading;
        const configuration = reading?.configuration;
        if (configuration?.found !== true)
            return _refused("notFound");
        const folder = configuration.folder;
        if (!RootScriptRules.plainPath(folder) || (base !== "" && !folder.startsWith(base + "/")))
            return _refused("paths");
        const file = reading.file;
        const words = [];
        const expected = { op: request?.op, folder, current: "", sha256: "" };
        let host = "-";
        if (request?.op === "create") {
            if (reading.rootWrites !== true)
                return _refused("notRoot");
            if (file?.state !== "absent")
                return _refused(file?.state === "present" ? "exists" : "unread");
            words.push("create", folder);
            expected.current = "absent";
            expected.sha256 = PamEditRules.sha256(createdText);
        } else if (request?.op === "restore") {
            const from = request.from;
            if (reading.rootWrites !== true)
                return _refused("notRoot");
            if (from?.folder !== folder)
                return _refused("otherFolder");
            if (!validBackup(from.backup))
                return _refused("backupName");
            if (from.sha256 !== "absent" && !isHash(from.sha256))
                return _refused("unread");
            words.push("restore", folder, from.backup, from.sha256);
            expected.current = from.sha256;
        } else if (request?.op === "apply") {
            const op = applyOp(reading);
            const entry = configuration.entry;
            if (!validEntry(entry) || (entry === "flake.nix") !== (configuration.type === "flake"))
                return _refused("arguments");
            if (entry === "flake.nix") {
                if (!validHost(reading.host))
                    return _refused("host");
                host = reading.host;
            }
            const candidate = request.candidate;
            const text = candidate?.text;
            if (typeof text !== "string" || !text.startsWith("{") || text.includes("\u0000") || byteLength(text) > maxBytes)
                return _refused("candidate");
            const sha256 = PamEditRules.sha256(text);
            if (candidate.sha256 !== undefined && candidate.sha256 !== sha256)
                return _refused("candidate");
            if (!storePath(candidate.drvPath, paths.store, true) || !storePath(candidate.outPath, paths.store, false))
                return _refused("built");
            words.push(op, folder, entry, host);
            if (op === "apply") {
                const current = file?.state === "absent" ? "absent" : file?.state === "present" && isHash(file.sha256) ? file.sha256 : "";
                if (current === "")
                    return _refused("unread");
                words.push(current);
                expected.current = current;
            }
            words.push(sha256, candidate.drvPath, candidate.outPath, text);
            expected.op = op;
            expected.sha256 = sha256;
        } else {
            return _refused("arguments");
        }
        return {
            argv: [shell, "-c", script, "sh", base].concat(words),
            expected,
            what: what(expected.op, folder, host),
            refusal: null
        };
    }

    // The words of a line the root step ends with → { word, fields } or null
    function _line(text) {
        const line = String(text ?? "").trim().split("\n").pop().trim();
        const words = line.split(" ");
        return line === "" ? null : { word: words[0], fields: words.slice(1) };
    }

    function _generation(field) {
        return /^[0-9]+$/.test(field) ? Number(field) : field === "unknown" ? 0 : -1;
    }

    // The root step's reply (PrivilegedRules' result: ok, code, stdout, stderr, dismissed,
    // refused, cancelled, blocked, timedOut, error) for what plan expected → { ok (what was
    // asked was done: created, applied, appliedWithErrors, restored), quiet (a prompt
    // dismissed, a run refused by polkit, cancelled, or not started while locked: nothing to
    // say), kind ("created" | "applied" | "appliedWithErrors" | "restored" | "changed" |
    // "refused" | "failed" | ""), op, folder, generation (the system profile's after the run;
    // 0 unknown), backup (the backup this run made, "" none), sha256 (what the shell's file
    // holds after the run, "absent" for none, "" unknown), nothingChanged (neither the system
    // nor the file changed, for certain), refused (the root step's code), error (the text for
    // the page, "" when there is nothing to say) }. Only a last line of the expected op, its
    // exit code, and its values counts.
    function reply(result, expected) {
        const op = String(expected?.op ?? "");
        const outcome = {
            ok: false, quiet: false, kind: "", op, folder: String(expected?.folder ?? ""), generation: 0, backup: "", sha256: "",
            nothingChanged: false, refused: "", error: ""
        };
        const code = result?.code;
        const switching = op === "apply" || op === "switch";
        const backupOf = field => op === "apply" ? validBackup(field) : field === "-";
        // The refusal: stderr only, before anything changed
        const refusedLine = _line(result?.stderr);
        if (code === 3 && refusedLine?.word === "refused" && refusedLine.fields.length === 1 && /^[a-z]+$/.test(refusedLine.fields[0])) {
            const reason = refusedLine.fields[0];
            return Object.assign(outcome, {
                kind: reason === "changed" ? "changed" : "refused", refused: reason, nothingChanged: true, error: texts[reason] ?? texts.arguments,
                sha256: String(expected?.current ?? "")
            });
        }
        for (const said of [refusedLine, _line(result?.stdout)]) {
            const fields = said?.fields ?? [];
            const generation = _generation(fields[0]);
            if (said?.word === "created" && op === "create" && code === 0 && fields.length === 2 && fields[0] === expected.sha256
                    && validBackup(fields[1]) && fields[1].endsWith(".absent"))
                return Object.assign(outcome, { ok: true, kind: "created", backup: fields[1], sha256: fields[0] });
            if (said?.word === "restored" && op === "restore" && code === 0 && fields.length === 2
                    && (fields[0] === "absent" || isHash(fields[0])) && validBackup(fields[1]))
                return Object.assign(outcome, { ok: true, kind: "restored", backup: fields[1], sha256: fields[0] });
            if (!switching || fields.length < 2 || generation < 0)
                continue;
            if (said.word === "applied" && code === 0 && fields.length === 2 && backupOf(fields[1]))
                return Object.assign(outcome, { ok: true, kind: "applied", generation, backup: op === "apply" ? fields[1] : "", sha256: expected.sha256 });
            if (said.word === "applied-with-errors" && code === 4 && fields.length === 2 && backupOf(fields[1]))
                return Object.assign(outcome, {
                    ok: true, kind: "appliedWithErrors", generation, backup: op === "apply" ? fields[1] : "", sha256: expected.sha256,
                    error: texts.appliedWithErrors
                });
            if (said.word === "failed" && code === 1 && fields.length === 2 && backupOf(fields[1]))
                return Object.assign(outcome, { kind: "failed", generation, backup: op === "apply" ? fields[1] : "", sha256: expected.sha256, error: texts.failed });
            // Nothing activated, the profile at the generation before, the old file back
            // (switch: nothing was written)
            if (said.word === "not-activated" && code === 5 && fields.length === 3
                    && (op === "apply" ? fields[1] === expected.current && validBackup(fields[2]) : fields[1] === "-" && fields[2] === "-"))
                return Object.assign(outcome, {
                    kind: "failed", generation, backup: op === "apply" ? fields[2] : "", sha256: expected.current, nothingChanged: true,
                    error: texts.notActivated
                });
        }
        if (op === "apply") {
            // The profile could not be set: the old file back. Or not put back: the candidate
            // still written, nothing activated
            const said = refusedLine ?? { word: "", fields: [] };
            const fields = said.fields;
            if (said.word === "restored" && code === 1 && fields.length === 2 && fields[0] === expected.current && validBackup(fields[1]))
                return Object.assign(outcome, { kind: "failed", backup: fields[1], sha256: fields[0], nothingChanged: true, error: texts.profile });
            if (said.word === "not-restored" && code === 6 && fields.length === 2 && fields[0] === expected.sha256 && validBackup(fields[1]))
                return Object.assign(outcome, { kind: "failed", backup: fields[1], sha256: fields[0], error: texts.notRestored });
        }
        // No line it can read: a prompt dismissed, a run refused by polkit or not started
        // while locked ran nothing; anything else may have changed anything
        const notRun = result?.dismissed === true || result?.refused === true || (result?.blocked ?? "") !== "";
        if (notRun || result?.cancelled === true)
            return Object.assign(outcome, { quiet: true, nothingChanged: notRun, sha256: notRun ? String(expected?.current ?? "") : "" });
        const reason = result?.timedOut === true ? texts.timedOut : texts.unclear;
        return Object.assign(outcome, { kind: "failed", error: reason });
    }
}
