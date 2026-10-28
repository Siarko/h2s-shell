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

    onLockedChanged: if (!locked) promptActive = false

    function lock() { _lock.locked = true }
    function unlock() { _lock.locked = false }

    // enabled is set via callLater so timeout binding updates first
    Connections {
        target: Config.lockscreen
        function onScreensaverEnabledChanged() {
            Qt.callLater(() => {
                _ssMonitor.enabled = Config.lockscreen.screensaverEnabled
                _lockMonitor.enabled = Config.lockscreen.lockscreenEnabled && !Config.lockscreen.screensaverEnabled
            })
        }
        function onLockscreenEnabledChanged() {
            Qt.callLater(() => {
                _lockMonitor.enabled = Config.lockscreen.lockscreenEnabled && !Config.lockscreen.screensaverEnabled
            })
        }
        // Changing timeout requires recreating the Wayland idle notification object
        function onScreensaverTimeoutChanged() {
            Qt.callLater(() => {
                if (!_ssMonitor.enabled) return
                _ssMonitor.enabled = false
                _ssMonitor.enabled = true
            })
        }
        function onLockscreenTimeoutChanged() {
            Qt.callLater(() => {
                if (!_lockMonitor.enabled) return
                _lockMonitor.enabled = false
                _lockMonitor.enabled = true
            })
        }
    }

    IdleMonitor {
        id: _ssMonitor
        enabled: false
        timeout: Config.lockscreen.screensaverTimeout
        onIsIdleChanged: console.log("[Lockscreen] screensaver isIdle →", isIdle)
    }

    Timer {
        interval: Config.lockscreen.lockscreenTimeout * 1000
        running: Config.lockscreen.lockscreenEnabled && Config.lockscreen.screensaverEnabled
                 && _ssMonitor.isIdle && !root.locked
        repeat: false
        onTriggered: root.lock()
    }

    // Lock without screensaver: dedicated IdleMonitor
    IdleMonitor {
        id: _lockMonitor
        enabled: false
        timeout: Config.lockscreen.lockscreenTimeout
        onIsIdleChanged: if (isIdle) root.lock()
    }

    WlSessionLock {
        id: _lock
        LockSurface {}
    }
}
