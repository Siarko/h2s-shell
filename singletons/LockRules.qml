pragma Singleton

import Quickshell
import QtQuick

// The lock screen's decisions — pure, so tests/LockRulesTest.qml checks every rule without
// a compositor, PAM or logind. This file is the specification of the lock; the driver
// (Lockscreen) owns the one live state, feeds events in and carries the effects out.
// notes/plans/lockscreen.md, section 7, is the contract between the two.
//
//   initial(settings)        → state
//   step(state, event, now)  → { state, effects, ignored }
//
// A state always begins unlocked; a lock carried over a reload of the shell enters by the
// `restored` event, from a fresh state only (_restored).
//
// States are plain objects, replaced and never mutated: a caller may keep an old one and
// compare. `now` is the wall clock (Date.now()) at the moment the event is handled; no
// rule reads a clock, a process or another singleton.
//
// The state is in independent regions, each with a `status`:
//   phase    unlocked / locking / locked / unlocking, and `session`, one more at every lock.
//            "unlocking" is an unlock decided before the compositor confirmed the lock: it
//            is carried out only once the compositor does (FAIL CLOSED, see _endLock)
//   sleep    awake / suspending / resuming, and whether the sleep inhibitor is held
//   methods  unknown / detecting / known: which PAM configs this lock uses
//   password idle / pending / verifying / asking / failed / unavailable
//   passive  one per entry of `passiveMethods`: unavailable / idle / running / backoff /
//            paused / broken
//   prompt   the lock surfaces there are (instances, by the driver's id), the one that owns
//            the prompt (null while it is asleep), and `fieldEpoch` (the field empties
//            whenever it changes)
//   timers   the timers running, by name, each with the token its expiry must carry
//   secret   the typed password while a conversation is being started — see describe()
//
// Every region that belongs to one lock (methods, password, passive, prompt, secret and
// their timers) is created afresh at each lock and thrown away at each unlock. That is the
// cure for "works once": the old code kept one long-lived object and a hand-kept reset
// list, and the second lock never armed.
//
// THE COMPOSITOR RULE. ext-session-lock-v1 makes unlock_and_destroy a protocol error until
// the compositor has sent `locked` (WlSessionLock.secure), and Quickshell sends exactly
// that whenever `locked` is set false on a lock object that is neither confirmed nor
// finished. A strict compositor then kills the client (the session stays locked with no
// way back but a TTY); a lenient one unlocks. So `unlockCompositor` is emitted only for a
// session the compositor has confirmed — never while locking — whatever happens.
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

    // The unlocks by request, not by authentication — the owner's decision (plan, section
    // 5): logind's Unlock signal (`loginctl unlock-session`), the way in from another
    // console. An unlockRequested from any other source is refused.
    readonly property var unlockSources: ["logind"]

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

    // PamContext's results, as the driver names them (PamResult.Success … MaxTries)
    readonly property var pamResults: ["success", "failed", "error", "maxTries"]

    // ------------------------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------------------------

    // `settings`: { lockOnSleep (default false), passwordFallback: { directory, config } —
    // the password config used when detection names none or fails, or when the detected one
    // could not be used (null: none), timings: overrides of `timings` (non-negative numbers;
    // anything else keeps the default) }. Copied: the caller's objects are not kept.
    function initial(settings) {
        return Object.assign({
            serial: 0,
            settings: _settingsFrom(settings),
            phase: { status: "unlocked", session: 0, lastEnd: "", confirmLate: false, pending: null },
            sleep: { status: "awake", inhibitor: "released", minSuspendPassed: false },
            timers: {}
        }, _freshLockRegions());
    }

    // → { state, effects, ignored }. `ignored` is "" when the event was taken, else why not
    // (the state is then the very object passed in, and there are no effects). Never throws:
    // an internal error is reported with `error: true` — as ignored, the state left as it
    // was, except for a PAM completion or refused start of the current conversation, which
    // still ends that conversation (see _internalError).
    function step(state, event, now) {
        if (state === null || typeof state !== "object" || !state.phase)
            return { state: state, effects: [], ignored: "no state" };
        const type = event?.type;
        if (typeof type !== "string" || !Object.prototype.hasOwnProperty.call(_handlers, type))
            return _ignored(state, "unknown event");
        if (typeof now !== "number" || !isFinite(now))
            return _ignored(state, "no time");
        const transaction = { state: state, now: now, effects: [] };
        try {
            const refused = _handlers[type](transaction, event);
            if (typeof refused === "string")
                return _ignored(state, refused);
            _reconcile(transaction);
            return { state: transaction.state, effects: transaction.effects, ignored: "" };
        } catch (error) {
            return _internalError(state, event, now, error);
        }
    }

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
            methods: passiveMethods.map(method => _passiveView(method, state.passive[method.name]))
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
    // when it is one of `namedKeys`
    function describeEvent(event) {
        return _redacted(event);
    }

    function describeEffect(effect) {
        return _redacted(effect);
    }

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

    // ---- Parsers ----

    // The methods script's output (scripts/lock-auth-methods.sh): lines of
    // `<method> TAB <config directory> TAB <config name>`, as an array or one string.
    // → { method: { directory, config } }. Anything else on a line is junk and skipped; the
    // first line for a method wins.
    function parseMethods(lines) {
        const list = typeof lines === "string" ? lines.split("\n") : Array.isArray(lines) ? lines : [];
        const found = {};
        for (const line of list) {
            if (typeof line !== "string")
                continue;
            const fields = line.replace(/\r$/, "").split("\t").map(field => field.trim());
            if (fields.length !== 3)
                continue;
            const [name, directory, config] = fields;
            if (!/^[a-z][a-z0-9_-]*$/.test(name) || !directory.startsWith("/") || !/^[^\s/]+$/.test(config))
                continue;
            if (!Object.prototype.hasOwnProperty.call(found, name))
                found[name] = { directory: directory, config: config };
        }
        return found;
    }

    // One line of `gdbus monitor --system --dest org.freedesktop.login1` → the event it
    // means, or null. Lock and Unlock count only on the shell's own session (`sessionPath`,
    // from parseSessionPath): another session's Unlock must not unlock this one.
    function parseLogind(line, sessionPath) {
        const match = /^(\/\S*): ([\w.]+) \((.*)\)$/.exec(String(line ?? "").trim());
        if (match === null)
            return null;
        const [, path, member, args] = match;
        if (member === "org.freedesktop.login1.Manager.PrepareForSleep" && path === "/org/freedesktop/login1") {
            const value = args.trim().replace(/,$/, "").trim();
            return value === "true" ? { type: "prepareForSleep" } : value === "false" ? { type: "resumed" } : null;
        }
        if (typeof sessionPath !== "string" || sessionPath === "" || path !== sessionPath)
            return null;
        if (member === "org.freedesktop.login1.Session.Lock")
            return { type: "lockRequested", source: "logind" };
        if (member === "org.freedesktop.login1.Session.Unlock")
            return { type: "unlockRequested", source: "logind" };
        return null;
    }

    // `gdbus call … Manager.GetSession` output → the session's object path, "" for an error
    // or nothing (then there is no session to listen to, and that is said once)
    function parseSessionPath(output) {
        const match = /^\(objectpath '(\/org\/freedesktop\/login1\/session\/[A-Za-z0-9_]+)',?\)$/
            .exec(String(output ?? "").trim());
        return match === null ? "" : match[1];
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
    // Events, one handler each. A handler changes `transaction.state` through the helpers below and
    // returns nothing, or a string saying why the event is ignored (its changes are then
    // dropped). `_reconcile` runs after every taken event.
    // ------------------------------------------------------------------------------------

    readonly property var _handlers: ({
        started: (transaction, event) => root._started(transaction, event),
        restored: (transaction, event) => root._restored(transaction, event),
        lockRequested: (transaction, event) => root._lockRequested(transaction, event),
        unlockRequested: (transaction, event) => root._unlockRequested(transaction, event),
        compositorLocked: (transaction, event) => root._compositorLocked(transaction, event),
        compositorFinished: (transaction, event) => root._compositorFinished(transaction, event),
        surfaceAdded: (transaction, event) => root._surfaceAdded(transaction, event),
        surfaceRemoved: (transaction, event) => root._surfaceRemoved(transaction, event),
        activity: (transaction, event) => root._activity(transaction, event),
        press: (transaction, event) => root._press(transaction, event),
        key: (transaction, event) => root._key(transaction, event),
        submit: (transaction, event) => root._submit(transaction, event),
        methodsDetected: (transaction, event) => root._methodsDetected(transaction, event),
        methodsFailed: (transaction, event) => root._methodsFailed(transaction, event),
        pamMessage: (transaction, event) => root._pamMessage(transaction, event),
        pamCompleted: (transaction, event) => root._pamCompleted(transaction, event),
        pamStartFailed: (transaction, event) => root._pamStartFailed(transaction, event),
        prepareForSleep: (transaction, event) => root._prepareForSleep(transaction, event),
        resumed: (transaction, event) => root._resumed(transaction, event),
        timer: (transaction, event) => root._timer(transaction, event),
        settings: (transaction, event) => root._settingsChanged(transaction, event)
    })

    // ---- Phase ----

    // Once, after initial(). It does nothing itself: being a taken event, it runs
    // _reconcile, which takes the sleep inhibitor if the settings want it
    function _started(transaction, event) {
    }

    // The compositor's lock is already held by this process: Quickshell reloaded the shell
    // while it was locked, and the new WlSessionLock took the old one's lock over (the driver
    // set it before Quickshell realized it, plan section 7, "Reload"). So the lock goes on
    // without asking the compositor for one: `adoptCompositorLock` (the session the
    // compositor's later word belongs to), then announceLocked(true), first — no
    // lockCompositor. Everything else of the lock starts afresh, as at any lock: the methods
    // asked, no conversation, no secret, no pending unlock, the prompt asleep; what was
    // typed or under way before the reload is gone, and getting in needs a new
    // authentication.
    //
    // Only from a FRESH state (unlocked, no lock yet in this state's life): it is a way to
    // begin, never a way to change a lock — it can only enter one, never end or replace one.
    // `secure`: the compositor had confirmed that lock (exactly true); anything else is taken
    // as not confirmed (locking, the confirm timer runs), so an unconfirmed lock can never be
    // unlocked on this event's word (THE COMPOSITOR RULE).
    function _restored(transaction, event) {
        if (transaction.state.phase.status !== "unlocked" || transaction.state.phase.session !== 0)
            return transaction.state.phase.status !== "unlocked" ? "already locked" : "not a fresh state";
        const secure = event.secure === true;
        const session = transaction.state.phase.session + 1;
        _setTop(transaction, Object.assign(_freshLockRegions(), {
            phase: { status: secure ? "locked" : "locking", session: session, lastEnd: "", confirmLate: false, pending: null }
        }));
        _emit(transaction, "adoptCompositorLock", { session: session });
        _emit(transaction, "announceLocked", { locked: true });
        _log(transaction, "info", "the compositor's lock carried over (" + (secure ? "confirmed" : "not confirmed yet")
            + "): locked as session " + session + ", a new authentication needed");
        if (!secure)
            _startTimer(transaction, "confirm", transaction.state.settings.timings.confirm);
        _detect(transaction, true);
    }

    // Locking or locked: a lock whose owner may authenticate (conversations run, input is
    // taken). Not "unlocking", where an unlock is decided and only waits for the compositor
    function _authenticating(state) {
        return state.phase.status === "locking" || state.phase.status === "locked";
    }

    function _lockRequested(transaction, event) {
        const source = typeof event.source === "string" ? event.source : "";
        // Asked to lock while an unlock waits for the compositor: the latest word is "stay
        // locked". The pending unlock is dropped, and getting in needs a fresh
        // authentication
        if (transaction.state.phase.status === "unlocking") {
            _cancelPendingUnlock(transaction, "a lock request (" + (source || "request") + ")");
            return;
        }
        // A second Lock (logind, idle, IPC) while locked must not start a second session
        // or restart the conversations under way
        if (transaction.state.phase.status !== "unlocked")
            return "already locked";
        _enterLock(transaction, source);
    }

    function _unlockRequested(transaction, event) {
        const status = transaction.state.phase.status;
        if (status === "unlocked")
            return "not locked";
        if (status === "unlocking")
            return "unlock pending";
        // Defect 5: anything could unlock. Only the sources the owner named do
        if (!unlockSources.includes(event.source))
            return "unlock source not allowed: " + String(event.source);
        _endLock(transaction, event.source, "");
    }

    // The compositor's word counts only for the session in force when the driver set the
    // lock: Quickshell emits secureStateChanged synchronously inside an unlock, and that
    // report must not end the lock that follows it
    function _checkCompositor(state, event) {
        if (state.phase.status === "unlocked")
            return "not locked";
        if (event.session !== state.phase.session)
            return "stale session";
        return "";
    }

    // The compositor confirmed the lock: from now on (and only now) it may be unlocked.
    // An unlock decided meanwhile is carried out at once.
    function _compositorLocked(transaction, event) {
        const refused = _checkCompositor(transaction.state, event);
        if (refused !== "")
            return refused;
        const phase = transaction.state.phase;
        if (phase.status === "locked")
            return "not locking";
        _stopTimer(transaction, "confirm");
        // On the way to sleep the inhibitor was held for exactly this
        if (transaction.state.sleep.status === "suspending" && transaction.state.sleep.inhibitor === "held")
            _releaseInhibitor(transaction);
        if (phase.status === "unlocking") {
            _log(transaction, "info", "the compositor confirmed the lock: carrying out the pending unlock (" + phase.pending.reason + ")");
            _leaveLock(transaction, phase.pending.reason, phase.pending.method, true);
            return;
        }
        _set(transaction, "phase", { status: "locked" });
    }

    // The compositor ended the lock (locked), or refused it (locking, unlocking). Either
    // way the lock is over — and there is nothing to unlock: Quickshell has destroyed the
    // lock object already (a `finished` lock, or a refusal that never made one), and
    // reset WlSessionLock.locked itself.
    function _compositorFinished(transaction, event) {
        const refused = _checkCompositor(transaction.state, event);
        if (refused !== "")
            return refused;
        const phase = transaction.state.phase;
        if (phase.status === "locked") {
            _leaveLock(transaction, "compositor", "", false);
            return;
        }
        _log(transaction, "warning", "the compositor refused the lock"
            + (phase.status === "unlocking" ? " (an unlock by " + phase.pending.reason + " was waiting for it)" : ""));
        _leaveLock(transaction, "denied", "", false);
    }

    // The lock's first effects are always lockCompositor and announceLocked(true), whatever
    // the event did before (a sleep's timers): the lock is what matters most on the way down
    function _enterLock(transaction, source) {
        const session = transaction.state.phase.session + 1;
        const before = transaction.effects;
        transaction.effects = [];
        _setTop(transaction, Object.assign(_freshLockRegions(), {
            phase: { status: "locking", session: session, lastEnd: "", confirmLate: false, pending: null }
        }));
        _emit(transaction, "lockCompositor", { session: session });
        _emit(transaction, "announceLocked", { locked: true });
        transaction.effects = transaction.effects.concat(before);
        _log(transaction, "info", "locking (" + (source || "request") + "), session " + session);
        _startTimer(transaction, "confirm", transaction.state.settings.timings.confirm);
        _detect(transaction, true);
    }

    // No word from the compositor in `timings.confirm`: said once, shown in the view —
    // and nothing else. Setting the lock again or giving it up would both set `locked`
    // false before `locked` (THE COMPOSITOR RULE in the header). The owner can still
    // authenticate meanwhile; an unlock waits for the confirmation (_endLock).
    function _confirmTimedOut(transaction) {
        const phase = transaction.state.phase;
        if (phase.status !== "locking" && phase.status !== "unlocking")
            return;
        _set(transaction, "phase", { confirmLate: true });
        _log(transaction, "warning", "the compositor has not confirmed the lock after " + transaction.state.settings.timings.confirm
            + " ms: still waiting (the password can be checked meanwhile; an unlock waits for the confirmation)");
    }

    // An unlock decided — an accepted authentication or logind's Unlock. Locked: done
    // now. Locking: the compositor has not confirmed the lock, and unlocking it now would
    // be a protocol error (the header) — so everything of the lock is wound down as for an
    // unlock, and the unlock itself waits, as `phase.pending`, for compositorLocked
    // (_compositorLocked); compositorFinished ends it with nothing to unlock.
    function _endLock(transaction, reason, method) {
        if (transaction.state.phase.status === "locked") {
            _leaveLock(transaction, reason, method, true);
            return;
        }
        _windDown(transaction);
        const prompt = transaction.state.prompt;
        _setTop(transaction, Object.assign(_freshLockRegions(), {
            phase: Object.assign({}, transaction.state.phase, { status: "unlocking", pending: { reason: reason, method: method || "" } }),
            // The surfaces are still there; the prompt stays where it is, saying "Unlocking…"
            prompt: { surfaces: prompt.surfaces, owner: prompt.owner, awakeUntil: null, fieldEpoch: prompt.fieldEpoch + 1 }
        }));
        _log(transaction, "info", "unlock (" + reason + (method ? ", " + method : "") + ") decided before the compositor confirmed the lock: "
            + "waiting for its confirmation, session " + transaction.state.phase.session);
    }

    // A lock request (or a sleep) while an unlock waits for the compositor: the lock stays,
    // as fresh as a new one — the methods asked again, and getting in needs a new
    // authentication. The compositor's lock is the same one, still in force: nothing is
    // set again, and nothing announced.
    function _cancelPendingUnlock(transaction, why) {
        const pending = transaction.state.phase.pending;
        const prompt = transaction.state.prompt;
        _setTop(transaction, Object.assign(_freshLockRegions(), {
            phase: Object.assign({}, transaction.state.phase, { status: "locking", pending: null }),
            prompt: { surfaces: prompt.surfaces, owner: null, awakeUntil: null, fieldEpoch: prompt.fieldEpoch + 1 }
        }));
        _log(transaction, "info", "the pending unlock (" + pending.reason + ") is dropped by " + why
            + ": the screen stays locked, a new authentication is needed");
        _detect(transaction, true);
    }

    // Aborts every conversation and stops every timer of the lock — but the confirm timer,
    // which runs for as long as the compositor's word is awaited
    function _windDown(transaction) {
        for (const conversation of running(transaction.state).conversations)
            _emit(transaction, "abortPam", { method: conversation.method, conversation: conversation.conversation });
        for (const name of running(transaction.state).lockTimers) {
            if (name !== "confirm" || transaction.state.phase.status === "locked")
                _stopTimer(transaction, name);
        }
    }

    // Every way out of the lock goes through here: conversations aborted, the lock's
    // timers stopped, the secret dropped, the lock's regions thrown away — so nothing of
    // this lock reaches the next one (defects 6 and the root cause in section 1).
    // `unlock`: the compositor's lock is to be unlocked (it confirmed this session); false
    // when the compositor itself ended or refused it.
    function _leaveLock(transaction, reason, method, unlock) {
        _windDown(transaction);
        _stopTimer(transaction, "confirm");
        // Held for the lock on the way to sleep: there is no lock to wait for any more
        if (transaction.state.sleep.status === "suspending" && transaction.state.sleep.inhibitor === "held")
            _releaseInhibitor(transaction);
        const session = transaction.state.phase.session;
        _setTop(transaction, Object.assign(_freshLockRegions(), {
            phase: { status: "unlocked", session: session, lastEnd: reason, confirmLate: false, pending: null }
        }));
        if (unlock) {
            const fields = { session: session, reason: reason };
            if (method)
                fields.method = method;
            _emit(transaction, "unlockCompositor", fields);
        }
        _emit(transaction, "announceLocked", { locked: false });
        _log(transaction, "info", (unlock ? "unlocked (" : "the lock ended (") + reason + (method ? ", " + method : "") + "), session " + session);
    }

    // ---- Prompt ----

    // Surfaces are instances, by the driver's id, not screens: Quickshell destroys a lock
    // surface with deleteLater() and creates its successor at once, so a screen's new
    // surface can report itself before the old one's removal (an output re-added, unlock
    // and lock in one pass, a reload). Keyed by screen, the old removal took the new
    // surface with it and the only screen stopped taking input. Followed also while an
    // unlock is pending: a cancelled unlock goes on with these surfaces.
    function _surfaceAdded(transaction, event) {
        if (transaction.state.phase.status === "unlocked")
            return "not locked";
        if (!_isSurfaceId(event.surface))
            return "no surface";
        if (typeof event.screen !== "string" || event.screen === "")
            return "no screen";
        if (_findSurface(transaction.state, event.surface) !== undefined)
            return "surface already known";
        _set(transaction, "prompt", { surfaces: transaction.state.prompt.surfaces.concat([{ id: event.surface, screen: event.screen }]) });
    }

    // A surface going away that owned the prompt hands it on, awake, the question (if any)
    // kept — it is in the state, not the view: to the NEWEST other instance on the same
    // screen (its successor; an older one there is one being destroyed), else to the first
    // surface left. With none left the prompt sleeps. The old code left the prompt "active"
    // on a surface that no longer existed: the screen that came back never woke.
    function _surfaceRemoved(transaction, event) {
        if (transaction.state.phase.status === "unlocked")
            return "not locked";
        const removed = _findSurface(transaction.state, event.surface);
        if (removed === undefined)
            return "unknown surface";
        const remaining = transaction.state.prompt.surfaces.filter(surface => surface !== removed);
        _set(transaction, "prompt", { surfaces: remaining });
        if (transaction.state.prompt.owner !== removed.id)
            return;
        if (remaining.length === 0) {
            _sleepPrompt(transaction);
            return;
        }
        const sameScreen = remaining.filter(surface => surface.screen === removed.screen);
        const heir = sameScreen.length > 0 ? sameScreen[sameScreen.length - 1] : remaining[0];
        _set(transaction, "prompt", { owner: heir.id, fieldEpoch: transaction.state.prompt.fieldEpoch + 1 });
    }

    // Pointer motion: wakes the prompt where it happens, or extends its time on the
    // surface that has it
    function _activity(transaction, event) {
        const refused = _checkInput(transaction.state, event.surface);
        if (refused !== "")
            return refused;
        _recoverSleep(transaction);
        _wake(transaction, event.surface);
    }

    // A pointer press: on a surface that does not own the prompt it brings the prompt
    // there — the only way to move it while somebody is active (the owner's decision). The
    // field starts empty there; a question is kept (it is in the state), a verification
    // goes on.
    function _press(transaction, event) {
        const refused = _checkInput(transaction.state, event.surface);
        if (refused !== "")
            return refused;
        _recoverSleep(transaction);
        const owner = transaction.state.prompt.owner;
        if (owner !== null && owner !== event.surface)
            _set(transaction, "prompt", { owner: event.surface, fieldEpoch: transaction.state.prompt.fieldEpoch + 1 });
        _wake(transaction, event.surface);
    }

    // Every key pressed on a lock surface: the field never takes focus, each surface's key
    // catcher sends them all here. It wakes the prompt and is forwarded to the field of the
    // surface that owns it — Enter and Backspace included, so that the key that wakes the
    // prompt and the ones right after are not lost (defect 9). A key on another surface
    // while the prompt is awake is forwarded there rather than moving the prompt: the
    // half-typed text lives in the owner's field (a press moves it).
    function _key(transaction, event) {
        const refused = _checkInput(transaction.state, event.surface);
        if (refused !== "")
            return refused;
        // A character belongs in `text`; a `key` outside the list is dropped, so that it can
        // neither carry typed text into a log nor act as a key the field does not know
        const key = namedKeys.includes(event.key) ? event.key : "";
        // A held Escape would wake a sleeping prompt and hide it again at its first repeat,
        // and so on: its auto-repeats count for nothing
        if (key === "Escape" && event.autoRepeat === true)
            return "repeated Escape";
        _recoverSleep(transaction);
        // Control characters (Enter's "\r", Backspace's "\b", Ctrl+letters) are not text
        const text = typeof event.text === "string" && !/[\u0000-\u001f\u007f]/.test(event.text) ? event.text : "";
        // Escape never unlocks (it did until 2026-11-15: plan, section 5). On a sleeping
        // prompt it wakes it, as any key; at an awake prompt — from any surface — it hides
        // the prompt exactly as its inactivity time-out does: the field empties, a question
        // left unanswered is cancelled, a verification under way goes on. Never forwarded.
        if (key === "Escape") {
            if (transaction.state.prompt.owner !== null)
                _sleepPrompt(transaction);
            else
                _wake(transaction, event.surface);
            return;
        }
        _wake(transaction, event.surface);
        if (key !== "" || text !== "")
            _emit(transaction, "forwardKey", { surface: transaction.state.prompt.owner, key: key, text: text });
    }

    function _checkSurface(state, surface) {
        if (state.phase.status === "unlocked")
            return "not locked";
        // A surface reports itself before any input (surfaceAdded); one not known is one
        // already gone, whose event was still queued
        if (_findSurface(state, surface) === undefined)
            return "unknown surface";
        return "";
    }

    // Input — activity, press, key, submit: only while somebody may authenticate. With an
    // unlock decided and waiting for the compositor, it is ignored
    function _checkInput(state, surface) {
        const refused = _checkSurface(state, surface);
        if (refused !== "")
            return refused;
        return state.phase.status === "unlocking" ? "unlock pending" : "";
    }

    function _wake(transaction, surface) {
        const times = transaction.state.settings.timings;
        if (transaction.state.prompt.owner !== null) {
            // No timer restart on every pointer move: the timer re-arms itself at expiry
            // when the deadline has moved
            _set(transaction, "prompt", { awakeUntil: transaction.now + times.prompt });
            return;
        }
        _set(transaction, "prompt", { owner: surface, awakeUntil: transaction.now + times.prompt });
        _startTimer(transaction, "prompt", times.prompt);
        _nudge(transaction);
    }

    // Somebody came back to the prompt: an eager method backing off after a failure or an
    // Error (a security key not plugged in yet) tries again now rather than after its delay
    // — not one waiting out MaxTries (somebody failing) — and one broken by Errors gets one
    // more round, at most `limits.revivals` times. A lock whose last detection FAILED asks
    // again, at most every `timings.redetect`.
    function _nudge(transaction) {
        if (transaction.state.sleep.status === "suspending")
            return;
        for (const method of passiveMethods) {
            if (!method.eager)
                continue;
            const passive = transaction.state.passive[method.name];
            if (passive.status === "backoff" && passive.lastResult !== "maxTries") {
                _stopTimer(transaction, "retry:" + method.name);
                _setPassive(transaction, method.name, { status: "idle" });
            } else if (passive.status === "broken" && passive.brokenBy === "error" && passive.revivals < limits.revivals) {
                // Another Error breaks it again at once (errors stays at the limit)
                _setPassive(transaction, method.name, { status: "idle", brokenBy: "", revivals: passive.revivals + 1 });
            }
        }
        // The configs known so far serve meanwhile: the eager retry above starts now
        _redetectIfMissing(transaction, true);
    }

    // Asks the methods script again when a passive method is unavailable. `onlyAfterFailure`
    // (somebody came back to the prompt): only when the last detection failed or timed out,
    // and not more often than `timings.redetect` — a clean answer without the method means
    // it is not offered (no reader, no finger enrolled, no key registered), and asking at
    // every wake of the prompt only ran the script for nothing
    function _redetectIfMissing(transaction, onlyAfterFailure) {
        const methods = transaction.state.methods;
        if (methods.status !== "known" || !_anyPassive(transaction.state, "unavailable"))
            return;
        if (onlyAfterFailure) {
            if (methods.lastResult !== "failed")
                return;
            const since = transaction.now - methods.askedAt;
            // A wall clock set back counts as long enough
            if (since >= 0 && since < transaction.state.settings.timings.redetect)
                return;
        }
        _detect(transaction, false);
    }

    // The prompt's inactivity time-out, Escape at an awake prompt (and the last surface
    // gone): the prompt hides, its field empties, a QUESTION left unanswered (a one-time
    // code) is cancelled — but a verification under way is not touched (defect 8: the old
    // 10 s sleep aborted it)
    function _sleepPrompt(transaction) {
        _stopTimer(transaction, "prompt");
        _set(transaction, "prompt", { owner: null, awakeUntil: null, fieldEpoch: transaction.state.prompt.fieldEpoch + 1 });
        const password = transaction.state.password;
        if (password.status === "asking") {
            _abort(transaction, "password");
            _set(transaction, "password", { status: "idle", question: "", answerVisible: false, pamError: "" });
        } else if (password.status === "failed" || password.status === "unavailable") {
            _set(transaction, "password", { status: "idle", error: "", pamError: "" });
        }
        _set(transaction, "password", { refusal: "" });
    }

    // ---- Password ----

    // What was typed and sent: the password, or the answer to the question — from the
    // surface showing the prompt only. The field empties only when the input was taken
    // (fieldEpoch); a refusal says why in `refusal` and leaves the field as it is (defect
    // 10: it emptied either way, which hid the root cause). The verify timer is armed by
    // _reconcile, which keeps it running exactly while the password waits for PAM.
    function _submit(transaction, event) {
        const refused = _checkInput(transaction.state, event.surface);
        if (refused !== "")
            return refused;
        if (transaction.state.prompt.owner !== event.surface)
            return transaction.state.prompt.owner === null ? "prompt asleep" : "not the prompt's surface";
        const text = typeof event.text === "string" ? event.text : "";
        const password = transaction.state.password;
        _set(transaction, "prompt", { awakeUntil: transaction.now + transaction.state.settings.timings.prompt });
        if (password.status === "asking") {
            // At most one answer per prompt: PamContext hands a second respond() to the
            // next prompt. After this the state is "verifying" and a submit is refused.
            _emit(transaction, "respondPam", { method: "password", conversation: password.conversation.id, text: text });
            _set(transaction, "password", { status: "verifying", question: "", answerVisible: false, refusal: "" });
            _takeInput(transaction);
            return;
        }
        if (password.status === "pending" || password.status === "verifying") {
            _set(transaction, "password", { refusal: "busy" });
            return;
        }
        // An empty password is never sent: with `nullok` it could unlock (defect 13), and
        // an Enter forwarded right after waking would otherwise count as a failed attempt
        if (text === "") {
            _set(transaction, "password", { refusal: "empty" });
            return;
        }
        // Held until PAM asks for it — the conversation may not be startable yet (methods
        // unknown, an abort settling); _reconcilePassword starts it
        _setTop(transaction, { secret: text });
        _set(transaction, "password", { status: "pending", error: "", pamError: "", refusal: "" });
        _takeInput(transaction);
        // No password config known: the script is asked again before saying so (a config
        // that appeared since, or a detection that came back empty)
        if (transaction.state.methods.status === "known" && !transaction.state.methods.configs.password)
            _detect(transaction, false);
    }

    function _takeInput(transaction) {
        _set(transaction, "prompt", { fieldEpoch: transaction.state.prompt.fieldEpoch + 1 });
    }

    // The password's conversation is over without success: secret dropped, nothing asked,
    // `status` (failed / unavailable) with `error` shown
    function _passwordEnded(transaction, status, error) {
        _setTop(transaction, { secret: null });
        _set(transaction, "password", { status: status, conversation: null, question: "", answerVisible: false, refusal: "", error: error });
    }

    // A submitted password with no answer from PAM in `timings.verify`: a hung module, a
    // start that never came. Without this the owner could not try again for the rest of
    // the lock (the prompt's sleep deliberately never aborts a verification).
    function _verifyTimedOut(transaction) {
        const status = transaction.state.password.status;
        if (status !== "pending" && status !== "verifying")
            return;
        _log(transaction, "warning", "the password check did not answer in time: aborted");
        _abort(transaction, "password");
        _passwordEnded(transaction, "failed", "Password check timed out");
    }

    // ---- Methods ----

    // Asks which methods there are. A newer request supersedes an older one: its answer
    // carries an older generation and is ignored. `waitForAnswer`: passive methods wait for
    // this answer (at the lock, and after a wake — then the reader's service may have
    // changed); otherwise the configs known so far serve meanwhile.
    function _detect(transaction, waitForAnswer) {
        const generation = _nextId(transaction);
        _set(transaction, "methods", { status: "detecting", generation: generation, waitForAnswer: waitForAnswer, askedAt: transaction.now });
        _emit(transaction, "detectMethods", { generation: generation });
        _startTimer(transaction, "detect", transaction.state.settings.timings.detect);
    }

    function _methodsDetected(transaction, event) {
        const refused = _checkDetection(transaction.state, event);
        if (refused !== "")
            return refused;
        _applyDetection(transaction, parseMethods(event.lines), "answered");
    }

    function _methodsFailed(transaction, event) {
        const refused = _checkDetection(transaction.state, event);
        if (refused !== "")
            return refused;
        _detectionFailed(transaction, typeof event.reason === "string" && event.reason !== "" ? "failed (" + event.reason + ")" : "failed");
    }

    function _checkDetection(state, event) {
        if (state.phase.status === "unlocked")
            return "not locked";
        if (state.methods.status !== "detecting" || event.generation !== state.methods.generation)
            return "stale detection";
        return "";
    }

    // The script's answer replaces the configs. A method running keeps its conversation:
    // PamContext cannot change config while active, the new one serves the next round. A
    // method the answer no longer names stops: aborted if running, unavailable (a broken
    // one stays broken — only a wake clears that). `result`: "answered", or "failed" when
    // this is what a failed detection kept.
    function _applyDetection(transaction, found, result) {
        _stopTimer(transaction, "detect");
        const detectedPassword = _copyConfig(found.password);
        const fallback = transaction.state.settings.passwordFallback;
        const configs = { password: detectedPassword ?? fallback ?? null };
        for (const method of passiveMethods)
            configs[method.name] = _copyConfig(found[method.name]);
        _set(transaction, "methods", {
            status: "known", configs: configs, answered: transaction.state.methods.answered || result === "answered",
            waitForAnswer: false, lastResult: result,
            // Where the password config came from: "detected", "fallback" or "none"
            passwordSource: detectedPassword !== null ? "detected" : fallback ? "fallback" : "none"
        });
        for (const method of passiveMethods) {
            const passive = transaction.state.passive[method.name];
            const config = configs[method.name];
            if (config === null && passive.status === "running") {
                _abort(transaction, method.name);
                _setPassive(transaction, method.name, { status: "unavailable" });
            } else if (config === null && passive.status === "backoff") {
                _stopTimer(transaction, "retry:" + method.name);
                _setPassive(transaction, method.name, { status: "unavailable" });
            }
            _setPassive(transaction, method.name, { config: config });
        }
    }

    // No answer (script failed or timed out): go on with what this lock already knew, and
    // the password fallback where that names no password — a lock must never wait on
    // "verifying" for good (defect 7)
    function _detectionFailed(transaction, reason) {
        const methods = transaction.state.methods;
        const last = {};
        if (methods.answered) {
            for (const method of passiveMethods)
                last[method.name] = methods.configs[method.name];
            // Only a password config the script named is an answer; a fallback is taken afresh
            if (methods.passwordSource === "detected")
                last.password = methods.configs.password;
        }
        _applyDetection(transaction, last, "failed");
        const source = transaction.state.methods.passwordSource;
        _log(transaction, "warning", "detecting the methods " + reason + "; going on with "
            + (methods.answered ? "this lock's last answer" : "nothing detected")
            + ", password config: " + (source === "detected" ? "from that answer" : source === "fallback" ? "the fallback" : "none"));
    }

    // ---- PAM ----

    function _pamMessage(transaction, event) {
        const refused = _checkConversation(transaction.state, event);
        if (refused !== "")
            return refused;
        const message = typeof event.message === "string" ? event.message.trim() : "";
        if (event.method === "password") {
            _passwordMessage(transaction, event, message);
            return;
        }
        if (message !== "")
            _setPassive(transaction, event.method, { message: message, messageIsError: event.messageIsError === true });
        // Nothing is typed for a passive method. A prompt asking for input means a config
        // that is not passive (a password module, pam_u2f's "interactive") — and the old
        // empty answer, repeated every round, was a failed password attempt each time
        // (defect 12): faillock locks the account. So the method stops, broken for this
        // lock, and says so.
        if (event.responseRequired === true) {
            _abort(transaction, event.method);
            _setPassive(transaction, event.method, { status: "broken", brokenBy: "asks", message: "", messageIsError: false });
            _log(transaction, "warning", event.method + " asks for input, which a passive method never gives: not used");
        }
    }

    function _passwordMessage(transaction, event, message) {
        if (event.responseRequired !== true) {
            // PAM knows why it says no (an account locked, a password expired): shown on
            // failure instead of a plain "failed"
            if (event.messageIsError === true && message !== "")
                _set(transaction, "password", { pamError: message });
            return;
        }
        const secret = transaction.state.secret;
        // The typed password answers the first prompt that hides its answer. A prompt that
        // shows it is no password prompt: the password is dropped, not shown, and the
        // question asked.
        if (secret !== null && event.responseVisible !== true) {
            _emit(transaction, "respondPam", { method: "password", conversation: transaction.state.password.conversation.id, text: secret });
            _setTop(transaction, { secret: null });
            return;
        }
        _setTop(transaction, { secret: null });
        _set(transaction, "password", {
            status: "asking",
            question: message.replace(/:$/, "").trim() || "Answer",
            answerVisible: event.responseVisible === true
        });
    }

    function _pamCompleted(transaction, event) {
        const refused = _checkConversation(transaction.state, event);
        if (refused !== "")
            return refused;
        const result = pamResults.includes(event.result) ? event.result : "error";
        const method = event.method;
        if (result === "success") {
            _endLock(transaction, "authenticated", method);
            return;
        }
        if (method === "password") {
            const password = transaction.state.password;
            _log(transaction, "warning", "password not accepted (" + result + "), PAM config " + _where(password.config));
            if (result === "error")
                _passwordConfigFailed(transaction);
            _passwordEnded(transaction, result === "error" ? "unavailable" : "failed",
                result === "error" ? "Password check is not available"
                : password.pamError !== "" ? password.pamError
                : result === "maxTries" ? "Too many attempts" : "Authentication failed");
            return;
        }
        const passive = transaction.state.passive[method];
        if (result === "error") {
            // An Error after a full-length round is the module's own time-out with nobody
            // trying (pam_fprintd: PAM_AUTHINFO_UNAVAIL after its `timeout`, 30 s by
            // default), not a fault: counted, it broke the fingerprint after ~4.5 minutes
            // of an untouched lock. A wall clock set back makes the round look quick
            // (counted: fail towards "broken", which a wake clears)
            if (transaction.now - passive.startedAt >= transaction.state.settings.timings.quickRound)
                _passiveTimedOut(transaction, method);
            else
                _passiveErred(transaction, method);
            return;
        }
        const delay = retryDelay(passive.delay, transaction.now - passive.startedAt, result, transaction.state.settings.timings);
        _setPassive(transaction, method, { status: "backoff", conversation: null, errors: 0, delay: delay, lastResult: result });
        _startTimer(transaction, "retry:" + method, delay);
    }

    // Quickshell's Error is every PAM code but success, auth error and max tries: a module
    // missing (for good) or a device not there yet (for now). A long wait, and broken only
    // after several in a row.
    function _passiveErred(transaction, method) {
        const passive = transaction.state.passive[method];
        const errors = passive.errors + 1;
        if (errors >= limits.errorLimit) {
            _log(transaction, "warning", method + " cannot be used (" + errors + " errors in a row), PAM config " + _where(passive.config));
            _setPassive(transaction, method, { status: "broken", brokenBy: "error", conversation: null, errors: errors, lastResult: "error" });
            return;
        }
        const wait = transaction.state.settings.timings.errorRetry;
        _log(transaction, "warning", method + ": PAM error (" + errors + " of " + limits.errorLimit + "), trying again later");
        _setPassive(transaction, method, { status: "backoff", conversation: null, errors: errors, delay: wait, lastResult: "error" });
        _startTimer(transaction, "retry:" + method, wait);
    }

    // A full-length round that ended in Error: nobody tried, the reader is fine. Not
    // counted, and it resets the count (as any result but a quick Error does); the next
    // round starts after `retryMin` — the shortest wait, as after a full-length failed
    // round. A completion is no abort, so no settle; the round ends by its retry timer,
    // never in this step.
    function _passiveTimedOut(transaction, method) {
        const wait = transaction.state.settings.timings.retryMin;
        _setPassive(transaction, method, { status: "backoff", conversation: null, errors: 0, delay: wait, lastResult: "timeout" });
        _startTimer(transaction, "retry:" + method, wait);
    }

    // The password's config could not be used (start() refused, or PAM's Error): the next
    // attempt takes the other one there is — the fallback after the detected config, the
    // detected one after the fallback (_passwordConfig) — and the methods are asked again.
    // Without this a detected config that cannot work was tried at every submit for the
    // rest of the lock, the fallback never.
    function _passwordConfigFailed(transaction) {
        const config = transaction.state.password.config;
        if (config === null)
            return;
        _set(transaction, "password", { avoid: _copyConfig(config) });
        if (transaction.state.methods.status !== "detecting")
            _detect(transaction, false);
    }

    // PamContext.start() refused (a config that is not there): reported by the driver,
    // since start() says so only through its return value. Visible, never "verifying".
    function _pamStartFailed(transaction, event) {
        const refused = _checkConversation(transaction.state, event);
        if (refused !== "")
            return refused;
        _log(transaction, "warning", event.method + ": PAM refused to start the conversation");
        if (event.method === "password") {
            _passwordConfigFailed(transaction);
            _passwordEnded(transaction, "unavailable", "Password check could not start");
        } else {
            _setPassive(transaction, event.method, { status: "broken", brokenBy: "start", conversation: null });
        }
    }

    // A PAM event counts only for the conversation that is running now, for this method,
    // in this lock. A completion that arrives after an abort, or from a conversation of an
    // earlier lock, is ignored (ids are never reused within a state's life; compared
    // strictly, so neither "7" nor [7] passes for 7).
    function _checkConversation(state, event) {
        if (state.phase.status === "unlocked")
            return "not locked";
        if (state.phase.status === "unlocking")
            return "unlock pending";
        const method = event.method;
        let conversation = null;
        if (method === "password")
            conversation = state.password.conversation;
        else if (passiveMethods.some(passive => passive.name === method))
            conversation = state.passive[method].conversation;
        else
            return "unknown method";
        if (conversation === null)
            return "method not running";
        if (conversation.id !== event.conversation)
            return "stale conversation";
        if (conversation.session !== state.phase.session)
            return "stale session";
        return "";
    }

    // A conversation's end must reach the state even when handling it went wrong: else a
    // method shows "running" for good with nothing running, or the password "verifying".
    // FAIL CLOSED: whatever the event said — a success included — it is not believed. The
    // password shows "Password check failed, try again"; a passive method backs off as
    // after a PAM Error (counted against errorLimit: not broken for the lock by one fault).
    // If even that throws, the minimum with no rule that could throw again: the
    // conversation over, a passive method broken. The error's text is logged without the
    // secret.
    function _internalError(state, event, now, error) {
        const reason = _withoutSecret("internal error: " + String(error), state);
        const ignored = { state: state, effects: [], ignored: reason, error: true };
        try {
            const type = event.type;
            if (type !== "pamCompleted" && type !== "pamStartFailed")
                return ignored;
            if (_checkConversation(state, event) !== "")
                return ignored;
            const method = event.method;
            const what = type + " for " + method + " (" + reason + ")";
            try {
                const transaction = { state: state, now: now, effects: [] };
                if (method === "password")
                    _passwordEnded(transaction, "failed", "Password check failed, try again");
                else
                    _passiveErred(transaction, method);
                _log(transaction, "error", _withoutSecret("internal error on " + what + ": the conversation is ended, its result not believed", state));
                _reconcile(transaction);
                return { state: transaction.state, effects: transaction.effects, ignored: "", error: true };
            } catch (again) {
                const transaction = { state: state, now: now, effects: [] };
                if (method === "password")
                    _passwordEnded(transaction, "failed", "Password check failed, try again");
                else
                    _setPassive(transaction, method, { status: "broken", brokenBy: "internal", conversation: null });
                _log(transaction, "error", _withoutSecret("internal error on " + what + ", and again while ending it: the conversation is ended", state));
                return { state: transaction.state, effects: transaction.effects, ignored: "", error: true };
            }
        } catch (again) {
            return ignored;
        }
    }

    function _withoutSecret(text, state) {
        const secret = state?.secret;
        return typeof secret === "string" && secret !== "" ? text.split(secret).join("<redacted>") : text;
    }

    // ---- Sleep ----

    // PrepareForSleep(true). While still suspending it means the wake was missed (the
    // `resumed` lost) and this is a new sleep: the lock must happen again, not be ignored
    // with the machine going down unlocked. An unlock waiting for the compositor is
    // dropped: the machine goes down locked.
    function _prepareForSleep(transaction, event) {
        const times = transaction.state.settings.timings;
        // First the missed wake (a lock already there is woken: methods asked again), then
        // the new sleep: a lock entered or kept now asks for the methods itself
        if (transaction.state.sleep.status === "suspending") {
            _log(transaction, "warning", "PrepareForSleep while suspending: the resume signal was missed");
            _resume(transaction, false);
        }
        if (transaction.state.phase.status === "unlocking")
            _cancelPendingUnlock(transaction, "going to sleep");
        if (transaction.state.phase.status === "unlocked" && transaction.state.settings.lockOnSleep)
            _enterLock(transaction, "sleep");
        const held = transaction.state.sleep.inhibitor === "held";
        _stopTimer(transaction, "resumeGrace");
        _set(transaction, "sleep", { status: "suspending", minSuspendPassed: false });
        _startTimer(transaction, "missedResume", times.missedResume);
        _startTimer(transaction, "minSuspend", times.minSuspend);
        if (!held)
            return;
        // logind waits while the inhibitor is held: until the compositor confirms the lock,
        // or the fallback lets the machine go
        if (transaction.state.phase.status === "locking")
            _startTimer(transaction, "inhibitor", times.inhibitorFallback);
        else
            _releaseInhibitor(transaction);
        // Passive methods running are aborted and none starts until the wake (reconcile):
        // their devices go away over a suspend, a conversation is dead when it wakes
    }

    function _resumed(transaction, event) {
        _resume(transaction, true);
    }

    // After a wake — signalled, or recovered when the signal was lost: the sleep region,
    // and the lock (_wakeLock). `grace`: false when a new sleep follows in the same step
    // (no grace period to run)
    function _resume(transaction, grace) {
        const times = transaction.state.settings.timings;
        _stopTimer(transaction, "missedResume");
        _stopTimer(transaction, "minSuspend");
        _stopTimer(transaction, "inhibitor");
        _set(transaction, "sleep", { status: "resuming", minSuspendPassed: false });
        if (grace)
            _startTimer(transaction, "resumeGrace", times.resumeGrace);
        if (_authenticating(transaction.state))
            _wakeLock(transaction);
    }

    // … and the lock: what the reader's service said before is not trusted — methods asked
    // again, broken ones given another chance, conversations started afresh once the
    // answer is in. Also when no prepareForSleep was seen: then running conversations may
    // be dead and are restarted.
    function _wakeLock(transaction) {
        for (const method of passiveMethods) {
            const status = transaction.state.passive[method.name].status;
            if (status === "running")
                _abort(transaction, method.name);
            else if (status === "backoff")
                _stopTimer(transaction, "retry:" + method.name);
            if (status === "running" || status === "backoff" || status === "broken")
                _setPassive(transaction, method.name, { status: "idle", brokenBy: "" });
            _setPassive(transaction, method.name, { errors: 0, revivals: 0 });
        }
        _detect(transaction, true);
    }

    // The resume signal was lost: activity after `minSuspend` of running time since going
    // down means the machine is up
    function _recoverSleep(transaction) {
        const sleep = transaction.state.sleep;
        if (sleep.status === "suspending" && sleep.minSuspendPassed) {
            _log(transaction, "warning", "activity while suspending: the resume signal was missed");
            _resume(transaction, true);
        }
    }

    function _releaseInhibitor(transaction) {
        _stopTimer(transaction, "inhibitor");
        if (transaction.state.sleep.inhibitor !== "held")
            return;
        _set(transaction, "sleep", { inhibitor: "released" });
        _emit(transaction, "releaseInhibitor", {});
    }

    // ---- Timers ----

    // A timer's expiry counts only with the token of its latest start: one stopped or
    // restarted meanwhile reports a token no longer there
    function _timer(transaction, event) {
        const name = event.name;
        if (typeof name !== "string" || !Object.prototype.hasOwnProperty.call(transaction.state.timers, name))
            return "timer not running";
        if (transaction.state.timers[name].token !== event.token)
            return "stale timer";
        const timers = Object.assign({}, transaction.state.timers);
        delete timers[name];
        _setTop(transaction, { timers: timers });
        const [kind, method] = name.split(":");
        const handler = _timerHandlers[kind];
        return handler ? handler(transaction, method) : undefined;
    }

    readonly property var _timerHandlers: ({
        confirm: transaction => root._confirmTimedOut(transaction),
        detect: transaction => {
            if (transaction.state.methods.status === "detecting")
                root._detectionFailed(transaction, "timed out");
        },
        verify: transaction => root._verifyTimedOut(transaction),
        prompt: transaction => {
            const prompt = transaction.state.prompt;
            if (prompt.owner === null)
                return;
            // A wall clock set back leaves the deadline far ahead: never more than one
            // full time-out from now
            const promptTime = transaction.state.settings.timings.prompt;
            const left = Math.min(prompt.awakeUntil - transaction.now, promptTime);
            if (left > transaction.state.settings.timings.promptSlack) {
                root._set(transaction, "prompt", { awakeUntil: transaction.now + left });
                root._startTimer(transaction, "prompt", left);
            } else {
                root._sleepPrompt(transaction);
            }
        },
        inhibitor: transaction => {
            if (transaction.state.sleep.inhibitor === "held") {
                root._log(transaction, "warning", "the compositor did not confirm the lock in time: letting the machine sleep");
                root._releaseInhibitor(transaction);
            }
        },
        missedResume: transaction => {
            if (transaction.state.sleep.status === "suspending") {
                root._log(transaction, "warning", "no resume signal: going on as awake");
                root._resume(transaction, true);
            }
        },
        minSuspend: transaction => {
            if (transaction.state.sleep.status === "suspending")
                root._set(transaction, "sleep", { minSuspendPassed: true });
        },
        resumeGrace: transaction => {
            root._set(transaction, "sleep", { status: "awake" });
            if (root._authenticating(transaction.state))
                root._redetectIfMissing(transaction, false);
        },
        retry: (transaction, method) => {
            if (transaction.state.passive[method]?.status === "backoff")
                root._setPassive(transaction, method, { status: "idle" });
        },
        settle: (transaction, method) => {
            if (method === "password")
                root._set(transaction, "password", { settling: false });
            else if (transaction.state.passive[method])
                root._setPassive(transaction, method, { settling: false });
        }
    })

    // ---- Settings ----

    // `values`: { lockOnSleep, passwordFallback } — either may be left out. The idle and
    // screensaver settings are the driver's (IdleMonitor), see the plan, section 7.
    function _settingsChanged(transaction, event) {
        const values = event.values !== null && typeof event.values === "object" ? event.values : {};
        const changes = {};
        if (typeof values.lockOnSleep === "boolean")
            changes.lockOnSleep = values.lockOnSleep;
        if (values.passwordFallback === null || _isConfig(values.passwordFallback))
            changes.passwordFallback = _copyConfig(values.passwordFallback);
        if (Object.keys(changes).length === 0)
            return "no known setting";
        _set(transaction, "settings", changes);
    }

    // ------------------------------------------------------------------------------------
    // Reconcile: after every taken event, what follows from the state as it now is —
    // whichever event led there. This is where the invariants live that no single handler
    // could keep alone: the inhibitor held exactly when wanted, no passive method running
    // while suspending, conversations started when they can be and not before, the verify
    // timer running exactly while a password waits for PAM.
    // ------------------------------------------------------------------------------------

    function _reconcile(transaction) {
        _reconcileInhibitor(transaction);
        if (!_authenticating(transaction.state))
            return;
        for (const method of passiveMethods)
            _reconcilePassive(transaction, method.name);
        _reconcilePassword(transaction);
        const status = transaction.state.password.status;
        const busy = status === "pending" || status === "verifying";
        if (busy && !("verify" in transaction.state.timers))
            _startTimer(transaction, "verify", transaction.state.settings.timings.verify);
        else if (!busy)
            _stopTimer(transaction, "verify");
    }

    // Held while awake with lockOnSleep, so that logind waits for the lock before sleep;
    // taken again after every wake (the old code lost it for good once released)
    function _reconcileInhibitor(transaction) {
        const sleep = transaction.state.sleep;
        const lockOnSleep = transaction.state.settings.lockOnSleep;
        if (sleep.inhibitor === "held" && !lockOnSleep) {
            _releaseInhibitor(transaction);
        } else if (sleep.inhibitor !== "held" && lockOnSleep && sleep.status !== "suspending") {
            _set(transaction, "sleep", { inhibitor: "held" });
            _emit(transaction, "holdInhibitor", {});
        }
    }

    function _reconcilePassive(transaction, name) {
        const suspending = transaction.state.sleep.status === "suspending";
        let passive = transaction.state.passive[name];
        if (passive.status === "running") {
            if (suspending) {
                _abort(transaction, name);
                _setPassive(transaction, name, { status: "paused" });
            }
            return;
        }
        if (passive.status === "backoff") {
            if (!suspending)
                return;
            _stopTimer(transaction, "retry:" + name);
        }
        if (passive.status === "broken")
            return;
        passive = transaction.state.passive[name];
        const status = passive.config === null ? "unavailable" : suspending ? "paused" : "idle";
        if (status !== passive.status)
            _setPassive(transaction, name, { status: status });
        // Not while the methods are being asked and their answer is awaited (after a wake:
        // it is what is trusted), or an abort is still settling. While locking too: the
        // owner can get in even if the compositor confirms late, the unlock then waits
        const methods = transaction.state.methods;
        const configsServe = methods.status === "known" || (methods.status === "detecting" && !methods.waitForAnswer);
        if (status === "idle" && configsServe && !passive.settling)
            _startPassive(transaction, name);
    }

    function _reconcilePassword(transaction) {
        const password = transaction.state.password;
        if (password.status !== "pending" || password.settling)
            return;
        // A config known from an earlier answer serves while the methods are asked again
        const config = _passwordConfig(transaction.state);
        if (config !== null) {
            const id = _nextId(transaction);
            _set(transaction, "password", { status: "verifying", conversation: { id: id, session: transaction.state.phase.session }, config: config });
            _emit(transaction, "startPam", { method: "password", conversation: id, configDirectory: config.directory, config: config.config });
        } else if (transaction.state.methods.status === "known") {
            _log(transaction, "warning", "no password config: the password cannot be checked");
            _passwordEnded(transaction, "unavailable", "Password check is not available");
        }
    }

    // The password config for the next conversation: the known one (detected, else the
    // fallback) — unless it is the one that could not be used in this lock
    // (password.avoid), and the fallback is another: then the fallback
    function _passwordConfig(state) {
        const known = _copyConfig(state.methods.configs.password);
        const avoid = state.password.avoid;
        const fallback = state.settings.passwordFallback;
        if (known !== null && avoid !== null && _sameConfig(known, avoid) && fallback && !_sameConfig(fallback, avoid))
            return _copyConfig(fallback);
        return known;
    }

    function _startPassive(transaction, name) {
        const passive = transaction.state.passive[name];
        const id = _nextId(transaction);
        _setPassive(transaction, name, {
            status: "running",
            conversation: { id: id, session: transaction.state.phase.session },
            startedAt: transaction.now,
            message: "",
            messageIsError: false
        });
        _emit(transaction, "startPam", { method: name, conversation: id, configDirectory: passive.config.directory, config: passive.config.config });
    }

    // Aborts a method's conversation within the lock. PamContext kills the child only at
    // the next event-loop pass: the method is not started again until its settle timer
    // has run — never in the step that aborts it.
    function _abort(transaction, method) {
        const region = method === "password" ? transaction.state.password : transaction.state.passive[method];
        if (region.conversation === null)
            return;
        _emit(transaction, "abortPam", { method: method, conversation: region.conversation.id });
        if (method === "password")
            _set(transaction, "password", { conversation: null, settling: true });
        else
            _setPassive(transaction, method, { conversation: null, settling: true });
        _startTimer(transaction, "settle:" + method, transaction.state.settings.timings.settle);
    }

    // ------------------------------------------------------------------------------------
    // Helpers: every change goes through these, which copy what they change
    // ------------------------------------------------------------------------------------

    function _ignored(state, reason) {
        return { state: state, effects: [], ignored: reason };
    }

    function _emit(transaction, type, fields) {
        transaction.effects.push(Object.assign({ type: type }, fields));
    }

    function _log(transaction, level, message) {
        _emit(transaction, "log", { level: level, message: message });
    }

    function _setTop(transaction, changes) {
        transaction.state = Object.assign({}, transaction.state, changes);
    }

    function _set(transaction, region, changes) {
        const replaced = {};
        replaced[region] = Object.assign({}, transaction.state[region], changes);
        _setTop(transaction, replaced);
    }

    function _setPassive(transaction, name, changes) {
        const passive = Object.assign({}, transaction.state.passive);
        passive[name] = Object.assign({}, passive[name], changes);
        _setTop(transaction, { passive: passive });
    }

    // Conversation ids, timer tokens and detection generations: one counter, never reset
    // within a state's life, so that nothing of an earlier conversation, timer or lock can
    // pass for a current one
    function _nextId(transaction) {
        const id = transaction.state.serial + 1;
        _setTop(transaction, { serial: id });
        return id;
    }

    // Starts the timer, or restarts it if it runs
    function _startTimer(transaction, name, milliseconds) {
        const ms = Math.max(0, Math.round(milliseconds));
        const token = _nextId(transaction);
        const timers = Object.assign({}, transaction.state.timers);
        timers[name] = { token: token };
        _setTop(transaction, { timers: timers });
        _emit(transaction, "startTimer", { name: name, ms: ms, token: token });
    }

    function _stopTimer(transaction, name) {
        if (!Object.prototype.hasOwnProperty.call(transaction.state.timers, name))
            return;
        const timers = Object.assign({}, transaction.state.timers);
        delete timers[name];
        _setTop(transaction, { timers: timers });
        _emit(transaction, "stopTimer", { name: name });
    }

    function _anyPassive(state, status) {
        return passiveMethods.some(method => state.passive[method.name].status === status);
    }

    // Surface ids are the driver's: a non-empty string or a finite number, compared strictly
    function _isSurfaceId(value) {
        return (typeof value === "string" && value !== "") || (typeof value === "number" && isFinite(value));
    }

    function _findSurface(state, id) {
        return state.prompt.surfaces.find(surface => surface.id === id);
    }

    function _isConfig(value) {
        return value !== null && typeof value === "object"
            && typeof value.directory === "string" && typeof value.config === "string";
    }

    // A config of our own, never the caller's object
    function _copyConfig(value) {
        return _isConfig(value) ? { directory: value.directory, config: value.config } : null;
    }

    function _sameConfig(a, b) {
        return _isConfig(a) && _isConfig(b) && a.directory === b.directory && a.config === b.config;
    }

    function _where(config) {
        return config ? config.directory + "/" + config.config : "(none)";
    }

    function _settingsFrom(settings) {
        const given = settings !== null && typeof settings === "object" ? settings : {};
        const overrides = given.timings !== null && typeof given.timings === "object" ? given.timings : {};
        const times = {};
        for (const name of Object.keys(timings)) {
            const value = overrides[name];
            times[name] = typeof value === "number" && isFinite(value) && value >= 0 ? value : timings[name];
        }
        return {
            lockOnSleep: typeof given.lockOnSleep === "boolean" ? given.lockOnSleep : false,
            passwordFallback: _copyConfig(given.passwordFallback),
            timings: times
        };
    }

    // "Lock before the computer sleeps" as the driver takes it: on when the user's settings
    // could not be read (`configFailed`, Profiles.configFailed: the value is then the default,
    // not the user's choice, and a lock nobody wanted is safer than a missing one); else the
    // profile's value when it is a boolean, else the schema's default (`schemaDefault`) — so
    // an unset value follows the schema, and anything but a boolean true there reads as off
    function lockOnSleepSetting(value, schemaDefault, configFailed) {
        if (configFailed === true)
            return true;
        return typeof value === "boolean" ? value : schemaDefault === true;
    }

    // The regions that live for one lock, as each lock starts them
    function _freshLockRegions() {
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
        if ("key" in copy && copy.key !== "" && !namedKeys.includes(copy.key))
            copy.key = "<redacted>";
        // What the password's PAM stack says is not logged either (a prompt, a verdict —
        // nothing typed, but a module may echo what it got): the passive methods' messages
        // ("Place your finger on the reader") are what tells a failure on the real machine
        if (copy.type === "pamMessage" && copy.method === "password" && "message" in copy)
            copy.message = "<not logged>";
        return copy;
    }
}
