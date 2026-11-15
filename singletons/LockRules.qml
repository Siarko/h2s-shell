pragma Singleton

import Quickshell
import QtQuick

// The lock screen's decisions — pure, so tests/LockRulesTest.qml checks every rule without
// a compositor, PAM or logind. This file is the specification of the lock; the driver
// (Lockscreen) owns the one live state, feeds events in and carries the effects out.
// docs/plans/lockscreen.md, section 7, is the contract between the two.
//
//   initial(settings)        → state
//   step(state, event, now)  → { state, effects, ignored }
//
// States are plain objects, replaced and never mutated: a caller may keep an old one and
// compare. `now` is the wall clock (Date.now()) at the moment the event is handled; no
// rule reads a clock, a process or another singleton.
//
// The state is in independent regions, each with a `status`:
//   phase    unlocked / locking / locked, and `session`, one more at every lock and at every
//            retry of a lock the compositor did not confirm
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
Singleton {
    id: root

    // Defaults, in milliseconds; `initial(settings)` takes overrides in `settings.timings`
    readonly property var timings: ({
        // The compositor confirms a lock within milliseconds. Past this the lock is set
        // again (a new session); after `limits.confirmAttempts` it is given up. Quickshell
        // refuses some locks without any signal, and the old code then sat in "locking"
        // for good, ignoring every later lock request
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
        // Activity this long after PrepareForSleep means the machine is up again, the
        // resume signal lost; earlier it is the hand that closed the lid
        minSuspend: 5000,
        // Passive methods' retries after a failed round (retryDelay)
        retryMin: 500,
        retryMax: 10000,
        quickRound: 20000,
        // A passive method's round that ended in PAM's Error (Quickshell maps every code
        // but success / auth error / max tries to it, a device not plugged in included):
        // tried again after this
        errorRetry: 30000
    })

    // Counts, not durations: not overridable
    readonly property var limits: ({
        // Attempts at a lock the compositor does not confirm (the first and two retries)
        confirmAttempts: 3,
        // Consecutive Error rounds after which a passive method is broken for the lock.
        // A config that cannot work at all (a module not installed) errs every time: this
        // bounds the PAM children and warnings it causes to five per lock — two and a half
        // minutes of retries, which also covers a device that takes a while to appear. An
        // eager method broken this way gets one more try each time somebody comes back to
        // the prompt (a security key plugged in when they sit down)
        errorLimit: 5
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

    // ESCAPE UNLOCKS — kept for now, deliberately: the owner uses it while testing (plan,
    // section 5). The one place it acts is the marked block in _key. Removing it is
    // deleting that block and this property; the Escape key then only wakes the prompt.
    readonly property bool escapeUnlocks: true

    // The key names a `key` event may carry (the driver maps Qt's keys to these; Return and
    // the keypad's Enter are both "Enter"). Anything else is a character and belongs in
    // `text`: an unknown `key` is taken as "" and never logged.
    readonly property var namedKeys: ["Escape", "Enter", "Backspace", "Delete", "Tab",
                                      "Left", "Right", "Up", "Down", "Home", "End"]

    // The timers of the sleep region: they outlive an unlock, every other timer belongs to
    // one lock and is stopped when it ends
    readonly property var sleepTimers: ["inhibitor", "missedResume", "resumeGrace"]

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

    // `settings`: { lockOnSleep (default true), passwordFallback: { directory, config } —
    // the password config used when detection names none or fails (null: none), timings:
    // overrides of `timings` (non-negative numbers; anything else keeps the default) }.
    // Copied: the caller's objects are not kept.
    function initial(settings) {
        return Object.assign({
            serial: 0,
            settings: _settingsFrom(settings),
            phase: { status: "unlocked", session: 0, lastEnd: "" },
            sleep: { status: "awake", since: null, deadline: null, inhibitor: "released" },
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
        const tx = { state: state, now: now, effects: [] };
        try {
            const refused = _handlers[type](tx, event);
            if (typeof refused === "string")
                return _ignored(state, refused);
            _reconcile(tx);
            return { state: tx.state, effects: tx.effects, ignored: "" };
        } catch (error) {
            return _internalError(state, event, now, error);
        }
    }

    // What the views render, so that they hold no logic of their own. A fresh object (and
    // `methods` a fresh array) on every call: feed `methods` to a Repeater through a
    // ScriptModel, never directly.
    function view(state) {
        const password = state.password;
        const asking = password.status === "asking";
        const busy = password.status === "pending" || password.status === "verifying";
        const owner = state.prompt.surfaces.find(surface => surface.id === state.prompt.owner);
        return {
            locked: state.phase.status !== "unlocked",
            // The one surface instance showing the prompt; null while it is asleep. Two
            // instances may share a screen for a moment (one being destroyed): only this
            // one shows it
            promptSurface: state.prompt.owner,
            // Its screen, for information; "" while asleep
            promptScreen: owner ? owner.screen : "",
            busy: busy,
            buttonText: busy ? "Verifying…" : "Unlock",
            placeholder: asking ? password.question : "Password",
            // The field shows what is typed only for a question that allows it
            answerVisible: asking && password.answerVisible,
            error: password.error,
            // Why the last submit was not taken ("busy", "empty"), "" when it was
            refusal: password.refusal,
            // The field empties whenever this changes: input taken, prompt moved or gone to
            // sleep
            fieldEpoch: state.prompt.fieldEpoch,
            methods: passiveMethods.map(method => _passiveView(method, state.passive[method.name]))
        };
    }

    // The state as it may be shown: JSON-serialisable, without the secret. The driver
    // exposes only this — the IPC `state`, logs, test output — never the state itself.
    function describe(state) {
        const copy = JSON.parse(JSON.stringify(state, (key, value) => key === "secret" ? undefined : value));
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
    // Error here: its wait is `errorRetry`, counted against `limits.errorLimit`.
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
    // Events, one handler each. A handler changes `tx.state` through the helpers below and
    // returns nothing, or a string saying why the event is ignored (its changes are then
    // dropped). `_reconcile` runs after every taken event.
    // ------------------------------------------------------------------------------------

    readonly property var _handlers: ({
        started: (tx, event) => root._started(tx, event),
        lockRequested: (tx, event) => root._lockRequested(tx, event),
        unlockRequested: (tx, event) => root._unlockRequested(tx, event),
        compositorLocked: (tx, event) => root._compositorLocked(tx, event),
        compositorFinished: (tx, event) => root._compositorFinished(tx, event),
        surfaceAdded: (tx, event) => root._surfaceAdded(tx, event),
        surfaceRemoved: (tx, event) => root._surfaceRemoved(tx, event),
        activity: (tx, event) => root._activity(tx, event),
        press: (tx, event) => root._press(tx, event),
        key: (tx, event) => root._key(tx, event),
        submit: (tx, event) => root._submit(tx, event),
        methodsDetected: (tx, event) => root._methodsDetected(tx, event),
        methodsFailed: (tx, event) => root._methodsFailed(tx, event),
        pamMessage: (tx, event) => root._pamMessage(tx, event),
        pamCompleted: (tx, event) => root._pamCompleted(tx, event),
        pamStartFailed: (tx, event) => root._pamStartFailed(tx, event),
        prepareForSleep: (tx, event) => root._prepareForSleep(tx, event),
        resumed: (tx, event) => root._resumed(tx, event),
        timer: (tx, event) => root._timer(tx, event),
        settings: (tx, event) => root._settingsChanged(tx, event)
    })

    // ---- Phase ----

    // Once, after initial(): takes the sleep inhibitor if the settings want it (reconcile)
    function _started(tx, event) {
    }

    function _lockRequested(tx, event) {
        // A second Lock (logind, idle, IPC) while locked must not start a second session
        // or restart the conversations under way
        if (tx.state.phase.status !== "unlocked")
            return "already locked";
        _enterLock(tx, typeof event.source === "string" ? event.source : "");
    }

    function _unlockRequested(tx, event) {
        if (tx.state.phase.status === "unlocked")
            return "not locked";
        // Defect 5: anything could unlock. Only the sources the owner named do
        if (!unlockSources.includes(event.source))
            return "unlock source not allowed: " + String(event.source);
        _leaveLock(tx, event.source, "");
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

    function _compositorLocked(tx, event) {
        const refused = _checkCompositor(tx.state, event);
        if (refused !== "")
            return refused;
        if (tx.state.phase.status !== "locking")
            return "not locking";
        _stopTimer(tx, "confirm");
        _set(tx, "phase", { status: "locked" });
        // On the way to sleep the inhibitor was held for exactly this
        if (tx.state.sleep.status === "suspending" && tx.state.sleep.inhibitor === "held")
            _releaseInhibitor(tx);
    }

    // The compositor ended the lock, or refused it. Either way the lock is over: the
    // WlSessionLock is set back to unlocked so that the next lock can happen at all.
    function _compositorFinished(tx, event) {
        const refused = _checkCompositor(tx.state, event);
        if (refused !== "")
            return refused;
        const locking = tx.state.phase.status === "locking";
        if (locking)
            _log(tx, "warning", "the compositor refused the lock");
        _leaveLock(tx, locking ? "denied" : "compositor", "");
    }

    // The lock's first effects are always lockCompositor and announceLocked(true), whatever
    // the event did before (a sleep's timers): the lock is what matters most on the way down
    function _enterLock(tx, source) {
        const session = tx.state.phase.session + 1;
        const before = tx.effects;
        tx.effects = [];
        _setTop(tx, Object.assign(_freshLockRegions(), {
            phase: { status: "locking", session: session, source: source, since: tx.now, attempt: 1 }
        }));
        _emit(tx, "lockCompositor", { session: session });
        _emit(tx, "announceLocked", { locked: true });
        tx.effects = tx.effects.concat(before);
        _log(tx, "info", "locking (" + (source || "request") + "), session " + session);
        _startTimer(tx, "confirm", tx.state.settings.timings.confirm);
        _detect(tx, true);
    }

    // No word from the compositor: the lock is set again under a new session (so that a
    // late word about the old one is stale), a few times, then given up — back to a state
    // where the next lock request locks, the secret dropped.
    function _confirmTimedOut(tx) {
        const phase = tx.state.phase;
        if (phase.status !== "locking")
            return;
        if (phase.attempt >= limits.confirmAttempts) {
            _log(tx, "warning", "the compositor did not confirm the lock after " + phase.attempt + " attempts: giving up");
            _leaveLock(tx, "unconfirmed", "");
            return;
        }
        const session = phase.session + 1;
        _emit(tx, "unlockCompositor", { session: phase.session, reason: "retry" });
        _set(tx, "phase", { session: session, attempt: phase.attempt + 1 });
        _emit(tx, "lockCompositor", { session: session });
        _log(tx, "warning", "the compositor did not confirm the lock: setting it again, session " + session);
        _startTimer(tx, "confirm", tx.state.settings.timings.confirm);
    }

    // Every way out of the lock goes through here: conversations aborted, the lock's
    // timers stopped, the secret dropped, the lock's regions thrown away — so nothing of
    // this lock reaches the next one (defects 6 and the root cause in section 1).
    function _leaveLock(tx, reason, method) {
        for (const conversation of running(tx.state).conversations)
            _emit(tx, "abortPam", { method: conversation.method, conversation: conversation.conversation });
        for (const name of running(tx.state).lockTimers)
            _stopTimer(tx, name);
        // Held for the lock on the way to sleep: there is no lock to wait for any more
        if (tx.state.sleep.status === "suspending" && tx.state.sleep.inhibitor === "held")
            _releaseInhibitor(tx);
        const session = tx.state.phase.session;
        _setTop(tx, Object.assign(_freshLockRegions(), {
            phase: { status: "unlocked", session: session, lastEnd: reason }
        }));
        const fields = { session: session, reason: reason };
        if (method)
            fields.method = method;
        _emit(tx, "unlockCompositor", fields);
        _emit(tx, "announceLocked", { locked: false });
        _log(tx, "info", "unlocked (" + reason + (method ? ", " + method : "") + "), session " + session);
    }

    // ---- Prompt ----

    // Surfaces are instances, by the driver's id, not screens: Quickshell destroys a lock
    // surface with deleteLater() and creates its successor at once, so a screen's new
    // surface can report itself before the old one's removal (an output re-added, unlock
    // and lock in one pass, a reload). Keyed by screen, the old removal took the new
    // surface with it and the only screen stopped taking input.
    function _surfaceAdded(tx, event) {
        if (tx.state.phase.status === "unlocked")
            return "not locked";
        if (!_isSurfaceId(event.surface))
            return "no surface";
        if (typeof event.screen !== "string" || event.screen === "")
            return "no screen";
        if (_findSurface(tx.state, event.surface) !== undefined)
            return "surface already known";
        _set(tx, "prompt", { surfaces: tx.state.prompt.surfaces.concat([{ id: event.surface, screen: event.screen }]) });
    }

    // A surface going away that owned the prompt hands it on, awake, the question (if any)
    // kept — it is in the state, not the view: to the newest other instance on the same
    // screen (its successor), else to the first surface left. With none left the prompt
    // sleeps. The old code left the prompt "active" on a surface that no longer existed:
    // the screen that came back never woke.
    function _surfaceRemoved(tx, event) {
        if (tx.state.phase.status === "unlocked")
            return "not locked";
        const removed = _findSurface(tx.state, event.surface);
        if (removed === undefined)
            return "unknown surface";
        const remaining = tx.state.prompt.surfaces.filter(surface => surface !== removed);
        _set(tx, "prompt", { surfaces: remaining });
        if (tx.state.prompt.owner !== removed.id)
            return;
        if (remaining.length === 0) {
            _sleepPrompt(tx);
            return;
        }
        const sameScreen = remaining.filter(surface => surface.screen === removed.screen);
        const heir = sameScreen.length > 0 ? sameScreen[sameScreen.length - 1] : remaining[0];
        _set(tx, "prompt", { owner: heir.id, fieldEpoch: tx.state.prompt.fieldEpoch + 1 });
    }

    // Pointer motion, typing in the field: wakes the prompt where it happens, or extends
    // its time on the surface that has it
    function _activity(tx, event) {
        const refused = _checkSurface(tx.state, event.surface);
        if (refused !== "")
            return refused;
        _recoverSleep(tx);
        _wake(tx, event.surface);
    }

    // A pointer press: on a surface that does not own the prompt it brings the prompt
    // there — the only way to move it while somebody is active (the owner's decision). The
    // field starts empty there; a question is kept (it is in the state), a verification
    // goes on.
    function _press(tx, event) {
        const refused = _checkSurface(tx.state, event.surface);
        if (refused !== "")
            return refused;
        _recoverSleep(tx);
        const owner = tx.state.prompt.owner;
        if (owner !== null && owner !== event.surface)
            _set(tx, "prompt", { owner: event.surface, fieldEpoch: tx.state.prompt.fieldEpoch + 1 });
        _wake(tx, event.surface);
    }

    // Any key that reaches a surface's key catcher (the field could not take it: the
    // prompt asleep, fading in, or on another surface). It wakes the prompt and is
    // forwarded to the field of the surface that owns it — Enter and Backspace included,
    // so that no key is lost (defect 9). A key on another surface while the prompt is awake
    // is forwarded there rather than moving the prompt: the half-typed text lives in the
    // owner's field (a press moves it).
    function _key(tx, event) {
        const refused = _checkSurface(tx.state, event.surface);
        if (refused !== "")
            return refused;
        _recoverSleep(tx);
        // A character belongs in `text`; a `key` outside the list is dropped, so that it can
        // neither carry typed text into a log nor act as a key the field does not know
        const key = namedKeys.includes(event.key) ? event.key : "";
        // Control characters (Enter's "\r", Backspace's "\b", Ctrl+letters) are not text
        const text = typeof event.text === "string" && !/[\u0000-\u001f\u007f]/.test(event.text) ? event.text : "";
        const wasAwake = tx.state.prompt.owner !== null;
        if (key === "Escape") {
            // ---- ESCAPE UNLOCKS (see `escapeUnlocks`): delete this block to remove it ----
            if (escapeUnlocks && wasAwake) {
                _leaveLock(tx, "escape", "");
                return;
            }
            // ---- end of Escape ----
            // On a sleeping prompt Escape only wakes it, and is not passed on
            _wake(tx, event.surface);
            return;
        }
        _wake(tx, event.surface);
        if (key !== "" || text !== "")
            _emit(tx, "forwardKey", { surface: tx.state.prompt.owner, key: key, text: text });
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

    function _wake(tx, surface) {
        const times = tx.state.settings.timings;
        if (tx.state.prompt.owner !== null) {
            // No timer restart on every pointer move: the timer re-arms itself at expiry
            // when the deadline has moved
            _set(tx, "prompt", { awakeUntil: tx.now + times.prompt });
            return;
        }
        _set(tx, "prompt", { owner: surface, awakeUntil: tx.now + times.prompt });
        _startTimer(tx, "prompt", times.prompt);
        _nudge(tx);
    }

    // Somebody came back to the prompt: a method that fails at once without its device
    // (a security key not plugged in yet) tries again now rather than after its delay, and
    // a lock without one of its passive methods asks again whether it has it now
    function _nudge(tx) {
        if (tx.state.sleep.status === "suspending")
            return;
        for (const method of passiveMethods) {
            if (!method.eager)
                continue;
            const passive = tx.state.passive[method.name];
            if (passive.status === "backoff") {
                _stopTimer(tx, "retry:" + method.name);
                _setPassive(tx, method.name, { status: "idle" });
            } else if (passive.status === "broken" && passive.brokenBy === "error") {
                // One more try per return; another Error breaks it again at once
                _setPassive(tx, method.name, { status: "idle", brokenBy: "" });
            }
        }
        // The configs known so far serve meanwhile: the eager retry above starts now
        if (tx.state.methods.status === "known" && _anyPassive(tx.state, "unavailable"))
            _detect(tx, false);
    }

    // The prompt's inactivity time-out (and the last surface gone): the prompt hides, its
    // field empties, a QUESTION left unanswered (a one-time code) is cancelled — but a
    // verification under way is not touched (defect 8: the old 10 s sleep aborted it)
    function _sleepPrompt(tx) {
        _stopTimer(tx, "prompt");
        _set(tx, "prompt", { owner: null, awakeUntil: null, fieldEpoch: tx.state.prompt.fieldEpoch + 1 });
        const password = tx.state.password;
        if (password.status === "asking") {
            _abort(tx, "password");
            _set(tx, "password", { status: "idle", question: "", answerVisible: false, pamError: "" });
        } else if (password.status === "failed" || password.status === "unavailable") {
            _set(tx, "password", { status: "idle", error: "", pamError: "" });
        }
        _set(tx, "password", { refusal: "" });
    }

    // ---- Password ----

    // What was typed and sent: the password, or the answer to the question — from the
    // surface showing the prompt only. The field empties only when the input was taken
    // (fieldEpoch); a refusal says why in `refusal` and leaves the field as it is (defect
    // 10: it emptied either way, which hid the root cause).
    function _submit(tx, event) {
        const refused = _checkSurface(tx.state, event.surface);
        if (refused !== "")
            return refused;
        if (tx.state.prompt.owner !== event.surface)
            return tx.state.prompt.owner === null ? "prompt asleep" : "not the prompt's surface";
        const text = typeof event.text === "string" ? event.text : "";
        const password = tx.state.password;
        _set(tx, "prompt", { awakeUntil: tx.now + tx.state.settings.timings.prompt });
        if (password.status === "asking") {
            // At most one answer per prompt: PamContext hands a second respond() to the
            // next prompt. After this the state is "verifying" and a submit is refused.
            _emit(tx, "respondPam", { method: "password", conversation: password.conversation.id, text: text });
            _set(tx, "password", { status: "verifying", question: "", answerVisible: false, refusal: "" });
            _startTimer(tx, "verify", tx.state.settings.timings.verify);
            _takeInput(tx);
            return;
        }
        if (password.status === "pending" || password.status === "verifying") {
            _set(tx, "password", { refusal: "busy" });
            return;
        }
        // An empty password is never sent: with `nullok` it could unlock (defect 13), and
        // an Enter forwarded right after waking would otherwise count as a failed attempt
        if (text === "") {
            _set(tx, "password", { refusal: "empty" });
            return;
        }
        // Held until PAM asks for it — the conversation may not even be startable yet
        // (methods unknown, compositor not confirmed); _reconcilePassword starts it
        _setTop(tx, { secret: text });
        _set(tx, "password", { status: "pending", error: "", pamError: "", refusal: "" });
        _startTimer(tx, "verify", tx.state.settings.timings.verify);
        _takeInput(tx);
        // No password config known: the script is asked again before saying so (a config
        // that appeared since, or a detection that came back empty)
        if (tx.state.methods.status === "known" && !tx.state.methods.configs.password)
            _detect(tx, false);
    }

    function _takeInput(tx) {
        _set(tx, "prompt", { fieldEpoch: tx.state.prompt.fieldEpoch + 1 });
    }

    // A submitted password with no answer from PAM in `timings.verify`: a hung module, a
    // start that never came. Without this the owner could not try again for the rest of
    // the lock (the prompt's sleep deliberately never aborts a verification).
    function _verifyTimedOut(tx) {
        const status = tx.state.password.status;
        if (status !== "pending" && status !== "verifying")
            return;
        _log(tx, "warning", "the password check did not answer in time: aborted");
        _abort(tx, "password");
        _setTop(tx, { secret: null });
        _set(tx, "password", { status: "failed", question: "", answerVisible: false, refusal: "",
                               error: "Password check timed out" });
    }

    // ---- Methods ----

    // Asks which methods there are. A newer request supersedes an older one: its answer
    // carries an older generation and is ignored. `waitForAnswer`: passive methods wait for
    // this answer (at the lock, and after a wake — then the reader's service may have
    // changed); otherwise the configs known so far serve meanwhile.
    function _detect(tx, waitForAnswer) {
        const generation = _nextId(tx);
        _set(tx, "methods", { status: "detecting", generation: generation, waitForAnswer: waitForAnswer });
        _emit(tx, "detectMethods", { generation: generation });
        _startTimer(tx, "detect", tx.state.settings.timings.detect);
    }

    function _methodsDetected(tx, event) {
        const refused = _checkDetection(tx.state, event);
        if (refused !== "")
            return refused;
        _applyDetection(tx, parseMethods(event.lines));
    }

    function _methodsFailed(tx, event) {
        const refused = _checkDetection(tx.state, event);
        if (refused !== "")
            return refused;
        _detectionFailed(tx, typeof event.reason === "string" && event.reason !== "" ? "failed (" + event.reason + ")" : "failed");
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
    // one stays broken — only a wake clears that).
    function _applyDetection(tx, found) {
        _stopTimer(tx, "detect");
        const detectedPassword = _copyConfig(found.password);
        const fallback = tx.state.settings.passwordFallback;
        const configs = { password: detectedPassword ?? fallback ?? null };
        for (const method of passiveMethods)
            configs[method.name] = _copyConfig(found[method.name]);
        _set(tx, "methods", {
            status: "known", configs: configs, answered: true, waitForAnswer: false,
            // Where the password config came from: "detected", "fallback" or "none"
            passwordSource: detectedPassword !== null ? "detected" : fallback ? "fallback" : "none"
        });
        for (const method of passiveMethods) {
            const passive = tx.state.passive[method.name];
            const config = configs[method.name];
            if (config === null && passive.status === "running") {
                _abort(tx, method.name);
                _setPassive(tx, method.name, { status: "unavailable" });
            } else if (config === null && passive.status === "backoff") {
                _stopTimer(tx, "retry:" + method.name);
                _setPassive(tx, method.name, { status: "unavailable" });
            }
            _setPassive(tx, method.name, { config: config });
        }
    }

    // No answer (script failed or timed out): go on with what this lock already knew, and
    // the password fallback where that names no password — a lock must never wait on
    // "verifying" for good (defect 7)
    function _detectionFailed(tx, reason) {
        const methods = tx.state.methods;
        const last = {};
        if (methods.answered) {
            for (const method of passiveMethods)
                last[method.name] = methods.configs[method.name];
            // Only a password config the script named is an answer; a fallback is taken afresh
            if (methods.passwordSource === "detected")
                last.password = methods.configs.password;
        }
        _applyDetection(tx, last);
        const source = tx.state.methods.passwordSource;
        _log(tx, "warning", "detecting the methods " + reason + "; going on with "
            + (methods.answered ? "this lock's last answer" : "nothing detected")
            + ", password config: " + (source === "detected" ? "from that answer" : source === "fallback" ? "the fallback" : "none"));
    }

    // ---- PAM ----

    function _pamMessage(tx, event) {
        const refused = _checkConversation(tx.state, event);
        if (refused !== "")
            return refused;
        const message = typeof event.message === "string" ? event.message.trim() : "";
        if (event.method === "password") {
            _passwordMessage(tx, event, message);
            return;
        }
        if (message !== "")
            _setPassive(tx, event.method, { message: message, messageIsError: event.messageIsError === true });
        // Nothing is typed for a passive method. A prompt asking for input means a config
        // that is not passive (a password module, pam_u2f's "interactive") — and the old
        // empty answer, repeated every round, was a failed password attempt each time
        // (defect 12): faillock locks the account. So the method stops, broken for this
        // lock, and says so.
        if (event.responseRequired === true) {
            _abort(tx, event.method);
            _setPassive(tx, event.method, { status: "broken", brokenBy: "asks", message: "", messageIsError: false });
            _log(tx, "warning", event.method + " asks for input, which a passive method never gives: not used");
        }
    }

    function _passwordMessage(tx, event, message) {
        if (event.responseRequired !== true) {
            // PAM knows why it says no (an account locked, a password expired): shown on
            // failure instead of a plain "failed"
            if (event.messageIsError === true && message !== "")
                _set(tx, "password", { pamError: message });
            return;
        }
        const secret = tx.state.secret;
        // The typed password answers the first prompt that hides its answer. A prompt that
        // shows it is no password prompt: the password is dropped, not shown, and the
        // question asked.
        if (secret !== null && event.responseVisible !== true) {
            _emit(tx, "respondPam", { method: "password", conversation: tx.state.password.conversation.id, text: secret });
            _setTop(tx, { secret: null });
            return;
        }
        _setTop(tx, { secret: null });
        _set(tx, "password", {
            status: "asking",
            question: message.replace(/:$/, "").trim() || "Answer",
            answerVisible: event.responseVisible === true
        });
    }

    function _pamCompleted(tx, event) {
        const refused = _checkConversation(tx.state, event);
        if (refused !== "")
            return refused;
        const result = pamResults.includes(event.result) ? event.result : "error";
        const method = event.method;
        if (result === "success") {
            _leaveLock(tx, "authenticated", method);
            return;
        }
        if (method === "password") {
            const password = tx.state.password;
            _log(tx, "warning", "password not accepted (" + result + "), PAM config " + _where(password.config));
            _setTop(tx, { secret: null });
            _set(tx, "password", {
                status: result === "error" ? "unavailable" : "failed",
                conversation: null,
                question: "",
                answerVisible: false,
                // A "busy" from a submit during this verification is old news now
                refusal: "",
                error: result === "error" ? "Password check is not available"
                    : password.pamError !== "" ? password.pamError
                    : result === "maxTries" ? "Too many attempts" : "Authentication failed"
            });
            return;
        }
        const passive = tx.state.passive[method];
        if (result === "error") {
            // Quickshell's Error is every PAM code but success, auth error and max tries: a
            // module missing (for good) or a device not there yet (for now). A long wait,
            // and broken only after several in a row.
            const errors = passive.errors + 1;
            if (errors >= limits.errorLimit) {
                _log(tx, "warning", method + " cannot be used (" + errors + " errors in a row), PAM config " + _where(passive.config));
                _setPassive(tx, method, { status: "broken", brokenBy: "error", conversation: null, errors: errors, lastResult: result });
                return;
            }
            const wait = tx.state.settings.timings.errorRetry;
            _log(tx, "warning", method + ": PAM error (" + errors + " of " + limits.errorLimit + "), trying again later");
            _setPassive(tx, method, { status: "backoff", conversation: null, errors: errors, delay: wait, lastResult: result });
            _startTimer(tx, "retry:" + method, wait);
            return;
        }
        const delay = retryDelay(passive.delay, tx.now - passive.startedAt, result, tx.state.settings.timings);
        _setPassive(tx, method, { status: "backoff", conversation: null, errors: 0, delay: delay, lastResult: result });
        _startTimer(tx, "retry:" + method, delay);
    }

    // PamContext.start() refused (a config that is not there): reported by the driver,
    // since start() says so only through its return value. Visible, never "verifying".
    function _pamStartFailed(tx, event) {
        const refused = _checkConversation(tx.state, event);
        if (refused !== "")
            return refused;
        _log(tx, "warning", event.method + ": PAM refused to start the conversation");
        if (event.method === "password") {
            _setTop(tx, { secret: null });
            _set(tx, "password", { status: "unavailable", conversation: null, refusal: "",
                                   error: "Password check could not start" });
        } else {
            _setPassive(tx, event.method, { status: "broken", brokenBy: "start", conversation: null });
        }
    }

    // A PAM event counts only for the conversation that is running now, for this method,
    // in this lock. A completion that arrives after an abort, or from a conversation of an
    // earlier lock, is ignored (ids are never reused within a state's life; compared
    // strictly, so neither "7" nor [7] passes for 7).
    function _checkConversation(state, event) {
        if (state.phase.status !== "locked")
            return "not locked";
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
    // The minimum, with no rule that could throw again: the conversation is over.
    function _internalError(state, event, now, error) {
        const ignored = { state: state, effects: [], ignored: "internal error: " + error, error: true };
        try {
            if (event.type !== "pamCompleted" && event.type !== "pamStartFailed")
                return ignored;
            if (_checkConversation(state, event) !== "")
                return ignored;
            const tx = { state: state, now: now, effects: [] };
            if (event.method === "password") {
                _setTop(tx, { secret: null });
                _set(tx, "password", { status: "failed", conversation: null, question: "", answerVisible: false,
                                       refusal: "", error: "Password check failed, try again" });
            } else {
                _setPassive(tx, event.method, { status: "broken", brokenBy: "internal", conversation: null });
            }
            _log(tx, "error", "internal error on " + event.type + " for " + event.method + " (" + error + "): the conversation is ended");
            return { state: tx.state, effects: tx.effects, ignored: "", error: true };
        } catch (again) {
            return ignored;
        }
    }

    // ---- Sleep ----

    // PrepareForSleep(true). While still suspending it means the wake was missed (the
    // `resumed` lost) and this is a new sleep: the lock must happen again, not be ignored
    // with the machine going down unlocked.
    function _prepareForSleep(tx, event) {
        const times = tx.state.settings.timings;
        const missedWake = tx.state.sleep.status === "suspending";
        const wasLocked = tx.state.phase.status !== "unlocked";
        if (!wasLocked && tx.state.settings.lockOnSleep)
            _enterLock(tx, "sleep");
        if (missedWake) {
            _log(tx, "warning", "PrepareForSleep while suspending: the resume signal was missed");
            _wakeSleep(tx, false);
            if (wasLocked)
                _wakeLock(tx);
        }
        const held = tx.state.sleep.inhibitor === "held";
        _stopTimer(tx, "resumeGrace");
        _set(tx, "sleep", { status: "suspending", since: tx.now, deadline: tx.now + times.missedResume });
        _startTimer(tx, "missedResume", times.missedResume);
        if (!held)
            return;
        // logind waits while the inhibitor is held: until the compositor confirms the lock,
        // or the fallback lets the machine go
        if (tx.state.phase.status === "locking")
            _startTimer(tx, "inhibitor", times.inhibitorFallback);
        else
            _releaseInhibitor(tx);
        // Passive methods running are aborted and none starts until the wake (reconcile):
        // their devices go away over a suspend, a conversation is dead when it wakes
    }

    function _resumed(tx, event) {
        _wakeSleep(tx);
        if (tx.state.phase.status !== "unlocked")
            _wakeLock(tx);
    }

    // After a wake — signalled, or recovered when the signal was lost — the sleep region.
    // `grace`: false when a new sleep follows in the same step (no grace period to run)
    function _wakeSleep(tx, grace) {
        const times = tx.state.settings.timings;
        _stopTimer(tx, "missedResume");
        _stopTimer(tx, "inhibitor");
        _set(tx, "sleep", { status: "resuming", since: tx.now, deadline: tx.now + times.resumeGrace });
        if (grace !== false)
            _startTimer(tx, "resumeGrace", times.resumeGrace);
    }

    // … and the lock: what the reader's service said before is not trusted — methods asked
    // again, broken ones given another chance, conversations started afresh once the
    // answer is in. Also when no prepareForSleep was seen: then running conversations may
    // be dead and are restarted.
    function _wakeLock(tx) {
        for (const method of passiveMethods) {
            const status = tx.state.passive[method.name].status;
            if (status === "running")
                _abort(tx, method.name);
            else if (status === "backoff")
                _stopTimer(tx, "retry:" + method.name);
            if (status === "running" || status === "backoff" || status === "broken")
                _setPassive(tx, method.name, { status: "idle", brokenBy: "" });
            _setPassive(tx, method.name, { errors: 0 });
        }
        _detect(tx, true);
    }

    // The resume signal was lost: activity well after going down means the machine is up
    function _recoverSleep(tx) {
        const sleep = tx.state.sleep;
        if (sleep.status === "suspending" && tx.now - sleep.since >= tx.state.settings.timings.minSuspend) {
            _log(tx, "warning", "activity while suspending: the resume signal was missed");
            _wakeSleep(tx);
            if (tx.state.phase.status !== "unlocked")
                _wakeLock(tx);
        }
    }

    function _releaseInhibitor(tx) {
        _stopTimer(tx, "inhibitor");
        if (tx.state.sleep.inhibitor !== "held")
            return;
        _set(tx, "sleep", { inhibitor: "released" });
        _emit(tx, "releaseInhibitor", {});
    }

    // ---- Timers ----

    // A timer's expiry counts only with the token of its latest start: one stopped or
    // restarted meanwhile reports a token no longer there
    function _timer(tx, event) {
        const name = event.name;
        if (typeof name !== "string" || !Object.prototype.hasOwnProperty.call(tx.state.timers, name))
            return "timer not running";
        if (tx.state.timers[name].token !== event.token)
            return "stale timer";
        const timers = Object.assign({}, tx.state.timers);
        delete timers[name];
        _setTop(tx, { timers: timers });
        const [kind, method] = name.split(":");
        const handler = _timerHandlers[kind];
        return handler ? handler(tx, method) : undefined;
    }

    readonly property var _timerHandlers: ({
        confirm: tx => root._confirmTimedOut(tx),
        detect: tx => {
            if (tx.state.methods.status === "detecting")
                root._detectionFailed(tx, "timed out");
        },
        verify: tx => root._verifyTimedOut(tx),
        prompt: tx => {
            const prompt = tx.state.prompt;
            if (prompt.owner === null)
                return;
            // A wall clock set back leaves the deadline far ahead: never more than one
            // full time-out from now
            const promptTime = tx.state.settings.timings.prompt;
            const left = Math.min(prompt.awakeUntil - tx.now, promptTime);
            if (left > tx.state.settings.timings.promptSlack) {
                root._set(tx, "prompt", { awakeUntil: tx.now + left });
                root._startTimer(tx, "prompt", left);
            } else {
                root._sleepPrompt(tx);
            }
        },
        inhibitor: tx => {
            if (tx.state.sleep.inhibitor === "held") {
                root._log(tx, "warning", "the compositor did not confirm the lock in time: letting the machine sleep");
                root._releaseInhibitor(tx);
            }
        },
        missedResume: tx => {
            if (tx.state.sleep.status === "suspending") {
                root._log(tx, "warning", "no resume signal: going on as awake");
                root._wakeSleep(tx);
                if (tx.state.phase.status !== "unlocked")
                    root._wakeLock(tx);
            }
        },
        resumeGrace: tx => {
            root._set(tx, "sleep", { status: "awake", since: null, deadline: null });
            if (tx.state.phase.status !== "unlocked" && tx.state.methods.status === "known"
                    && root._anyPassive(tx.state, "unavailable"))
                root._detect(tx, false);
        },
        retry: (tx, method) => {
            if (tx.state.passive[method]?.status === "backoff")
                root._setPassive(tx, method, { status: "idle" });
        },
        settle: (tx, method) => {
            if (method === "password")
                root._set(tx, "password", { settling: false });
            else if (tx.state.passive[method])
                root._setPassive(tx, method, { settling: false });
        }
    })

    // ---- Settings ----

    // `values`: { lockOnSleep, passwordFallback } — either may be left out. The idle and
    // screensaver settings are the driver's (IdleMonitor), see the plan, section 7.
    function _settingsChanged(tx, event) {
        const values = event.values !== null && typeof event.values === "object" ? event.values : {};
        const changes = {};
        if (typeof values.lockOnSleep === "boolean")
            changes.lockOnSleep = values.lockOnSleep;
        if (values.passwordFallback === null || _isConfig(values.passwordFallback))
            changes.passwordFallback = _copyConfig(values.passwordFallback);
        if (Object.keys(changes).length === 0)
            return "no known setting";
        _set(tx, "settings", changes);
    }

    // ------------------------------------------------------------------------------------
    // Reconcile: after every taken event, what follows from the state as it now is —
    // whichever event led there. This is where the invariants live that no single handler
    // could keep alone: the inhibitor held exactly when wanted, no passive method running
    // while suspending, conversations started when they can be and not before, the verify
    // timer running exactly while a password waits for PAM.
    // ------------------------------------------------------------------------------------

    function _reconcile(tx) {
        _reconcileInhibitor(tx);
        if (tx.state.phase.status === "unlocked")
            return;
        for (const method of passiveMethods)
            _reconcilePassive(tx, method.name);
        _reconcilePassword(tx);
        const status = tx.state.password.status;
        const busy = status === "pending" || status === "verifying";
        if (busy && !("verify" in tx.state.timers))
            _startTimer(tx, "verify", tx.state.settings.timings.verify);
        else if (!busy)
            _stopTimer(tx, "verify");
    }

    // Held while awake with lockOnSleep, so that logind waits for the lock before sleep;
    // taken again after every wake (the old code lost it for good once released)
    function _reconcileInhibitor(tx) {
        const sleep = tx.state.sleep;
        const lockOnSleep = tx.state.settings.lockOnSleep;
        if (sleep.inhibitor === "held" && !lockOnSleep) {
            _releaseInhibitor(tx);
        } else if (sleep.inhibitor !== "held" && lockOnSleep && sleep.status !== "suspending") {
            _set(tx, "sleep", { inhibitor: "held" });
            _emit(tx, "holdInhibitor", {});
        }
    }

    function _reconcilePassive(tx, name) {
        const suspending = tx.state.sleep.status === "suspending";
        let passive = tx.state.passive[name];
        if (passive.status === "running") {
            if (suspending) {
                _abort(tx, name);
                _setPassive(tx, name, { status: "paused" });
            }
            return;
        }
        if (passive.status === "backoff") {
            if (!suspending)
                return;
            _stopTimer(tx, "retry:" + name);
        }
        if (passive.status === "broken")
            return;
        passive = tx.state.passive[name];
        const status = passive.config === null ? "unavailable" : suspending ? "paused" : "idle";
        if (status !== passive.status)
            _setPassive(tx, name, { status: status });
        // Not while the compositor has not confirmed the lock, the methods are being asked
        // and their answer is awaited (after a wake: it is what is trusted), or an abort is
        // still settling
        const methods = tx.state.methods;
        const configsServe = methods.status === "known" || (methods.status === "detecting" && !methods.waitForAnswer);
        if (status === "idle" && tx.state.phase.status === "locked" && configsServe && !passive.settling)
            _startPassive(tx, name);
    }

    function _reconcilePassword(tx) {
        const password = tx.state.password;
        if (password.status !== "pending" || tx.state.phase.status !== "locked" || password.settling)
            return;
        // A config known from an earlier answer serves while the methods are asked again
        const config = tx.state.methods.configs.password ?? null;
        if (config !== null) {
            const id = _nextId(tx);
            _set(tx, "password", { status: "verifying", conversation: { id: id, session: tx.state.phase.session }, config: config });
            _emit(tx, "startPam", { method: "password", conversation: id, configDirectory: config.directory, config: config.config });
        } else if (tx.state.methods.status === "known") {
            _log(tx, "warning", "no password config: the password cannot be checked");
            _setTop(tx, { secret: null });
            _set(tx, "password", { status: "unavailable", error: "Password check is not available" });
        }
    }

    function _startPassive(tx, name) {
        const passive = tx.state.passive[name];
        const id = _nextId(tx);
        _setPassive(tx, name, {
            status: "running",
            conversation: { id: id, session: tx.state.phase.session },
            startedAt: tx.now,
            message: "",
            messageIsError: false
        });
        _emit(tx, "startPam", { method: name, conversation: id, configDirectory: passive.config.directory, config: passive.config.config });
    }

    // Aborts a method's conversation within the lock. PamContext kills the child only at
    // the next event-loop pass: the method is not started again until its settle timer
    // has run — never in the step that aborts it.
    function _abort(tx, method) {
        const region = method === "password" ? tx.state.password : tx.state.passive[method];
        if (region.conversation === null)
            return;
        _emit(tx, "abortPam", { method: method, conversation: region.conversation.id });
        if (method === "password")
            _set(tx, "password", { conversation: null, settling: true });
        else
            _setPassive(tx, method, { conversation: null, settling: true });
        _startTimer(tx, "settle:" + method, tx.state.settings.timings.settle);
    }

    // ------------------------------------------------------------------------------------
    // Helpers: every change goes through these, which copy what they change
    // ------------------------------------------------------------------------------------

    function _ignored(state, reason) {
        return { state: state, effects: [], ignored: reason };
    }

    function _emit(tx, type, fields) {
        tx.effects.push(Object.assign({ type: type }, fields));
    }

    function _log(tx, level, message) {
        _emit(tx, "log", { level: level, message: message });
    }

    function _setTop(tx, changes) {
        tx.state = Object.assign({}, tx.state, changes);
    }

    function _set(tx, region, changes) {
        const replaced = {};
        replaced[region] = Object.assign({}, tx.state[region], changes);
        _setTop(tx, replaced);
    }

    function _setPassive(tx, name, changes) {
        const passive = Object.assign({}, tx.state.passive);
        passive[name] = Object.assign({}, passive[name], changes);
        _setTop(tx, { passive: passive });
    }

    // Conversation ids, timer tokens and detection generations: one counter, never reset
    // within a state's life, so that nothing of an earlier conversation, timer or lock can
    // pass for a current one
    function _nextId(tx) {
        const id = tx.state.serial + 1;
        _setTop(tx, { serial: id });
        return id;
    }

    // Starts the timer, or restarts it if it runs
    function _startTimer(tx, name, milliseconds) {
        const ms = Math.max(0, Math.round(milliseconds));
        const token = _nextId(tx);
        const timers = Object.assign({}, tx.state.timers);
        timers[name] = { token: token, due: tx.now + ms };
        _setTop(tx, { timers: timers });
        _emit(tx, "startTimer", { name: name, ms: ms, token: token });
    }

    function _stopTimer(tx, name) {
        if (!Object.prototype.hasOwnProperty.call(tx.state.timers, name))
            return;
        const timers = Object.assign({}, tx.state.timers);
        delete timers[name];
        _setTop(tx, { timers: timers });
        _emit(tx, "stopTimer", { name: name });
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
            lockOnSleep: typeof given.lockOnSleep === "boolean" ? given.lockOnSleep : true,
            passwordFallback: _copyConfig(given.passwordFallback),
            timings: times
        };
    }

    // The regions that live for one lock, as each lock starts them
    function _freshLockRegions() {
        const passive = {};
        for (const method of passiveMethods) {
            passive[method.name] = {
                status: "unavailable", config: null, conversation: null, startedAt: null,
                delay: 0, lastResult: "", errors: 0, brokenBy: "", message: "", messageIsError: false,
                settling: false
            };
        }
        return {
            methods: { status: "unknown", generation: null, configs: {}, answered: false, waitForAnswer: false, passwordSource: "none" },
            password: {
                status: "idle", conversation: null, config: null, question: "", answerVisible: false,
                error: "", pamError: "", refusal: "", settling: false
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
        return copy;
    }
}
