pragma Singleton

import Quickshell
import QtQuick

// The lock's rules, their lowest layer (LockRules is the specification and says what each
// event does): the constants every layer reads, and the primitives every change of a state
// goes through. A step's handlers change `transaction.state` only through these, which copy
// what they change: states are replaced, never mutated (the header of LockRules.qml). Pure:
// no clock, no process, no other singleton.
Singleton {
    id: root

    // Defaults, in milliseconds; `initial(settings)` takes overrides in `settings.timings`
    readonly property var timings: ({
        // The compositor confirms a lock within milliseconds. Past this it is reported as
        // not confirmed (a warning, once; the view says it waits) — and nothing else
        // changes: the lock is never set again or given up (THE COMPOSITOR RULE above)
        confirm: 5000,
        // The methods script answers in well under a second; past this the lock goes on
        // with what it knows rather than wait (defect 7: "Verifying…" stuck for good)
        detect: 5000,
        // The prompt hides after this long without activity
        prompt: 10000,
        // A timer can fire a little early (Qt coarse timers: up to 5 %): an expiry within
        // this of the deadline counts as the deadline
        promptSlack: 50,
        // The longest a submitted password may stay "pending"/"verifying" with no answer
        // from PAM. pam_unix answers in a few seconds even with its fail delay, a network
        // backend (sssd, LDAP) in well under a minute; past this the conversation is taken
        // to be hung, aborted, and the field usable again
        verify: 90000,
        // How long the inhibitor is held for the compositor to confirm the lock before the
        // machine is let go to sleep anyway. Just under logind's InhibitDelayMaxSec (5 s):
        // the old 1.5 s let the machine sleep unlocked on a slow compositor (defect 11)
        inhibitorFallback: 4000,
        // After abortPam the child is only killed at the next event-loop pass, and an
        // aborted pam_fprintd may hold the reader a little longer: an aborted method is
        // started again only after this
        settle: 1000,
        // After waking: once this has passed, a lock still without a passive method asks
        // again — the reader's service may not answer in the first moments
        resumeGrace: 4000,
        // `resumed` never came (the monitor died over the sleep): this long after going
        // down, the lock behaves as if it had. Timers are monotonic and stand still while
        // the machine sleeps, so this counts from the wake
        missedResume: 60000,
        // (monotonic, a timer) Activity after this much running time since PrepareForSleep
        // means the machine is up again, the resume signal lost; earlier it is the hand
        // that closed the lid. A timer and not the wall clock: an NTP step forward while
        // going down would otherwise count the lid's hand as a wake
        minSuspend: 5000,
        // A detection that FAILED (not one that answered without a method) is asked again
        // when somebody comes back to the prompt — at most this often
        redetect: 30000,
        // Passive methods' retries after a failed round (retryDelay)
        retryMin: 500,
        retryMax: 10000,
        quickRound: 20000,
        // A passive method's round that ended in PAM's Error (Quickshell maps every code
        // but success / auth error / max tries to it, a device not plugged in included)
        // before `quickRound`: tried again after this. An Error after a full-length round
        // is the module's time-out with nobody trying: `retryMin`, not counted
        errorRetry: 30000
    })

    // Counts, not durations: not overridable
    readonly property var limits: ({
        // Consecutive QUICK Error rounds (shorter than `timings.quickRound`; a longer one is
        // a time-out, not counted, and resets the count) after which a passive method is
        // broken for the lock (and
        // until the next wake from sleep, which clears it). A config that cannot work at all
        // (a module not installed) errs every time: with `revivals` this bounds its PAM
        // children and warnings to errorLimit + revivals rounds per lock and wake — while
        // two and a half minutes of retries cover a device that takes a while to appear
        errorLimit: 5,
        // An EAGER method broken by Errors is given one more round when somebody comes back
        // to the prompt (a security key plugged in when they sit down) — at most this many
        // times per lock and wake; another Error breaks it again at once
        revivals: 3
    })

    // The methods that need nothing typed, run side by side with the password for as long
    // as the screen is locked. `name` is the methods script's; `eager` ones are tried again
    // at once when somebody comes back to the prompt (a security key plugged in just now).
    readonly property var passiveMethods: [
        { name: "fingerprint", label: "Fingerprint", hint: "Touch the fingerprint reader", eager: false },
        { name: "u2f", label: "Security key", hint: "Touch your security key", eager: true }
    ]


    // The key names a `key` event may carry (the driver maps Qt's keys to these; Return and
    // the keypad's Enter are both "Enter"). Anything else is a character and belongs in
    // `text`: an unknown `key` is taken as "" and never logged.
    readonly property var namedKeys: ["Escape", "Enter", "Backspace", "Delete", "Tab",
                                      "Left", "Right", "Up", "Down", "Home", "End"]

    // The timers of the sleep region: they outlive an unlock, every other timer belongs to
    // one lock and is stopped when it ends
    readonly property var sleepTimers: ["inhibitor", "missedResume", "resumeGrace", "minSuspend"]


    // Every timer name a startTimer can carry — the driver needs no other
    readonly property var timerNames: ["confirm", "detect", "prompt", "verify", "settle:password"]
        .concat(sleepTimers)
        .concat(passiveMethods.map(method => "retry:" + method.name))
        .concat(passiveMethods.map(method => "settle:" + method.name))

    // ------------------------------------------------------------------------------------
    // Read from a state
    // ------------------------------------------------------------------------------------

    // What is running: conversations and timers (`lockTimers` without the sleep region's)
    function running(state) {
        const conversations = [];
        if (state.password.conversation !== null)
            conversations.push({ method: "password", conversation: state.password.conversation.id });
        for (const method of passiveMethods) {
            const passive = state.passive[method.name];
            if (passive.conversation !== null)
                conversations.push({ method: method.name, conversation: passive.conversation.id });
        }
        const timers = Object.keys(state.timers);
        return {
            conversations: conversations,
            timers: timers,
            lockTimers: timers.filter(name => !sleepTimers.includes(name))
        };
    }

    // The pause before a passive method's next round after a failure, or null for none.
    // Rounds that end quickly are failed attempts or an absent device, and each doubles the
    // wait up to the maximum; a round that ran its full time was nobody trying, and resets
    // it. MaxTries is the module giving up after its own attempts — somebody is trying and
    // failing — so it waits the longest at once. Success does not retry, and neither does
    // Error here: a quick one waits `errorRetry`, counted against `limits.errorLimit`; one
    // after a full-length round (the module's time-out) waits `retryMin`, not counted
    // (_pamCompleted).
    // `timingOverrides`: the timings to use (a state's `settings.timings`); the defaults
    // when left out.
    function retryDelay(previousDelay, roundMilliseconds, result, timingOverrides) {
        const times = timingOverrides ?? timings;
        if (result === "maxTries")
            return times.retryMax;
        if (result !== "failed")
            return null;
        if (roundMilliseconds >= times.quickRound)
            return times.retryMin;
        const previous = typeof previousDelay === "number" && previousDelay > 0 ? previousDelay : 0;
        return previous === 0 ? times.retryMin : Math.min(Math.max(previous * 2, times.retryMin), times.retryMax);
    }

    // ------------------------------------------------------------------------------------
    // Helpers: every change goes through these, which copy what they change
    // ------------------------------------------------------------------------------------

    function ignored(state, reason) {
        return { state: state, effects: [], ignored: reason };
    }

    function emit(transaction, type, fields) {
        transaction.effects.push(Object.assign({ type: type }, fields));
    }

    function log(transaction, level, message) {
        emit(transaction, "log", { level: level, message: message });
    }

    function setTop(transaction, changes) {
        transaction.state = Object.assign({}, transaction.state, changes);
    }

    function setRegion(transaction, region, changes) {
        const replaced = {};
        replaced[region] = Object.assign({}, transaction.state[region], changes);
        setTop(transaction, replaced);
    }

    function setPassive(transaction, name, changes) {
        const passive = Object.assign({}, transaction.state.passive);
        passive[name] = Object.assign({}, passive[name], changes);
        setTop(transaction, { passive: passive });
    }

    // Conversation ids, timer tokens and detection generations: one counter, never reset
    // within a state's life, so that nothing of an earlier conversation, timer or lock can
    // pass for a current one
    function nextId(transaction) {
        const id = transaction.state.serial + 1;
        setTop(transaction, { serial: id });
        return id;
    }

    // Starts the timer, or restarts it if it runs
    function startTimer(transaction, name, milliseconds) {
        const ms = Math.max(0, Math.round(milliseconds));
        const token = nextId(transaction);
        const timers = Object.assign({}, transaction.state.timers);
        timers[name] = { token: token };
        setTop(transaction, { timers: timers });
        emit(transaction, "startTimer", { name: name, ms: ms, token: token });
    }

    function stopTimer(transaction, name) {
        if (!Object.prototype.hasOwnProperty.call(transaction.state.timers, name))
            return;
        const timers = Object.assign({}, transaction.state.timers);
        delete timers[name];
        setTop(transaction, { timers: timers });
        emit(transaction, "stopTimer", { name: name });
    }

    function anyPassive(state, status) {
        return passiveMethods.some(method => state.passive[method.name].status === status);
    }

    // Surface ids are the driver's: a non-empty string or a finite number, compared strictly
    function isSurfaceId(value) {
        return (typeof value === "string" && value !== "") || (typeof value === "number" && isFinite(value));
    }

    function findSurface(state, id) {
        return state.prompt.surfaces.find(surface => surface.id === id);
    }

    function isConfig(value) {
        return value !== null && typeof value === "object"
            && typeof value.directory === "string" && typeof value.config === "string";
    }

    // A config of our own, never the caller's object
    function copyConfig(value) {
        return isConfig(value) ? { directory: value.directory, config: value.config } : null;
    }

    function sameConfig(a, b) {
        return isConfig(a) && isConfig(b) && a.directory === b.directory && a.config === b.config;
    }

    function where(config) {
        return config ? config.directory + "/" + config.config : "(none)";
    }

    function settingsFrom(settings) {
        const given = settings !== null && typeof settings === "object" ? settings : {};
        const overrides = given.timings !== null && typeof given.timings === "object" ? given.timings : {};
        const times = {};
        for (const name of Object.keys(timings)) {
            const value = overrides[name];
            times[name] = typeof value === "number" && isFinite(value) && value >= 0 ? value : timings[name];
        }
        return {
            lockOnSleep: typeof given.lockOnSleep === "boolean" ? given.lockOnSleep : false,
            passwordFallback: copyConfig(given.passwordFallback),
            timings: times
        };
    }

    // The regions that live for one lock, as each lock starts them
    function freshLockRegions() {
        const passive = {};
        for (const method of passiveMethods) {
            passive[method.name] = {
                status: "unavailable", config: null, conversation: null, startedAt: null,
                delay: 0, lastResult: "", errors: 0, revivals: 0, brokenBy: "", message: "", messageIsError: false,
                settling: false
            };
        }
        return {
            methods: { status: "unknown", generation: null, configs: {}, answered: false, waitForAnswer: false,
                       passwordSource: "none", lastResult: "", askedAt: null },
            password: {
                status: "idle", conversation: null, config: null, question: "", answerVisible: false,
                error: "", pamError: "", refusal: "", settling: false, avoid: null
            },
            passive: passive,
            prompt: { owner: null, awakeUntil: null, surfaces: [], fieldEpoch: 0 },
            secret: null
        };
    }
}
