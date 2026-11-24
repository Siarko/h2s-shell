import QtQuick
import qs.singletons

// NixosRebuildRules: every transition of the rebuild and every refusal — announce, Undo,
// Build (as root only where needed: known before, or after a build failed for lack of
// rights), the build's answers (built and the notification, quiet, cancelled, failed), Cancel
// only while a build as the user runs, Apply now the only way to the root run and keyed to
// the system built, the root run's lines and answers, a refusal to start, stale candidates,
// Close, late answers losing, and a lock changing nothing in any phase. Pure.
TestCase {
    suiteName: "NixosRebuildRules"

    function run() {
        const rules = NixosRebuildRules;
        const show = value => JSON.stringify(value);
        const folder = "/etc/nixos";
        const drv = "/nix/store/zyxwvsrqpnmlkjihgfdcba9876543210-nixos-system-test.drv";
        const out = "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-nixos-system-test";
        const sha = "a".repeat(64);
        const reading = more => Object.assign({
            configuration: { found: true, folder, entry: "flake.nix", type: "flake" },
            real: folder, rootWrites: true, host: "laptop", git: "absent", gitAccess: "", gitKnowsFile: "",
            file: { path: folder + "/h2s-shell.json", state: "present", sha256: sha }
        }, more ?? {});
        const request = more => Object.assign({
            key: "idle.hibernateDelay", value: "3h", text: "{\"version\":1,\"idle\":{\"hibernateDelay\":\"3h\"}}", reading: reading(),
            previous: { value: "2h", text: "{\"version\":1,\"idle\":{\"hibernateDelay\":\"2h\"}}" }
        }, more ?? {});
        const builtOutcome = { ok: true, quiet: false, kind: "built", reason: "", error: "", drvPath: drv, outPath: out, lines: ["a line"] };
        const step = (state, event) => rules.step(state, event);
        // Steps a chain of events, each taken; → the last result
        const walk = (events, from) => {
            let result = { state: from ?? rules.initial(), actions: [], refused: "" };
            for (const event of events)
                result = step(result.state, event);
            return result;
        };
        const types = result => result.actions.map(action => action.type).join(",");

        // ---- The start ----
        const idle = rules.initial();
        assertEqual(show(idle), show({ phase: "idle", run: 0, subject: null, asRoot: false, needsRootFolder: "", stale: false, outcome: null, error: "", last: null }),
                    "initial: idle, no run, nothing built, nothing to undo");
        assert(!rules.busy(idle), "… not busy");
        assertEqual(show(rules.phases), show(["idle", "announced", "building", "built", "authorizing", "switching", "applied", "appliedWithErrors", "failed", "changed",
                                               "cancelled"]), "the phases");

        // ---- announce ----
        const announced = step(idle, { type: "announce", request: request() });
        assertEqual(announced.state.phase + " " + types(announced) + " " + announced.refused, "announced  ", "announce: announced, nothing runs yet");
        assertEqual(show([announced.state.subject.key, announced.state.subject.value, announced.state.subject.sha256, announced.state.subject.undo,
                          announced.state.subject.drvPath, announced.state.asRoot]),
                    show(["idle.hibernateDelay", "3h", sha, false, "", false]), "… the candidate keyed: setting, value, the file's sha256 read; as the user");
        assert(rules.busy(announced.state), "… busy: every other NixOS Apply waits");
        assertEqual(step(idle, { type: "announce", request: request({ reading: reading({ file: { state: "absent" } }) }) }).state.subject.sha256, "absent",
                    "announce: a file not there is keyed as absent");
        assertEqual(step(idle, { type: "announce", request: request({ previous: undefined }) }).state.subject.previous, null, "announce: no file before given: none");
        for (const [bad, name] of [[request({ key: "" }), "no key"], [request({ key: 3 }), "a key not text"], [request({ text: 7 }), "no text"],
                                   [request({ text: "[]" }), "text not an object"],
                                   [request({ reading: reading({ configuration: { found: false } }) }), "no configuration"], [null, "no request"]]) {
            const refused = step(idle, { type: "announce", request: bad });
            assert(refused.state === idle && refused.refused === "request" && refused.actions.length === 0, "announce refused: " + name);
        }
        const needsRootBefore = step(idle, { type: "announce", request: request({ reading: reading({ git: "present", gitAccess: "" }) }) });
        assertEqual(needsRootBefore.state.asRoot, true, "announce: a repository neither the user's nor root's: the build as root (the mark on Build)");
        assertEqual(step(idle, { type: "announce", request: request({ reading: reading({ git: "present", gitAccess: "user" }) }) }).state.asRoot, false,
                    "… the user's own repository: as the user");

        // ---- build ----
        const building = step(announced.state, { type: "build" });
        assertEqual(building.state.phase + " " + building.state.run + " " + types(building), "building 1 build", "build: building, run 1, the build started");
        assertEqual(show([building.actions[0].run, building.actions[0].asRoot, building.actions[0].subject.key]), show([1, false, "idle.hibernateDelay"]),
                    "… the build's run, as the user, the candidate");
        assertEqual(step(needsRootBefore.state, { type: "build" }).actions[0].asRoot, true, "build: as root only where announce said so (the Build click asks)");
        for (const state of [idle, building.state])
            assertEqual(step(state, { type: "build" }).refused, "notNow", "build refused in " + state.phase);

        // ---- the build's answers ----
        const built = step(building.state, { type: "built", run: 1, outcome: builtOutcome });
        assertEqual(built.state.phase + " " + types(built) + " " + built.actions[0].run, "built notify 1", "built: waiting for Apply now, the notification");
        assertEqual(built.state.subject.drvPath + " " + built.state.subject.outPath, drv + " " + out, "… the candidate keyed to the system built");
        assert(rules.busy(built.state) && !rules.rootRunning(built.state), "… busy, nothing asked as root");
        assertEqual(rules.texts.built, "Built. Apply it in Settings → NixOS.", "the notification's text");
        assert(step(building.state, { type: "built", run: 0, outcome: builtOutcome }).state === building.state, "built: an earlier run's answer loses");
        assert(step(announced.state, { type: "built", run: 0, outcome: builtOutcome }).state === announced.state, "built: no build running: nothing");
        for (const [bad, name] of [[{ ok: true, drvPath: "", outPath: out }, "no drvPath"], [{ ok: true, drvPath: drv, outPath: "" }, "no out path"],
                                   [{ ok: true, drvPath: drv }, "no out path at all"], [{ ok: true, outPath: out }, "no drvPath at all"]]) {
            const result = step(building.state, { type: "built", run: 1, outcome: bad });
            assertEqual(result.state.phase + " " + types(result), "failed ", "built without its paths: failed, no notification (" + name + ")");
        }
        const quiet = step(building.state, { type: "built", run: 1, outcome: { ok: false, quiet: true, kind: "failed", reason: "" } });
        assertEqual(quiet.state.phase + " " + quiet.state.subject + " " + types(quiet) + " " + quiet.state.outcome, "idle null  null",
                    "a build as root, its prompt dismissed: quiet, back to idle, nothing to say");
        const failedBuild = step(building.state, { type: "built", run: 1, outcome: { ok: false, kind: "failed", reason: "untracked", error: "git…", lines: ["x"] } });
        assertEqual(show([failedBuild.state.phase, failedBuild.state.outcome.reason, failedBuild.state.outcome.error, failedBuild.state.outcome.lines, types(failedBuild),
                          failedBuild.state.needsRootFolder]), show(["failed", "untracked", "git…", ["x"], "", ""]),
                    "a failed build: failed, said with its lines, nothing asked");
        assert(!rules.busy(failedBuild.state), "… no longer busy");
        assertEqual(step(building.state, { type: "built", run: 1, outcome: { ok: false, kind: "failed" } }).state.outcome.error, NixBuildRules.texts.failed,
                    "a failed build without a text: the build failed");
        assertEqual(step(building.state, { type: "built", run: 1, outcome: undefined }).state.phase, "failed", "a build with no outcome: failed");
        const denied = step(building.state, { type: "built", run: 1, outcome: { ok: false, kind: "failed", reason: "needsRoot", error: "e" } });
        assertEqual(denied.state.needsRootFolder + " " + types(denied), folder + " ", "a build that needs root: the folder remembered, no prompt by itself");
        const again = walk([{ type: "announce", request: request() }, { type: "build" }], denied.state);
        assertEqual(again.actions[0].asRoot, true, "… the next Build of that folder carries the mark: as root");
        assertEqual(walk([{ type: "announce", request: request({ reading: reading({ real: "/srv/other", configuration: { found: true, folder: "/srv/other" } }) }) }],
                         denied.state).state.asRoot, false, "… another folder: as the user");
        const cancelledAnswer = step(building.state, { type: "built", run: 1, outcome: { ok: false, kind: "cancelled", lines: ["l"] } });
        assertEqual(show([cancelledAnswer.state.phase, cancelledAnswer.state.outcome.error, cancelledAnswer.state.outcome.lines]), show(["cancelled", rules.texts.cancelled, ["l"]]),
                    "a build that ended cancelled: cancelled");

        // ---- cancel ----
        const cancelled = step(building.state, { type: "cancel" });
        assertEqual(show([cancelled.state.phase, cancelled.state.run, types(cancelled), cancelled.state.outcome.error]), show(["cancelled", 2, "cancelBuild", rules.texts.cancelled]),
                    "cancel while building: cancelled, the build stopped, a new run");
        assert(step(cancelled.state, { type: "built", run: 1, outcome: builtOutcome }).state === cancelled.state, "… the build's answer after the cancel loses");
        assert(!rules.busy(cancelled.state), "… not busy");
        const rootBuilding = step(needsRootBefore.state, { type: "build" }).state;
        assertEqual(step(rootBuilding, { type: "cancel" }).refused, "notCancellable", "cancel: a build as root cannot be stopped");
        for (const state of [idle, announced.state, built.state])
            assertEqual(step(state, { type: "cancel" }).refused, "notNow", "cancel only while building, not in " + state.phase);

        // ---- Apply now: the only way to the root run ----
        const authorizing = step(built.state, { type: "applyNow", drvPath: drv });
        assertEqual(show([authorizing.state.phase, authorizing.state.run, types(authorizing), authorizing.actions[0].run, authorizing.actions[0].subject.drvPath]),
                    show(["authorizing", 2, "apply", 2, drv]), "Apply now: authorizing, a new run, the root run of the candidate built");
        assert(rules.rootRunning(authorizing.state), "… the root run asked");
        assertEqual(step(built.state, { type: "applyNow", drvPath: drv.replace("zyx", "abc") }).refused, "other", "Apply now naming another system: refused");
        assertEqual(step(built.state, { type: "applyNow" }).refused, "other", "Apply now naming none: refused");
        for (const state of [idle, announced.state, building.state, authorizing.state, failedBuild.state, cancelled.state])
            assertEqual(step(state, { type: "applyNow", drvPath: drv }).refused, "notNow", "Apply now refused in " + state.phase);
        // No other event leads to the root run: from every phase reached here, every event
        // but applyNow, with any run
        const everyEvent = [
            { type: "announce", request: request() }, { type: "undo", reading: reading() }, { type: "build" }, { type: "built", run: 1, outcome: builtOutcome },
            { type: "built", run: 2, outcome: builtOutcome }, { type: "cancel" }, { type: "line", run: 1 }, { type: "line", run: 2 },
            { type: "refused", run: 2, refusal: { code: "x", text: "y" } }, { type: "applied", run: 2, outcome: { ok: true, kind: "applied" } },
            { type: "setting", key: "idle.hibernateDelay", value: "4h" }, { type: "file", sha256: "b".repeat(64) }, { type: "close" },
            { type: "lock" }, { type: "unlock" }, { type: "notification" }, { type: "timer" }, {}, null
        ];
        const reached = [idle, announced.state, needsRootBefore.state, building.state, rootBuilding, built.state, failedBuild.state, cancelled.state, quiet.state, denied.state];
        for (const state of reached) {
            for (const event of everyEvent) {
                const result = step(state, event);
                assert(!rules.rootRunning(result.state) && !result.actions.some(action => action.type === "apply"),
                       "no root run without Apply now: " + state.phase + " + " + show(event));
                assert(!result.actions.some(action => action.type === "build" && action.asRoot) || (event?.type === "build" && state.asRoot),
                       "a build as root only from the Build click where it is needed: " + state.phase + " + " + show(event));
            }
        }

        // ---- the root run ----
        const switching = step(authorizing.state, { type: "line", run: 2 });
        assertEqual(switching.state.phase + " " + types(switching), "switching ", "a line of the root run: switching");
        assert(step(authorizing.state, { type: "line", run: 1 }).state === authorizing.state, "… a line of an earlier run loses");
        assert(step(switching.state, { type: "line", run: 2 }).state === switching.state, "… more lines: still switching");
        assert(step(built.state, { type: "line", run: 1 }).state === built.state, "… no root run: nothing");
        const refusedStart = step(authorizing.state, { type: "refused", run: 2, refusal: { code: "running", text: "busy text" } });
        assertEqual(refusedStart.state.phase + "|" + refusedStart.state.error + "|" + types(refusedStart), "built|busy text|",
                    "the root run not started: back to built, said");
        assertEqual(step(authorizing.state, { type: "refused", run: 2 }).state.error, rules.texts.notNow, "… without a text: not possible now");
        assert(step(authorizing.state, { type: "refused", run: 1, refusal: {} }).state === authorizing.state, "… an earlier run's refusal loses");
        assert(step(built.state, { type: "refused", run: 1, refusal: {} }).state === built.state, "… none running: nothing");
        assertEqual(step(refusedStart.state, { type: "applyNow", drvPath: drv }).state.error, "", "Apply now again: the error goes");

        const ends = [
            [{ ok: true, kind: "applied", generation: 2, backup: "b", error: "" }, "applied", ""],
            [{ ok: true, kind: "appliedWithErrors", error: "Applied, but some services did not start." }, "appliedWithErrors", "Applied, but some services did not start."],
            [{ ok: false, kind: "changed", error: "Your configuration changed since the build. Nothing changed. Build again." }, "changed",
             "Your configuration changed since the build. Nothing changed. Build again."],
            [{ ok: false, kind: "refused", error: "r" }, "failed", "r"],
            [{ ok: false, kind: "failed", error: "" }, "failed", rules.texts.failed],
            [{ ok: false, kind: "created" }, "failed", rules.texts.failed],
            [undefined, "failed", rules.texts.failed]
        ];
        for (const [outcome, phase, error] of ends) {
            for (const from of [authorizing.state, switching.state]) {
                const result = step(from, { type: "applied", run: 2, outcome });
                assertEqual(show([result.state.phase, result.state.outcome.kind, result.state.outcome.error, types(result)]), show([phase, phase, error, "release"]),
                            "the root run answered " + show(outcome?.kind) + " from " + from.phase + ": " + phase + ", the built system let go");
                assert(!rules.busy(result.state), "… not busy");
            }
        }
        const applied = step(switching.state, { type: "applied", run: 2, outcome: ends[0][0] });
        assertEqual(applied.state.last.key + " " + applied.state.last.value, "idle.hibernateDelay 3h", "applied: the last Apply kept for Undo");
        assertEqual(applied.state.outcome.generation, 2, "… the outcome's fields kept");
        assertEqual(step(switching.state, { type: "applied", run: 2, outcome: ends[1][0] }).state.last.value, "3h", "applied with errors: kept for Undo too");
        for (const index of [2, 3, 4])
            assertEqual(step(switching.state, { type: "applied", run: 2, outcome: ends[index][0] }).state.last, null, "not applied: nothing to undo (" + ends[index][1] + ")");
        const dismissed = step(authorizing.state, { type: "applied", run: 2, outcome: { quiet: true, ok: false, kind: "" } });
        assertEqual(dismissed.state.phase + " " + types(dismissed) + " " + dismissed.state.subject.drvPath, "built  " + drv,
                    "the prompt dismissed: quiet, back to built, the system still held");
        assert(step(authorizing.state, { type: "applied", run: 1, outcome: ends[0][0] }).state === authorizing.state, "the root run's answer of an earlier run loses");
        assert(step(built.state, { type: "applied", run: 1, outcome: ends[0][0] }).state === built.state, "… none running: nothing");

        // ---- Undo ----
        const after = reading({ file: { path: folder + "/h2s-shell.json", state: "present", sha256: "d".repeat(64) } });
        const undone = step(applied.state, { type: "undo", reading: after });
        assertEqual(show([undone.state.phase, undone.state.subject.undo, undone.state.subject.value, undone.state.subject.text, undone.state.subject.previous.value,
                          types(undone)]), show(["announced", true, "2h", request().previous.text, "3h", ""]),
                    "Undo: the last Apply's file before as the candidate, announced (the Undo modal), nothing runs");
        assertEqual(undone.state.subject.sha256, "d".repeat(64), "… keyed to the file as read now");
        assertEqual(step(applied.state, { type: "undo" }).refused, "request", "Undo without a reading: refused");
        assertEqual(step(applied.state, { type: "undo", reading: reading({ configuration: { found: false } }) }).refused, "request", "Undo with no configuration: refused");
        const undoBuilt = walk([{ type: "build" }, { type: "built", run: 3, outcome: builtOutcome }], undone.state);
        assertEqual(undoBuilt.state.phase + " " + types(undoBuilt), "built notify", "… the same chain: build, built and the notification");
        assertEqual(walk([{ type: "applyNow", drvPath: drv }, { type: "applied", run: 4, outcome: ends[0][0] }], undoBuilt.state).state.last.value, "2h",
                    "… applied: the undo is now the last Apply, its own before the value it undid");
        assertEqual(step(idle, { type: "undo", reading: after }).refused, "nothingToUndo", "Undo with no Apply: refused");
        const noPrevious = walk([{ type: "announce", request: request({ previous: null }) }, { type: "build" }, { type: "built", run: 1, outcome: builtOutcome },
                                 { type: "applyNow", drvPath: drv }, { type: "applied", run: 2, outcome: ends[0][0] }]);
        assertEqual(noPrevious.state.phase, "applied", "an Apply without the file before: applied");
        assertEqual(step(noPrevious.state, { type: "undo", reading: after }).refused, "nothingToUndo", "… then nothing to undo");
        assertEqual(step(built.state, { type: "undo", reading: after }).refused, "running", "Undo while a run is on its way: busy");

        // ---- one run at a time ----
        for (const state of [announced.state, building.state, built.state, authorizing.state, switching.state]) {
            const refused = step(state, { type: "announce", request: request() });
            assert(refused.state === state && refused.refused === "running", "announce while " + state.phase + ": refused, busy");
        }
        for (const state of [applied.state, failedBuild.state, cancelled.state, step(switching.state, { type: "applied", run: 2, outcome: ends[2][0] }).state]) {
            const next = step(state, { type: "announce", request: request({ value: "5h" }) });
            assertEqual(show([next.state.phase, next.state.subject.value, next.state.outcome, next.state.stale]), show(["announced", "5h", null, false]),
                        "announce after " + state.phase + ": a new run, the old outcome gone");
        }

        // ---- stale ----
        for (const state of [announced.state, building.state, built.state, authorizing.state]) {
            const stale = step(state, { type: "setting", key: "idle.hibernateDelay", value: "4h" });
            assertEqual(stale.state.stale + " " + stale.state.phase + " " + stale.state.subject.value, "true " + state.phase + " 3h",
                        "the setting changed while " + state.phase + ": stale, still the candidate built for 3h");
            assert(step(stale.state, { type: "setting", key: "idle.hibernateDelay", value: "5h" }).state === stale.state, "… stays stale");
            assert(step(state, { type: "setting", key: "idle.hibernateDelay", value: "3h" }).state === state, "… the same value: not stale");
            assert(step(state, { type: "setting", key: "other", value: "4h" }).state === state, "… another setting: not stale");
            const fileChanged = step(state, { type: "file", sha256: "b".repeat(64) });
            assertEqual(fileChanged.state.stale, true, "the file changed while " + state.phase + ": stale");
            assert(step(fileChanged.state, { type: "file", sha256: "c".repeat(64) }).state === fileChanged.state, "… stays stale");
            assert(step(state, { type: "file", sha256: sha }).state === state, "… the same file: not stale");
        }
        assertEqual(walk([{ type: "setting", key: "idle.hibernateDelay", value: "4h" }, { type: "applyNow", drvPath: drv }], built.state).actions[0].subject.value, "3h",
                    "Apply now on a stale candidate acts on what was built, never on what is current");
        assert(step(idle, { type: "setting", key: "idle.hibernateDelay", value: "4h" }).state === idle, "a setting change with no run: nothing");
        assert(step(applied.state, { type: "file", sha256: "b".repeat(64) }).state === applied.state, "a file change after the run: nothing");
        assert(step(applied.state, { type: "setting", key: "idle.hibernateDelay", value: "4h" }).state === applied.state, "a setting change after the run: nothing");
        assert(step(idle, { type: "file", sha256: "b".repeat(64) }).state === idle, "a file read with no run: nothing");

        // ---- close ----
        assert(step(idle, { type: "close" }).state === idle, "close when idle: nothing");
        for (const state of [announced.state, applied.state, failedBuild.state, cancelled.state]) {
            const closed = step(state, { type: "close" });
            assertEqual(show([closed.state.phase, closed.state.subject, closed.state.outcome, types(closed)]), show(["idle", null, null, ""]), "close in " + state.phase + ": idle");
        }
        assertEqual(step(applied.state, { type: "close" }).state.last.value, "3h", "close keeps the last Apply for Undo");
        assertEqual(step(denied.state, { type: "close" }).state.needsRootFolder, folder, "close keeps what needs root");
        const staleClosed = step(step(announced.state, { type: "setting", key: "idle.hibernateDelay", value: "4h" }).state, { type: "close" });
        assertEqual(staleClosed.state.stale, false, "close of a stale announcement: nothing stale left");
        const discarded = step(step(built.state, { type: "file", sha256: "b".repeat(64) }).state, { type: "close" });
        assertEqual(show([discarded.state.phase, discarded.state.subject, discarded.state.stale, types(discarded)]), show(["idle", null, false, "release"]),
                    "close while built: the built system let go");
        for (const state of [building.state, authorizing.state, switching.state])
            assert(step(state, { type: "close" }).state === state, "close while " + state.phase + ": the run goes on");

        // ---- a lock changes nothing ----
        for (const state of reached.concat([authorizing.state, switching.state, applied.state])) {
            for (const type of ["lock", "unlock"]) {
                const result = step(state, { type });
                assert(result.state === state && result.actions.length === 0 && result.refused === "", type + " in " + state.phase + ": nothing changes");
            }
        }
        const lockedBuild = walk([{ type: "lock" }, { type: "built", run: 1, outcome: builtOutcome }], building.state);
        assertEqual(lockedBuild.state.phase + " " + types(lockedBuild), "built notify", "a lock while building: the build goes on to built");
        assertEqual(step(switching.state, { type: "lock" }).state.phase, "switching", "a lock while switching: the root run goes on");

        // ---- odd input ----
        assertEqual(step(undefined, { type: "announce", request: request() }).state.phase, "announced", "no state: from the start");
        assert(step(idle, { type: "nonsense" }).state === idle && step(idle, undefined).state === idle, "an unknown event: nothing");
        assertEqual(show(rules.refusal("running")), show({ code: "running", text: rules.texts.running }), "refusal: its text");
        assertEqual(rules.refusal("constructor").text, rules.texts.notNow, "refusal: an unknown code: not possible now");
        assert(!rules.busy(null) && !rules.busy({ phase: "elsewhere" }), "busy: no state or an unknown phase is not busy");
    }
}
