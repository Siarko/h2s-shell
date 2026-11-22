pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.singletons
import qs.singletons.io
import qs.singletons.lock
import qs.screensaver

// The lock screen's driver, and the one owner of its state (notes/plans/lockscreen.md,
// sections 3 and 7). LockRules decides everything; this holds the one current state,
// feeds events in, one at a time, and carries the effects out through the adapters in
// singletons/lock/ (PAM, the methods script, logind, the sleep inhibitor) and the
// WlSessionLock. The views (screensaver/LockSurface, LockPrompt) render `view` and report
// input through the surface functions below.
//
// What the rest of the shell gets: `view` (LockRules.view of the state), `locked`,
// lock(), the surface functions (which take the LockSurface object
// itself and act only for one registered by addSurface), and the read-only IPC `state`
// (LockRules.describe). There is no unlock function, no dispatch function, and the state,
// the event queue and the surface registry are not properties: they live in the closure
// _build() makes, reachable only through the operations it returns. The lock ends only as
// the rules say — an accepted authentication, logind's Unlock (`loginctl unlock-session`,
// from another console), or the compositor ending it. Escape never unlocks.
//
// What same-process QML can still do (plan, section 7, "What other QML can reach"): call
// lock() and the surface functions with a LockSurface it got hold of; emit the signals of
// this singleton's child objects (`Lockscreen.children`: the logind monitor, the adapters),
// which are filtered by event type but can carry logind's Unlock; and, like any process of
// the user, run `loginctl unlock-session`. The tightening is defence in depth, not a
// boundary against code running in the shell.
//
// The Quickshell bug worked around here (plan, section 1): Quickshell 0.3.2 never emits
// lockStateChanged when a WlSessionLock unlocks, so a binding to its `locked` stays true
// after the first unlock — and the old code, hung on that binding, worked once per shell.
// Here `locked` is never bound or watched: it is set by the effects, read back only right
// after being set to true, and the compositor's word comes from secureStateChanged.
//
// Recovery (plan, section 7, "Reload" and "Restart"): a reload of the shell while locked
// carries the compositor's lock over (`_carried`, set into the new WlSessionLock before
// Quickshell realizes it, and the rules' `restored`); a shell that stopped while locked —
// crashed, killed, stopped, restarted — finds the lock marker it wrote at the lock
// ($XDG_RUNTIME_DIR/h2s-shell-lock) and locks again at once. The launcher
// (scripts/launch.sh) restarts a shell that died. FAIL CLOSED: a shell that cannot take
// the lock back says so and keeps trying; it never comes up unlocked over a locked session.
Singleton {
    id: root

    // ---- For the rest of the shell ----

    // What the lock surfaces render (LockRules.view): replaced, never mutated
    readonly property var view: _view
    // Also while the compositor holds a lock this shell could not take back (see "Recovery"
    // below): the screen is locked whatever the rules' state says, so nothing may act as if
    // it were not (the idle lock, the screensaver)
    readonly property bool locked: _view.locked || _restorePending
    // The compositor holds a lock of this shell's: confirmed (secure), or one it could not
    // take back — the screen is locked now, not on its way (SleepLockNotice)
    readonly property bool lockConfirmed: _sessionLock.secure || _restorePending
    // logind's object path of this shell's session ("" while unknown)
    readonly property string sessionPath: _logind.sessionPath
    // Somebody at the lock screen (LockViewRules: the prompt awake, a check under way): Idle
    // holds the lock screen's screen-off meanwhile
    readonly property bool attended: _view.attended === true
    // The start has read the lock marker (or there is none to read), and `restoring` says
    // whether it is taking a lock back: until then a session the compositor holds locked may
    // still look unlocked here (LockNotice waits for both)
    readonly property bool startChecked: _markerChecked
    readonly property bool restoring: _restoring
    // Whether Caps Lock is on, from the keyboards' LEDs (singletons/lock/CapsLockLed.qml):
    // true, false, or null while unknown (no LED, or none readable: no indicator). Read
    // when the prompt wakes and at each key on an awake prompt. Shown on the prompt; no
    // part of the lock's state — the rules never see it
    readonly property var capsLock: _capsLed.on

    // Locking needs no proof, so anything may ask (the IPC, idle, a future button)
    function lock(source) {
        _api?.lock(source);
    }

    // ---- For the lock surfaces (screensaver/LockSurface.qml) ----
    // A surface instance registers itself once its screen is known and gets an id of its
    // own, never reused within the shell's life (what the view's promptSurface names). Every
    // other call passes the surface object itself: only a LockSurface registered here counts.

    function addSurface(surface, screenName) {
        return _api?.addSurface(surface, screenName) ?? null;
    }

    function removeSurface(surface) {
        _api?.removeSurface(surface);
    }

    function surfaceActivity(surface) {
        _api?.input(surface, { type: "activity" });
    }

    function surfacePress(surface) {
        _api?.input(surface, { type: "press" });
    }

    // `key`: one of LockRules.namedKeys or ""; `text`: what the key types; `autoRepeat`:
    // the key event is a repeat of a held key
    function surfaceKey(surface, key, text, autoRepeat) {
        _api?.input(surface, { type: "key", key: key, text: text, autoRepeat: autoRepeat === true });
    }

    function surfaceSubmit(surface, text) {
        _api?.input(surface, { type: "submit", text: text });
    }

    // ---- Settings (notes/plans/global-profiles.md) ----

    readonly property bool lockOnSleep: LockRules.lockOnSleepSetting(Profiles.value("lockscreen.lockOnSleep"),
                                                                     SettingsSchema.coreDefaults["lockscreen.lockOnSleep"],
                                                                     Profiles.configFailed)

    // The driver reads the setting itself: nothing passed in can change it
    onLockOnSleepChanged: _api?.lockOnSleepChanged()

    // ---- The driver ----

    property var _view: LockRules.view(LockRules.initial({}))
    // The compositor holds a lock this shell had (the marker says so) and has refused to let
    // it take that lock back — Hyprland without misc:allow_session_lock_restore. Retried
    // with a growing pause; see the "Recovery" note above
    property bool _restorePending: false
    // The start probe has answered; a lock is being taken back from the marker (from the
    // marker's answer until the compositor confirms the lock or ends it) — the recovery
    // state's `checked` and `restoring` (LockRecoveryRules), mirrored
    property bool _markerChecked: false
    property bool _restoring: false
    // The operations of the driver, closures over its private state; null until built
    property var _api: null

    // The lock test bed's seams (tests/lock/README.md; read by TestSeams), like
    // H2S_LOCK_AUTH_METHODS, inert unless set. H2S_LOCK_TOOLS: a directory whose `gdbus` and `systemd-inhibit` stand in
    // for the real ones, since the test bed cuts the system bus off (and the launcher puts
    // the real gdbus first on PATH). H2S_LOCK_SYSTEM_PAM_DIR: where the system-wide
    // h2s-shell-* configs are looked for (/etc/pam.d), so that the password fallback of a
    // test shell can never be the system's real PAM stack. Neither grants anything: whoever
    // sets the shell's environment can already run anything as the user.
    readonly property string _toolDirectory: TestSeams.lockTools
    readonly property string _systemPamDirectory: TestSeams.systemPamDirectory || "/etc/pam.d"

    // H2S_LOCK_TEST_TIMINGS: a JSON object of LockRules.timings overrides, so that a test of
    // what happens after minutes (rounds that time out) runs in seconds. initial() keeps
    // only known names with finite values ≥ 0; anything unparsable is no override. Like the
    // seams above, it grants nothing: the timings decide when, never whether, a lock ends.
    function _testTimings() {
        if (TestSeams.timingsProblem !== "") {
            _log("error", "H2S_LOCK_TEST_TIMINGS is " + TestSeams.timingsProblem + ": ignored");
            return {};
        }
        if (TestSeams.inForce.includes("H2S_LOCK_TEST_TIMINGS"))
            _log("warning", "test timings in force (H2S_LOCK_TEST_TIMINGS): " + JSON.stringify(TestSeams.timings));
        return Object.assign({}, TestSeams.timings);
    }

    // The events each source may raise: a child object's signal emitted by other QML can
    // raise no other kind
    readonly property var _adapterEvents: ["pamMessage", "pamCompleted", "pamStartFailed", "methodsDetected", "methodsFailed"]
    readonly property var _logindEvents: ["lockRequested", "unlockRequested", "prepareForSleep", "resumed"]

    // The events whose handling goes to the log, taken or not: everything about
    // authentication, the lock's life and sleep. Pointer motion, keys and timers would drown
    // them; what those cause shows in the rules' own log effects.
    readonly property var _loggedEvents: ["started", "restored", "lockRequested", "unlockRequested", "compositorLocked",
        "compositorFinished", "surfaceAdded", "surfaceRemoved", "submit", "methodsDetected", "methodsFailed",
        "pamMessage", "pamCompleted", "pamStartFailed", "prepareForSleep", "resumed", "settings"]
    readonly property var _loggedEffects: ["lockCompositor", "adoptCompositorLock", "unlockCompositor", "announceLocked",
        "reportLockedHint", "detectMethods", "startPam", "abortPam", "respondPam", "holdInhibitor", "releaseInhibitor"]

    // The lock marker: "locked <key>" from the moment this shell asks for a compositor lock
    // until that lock is over, "unlocked" otherwise. A shell that starts and finds "locked"
    // with this compositor's key was locked when its predecessor stopped (a crash, a kill, a
    // restart): it locks again at once. In $XDG_RUNTIME_DIR, the user's own 0700 directory
    // on a tmpfs (gone at reboot and at the end of the user's last session); without it,
    // there is no marker and a restarted shell cannot know (logged once).
    readonly property string _runtimeDirectory: Quickshell.env("XDG_RUNTIME_DIR") ?? ""
    readonly property string _markerPath: _runtimeDirectory !== "" ? _runtimeDirectory + "/h2s-shell-lock" : ""
    // The launcher's record of its restarts while locked (scripts/launch.sh, "Restarts while
    // locked"): overwritten here when a lock ends, which tells the launcher of the unlock
    readonly property string _lockRestartsPath: _runtimeDirectory !== "" ? _runtimeDirectory + "/h2s-shell-lock-restarts" : ""
    // Hyprland's instance, when the shell runs under it: asked before a lock is taken back
    readonly property string _hyprlandSignature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? ""

    // Builds the driver: its state lives in this function's scope, never in a property.
    // Returns the operations the singleton's functions and the IPC call.
    function _build() {
        // The one current state. It may hold the secret: only describe() of it leaves here,
        // and old states are never kept
        let state = LockRules.initial({
            lockOnSleep: root.lockOnSleep,
            passwordFallback: LockIoRules.passwordFallback({ shellDirectory: Quickshell.shellDir, systemDirectory: root._systemPamDirectory }),
            timings: root._testTimings()
        });
        let viewJson = "";
        // What publish() saw change, to be logged at the end of the step
        let viewLog = [];
        // Surface objects ↔ ids; the timers by name; the per-lock adapters; the session of
        // the last lockCompositor; Quickshell.watchFiles as it was before the lock
        const surfaceIds = new Map();
        const surfaceObjects = {};
        let nextSurfaceId = 1;
        const timers = {};
        let scope = null;
        let sessionInForce = 0;
        let watchFilesBefore = true;
        let fallbackKnown = false;
        // Recovery (see the header): the marker, taking a lock back, asking again — decided
        // by LockRecoveryRules, whose one state this is. What a reload carries over is not in
        // it but in `_carried`, read in before each of its steps
        let recovery = LockRecoveryRules.initial({
            markerUsable: root._markerPath !== "",
            hyprland: root._hyprlandSignature !== "",
            runtimeDirectory: root._runtimeDirectory
        });
        // Each PAM conversation's start, for the duration logged at its end: { method:
        // { conversation, at, config } }
        const pamStarts = {};

        const log = root._log;
        const describeEvent = event => JSON.stringify(LockRules.describeEvent(event));
        const describeEffect = effect => JSON.stringify(LockRules.describeEffect(effect));

        // One step at a time (LockIoRules.serialQueue). An event raised while a step's
        // effects run (a refused start(), a signal emitted synchronously inside respond(),
        // abort() or the lock's setter) is queued and handled after them, in the order raised
        // — never re-entered.
        const queue = LockIoRules.serialQueue(event => handle(event),
            (error, event) => log("error", "handling " + describeEvent(event) + " failed: " + error));

        // Events from the adapters come through QML signals (`var` arguments), which turn a
        // JS array into a list wrapper that Array.isArray does not recognise — the methods
        // script's lines were then read as no lines at all. So every event is made a plain
        // JS object first; the copy lives no longer than the original.
        const dispatch = event => queue(JSON.parse(JSON.stringify(event)));
        const dispatchFrom = allowed => event => {
            if (event !== null && typeof event === "object" && allowed.includes(event.type))
                dispatch(event);
            else
                log("error", "an event of a kind its source may not raise was dropped: " + describeEvent(event));
        };

        function handle(event) {
            const result = LockRules.step(state, event, Date.now());
            const logged = root._loggedEvents.includes(event?.type);
            if (result.error === true)
                log("error", "internal error in the rules on " + describeEvent(event) + (result.ignored ? ": " + result.ignored : ""));
            if (event?.type === "pamCompleted")
                logPamEnd(event, result.ignored);
            if (result.ignored !== "") {
                if (logged)
                    log("info", "ignored " + describeEvent(event) + ": " + result.ignored);
                return;
            }
            if (logged)
                log("info", "event " + describeEvent(event));
            LockIoRules.runStep(result, {
                // Commit before the effects run: whatever they raise is handled against it
                commit: next => { state = next; },
                prepare: () => {
                    if (state.phase.status !== "unlocked" && scope === null)
                        scope = createScope();
                },
                publish: () => publish(event),
                execute: execute,
                // The lock is over and its effects (aborts included) have run: its adapters
                // go, and with them anything they still had running
                finish: () => {
                    finishViewLog();
                    if (state.phase.status === "unlocked" && scope !== null) {
                        const ending = scope;
                        scope = null;
                        ending.retire();
                        ending.destroy();
                    }
                    if (state.phase.status === "unlocked")
                        recover({ type: "ended", locked: false, lastEnd: state.phase.lastEnd });
                },
                onError: (where, error, effect) => log("error", (effect ? "effect " + describeEffect(effect) : where) + " failed: " + error)
            });
        }

        // `view` is replaced only when it changed: pointer motion moves the prompt's deadline
        // in the state at every event, which the views need not hear about
        // What the owner saw change goes to the log too, with what caused it (`cause`: the
        // event of the step): the prompt waking and sleeping, a refused submit, an error shown
        function publish(cause) {
            const view = LockRules.view(state);
            const json = JSON.stringify(view);
            if (json === viewJson)
                return;
            const before = root._view;
            const woke = view.promptSurface !== null && before.promptSurface === null;
            const slept = view.promptSurface === null && before.promptSurface !== null;
            viewJson = json;
            root._view = view;
            const by = cause ? cause.type + (cause.type === "timer" ? " " + cause.name : "")
                + (cause.type === "key" && cause.key ? " " + cause.key : "") : "start";
            // Said after the step's effects (finishViewLog), so that the log reads in the
            // order things happened: the verdict, then what the prompt showed for it
            const said = [];
            if (woke)
                said.push("prompt awake on surface " + view.promptSurface + " (" + view.promptScreen + "), woken by " + by);
            else if (slept && view.locked)
                said.push("prompt asleep (" + by + ")");
            if (view.refusal !== "" && view.refusal !== before.refusal)
                said.push("submit refused: " + view.refusal);
            if (view.error !== "" && view.error !== before.error)
                said.push("prompt shows: " + view.error);
            if (view.locked !== before.locked)
                said.push(view.locked ? "the lock screen is up" : "the lock screen is gone");
            viewLog = viewLog.concat(said);
            if (!cause)
                finishViewLog();
            // Caps Lock is read from its LED when somebody comes back to the prompt
            if (woke)
                _capsLed.read();
        }

        function finishViewLog() {
            const lines = viewLog;
            viewLog = [];
            for (const line of lines)
                log("info", line);
        }

        // A PAM conversation's end, with how long it ran and its config (the start effect
        // logs the start); `ignored`: why the rules did not take it, if they did not
        function logPamEnd(event, ignored) {
            const start = pamStarts[event.method];
            if (!start || start.conversation !== event.conversation)
                return;
            delete pamStarts[event.method];
            log("info", event.method + " conversation " + event.conversation + " ended: " + event.result + " after "
                + (Date.now() - start.at) + " ms (" + start.config + ")" + (ignored ? "; not taken: " + ignored : ""));
        }

        function execute(effect) {
            if (root._loggedEffects.includes(effect.type))
                log("info", "effect " + describeEffect(effect));
            switch (effect.type) {
            case "lockCompositor":
                sessionInForce = effect.session;
                // The marker first: a shell that dies from here on comes back locked
                recover({ type: "lockAsked" });
                _sessionLock.locked = true;
                // Reliable in this direction (only the unlock notify is broken): false right
                // after setting it means Quickshell refused the lock without a signal — no
                // ext-session-lock, no surface component, lock() failing. No lock object was
                // made then, so setting `locked` back to false sends nothing to the
                // compositor; it only clears Quickshell's target, so that the next lock is
                // not taken for a no-op.
                if (!_sessionLock.locked) {
                    log("warning", "the session lock was refused at once (session " + effect.session + ")");
                    _sessionLock.locked = false;
                    // The rules say whether the lock rules hear of it, or (a lock being taken
                    // back) this process quits for a fresh one
                    recover({ type: "lockRefused", session: effect.session });
                } else {
                    recover({ type: "lockTaken" });
                }
                break;
            case "adoptCompositorLock":
                // `restored`: the new WlSessionLock takes the old one's lock over when
                // Quickshell realizes it (later in this reload); its target must be true by
                // then, or it would unlock (plan, section 1). Nothing is sent to the
                // compositor here
                sessionInForce = effect.session;
                _sessionLock.locked = true;
                recover({ type: "lockAdopted" });
                break;
            case "unlockCompositor":
                // The rules emit this only for a session the compositor confirmed. Checked
                // again here: before `locked` arrived, Quickshell would send
                // unlock_and_destroy — a protocol error (ext-session-lock-v1)
                if (_sessionLock.locked && !_sessionLock.secure) {
                    log("error", "refused to unlock a lock the compositor has not confirmed (session " + effect.session + ")");
                    break;
                }
                _sessionLock.locked = false;
                break;
            case "announceLocked":
                Profiles.screenLocked = effect.locked;
                // No reload while locked, from file changes: a reload carries the lock over
                // now (`restored`), but that is the recovery path, not one to take at every
                // file written while the owner is away. At the unlock file watching is
                // simply switched back on: edits made meanwhile take effect at the next
                // file change. (A reload right after the unlock was tried and removed: for
                // its ~2 s a lock request by IPC was dropped and logind's PrepareForSleep
                // missed — the lid closed right after an unlock slept unlocked.)
                if (effect.locked) {
                    // Nothing of an earlier lock's Caps Lock is shown: read at the wake
                    _capsLed.forget();
                    watchFilesBefore = Quickshell.watchFiles;
                    Quickshell.watchFiles = false;
                    probeFallback();
                } else {
                    Quickshell.watchFiles = watchFilesBefore;
                }
                break;
            case "reportLockedHint":
                _lockedHint.report(effect.locked);
                break;
            case "detectMethods":
                scopeFor(effect)?.detect(effect.generation);
                break;
            case "startPam":
                pamStarts[effect.method] = { conversation: effect.conversation, at: Date.now(),
                    config: effect.configDirectory + "/" + effect.config };
                scopeFor(effect)?.pam(effect.method)?.start(effect.conversation, effect.configDirectory, effect.config);
                break;
            case "abortPam":
                scope?.pam(effect.method)?.abort(effect.conversation);
                break;
            case "respondPam":
                scope?.pam(effect.method)?.respond(effect.conversation, effect.text);
                break;
            case "startTimer":
                startTimer(effect.name, effect.ms, effect.token);
                break;
            case "stopTimer":
                timers[effect.name]?.stop();
                break;
            case "holdInhibitor":
                _inhibitor.wanted = true;
                break;
            case "releaseInhibitor":
                _inhibitor.wanted = false;
                break;
            case "forwardKey": {
                const surface = surfaceObjects[effect.surface];
                if (surface)
                    surface.applyKey(effect.key, effect.text);
                break;
            }
            case "log":
                log(effect.level, effect.message);
                break;
            default:
                log("error", "unknown effect " + describeEffect(effect));
            }
        }

        // The lock's adapters exist from the step that begins a lock to the one that ends it
        function scopeFor(effect) {
            if (scope === null)
                log("error", "no lock scope for " + describeEffect(effect));
            return scope;
        }

        function createScope() {
            const created = _scopeComponent.createObject(root);
            if (created === null) {
                log("error", "could not create the lock's adapters");
                return null;
            }
            created.event.connect(dispatchFrom(root._adapterEvents));
            created.logLine.connect(log);
            return created;
        }

        // One single-shot timer per name, created on first use. Qt's timers are monotonic,
        // which the rules want: missedResume stands still while the machine sleeps
        function startTimer(name, milliseconds, token) {
            let timer = timers[name];
            if (!timer) {
                timer = _timerComponent.createObject(root);
                timer.triggered.connect(() => dispatch({ type: "timer", name: name, token: timer.token }));
                timers[name] = timer;
            }
            timer.stop();
            timer.token = token;
            timer.interval = Math.max(0, milliseconds);
            timer.start();
        }

        // The password fallback is chosen from what is on this machine (LockIoRules
        // .passwordFallback): asked at start and at every lock, handed to the rules. Locking
        // never waits for it: until an answer the rules keep the fallback they have.
        //
        // The methods script is asked first, so that it and the fallback tell the system
        // the same way. When it does not answer (it cannot be run, exits non-zero, says
        // something else: LockIoRules.fallbackFacts), the machine is asked directly — the
        // script failing is exactly when the fallback is needed, so the fallback must not
        // depend on it. When that gives no answer either, the fallback stays as it is.
        // `fallbackAsked` numbers the requests; `fallbackDirectFor` is the request the
        // direct question is wanted for (0: none), so that a direct answer that comes
        // after a newer request was made is dropped. `fallbackSource`: who answered last
        // ("script" / "direct" / "none"), for a log line when that changes
        let fallbackAsked = 0;
        let fallbackDirectFor = 0;
        let fallbackSource = "";

        function probeFallback() {
            if (_fallbackProbe.running)
                return;
            fallbackAsked += 1;
            fallbackDirectFor = 0;
            _fallbackProbe.request();
        }

        function probeFallbackDirectly() {
            // One still running was started for an older request: its answer is dropped
            // and the question asked again (below)
            if (_fallbackDirectProbe.running)
                return;
            _fallbackDirectProbe.generation = fallbackDirectFor;
            _fallbackDirectProbe.request();
        }

        function fallbackAnsweredBy(source, reason) {
            if (source === fallbackSource)
                return;
            fallbackSource = source;
            if (source === "script")
                log("info", "password fallback: the methods script answers again");
            else if (source === "direct")
                log("warning", "password fallback: no answer from the methods script (" + reason + "): the machine is asked directly");
            else
                log("error", "password fallback: the machine could not be asked either (" + reason + "): it stays as it is");
        }

        function applyFallbackFacts(facts) {
            const fallback = LockIoRules.passwordFallback({
                shellDirectory: Quickshell.shellDir,
                systemDirectory: root._systemPamDirectory,
                systemConfigReadable: facts.systemConfigReadable,
                nixos: facts.nixos
            });
            fallbackKnown = true;
            const current = state.settings.passwordFallback;
            if (!current || current.directory !== fallback.directory || current.config !== fallback.config)
                dispatch({ type: "settings", values: { passwordFallback: fallback } });
        }

        _fallbackProbe.answered.connect((lines, result) => {
            const facts = LockIoRules.fallbackFacts(LockIoRules.probeRun(lines, result));
            if (facts.known) {
                fallbackAnsweredBy("script", "");
                applyFallbackFacts(facts);
                return;
            }
            fallbackAnsweredBy("direct", facts.reason);
            fallbackDirectFor = fallbackAsked;
            probeFallbackDirectly();
        });

        _fallbackDirectProbe.answered.connect((lines, result) => {
            // The request it was started for
            const generation = _fallbackDirectProbe.generation;
            if (generation !== fallbackDirectFor) {
                if (fallbackDirectFor !== 0)
                    probeFallbackDirectly();
                return;
            }
            fallbackDirectFor = 0;
            const facts = LockIoRules.fallbackFacts(LockIoRules.probeRun(lines, result));
            if (facts.known)
                applyFallbackFacts(facts);
            else
                fallbackAnsweredBy("none", facts.reason);
        });

        // ---- Recovery ----

        // One step of LockRecoveryRules: `_carried` read in, the new state committed and
        // mirrored before the effects run (an effect may lead back here: requestLock runs the
        // lock rules at once, and their lockCompositor comes back as lockAsked)
        function recover(event) {
            const result = LockRecoveryRules.step(LockRecoveryRules.withCarried(recovery, _carried), event);
            recovery = result.state;
            _carried.held = recovery.carried.held;
            _carried.secure = recovery.carried.secure;
            _carried.markerUnlockPending = recovery.carried.markerUnlockPending;
            root._restoring = recovery.restoring;
            root._restorePending = recovery.restorePending;
            root._markerChecked = recovery.checked;
            for (const effect of result.effects)
                recoveryEffect(effect);
        }

        function recoveryEffect(effect) {
            switch (effect.type) {
            case "probeMarker":
                _markerProbe.request();
                break;
            case "probeRestore":
                if (!_restoreProbe.running)
                    _restoreProbe.request();
                break;
            case "requestLock":
                dispatch({ type: "lockRequested", source: effect.source });
                break;
            case "writeMarker":
                _marker.setText(effect.text);
                break;
            case "resetLockRestarts":
                // Anything but its count says so; the time makes each write differ from the
                // last (FileView skips a write of the text it already holds, and the launcher
                // writes behind its back)
                _lockRestarts.setText("unlocked " + Date.now() + "\n");
                break;
            case "startTimer":
                _restoreRetry.interval = effect.ms;
                _restoreRetry.start();
                break;
            case "startMarkerUnlockDelay":
                if (!_markerUnlockDelay.running)
                    _markerUnlockDelay.restart();
                break;
            case "stopTimer":
                if (effect.name === "markerUnlock")
                    _markerUnlockDelay.stop();
                else
                    _restoreRetry.stop();
                break;
            case "compositorFinished":
                dispatch({ type: "compositorFinished", session: effect.session });
                break;
            case "checkCarriedLater":
                Qt.callLater(checkCarriedLock);
                break;
            case "exit":
                Qt.exit(1);
                break;
            case "log":
                log(effect.level, effect.message);
                break;
            default:
                log("error", "unknown recovery effect " + JSON.stringify(effect));
            }
        }

        // "unlocked" goes on disk a moment after the step that ended the lock, not in it:
        // that step also set `locked = false`, and Quickshell's unlock_and_destroy is only
        // queued then — it reaches the compositor when the event loop flushes the Wayland
        // connection. A shell killed in between used to leave the compositor locked and a
        // marker saying "unlocked": its successor came up believing the session unlocked,
        // and the owner sat at the compositor's dead-lock screen. Now the marker says
        // "locked" until the request is long sent: killed then, the successor locks again
        // (fail closed — one authentication too many). ext-session-lock-v1 has no reply to
        // the unlock (and `secure` turns false inside the setter, before anything is
        // sent), so a short wait is the confirmation to be had.
        _markerUnlockDelay.triggered.connect(() => recover({ type: "markerUnlockDue", locked: state.phase.status !== "unlocked" }));

        // Reload, after Quickshell realized the new WlSessionLock: the lock must now be held
        // by this process (LockRecoveryRules: else it quits for a fresh one). One function,
        // so that Qt.callLater runs it once per pass
        function checkCarriedLock() {
            recover({ type: "carriedChecked", locked: state.phase.status !== "unlocked", compositorLocked: _sessionLock.locked });
        }

        // Its lines as one text again (the blank one between the two answers dropped); a
        // signal's array arrives as a list wrapper, hence Array.from
        _restoreProbe.done.connect(lines => recover({ type: "restoreAnswered", output: Array.from(lines).join("\n"), locked: state.phase.status !== "unlocked" }));
        // The start probe, then — its decision made — the start counts as checked
        _markerProbe.done.connect(lines => {
            recover({ type: "markerAnswered", lines: lines, locked: state.phase.status !== "unlocked" });
            recover({ type: "markerChecked" });
        });
        _restoreRetry.triggered.connect(() => recover({ type: "restoreRetry", locked: state.phase.status !== "unlocked" }));

        // The compositor confirmed the lock (secure) or ended / refused it. Tagged with the
        // session of the last lockCompositor executed, as it is at the moment of the
        // signal: inside an unlock effect that is the old session, which the rules then
        // ignore once a new lock has begun
        _sessionLock.secureStateChanged.connect(() => {
            if (_sessionLock.secure)
                recover({ type: "confirmed" });
            dispatch({
                type: _sessionLock.secure ? "compositorLocked" : "compositorFinished",
                session: sessionInForce
            });
        });
        _logind.event.connect(dispatchFrom(root._logindEvents));
        // The machine sleeps and wakes: told to the neutral SystemSleep too (whoever else
        // cares — Idle, the module host for module.resumed() — listens there, never here)
        _logind.event.connect(event => {
            if (event?.type === "resumed")
                Qt.callLater(SystemSleep.reportResumed);
            else if (event?.type === "prepareForSleep")
                Qt.callLater(SystemSleep.reportGoingToSleep);
        });
        // logind is already preparing for sleep when the monitor starts listening: its
        // PrepareForSleep came while no monitor of this shell could hear it — the shell
        // reloading (the event loop blocked, then the old generation torn down) or starting.
        // Taken as that PrepareForSleep, once (only while the rules think the machine is
        // awake): the lock goes up now, while logind still waits for the inhibitor the old
        // generation held (SleepInhibitor: kept a few seconds after its holder vanished)
        _logind.preparingForSleep.connect(() => {
            if (state.sleep.status !== "awake")
                return;
            log("warning", "logind is preparing for sleep and no PrepareForSleep was heard (it came while the shell was "
                + "reloading or starting): acting on it now");
            dispatch({ type: "prepareForSleep" });
            Qt.callLater(SystemSleep.reportGoingToSleep);
        });

        const registered = surface => surfaceIds.has(surface) ? surfaceIds.get(surface) : null;

        const api = {
            // While the compositor holds a lock it will not give back, asking for a new one
            // is asking for that one back (and nothing else would be given)
            lock: source => recover({ type: "lockWanted", source: source, locked: state.phase.status !== "unlocked" }),
            // Only a LockSurface, once, while a lock is in force (Quickshell creates them in
            // the lockCompositor effect, after the step's state is committed). A screen
            // without a name gets one of its own: the rules refuse an empty one
            addSurface: (surface, screenName) => {
                if (!(surface instanceof LockSurface) || surfaceIds.has(surface) || state.phase.status === "unlocked")
                    return null;
                const id = nextSurfaceId++;
                surfaceIds.set(surface, id);
                surfaceObjects[id] = surface;
                const screen = String(screenName ?? "");
                dispatch({ type: "surfaceAdded", surface: id, screen: screen !== "" ? screen : "screen-" + id });
                return id;
            },
            removeSurface: surface => {
                const id = registered(surface);
                if (id === null)
                    return;
                surfaceIds.delete(surface);
                delete surfaceObjects[id];
                dispatch({ type: "surfaceRemoved", surface: id });
            },
            input: (surface, event) => {
                const id = registered(surface);
                if (id === null)
                    return;
                dispatch(Object.assign({}, event, { surface: id }));
                // Every key at an awake prompt reads Caps Lock again (the Caps Lock key
                // itself among them): sysfs tells nobody when the LED changes
                if (event.type === "key" && root._view.promptSurface !== null)
                    _capsLed.read();
            },
            lockOnSleepChanged: () => dispatch({ type: "settings", values: { lockOnSleep: root.lockOnSleep } }),
            // A reload while locked (`_carried` said so): the rules go on with the lock this
            // process holds — called before Quickshell realizes the new WlSessionLock
            restoreAfterReload: secure => {
                log("warning", "the shell was reloaded while locked: the lock is carried over");
                dispatch({ type: "restored", secure: secure === true });
            },
            // What the IPC `state` answers: the rules' describe() (no secret, nothing that
            // times keystrokes), plus a few facts only the driver knows
            describe: () => {
                const described = LockRules.describe(state);
                described.driver = {
                    secure: _sessionLock.secure,
                    sessionInForce: sessionInForce,
                    surfaces: surfaceIds.size,
                    // The screensaver up (Idle), or locked: what the test bed reads as
                    // "the screensaver"
                    screensaverVisible: Idle.saverShown || root.locked,
                    inhibitorRunning: _inhibitor.running,
                    logindSession: _logind.sessionPath,
                    lockScope: scope !== null,
                    testSeams: TestSeams.inForce.slice(),
                    watchFiles: Quickshell.watchFiles,
                    passwordFallbackKnown: fallbackKnown,
                    capsLock: _capsLed.on,
                    // Recovery: the marker as last written ("locked" / "unlocked" / "" for
                    // none yet), whether its key is known, a lock being taken back, the
                    // compositor refusing that, what a reload would carry over
                    marker: recovery.marker,
                    markerKeyKnown: recovery.key !== "?",
                    restoring: recovery.restoring,
                    restorePending: recovery.restorePending,
                    carriedHeld: _carried.held,
                    carriedSecure: _carried.secure
                };
                return JSON.stringify(described);
            }
        };

        const supervisor = Quickshell.env("H2S_SHELL_SUPERVISOR") ?? "";
        log("info", "driver started" + (supervisor !== "" ? ", supervised by the launcher (pid " + supervisor + ")"
            : ", NOT supervised (started without scripts/launch.sh): a shell that dies while locked is not started again"));
        publish();
        dispatch({ type: "started" });
        probeFallback();
        recover({ type: "started" });
        return api;
    }

    // ---- What a reload carries over ----
    // Quickshell hands a reloaded singleton's children their old instances by position,
    // and copies a PersistentProperties' values from the old one before `reloaded`. This one
    // comes BEFORE the WlSessionLock below, so its `reloaded` runs before Quickshell realizes
    // the new WlSessionLock: setting that one's `locked` there makes it take the old lock
    // over instead of unlocking (WlSessionLock::onReload → realizeLockTarget: with the target
    // false it calls unlock(), which sends unlock_and_destroy — the reload that unlocked).
    // `held`: this process has a compositor lock (asked for or confirmed); `secure`: the
    // compositor confirmed it. Keep this object before the WlSessionLock.
    PersistentProperties {
        id: _carried
        property bool held: false
        property bool secure: false
        // The lock ended and the marker's "unlocked" is still to be written (LockRecoveryRules)
        property bool markerUnlockPending: false
        onReloaded: {
            if (held)
                root._api?.restoreAfterReload(secure);
        }
    }

    Component {
        id: _scopeComponent
        LockScope {}
    }

    Component {
        id: _timerComponent
        Timer {
            property int token: 0
            repeat: false
        }
    }

    // Every line is shown whatever the debug setting: this is what is read when unlocking
    // fails on the real machine. Never typed text: events and effects go through
    // LockRules.describeEvent / describeEffect, the rules' messages carry none.
    function _log(level, message) {
        const line = "[Lockscreen] " + message;
        if (level === "error")
            console.error(line);
        else if (level === "warning")
            console.warn(line);
        else
            console.info(line);
    }

    // ---- The compositor ----

    WlSessionLock {
        id: _sessionLock

        // `locked` is not bound: see the header. The surfaces are views of `view`
        LockSurface {}
    }

    // ---- Recovery: the lock marker, and what the start needs to read it ----

    // Written synchronously (blockWrites), atomically: "locked <key>" is on disk before the
    // compositor is asked for a lock
    FileView {
        id: _marker
        path: root._markerPath
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: error => root._log("warning", "could not write the lock marker " + root._markerPath + ": "
            + FileViewError.toString(error))
    }

    // One line each: `private yes|no` (XDG_RUNTIME_DIR is a directory of this user's that
    // nobody else can write to — 0700 by the XDG spec: no other user can plant, remove or
    // read the marker), `key <boot id>:<display>:<socket device:inode:ctime>` — this compositor
    // session, which a new compositor (a new socket) or a reboot changes — and `marker
    // <its first line>` when there is one
    CommandQuery {
        id: _markerProbe
        command: ["sh", "-c",
            "dir=$1; marker=$2\n"
            + "mode=$(stat -c %A \"$dir\" 2> /dev/null)\n"
            + "case $mode in d????w* | d???????w*) mode= ;; esac\n"
            + "if [ -n \"$mode\" ] && [ -d \"$dir\" ] && [ -O \"$dir\" ] && [ ! -L \"$dir\" ]; then echo 'private yes'; else echo 'private no'; fi\n"
            + "display=${WAYLAND_DISPLAY:-wayland-0}\n"
            + "case $display in /*) socket=$display ;; *) socket=$dir/$display ;; esac\n"
            + "boot=$(cat /proc/sys/kernel/random/boot_id 2> /dev/null)\n"
            + "where=$(stat -L -c '%d:%i:%Z' \"$socket\" 2> /dev/null)\n"
            + "[ -n \"$where\" ] && echo \"key $boot:$display:$where\"\n"
            + "[ -f \"$marker\" ] && [ ! -L \"$marker\" ] && [ -O \"$marker\" ] && IFS= read -r line < \"$marker\" && echo \"marker $line\"\n"
            + "exit 0",
            "sh", root._runtimeDirectory, root._markerPath]
    }

    Timer {
        id: _restoreRetry
        repeat: false
    }

    // The marker's "unlocked" after a lock ended (see its `triggered` in _build)
    Timer {
        id: _markerUnlockDelay
        interval: 250
        repeat: false
    }

    // Hyprland's word before a lock is taken back (LockIoRules.hyprlandLockFacts): whether
    // restoring a dead client's lock is allowed, and whether the session is locked
    CommandQuery {
        id: _restoreProbe
        // Each question bounded (2 s): a hung hyprctl used to stall the restore for good while
        // the status said "unlocked". No answer is no answer: the lock is asked for (the
        // generic path), as without Hyprland
        command: ["sh", "-c", "timeout 2 hyprctl -j getoption misc:allow_session_lock_restore; echo; timeout 2 hyprctl -j locked"]
    }

    // ---- What the password fallback depends on ----
    // Both answer one word per line for what holds — "readable" (the system-wide password
    // config), "nixos" — and "answered" last. Each is a LatestQuery, whose answer says how
    // the run ended (CommandQuery's does not): LockIoRules.probeRun makes it the run
    // LockIoRules.fallbackFacts reads, also a run that could not be started.

    // The methods script answers, so that it and the fallback tell the system the same way
    LatestQuery {
        id: _fallbackProbe
        command: [Quickshell.shellDir + "/scripts/lock-auth-methods.sh", "--fallback-facts"]
    }

    // The same question without the script, for when the script gives no answer: nothing
    // here but `sh` and `test`. The test bed's seam for the system (H2S_LOCK_SYSTEM, read
    // as the script reads it: LockIoRules.systemSeam) is honoured here too, so that a test
    // of this path gets the same answer on every machine. `generation`: the request it
    // was started for
    LatestQuery {
        id: _fallbackDirectProbe
        property int generation: 0
        command: ["sh", "-c",
            "test -r \"$1/h2s-shell-password\" && echo readable\n"
            + "case $2 in nixos) echo nixos ;; other) ;; *) test -e /etc/NIXOS && echo nixos ;; esac\n"
            + "echo answered",
            "sh", root._systemPamDirectory,
            LockIoRules.systemSeam(TestSeams.systemPamDirectory, TestSeams.lockSystem)]
    }

    // ---- Adapters for the shell's lifetime ----

    LogindMonitor {
        id: _logind
        toolDirectory: root._toolDirectory
        onLogLine: (level, message) => root._log(level, message)
    }

    SleepInhibitor {
        id: _inhibitor
        toolDirectory: root._toolDirectory
        onLogLine: (level, message) => root._log(level, message)
    }

    Component.onCompleted: {
        _api = _build();
        _logind.start();
    }

    // ---- Requests from outside ----
    // h2s-shell ipc call lockscreen lock       (Arch: launch.sh ipc call ...)
    // h2s-shell ipc call lockscreen status
    // h2s-shell ipc call lockscreen state      (JSON, for tests/lock/)
    // No unlock here: that would let any program skip the password prompt.
    IpcHandler {
        target: "lockscreen"

        function lock(): string {
            root.lock("ipc");
            return status();
        }

        // "locked", "unlocked", or "compositor-locked": the compositor holds a lock this
        // shell had and refuses to give it back (see "Recovery" in the header) — the screen
        // is locked, but not by a prompt of this shell's
        function status(): string {
            return root._view.locked ? "locked" : root._restorePending ? "compositor-locked" : "unlocked";
        }

        // What the lock test bed reads to know where the lock stands: the rules' describe()
        // (no secret, no typed text, nothing that times keystrokes), plus a few facts only
        // the driver knows — the compositor's `secure`, the session of the last
        // lockCompositor, the surface instances registered, whether the screensaver shows,
        // the helpers running, file watching, whether the password fallback is known (idle and
        // the screensaver: `idle state`)
        function state(): string {
            return root._api?.describe() ?? "{}";
        }
    }

    // Caps Lock, from the keyboards' LEDs: the prompt's "Caps Lock is on". Last among the
    // children, so that the ones before keep their positions (a reload matches by position)
    CapsLockLed {
        id: _capsLed
    }

    // ---- PAM helpers left by this very process before a crash ----
    // Quickshell's crash handler restarts a crashed shell in the same process (execve, same
    // pid): the PAM helpers it had forked are still its children, and nobody ends them — the
    // launcher sees no exit, so its clean-up does not run. A fingerprint helper blocked in
    // pam_fprintd with `timeout=-1` (no time limit: pam/fingerprint) would keep the reader
    // claimed for good, and the new shell's fingerprint would fail at its claim. So once per
    // process (`done` is carried over soft reloads, which leave the helpers to their own
    // PamContexts), children of this process running Quickshell's binary that started
    // before this check are killed — not Quickshell's crash reporter (only it has
    // `__QUICKSHELL_CRASH_DUMP_FD`, src/crash/handler.cpp). And only in a process that WAS
    // relaunched in place: its exec-time environment (/proc/<pid>/environ, which qunsetenv
    // does not change) holds `__QUICKSHELL_CRASH_INFO_FD`; a process started fresh sweeps
    // nothing. Why it cannot hit a helper of this process's own conversations: those are
    // forked after the methods script has answered, which is after this check's `sh` was
    // forked (both are Processes, started at the generation's first postReload at the
    // earliest), and a process forked later never has an earlier start time (equal, within
    // one clock tick, is spared: `-lt`). What else this process forks before the check runs
    // `sh`, not Quickshell's binary. The launcher's clean-up (scripts/launch.sh) is the other
    // layer, for a shell that died: the same two tests, at another moment.
    PersistentProperties {
        id: _helperSweepOnce
        property bool done: false
        onLoaded: {
            if (done)
                return;
            done = true;
            _helperSweep.running = true;
        }
    }

    Process {
        id: _helperSweep
        command: ["sh", "-c",
            "shell=$PPID\n"
            + "read -r own < /proc/$$/stat; own=${own##*) }; set -- $own; own_start=${20}\n"
            + "binary=$(readlink /proc/$shell/exe)\n"
            + "tr '\\0' '\\n' < /proc/$shell/environ 2> /dev/null | grep -q '^__QUICKSHELL_CRASH_INFO_FD=' || exit 0\n"
            + "for stat in /proc/[0-9]*/stat; do\n"
            + "    pid=${stat#/proc/}; pid=${pid%/stat}\n"
            + "    [ \"$pid\" = $$ ] && continue\n"
            + "    read -r line < \"$stat\" 2> /dev/null || continue\n"
            + "    line=${line##*) }; set -f; set -- $line; set +f\n"
            + "    [ \"$2\" = \"$shell\" ] && [ \"${20}\" -lt \"$own_start\" ] || continue\n"
            + "    [ \"$(readlink /proc/$pid/exe 2> /dev/null)\" = \"$binary\" ] || continue\n"
            + "    tr '\\0' '\\n' < /proc/$pid/environ 2> /dev/null | grep -q '^__QUICKSHELL_CRASH_DUMP_FD=' && continue\n"
            + "    kill -KILL \"$pid\" 2> /dev/null && echo \"$pid\"\n"
            + "done\n"
            + "exit 0"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root._log("warning", "killed a PAM helper this process left before it was restarted in place: " + line)
        }
    }

    // The launcher's record of restarts while locked, overwritten at an unlock
    // (resetLockRestarts). Never read here. Last among the children: the ones before keep their positions
    FileView {
        id: _lockRestarts
        path: root._lockRestartsPath
        preload: false
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: error => root._log("warning", "could not write the launcher's record " + root._lockRestartsPath + ": "
            + FileViewError.toString(error))
    }

    // logind's LockedHint (reportLockedHint). Last among the children: the ones before keep
    // their positions
    LockedHint {
        id: _lockedHint
        sessionPath: _logind.sessionPath
        toolDirectory: root._toolDirectory
        onLogLine: (level, message) => root._log(level, message)
    }
}
