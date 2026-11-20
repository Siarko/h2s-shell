import QtQuick
import QtTest as QT
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.components
import qs.hud
import qs.singletons

// Modals under real input events: a staying toast dragged by its title line (the grip) in a
// ToastStack as Hud makes it — it follows the pointer, dropped it is a modal there (inside
// the screen) and its slot in the queue takes the next; an ordinary toast and the option off
// do not drag, and a drop refused at the release goes back to its place; a modal's look (accent outline, grip); the centre's pin button on a card
// pins and unpins; a pinned toast that counted down stays; a modal job that ends counts
// down and goes; "×" on a modal dismisses; its HUD destroyed, a modal waits again. The
// rules alone: ToastRulesTest. That clicks beside a modal reach the window beneath (the
// HUD's input mask) needs the compositor: the lock test bed's toast-modal.
//
// Opens a small window in a corner of the screen for a moment (a layer surface).
TestCase {
    id: root
    suiteName: "ToastDrag"
    asynchronous: true

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 800
        implicitHeight: 600
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // The screen, which stays put: QtTest maps each event through the item given, and a
        // dragged toast moves under the pointer
        Item {
            id: screenArea
            width: 800
            height: 600
        }

        // Where a stack is made, as Hud places it: under the bar
        Item {
            id: stackHost
            width: 800
            height: 600
        }

        // An entry of the centre, for its pin button
        Item {
            id: cardHost
            x: 20
            y: 20
            width: 300
            height: 200
        }

        QT.TestCase {
            id: driver
            name: "ToastDragDriver"
            when: false
        }
    }

    property Component _stack: Component {
        ToastStack {
            y: 40
            width: 800
            screenWidth: 800
            screenHeight: 600
            screenModelData: ({ name: "drag-screen" })
        }
    }
    property Component _card: Component {
        NotificationCard {
            width: 300
            pinnable: true
        }
    }
    // A notification as the server hands it, as far as a toast reads it
    property Component _standIn: Component {
        QtObject {
            property int id
            property real expireTimeout: -1
            property int urgency: NotificationUrgency.Normal
            property string appName: "Test"
            property string appIcon: ""
            property string summary: "Toast"
            property string body: ""
            property string image: ""
            property var actions: []
            property bool hasInlineReply: false
            property var hints: ({})
            property bool resident: false
            property bool tracked: true
            property int dismissCalls: 0
            signal closed(int reason)
            function dismiss() {
                dismissCalls++;
                closed(NotificationCloseReason.Dismissed);
                tracked = false;
            }
        }
    }

    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    function _find(item, test) {
        for (const child of item?.children ?? []) {
            if (test(child))
                return child;
            const found = _find(child, test);
            if (found)
                return found;
        }
        return null;
    }

    // Drags `toast` by its title line by (dx, dy) in `steps` moves, the button held; `during`
    // runs half-way, still held
    function _drag(toast, dx, dy, steps, during) {
        const start = toast.mapToItem(screenArea, 60, 12);
        driver.mousePress(screenArea, start.x, start.y);
        for (let i = 1; i <= steps; i++) {
            driver.wait(16);
            driver.mouseMove(screenArea, start.x + dx * i / steps, start.y + dy * i / steps);
            if (i === Math.floor(steps / 2) && during)
                during();
        }
        driver.wait(16);
        driver.mouseRelease(screenArea, start.x + dx, start.y + dy);
        driver.wait(30);
    }

    function _place(notification) {
        const at = Notifications.toastPlace(notification.id);
        return at.place + (at.queue ? " " + at.queue : "");
    }

    function runAsync() {
        driver.wait(300); // the window shown
        const savedGlobals = Config.globals;
        const settings = change => {
            Config.globals = JSON.stringify(Object.assign(JSON.parse(savedGlobals || "{}"), change));
        };
        settings({});
        Notifications.clearHudQueue();
        Notifications.screensOverride = [{ name: "drag-screen", focused: true, fullscreen: false, workspace: 1 }];
        const made = [];
        let nextId = 9501;
        const standIn = (expire, change) => {
            const standing = _standIn.createObject(root, Object.assign({ id: nextId++, expireTimeout: expire }, change ?? {}));
            made.push(standing);
            return standing;
        };
        let stack = _stack.createObject(stackHost);
        const show = notification => {
            Notifications.enqueueHudNotification(notification);
            return stack.toastFor(notification.id);
        };
        const settle = () => driver.wait(Math.max(Theme.duration("enter"), Theme.duration("move")) + 80);

        // --- a staying toast dragged out by its title line ---
        const backup = standIn(0, { summary: "Backup running" });
        const next = standIn(0, { summary: "Second backup" });
        const backupToast = show(backup);
        show(next);
        settle();
        assert(_place(backup) === "shown staying" && _place(next) === "waiting staying", "one staying toast shown, the next waits");
        const grip = _find(backupToast, item => item.objectName === "toastGrip");
        assert(backupToast.movable && grip !== null && grip.visible, "movable (the default): the grip shows");
        const startX = backupToast.x;
        const startY = backupToast.y;
        let followed = false;
        _drag(backupToast, -300, 250, 20, () => {
            followed = backupToast.dragging && Math.abs(backupToast.x - (startX - 150)) <= 25 && Math.abs(backupToast.y - (startY + 125)) <= 25;
        });
        assert(followed, "while held, the toast follows the pointer");
        assert(_place(backup) === "moved staying" && Notifications.isModal(backup.id), "dropped: a modal");
        const moved = Notifications.toastState.moved.find(entry => entry.id === backup.id);
        assert(Math.abs(moved.x - (startX - 300)) <= 2 && Math.abs(moved.y - (startY + 40 + 250)) <= 2,
               "… its place in the window's coordinates, where it was dropped (" + moved.x + ", " + moved.y + ")");
        assert(_until(() => stack.toastFor(backup.id) === backupToast && backupToast.modal && !backupToast.dragging),
               "the same toast, now a modal (its countdown and text kept)");
        assert(_place(next) === "shown staying", "its slot in the staying queue went to the next one");
        assert(stack.modalToasts.length === 1 && stack.modalToasts[0] === backupToast, "the stack hands it to the window's input mask");
        const card = _find(backupToast, item => item.bodyMaxLines !== undefined);
        assert(card.border.color === Theme.accent && card.border.width >= Theme.border.width, "a modal: the accent outline");
        settle();
        const contentHeight = stack.contentHeight;
        assert(contentHeight < backupToast.y, "the stack's strip leaves the modal out (" + contentHeight + ")");

        // --- dragged again: it just changes place; past the screen's edge: back inside ---
        _drag(backupToast, -1000, 1000, 10);
        let corner = Notifications.toastState.moved.find(entry => entry.id === backup.id);
        assert(corner.x === 0 && corner.y === 600 - backupToast.height, "dropped past the bottom left: inside the screen, whole");
        settle();
        assert(Math.abs(backupToast.x) < 1 && Math.abs(backupToast.y + 40 - corner.y) < 1, "… and the toast there");

        // --- a bar at the bottom and the left: a drop stays off it, and the toasts' column is not moved ---
        stack.barInsets = { top: 0, bottom: 50, left: 30, right: 0 };
        _drag(backupToast, -100, 100, 6);
        const offBar = Notifications.toastState.moved.find(entry => entry.id === backup.id);
        assert(offBar.x === 30 && offBar.y === 600 - 50 - backupToast.height, "dropped onto the bars: beside them (" + offBar.x + ", " + offBar.y + ")");
        settle();
        stack.barInsets = { top: 0, bottom: 0, left: 0, right: 0 };
        corner = offBar;

        // --- a modal dragged with the option turned off meanwhile: back to its place ---
        _drag(backupToast, 300, -250, 10, () => settings({ "notifications.movableToasts": false }));
        settings({});
        const kept = Notifications.toastState.moved.find(entry => entry.id === backup.id);
        assert(kept.x === corner.x && kept.y === corner.y, "refused at the release: the modal keeps its place");
        assert(_until(() => backupToast.settled && Math.abs(backupToast.x - corner.x) < 1 && Math.abs(backupToast.y + 40 - corner.y) < 1),
               "… and goes back there (inside the input mask)");

        // --- the option turned off during a drag: refused at the release, back in the stack ---
        const nextStackToast = stack.toastFor(next.id);
        settle();
        const restingX = nextStackToast.x;
        const restingY = nextStackToast.y;
        _drag(nextStackToast, -300, 200, 10, () => settings({ "notifications.movableToasts": false }));
        settings({});
        assert(_place(next) === "shown staying", "refused at the release: still in its queue");
        assert(_until(() => Math.abs(nextStackToast.x - restingX) < 1 && Math.abs(nextStackToast.y - restingY) < 1),
               "… and back at its place in the stack (inside the input mask)");

        // --- what does not drag: an ordinary toast; any toast with the option off ---
        const ordinary = standIn(-1);
        const ordinaryToast = show(ordinary);
        settle();
        assert(!ordinaryToast.movable && !_find(ordinaryToast, item => item.objectName === "toastGrip").visible, "an ordinary toast: no grip");
        _drag(ordinaryToast, -200, 200, 10);
        assert(_place(ordinary) === "shown ordinary", "… and no drag");
        settings({ "notifications.movableToasts": false });
        const nextToast = stack.toastFor(next.id);
        assert(!nextToast.movable && !backupToast.movable, "the option off: nothing drags, a modal neither");
        _drag(nextToast, -200, 200, 10);
        assert(_place(next) === "shown staying" && _place(backup) === "moved staying", "… the staying one stays in its queue, the modal where it is");
        settings({});

        // --- a modal job that ends counts down where it is, and goes ---
        backup.expireTimeout = 2000;
        Notifications._retime(backup.id, backup);
        assert(Notifications.countingToasts.includes(backup.id) && backupToast._counting, "its job ended: the modal counts down");
        assert(_find(backupToast, item => item.bodyMaxLines !== undefined).timerVisible, "… and shows its countdown bar");
        backupToast.resources.find(resource => resource.property === "remaining")?.complete();
        assert(_place(backup) === "none" && _until(() => stack.toastFor(backup.id) === null), "… and goes, fading where it is");

        // --- "×" on a modal dismisses the notification ---
        const nextToastNow = stack.toastFor(next.id);
        _drag(nextToastNow, -300, 100, 10);
        assert(_place(next) === "moved staying", "the next one dragged out too");
        _find(nextToastNow, item => item instanceof MouseArea && item.parent?.text === "×").clicked(null);
        assert(_place(next) === "none" && next.dismissCalls === 1 && !next.tracked, "its \"×\": the notification dismissed");

        // --- the centre's pin: any notification a modal, then unpinned ---
        const mail = standIn(-1, { summary: "Mail from Ann" });
        const entry = _card.createObject(cardHost, { notification: mail });
        made.push(entry);
        assert(entry.screenName !== "" && entry.screenName === (_window.screen?.name ?? ""),
               "an entry's pin goes to its window's screen (" + entry.screenName + ")");
        // The stack here stands for that screen's
        entry.screenName = "drag-screen";
        const pinButton = _find(entry, item => item.objectName === "pinButton");
        assert(pinButton !== null && pinButton.visible && entry.pinLook.action === "pin", "an entry in the centre: a pin");
        driver.mouseClick(pinButton, pinButton.width / 2, pinButton.height / 2);
        assert(_place(mail) === "moved ordinary" && entry.pinLook.action === "unpin", "pinned: a modal; the pin now unpins");
        assert(_until(() => Notifications.toastState.moved.find(modal => modal.id === mail.id)?.x !== null), "… placed by its screen's stack");
        const pinned = Notifications.toastState.moved.find(modal => modal.id === mail.id);
        const mailToast = stack.toastFor(mail.id);
        assert(mailToast !== null && mailToast.present && pinned.x + Theme.osdToast.width <= 800 - Theme.osdToast.width,
               "… beside the toasts' column (" + pinned.x + ", " + pinned.y + ")");
        assert(!Notifications.countingToasts.includes(mail.id), "pinned while it would count down: it stays");
        assert(_until(() => mailToast.opacity > 0.99 && Math.abs(mailToast.x - pinned.x) < 1), "… shown there");
        const mailCard = _find(mailToast, item => item.bodyMaxLines !== undefined);
        assert(!mailCard.timerVisible, "… with no countdown bar: it does not count down");
        driver.mouseClick(pinButton, pinButton.width / 2, pinButton.height / 2);
        assert(_place(mail) === "none" && mail.tracked && entry.pinLook.action === "pin", "unpinned: the modal ends, the entry stays");

        // --- its screen's HUD destroyed: a modal waits in its queue again ---
        const alert = standIn(0, { summary: "Disk almost full" });
        const alertToast = show(alert);
        settle();
        _drag(alertToast, -300, 200, 10);
        assert(_place(alert) === "moved staying", "a modal again");
        Notifications.screensOverride = [{ name: "other-screen", focused: true, fullscreen: false, workspace: 1 }];
        stack.destroy();
        stack = null;
        assert(_until(() => _place(alert) === "waiting staying"), "its HUD gone: it waits in its queue again");

        Notifications.clearHudQueue();
        Notifications.screensOverride = null;
        Config.globals = savedGlobals;
        for (const object of made)
            object.destroy();
        finish();
    }
}
