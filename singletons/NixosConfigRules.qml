pragma Singleton

import Quickshell
import QtQuick

// The system's NixOS configuration as the shell reads it, as the user
// (distributions/nixos/NixosConfiguration.qml does the reads; tests/NixosConfigRulesTest.qml):
// which configuration it is, who owns its folder, the shell's file in it and whether that is
// in force, whether the shell's NixOS module is, the generations, and the facts shown one per
// line. Pure.
//
// The configuration is the first of: the folder the user chose (kept in Config; its
// flake.nix, else its configuration.nix), /etc/nixos/flake.nix, then the classic one —
// NIX_PATH's nixos-config= when it names one, else /etc/nixos/configuration.nix. A chosen
// folder that has neither is not passed over for another: the user picked that one.
//
// Whatever could not be read is unknown, never fine: an unreadable shell's file or
// /etc/h2s-shell/settings.json is never "In force", an owner chain that cannot be read is
// unknown (shown so, and never root's for writing).
Singleton {
    id: root

    // The shell's file, beside the configuration's entry file
    readonly property string fileName: "h2s-shell.json"
    // A flake's nixosConfigurations name, as the root step will take it
    readonly property var hostPattern: /^[A-Za-z0-9_-]+$/

    // The system's places, under `base` ("" for the system's own; a suite's scratch folder)
    function places(base) {
        const under = typeof base === "string" ? base : "";
        return {
            etcFolder: under + "/etc/nixos",
            hostname: under + "/etc/hostname",
            settings: under + "/etc/h2s-shell/settings.json",
            // The shell's NixOS module's own files: there only while the module is in force
            pamMarker: under + "/etc/pam.d/h2s-shell-password",
            binMarker: under + "/run/current-system/sw/bin/h2s-shell",
            profiles: under + "/nix/var/nix/profiles",
            systemProfile: under + "/nix/var/nix/profiles/system"
        };
    }

    // An absolute path of plain parts: what the root step takes
    function plainPath(path) {
        return RootScriptRules.plainPath(path);
    }

    // NIX_PATH's nixos-config= entry → its path, "" for none
    function nixPathConfig(nixPath) {
        if (typeof nixPath !== "string")
            return "";
        for (const entry of nixPath.split(":")) {
            if (entry.startsWith("nixos-config="))
                return entry.slice("nixos-config=".length);
        }
        return "";
    }

    function _dirname(path) {
        const cut = path.lastIndexOf("/");
        return cut <= 0 ? "/" : path.slice(0, cut);
    }

    // The candidate folders, in order: { candidate, folder, entry ("" for a folder whose
    // entry is told by what is in it) }; a chosen folder or a nixos-config path that is not
    // plain is left out (choose says so)
    function candidates(inputs) {
        const list = [];
        const chosen = inputs?.chosenFolder ?? "";
        if (chosen !== "") {
            if (plainPath(chosen))
                list.push({ candidate: "chosen", folder: chosen, entry: "" });
            return list;
        }
        list.push({ candidate: "etc", folder: places(inputs?.base).etcFolder, entry: "" });
        const config = nixPathConfig(inputs?.nixPath);
        if (config !== "" && plainPath(config))
            list.push({ candidate: "nixPath", folder: _dirname(config), entry: config.slice(config.lastIndexOf("/") + 1) });
        return list;
    }

    // The words for scripts/nixos-config.sh: everything the reading needs, in one run
    function readArgs(inputs) {
        const where = places(inputs?.base);
        const args = ["uid", "/", "file", where.hostname, "file", where.settings, "exists", where.pamMarker, "exists", where.binMarker,
                      "list", where.profiles, "link", where.systemProfile];
        // Each pair asked once
        const seen = {};
        const ask = (op, path) => {
            if (seen[op + " " + path])
                return;
            seen[op + " " + path] = true;
            args.push(op, path);
        };
        for (const each of candidates(inputs)) {
            const folder = each.folder;
            if (each.entry !== "") {
                for (const op of ["exists", "real", "chain"])
                    ask(op, folder + "/" + each.entry);
            }
            for (const name of ["flake.nix", "configuration.nix", ".git"])
                ask("exists", folder + "/" + name);
            ask("file", folder + "/" + fileName);
            // What root builds and reads, each through its own links: the entry files and the
            // shell's file count in the owner chain as much as the folder
            for (const path of [folder, folder + "/flake.nix", folder + "/configuration.nix", folder + "/" + fileName]) {
                ask("real", path);
                ask("chain", path);
            }
        }
        return args;
    }

    // The script's answer → { uid (the user's id, "" unknown), exists, files, sha256, real,
    // chain: { path: { parts: [{ part, uid, mode }], end } }, lists: { folder: { names, end } },
    // links }. The first record of a path counts. A run that failed or was cut short answers
    // nothing (every path unknown). `result` is CommandRunner's.
    function records(lines, result, args) {
        const usable = result !== null && typeof result === "object" && result.ok === true && result.truncated !== true;
        const list = usable && Array.isArray(lines) ? lines : [];
        const asked = [];
        for (let i = 0; Array.isArray(args) && i + 1 < args.length; i += 2) {
            if (args[i] === "file")
                asked.push(args[i + 1]);
        }
        const raw = { uid: "", exists: {}, files: PamStackRules.filesAnswer(list, usable ? result : null, asked).answers, sha256: {}, real: {},
                      chain: {}, lists: {}, links: {} };
        // A file's lines each start with "|", so they never read as a record
        for (const line of list) {
            const fields = String(line).split("\t");
            const [kind, path] = fields;
            const first = map => !Object.prototype.hasOwnProperty.call(map, path);
            if (kind === "uid" && fields.length === 2 && /^[0-9]+$/.test(path)) {
                raw.uid = raw.uid === "" ? path : raw.uid;
            } else if (kind === "exists" && fields.length === 3 && ["present", "unreadable", "absent", "unknown"].includes(fields[2])) {
                if (first(raw.exists))
                    raw.exists[path] = fields[2];
            } else if (kind === "sha256" && fields.length === 3 && /^[0-9a-f]{64}$/.test(fields[2])) {
                if (first(raw.sha256))
                    raw.sha256[path] = fields[2];
            } else if (kind === "real" && fields.length === 3 && fields[2].startsWith("/")) {
                if (first(raw.real))
                    raw.real[path] = fields[2];
            } else if (kind === "chain" && fields.length === 5) {
                raw.chain[path] = raw.chain[path] ?? { parts: [], end: "" };
                // Parts after the chain's end are not its
                if (raw.chain[path].end === "")
                    raw.chain[path].parts.push({ part: fields[2], uid: fields[3], mode: fields[4] });
            } else if (kind === "chainend" && fields.length === 3) {
                raw.chain[path] = raw.chain[path] ?? { parts: [], end: "" };
                raw.chain[path].end = raw.chain[path].end === "" ? fields[2] : raw.chain[path].end;
            } else if (kind === "list" && fields.length === 3) {
                raw.lists[path] = raw.lists[path] ?? { names: [], end: "" };
                raw.lists[path].names.push(fields[2]);
            } else if (kind === "listend" && fields.length === 3) {
                raw.lists[path] = raw.lists[path] ?? { names: [], end: "" };
                raw.lists[path].end = fields[2];
            } else if (kind === "link" && fields.length === 3 && fields[2] !== "unknown") {
                if (first(raw.links))
                    raw.links[path] = fields[2];
            }
        }
        return raw;
    }

    function _exists(raw, path) {
        return raw?.exists?.[path] ?? "unknown";
    }

    // Which configuration → { found, candidate, folder, entry, type ("flake" | "classic"),
    // entryReadable, problem: "" | "none" (nothing anywhere) | "chosenMissing" (the chosen
    // folder has neither file) | "path" (the chosen folder or nixos-config is not a plain
    // path) | "unknown" (a candidate's presence could not be told) }
    function choose(inputs, raw) {
        const result = (candidate, folder, entry, type, state) => ({
            found: true, candidate, folder, entry, type, entryReadable: state === "present", problem: ""
        });
        const missing = problem => ({ found: false, candidate: "", folder: "", entry: "", type: "", entryReadable: false, problem });
        const there = state => state === "present" || state === "unreadable";
        const chosen = inputs?.chosenFolder ?? "";
        if (chosen !== "") {
            if (!plainPath(chosen))
                return missing("path");
            const flake = _exists(raw, chosen + "/flake.nix");
            if (there(flake))
                return result("chosen", chosen, "flake.nix", "flake", flake);
            if (flake === "unknown")
                return missing("unknown");
            const classic = _exists(raw, chosen + "/configuration.nix");
            if (there(classic))
                return result("chosen", chosen, "configuration.nix", "classic", classic);
            return missing(classic === "unknown" ? "unknown" : "chosenMissing");
        }
        const etc = places(inputs?.base).etcFolder;
        const flake = _exists(raw, etc + "/flake.nix");
        if (there(flake))
            return result("etc", etc, "flake.nix", "flake", flake);
        if (flake === "unknown")
            return missing("unknown");
        const config = nixPathConfig(inputs?.nixPath);
        if (config !== "") {
            if (!plainPath(config))
                return missing("path");
            const named = _exists(raw, config);
            if (there(named))
                return result("nixPath", _dirname(config), config.slice(config.lastIndexOf("/") + 1), "classic", named);
            return missing(named === "unknown" ? "unknown" : "none");
        }
        const classic = _exists(raw, etc + "/configuration.nix");
        if (there(classic))
            return result("etc", etc, "configuration.nix", "classic", classic);
        return missing(classic === "unknown" ? "unknown" : "none");
    }

    // A path's owner chain → "root" (every part of its real path, / down to it, root's and
    // not writable by group or others), "yours" (any other: what any program of the user's
    // may change, as a folder in the home folder or a file behind a link into it) or
    // "unknown" (not all of it could be read)
    function ownerChain(raw, path) {
        const chain = raw?.chain?.[path];
        const real = raw?.real?.[path];
        if (!chain || !Array.isArray(chain.parts))
            return "unknown";
        let unknown = chain.end !== "ok" || chain.parts.length === 0 || typeof real !== "string"
            || chain.parts[0].part !== "/" || chain.parts[chain.parts.length - 1].part !== real;
        for (const entry of chain.parts) {
            const uid = /^[0-9]+$/.test(entry.uid) ? Number(entry.uid) : -1;
            const mode = /^[0-7]{3,4}$/.test(entry.mode) ? parseInt(entry.mode, 8) : -1;
            if (uid === -1 || mode === -1) {
                unknown = true;
                continue;
            }
            if (uid !== 0 || (mode & 0o022) !== 0)
                return "yours";
        }
        return unknown ? "unknown" : "root";
    }

    function _object(text) {
        try {
            const value = JSON.parse(text);
            return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null;
        } catch (error) {
            return null;
        }
    }

    // The file's value against what the module took in (settings.json's `settings`): equal,
    // except that a sign-in rule row (inside a list) is published with every field, the
    // defaults the file left out filled in
    function _matches(fileValue, published, inRow) {
        if (Array.isArray(fileValue))
            return Array.isArray(published) && published.length === fileValue.length
                && fileValue.every((item, index) => _matches(item, published[index], true));
        if (fileValue !== null && typeof fileValue === "object") {
            if (published === null || typeof published !== "object" || Array.isArray(published))
                return false;
            const has = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
            return Object.keys(fileValue).every(key => has(published, key) && _matches(fileValue[key], published[key], inRow))
                && (inRow || Object.keys(published).every(key => has(fileValue, key)));
        }
        return fileValue === published;
    }

    // The shell's file against /etc/h2s-shell/settings.json (answers as filesAnswer gives
    // them) → "inForce" (what the running system took in is the file's values),
    // "created" (the file is there, but differs or nothing is published: not in force yet),
    // "notCreated" (no file) or "unknown" (either could not be read, or is not JSON)
    function fileStatus(fileAnswer, settingsAnswer) {
        if (fileAnswer?.absent === true)
            return "notCreated";
        if (typeof fileAnswer?.text !== "string")
            return "unknown";
        const file = _object(fileAnswer.text);
        if (file === null)
            return "unknown";
        if (settingsAnswer?.absent === true)
            return "created";
        if (typeof settingsAnswer?.text !== "string")
            return "unknown";
        const published = _object(settingsAnswer.text);
        if (published === null || published.settings === null || typeof published.settings !== "object" || Array.isArray(published.settings))
            return "unknown";
        if (file.version !== published.version)
            return "created";
        const values = Object.assign({}, file);
        delete values.version;
        return _matches(values, published.settings, false) ? "inForce" : "created";
    }

    // The system profile's links → { count (-1 unknown), current (0 unknown) }
    function generations(list, link) {
        const pattern = /^system-([0-9]+)-link$/;
        const count = list?.end === "ok" && Array.isArray(list.names) ? list.names.filter(name => pattern.test(name)).length : -1;
        const target = typeof link === "string" ? link.slice(link.lastIndexOf("/") + 1) : "";
        const match = pattern.exec(target);
        return { count, current: match ? Number(match[1]) : 0 };
    }

    // The host a flake is built for: the one chosen with the folder, else /etc/hostname's;
    // "" when neither is a name the root step takes
    function host(inputs, hostnameAnswer) {
        const chosen = inputs?.chosenHost ?? "";
        if ((inputs?.chosenFolder ?? "") !== "" && hostPattern.test(chosen))
            return chosen;
        const text = typeof hostnameAnswer?.text === "string" ? hostnameAnswer.text.split("\n")[0].trim() : "";
        return hostPattern.test(text) ? text : "";
    }

    // The configuration's owner chain: the folder's, the entry file's and — when there is
    // one — the shell's file's, the most open of them (any "yours" is yours, else any
    // "unknown" is unknown): root builds what the entry file says and reads the shell's
    // file, each through its own links
    function configurationOwner(raw, configuration, fileState) {
        if (!configuration?.found)
            return "";
        const paths = [configuration.folder, configuration.folder + "/" + configuration.entry];
        if (fileState !== "absent")
            paths.push(configuration.folder + "/" + fileName);
        const owners = paths.map(path => ownerChain(raw, path));
        return owners.includes("yours") ? "yours" : owners.includes("unknown") ? "unknown" : "root";
    }

    // Whose repository git may be asked about → "root" (a root-owned chain: named safe, as git
    // would otherwise refuse a repository not the user's), "user" (the folder the user's own:
    // git's own ownership check stands) or "" (anyone else's: git is not asked — a repository
    // another account can write could name programs git runs)
    function gitAccess(raw, folder) {
        if (ownerChain(raw, folder) === "root")
            return "root";
        const parts = raw?.chain?.[folder]?.parts ?? [];
        const own = parts.length > 0 ? parts[parts.length - 1].uid : "";
        return typeof raw?.uid === "string" && raw.uid !== "" && own === raw.uid ? "user" : "";
    }

    // The check whether git knows the shell's file — read only: the repository's own
    // fsmonitor program never run (core.fsmonitor from the command line wins over the
    // repository's config; ls-files reads no file contents, so no filter or textconv runs,
    // and runs no hooks), safe.directory only for root's repository (`access` gitAccess's), no
    // optional locks so nothing refreshes the index; a flake in git sees only the files git
    // knows. [] when the folder is not plain or git may not be asked.
    function gitArgv(git, realFolder, access) {
        if (!plainPath(realFolder) || typeof git !== "string" || git === "" || (access !== "root" && access !== "user"))
            return [];
        return [git, "-c", "core.fsmonitor=false"].concat(access === "root" ? ["-c", "safe.directory=" + realFolder] : [])
            .concat(["--no-optional-locks", "-C", realFolder, "ls-files", "--error-unmatch", "--", fileName]);
    }

    // git's answer → "tracked", "untracked" (it ran and does not know the file) or "unknown"
    function gitAnswer(result) {
        if (result?.ok === true)
            return "tracked";
        if (result !== null && typeof result === "object" && result.code === 1 && !result.timedOut && !result.cancelled
            && !result.failedToStart && (result.error ?? "") === "")
            return "untracked";
        return "unknown";
    }

    // The whole reading, before git is asked → { configuration (choose's), real ("" unknown),
    // owner (configurationOwner's), rootWrites (only a root-owned chain: an unknown one is the
    // user's for writing), git ("present" | "absent" | "unknown"), gitAccess (gitAccess's),
    // gitKnowsFile ("" without git, "unknown" until withGit), host, file { path, state
    // ("absent" | "present" | "unreadable"), sha256 ("" unknown or none) }, fileStatus,
    // module ("present" | "absent" | "unknown"), published ("present" | "absent" |
    // "unknown"), generations, state, homeWarning, facts }. `inputs` { base, chosenFolder,
    // chosenHost, nixPath, acknowledged (the real paths whose home-folder warning the user
    // took) }.
    function reading(inputs, raw) {
        const where = places(inputs?.base);
        const configuration = choose(inputs, raw);
        const folder = configuration.folder;
        const found = configuration.found;
        const real = found ? (raw?.real?.[folder] ?? "") : "";
        const gitState = found ? _exists(raw, folder + "/.git") : "unknown";
        const git = gitState === "present" || gitState === "unreadable" ? "present" : gitState;
        const filePath = found ? folder + "/" + fileName : "";
        const fileAnswer = found ? raw?.files?.[filePath] : null;
        const file = {
            path: filePath,
            state: fileAnswer?.absent === true ? "absent" : typeof fileAnswer?.text === "string" ? "present" : "unreadable",
            sha256: typeof fileAnswer?.text === "string" ? (raw?.sha256?.[filePath] ?? "") : ""
        };
        const owner = configurationOwner(raw, configuration, file.state);
        const settingsAnswer = raw?.files?.[where.settings];
        const markers = [_exists(raw, where.pamMarker), _exists(raw, where.binMarker)];
        const module = markers.every(state => state === "present" || state === "unreadable") ? "present"
            : markers.some(state => state === "absent") ? "absent" : "unknown";
        const published = settingsAnswer?.absent === true ? "absent"
            : typeof settingsAnswer?.text === "string" && _object(settingsAnswer.text) !== null ? "present" : "unknown";
        const status = found ? fileStatus(fileAnswer, settingsAnswer) : "unknown";
        const acknowledged = Array.isArray(inputs?.acknowledged) ? inputs.acknowledged : [];
        const result = {
            configuration,
            real,
            owner,
            rootWrites: owner === "root",
            git,
            gitAccess: found ? gitAccess(raw, folder) : "",
            gitKnowsFile: git === "present" ? "unknown" : "",
            host: found ? host(inputs, raw?.files?.[where.hostname]) : "",
            file,
            fileStatus: status,
            module,
            published,
            generations: generations(raw?.lists?.[where.profiles], raw?.links?.[where.systemProfile]),
            state: state(found, module, published),
            homeWarning: found && owner !== "root" && !(real !== "" && acknowledged.includes(real))
        };
        result.facts = facts(result);
        return result;
    }

    // git's answer added to a reading → a new reading
    function withGit(reading, result) {
        if (reading === null || typeof reading !== "object" || reading.git !== "present")
            return reading;
        const next = Object.assign({}, reading, { gitKnowsFile: gitAnswer(result) });
        next.facts = facts(next);
        return next;
    }

    // "notConnected" (no configuration, or the shell's module not in force — or either
    // unknown), "found" (the module in force, nothing published: the settingsFile line not
    // in place, or settings.json unreadable) or "connected" (settings.json published)
    function state(found, module, published) {
        if (!found || module !== "present")
            return "notConnected";
        return published === "present" ? "connected" : "found";
    }

    // The facts, one per line: [{ name, value }] (Generations only while connected)
    function facts(reading) {
        if (!reading?.configuration?.found)
            return [];
        const status = { inForce: "In force", created: "Created, not in force yet", notCreated: "Not created", unknown: "Unknown" };
        const rows = [
            { name: "Configuration", value: reading.configuration.folder },
            { name: "Type", value: reading.configuration.type === "flake" ? "Flake" : "Classic (" + reading.configuration.entry + ")" },
            { name: "Git", value: reading.git === "present" ? "Yes" : reading.git === "absent" ? "No" : "Unknown" },
            { name: "Host", value: reading.host !== "" ? reading.host : "Unknown" },
            { name: "The shell's file", value: reading.file.path },
            { name: "File status", value: status[reading.fileStatus] ?? "Unknown" }
        ];
        if (reading.state === "connected")
            rows.push({ name: "Generations", value: reading.generations.count >= 0 ? String(reading.generations.count) : "Unknown" });
        return rows;
    }
}
