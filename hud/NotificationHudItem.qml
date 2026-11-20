import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.components

// One notification's toast, made by ToastStack for a toast on its screen and destroyed after
// it slid out. Notifications holds the queues: whether the toast is on screen (`present`,
// from the stack), whether it counts down (Notifications.countingToasts) and for how long
// (Notifications.toastDurations). The toast only slides, counts and reports its end
// (Notifications.toastGone) — it holds nothing another toast waits for.
// A critical or staying toast — or a modal — can be dragged by its title line (the grip) when
// the option is on (Notifications.canMoveToast); dropped, it is a modal at that place, inside
// its screen (ToastRules.clampToScreen, Notifications.moveToast). A modal has the accent
// outline and fades in and out where it is instead of sliding.
Item {
    id: root

    required property int screenWidth
    // Where a dropped toast is kept, from the window's top left (its part on the screen); a
    // height of 0: the window's
    property int dropWidth: screenWidth
    property int dropHeight: 0
    // What the bar keeps at the screen's edges: a drop stays off it (ToastRules.clampToScreen)
    property var dropInsets: null
    required property var screenModelData
    // The notification's id, -1 for a card shown alone (no queue behind it)
    property int toastId: -1
    // In its queue on screen; false once it leaves: it slides out and the stack lets it go
    property bool present: false
    // Where it rests, from the stack: left of the badges while any shows
    property real restX: screenWidth - cardWidth - Theme.osdToast.screenGap
    // Comes in from the screen's edge and goes back there; false (the column by the open
    // centre, which it would cross): fades in and out where it rests
    property bool slides: true
    // Its place in the stack, from the stack; null once it is leaving, when it stays where
    // it was
    property var stackY: null
    property real _lastY: 0
    onStackYChanged: if (stackY !== null) _lastY = stackY
    // Where the stack is in the window: a modal's place is kept in the window's coordinates
    property real originY: 0
    // A modal (out of its queue: dragged out or pinned), and its place in the stack's
    // coordinates — null while a pinned one waits for its first place
    property bool modal: false
    property var modalPlace: null
    onModalPlaceChanged: _takeModalPlace()
    // Once a modal, it looks and leaves as one: its place in the queues goes before it has
    // faded out
    property bool _wasModal: false
    onModalChanged: if (modal) _wasModal = true
    // Moves to a new place smoothly — except when it first appears, which is at its place
    property bool _placing: true
    y: dragging ? _dragY : _lastY
    Behavior on y {
        enabled: !root._placing && !root.dragging
        NumberAnimation { duration: Theme.duration("move"); easing: Theme.curve("move") }
    }
    // Over the stack while a modal, over everything while dragged
    z: dragging ? 2 : _wasModal ? 1 : 0

    // ---- Dragged by its title line ----
    // Allowed by the rules (an option; critical, staying or a modal) while it is on screen
    readonly property bool movable: present && toastId >= 0 && Notifications.canMoveToast(toastId)
    property bool dragging: false
    // Not moving: no slide, nudge, move to a place or fade running (for tests from outside)
    readonly property bool settled: !slideIn.running && !nudge.running && !toPlace.running && !fadeIn.running
        && !slideOut.running && !fadeOut.running && !dragging
    property real _dragY: 0
    property real _dragStartX: 0
    property real _dragStartY: 0

    // Its new place as a modal: from the stack a moment after it was dropped or pinned. One
    // already on screen moves there; one that waited for it appears there.
    function _takeModalPlace() {
        if (modalPlace === null || dragging)
            return;
        slideIn.stop();
        nudge.stop();
        if (opacity > 0 && x < screenWidth && !_placing) {
            toPlace.to = modalPlace.x;
            toPlace.restart();
            _lastY = modalPlace.y;
            return;
        }
        _placing = true;
        x = modalPlace.x;
        _lastY = modalPlace.y;
        fadeIn.restart();
        Qt.callLater(() => root._placing = false);
    }

    // Let go: inside the screen (ToastRules.clampToScreen), then a modal there. Refused at
    // the release (the option turned off, or its queue changed, during the drag): back to its
    // place — in the stack, or a modal's (it was one already, or was pinned meanwhile) — left
    // where it was dropped it would be outside the window's input mask, unclickable.
    function _drop() {
        const windowHeight = dropHeight > 0 ? dropHeight : (Window.window?.height ?? 0);
        const place = ToastRules.clampToScreen(x, y + originY, width, height, dropWidth, windowHeight, dropInsets);
        _lastY = place.y - originY;
        x = place.x;
        dragging = false;
        Notifications.moveToast(toastId, place.x, place.y);
        if (Notifications.isModal(toastId)) {
            // Taken, the modal's place is where it was dropped and this changes nothing;
            // refused, it is the old one. Not placed yet (pinned meanwhile): the stack places it.
            _takeModalPlace();
        } else if (present && stackY !== null) {
            _lastY = stackY;
            nudge.restart();
        }
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
    readonly property bool _held: cardHover.hovered || notifCard.replying || notifCard.swiping || dragging
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
        fadeOut.stop();
        remaining = 1.0;
        _generation++;
        // A modal appears where it is put (a pinned one once it has a place)
        if (modal) {
            opacity = 0;
            _takeModalPlace();
            return;
        }
        if (!slides) {
            x = restX;
            opacity = 0;
            fadeIn.restart();
            return;
        }
        opacity = 1;
        slideIn.start();
    }

    function _exit() {
        countdown.stop();
        slideIn.stop();
        nudge.stop();
        toPlace.stop();
        dragging = false;
        // A modal fades where it is; a toast in the stack slides out to the right
        if (_wasModal || !slides || x < restX - 1)
            fadeOut.start();
        else
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
    // A modal whose screen went waits in its queue again (Notifications.modalScreenGone)
    Component.onDestruction: {
        if (toastId < 0 || !present)
            return;
        if (modal)
            Notifications.modalScreenGone(toastId);
        else
            Notifications.toastGone(toastId);
    }

    onRestXChanged: {
        if (present && !modal && !dragging && !slideIn.running && !slideOut.running)
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

    // A modal comes in and goes where it is
    NumberAnimation {
        id: fadeIn
        target: root
        property: "opacity"
        to: 1
        duration: Theme.duration("enter")
        easing: Theme.curve("enter")
    }

    NumberAnimation {
        id: fadeOut
        target: root
        property: "opacity"
        to: 0
        duration: Theme.duration("exit")
        easing: Theme.curve("exit")
        onStopped: {
            if (!root.present)
                root.slidOut();
        }
    }

    // A toast on screen pinned: over to its place
    NumberAnimation {
        id: toPlace
        target: root
        property: "x"
        duration: Theme.duration("move")
        easing: Theme.curve("move")
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
        // A modal: the accent outline (a critical one keeps the critical outline)
        borderWidth: root._wasModal ? Math.max(Theme.osdToast.borderWidth, Theme.border.width) : Theme.osdToast.borderWidth
        borderColor: root._wasModal ? Theme.accent : Theme.osdToastBorder
        replyBackground: Theme.surfaceSunken
        width: root.cardWidth
        // "×" or a swipe dismisses the notification itself (its entry leaves the centre; a
        // job goes on); the toast then leaves as its notification does
        onCloseClicked: {
            if (root.toastId >= 0)
                Notifications.dismissToast(root.toastId, root.currentNotif);
        }
        // Also after an action on a notification that does not stay after it
        onDismissRequested: root.dismiss()
        // An action on a resident notification leaves its toast on screen (the spec: it
        // stays after an action); only "×" takes it away
        // No bar on a toast that stays, nor on a modal that does not count (a pinned one)
        timerVisible: ToastRules.showsTimer({ staying: root._staying, modal: root.modal, counting: root._counting })
        timerProgress: root.remaining

        HoverHandler {
            id: cardHover
        }
    }

    // The grip at the top: this toast can be dragged by its title line
    Rectangle {
        objectName: "toastGrip"
        visible: root.movable || root.dragging
        anchors.horizontalCenter: parent.horizontalCenter
        y: 3
        width: 36
        height: 3
        radius: height / 2
        color: Theme.textMuted
        opacity: dragHover.hovered || root.dragging ? 0.9 : 0.45
    }

    // The title line, less the "×": grabbed here. A press that does not move goes on to the
    // card beneath (its default action); one that moves past the threshold is a drag. The
    // toast follows the pointer in the window's coordinates: this zone moves with the toast,
    // so a translation in its own would feed back.
    Item {
        id: dragZone
        objectName: "toastDragZone"
        width: root.cardWidth - Theme.osdToast.padding - Theme.target.minSize
        height: Theme.osdToast.padding + Theme.fontSizeSection + 8

        HoverHandler {
            id: dragHover
            enabled: root.movable
            cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        }

        DragHandler {
            id: dragHandler
            target: null
            enabled: root.movable || root.dragging
            onActiveChanged: {
                if (active) {
                    nudge.stop();
                    slideIn.stop();
                    toPlace.stop();
                    root._dragStartX = root.x;
                    root._dragStartY = root.y;
                    root._dragY = root.y;
                    root.dragging = true;
                } else if (root.dragging) {
                    root._drop();
                }
            }
            onCentroidChanged: {
                if (!root.dragging)
                    return;
                root.x = root._dragStartX + centroid.scenePosition.x - centroid.scenePressPosition.x;
                root._dragY = root._dragStartY + centroid.scenePosition.y - centroid.scenePressPosition.y;
            }
        }
    }
}
