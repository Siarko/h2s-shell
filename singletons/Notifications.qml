pragma Singleton

import Quickshell
import Quickshell.Services.Notifications
import QtQml

Singleton {
    id: root
    property alias notifications: server.trackedNotifications
    // Map of notification id -> arrival timestamp string (hh:mm:ss)
    property var timestamps: ({})
    // Map of notification id -> string[] of extracted codes matching the notifications.codePatterns setting
    property var extractedCodes: ({})

    NotificationServer {
        id: server

        bodyHyperlinksSupported: true
        bodyMarkupSupported: true
        // Images in a body are not loaded (NotificationMarkup: a row linking to them)
        bodyImagesSupported: false
        actionIconsSupported: true
        imageSupported: true
        actionsSupported: true
        // A reply typed on the card (NotificationReply), sent back with sendInlineReply
        inlineReplySupported: true

        onNotification: notification => {
            if (isShellNotification(notification)) {
                // Copy summary immediately — the notification object is not tracked
                // and may be freed by Quickshell before ShellNotificationHudItem reads it
                shellQueue = shellQueue.concat([{ summary: notification.summary }]);
                return;
            }

            // Timestamp and codes first, tracking last: tracking adds the notification to
            // the list, and a card created right then has to find both already there.
            // Both maps are reassigned, not mutated — an in-place change emits no signal,
            // so a card would never see a value that arrived after it.
            var now = new Date();
            var h = String(now.getHours()).padStart(2, '0');
            var m = String(now.getMinutes()).padStart(2, '0');
            var s = String(now.getSeconds()).padStart(2, '0');
            var updatedTimestamps = Object.assign({}, timestamps);
            updatedTimestamps[notification.id] = h + ":" + m + ":" + s;
            timestamps = updatedTimestamps;

            // Extract codes from summary + body using configured regex patterns
            // In the body's text, not its markup: a link's address or an entity's digits
            // are no code
            var text = (notification.summary ?? "") + " " + NotificationMarkup.plainText(notification.body);
            var codes = [];
            var patterns = Profiles.value("notifications.codePatterns") ?? [];
            for (var i = 0; i < patterns.length; i++) {
                var pat = patterns[i];
                if (!pat) continue;
                try {
                    var matches = text.match(new RegExp(pat, "g"));
                    if (matches) {
                        for (var j = 0; j < matches.length; j++) {
                            if (codes.indexOf(matches[j]) < 0)
                                codes.push(matches[j]);
                        }
                    }
                } catch(e) {}
            }
            if (codes.length > 0) {
                var updatedCodes = Object.assign({}, extractedCodes);
                updatedCodes[notification.id] = codes;
                extractedCodes = updatedCodes;
            }

            notification.tracked = true;
            if (!hudPanelOpen && Profiles.value("notifications.toasts") !== false)
                enqueueHudNotification(notification);
            // One arriving while the panel is open is seen as it comes
            if (hudPanelOpen)
                markSeen();
            arrived();

            // A sender replacing it (same id) changes it in place — no new notification
            // comes, only new text
            notification.summaryChanged.connect(() => root._replaced(notification));
            notification.bodyChanged.connect(() => root._replaced(notification));

            // Remove timestamp and extracted codes when this notification is dismissed
            notification.trackedChanged.connect(function () {
                if (!notification.tracked) {
                    var remainingTimestamps = Object.assign({}, timestamps);
                    delete remainingTimestamps[notification.id];
                    timestamps = remainingTimestamps;
                    if (extractedCodes[notification.id]) {
                        var remaining = Object.assign({}, extractedCodes);
                        delete remaining[notification.id];
                        extractedCodes = remaining;
                    }
                }
            });
        }
    }

    signal dismissAllRequested
    signal openPanelRequested

    function isShellNotification(notification) {
        return (notification.hints["category"] ?? "") === "x-qs-shell";
    }

    function dismissAll() {
        dismissAllRequested();
    }

    // Shell notification queue (category: x-qs-shell) — bottom pill toast
    property var shellQueue: []
    signal shellQueueCleared

    function dequeueShellNotification() {
        if (shellQueue.length === 0) return null;
        const item = shellQueue[0];
        shellQueue = shellQueue.slice(1);
        return item;
    }

    function clearShellQueue() {
        shellQueue = [];
        shellQueueCleared();
    }

    // HUD queue — shared across all HUD instances
    property var hudQueue: []
    // Ids of the toasts on screen, oldest first. Only the oldest counts down to its
    // dismissal; the others wait their turn, so a column of toasts leaves one at a time.
    property var shownToasts: []

    function toastShown(id) {
        shownToasts = shownToasts.concat([id]);
    }

    function toastGone(id) {
        shownToasts = shownToasts.filter(shown => shown !== id);
    }

    // Toasts switched off — by the user or a profile — drop the ones still waiting
    readonly property bool _toastsOn: Profiles.value("notifications.toasts") !== false
    on_ToastsOnChanged: if (!_toastsOn) clearHudQueue()

    property bool hudPanelOpen: false

    // hudQueueChanged is auto-generated by the property above
    signal hudQueueCleared

    function enqueueHudNotification(notification) {
        hudQueue = hudQueue.concat([notification]);
    }

    function dequeueHudNotification() {
        if (hudQueue.length === 0)
            return null;
        const item = hudQueue[0];
        hudQueue = hudQueue.slice(1);
        return item;
    }

    function setHudPanelOpen(open) {
        hudPanelOpen = open;
        if (open) {
            clearHudQueue();
            markSeen();
        }
    }

    // How many notifications the panel holds, and how many came since it was last open —
    // the bell widget shows the first and keeps ringing for the second ("until opened").
    // Ids only grow, so "seen" is the highest id the panel has shown — and a seen one that
    // its sender replaced since is unread again, by id in `_replacedSince`.
    readonly property int count: notifications.values.length
    property int _seenUpTo: 0
    property var _replacedSince: []
    readonly property int unreadCount: notifications.values.filter(notification => notification.id > _seenUpTo
        || _replacedSince.includes(notification.id)).length

    // A notification came — a new one, or a seen one replaced — for the bell to ring
    signal arrived()

    function markSeen() {
        _seenUpTo = notifications.values.reduce((highest, notification) => Math.max(highest, notification.id), _seenUpTo);
        _replacedSince = [];
    }

    // A replacement is news only if what it replaces was seen: a sender updating its
    // notification again and again (a download's progress, what is playing) rings once
    // between two openings of the panel, not at every update
    function _replaced(notification) {
        if (!notification.tracked || hudPanelOpen)
            return;
        const unread = notification.id > _seenUpTo || _replacedSince.includes(notification.id);
        if (unread)
            return;
        _replacedSince = _replacedSince.concat([notification.id]);
        arrived();
    }
    // The server keeps its notifications over a reload of the shell; this count starts
    // afresh — so what is there when it starts counts as seen, or after every reload each
    // one was unread again and the bell rang ("until opened") until the panel was opened
    Component.onCompleted: Qt.callLater(markSeen)

    function clearHudQueue() {
        hudQueue = [];
        hudQueueCleared();
    }
}
