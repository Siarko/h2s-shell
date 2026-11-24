pragma Singleton

import Quickshell
import Quickshell.Services.Notifications
import QtQml

Singleton {
    id: root
    // The server's notifications; in an isolated process (Isolation), where no server is
    // registered on the session bus, an empty list
    readonly property var notifications: _server.item?.trackedNotifications ?? _none

    // Map of notification id -> arrival timestamp string (hh:mm:ss)
    property var timestamps: ({})
    // Map of notification id -> string[] of extracted codes matching the notifications.codePatterns setting
    property var extractedCodes: ({})

    ScriptModel {
        id: _none
        values: []
    }

    LazyLoader {
        id: _server
        active: !Isolation.active

        NotificationServer {
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
                    // Nowhere to show it (a fullscreen window, ToastRules): dropped
                    if (Toasts.toastScreen === "")
                        return;
                    // Copy summary immediately — the notification object is not tracked
                    // and may be freed by Quickshell before ShellNotificationHudItem reads it
                    Toasts.shellQueue = Toasts.shellQueue.concat([{ summary: notification.summary }]);
                    return;
                }

                // Left running by the shell's own sender before a reload (the server hands its
                // notifications to the new shell again): nothing will update or end it
                if (NotificationRules.orphaned(notification.hints, Notifier.progressRun)) {
                    notification.dismiss();
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
                // Its queue takes it when it can (ToastRules.accepts): toasts on, a screen for
                // it, and not an ordinary one while the centre is open (seen there)
                Toasts.enqueueHudNotification(notification);
                // One arriving while the panel is open is seen as it comes
                if (Toasts.hudPanelOpen)
                    markSeen();
                arrived();

                // A sender replacing it (same id) changes it in place — no new notification
                // comes, only new text
                notification.summaryChanged.connect(() => root._replaced(notification));
                notification.bodyChanged.connect(() => root._replaced(notification));
                Toasts.watchAnnounces(notification);

                // Said by id, for the shell's own sender (Notifier's handles). Its toast follows
                // the closing itself (Toasts._watchToast)
                const closedId = notification.id;
                notification.closed.connect(reason => root.notificationClosed(closedId, reason));

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
    }

    signal dismissAllRequested
    // A queue's badge clicked on `screen` (its name): the centre opens or closes there
    signal openPanelRequested(string screen)

    // For the shell's own sender (Notifier's progress handles), which learns a click and a
    // dismissal here, in-process, rather than from a process waiting on the bus: a tracked
    // notification closed (its id, NotificationCloseReason), and an action run on a card
    signal notificationClosed(int id, int reason)
    signal actionInvoked(int id, string actionId)

    // Whether the server holds a notification with this id now
    function tracks(id): bool {
        return notifications.values.some(notification => notification.id === id);
    }

    // The ids of the notifications the shell's own sender made with this run token and
    // handle mark (x-qs-progress-run, x-qs-progress-handle)
    function progressIds(run, handle) {
        if (typeof run !== "string" || run === "" || typeof handle !== "string" || handle === "")
            return [];
        return notifications.values.filter(notification => notification.hints?.["x-qs-progress-run"] === run
            && notification.hints?.["x-qs-progress-handle"] === handle).map(notification => notification.id);
    }

    // Runs one of a notification's actions, as its card does: the server sends it to the
    // sender, and it is said by id (actionInvoked)
    function invokeAction(notification, action) {
        if (!action)
            return;
        action.invoke();
        if (notification)
            actionInvoked(notification.id, String(action.identifier ?? ""));
    }

    // Dismisses what an earlier run of the shell's own sender left running (a reload made
    // a new Notifier): nothing will update or end it (NotificationRules.orphaned). Those
    // the server hands over again after a reload come through onNotification, which drops
    // them the same way; this catches any held already when the shell starts
    function dismissOrphans() {
        for (const notification of notifications.values.slice()) {
            if (NotificationRules.orphaned(notification.hints, Notifier.progressRun))
                notification.dismiss();
        }
    }

    function isShellNotification(notification) {
        return (notification.hints["category"] ?? "") === "x-qs-shell";
    }

    function dismissAll() {
        dismissAllRequested();
    }

    // A critical notification is outlined in red, and its toast stays until taken away, as
    // the notification spec asks (a battery about to die, the shell's authentication prompt
    // failing)
    function isCritical(notification) {
        return notification?.urgency === NotificationUrgency.Critical;
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
        if (!notification.tracked || Toasts.hudPanelOpen)
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
    Component.onCompleted: Qt.callLater(() => {
        markSeen();
        dismissOrphans();
    })

}
