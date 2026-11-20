import QtQuick
import QtQuick.Layouts
import QtTest as QT
import Quickshell
import Quickshell.Wayland
import qs.api as Public
import qs.components
import qs.singletons

// The public StatusPill and ProgressBar's wave (module API 1.35), and the notification
// card's wave. The wave: a band moving through the fill within two periods with `wave`, its
// period the theme's, none without, hidden, full, of unknown length or with reduced motion.
// The pill: its parts in order in their kinds' colours, a tooltip each, a click expands and
// a second folds, none without parts, unknown words logged once, its views on ScriptModels.
// The card: its bar waves while the job runs and its value grows, and stops when it stands.
//
// Opens a small window in a corner for a moment (a layer surface that takes no keyboard), in
// the runner's headless compositor.
TestCase {
    id: suite
    suiteName: "StatusPill"
    asynchronous: true

    property var toggles: []

    // A layer surface that never takes the keyboard: the side panel's suite needs it
    property var _window: PanelWindow {
        anchors { bottom: true; left: true }
        implicitWidth: 520
        implicitHeight: 420
        color: Theme.popupBackground
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Item { id: elsewhere; x: 480; y: 380; width: 30; height: 30 }

        ColumnLayout {
            id: bars
            x: 10; y: 10
            width: 200
            spacing: 6
            Public.ProgressBar { id: waveBar; value: 0.5; wave: true }
            Public.ProgressBar { id: stillBar; value: 0.5 }
        }

        Public.StatusPill {
            id: pill
            x: 10; y: 60
            icon: ""
            label: "Sending 1/6"
            parts: [
                { icon: "", text: "1", kind: "normal", tip: "1 sending" },
                { icon: "", text: "3", kind: "muted", tip: "3 queued" },
                { icon: "", text: "1", kind: "warning", tip: "1 stalled", line: "1 with no progress for 3 min" },
                { icon: "", text: "1", kind: "danger", tip: "1 failed" }
            ]
            onToggled: expanded => suite.toggles = suite.toggles.concat([expanded])
        }

        Public.StatusPill { id: emptyPill; x: 10; y: 220; label: "<b>No transfers</b>"; kind: "muted" }
        Public.StatusPill { id: mistyped; x: 200; y: 220; label: "Odd"; kind: "pinkish"; parts: [{ text: "1", kind: "blueish", tip: "one" }] }

        Item { id: cardArea; x: 10; y: 260; width: 360; height: 150 }

        QT.TestCase {
            id: driver
            name: "StatusPillDriver"
            when: false
        }
    }

    // A notification as the server hands it, as far as a card reads it; the same object
    // updated as the sender's job goes
    property Component _standIn: Component {
        QtObject {
            property int id: 7
            property string appName: "Test"
            property string appIcon: ""
            property string summary: "Sending"
            property string body: "photo.jpg"
            property string image: ""
            property var actions: []
            property bool hasInlineReply: false
            property var hints: ({})
            property bool resident: false
            property bool tracked: true
            signal closed(int reason)
            function dismiss() {}
        }
    }
    property Component _cardComp: Component { NotificationCard { width: 360 } }

    // Waits for `condition`, at most `limitMs`; whether it came true
    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    // The items under `item`, at any depth, that `test` takes, in order
    function _find(item, test) {
        let found = [];
        for (const child of Array.from(item.children ?? [])) {
            if (test(child))
                found.push(child);
            found = found.concat(_find(child, test));
        }
        return found;
    }

    function _texts(item) {
        return _find(item, child => /^QQuickText(_QML_\d+)?\(/.test(child.toString()));
    }

    // The internal tooltip of `target` in the window's top item, if one shows
    function _tipOver(target) {
        const top = target.Window.window?.contentItem;
        return top ? Array.from(top.children).find(child => child.toString().startsWith("HoverTip") && child.target === target) ?? null : null;
    }

    function runAsync() {
        try {
            _run();
        } finally {
            _window.visible = false;
        }
        finish();
    }

    function _run() {
        assert(_until(() => _window.visible && waveBar.width > 0 && pill.width > 0), "the window shows, laid out");
        _wave();
        _pill();
        _card();
    }

    // --- the bar's wave ---
    function _wave() {
        const inner = waveBar.children[0];
        const still = stillBar.children[0];
        // The user's profile may reduce motion; the bar is checked both ways
        inner.reduceMotion = false;
        still.reduceMotion = false;
        const band = _find(inner, child => child.objectName === "wave")[0];
        assert(band !== undefined, "the bar has its band");
        const animation = Array.from(inner.data).find(child => child.toString().startsWith("QQuickNumberAnimation") && child.property === "_wavePhase");
        const period = Theme.duration("progressWave");
        assert(animation !== undefined && animation.duration === period && animation.loops < 0,
               "its period is the theme's progressWave (" + animation?.duration + " of " + period + " ms), again and again (loops " + animation?.loops + ")");
        assert(inner.waving && band.parent.visible, "wave: true at half: the band shows");
        const fill = inner.children[1];
        assert(band.parent.parent === fill && band.parent.clip, "… clipped to the fill");
        const firstPlace = band.x;
        assert(_until(() => Math.abs(band.x - firstPlace) > 1, 2 * period), "… and moves within two periods");
        let wrapped = false;
        let last = band.x;
        _until(() => {
            wrapped = wrapped || band.x < last - 1;
            last = band.x;
            return wrapped;
        }, 2 * period + 100);
        assert(wrapped, "… crossing the fill and starting again");

        assert(!still.waving && !_find(still, child => child.objectName === "wave")[0].parent.visible, "without wave: no band");
        const stillPhase = still._wavePhase;
        driver.wait(period);
        assertEqual(still._wavePhase, stillPhase, "… nothing moves");

        waveBar.visible = false;
        assert(!inner.waving && !animation.running, "hidden: no wave, its animation stopped");
        waveBar.visible = true;
        assert(_until(() => inner.waving && animation.running), "shown again: the wave again");

        inner.reduceMotion = true;
        assert(!inner.waving && !band.parent.visible && !animation.running && inner._wavePhase === 0, "reduced motion: no band, nothing running");
        inner.reduceMotion = false;

        for (const [value, what] of [[1, "full"], [-1, "of unknown length"], [NaN, "not a number"]]) {
            waveBar.value = value;
            assert(!inner.waving && !band.parent.visible, "a bar " + what + ": no wave");
        }
        waveBar.value = 0.5;
        assert(inner.waving, "back at half: the wave");
        waveBar.wave = false;
        assert(!inner.waving && !animation.running, "wave set false by the owner (a stall): it stops");
    }

    // --- the status pill ---
    function _pill() {
        const inner = pill.children[0];
        const rules = ApiElementRules;
        const parts = _find(inner, child => child.objectName === "part");
        assertEqual(parts.length, 4, "four parts after the label");
        assertEqual(parts.map(part => _texts(part).map(text => text.text).join("")).join(" "), "1 3 1 1", "… in order, each its icon and its text");
        assert(parts.every((part, i) => i === 0 || part.x > parts[i - 1].x), "… left to right");
        const label = _find(inner, child => child.objectName === "label")[0];
        const icon = _find(inner, child => child.objectName === "icon")[0];
        assert(label.x > icon.x && parts[0].mapToItem(inner, 0, 0).x > label.mapToItem(inner, label.width, 0).x, "the icon, the label, then the parts");
        const kinds = ["normal", "muted", "warning", "danger"];
        for (let i = 0; i < parts.length; i++) {
            const colour = Theme[rules.statusKinds[kinds[i]].icon];
            assert(_texts(parts[i]).every(text => Qt.colorEqual(text.color, colour)), "a " + kinds[i] + " part in the theme's " + rules.statusKinds[kinds[i]].icon);
        }
        for (const kind in rules.statusKinds) {
            pill.kind = kind;
            assert(Qt.colorEqual(icon.color, Theme[rules.statusKinds[kind].icon]) && Qt.colorEqual(label.color, Theme[rules.statusKinds[kind].text]),
                   "a " + kind + " pill: its icon in " + rules.statusKinds[kind].icon + ", its label in " + rules.statusKinds[kind].text);
        }
        pill.kind = "normal";
        assert(Qt.colorEqual(inner.color, Theme.fill) && Qt.colorEqual(inner.border.color, Theme.outline), "the pill filled and outlined as the theme says");
        const repeaters = _find(inner, child => child.toString().startsWith("QQuickRepeater"));
        assert(repeaters.length === 2 && repeaters.every(repeater => repeater.model !== null && typeof repeater.model === "object" && "objectProp" in repeater.model),
               "its two views on ScriptModels, never a live array");

        // --- tooltips ---
        driver.mouseMove(elsewhere, 5, 5);
        for (let i = 0; i < parts.length; i++) {
            driver.mouseMove(parts[i], parts[i].width / 2, parts[i].height / 2);
            const tip = _tipOver(parts[i]);
            assert(tip !== null && _until(() => tip.visible), "the pointer over part " + i + ": its tooltip");
            assertEqual(_texts(tip)[0]?.text, pill.parts[i].tip, "… saying " + pill.parts[i].tip);
            assert(parts.every((other, j) => j === i || !(_tipOver(other)?.visible ?? false)), "… only its own");
        }
        driver.mouseMove(elsewhere, 5, 5);
        assert(_until(() => parts.every(part => !(_tipOver(part)?.visible ?? false))), "the pointer gone: no tooltip");

        // --- expanding ---
        const folded = pill.height;
        const lines = _find(inner, child => child.objectName === "lines")[0];
        assert(!pill.expanded && !lines.visible, "folded at first");
        driver.mouseClick(pill, pill.width / 2, folded / 2);
        assert(pill.expanded && lines.visible, "a click expands it");
        assertEqual(JSON.stringify(toggles), "[true]", "… toggled(true)");
        const rows = _find(lines, child => child.objectName === "line");
        assertEqual(rows.map(row => _texts(row)[1].text).join("|"), "1 sending|3 queued|1 with no progress for 3 min|1 failed", "one part per line: its line, or its tip");
        assert(rows.every((row, i) => i === 0 || row.y > rows[i - 1].y), "… one under another");
        assert(rows.every((row, i) => Qt.colorEqual(_texts(row)[1].color, Theme[rules.statusKinds[kinds[i]].text])
                                      && Qt.colorEqual(_texts(row)[0].color, Theme[rules.statusKinds[kinds[i]].icon])), "… each in its kind's colours");
        assert(_find(inner, child => child.objectName === "rule")[0].visible, "… under a rule");
        assert(_until(() => pill.height > folded + rows.length * 5), "… the pill grown down (" + folded + " → " + pill.height + ")");
        driver.mouseClick(pill, pill.width / 2, folded / 2);
        assert(!pill.expanded && !lines.visible && _until(() => pill.height === folded), "a second click folds it");
        assertEqual(JSON.stringify(toggles), "[true,false]", "… toggled(false)");
        pill.expanded = true;
        assert(lines.visible, "the owner may expand it");
        pill.expanded = false;

        // --- without parts ---
        driver.mouseClick(emptyPill, emptyPill.width / 2, emptyPill.height / 2);
        assert(!emptyPill.expanded && toggles.length === 2, "no parts: a click does nothing");
        const emptyLabel = _find(emptyPill.children[0], child => child.objectName === "label")[0];
        assert(emptyLabel.textFormat === Text.PlainText && emptyLabel.text === "<b>No transfers</b>", "its label as written");
        assert(Qt.colorEqual(emptyLabel.color, Theme.textMuted), "… muted");

        // --- words it does not know, too many parts ---
        assertEqual(mistyped.children[0].kind, "normal", "a kind it does not know: normal");
        assertEqual(ApiElements.warned.filter(key => key === "StatusPill.kind=pinkish").length, 1, "… logged once");
        assertEqual(ApiElements.warned.filter(key => key === "StatusPill.parts.kind=blueish").length, 1, "a part's unknown kind logged once");
        mistyped.parts = Array.from({ length: 14 }, (_, i) => ({ text: String(i), tip: "part " + i }));
        assert(_until(() => _find(mistyped.children[0], child => child.objectName === "part").length === rules.statusPartCap), "past " + rules.statusPartCap + " parts the rest dropped");
        mistyped.parts = Array.from({ length: 15 }, (_, i) => ({ text: String(i) }));
        assertEqual(ApiElements.warned.filter(key => key === "StatusPill.parts>" + rules.statusPartCap).length, 1, "… logged once");
    }

    // --- the notification card's wave ---
    function _card() {
        const notification = _standIn.createObject(suite, { hints: { value: 40 } });
        const card = _cardComp.createObject(cardArea, { notification: notification, progressWaveMs: 500 });
        const bar = _find(card, child => child.objectName === "progress")[0];
        assert(bar !== undefined && bar.visible, "the card shows its bar");
        bar.reduceMotion = false;
        assert(!card.progressWave && !bar.wave, "a value seen once: not moving yet, no wave");
        notification.hints = { value: 50, "x-qs-progress-state": "running" };
        assert(card.progressWave && bar.wave && bar.waving, "the value grew while running: the bar waves");
        assert(_until(() => !bar.wave, 2000), "the value standing still past the window: the wave stops");
        notification.hints = { value: 50 };
        assert(!bar.wave, "the same value again: none");
        notification.hints = { value: 60 };
        assert(bar.wave, "grown again: the wave again");
        notification.hints = { value: 60, "x-qs-progress-state": "done" };
        assert(!bar.wave, "done: no wave");
        const next = _standIn.createObject(suite, { hints: { value: 30 } });
        card.notification = next;
        next.hints = { value: 20 };
        assert(!bar.wave, "another notification in the card, its value going down: no wave");
        card.destroy();
        notification.destroy();
        next.destroy();
    }
}
