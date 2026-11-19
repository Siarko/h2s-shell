import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.components

// One notification toast slot. Manages its own queue consumption, slide-in/out
// animations, and auto-dismiss timer. Hud stacks several of them: those that count down
// newest on top, as many as the layout has slots ("notifications.toastLayout"), and the
// toasts that stay above them; every free slot takes the next notification that has room
// from the shared queue (Notifications.takeHudNotification), and Hud works out its
// place (stackY).
Item {
    id: root

    required property int screenWidth
    required property var screenModelData
    // Slots past the column's current size stay idle: they finish what they show, but
    // take nothing new
    property bool slotEnabled: true
    // Its place in the stack, from Hud; null once it is leaving, when it stays where it was
    property var stackY: null
    property real _lastY: 0
    onStackYChanged: if (stackY !== null) _lastY = stackY
    // Moves to a new place smoothly — except when it first appears, which is at its place
    property bool _placing: false
    y: _lastY
    Behavior on y {
        enabled: !root._placing
        NumberAnimation { duration: Theme.duration("move"); easing: Theme.curve("move") }
    }

    property var currentNotif: null
    // The id this slot put on the list of shown toasts, -1 while none: taken off by that,
    // even when the notification object is gone by then
    property int _shownId: -1
    // Counts the toasts this slot showed, so one shown after another counts afresh
    property int _generation: 0
    property bool _taking: false
    // A reply hovered or being written: Hud gives its window the keyboard
    readonly property bool wantsKeyboard: currentNotif !== null && notifCard.wantsKeyboard
    // Held: under a resting pointer, or with a reply being written — no countdown either way,
    // so a toast does not slide away mid-reply when the pointer wanders off
    readonly property bool _held: cardHover.hovered || notifCard.replying || notifCard.swiping
    on_HeldChanged: {
        if (_held)
            countdown.pause();
        else
            countdown.resume();
    }
    readonly property int cardWidth: Theme.osdToast.width

    // Resting x: the gap from the screen edge, or, while the queue badge shows, the badge
    // and a gap of 8 beside it, so the toast doesn't overlap it
    readonly property int restX: screenWidth - cardWidth
        - (Notifications.hudQueue.length > 0 ? Theme.osdToast.badgeWidth + 8 : Theme.osdToast.screenGap)

    // Start off-screen to the right; animations move it in and out
    x: screenWidth
    width: cardWidth
    height: notifCard.implicitHeight
    visible: currentNotif !== null || slideIn.running || slideOut.running

    // Consume the next item from the shared queue and start the slide-in
    function showNext() {
        // Taking one changes the queue, which asks every free slot — this one too — to take
        // one: this slot is busy with the first (Notifications counts it as shown already)
        if (_taking)
            return;
        if (Notifications.hudPanelOpen || !slotEnabled) {
            currentNotif = null;
            return;
        }
        _taking = true;
        const notif = Notifications.takeHudNotification();
        _taking = false;
        if (!notif) {
            currentNotif = null;
            return;
        }
        _placing = true;
        currentNotif = notif;
        remaining = 1.0;
        _shownId = notif.id;
        _generation++;
        Qt.callLater(() => root._placing = false);
        slideIn.start();
    }

    // Room on screen came (a toast left, changed its time, a setting): a free slot on the
    // toasts' screen takes what waits
    function _retry() {
        if (currentNotif === null && !slideOut.running && Notifications.toastScreen === screenModelData.name)
            showNext();
    }

    function dismiss() {
        countdown.stop();
        _leave();
        slideOut.start();
    }

    // Off the list of shown toasts as soon as it starts leaving, so the next one in line
    // starts counting down at once
    function _leave() {
        if (_shownId < 0)
            return;
        const id = _shownId;
        _shownId = -1;
        Notifications.toastGone(id);
    }

    // Left without a notification while shown: off the list too, or a toast waiting behind
    // it would never count down
    onCurrentNotifChanged: {
        if (currentNotif === null)
            _leave();
    }

    // Its notification closed while shown (its sender closed it, or it was dismissed in the
    // centre): Quickshell then frees the object, and a var holding it reads null with no
    // change signal — so the toast goes now, or one waiting behind it would never count
    Connections {
        target: root.currentNotif?.closed !== undefined ? root.currentNotif : null
        ignoreUnknownSignals: true

        function onClosed() {
            if (root._shownId >= 0)
                root.dismiss();
        }
    }

    // Gone without leaving — a reload rebuilding the HUD — it must still come off the list,
    // or the toasts after it wait for it to count down, for ever
    Component.onDestruction: _leave()

    // How long it shows (Notifications.toastTiming, ToastRules.timing): the sender's time,
    // the user's, or 0 — it stays until taken away ("×", a swipe), no countdown. Read again
    // when the sender replaces the notification with another time.
    readonly property var _timing: currentNotif !== null ? Notifications.toastTiming(currentNotif) : ({ ms: 0, kind: "stays" })
    readonly property string _timingKey: _timing.kind + ":" + _timing.ms
    on_TimingKeyChanged: {
        if (_shownId >= 0)
            Notifications.toastTimed(_shownId, _timing);
    }
    readonly property bool _staying: currentNotif !== null && _timing.kind === "stays"
    // Whether this toast counts down now: one with the sender's time at once, one with the
    // user's time when it is the oldest of those on screen; one that stays never
    readonly property bool _counting: _shownId >= 0 && currentNotif !== null && !_staying
        && (_timing.kind === "own" || Notifications.countingToast === _shownId)
    // What it counts: a new toast, or a new time, counts from full
    readonly property string _countKey: _counting ? _generation + ":" + _timing.ms : ""

    on_CountKeyChanged: {
        if (_countKey === "") {
            countdown.stop();
            // Waiting its turn again, or staying: full; leaving, its bar stays as it was
            if (_shownId >= 0)
                remaining = 1.0;
            return;
        }
        countdown.duration = Math.max(1000, _timing.ms);
        countdown.restart();
        // A held toast does not count down either
        if (_held)
            countdown.pause();
    }

    Connections {
        target: Notifications

        function onHudQueueChanged() {
            // Only the toasts' screen shows them (Notifications.toastScreen)
            if (Notifications.toastScreen !== root.screenModelData.name) return;
            if (root.currentNotif !== null) {
                // Toast already visible — nudge its x to account for badge appearing/disappearing
                if (!slideIn.running && !slideOut.running) {
                    nudge.restart();
                }
                return;
            }
            // Don't interrupt an ongoing slide-out
            if (slideOut.running) return;
            root.showNext();
        }

        // Toasts moved here (focus, a fullscreen window elsewhere): those waiting show
        function onToastScreenChanged() {
            if (Notifications.toastScreen === root.screenModelData.name && root.currentNotif === null && !slideOut.running)
                root.showNext();
        }

        function onRoomForToasts() {
            Qt.callLater(root._retry);
        }

        function onHudQueueCleared() {
            countdown.stop();
            if (root.currentNotif !== null) {
                root._leave();
                slideOut.start();
            }
        }
    }

    NumberAnimation {
        id: slideIn
        target: root
        property: "x"
        from: root.screenWidth
        to: root.restX
        duration: Theme.duration("enter")
        easing: Theme.curve("enter")
        // The target is taken when the slide starts. A notification queued meanwhile
        // brings the badge and moves restX, and the nudge is skipped while sliding — so
        // the first toast of a burst stopped against the badge. Catch up afterwards.
        onFinished: if (root.x !== root.restX) nudge.restart()
    }

    NumberAnimation {
        id: slideOut
        target: root
        property: "x"
        to: root.screenWidth
        duration: Theme.duration("exit")
        easing: Theme.curve("exit")
        onStopped: root.showNext()
    }

    // Nudge the resting toast when the badge appears/disappears mid-show.
    NumberAnimation {
        id: nudge
        target: root
        property: "x"
        to: root.restX
        duration: Theme.duration("move")
        easing: Theme.curve("move")
        // The badge can come or go during the nudge too
        onFinished: if (root.x !== root.restX) nudge.restart()
    }

    // Auto-dismiss countdown, 1 → 0. An animation rather than a Timer because it has to
    // pause while hovered and carry on from where it stopped, and a Timer can only restart.
    // It also drives the card's timer bar, so the two cannot drift apart.
    property real remaining: 1.0

    NumberAnimation {
        id: countdown
        target: root
        property: "remaining"
        from: 1.0
        to: 0.0
        // Set with each start, from the toast's time (on_CountKeyChanged)
        duration: 5000
        onFinished: root.dismiss()
    }

    NotificationCard {
        id: notifCard
        notification: root.currentNotif
        compactDismiss: true
        imageMaxHeight: 120
        // A toast stays small: a long body is cut, the notification centre shows it whole
        bodyMaxLines: 6
        contentPadding: Theme.osdToast.padding
        cornerRadius: Theme.osdToast.radius
        borderWidth: Theme.osdToast.borderWidth
        borderColor: Theme.osdToastBorder
        replyBackground: Theme.surfaceSunken
        width: root.cardWidth
        onDismissRequested: root.dismiss()
        // An action on a resident notification: the toast leaves, the entry stays
        onActionInvoked: root.dismiss()
        // No bar on a toast that stays
        timerVisible: !root._staying
        timerProgress: root.remaining

        HoverHandler {
            id: cardHover
        }
    }
}
