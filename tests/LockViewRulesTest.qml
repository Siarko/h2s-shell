import QtQuick
import qs.singletons

// What leaves the lock's rules (singletons/LockViewRules.qml): events and effects as they may
// be logged — typed text and the password's PAM messages never — and the view and describe()
// of a state, also through LockRules' forwarders. The states themselves come from
// LockRules.step; LockRulesTest checks what they hold on every path.
TestCase {
    suiteName: "LockViewRules"

    function run() {
        assertEqual(LockViewRules.describeEvent({ type: "submit", surface: "s1", text: "pw" }).text, "<redacted>", "secrets: describeEvent() redacts a submit");
        assertEqual(LockViewRules.describeEvent({ type: "key", surface: "s1", key: "", text: "p" }).text, "<redacted>",
                    "secrets: … and a key's text");
        const named = LockViewRules.describeEvent({ type: "key", surface: "s1", key: "A", text: "a" });
        assert(named.key === "<redacted>" && named.text === "<redacted>", "secrets: … and a key named by its character");
        assertEqual(LockViewRules.describeEvent({ type: "key", surface: "s1", key: "Enter", text: "" }).key, "Enter",
                    "secrets: … but a named key is kept");
        const forward = LockViewRules.describeEffect({ type: "forwardKey", surface: "s1", key: "q", text: "p" });
        assert(forward.text === "<redacted>" && forward.key === "<redacted>", "secrets: … and a forwarded key's");
        assertEqual(LockViewRules.describeEvent({ type: "pamMessage", method: "password", conversation: 1, message: "Password:" }).message,
                    "<not logged>", "secrets: … and what the password's PAM stack says");
        assertEqual(LockViewRules.describeEvent({ type: "pamMessage", method: "fingerprint", conversation: 2, message: "Place your finger" }).message,
                    "Place your finger", "secrets: … but a passive method's message is kept (it is what explains a failure)");

        // The view of a fresh state, and describe() of it, as LockRules forwards them
        const fresh = LockRules.initial({});
        const view = LockViewRules.view(fresh);
        assert(view.locked === false && view.promptSurface === null && view.buttonText === "Unlock" && view.placeholder === "Password",
               "view: a fresh state is unlocked, the prompt asleep, the plain button and placeholder");
        assertEqual(JSON.stringify(view.methods.map(method => method.name + ":" + method.visible)), JSON.stringify(["fingerprint:false", "u2f:false"]),
                    "view: one line per passive method, none shown before a lock");
        assertEqual(JSON.stringify(LockRules.view(fresh)), JSON.stringify(view), "LockRules.view forwards");
        assert(LockRules.view(fresh) !== LockRules.view(fresh) && LockRules.view(fresh).methods !== LockRules.view(fresh).methods,
               "view: a fresh object and a fresh methods array on every call (fed to a ScriptModel)");
        const described = LockViewRules.describe(fresh);
        assert(described.hasSecret === false && Array.isArray(described.timers) && !("serial" in described)
               && JSON.stringify(described.view) === JSON.stringify(view), "describe: no secret, no counter, timers by name, the view along");
        assertEqual(JSON.stringify(LockRules.describe(fresh)), JSON.stringify(described), "LockRules.describe forwards");
        const event = { type: "submit", surface: "s1", text: "pw" };
        assertEqual(JSON.stringify(LockRules.describeEvent(event)), JSON.stringify(LockViewRules.describeEvent(event)), "LockRules.describeEvent forwards");
        // Attended: somebody at the lock screen, so its screen-off waits
        const withState = changes => Object.assign({}, fresh, changes);
        assertEqual(LockViewRules.view(fresh).attended, false, "attended: nobody at a fresh state");
        assertEqual(LockViewRules.view(withState({ prompt: Object.assign({}, fresh.prompt, { owner: 1 }) })).attended, true,
                    "attended: the prompt awake");
        assertEqual(LockViewRules.view(withState({ password: Object.assign({}, fresh.password, { status: "verifying" }) })).attended, true,
                    "attended: a password being checked");
        assertEqual(LockViewRules.view(withState({ password: Object.assign({}, fresh.password, { status: "asking", question: "Code:" }) })).attended,
                    true, "attended: a question asked");
        const passive = (message, isError, status) => withState({ passive: Object.assign({}, fresh.passive, {
            fingerprint: Object.assign({}, fresh.passive.fingerprint, { status: status ?? "running", message: message, messageIsError: isError }) }) });
        assertEqual(LockViewRules.view(passive("Place your finger on the reader", false)).attended, false,
                    "attended: not for a fingerprint's every-round hint");
        assertEqual(LockViewRules.view(passive("Failed to match fingerprint", true)).attended, true,
                    "attended: a finger not recognised: somebody at the reader");
        assertEqual(LockViewRules.view(passive("Failed to match fingerprint", true, "backoff")).attended, false,
                    "attended: not for an error left from a round that ended (the pause before the next)");
        assertEqual(LockViewRules.view(passive("Device error", true, "broken")).attended, false,
                    "attended: not for a broken reader's error, shown for the whole lock");
        const effect = { type: "respondPam", method: "password", conversation: 3, text: "pw" };
        assertEqual(JSON.stringify(LockRules.describeEffect(effect)), JSON.stringify(LockViewRules.describeEffect(effect)), "LockRules.describeEffect forwards");
    }
}
