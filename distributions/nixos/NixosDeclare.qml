import QtQuick
import qs.singletons

// The writer of a setting kept in the shell's file in the NixOS configuration (mode
// "declare"; NixosDeclareRules decides): Apply hands the rebuild the shell's file with that key
// changed, Undo the rebuild's own Undo of its last Apply — both through the Settings window's
// way to the rebuild (`handlers.flow`, NixosRebuildFlow: the announcing modal, then the
// build, Apply now and the password), never by themselves. `done` comes once, when that run
// has settled: applied (ok), or ended otherwise (the modal closed: quiet). What is in force is
// read from the configuration's reading, read anew for it.
QtObject {
    id: root

    property string kind: ""
    // The configuration's reading (NixosConfiguration: read, current, revision) and the
    // rebuild run (NixosRebuild: state, busy); null off NixOS
    property var configuration: null
    property var rebuild: null

    readonly property bool busy: rebuild?.busy === true

    // The run this writer started, waiting for it to settle: { done } or null
    property var _pending: null
    // readInForce's callers waiting for a reading finished after their ask: [{ after, done }]
    property var _readers: []

    function _settledOutcome(state) {
        const phase = state?.phase ?? "idle";
        if (phase === "applied" || phase === "appliedWithErrors")
            return { ok: true, quiet: false, kind: phase, error: String(state.outcome?.error ?? "") };
        if (phase === "idle")
            return { ok: false, quiet: true, kind: "closed", error: "" };
        return { ok: false, quiet: false, kind: phase, error: String(state?.outcome?.error || NixosRebuildRules.texts.notNow) };
    }

    property Connections _watch: Connections {
        target: root.rebuild
        ignoreUnknownSignals: true
        function onStateChanged() {
            const state = root.rebuild?.state;
            if (root._pending === null || !NixosRebuildRules.settled.includes(state?.phase))
                return;
            const pending = root._pending;
            root._pending = null;
            pending.done?.(root._settledOutcome(state));
        }
    }

    property Connections _reads: Connections {
        target: root.configuration
        ignoreUnknownSignals: true
        function onRevisionChanged() {
            const revision = root.configuration?.revision ?? 0;
            const ready = root._readers.filter(reader => revision > reader.after);
            if (ready.length === 0)
                return;
            root._readers = root._readers.filter(reader => revision <= reader.after);
            const reading = root.configuration.current();
            for (const reader of ready)
                reader.done(reading);
        }
    }

    function _start(handlers, call) {
        const flow = handlers?.flow ?? null;
        if (flow === null || typeof flow !== "object")
            return { started: false, refusal: NixosDeclareRules.refusal("noFlow") };
        if (_pending !== null || busy)
            return { started: false, refusal: NixosRebuildRules.refusal("running") };
        // Before the call: the announcement changes the state at once
        _pending = { done: handlers?.done };
        const answer = call(flow);
        if (answer?.taken !== true) {
            _pending = null;
            return { started: false, refusal: answer?.refusal ?? NixosRebuildRules.refusal("notNow") };
        }
        return { started: true, refusal: null };
    }

    // `value` for the kind; `handlers` { flow, done } → { started, refusal }
    function apply(value, handlers) {
        const made = NixosDeclareRules.request(configuration?.current() ?? null, kind, value);
        if (made.refusal !== null)
            return { started: false, refusal: made.refusal };
        return _start(handlers, flow => flow.apply(made.request));
    }

    // The rebuild's Undo of its last Apply; `handlers` { flow, done } → { started, refusal }
    function undo(handlers) {
        return _start(handlers, flow => flow.undo());
    }

    // done(answer) once, after a reading of the configuration finished after this call:
    // NixosDeclareRules.inForce's while connected, else `otherwise(done)` (the system's own
    // reading, as for a setting to copy)
    function readInForce(done, otherwise) {
        if (configuration === null) {
            otherwise(done);
            return;
        }
        _readers = _readers.concat([{ after: configuration.revision ?? 0, done: reading => {
            if (reading?.state === "connected")
                done(NixosDeclareRules.inForce(reading, root.kind));
            else
                otherwise(done);
        } }]);
        configuration.read();
    }
}
