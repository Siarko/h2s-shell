import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.components

// One notification toast slot. Manages its own queue consumption, slide-in/out
// animations, and auto-dismiss timer. Hud stacks one or more of them, newest on top
// ("notifications.toastLayout"); every free slot takes the next notification from the
// shared queue, and Hud works out its place (stackY).
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
        if (Notifications.hudPanelOpen || !slotEnabled) {
            currentNotif = null;
            return;
        }
        const notif = Notifications.dequeueHudNotification();
        if (!notif) {
            currentNotif = null;
            return;
        }
        _placing = true;
        currentNotif = notif;
        remaining = 1.0;
        Notifications.toastShown(notif.id);
        Qt.callLater(() => root._placing = false);
        slideIn.start();
    }

    function dismiss() {
        countdown.stop();
        _leave();
        slideOut.start();
    }

    // Off the list of shown toasts as soon as it starts leaving, so the next one in line
    // starts counting down at once
    function _leave() {
        if (currentNotif !== null)
            Notifications.toastGone(currentNotif.id);
    }

    // Gone without leaving — a reload rebuilding the HUD — it must still come off the list,
    // or the toasts after it wait for it to count down, for ever
    Component.onDestruction: _leave()

    // Whether this toast is the oldest on screen, the one counting down
    readonly property bool _counting: currentNotif !== null && Notifications.shownToasts[0] === currentNotif.id

    on_CountingChanged: {
        if (!_counting)
            return;
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
        duration: (Profiles.value("notifications.toastDuration") ?? 5) * 1000
        onFinished: root.dismiss()
    }

    NotificationCard {
        id: notifCard
        notification: root.currentNotif
        compactDismiss: true
        imageMaxHeight: 120
        contentPadding: Theme.osdToast.padding
        cornerRadius: Theme.osdToast.radius
        borderWidth: Theme.osdToast.borderWidth
        borderColor: Theme.osdToastBorder
        replyBackground: Theme.surfaceSunken
        width: root.cardWidth
        onDismissRequested: root.dismiss()
        timerVisible: true
        timerProgress: root.remaining

        HoverHandler {
            id: cardHover
        }
    }
}
