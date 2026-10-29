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

    IdleMonitor {
        id: _ssMonitor
        enabled: false
        timeout: root.screensaverTimeout
        onIsIdleChanged: console.log("[Lockscreen] screensaver isIdle →", isIdle)
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
