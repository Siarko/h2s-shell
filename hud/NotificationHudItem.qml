import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.components

// One notification's toast, made by ToastStack for a toast on its screen and destroyed after
// it slid out. Notifications holds the queues: whether the toast is on screen (`present`,
// from the stack), whether it counts down (Notifications.countingToasts) and for how long
// (Notifications.toastDurations). The toast only slides, counts and reports its end
// (Notifications.toastGone) — it holds nothing another toast waits for.
Item {
    id: root

    required property int screenWidth
    required property var screenModelData
    // The notification's id, -1 for a card shown alone (no queue behind it)
    property int toastId: -1
    // In its queue on screen; false once it leaves: it slides out and the stack lets it go
    property bool present: false
    // Where it rests, from the stack: left of the badges while any shows
    property real restX: screenWidth - cardWidth - Theme.osdToast.screenGap
    // Its place in the stack, from the stack; null once it is leaving, when it stays where
    // it was
    property var stackY: null
    property real _lastY: 0
    onStackYChanged: if (stackY !== null) _lastY = stackY
    // Moves to a new place smoothly — except when it first appears, which is at its place
    property bool _placing: true
    y: _lastY
    Behavior on y {
        enabled: !root._placing
        NumberAnimation { duration: Theme.duration("move"); easing: Theme.curve("move") }
    }

    // Slid out: the stack may destroy it
    signal slidOut()

    property var currentNotif: null
    // Counts the times this toast came on screen and was announced, so each counts afresh
    property int _generation: 0
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

    // Start off-screen to the right; animations move it in and out
    x: screenWidth
    width: cardWidth
    height: notifCard.implicitHeight
    visible: currentNotif !== null || slideIn.running || slideOut.running

    Component.onCompleted: {
        if (present)
            _enter();
        Qt.callLater(() => root._placing = false);
    }

    onPresentChanged: {
        if (present)
            _enter();
        else
            _exit();
    }

    function _enter() {
        // Its notification, read when it shows: the queues forget it once it left, and the
        // card still shows it while it slides out
        if (toastId >= 0)
            currentNotif = Notifications.toastObject(toastId) ?? currentNotif;
        slideOut.stop();
        remaining = 1.0;
        _generation++;
        slideIn.start();
    }

    function _exit() {
        countdown.stop();
        slideIn.stop();
        nudge.stop();
        slideOut.start();
    }

    // Its end: out of its queue — the stack then takes it off screen (present false)
    function dismiss() {
        countdown.stop();
        if (toastId >= 0)
            Notifications.toastGone(toastId);
    }

    // Gone while still in its queue — its screen's HUD destroyed: out of the queue too, or the
    // toasts after it would wait for it to count down, for ever
    Component.onDestruction: {
        if (toastId >= 0 && present)
            Notifications.toastGone(toastId);
    }

    onRestXChanged: {
        if (present && !slideIn.running && !slideOut.running)
            nudge.restart();
    }

    // How long it shows (Notifications.toastDurations, ToastRules.timing): the sender's time,
    // the user's, or 0 — it stays until taken away ("×", a swipe), no countdown
    readonly property int _ms: toastId >= 0 ? (Notifications.toastDurations[toastId] ?? 0) : 0
    readonly property bool _staying: toastId < 0 || (Notifications.toastKinds[toastId] ?? "stays") === "stays"
    // Whether this toast counts down now (Notifications.countingToasts)
    readonly property bool _counting: present && toastId >= 0 && Notifications.countingToasts.includes(toastId)
    // What it counts: a new showing, an announce, or a new time counts from full
    readonly property string _countKey: _counting ? _generation + ":" + _ms : ""

    on_CountKeyChanged: {
        if (_countKey === "") {
            countdown.stop();
            // Waiting its turn again, or staying: full; leaving, its bar stays as it was
            if (present)
                remaining = 1.0;
            return;
        }
        countdown.duration = Math.max(1000, _ms);
        countdown.restart();
        // A held toast does not count down either
        if (_held)
            countdown.pause();
    }

    Connections {
        target: Notifications

        // Announced again while on screen: counting, it counts its time from full (a new
        // count key); waiting its turn or staying, it is full already
        function onToastRestartRequested(id) {
            if (id === root.toastId && root.present)
                root._generation++;
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
        // The target is taken when the slide starts; a badge coming meanwhile moves restX
        onFinished: if (root.x !== root.restX) nudge.restart()
    }

    NumberAnimation {
        id: slideOut
        target: root
        property: "x"
        to: root.screenWidth
        duration: Theme.duration("exit")
        easing: Theme.curve("exit")
        onStopped: {
            if (!root.present)
                root.slidOut();
        }
    }

    // Nudge the resting toast when a badge appears/disappears mid-show.
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
        // "×" or a swipe dismisses the notification itself (its entry leaves the centre; a
        // job goes on); the toast then leaves as its notification does
        onCloseClicked: {
            if (root.toastId >= 0)
                Notifications.dismissToast(root.toastId);
        }
        // Also after an action on a notification that does not stay after it
        onDismissRequested: root.dismiss()
        // An action on a resident notification leaves its toast on screen (the spec: it
        // stays after an action); only "×" takes it away
        // No bar on a toast that stays
        timerVisible: !root._staying
        timerProgress: root.remaining

        HoverHandler {
            id: cardHover
        }
    }
}
