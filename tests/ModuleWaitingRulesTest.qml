import QtQuick
import qs.singletons

// The notice that modules wait for confirmation (singletons/ModuleWaitingRules.qml): which
// modules wait, what the notification says, and when it is raised, replaced or closed
TestCase {
    suiteName: "ModuleWaitingRules"

    function status(id, state, reasons, extra) {
        return Object.assign({ id: id, name: id.charAt(0).toUpperCase() + id.slice(1), directory: "/m/" + id, state: state,
                               enabled: true, confirmation: reasons ?? [] }, extra ?? {});
    }

    function run() {
        // ---- waiting ----
        const statuses = [status("weather", "loaded"), status("notes", "unconfirmed", ["new"]), status("clock", "approval", ["author", "privileged"]),
                          status("off", "unconfirmed", ["new"], { enabled: false }), status("pending", "pending"), status("dup", "duplicate"),
                          status("notes", "unconfirmed", ["source"], { directory: "/other/notes" })];
        const waiting = ModuleWaitingRules.waiting(statuses);
        assertEqual(waiting.map(entry => entry.id).join(" "), "clock notes", "waiting: unconfirmed and approval, by id; one entry per id");
        assertEqual(JSON.stringify(waiting[0]), JSON.stringify({ id: "clock", name: "Clock", directory: "/m/clock", state: "approval", reasons: ["author", "privileged"] }),
                    "waiting: id, name, directory, state, reasons (sorted)");
        assertEqual(ModuleWaitingRules.waiting([status("off", "unconfirmed", ["new"], { enabled: false })]).length, 0,
                    "waiting: a module the user turned off is not waiting");
        assertEqual(ModuleWaitingRules.waiting([status("a", "approval", ["author"], { enabled: undefined })]).length, 1,
                    "waiting: no enabled flag counts as on");
        assertEqual(ModuleWaitingRules.waiting([status("x", "unconfirmed", ["new"], { name: "  " })])[0].name, "x", "waiting: no name, its id");
        assertEqual(ModuleWaitingRules.waiting(null).length + ModuleWaitingRules.waiting([null, 3, "s", { state: "approval" }]).length, 0,
                    "waiting: garbage is no module");

        // ---- key ----
        assertEqual(ModuleWaitingRules.key([]), "", "key: none waiting, \"\"");
        assertEqual(ModuleWaitingRules.key(null), "", "key: no list, \"\"");
        const key = ModuleWaitingRules.key(waiting);
        assert(key !== "", "key: a set has one");
        assertEqual(ModuleWaitingRules.key(ModuleWaitingRules.waiting(statuses.slice().reverse().filter(each => each.directory !== "/other/notes"))), key,
                    "key: the same set in another order, the same key");
        const keyOf = list => ModuleWaitingRules.key(ModuleWaitingRules.waiting(list));
        assert(keyOf([status("notes", "unconfirmed", ["new"])]) !== keyOf([status("notes", "unconfirmed", ["source"])]), "key: another reason, another set");
        assert(keyOf([status("notes", "unconfirmed", ["new"])]) !== keyOf([status("notes", "unconfirmed", ["new"], { directory: "/x" })]), "key: another directory, another set");
        assert(keyOf([status("notes", "unconfirmed", ["new"])]) !== keyOf([status("notes", "approval", ["new"])]), "key: another state, another set");
        assert(keyOf([status("notes", "unconfirmed", ["new"])]) !== keyOf([status("notes", "unconfirmed", ["new"]), status("clock", "unconfirmed", ["new"])]),
               "key: one more module, another set");
        assertEqual(keyOf([status("notes", "unconfirmed", ["new"])]), keyOf([status("notes", "unconfirmed", ["new"], { name: "Renamed" })]),
                    "key: a name alone does not make another set");

        // ---- noticeText ----
        const one = (state, reasons) => ModuleWaitingRules.noticeText(ModuleWaitingRules.waiting([status("notes", state, reasons)]));
        assertEqual(JSON.stringify(one("unconfirmed", ["source"])),
                    JSON.stringify({ title: "Notes is off", body: "It now loads from another place. Confirm it to turn it on." }), "noticeText: one, another place");
        assertEqual(JSON.stringify(one("unconfirmed", ["new"])),
                    JSON.stringify({ title: "Notes is off", body: "It is new and not part of h2s-shell. Confirm it to turn it on." }), "noticeText: one, new");
        assertEqual(one("approval", ["privileged"]).body, "It now asks for administrator rights. Approve it to turn it on.", "noticeText: one, administrator rights");
        assertEqual(one("approval", ["author"]).body, "It now names another author. Approve it to turn it on.", "noticeText: one, another author");
        assertEqual(one("approval", ["author", "privileged"]).body, "It now asks for administrator rights and names another author. Approve it to turn it on.",
                    "noticeText: one, both");
        assertEqual(JSON.stringify(ModuleWaitingRules.noticeText(waiting)),
                    JSON.stringify({ title: "2 modules are off", body: "Clock, Notes wait for your confirmation." }), "noticeText: several, their names");
        const many = ModuleWaitingRules.waiting(["a", "b", "c", "d", "e", "f", "g", "h"].map(id => status(id, "unconfirmed", ["new"])));
        assertEqual(JSON.stringify(ModuleWaitingRules.noticeText(many)),
                    JSON.stringify({ title: "8 modules are off", body: "A, B, C, D, E, F and 2 more wait for your confirmation." }), "noticeText: many, six named, the rest counted");
        assertEqual(ModuleWaitingRules.noticeText(many.slice(0, 7)).body, "A, B, C, D, E, F and 1 more wait for your confirmation.", "noticeText: one past six, counted");
        assertEqual(ModuleWaitingRules.noticeText(many.slice(0, 6)).body, "A, B, C, D, E, F wait for your confirmation.", "noticeText: six, all named");
        const hostile = ModuleWaitingRules.noticeText(ModuleWaitingRules.waiting([status("evil", "unconfirmed", ["new"], { name: "<b>Bad</b>\nline‮" + "x".repeat(200) })]));
        assert(!hostile.title.includes("\n") && !hostile.title.includes("‮"), "noticeText: a name on one line, no bidi controls");
        assertEqual(hostile.title.length, 60 + " is off".length, "noticeText: a name capped in the title");
        const hostileList = ModuleWaitingRules.noticeText(ModuleWaitingRules.waiting([status("a", "unconfirmed", ["new"], { name: "y".repeat(200) }), status("b", "unconfirmed", ["new"])]));
        assertEqual(hostileList.body, "y".repeat(39) + "…, B wait for your confirmation.", "noticeText: a name capped in the list");
        assertEqual(JSON.stringify(ModuleWaitingRules.noticeText([])), JSON.stringify({ title: "", body: "" }), "noticeText: none, nothing");

        // ---- step ----
        const quiet = ModuleWaitingRules.quiet;
        const facts = (key, extra) => Object.assign({ key: key, settled: true, active: true }, extra ?? {});
        const shown = key => ({ shownKey: key });
        const show = result => result.action + " " + result.state.shownKey;
        const step = (state, given) => show(ModuleWaitingRules.step(state, given));
        assertEqual(step(quiet, facts("A")), "raise A", "step: a set waiting, raised");
        assertEqual(step(quiet, facts("A", { settled: false })), "none ", "step: not settled (modules still being found), nothing");
        assertEqual(step(shown("A"), facts("", { settled: false })), "none A", "step: not settled, a notification shown stays");
        assertEqual(step(shown("A"), facts("B", { settled: false })), "none A", "step: not settled, a half-read set does not replace it");
        assertEqual(step(quiet, facts("A", { active: false })), "none ", "step: no confirmations or safe mode, nothing raised");
        assertEqual(step(shown("A"), facts("A", { active: false })), "close ", "step: safe mode, a notification shown closed");
        assertEqual(step(shown("A"), facts("A")), "none A", "step: the same set (a reload, a dismissal meanwhile), nothing raised again");
        assertEqual(step(shown("A"), facts("B")), "replace B", "step: the set changed, replaced");
        assertEqual(step(shown("A"), facts("")), "close ", "step: none waits, closed");
        assertEqual(step(quiet, facts("")), "none ", "step: none waits, nothing shown, nothing");
        assertEqual(step(ModuleWaitingRules.step(shown("A"), facts("")).state, facts("A")), "raise A", "step: the same set coming back after none waited, told again");
        assertEqual(step(null, facts("A")), "raise A", "step: no state, as quiet");
        assertEqual(step({ shownKey: 3 }, facts("A")), "raise A", "step: a broken state, as quiet");
        assertEqual(step(shown("A"), null), "none A", "step: no facts, nothing");
        assertEqual(step(shown("A"), facts(7)), "close ", "step: a key that is not a string, none waiting");
        assertEqual(JSON.stringify(ModuleWaitingRules.restore({ shownKey: "A", extra: 1 })), JSON.stringify({ shownKey: "A" }), "restore: the key kept");

        // ---- logLine ----
        assertEqual(ModuleWaitingRules.logLine("none", 2), "", "logLine: nothing changed, nothing");
        assertEqual(ModuleWaitingRules.logLine("raise", 1), "notice raised: 1 module waits for confirmation", "logLine: raised, one");
        assertEqual(ModuleWaitingRules.logLine("replace", 3), "notice replaced: 3 modules wait for confirmation", "logLine: replaced, several");
        assert(ModuleWaitingRules.logLine("close", 0).startsWith("notice closed"), "logLine: closed");
    }
}
