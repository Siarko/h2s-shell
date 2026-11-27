import QtQuick
import qs.singletons

// NixosViewRules: the NixOS page for each reading — nothing read yet, not connected, found
// (the one-time setup: Create the root step's way or the user's, the file there or unread,
// the git line), connected (the facts, Generations), the home-folder warning holding the
// setup back — the page listed only on NixOS, Create's words and answers. Pure.
TestCase {
    suiteName: "NixosViewRules"

    function run() {
        const rules = NixosViewRules;
        const show = value => JSON.stringify(value);
        const folder = "/srv/nixos-config";
        const reading = more => {
            const result = Object.assign({
                configuration: { found: true, folder, entry: "flake.nix", type: "flake" },
                real: folder, owner: "root", rootWrites: true, git: "present", gitKnowsFile: "tracked", host: "nixos",
                file: { path: folder + "/h2s-shell.json", state: "absent", sha256: "" },
                fileStatus: "notCreated", generations: { count: 14, current: 14 }, state: "found", homeWarning: false
            }, more ?? {});
            result.facts = NixosConfigRules.facts(result);
            return result;
        };

        // Listed only on NixOS
        assertEqual(["nixos", "arch", "generic", ""].map(id => rules.pageShown(id)).join(" "), "true false false false",
                    "pageShown: NixOS only, never while the distribution is not known");
        assertEqual(JSON.stringify(rules.settingsLine(reading())), JSON.stringify({ line: "{ programs.h2s-shell.settingsFile = ./h2s-shell.json; }",
                    caption: "In flake.nix, in your system's modules list. This page notices when it is in force." }),
                    "settingsLine: a flake: a module for its modules list, flake.nix beside the file");
        assertEqual(JSON.stringify(rules.settingsLine(reading({ configuration: { found: true, folder, entry: "machine.nix", type: "classic" } }))),
                    JSON.stringify({ line: "programs.h2s-shell.settingsFile = ./h2s-shell.json;", caption: "In machine.nix, among its options. This page notices when it is in force." }),
                    "… classic: an option in its entry file, beside the file");
        assertEqual(rules.texts.intro, "The shell can keep its settings in your NixOS configuration and apply them by rebuilding NixOS. Turn that on here.",
                    "the intro");

        // Nothing read yet
        const none = rules.view(null, true);
        assertEqual(none.state + "|" + none.status.text + "|" + none.facts.length + "|" + none.folder + "|" + none.setup.shown + "|" + none.lookAgain.available,
                    "|Looking for the configuration…|0||false|false", "before a reading: looking, no folder, nothing else, Look again waits");
        assertEqual([none.change, none.chooseFolder].join(" "), " ", "… no fields for other folder buttons: Select directory is always the page's");

        // Not connected
        const off = rules.view(reading({ state: "notConnected", configuration: { found: false, folder: "", entry: "", type: "" }, searched: ["/etc/nixos", "/srv/c"] }), false);
        assertEqual(off.status.text + "|" + off.status.tone + "|" + off.caption, "Not connected|muted|" + rules.texts.notConnectedCaption,
                    "not connected: the status and the lines-to-copy caption");
        assertEqual([off.facts.length, off.folder, off.lookAgain.shown, off.home, off.setup.shown, off.generationsShown].join(" "),
                    "0 /etc/nixos, /srv/c true false false false", "… no facts, the places looked in, Look again, no setup");
        assertEqual(show(off.setup), show({ shown: false, create: { shown: false, way: "", privileged: false, available: false, tooltip: "" }, step: "", stepDone: false, git: false,
                    line: "", lineCaption: "" }), "… the setup all off");
        assert(!rules.view(reading({ state: "notConnected", homeWarning: true }), false).home, "… no home-folder warning without a configuration");
        assertEqual(rules.view(reading({ state: "notConnected" }), false).folder, folder, "… a configuration found without the shell's module: its folder");
        assertEqual(rules.view(reading({ state: "notConnected", configuration: { found: false, folder: "", entry: "", type: "" } }), false).folder, "",
                    "… no places told: none");

        // Found: the root's Create
        const found = rules.view(reading(), false);
        assertEqual(found.status.text + "|" + found.status.tone, "Found, not connected yet: the shell's file is not in force.|warning", "found: the status");
        assertEqual(found.facts.map(row => row.name).join(", "), "Type, Git, Host, The shell's file, File status",
                    "… the facts, one per line, no Generations, no Configuration (the folder's line says it)");
        assertEqual(found.facts[4].value, "Not created", "… their values");
        assertEqual([found.folder, found.lookAgain.shown, found.generationsShown].join(" "), folder + " true false",
                    "… the configuration's folder, Look again");
        assertEqual(show(found.setup), show({ shown: true, create: { shown: true, way: "root", privileged: true, available: true, tooltip: "Asks for an administrator's password" },
                                             step: "Create the shell's file, h2s-shell.json.", stepDone: false, git: false,
                                             line: "{ programs.h2s-shell.settingsFile = ./h2s-shell.json; }",
                                             lineCaption: "In flake.nix, in your system's modules list. This page notices when it is in force." }),
                    "… the setup: Create through the root step, marked, git knows the file");
        assert(!rules.view(reading(), true).setup.create.available, "… Create waits while a read or a Create runs");
        assertEqual(rules.createWay(reading()), "root", "createWay: a root-owned configuration: the root step");

        // Found: the user's own
        const yours = reading({ owner: "yours", rootWrites: false, homeWarning: false, gitKnowsFile: "untracked" });
        const user = rules.view(yours, false);
        assertEqual([user.setup.create.way, user.setup.create.privileged, user.setup.create.tooltip, user.setup.git].join("|"), "user|false||true",
                    "found, the user's own: Create as the user, no mark; the git line while git does not know the file");
        assertEqual(rules.createWay(reading({ owner: "unknown", rootWrites: false })), "user", "createWay: an owner not known: the user's for writing");
        assertEqual(show(rules.userCreateArgv(["/shell/scripts/nixos-create.sh"], yours)), show(["/shell/scripts/nixos-create.sh", folder]),
                    "userCreateArgv: the script and the folder");
        assertEqual(show(rules.userCreateArgv(["/s"], reading())), "[]", "… none for a root-owned configuration");
        assertEqual(show(rules.userCreateArgv(["/s"], reading({ rootWrites: false, configuration: { found: true, folder: "/a/../b", entry: "flake.nix", type: "flake" } }))),
                    "[]", "… none for a folder that is not plain");
        assertEqual(show(rules.userCreateArgv([], yours)) + show(rules.userCreateArgv("/s", yours)), "[][]", "… none without the script");

        // The home-folder warning holds the setup back
        const home = rules.view(reading({ owner: "yours", rootWrites: false, homeWarning: true }), false);
        assertEqual([home.home, home.setup.shown, home.setup.create.shown].join(" "), "true false false", "home folder: the warning, no setup until Use it");
        assertEqual(rules.createWay(reading({ rootWrites: false, homeWarning: true })), "", "… and no Create");

        // The file there, or unread
        const there = rules.view(reading({ file: { path: folder + "/h2s-shell.json", state: "present", sha256: "a" }, fileStatus: "created" }), false);
        assertEqual([there.setup.step, there.setup.stepDone, there.setup.create.shown].join("|"), "h2s-shell.json is created.|true|false",
                    "the file created: step 1 done, no Create");
        assertEqual(there.facts[4].value, "Created, not in force yet", "… its status");
        const unread = rules.view(reading({ file: { path: folder + "/h2s-shell.json", state: "unreadable", sha256: "" }, fileStatus: "unknown" }), false);
        assertEqual([unread.setup.step, unread.setup.create.shown].join("|"), "h2s-shell.json could not be read.|false", "the file unread: said, no Create");
        assertEqual(rules.createWay(reading({ state: "connected" })), "", "createWay: none once connected");

        // Connected
        const on = rules.view(reading({ state: "connected", fileStatus: "inForce", file: { path: folder + "/h2s-shell.json", state: "present", sha256: "a" } }), false);
        assertEqual(on.status.text + "|" + on.status.tone, "Connected|success", "connected: the status");
        assertEqual(on.facts.map(row => row.name + "=" + row.value).slice(4).join(", "), "File status=In force, Generations=14", "… File status and Generations");
        assertEqual([on.generationsShown, on.folder, on.lookAgain.shown, on.setup.shown].join(" "), "true " + folder + " false false",
                    "… the generations line, the folder, no Look again, no setup");
        assert(rules.view(reading({ state: "connected", homeWarning: true }), false).home, "… a home folder's warning once while connected too");
        const long = "/" + "x".repeat(1000);
        assertEqual(rules.view(reading({ file: { path: long, state: "absent", sha256: "" } }), false).facts[3].value.length, 400, "a fact's value is capped");
        assertEqual(rules.view(reading({ configuration: { found: true, folder: long, entry: "flake.nix", type: "flake" } }), false).folder.length, 400,
                    "… the folder too");
        assertEqual(rules.view(reading({ state: "notConnected", configuration: { found: false }, searched: [long, long] }), false).folder.length, 400,
                    "… and the folders looked in");

        // Create's answers
        assertEqual(show(rules.userCreateOutcome({ ok: true, code: 0, stdout: "created" })), show({ ok: true, quiet: false, error: "" }), "userCreateOutcome: created");
        assertEqual(rules.userCreateOutcome({ ok: false, code: 3, stdout: "exists" }).error, "h2s-shell.json is already there.", "… there already");
        assertEqual(rules.userCreateOutcome({ ok: false, code: 1, stdout: "failed" }).error, "h2s-shell.json could not be written: nothing changed.", "… failed");
        assertEqual(rules.userCreateOutcome({ ok: false, code: 1, stdout: "exists" }).error, "h2s-shell.json could not be written: nothing changed.",
                    "… \"exists\" without its exit: failed");
        assert(!rules.userCreateOutcome({ ok: true, code: 0, stdout: "exists" }).ok, "… a line that does not agree with the code: not created");
        assert(!rules.userCreateOutcome({ ok: false, code: 3, stdout: "created" }).ok && rules.userCreateOutcome({ ok: false, code: 3, stdout: "created" }).error !== "",
               "… exit 3 without its line: failed");
        assertEqual(show(rules.rootCreateOutcome({ ok: true, kind: "created" })), show({ ok: true, quiet: false, error: "" }), "rootCreateOutcome: created");
        assertEqual(show(rules.rootCreateOutcome({ ok: false, quiet: true, error: "" })), show({ ok: false, quiet: true, error: "" }), "… dismissed: quiet");
        assertEqual(rules.rootCreateOutcome({ ok: false, kind: "refused", error: "x" }).error, "x", "… refused: its text");
        assertEqual(rules.rootCreateOutcome({ ok: true, kind: "applied" }).error, NixosApplyRules.texts.unclear, "… another kind: unclear, never created");
    }
}
