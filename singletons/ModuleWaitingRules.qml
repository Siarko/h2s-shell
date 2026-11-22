pragma Singleton

import Quickshell
import QtQuick

// The notice that modules are held for the user's confirmation or approval: which modules wait,
// what the one notification says, and when it is raised, replaced or closed. One notification
// stands for the whole set of waiting modules; it stays until no module waits, a new one takes
// its place when the set changes; dismissed by the user, it is not raised again for the same
// set. It only opens Settings → Modules: confirming stays the page's (a click there).
// Pure: the module host's statuses in, words and actions out; ModuleWaitingNotice does the I/O.
// Checked by tests/ModuleWaitingRulesTest.qml.
Singleton {
    id: root

    // The states of a module held until the user says yes (ModuleMergeRules.stateOf)
    readonly property var waitingStates: ["unconfirmed", "approval"]
    // How many names the body of a notice for several lists; the rest are counted
    readonly property int namesShown: 6
    // How long a name may be in a title, and in the body's list
    readonly property int titleNameLength: 60
    readonly property int listNameLength: 40

    // The modules that wait, from the host's statuses → [{ id, name, directory, state,
    // reasons }], by id. A module the user turned off is not waiting: it would stay off once
    // confirmed, so it has nothing to tell. Names and ids come from outside: shown plain,
    // capped (noticeText).
    function waiting(statuses) {
        const list = [];
        for (const status of Array.isArray(statuses) ? statuses : []) {
            if (status === null || typeof status !== "object" || !waitingStates.includes(status.state) || status.enabled === false)
                continue;
            const id = typeof status.id === "string" ? status.id : "";
            if (id === "" || list.some(entry => entry.id === id))
                continue;
            list.push({
                id: id,
                name: typeof status.name === "string" && status.name.trim() !== "" ? status.name : id,
                directory: typeof status.directory === "string" ? status.directory : "",
                state: status.state,
                reasons: (Array.isArray(status.confirmation) ? status.confirmation : []).filter(reason => typeof reason === "string").slice().sort()
            });
        }
        return list.sort((first, second) => first.id < second.id ? -1 : first.id > second.id ? 1 : 0);
    }

    // What makes one set of waiting modules another: each module's id, directory, state and
    // reasons (a module waiting for another reason says other words). "" when none waits
    function key(waitingList) {
        const list = Array.isArray(waitingList) ? waitingList : [];
        if (list.length === 0)
            return "";
        return JSON.stringify(list.map(entry => [String(entry?.id ?? ""), String(entry?.directory ?? ""), String(entry?.state ?? ""),
                                                 Array.isArray(entry?.reasons) ? entry.reasons.map(String) : []]));
    }

    // The words for one module, by why it waits
    function _reasonLine(entry) {
        const reasons = Array.isArray(entry?.reasons) ? entry.reasons : [];
        if (entry?.state === "approval") {
            const privileged = reasons.includes("privileged");
            const author = reasons.includes("author");
            const what = privileged && author ? "It now asks for administrator rights and names another author."
                       : privileged ? "It now asks for administrator rights." : "It now names another author.";
            return what + " Approve it to turn it on.";
        }
        return (reasons.includes("source") ? "It now loads from another place." : "It is new and not part of h2s-shell.")
             + " Confirm it to turn it on.";
    }

    // The notification's words → { title, body }; both "" when none waits
    function noticeText(waitingList) {
        const list = Array.isArray(waitingList) ? waitingList : [];
        const nameOf = (entry, most) => {
            const shown = ModuleInstallRules._plain(String(entry?.name ?? ""), most);
            return shown !== "" ? shown : ModuleInstallRules._plain(String(entry?.id ?? ""), most);
        };
        if (list.length === 0)
            return { title: "", body: "" };
        if (list.length === 1)
            return { title: nameOf(list[0], titleNameLength) + " is off", body: _reasonLine(list[0]) };
        const names = list.slice(0, namesShown).map(entry => nameOf(entry, listNameLength));
        const more = list.length - names.length;
        return {
            title: list.length + " modules are off",
            body: names.join(", ") + (more > 0 ? " and " + more + " more" : "") + " wait for your confirmation."
        };
    }

    // The notice's state: the set its notification shows ("" none). The set is remembered, not
    // whether the notification is still on screen: a notification the user dismissed is not
    // raised again until the set changes
    readonly property var quiet: ({ shownKey: "" })

    // A state as remembered (over a reload), made sound: anything else is quiet
    function restore(value) {
        const given = value !== null && typeof value === "object" ? value : {};
        return { shownKey: typeof given.shownKey === "string" ? given.shownKey : "" };
    }

    // One step of the notice, the host now → { state, action }: action "none", "raise" (no
    // notification yet: show one), "replace" (close the one shown, show one for the new set) or
    // "close". `facts`: { key — the waiting set (key()); settled — false while modules are
    // still being found or checked (nothing changes then: a set half-read would raise, close
    // and raise again); active — false without confirmations or in safe mode (nothing is held:
    // a notification shown is closed) }. Only a change of the set raises: the same set again (a
    // reload, a search that found the same, the notification dismissed meanwhile) raises
    // nothing; nothing waiting closes it, so the same set coming back later is told again.
    function step(state, facts) {
        const current = restore(state);
        if (facts?.settled !== true)
            return { state: current, action: "none" };
        const key = facts.active === true && typeof facts.key === "string" ? facts.key : "";
        if (key === current.shownKey)
            return { state: current, action: "none" };
        if (key === "")
            return { state: { shownKey: "" }, action: "close" };
        return { state: { shownKey: key }, action: current.shownKey !== "" ? "replace" : "raise" };
    }

    // The log line for a step's outcome ("" when nothing changed on screen): `count` the
    // modules waiting
    function logLine(action, count) {
        const what = count === 1 ? "1 module waits" : count + " modules wait";
        switch (action) {
        case "raise":
            return "notice raised: " + what + " for confirmation";
        case "replace":
            return "notice replaced: " + what + " for confirmation";
        case "close":
            return "notice closed: no module waits for confirmation";
        default:
            return "";
        }
    }
}
