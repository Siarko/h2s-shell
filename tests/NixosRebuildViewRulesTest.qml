import QtQuick
import qs.singletons

// NixosRebuildViewRules: the announcing and Undo modals (the Build button marked when the
// configuration can be built only as root), the panel's steps, phase, outcome, output and
// buttons for each phase of NixosRebuildRules, the elapsed time, the page's line. Pure.
TestCase {
    suiteName: "NixosRebuildViewRules"

    function run() {
        const rules = NixosRebuildViewRules;
        const show = value => JSON.stringify(value);
        const subject = more => Object.assign({ key: "sleep.hibernateDelay", value: "3h", text: "{}", reading: {}, previous: null, undo: false,
                                                drvPath: "/nix/store/a.drv", outPath: "/nix/store/a" }, more ?? {});
        const state = (phase, more) => Object.assign(NixosRebuildRules.initial(), { phase, run: 3, subject: subject() }, more ?? {});
        const times = { started: 10000, built: 82000, ended: 91000 };

        // Durations
        assertEqual(["0", "999", "41000", "60000", "72500", "-5"].map(ms => rules.duration(Number(ms))).join("|"), "0 s|0 s|41 s|1 min 0 s|1 min 12 s|0 s",
                    "duration: seconds, minutes and seconds, never negative");
        assertEqual([rules.elapsedMs(state("building"), times, 51000), rules.elapsedMs(state("built"), times, 99999), rules.elapsedMs(state("switching"), times, 95000),
                     rules.elapsedMs(state("applied"), times, 99999), rules.elapsedMs(state("idle"), { started: 0 }, 5), rules.elapsedMs(state("cancelled"), { started: 1, ended: 0 }, 5)].join(" "),
                    "41000 72000 85000 81000 0 0", "elapsedMs: counting while it runs, the build's time while built, the run's once ended");
        assertEqual(["building", "built", "authorizing", "switching", "applied", "idle"].map(phase => rules.counting(state(phase))).join(" "),
                    "true false true true false false", "counting: only while a process runs");

        // The modals
        assertEqual(show(rules.question(state("announced"))), show({
            kind: "info", title: "Rebuild NixOS",
            body: ["A new NixOS system is built first, as you. No password yet.", "This may take minutes and load the machine. You can cancel while it builds.",
                   "When it is built, your password applies it."],
            buttons: [{ id: "build", label: "Build", kind: "save", privileged: false }], subject: { nixosRebuild: 3 }
        }), "question: the announcement, Build without the mark, keyed to the run");
        const rootQuestion = rules.question(state("announced", { asRoot: true }));
        assertEqual(rootQuestion.buttons[0].privileged + " " + rootQuestion.body[0], "true A new NixOS system is built first. The configuration can be built only with your password.",
                    "… a configuration only root can build: Build marked, no 'as you'");
        assertEqual(show(rules.question(state("announced", { subject: subject({ undo: true }) }))), show({
            kind: "info", title: "Undo the last Apply", body: ["The shell's previous settings are put back and NixOS is rebuilt."],
            buttons: [{ id: "build", label: "Undo and build", kind: "save", privileged: false }], subject: { nixosRebuild: 3 }
        }), "… Undo's modal, one sentence");
        assertEqual(rules.title(state("building")) + " | " + rules.title(state("building", { subject: subject({ undo: true }) })),
                    "Applying: rebuilding NixOS | Undo: rebuilding NixOS", "title: Apply's or Undo's");

        // The steps
        const marks = value => rules.steps(value).map(step => step.mark).join(" ");
        assertEqual(["building", "built", "authorizing", "switching", "applied", "appliedWithErrors", "cancelled", "changed"].map(phase => marks(state(phase))).join(" | "),
                    "current todo todo | done current todo | done current todo | done done current | done done done | done done warning | stopped todo todo | done stopped todo",
                    "steps: the step reached, the stopped one");
        assertEqual(marks(state("failed", { outcome: { kind: "failed", reason: "failed", lines: [] } })) + " | "
                    + marks(state("failed", { outcome: { kind: "failed", op: "apply", error: "x" } })), "stopped todo todo | done done stopped",
                    "… a failed build stops the build; a failed switch the switch");
        assertEqual(rules.steps(state("building")).map(step => step.label + ": " + step.caption).join(" / "),
                    "Build, as you: No password. Nothing changes yet. / Your password: Writes the shell's file, then switches. / Switch: nixos-rebuild switch, as root. Seconds: the build is reused.",
                    "… their words");
        assertEqual(rules.steps(state("building", { asRoot: true }))[0].label + ": " + rules.steps(state("building", { asRoot: true }))[0].caption,
                    "Build: With your password. Nothing changes yet.", "… a build as root is not 'as you'");

        // The phase line
        assertEqual([rules.phaseLabel(state("building"), { label: "Building 3 of 7" }), rules.phaseLabel(state("building"), null), rules.phaseLabel(state("built")),
                     rules.phaseLabel(state("authorizing")), rules.phaseLabel(state("switching")), rules.phaseLabel(state("applied", { subject: subject({ undo: true }) }))].join(" | "),
                    "Building 3 of 7 | Evaluating | Built | Waiting for the password | Switching | Undone", "phaseLabel: nix's phase while building");

        // The outcomes
        const box = value => { const answer = rules.outcome(value, times); return answer.shown + " " + answer.tone + " " + answer.text + " / " + answer.caption; };
        assertEqual(box(state("building")), "false muted  / ", "outcome: none while building");
        assertEqual(box(state("built")), "true privileged Built in 1 min 12 s. / Apply now asks for your password. Cancelling it changes nothing.", "… built: Built in …");
        assertEqual(box(state("built", { stale: true, error: "Not possible now." })),
                    "true privileged Built in 1 min 12 s. / Not possible now. Built for 3h: the setting changed since. Apply now asks for your password. Cancelling it changes nothing.",
                    "… a refused root run and a stale candidate said");
        assertEqual(box(state("applied", { outcome: { kind: "applied", generation: 15 } })), "true success Applied in 1 min 21 s. Generation 15 is in use. / ", "… applied");
        assertEqual(box(state("applied", { subject: subject({ undo: true }), outcome: { kind: "applied", generation: 0 } })), "true success Undone in 1 min 21 s. / ",
                    "… undone, the generation not known");
        assertEqual(box(state("appliedWithErrors", { outcome: { kind: "appliedWithErrors" } })),
                    "true warning Applied, with errors: some services did not start again. / The new values are in force.", "… applied with errors");
        assertEqual(box(state("failed", { outcome: { kind: "failed", reason: "failed", error: "The build failed." } })),
                    "true error The build failed. Nothing changed. / Fix the error, then Apply again.", "… the build failed");
        assertEqual(box(state("failed", { outcome: { kind: "failed", reason: "untracked", error: NixBuildRules.texts.untracked } })),
                    "true error The build failed. Nothing changed. / " + NixBuildRules.texts.untracked + " Fix the error, then Apply again.", "… with why");
        assertEqual(box(state("failed", { outcome: { kind: "failed", op: "apply", error: "The switch failed: the system may be partly changed." } })),
                    "true error The switch failed: the system may be partly changed. / ", "… the switch failed");
        assertEqual(box(state("changed", { outcome: { kind: "changed", op: "apply", error: NixosApplyRules.texts.changed } })),
                    "true error Your configuration changed since the build. Nothing changed. Build again. / ", "… changed since the build");
        assertEqual(box(state("cancelled", { outcome: { kind: "cancelled" } })), "true muted Cancelled. Nothing changed. / ", "… cancelled");

        // The output
        const nine = Array.from({ length: 12 }, (unused, index) => "line " + index);
        const out = rules.output(state("building"), nine, ["root"]);
        assertEqual(out.caption + " " + out.lines.length + " " + out.shown.join(","), "Output 12 line 3,line 4,line 5,line 6,line 7,line 8,line 9,line 10,line 11",
                    "output: nix's lines while building, the last nine shown, all for Copy all");
        assertEqual(rules.output(state("switching"), ["nix"], ["root 1"]).lines.join(",") + " | " + rules.output(state("authorizing"), ["nix"], []).lines.join(","),
                    "root 1 | nix", "… the root run's once it goes, nix's until it says anything");
        assertEqual(rules.output(state("failed", { outcome: { kind: "failed", reason: "failed", lines: ["error: x"] } }), ["nix"], ["root"]).caption + " "
                    + rules.output(state("failed", { outcome: { kind: "failed", reason: "failed", lines: ["error: x"] } }), ["nix"], ["root"]).lines.join(","),
                    "nix's last lines error: x", "… a failed build: nix's last lines");

        // The buttons
        const buttons = value => { const answer = rules.controls(value); return ["cancel", "applyNow", "applyAgain", "undo", "progress", "switching", "closing"].filter(key => answer[key]).join(","); };
        const last = { previous: { value: "1h", text: "{}" } };
        assertEqual([buttons(state("building")), buttons(state("building", { asRoot: true })), buttons(state("built")), buttons(state("authorizing")),
                     buttons(state("switching"))].join(" | "),
                    "cancel,progress,closing | progress,closing | applyNow |  | progress,switching", "controls: Cancel only for a build as you, Apply now only while built");
        assertEqual([buttons(state("failed", { outcome: { kind: "failed" } })), buttons(state("cancelled", { last })), buttons(state("applied", { last })),
                     buttons(state("failed", { subject: subject({ undo: true }) })), buttons(state("changed")), buttons(state("building", { last }))].join(" | "),
                    "applyAgain | applyAgain,undo | undo |  |  | cancel,progress,closing", "… Apply again after a failed or cancelled Apply, Undo while nothing runs");
        assertEqual([rules.canUndo(state("idle", { last })), rules.canUndo(state("built", { last })), rules.canUndo(state("idle", { last: { previous: null } }))].join(" "),
                    "true false false", "canUndo: an Apply to undo, nothing running");

        // The page's line
        const line = value => { const answer = rules.pageLine(value, times, 51000); return answer.shown + " " + answer.tone + " " + answer.text; };
        assertEqual([line(state("idle")), line(state("building")), line(state("building", { subject: subject({ undo: true }) })), line(state("built")),
                     line(state("applied", { outcome: { generation: 15 } }))].join(" | "),
                    "false muted  | true accent Building… 41 s | true accent Undoing: building… 41 s | true privileged Built. Waiting for Apply now. | true success Applied. Generation 15.",
                    "pageLine: where the run is");
    }
}
