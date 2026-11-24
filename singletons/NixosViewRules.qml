pragma Singleton

import Quickshell
import QtQuick

// What Settings → System → NixOS (panels/settings/NixosSettings.qml) shows for a reading of
// the system's NixOS configuration (NixosConfigRules.reading), and what its Create does
// (tests/NixosViewRulesTest.qml). Pure.
//
// The page shows one of: nothing read yet; not connected (no configuration that imports the
// shell's NixOS module: every setting keeps its lines to copy); found (the module in force,
// the shell's file not: the one-time setup — create the file, add the line once); connected
// (the facts, the generations). A configuration whose folder is the user's own (or whose
// owner could not be told) shows the home-folder warning once, until "Use it"; the one-time
// setup waits for that answer.
Singleton {
    id: root

    // The page is listed only on NixOS
    function pageShown(distributionId) {
        return distributionId === "nixos";
    }

    readonly property var texts: ({
        title: "NixOS configuration",
        intro: "The shell can keep its settings in your NixOS configuration and apply them by rebuilding NixOS. Turn that on here.",
        reading: "Looking for the configuration…",
        notConnected: "Not connected",
        notConnectedCaption: "No NixOS configuration found that imports the shell's NixOS module. Built on another machine? Then keep copying the lines.",
        found: "Found, not connected yet: the shell's file is not in force.",
        connected: "Connected",
        generations: "Each Apply adds a generation. The shell never deletes them.",
        homeTitle: "This configuration is in your home folder.",
        homeBody: "Any program you run can change it, and NixOS builds it as root at every rebuild. The shell writes its file there without a password.",
        createStep: "Create the shell's file, h2s-shell.json.",
        created: "h2s-shell.json is created.",
        unread: "h2s-shell.json could not be read.",
        createTooltip: "Asks for an administrator's password",
        git: "In git: run git add h2s-shell.json once. The shell never commits.",
        lineStep: "Add this line once to your configuration, then run nixos-rebuild switch.",
        noticed: "This page notices when it is in force.",
        chooserTitle: "The NixOS configuration's folder"
    })

    // The line the configuration takes once, and where it goes → { line, caption }. Where it
    // goes is the configuration's entry file, which is beside the shell's file, so `./` names
    // that file there: a flake's flake.nix takes it as a module in its modules list, a
    // classic configuration's file as one more option among its own. (An absolute path would
    // not do: a flake is evaluated without access to paths outside it.)
    function settingsLine(reading) {
        const option = "programs.h2s-shell.settingsFile = ./" + NixosConfigRules.fileName + ";";
        const entry = String(reading?.configuration?.entry ?? "");
        if (reading?.configuration?.type === "flake")
            return { line: "{ " + option + " }", caption: "In flake.nix, in your system's modules list. " + texts.noticed };
        return { line: option, caption: "In " + (entry !== "" ? entry : "configuration.nix") + ", among its options. " + texts.noticed };
    }

    // How Create writes the shell's file of this reading: "root" (a root-owned configuration:
    // the root step's create, asking the password at the click), "user" (any other: written as
    // the user, no password — an owner chain not known is the user's for writing, as for the
    // root step) or "" (no Create: not the one-time setup, or the file is there or unread)
    function createWay(reading) {
        if (reading?.state !== "found" || reading?.configuration?.found !== true || reading?.file?.state !== "absent")
            return "";
        if (reading.homeWarning === true)
            return "";
        return reading.rootWrites === true ? "root" : "user";
    }

    // The words of scripts/nixos-create.sh for the user's own configuration; [] for none
    function userCreateArgv(command, reading) {
        const folder = reading?.configuration?.folder;
        if (createWay(reading) !== "user" || !NixosConfigRules.plainPath(folder) || !Array.isArray(command) || command.length === 0)
            return [];
        return Array.from(command).concat([folder]);
    }

    // scripts/nixos-create.sh's answer (CommandRunner's result) → { ok, quiet, error }
    function userCreateOutcome(result) {
        const lines = String(result?.stdout ?? "").trim().split("\n");
        const last = lines[lines.length - 1].trim();
        if (result?.ok === true && result.code === 0 && last === "created")
            return { ok: true, quiet: false, error: "" };
        if (result?.code === 3 && last === "exists")
            return { ok: false, quiet: false, error: NixosApplyRules.texts.exists };
        return { ok: false, quiet: false, error: NixosApplyRules.texts.write };
    }

    // The root step's create outcome (NixosApplyRules.reply) → { ok, quiet, error }
    function rootCreateOutcome(outcome) {
        if (outcome?.ok === true && outcome.kind === "created")
            return { ok: true, quiet: false, error: "" };
        if (outcome?.quiet === true)
            return { ok: false, quiet: true, error: "" };
        return { ok: false, quiet: false, error: typeof outcome?.error === "string" && outcome.error !== "" ? outcome.error : NixosApplyRules.texts.unclear };
    }

    // The page for a reading (null: none yet), `busy` (a read or a Create under way) →
    // { state ("" | "notConnected" | "found" | "connected"), status { text, tone ("muted" |
    // "warning" | "success") }, caption (under the status, "" none), facts [{ name, value }],
    // generationsShown, change (Change… beside the title), chooseFolder (Choose folder… in the
    // status line), lookAgain { shown, available }, home (the home-folder warning), setup {
    // shown, create { shown, way, privileged, available, tooltip }, step (step 1's text),
    // stepDone (step 1 done or not possible: muted), git (the git line shown), line and
    // lineCaption (settingsLine's) } }
    function view(reading, busy) {
        const working = busy === true;
        const state = reading === null || typeof reading !== "object" ? "" : String(reading.state ?? "");
        const connected = state === "connected", found = state === "found";
        const known = connected || found;
        const result = {
            state,
            status: connected ? { text: texts.connected, tone: "success" }
                : found ? { text: texts.found, tone: "warning" }
                : state === "notConnected" ? { text: texts.notConnected, tone: "muted" }
                : { text: texts.reading, tone: "muted" },
            caption: state === "notConnected" ? texts.notConnectedCaption : "",
            facts: known && Array.isArray(reading.facts) ? reading.facts.map(row => ({ name: String(row.name), value: String(row.value).slice(0, 400) })) : [],
            generationsShown: connected,
            change: known,
            chooseFolder: state === "notConnected",
            lookAgain: { shown: !connected, available: !working },
            home: known && reading.homeWarning === true,
            setup: { shown: false, create: { shown: false, way: "", privileged: false, available: false, tooltip: "" }, step: "", stepDone: false, git: false,
                     line: "", lineCaption: "" }
        };
        if (found && reading.homeWarning !== true) {
            const way = createWay(reading);
            const fileState = reading.file?.state;
            result.setup = {
                shown: true,
                create: { shown: way !== "", way, privileged: way === "root", available: way !== "" && !working,
                          tooltip: way === "root" ? texts.createTooltip : "" },
                step: fileState === "present" ? texts.created : fileState === "absent" ? texts.createStep : texts.unread,
                stepDone: fileState !== "absent",
                git: reading.git === "present" && reading.gitKnowsFile !== "tracked",
                line: settingsLine(reading).line,
                lineCaption: settingsLine(reading).caption
            };
        }
        return result;
    }
}
