pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.singletons
import qs.screensaver

Singleton {
    id: root

    readonly property bool screensaverVisible: _ssMonitor.isIdle || locked
    readonly property bool locked: _lock.locked

    // True when any one LockSurface has the prompt active — prevents multi-monitor duplication
    property bool promptActive: false

    onLockedChanged: {
        if (!locked)
            promptActive = false
        Profiles.screenLocked = locked
        if (locked)
            LockAuth.begin()
        else
            LockAuth.end()
    }

    // The one way out of a locked screen: LockAuth saw a password, finger or key it accepts
    Connections {
        target: LockAuth
        function onAuthenticated() { root.unlock() }
    }

    function lock() { _lock.locked = true }
    function unlock() { _lock.locked = false }

    // From the active profile (docs/plans/global-profiles.md)
    readonly property bool screensaverEnabled: Profiles.value("lockscreen.screensaverEnabled") ?? false
    readonly property int screensaverTimeout: Profiles.value("lockscreen.screensaverTimeout") ?? 300
    readonly property bool lockscreenEnabled: Profiles.value("lockscreen.lockscreenEnabled") ?? false
    readonly property int lockscreenTimeout: Profiles.value("lockscreen.lockscreenTimeout") ?? 300
    readonly property bool lockOnSleep: Profiles.value("lockscreen.lockOnSleep") ?? true

    // The idle monitors are switched on and off here rather than bound: a timeout change
    // only takes effect when the Wayland idle notification is recreated, by toggling the
    // monitor. Deferred so the timeout binding has updated first. Applied once at start,
    // and whenever a profile changes the values.
    function _applyMonitors() {
        Qt.callLater(() => {
            _ssMonitor.enabled = false
            _lockMonitor.enabled = false
            _ssMonitor.enabled = root.screensaverEnabled
            _lockMonitor.enabled = root.lockscreenEnabled && !root.screensaverEnabled
        })
    }

    onScreensaverEnabledChanged: _applyMonitors()
    onScreensaverTimeoutChanged: _applyMonitors()
    onLockscreenEnabledChanged: _applyMonitors()
    onLockscreenTimeoutChanged: _applyMonitors()
    Component.onCompleted: {
        _applyMonitors()
        _sessionMonitor.running = true
        _sleepMonitor.running = true
        _holdInhibitor()
    }

    // ---- Screensaver commands ----
    // Tied to idleness, not to the screensaver being on screen: when the screen locks
    // during a screensaver, the screensaver hides under the lock screen while the user is
    // still away, so "ended" there would be wrong. The end command runs when the user is
    // back — activity, even at the lock prompt — and only after a start command, so a
    // profile switching the screensaver off mid-idle does not fire an unpaired end.
    property bool _idleSession: false

    function _runCommand(key) {
        const command = Profiles.value(key) ?? ""
        if (Profiles.value("lockscreen.screensaverCommands") === true && command.trim() !== "")
            Quickshell.execDetached(["sh", "-c", command])
    }

    function _idleChanged(idle) {
        if (idle && !_idleSession) {
            _idleSession = true
            _runCommand("lockscreen.screensaverStartCommand")
        } else if (!idle && _idleSession) {
            _idleSession = false
            _runCommand("lockscreen.screensaverEndCommand")
        }
    }

    IdleMonitor {
        id: _ssMonitor
        enabled: false
        timeout: root.screensaverTimeout
        onIsIdleChanged: root._idleChanged(isIdle)
    }

    Timer {
        interval: root.lockscreenTimeout * 1000
        running: root.lockscreenEnabled && root.screensaverEnabled
                 && _ssMonitor.isIdle && !root.locked
        repeat: false
        onTriggered: root.lock()
    }

    // Lock without screensaver: dedicated IdleMonitor
    IdleMonitor {
        id: _lockMonitor
        enabled: false
        timeout: root.lockscreenTimeout
        onIsIdleChanged: if (isIdle) root.lock()
    }

    WlSessionLock {
        id: _lock
        LockSurface {}
    }

    // ---- Lock requests from outside ----
    // h2s-shell ipc call lockscreen lock       (Arch: launch.sh ipc call ...)
    // h2s-shell ipc call lockscreen status
    // h2s-shell ipc call lockscreen state      (JSON, for tests/lock/)
    // No unlock here: that would let any program skip the password prompt.
    IpcHandler {
        target: "lockscreen"

        function lock(): string {
            root.lock();
            return status();
        }

        function status(): string {
            return root.locked ? "locked" : "unlocked";
        }

        // What the lock test bed (tests/lock/) reads to know where the lock stands, as
        // JSON. Read-only, and nothing secret: no typed text. `locked` is the shell's
        // own mirror, which everything here acts on; `sessionLockLocked` is the
        // WlSessionLock's property read at this moment, and `secure` whether the
        // compositor confirmed the lock — they can disagree, which is the point.
        function state(): string {
            const passive = method => ({
                available: method.available,
                waiting: method.waiting,
                message: method.message,
                messageIsError: method.messageIsError
            });
            return JSON.stringify({
                locked: root.locked,
                sessionLockLocked: _lock.locked,
                secure: _lock.secure,
                promptActive: root.promptActive,
                screensaverVisible: root.screensaverVisible,
                auth: {
                    active: LockAuth._active,
                    verifying: LockAuth.verifying,
                    awaitingInput: LockAuth.awaitingInput,
                    question: LockAuth.question,
                    error: LockAuth.error,
                    passwordConfig: LockAuth._passwordConfig === "" ? ""
                        : LockAuth._passwordDirectory + "/" + LockAuth._passwordConfig,
                    fingerprint: passive(LockAuth.fingerprint),
                    securityKey: passive(LockAuth.securityKey)
                }
            });
        }
    }

    // systemd-logind asks the session to lock by emitting the Lock signal on the session's
    // DBus object: for `loginctl lock-session`, and for a power key or lid switch set to
    // "lock" in logind.conf. Somebody in the session has to listen, and that is this
    // long-running `gdbus monitor` on the shell's own session. logind's Unlock signal is
    // deliberately not acted on, for the same reason the IPC has no unlock.
    Process {
        id: _sessionMonitor
        command: ["sh", "-c", "session=$(gdbus call --system --dest org.freedesktop.login1"
            + " --object-path /org/freedesktop/login1"
            + " --method org.freedesktop.login1.Manager.GetSession \"$XDG_SESSION_ID\" | cut -d\"'\" -f2);"
            + " [ -n \"$session\" ] || exit 1;"
            + " exec gdbus monitor --system --dest org.freedesktop.login1 --object-path \"$session\""]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line.includes("org.freedesktop.login1.Session.Lock "))
                    root.lock()
            }
        }

        // Without a logind session (XDG_SESSION_ID unset) or after logind restarts, the
        // monitor exits: try again later rather than lose the power key for good
        onRunningChanged: if (!running) _monitorRestart.start()
    }

    // ---- Sleep ----
    // logind says when the machine is about to sleep and when it is back
    // (PrepareForSleep true, then false). Before sleep the screen locks, if the setting
    // says so, and the fingerprint and security key conversations stop: their devices go
    // away over a suspend. After it they start again.
    //
    // Locking takes a moment, and logind does not wait for it by itself: the machine
    // would sleep with the desktop still shown and wake showing it. So the shell holds a
    // "delay" inhibitor lock, which makes logind wait (up to its InhibitDelayMaxSec, 5 s
    // by default) until the lock is released — done once the compositor confirms the
    // screen is covered.
    property bool _goingToSleep: false

    function _sleepChanged(goingToSleep) {
        _goingToSleep = goingToSleep
        if (goingToSleep) {
            LockAuth.pause()
            if (lockOnSleep) {
                lock()
                if (_lock.secure)
                    _releaseInhibitor()
                else
                    _inhibitorFallback.restart()
            }
        } else {
            LockAuth.resume()
            _holdInhibitor()
        }
    }

    function _holdInhibitor() {
        if (lockOnSleep && !_sleepInhibitor.running)
            _sleepInhibitor.running = true
    }

    function _releaseInhibitor() {
        _inhibitorFallback.stop()
        if (_sleepInhibitor.running)
            _sleepInhibitor.write("\n")
    }

    onLockOnSleepChanged: lockOnSleep ? _holdInhibitor() : _releaseInhibitor()

    Process {
        id: _sleepMonitor
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1",
            "--object-path", "/org/freedesktop/login1"]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line.includes("Manager.PrepareForSleep (true"))
                    root._sleepChanged(true)
                else if (line.includes("Manager.PrepareForSleep (false"))
                    root._sleepChanged(false)
            }
        }

        onRunningChanged: if (!running) _monitorRestart.start()
    }

    // Holds the inhibitor lock for as long as it runs: it ends when a line arrives on its
    // input (the release), or when the shell goes away and the input closes with it
    Process {
        id: _sleepInhibitor
        command: ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=h2s-shell",
            "--why=Lock the screen before sleep", "sh", "-c", "read -r release"]
        stdinEnabled: true
    }

    // The compositor not confirming the lock must not hold the sleep up for long
    Timer {
        id: _inhibitorFallback
        interval: 1500
        onTriggered: root._releaseInhibitor()
    }

    Connections {
        target: _lock
        function onSecureStateChanged() {
            if (_lock.secure && root._goingToSleep)
                root._releaseInhibitor()
        }
    }

    Timer {
        id: _monitorRestart
        interval: 10000
        onTriggered: {
            if (!_sessionMonitor.running)
                _sessionMonitor.running = true
            if (!_sleepMonitor.running)
                _sleepMonitor.running = true
        }
    }
}
