pragma Singleton

import Quickshell
import QtQuick

// The rebuild of NixOS with the shell's settings (tests/NixosRebuildRulesTest.qml): one run
// at a time, from the Apply that announces it to its outcome, as a pure step(state, event).
// It is the only place that may lead to a password prompt for a rebuild, and it leads there
// only from a click: the Build click (a configuration only root can build: the button
// carries the privileged mark) and the Apply now click (the root run that switches). Never
// from the end of a build, the notification, a timer or a lock.
//
// Phases: idle → announced (the announcing modal, or Undo's) → building (as the user, or as
// root for a configuration the user cannot build) → built (waiting for Apply now; the
// notification sent) → authorizing (the root run asked: the prompt, or a remembered
// authorization) → switching (the root run going) → applied | appliedWithErrors | failed |
// changed (the configuration changed since the build) | cancelled. A dismissed prompt is
// quiet: a build goes back to idle, Apply now back to built.
//
// The candidate is keyed: { key (the setting), value, text (the shell's file as built),
// reading (the configuration as read at the Apply, its file's sha256 among it), and after the
// build drvPath and outPath }; Apply now acts on it and carries its drvPath, never on what is
// current at the click. A later change of that setting, or of the file, makes it stale (the
// panel says what it was built for). Each process answer carries the run it was started for:
// an answer of an earlier run, or one after a cancel, loses. A screen lock changes nothing:
// a build goes on to built, a root run to its end.
Singleton {
    id: root

    readonly property var phases: ["idle", "announced", "building", "built", "authorizing", "switching", "applied", "appliedWithErrors", "failed",
        "changed", "cancelled"]
    // Where a run has ended (or none started): a new Apply may announce
    readonly property var settled: ["idle", "applied", "appliedWithErrors", "failed", "changed", "cancelled"]

    readonly property var texts: ({
        built: "Built. Apply it in Settings → NixOS.",
        running: "A change to NixOS is already running.",
        request: "The new settings could not be checked.",
        nothingToUndo: "There is no Apply to undo.",
        fileChanged: "h2s-shell.json changed since the last Apply: nothing to undo.",
        notNow: "Not possible now.",
        other: "That is not the system that was built.",
        notCancellable: "A build with your password cannot be stopped.",
        cancelled: "The build was stopped. Nothing changed.",
        failed: "The switch failed: the system may be partly changed."
    })

    function initial() {
        return { phase: "idle", run: 0, subject: null, asRoot: false, needsRootFolder: "", stale: false, outcome: null, error: "", last: null };
    }

    // A run is on its way (announced, building, built and waiting, authorizing, switching):
    // every other NixOS Apply shows busy
    function busy(state) {
        return phases.includes(state?.phase) && !settled.includes(state.phase);
    }

    // The root step may be waiting for its password or running
    function rootRunning(state) {
        return state?.phase === "authorizing" || state?.phase === "switching";
    }

    function _text(code) {
        return typeof code === "string" && Object.prototype.hasOwnProperty.call(texts, code) ? texts[code] : texts.notNow;
    }

    // The keyed candidate of an Apply's request { key, value, text, reading, previous ({ value,
    // text }: the setting and the file before, for Undo; optional) } → the subject, or null
    function subject(request, undo) {
        const reading = request?.reading;
        if (typeof request?.key !== "string" || request.key === "" || typeof request.text !== "string" || !request.text.startsWith("{")
                || reading?.configuration?.found !== true)
            return null;
        const file = reading.file;
        const previous = typeof request.previous?.text === "string" ? { value: request.previous.value, text: request.previous.text } : null;
        return {
            key: request.key, value: request.value, text: request.text, reading,
            sha256: file?.state === "absent" ? "absent" : String(file?.sha256 ?? ""),
            previous, undo: undo === true, drvPath: "", outPath: ""
        };
    }

    // Whether the configuration needs root to be built: known before (NixBuildRules
    // .needsRootBefore), or a build of the same folder failed for lack of rights
    function needsRoot(state, reading) {
        return NixBuildRules.needsRootBefore(reading) || (state.needsRootFolder !== "" && state.needsRootFolder === String(reading?.real ?? ""));
    }

    function _with(state, changes) {
        return Object.assign({}, state, changes);
    }

    function _announced(state, subjectNow) {
        return { state: _with(state, { phase: "announced", subject: subjectNow, asRoot: needsRoot(state, subjectNow.reading), stale: false, outcome: null, error: "" }),
                 actions: [], refused: "" };
    }

    function _ended(state, outcome, more) {
        return { state: _with(state, Object.assign({ phase: outcome.kind, outcome }, more ?? {})), actions: [{ type: "release" }], refused: "" };
    }

    // `event` (each answer of a process carries `run`, the run it was started for):
    //   announce { request }   the Apply: the announcing modal with that candidate
    //   undo { reading }        Undo of the last Apply: its file before as the candidate,
    //                           keyed to the configuration as read now; refused unless the
    //                           file still holds what that Apply wrote
    //   build                   the Build click in the modal (as root where needsRoot says)
    //   built { run, outcome }  the build ended (NixBuildRules.outcome / rootOutcome)
    //   cancel                  Cancel, while a build as the user runs
    //   applyNow { drvPath }    the Apply now click, naming the system it was shown
    //   line { run }            a line of the root run: it is going (past the prompt)
    //   refused { run, refusal } the root run was not started
    //   applied { run, outcome } the root run ended (NixosApplyRules.reply)
    //   setting { key, value }  a setting changed; file { sha256 } the shell's file read anew
    //   close                   the modal or the panel closed on an ended run, or a built
    //                           system no longer wanted
    //   lock, unlock            the screen: nothing changes
    // → { state, actions, refused ("" taken or nothing to do; else the code a click was
    // refused with) }. Actions: build { run, subject, asRoot }, cancelBuild, notify { run },
    // apply { run, subject }, release (the built system is not needed any more). A state not
    // changed is the same object.
    function step(state, event) {
        const current = state ?? initial();
        const stay = { state: current, actions: [], refused: "" };
        const refuse = code => ({ state: current, actions: [], refused: code });
        const phase = current.phase;
        const ownRun = event?.run === current.run;
        switch (event?.type) {
        case "announce": {
            if (!settled.includes(phase))
                return refuse("running");
            const subjectNow = subject(event.request, false);
            return subjectNow === null ? refuse("request") : _announced(current, subjectNow);
        }
        case "undo": {
            if (!settled.includes(phase))
                return refuse("running");
            const last = current.last;
            if (last?.previous === null || last?.previous === undefined)
                return refuse("nothingToUndo");
            // Only while the file still holds what that Apply wrote: a later Apply that failed
            // after writing, an edit by hand or a new Create would otherwise be overwritten
            // unseen. (The backups the root step keeps are root's alone: the user cannot read
            // them to offer them instead.)
            const file = event.reading?.file;
            if (event.reading?.configuration?.found === true && (file?.state !== "present" || file.sha256 !== last.wrote))
                return refuse("fileChanged");
            const subjectNow = subject({ key: last.key, value: last.previous.value, text: last.previous.text, reading: event.reading,
                                         previous: { value: last.value, text: last.text } }, true);
            return subjectNow === null ? refuse("request") : _announced(current, subjectNow);
        }
        case "build": {
            if (phase !== "announced")
                return refuse("notNow");
            const run = current.run + 1;
            return { state: _with(current, { phase: "building", run }), actions: [{ type: "build", run, subject: current.subject, asRoot: current.asRoot }], refused: "" };
        }
        case "built": {
            if (phase !== "building" || !ownRun)
                return stay;
            const outcome = event.outcome;
            if (outcome?.ok === true && typeof outcome.drvPath === "string" && outcome.drvPath !== "" && typeof outcome.outPath === "string" && outcome.outPath !== "")
                return { state: _with(current, { phase: "built", subject: _with(current.subject, { drvPath: outcome.drvPath, outPath: outcome.outPath }), error: "" }),
                         actions: [{ type: "notify", run: current.run }], refused: "" };
            if (outcome?.quiet === true)
                return { state: _with(current, { phase: "idle", subject: null }), actions: [], refused: "" };
            if (outcome?.kind === "cancelled")
                return { state: _with(current, { phase: "cancelled", outcome: { kind: "cancelled", error: texts.cancelled, lines: outcome.lines ?? [] } }), actions: [], refused: "" };
            const reason = String(outcome?.reason ?? "");
            return {
                state: _with(current, {
                    phase: "failed",
                    outcome: { kind: "failed", reason, error: String(outcome?.error || NixBuildRules.texts.failed), lines: outcome?.lines ?? [] },
                    needsRootFolder: reason === "needsRoot" ? String(current.subject?.reading?.real ?? "") : current.needsRootFolder
                }),
                actions: [], refused: ""
            };
        }
        case "cancel":
            if (phase !== "building")
                return refuse("notNow");
            if (current.asRoot)
                return refuse("notCancellable");
            return { state: _with(current, { phase: "cancelled", run: current.run + 1, outcome: { kind: "cancelled", error: texts.cancelled, lines: [] } }),
                     actions: [{ type: "cancelBuild" }], refused: "" };
        case "applyNow": {
            if (phase !== "built")
                return refuse("notNow");
            if (event.drvPath !== current.subject.drvPath)
                return refuse("other");
            const run = current.run + 1;
            return { state: _with(current, { phase: "authorizing", run, error: "" }), actions: [{ type: "apply", run, subject: current.subject }], refused: "" };
        }
        case "line":
            if (phase !== "authorizing" || !ownRun)
                return stay;
            return { state: _with(current, { phase: "switching" }), actions: [], refused: "" };
        case "refused":
            if (!rootRunning(current) || !ownRun)
                return stay;
            return { state: _with(current, { phase: "built", error: String(event.refusal?.text ?? texts.notNow) }), actions: [], refused: "" };
        case "applied": {
            if (!rootRunning(current) || !ownRun)
                return stay;
            const outcome = event.outcome;
            if (outcome?.quiet === true)
                return { state: _with(current, { phase: "built" }), actions: [], refused: "" };
            const kind = ["applied", "appliedWithErrors", "changed"].includes(outcome?.kind) ? outcome.kind : "failed";
            const ended = Object.assign({}, outcome ?? {}, { kind, error: String(outcome?.error || (kind === "failed" ? texts.failed : "")) });
            // The last Apply, with what the shell's file holds after it (the candidate: root wrote
            // it, or the user's file held it, as the root step checked)
            return _ended(current, ended, kind === "applied" || kind === "appliedWithErrors"
                          ? { last: _with(current.subject, { wrote: PamEditRules.sha256(current.subject.text) }) } : {});
        }
        case "setting":
            if (!busy(current) || event.key !== current.subject.key || current.stale)
                return stay;
            return JSON.stringify(event.value) === JSON.stringify(current.subject.value) ? stay : { state: _with(current, { stale: true }), actions: [], refused: "" };
        case "file":
            if (!busy(current) || current.stale || event.sha256 === current.subject.sha256)
                return stay;
            return { state: _with(current, { stale: true }), actions: [], refused: "" };
        case "close":
            if (phase === "idle")
                return stay;
            if (phase === "announced" || settled.includes(phase))
                return { state: _with(current, { phase: "idle", subject: null, outcome: null, error: "", stale: false }), actions: [], refused: "" };
            if (phase === "built")
                return { state: _with(current, { phase: "idle", subject: null, error: "", stale: false }), actions: [{ type: "release" }], refused: "" };
            // A build or a root run goes on: closing the panel does not stop it
            return stay;
        case "lock":
        case "unlock":
            return stay;
        default:
            return stay;
        }
    }

    // A refusal's text
    function refusal(code) {
        return { code, text: _text(code) };
    }
}
