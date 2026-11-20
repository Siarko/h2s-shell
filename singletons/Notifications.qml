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
    readonly property var _toastScreenSettings: ({
        screen: Profiles.value("notifications.toastScreen") ?? "",
        fullscreen: Profiles.value("notifications.toastFullscreen") ?? "show",
        fullscreenScreen: Profiles.value("notifications.toastFullscreenScreen") ?? ""
    })
    readonly property string toastScreen: ToastRules.screenFor(_toastScreenSettings, screensOverride ?? Workspaces.screens)
    // The screen critical toasts show on: the same, except that "Don't show" over a
    // fullscreen window leaves them there
    readonly property string criticalToastScreen: ToastRules.screenFor(_toastScreenSettings, screensOverride ?? Workspaces.screens, true)
    // A fullscreen window on the toasts' screen hides all but the critical toasts
    readonly property bool _fullscreenHidden: toastScreen === "" && criticalToastScreen !== ""
    // The screens a suite stands in for the compositor's (Workspaces.screens' shape), so a
    // toast has a screen to go to there; null: the compositor's
    property var screensOverride: null
    onToastScreenChanged: {
        if (toastScreen !== "")
            return;
        // Over a fullscreen window ("Don't show") only the critical toasts stay; with no
        // screen at all everything goes
        if (criticalToastScreen !== "")
            _applyToasts(ToastRules.fullscreenHid(toastState).state);
        else
            clearHudQueue();
        clearShellQueue();
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
            // Its queue takes it when it can (ToastRules.accepts): toasts on, a screen for
            // it, and not an ordinary one while the centre is open (seen there)
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

            // Said by id, for the shell's own sender (Notifier's handles). Its toast follows
            // the closing itself (_watchToast)
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

    // ---- Toasts: three queues (ToastRules) ----
    // Toasts stack in three queues, top to bottom: critical, staying (they stay until taken
    // away), ordinary (they count down). Each shows up to its limit (toastLimits); the rest
    // wait, oldest first, counted on the queue's badge. The queues' state is one plain
    // object of ids (ToastRules.emptyState's shape), changed only through the rules and
    // always replaced, never mutated: a toast shows only when the state says so, so no
    // stale slot can show or hold one.
    property var toastState: ToastRules.emptyState()
    // The notification objects in the state, by id (the state holds ids only)
    property var _toastObjects: ({})
    // Each toast's timing in the state, by id: its kind (ToastRules.timing) and its time in
    // ms, 0 when it stays
    property var toastKinds: ({})
    property var toastDurations: ({})
    // The screen each shown toast went to, by id: it stays there while the toasts' screen
    // moves on
    property var toastScreens: ({})
    // How many each queue shows at once
    readonly property var toastLimits: ToastRules.limits({
        critical: Profiles.value("notifications.criticalToastLimit") ?? 1,
        staying: Profiles.value("notifications.stayingToastLimit") ?? 1,
        layout: Profiles.value("notifications.toastLayout") ?? "queue",
        columnSize: Profiles.value("notifications.toastColumnSize") ?? 3
    })
    // The toasts that count down now (ToastRules.counting): in the ordinary queue the
    // sender's time at once and the user's time one at a time, the oldest first; elsewhere
    // one that no longer stays, at once. Derived from the state, so a toast that leaves or
    // changes queue hands the count on at once — nothing has to give it back.
    readonly property var countingToasts: ToastRules.counting(toastState, toastKinds)
    // How many wait in each queue: { critical, staying, ordinary }
    readonly property var toastBadges: ToastRules.badges(toastState)
    // The waiting notifications, all queues, oldest first
    readonly property var hudQueue: {
        const waiting = toastState.waiting;
        return waiting.critical.concat(waiting.staying, waiting.ordinary).sort((left, right) => left - right)
            .map(id => _toastObjects[id] ?? null).filter(notification => notification !== null);
    }
    // The state changed or the limits did: the toasts' screen shows what now fits
    signal roomForToasts
    onToastStateChanged: roomForToasts()
    onToastLimitsChanged: roomForToasts()

    // A critical notification is outlined in red, and its toast stays until taken away, as
    // the notification spec asks (a battery about to die, the shell's authentication prompt
    // failing)
    function isCritical(notification) {
        return notification?.urgency === NotificationUrgency.Critical;
    }

    // How long a notification's toast shows (ToastRules.timing): the time its sender asks
    // for, unless the user turned that off; the user's time when the sender leaves it to us.
    // A resident one stays unless the user hides resident ones; the shell's own progress
    // handles (x-qs-progress-run) are resident by make, so not that rule's.
    function toastTiming(notification) {
        return ToastRules.timing({
            expireTimeout: notification?.expireTimeout,
            critical: isCritical(notification),
            defaultSeconds: Profiles.value("notifications.toastDuration") ?? 5,
            followSender: Profiles.value("notifications.followSenderTime") !== false,
            resident: notification?.resident === true,
            residentHide: Profiles.value("notifications.residentHide") === true,
            shellJob: typeof notification?.hints?.["x-qs-progress-run"] === "string"
        });
    }

    // The queue a notification's toast belongs to, by its timing
    function toastQueue(notification, timing) {
        return ToastRules.queueFor({ critical: isCritical(notification), timingKind: (timing ?? toastTiming(notification)).kind });
    }

    // Where a toast is now: { place: "waiting" | "shown" | "moved" | "none", queue }
    function toastPlace(id) {
        return ToastRules.where(toastState, id);
    }

    function toastObject(id) {
        return _toastObjects[id] ?? null;
    }

    // What the queues take now (ToastRules.accepts)
    function _toastConditions() {
        return { toastsOn: _toastsOn, hasScreen: criticalToastScreen !== "", centreOpen: hudPanelOpen,
                 fullscreenHidden: _fullscreenHidden };
    }

    // The queues as `next` says, the maps kept to what is still in them
    function _applyToasts(next) {
        if (next === toastState)
            return;
        toastState = next;
        _pruneToasts();
        _logQueues();
    }

    function _setToastTiming(id, timing) {
        if (toastKinds[id] !== timing.kind) {
            const kinds = Object.assign({}, toastKinds);
            kinds[id] = timing.kind;
            toastKinds = kinds;
        }
        if (toastDurations[id] !== timing.ms) {
            const durations = Object.assign({}, toastDurations);
            durations[id] = timing.ms;
            toastDurations = durations;
        }
    }

    // The maps keep only the ids still in the state
    function _pruneToasts() {
        const keep = id => ToastRules.where(toastState, id).place !== "none";
        const pruned = map => {
            const ids = Object.keys(map);
            if (ids.every(id => keep(Number(id))))
                return map;
            const kept = {};
            for (const id of ids) {
                if (keep(Number(id)))
                    kept[id] = map[id];
            }
            return kept;
        };
        _toastObjects = pruned(_toastObjects);
        toastKinds = pruned(toastKinds);
        toastDurations = pruned(toastDurations);
        toastScreens = pruned(toastScreens);
    }

    // The notifications whose changes a toast follows, by id
    property var _toastWatched: ({})

    // A toast follows its notification: a new time from its sender (a job ending), a new
    // urgency or residency moves it to another queue; closed or dismissed, it goes, shown or
    // waiting
    function _watchToast(notification) {
        const id = notification.id;
        if (_toastWatched[id] === notification)
            return;
        const watched = Object.assign({}, _toastWatched);
        watched[id] = notification;
        _toastWatched = watched;
        const retime = () => root._retime(id, notification);
        for (const change of ["expireTimeoutChanged", "urgencyChanged", "residentChanged", "hintsChanged"]) {
            if (notification[change] !== undefined)
                notification[change].connect(retime);
        }
        if (notification.closed !== undefined)
            notification.closed.connect(() => root._toastEnded(id, notification));
        if (notification.trackedChanged !== undefined) {
            notification.trackedChanged.connect(() => {
                if (notification.tracked === false)
                    root._toastEnded(id, notification);
            });
        }
    }

    // Its notification is over: its toast goes, and nothing follows it any more
    function _toastEnded(id, notification) {
        if (_toastObjects[id] === notification)
            toastGone(id);
        if (_toastWatched[id] === notification) {
            const watched = Object.assign({}, _toastWatched);
            delete watched[id];
            _toastWatched = watched;
        }
    }

    // A toast's timing again, after its notification or a setting changed: its time, and
    // its queue — a waiting one moves to its new queue by age (a job ending while it waits
    // in staying goes to ordinary), a shown ordinary one that now stays goes up to its new
    // queue, a shown critical or staying one keeps its place and counts there
    function _retime(id, notification) {
        if (_toastObjects[id] !== notification || ToastRules.where(toastState, id).place === "none"
                || !_waitingAlive(notification))
            return;
        const timing = toastTiming(notification);
        _setToastTiming(id, timing);
        const queue = toastQueue(notification, timing);
        const before = ToastRules.where(toastState, id);
        // One that no queue takes now leaves the state, and the maps with it
        if (queue !== before.queue)
            _applyToasts(ToastRules.requeue(toastState, id, queue, _toastConditions(), toastLimits));
    }

    // A setting that changes every toast's time (how long, "Apps choose how long", resident
    // hide): every toast in the state again
    readonly property string _timingSettings: JSON.stringify([Profiles.value("notifications.toastDuration") ?? 5,
        Profiles.value("notifications.followSenderTime") !== false, Profiles.value("notifications.residentHide") === true])
    on_TimingSettingsChanged: {
        for (const id of Object.keys(_toastObjects))
            _retime(Number(id), _toastObjects[id]);
    }

    // Toasts switched off — by the user or a profile — drop the ones still waiting, in every
    // queue; those on screen end as they would
    readonly property bool _toastsOn: Profiles.value("notifications.toasts") !== false
    on_ToastsOnChanged: {
        if (!_toastsOn) {
            _applyToasts(ToastRules.dropWaiting(toastState).state);
            hudQueueCleared();
        }
    }

    property bool hudPanelOpen: false

    signal hudQueueCleared

    // A new toast waits in its queue, by age, when that queue takes it now
    // (_toastConditions); one already in a queue or on screen stays where it is
    function enqueueHudNotification(notification) {
        if (!_waitingAlive(notification))
            return;
        const id = notification.id;
        const timing = toastTiming(notification);
        const next = ToastRules.enqueue(toastState, id, toastQueue(notification, timing), _toastConditions());
        if (next === toastState)
            return;
        _watchToast(notification);
        const objects = Object.assign({}, _toastObjects);
        objects[id] = notification;
        _toastObjects = objects;
        _setToastTiming(id, timing);
        toastState = next;
        _logQueues();
    }

    // The pull form: a free place of `queue` on `screenName` (that queue's screen) takes its
    // oldest waiting toast — or null, while that queue is full, nothing waits, or it takes
    // nothing now (the centre open: ordinary ones). One freed or dismissed while it waited is
    // dropped, never shown.
    function takeToast(queue, screenName) {
        const queueScreen = queue === "critical" ? criticalToastScreen : toastScreen;
        if (screenName === undefined || screenName === "" || screenName !== queueScreen
                || !ToastRules.accepts(queue, _toastConditions()))
            return null;
        for (;;) {
            const id = ToastRules.nextWaiting(toastState, queue, toastLimits);
            if (id < 0)
                return null;
            const notification = _toastObjects[id] ?? null;
            if (!_waitingAlive(notification)) {
                toastGone(id);
                continue;
            }
            const screens = Object.assign({}, toastScreens);
            screens[id] = screenName;
            toastScreens = screens;
            toastState = ToastRules.show(toastState, id);
            _logQueues();
            return notification;
        }
    }

    // Every queue of the toasts' screen takes what fits, critical first
    function fillToasts(screenName) {
        for (const queue of ToastRules.queues) {
            while (takeToast(queue, screenName) !== null) {}
        }
    }

    // "×" on a toast (or its swipe): the notification is dismissed — its entry leaves the
    // centre, and a job's handle learns it as from the centre (onDismissed); the job goes on
    function dismissToast(id) {
        const notification = _toastObjects[id] ?? null;
        if (_waitingAlive(notification))
            notification.dismiss();
        toastGone(id);
    }

    // A toast is over — its time ran out, "×", an action, its notification closed: off the
    // screen and out of its queue, so the next in line takes its place
    function toastGone(id) {
        if (ToastRules.where(toastState, id).place === "none")
            return;
        toastState = ToastRules.remove(toastState, id);
        _pruneToasts();
        _logQueues();
    }

    // "critical 1/1 shown, 1 wait; …", logged when it changes
    property string _queuesLogged: ""
    function _logQueues() {
        const line = ToastRules.queues.map(queue => queue + " " + ToastRules.describe(toastState, toastLimits, queue)).join("; ");
        if (line === _queuesLogged)
            return;
        _queuesLogged = line;
        console.debug("[Notifications] toasts: " + line);
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
        const effect = ToastRules.announceEffect(toastState, notification.id, Object.assign(_toastConditions(), {
            alive: _waitingAlive(notification),
            queue: toastQueue(notification)
        }));
        if (effect === "restart")
            toastRestartRequested(notification.id);
        else if (effect === "queue")
            enqueueHudNotification(notification);
    }

    function _waitingAlive(notification) {
        return notification !== null && notification !== undefined && notification.tracked !== false;
    }

    // The centre opened: the ordinary toasts go, shown and waiting (it shows them);
    // critical, staying and modal ones stay, and new ones of those still show meanwhile
    function setHudPanelOpen(open) {
        hudPanelOpen = open;
        if (open) {
            _applyToasts(ToastRules.centreOpened(toastState).state);
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

    // Every toast goes, shown and waiting, in every queue
    function clearHudQueue() {
        toastState = ToastRules.emptyState();
        _pruneToasts();
        _logQueues();
        hudQueueCleared();
    }
}
