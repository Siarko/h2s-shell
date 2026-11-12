import QtQuick
import qs.singletons

TestCase {
    suiteName: "PolkitRules"

    function run() {
        const rules = PolkitRules;

        // --- finding agents in a process list ---
        assertEqual(JSON.stringify(rules.agentsIn(["/usr/lib/hyprpolkitagent/hyprpolkitagent", "kitty", "bash -l"])),
                    "[\"hyprpolkitagent\"]", "by the program's name, path dropped");
        assertEqual(JSON.stringify(rules.agentsIn(["/nix/store/x-polkit-gnome/libexec/polkit-gnome-authentication-agent-1 --flag"])),
                    "[\"polkit-gnome-authentication-agent-1\"]", "arguments ignored");
        assertEqual(rules.agentsIn(["vim hyprpolkitagent.conf", "grep hyprpolkitagent"]).length, 0,
                    "a name in the arguments is not the agent");
        assertEqual(rules.agentsIn(["/usr/lib/polkit-1/polkit-agent-helper-1"]).length, 0,
                    "polkit's helper (run by any agent, the shell's too) is no agent");
        assertEqual(rules.agentsIn(["soteria", "soteria"]).length, 1, "each once");
        assertEqual(rules.agentsIn([]).length, 0, "none");

        // --- the first start ---
        assertEqual(rules.firstStart(["hyprpolkitagent"], null), "off", "another agent running: stays off");
        assertEqual(rules.firstStart([], null), "try", "none running: tried");
        assertEqual(rules.firstStart([], true), "on", "tried and registered: on");
        assertEqual(rules.firstStart([], false), "off", "tried, not registered (an unknown agent holds it): off");

        // --- what is told ---
        assertEqual(rules.state("", false, []), "deciding", "undecided");
        assertEqual(rules.state("on", true, []), "active", "the shell's prompts");
        assertEqual(rules.state("on", false, []), "blocked", "on but not registered");
        assertEqual(rules.state("on", true, ["hyprpolkitagent"]), "conflict", "another one running beside the shell's");
        assertEqual(rules.state("off", false, ["hyprpolkitagent"]), "other", "another agent answers");
        assertEqual(rules.state("off", false, []), "none", "no agent at all");
        assertEqual(rules.state("off", false, [], true), "other", "an agent the shell does not know: refused its registration");
    }
}
