import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.components
import qs.hud
import qs.singletons
import qs.tests

// A notification's long body under real input (InputDriver) and a finger (QtTest's touch
// screen): capped at its lines, it scrolls inside the card under a mouse wheel, a touchpad's
// stroke and a finger dragged up or down — in a toast (a ToastStack as Hud makes it) and in
// the centre's list, where the list stays put while the body moves and takes the wheel
// once the body is at its end. The card's own input still works: a sideways swipe
// dismisses, a click runs its default action, and a toast holds its countdown while read.
TestCase {
    id: suite
    suiteName: "NotificationScrollInput"
    asynchronous: true
    // The globals it pins for a while, put back key by key
    property GlobalsPin _globalsPin: GlobalsPin {}

    // The centre's entries, as its list shows them
    property var centreItems: []

    // A suite to wait for first: one window at a time under the pointer
    property var after: null
    property var _idle: WindowDriver {}
    // The window's parts, once it is made (after the suite before is done)
    property var _window: null
    property Item screenArea: null
    property Item stackHost: null
    property ListView centreList: null
    property var driver: _idle
    property var input: null

    property Component _windowComponent: Component { PanelWindow {
        readonly property Item screenArea: screenAreaItem
        readonly property Item stackHost: stackHostItem
        readonly property ListView centreList: centreListView
        readonly property var driver: windowDriver
        readonly property var input: inputDriver
        anchors { top: true; left: true }
        implicitWidth: 800
        implicitHeight: 600
        color: Theme.surface
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // The screen, which stays put: touch positions are given on it
        Item {
            id: screenAreaItem
            width: 800
            height: 600
        }

        // Where the toasts' stack is made
        Item {
            id: stackHostItem
            width: 800
            height: 600
        }

        // The centre's list, as NotificationPanel lays it out: cards in a ListView
        ListView {
            id: centreListView
            x: 20; y: 20
            width: 340; height: 300
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: suite.centreItems.length
            delegate: Item {
                id: entry
                required property int index
                width: ListView.view.width
                implicitHeight: card.implicitHeight
                NotificationCard {
                    id: card
                    objectName: "centreCard" + entry.index
                    width: parent.width
                    notification: suite.centreItems[entry.index]
                }
            }
        }

        WindowDriver {
            id: windowDriver
            name: "NotificationScrollInputDriver"
        }
        InputDriver {
            id: inputDriver
            driver: windowDriver
        }
    } }

    property Component _stack: Component {
        ToastStack {
            y: 40
            width: 800
            screenWidth: 800
            screenHeight: 600
            screenModelData: ({ name: "scroll-screen" })
        }
    }
    // A notification as the server hands it, as far as a card reads it; its default action
    // counts its runs
    property Component _standIn: Component {
        QtObject {
            id: standIn
            property int id
            property real expireTimeout: -1
            property int urgency: NotificationUrgency.Normal
            property string appName: "Test"
            property string appIcon: ""
            property string summary: "Long"
            property string body: ""
            property string image: ""
            property int defaultRuns: 0
            property var actions: [{ identifier: "default", text: "Open", invoke: () => standIn.defaultRuns++ }]
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

    function _until(condition, limitMs = 5000) {
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

    function _cardOf(item) {
        return _find(item, child => child.bodyMaxLines !== undefined);
    }

    function _bodyOf(card) {
        return _find(card, child => child.scrollBy !== undefined && child.view !== undefined);
    }

    function _lines(count) {
        return Array.from({ length: count }, (_, i) => "line " + (i + 1)).join("\n");
    }

    // A finger from (x, y) of the body by (dx, dy) in `steps` moves, given on the screen,
    // which stays put; `during` runs before the release, the finger still down
    function _drag(body, x, y, dx, dy, steps, during) {
        const start = body.mapToItem(screenArea, x, y);
        const touch = driver.touchEvent(screenArea);
        touch.press(0, screenArea, start.x, start.y).commit();
        for (let i = 1; i <= steps; i++) {
            driver.wait(30);
            touch.move(0, screenArea, start.x + dx * i / steps, start.y + dy * i / steps).commit();
        }
        driver.wait(30);
        if (during)
            during();
        touch.release(0, screenArea, start.x + dx, start.y + dy).commit();
        driver.wait(Theme.duration("exit") + Theme.duration("move") + 120);
    }

    // The pointer off every card, so no hover holds anything
    function _away() {
        return input.pointAt(screenArea, 400, 590);
    }

    function runAsync() {
        if (after)
            _until(() => after.done, 110000);
        _window = _windowComponent.createObject(suite);
        screenArea = _window.screenArea;
        stackHost = _window.stackHost;
        centreList = _window.centreList;
        driver = _window.driver;
        input = _window.input;
        if (!driver.waitShown()) {
            fail("the window was never drawn");
            finish();
            return;
        }
        _globalsPin.use({});
        Toasts.clearHudQueue();
        Toasts.screensOverride = [{ name: "scroll-screen", focused: true, fullscreen: false, workspace: 1 }];
        const made = [];
        let nextId = 9701;
        const standIn = change => {
            const object = _standIn.createObject(suite, Object.assign({ id: nextId++ }, change ?? {}));
            made.push(object);
            return object;
        };
        _away();
        const stack = _stack.createObject(stackHost);
        _toast(stack, standIn);
        _centre(standIn);
        stack.destroy();
        Toasts.clearHudQueue();
        Toasts.screensOverride = null;
        _globalsPin.restore();
        centreItems = [];
        for (const object of made)
            object.destroy();
        driver = _idle;
        _window.destroy();
        finish();
    }

    function _toast(stack, standIn) {
        // A long one that counts down
        const long = standIn({ expireTimeout: 60000, body: _lines(20) });
        Toasts.enqueueHudNotification(long);
        const toast = stack.toastFor(long.id);
        assert(toast !== null && _until(() => toast.settled && toast.opacity > 0.99 && toast._counting), "the toast is shown and counts down");
        const card = _cardOf(toast);
        const body = _bodyOf(card);
        assert(card.bodyCut && card.bodyMaxLines === NotificationRules.bodyLines.toast, "its body cut at the toast's lines (" + card.bodyMaxLines + ")");

        // A mouse wheel over the body scrolls it; the pointer over the card holds the countdown
        assert(input.pointAt(body, body.width / 2, body.height / 2) && input.wheel(1), "a notch down over the toast's body");
        assert(_until(() => card.bodyOffset > 0), "the wheel scrolls the toast's body (" + card.bodyOffset + ")");
        assert(toast._held, "… the pointer over it holds its countdown");
        const afterWheel = card.bodyOffset;
        assert(input.stroke(40), "a touchpad's stroke down over it");
        assert(_until(() => card.bodyOffset > afterWheel + 1), "the stroke scrolls it further (" + afterWheel + " → " + card.bodyOffset + ")");
        assert(input.wheel(-5), "notches back up");
        assert(_until(() => card.bodyOffset === 0), "back at its start, no further (" + card.bodyOffset + ")");

        // A finger dragged up scrolls it; the finger on the card holds the countdown meanwhile,
        // as a resting pointer does
        _away();
        assert(_until(() => !toast._held), "the pointer gone: the countdown runs again");
        let heldWhileDragged = false;
        _drag(body, body.width / 2, body.height - 10, 0, -50, 8, () => { heldWhileDragged = toast._held; });
        assert(card.bodyOffset > 30, "a finger dragged up scrolls the toast's body (" + card.bodyOffset + ")");
        assert(heldWhileDragged, "… and holds the countdown while it scrolls");
        assert(_until(() => !toast._held), "let go: the countdown runs again");
        assert(Math.abs(toast.x - toast.restX) < 1 && long.dismissCalls === 0, "… the toast in its place, not swiped");

        // A click on the body runs the default action (and the toast goes after it)
        assert(input.click(body, body.width / 2, body.height / 2), "a click on the toast's body");
        assert(_until(() => long.defaultRuns === 1), "the click runs the default action (" + long.defaultRuns + ")");
        _away();
        assert(_until(() => stack.toastFor(long.id) === null || !stack.toastFor(long.id).present), "… and the toast goes");

        // A sideways swipe on a cut body still dismisses
        const swiped = standIn({ expireTimeout: 0, body: _lines(20) });
        Toasts.enqueueHudNotification(swiped);
        const swipedToast = stack.toastFor(swiped.id);
        assert(swipedToast !== null && _until(() => swipedToast.settled && swipedToast.opacity > 0.99), "a second long toast shown");
        const swipedCard = _cardOf(swipedToast);
        const swipedBody = _bodyOf(swipedCard);
        let offsetDuring = -1;
        _drag(swipedBody, 40, swipedBody.height / 2, 260, 0, 10, () => { offsetDuring = swipedCard.bodyOffset; });
        assert(_until(() => swiped.dismissCalls === 1), "a sideways swipe over its body dismisses it (" + swiped.dismissCalls + ")");
        assertEqual(offsetDuring, 0, "… without scrolling the body");
    }

    function _centre(standIn) {
        centreItems = [standIn({ body: _lines(30) }), standIn({ body: _lines(10) }), standIn({ body: _lines(10) }), standIn({ body: _lines(10) })];
        assert(_until(() => _find(centreList, item => item.objectName === "centreCard0") !== null), "the centre's list shows its cards");
        const card = _find(centreList, item => item.objectName === "centreCard0");
        const body = _bodyOf(card);
        assert(card.bodyCut && card.bodyMaxLines === NotificationRules.bodyLines.centre, "the centre's long body cut at its lines (" + card.bodyMaxLines + ")");
        assert(_until(() => centreList.contentHeight > centreList.height), "the list is longer than its view (" + centreList.contentHeight + ")");

        // The wheel over the body scrolls the body, not the list
        assert(input.pointAt(body, body.width / 2, body.height / 2) && input.wheel(2), "two notches down over the centre's body");
        assert(_until(() => card.bodyOffset > 0), "the wheel scrolls the body (" + card.bodyOffset + ")");
        assertEqual(centreList.contentY, 0, "… not the list");
        const afterWheel = card.bodyOffset;
        assert(input.stroke(40), "a touchpad's stroke down over it");
        assert(_until(() => card.bodyOffset > afterWheel + 1), "the stroke scrolls the body further (" + card.bodyOffset + ")");
        assertEqual(centreList.contentY, 0, "… not the list");

        // At the body's end the wheel goes on to the list
        assert(input.wheel(20), "notches to the body's end");
        assert(_until(() => card.bodyOffset >= body.edit.implicitHeight - body.height - 0.5), "the body at its end (" + card.bodyOffset + ")");
        const listBefore = centreList.contentY;
        assert(input.pointAt(body, body.width / 2, body.height / 2) && input.wheel(1), "a notch more over the body at its end");
        assert(_until(() => centreList.contentY > listBefore), "the list scrolls on (" + listBefore + " → " + centreList.contentY + ")");
        centreList.contentY = 0;
        input.wheel(-30);
        assert(_until(() => card.bodyOffset === 0), "notches back up: the body at its start");
        centreList.contentY = 0;
        _away();

        // A finger dragged up over the body scrolls the body, not the list
        _until(() => body.mapToItem(screenArea, 0, 0).y >= centreList.y);
        _drag(body, body.width / 2, body.height - 10, 0, -60, 8);
        assert(card.bodyOffset > 30, "a finger dragged up scrolls the centre's body (" + card.bodyOffset + ")");
        assertEqual(centreList.contentY, 0, "… not the list");

        // Dragged on past the body's end, the rest of the drag moves the list
        const endOffset = body.edit.implicitHeight - body.height;
        _drag(body, body.width / 2, body.height - 10, 0, -(endOffset + 120), 12);
        assert(Math.abs(card.bodyOffset - endOffset) < 0.5, "a long finger drag up takes the body to its end (" + card.bodyOffset + " of " + endOffset + ")");
        assert(centreList.contentY > 60, "… and the rest of it scrolls the list on (" + centreList.contentY + ")");
        // And back down, from where the body shows in the list: the body to its start, then
        // the list back to its top
        const shownY = Math.max(10, Math.min(body.height - 10, centreList.mapToItem(body, 0, centreList.height / 2).y));
        _drag(body, body.width / 2, shownY, 0, endOffset + 240, 12);
        assert(card.bodyOffset === 0 && centreList.contentY === 0,
               "a long finger drag down: the body at its start, the list at its top (" + card.bodyOffset + ", " + centreList.contentY + ")");
        _until(() => body.mapToItem(screenArea, 0, 0).y >= centreList.y);

        // A click on the body runs the default action
        const entry = centreItems[0];
        assert(input.click(body, body.width / 2, body.height / 2), "a click on the centre's body");
        assert(_until(() => entry.defaultRuns === 1), "the click runs the default action (" + entry.defaultRuns + ")");
        _away();
    }
}
