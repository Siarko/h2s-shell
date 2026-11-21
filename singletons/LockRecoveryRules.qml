pragma Singleton

import Quickshell
import QtQuick

// The lock's recovery decisions (Lockscreen, "Recovery"; notes/plans/lockscreen.md, section
// 7): the lock marker, taking a lock back after the shell stopped while locked, and asking
// again while the compositor refuses it. Pure, like LockRules: the driver holds the one
// state, feeds events in and carries the effects out (tests/LockRecoveryRulesTest.qml).
//
//   initial(settings)       → state
//   withCarried(state, ...) → the state with what a reload carries over, as it is now
//   step(state, event)      → { state, effects }
//
// `settings`: { markerUsable (XDG_RUNTIME_DIR is set: there is a marker, and the launcher's
// record of restarts beside it), hyprland (the shell runs under Hyprland, which is asked
// before a lock is taken back), runtimeDirectory (for a log line) }.
//
// The state: `key` (this compositor session's, "?" until the start probe has answered — a
// marker with "?" counts as this session's: fail closed), `marker` (as last written:
// "locked", "unlocked", "" for none yet), `restoring` (the lock in force or asked for is one
// the marker asked to take back, until the compositor confirms it), `restorePending` (the
// compositor holds that lock and refuses to give it back), `restoreDelay`, `refusalLogged`,
// `checked` (the start has read the marker, or there is none to read), and `carried` — what
// a reload hands the next generation (Lockscreen's `_carried`): `held` (this process has a
// compositor lock, asked for or confirmed), `secure` (the compositor confirmed it),
// `markerUnlockPending` (a lock ended and the marker's "unlocked" is still to be written).
//
// Events (`locked`: the lock rules' phase is not "unlocked" at that moment):
//   started                         the driver is built
//   markerAnswered { lines, locked } the start probe's lines (LockIoRules.markerFacts)
//   markerChecked                   after markerAnswered: the start's decision is made
//   lockAsked                       the driver is about to set the compositor's lock
//   lockRefused { session }         … and Quickshell refused it at once
//   lockTaken                       … and it was taken
//   lockAdopted                     a reload carried the compositor's lock over
//   carriedChecked { locked, compositorLocked }  after Quickshell realized the new lock
//   confirmed                       the compositor confirmed the lock (secure)
//   ended { locked, lastEnd }       a step of the lock rules ended unlocked
//   markerUnlockDue { locked }      the pause before the marker's "unlocked" is over
//   restoreRetry { locked }         the pause before asking for the lock back again is over
//   restoreAnswered { output, locked }  Hyprland's word (LockIoRules.hyprlandLockFacts)
//   lockWanted { source, locked }   lock() was called
//
// Effects: probeMarker; probeRestore (unless running); requestLock { source } (the lock
// rules' lockRequested; always a step's last effect, since it may come back here at once);
// writeMarker { text }; resetLockRestarts (the launcher's record overwritten: the session
// is unlocked); startTimer { name: "restoreRetry", ms }; startMarkerUnlockDelay (unless
// running); stopTimer { name: "markerUnlock" | "restoreRetry" }; compositorFinished
// { session } (the lock rules' event); checkCarriedLater (carriedChecked, once Quickshell
// has realized the new lock); exit (quit with a failure: the launcher starts a fresh shell,
// the marker locks it); log { level, message }.
Singleton {
    id: root

    // Taking the lock back after the compositor refused it: 5 s, doubling up to a minute
    // (under Hyprland each attempt is first a question to it — cheap, and asking for the lock
    // only once it would be given)
    readonly property var restoreTable: ({ minimum: 5000, maximum: 60000, healthyRun: Infinity })

    function initial(settings) {
        return {
            markerUsable: settings?.markerUsable === true,
            hyprland: settings?.hyprland === true,
            runtimeDirectory: String(settings?.runtimeDirectory ?? ""),
            key: "?",
            marker: "",
            restoring: false,
            restorePending: false,
            restoreDelay: 0,
            refusalLogged: false,
            checked: false,
            carried: { held: false, secure: false, markerUnlockPending: false }
        };
    }

    // What a reload carries over lives outside the state (a PersistentProperties, which
    // Quickshell fills from the old generation): read into it before each step
    function withCarried(state, carried) {
        return Object.assign({}, state, { carried: {
            held: carried?.held === true,
            secure: carried?.secure === true,
            markerUnlockPending: carried?.markerUnlockPending === true
        } });
    }

    // → { state, effects }. An unknown event changes nothing
    function step(state, event) {
        const transaction = { state: state, effects: [] };
        const type = event?.type;
        if (typeof type === "string" && Object.prototype.hasOwnProperty.call(_handlers, type))
            _handlers[type](transaction, event);
        return { state: transaction.state, effects: transaction.effects };
    }

    readonly property var _handlers: ({
        started: (transaction, event) => root._started(transaction),
        markerAnswered: (transaction, event) => root._markerAnswered(transaction, event),
        markerChecked: (transaction, event) => root._set(transaction, { checked: true }),
        lockAsked: (transaction, event) => {
            // The marker first: a shell that dies from here on comes back locked
            root._writeMarker(transaction, "locked");
            root._setCarried(transaction, { secure: false });
        },
        lockRefused: (transaction, event) => root._lockRefused(transaction, event),
        lockTaken: (transaction, event) => root._setCarried(transaction, { held: true }),
        lockAdopted: (transaction, event) => {
            root._setCarried(transaction, { held: true });
            root._writeMarker(transaction, "locked");
            root._emit(transaction, "checkCarriedLater", {});
        },
        carriedChecked: (transaction, event) => root._carriedChecked(transaction, event),
        confirmed: (transaction, event) => root._confirmed(transaction),
        ended: (transaction, event) => root._ended(transaction, event),
        markerUnlockDue: (transaction, event) => root._markerUnlockDue(transaction, event),
        restoreRetry: (transaction, event) => root._tryRestore(transaction, event.locked === true),
        restoreAnswered: (transaction, event) => root._restoreAnswered(transaction, event),
        lockWanted: (transaction, event) => root._lockWanted(transaction, event)
    })

    function _started(transaction) {
        if (transaction.state.markerUsable) {
            _emit(transaction, "probeMarker", {});
            return;
        }
        _log(transaction, "warning", "XDG_RUNTIME_DIR is not set: no lock marker, a restarted shell cannot know it was locked");
        _set(transaction, { checked: true });
    }

    // The start probe: this compositor session's key, whether the runtime dir is private,
    // and the marker as the last shell left it
    function _markerAnswered(transaction, event) {
        const facts = LockIoRules.markerFacts(event.lines);
        const locked = event.locked === true;
        if (!facts.private) {
            _log(transaction, "warning", "XDG_RUNTIME_DIR (" + transaction.state.runtimeDirectory + ") is not a private directory of this user: "
                + "no lock marker, a restarted shell cannot know it was locked");
            return;
        }
        if (facts.key !== "")
            _set(transaction, { key: facts.key });
        // A reload came between an unlock and its "unlocked" (_markerUnlockDue): the old
        // generation sent its unlock long before this one could start
        const carried = transaction.state.carried;
        if (carried.markerUnlockPending && !carried.held && !locked) {
            _set(transaction, { marker: "locked" });
            _writeMarker(transaction, "unlocked");
            return;
        }
        // A lock in force got "?" in its marker: now the key is known
        if (transaction.state.marker === "locked")
            _writeMarker(transaction, "locked");
        const decision = LockIoRules.markerDecision(facts.marker, transaction.state.key);
        if (decision === "lock") {
            _restoreFromMarker(transaction, "the shell was locked when it stopped (the lock marker says so)", locked);
        } else if (decision === "stale") {
            _log(transaction, "info", "a lock marker from another compositor session (" + facts.marker + "): not this session's, ignored");
            if (!locked && transaction.state.marker === "")
                _writeMarker(transaction, "unlocked");
        }
    }

    // "locked <key>" from the moment this shell asks for a compositor lock until that lock
    // is over, "unlocked" otherwise. A pending "unlocked" never overwrites a newer "locked"
    function _writeMarker(transaction, word) {
        if (!transaction.state.markerUsable)
            return;
        _emit(transaction, "stopTimer", { name: "markerUnlock" });
        _setCarried(transaction, { markerUnlockPending: false });
        _set(transaction, { marker: word });
        const key = transaction.state.key;
        _emit(transaction, "writeMarker", { text: word === "locked" ? "locked " + key + "\n" : "unlocked\n" });
        _log(transaction, "info", "lock marker: " + (word === "locked" ? "locked " + key : "unlocked"));
        // The session is unlocked: the launcher's count of restarts while locked starts
        // afresh (scripts/launch.sh, "Restarts while locked")
        if (word === "unlocked")
            _emit(transaction, "resetLockRestarts", {});
    }

    // Quickshell refused the lock at once (no lock object was made). Taking back a lock this
    // process had is refused only by a process that believes it still holds one
    // (Quickshell's process-wide lock manager, left with a stale lock when a locked
    // WlSessionLock was destroyed: a hard reload). It can never lock again: a fresh process
    // can — the launcher starts one, and the marker locks it
    function _lockRefused(transaction, event) {
        _setCarried(transaction, { held: false });
        if (transaction.state.restoring) {
            _exitForRestart(transaction, "this process cannot take the session lock back (Quickshell still counts a destroyed lock as active)");
            return;
        }
        _emit(transaction, "compositorFinished", { session: event.session });
    }

    // Reload, after Quickshell realized the new WlSessionLock: the lock must now be held by
    // this process. If it is not (the old WlSessionLock was not handed over — a reload that
    // changed the driver's objects), the old one's lock dies with the old generation and
    // Quickshell still counts it as active: this process can never lock again
    function _carriedChecked(transaction, event) {
        if (event.locked !== true || event.compositorLocked === true)
            return;
        _exitForRestart(transaction, "the lock was not carried over the reload");
    }

    // The process cannot lock (again): it quits with a failure, the launcher starts a fresh
    // one, and the marker (still "locked") locks that one at once. Without the launcher's
    // supervision nothing restarts it — no worse than staying, unable to lock
    function _exitForRestart(transaction, why) {
        _log(transaction, "error", why + ": quitting so that a fresh shell takes the lock (the launcher restarts it; the marker locks it)");
        _writeMarker(transaction, "locked");
        _emit(transaction, "exit", {});
    }

    // A lock the marker asked for: once the compositor confirms it, it is an ordinary lock
    // (and a later refusal is an ordinary one too)
    function _confirmed(transaction) {
        _setCarried(transaction, { secure: true });
        if (transaction.state.restoring)
            _log(transaction, "info", "the lock is back: the compositor confirmed it");
        _set(transaction, { restoring: false, restorePending: false, restoreDelay: 0 });
        _emit(transaction, "stopTimer", { name: "restoreRetry" });
    }

    // The lock this shell had (or asked for) is over. A lock the marker asked to take back
    // and the compositor refused is not over for the compositor: it keeps its lock (Hyprland
    // without misc:allow_session_lock_restore shows "lockscreen app died"), so the marker
    // stays and the lock is asked for again, with a growing pause — a way back in once the
    // setting is switched on
    function _ended(transaction, event) {
        if (event.locked === true)
            return;
        if (transaction.state.marker !== "locked" && !transaction.state.carried.held)
            return;
        _setCarried(transaction, { held: false, secure: false });
        if (transaction.state.restoring && event.lastEnd === "denied") {
            _restoreRefused(transaction, "the compositor refused the lock");
            return;
        }
        _set(transaction, { restoring: false, restorePending: false, restoreDelay: 0 });
        if (transaction.state.marker === "locked") {
            // "unlocked" goes on disk a moment after the step that ended the lock (the
            // driver's _markerUnlockDelay says why); a reload in the meantime writes it in
            // the new generation (the start probe)
            _emit(transaction, "startMarkerUnlockDelay", {});
            _setCarried(transaction, { markerUnlockPending: true });
        } else {
            _writeMarker(transaction, "unlocked");
        }
    }

    function _markerUnlockDue(transaction, event) {
        const state = transaction.state;
        if (event.locked !== true && !state.restoring && !state.carried.held && state.marker === "locked")
            _writeMarker(transaction, "unlocked");
    }

    // The compositor will not (or did not) give the lock back: said once, shown in the
    // status ("compositor-locked"), asked again later
    function _restoreRefused(transaction, why) {
        _set(transaction, {
            restoreDelay: LockIoRules.restartDelay(transaction.state.restoreDelay, 0, restoreTable),
            restorePending: true
        });
        if (!transaction.state.refusalLogged) {
            _set(transaction, { refusalLogged: true });
            _log(transaction, "error", "the compositor refused to let this shell take back the lock it had (" + why + "): the session "
                + "stays locked, with no prompt of this shell's (Hyprland: misc:allow_session_lock_restore is off). Asking "
                + "again every few seconds to a minute; to get the prompt back, switch it on — from a TTY: hyprctl -i 0 eval "
                + "'hl.config({ misc = { allow_session_lock_restore = true } })' — see notes/plans/lockscreen.md, section 7, "
                + "\"Recovery\"");
        }
        const delay = transaction.state.restoreDelay;
        _log(transaction, "warning", "taking the lock back again in " + Math.round(delay / 1000) + " s");
        _emit(transaction, "startTimer", { name: "restoreRetry", ms: delay });
    }

    function _restoreFromMarker(transaction, why, locked) {
        if (locked)
            return;
        _set(transaction, { restoring: true });
        _log(transaction, "warning", why + ": locking again");
        _tryRestore(transaction, locked);
    }

    // Asks for the lock back — under Hyprland only after asking it whether it would give
    // it: Hyprland 0.57 refuses a new lock while a dead client's lock stands and restoring
    // is off, and then kills the client that asked (it destroys the refused lock at once;
    // Quickshell's get_lock_surface on it is a protocol error). Without Hyprland (or without
    // an answer), the lock is simply asked for: refused, it is asked again later; a shell
    // killed for asking is started again by the launcher, at most a few times
    function _tryRestore(transaction, locked) {
        if (!transaction.state.restoring || locked)
            return;
        if (transaction.state.hyprland) {
            _emit(transaction, "probeRestore", {});
            return;
        }
        _emit(transaction, "requestLock", { source: "restore" });
    }

    function _restoreAnswered(transaction, event) {
        if (!transaction.state.restoring || event.locked === true)
            return;
        const facts = LockIoRules.hyprlandLockFacts(event.output);
        if (facts.restoreAllowed === null && facts.locked === null)
            _log(transaction, "warning", "Hyprland did not answer (hyprctl, 2 s each): asking for the lock back anyway");
        if (LockIoRules.lockSurelyRefused(facts)) {
            _restoreRefused(transaction, "Hyprland is locked and does not allow restoring the lock; not asking, which would get "
                + "this shell killed");
            return;
        }
        _emit(transaction, "requestLock", { source: "restore" });
    }

    // While the compositor holds a lock it will not give back, asking for a new one is
    // asking for that one back (and nothing else would be given)
    function _lockWanted(transaction, event) {
        if (transaction.state.restorePending) {
            _tryRestore(transaction, event.locked === true);
            return;
        }
        const source = event.source;
        _emit(transaction, "requestLock", { source: typeof source === "string" && source !== "" ? source : "request" });
    }

    // ---- Helpers: every change copies what it changes ----

    function _emit(transaction, type, fields) {
        transaction.effects.push(Object.assign({ type: type }, fields));
    }

    function _log(transaction, level, message) {
        _emit(transaction, "log", { level: level, message: message });
    }

    function _set(transaction, changes) {
        transaction.state = Object.assign({}, transaction.state, changes);
    }

    function _setCarried(transaction, changes) {
        _set(transaction, { carried: Object.assign({}, transaction.state.carried, changes) });
    }
}
