import QtQuick
import qs.singletons

// The rebuild of NixOS with the shell's settings, held by the Nixos singleton — outside any
// page or panel, so closing the panel does not stop it; a restart of the shell ends it (the
// build dies with it, nothing is remembered). What happens when is NixosRebuildRules.step's;
// this feeds it the clicks and the answers of the build (`builder`, NixosBuild) and of the
// root step (`writer`, NixosApply), and does what it says: starts the build, cancels it,
// sends the notification when it is built, starts the root run, lets the built system go.
// The notification's action only opens the page and the panel (open()), never the prompt:
// the root run starts only from applyNow(), the Apply now click.
QtObject {
    id: root

    // The notification's action: Settings → NixOS with the panel (the panel listens)
    signal opened()

    property var builder: null
    property var writer: null
    property var notifier: Notifier

    // NixosRebuildRules' state: phase, subject (the candidate), asRoot, stale, outcome, error
    readonly property var state: _state
    readonly property string phase: _state.phase
    readonly property bool busy: NixosRebuildRules.busy(_state)
    // The build's progress (NixBuildRules.progress), while building and after
    readonly property var progress: builder?.progress ?? null
    // The root run's lines as they came (the last maxLines, each capped)
    readonly property var lines: _lines.slice()
    readonly property int maxLines: 200
    readonly property int lineMaxLength: 500
    // When the run started building, was built, was applied (the Apply now click) and ended
    // (ms by `clock`; 0 not yet), for the panel's elapsed times
    readonly property var times: _times
    // A suite's seam: the clock the times are read from
    property var clock: () => Date.now()

    property var _state: NixosRebuildRules.initial()
    property var _lines: []
    property var _times: ({ started: 0, built: 0, applying: 0, ended: 0 })
    property var _notification: null

    // The Apply: the announcing modal for `request` { key, value, text (the shell's file with
    // the change), reading (as the page showed it), previous ({ value, text }: before, for
    // Undo) } → { taken, refusal (null or { code, text }) }
    function announce(request) {
        return _answer(_step({ type: "announce", request }));
    }

    // Undo of the last Apply: its file before, through the same chain; `reading` the
    // configuration as read now (the file holds what that Apply wrote)
    function undo(reading) {
        return _answer(_step({ type: "undo", reading }));
    }

    // The Build click in the modal (it carries the privileged mark when state.asRoot)
    function build() {
        return _answer(_step({ type: "build" }));
    }

    function cancel() {
        return _answer(_step({ type: "cancel" }));
    }

    // The Apply now click, naming the system the panel showed (state.subject.drvPath)
    function applyNow(drvPath) {
        return _answer(_step({ type: "applyNow", drvPath }));
    }

    // The modal or panel closed on an ended run, or the built system is no longer wanted
    function close() {
        return _answer(_step({ type: "close" }));
    }

    // A setting changed, or the shell's file was read anew: a built candidate may be stale
    function settingChanged(key, value) {
        _step({ type: "setting", key, value });
    }

    function fileRead(sha256) {
        _step({ type: "file", sha256 });
    }

    // Opens Settings → NixOS and its panel; nothing else
    function open() {
        Shell.openSettingsAt("nixos", "rebuild");
        opened();
    }

    function _answer(result) {
        return { taken: result.refused === "", refusal: result.refused === "" ? null : NixosRebuildRules.refusal(result.refused) };
    }

    function _step(event) {
        const result = NixosRebuildRules.step(_state, event);
        if (result.state !== _state) {
            _time(_state.phase, result.state.phase);
            _state = result.state;
        }
        for (const action of result.actions)
            _act(action);
        return result;
    }

    function _time(before, after) {
        if (before === after)
            return;
        const now = clock();
        if (after === "building")
            _times = { started: now, built: 0, applying: 0, ended: 0 };
        else if (after === "built" && before === "building")
            _times = Object.assign({}, _times, { built: now });
        else if (after === "authorizing" && before === "built")
            _times = Object.assign({}, _times, { applying: now, ended: 0 });
        else if (NixosRebuildRules.settled.includes(after) && ["building", "authorizing", "switching"].includes(before))
            _times = Object.assign({}, _times, { ended: now });
    }

    function _act(action) {
        switch (action.type) {
        case "build":
            _build(action);
            break;
        case "cancelBuild":
            builder?.cancel();
            break;
        case "notify":
            _notify();
            break;
        case "apply":
            _apply(action);
            break;
        case "release":
            builder?.release(null);
            break;
        }
    }

    function _build(action) {
        const run = action.run;
        const subject = action.subject;
        const answered = outcome => {
            const result = root._step({ type: "built", run, outcome });
            // A system built for a run that is gone (cancelled meanwhile) is not kept
            if (outcome?.ok === true && (result.state.phase !== "built" || result.state.run !== run))
                root.builder?.release(null);
        };
        const started = builder ? builder.build({ reading: subject.reading, candidate: subject.text, asRoot: action.asRoot }, { done: answered })
                                : { started: false, refusal: NixBuildRules.refusal("start") };
        if (started?.started !== true)
            _step({ type: "built", run, outcome: { ok: false, quiet: false, kind: "failed", reason: started?.refusal?.code ?? "start",
                                                   error: started?.refusal?.text ?? NixBuildRules.texts.start, lines: [] } });
    }

    function _notify() {
        if (_notification?.open)
            _notification.close();
        _notification = notifier?.send(NixosRebuildRules.texts.built, {
            format: "plain", handle: true,
            actions: [{ id: "default", label: "Open", onTriggered: () => root.open() }]
        }) ?? null;
    }

    function _apply(action) {
        const run = action.run;
        const subject = action.subject;
        _lines = [];
        const started = writer ? writer.apply({ op: "apply", reading: subject.reading, candidate: { text: subject.text, drvPath: subject.drvPath, outPath: subject.outPath } }, {
            onLine: line => {
                if (root._state.run !== run)
                    return;
                root._lines = root._lines.concat([String(line).slice(0, root.lineMaxLength)]).slice(-root.maxLines);
                root._step({ type: "line", run });
            },
            done: outcome => root._step({ type: "applied", run, outcome })
        }) : { started: false, refusal: NixosApplyRules.refusal("start") };
        if (started?.started !== true)
            _step({ type: "refused", run, refusal: started?.refusal ?? NixosApplyRules.refusal("start") });
    }
}
