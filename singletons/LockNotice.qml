pragma Singleton

import Quickshell
import QtQuick

// What the launcher hands the first shell it starts after the last launcher gave up on a
// shell that died while the screen was locked (scripts/launch.sh, "Restarts while locked"):
// H2S_SHELL_LOCK_NOTICE, the restarts it made. Said once, as one notification
// (LockIoRules.lockNotice), when the session is unlocked: under the lock nobody sees its
// toast. "Unlocked" only once the start has had time to lock again from the marker
// (Lockscreen's start probe answers within a moment; a lock it takes back counts as locked
// from its request on). Once per process: a reload does not say it again.
Singleton {
    id: root

    readonly property var _notice: LockIoRules.lockNotice(Quickshell.env("H2S_SHELL_LOCK_NOTICE") ?? "",
                                                          Quickshell.env("XDG_RUNTIME_DIR") ?? "")
    property bool _settled: false
    readonly property bool _due: _notice !== null && _settled && !_sentOnce.sent && !Lockscreen.locked

    on_DueChanged: {
        if (!_due)
            return;
        _sentOnce.sent = true;
        Notifier.send(_notice.summary, { body: _notice.body, urgency: "critical", format: "plain" });
    }

    PersistentProperties {
        id: _sentOnce
        property bool sent: false
    }

    Timer {
        interval: 3000
        running: root._notice !== null && !root._settled
        onTriggered: root._settled = true
    }
}
