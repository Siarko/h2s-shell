import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.components

// Self-contained notification toast. Manages its own queue consumption,
// slide-in/out animations, and auto-dismiss timer.
Item {
    id: root

    required property int screenWidth
    required property var screenModelData

    property var currentNotif: null
    readonly property int cardWidth: 360

    // Resting x: shift left by an extra 28px (badge 36px - existing 16px gap) when
    // the queue badge is visible so the toast doesn't overlap it.
    readonly property int restX: screenWidth - cardWidth - (Notifications.hudQueue.length > 0 ? 44 : 16)

    // Start off-screen to the right; animations move it in and out
    x: screenWidth
    y: Config.bar.layout.reservedSpace + 16
    width: cardWidth
    height: notifCard.implicitHeight

    // Consume the next item from the shared queue and start the slide-in
    function showNext() {
        if (Notifications.hudPanelOpen) {
            currentNotif = null;
            return;
        }
        const notif = Notifications.dequeueHudNotification();
        if (!notif) {
            currentNotif = null;
            return;
        }
        currentNotif = notif;
        slideIn.start();
        countdown.restart();
        // A toast appearing under a resting pointer must not count down either
        if (cardHover.hovered)
            countdown.pause();
    }

    function dismiss() {
        countdown.stop();
        slideOut.start();
    }

    Connections {
        target: Notifications

        function onHudQueueChanged() {
            // Only the screen that owns the focused workspace shows toasts
            if (Workspaces.focused?.monitor?.name !== root.screenModelData.name) return;
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

        function onHudQueueCleared() {
            countdown.stop();
            if (root.currentNotif !== null) {
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
        duration: 250
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: slideOut
        target: root
        property: "x"
        to: root.screenWidth
        duration: 200
        easing.type: Easing.InCubic
        onStopped: root.showNext()
    }

    // Nudge the resting toast when the badge appears/disappears mid-show.
    NumberAnimation {
        id: nudge
        target: root
        property: "x"
        to: root.restX
        duration: 200
        easing.type: Easing.OutCubic
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
        duration: 5000
        onFinished: root.dismiss()
    }

    NotificationCard {
        id: notifCard
        notification: root.currentNotif
        compactDismiss: true
        imageMaxHeight: 120
        contentPadding: 10
        replyBackground: Qt.rgba(0, 0, 0, 0.2)
        width: root.cardWidth
        onDismissRequested: root.dismiss()
        timerVisible: true
        timerProgress: root.remaining

        HoverHandler {
            id: cardHover
            onHoveredChanged: {
                if (hovered)
                    countdown.pause();
                else
                    countdown.resume();
            }
        }
    }
}
