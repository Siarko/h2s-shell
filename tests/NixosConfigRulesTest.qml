import QtQuick
import qs.singletons

// NixosConfigRules: the candidates in order (a chosen folder never passed over), the owner
// chain (a /etc/nixos linked into the home folder is the user's), the shell's file against
// settings.json, the states, the generations, the host, git's check and the facts. Readings
// are built from made-up answers of scripts/nixos-config.sh, through records().
TestCase {
    suiteName: "NixosConfigRules"

    readonly property var ok: ({ ok: true, code: 0, truncated: false })

    // Lines of the script's answer: { exists: { path: state }, files: { path: text | "absent"
    // | "unreadable" }, chains: { folder: { real, parts: [[part, uid, mode]] } }, lists, links }
    function answer(spec) {
        const lines = [];
        for (const path of Object.keys(spec.exists ?? {}))
            lines.push("exists\t" + path + "\t" + spec.exists[path]);
        for (const path of Object.keys(spec.files ?? {})) {
            const text = spec.files[path];
            if (text === "absent" || text === "unreadable") {
                lines.push("file\t" + path + "\t" + text);
                continue;
            }
            lines.push("file\t" + path + "\ttext");
            for (const line of text.split("\n"))
                lines.push("|" + line);
            lines.push("end\t" + path);
            lines.push("sha256\t" + path + "\t" + "a".repeat(64));
        }
        for (const folder of Object.keys(spec.chains ?? {})) {
            const chain = spec.chains[folder];
            if (chain.real !== "")
                lines.push("real\t" + folder + "\t" + chain.real);
            for (const part of chain.parts)
                lines.push("chain\t" + folder + "\t" + part.join("\t"));
            lines.push("chainend\t" + folder + "\t" + (chain.real === "" ? "unknown" : "ok"));
        }
        for (const folder of Object.keys(spec.lists ?? {})) {
            for (const name of spec.lists[folder])
                lines.push("list\t" + folder + "\t" + name);
            lines.push("listend\t" + folder + "\tok");
        }
        for (const path of Object.keys(spec.links ?? {}))
            lines.push("link\t" + path + "\t" + spec.links[path]);
        return lines;
    }

    function readingOf(inputs, spec, result) {
        const args = NixosConfigRules.readArgs(inputs);
        return NixosConfigRules.reading(inputs, NixosConfigRules.records(answer(spec), result ?? ok, args));
    }

    function run() {
        const rules = NixosConfigRules;
        const settings = text => ({ version: 1, settings: text, inForce: {} });
        const rootChain = [["/", "0", "755"], ["/etc", "0", "755"], ["/etc/nixos", "0", "755"]];
        const connected = {
            exists: { "/etc/nixos/flake.nix": "present", "/etc/nixos/configuration.nix": "present", "/etc/nixos/.git": "absent",
                      "/etc/pam.d/h2s-shell-password": "present", "/run/current-system/sw/bin/h2s-shell": "present" },
            files: { "/etc/hostname": "nixos\n", "/etc/nixos/h2s-shell.json": JSON.stringify({ version: 1, idle: { hibernateDelay: "3h" } }),
                     "/etc/h2s-shell/settings.json": JSON.stringify(settings({ idle: { hibernateDelay: "3h" } })) },
            chains: { "/etc/nixos": { real: "/etc/nixos", parts: rootChain } },
            lists: { "/nix/var/nix/profiles": ["default", "per-user", "system", "system-10-link", "system-11-link", "system-48-link"] },
            links: { "/nix/var/nix/profiles/system": "system-48-link" }
        };
        const usual = { base: "", chosenFolder: "", chosenHost: "", nixPath: "", acknowledged: [] };
        const changed = (spec, change) => {
            const copy = JSON.parse(JSON.stringify(spec));
            change(copy);
            return copy;
        };

        // ── The places and the words asked ──
        assertEqual(rules.places("/run/x").settings, "/run/x/etc/h2s-shell/settings.json", "the places under a scratch base");
        assertEqual(rules.places("").pamMarker + " " + rules.places("").binMarker, "/etc/pam.d/h2s-shell-password /run/current-system/sw/bin/h2s-shell",
                    "the module's own files as the markers");
        assertEqual(rules.nixPathConfig("nixpkgs=/nix/store/x:nixos-config=/srv/c/configuration.nix"), "/srv/c/configuration.nix", "nixos-config= read from NIX_PATH");
        assertEqual(rules.nixPathConfig("nixpkgs=/nix/store/x") + rules.nixPathConfig(undefined), "", "… none there");
        const args = rules.readArgs(usual);
        assert(args.join(" ").includes("exists /etc/nixos/flake.nix") && args.join(" ").includes("chain /etc/nixos")
               && args.join(" ").includes("file /etc/h2s-shell/settings.json"), "the usual places asked: " + args.join(" "));
        assertEqual(rules.readArgs({ chosenFolder: "/srv/cfg" }).join(" ").includes("/etc/nixos/flake.nix"), false,
                    "a chosen folder: /etc/nixos is not asked");
        assert(rules.readArgs({ nixPath: "nixos-config=/srv/c/configuration.nix" }).join(" ").includes("exists /srv/c/configuration.nix"),
               "nixos-config's file asked");

        // ── The candidates ──
        const pick = (inputs, exists) => rules.choose(inputs, { exists });
        let chosen = pick(usual, { "/etc/nixos/flake.nix": "present", "/etc/nixos/configuration.nix": "present" });
        assertEqual(chosen.folder + " " + chosen.type + " " + chosen.candidate, "/etc/nixos flake etc", "/etc/nixos/flake.nix before its configuration.nix");
        chosen = pick({ chosenFolder: "/srv/cfg" }, { "/srv/cfg/flake.nix": "absent", "/srv/cfg/configuration.nix": "present", "/etc/nixos/flake.nix": "present" });
        assertEqual(chosen.folder + " " + chosen.type + " " + chosen.entry, "/srv/cfg classic configuration.nix", "the chosen folder first, its configuration.nix");
        chosen = pick({ chosenFolder: "/srv/cfg" }, { "/srv/cfg/flake.nix": "present" });
        assertEqual(chosen.type + " " + chosen.candidate, "flake chosen", "… its flake.nix");
        chosen = pick({ chosenFolder: "/srv/cfg" }, { "/srv/cfg/flake.nix": "absent", "/srv/cfg/configuration.nix": "absent", "/etc/nixos/flake.nix": "present" });
        assertEqual(chosen.found + " " + chosen.problem, "false chosenMissing", "a chosen folder with neither file: not passed over for /etc/nixos");
        chosen = pick({ chosenFolder: "/srv/cfg" }, { "/srv/cfg/flake.nix": "unknown" });
        assertEqual(chosen.found + " " + chosen.problem, "false unknown", "a chosen flake.nix whose presence is unknown: unknown");
        assertEqual(pick({ chosenFolder: "/srv/my cfg" }, {}).problem, "path", "a chosen folder that is not a plain path");
        chosen = pick(usual, { "/etc/nixos/flake.nix": "unreadable" });
        assertEqual(chosen.found + " " + chosen.entryReadable, "true false", "an unreadable flake.nix is still the configuration, not readable");
        assertEqual(pick(usual, { "/etc/nixos/flake.nix": "unknown", "/etc/nixos/configuration.nix": "present" }).problem, "unknown",
                    "an unknown flake.nix is never passed over for the classic one");
        chosen = pick({ nixPath: "nixos-config=/srv/c/configuration.nix" }, { "/etc/nixos/flake.nix": "absent", "/srv/c/configuration.nix": "present",
                                                                             "/etc/nixos/configuration.nix": "present" });
        assertEqual(chosen.folder + " " + chosen.type + " " + chosen.candidate, "/srv/c classic nixPath", "nixos-config= before /etc/nixos/configuration.nix");
        assertEqual(pick({ nixPath: "nixos-config=/srv/c/configuration.nix" }, { "/etc/nixos/flake.nix": "absent", "/srv/c/configuration.nix": "absent",
                                                                             "/etc/nixos/configuration.nix": "present" }).problem,
                    "none", "nixos-config= naming a missing file: none (it is what a rebuild would use)");
        chosen = pick(usual, { "/etc/nixos/flake.nix": "absent", "/etc/nixos/configuration.nix": "present" });
        assertEqual(chosen.type + " " + chosen.entry, "classic configuration.nix", "/etc/nixos/configuration.nix last");
        assertEqual(pick(usual, { "/etc/nixos/flake.nix": "absent", "/etc/nixos/configuration.nix": "absent" }).problem, "none", "nothing anywhere");
        assertEqual(pick(usual, {}).problem, "unknown", "nothing answered: unknown, not none");

        // ── Connected, root-owned ──
        let reading = readingOf(usual, connected);
        assertEqual(reading.state, "connected", "the module's files, settings.json published, a flake found: connected");
        assertEqual(reading.owner + " " + reading.rootWrites + " " + reading.homeWarning, "root true false", "root's chain: root writes, no warning");
        assertEqual(reading.fileStatus, "inForce", "the file's values are what was taken in: In force");
        assertEqual(reading.file.sha256, "a".repeat(64), "the file's sha256 kept");
        assertEqual(reading.host, "nixos", "the host from /etc/hostname");
        assertEqual(JSON.stringify(reading.generations), JSON.stringify({ count: 3, current: 48 }), "generations counted, the current one");
        assertEqual(JSON.stringify(reading.facts.map(row => row.name + "=" + row.value)),
                    JSON.stringify(["Configuration=/etc/nixos", "Type=Flake", "Git=No", "Host=nixos", "The shell's file=/etc/nixos/h2s-shell.json",
                                    "File status=In force", "Generations=3"]), "the facts, one per line");

        // ── The owner chain ──
        const chainOf = parts => readingOf(usual, changed(connected, spec => spec.chains["/etc/nixos"].parts = parts)).owner;
        assertEqual(chainOf([["/", "0", "755"], ["/etc", "0", "775"], ["/etc/nixos", "0", "755"]]), "yours", "a parent writable by its group: yours");
        assertEqual(chainOf([["/", "0", "755"], ["/etc", "0", "757"], ["/etc/nixos", "0", "755"]]), "yours", "… by others");
        assertEqual(chainOf([["/", "0", "755"], ["/etc", "0", "755"], ["/etc/nixos", "1000", "755"]]), "yours", "the folder the user's");
        assertEqual(chainOf([["/", "0", "755"], ["/etc", "0", "1777"], ["/etc/nixos", "0", "755"]]), "yours", "a sticky folder anyone writes in: yours");
        assertEqual(chainOf([["/", "0", "755"], ["/etc", "unknown", "unknown"], ["/etc/nixos", "0", "755"]]), "unknown", "a part that could not be read: unknown");
        assertEqual(chainOf([["/", "0", "755"], ["/etc", "unknown", "unknown"], ["/etc/nixos", "1000", "755"]]), "yours", "… unless another part is the user's");
        assertEqual(chainOf([["/", "0", "755"], ["/etc", "0", "755"]]), "unknown", "a chain that stops short of the folder: unknown");
        assertEqual(chainOf([]), "unknown", "no chain: unknown");
        reading = readingOf(usual, changed(connected, spec => spec.chains["/etc/nixos"] = { real: "", parts: [] }));
        assertEqual(reading.owner + " " + reading.rootWrites + " " + reading.homeWarning, "unknown false true",
                    "an unknown chain: unknown for display, the user's for writing, the warning before any write");

        // A symlinked /etc/nixos into the home folder
        const linked = changed(connected, spec => spec.chains["/etc/nixos"] = {
            real: "/home/someone/nixos-config", parts: [["/", "0", "755"], ["/home", "0", "755"], ["/home/someone", "1000", "700"],
                                                        ["/home/someone/nixos-config", "1000", "755"]] });
        reading = readingOf(usual, linked);
        assertEqual(reading.owner + " " + reading.real + " " + reading.homeWarning, "yours /home/someone/nixos-config true",
                    "/etc/nixos a link into the home folder: yours, the warning due");
        assertEqual(reading.configuration.folder, "/etc/nixos", "… the configuration still named as found");
        assertEqual(readingOf(Object.assign({}, usual, { acknowledged: ["/home/someone/nixos-config"] }), linked).homeWarning, false,
                    "the warning taken for the real path: not again");
        assertEqual(readingOf(Object.assign({}, usual, { acknowledged: ["/etc/nixos"] }), linked).homeWarning, true,
                    "… taken for the link's path only: due again (keyed by the real path)");

        // ── The shell's file against settings.json ──
        const status = (file, published) => rules.fileStatus(file, published);
        const text = value => ({ text: JSON.stringify(value) });
        const file = { version: 1, idle: { hibernateDelay: "3h" }, pam: { rules: [{ method: "password" }] } };
        const taken = { idle: { hibernateDelay: "3h" }, pam: { rules: [{ method: "password", control: "sufficient", module: null }] } };
        assertEqual(status({ absent: true }, text(settings(taken))), "notCreated", "no file: Not created");
        assertEqual(status(text(file), text(settings(taken))), "inForce", "equal, a row published with its defaults filled in: In force");
        assertEqual(status(text(Object.assign({}, file, { idle: { hibernateDelay: "1h" } })), text(settings(taken))), "created", "a value differs: not in force yet");
        assertEqual(status(text({ version: 1 }), text(settings(taken))), "created", "the published has a key the file no longer has: not in force yet");
        assertEqual(status(text(Object.assign({}, file, { future: 1 })), text(settings(taken))), "created", "a key the module did not take: not in force yet");
        assertEqual(status(text(file), text({ version: 2, settings: taken })), "created", "another schema version: not in force yet");
        assertEqual(status(text(file), { absent: true }), "created", "nothing published: Created, not in force yet");
        assertEqual(status(text(file), { unreadable: true }), "unknown", "settings.json unreadable: unknown, never In force");
        assertEqual(status(text(file), { text: "{" }), "unknown", "settings.json not JSON: unknown");
        assertEqual(status(text(file), text({ version: 1 })), "unknown", "settings.json without settings: unknown");
        assertEqual(status({ unreadable: true }, text(settings(taken))), "unknown", "the file unreadable: unknown, never In force");
        assertEqual(status(undefined, text(settings(taken))), "unknown", "the file not answered: unknown");
        assertEqual(status({ text: "[1]" }, text(settings(taken))), "unknown", "the file not a JSON object: unknown");
        assertEqual(status(text({ version: 1, pam: { rules: [{ method: "password", extra: 1 }] } }),
                           text(settings({ pam: { rules: [{ method: "password" }] } }))), "created", "a row field the published row lacks: not in force");
        assertEqual(status(text({ version: 1, pam: { rules: [] } }), text(settings({ pam: { rules: [{ method: "password" }] } }))), "created",
                    "rows of another length: not in force");

        // ── The states ──
        const stateOf = change => readingOf(usual, changed(connected, change)).state;
        assertEqual(stateOf(spec => spec.files["/etc/h2s-shell/settings.json"] = "absent"), "found", "the module in force, nothing published: found");
        assertEqual(stateOf(spec => spec.files["/etc/h2s-shell/settings.json"] = "unreadable"), "found", "settings.json unreadable: found, not connected");
        assertEqual(readingOf(usual, changed(connected, spec => spec.files["/etc/h2s-shell/settings.json"] = "unreadable")).fileStatus, "unknown",
                    "… the file's status unknown");
        assertEqual(stateOf(spec => spec.exists["/etc/pam.d/h2s-shell-password"] = "absent"), "notConnected", "the module's PAM file missing: not connected");
        assertEqual(stateOf(spec => spec.exists["/run/current-system/sw/bin/h2s-shell"] = "unknown"), "notConnected", "a marker unknown: not connected");
        assertEqual(stateOf(spec => { spec.exists["/etc/nixos/flake.nix"] = "absent"; spec.exists["/etc/nixos/configuration.nix"] = "absent"; }),
                    "notConnected", "no configuration: not connected");
        reading = readingOf(usual, changed(connected, spec => spec.files["/etc/h2s-shell/settings.json"] = "absent"));
        assertEqual(reading.facts.map(row => row.name).includes("Generations"), false, "the generations shown only while connected");
        reading = readingOf(usual, changed(connected, spec => { spec.exists["/etc/nixos/flake.nix"] = "absent"; spec.exists["/etc/nixos/configuration.nix"] = "absent"; }));
        assertEqual(reading.facts.length + " " + reading.homeWarning + " " + reading.owner, "0 false ", "no configuration: no facts, no warning");
        reading = readingOf(usual, changed(connected, spec => spec.files["/etc/nixos/h2s-shell.json"] = "absent"));
        assertEqual(reading.fileStatus + " " + reading.file.state + " " + reading.file.sha256, "notCreated absent ", "the file not created");

        // ── A run that failed answers nothing ──
        reading = readingOf(usual, connected, { ok: false, code: 1, truncated: false });
        assertEqual(reading.state + " " + reading.configuration.problem + " " + reading.module + " " + reading.published,
                    "notConnected unknown unknown unknown", "a failed run: everything unknown");
        reading = readingOf(usual, connected, { ok: true, code: 0, truncated: true });
        assertEqual(reading.state + " " + reading.generations.count, "notConnected -1", "a cut-short run: unknown");

        // ── Generations ──
        assertEqual(JSON.stringify(rules.generations({ names: ["system-1-link", "system-x-link", "system"], end: "ok" }, "/nix/var/nix/profiles/system-1-link")),
                    JSON.stringify({ count: 1, current: 1 }), "only system-<n>-link counted; an absolute target read");
        assertEqual(JSON.stringify(rules.generations({ names: [], end: "unreadable" }, undefined)), JSON.stringify({ count: -1, current: 0 }),
                    "an unreadable profiles folder: unknown");

        // ── The host ──
        assertEqual(rules.host({ chosenFolder: "/srv/c", chosenHost: "laptop" }, { text: "nixos\n" }), "laptop", "the host chosen with the folder");
        assertEqual(rules.host({ chosenFolder: "", chosenHost: "laptop" }, { text: "nixos\n" }), "nixos", "… only with a chosen folder");
        assertEqual(rules.host({ chosenFolder: "/srv/c", chosenHost: "a b" }, { text: " nixos \n" }), "nixos", "a chosen host that is not a name: /etc/hostname's");
        assertEqual(rules.host({}, { text: "bad.name\n" }) + rules.host({}, { unreadable: true }), "", "a hostname the root step would not take, or none: unknown");
        assertEqual(readingOf(usual, changed(connected, spec => spec.files["/etc/hostname"] = "unreadable")).facts[3].value, "Unknown", "the Host fact unknown");

        // ── git ──
        assertEqual(JSON.stringify(rules.gitArgv("git", "/srv/cfg")),
                    JSON.stringify(["git", "-c", "safe.directory=/srv/cfg", "--no-optional-locks", "-C", "/srv/cfg", "ls-files", "--error-unmatch", "--", "h2s-shell.json"]),
                    "git asked read only, its repository named safe");
        assertEqual(rules.gitArgv("git", "/srv/my cfg").length + rules.gitArgv("", "/srv/cfg").length, 0, "no plain folder or no git: not asked");
        assertEqual(rules.gitAnswer({ ok: true, code: 0 }), "tracked", "0: git knows the file");
        assertEqual(rules.gitAnswer({ ok: false, code: 1, timedOut: false, cancelled: false, failedToStart: false, error: "" }), "untracked", "1: it does not");
        assertEqual(rules.gitAnswer({ ok: false, code: 128 }) + " " + rules.gitAnswer({ ok: false, code: 1, timedOut: true })
                    + " " + rules.gitAnswer({ ok: false, code: 1, failedToStart: true }) + " " + rules.gitAnswer(null),
                    "unknown unknown unknown unknown", "anything else: unknown");
        const inGit = changed(connected, spec => spec.exists["/etc/nixos/.git"] = "present");
        reading = readingOf(usual, inGit);
        assertEqual(reading.git + " " + reading.gitKnowsFile + " " + reading.facts[2].value, "present unknown Yes", "a .git beside it: in git, not asked yet");
        assertEqual(rules.withGit(reading, { ok: true, code: 0 }).gitKnowsFile, "tracked", "git's answer added");
        assertEqual(reading.gitKnowsFile, "unknown", "… to a new reading, the old one unchanged");
        assertEqual(rules.withGit(readingOf(usual, connected), { ok: true, code: 0 }).gitKnowsFile, "", "no git: nothing added");

        // ── Edges ──
        const joined = inputs => rules.readArgs(inputs).join(" ");
        assert(joined({ nixPath: "nixos-config=/srv/c/machine.nix" }).includes("exists /srv/c/machine.nix"), "nixos-config's own file name asked");
        assertEqual(joined({ nixPath: "nixos-config=/srv/my c/configuration.nix" }).includes("/srv/my c"), false, "a nixos-config that is not plain: not asked");
        assertEqual(joined({ nixPath: "nixos-config=/etc/nixos/configuration.nix" }).split("chain /etc/nixos").length, 2, "a folder asked once");
        chosen = pick({ nixPath: "nixos-config=/srv/c/machine.nix" }, { "/etc/nixos/flake.nix": "absent", "/srv/c/machine.nix": "present" });
        assertEqual(chosen.entry + " " + chosen.entryReadable, "machine.nix true", "nixos-config's entry file");
        assertEqual(pick({ nixPath: "nixos-config=/c.nix" }, { "/etc/nixos/flake.nix": "absent", "/c.nix": "present" }).folder, "/", "… at the root: the folder /");
        assertEqual(pick(usual, {}).entryReadable, false, "nothing found: nothing readable");
        let raw = rules.records(["exists\t/a\tbogus", "exists\t/b", "x\t/c\tpresent", "sha256\t/a\tnothex", "real\t/a\trelative", "chain\t/a\t/\t0",
                                 "link\t/a\tunknown", "link\t/b", "x\t/d\t/e", "|exists\t/f\tpresent", "file\t/g\ttext", "|line", "end\t/g"], ok, ["file", "/g"]);
        assertEqual(JSON.stringify([raw.exists, raw.sha256, raw.real, raw.chain, raw.links]), JSON.stringify([{}, {}, {}, {}, {}]),
                    "malformed records and a file's lines read as nothing");
        assertEqual(raw.files["/g"].text, "line\n", "the last pair asked is a file read");
        assertEqual(rules.ownerChain({}, "/etc/nixos"), "unknown", "no chain at all: unknown");
        assertEqual(chainOf([["/etc", "0", "755"], ["/etc/nixos", "0", "755"]]), "unknown", "a chain that does not start at /: unknown");
        assertEqual(chainOf([["/", "0", "755"], ["/etc", "unknown", "755"], ["/etc/nixos", "0", "755"]]), "unknown", "an owner that could not be read: unknown");
        assertEqual(chainOf([["/", "0", "755"], ["/etc", "0", "unknown"], ["/etc/nixos", "0", "755"]]), "unknown", "a mode that could not be read: unknown");
        assertEqual(chainOf([["/", "0", "755"], ["/etc", "0", "755"], ["/etc/nixos", "0", "700"]]), "root", "mode 700, octal: root's");
        assertEqual(status(text({ version: 1, idle: { hibernateDelay: "3h" } }), text(settings({ idle: null }))), "created", "the published value null: not in force");
        assertEqual(status(text({ version: 1, idle: {} }), text(settings({ idle: 5 }))), "created", "an object against a number: not in force");
        assertEqual(status(text({ version: 1, pam: {} }), text(settings({ pam: [] }))), "created", "an object against a list: not in force");
        reading = readingOf(usual, changed(connected, spec => spec.exists["/etc/nixos/.git"] = "unreadable"));
        assertEqual(reading.git, "present", "a .git that cannot be read is still git");
        reading = readingOf(usual, changed(connected, spec => spec.files["/etc/nixos/h2s-shell.json"] = "unreadable"));
        assertEqual(reading.file.state + " " + reading.fileStatus, "unreadable unknown", "the file unreadable");
        assertEqual(readingOf(usual, changed(connected, spec => spec.files["/etc/h2s-shell/settings.json"] = "absent")).published, "absent", "nothing published");
        assertEqual(readingOf(usual, changed(connected, spec => spec.files["/etc/h2s-shell/settings.json"] = "{")).published, "unknown", "settings.json not JSON: unknown");
        assertEqual(rules.withGit(null, { ok: true }), null, "no reading: nothing added");
        reading = readingOf(usual, changed(connected, spec => spec.lists["/nix/var/nix/profiles"] = []));
        assertEqual(reading.facts[6].value, "0", "no generations: 0, not unknown");

        // ── Config keeps the choice: machine state ──
        assertEqual(typeof Config.nixos.folder + typeof Config.nixos.host + Array.isArray(Array.from(Config.nixos.homeWarningAcknowledged)),
                    "stringstringtrue", "Config's NixOS keys: folder, host, the acknowledged real paths");
    }
}
