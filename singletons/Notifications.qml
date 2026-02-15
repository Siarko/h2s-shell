pragma Singleton

import Quickshell
import Quickshell.Services.Notifications

Singleton {
    property alias notifications: server.trackedNotifications
    // Map of notification id -> arrival timestamp string (hh:mm:ss)
    property var timestamps: ({})

    NotificationServer {
        id: server

        // Track all incoming notifications so they appear in the panel
        onNotification: notification => {
            notification.tracked = true;
            var now = new Date();
            var h = String(now.getHours()).padStart(2, '0');
            var m = String(now.getMinutes()).padStart(2, '0');
            var s = String(now.getSeconds()).padStart(2, '0');
            timestamps[notification.id] = h + ":" + m + ":" + s;
        }
    }

    signal dismissAllRequested()

    function dismissAll() {
        dismissAllRequested();
    }
}
