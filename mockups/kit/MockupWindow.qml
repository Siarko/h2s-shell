import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.singletons
import qs.components

// The window every mockup is: a Mockup.qml's root (mockups/<kind>/<name>/Mockup.qml), started
// by the root entry (mockup.qml). The mockup's items go into a content area of a fixed size
// (contentWidth x contentHeight), at the window's top-left corner, on the theme's
// background. The kit makes the window itself, once start() knows which one:
//   shooting   a panel anchored at the output's top-left corner, ignoring exclusive zones
//              (layer-shell namespace h2s-mockup), so that an item's window coordinates are
//              output coordinates and a shooter can crop to them
//   on screen  a normal window titled with the mockup's name, which the compositor
//              moves and resizes like any other: the buttons (one per state or scene)
//              along its top, the content under them, scrolled by the wheel and scroll
//              bars (never by a drag, which is the mockup's) when the window is smaller
//              than it (the window opens at the content's size, at most the screen's)
//
// A component or a view has states, a plan has scenes; the kit treats both alike (not
// `states`/`state`, which every Qt Quick Item has: a binding to `state` inside a mockup's item
// would read that item's own property). The states or scenes are declared in the element's
// about.txt (its description, then a `state:` or `scene:` line each), never in Mockup.qml:
// the entry reads it and hands the list over before the mockup's bindings run. The contract:
//   names         the names of the states or scenes, in their fixed order (read-only: a
//                 Mockup.qml that sets it fails to load); each non-empty, without whitespace
//                 or "/" (a name goes into the shot line and a file name), none repeated
//   descriptions  each one's description from about.txt, in the same order (read-only)
//   current       the current state or scene: the mockup binds its stand-in data to it
//   subject       the item a shot is cropped to; the content by default
//   subjectRect   overrides the crop, in window coordinates, for a subject spread over
//                 several items (a side panel and a modal); ignored while it has no size
//   now           the time every mockup shows (2026-01-15 10:30 UTC), handed to what shows
//                 a time or a date: a state must not depend on when it is drawn
//
// A mockup keeps no time of its own: no Timer, no read of the clock, no animation of a
// literal duration (tests/run-mockups.sh fails a component or view mockup that has one in
// its Mockup.qml). Animations take Theme's durations, which the entry makes instant; a
// looping one is off through the component's own property. A text field shows no cursor
// while shooting: the panel never takes the keyboard focus.
// `visible` shows and hides the window (the entry shows it once the mockup has started).
// A simulated pointer (hover, press) acts only inside the state's own cell: one cell per
// state, all shown while shooting, `subject` the state's cell, the pointer otherwise parked
// off every cell; nothing is shown or hidden under the pointer between states (Qt Quick
// sends hover again where the pointer was left).
//
// Shooting (shooting, set by the entry): each state or scene in turn is set, three frames are
// waited for once the window is mapped (the first frame after a change can still show the
// one before), and a line
//   MOCKUP-SHOT <i> <name> <x>,<y> <w>x<h>
// gives the subject's bounds; then the shooter calls `ipc call mockup next`. After the last
// one `finished` comes; an error (a bad list of names, a subject without a size, the shots
// taking longer than shotLimitMs in all) `failed`.
// On screen: the state or scene the entry names (H2S_MOCKUP_STATE, H2S_MOCKUP_SCENE), else
// the first, and a row of
// buttons above the content that switches between them, the current one checked.
//
// Over IPC (the config path is the entry's, the same for every mockup, so `name` tells
// running ones apart):
//   qs -p <tree>/mockup.qml ipc call mockup next   the next one, after a shot: "" or why not
//   qs -p <tree>/mockup.qml ipc call mockup name   the mockup's <kind>/<name>
//   qs -p <tree>/mockup.qml ipc call mockup current
//                                                  the current state or scene
//   qs -p <tree>/mockup.qml ipc call mockup window the window made: "panel" while shooting,
//                                                  "floating" on screen, "" before start()
//   qs -p <tree>/mockup.qml ipc call mockup scroller
//                         on screen, how the content scrolls: "wheel, vertical bar shown"
//                         (or hidden while the content fits; never "drag": a drag belongs
//                         to the mockup); "" while shooting
//   qs -p <tree>/mockup.qml ipc call mockup buttons
//                         the buttons inside the window: "<shown> of <names> shown,
//                         checked <name>" (none while shooting)
// With several mockups running on one display, `qs ipc --id <instance id>` (or --pid) picks
// one: the target is the same in all of them.
QtObject {
    id: root

    readonly property var names: declaredNames
    readonly property var descriptions: declaredDescriptions
    // Set by the entry from about.txt, as the mockup is created
    property var declaredNames: []
    property var declaredDescriptions: []
    property string current: ""
    // "state" for a component or a view, "scene" for a plan: the word in the messages
    readonly property string _word: mockupName.startsWith("plans/") ? "scene" : "state"
    property Item subject: content
    property rect subjectRect: Qt.rect(0, 0, 0, 0)
    readonly property date now: new Date(Date.UTC(2026, 0, 15, 10, 30, 0))

    property int contentWidth: 480
    property int contentHeight: 320
    // The mockup's own items go into the content area
    default property alias data: content.data

    property bool visible: true

    // Set by the entry before start()
    property string mockupName: ""
    property bool shooting: false
    property int shotLimitMs: 60000

    signal finished
    signal failed(string text)

    property int _index: -1
    property bool _waitingForNext: false
    property bool _done: false
    // The window start() made: the panel while shooting, a floating window on screen
    property var _window: null

    readonly property int _windowWidth: Math.max(contentWidth, shooting ? 0 : _switcher.implicitWidth)
    readonly property int _windowHeight: contentHeight + (shooting ? 0 : _switcher.implicitHeight)

    // The buttons wholly inside the window, and the checked one's name
    function _buttonsShown() {
        let shown = 0, checked = "";
        for (let i = 0; i < _buttons.count; i++) {
            const button = _buttons.itemAt(i);
            if (!button || !button.visible || !(button.width > 0 && button.height > 0))
                continue;
            const origin = button.mapToItem(null, 0, 0);
            if (origin.x < 0 || origin.y < 0 || origin.x + button.width > _window.width || origin.y + button.height > _window.height)
                continue;
            shown++;
            if (button.checked)
                checked = button.modelData;
        }
        return shown + " of " + names.length + " shown, checked " + checked;
    }

    // Why the list of names cannot be used, or ""
    function _namesError() {
        if (!Array.isArray(names) && !(names && typeof names.length === "number"))
            return "names is not a list";
        if (names.length === 0)
            return "no " + _word + "s";
        const seen = {};
        for (let i = 0; i < names.length; i++) {
            const name = names[i];
            if (typeof name !== "string" || name === "")
                return _word + " " + i + " has an empty name";
            if (/[\s\/]/.test(name))
                return _word + " name '" + name + "' has whitespace or '/'";
            if (seen[name])
                return _word + " name '" + name + "' is repeated";
            seen[name] = true;
        }
        return "";
    }

    // Whether the list of names can be used, without making a window: "" or why not
    function check() {
        return _namesError();
    }

    // Starts the mockup on `first` ("" for the first); "" or why it cannot start
    function start(first) {
        const error = _namesError();
        if (error !== "")
            return error;
        const index = shooting || first === "" ? 0 : Array.prototype.indexOf.call(names, first);
        if (index < 0)
            return "no " + _word + " '" + first + "' (the " + _word + "s: " + Array.prototype.join.call(names, " ") + ")";
        const window = (shooting ? _panelWindow : _floatingWindow).createObject(root);
        if (!window)
            return "the window cannot be made";
        _body.parent = window.contentItem;
        if (!shooting)
            content.parent = _scroller.contentItem;
        _window = window;
        if (shooting) {
            _show(0);
            return "";
        }
        _index = index;
        current = names[index];
        return "";
    }

    function _show(index) {
        _index = index;
        current = names[index];
        _settle.frames = 0;
        _settle.running = true;
    }

    function _shoot() {
        let bounds = subjectRect;
        if (!(bounds.width > 0 && bounds.height > 0)) {
            if (!subject) {
                failed("no subject");
                return;
            }
            const origin = subject.mapToItem(null, 0, 0);
            bounds = Qt.rect(origin.x, origin.y, subject.width, subject.height);
        }
        const x = Math.round(bounds.x), y = Math.round(bounds.y);
        const width = Math.round(bounds.width), height = Math.round(bounds.height);
        if (width <= 0 || height <= 0) {
            failed(_word + " '" + current + "': the subject has no size");
            return;
        }
        if (x < 0 || y < 0 || x + width > _window.width || y + height > _window.height) {
            failed(_word + " '" + current + "': the subject (" + x + "," + y + " " + width + "x" + height
                   + ") is not inside the window (" + _window.width + "x" + _window.height + ")");
            return;
        }
        console.info("MOCKUP-SHOT " + _index + " " + current + " " + x + "," + y + " " + width + "x" + height);
        _waitingForNext = true;
    }

    function _next() {
        if (!shooting)
            return "not shooting";
        if (_done)
            return "finished";
        if (!_waitingForNext)
            return "no shot is waiting";
        _waitingForNext = false;
        if (_index + 1 >= names.length) {
            _done = true;
            finished();
        }
        else
            _show(_index + 1);
        return "";
    }

    readonly property Component _panelWindow: Component {
        PanelWindow {
            anchors {
                top: true
                left: true
            }
            margins {
                top: 0
                left: 0
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "h2s-mockup"
            implicitWidth: root._windowWidth
            implicitHeight: root._windowHeight
            color: Theme.popupBackground
            visible: root.visible
        }
    }

    readonly property Component _floatingWindow: Component {
        FloatingWindow {
            title: root.mockupName
            implicitWidth: Math.min(root._windowWidth, screen ? screen.width : root._windowWidth)
            implicitHeight: Math.min(root._windowHeight, screen ? screen.height : root._windowHeight)
            color: Theme.popupBackground
            visible: root.visible
        }
    }

    // The content and the buttons, put into the window start() makes: while shooting
    // the content at the window's corner; on screen the buttons, and under them the content
    // moved into the scroller
    readonly property Item _body: Item {
        width: parent ? parent.width : root._windowWidth
        height: parent ? parent.height : root._windowHeight

        Item {
            id: content
            x: 0
            y: 0
            width: root.contentWidth
            height: root.contentHeight
        }

        Flickable {
            id: _scroller
            visible: !root.shooting
            y: _switcher.height
            width: parent.width
            height: Math.max(0, parent.height - y)
            contentWidth: root.contentWidth
            contentHeight: root.contentHeight
            boundsBehavior: Flickable.StopAtBounds
            // Nothing of the mockup's own reaches over the buttons
            clip: true
            // A drag belongs to the mockup (a slider, a text selection), never to the
            // scroller: it scrolls by the wheel and its scroll bars only
            interactive: false

            // Scrolls by the wheel where the mockup's own items did not take it; a
            // horizontal wheel, or Shift with a vertical one, scrolls sideways
            WheelHandler {
                target: null
                onWheel: event => {
                    const step = (pixel, angle) => pixel !== 0 ? pixel : angle / 120 * 48;
                    let dx = step(event.pixelDelta.x, event.angleDelta.x);
                    let dy = step(event.pixelDelta.y, event.angleDelta.y);
                    if (event.modifiers & Qt.ShiftModifier && dx === 0) {
                        dx = dy;
                        dy = 0;
                    }
                    const flick = _scroller;
                    flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - dx));
                    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - dy));
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: _scroller.contentHeight > _scroller.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: width / 2
                    color: Theme.textSecondary
                }
            }
            ScrollBar.horizontal: ScrollBar {
                policy: _scroller.contentWidth > _scroller.width ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                contentItem: Rectangle {
                    implicitHeight: 6
                    radius: height / 2
                    color: Theme.textSecondary
                }
            }
        }

        Flow {
            id: _switcher
            visible: !root.shooting
            width: parent.width
            padding: Theme.popup.contentPadding
            spacing: Theme.popup.contentPadding
            Repeater {
                id: _buttons
                model: ScriptModel {
                    values: root.shooting ? [] : Array.prototype.slice.call(root.names)
                }
                SmallButton {
                    required property string modelData
                    label: modelData
                    checked: modelData === root.current
                    onClicked: root.current = modelData
                }
            }
        }
    }

    // Three frames after a state or scene is set, then the shot line
    readonly property FrameAnimation _settle: FrameAnimation {
        property int frames: 0
        running: false
        onTriggered: {
            if (!root._window || !root._window.backingWindowVisible || ++frames < 3)
                return;
            running = false;
            root._shoot();
        }
    }

    // The guard against a hang while shooting: a state that never settles, a shooter that
    // never calls next
    readonly property Timer _limit: Timer {
        interval: root.shotLimitMs
        running: root.shooting && root._index >= 0 && !root._done
        onTriggered: {
            root._done = true;
            root._settle.running = false;
            root.failed("the shots took longer than " + root.shotLimitMs + " ms (at " + root._word + " " + root._index + " '" + root.current + "', "
                        + (root._waitingForNext ? "waiting for next" : "settling") + ")");
        }
    }

    readonly property IpcHandler _ipc: IpcHandler {
        target: "mockup"

        function next(): string {
            return root._next();
        }

        function name(): string {
            return root.mockupName;
        }

        function current(): string {
            return root.current;
        }

        function window(): string {
            return !root._window ? "" : root.shooting ? "panel" : "floating";
        }

        function buttons(): string {
            return root._window ? root._buttonsShown() : "";
        }

        function scroller(): string {
            if (!root._window || root.shooting)
                return "";
            const bar = _scroller.ScrollBar.vertical;
            return (_scroller.interactive ? "drag" : "wheel") + ", vertical bar "
                + (bar && bar.visible && bar.policy === ScrollBar.AlwaysOn ? "shown" : "hidden");
        }
    }
}
