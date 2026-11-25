import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.singletons

// The cell's one input layer under real input events: each core widget, loaded from the
// registry and wired as the bar wires it, gets a hover, clicks, the wheel and a tap, and
// what it does goes through InteractionRules and WidgetActions to its own actions (on
// stand-in targets) or its popup (a stand-in popup). A config written before bindings
// (tests/fixtures/widget-bindings/existing-config.json) does what it did before, for every
// core type and each popup mode; a binding stored in a preset, a declared left click over
// the popup, alternate and cycle from state or memory. The rules alone: InteractionRulesTest,
// CoreActionRulesTest.
//
// Opens a small window in a corner of the screen for a moment (a layer surface, so it
// moves no windows).
TestCase {
    id: suite
    suiteName: "WidgetActions"
    asynchronous: true

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 400
        implicitHeight: 120
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Somewhere for the mouse to go that is no cell
        Item {
            id: away
            width: 40
            height: 40
        }

        // Where each widget is made, one at a time
        Item {
            id: host
            x: 80
            width: 300
            height: 40
        }

        // A popup widget whose type declares a left click of its own
        PopupWidget {
            id: ownPopupCell
            x: 80
            y: 60
            width: 100
            height: 40
            widgetType: "clock"
            popup: fakePopup
            visible: false
            function runAction(id, details) {
                suite._record("own " + id + " byTouch=" + details.byTouch);
            }
        }

        WindowDriver {
            id: driver
            name: "WidgetActionsDriver"
        }
    }

    // What the widgets did in the step going on
    property var _effects: []
    function _record(effect) {
        _effects.push(effect);
    }

    // Records what PopupWidget asks of its popup
    property QtObject _fakePopup: QtObject {
        id: fakePopup
        property bool active: false
        property string contentType: ""
        property Item openedBy: null
        function open(element, persistent, contentType, contentData, byTouch) {
            suite._record("popup open persistent=" + persistent + " byTouch=" + byTouch);
            fakePopup.active = true;
            fakePopup.contentType = contentType;
            fakePopup.openedBy = element;
        }
        function close() {
            suite._record("popup close");
            fakePopup.active = false;
        }
    }

    // Stand-ins for what the widgets' own actions act on
    property QtObject _music: QtObject {
        property bool playing: false
        function togglePlay() { suite._record("music.togglePlay"); }
        function next() { suite._record("music.next"); }
        function previous() { suite._record("music.previous"); }
        function play() { suite._record("music.play"); }
        function pause() { suite._record("music.pause"); }
    }
    property QtObject _sound: QtObject {
        property QtObject sink: QtObject {
            property QtObject audio: QtObject {
                property real volume: 0.5
                property bool muted: false
                onVolumeChanged: if (suite._recording) suite._record("sound.volume=" + Math.round(volume * 100) / 100)
                onMutedChanged: if (suite._recording) suite._record("sound.muted=" + muted)
            }
        }
    }
    property QtObject _settings: QtObject {
        function toggleSettings() { suite._record("settings.toggleSettings"); }
    }
    property QtObject _stt: QtObject {
        property string server: "off"
        property string dictation: "idle"
        function toggle() { suite._record("stt.toggle"); }
        function start() { suite._record("stt.start"); }
        function stop() { suite._record("stt.stop"); }
        function serverStart() { suite._record("stt.serverStart"); }
        function serverStop() { suite._record("stt.serverStop"); }
    }
    readonly property var _targets: ({ music: _music, sound: _sound, settings: _settings, stt: _stt })
    property bool _recording: false

    property FileView _file: FileView {
        blockAllReads: true
        printErrors: false
    }

    function _json(relative) {
        _file.path = Quickshell.shellDir + "/" + relative;
        _file.reload();
        const text = _file.text();
        _file.path = "";
        try {
            return JSON.parse(text);
        } catch (error) {
            return null;
        }
    }

    // The bar entry's widget, made and wired as Bar's _wireWidget does
    property var _entry: ({ type: "", preset: "" })
    property var _seen: []

    function _make(type, preset) {
        suite._entry = { type: type, preset: preset };
        const component = Qt.createComponent(WidgetRegistry.widgetUrl(type));
        if (component.status !== Component.Ready) {
            fail(type + ": its widget does not load: " + component.errorString());
            return null;
        }
        const item = component.createObject(host, { x: 0, y: 0 });
        if (typeof item.popup !== "undefined")
            item.popup = fakePopup;
        if (typeof item.preset !== "undefined")
            item.preset = Qt.binding(() => suite._entry.preset);
        if (typeof item.bindingLookup !== "undefined")
            item.bindingLookup = Qt.binding(() => WidgetPresets.bindingLookup(suite._entry.type ?? "", suite._entry.preset ?? ""));
        if (typeof item.actionTarget !== "undefined")
            item.actionTarget = _targets[type];
        item.width = Math.max(item.implicitWidth, 60);
        item.height = 30;
        suite._seen = [];
        item.interaction.connect((name, details) => suite._seen.push(name + (details.phase !== "" ? ":" + details.phase : "")));
        return item;
    }

    function _resetEffects() {
        _recording = false;
        fakePopup.active = false;
        fakePopup.contentType = "";
        fakePopup.openedBy = null;
        _sound.sink.audio.volume = 0.5;
        _sound.sink.audio.muted = false;
        _effects = [];
        _recording = true;
    }

    function _until(condition, limitMs = 5000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    function _tap(item) {
        const touch = driver.touchEvent(item);
        touch.press(0, item, item.width / 2, item.height / 2).commit();
        driver.wait(150);
        touch.release(0, item, item.width / 2, item.height / 2).commit();
        driver.wait(50);
    }

    // The steps a cell is driven through: hover first, the mouse then stays over it
    readonly property var _steps: ["hover", "leftClick", "shiftClick", "middleClick", "rightClick", "scrollUp", "scrollDown", "tap"]

    function _drive(item, step) {
        const x = item.width / 2;
        const y = item.height / 2;
        const before = _seen.length;
        switch (step) {
        case "hover":
            driver.mouseMove(item, x, y);
            assert(_until(() => _seen.includes("hover:start")), "hover reported");
            break;
        case "leftClick":
            driver.mouseClick(item, x, y, Qt.LeftButton);
            break;
        case "shiftClick":
            driver.mouseClick(item, x, y, Qt.LeftButton, Qt.ShiftModifier);
            break;
        case "middleClick":
            driver.mouseClick(item, x, y, Qt.MiddleButton);
            break;
        case "rightClick":
            driver.mouseClick(item, x, y, Qt.RightButton);
            break;
        case "scrollUp":
            driver.mouseWheel(item, x, y, 0, 120);
            break;
        case "scrollDown":
            driver.mouseWheel(item, x, y, 0, -120);
            break;
        case "tap":
            _tap(item);
            break;
        }
        assert(_seen.length > before, step + ": the cell reported it");
    }

    function _leave() {
        driver.mouseMove(away, 5, 5);
        driver.wait(100);
    }

    // What every entry of a config written before bindings does: what it did before
    function _existingConfig() {
        const fixture = _json("tests/fixtures/widget-bindings/existing-config.json");
        assert(fixture !== null, "the fixture reads");
        if (fixture === null)
            return;
        Config.profiles = JSON.stringify(fixture.profiles);
        Config.widgetPresets = JSON.stringify(fixture.widgetPresets);
        const sections = fixture.profiles[0].set;
        const seen = [];
        for (const side of ["left", "center", "right"]) {
            sections["bar." + side].forEach((entry, index) => {
                const label = side + "/" + index + " " + entry.type;
                seen.push(label);
                const wanted = fixture.effects[label];
                const item = _make(entry.type, entry.preset);
                if (!item)
                    return;
                if (typeof wanted === "string") {
                    assert(!item.interactive && item.bindingLookup === null, label + ": " + wanted + ", the cell takes no input");
                    item.destroy();
                    return;
                }
                _leave();
                for (const step of _steps) {
                    _resetEffects();
                    _drive(item, step);
                    assertEqual(JSON.stringify(_effects), JSON.stringify(wanted[step] ?? []), label + ", " + step + ": does what it did before");
                }
                _leave();
                _recording = false;
                item.destroy();
            });
        }
        assertEqual(seen.join(","), Object.keys(fixture.effects).join(","), "every entry of the fixture driven");
        assertEqual(new Set(seen.map(label => label.split(" ")[1])).size, WidgetRegistry.coreEntries.length, "… every core widget type among them");
    }

    // Bindings stored in a preset reach the widget; alternate and cycle step from the state
    // where the actions tell it, else from memory
    function _presetBindings() {
        const own = id => ({ mode: "single", action: { action: "own:" + id } });
        const cycle = ids => ({ mode: "cycle", actions: ids.map(id => ({ action: "own:" + id })) });
        Config.profiles = JSON.stringify([{ name: "Full", set: {} }]);
        Config.widgetPresets = JSON.stringify({
            music: { "Music 1": { "on.middleClick": own("next"), "on.rightClick": cycle(["next", "previous"]),
                                  "on.leftClick": null, "on.scrollUp": cycle(["play", "pause"]) } },
            stt: { "Stt 1": { "on.middleClick": cycle(["serverStart", "serverStop"]), "on.rightClick": own("serverToggle"),
                              "on.scrollUp": cycle(["start", "stop"]) } },
            sound: { "Sound 1": { "on.scrollUp": own("volume"), "on.scroll": null } }
        });
        _leave();
        const music = _make("music", "Music 1");
        const step = (item, name) => {
            _resetEffects();
            _drive(item, name);
            return JSON.stringify(_effects);
        };
        assertEqual(step(music, "middleClick"), JSON.stringify(["music.next"]), "a preset's binding: the middle click skips");
        assertEqual(step(music, "leftClick"), JSON.stringify([]), "a preset's nothing on the left click: the popup does not open");
        assertEqual(step(music, "tap"), JSON.stringify([]), "… nor on a tap, whose fallback it is");
        assertEqual(step(music, "scrollDown"), JSON.stringify(["music.previous"]), "a key it does not set: the default");
        assertEqual(step(music, "rightClick") + step(music, "rightClick") + step(music, "rightClick"),
                    JSON.stringify(["music.next"]) + JSON.stringify(["music.previous"]) + JSON.stringify(["music.next"]),
                    "alternate without state: in turn from the first");
        _music.playing = false;
        assertEqual(step(music, "scrollUp"), JSON.stringify(["music.play"]), "alternate with state: paused, it plays");
        assertEqual(step(music, "scrollUp"), JSON.stringify(["music.play"]), "… still paused: it plays again, the state decides");
        _music.playing = true;
        assertEqual(step(music, "scrollUp"), JSON.stringify(["music.pause"]), "… playing: it pauses");
        _music.playing = false;
        _leave();
        music.destroy();

        const stt = _make("stt", "Stt 1");
        _stt.server = "off";
        assertEqual(step(stt, "middleClick"), JSON.stringify(["stt.serverStart"]), "the server off: alternate starts it");
        assertEqual(step(stt, "rightClick"), JSON.stringify(["stt.serverStart"]), "… and start or stop starts it");
        _stt.server = "loading";
        assertEqual(step(stt, "middleClick"), JSON.stringify(["stt.serverStop"]), "loading: alternate stops it");
        assertEqual(step(stt, "rightClick"), JSON.stringify(["stt.serverStop"]), "… and start or stop stops it");
        _stt.server = "ready";
        assertEqual(step(stt, "middleClick"), JSON.stringify(["stt.serverStop"]), "running: stopped");
        _stt.server = "error";
        assertEqual(step(stt, "middleClick"), JSON.stringify(["stt.serverStart"]), "failed: started again");
        _stt.server = "off";
        _stt.dictation = "speaking";
        assertEqual(step(stt, "scrollUp"), JSON.stringify(["stt.stop"]), "dictating: alternate stops dictation");
        _stt.dictation = "idle";
        assertEqual(step(stt, "scrollUp"), JSON.stringify(["stt.start"]), "idle: it starts it");
        assertEqual(step(stt, "leftClick"), JSON.stringify(["stt.toggle"]), "the left click: the default, dictation on or off");
        _leave();
        stt.destroy();

        const sound = _make("sound", "Sound 1");
        assertEqual(step(sound, "scrollUp"), JSON.stringify(["sound.volume=0.51"]), "an adjust action on a step: one step's amount");
        assertEqual(step(sound, "scrollDown"), JSON.stringify([]), "the continuous scroll bound to nothing: a step down does nothing");
        _leave();
        sound.destroy();
    }

    // A left click the type declares wins over the popup's; hovering still opens it
    function _declaredLeftClick() {
        _recording = false;
        ownPopupCell.visible = true;
        const step = name => {
            _resetEffects();
            const before = suite._seen;
            suite._seen = [];
            const connection = (n, d) => suite._seen.push(n + (d.phase !== "" ? ":" + d.phase : ""));
            ownPopupCell.interaction.connect(connection);
            _drive(ownPopupCell, name);
            ownPopupCell.interaction.disconnect(connection);
            return JSON.stringify(_effects);
        };
        const mine = { leftClick: { mode: "single", action: { action: "own:mine" } } };
        _leave();
        ownPopupCell.bindingLookup = InteractionRules.lookupFor({}, mine, true, "click", ["mine"]);
        assertEqual(step("leftClick"), JSON.stringify(["own mine byTouch=false"]), "a declared left click: its own action, not the popup");
        assertEqual(step("tap"), JSON.stringify(["own mine byTouch=true"]), "… a tap does the same");
        _leave();
        ownPopupCell.bindingLookup = InteractionRules.lookupFor({}, mine, true, "hover", ["mine"]);
        assertEqual(step("hover"), JSON.stringify(["popup open persistent=false byTouch=false"]), "hover mode: hovering still opens the popup");
        assertEqual(step("leftClick"), JSON.stringify(["own mine byTouch=false"]), "… the left click its own action");
        _leave();
        ownPopupCell.bindingLookup = InteractionRules.lookupFor({}, {}, true, "click", []);
        assertEqual(step("leftClick"), JSON.stringify(["popup open persistent=true byTouch=false"]), "none declared: the click opens the popup");
        fakePopup.active = true;
        fakePopup.contentType = ownPopupCell.popupContent;
        fakePopup.openedBy = ownPopupCell;
        _effects = [];
        driver.mouseClick(ownPopupCell, ownPopupCell.width / 2, ownPopupCell.height / 2);
        assertEqual(JSON.stringify(_effects), JSON.stringify(["popup close"]), "… and a click while it shows from here closes it");
        _leave();
        _recording = false;
        ownPopupCell.visible = false;
    }

    function runAsync() {
        if (!driver.waitShown()) {
            fail("the window was never drawn");
            finish();
            return;
        }
        const savedProfiles = Config.profiles;
        const savedPresets = Config.widgetPresets;
        try {
            _existingConfig();
            _presetBindings();
            _declaredLeftClick();
        } finally {
            _recording = false;
            Config.profiles = savedProfiles;
            Config.widgetPresets = savedPresets;
            finish();
        }
    }
}
