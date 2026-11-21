pragma Singleton

import Quickshell
import QtQuick

// What the launcher hands the first shell it starts after the last launcher gave up on a
// shell that died while the screen was locked (scripts/launch.sh, "Restarts while locked"):
// H2S_SHELL_LOCK_NOTICE, the restarts it made. Said once, as one notification
// (LockIoRules.lockNotice), when the session is unlocked: under the lock nobody sees its
// toast. "Unlocked" only once the start has read the lock marker and is not taking a lock
// back from it (Lockscreen.startChecked, Lockscreen.restoring: while its question to
// Hyprland is pending, `locked` is still false over a session the compositor holds
// locked). Once per process: a reload does not say it again.
Singleton {
    id: root

    readonly property var _notice: LockIoRules.lockNotice(Quickshell.env("H2S_SHELL_LOCK_NOTICE") ?? "",
                                                          Quickshell.env("XDG_RUNTIME_DIR") ?? "")
    readonly property bool _settled: _notice !== null && Lockscreen.startChecked && !_sentOnce.sent
    readonly property bool _sessionLocked: Lockscreen.locked || Lockscreen.restoring
    readonly property bool _due: _settled && !_sessionLocked
    // Said once in the log while it waits (the lock test bed waits for this line)
    property bool _waitLogged: false

    on_SettledChanged: _logWait()
    on_SessionLockedChanged: _logWait()
    on_DueChanged: {
        if (!_due)
            return;
        _sentOnce.sent = true;
        console.info("[LockNotice] the session is unlocked: telling of the launcher that gave up");
        Notifier.send(_notice.summary, { body: _notice.body, urgency: "critical", format: "plain" });
    }

    function _logWait() {
        if (!_settled || !_sessionLocked || _waitLogged)
            return;
        _waitLogged = true;
        console.info("[LockNotice] the launcher gave up while locked: said once the session is unlocked");
    }

    PersistentProperties {
        id: _sentOnce
        property bool sent: false
    }
}
