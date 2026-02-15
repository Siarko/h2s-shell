pragma Singleton

import Quickshell
import Quickshell.Services.Notifications

Singleton {
    property alias notifications: server.trackedNotifications

    NotificationServer {
        id: server

        // Track all incoming notifications so they appear in the panel
        onNotification: notification => {
            notification.tracked = true;
        }
    }

    signal dismissAllRequested()

    function dismissAll() {
        dismissAllRequested();
    }
}
