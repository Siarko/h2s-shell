pragma Singleton

import Quickshell
import QtQuick

// The polkit agent's decisions — pure, so tests/PolkitRulesTest.qml checks them without
// polkit. Authentication holds the live state; docs/plans/polkit.md has the reasoning.
Singleton {
    id: root

    // Authentication agents by their program's name, as a process list shows it. Not
    // every agent there is, the usual ones: one not here is still found at the first start
    // by the shell failing to register.
    readonly property var knownAgents: [
        "hyprpolkitagent",
        "polkit-gnome-authentication-agent-1",
        "polkit-kde-authentication-agent-1",
        "polkit-mate-authentication-agent-1",
        "lxqt-policykit-agent",
        "lxpolkit",
        "xfce-polkit",
        "soteria",
        "polkit-dumb-agent"
    ]

    // The known agents among `commands` (each a process's command line): their names
    function agentsIn(commands) {
        const found = [];
        for (const command of commands ?? []) {
            const program = String(command).trim().split(/\s+/)[0] ?? "";
            const name = program.slice(program.lastIndexOf("/") + 1);
            if (knownAgents.includes(name) && !found.includes(name))
                found.push(name);
        }
        return found;
    }

    // At the first start: with another agent running, the shell's stays off; with none,
    // it is tried, and kept on if it registered. → "off", "try", "on"
    function firstStart(othersRunning, triedAndRegistered) {
        if ((othersRunning ?? []).length > 0)
            return "off";
        if (triedAndRegistered === undefined || triedAndRegistered === null)
            return "try";
        return triedAndRegistered ? "on" : "off";
    }

    // What to tell about the agents: "deciding", "active" (the shell's prompts), "blocked"
    // (the shell's is on but could not register: another holds the session), "conflict"
    // (the shell's holds it while another agent runs, unable to register), "other"
    // (another agent answers — a known one running, or `unknownAgent`: the shell was
    // refused registering), "none" (no agent: requests for a password are refused)
    function state(mode, registered, othersRunning, unknownAgent) {
        const others = (othersRunning ?? []).length > 0;
        if (mode !== "on" && mode !== "off")
            return "deciding";
        if (mode === "on")
            return !registered ? "blocked" : others ? "conflict" : "active";
        return others || unknownAgent === true ? "other" : "none";
    }
}
