import QtQuick
import qs.singletons
import qs.singletons.io

// A distribution integration: what the shell asks instead of "which system is this" before a
// change (IntegrationRules: the answers' shapes). Each distribution's (distributions/<id>/)
// is one of these with its table; Distribution forwards to the one the system is.
//
// `table` names each change kind it offers ({ <kind>: { mode, trial, undo, inForce, reason,
// option } }); a kind it does not name is unavailable. A kind it applies is written by
// `files` (EtcFiles; null where nothing is written). Every function answers: apply and undo
// at once with { started, refusal } and, when started, `handlers.done` once later;
// readInForce always later, once.
QtObject {
    id: root

    // The distribution's id (distributions/<id>/)
    property string distribution: ""
    property var table: ({})
    property EtcFiles files: null
    // Per kind, the command readInForce runs in place of IntegrationRules.inForceCommand's (a
    // suite's stand-in)
    property var inForceCommands: ({})

    function capability(kind) {
        return IntegrationRules.capability(table, kind);
    }

    function plan(kind, value) {
        return IntegrationRules.plan(table, kind, value);
    }

    // `handlers` { current (readInForce's `file` as the user saw it: its text decides; left
    // out: read at the run), replace (the user was told the file is not exactly the shell's),
    // done (EtcFiles' outcome → nothing) }
    function apply(kind, value, handlers) {
        const refusal = IntegrationRules.applyRefusal(capability(kind));
        if (refusal !== null)
            return { started: false, refusal };
        const planned = plan(kind, value);
        if (planned.refusal !== null)
            return { started: false, refusal: planned.refusal };
        if (files === null)
            return { started: false, refusal: IntegrationRules.refusal("mode") };
        return files.write(kind, IntegrationRules.textOf(kind, value), handlers);
    }

    // `handlers` { from (the outcome of the change undone; left out: the last one), done }
    function undo(kind, handlers) {
        const refusal = IntegrationRules.undoRefusal(capability(kind));
        if (refusal !== null)
            return { started: false, refusal };
        if (files === null)
            return { started: false, refusal: IntegrationRules.refusal("mode") };
        return files.undo(kind, handlers);
    }

    // done({ state, value, from, elsewhere, file }) once, later: the setting as the system
    // merges it, and the shell's own file where it writes one (IntegrationRules.inForceOf)
    function readInForce(kind, done) {
        const command = Object.prototype.hasOwnProperty.call(inForceCommands, kind) ? inForceCommands[kind] : IntegrationRules.inForceCommand(kind);
        if (!capability(kind).inForce || command === null) {
            Qt.callLater(() => done(IntegrationRules.inForceUnknown()));
            return;
        }
        // Both readings, then one answer
        const reading = { merged: undefined, own: files === null ? null : undefined };
        const answer = () => {
            if (reading.merged !== undefined && reading.own !== undefined)
                done(IntegrationRules.inForceOf(kind, reading.merged, reading.own));
        };
        _runner.start(Array.from(command), {
            timeoutMs: 10000,
            killAfterMs: 1000,
            maxOutputBytes: 1048576,
            done: result => {
                reading.merged = result.ok === true && result.truncated !== true ? String(result.stdout ?? "") : null;
                answer();
            }
        });
        if (files !== null) {
            files.read(kind, own => {
                reading.own = own;
                answer();
            });
        }
    }

    property CommandRunner _runner: CommandRunner {}
}
