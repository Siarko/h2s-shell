pragma Singleton

import QtQuick
import Quickshell
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
    }

    // From the active profile (docs/plans/global-profiles.md)
    readonly property bool screensaverEnabled: Profiles.value("lockscreen.screensaverEnabled") ?? false
    readonly property int screensaverTimeout: Profiles.value("lockscreen.screensaverTimeout") ?? 300
    readonly property bool lockscreenEnabled: Profiles.value("lockscreen.lockscreenEnabled") ?? false
    readonly property int lockscreenTimeout: Profiles.value("lockscreen.lockscreenTimeout") ?? 300

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
    Component.onCompleted: _applyMonitors()

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
}
