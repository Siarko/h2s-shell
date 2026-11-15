import QtQuick
import qs.singletons

// The notifications as the screensaver and the lock screen list them: cards to look at,
// nothing to act on — no actions, no links, no images, no scrolling — at the detail their
// privacy setting allows (NotificationPreview).
//
// The model is the notification server's tracked list, an object model (a real
// QAbstractItemModel that reports rows added and removed), not a JS array: the
// Repeater/ListView crash comes from assigning a new array to `model`, which this never
// does (docs/ARCHITECTURE.md, "The Repeater crash"; the notifications panel does the same).
ListView {
    id: root

    // "full", "title" or "app" (NotificationPreview)
    property string detail: "app"

    clip: true
    spacing: 8
    interactive: false
    model: Notifications.notifications

    delegate: NotificationPreview {
        width: root.width
        detail: root.detail
    }
}
