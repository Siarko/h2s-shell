pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.singletons
import qs.singletons.lock
import qs.screensaver

// The lock screen's driver, and the one owner of its state (docs/plans/lockscreen.md,
// sections 3 and 7). LockRules decides everything; this holds the one current state,
// feeds events in, one at a time, and carries the effects out through the adapters in
// singletons/lock/ (PAM, the methods script, logind, the sleep inhibitor) and the
// WlSessionLock. The views (screensaver/LockSurface, LockPrompt) render `view` and report
// input through the surface functions below.
//
// What the rest of the shell gets: `view` (LockRules.view of the state), `locked`,
// `screensaverVisible`, lock(), the surface functions (which take the LockSurface object
// itself and act only for one registered by addSurface), and the read-only IPC `state`
// (LockRules.describe). There is no unlock function, no dispatch function, and the state,
// the event queue and the surface registry are not properties: they live in the closure
// _build() makes, reachable only through the operations it returns. The lock ends only as
// the rules say — an accepted authentication, logind's Unlock, the Escape key at an awake
// prompt (the owner's decision, for now), or the compositor ending it.
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
Singleton {
    id: root

    // ---- For the rest of the shell ----

    // What the lock surfaces render (LockRules.view): replaced, never mutated
    readonly property var view: _view
    readonly property bool locked: _view.locked
    readonly property bool screensaverVisible: _screensaverMonitor.isIdle || locked
    // Whether Caps Lock is on, as far as the keys typed at the lock surfaces tell
    // (LockIoRules.capsLockAfterKey): true, false, or null while unknown. Shown on the
    // prompt; no part of the lock's state — the rules never see it
    readonly property var capsLock: _capsLock

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

    // What a key on the surface told about Caps Lock: true, false or null (unknown)
    function surfaceCapsLock(surface, on) {
        _api?.capsLock(surface, on);
    }

    // ---- Settings (docs/plans/global-profiles.md) ----

    readonly property bool screensaverEnabled: Profiles.value("lockscreen.screensaverEnabled") ?? false
    readonly property int screensaverTimeout: Profiles.value("lockscreen.screensaverTimeout") ?? 300
    readonly property bool lockscreenEnabled: Profiles.value("lockscreen.lockscreenEnabled") ?? false
    readonly property int lockscreenTimeout: Profiles.value("lockscreen.lockscreenTimeout") ?? 300
    readonly property bool lockOnSleep: Profiles.value("lockscreen.lockOnSleep") ?? true

    // The driver reads the setting itself: nothing passed in can change it
    onLockOnSleepChanged: _api?.lockOnSleepChanged()

    // ---- The driver ----

    property var _view: LockRules.view(LockRules.initial({}))
    property var _capsLock: null
    // The operations of the driver, closures over its private state; null until built
    property var _api: null

    // The lock test bed's seams (tests/lock/README.md), like H2S_LOCK_AUTH_METHODS, inert
    // unless set. H2S_LOCK_TOOLS: a directory whose `gdbus` and `systemd-inhibit` stand in
    // for the real ones, since the test bed cuts the system bus off (and the launcher puts
    // the real gdbus first on PATH). H2S_LOCK_SYSTEM_PAM_DIR: where the system-wide
    // h2s-shell-* configs are looked for (/etc/pam.d), so that the password fallback of a
    // test shell can never be the system's real PAM stack. Neither grants anything: whoever
    // sets the shell's environment can already run anything as the user.
    readonly property string _toolDirectory: Quickshell.env("H2S_LOCK_TOOLS") ?? ""
    readonly property string _systemPamDirectory: Quickshell.env("H2S_LOCK_SYSTEM_PAM_DIR") || "/etc/pam.d"

    // The events each source may raise: a child object's signal emitted by other QML can
    // raise no other kind
    readonly property var _adapterEvents: ["pamMessage", "pamCompleted", "pamStartFailed", "methodsDetected", "methodsFailed"]
    readonly property var _logindEvents: ["lockRequested", "unlockRequested", "prepareForSleep", "resumed"]

    // The events whose handling goes to the log, taken or not: everything about
    // authentication, the lock's life and sleep. Pointer motion, keys and timers would drown
    // them; what those cause shows in the rules' own log effects.
    readonly property var _loggedEvents: ["started", "lockRequested", "unlockRequested", "compositorLocked",
        "compositorFinished", "surfaceAdded", "surfaceRemoved", "submit", "methodsDetected", "methodsFailed",
        "pamMessage", "pamCompleted", "pamStartFailed", "prepareForSleep", "resumed", "settings"]
    readonly property var _loggedEffects: ["lockCompositor", "unlockCompositor", "announceLocked", "detectMethods",
        "startPam", "abortPam", "respondPam", "holdInhibitor", "releaseInhibitor"]

    // Builds the driver: its state lives in this function's scope, never in a property.
    // Returns the operations the singleton's functions and the IPC call.
    function _build() {
        // The one current state. It may hold the secret: only describe() of it leaves here,
        // and old states are never kept
        let state = LockRules.initial({
            lockOnSleep: root.lockOnSleep,
            passwordFallback: LockIoRules.passwordFallback({ shellDirectory: Quickshell.shellDir, systemDirectory: root._systemPamDirectory })
        });
        let viewJson = "";
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
                publish: publish,
                execute: execute,
                // The lock is over and its effects (aborts included) have run: its adapters
                // go, and with them anything they still had running
                finish: () => {
                    if (state.phase.status === "unlocked" && scope !== null) {
                        const ending = scope;
                        scope = null;
                        ending.retire();
                        ending.destroy();
                    }
                },
                onError: (where, error, effect) => log("error", (effect ? "effect " + describeEffect(effect) : where) + " failed: " + error)
            });
        }

        // `view` is replaced only when it changed: pointer motion moves the prompt's deadline
        // in the state at every event, which the views need not hear about
        function publish() {
            const view = LockRules.view(state);
            const json = JSON.stringify(view);
            if (json === viewJson)
                return;
            viewJson = json;
            root._view = view;
        }

        function execute(effect) {
            if (root._loggedEffects.includes(effect.type))
                log("info", "effect " + describeEffect(effect));
            switch (effect.type) {
            case "lockCompositor":
                sessionInForce = effect.session;
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
                    dispatch({ type: "compositorFinished", session: effect.session });
                }
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
                // Quickshell reloads the shell when a file of it changes, and a reload while
                // locked unlocks (plan, section 1): no reload while locked. Edits made
                // meanwhile are picked up by the next file change after the unlock.
                if (effect.locked) {
                    watchFilesBefore = Quickshell.watchFiles;
                    Quickshell.watchFiles = false;
                    probeFallback();
                } else {
                    Quickshell.watchFiles = watchFilesBefore;
                }
                break;
            case "detectMethods":
                scopeFor(effect)?.detect(effect.generation);
                break;
            case "startPam":
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
        // .passwordFallback): asked at start and at every lock, handed to the rules
        function probeFallback() {
            if (!_fallbackProbe.running)
                _fallbackProbe.running = true;
        }

        _fallbackProbe.answered.connect(lines => {
            const facts = LockIoRules.fallbackFacts(lines);
            facts.shellDirectory = Quickshell.shellDir;
            facts.systemDirectory = root._systemPamDirectory;
            const fallback = LockIoRules.passwordFallback(facts);
            fallbackKnown = true;
            const current = state.settings.passwordFallback;
            if (!current || current.directory !== fallback.directory || current.config !== fallback.config)
                dispatch({ type: "settings", values: { passwordFallback: fallback } });
        });

        // The compositor confirmed the lock (secure) or ended / refused it. Tagged with the
        // session of the last lockCompositor executed, as it is at the moment of the
        // signal: inside an unlock effect that is the old session, which the rules then
        // ignore once a new lock has begun
        _sessionLock.secureStateChanged.connect(() => dispatch({
            type: _sessionLock.secure ? "compositorLocked" : "compositorFinished",
            session: sessionInForce
        }));
        _logind.event.connect(dispatchFrom(root._logindEvents));

        const registered = surface => surfaceIds.has(surface) ? surfaceIds.get(surface) : null;

        const api = {
            lock: source => dispatch({ type: "lockRequested", source: typeof source === "string" && source !== "" ? source : "request" }),
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
                if (id !== null)
                    dispatch(Object.assign({}, event, { surface: id }));
            },
            capsLock: (surface, on) => {
                if (registered(surface) !== null)
                    root._capsLock = on === true || on === false ? on : null;
            },
            lockOnSleepChanged: () => dispatch({ type: "settings", values: { lockOnSleep: root.lockOnSleep } }),
            // What the IPC `state` answers: the rules' describe() (no secret, nothing that
            // times keystrokes), plus a few facts only the driver knows
            describe: () => {
                const described = LockRules.describe(state);
                described.driver = {
                    secure: _sessionLock.secure,
                    sessionInForce: sessionInForce,
                    surfaces: surfaceIds.size,
                    screensaverVisible: root.screensaverVisible,
                    inhibitorRunning: _inhibitor.running,
                    logindSession: _logind.sessionPath,
                    lockScope: scope !== null,
                    watchFiles: Quickshell.watchFiles,
                    passwordFallbackKnown: fallbackKnown,
                    capsLock: root._capsLock
                };
                return JSON.stringify(described);
            }
        };

        publish();
        dispatch({ type: "started" });
        probeFallback();
        return api;
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

    // ---- What the password fallback depends on ----
    // One word per line for what holds: the system-wide password config readable, NixOS
    Process {
        id: _fallbackProbe
        signal answered(var lines)
        property var _lines: []
        command: ["sh", "-c", "test -r \"$1/h2s-shell-password\" && echo readable; test -e /etc/NIXOS && echo nixos; exit 0",
            "sh", root._systemPamDirectory]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => _fallbackProbe._lines = _fallbackProbe._lines.concat([line])
        }
        onRunningChanged: {
            if (running)
                return;
            const lines = _lines;
            _lines = [];
            answered(lines);
        }
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

    // ---- Idle: the screensaver, and locking after it ----
    // Through IdleWatch, which makes a new IdleMonitor whenever `enabled` or `timeout`
    // change: changing them on a live IdleMonitor can leave its `isIdle` false for good in
    // Quickshell 0.3.2 (see IdleWatch.qml) — the screensaver and the idle lock never came.

    IdleWatch {
        id: _screensaverMonitor
        enabled: root.screensaverEnabled
        timeout: root.screensaverTimeout
        onIsIdleChanged: root._idleChanged(isIdle)
    }

    // Lock a while after the screensaver started
    Timer {
        interval: root.lockscreenTimeout * 1000
        running: root.lockscreenEnabled && root.screensaverEnabled && _screensaverMonitor.isIdle && !root.locked
        repeat: false
        onTriggered: root.lock("idle")
    }

    // Lock without a screensaver
    IdleWatch {
        enabled: root.lockscreenEnabled && !root.screensaverEnabled
        timeout: root.lockscreenTimeout
        onIsIdleChanged: if (isIdle) root.lock("idle")
    }

    // ---- Screensaver commands ----
    // Tied to idleness, not to the screensaver being on screen: when the screen locks
    // during a screensaver, the screensaver hides under the lock screen while the user is
    // still away, so "ended" there would be wrong. The end command runs when the user is
    // back — activity, even at the lock prompt — and only after a start command, so a
    // profile switching the screensaver off mid-idle does not fire an unpaired end.
    property bool _idleSession: false

    function _runCommand(key) {
        const command = Profiles.value(key) ?? "";
        if (Profiles.value("lockscreen.screensaverCommands") === true && command.trim() !== "")
            Quickshell.execDetached(["sh", "-c", command]);
    }

    function _idleChanged(idle) {
        if (idle && !_idleSession) {
            _idleSession = true;
            _runCommand("lockscreen.screensaverStartCommand");
        } else if (!idle && _idleSession) {
            _idleSession = false;
            _runCommand("lockscreen.screensaverEndCommand");
        }
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

        function status(): string {
            return root.locked ? "locked" : "unlocked";
        }

        // What the lock test bed reads to know where the lock stands: the rules' describe()
        // (no secret, no typed text, nothing that times keystrokes), plus a few facts only
        // the driver knows — the compositor's `secure`, the session of the last
        // lockCompositor, the surface instances registered, whether the screensaver shows,
        // the helpers running, file watching, whether the password fallback is known
        function state(): string {
            return root._api?.describe() ?? "{}";
        }
    }
}
