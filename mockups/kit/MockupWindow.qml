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
//              moves and resizes like any other: the content scrolled by the wheel and
//              scroll bars (never by a drag, which is the mockup's) when the window is
//              smaller than it (the window opens at the content's size, at most the
//              screen's); a plan's buttons (one per scene) along its top
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
//   pointerStates the states a simulated pointer shows (hover, press), and keyboardStates
//   keyboardStates the ones the keyboard's focus shows: one pointer and one focus cannot
//                 show them all at once, so their labels in the all-states layout say how
//                 to see them
//   layout        how the window shows the mockup (set by start()): "shot", "all", "one" or
//                 "buttons"
//   now           the time every mockup shows (2026-01-15 10:30 UTC), handed to what shows
//                 a time or a date: a state must not depend on when it is drawn
//
// A mockup keeps no time of its own: no Timer, no read of the clock, no animation of a
// literal duration (tests/run-mockups.sh fails a component or view mockup that has one in
// its Mockup.qml). Animations take Theme's durations, which the entry makes instant; a
// looping one is off through the component's own property. A text field shows no cursor
// while shooting: the panel never takes the keyboard focus.
// `visible` shows and hides the window (the entry shows it once the mockup has started).
// On screen, the window closed by the user or the compositor emits `closed`, on which the
// entry ends the process: a mockup is never left running without a window.
// A component's or a view's states are cells: a StateGrid among its items, a StateCell per
// state in it (StateGrid.qml). The grid then sets the content's size and the subject (the
// current cell), and lays the cells out by `layout`: while shooting all side by side (or on
// one another), on screen with no state named all of them labelled ("all", `current`
// empty), with one named that one labelled ("one"). A mockup without one, and a plan, shows
// its current state or scene under a row of buttons ("buttons"), each button's tooltip its
// description.
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
// On screen: the state or scene the entry names (H2S_MOCKUP_STATE, H2S_MOCKUP_SCENE); with
// none, every state of a component or view with cells, else the first, and for a plan (or a
// mockup without cells) a row of buttons above the content that switches between them, the
// current one checked.
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
//   qs -p <tree>/mockup.qml ipc call mockup position
//                         on screen, how far the content is scrolled: "<x>,<y>" in pixels
//                         ("" while shooting)
//   qs -p <tree>/mockup.qml ipc call mockup buttons
//                         the buttons inside the window: "<shown> of <names> shown,
//                         checked <name>" (none while shooting)
//   qs -p <tree>/mockup.qml ipc call mockup tooltips
//                         each button's "<name>: <tooltip>", a line each
//   qs -p <tree>/mockup.qml ipc call mockup cells
//                         the cells shown: "<shown> of <names> shown, none overlapping" (or
//                         "overlapping <a>/<b> …", a cell's label named <name>:label), then
//                         each shown cell's label a line, in order; "no cells: …" for a
//                         plan or a mockup without a StateGrid
//   qs -p <tree>/mockup.qml ipc call mockup theme <name>
//                         on screen, shows it in that theme (MockupTheme; "" only asks):
//                         the name in force, or why not
//   qs -p <tree>/mockup.qml ipc call mockup grab <state> <path>
//                         saves that state's cell as drawn into a PNG at <path>, which
//                         appears once done: "" or why not
// Hosted (`host` set as it is created, by the gallery): start() makes no window, lays the
// content out in `host` in all its states, and the IpcHandler is off.
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

    // The states a simulated pointer or the keyboard shows, which the all-states layout
    // cannot show at once (one pointer, one keyboard focus): their labels say how to see them
    property var pointerStates: []
    property var keyboardStates: []
    // How the window shows the mockup, set by start(): "shot" while shooting; on screen
    // "all" (every state's cell, labelled), "one" (one state's cell, labelled) or
    // "buttons" (a plan, or a mockup without a StateGrid: the current state or scene under a
    // row of buttons); "" before start()
    property string layout: ""
    // The mockup's StateGrid, found by start(); null when it has none
    property Item _grid: null
    // The mockup's own items go into the content area
    default property alias data: content.data

    property bool visible: true

    // Set by the entry before start()
    property string mockupName: ""
    // Hosted (the gallery): no window and no IpcHandler of its own, the content laid out in
    // `host` (its width the one the cells flow in); one process, many mockups, one IPC target
    property Item host: null
    readonly property bool hosted: host !== null
    property bool shooting: false
    property int shotLimitMs: 60000

    signal finished
    signal failed(string text)
    // The floating window closed by the user or the compositor (never while shooting)
    signal closed

    property int _index: -1
    property bool _waitingForNext: false
    property bool _done: false
    // The window start() made: the panel while shooting, a floating window on screen
    property var _window: null

    readonly property bool _withButtons: layout === "buttons"
    readonly property int _switcherHeight: _withButtons ? _switcher.implicitHeight : 0
    readonly property int _windowWidth: Math.max(contentWidth, _withButtons ? _switcher.implicitWidth : 0)
    readonly property int _windowHeight: contentHeight + _switcherHeight
    // The content's size as laid out: with a StateGrid on screen it follows the window's width
    readonly property int _laidWidth: _grid ? _grid.laidWidth : contentWidth
    readonly property int _laidHeight: _grid ? _grid.laidHeight : contentHeight

    // What a pointer or keyboard state's label adds in the all-states layout
    function hintFor(name) {
        const element = mockupName.replace(/^[^\/]*\//, "");
        if (Array.prototype.includes.call(pointerStates, name))
            return " (point at it, or open " + element + "/" + name + ")";
        if (Array.prototype.includes.call(keyboardStates, name))
            return " (one item has the keyboard at a time: open " + element + "/" + name + ")";
        return "";
    }

    // The StateGrid among the content's items, depth first
    function _findGrid(item) {
        for (const child of item.children) {
            if (child.isStateGrid)
                return child;
            const inner = _findGrid(child);
            if (inner)
                return inner;
        }
        return null;
    }

    // The cells shown and their labels: "<shown> of <names> shown, <none|overlapping …>",
    // then each shown cell's label on a line of its own, in order (on screen; while shooting
    // the cells without labels)
    function _cellsShown() {
        if (!_grid)
            return "no cells: " + (_word === "scene" ? "a plan, its scene buttons" : "no StateGrid, the state buttons");
        const boxes = [];
        const lines = [];
        for (const cell of _grid.cells) {
            if (!cell.visible || !(cell.width > 0 && cell.height > 0))
                continue;
            const origin = cell.mapToItem(content, 0, 0);
            boxes.push({ name: cell.name, x: origin.x, y: origin.y, w: cell.width, h: cell.height });
            const label = _grid.labelItem(cell.name);
            if (label && label.visible) {
                const at = label.mapToItem(content, 0, 0);
                boxes.push({ name: cell.name + ":label", x: at.x, y: at.y, w: label.width, h: label.height });
                lines.push(label.text);
            } else {
                lines.push(cell.name);
            }
        }
        const overlapping = [];
        for (let i = 0; i < boxes.length; i++)
            for (let j = i + 1; j < boxes.length; j++) {
                const a = boxes[i], b = boxes[j];
                if (a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h)
                    overlapping.push(a.name + "/" + b.name);
            }
        return [lines.length + " of " + names.length + " shown, " + (overlapping.length ? "overlapping " + overlapping.join(" ") : "none overlapping")]
            .concat(lines).join("\n");
    }

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
        const seen = Object.create(null);
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
        // A plan keeps its scene buttons; a component or view with state cells shows them
        _grid = _word === "state" ? _findGrid(content) : null;
        layout = shooting ? "shot" : !_grid ? "buttons" : first === "" ? "all" : "one";
        // Every state at once: open modals side by side must not take the keyboard from each
        // other without end
        if (layout === "all")
            Isolation.keyboardHeld = false;
        if (_grid) {
            _grid.mockup = root;
            _grid.availableWidth = Qt.binding(() => hosted ? host.width : _scroller.width);
            contentWidth = Qt.binding(() => _grid.preferredWidth);
            contentHeight = Qt.binding(() => _grid.preferredHeight);
            subject = Qt.binding(() => _grid.currentCell ?? content);
        }
        if (hosted) {
            content.parent = host;
            _index = index;
            current = layout === "all" ? "" : names[index];
            return "";
        }
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
        // All states at once: none is current, the simulated pointer stays off every cell
        current = layout === "all" ? "" : names[index];
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
            onClosed: root.closed()
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
            width: root._laidWidth
            height: root._laidHeight
        }

        Flickable {
            id: _scroller
            visible: !root.shooting
            y: root._switcherHeight
            width: parent.width
            height: Math.max(0, parent.height - y)
            contentWidth: root._laidWidth
            contentHeight: root._laidHeight
            boundsBehavior: Flickable.StopAtBounds
            // Nothing of the mockup's own reaches over the buttons
            clip: true
            // A drag belongs to the mockup (a slider, a text selection), never to the
            // scroller: it scrolls by the wheel and its scroll bars only
            interactive: false

            // Scrolls by the wheel where the mockup's own items did not take it; a
            // horizontal wheel, or Shift with a vertical one, scrolls sideways. Qt on Wayland
            // hands a mouse wheel's notches over as from a touchpad device (every axis event
            // has a pixel delta), so both devices are taken; and a WheelHandler takes one
            // orientation only, so there is one for each
            function _scrollBy(dx, dy) {
                contentX = Math.max(0, Math.min(contentWidth - width, contentX - dx));
                contentY = Math.max(0, Math.min(contentHeight - height, contentY - dy));
            }
            // How far an event moves along one axis: a notch (no scroll phase) by its angle,
            // a touchpad's stroke by its pixels
            function _step(pixel, angle, phase) {
                return phase === Qt.NoScrollPhase || pixel === 0 ? angle / 120 * 48 : pixel;
            }

            WheelHandler {
                target: null
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const step = _scroller._step(event.pixelDelta.y, event.angleDelta.y, event.phase);
                    if (event.modifiers & Qt.ShiftModifier)
                        _scroller._scrollBy(step, 0);
                    else
                        _scroller._scrollBy(0, step);
                }
            }
            WheelHandler {
                target: null
                orientation: Qt.Horizontal
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => _scroller._scrollBy(_scroller._step(event.pixelDelta.x, event.angleDelta.x, event.phase), 0)
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
            visible: root._withButtons
            width: parent.width
            padding: Theme.popup.contentPadding
            spacing: Theme.popup.contentPadding
            Repeater {
                id: _buttons
                model: ScriptModel {
                    values: root._withButtons ? Array.prototype.slice.call(root.names) : []
                }
                SmallButton {
                    required property string modelData
                    required property int index
                    label: modelData
                    tooltip: root.descriptions[index] ?? ""
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
        enabled: !root.hosted

        function next(): string {
            return root._next();
        }

        function name(): string {
            return root.mockupName;
        }

        function current(): string {
            return root.current;
        }

        // Shows the mockup in that theme ("" only asks): the name in force, or why not
        function theme(name: string): string {
            return MockupTheme.apply(name);
        }

        // Saves the cell of a state as drawn (grabToImage) into a PNG at `path`: "" once
        // started, or why not; the file appears when it is done
        function grab(name: string, path: string): string {
            const cell = root._grid ? root._grid.cells.find(c => c.name === name) : null;
            if (!cell || !cell.visible)
                return "no cell '" + name + "' shown";
            return cell.grabToImage(result => result.saveToFile(path)) ? "" : "the cell cannot be grabbed";
        }

        function cells(): string {
            return root._window ? root._cellsShown() : "";
        }

        function tooltips(): string {
            if (!root._window)
                return "";
            const lines = [];
            for (let i = 0; i < _buttons.count; i++) {
                const button = _buttons.itemAt(i);
                if (button)
                    lines.push(button.modelData + ": " + button.tooltip);
            }
            return lines.join("\n");
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

        function position(): string {
            if (!root._window || root.shooting)
                return "";
            return Math.round(_scroller.contentX) + "," + Math.round(_scroller.contentY);
        }
    }
}
