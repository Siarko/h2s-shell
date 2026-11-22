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
//
// The layers below, each pure: LockStepRules (the constants, and the primitives every change
// of a state goes through), LockViewRules (view and describe*), LockParseRules (the methods
// script's and logind's lines). What callers use of them is forwarded here.
Singleton {
    id: root

    // The constants, from the layer below (LockStepRules, which says what each is for)
    readonly property var timings: LockStepRules.timings
    readonly property var limits: LockStepRules.limits
    readonly property var passiveMethods: LockStepRules.passiveMethods
    readonly property var namedKeys: LockStepRules.namedKeys
    readonly property var sleepTimers: LockStepRules.sleepTimers
    readonly property var timerNames: LockStepRules.timerNames

    // The unlocks by request, not by authentication — the owner's decision (plan, section
    // 5): logind's Unlock signal (`loginctl unlock-session`), the way in from another
    // console. An unlockRequested from any other source is refused.
    readonly property var unlockSources: ["logind"]

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
            settings: LockStepRules.settingsFrom(settings),
            phase: { status: "unlocked", session: 0, lastEnd: "", confirmLate: false, pending: null },
            sleep: { status: "awake", inhibitor: "released", minSuspendPassed: false },
            timers: {}
        }, LockStepRules.freshLockRegions());
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
            return LockStepRules.ignored(state, "unknown event");
        if (typeof now !== "number" || !isFinite(now))
            return LockStepRules.ignored(state, "no time");
        const transaction = { state: state, now: now, effects: [] };
        try {
            const refused = _handlers[type](transaction, event);
            if (typeof refused === "string")
                return LockStepRules.ignored(state, refused);
            _reconcile(transaction);
            return { state: transaction.state, effects: transaction.effects, ignored: "" };
        } catch (error) {
            return _internalError(state, event, now, error);
        }
    }

    // What the views render, and the state, events and effects as they may be shown
    // (LockViewRules)
    function view(state) {
        return LockViewRules.view(state);
    }

    function describe(state) {
        return LockViewRules.describe(state);
    }

    function describeEvent(event) {
        return LockViewRules.describeEvent(event);
    }

    function describeEffect(effect) {
        return LockViewRules.describeEffect(effect);
    }

    // What is running: conversations and timers (LockStepRules)
    function running(state) {
        return LockStepRules.running(state);
    }

    // The pause before a passive method's next round (LockStepRules)
    function retryDelay(previousDelay, roundMilliseconds, result, timingOverrides) {
        return LockStepRules.retryDelay(previousDelay, roundMilliseconds, result, timingOverrides);
    }

    // The methods script's lines and logind's, read (LockParseRules)
    function parseMethods(lines) {
        return LockParseRules.parseMethods(lines);
    }

    function parseLogind(line, sessionPath) {
        return LockParseRules.parseLogind(line, sessionPath);
    }

    function parseSessionPath(output) {
        return LockParseRules.parseSessionPath(output);
    }

    // ------------------------------------------------------------------------------------
    // Events, one handler each. A handler changes `transaction.state` through LockStepRules'
    // helpers and returns nothing, or a string saying why the event is ignored (its changes
    // are then dropped). `_reconcile` runs after every taken event.
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

    // Once, after initial(). Being a taken event, it runs _reconcile, which takes the sleep
    // inhibitor if the settings want it. It reports the session unlocked to logind: a hint
    // left true by a shell that crashed or was stopped while locked, or by a call that
    // failed, would otherwise stay so (a lock carried over a reload follows at once, as
    // `restored`, and its true wins before anything is sent)
    function _started(transaction, event) {
        LockStepRules.emit(transaction, "reportLockedHint", { locked: false });
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
        LockStepRules.setTop(transaction, Object.assign(LockStepRules.freshLockRegions(), {
            phase: { status: secure ? "locked" : "locking", session: session, lastEnd: "", confirmLate: false, pending: null }
        }));
        LockStepRules.emit(transaction, "adoptCompositorLock", { session: session });
        LockStepRules.emit(transaction, "announceLocked", { locked: true });
        if (secure)
            LockStepRules.emit(transaction, "reportLockedHint", { locked: true });
        LockStepRules.log(transaction, "info", "the compositor's lock carried over (" + (secure ? "confirmed" : "not confirmed yet")
            + "): locked as session " + session + ", a new authentication needed");
        if (!secure)
            LockStepRules.startTimer(transaction, "confirm", transaction.state.settings.timings.confirm);
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
        LockStepRules.stopTimer(transaction, "confirm");
        // On the way to sleep the inhibitor was held for exactly this
        if (transaction.state.sleep.status === "suspending" && transaction.state.sleep.inhibitor === "held")
            _releaseInhibitor(transaction);
        if (phase.status === "unlocking") {
            LockStepRules.log(transaction, "info", "the compositor confirmed the lock: carrying out the pending unlock (" + phase.pending.reason + ")");
            _leaveLock(transaction, phase.pending.reason, phase.pending.method, true);
            return;
        }
        LockStepRules.setRegion(transaction, "phase", { status: "locked" });
        // The system is told only of a lock the compositor holds (logind's LockedHint, which
        // programs that lock themselves with the session follow)
        LockStepRules.emit(transaction, "reportLockedHint", { locked: true });
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
        LockStepRules.log(transaction, "warning", "the compositor refused the lock"
            + (phase.status === "unlocking" ? " (an unlock by " + phase.pending.reason + " was waiting for it)" : ""));
        _leaveLock(transaction, "denied", "", false);
        // Another program's session lock is the usual cause: the driver looks (foreignStep)
        LockStepRules.emit(transaction, "checkForeignLock", {});
    }

    // The lock's first effects are always lockCompositor and announceLocked(true), whatever
    // the event did before (a sleep's timers): the lock is what matters most on the way down
    function _enterLock(transaction, source) {
        const session = transaction.state.phase.session + 1;
        const before = transaction.effects;
        transaction.effects = [];
        LockStepRules.setTop(transaction, Object.assign(LockStepRules.freshLockRegions(), {
            phase: { status: "locking", session: session, lastEnd: "", confirmLate: false, pending: null }
        }));
        LockStepRules.emit(transaction, "lockCompositor", { session: session });
        LockStepRules.emit(transaction, "announceLocked", { locked: true });
        transaction.effects = transaction.effects.concat(before);
        LockStepRules.log(transaction, "info", "locking (" + (source || "request") + "), session " + session);
        LockStepRules.startTimer(transaction, "confirm", transaction.state.settings.timings.confirm);
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
        LockStepRules.setRegion(transaction, "phase", { confirmLate: true });
        LockStepRules.log(transaction, "warning", "the compositor has not confirmed the lock after " + transaction.state.settings.timings.confirm
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
        LockStepRules.setTop(transaction, Object.assign(LockStepRules.freshLockRegions(), {
            phase: Object.assign({}, transaction.state.phase, { status: "unlocking", pending: { reason: reason, method: method || "" } }),
            // The surfaces are still there; the prompt stays where it is, saying "Unlocking…"
            prompt: { surfaces: prompt.surfaces, owner: prompt.owner, awakeUntil: null, fieldEpoch: prompt.fieldEpoch + 1 }
        }));
        LockStepRules.log(transaction, "info", "unlock (" + reason + (method ? ", " + method : "") + ") decided before the compositor confirmed the lock: "
            + "waiting for its confirmation, session " + transaction.state.phase.session);
    }

    // A lock request (or a sleep) while an unlock waits for the compositor: the lock stays,
    // as fresh as a new one — the methods asked again, and getting in needs a new
    // authentication. The compositor's lock is the same one, still in force: nothing is
    // set again, and nothing announced.
    function _cancelPendingUnlock(transaction, why) {
        const pending = transaction.state.phase.pending;
        const prompt = transaction.state.prompt;
        LockStepRules.setTop(transaction, Object.assign(LockStepRules.freshLockRegions(), {
            phase: Object.assign({}, transaction.state.phase, { status: "locking", pending: null }),
            prompt: { surfaces: prompt.surfaces, owner: null, awakeUntil: null, fieldEpoch: prompt.fieldEpoch + 1 }
        }));
        LockStepRules.log(transaction, "info", "the pending unlock (" + pending.reason + ") is dropped by " + why
            + ": the screen stays locked, a new authentication is needed");
        _detect(transaction, true);
    }

    // Aborts every conversation and stops every timer of the lock — but the confirm timer,
    // which runs for as long as the compositor's word is awaited
    function _windDown(transaction) {
        for (const conversation of LockStepRules.running(transaction.state).conversations)
            LockStepRules.emit(transaction, "abortPam", { method: conversation.method, conversation: conversation.conversation });
        for (const name of LockStepRules.running(transaction.state).lockTimers) {
            if (name !== "confirm" || transaction.state.phase.status === "locked")
                LockStepRules.stopTimer(transaction, name);
        }
    }

    // Every way out of the lock goes through here: conversations aborted, the lock's
    // timers stopped, the secret dropped, the lock's regions thrown away — so nothing of
    // this lock reaches the next one (defects 6 and the root cause in section 1).
    // `unlock`: the compositor's lock is to be unlocked (it confirmed this session); false
    // when the compositor itself ended or refused it.
    function _leaveLock(transaction, reason, method, unlock) {
        _windDown(transaction);
        LockStepRules.stopTimer(transaction, "confirm");
        // Held for the lock on the way to sleep: there is no lock to wait for any more
        if (transaction.state.sleep.status === "suspending" && transaction.state.sleep.inhibitor === "held")
            _releaseInhibitor(transaction);
        const session = transaction.state.phase.session;
        // Reported locked exactly when the phase was "locked" (confirmed, no unlock pending)
        const hinted = transaction.state.phase.status === "locked";
        LockStepRules.setTop(transaction, Object.assign(LockStepRules.freshLockRegions(), {
            phase: { status: "unlocked", session: session, lastEnd: reason, confirmLate: false, pending: null }
        }));
        if (unlock) {
            const fields = { session: session, reason: reason };
            if (method)
                fields.method = method;
            LockStepRules.emit(transaction, "unlockCompositor", fields);
        }
        LockStepRules.emit(transaction, "announceLocked", { locked: false });
        if (hinted)
            LockStepRules.emit(transaction, "reportLockedHint", { locked: false });
        LockStepRules.log(transaction, "info", (unlock ? "unlocked (" : "the lock ended (") + reason + (method ? ", " + method : "") + "), session " + session);
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
        if (!LockStepRules.isSurfaceId(event.surface))
            return "no surface";
        if (typeof event.screen !== "string" || event.screen === "")
            return "no screen";
        if (LockStepRules.findSurface(transaction.state, event.surface) !== undefined)
            return "surface already known";
        LockStepRules.setRegion(transaction, "prompt", { surfaces: transaction.state.prompt.surfaces.concat([{ id: event.surface, screen: event.screen }]) });
    }

    // A surface going away that owned the prompt hands it on, awake, the question (if any)
    // kept — it is in the state, not the view: to the NEWEST other instance on the same
    // screen (its successor; an older one there is one being destroyed), else to the first
    // surface left. With none left the prompt sleeps. The old code left the prompt "active"
    // on a surface that no longer existed: the screen that came back never woke.
    function _surfaceRemoved(transaction, event) {
        if (transaction.state.phase.status === "unlocked")
            return "not locked";
        const removed = LockStepRules.findSurface(transaction.state, event.surface);
        if (removed === undefined)
            return "unknown surface";
        const remaining = transaction.state.prompt.surfaces.filter(surface => surface !== removed);
        LockStepRules.setRegion(transaction, "prompt", { surfaces: remaining });
        if (transaction.state.prompt.owner !== removed.id)
            return;
        if (remaining.length === 0) {
            _sleepPrompt(transaction);
            return;
        }
        const sameScreen = remaining.filter(surface => surface.screen === removed.screen);
        const heir = sameScreen.length > 0 ? sameScreen[sameScreen.length - 1] : remaining[0];
        LockStepRules.setRegion(transaction, "prompt", { owner: heir.id, fieldEpoch: transaction.state.prompt.fieldEpoch + 1 });
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
            LockStepRules.setRegion(transaction, "prompt", { owner: event.surface, fieldEpoch: transaction.state.prompt.fieldEpoch + 1 });
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
            LockStepRules.emit(transaction, "forwardKey", { surface: transaction.state.prompt.owner, key: key, text: text });
    }

    function _checkSurface(state, surface) {
        if (state.phase.status === "unlocked")
            return "not locked";
        // A surface reports itself before any input (surfaceAdded); one not known is one
        // already gone, whose event was still queued
        if (LockStepRules.findSurface(state, surface) === undefined)
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
            LockStepRules.setRegion(transaction, "prompt", { awakeUntil: transaction.now + times.prompt });
            return;
        }
        LockStepRules.setRegion(transaction, "prompt", { owner: surface, awakeUntil: transaction.now + times.prompt });
        LockStepRules.startTimer(transaction, "prompt", times.prompt);
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
                LockStepRules.stopTimer(transaction, "retry:" + method.name);
                LockStepRules.setPassive(transaction, method.name, { status: "idle" });
            } else if (passive.status === "broken" && passive.brokenBy === "error" && passive.revivals < limits.revivals) {
                // Another Error breaks it again at once (errors stays at the limit)
                LockStepRules.setPassive(transaction, method.name, { status: "idle", brokenBy: "", revivals: passive.revivals + 1 });
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
        if (methods.status !== "known" || !LockStepRules.anyPassive(transaction.state, "unavailable"))
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
        LockStepRules.stopTimer(transaction, "prompt");
        LockStepRules.setRegion(transaction, "prompt", { owner: null, awakeUntil: null, fieldEpoch: transaction.state.prompt.fieldEpoch + 1 });
        const password = transaction.state.password;
        if (password.status === "asking") {
            _abort(transaction, "password");
            LockStepRules.setRegion(transaction, "password", { status: "idle", question: "", answerVisible: false, pamError: "" });
        } else if (password.status === "failed" || password.status === "unavailable") {
            LockStepRules.setRegion(transaction, "password", { status: "idle", error: "", pamError: "" });
        }
        LockStepRules.setRegion(transaction, "password", { refusal: "" });
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
        LockStepRules.setRegion(transaction, "prompt", { awakeUntil: transaction.now + transaction.state.settings.timings.prompt });
        if (password.status === "asking") {
            // At most one answer per prompt: PamContext hands a second respond() to the
            // next prompt. After this the state is "verifying" and a submit is refused.
            LockStepRules.emit(transaction, "respondPam", { method: "password", conversation: password.conversation.id, text: text });
            LockStepRules.setRegion(transaction, "password", { status: "verifying", question: "", answerVisible: false, refusal: "" });
            _takeInput(transaction);
            return;
        }
        if (password.status === "pending" || password.status === "verifying") {
            LockStepRules.setRegion(transaction, "password", { refusal: "busy" });
            return;
        }
        // An empty password is never sent: with `nullok` it could unlock (defect 13), and
        // an Enter forwarded right after waking would otherwise count as a failed attempt
        if (text === "") {
            LockStepRules.setRegion(transaction, "password", { refusal: "empty" });
            return;
        }
        // Held until PAM asks for it — the conversation may not be startable yet (methods
        // unknown, an abort settling); _reconcilePassword starts it
        LockStepRules.setTop(transaction, { secret: text });
        LockStepRules.setRegion(transaction, "password", { status: "pending", error: "", pamError: "", refusal: "" });
        _takeInput(transaction);
        // No password config known: the script is asked again before saying so (a config
        // that appeared since, or a detection that came back empty)
        if (transaction.state.methods.status === "known" && !transaction.state.methods.configs.password)
            _detect(transaction, false);
    }

    function _takeInput(transaction) {
        LockStepRules.setRegion(transaction, "prompt", { fieldEpoch: transaction.state.prompt.fieldEpoch + 1 });
    }

    // The password's conversation is over without success: secret dropped, nothing asked,
    // `status` (failed / unavailable) with `error` shown
    function _passwordEnded(transaction, status, error) {
        LockStepRules.setTop(transaction, { secret: null });
        LockStepRules.setRegion(transaction, "password", { status: status, conversation: null, question: "", answerVisible: false, refusal: "", error: error });
    }

    // A submitted password with no answer from PAM in `timings.verify`: a hung module, a
    // start that never came. Without this the owner could not try again for the rest of
    // the lock (the prompt's sleep deliberately never aborts a verification).
    function _verifyTimedOut(transaction) {
        const status = transaction.state.password.status;
        if (status !== "pending" && status !== "verifying")
            return;
        LockStepRules.log(transaction, "warning", "the password check did not answer in time: aborted");
        _abort(transaction, "password");
        _passwordEnded(transaction, "failed", "Password check timed out");
    }

    // ---- Methods ----

    // Asks which methods there are. A newer request supersedes an older one: its answer
    // carries an older generation and is ignored. `waitForAnswer`: passive methods wait for
    // this answer (at the lock, and after a wake — then the reader's service may have
    // changed); otherwise the configs known so far serve meanwhile.
    function _detect(transaction, waitForAnswer) {
        const generation = LockStepRules.nextId(transaction);
        LockStepRules.setRegion(transaction, "methods", { status: "detecting", generation: generation, waitForAnswer: waitForAnswer, askedAt: transaction.now });
        LockStepRules.emit(transaction, "detectMethods", { generation: generation });
        LockStepRules.startTimer(transaction, "detect", transaction.state.settings.timings.detect);
    }

    function _methodsDetected(transaction, event) {
        const refused = _checkDetection(transaction.state, event);
        if (refused !== "")
            return refused;
        _applyDetection(transaction, LockParseRules.parseMethods(event.lines), "answered");
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
        LockStepRules.stopTimer(transaction, "detect");
        const detectedPassword = LockStepRules.copyConfig(found.password);
        const fallback = transaction.state.settings.passwordFallback;
        const configs = { password: detectedPassword ?? fallback ?? null };
        for (const method of passiveMethods)
            configs[method.name] = LockStepRules.copyConfig(found[method.name]);
        LockStepRules.setRegion(transaction, "methods", {
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
                LockStepRules.setPassive(transaction, method.name, { status: "unavailable" });
            } else if (config === null && passive.status === "backoff") {
                LockStepRules.stopTimer(transaction, "retry:" + method.name);
                LockStepRules.setPassive(transaction, method.name, { status: "unavailable" });
            }
            LockStepRules.setPassive(transaction, method.name, { config: config });
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
        LockStepRules.log(transaction, "warning", "detecting the methods " + reason + "; going on with "
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
            LockStepRules.setPassive(transaction, event.method, { message: message, messageIsError: event.messageIsError === true });
        // Nothing is typed for a passive method. A prompt asking for input means a config
        // that is not passive (a password module, pam_u2f's "interactive") — and the old
        // empty answer, repeated every round, was a failed password attempt each time
        // (defect 12): faillock locks the account. So the method stops, broken for this
        // lock, and says so.
        if (event.responseRequired === true) {
            _abort(transaction, event.method);
            LockStepRules.setPassive(transaction, event.method, { status: "broken", brokenBy: "asks", message: "", messageIsError: false });
            LockStepRules.log(transaction, "warning", event.method + " asks for input, which a passive method never gives: not used");
        }
    }

    function _passwordMessage(transaction, event, message) {
        if (event.responseRequired !== true) {
            // PAM knows why it says no (an account locked, a password expired): shown on
            // failure instead of a plain "failed"
            if (event.messageIsError === true && message !== "")
                LockStepRules.setRegion(transaction, "password", { pamError: message });
            return;
        }
        const secret = transaction.state.secret;
        // The typed password answers the first prompt that hides its answer. A prompt that
        // shows it is no password prompt: the password is dropped, not shown, and the
        // question asked.
        if (secret !== null && event.responseVisible !== true) {
            LockStepRules.emit(transaction, "respondPam", { method: "password", conversation: transaction.state.password.conversation.id, text: secret });
            LockStepRules.setTop(transaction, { secret: null });
            return;
        }
        LockStepRules.setTop(transaction, { secret: null });
        LockStepRules.setRegion(transaction, "password", {
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
            LockStepRules.log(transaction, "warning", "password not accepted (" + result + "), PAM config " + LockStepRules.where(password.config));
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
        const delay = LockStepRules.retryDelay(passive.delay, transaction.now - passive.startedAt, result, transaction.state.settings.timings);
        LockStepRules.setPassive(transaction, method, { status: "backoff", conversation: null, errors: 0, delay: delay, lastResult: result });
        LockStepRules.startTimer(transaction, "retry:" + method, delay);
    }

    // Quickshell's Error is every PAM code but success, auth error and max tries: a module
    // missing (for good) or a device not there yet (for now). A long wait, and broken only
    // after several in a row.
    function _passiveErred(transaction, method) {
        const passive = transaction.state.passive[method];
        const errors = passive.errors + 1;
        if (errors >= limits.errorLimit) {
            LockStepRules.log(transaction, "warning", method + " cannot be used (" + errors + " errors in a row), PAM config " + LockStepRules.where(passive.config));
            LockStepRules.setPassive(transaction, method, { status: "broken", brokenBy: "error", conversation: null, errors: errors, lastResult: "error" });
            return;
        }
        const wait = transaction.state.settings.timings.errorRetry;
        LockStepRules.log(transaction, "warning", method + ": PAM error (" + errors + " of " + limits.errorLimit + "), trying again later");
        LockStepRules.setPassive(transaction, method, { status: "backoff", conversation: null, errors: errors, delay: wait, lastResult: "error" });
        LockStepRules.startTimer(transaction, "retry:" + method, wait);
    }

    // A full-length round that ended in Error: nobody tried, the reader is fine. Not
    // counted, and it resets the count (as any result but a quick Error does); the next
    // round starts after `retryMin` — the shortest wait, as after a full-length failed
    // round. A completion is no abort, so no settle; the round ends by its retry timer,
    // never in this step.
    function _passiveTimedOut(transaction, method) {
        const wait = transaction.state.settings.timings.retryMin;
        LockStepRules.setPassive(transaction, method, { status: "backoff", conversation: null, errors: 0, delay: wait, lastResult: "timeout" });
        LockStepRules.startTimer(transaction, "retry:" + method, wait);
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
        LockStepRules.setRegion(transaction, "password", { avoid: LockStepRules.copyConfig(config) });
        if (transaction.state.methods.status !== "detecting")
            _detect(transaction, false);
    }

    // PamContext.start() refused (a config that is not there): reported by the driver,
    // since start() says so only through its return value. Visible, never "verifying".
    function _pamStartFailed(transaction, event) {
        const refused = _checkConversation(transaction.state, event);
        if (refused !== "")
            return refused;
        LockStepRules.log(transaction, "warning", event.method + ": PAM refused to start the conversation");
        if (event.method === "password") {
            _passwordConfigFailed(transaction);
            _passwordEnded(transaction, "unavailable", "Password check could not start");
        } else {
            LockStepRules.setPassive(transaction, event.method, { status: "broken", brokenBy: "start", conversation: null });
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
                LockStepRules.log(transaction, "error", _withoutSecret("internal error on " + what + ": the conversation is ended, its result not believed", state));
                _reconcile(transaction);
                return { state: transaction.state, effects: transaction.effects, ignored: "", error: true };
            } catch (again) {
                const transaction = { state: state, now: now, effects: [] };
                if (method === "password")
                    _passwordEnded(transaction, "failed", "Password check failed, try again");
                else
                    LockStepRules.setPassive(transaction, method, { status: "broken", brokenBy: "internal", conversation: null });
                LockStepRules.log(transaction, "error", _withoutSecret("internal error on " + what + ", and again while ending it: the conversation is ended", state));
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
            LockStepRules.log(transaction, "warning", "PrepareForSleep while suspending: the resume signal was missed");
            _resume(transaction, false);
        }
        if (transaction.state.phase.status === "unlocking")
            _cancelPendingUnlock(transaction, "going to sleep");
        if (transaction.state.phase.status === "unlocked" && transaction.state.settings.lockOnSleep)
            _enterLock(transaction, "sleep");
        const held = transaction.state.sleep.inhibitor === "held";
        LockStepRules.stopTimer(transaction, "resumeGrace");
        LockStepRules.setRegion(transaction, "sleep", { status: "suspending", minSuspendPassed: false });
        LockStepRules.startTimer(transaction, "missedResume", times.missedResume);
        LockStepRules.startTimer(transaction, "minSuspend", times.minSuspend);
        if (!held)
            return;
        // logind waits while the inhibitor is held: until the compositor confirms the lock,
        // or the fallback lets the machine go
        if (transaction.state.phase.status === "locking")
            LockStepRules.startTimer(transaction, "inhibitor", times.inhibitorFallback);
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
        LockStepRules.stopTimer(transaction, "missedResume");
        LockStepRules.stopTimer(transaction, "minSuspend");
        LockStepRules.stopTimer(transaction, "inhibitor");
        LockStepRules.setRegion(transaction, "sleep", { status: "resuming", minSuspendPassed: false });
        if (grace)
            LockStepRules.startTimer(transaction, "resumeGrace", times.resumeGrace);
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
                LockStepRules.stopTimer(transaction, "retry:" + method.name);
            if (status === "running" || status === "backoff" || status === "broken")
                LockStepRules.setPassive(transaction, method.name, { status: "idle", brokenBy: "" });
            LockStepRules.setPassive(transaction, method.name, { errors: 0, revivals: 0 });
        }
        _detect(transaction, true);
    }

    // The resume signal was lost: activity after `minSuspend` of running time since going
    // down means the machine is up
    function _recoverSleep(transaction) {
        const sleep = transaction.state.sleep;
        if (sleep.status === "suspending" && sleep.minSuspendPassed) {
            LockStepRules.log(transaction, "warning", "activity while suspending: the resume signal was missed");
            _resume(transaction, true);
        }
    }

    function _releaseInhibitor(transaction) {
        LockStepRules.stopTimer(transaction, "inhibitor");
        if (transaction.state.sleep.inhibitor !== "held")
            return;
        LockStepRules.setRegion(transaction, "sleep", { inhibitor: "released" });
        LockStepRules.emit(transaction, "releaseInhibitor", {});
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
        LockStepRules.setTop(transaction, { timers: timers });
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
                LockStepRules.setRegion(transaction, "prompt", { awakeUntil: transaction.now + left });
                LockStepRules.startTimer(transaction, "prompt", left);
            } else {
                root._sleepPrompt(transaction);
            }
        },
        inhibitor: transaction => {
            if (transaction.state.sleep.inhibitor === "held") {
                LockStepRules.log(transaction, "warning", "the compositor did not confirm the lock in time: letting the machine sleep");
                root._releaseInhibitor(transaction);
            }
        },
        missedResume: transaction => {
            if (transaction.state.sleep.status === "suspending") {
                LockStepRules.log(transaction, "warning", "no resume signal: going on as awake");
                root._resume(transaction, true);
            }
        },
        minSuspend: transaction => {
            if (transaction.state.sleep.status === "suspending")
                LockStepRules.setRegion(transaction, "sleep", { minSuspendPassed: true });
        },
        resumeGrace: transaction => {
            LockStepRules.setRegion(transaction, "sleep", { status: "awake" });
            if (root._authenticating(transaction.state))
                root._redetectIfMissing(transaction, false);
        },
        retry: (transaction, method) => {
            if (transaction.state.passive[method]?.status === "backoff")
                LockStepRules.setPassive(transaction, method, { status: "idle" });
        },
        settle: (transaction, method) => {
            if (method === "password")
                LockStepRules.setRegion(transaction, "password", { settling: false });
            else if (transaction.state.passive[method])
                LockStepRules.setPassive(transaction, method, { settling: false });
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
        if (values.passwordFallback === null || LockStepRules.isConfig(values.passwordFallback))
            changes.passwordFallback = LockStepRules.copyConfig(values.passwordFallback);
        if (Object.keys(changes).length === 0)
            return "no known setting";
        LockStepRules.setRegion(transaction, "settings", changes);
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
            LockStepRules.startTimer(transaction, "verify", transaction.state.settings.timings.verify);
        else if (!busy)
            LockStepRules.stopTimer(transaction, "verify");
    }

    // Held while awake with lockOnSleep, so that logind waits for the lock before sleep;
    // taken again after every wake (the old code lost it for good once released)
    function _reconcileInhibitor(transaction) {
        const sleep = transaction.state.sleep;
        const lockOnSleep = transaction.state.settings.lockOnSleep;
        if (sleep.inhibitor === "held" && !lockOnSleep) {
            _releaseInhibitor(transaction);
        } else if (sleep.inhibitor !== "held" && lockOnSleep && sleep.status !== "suspending") {
            LockStepRules.setRegion(transaction, "sleep", { inhibitor: "held" });
            LockStepRules.emit(transaction, "holdInhibitor", {});
        }
    }

    function _reconcilePassive(transaction, name) {
        const suspending = transaction.state.sleep.status === "suspending";
        let passive = transaction.state.passive[name];
        if (passive.status === "running") {
            if (suspending) {
                _abort(transaction, name);
                LockStepRules.setPassive(transaction, name, { status: "paused" });
            }
            return;
        }
        if (passive.status === "backoff") {
            if (!suspending)
                return;
            LockStepRules.stopTimer(transaction, "retry:" + name);
        }
        if (passive.status === "broken")
            return;
        passive = transaction.state.passive[name];
        const status = passive.config === null ? "unavailable" : suspending ? "paused" : "idle";
        if (status !== passive.status)
            LockStepRules.setPassive(transaction, name, { status: status });
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
            const id = LockStepRules.nextId(transaction);
            LockStepRules.setRegion(transaction, "password", { status: "verifying", conversation: { id: id, session: transaction.state.phase.session }, config: config });
            LockStepRules.emit(transaction, "startPam", { method: "password", conversation: id, configDirectory: config.directory, config: config.config });
        } else if (transaction.state.methods.status === "known") {
            LockStepRules.log(transaction, "warning", "no password config: the password cannot be checked");
            _passwordEnded(transaction, "unavailable", "Password check is not available");
        }
    }

    // The password config for the next conversation: the known one (detected, else the
    // fallback) — unless it is the one that could not be used in this lock
    // (password.avoid), and the fallback is another: then the fallback
    function _passwordConfig(state) {
        const known = LockStepRules.copyConfig(state.methods.configs.password);
        const avoid = state.password.avoid;
        const fallback = state.settings.passwordFallback;
        if (known !== null && avoid !== null && LockStepRules.sameConfig(known, avoid) && fallback && !LockStepRules.sameConfig(fallback, avoid))
            return LockStepRules.copyConfig(fallback);
        return known;
    }

    function _startPassive(transaction, name) {
        const passive = transaction.state.passive[name];
        const id = LockStepRules.nextId(transaction);
        LockStepRules.setPassive(transaction, name, {
            status: "running",
            conversation: { id: id, session: transaction.state.phase.session },
            startedAt: transaction.now,
            message: "",
            messageIsError: false
        });
        LockStepRules.emit(transaction, "startPam", { method: name, conversation: id, configDirectory: passive.config.directory, config: passive.config.config });
    }

    // Aborts a method's conversation within the lock. PamContext kills the child only at
    // the next event-loop pass: the method is not started again until its settle timer
    // has run — never in the step that aborts it.
    function _abort(transaction, method) {
        const region = method === "password" ? transaction.state.password : transaction.state.passive[method];
        if (region.conversation === null)
            return;
        LockStepRules.emit(transaction, "abortPam", { method: method, conversation: region.conversation.id });
        if (method === "password")
            LockStepRules.setRegion(transaction, "password", { conversation: null, settling: true });
        else
            LockStepRules.setPassive(transaction, method, { conversation: null, settling: true });
        LockStepRules.startTimer(transaction, "settle:" + method, transaction.state.settings.timings.settle);
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

    // ------------------------------------------------------------------------------------
    // Another program's session lock (notes/plans/idle-lock-flow.md §10)
    // ------------------------------------------------------------------------------------
    // Wayland shows no client another's session lock; the compositor refuses ours while one
    // is in force. On Hyprland `hyprctl -j locked` tells (`canRead`); elsewhere only the
    // refusal does, and the idle lock's growing pause (IdleRules) stands in for a poll. A
    // lock read as held counts as the session locked (the `screen.locked` fact, no idle
    // lock) and is read again after a growing pause until it ends.
    //
    //   foreignInitial()                       → state
    //   foreignStep(state, event, settings)    → { state, actions, ignored }
    //
    // `settings`: { canRead (the compositor can be asked: Hyprland), pollMaximum (the longest
    // pause between reads, ms; foreignPoll.maximum when not a positive number) }.
    //
    // Events: lockWanted { source } (a lock that waits for the read: the idle lock),
    // refused (the compositor refused ours: checkForeignLock), pollDue, answer { serial,
    // outcome: "locked" | "unlocked" | "unknown", ownLock: the shell has a lock asked or
    // held }, ownLocked (the compositor confirmed the shell's own lock). Actions: read
    // { serial }, held { held }, poll { ms }, lock { source }, log { level, message }.

    readonly property var foreignPoll: ({ minimum: 1000, maximum: 30000 })

    function foreignInitial() {
        return { held: false, reading: 0, serial: 0, polls: 0, pendingLock: "", told: "" };
    }

    // The pause before the n-th read again of a held lock: doubling, bounded
    function foreignPollDelay(polls, maximum) {
        const bound = typeof maximum === "number" && isFinite(maximum) && maximum > 0 ? maximum : foreignPoll.maximum;
        return Math.min(bound, foreignPoll.minimum * Math.pow(2, Math.max(0, polls - 1)));
    }

    function foreignStep(state, event, settings) {
        const canRead = settings?.canRead === true;
        const next = Object.assign({}, state);
        const actions = [];
        const read = () => {
            next.serial++;
            next.reading = next.serial;
            actions.push({ type: "read", serial: next.reading });
        };
        const tell = (key, level, message) => {
            if (next.told === key)
                return;
            next.told = key;
            actions.push({ type: "log", level: level, message: message });
        };
        const poll = () => {
            next.polls++;
            actions.push({ type: "poll", ms: foreignPollDelay(next.polls, settings?.pollMaximum) });
        };
        const release = () => {
            next.held = false;
            next.polls = 0;
            actions.push({ type: "held", held: false });
        };
        switch (event?.type) {
        case "lockWanted": {
            const source = typeof event.source === "string" && event.source !== "" ? event.source : "request";
            if (next.held)
                return { state: state, actions: [], ignored: "another program holds the session lock" };
            if (!canRead) {
                actions.push({ type: "lock", source: source });
                break;
            }
            next.pendingLock = source;
            if (next.reading === 0)
                read();
            break;
        }
        case "refused":
            if (!canRead || next.held || next.reading !== 0)
                return { state: state, actions: [], ignored: !canRead ? "cannot read the compositor's lock" : "already known or being read" };
            read();
            break;
        case "pollDue":
            if (!next.held || next.reading !== 0)
                return { state: state, actions: [], ignored: "nothing to poll" };
            read();
            break;
        case "answer": {
            // Late answers lose: one read counts, the last asked
            if (next.reading === 0 || event.serial !== next.reading)
                return { state: state, actions: [], ignored: "late answer" };
            next.reading = 0;
            const pending = next.pendingLock;
            next.pendingLock = "";
            // A lock of the shell's own asked meanwhile: whatever Hyprland says is ours
            if (event.ownLock === true) {
                if (next.held)
                    release();
                break;
            }
            if (event.outcome === "locked") {
                if (!next.held) {
                    next.held = true;
                    next.polls = 0;
                    actions.push({ type: "held", held: true });
                }
                tell("held", "info", "another program holds the session lock: the shell counts the session locked and asks no lock of its own while it lasts");
                poll();
            } else if (event.outcome === "unlocked") {
                if (next.held) {
                    release();
                    tell("ended", "info", "the other program's session lock ended");
                }
                if (pending !== "")
                    actions.push({ type: "lock", source: pending });
            } else {
                // Unknown is not proof either way: a held lock stays held (read again later),
                // a lock wanted is asked for, as without Hyprland
                tell("unknown", "warning", "could not read whether the compositor holds a session lock" + (next.held ? ": still counted as held" : ""));
                if (next.held)
                    poll();
                else if (pending !== "")
                    actions.push({ type: "lock", source: pending });
            }
            break;
        }
        case "ownLocked":
            if (!next.held && next.reading === 0 && next.pendingLock === "")
                return { state: state, actions: [], ignored: "no other lock known" };
            // Only one session lock at a time: the other one is over, and a read under way
            // would see ours
            next.reading = 0;
            next.pendingLock = "";
            if (next.held)
                release();
            next.told = "";
            break;
        default:
            return { state: state, actions: [], ignored: "unknown event" };
        }
        return { state: next, actions: actions, ignored: "" };
    }
}
