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

    function dismissAll() {
        while (server.trackedNotifications.count > 0) {
            server.trackedNotifications.objectAt(0).dismiss();
        }
    }
}
