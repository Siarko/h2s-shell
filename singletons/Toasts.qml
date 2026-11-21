pragma Singleton

import Quickshell
import QtQml

// The toasts of notifications and of the shell's own messages: where they show (the
// toasts' screen, by the settings and the screens), the shell's pill queue, the three
// toast queues and their timings, modals (toasts dragged out, notifications pinned from the
// centre), and what the HUD takes from them. Decisions are ToastRules'; the notifications
// themselves, their server and the centre's count are Notifications'.
Singleton {
    id: root

    // The screen toasts show on — notifications' and the shell's messages — by port, or ""
    // for none: a fullscreen window there, by the settings (ToastRules). None: a toast is
    // not shown at all, the notification only in the panel; those waiting are dropped.
    function _toastScreenSettings() {
        return {
            screen: Profiles.value("notifications.toastScreen") ?? "",
            fullscreen: Profiles.value("notifications.toastFullscreen") ?? "show",
            fullscreenScreen: Profiles.value("notifications.toastFullscreenScreen") ?? ""
        };
    }
    readonly property string toastScreen: ToastRules.screenFor(_toastScreenSettings(), screensOverride ?? Workspaces.screens)
    // The screen critical toasts show on: the same, except that "Don't show" over a
    // fullscreen window leaves them there
    readonly property string criticalToastScreen: ToastRules.screenFor(_toastScreenSettings(), screensOverride ?? Workspaces.screens, true)
    // A fullscreen window on the toasts' screen hides all but the critical toasts
    readonly property bool fullscreenHidden: toastScreen === "" && criticalToastScreen !== ""
    // The screens a suite stands in for the compositor's (Workspaces.screens' shape), so a
    // toast has a screen to go to there; null: the compositor's
    property var screensOverride: null
    onToastScreenChanged: _toastScreensChanged()
    onCriticalToastScreenChanged: _toastScreensChanged()
    // Either screen changed: both read afresh from the settings and the screens, not from
    // the two bindings — one of them may not have been brought up to date yet. No screen
    // for critical toasts (none for the others either): every toast goes; one for critical
    // toasts only (a fullscreen window, "Don't show"): only they stay.
    function _toastScreensChanged() {
        const settings = _toastScreenSettings();
        const screens = screensOverride ?? Workspaces.screens;
        const ordinary = ToastRules.screenFor(settings, screens);
        const critical = ToastRules.screenFor(settings, screens, true);
        if (critical === "")
            clearHudQueue();
        else if (ordinary === "")
            _applyToasts(ToastRules.fullscreenHid(toastState).state);
        if (ordinary === "")
            clearShellQueue();
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

    // How long a notification's toast shows (ToastRules.timing): the time its sender asks
    // for, unless the user turned that off; the user's time when the sender leaves it to us.
    // A resident one stays unless the user hides resident ones; the shell's own progress
    // handles (x-qs-progress-run) are resident by make, so not that rule's.
    function toastTiming(notification) {
        return ToastRules.timing({
            expireTimeout: notification?.expireTimeout,
            critical: Notifications.isCritical(notification),
            defaultSeconds: Profiles.value("notifications.toastDuration") ?? 5,
            followSender: Profiles.value("notifications.followSenderTime") !== false,
            resident: notification?.resident === true,
            residentHide: Profiles.value("notifications.residentHide") === true,
            shellJob: typeof notification?.hints?.["x-qs-progress-run"] === "string"
        });
    }

    // The queue a notification's toast belongs to, by its timing
    function toastQueue(notification, timing) {
        return ToastRules.queueFor({ critical: Notifications.isCritical(notification), timingKind: (timing ?? toastTiming(notification)).kind });
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
                 fullscreenHidden: fullscreenHidden };
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
        // A modal: its queue follows (where it waits again if its screen goes); one pinned
        // while it counted down, now staying (a job started again), is kept by its kind from
        // now on, so it counts when that ends
        if (before.place === "moved") {
            _applyToasts(ToastRules.modalRetimed(toastState, id, timing.kind, queue));
            return;
        }
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
    // Where the open notification centre is: { screen, x, y, width, height } in its screen's
    // coordinates, null while it is closed — the toasts on that screen move left of it
    // (ToastRules.stackEdge); the toasts' overlay is above it and would cover its cards
    property var centreArea: null

    // Told by each bar's popup: `area` while the centre is open in it, null when it closes or
    // shows another panel — which clears only that screen's, so another bar's popup, which
    // never showed the centre, cannot clear the one open elsewhere
    function setCentreArea(screen, area) {
        if (area === null || area === undefined) {
            if (centreArea !== null && centreArea.screen === screen)
                centreArea = null;
            return;
        }
        const next = { screen: screen, x: area.x, y: area.y, width: area.width, height: area.height };
        if (centreArea === null || JSON.stringify(centreArea) !== JSON.stringify(next))
            centreArea = next;
    }

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
    // `notification`: the toast's own, for one whose place in the queues is gone already
    // (its time ran out while it slid away)
    function dismissToast(id, notification) {
        notification = _toastObjects[id] ?? notification ?? null;
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

    // ---- Modals: toasts dragged out of their queue, notifications pinned from the centre ----
    // A modal is out of the queues: its slot is free for the next, and it stays at its place
    // on its screen until "×" (dismissed), unpinning, its sender closing it, or — a job that
    // ended — its countdown. The centre opening and toasts switched off leave it; a
    // fullscreen window with "Don't show" hides it until it goes. Positions are not kept over
    // a restart: what the server hands over again goes through its queue.

    // Dragging toasts by their title line (notifications.movableToasts): off, the ones moved
    // out stay where they are, and no new drag starts
    readonly property bool movableToasts: Profiles.value("notifications.movableToasts") !== false

    // Whether notification `id`'s toast can be dragged now (ToastRules.canMove)
    function canMoveToast(id): bool {
        return ToastRules.canMove(toastState, id, movableToasts);
    }

    // Whether notification `id` is a modal now
    function isModal(id): bool {
        return ToastRules.isModal(toastState, id);
    }

    // A toast dropped at (x, y) of its screen, already inside it (ToastRules.clampToScreen):
    // a modal there, its queue's slot free for the next
    function moveToast(id, x, y) {
        _applyToasts(ToastRules.moveOut(toastState, id, x, y, movableToasts));
    }

    // A pinned modal given its first place (the stack of its screen: ToastRules.pinSpot)
    function placeModal(id, x, y) {
        _applyToasts(ToastRules.placeModal(toastState, id, x, y));
    }

    // The centre's pin: the notification becomes a modal on `centreScreen` — the screen of
    // the centre it was pinned from (ToastRules.pinScreen; unknown: the toasts' screen) —
    // whether its toast is shown, waiting or long gone. Not without a screen; one that is a
    // modal already stays as it is. → whether it is a modal now
    function pinToast(notification, centreScreen): bool {
        if (!_waitingAlive(notification))
            return false;
        const id = notification.id;
        if (ToastRules.isModal(toastState, id))
            return true;
        const screen = ToastRules.pinScreen(centreScreen, criticalToastScreen);
        if (screen === "")
            return false;
        const timing = toastTiming(notification);
        const next = ToastRules.pin(toastState, id, toastQueue(notification, timing), timing.kind);
        if (next === toastState)
            return false;
        _watchToast(notification);
        const objects = Object.assign({}, _toastObjects);
        objects[id] = notification;
        _toastObjects = objects;
        _setToastTiming(id, timing);
        // On the centre's screen, where the click was — a toast shown on another screen
        // leaves it for that one
        const screens = Object.assign({}, toastScreens);
        screens[id] = screen;
        toastScreens = screens;
        _applyToasts(next);
        return true;
    }

    // The centre's unpin: the modal ends (its entry stays in the centre)
    function unpinToast(id) {
        if (ToastRules.isModal(toastState, id))
            toastGone(id);
    }

    // A modal's screen went (its HUD destroyed): it waits in its queue again, by age — or,
    // when that queue takes nothing now, it goes
    function modalScreenGone(id) {
        const at = ToastRules.where(toastState, id);
        if (at.place !== "moved")
            return;
        if (ToastRules.accepts(at.queue, _toastConditions()))
            _applyToasts(ToastRules.returnToQueue(toastState, id));
        else
            toastGone(id);
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
            Notifications.markSeen();
        }
    }

    // Every toast goes, shown and waiting, in every queue
    function clearHudQueue() {
        toastState = ToastRules.emptyState();
        _pruneToasts();
        _logQueues();
        hudQueueCleared();
    }
}
