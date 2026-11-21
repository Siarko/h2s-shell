import QtQuick
import Quickshell.Io
import qs.singletons

// ModuleInstallRules (pure): where a module comes from, the copies it replaces, a card's
// actions, the confirmation, what Remove deletes, which repository addresses are accepted and
// the git commands of a download, git's progress lines, the record, builtin.json, the list's
// order, the marks and a check's words — on the layouts of NixOS and Arch and on hostile
// input. Nothing here may throw.
TestCase {
    id: suite
    suiteName: "ModuleInstallRules"

    readonly property string home: "/home/anna"
    // builtin.json as the repository ships it (builtin-modules/)
    property var _shippedBuiltin: FileView {
        path: Qt.resolvedUrl("../builtin-modules/builtin.json")
        blockLoading: true
    }
    readonly property var places: ModuleInstallRules.paths(home + "/.local/share", home + "/.config")
    readonly property var roots: ({
        developer: [home + "/dev/modules"],
        user: places.user,
        versions: places.versions,
        builtin: home + "/.local/share/h2s-shell/builtin",
        system: ["/usr/share/h2s-shell/modules", "/run/current-system/sw/share/h2s-shell/modules"]
    })
    readonly property string weatherCommit: "abcdef1234567890abcdef1234567890abcdef12"

    function _recordText() {
        return JSON.stringify({
            weather: { kind: "repository", address: "https://codeberg.org/anna/weather.git", ref: "v1.2.0",
                       versions: [{ dir: "1.2.0-abcdef1", version: "1.2.0", commit: weatherCommit, fetchedAt: "2026-11-20T10:00:00Z" },
                                  { dir: "1.1.0-1234567", version: "1.1.0", commit: "1234567" }],
                       active: "1.2.0-abcdef1", refused: null, installedFor: "", checkedAt: "" },
            notes: { kind: "folder", address: home + "/src/notes", ref: "",
                     versions: [{ dir: "0.3.0-20261120", version: "0.3.0", commit: "" }], active: "0.3.0-20261120" },
            clipboard: { kind: "repository", address: "git@github.com:anna/h2s-clipboard.git", ref: "",
                         versions: [{ dir: "0.2.0-1a2b3c4", version: "0.2.0", commit: "1a2b3c4d" }], active: "0.2.0-1a2b3c4", installedFor: "notes" }
        });
    }

    function _source(directory, link, records) {
        return ModuleInstallRules.sourceOf(directory, link, roots, records ?? ModuleInstallRules.parseRecord(_recordText()));
    }

    function _weatherLink() {
        return { entry: places.user + "/weather", isLink: true, target: places.versions + "/weather/1.2.0-abcdef1" };
    }

    function run() {
        _paths();
        _sources();
        _replacing();
        _actions();
        _confirmation();
        _removal();
        _addresses();
        _download();
        _progress();
        _record();
        _builtin();
        _hostReads();
        _list();
        _checks();
        _installerSteps();
    }

    function _paths() {
        assertEqual(JSON.stringify(places), JSON.stringify({
            user: "/home/anna/.local/share/h2s-shell/modules", versions: "/home/anna/.local/share/h2s-shell/module-versions",
            staging: "/home/anna/.local/share/h2s-shell/module-staging", record: "/home/anna/.local/share/h2s-shell/module-sources.json",
            backups: "/home/anna/.local/share/h2s-shell/module-backups", data: "/home/anna/.local/share/h2s-shell/module-data",
            stores: "/home/anna/.config/h2s_shell/modules" }), "paths: every place under the data and config homes (§8b)");
        assertEqual(ModuleInstallRules.paths("/home/anna/.local/share/", "/x").user, places.user, "… a trailing slash makes no difference");
        const bad = ModuleInstallRules.paths("relative", null);
        assertEqual(bad.user + bad.stores + ModuleInstallRules.paths("/a/../b", "/c").user, "", "… a home that is not a clean absolute path: no places");
    }

    function _sources() {
        const rules = ModuleInstallRules;
        const records = rules.parseRecord(_recordText());

        // Installed by the shell: the link, the record, a listed version, loaded from there
        let found = _source(places.versions + "/weather/1.2.0-abcdef1", _weatherLink());
        assertEqual(found.source + " " + found.id + " " + found.entry, "repository weather " + places.user + "/weather", "the shell's link with its record: repository");
        assertEqual(found.label, "From codeberg.org/anna/weather @ v1.2.0", "… \"From <host/path> @ <ref>\"");
        assertEqual(found.address, "https://codeberg.org/anna/weather.git", "… the address an acknowledgement compares");
        found = _source(places.versions + "/weather/1.1.0-1234567",
                        { entry: places.user + "/weather", isLink: true, target: places.versions + "/weather/1.1.0-1234567" });
        assertEqual(found.source, "repository", "… a kept version the record lists: repository too");
        found = _source(places.versions + "/clipboard/0.2.0-1a2b3c4",
                        { entry: places.user + "/clipboard", isLink: true, target: places.versions + "/clipboard/0.2.0-1a2b3c4" });
        assertEqual(found.label, "From github.com/anna/h2s-clipboard @ 1a2b3c4", "… no ref: the commit, an scp-like address shown as host/path");
        found = _source(places.versions + "/notes/0.3.0-20261120",
                        { entry: places.user + "/notes", isLink: true, target: places.versions + "/notes/0.3.0-20261120" });
        assertEqual(found.source + " | " + found.label, "folder | Copied from /home/anna/src/notes", "a copied folder's record: folder, \"Copied from <path>\"");

        // Not the shell's after all: user
        const userOf = (directory, link, given) => _source(directory, link, given).source;
        assertEqual(userOf(places.versions + "/weather/1.2.0-abcdef1", _weatherLink(), rules.parseRecord("{")), "user",
                    "a record that cannot be read: user (unknown, never fine)");
        assertEqual(userOf(places.versions + "/weather/1.2.0-abcdef1", _weatherLink(), rules.parseRecord("{}")), "user", "a missing record entry: user");
        assertEqual(rules.sourceOf(places.versions + "/weather/1.2.0-abcdef1", _weatherLink(), roots, null).source, "user", "no record given: user");
        assertEqual(userOf(places.versions + "/weather/9.9.9-0000000",
                           { entry: places.user + "/weather", isLink: true, target: places.versions + "/weather/9.9.9-0000000" }), "user",
                    "a version the record does not list: user");
        assertEqual(userOf(places.versions + "/notes/0.3.0-20261120",
                           { entry: places.user + "/weather", isLink: true, target: places.versions + "/notes/0.3.0-20261120" }), "user",
                    "a link named weather into another id's versions: user");
        assertEqual(userOf(home + "/src/weather", { entry: places.user + "/weather", isLink: true, target: home + "/src/weather" }), "user",
                    "a link with a record, but out of module-versions: user");
        assertEqual(userOf(places.versions + "/weather/1.2.0-abcdef1/sub",
                           { entry: places.user + "/weather", isLink: true, target: places.versions + "/weather/1.2.0-abcdef1/sub" }), "user",
                    "… deeper than one version directory: user");
        assertEqual(userOf(home + "/elsewhere", _weatherLink()), "user", "… loaded from somewhere else than the link's target: user");
        assertEqual(userOf(places.versions + "/weather/1.2.0-abcdef1/", _weatherLink()), "repository", "… the same directory with a trailing slash: still the shell's");
        assertEqual(userOf(places.versions + "/weather/1.2.0-abcdef1",
                           { entry: places.user + "/weather", isLink: true, target: places.versions + "/weather/../weather/1.2.0-abcdef1" }), "user",
                    "… a target with \"..\": user");
        assertEqual(userOf(places.user + "/weather", { entry: places.user + "/weather", isLink: false, target: "" }), "user",
                    "a folder where the shell's link would be: user");

        // Placed by hand
        found = _source(places.user + "/player", { entry: places.user + "/player", isLink: false, target: "" });
        assertEqual(found.source + " | " + found.label + " | " + found.entry, "user | Your copy | " + places.user + "/player", "a folder placed by hand: \"Your copy\"");
        found = _source(places.user + "/player", null);
        assertEqual(found.source + " " + found.entry, "user " + places.user + "/player", "… found without an entry, directly in the user root: the same");
        found = _source(home + "/Projects/h2s-tailscale", { entry: places.user + "/tailscale", isLink: true, target: home + "/Projects/h2s-tailscale" });
        assertEqual(found.source + " | " + found.label + " | " + found.address, "user | Your link → /home/anna/Projects/h2s-tailscale | /home/anna/Projects/h2s-tailscale",
                    "a link placed by hand: \"Your link → <target>\", its target the address");
        assertEqual(_source("/nix/store/abc-x", { entry: places.user + "/x", isLink: true, target: "/nix/store/abc-x" }).source, "user",
                    "a user's link into the store: still the user's");

        // The others
        found = _source(home + "/dev/modules/weather", null);
        assertEqual(found.source + " | " + found.label + " | " + found.entry, "developer | Development path | ", "H2S_SHELL_MODULE_PATH: developer, nothing to remove");
        assertEqual(_source(home + "/dev/modules", null).source, "developer", "… the path itself a module: developer");
        assertEqual(_source(home + "/dev/modules-other/x", null).source, "user", "… a sibling with the same prefix is not inside it");
        found = _source(roots.builtin + "/clock", null);
        assertEqual(found.source + " | " + found.label, "builtin | Built-in", "Arch's built-in place: builtin");
        const nixBuiltin = "/nix/store/xyz-h2s-shell/share/h2s-shell-builtin";
        assertEqual(rules.sourceOf(nixBuiltin + "/clock", null, Object.assign({}, roots, { builtin: nixBuiltin }), records).source, "builtin",
                    "NixOS's built-in place in the package (under the store): builtin, before the store counts as system");
        found = _source("/usr/share/h2s-shell/modules/printers", null);
        assertEqual(found.source + " | " + found.label, "system | Installed by the system — not part of h2s-shell", "/usr/share: system");
        assertEqual(_source("/run/current-system/sw/share/h2s-shell/modules/x", null).source, "system", "NixOS's profile: system");
        assertEqual(_source("/nix/store/aaa-module/x", null).source, "system", "anything else under /nix/store: system");
        found = _source("/opt/strange/x", null);
        assertEqual(found.source + " " + found.entry, "user ", "a place nobody knows: user, nothing to remove");
        found = _source("relative/x", { entry: "", isLink: false });
        assertEqual(found.source + " " + found.entry, "user ", "a directory that is not a clean absolute path: user");
        assertEqual(_source(roots.builtin + "/../modules/x", null).source, "user", "\"..\" never counts as inside a root");
        assertEqual(rules.sourceOf(null, null, null, null).source, "user", "nothing given: user, no throw");
        assertEqual(rules.sources.join(","), "builtin,system,repository,folder,user,developer", "the six sources");

        // Labels keep text from outside plain
        assertEqual(rules.sourceLabel({ source: "repository", address: "https://user:secret@example.org/x/y.git/", ref: "" }), "From example.org/x/y",
                    "a password in an address is never shown");
        assert(rules.sourceLabel({ source: "user", isLink: true, target: "/a\nb‮c" }).indexOf("\n") < 0, "a target's control and bidi characters go");
        assertEqual(rules.addressShown("file:///srv/git/m.git#v1"), "/srv/git/m", "a file address: its path");
    }

    function _replacing() {
        const rules = ModuleInstallRules;
        const replaced = rules.replaces([
            { directory: places.user + "/clock", id: "clock", source: "user", version: "2.0" },
            { directory: "/x", id: "", source: "system", version: "" },
            { directory: roots.builtin + "/clock", id: "clock", source: "builtin", version: "1.2.0" },
            { directory: "/usr/share/h2s-shell/modules/clock", id: "clock", source: "system", version: "1.0" },
            { directory: "/usr/share/h2s-shell/modules/other", id: "other", source: "system", version: "1" }]);
        assertEqual(replaced.map(entry => entry.length).join(","), "2,0,0,0,0", "the winner lists what it replaces; the others nothing");
        assertEqual(replaced[0].map(entry => entry.source + ":" + entry.version).join(","), "builtin:1.2.0,system:1.0", "… in search order, with source and version");
        assertEqual(rules.replacesText(replaced[0]), "Replaces the built-in copy (1.2.0) and the system's copy (1.0)", "the card's line");
        assertEqual(rules.replacesText([{ source: "builtin", version: "1.2.0" }]), "Replaces the built-in copy (1.2.0)", "one copy");
        assertEqual(rules.replacesText([{ source: "user", version: "" }]), "Replaces another copy", "… without a version");
        assertEqual(rules.replacesText([]) + rules.replacesText(null), "", "none: no line");
        assertEqual(rules.replaces(null).length, 0, "nothing: nothing");
    }

    function _actions() {
        const rules = ModuleInstallRules;
        const repository = _source(places.versions + "/weather/1.2.0-abcdef1", _weatherLink());
        const status = (state, enabled) => ({ id: "weather", directory: places.versions + "/weather/1.2.0-abcdef1", state: state, enabled: enabled });
        const labels = actions => actions.map(action => action.label + "=" + action.effect + (action.asks !== "none" ? "/" + action.asks : "")).join(", ");

        let actions = rules.actionsFor(status("loaded", true), repository, {});
        assertEqual(labels(actions.row), "Disable=disable/button, Remove=remove/modal", "loaded: Disable (its own question), Remove last");
        assertEqual(labels(actions.opened), "Reload=reload, Check for updates=check, Switch version…=switchVersion, Backups…=backups",
                    "… opened: reload, check, switch version, backups");
        assertEqual(JSON.stringify(actions.row[0].subject), JSON.stringify({ id: "weather", directory: places.versions + "/weather/1.2.0-abcdef1" }),
                    "every action carries its subject");
        actions = rules.actionsFor(status("loaded", true), repository, { runningDependents: ["Exit map"] });
        assertEqual(labels(actions.row.slice(0, 1)) + " " + actions.row[0].dependents.join(","), "Disable=disable/modal Exit map",
                    "running dependents: Disable asks in the modal, naming them");
        actions = rules.actionsFor(status("disabled", false), repository, {});
        assertEqual(labels(actions.row.slice(0, 1)), "Enable=enable", "disabled: Enable, no question");
        actions = rules.actionsFor(status("unconfirmed", true), repository, {});
        assertEqual(labels(actions.row.slice(0, 1)), "Enable=enable/confirmation", "unconfirmed: Enable through the confirmation");
        actions = rules.actionsFor(status("approval", true), repository, {});
        assertEqual(labels(actions.row.slice(0, 1)), "Enable=enable/approval", "held for approval: off, Enable through the consent box (never Disable)");
        actions = rules.actionsFor(status("disabled", false), repository, { needsConfirmation: true });
        assertEqual(labels(actions.row.slice(0, 1)), "Enable=enable/confirmation", "… or when needsConfirmation says so");
        assertEqual(labels(rules.actionsFor(status("failed", true), repository, {}).row.slice(0, 1)), "Disable=disable/button", "failed but on: Disable");

        actions = rules.actionsFor(status("loaded", true), repository, { update: { version: "1.3.0", downloaded: true } });
        assertEqual(labels(actions.row), "Disable=disable/button, Update to 1.3.0=update, Remove=remove/modal", "an update downloaded: \"Update to 1.3.0\" before Remove");
        assertEqual(actions.row[1].version, "1.3.0", "… carrying the version it installs");
        assertEqual(rules.actionsFor(status("loaded", true), repository, { update: { version: "1.3.0", downloaded: false } }).row.length, 2, "… not yet downloaded: no Update");
        assertEqual(rules.actionsFor(status("loaded", true), repository, { update: { version: "1.3.0", downloaded: true }, autoUpdate: true }).row.length, 2,
                    "… automatic updates on: no Update button");
        actions = rules.actionsFor(status("safe-mode", true), repository, { update: { version: "1.3.0", downloaded: true } });
        assertEqual(labels(actions.row) + " | " + labels(actions.opened), "Disable=disable/button, Remove=remove/modal | Reload=reload, Switch version…=switchVersion, Backups…=backups",
                    "safe mode: no update, no check (switching back and backups stay)");

        const folder = { source: "folder", entry: places.user + "/notes", isLink: true };
        assertEqual(labels(rules.actionsFor({ id: "notes", state: "loaded", enabled: true }, folder, {}).opened),
                    "Reload=reload, Copy again=update, Switch version…=switchVersion, Backups…=backups", "a copied folder: copy again, no check");
        const user = _source(places.user + "/player", null);
        actions = rules.actionsFor({ id: "player", state: "loaded", enabled: true }, user, { update: { version: "2", downloaded: true } });
        assertEqual(labels(actions.row) + " | " + labels(actions.opened), "Disable=disable/button, Remove=remove/modal | Reload=reload", "placed by hand: Remove, never Update");
        for (const source of ["builtin", "system", "developer"]) {
            actions = rules.actionsFor({ id: "clock", state: "loaded", enabled: true }, { source: source, entry: places.user + "/clock" },
                                       { update: { version: "2", downloaded: true } });
            assertEqual(labels(actions.row) + " | " + labels(actions.opened), "Disable=disable/button | Reload=reload", source + ": enable/disable and reload only, never Remove");
        }
        assertEqual(rules.actionsFor({ id: "weather", state: "duplicate" }, repository, {}).row.length, 0, "a duplicate: no actions (shown in its winner's card)");
        assertEqual(rules.actionsFor(null, null, null).row.length, 0, "nothing: no actions, no throw");
        assertEqual(rules.actionsFor(status("loaded", true), repository, { update: { version: "1.3\n<b>x</b>", downloaded: true } }).row[1].label.indexOf("\n"), -1,
                    "a version from outside stays on one line");
    }

    function _confirmation() {
        const rules = ModuleInstallRules;
        const user = _source(home + "/Projects/h2s-tailscale", { entry: places.user + "/tailscale", isLink: true, target: home + "/Projects/h2s-tailscale" });
        const manifest = { id: "tailscale", author: "Anna", privileged: { why: "Connect", programs: ["tailscale"] } };
        const acknowledgement = rules.acknowledgementOf(user, manifest);
        assertEqual(JSON.stringify(acknowledgement), JSON.stringify({ source: "user", address: home + "/Projects/h2s-tailscale", author: "Anna", privileged: true }),
                    "acknowledgementOf: source, address, author, privileged");
        const verdict = (found, given, list) => {
            const result = rules.needsConfirmation(found, given, list);
            return result.needed + " " + result.state + " " + result.reasons.join(",") + (result.baseline ? " baseline" : "");
        };
        for (const source of ["builtin", "system", "developer"])
            assertEqual(verdict({ source: source, address: "/x" }, manifest, {}), "false  ", source + ": never asked");
        assertEqual(verdict(user, manifest, undefined), "false   baseline", "no list yet: acknowledged as found (the baseline, written at the first start)");
        assertEqual(verdict(user, manifest, null), "true unconfirmed new", "a null list: read as empty, asks (only a list never written is the baseline)");
        assertEqual(verdict(user, manifest, {}), "true unconfirmed new", "a list without it: unconfirmed, new");
        assertEqual(verdict(user, manifest, []), "true unconfirmed new", "a list that is no object: read as empty, asks");
        assertEqual(verdict(user, manifest, "x"), "true unconfirmed new", "… a string too");
        assertEqual(verdict(user, manifest, { tailscale: acknowledgement }), "false  ", "acknowledged as it is: fine");
        assertEqual(verdict(user, manifest, { tailscale: Object.assign({}, acknowledgement, { source: "builtin" }) }), "true unconfirmed source",
                    "acknowledged for another source (a user copy replacing a built-in one): asks again");
        assertEqual(verdict(user, manifest, { tailscale: Object.assign({}, acknowledgement, { address: "/elsewhere" }) }), "true unconfirmed source",
                    "… another address: asks again");
        assertEqual(verdict(user, manifest, { tailscale: Object.assign({}, acknowledgement, { privileged: false }) }), "true approval privileged",
                    "a hand-placed module that now declares administrator actions: approval required");
        assertEqual(verdict(user, manifest, { tailscale: Object.assign({}, acknowledgement, { author: "Bob" }) }), "true approval author",
                    "… another author: approval required");
        assertEqual(verdict(user, { id: "tailscale", author: "Anna" }, { tailscale: acknowledgement }), "false  ", "declaring less never asks");
        assertEqual(verdict(user, manifest, { tailscale: "yes" }), "true unconfirmed new", "an acknowledgement that is no object: none");
        assertEqual(verdict(user, { id: "constructor" }, {}), "true unconfirmed new", "an id named like a prototype key: not acknowledged by the prototype");

        assertEqual(rules.acknowledgementOf({ source: "user", address: "/home/anna/my#module" }, {}).address, "/home/anna/my#module",
                    "a path with \"#\": kept whole (only a repository's address loses its ref)");
        assertEqual(rules.acknowledgementOf({ source: "repository", address: "https://e.org/x#v1" }, {}).address, "https://e.org/x", "… a repository's does");
        // A new tag of the same repository is the same source
        const repository = _source(places.versions + "/weather/1.2.0-abcdef1", _weatherLink());
        const weather = { id: "weather" };
        const given = { weather: { source: "repository", address: "https://codeberg.org/anna/weather.git", author: "", privileged: false } };
        assertEqual(verdict(repository, weather, given), "false  ", "installed by the shell, acknowledged by its address: fine");
        assertEqual(verdict(repository, weather, { weather: Object.assign({}, given.weather, { address: "https://github.com/x/weather.git" }) }),
                    "true unconfirmed source", "… installed from elsewhere: asks again");
        assertEqual(verdict(null, null, undefined), "false   baseline", "nothing: no throw");
        assertEqual(verdict(null, null, null), "true unconfirmed new", "… a null list asks");
    }

    function _removal() {
        const rules = ModuleInstallRules;
        const records = rules.parseRecord(_recordText());
        const options = { dataHome: home + "/.local/share", configHome: home + "/.config", home: home };
        const steps = plan => plan.steps.map(step => step.op + (step.path ? " " + step.path.replace(home, "~") : "") + (step.prefix ? " " + step.prefix : "")).join("; ");

        const repository = _source(places.versions + "/weather/1.2.0-abcdef1", _weatherLink());
        let plan = rules.removalPlan(repository, { id: "weather", name: "Weather", version: "1.2.0" }, records.modules.weather, options);
        assert(plan.ok, "installed by the shell: planned");
        assertEqual(plan.title, "Remove Weather?", "… the title");
        assertEqual(plan.lines.join(" / "), "Deletes Weather 1.2.0 and the kept versions (1.1.0).", "… the body names the kept versions");
        assertEqual(steps(plan), "disable; unlink ~/.local/share/h2s-shell/modules/weather; deleteTree ~/.local/share/h2s-shell/module-versions/weather; dropRecord; dropAcknowledgement",
                    "… its link and every version, the record and the acknowledgement — no data");
        assertEqual(JSON.stringify(plan.subject), JSON.stringify({ id: "weather", entry: places.user + "/weather" }), "… keyed to what it removes");
        plan = rules.removalPlan(repository, { id: "weather", name: "Weather", version: "1.2.0" }, records.modules.weather, Object.assign({ withData: true }, options));
        assertEqual(steps(plan).split("; ").slice(5).join("; "),
                    "deleteTree ~/.local/share/h2s-shell/module-data/weather; deleteTree ~/.config/h2s_shell/modules/weather; deleteTree ~/.local/share/h2s-shell/module-backups/weather; deleteSettings mod.weather.",
                    "with data: its data directory, store, backups and settings too");
        assertEqual(plan.lines[plan.lines.length - 1], "Its data and settings are deleted too.", "… said");
        const clipboard = _source(places.versions + "/clipboard/0.2.0-1a2b3c4",
                                  { entry: places.user + "/clipboard", isLink: true, target: places.versions + "/clipboard/0.2.0-1a2b3c4" });
        plan = rules.removalPlan(repository, { id: "weather", name: "Weather", version: "1.2.0" }, records.modules.weather,
                                 Object.assign({ withData: true, dependents: { hard: ["Exit map"], soft: ["Clock"] },
                                                 alsoRemove: [{ found: clipboard, module: { id: "clipboard", name: "Clipboard", version: "0.2.0" }, record: records.modules.clipboard }] }, options));
        assert(plan.lines.includes("These stop working: Exit map.") && plan.lines.includes("These lose a feature: Clock."), "dependents named, hard and soft");
        assertEqual(plan.also.length + " " + plan.also[0].ok + " " + plan.also[0].title, "1 true Remove Clipboard?", "a dependency chosen with it: its own plan");
        assert(plan.also[0].steps.some(step => step.op === "deleteSettings" && step.prefix === "mod.clipboard."), "… with the same data choice");
        assertEqual(plan.also[0].lines[0], "Deletes Clipboard 0.2.0.", "… no kept versions: none named");
        assertEqual(rules.alsoRemoveLabel("Clipboard", "Notes"), "Also remove Clipboard (installed for Notes, nothing else uses it)", "the checkbox's words");

        // Placed by hand
        const link = _source(home + "/Projects/h2s-backup", { entry: places.user + "/backup", isLink: true, target: home + "/Projects/h2s-backup" });
        plan = rules.removalPlan(link, { id: "backup", name: "Backup" }, null, options);
        assertEqual(plan.lines.join(" / "), "Not installed by the shell. / Deletes only the link; ~/Projects/h2s-backup stays.", "a link: says it deletes the link only");
        assertEqual(steps(plan), "disable; unlink ~/.local/share/h2s-shell/modules/backup; dropAcknowledgement", "… unlinked, never deleted through");
        assert(!plan.steps.some(step => step.op === "deleteTree"), "… no tree deleted at all");
        plan = rules.removalPlan(link, { id: "backup", name: "Backup" }, null, Object.assign({ withData: true }, options));
        assert(!plan.steps.some(step => step.op === "deleteTree" && (step.path.startsWith(home + "/Projects") || step.path === places.user + "/backup")),
               "… with data: its data goes, the link's target never");
        const folder = _source(places.user + "/player", { entry: places.user + "/player", isLink: false });
        plan = rules.removalPlan(folder, { id: "player", name: "Player" }, null, options);
        assertEqual(plan.lines.join(" / "), "Not installed by the shell. / Deletes the folder ~/.local/share/h2s-shell/modules/player.", "a folder placed by hand");
        assertEqual(steps(plan), "disable; deleteTree ~/.local/share/h2s-shell/modules/player; dropAcknowledgement", "… that folder, no record to drop");
        assertEqual(rules.removalPlan(folder, { id: "player" }, null, options).title, "Remove player?", "no name: the id");

        // Refused
        const refused = (found, id, given) => rules.removalPlan(found, { id: id ?? "x" }, null, given ?? options);
        for (const source of ["builtin", "system", "developer"])
            assert(!refused({ source: source, entry: places.user + "/x" }).ok, source + ": never removed");
        assertEqual(refused({ source: "builtin", entry: "" }).reason, "A built-in module cannot be removed", "… said why");
        assertEqual(refused({ source: "system" }).reason, "Change it in the system's configuration", "… the system's: where to change it");
        assert(!refused({ source: "user", entry: "/opt/x/x" }).ok, "outside the user root: refused");
        assert(!refused({ source: "user", entry: places.user + "/a/b" }).ok, "… deeper in it: refused");
        assert(!refused({ source: "user", entry: places.user }).ok, "… the root itself: refused");
        assert(!refused({ source: "user", entry: places.user + "/../x" }).ok, "… through \"..\": refused");
        assert(!refused(folder, "Bad Id").ok && !refused(folder, "__proto__").ok, "an invalid id: refused");
        assert(!refused(folder, "player", {}).ok, "no data home: refused");
        assert(!rules.removalPlan(Object.assign({}, repository, { entry: places.user + "/other" }), { id: "weather" }, null, options).ok,
               "installed by the shell, but the link is not named by its id: refused");
        assert(!rules.removalPlan(Object.assign({}, repository, { isLink: false }), { id: "weather" }, null, options).ok,
               "… not a link: refused");
        const nothing = rules.removalPlan(null, null, null, null);
        assertEqual(nothing.ok + " " + nothing.steps.length, "false 0", "nothing: refused, no steps, no throw");
    }

    function _addresses() {
        const problem = ModuleInstallRules.repositoryProblem;
        for (const good of ["https://codeberg.org/anna/weather.git", "https://codeberg.org/anna/weather#v1.2.0", "ssh://git@example.org:2222/x/y.git",
                            "git://example.org/x", "file:///srv/git/weather.git", "git@github.com:anna/weather.git", "git@github.com:anna/weather.git#main",
                            "https://codeberg.org/anna/weather#" + weatherCommit, "https://[::1]/x", "https://example.org/x#release/1.0"])
            assertEqual(problem(good), "", "accepted: " + good);
        const refusedWith = (address, fragment, message) => {
            const said = problem(address);
            assert(said !== "" && said.indexOf(fragment) >= 0, message + " — said: " + said);
        };
        refusedWith("ext::sh -c touch% /tmp/x", "transport", "ext:: runs a command: refused");
        refusedWith("fd::3", "transport", "fd:: : refused");
        refusedWith("EXT::sh", "transport", "… in capitals too");
        refusedWith("-uhttps://x/y", "starts with", "a leading \"-\": refused");
        refusedWith("--upload-pack=touch /tmp/x", "starts with", "… an option: refused");
        refusedWith("https://x.org/y\n", "control", "a newline: refused");
        refusedWith("https://x.org/\u0000y", "control", "a NUL: refused");
        refusedWith("https://x.org/\u007fy", "control", "DEL: refused");
        refusedWith("https://x.org/" + "a".repeat(1000), "1000", "over 1000 characters: refused");
        assertEqual(problem("https://x.org/" + "a".repeat(1000 - "https://x.org/".length)), "", "… exactly 1000: accepted");
        refusedWith("ssh://-oProxyCommand=touch%20x/y", "host", "an ssh host that is an option: refused");
        refusedWith("git@-oProxyCommand=x:y", "host", "… scp-like too");
        refusedWith("ssh://-oProxyCommand=x@example.org/y", "user", "an ssh user part that is an option: refused");
        refusedWith("ssh://us er@example.org/y", "user", "… with a character outside a user name: refused");
        refusedWith("ssh://@example.org/y", "user", "… empty: refused");
        refusedWith("git://-x@example.org/y", "user", "… on git:// too");
        refusedWith("ssh://git@example.org:22a/y", "host", "a port that is not digits: refused");
        refusedWith("ssh://git@example.org:-1/y", "host", "… a negative one: refused");
        refusedWith("ssh://git@example.org:/y", "host", "… an empty one: refused");
        assertEqual(problem("ssh://git.user_1@example.org:2222/y") + problem("https://user:token@example.org/y"), "", "a plain user and a port: accepted (https keeps its user:token)");
        refusedWith("git@host:-x", "repository", "a path starting with \"-\": refused");
        refusedWith("http://example.org/x", "Only", "plain http: refused");
        refusedWith("ftp://example.org/x", "Only", "another scheme: refused");
        refusedWith("file://relative/x", "absolute", "a file address without an absolute path: refused");
        refusedWith("https://example.org", "repository", "a host without a path: refused");
        refusedWith("https:///x", "host", "no host: refused");
        refusedWith("/home/anna/src/x", "Not a repository", "a plain path is no address (a folder is installed as a folder)");
        refusedWith("x#v1", "Not a repository", "no scheme: refused");
        refusedWith("https://e.org/x#", "after", "nothing after \"#\": refused");
        refusedWith("https://e.org/x#-b", "after", "a ref that is an option: refused");
        refusedWith("https://e.org/x#a..b", "after", "a ref with \"..\": refused");
        refusedWith("https://e.org/x#a b", "after", "a ref with a space: refused");
        refusedWith("", "No address", "empty: refused");
        refusedWith("   ", "No address", "blank: refused");
        refusedWith(null, "No address", "not text: refused");
        refusedWith(42, "No address", "… a number too");

        assertEqual(JSON.stringify(ModuleInstallRules.splitAddress("https://e.org/x#v1")), JSON.stringify({ url: "https://e.org/x", ref: "v1" }), "splitAddress: at the first \"#\"");
        assertEqual(JSON.stringify(ModuleInstallRules.splitAddress(null)), JSON.stringify({ url: "", ref: "" }), "… nothing: empty");
        assert(ModuleInstallRules.isCommitId(weatherCommit) && ModuleInstallRules.isCommitId("a".repeat(64)), "a full SHA-1 or SHA-256 id is a commit id");
        assert(!ModuleInstallRules.isCommitId("abcdef1") && !ModuleInstallRules.isCommitId("v1.2.0") && !ModuleInstallRules.isCommitId(weatherCommit.toUpperCase()),
               "… a short one, a tag, capitals: not");
    }

    function _download() {
        const rules = ModuleInstallRules;
        const staging = places.staging + "/k3j2";
        const config = "-c core.hooksPath=/dev/null -c credential.helper= -c core.askPass="
                     + " -c filter.lfs.process= -c filter.lfs.smudge= -c filter.lfs.required=false -c protocol.allow=never -c protocol.https.allow=always -c protocol.ssh.allow=always"
                     + " -c protocol.git.allow=always -c protocol.file.allow=always";
        let download = rules.downloadCommands("https://codeberg.org/anna/weather.git#v1.2.0", staging);
        assert(download.ok && download.commands.length === 1, "a tag: one command");
        assertEqual(download.commands[0].argv.join(" "),
                    "git " + config + " clone --progress --depth 1 --no-recurse-submodules --branch v1.2.0 -- https://codeberg.org/anna/weather.git " + staging,
                    "… a shallow clone of that tag, no hooks, no credential helper or askpass, no git-lfs filter, no submodules, only four protocols, the address after \"--\"");
        const argv = download.commands[0].argv;
        for (const option of ["credential.helper=", "core.askPass=", "filter.lfs.process=", "filter.lfs.smudge=", "filter.lfs.required=false"])
            assert(argv.indexOf(option) > 0 && argv[argv.indexOf(option) - 1] === "-c" && argv.indexOf(option) < argv.indexOf("clone"),
                   "… \"-c " + option + "\" before the subcommand");
        assert(Array.isArray(download.commands[0].argv), "… an argv array, never a shell string");
        assertEqual(JSON.stringify(download.commands[0].environment),
                    JSON.stringify({ GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", GIT_TERMINAL_PROMPT: "0", GIT_ASKPASS: "", SSH_ASKPASS: "",
                                    GIT_SSH_COMMAND: "ssh -o BatchMode=yes", GIT_LFS_SKIP_SMUDGE: "1" }),
                    "… with none of the user's or the system's git configuration, no terminal prompt, no askpass program, ssh in batch mode, git-lfs not fetching");
        download.commands[0].environment.GIT_ASKPASS = "x";
        assertEqual(rules.gitEnvironment.GIT_ASKPASS, "", "… each command's environment its own copy");
        download = rules.downloadCommands("git@github.com:anna/weather.git", staging);
        assertEqual(download.commands[0].argv.slice(-4).join(" "), "--no-recurse-submodules -- git@github.com:anna/weather.git " + staging, "no ref: no --branch");
        download = rules.downloadCommands("https://codeberg.org/anna/weather.git#" + weatherCommit, staging);
        assertEqual(download.commands.map(command => command.argv.join(" ")).join(" | "),
                    "git " + config + " init --quiet -- " + staging
                    + " | git -C " + staging + " " + config + " fetch --progress --depth 1 --no-recurse-submodules -- https://codeberg.org/anna/weather.git " + weatherCommit
                    + " | git -C " + staging + " " + config + " checkout --quiet --detach FETCH_HEAD",
                    "a commit id: init, a shallow fetch of that commit, its checkout");
        for (const bad of ["ext::sh -c x", "-x", "https://e.org/x#-b"]) {
            download = rules.downloadCommands(bad, staging);
            assertEqual(download.ok + " " + download.commands.length, "false 0", "a refused address: no command — " + bad);
        }
        assert(rules.downloadCommands("ext::x", staging).problem.indexOf("transport") >= 0, "… the reason given");
        for (const bad of ["relative", "/", "", null, places.staging + "/../x"])
            assertEqual(rules.downloadCommands("https://e.org/x", bad).ok, false, "a directory that is no clean absolute path: refused — " + bad);
    }

    function _progress() {
        const progressOf = ModuleInstallRules.progressOf;
        let progress = progressOf("Receiving objects:  45% (120/266), 1.20 MiB | 2.40 MiB/s");
        assertEqual(JSON.stringify(progress), JSON.stringify({ phase: "receiving", percent: 45, bytes: Math.round(1.2 * 1048576), rate: Math.round(2.4 * 1048576), done: false }),
                    "receiving: share, bytes and speed");
        progress = progressOf("Receiving objects:  12% (3/25)\rReceiving objects:  60% (15/25), 512.00 KiB | 256.00 KiB/s\r");
        assertEqual(progress.percent + " " + progress.bytes + " " + progress.rate, "60 524288 262144", "a redrawn line: the last part counts");
        progress = progressOf("Receiving objects: 100% (266/266), 3.10 MiB | 2.40 MiB/s, done.");
        assertEqual(progress.percent + " " + progress.done, "100 true", "done");
        progress = progressOf("Resolving deltas:  50% (10/20)");
        assertEqual(progress.phase + " " + progress.percent + " " + progress.bytes + " " + progress.rate, "resolving 50 null null", "resolving deltas: no bytes, no speed");
        progress = progressOf("remote: Counting objects: 100% (10/10), done.");
        assertEqual(progress.phase + " " + progress.done, "counting true", "the server's lines too");
        progress = progressOf("Receiving objects:  45% (120/266), 900 bytes | 300 bytes/s");
        assertEqual(progress.bytes + " " + progress.rate, "900 300", "bytes as bytes");
        progress = progressOf("Receiving objects:  45% (120/266), 1.00 GiB | 0 bytes/s");
        assertEqual(progress.bytes + " " + progress.rate, "1073741824 0", "GiB, a speed of zero");
        for (const line of ["Cloning into '/tmp/x'...", "", "fatal: repository not found", "Receiving objects: lots", "Receiving objects:  45%", null, 3, "x".repeat(5000)])
            assertEqual(progressOf(line), null, "no progress: null — " + JSON.stringify(line).slice(0, 40));
        assertEqual(progressOf("Receiving objects: 450% (1/2)").percent, 100, "a share over 100: 100");
    }

    function _record() {
        const rules = ModuleInstallRules;
        const record = rules.parseRecord(_recordText());
        assertEqual(record.ok + " " + Object.keys(record.modules).sort().join(",") + " " + record.dropped.length, "true clipboard,notes,weather 0", "a good record: every entry");
        const weather = record.modules.weather;
        assertEqual(weather.kind + " " + weather.address + " " + weather.ref + " " + weather.active + " " + weather.versions.length + " " + weather.refused,
                    "repository https://codeberg.org/anna/weather.git v1.2.0 1.2.0-abcdef1 2 null", "… its fields");
        assertEqual(record.modules.clipboard.installedFor + " " + record.modules.notes.installedFor + "|", "notes |", "installedFor, \"\" for none");
        for (const bad of ["", "{", "[]", "null", "42", "\"x\"", null, undefined]) {
            const parsed = rules.parseRecord(bad);
            assertEqual(parsed.ok + " " + Object.keys(parsed.modules).length, "false 0", "unreadable: not ok, no modules — " + JSON.stringify(bad));
        }
        const good = JSON.parse(_recordText()).weather;
        const withEntry = changes => rules.parseRecord(JSON.stringify({ weather: Object.assign({}, good, changes) }));
        const dropped = (changes, message) => {
            const parsed = withEntry(changes);
            assert(parsed.ok && !ModuleRules.has(parsed.modules, "weather") && parsed.dropped[0] === "weather", message);
        };
        dropped({ kind: "magic" }, "another kind: dropped");
        dropped({ address: "ext::sh -c x" }, "an address that would be refused: dropped");
        dropped({ address: "https://e.org/x#v1" }, "a ref inside the address: dropped");
        dropped({ ref: "-x" }, "a ref that is an option: dropped");
        dropped({ versions: [] }, "no versions: dropped");
        dropped({ versions: "1.2.0" }, "versions not a list: dropped");
        dropped({ versions: [{ dir: "../../evil", version: "1" }], active: "../../evil" }, "a version directory with \"..\": dropped");
        dropped({ versions: [{ dir: "a/b", version: "1" }], active: "a/b" }, "… with a slash: dropped");
        dropped({ versions: [{ dir: "-x", version: "1" }], active: "-x" }, "… starting with \"-\": dropped");
        dropped({ versions: [{ dir: "a", version: "1" }, { dir: "a", version: "2" }], active: "a" }, "… twice: dropped");
        dropped({ versions: [{ dir: "a", version: "1", commit: "not hex" }], active: "a" }, "a commit that is no hex: dropped");
        dropped({ active: "9.9.9" }, "an active version not listed: dropped");
        dropped({ refused: "yes" }, "refused not a record: dropped");
        dropped({ installedFor: "Bad Id" }, "installedFor not an id: dropped");
        assertEqual(withEntry({ refused: { version: "1.3.0", commit: "ffff" } }).modules.weather.refused.version, "1.3.0", "a refused version kept");
        assert(!ModuleRules.has(rules.parseRecord(JSON.stringify({ notes: Object.assign({}, JSON.parse(_recordText()).notes, { address: "relative" }) })).modules, "notes"),
               "a folder's address that is no absolute path: dropped");
        const hostile = rules.parseRecord('{"__proto__": {"kind":"repository"}, "Bad": {}, "constructor": 1}');
        assertEqual(hostile.ok + " " + Object.keys(hostile.modules).length + " " + hostile.dropped.length, "true 0 3", "ids that are no module ids: dropped, the prototype untouched");
        assertEqual(Object.getPrototypeOf(hostile.modules), Object.prototype, "… the modules object an ordinary one");
    }

    function _builtin() {
        const rules = ModuleInstallRules;
        assertEqual(JSON.stringify(rules.builtinOff('{"off": ["player", "weather", "player", "Bad", "clock", 3]}')), JSON.stringify({ ok: true, off: ["player", "weather"] }),
                    "builtin.json: the valid ids (a reserved one is none), each once");
        const shipped = rules.builtinOff(_shippedBuiltin.text());
        assert(shipped.ok, "builtin.json as builtin-modules/ ships it: well formed (no problem for the host)");
        let listed = null;
        try {
            listed = JSON.parse(_shippedBuiltin.text()).off;
        } catch (error) {}
        assertEqual(JSON.stringify(shipped.off), JSON.stringify(listed), "… every id it lists as off valid, each once (none dropped)");
        for (const bad of ["", "{", "[]", '{"off": "clock"}', "{}", null])
            assertEqual(JSON.stringify(rules.builtinOff(bad)), JSON.stringify({ ok: false, off: [] }), "unreadable or another form: not ok, none off — " + JSON.stringify(bad));
        const on = (id, source, disabled, enabled) => rules.enabledByLists(id, source, ["clock"], enabled ?? [], disabled ?? []);
        assertEqual(on("clock", "builtin"), false, "a built-in module listed off: off");
        assertEqual(on("clock", "builtin", [], ["clock"]), true, "… until the user enables it (enabledModules)");
        assertEqual(on("clock", "builtin", ["clock"], ["clock"]), false, "… turned off again: disabledModules wins");
        assertEqual(on("weather", "builtin"), true, "a built-in module not listed: on");
        assertEqual(on("clock", "user"), true, "builtin.json speaks for built-in modules only");
        assertEqual(on("weather", "user", ["weather"]), false, "disabledModules: off");
        assertEqual(rules.enabledByLists("x", "builtin", null, null, null), true, "no lists: on, no throw");
    }

    // What the host reads and keeps: the acknowledgements' text, the first start's baseline,
    // the refusal's words, the places from the environment, the source check's output
    function _hostReads() {
        const rules = ModuleInstallRules;
        const given = { source: "user", address: "/home/anna/src/ts", author: "Anna", privileged: true };
        assertEqual(rules.parseAcknowledgements(""), undefined, "acknowledgements never written: undefined (the baseline)");
        assertEqual(rules.parseAcknowledgements(undefined), undefined, "… also when absent");
        assertEqual(JSON.stringify(rules.parseAcknowledgements(JSON.stringify({ tailscale: given }))), JSON.stringify({ tailscale: given }),
                    "a written list reads back");
        for (const broken of ["{", "[]", "null", "3", "\"x\""])
            assertEqual(JSON.stringify(rules.parseAcknowledgements(broken)), "{}", "a text that is not a JSON object: {} (asks again, never trusts) — " + broken);
        const mixed = rules.parseAcknowledgements(JSON.stringify({ tailscale: given, Bad: given, weather: { source: "user", address: 3 },
                                                                     clock: Object.assign({}, given, { source: "elsewhere" }), notes: "yes" }));
        assertEqual(Object.keys(mixed).join(","), "tailscale", "entries not well formed are left out: a bad id, a bad field, an unknown source");

        const read = (text, facts) => JSON.stringify(rules.readAcknowledgements(text, facts) ?? "undefined");
        assertEqual(read("", {}), "\"undefined\"", "read: no file, no key: never written (the baseline)");
        assertEqual(read("", { writtenBy: "2.0.0" }), "\"undefined\"", "read: a file an older shell wrote, without the key: never written");
        assertEqual(read("", { writtenBy: "2.1.0", inFile: true }), "\"undefined\"", "read: a newer file holding the key empty: not written yet");
        assertEqual(read("", { writtenBy: rules.acknowledgementsSince }), "{}", "read: a file of the version that added the key, without it: {} (asks again)");
        assertEqual(read("", { writtenBy: "3.0.0" }), "{}", "read: … of a later one: {}");
        assertEqual(read("", { writtenBy: "garbage" }), "{}", "read: a writer that cannot be read: {}");
        assertEqual(read(JSON.stringify({ tailscale: given }), { loadFailed: true }), "{}", "read: a file that could not be read: {}, whatever it seemed to hold");
        assertEqual(read(JSON.stringify({ tailscale: given }), { writtenBy: "2.1.0", inFile: true }), JSON.stringify({ tailscale: given }), "read: a written list");
        assertEqual(read("", null), "\"undefined\"", "read: no facts: never written, no throw");

        const dir = "/home/anna/.config/quickshell/default";
        const discovered = (value, shell, pid, parent) => JSON.stringify(rules.discoveryOf(value, shell ?? dir, pid ?? 500, parent ?? 400));
        assertEqual(discovered("ok 400 " + dir, dir + "/"), JSON.stringify({ launched: true, searched: true }),
                    "H2S_SHELL_DISCOVERY: the launcher (the shell's parent, its supervisor) started this shell and its search answered");
        assertEqual(discovered("ok 500 " + dir), JSON.stringify({ launched: true, searched: true }), "… the launcher's pid the shell's own (-d: exec)");
        assertEqual(discovered("failed 400 " + dir), JSON.stringify({ launched: true, searched: false }), "… its search failed: launched, not searched");
        assertEqual(discovered("ok 400 " + dir, "/home/anna/wt/m2"), JSON.stringify({ launched: false, searched: false }),
                    "… another directory's: neither");
        assertEqual(discovered("ok 400 " + dir, dir, 900, 800), JSON.stringify({ launched: false, searched: false }),
                    "… inherited by a shell started by hand from a terminal the bar opened (another pid and parent): neither");
        for (const junk of [null, "", "ok", "ok " + dir, "maybe 400 /x", "ok 400 relative", "ok -1 /x", "ok 0 " + dir])
            assertEqual(discovered(junk), JSON.stringify({ launched: false, searched: false }), "… unset or garbage: neither — " + JSON.stringify(junk));
        assertEqual(rules.parentPidOf("4242 (qs) S 400 4242 4242 0 -1"), 400, "parent pid: the field after the state");
        assertEqual(rules.parentPidOf("4242 (a) b) (c) R 17 1 1"), 17, "… a command with parentheses and spaces in it");
        assertEqual(rules.parentPidOf("") + rules.parentPidOf(null) + rules.parentPidOf("4242 (qs"), 0, "… unreadable: 0");

        const user = { source: "user", address: "/home/anna/src/ts" };
        const manifest = id => ({ id: id, author: "Anna", privileged: id === "tailscale" ? { why: "x", programs: [] } : null });
        const baseline = rules.baselineAcknowledgements([
            { found: user, manifest: manifest("tailscale"), enabled: true },
            { found: { source: "user", address: "/x/off" }, manifest: manifest("off"), enabled: false },
            { found: { source: "builtin", address: "/b/clock" }, manifest: manifest("clock"), enabled: true },
            { found: { source: "developer", address: "/d/dev" }, manifest: manifest("dev"), enabled: true },
            { found: { source: "repository", address: "https://codeberg.org/anna/w.git#v1" }, manifest: manifest("weather"), enabled: true },
            { found: user, manifest: { id: "Bad" }, enabled: true },
            null
        ]);
        assertEqual(JSON.stringify(baseline), JSON.stringify({
            tailscale: { source: "user", address: "/home/anna/src/ts", author: "Anna", privileged: true },
            weather: { source: "repository", address: "https://codeberg.org/anna/w.git", author: "Anna", privileged: false }
        }), "baseline: what is on and would be asked about, as it is (privileged included); off, built-in, development: not");
        assertEqual(JSON.stringify(rules.needsConfirmation(user, manifest("tailscale"), baseline)), JSON.stringify({ needed: false, state: "", reasons: [], baseline: false }),
                    "… after it, the module that ran before needs no confirmation");
        assertEqual(rules.needsConfirmation({ source: "user", address: "/x/off" }, manifest("off"), baseline).state, "unconfirmed",
                    "… one that was off asks when turned on");

        const text = (state, reasons) => rules.confirmationText("Tailscale", "tailscale", { needed: true, state: state, reasons: reasons });
        assertEqual(text("unconfirmed", ["new"]), "Tailscale is new and not part of h2s-shell: confirm it first (modules confirm tailscale <directory>)", "refusal: new");
        assertEqual(text("unconfirmed", ["source"]), "Tailscale comes from another place than the one confirmed: confirm it first (modules confirm tailscale <directory>)", "refusal: another source");
        assertEqual(text("approval", ["privileged"]), "Tailscale now asks for administrator rights: approve it first (modules confirm tailscale <directory>)", "refusal: privileged");
        assertEqual(text("approval", ["author"]), "Tailscale now names another author: approve it first (modules confirm tailscale <directory>)", "refusal: author");
        assertEqual(text("approval", ["privileged", "author"]), "Tailscale now asks for administrator rights and names another author: approve it first (modules confirm tailscale <directory>)", "refusal: both");
        assertEqual(rules.confirmationText("T", "t", { needed: false }) + rules.confirmationText("T", "t", null), "", "nothing to confirm: no words");
        assert(!rules.confirmationText("A\nB\u202e", "t", { needed: true, state: "unconfirmed", reasons: ["new"] }).includes("\n"), "a name from outside: one line");

        const places = rules.sourcePlaces({ dataHome: "/home/anna/.local/share", modulePath: "/home/anna/dev:relative::/x/y",
                                            dataDirs: "/usr/local/share:/usr/share/", builtin: "/home/anna/.local/share/h2s-shell/builtin" });
        assertEqual(JSON.stringify(places), JSON.stringify({
            user: "/home/anna/.local/share/h2s-shell/modules", versions: "/home/anna/.local/share/h2s-shell/module-versions",
            record: "/home/anna/.local/share/h2s-shell/module-sources.json", builtin: "/home/anna/.local/share/h2s-shell/builtin",
            developer: ["/home/anna/dev", "/x/y"], system: ["/usr/local/share/h2s-shell/modules", "/usr/share/h2s-shell/modules"]
        }), "places: as the launcher searches — the user root, the built-in root, the development path's absolute entries, each data dir's");
        assertEqual(JSON.stringify(rules.sourcePlaces({ dataHome: "/h", moduleDataDirs: "", dataDirs: "/usr/share" }).system), "[]",
                    "H2S_SHELL_MODULE_DATA_DIRS set and empty: no system places");
        assertEqual(JSON.stringify(rules.sourcePlaces({ dataHome: "/h", moduleDataDirs: null, dataDirs: "" }).system),
                    JSON.stringify(["/usr/local/share/h2s-shell/modules", "/usr/share/h2s-shell/modules"]), "neither set: the spec's default data dirs");
        assertEqual(rules.sourcePlaces({ builtin: "relative" }).builtin + rules.sourcePlaces(null).user, "", "a relative built-in root, no environment: none");
        assertEqual(JSON.stringify(rules.sourceCheckArguments(places)), JSON.stringify([places.user, places.versions, places.builtin, places.record,
                    "developer", "/home/anna/dev", "developer", "/x/y", "system", "/usr/local/share/h2s-shell/modules", "system", "/usr/share/h2s-shell/modules"]),
                    "the check's arguments: the roots, the record, then kind and path pairs");
        assertEqual(JSON.stringify(rules.sourceCheckArguments(null)), JSON.stringify(["", "", "", ""]), "… none: four empty ones");

        const checked = rules.parseSourceCheck([
            "root\tuser\t/home/anna/.local/share/h2s-shell/modules\t1000\t1", "root\tbuiltin\t/opt/builtin\t0\t0", "root\tdeveloper\t/home/anna/dev\t1000\t1",
            "root\tsystem\t/usr/share/h2s-shell/modules\t0\t0", "root\tsystem\t/usr/share/h2s-shell/modules\t0\t0", "root\tuser\trelative\t1000\t1",
            "root\tsystem\t/home/anna/.local/share/flatpak/exports/share/h2s-shell/modules\t1000\t1",
            "root\tsystem\t/opt/shared/h2s-shell/modules\t0\t1", "root\tsystem\t/srv/h2s-shell/modules\t\t0",
            "entry\tlink\t/home/anna/.local/share/h2s-shell/modules/tailscale\t/home/anna/src/ts",
            "entry\tdir\t/home/anna/.local/share/h2s-shell/modules/player\t/home/anna/.local/share/h2s-shell/modules/player",
            "entry\tlink\t/home/anna/.local/share/h2s-shell/modules/gone\t",
            "builtin\t{\"off\":", "builtin\t [\"player\"]}", "builtin-state\tok", "record-state\tmissing", "noise", "end"
        ]);
        assertEqual(JSON.stringify(checked.roots), JSON.stringify({ developer: ["/home/anna/dev"], user: "/home/anna/.local/share/h2s-shell/modules",
                    versions: "", builtin: "/opt/builtin", system: ["/usr/share/h2s-shell/modules"] }), "the check's roots, canonical, each once; a relative one dropped; a system root the user owns or can write, or whose owner is unknown, dropped");
        assertEqual(checked.entries.length + " " + checked.entries[0].isLink + " " + checked.entries[1].isLink + " " + JSON.stringify(checked.entries[2].target),
                    "3 true false \"\"", "its entries: links and folders, a dangling link leading nowhere");
        assertEqual(JSON.stringify(rules.builtinOff(checked.builtin.text)), JSON.stringify({ ok: true, off: ["player"] }), "builtin.json's lines joined back");
        assertEqual(checked.record.state, "missing", "no record: missing");
        const cut = rules.parseSourceCheck(["root\tuser\t/home/anna/.local/share/h2s-shell/modules\t1000\t1", "entry\tdir\t/a/b\t/a/b"]);
        assertEqual(rules.sourceOf("/home/anna/.local/share/flatpak/exports/share/h2s-shell/modules/x", null, checked.roots, rules.parseRecord("")).source, "user",
                    "a module in a user-writable data directory: placed by hand (user), never the system's");
        assertEqual(cut.complete + " " + cut.roots.user + cut.entries.length, "false 0", "cut off before its end: nothing of it is used");
        assertEqual(rules.parseSourceCheck(null).complete, false, "nothing: not complete, no throw");

        assertEqual(JSON.stringify(rules.linkFor("/home/anna/src/ts", checked.entries)),
                    JSON.stringify({ entry: "/home/anna/.local/share/h2s-shell/modules/tailscale", isLink: true, target: "/home/anna/src/ts" }),
                    "the entry a directory was found through: the link to it");
        assertEqual(rules.linkFor("/elsewhere", checked.entries), null, "found through none: null");
        const viaLink = rules.sourceOf("/home/anna/src/ts", rules.linkFor("/home/anna/src/ts", checked.entries), checked.roots, rules.parseRecord(""));
        assertEqual(viaLink.source + " | " + viaLink.label + " | " + viaLink.address, "user | Your link → /home/anna/src/ts | /home/anna/src/ts",
                    "a hand-made link in the user root: user, its address the directory it leads to");
        assertEqual(rules.sourceOf("/home/anna/src/ts", null, checked.roots, rules.parseRecord("")).address, "/home/anna/src/ts",
                    "… the same address when the entry is not known (an acknowledgement stays good)");
        assertEqual(rules.sourceOf("/opt/builtin/clock", null, checked.roots, rules.parseRecord("")).source, "builtin", "in the built-in root: builtin");
    }

    function _list() {
        const rules = ModuleInstallRules;
        const statuses = [
            { id: "zeta", name: "Zeta", state: "loaded", enabled: true },
            { id: "alpha", name: "alpha", state: "disabled", enabled: false },
            { id: "notes", name: "Notes", state: "unconfirmed", enabled: true },
            { id: "maps", name: "Maps", state: "approval", enabled: true },
            { id: "beta", name: "Beta", state: "failed", enabled: true },
            { id: "dup", name: "Aaa", state: "duplicate", enabled: true },
            { id: "b2", name: "beta", state: "loaded", enabled: true },
            null, { id: 5 }, { id: "" }
        ];
        assertEqual(rules.listOrder(statuses).join(","), "b2,beta,zeta,alpha,maps,notes",
                    "enabled first, then disabled, unconfirmed and held for approval, each by name (case-insensitive) then id; no duplicates");
        assertEqual(rules.listOrder([{ id: "x", state: "loaded" }, { id: "a", state: "loaded" }]).join(","), "a,x", "no name: by id");
        assertEqual(rules.listOrder(null).length, 0, "nothing: nothing");
        assert(rules.isOn({ state: "loaded", enabled: true }) && rules.isOn({ state: "failed" }), "isOn: loaded or failed while enabled");
        assert(!rules.isOn({ state: "approval", enabled: true }) && !rules.isOn({ state: "unconfirmed", enabled: true })
               && !rules.isOn({ state: "loaded", enabled: false }) && !rules.isOn({ state: "disabled" }), "… not held, new or turned off");

        assertEqual(JSON.stringify(rules.marks({ warnings: ["a"], deprecations: ["b", "c"] })),
                    JSON.stringify([{ kind: "warning", count: 1, tip: "1 warning" }, { kind: "deprecation", count: 2, tip: "2 deprecated API uses" }]),
                    "marks: each with its count and a tip saying what it counts");
        assertEqual(rules.marks({ warnings: ["a", "b"], deprecations: ["c"] }).map(mark => mark.tip).join(","), "2 warnings,1 deprecated API use", "… singular and plural");
        assertEqual(rules.marks({ warnings: [], deprecations: [] }).length + rules.marks(null).length, 0, "none: no marks");
    }

    function _checks() {
        const rules = ModuleInstallRules;
        const at = new Date(2026, 10, 21, 14, 32).getTime();
        assertEqual(rules.checkResultText({ outcome: "current", checkedAt: at }), "Up to date · checked 14:32", "up to date, with the time");
        assertEqual(rules.checkResultText({ outcome: "current", checkedAt: new Date(2026, 0, 1, 9, 5).getTime() }), "Up to date · checked 09:05", "… two digits each");
        assertEqual(rules.checkResultText({ outcome: "current" }), "Up to date", "… no time known: none said");
        assertEqual(rules.checkResultText({ outcome: "available", version: "1.3.0", downloading: true }), "1.3.0 available — downloading", "available, downloading");
        assertEqual(rules.checkResultText({ outcome: "available", version: "1.3.0" }), "1.3.0 available", "available, downloaded");
        assertEqual(rules.checkResultText({ outcome: "failed", reason: "codeberg.org did not answer" }), "Check failed: codeberg.org did not answer", "failed, with why");
        assertEqual(rules.checkResultText({ outcome: "failed", reason: "a\nb" + "c".repeat(300) }).indexOf("\n"), -1, "… a reason from outside on one line");
        assert(rules.checkResultText({ outcome: "failed", reason: "c".repeat(300) }).length < 150, "… capped");
        assertEqual(rules.checkResultText(null) + rules.checkResultText({ outcome: "x" }), "", "no result: no line");
        assertEqual(rules.checkSummaryText([{ outcome: "available" }, { outcome: "available" }, { outcome: "current" }, { outcome: "failed" }]),
                    "2 updates · 1 up to date · 1 failed", "Check all's summary");
        assertEqual(rules.checkSummaryText([{ outcome: "available" }]), "1 update", "… only the parts with a count");
        assertEqual(rules.checkSummaryText(null), "", "… nothing: no line");
        assertEqual(rules.checkingText(2, 4), "Checking 2 of 4…", "while it runs");
        assertEqual(rules.checkingText(0, 4) + " " + rules.checkingText(9, 4) + " " + rules.checkingText(1, 0), "Checking 1 of 4… Checking 4 of 4… Checking…", "… kept in range");
    }

    // The installer's decisions (singletons/ModuleInstaller.qml)
    function _installerSteps() {
        const rules = ModuleInstallRules;
        const records = rules.parseRecord(_recordText());

        // What install was given
        let source = rules.installSource("file:///srv/repos/weather.git#v1.2.0");
        assertEqual(source.kind + " " + source.url + " " + source.ref, "repository file:///srv/repos/weather.git v1.2.0", "install: an address with its ref");
        source = rules.installSource(home + "/src/notes/");
        assertEqual(source.kind + " " + source.folder, "folder " + home + "/src/notes", "install: an absolute path is a folder, cleaned");
        assertEqual(rules.installSource("/srv/../etc").kind, "", "… a path with \"..\": refused");
        assertEqual(rules.installSource("/").kind, "", "… the root: refused");
        assertEqual(rules.installSource("/srv/a\nb").kind, "", "… control characters: refused");
        assertEqual(rules.installSource("ext::sh -c touch% /tmp/x").kind, "", "… a transport that runs commands: refused");
        assert(rules.installSource("ext::sh").problem !== "", "… with why");
        assertEqual(rules.installSource("").problem + "|" + rules.installSource(null).problem, "No address or folder given|No address or folder given", "… nothing given");
        assertEqual(rules.fetchSource({ address: "file:///srv/clip.git", ref: "v0.2" }).address, "file:///srv/clip.git#v0.2", "a dependency's source: the address at its ref");
        assertEqual(rules.fetchSource({ address: home + "/src/clip", ref: "" }).kind, "folder", "… a folder copy: the folder again");
        assertEqual(rules.fetchSource({ address: "-oProxyCommand=x", ref: "" }).kind, "", "… refused as any address");

        // Version directories
        assertEqual(rules.versionDirectoryName("1.2.0", weatherCommit, 0), "1.2.0-abcdef1", "a version's directory: version and commit");
        assertEqual(rules.versionDirectoryName("1.2.0", "", Date.UTC(2026, 10, 21, 14, 32, 5)), "1.2.0-20261121143205", "… a folder copy: the time, UTC");
        assertEqual(rules.versionDirectoryName("../x y", weatherCommit, 0), "x-y-abcdef1", "… a version from outside made a plain name");
        assertEqual(rules.versionDirectoryName("", "zz", NaN), "0-00000000000000", "… nothing usable: still a plain name");
        assert(rules._versionDirectory(rules.versionDirectoryName("1.0.0-beta+7", weatherCommit, 0)), "… what parseRecord accepts as a directory");

        // What an id finds in the user root
        const entries = [{ entry: places.user + "/weather", isLink: true, target: places.versions + "/weather/1.2.0-abcdef1" },
                         { entry: places.user + "/mine", isLink: false, target: places.user + "/mine" },
                         { entry: places.user + "/elsewhere", isLink: true, target: home + "/src/elsewhere" },
                         { entry: places.user + "/dangling", isLink: true, target: "" }];
        const sources = { complete: true, roots: roots, entries: entries };
        assertEqual(rules.installTarget("clipboard", sources, records).kind, "new", "target: nothing of that name: new");
        let target = rules.installTarget("weather", sources, records);
        assertEqual(target.kind + " " + target.previousDir + " " + target.previousRecord?.address, "update 1.2.0-abcdef1 https://codeberg.org/anna/weather.git",
                    "… the shell's own link: an update, from the active version");
        target = rules.installTarget("mine", sources, records);
        assertEqual(target.kind, "taken", "… a folder placed by hand: taken, never replaced");
        assert(target.problem.includes("not installed by the shell") && target.problem.includes("remove it first"), "… with why: " + target.problem);
        assertEqual(rules.installTarget("elsewhere", sources, records).kind + " " + rules.installTarget("dangling", sources, records).kind, "taken taken", "… a hand-made link, a dangling one: taken");
        assertEqual(rules.installTarget("weather", sources, { ok: false, modules: {}, dropped: [] }).kind, "taken", "… a record that cannot be read: taken (unknown, never fine)");
        assertEqual(rules.installTarget("clipboard", { complete: false, roots: roots, entries: [] }, records).kind, "taken", "… a check that did not finish: taken");
        assertEqual(rules.installTarget("../x", sources, records).kind, "taken", "… not a module id: taken");
        target = rules.installTarget("weather", sources, records, [home + "/src/elsewhere"]);
        assertEqual(target.kind, "taken", "… the same id held by a module in the user root under another name (a hand-made link): taken");
        assert(target.problem.includes("as elsewhere"), "… naming the entry: " + target.problem);
        assertEqual(rules.installTarget("mine", sources, records, [places.user + "/mine"]).kind, "taken", "… a folder of that name: still taken");
        assertEqual(rules.installTarget("weather", sources, records, [places.versions + "/weather/1.2.0-abcdef1", "/usr/share/h2s-shell/modules/weather"]).kind,
                    "update", "… its own copy, and copies outside the user root (system, built in): no hindrance");
        assertEqual(rules.installTarget("clipboard", sources, records, [home + "/dev/modules/clipboard"]).kind, "new", "… a development copy: no hindrance");
        assertEqual(rules.installedEntry("weather", sources, records)?.source, "repository", "installed entry: the shell's own");
        assertEqual(rules.installedEntry("mine", sources, records), null, "… a hand-placed one: none");

        // The staged module's check
        const goodCheck = { manifest: { valid: true, id: "clipboard", errors: [] }, compatible: true, errors: [], mainFileError: "" };
        assertEqual(rules.stagedProblem(goodCheck, "clipboard") + rules.stagedProblem(goodCheck, ""), "", "staged: valid, fits, files fine");
        assert(rules.stagedProblem(goodCheck, "weather").includes("not weather"), "… another id than the chain asked for: refused");
        assert(rules.stagedProblem({ manifest: { valid: false, errors: ["api: missing"] }, errors: ["api: missing"] }, "").startsWith("module.json: api: missing"), "… an invalid manifest");
        assertEqual(rules.stagedProblem({ manifest: { valid: true, id: "a" }, compatible: false, errors: ["needs API 9.0"] }, ""), "needs API 9.0", "… an API that does not fit");
        assertEqual(rules.stagedProblem({ manifest: { valid: true, id: "a" }, compatible: true, errors: [], mainFileError: "Main.qml leads out of the module" }, ""),
                    "Main.qml leads out of the module", "… a file out of the module");
        assertEqual(rules.stagedProblem({ manifest: { valid: true, id: "a" }, compatible: true, errors: ["x\ny"], mainFileError: "" }, ""), "x y", "… any error, on one line");
        assertEqual(rules.stagedProblem(null, ""), "module.json: it could not be read", "… no check: refused");
        assertEqual(rules.stagedSizeProblem("120\t/x"), "", "size: small");
        assert(rules.stagedSizeProblem(String(200 * 1024) + "\t/x").includes("larger than 100 MiB"), "… too large");
        assertEqual(rules.stagedSizeProblem(""), "its size could not be read", "… unreadable: refused");
        assertEqual(rules.stagedSizeProblem("65\t/x", 64 * 1024), "it is larger than 64 KiB", "… against a cap given");
        assertEqual(rules.linkProblem(["/s/x/a\t/s/x/b"], "/s/x"), "", "links: inside the module");
        assert(rules.linkProblem(["/s/x/a\t/etc/passwd"], "/s/x").includes("a link leads out of the module: a"), "… one out: refused, named");
        assert(rules.linkProblem(["/s/x/a\t"], "/s/x") !== "" && rules.linkProblem(["/s/x/a\t/s/x"], "/s/x") !== "", "… dangling, or the module itself: refused");
        assert(rules.linkProblem(["junk"], "/s/x") !== "" && rules.linkProblem([], "") !== "", "… unreadable: refused");

        // A failed download, in one line
        assertEqual(rules.downloadProblem({ timedOut: true }, "", { timeoutMs: 120000 }), "the server did not answer within 120 s", "download: no answer in time");
        assertEqual(rules.downloadProblem({ code: 128 }, "fatal: repository 'x' not found", {}), "git: repository 'x' not found", "… git's own line");
        assertEqual(rules.downloadProblem({ code: 1 }, "", {}), "git failed (status 1)", "… nothing said");
        assertEqual(rules.downloadProblem({ code: -1, failedToStart: true }, "", {}), "git could not be run", "… git missing");
        assertEqual(rules.downloadProblem({ cancelled: true }, "", { tooLarge: true }), "it is larger than 100 MiB", "… stopped for its size");
        assertEqual(rules.downloadProblem({ cancelled: true }, "", { tooLarge: true, cap: 2 * 1024 * 1024 }), "it is larger than 2 MiB", "… against the cap given");
        assertEqual(rules.downloadProblem({ code: 128 }, "fatal: <b>x</b>‮" + "y".repeat(300), {}).length <= 125, true, "… text from outside capped");

        // The installed modules as the chain plan takes them
        const installed = rules.installedModules([
            { status: { id: "weather", name: "Weather", version: "1.2.0", api: "1.36", source: "repository", state: "loaded" },
              manifest: { exports: { version: "1.2" }, uses: [] } },
            { status: { id: "mine", name: "Mine", version: "0.1", api: "1.0", source: "user", state: "loaded" }, manifest: null },
            { status: { id: "weather", name: "Weather copy", state: "duplicate", source: "builtin" }, manifest: {} }
        ], records);
        assertEqual(JSON.stringify(Object.keys(installed)), JSON.stringify(["weather", "mine"]), "installed: the ones that count, once");
        assertEqual(installed.weather.address + " " + installed.weather.ref + " " + installed.weather.exports.version, "https://codeberg.org/anna/weather.git v1.2.0 1.2",
                    "… the shell's own with its recorded address and its exports");
        assertEqual(installed.mine.address + "|" + JSON.stringify(installed.mine.uses) + "|" + installed.mine.exports, "|[]|null", "… a hand-placed one: no address");

        // The record, changed
        let modules = rules.recordInstalled({}, "clipboard", { kind: "repository", address: "file:///srv/clip.git", ref: "v0.2", dir: "0.2.0-1234567",
                                                              version: "0.2.0", commit: "1234567", fetchedAt: "t", installedFor: "notes" });
        assertEqual(modules.clipboard.active + " " + modules.clipboard.installedFor + " " + modules.clipboard.versions.length, "0.2.0-1234567 notes 1", "record: a new module");
        assert(rules.parseRecord(rules.recordText(modules)).modules.clipboard !== undefined, "… what parseRecord reads back");
        const before = JSON.stringify(records.modules);
        modules = rules.recordInstalled(records.modules, "weather", { kind: "repository", address: "https://codeberg.org/anna/weather.git", ref: "main",
                                                                      dir: "1.3.0-7654321", version: "1.3.0", commit: "7654321", installedFor: "other" });
        assertEqual(modules.weather.versions.map(each => each.dir).join(",") + " " + modules.weather.active + " " + modules.weather.ref + " " + modules.weather.installedFor,
                    "1.2.0-abcdef1,1.1.0-1234567,1.3.0-7654321 1.3.0-7654321 main ", "… an update: kept versions stay, whom it was installed for stays");
        assertEqual(JSON.stringify(records.modules), before, "… the map given is not changed");
        const staged = rules.recordStaged(records.modules, "weather", { kind: "repository", address: "https://codeberg.org/anna/weather.git", ref: "",
                                                                        dir: "1.3.0-7654321", version: "1.3.0", commit: "7654321" });
        assertEqual(staged.weather.active + " " + staged.weather.versions.length, "1.2.0-abcdef1 3", "staged: the new version listed, the active one kept until the link moves");
        assertEqual(rules.recordStaged({}, "clipboard", { kind: "repository", address: "file:///srv/c.git", dir: "0.2.0-1234567", version: "0.2.0" }).clipboard.active,
                    "0.2.0-1234567", "… a new module: its only version");
        assert(rules.parseRecord(rules.recordText(staged)).modules.weather !== undefined, "… what parseRecord reads back");
        const raw = JSON.stringify({ weather: { kind: "repository", future: 1 }, "Bad Id": { x: 1 }, notes: { kind: "folder" } });
        const spliced = JSON.parse(rules.recordTextWithout(raw, ["notes"]));
        assertEqual(JSON.stringify(Object.keys(spliced)) + " " + spliced.weather.future, "[\"weather\",\"Bad Id\"] 1",
                    "remove's record: only the removed entry goes, unknown fields and entries parseRecord dropped stay");
        assertEqual(rules.recordTextWithout("{", ["x"]) + " " + rules.recordTextWithout("[]", ["x"]), "null null", "… a text that is no object: nothing written");
        const cutEntries = entries.concat([{ entry: places.user + "/notes", isLink: true, target: places.versions + "/notes/0.4.0-20261121120000" }]);
        let reconciled = rules.reconcileRecord({ complete: true, roots: roots, entries: cutEntries }, records);
        assertEqual(reconciled.changed + " " + reconciled.modules.notes.active + " " + reconciled.modules.notes.versions.map(each => each.version).join(","),
                    "true 0.4.0-20261121120000 0.3.0,0.4.0", "reconcile: a link to a version the record does not list: listed and active");
        assertEqual(reconciled.modules.weather.active, "1.2.0-abcdef1", "… the others as they were");
        const switchedEntries = [{ entry: places.user + "/weather", isLink: true, target: places.versions + "/weather/1.1.0-1234567" }];
        reconciled = rules.reconcileRecord({ complete: true, roots: roots, entries: switchedEntries }, records);
        assertEqual(reconciled.changed + " " + reconciled.modules.weather.active + " " + reconciled.modules.weather.versions.length, "true 1.1.0-1234567 2",
                    "… a link moved to a listed version the record does not have active: made active");
        assertEqual(rules.reconcileRecord(sources, records).changed, false, "… everything as recorded: nothing changes");
        reconciled = rules.reconcileRecord({ complete: true, roots: roots, entries: [{ entry: places.user + "/weather", isLink: true, target: "" }] }, records);
        assertEqual(reconciled.changed, false, "… a link whose version directory is gone (no target): nothing changes");
        reconciled = rules.reconcileRecord({ complete: true, roots: roots, entries: [{ entry: places.user + "/stray", isLink: true, target: places.versions + "/stray/1.0.0-1234567" }] }, records);
        assertEqual(reconciled.changed + " " + reconciled.notes.length, "false 1", "… an id the record does not have: named, not invented");
        assertEqual(rules.reconcileRecord({ complete: true, roots: roots, entries: cutEntries }, { ok: false, modules: {}, dropped: [] }).changed
                    || rules.reconcileRecord({ complete: false, roots: roots, entries: cutEntries }, records).changed, false, "… an unreadable record or check: nothing");
        assertEqual(rules.recordSwitched(modules, "weather", "1.1.0-1234567").weather.active, "1.1.0-1234567", "switched: another kept version active");
        assertEqual(rules.recordSwitched(modules, "weather", "9.9.9-0000000"), null, "… a version not kept: none");
        assertEqual(rules.recordWithoutVersions(modules, "weather", ["1.1.0-1234567", "1.3.0-7654321"]).weather.versions.map(each => each.dir).join(","),
                    "1.2.0-abcdef1,1.3.0-7654321", "versions dropped, never the active one");
        assertEqual(rules.recordWithout(modules, "weather").weather, undefined, "an entry gone");
        assertEqual(rules.recordRestored(modules, "weather", records.modules.weather).weather.active, "1.2.0-abcdef1", "… restored as it was");
        assertEqual(rules.recordRestored(modules, "clipboard", null).clipboard, undefined, "… none before: gone");
        const text = rules.recordText({ b: records.modules.weather, a: records.modules.notes });
        assert(text.indexOf("\"a\"") < text.indexOf("\"b\""), "record text: ids in order");
        assertEqual(rules.recordChunks("x".repeat(70000)).map(chunk => chunk.length).join(","), "32768,32768,4464", "… handed over in pieces");
        assertEqual(rules.recordChunks("😀".repeat(20000)).join(""), "😀".repeat(20000), "… never splitting a character");
        assert(rules.recordChunks("😀".repeat(20000)).every(chunk => chunk.length <= rules.recordChunkLength && !/^[\udc00-\udfff]/.test(chunk)), "… each within the length");
        assertEqual(rules.recordChunks("x".repeat(rules.maxRecordBytes + 1)), null, "… longer than the check reads: not written");

        // What may be deleted
        let deletion = rules.deletionTarget(places.user + "/weather", places);
        assertEqual(deletion.ok + " " + deletion.root + " " + deletion.relative, "true " + places.user + " weather", "delete: a user root entry");
        deletion = rules.deletionTarget(places.versions + "/weather/1.2.0-abcdef1", places);
        assertEqual(deletion.relative, "weather/1.2.0-abcdef1", "… a version");
        assertEqual(rules.deletionTarget(places.versions + "/weather", places).relative, "weather", "… a module's versions");
        assertEqual(rules.deletionTarget(places.user + "/My.Module", places).ok, true, "… a folder placed by hand in the user root, under any plain name");
        assertEqual(rules.deletionTarget(places.data + "/My.Module", places).ok, false, "… elsewhere only a module id");
        assertEqual(rules.deletionTarget(places.staging + "/install.Ab12Cd", places).ok, true, "… a staging directory");
        assertEqual(rules.deletionTarget(places.stores + "/weather", places).root + " " + rules.deletionTarget(places.data + "/weather", places).root,
                    places.stores + " " + places.data, "… a store, a data directory");
        assertEqual(rules.deletionTarget(places.user, places).ok || rules.deletionTarget(home, places).ok || rules.deletionTarget("/", places).ok
                    || rules.deletionTarget(places.user + "/../x", places).ok || rules.deletionTarget(places.user + "/a/b", places).ok
                    || rules.deletionTarget(places.versions + "/weather/..", places).ok || rules.deletionTarget(places.user + "/-x", places).ok
                    || rules.deletionTarget("relative/x", places).ok || rules.deletionTarget(places.user + "/x", {}).ok, false,
                    "… a place itself, the home, the root, \"..\", deeper, an option-like name, no places: never");

        // Switch and delete a version
        const found = rules.installedEntry("weather", sources, records);
        let plan = rules.switchPlan("weather", "1.1.0-1234567", found, records.modules.weather);
        assertEqual(plan.ok + " " + plan.dir + " " + plan.previousDir, "true 1.1.0-1234567 1.2.0-abcdef1", "switch: to a kept version");
        assertEqual(rules.switchPlan("weather", places.versions + "/weather/1.1.0-1234567", found, records.modules.weather).dir, "1.1.0-1234567", "… given as its path");
        assert(rules.switchPlan("weather", "1.2.0-abcdef1", found, records.modules.weather).problem.includes("already the active"), "… the active one: refused");
        assert(rules.switchPlan("weather", "2.0.0-0000000", found, records.modules.weather).problem.includes("not a kept version"), "… one not kept: refused");
        assert(!rules.switchPlan("weather", "../x", found, records.modules.weather).ok, "… not a version name: refused");
        assert(!rules.switchPlan("mine", "1.0", null, null).ok, "… not installed by the shell: refused");
        assertEqual(rules.deleteVersionPlan("weather", "1.1.0-1234567", found, records.modules.weather).ok, true, "delete a version: a kept one");
        assert(rules.deleteVersionPlan("weather", "1.2.0-abcdef1", found, records.modules.weather).problem.includes("active"), "… the active one: refused");
        assert(!rules.deleteVersionPlan("weather", "3.0.0-0000000", found, records.modules.weather).ok, "… one not kept: refused");

        // Back on a failed start
        assert(rules.backOnFailedStart({ kind: "update", dir: "1.3.0-7654321", previousDir: "1.2.0-abcdef1" }, { state: "failed" }), "a failed start after an update: back");
        assert(rules.backOnFailedStart({ kind: "switch", dir: "1.1.0-1234567", previousDir: "1.2.0-abcdef1" }, { state: "failed" }), "… after a switch: back");
        assert(!rules.backOnFailedStart({ kind: "install", dir: "1.0.0-1234567", previousDir: "" }, { state: "failed" }), "… a new module: keeps its files, shows Failed");
        assert(!rules.backOnFailedStart({ kind: "update", dir: "1.3.0-7654321", previousDir: "1.2.0-abcdef1" }, { state: "loaded" }), "… one that started: stays");
        assert(!rules.backOnFailedStart({ kind: "update", dir: "1.3.0-7654321", previousDir: "" }, { state: "failed" }), "… no version before known: stays");
        assert(!rules.backOnFailedStart(null, null), "… nothing known: nothing done");
    }
}
