pragma Singleton

import Quickshell
import QtQuick

// What the rebuild of NixOS shows (tests/NixosRebuildViewRulesTest.qml): the announcing and
// the Undo modals, the side panel (panels/settings/NixosRebuildPanel.qml) and the run's line
// on the NixOS page, for a state of NixosRebuildRules and the run's times. Pure.
//
// Each button is offered with what it does: Apply now only while built (the one control that
// starts the root run, so the password prompt follows only that click), Cancel build only
// while a build as the user runs, Apply again after a build that failed or was cancelled,
// Undo while nothing runs and the last Apply can be undone. The Build button carries the
// privileged mark when the configuration can be built only as root.
Singleton {
    id: root

    readonly property var texts: ({
        titleApply: "Applying: rebuilding NixOS",
        titleUndo: "Undo: rebuilding NixOS",
        announceTitle: "Rebuild NixOS",
        announceBody: ["A new NixOS system is built first, as you. No password yet.",
                       "This may take minutes and load the machine. You can cancel while it builds.",
                       "When it is built, your password applies it."],
        announceBodyRoot: ["A new NixOS system is built first. The configuration can be built only with your password.",
                           "This may take minutes and load the machine.",
                           "When it is built, your password applies it."],
        build: "Build",
        undoTitle: "Undo the last Apply",
        undoBody: ["The shell's previous settings are put back and NixOS is rebuilt."],
        undoBuild: "Undo and build",
        stepBuild: "Build, as you",
        stepBuildCaption: "No password. Nothing changes yet.",
        stepBuildRoot: "Build",
        stepBuildRootCaption: "With your password. Nothing changes yet.",
        stepPassword: "Your password",
        stepPasswordCaption: "Writes the shell's file, then switches.",
        stepSwitch: "Switch",
        stepSwitchCaption: "nixos-rebuild switch, as root. Seconds: the build is reused.",
        evaluating: "Evaluating",
        built: "Built",
        waiting: "Waiting for the password",
        switchingPhase: "Switching",
        builtIn: "Built in ",
        builtCaption: "Apply now asks for your password. Cancelling it changes nothing.",
        switching: "Switching. This cannot be cancelled now.",
        closing: "Closing this panel does not stop the build.",
        buildFailed: "The build failed. Nothing changed.",
        buildFailedCaption: "Fix the error, then Apply again.",
        withErrors: "Applied, with errors: some services did not start again.",
        withErrorsCaption: "The new values are in force.",
        cancelled: "Cancelled. Nothing changed.",
        output: "Output",
        nixLines: "nix's last lines",
        pageBuilt: "Built. Waiting for Apply now.",
        pageSwitching: "Switching…"
    })

    readonly property int shownLines: 9

    // A duration in milliseconds as the panel shows it: "41 s", "1 min 12 s"
    function duration(ms) {
        const seconds = Math.max(0, Math.floor((Number(ms) || 0) / 1000));
        return seconds >= 60 ? Math.floor(seconds / 60) + " min " + (seconds % 60) + " s" : seconds + " s";
    }

    // How long the run has taken at `now`, from its `times` { started (the build began),
    // built, applying (the Apply now click), ended } (ms; 0 not yet): the build's time while it
    // builds and once built; the root run's from the Apply now click — never the wait at Built
    // between them — while it goes and once it ended; a run that ended in its build, the build's
    function elapsedMs(state, times, now) {
        const started = Number(times?.started) || 0;
        if (started <= 0)
            return 0;
        const applying = Number(times?.applying) || 0;
        const phase = state?.phase ?? "idle";
        if (phase === "building")
            return Math.max(0, now - started);
        if (phase === "built")
            return Math.max(0, (Number(times?.built) || now) - started);
        if (phase === "authorizing" || phase === "switching")
            return applying > 0 ? Math.max(0, now - applying) : 0;
        const ended = Number(times?.ended) || 0;
        if (ended <= 0)
            return 0;
        return Math.max(0, ended - (applying > 0 ? applying : started));
    }

    // The run's time is counting (the panel's clock ticks only then)
    function counting(state) {
        return ["building", "authorizing", "switching"].includes(state?.phase);
    }

    function _undo(state) {
        return state?.subject?.undo === true;
    }

    // The run's outcome came from the root run (its op), not from the build
    function _rootOutcome(state) {
        return typeof state?.outcome?.op === "string" && state.outcome.op !== "";
    }

    function title(state) {
        return _undo(state) ? texts.titleUndo : texts.titleApply;
    }

    // The announcing modal (or Undo's) for an announced state → SettingsModalHost's spec
    function question(state) {
        const undo = _undo(state);
        const asRoot = state?.asRoot === true;
        return {
            kind: "info",
            title: undo ? texts.undoTitle : texts.announceTitle,
            body: undo ? texts.undoBody : asRoot ? texts.announceBodyRoot : texts.announceBody,
            buttons: [{ id: "build", label: undo ? texts.undoBuild : texts.build, kind: "save", privileged: asRoot }],
            subject: { nixosRebuild: state?.run ?? 0 }
        };
    }

    // The three steps → [{ id, label, caption, mark ("done" | "current" | "todo" | "stopped" |
    // "warning") }]
    function steps(state) {
        const phase = state?.phase ?? "idle";
        const reached = ({ building: 0, built: 1, authorizing: 1, switching: 2, applied: 3, appliedWithErrors: 3 })[phase] ?? 0;
        const live = ["building", "built", "authorizing", "switching"].includes(phase);
        const root = _rootOutcome(state);
        const stoppedAt = phase === "cancelled" ? 0
            : phase === "failed" ? (root ? 2 : 0)
            : phase === "changed" ? 1
            : -1;
        const asRoot = state?.asRoot === true;
        const list = [
            { id: "build", label: asRoot ? texts.stepBuildRoot : texts.stepBuild, caption: asRoot ? texts.stepBuildRootCaption : texts.stepBuildCaption },
            { id: "password", label: texts.stepPassword, caption: texts.stepPasswordCaption },
            { id: "switch", label: texts.stepSwitch, caption: texts.stepSwitchCaption }
        ];
        return list.map((step, order) => Object.assign(step, {
            mark: order === stoppedAt ? "stopped"
                : phase === "appliedWithErrors" && order === 2 ? "warning"
                : stoppedAt >= 0 ? (order < stoppedAt ? "done" : "todo")
                : order < reached ? "done"
                : live && order === reached ? "current"
                : "todo"
        }));
    }

    // Where the run is now, one word or a few: nix's phase while it builds
    function phaseLabel(state, progress) {
        const phase = state?.phase ?? "idle";
        const undo = _undo(state);
        switch (phase) {
        case "building":
            return String(progress?.label ?? "") !== "" ? String(progress.label) : texts.evaluating;
        case "built":
            return texts.built;
        case "authorizing":
            return texts.waiting;
        case "switching":
            return texts.switchingPhase;
        case "applied":
            return undo ? "Undone" : "Applied";
        case "appliedWithErrors":
            return "Applied, with errors";
        case "failed":
            return _rootOutcome(state) ? "The switch failed" : "The build failed";
        case "changed":
            return "Not applied";
        case "cancelled":
            return "Cancelled";
        default:
            return "";
        }
    }

    // A value as the panel names it: plain, on one line, capped
    function _valueText(value) {
        let text = "";
        try {
            text = typeof value === "string" ? value : JSON.stringify(value);
        } catch (error) {
            text = "";
        }
        return String(text ?? "").replace(/\s+/g, " ").slice(0, 80);
    }

    // The outcome box → { shown, tone ("privileged" | "success" | "warning" | "error" |
    // "muted"), text, caption }
    function outcome(state, times) {
        const phase = state?.phase ?? "idle";
        const result = state?.outcome ?? {};
        const undo = _undo(state);
        const took = duration(elapsedMs(state, times, Number(times?.ended) || 0));
        const box = (tone, text, caption) => ({ shown: true, tone, text, caption: caption ?? "" });
        switch (phase) {
        case "built": {
            const captions = [texts.builtCaption];
            if (state.stale === true)
                captions.unshift("Built for " + _valueText(state.subject?.value) + ": the setting changed since.");
            if (String(state.error ?? "") !== "")
                captions.unshift(String(state.error));
            return box("privileged", texts.builtIn + duration(elapsedMs(state, times, Number(times?.built) || 0)) + ".", captions.join(" "));
        }
        case "applied": {
            const generation = Number(result.generation) || 0;
            return box("success", (undo ? "Undone" : "Applied") + " in " + took + "." + (generation > 0 ? " Generation " + generation + " is in use." : ""));
        }
        case "appliedWithErrors":
            return box("warning", texts.withErrors, texts.withErrorsCaption);
        case "failed":
            if (_rootOutcome(state))
                return box("error", String(result.error || NixosRebuildRules.texts.failed));
            return box("error", texts.buildFailed,
                       [String(result.error ?? "") !== NixBuildRules.texts.failed ? String(result.error ?? "") : "", texts.buildFailedCaption]
                       .filter(text => text !== "").join(" "));
        case "changed":
            return box("error", String(result.error || NixosApplyRules.texts.changed));
        case "cancelled":
            return box("muted", texts.cancelled);
        default:
            return { shown: false, tone: "muted", text: "", caption: "" };
        }
    }

    // nix's or the root run's lines, as far as the run got → { caption, lines (all, for Copy
    // all), shown (the last few) }
    function output(state, progressLines, rootLines) {
        const phase = state?.phase ?? "idle";
        const fromRoot = ["authorizing", "switching", "applied", "appliedWithErrors", "changed"].includes(phase) || (phase === "failed" && _rootOutcome(state));
        const fromOutcome = (phase === "failed" && !_rootOutcome(state)) || phase === "cancelled";
        const own = list => Array.isArray(list) ? list.map(line => String(line)) : [];
        let lines = fromRoot ? own(rootLines) : fromOutcome ? own(state?.outcome?.lines) : own(progressLines);
        if (fromRoot && lines.length === 0)
            lines = own(progressLines);
        return { caption: phase === "failed" && !_rootOutcome(state) ? texts.nixLines : texts.output, lines, shown: lines.slice(-shownLines) };
    }

    // The panel's controls → { cancel, applyNow, applyAgain, undo, progress, switching,
    // closing } (each shown or not)
    function controls(state) {
        const phase = state?.phase ?? "idle";
        const settled = NixosRebuildRules.settled.includes(phase);
        return {
            cancel: phase === "building" && state?.asRoot !== true,
            applyNow: phase === "built",
            applyAgain: (phase === "failed" || phase === "cancelled") && state?.subject !== null && state?.subject !== undefined && !_undo(state),
            undo: canUndo(state),
            progress: phase === "building" || phase === "switching",
            switching: phase === "switching",
            closing: phase === "building"
        };
    }

    // Undo of the last Apply is offered: nothing runs and an Apply can be undone
    function canUndo(state) {
        const phase = state?.phase ?? "idle";
        return NixosRebuildRules.settled.includes(phase) && state?.last?.previous !== null && state?.last?.previous !== undefined;
    }

    // The run's line on the NixOS page → { shown, tone, text }
    function pageLine(state, times, now) {
        const phase = state?.phase ?? "idle";
        const undo = _undo(state);
        const result = state?.outcome ?? {};
        const line = (tone, text) => ({ shown: true, tone, text });
        switch (phase) {
        case "building":
            return line("accent", (undo ? "Undoing: building… " : "Building… ") + duration(elapsedMs(state, times, now)));
        case "built":
            return line("privileged", texts.pageBuilt);
        case "authorizing":
            return line("accent", texts.waiting + ".");
        case "switching":
            return line("accent", texts.pageSwitching);
        case "applied": {
            const generation = Number(result.generation) || 0;
            return line("success", (undo ? "Undone." : "Applied.") + (generation > 0 ? " Generation " + generation + "." : ""));
        }
        case "appliedWithErrors":
            return line("warning", texts.withErrors);
        case "failed":
            return line("error", _rootOutcome(state) ? String(result.error || NixosRebuildRules.texts.failed) : texts.buildFailed);
        case "changed":
            return line("error", String(result.error || NixosApplyRules.texts.changed));
        case "cancelled":
            return line("muted", texts.cancelled);
        default:
            return { shown: false, tone: "muted", text: "" };
        }
    }
}
