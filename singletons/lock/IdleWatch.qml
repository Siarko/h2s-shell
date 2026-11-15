import QtQuick
import Quickshell.Wayland

// An IdleMonitor (ext-idle-notify) made anew whenever its parameters change, instead of
// changing them on a live one — which, in Quickshell 0.3.2, can leave `isIdle` false for
// good (observed in the lock test bed, tests/lock/tests/idle.sh). The monitor deletes its
// notification and creates the next one, which the allocator often puts at the very same
// address; the property holding it then does not change, so `isIdle`, bound to the old
// notification's state, is never evaluated again (src/wayland/idle_notify/monitor.cpp:
// updateNotification). Every monitor starts with the shell's default timeout and gets the
// configured one a moment later, when the profiles are read: the screensaver and the idle
// lock never came. A new monitor starts from no notification, so its first one is always a
// change.
Item {
    id: root

    property bool enabled: false
    // Seconds
    property int timeout: 300
    readonly property bool isIdle: _loader.item?.isIdle ?? false
    // The IdleMonitor in use, null while disabled (for tests/LockViewTest.qml)
    readonly property var monitor: _loader.item

    // The parameters the current monitor was made with
    property bool _madeEnabled: false
    property int _madeTimeout: 0

    function _remake() {
        if (_loader.active && enabled === _madeEnabled && timeout === _madeTimeout)
            return;
        _loader.active = false;
        _madeEnabled = enabled;
        _madeTimeout = timeout;
        _loader.active = enabled;
    }

    // Both may change in one pass (a profile switch): remake once, after it
    onEnabledChanged: Qt.callLater(_remake)
    onTimeoutChanged: Qt.callLater(_remake)
    Component.onCompleted: _remake()

    Loader {
        id: _loader
        active: false
        sourceComponent: IdleMonitor {
            enabled: true
            timeout: root._madeTimeout
        }
    }
}
