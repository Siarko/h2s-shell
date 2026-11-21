pragma Singleton

import Quickshell
import QtQuick

// The lock's rules, what leaves them: what the views render (view), and the state, an event
// or an effect as it may be shown or logged — never the secret, never typed text, nothing
// that times keystrokes (describe*). Pure, on the states LockRules makes.
Singleton {
    id: root

    // What the views render, so that they hold no logic of their own. A fresh object (and
    // `methods` a fresh array) on every call: feed `methods` to a Repeater through a
    // ScriptModel, never directly.
    function view(state) {
        const password = state.password;
        const phase = state.phase;
        const asking = password.status === "asking";
        const unlocking = phase.status === "unlocking";
        const busy = unlocking || password.status === "pending" || password.status === "verifying";
        const owner = state.prompt.surfaces.find(surface => surface.id === state.prompt.owner);
        const unconfirmed = phase.status === "locking" || unlocking;
        return {
            locked: phase.status !== "unlocked",
            // An unlock is decided and waits for the compositor's confirmation of the lock
            unlocking: unlocking,
            // The one surface instance showing the prompt; null while it is asleep. Two
            // instances may share a screen for a moment (one being destroyed): only this
            // one shows it
            promptSurface: state.prompt.owner,
            // Its screen, for information; "" while asleep
            promptScreen: owner ? owner.screen : "",
            busy: busy,
            buttonText: unlocking ? "Unlocking…" : busy ? "Verifying…" : "Unlock",
            placeholder: asking ? password.question : "Password",
            // The field shows what is typed only for a question that allows it
            answerVisible: asking && password.answerVisible,
            error: password.error,
            // A line of information that is no error: the compositor is late
            notice: unconfirmed && phase.confirmLate ? "Waiting for the compositor to confirm the lock" : "",
            // Why the last submit was not taken ("busy", "empty"), "" when it was
            refusal: password.refusal,
            // The field empties whenever this changes: input taken, prompt moved or gone to
            // sleep
            fieldEpoch: state.prompt.fieldEpoch,
            methods: LockStepRules.passiveMethods.map(method => _passiveView(method, state.passive[method.name]))
        };
    }

    // The state as it may be shown: JSON-serialisable, without the secret — and without
    // what changes at every keystroke or pointer move (the prompt's deadline, timer tokens,
    // the id counter): the IPC `state` is readable by any process of the user, and those
    // would time each key typed. The driver exposes only this — the IPC `state`, logs, test
    // output — never the state itself. `timers` is the list of the names running.
    function describe(state) {
        const copy = JSON.parse(JSON.stringify(state, (key, value) =>
            key === "secret" || key === "serial" || key === "awakeUntil" ? undefined : value));
        copy.timers = Object.keys(state.timers).sort();
        copy.hasSecret = state.secret !== null;
        copy.view = view(state);
        return copy;
    }

    // An event or an effect as it may be logged: any `text` replaced, a `key` kept only
    // when it is one of `LockStepRules.namedKeys`
    function describeEvent(event) {
        return _redacted(event);
    }

    function describeEffect(effect) {
        return _redacted(effect);
    }

    // What a passive method shows: waiting for the user, or backing off — never one for
    // the other
    function _passiveView(method, passive) {
        const shown = (text, isError) => ({ name: method.name, visible: true, waiting: passive.status === "running", text: text, isError: isError });
        switch (passive.status) {
        case "running":
            return shown(passive.message || method.hint, passive.messageIsError);
        case "backoff":
            if (passive.lastResult === "maxTries")
                return shown(method.label + ": too many attempts, wait a moment", true);
            if (passive.lastResult === "error")
                return shown(method.label + " not available, trying again later", false);
            // The module's own time-out: restarted in a moment, the line stays as it was
            if (passive.lastResult === "timeout")
                return shown(method.hint, false);
            return shown((passive.messageIsError && passive.message ? passive.message : method.label + " not ready")
                + ", trying again shortly", false);
        case "broken":
            return shown(method.label + " cannot be used", true);
        default:
            return { name: method.name, visible: false, waiting: false, text: "", isError: false };
        }
    }

    // Typed text goes wherever `text` is, in any event or effect; a `key` that is not one of
    // the named keys may be a character
    function _redacted(item) {
        if (item === null || typeof item !== "object")
            return item;
        const copy = Object.assign({}, item);
        if ("text" in copy)
            copy.text = "<redacted>";
        if ("key" in copy && copy.key !== "" && !LockStepRules.namedKeys.includes(copy.key))
            copy.key = "<redacted>";
        // What the password's PAM stack says is not logged either (a prompt, a verdict —
        // nothing typed, but a module may echo what it got): the passive methods' messages
        // ("Place your finger on the reader") are what tells a failure on the real machine
        if (copy.type === "pamMessage" && copy.method === "password" && "message" in copy)
            copy.message = "<not logged>";
        return copy;
    }
}
