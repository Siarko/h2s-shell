import QtQuick
import qs.singletons

// One change kind made through the distribution's integration (IntegrationRules): what this
// system can do for it, what is in force, and the user's Apply and Undo of it. One apply or
// undo at a time; what is in force read again after each; a reading's answer taken only
// while no later reading was asked. I/O only: what to offer and what it says is the
// caller's rule.
//
// `integration` is Distribution (which forwards to the system's integration, and answers
// nothing offered while the system is not known), or a suite's integration with stand-ins.
QtObject {
    id: root

    property string kind: ""
    property var integration: Distribution

    // After each apply or undo that was started: "apply" or "undo" and its outcome
    // (EtcFiles': ok, quiet, error, …)
    signal finished(string mode, var outcome)

    // The integration's capability for the kind
    readonly property var capability: integration?.capability(kind) ?? IntegrationRules.unknownCapability()
    // readInForce's answer, null until the first, and while an apply or undo runs (what was
    // read may no longer be so: nothing acts on it)
    readonly property var inForce: _inForce
    // "apply" or "undo" while one runs, else ""
    readonly property string busy: _busy
    // A change made by this object that Undo can put back
    readonly property bool undoable: _last !== null

    property var _inForce: null
    property string _busy: ""
    // The outcome of the last change Undo puts back, or null
    property var _last: null
    property int _reads: 0

    // Read what is in force (once the distribution is known, when the integration says when)
    function read() {
        const ask = () => {
            const number = ++root._reads;
            root.integration.readInForce(root.kind, answer => {
                // An answer after this object is gone (a page closed, its runner torn down)
                if (!root)
                    return;
                if (number === root._reads)
                    root._inForce = answer;
            });
        };
        if (typeof integration?.whenReady === "function")
            integration.whenReady(ask);
        else
            ask();
    }

    // The user's Apply of `value`: `request` { current (readInForce's `file` as the user saw
    // it), replace (the user was told that file is not exactly the shell's), anyway (the user
    // asked to write where the system's configuration makes /etc), flow (the Settings
    // window's way to the rebuild, for a setting kept in the system's configuration) } → the
    // integration's { started, refusal }
    function apply(value, request) {
        if (_busy !== "")
            return { started: false, refusal: EtcFilesRules.refusal("busy") };
        _busy = "apply";
        const handlers = { replace: request?.replace === true, anyway: request?.anyway === true, done: outcome => root?._finish("apply", outcome) };
        if (request?.current !== undefined && request?.current !== null)
            handlers.current = request.current;
        if (request?.flow)
            handlers.flow = request.flow;
        // Before the run: its answer may come at once
        _forget();
        const started = _started(integration.apply(kind, value, handlers));
        if (!started.started) {
            _busy = "";
            read();
        }
        return started;
    }

    // Put back what the last change of this object replaced; `request` { flow } as apply's →
    // as apply
    function undo(request) {
        if (_busy !== "")
            return { started: false, refusal: EtcFilesRules.refusal("busy") };
        if (_last === null)
            return { started: false, refusal: IntegrationRules.refusal("noUndo") };
        _busy = "undo";
        // Before the run: its answer may come at once
        _forget();
        const handlers = { from: _last, done: outcome => root?._finish("undo", outcome) };
        if (request?.flow)
            handlers.flow = request.flow;
        const started = _started(integration.undo(kind, handlers));
        if (!started.started) {
            _busy = "";
            read();
        }
        return started;
    }

    // An answer that is not the contract's counts as not started
    function _started(answer) {
        return answer?.started === true ? answer : { started: false, refusal: answer?.refusal ?? EtcFilesRules.refusal("start") };
    }

    // What was read is dropped, and a reading under way loses
    function _forget() {
        _reads++;
        _inForce = null;
    }

    function _finish(mode, outcome) {
        _busy = "";
        _forget();
        if (outcome?.ok === true)
            _last = mode === "apply" ? outcome : null;
        finished(mode, outcome);
        read();
    }
}
