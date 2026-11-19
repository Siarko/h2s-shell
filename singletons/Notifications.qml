pragma Singleton

import Quickshell
import Quickshell.Services.Notifications
import QtQml

Singleton {
    id: root
    property alias notifications: server.trackedNotifications

    // The screen toasts show on — notifications' and the shell's messages — by port, or ""
    // for none: a fullscreen window there, by the settings (ToastRules). None: a toast is
    // not shown at all, the notification only in the panel; those waiting are dropped.
    readonly property string toastScreen: ToastRules.screenFor({
        screen: Profiles.value("notifications.toastScreen") ?? "",
        fullscreen: Profiles.value("notifications.toastFullscreen") ?? "show",
        fullscreenScreen: Profiles.value("notifications.toastFullscreenScreen") ?? ""
    }, screensOverride ?? Workspaces.screens)
    // The screens a suite stands in for the compositor's (Workspaces.screens' shape), so a
    // toast has a screen to go to there; null: the compositor's
    property var screensOverride: null
    onToastScreenChanged: {
        if (toastScreen === "") {
            clearHudQueue();
            clearShellQueue();
        }
    }
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
                // Nowhere to show it (a fullscreen window, ToastRules): dropped
                if (root.toastScreen === "")
                    return;
                // Copy summary immediately — the notification object is not tracked
                // and may be freed by Quickshell before ShellNotificationHudItem reads it
                shellQueue = shellQueue.concat([{ summary: notification.summary }]);
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
            if (!hudPanelOpen && Profiles.value("notifications.toasts") !== false && root.toastScreen !== "")
                enqueueHudNotification(notification);
            // One arriving while the panel is open is seen as it comes
            if (hudPanelOpen)
                markSeen();
            arrived();

            // A sender replacing it (same id) changes it in place — no new notification
            // comes, only new text
            notification.summaryChanged.connect(() => root._replaced(notification));
            notification.bodyChanged.connect(() => root._replaced(notification));
            root.watchAnnounces(notification);

            // Closed while its toast waits (its sender closed it, or it was dismissed in the
            // centre): out of the queue, where it would be shown, and counted on the badge.
            // And said by id, for the shell's own sender (Notifier's handles)
            const closedId = notification.id;
            notification.closed.connect(reason => {
                root._dropWaiting(notification);
                root.notificationClosed(closedId, reason);
            });

            // Remove timestamp and extracted codes when this notification is dismissed
            notification.trackedChanged.connect(function () {
                if (!notification.tracked) {
                    root._dropWaiting(notification);
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
    // Ids of the toasts on screen, oldest first. Only the oldest with the user's time
    // counts down to its dismissal; the others with that time wait their turn, so a column
    // of toasts leaves one at a time.
    property var shownToasts: []
    // Of those, the toasts with a time of their own (ToastRules.timing: "own" or "stays"):
    // a sender's time counts by itself, at once, and a toast that stays never counts — so
    // neither holds up the others, and the next with the user's time counts instead
    property var ownTimeToasts: []
    // Of those, the ones that stay until taken away: they take none of the layout's slots,
    // they stack above them (ToastRules.slots)
    property var stayingToasts: []
    // Each shown toast's time in ms, by id; 0: it stays
    property var toastDurations: ({})
    // The toast counting down the user's time now: the oldest without a time of its own
    readonly property var countingToast: shownToasts.find(id => !ownTimeToasts.includes(id)) ?? null

    // Room on screen (ToastRules.slots): the layout's slots for toasts that count down,
    // toasts that stay above them up to their limit
    readonly property var toastRoom: ToastRules.slots(Profiles.value("notifications.toastLayout") ?? "queue",
        Profiles.value("notifications.toastColumnSize") ?? 3, stayingToasts.length,
        Profiles.value("notifications.maxStayingToasts") ?? 3)
    // A slot that was free may take a toast now: one left, changed its time, or the room grew
    signal roomForToasts
    onShownToastsChanged: roomForToasts()
    onToastRoomChanged: roomForToasts()

    // A critical notification is outlined in red, and its toast stays until taken away, as
    // the notification spec asks (a battery about to die, the shell's authentication prompt
    // failing)
    function isCritical(notification) {
        return notification?.urgency === NotificationUrgency.Critical;
    }

    // How long a notification's toast shows (ToastRules.timing): the time its sender asks
    // for, unless the user turned that off; the user's time when the sender leaves it to us
    function toastTiming(notification) {
        return ToastRules.timing({
            expireTimeout: notification?.expireTimeout,
            critical: isCritical(notification),
            defaultSeconds: Profiles.value("notifications.toastDuration") ?? 5,
            followSender: Profiles.value("notifications.followSenderTime") !== false
        });
    }

    function toastShown(id, timing) {
        shownToasts = shownToasts.concat([id]);
        toastTimed(id, timing);
    }

    // A shown toast's time, when it shows and whenever it changes (its sender replaced it
    // with another time, a setting changed)
    function toastTimed(id, timing) {
        if (!shownToasts.includes(id))
            return;
        const own = timing.kind !== "default";
        const stays = timing.kind === "stays";
        if (own !== ownTimeToasts.includes(id))
            ownTimeToasts = own ? ownTimeToasts.concat([id]) : ownTimeToasts.filter(shown => shown !== id);
        if (stays !== stayingToasts.includes(id))
            stayingToasts = stays ? stayingToasts.concat([id]) : stayingToasts.filter(shown => shown !== id);
        if (toastDurations[id] !== timing.ms) {
            const durations = Object.assign({}, toastDurations);
            durations[id] = timing.ms;
            toastDurations = durations;
        }
    }

    function toastGone(id) {
        shownToasts = shownToasts.filter(shown => shown !== id);
        ownTimeToasts = ownTimeToasts.filter(shown => shown !== id);
        stayingToasts = stayingToasts.filter(shown => shown !== id);
        if (toastDurations[id] !== undefined) {
            const durations = Object.assign({}, toastDurations);
            delete durations[id];
            toastDurations = durations;
        }
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

    // The next toast a free slot shows: the oldest waiting that has room on screen
    // (ToastRules.nextToast) — or null, and those waiting go on waiting. Taken and put on
    // the list of shown toasts in one step, before the queue changes: a change of the
    // queue makes every other free slot take one at once, and each must count this one.
    function takeHudNotification() {
        // One freed while it waited reads null: dropped, never shown
        if (hudQueue.some(notification => !_waitingAlive(notification)))
            hudQueue = hudQueue.filter(notification => _waitingAlive(notification));
        const kinds = hudQueue.map(notification => toastTiming(notification).kind);
        const index = ToastRules.nextToast(kinds, shownToasts.length - stayingToasts.length, toastRoom);
        if (index < 0)
            return null;
        const item = hudQueue[index];
        toastShown(item.id, toastTiming(item));
        hudQueue = hudQueue.slice(0, index).concat(hudQueue.slice(index + 1));
        return item;
    }

    // A shown toast is asked to start its time again (an announce), by id
    signal toastRestartRequested(int id)

    // The shell's own sender announcing a notification again (a replacement raising its
    // x-qs-announce, NotificationRules.announced) brings its toast back once, through the
    // queue like a new one — or, on screen, starts its time again. Every other replacement
    // leaves the toast as it is.
    function watchAnnounces(notification) {
        let seen = notification.hints?.["x-qs-announce"];
        notification.hintsChanged.connect(() => {
            const hints = notification.hints;
            const announcedNow = NotificationRules.announced(seen, hints, Notifier.progressRun);
            seen = hints?.["x-qs-announce"];
            if (announcedNow)
                root._announce(notification);
        });
    }

    function _announce(notification) {
        const effect = NotificationRules.announceEffect({
            toastsOn: _toastsOn,
            toastScreen: toastScreen,
            centreOpen: hudPanelOpen,
            alive: _waitingAlive(notification),
            shown: shownToasts.includes(notification.id),
            waiting: hudQueue.includes(notification)
        });
        if (effect === "restart")
            toastRestartRequested(notification.id);
        else if (effect === "queue")
            enqueueHudNotification(notification);
    }

    function _waitingAlive(notification) {
        return notification !== null && notification !== undefined && notification.tracked !== false;
    }

    function _dropWaiting(notification) {
        if (hudQueue.includes(notification))
            hudQueue = hudQueue.filter(waiting => waiting !== notification);
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
    Component.onCompleted: Qt.callLater(() => {
        markSeen();
        dismissOrphans();
    })

    function clearHudQueue() {
        hudQueue = [];
        hudQueueCleared();
    }
}
