pragma Singleton

import Quickshell
import QtQuick

// The module system's decisions about where a module comes from and what may be done with it
// (notes/plans/modules-management.md §3–§6; ModuleRules.qml has the overview): its source
// (built in, the system's, the development path, the user's root — installed by the shell or
// placed by hand), the copies it replaces, the actions its card offers, whether turning it on
// needs the user's confirmation, what removing it deletes, which repository addresses are
// accepted and the git commands that download one, git's progress lines, the record of what
// the shell installed, the built-in modules that start off, the order of the list, the marks
// beside a name and the words of a check's result. Pure: no file, no process; the host and
// the installer do the I/O. Nothing here throws on any input — paths, records and addresses
// come from outside. Checked by tests/ModuleInstallRulesTest.qml.
Singleton {
    id: root

    // The sources a module can come from (sourceOf)
    readonly property var sources: ["builtin", "system", "repository", "folder", "user", "developer"]
    // Sources whose modules are trusted without the user's confirmation: the shell's own,
    // the administrator's, and the developer's working copy (§10, 1, 5, 8)
    readonly property var exemptSources: ["builtin", "system", "developer"]
    // The longest repository address accepted (with its "#ref")
    readonly property int maxAddressLength: 1000
    // How much of a text from outside (an address, a version, a reason) a line shows
    readonly property int maxShownLength: 120
    readonly property int maxVersionLength: 40
    // The protocols git may use for a download; every other one is refused by git itself
    // (protocol.allow=never), so an address that slipped past repositoryProblem still cannot
    // reach ext:: or fd::
    readonly property var gitProtocols: ["https", "ssh", "git", "file"]

    // ---- Small helpers ----

    // Text from outside on one line, capped: control characters become spaces, bidi controls
    // go (ModuleRules._plainLine), cut with "…"
    function _plain(value, most) {
        const limit = most ?? maxShownLength;
        const line = ModuleRules._plainLine(typeof value === "string" ? value : "", 100000).trim();
        return line.length > limit ? line.slice(0, limit - 1) + "…" : line;
    }

    // An absolute path with no "." or ".." segment, trailing slashes dropped; "" for anything
    // else — a path that cannot be compared safely is never inside a root
    function _cleanPath(path) {
        if (typeof path !== "string" || !path.startsWith("/") || path.includes("\u0000"))
            return "";
        const parts = path.split("/").filter(part => part !== "");
        if (parts.some(part => part === "." || part === ".."))
            return "";
        return "/" + parts.join("/");
    }

    // Whether clean `path` is `rootPath` or below it (both cleaned; an unclean one never is)
    function _inside(path, rootPath) {
        const clean = _cleanPath(path);
        const base = _cleanPath(rootPath);
        if (clean === "" || base === "")
            return false;
        return clean === base || clean.startsWith(base === "/" ? "/" : base + "/");
    }

    function _parentOf(path) {
        const clean = _cleanPath(path);
        if (clean === "" || clean === "/")
            return "";
        const cut = clean.lastIndexOf("/");
        return cut === 0 ? "/" : clean.slice(0, cut);
    }

    function _baseName(path) {
        const clean = _cleanPath(path);
        return clean === "" || clean === "/" ? "" : clean.slice(clean.lastIndexOf("/") + 1);
    }

    // A path as a person reads it: the home directory as "~"
    function _shownPath(path, home) {
        const clean = _cleanPath(path);
        const homePath = _cleanPath(home);
        if (clean === "")
            return _plain(String(path ?? ""));
        if (homePath !== "" && homePath !== "/" && _inside(clean, homePath))
            return _plain("~" + clean.slice(homePath.length));
        return _plain(clean);
    }

    function _list(value) {
        return Array.isArray(value) ? value : [];
    }

    // ---- Paths ----

    // The places the shell's module management uses, from the data and config homes (§8b);
    // "" each when a home is not an absolute path
    function paths(dataHome, configHome) {
        const data = _cleanPath(dataHome);
        const config = _cleanPath(configHome);
        const under = (base, tail) => base === "" ? "" : (base === "/" ? "" : base) + tail;
        return {
            user: under(data, "/h2s-shell/modules"),
            versions: under(data, "/h2s-shell/module-versions"),
            staging: under(data, "/h2s-shell/module-staging"),
            record: under(data, "/h2s-shell/module-sources.json"),
            backups: under(data, "/h2s-shell/module-backups"),
            data: under(data, "/h2s-shell/module-data"),
            stores: under(config, "/h2s_shell/modules")
        };
    }

    // ---- Where a module comes from (§3) ----

    // The source of one module. `directory`: its canonical directory (what discovery found).
    // `link`: the entry in a root it was found through, { entry, isLink, target } — `entry`
    // the path in the root (not resolved), `target` the canonical directory a link leads to;
    // null when it was not found through a root entry. `roots`: { developer: [paths], user,
    // versions, builtin, system: [paths] }, canonical. `records`: parseRecord's result.
    // → { source, id, entry, isLink, target, address, ref, label }
    //   `entry` is set only for what the user root holds (what Remove may delete), `address`
    //   is what an acknowledgement compares (§5), `label` the card's words (plain text).
    // In discovery's order: the development path, the user root, the built-in place, the
    // system's places and the Nix store. A link in the user root is `repository`/`folder`
    // only when the record names its id with that kind, the link leads to
    // `<versions>/<id>/<dir>`, `<dir>` is a version the record lists, and the module was
    // loaded from there; anything else in the user root is `user`, and so is a directory
    // found nowhere known ("unknown", never trusted).
    function sourceOf(directory, link, roots, records) {
        const dir = _cleanPath(directory);
        const result = { source: "user", id: "", entry: "", isLink: false, target: "", address: dir, ref: "", label: "" };
        const finish = () => {
            result.label = sourceLabel(result);
            return result;
        };
        if (dir !== "" && _list(roots?.developer).some(path => _inside(dir, path))) {
            result.source = "developer";
            return finish();
        }
        const userRoot = _cleanPath(roots?.user);
        const entry = _cleanPath(link?.entry);
        const isLink = link?.isLink === true;
        let inUserRoot = false;
        if (userRoot !== "" && entry !== "" && _parentOf(entry) === userRoot)
            inUserRoot = true;
        else if (userRoot !== "" && !link && dir !== "" && _parentOf(dir) === userRoot)
            inUserRoot = true;
        if (inUserRoot) {
            result.entry = entry !== "" ? entry : dir;
            result.isLink = isLink;
            if (isLink) {
                result.target = _cleanPath(link?.target);
                result.address = result.target;
                const installed = _installedBy(result, dir, roots, records);
                if (installed) {
                    result.source = installed.kind;
                    result.id = _baseName(result.entry);
                    result.address = installed.address;
                    result.ref = installed.ref;
                    result.commit = installed.commit;
                }
            } else {
                result.address = result.entry;
            }
            return finish();
        }
        if (dir !== "" && _inside(dir, roots?.builtin)) {
            result.source = "builtin";
            return finish();
        }
        if (dir !== "" && (_list(roots?.system).some(path => _inside(dir, path)) || dir.startsWith("/nix/store/"))) {
            result.source = "system";
            return finish();
        }
        return finish();
    }

    // The record's entry when a user-root link is the shell's own (sourceOf), else null
    function _installedBy(found, directory, roots, records) {
        if (records?.ok !== true || !ModuleRules.isObject(records.modules))
            return null;
        const id = _baseName(found.entry);
        if (!ModuleManifestRules.validId(id) || !ModuleRules.has(records.modules, id))
            return null;
        const record = records.modules[id];
        const versionsRoot = _cleanPath(roots?.versions);
        if (versionsRoot === "" || found.target === "" || _parentOf(found.target) !== versionsRoot + "/" + id)
            return null;
        // What runs must be what the record describes: a link whose target resolves elsewhere
        // is not the shell's
        if (_cleanPath(directory) === "" || _cleanPath(directory) !== found.target)
            return null;
        const versionDirectory = _baseName(found.target);
        const version = _list(record.versions).find(each => each.dir === versionDirectory);
        if (!version)
            return null;
        return { kind: record.kind, address: record.address, ref: record.ref, commit: version.commit ?? "" };
    }

    // The card's words for a source (§3's table), plain text
    function sourceLabel(found) {
        switch (found?.source) {
        case "builtin": return "Built-in";
        case "system": return "Installed by the system — not part of h2s-shell";
        case "developer": return "Development path";
        case "repository": {
            const ref = typeof found.ref === "string" && found.ref !== "" ? found.ref
                      : (typeof found.commit === "string" ? found.commit.slice(0, 7) : "");
            return "From " + addressShown(found.address) + (ref !== "" ? " @ " + _plain(ref, maxVersionLength) : "");
        }
        case "folder": return "Copied from " + _plain(String(found.address ?? ""));
        default:
            return found?.isLink === true ? "Your link → " + (found.target ? _plain(found.target) : "?") : "Your copy";
        }
    }

    // A repository address as a card shows it: host and path, without the scheme, any user
    // name or password, ".git" and the "#ref" — "codeberg.org/anna/weather"
    function addressShown(address) {
        if (typeof address !== "string")
            return "";
        const url = address.split("#")[0];
        let shown = url;
        const withScheme = /^[a-z][a-z0-9+.-]*:\/\/(?:[^@\/]*@)?(.*)$/i.exec(url);
        const scpLike = /^[^@\/:]+@([^:\/]+):(.*)$/.exec(url);
        if (withScheme)
            shown = withScheme[1];
        else if (scpLike)
            shown = scpLike[1] + "/" + scpLike[2];
        shown = shown.replace(/\/+$/, "").replace(/\.git$/, "");
        return _plain(shown);
    }

    // Which copies each winner of an id replaces. `candidates`: in search order, each
    // { directory, id, source, version } → one entry per candidate: the later candidates with
    // its id ([{ directory, source, version }]) for a winner, [] for the others (they are
    // shown inside their winner's card). Precedence is ModuleMergeRules.precedence's.
    function replaces(candidates) {
        const list = _list(candidates);
        const order = ModuleMergeRules.precedence(list);
        return list.map((candidate, index) => {
            const id = candidate?.id ?? "";
            if (!order[index].winner || id === "")
                return [];
            return list.slice(index + 1).filter(other => other?.id === id)
                .map(other => ({ directory: String(other.directory ?? ""), source: String(other.source ?? ""), version: String(other.version ?? "") }));
        });
    }

    // The card's line for what a module replaces (replaces' entry): "Replaces the built-in copy
    // (1.2.0)", several joined; "" for none
    function replacesText(replaced) {
        const words = { builtin: "the built-in copy", system: "the system's copy", developer: "the development copy" };
        const parts = _list(replaced).map(each => {
            const what = ModuleRules.has(words, each?.source) ? words[each.source] : "another copy";
            const version = _plain(String(each?.version ?? ""), maxVersionLength);
            return version !== "" ? what + " (" + version + ")" : what;
        });
        if (parts.length === 0)
            return "";
        const joined = parts.length === 1 ? parts[0] : parts.slice(0, -1).join(", ") + " and " + parts[parts.length - 1];
        return "Replaces " + joined;
    }

    // Whether Remove is offered: for what the user root holds, never for a built-in, system or
    // development copy (§3, "Remove")
    function removable(found) {
        return ["repository", "folder", "user"].includes(found?.source) && _cleanPath(found?.entry) !== "";
    }

    // ---- The card's actions (§4) ----

    // The actions a card offers, each label with its effect (one decision, from the state at
    // the time the card is built). `status`: the module's status (statusOf: id, directory,
    // state, enabled); `found`: sourceOf's result; `context`: { runningDependents: [names],
    // needsConfirmation: bool (needsConfirmation's `needed`), update: { version, downloaded }
    // | null, autoUpdate: bool }.
    // → { row: [action], opened: [action] } — `row` the button row (main, Update, Remove),
    //   `opened` the opened card's buttons. An action: { label, effect, asks, subject } plus
    //   what it needs (`dependents`, `version`); `asks`: "none", "button" (the button's own
    //   question), "modal" (the Settings modal), "confirmation" (§5's box) or "approval" (the
    //   consent box, §6.4, for a module held for approval); `subject`
    //   { id, directory } — what it acts on.
    // A duplicate gets none (it is shown inside its winner's card). In safe mode no update
    // or check is offered (§7).
    function actionsFor(status, found, context) {
        const subject = { id: String(status?.id ?? ""), directory: String(status?.directory ?? "") };
        const row = [];
        const opened = [];
        const state = status?.state;
        if (state === "duplicate" || subject.id === "")
            return { row: row, opened: opened };
        const action = (label, effect, asks, extra) => Object.assign({ label: label, effect: effect, asks: asks, subject: subject }, extra ?? {});
        const off = !isOn(status);
        if (off) {
            // Held for approval: the consent box (§6.4's); new: the confirmation (§5)
            const asks = state === "approval" ? "approval"
                       : state === "unconfirmed" || context?.needsConfirmation === true ? "confirmation" : "none";
            row.push(action("Enable", "enable", asks));
        } else {
            const dependents = _list(context?.runningDependents).map(name => _plain(String(name ?? "")));
            row.push(action("Disable", "disable", dependents.length > 0 ? "modal" : "button", { dependents: dependents }));
        }
        const installed = found?.source === "repository" || found?.source === "folder";
        const safeMode = state === "safe-mode";
        const version = _plain(String(context?.update?.version ?? ""), maxVersionLength);
        if (installed && !safeMode && context?.update?.downloaded === true && context?.autoUpdate !== true && version !== "")
            row.push(action("Update to " + version, "update", "none", { version: version }));
        if (removable(found))
            row.push(action("Remove", "remove", "modal"));
        opened.push(action("Reload", "reload", "none"));
        if (found?.source === "repository") {
            if (!safeMode)
                opened.push(action("Check for updates", "check", "none"));
            opened.push(action("Switch version…", "switchVersion", "none"));
            opened.push(action("Backups…", "backups", "none"));
        } else if (found?.source === "folder") {
            if (!safeMode)
                opened.push(action("Copy again", "update", "none"));
            opened.push(action("Switch version…", "switchVersion", "none"));
            opened.push(action("Backups…", "backups", "none"));
        }
        return { row: row, opened: opened };
    }

    // ---- The confirmation (§5) ----

    // What an acknowledgement records for a module: { source, address, author, privileged }
    // — the source kind, where it comes from (sourceOf's `address`; a repository's without a
    // "#ref": a new tag of the same repository is the same source), the manifest's author and whether it
    // declares administrator actions
    function acknowledgementOf(found, manifest) {
        return {
            source: String(found?.source ?? ""),
            address: found?.source === "repository" ? String(found?.address ?? "").split("#")[0] : String(found?.address ?? ""),
            author: typeof manifest?.author === "string" ? manifest.author : "",
            privileged: ModuleRules.isObject(manifest?.privileged)
        };
    }

    // Whether turning a module on needs the user's confirmation. `found`: sourceOf's result;
    // `manifest`: its checked manifest ({ id, author, privileged }); `acknowledgements`:
    // ModuleHost.acknowledgements (Config.acknowledgedModulesText read) — undefined when it was
    // never written.
    // → { needed, state, reasons, baseline }
    //   built-in, system, development copies: never needed;
    //   no list yet: not needed, `baseline` true — the first start acknowledges everything it
    //     finds as it is (the host writes acknowledgementOf for each), so what ran before
    //     keeps running;
    //   no acknowledgement for the id, or one of another source or address: `unconfirmed`
    //     (reasons "new" / "source") — it starts off and asks as a new module;
    //   the same source, but the manifest now declares administrator actions the
    //     acknowledgement did not, or names another author: `approval` (reasons
    //     "privileged", "author") — held off as "Approval required".
    // A list that is not an object (null included) is read as empty: a broken list asks again,
    // never trusts.
    function needsConfirmation(found, manifest, acknowledgements) {
        const fine = { needed: false, state: "", reasons: [], baseline: false };
        if (exemptSources.includes(found?.source))
            return fine;
        if (acknowledgements === undefined)
            return Object.assign(fine, { baseline: true });
        const list = ModuleRules.isObject(acknowledgements) ? acknowledgements : {};
        const id = manifest?.id;
        const given = typeof id === "string" && ModuleRules.has(list, id) && ModuleRules.isObject(list[id]) ? list[id] : null;
        const wanted = acknowledgementOf(found, manifest);
        if (!given)
            return { needed: true, state: "unconfirmed", reasons: ["new"], baseline: false };
        if (given.source !== wanted.source || given.address !== wanted.address)
            return { needed: true, state: "unconfirmed", reasons: ["source"], baseline: false };
        const reasons = [];
        if (wanted.privileged && given.privileged !== true)
            reasons.push("privileged");
        if (wanted.author !== (typeof given.author === "string" ? given.author : ""))
            reasons.push("author");
        return reasons.length > 0 ? { needed: true, state: "approval", reasons: reasons, baseline: false } : fine;
    }

    // The acknowledgements as the config file keeps them (a JSON text) → what
    // needsConfirmation takes: undefined for "" (never written: the baseline), else an object
    // of the well-formed entries, { <id>: { source, address, author, privileged } }. A text
    // that is not a JSON object reads as {}, and an entry that is not well formed is left out:
    // what cannot be read asks again, never trusts.
    function parseAcknowledgements(text) {
        if (text === "" || text === undefined || text === null)
            return undefined;
        let data;
        try {
            data = typeof text === "string" ? JSON.parse(text) : null;
        } catch (error) {
            data = null;
        }
        const list = {};
        if (!ModuleRules.isObject(data))
            return list;
        for (const id of Object.keys(data)) {
            const entry = data[id];
            if (!ModuleManifestRules.validId(id) || !ModuleRules.isObject(entry) || !sources.includes(entry.source)
                    || typeof entry.address !== "string" || typeof entry.author !== "string" || typeof entry.privileged !== "boolean")
                continue;
            list[id] = { source: entry.source, address: entry.address, author: entry.author, privileged: entry.privileged };
        }
        return list;
    }

    // The first shell version whose config file holds the acknowledgements (Config's
    // acknowledgedModules key): a file written by it or a later one without the key was not
    // left by an older shell, and is read as {}
    readonly property string acknowledgementsSince: "2.1.0"

    // The acknowledgements from the config file: `text` its entry, `facts` { loadFailed (the
    // file could not be read), inFile (the file held the key when loaded), writtenBy (the
    // version that wrote it, "" for none) }. → undefined (never written: the baseline may be
    // written) when the entry is "" and the file holds the key or predates
    // acknowledgementsSince (or there is no file); {} when the file could not be read, or is
    // newer and lacks the key, or its writer cannot be read; else parseAcknowledgements
    function readAcknowledgements(text, facts) {
        if (facts?.loadFailed === true)
            return {};
        if (typeof text === "string" && text !== "")
            return parseAcknowledgements(text);
        if (facts?.inFile === true)
            return undefined;
        const writtenBy = typeof facts?.writtenBy === "string" ? facts.writtenBy : "";
        if (writtenBy === "")
            return undefined;
        const parse = version => {
            const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(version);
            return match ? [Number(match[1]), Number(match[2]), Number(match[3])] : null;
        };
        const written = parse(writtenBy);
        const since = parse(acknowledgementsSince);
        if (!written || !since)
            return {};
        for (let i = 0; i < 3; i++) {
            if (written[i] !== since[i])
                return written[i] < since[i] ? undefined : {};
        }
        return {};
    }

    // What the first start of a shell that confirms modules acknowledges, so that what ran
    // before keeps running without a question (§5): `modules` [{ found, manifest, enabled }],
    // the modules that count (not shadowed, a valid manifest). → { <id>: acknowledgementOf }
    // for each one that is on and needs a confirmation by its source; built-in, system and
    // development copies are never asked about and need none; one that is off then is asked
    // about when it is turned on.
    function baselineAcknowledgements(modules) {
        const list = {};
        for (const module of _list(modules)) {
            const id = module?.manifest?.id;
            if (!ModuleManifestRules.validId(id) || module.enabled !== true || exemptSources.includes(module.found?.source)
                    || !sources.includes(module.found?.source) || ModuleRules.has(list, id))
                continue;
            list[id] = acknowledgementOf(module.found, module.manifest);
        }
        return list;
    }

    // Why a module cannot be turned on yet (needsConfirmation's answer `confirmation`), in a
    // few words for `modules setEnabled`, with the command that confirms it; "" when it can.
    // `name` and `id` from its manifest (shown as plain text, capped)
    function confirmationText(name, id, confirmation) {
        if (confirmation?.needed !== true)
            return "";
        const shown = _plain(typeof name === "string" && name !== "" ? name : String(id ?? ""), 60);
        const command = " (modules confirm " + _plain(String(id ?? ""), 60) + " <directory>)";
        const reasons = _list(confirmation.reasons);
        if (confirmation.state === "approval") {
            const what = reasons.includes("privileged") && reasons.includes("author") ? "now asks for administrator rights and names another author"
                       : reasons.includes("privileged") ? "now asks for administrator rights" : "now names another author";
            return shown + " " + what + ": approve it first" + command;
        }
        return shown + (reasons.includes("source") ? " comes from another place than the one confirmed" : " is new and not part of h2s-shell")
             + ": confirm it first" + command;
    }

    // ---- What the host reads to tell sources apart (§3) ----

    // The places sourceOf compares a module's directory with, as given (not yet canonical),
    // from the shell's environment: { dataHome, modulePath (H2S_SHELL_MODULE_PATH),
    // moduleDataDirs (H2S_SHELL_MODULE_DATA_DIRS: undefined when not set, which is not the
    // same as set and empty), dataDirs (XDG_DATA_DIRS), builtin (H2S_SHELL_BUILTIN_MODULES) }
    // — the launcher's own search (scripts/launch.sh, module_roots). → { user, versions,
    // record, builtin, developer: [paths], system: [paths] }; only absolute paths, "" / [] else
    function sourcePlaces(environment) {
        const env = ModuleRules.isObject(environment) ? environment : {};
        const places = paths(env.dataHome, "/");
        const absolute = value => typeof value === "string" && value.startsWith("/") && !value.includes("\u0000") ? value : "";
        const split = value => typeof value === "string" ? value.split(":").map(absolute).filter(path => path !== "") : [];
        const dataDirs = typeof env.moduleDataDirs === "string" ? env.moduleDataDirs
                       : typeof env.dataDirs === "string" && env.dataDirs !== "" ? env.dataDirs : "/usr/local/share:/usr/share";
        return {
            user: places.user, versions: places.versions, record: places.record,
            builtin: absolute(env.builtin),
            developer: split(env.modulePath),
            system: split(dataDirs).map(path => path.replace(/\/+$/, "") + "/h2s-shell/modules")
        };
    }

    // The shell script that reads them (the host's source check, run as the user, under a
    // time limit): arguments the user root, the versions root, the built-in root, the record
    // file, then pairs "developer <path>" / "system <path>". Prints, tab-separated:
    //   root <kind> <canonical path> <owner uid> <writable 1|0>
    //                                          each root that resolves (cd -P), who owns it
    //                                          and whether the user can write it
    //   entry <link|dir> <path> <canonical>    each entry of the user root (at most 400), its
    //                                          path under the canonical root, where it leads
    //                                          ("" when nowhere: a dangling link, a file)
    //   builtin <line> / builtin-state <missing|ok|unreadable>   builtin.json (64 KiB at most)
    //   record <line> / record-state <…>       the record (256 KiB at most)
    //   end                                    it got to the end
    // A path holding a tab or a line break is left out.
    readonly property string sourceCheckScript: "tab=$(printf '\\t'); nl=$(printf '\\nx'); nl=${nl%x}; "
        + "canon() { (cd -P -- \"$1\" 2>/dev/null && pwd); }; "
        + "plain() { case \"$1\" in *\"$tab\"*|*\"$nl\"*) return 1 ;; esac; return 0; }; "
        + "root() { [ -n \"$2\" ] || return 0; real=$(canon \"$2\") || return 0; plain \"$real\" || return 0; "
        + "owner=$(stat -c %u -- \"$real\" 2>/dev/null) || owner=; writable=0; [ -w \"$real\" ] && writable=1; "
        + "printf 'root\\t%s\\t%s\\t%s\\t%s\\n' \"$1\" \"$real\" \"$owner\" \"$writable\"; }; "
        + "user=$1; versions=$2; builtin=$3; record=$4; shift 4; "
        + "root user \"$user\"; root versions \"$versions\"; root builtin \"$builtin\"; "
        + "while [ $# -ge 2 ]; do root \"$1\" \"$2\"; shift 2; done; "
        + "base=; if [ -n \"$user\" ]; then base=$(canon \"$user\") || base=; fi; "
        + "if [ -n \"$base\" ] && plain \"$base\"; then count=0; for path in \"$base\"/*; do "
        + "[ -e \"$path\" ] || [ -L \"$path\" ] || continue; count=$((count + 1)); [ \"$count\" -le 400 ] || break; "
        + "plain \"$path\" || continue; kind=dir; [ -L \"$path\" ] && kind=link; "
        + "target=$(canon \"$path\") || target=; plain \"$target\" || target=; "
        + "printf 'entry\\t%s\\t%s\\t%s\\n' \"$kind\" \"$path\" \"$target\"; done; fi; "
        + "file() { if [ -z \"$2\" ] || { [ ! -e \"$2\" ] && [ ! -L \"$2\" ]; }; then printf '%s-state\\tmissing\\n' \"$1\"; return 0; fi; "
        + "if [ ! -f \"$2\" ] || ! text=$(head -c \"$3\" -- \"$2\" 2>/dev/null); then printf '%s-state\\tunreadable\\n' \"$1\"; return 0; fi; "
        + "printf '%s\\n' \"$text\" | while IFS= read -r line; do printf '%s\\t%s\\n' \"$1\" \"$line\"; done; "
        + "printf '%s-state\\tok\\n' \"$1\"; }; "
        + "file builtin \"${builtin:+$builtin/builtin.json}\" 65536; file record \"$record\" 262144; echo end"

    // What the launcher's H2S_SHELL_DISCOVERY says to the shell in `shellDirectory`:
    // { launched — the launcher started this shell (its directory named), searched — and its
    // search answered }. Anything else (unset, another directory: a shell started by hand that
    // inherited it) is neither
    function discoveryOf(value, shellDirectory) {
        const text = typeof value === "string" ? value : "";
        const cut = text.indexOf(" ");
        const word = cut < 0 ? "" : text.slice(0, cut);
        const directory = _cleanPath(cut < 0 ? "" : text.slice(cut + 1));
        const own = _cleanPath(String(shellDirectory ?? "").replace(/^file:\/\//, ""));
        const launched = directory !== "" && directory === own && (word === "ok" || word === "failed");
        return { launched: launched, searched: launched && word === "ok" };
    }

    // The arguments of sourceCheckScript for sourcePlaces' result
    function sourceCheckArguments(places) {
        const given = ModuleRules.isObject(places) ? places : {};
        const text = value => typeof value === "string" ? value : "";
        const pairs = [];
        for (const path of _list(given.developer))
            pairs.push("developer", text(path));
        for (const path of _list(given.system))
            pairs.push("system", text(path));
        return [text(given.user), text(given.versions), text(given.builtin), text(given.record)].concat(pairs);
    }

    // What sourceCheckScript printed (its lines) → { complete, roots: { developer: [], user,
    // versions, builtin, system: [] } (canonical; a system root only when root owns it and
    // the user cannot write it — anything else there is the user's to change, so its modules
    // count as placed by hand), entries: [{ entry, isLink, target }],
    // builtin: { state, text }, record: { state, text } }. Not `complete` (cut off, failed):
    // nothing in it is used — every module is then "user", the unknown, never trusted.
    function parseSourceCheck(lines) {
        const empty = () => ({
            complete: false, roots: { developer: [], user: "", versions: "", builtin: "", system: [] }, entries: [],
            builtin: { state: "missing", text: "" }, record: { state: "missing", text: "" }
        });
        const result = empty();
        const texts = { builtin: [], record: [] };
        for (const raw of _list(lines)) {
            const line = typeof raw === "string" ? raw : "";
            const fields = line.split("\t");
            if (line === "end") {
                result.complete = true;
            } else if (fields[0] === "root" && fields.length === 5 && _cleanPath(fields[2]) !== "") {
                if (fields[1] === "system" && !(fields[3] === "0" && fields[4] === "0")) {
                    continue;
                } else if (fields[1] === "developer" || fields[1] === "system") {
                    if (!result.roots[fields[1]].includes(fields[2]))
                        result.roots[fields[1]].push(fields[2]);
                } else if (["user", "versions", "builtin"].includes(fields[1])) {
                    result.roots[fields[1]] = fields[2];
                }
            } else if (fields[0] === "entry" && fields.length === 4 && _cleanPath(fields[2]) !== "" && result.entries.length < 400) {
                result.entries.push({ entry: fields[2], isLink: fields[1] === "link", target: _cleanPath(fields[3]) });
            } else if ((fields[0] === "builtin" || fields[0] === "record") && fields.length >= 2) {
                texts[fields[0]].push(line.slice(fields[0].length + 1));
            } else if ((fields[0] === "builtin-state" || fields[0] === "record-state") && ["missing", "ok", "unreadable"].includes(fields[1])) {
                const which = fields[0].replace("-state", "");
                result[which] = { state: fields[1], text: fields[1] === "ok" ? texts[which].join("\n") : "" };
            }
        }
        return result.complete ? result : empty();
    }

    // The user root's entry a module's canonical directory was found through (an entry of
    // parseSourceCheck's), as sourceOf takes it: { entry, isLink, target }, or null
    function linkFor(directory, entries) {
        const dir = _cleanPath(directory);
        if (dir === "")
            return null;
        const found = _list(entries).find(each => each?.target === dir);
        return found ? { entry: found.entry, isLink: found.isLink === true, target: found.target } : null;
    }

    // ---- Remove (§4, "Remove") ----

    // What removing a module deletes. `found`: sourceOf's result; `module`: { id, name,
    // version }; `record`: the record's entry for it (parseRecord's modules[id]) or null;
    // `options`: { withData, dataHome, configHome, home, dependents: { hard: [names], soft:
    // [names] }, alsoRemove: [{ found, module, record }] }.
    // → { ok, reason, subject: { id, entry }, title, lines, steps, also }
    //   `steps` in order, each { op, … }: "disable" { id }; "unlink" { path } — removes the
    //   link itself, never its target; "deleteTree" { path } — a directory the shell owns,
    //   never followed through a link at its top; "dropRecord" { id }; "dropAcknowledgement"
    //   { id }; "deleteSettings" { prefix } (mod.<id>. in every profile).
    //   A link placed by hand: the link only. A folder placed by hand: that folder. Installed
    //   by the shell: its link and every kept version. With data: its data directory, store,
    //   backups and settings. `also`: the plans of the dependencies chosen with it, each with
    //   the same data choice.
    // Refused (ok false) for anything the user root does not hold, an invalid id, or paths
    // that do not lie where the shell puts them — nothing is planned then.
    function removalPlan(found, module, record, options) {
        const id = String(module?.id ?? "");
        const refused = reason => ({ ok: false, reason: reason, subject: { id: id, entry: "" }, title: "", lines: [], steps: [], also: [] });
        if (!removable(found))
            return refused(found?.source === "builtin" ? "A built-in module cannot be removed"
                         : found?.source === "system" ? "Change it in the system's configuration"
                         : found?.source === "developer" ? "A module on the development path cannot be removed here"
                         : "It is not in your modules folder");
        if (!ModuleManifestRules.validId(id))
            return refused("Not a module id");
        const places = paths(options?.dataHome, options?.configHome);
        const entry = _cleanPath(found.entry);
        if (places.user === "" || _parentOf(entry) !== places.user)
            return refused("It is not in your modules folder");
        const installed = found.source === "repository" || found.source === "folder";
        if (installed && (_baseName(entry) !== id || places.versions === "" || !found.isLink))
            return refused("The record does not match what is on disk");
        const name = _plain(String(module?.name ?? "")) || id;
        const version = _plain(String(module?.version ?? ""), maxVersionLength);
        const steps = [{ op: "disable", id: id }];
        const lines = [];
        if (installed) {
            steps.push({ op: "unlink", path: entry });
            steps.push({ op: "deleteTree", path: places.versions + "/" + id });
            steps.push({ op: "dropRecord", id: id });
            const activeDir = record?.active;
            const kept = _list(record?.versions).filter(each => each?.dir !== activeDir)
                .map(each => _plain(String(each?.version ?? ""), maxVersionLength)).filter(text => text !== "");
            lines.push("Deletes " + name + (version !== "" ? " " + version : "")
                       + (kept.length > 0 ? " and the kept versions (" + kept.join(", ") + ")." : "."));
        } else if (found.isLink) {
            steps.push({ op: "unlink", path: entry });
            lines.push("Not installed by the shell.");
            lines.push("Deletes only the link; " + (found.target ? _shownPath(found.target, options?.home) : "its target") + " stays.");
        } else {
            steps.push({ op: "deleteTree", path: entry });
            lines.push("Not installed by the shell.");
            lines.push("Deletes the folder " + _shownPath(entry, options?.home) + ".");
        }
        steps.push({ op: "dropAcknowledgement", id: id });
        if (options?.withData === true) {
            for (const base of [places.data, places.stores, places.backups])
                if (base !== "")
                    steps.push({ op: "deleteTree", path: base + "/" + id });
            steps.push({ op: "deleteSettings", prefix: "mod." + id + "." });
            lines.push("Its data and settings are deleted too.");
        }
        const hard = _list(options?.dependents?.hard).map(each => _plain(String(each ?? ""))).filter(text => text !== "");
        const soft = _list(options?.dependents?.soft).map(each => _plain(String(each ?? ""))).filter(text => text !== "");
        if (hard.length > 0)
            lines.push("These stop working: " + hard.join(", ") + ".");
        if (soft.length > 0)
            lines.push("These lose a feature: " + soft.join(", ") + ".");
        const also = _list(options?.alsoRemove).map(each =>
            removalPlan(each?.found, each?.module, each?.record, Object.assign({}, options, { dependents: null, alsoRemove: [] })));
        return { ok: true, reason: "", subject: { id: id, entry: entry }, title: "Remove " + name + "?", lines: lines, steps: steps, also: also };
    }

    // The checkbox offering a dependency installed for a module with its removal (§6.9)
    function alsoRemoveLabel(name, forName) {
        return "Also remove " + _plain(String(name ?? "")) + " (installed for " + _plain(String(forName ?? "")) + ", nothing else uses it)";
    }

    // ---- Repository addresses and the download (§6.2) ----

    // Why an address is refused, "" when it is accepted: https://, ssh://, git://, file:// or
    // user@host:path, optionally "#<ref>". Refused: no text, over 1000 characters, control
    // characters, a leading "-" (an option to git), "<transport>::" forms (ext:: and fd:: run
    // commands), other schemes, a host or path starting with "-" (ssh would read it as an
    // option), a ref that is no plain ref name.
    function repositoryProblem(address) {
        if (typeof address !== "string" || address.trim() === "")
            return "No address given";
        if (address.length > maxAddressLength)
            return "The address is longer than " + maxAddressLength + " characters";
        if (/[\u0000-\u001f\u007f]/.test(address))
            return "The address contains control characters";
        if (address.startsWith("-"))
            return "The address starts with \"-\"";
        if (/^[A-Za-z][A-Za-z0-9+.-]*::/.test(address))
            return "Addresses that name a git transport (\"ext::\", \"fd::\") are not accepted";
        const parts = splitAddress(address);
        if (address.includes("#")) {
            const refProblem = _refProblem(parts.ref);
            if (refProblem !== "")
                return refProblem;
        }
        const url = parts.url;
        const scheme = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/(.*)$/.exec(url);
        if (scheme) {
            const kind = scheme[1].toLowerCase();
            if (!gitProtocols.includes(kind))
                return "Only https, ssh, git and file addresses are accepted";
            const rest = scheme[2];
            if (kind === "file")
                return /^\/[^\/]/.test(rest) || rest === "/" ? "" : "A file address needs an absolute path (file:///…)";
            const slash = rest.indexOf("/");
            const authority = slash < 0 ? rest : rest.slice(0, slash);
            const at = authority.lastIndexOf("@");
            const user = at < 0 ? "" : authority.slice(0, at);
            // ssh would read a user name starting with "-" as an option
            if (at >= 0 && kind !== "https" && (user === "" || user.startsWith("-") || !/^[A-Za-z0-9._-]+$/.test(user)))
                return "The address names no valid user";
            const hostAndPort = /^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+)(?::(\d{1,5}))?$/.exec(authority.slice(at + 1));
            if (!hostAndPort || hostAndPort[1].startsWith("-"))
                return "The address names no valid host";
            if (slash < 0 || rest.slice(slash + 1) === "")
                return "The address names no repository";
            return "";
        }
        const scpLike = /^([A-Za-z0-9._-]+)@([^:\/]+):(.*)$/.exec(url);
        if (scpLike) {
            if (scpLike[2].startsWith("-") || !/^[A-Za-z0-9.-]+$/.test(scpLike[2]))
                return "The address names no valid host";
            if (scpLike[3] === "" || scpLike[3].startsWith("-"))
                return "The address names no repository";
            return "";
        }
        return "Not a repository address";
    }

    // Why a ref after "#" is refused, "" when it is a plain ref name: a tag, a branch or a
    // commit id
    function _refProblem(ref) {
        if (typeof ref !== "string" || ref === "")
            return "Nothing after \"#\"";
        if (ref.startsWith("-") || ref.includes("..") || ref.includes("//") || ref.endsWith("/") || ref.endsWith(".")
                || ref.endsWith(".lock") || !/^[A-Za-z0-9._\/+-]+$/.test(ref))
            return "Not a tag, branch or commit after \"#\"";
        return "";
    }

    // An address split at its first "#": { url, ref } (ref "" for none)
    function splitAddress(address) {
        const text = typeof address === "string" ? address : "";
        const cut = text.indexOf("#");
        return cut < 0 ? { url: text, ref: "" } : { url: text.slice(0, cut), ref: text.slice(cut + 1) };
    }

    // Whether a ref is a full commit id (SHA-1 or SHA-256), fetched by id instead of cloned
    function isCommitId(ref) {
        return typeof ref === "string" && /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(ref);
    }

    // The environment every git command of a download runs with: no terminal prompt, no
    // askpass program, ssh in batch mode (with _gitConfig's options, no credential prompt of
    // any kind), and git-lfs never fetching: its downloads would go past the protocol list and
    // the size cap
    readonly property var gitEnvironment: ({
        GIT_TERMINAL_PROMPT: "0",
        GIT_ASKPASS: "",
        SSH_ASKPASS: "",
        GIT_SSH_COMMAND: "ssh -o BatchMode=yes",
        GIT_LFS_SKIP_SMUDGE: "1"
    })

    // git's options before the subcommand: no hooks, no credential helper or askpass from the
    // user's configuration (a helper can prompt), no git-lfs filter, only the listed protocols
    function _gitConfig() {
        const config = ["-c", "core.hooksPath=/dev/null", "-c", "credential.helper=", "-c", "core.askPass=",
                        "-c", "filter.lfs.process=", "-c", "filter.lfs.smudge=", "-c", "filter.lfs.required=false",
                        "-c", "protocol.allow=never"];
        for (const protocol of gitProtocols)
            config.push("-c", "protocol." + protocol + ".allow=always");
        return config;
    }

    // The commands that download `address` into `directory` (a new, empty staging directory),
    // each { argv, environment } — an argv array, the address always after "--", never a shell
    // string. A branch or tag: one shallow clone; a commit id: init, a shallow fetch of that
    // commit and a checkout of it. No submodules, no hooks.
    // → { ok, problem, commands } — refused (no commands) for an address repositoryProblem
    //   refuses or a directory that is not an absolute path.
    function downloadCommands(address, directory) {
        const problem = repositoryProblem(address);
        if (problem !== "")
            return { ok: false, problem: problem, commands: [] };
        const target = _cleanPath(directory);
        if (target === "" || target === "/")
            return { ok: false, problem: "The download directory is not an absolute path", commands: [] };
        const parts = splitAddress(address);
        const config = _gitConfig();
        const command = argv => ({ argv: argv, environment: Object.assign({}, gitEnvironment) });
        if (isCommitId(parts.ref))
            return { ok: true, problem: "", commands: [
                command(["git"].concat(config, ["init", "--quiet", "--", target])),
                command(["git", "-C", target].concat(config, ["fetch", "--progress", "--depth", "1", "--no-recurse-submodules", "--", parts.url, parts.ref])),
                command(["git", "-C", target].concat(config, ["checkout", "--quiet", "--detach", "FETCH_HEAD"]))
            ] };
        const branch = parts.ref !== "" ? ["--branch", parts.ref] : [];
        return { ok: true, problem: "", commands: [
            command(["git"].concat(config, ["clone", "--progress", "--depth", "1", "--no-recurse-submodules"], branch, ["--", parts.url, target]))
        ] };
    }

    // ---- git's progress (§6.2) ----

    readonly property var _sizeUnits: ({ "bytes": 1, "B": 1, "KiB": 1024, "MiB": 1024 * 1024, "GiB": 1024 * 1024 * 1024, "TiB": 1024 * 1024 * 1024 * 1024 })

    // One line of git's progress (its standard error) → { phase, percent, bytes, rate, done },
    // or null for a line that is no progress. git redraws a line with "\r": the last part
    // counts. `phase`: the first word, lower case ("receiving", "resolving", "counting",
    // "compressing", …); `bytes` and `rate` (per second) in bytes, null where git gives none.
    //   "Receiving objects:  45% (120/266), 1.20 MiB | 2.40 MiB/s"
    //     → { phase: "receiving", percent: 45, bytes: 1258291, rate: 2516582, done: false }
    function progressOf(line) {
        if (typeof line !== "string" || line.length > 4000)
            return null;
        const parts = line.split(/[\r\n]/).map(part => part.trim()).filter(part => part !== "");
        let text = parts.length > 0 ? parts[parts.length - 1] : "";
        text = text.replace(/^remote:\s*/, "");
        const match = /^([A-Za-z]+)(?: [A-Za-z]+)*:\s+(\d{1,3})% \((\d+)\/(\d+)\)(.*)$/.exec(text);
        if (!match)
            return null;
        const rest = match[5];
        const size = /^,\s*([\d.]+)\s*(bytes|B|KiB|MiB|GiB|TiB)(?:\s*\|\s*([\d.]+)\s*(bytes|B|KiB|MiB|GiB|TiB)\/s)?/.exec(rest);
        const amount = (number, unit) => {
            const value = Number(number);
            return Number.isFinite(value) && ModuleRules.has(_sizeUnits, unit) ? Math.round(value * _sizeUnits[unit]) : null;
        };
        return {
            phase: match[1].toLowerCase(),
            percent: Math.min(100, Number(match[2])),
            bytes: size ? amount(size[1], size[2]) : null,
            rate: size && size[3] !== undefined ? amount(size[3], size[4]) : null,
            done: /,\s*done\.?$/.test(rest)
        };
    }

    // ---- The record of what the shell installed (§6.2) ----

    // module-sources.json's text → { ok, modules: { <id>: entry }, dropped: [ids] }. Text
    // that is no JSON object: ok false, no modules — every module then reads as `user`
    // ("unknown", never "fine": no update, no switch). An entry that is not well formed is
    // dropped (named in `dropped`) and its module reads as `user` too. An entry:
    // { kind: "repository" | "folder", address, ref, versions: [{ dir, version, commit,
    //   fetchedAt }], active, refused: { version, commit } | null, installedFor, checkedAt }
    function parseRecord(text) {
        let data;
        try {
            data = typeof text === "string" ? JSON.parse(text) : null;
        } catch (error) {
            data = null;
        }
        if (!ModuleRules.isObject(data))
            return { ok: false, modules: {}, dropped: [] };
        const modules = {};
        const dropped = [];
        for (const id of Object.keys(data)) {
            const entry = ModuleManifestRules.validId(id) ? _recordEntry(data[id]) : null;
            if (entry)
                modules[id] = entry;
            else
                dropped.push(_plain(id, 40));
        }
        return { ok: true, modules: modules, dropped: dropped };
    }

    // One record entry checked and copied, or null
    function _recordEntry(raw) {
        if (!ModuleRules.isObject(raw) || !["repository", "folder"].includes(raw.kind))
            return null;
        const ref = raw.ref === undefined || raw.ref === null ? "" : raw.ref;
        if (typeof raw.address !== "string" || typeof ref !== "string")
            return null;
        if (raw.kind === "repository" && (raw.address.includes("#") || repositoryProblem(raw.address) !== "" || (ref !== "" && _refProblem(ref) !== "")))
            return null;
        if (raw.kind === "folder" && _cleanPath(raw.address) === "")
            return null;
        if (!Array.isArray(raw.versions) || raw.versions.length === 0 || raw.versions.length > 16)
            return null;
        const versions = [];
        for (const each of raw.versions) {
            if (!ModuleRules.isObject(each) || !_versionDirectory(each.dir) || typeof each.version !== "string" || each.version.length > 64)
                return null;
            const commit = each.commit === undefined || each.commit === null ? "" : each.commit;
            if (typeof commit !== "string" || !/^[0-9a-f]{0,64}$/.test(commit))
                return null;
            if (versions.some(other => other.dir === each.dir))
                return null;
            versions.push({ dir: each.dir, version: each.version, commit: commit,
                            fetchedAt: typeof each.fetchedAt === "string" || typeof each.fetchedAt === "number" ? each.fetchedAt : "" });
        }
        if (typeof raw.active !== "string" || !versions.some(each => each.dir === raw.active))
            return null;
        let refused = null;
        if (raw.refused !== undefined && raw.refused !== null) {
            if (!ModuleRules.isObject(raw.refused) || typeof raw.refused.version !== "string")
                return null;
            refused = { version: raw.refused.version, commit: typeof raw.refused.commit === "string" ? raw.refused.commit : "" };
        }
        const installedFor = raw.installedFor === undefined || raw.installedFor === null ? "" : raw.installedFor;
        if (installedFor !== "" && !ModuleManifestRules.validId(installedFor))
            return null;
        return {
            kind: raw.kind, address: raw.address, ref: ref, versions: versions, active: raw.active, refused: refused,
            installedFor: installedFor,
            checkedAt: typeof raw.checkedAt === "string" || typeof raw.checkedAt === "number" ? raw.checkedAt : ""
        };
    }

    // A version directory's name: one path segment, as the installer makes them
    // ("<version>-<commit7>", "<version>-<date>")
    function _versionDirectory(name) {
        return typeof name === "string" && name.length <= 100 && /^[A-Za-z0-9._+-]+$/.test(name)
            && !name.startsWith("-") && name !== "." && name !== "..";
    }

    // ---- Built-in modules that start off (§3) ----

    // builtin.json's text, { "off": [ids] } → { ok, off: [ids] }. Unreadable or not that form:
    // ok false, none off (the host logs it); an entry that is no valid id is skipped.
    function builtinOff(text) {
        let data;
        try {
            data = typeof text === "string" ? JSON.parse(text) : null;
        } catch (error) {
            data = null;
        }
        if (!ModuleRules.isObject(data) || !Array.isArray(data.off))
            return { ok: false, off: [] };
        const off = [];
        for (const id of data.off)
            if (ModuleManifestRules.validId(id) && !off.includes(id))
                off.push(id);
        return { ok: true, off: off };
    }

    // Whether a module is on by the user's lists: off when Config.disabledModules names it; a
    // built-in one that builtin.json lists as off only when Config.enabledModules names it;
    // anything else on
    function enabledByLists(id, source, offIds, enabledModules, disabledModules) {
        if (_list(disabledModules).includes(id))
            return false;
        if (source === "builtin" && _list(offIds).includes(id))
            return _list(enabledModules).includes(id);
        return true;
    }

    // ---- The list (§4) ----

    // Whether a module counts as on (the card's main button, the list's first group): not
    // turned off, not waiting for the user's confirmation or approval
    function isOn(status) {
        return status?.enabled !== false && !["disabled", "unconfirmed", "approval"].includes(status?.state);
    }

    // The cards' order: the ids of `statuses` (statusOf), enabled modules first, then the
    // disabled, unconfirmed and held ones (isOn), each group by name (case-insensitive), then by id.
    // Duplicates are left out: they show inside their winner's card.
    function listOrder(statuses) {
        const shown = _list(statuses).filter(status => ModuleRules.isObject(status) && typeof status.id === "string"
                                                       && status.id !== "" && status.state !== "duplicate");
        const nameOf = status => String(typeof status.name === "string" && status.name !== "" ? status.name : status.id).toLowerCase();
        return shown.slice().sort((first, second) => {
            const group = (isOn(first) ? 0 : 1) - (isOn(second) ? 0 : 1);
            if (group !== 0)
                return group;
            const byName = nameOf(first) < nameOf(second) ? -1 : nameOf(first) > nameOf(second) ? 1 : 0;
            if (byName !== 0)
                return byName;
            return first.id < second.id ? -1 : first.id > second.id ? 1 : 0;
        }).map(status => status.id);
    }

    // The marks beside a name: [{ kind, count, tip }] for the warnings ("warning") and the
    // deprecated API uses ("deprecation") a status lists, only those with a count
    function marks(status) {
        const result = [];
        const warnings = _list(status?.warnings).length;
        const deprecations = _list(status?.deprecations).length;
        if (warnings > 0)
            result.push({ kind: "warning", count: warnings, tip: warnings + (warnings === 1 ? " warning" : " warnings") });
        if (deprecations > 0)
            result.push({ kind: "deprecation", count: deprecations,
                          tip: deprecations + (deprecations === 1 ? " deprecated API use" : " deprecated API uses") });
        return result;
    }

    // ---- A check's result (§6.3) ----

    // A moment as the local "14:32"
    function _clock(ms) {
        const moment = new Date(Number(ms));
        if (!Number.isFinite(moment.getTime()))
            return "";
        const pad = number => (number < 10 ? "0" : "") + number;
        return pad(moment.getHours()) + ":" + pad(moment.getMinutes());
    }

    // The card's line after a check. `result`: { outcome: "current" | "available" | "failed",
    // checkedAt (ms), version, downloading, reason } → "Up to date · checked 14:32",
    // "1.3.0 available — downloading", "1.3.0 available", "Check failed: <reason>"; "" for
    // no result
    function checkResultText(result) {
        switch (result?.outcome) {
        case "current": {
            const at = _clock(result.checkedAt);
            return "Up to date" + (at !== "" ? " · checked " + at : "");
        }
        case "available": {
            const version = _plain(String(result.version ?? ""), maxVersionLength);
            return (version !== "" ? version : "A new version") + " available" + (result.downloading === true ? " — downloading" : "");
        }
        case "failed": {
            const reason = _plain(String(result.reason ?? ""));
            return "Check failed" + (reason !== "" ? ": " + reason : "");
        }
        default:
            return "";
        }
    }

    // The line at the top after "Check all": "2 updates · 1 up to date · 1 failed", the parts
    // with a count only; "" for no results
    function checkSummaryText(results) {
        const count = outcome => _list(results).filter(result => result?.outcome === outcome).length;
        const updates = count("available");
        const current = count("current");
        const failed = count("failed");
        const parts = [];
        if (updates > 0)
            parts.push(updates + (updates === 1 ? " update" : " updates"));
        if (current > 0)
            parts.push(current + " up to date");
        if (failed > 0)
            parts.push(failed + " failed");
        return parts.join(" · ");
    }

    // "Check all" while it runs: "Checking 2 of 4…" (`current` the one being checked, from 1)
    function checkingText(current, total) {
        const all = Math.max(0, Math.floor(Number(total) || 0));
        const now = Math.min(all, Math.max(1, Math.floor(Number(current) || 0)));
        return all === 0 ? "Checking…" : "Checking " + now + " of " + all + "…";
    }
}
