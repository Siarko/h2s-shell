import QtQuick
import QtQuick.Layouts
import qs.singletons

// Reusable interactive bar widget with click and hover signals
Item {
    id: container
    // Key into WidgetRegistry and the widget preset library
    property string widgetType: ""
    property color cellColor: Theme.surface
    // When true, keeps the cell highlighted regardless of hover (e.g. while its popup is open)
    property bool active: false
    // Optional outline around the cell — off by default, so existing widgets are unaffected
    property color borderColor: Theme.capsuleBorder
    property int borderWidth: Theme.capsule.borderWidth
    // False for widgets with several click targets of their own (tray icons, workspace
    // buttons): the cell keeps its size and background but stops taking input, which
    // otherwise lands on its full-size MouseArea above the content
    property bool interactive: true
    // Space between the content and the cell edge, on each side
    property int horizontalPadding: Theme.capsule.horizontalPadding
    // Emitted on click, carries the cell's color
    signal clicked(cellColor: color)
    // Emitted when a pointer that can hover — a mouse, a touchpad, a stylus held above the
    // screen — comes over the cell (true) and leaves it (false). Not for a finger: a touch
    // screen reports a press as hover, and a hover popup opened by it could not be closed.
    // The device a hover names cannot tell them apart (a touch is reported as a touch
    // screen, or as a touchpad when the finger slides in), the timing
    // can: a finger's hover comes with its press, within milliseconds. So hover is passed on
    // only after a moment with no touch press (_hoverSettle).
    signal hover(status: bool)
    // Whether the last press came from a touch screen (Qt makes it a mouse press), so a
    // click can be told from a tap: a popup opened by a tap behaves for touch (PopupWidget)
    property bool lastPressByTouch: false
    // Emitted on every wheel event, with its movement in notches (fractional)
    signal scrolled(delta: real)
    // Emitted for each whole notch, 1 for up, -1 for down (ScrollNotches)
    signal scrollNotch(direction: int)
    // Emitted on middle mouse button click
    signal middleClicked
    // Every pointer interaction on the cell, once per occurrence, named as InteractionRules
    // names them ("leftClick", "rightClick", "shiftClick", "doubleClick", "longPress",
    // "scrollUp", "scroll", "scrollSideways", "scrollLeft", "hover", …). `details`:
    // { phase: "start" or "end" for an interaction with an end (hover, longPress), else "";
    //   byTouch; amount: the movement in notches for a continuous scroll (positive up and
    //   right), ±1 for a step, else 0; direction: "up", "down", "left", "right" or "" }.
    // A finger's tap is reported as "tap" (byTouch true); its double tap, hold and swipes
    // are not reported yet. The signals above keep firing as they always have, whatever
    // this one reports. Each interaction goes to WidgetActions, which runs what the entry
    // binds to it: the cell's one input layer.
    signal interaction(name: string, details: var)
    // What the entry binds, interaction => resolved binding (InteractionRules.lookupFor);
    // null: nothing bound. It decides what each interaction runs, whether a plain click
    // waits for a second one (only when a double click is bound) and whether a scroll is
    // reported as one continuous movement or as whole notches. The bar sets its entry's;
    // a cell made elsewhere has its type's, with its preset where it declares one.
    property var bindingLookup: WidgetPresets.bindingLookup(widgetType, typeof container.preset === "string" ? container.preset : "")

    // Runs one of the widget's own actions (WidgetRegistry `actions`), named by its id, when
    // an interaction bound to it occurs. `details`, frozen: { interaction, amount (an adjust
    // action's signed amount), direction, byTouch, preset }. A widget with actions overrides it.
    function runAction(id, details) {
    }

    // Whether the effect of an own action that declares `state` holds now, so alternate
    // and cycle go on from the state
    function actionHolds(id) {
        return false;
    }

    // Where each interaction's alternate or cycle stands, for this bar entry
    property var _actionMemory: ({})

    Layout.fillHeight: true
    Layout.preferredHeight: 20
    Layout.topMargin: 5
    Layout.bottomMargin: 5
    Layout.minimumWidth: 40
    // On a bar at a side the cell is as wide as the bar (its Loader sizes it) and as tall
    // as its content, the padding then above and below it
    readonly property bool vertical: BarLayout.vertical
    implicitWidth: vertical ? 0 : contentItem.childrenRect.width + horizontalPadding * 2
    implicitHeight: vertical ? contentItem.childrenRect.height + horizontalPadding * 2 : 0

    default property alias content: contentItem.data

    readonly property ScrollNotches _notches: ScrollNotches {}
    // The interactions' own notches, apart from the ones scrollNotch reports, which are
    // left as they always were
    readonly property ScrollNotches _verticalSteps: ScrollNotches {}
    readonly property ScrollNotches _horizontalSteps: ScrollNotches {}

    Rectangle {
        id: rectangle
        radius: Theme.capsule.radius
        anchors.fill: parent
        color: (mouseArea.lit || container.active) ? Theme.surfaceHover : container.cellColor
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
        border.color: container.borderColor
        border.width: container.borderWidth
    }

    // Free-standing item for measuring content size without anchoring loops
    Item {
        id: contentItem
        anchors.centerIn: parent
    }

    // At least Theme.target.minSize around the cell (PointerArea): the bar's whole height
    PointerArea {
        id: mouseArea
        enabled: container.interactive
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        onPressed: event => {
            container.lastPressByTouch = PointerRules.pressIsTouch(event.source);
            if (container.lastPressByTouch)
                _hoverSettle.stop();
            container._held = false;
            container._pressAt = Qt.point(event.x, event.y);
            // Armed only where a long press is bound: otherwise a slow click stays a click
            if (!container.lastPressByTouch && InteractionRules.holdInteraction(event.button, false) !== ""
                    && InteractionRules.armsLongPress(false, container._lookup))
                _holdTimer.restart();
            else
                _holdTimer.stop();
        }
        // A press that moves away is a drag, not a hold (Qt's own pressAndHold the same)
        onPositionChanged: event => {
            if (_holdTimer.running && Math.hypot(event.x - container._pressAt.x, event.y - container._pressAt.y) > Qt.styleHints.startDragDistance)
                _holdTimer.stop();
        }
        onReleased: {
            _holdTimer.stop();
            container._endHold();
        }
        onCanceled: {
            _holdTimer.stop();
            container._endHold();
        }
        onContainsMouseChanged: {
            if (containsMouse) {
                _hoverSettle.restart();
            } else {
                _hoverSettle.stop();
                if (container._hoverReported) {
                    container._hoverReported = false;
                    container.hover(false);
                    container._report(InteractionRules.hoverInteraction(false), "end", 0, "");
                }
            }
        }
        onClicked: event => {
            if (event.button === Qt.MiddleButton)
                container.middleClicked();
            else if (event.button === Qt.LeftButton)
                container.clicked(container.cellColor);
            container._reportClick(event.button, event.modifiers);
        }
        onWheel: event => {
            container.scrolled(container._notches.notches(event.angleDelta.y));
            const direction = container._notches.feed(event.angleDelta.y);
            if (direction !== 0)
                container.scrollNotch(direction);
            container._reportWheel("vertical", event.angleDelta.y, container._verticalSteps);
            container._reportWheel("horizontal", event.angleDelta.x, container._horizontalSteps);
        }
    }

    readonly property var _lookup: bindingLookup ?? (name => undefined)
    // The press-and-hold fired for the press going on: its release ends it, and is no click
    property bool _held: false
    // …and its end is still to be reported
    property bool _holdOpen: false
    property point _pressAt: Qt.point(0, 0)

    function _report(name, phase, amount, direction, byTouch = false) {
        if (name === "")
            return;
        const details = { phase: phase, byTouch: byTouch, amount: amount, direction: direction };
        interaction(name, details);
        WidgetActions.handle(container, name, details);
    }

    // A plain click held back while a second one may come: it goes now, before what follows
    function _flushClick() {
        if (!_doubleWait.running)
            return;
        _doubleWait.stop();
        _report("leftClick", "", 0, "");
    }

    function _endHold() {
        if (!_holdOpen)
            return;
        _holdOpen = false;
        _report(InteractionRules.holdInteraction(Qt.LeftButton, false), "end", 0, "");
    }

    function _reportClick(button, modifiers) {
        // A finger's press is a tap (its double tap and hold come with the finger
        // interactions); the release of a hold was the hold's
        if (lastPressByTouch) {
            _report(InteractionRules.pressInteraction({ button: button, modifiers: modifiers, byTouch: true, held: false, second: false, swiped: false }), "", 0, "", true);
            return;
        }
        const event = { button: button, modifiers: modifiers, byTouch: false, held: _held, second: false, swiped: false };
        const name = InteractionRules.pressInteraction(event);
        if (name === "leftClick" && InteractionRules.waitsForDouble(false, _lookup)) {
            if (_doubleWait.running) {
                _doubleWait.stop();
                event.second = true;
                _report(InteractionRules.pressInteraction(event), "", 0, "");
            } else {
                _doubleWait.restart();
            }
            return;
        }
        _flushClick();
        if (name !== "longPress")
            _report(name, "", 0, "");
    }

    function _reportWheel(axis, angleDelta, steps) {
        if (angleDelta === 0)
            return;
        // Every whole notch the event completes: a fast wheel's one event may hold two
        let whole = steps.feed(angleDelta);
        for (let next = steps.feed(0); next !== 0; next = steps.feed(0))
            whole += next;
        const found = InteractionRules.scrollInteractions(axis, steps.notches(angleDelta), whole, _lookup);
        for (const occurrence of found)
            for (let i = 0; i < occurrence.times; i++)
                _report(occurrence.interaction, "", occurrence.amount, occurrence.direction);
    }

    Timer {
        id: _holdTimer
        interval: mouseArea.pressAndHoldInterval
        onTriggered: {
            if (!mouseArea.pressed || container.lastPressByTouch)
                return;
            container._flushClick();
            container._held = true;
            container._holdOpen = true;
            container._report(InteractionRules.holdInteraction(Qt.LeftButton, false), "start", 0, "");
        }
    }

    Timer {
        id: _doubleWait
        interval: Qt.styleHints.mouseDoubleClickInterval
        onTriggered: container._report("leftClick", "", 0, "")
    }

    property bool _hoverReported: false

    Timer {
        id: _hoverSettle
        interval: 60
        onTriggered: {
            if (!mouseArea.containsMouse || (mouseArea.pressed && container.lastPressByTouch))
                return;
            container._hoverReported = true;
            container.hover(true);
            container._report(InteractionRules.hoverInteraction(false), "start", 0, "");
        }
    }
}
