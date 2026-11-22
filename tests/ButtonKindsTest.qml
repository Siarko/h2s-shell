import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.singletons

// The shell's buttons as they are drawn (SmallButton, DeleteButton): each kind's fill,
// label and border at rest, under the pointer, asking and not available; the question's
// two parts under one border; a label shown as written; a narrow button's label elided.
// The rule alone (which colour for which kind and state): ThemeTest, ThemeRules.buttonLook.
// What is expected here is written out, not asked of that rule.
//
// Opens a small window in a corner of the screen for a moment (a layer surface, so it
// moves no windows).
TestCase {
    id: root
    suiteName: "ButtonKinds"
    asynchronous: true

    // Per kind: the colours' names in Theme. `border` "" is no border.
    readonly property var kinds: [
        { kind: "normal", fill: "surface", label: "textSecondary", border: "", hotFill: "surfaceHover", hotLabel: "textSecondary", asking: "textPrimary", askingBorder: "outline" },
        { kind: "save", fill: "confirm", label: "textPrimary", border: "", hotFill: "confirmHover", hotLabel: "textPrimary", asking: "confirm", askingBorder: "confirm" },
        { kind: "delete", fill: "surface", label: "textSecondary", border: "error", hotFill: "error", hotLabel: "textPrimary", asking: "error", askingBorder: "error" },
        { kind: "warning", fill: "surface", label: "textSecondary", border: "warning", hotFill: "warning", hotLabel: "textPrimary", asking: "warning", askingBorder: "warning" },
        { kind: "success", fill: "surface", label: "textSecondary", border: "success", hotFill: "success", hotLabel: "textPrimary", asking: "success", askingBorder: "success" },
        { kind: "action", fill: "accent", label: "onAccent", border: "", hotFill: "accentHover", hotLabel: "onAccent", asking: "accent", askingBorder: "accent" }
    ]

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 1000
        implicitHeight: 200
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Somewhere for the mouse to go that is no button
        Item {
            id: away
            x: 940; y: 150
            width: 40; height: 40
        }

        Row {
            id: plainButtons
            x: 10; y: 10
            spacing: 30

            Repeater {
                model: root.kinds.length
                SmallButton {
                    required property int index
                    property int clicks: 0
                    kind: root.kinds[index].kind
                    label: "Kind " + kind
                    onClicked: clicks++
                }
            }
        }

        Row {
            id: askingButtons
            x: 10; y: 60
            spacing: 60

            Repeater {
                model: root.kinds.length
                DeleteButton {
                    required property int index
                    property int confirmations: 0
                    property int questions: 0
                    kind: root.kinds[index].kind
                    label: "Ask " + kind
                    confirmLabel: "Really " + kind + "?"
                    onConfirmed: confirmations++
                    onAskingStarted: questions++
                }
            }
        }

        Row {
            x: 10; y: 110
            spacing: 30

            SmallButton {
                id: unavailable
                property int clicks: 0
                kind: "delete"
                label: "Not now"
                available: false
                onClicked: clicks++
            }
            DeleteButton {
                id: unavailableAsking
                property int questions: 0
                label: "Not now either"
                available: false
                onAskingStarted: questions++
            }
            SmallButton {
                id: narrow
                kind: "warning"
                label: "A label much longer than its button"
                width: 80
            }
            SmallButton {
                id: marked
                label: "<b>x</b>"
            }
            DeleteButton {
                id: markedAsking
                label: "<i>y</i>"
                confirmLabel: "<b>z</b>?"
            }
        }

        WindowDriver {
            id: driver
            name: "ButtonKindsDriver"
        }
    }

    // Waits for `condition`, at most `limitMs`; whether it came true
    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    // By the channels: Qt.colorEqual tells the theme's `onAccent` and a label drawn in it
    // apart, though their channels are the same
    function _is(colour, name) {
        const wanted = Theme[name];
        return ["r", "g", "b", "a"].every(channel => Math.abs(colour[channel] - wanted[channel]) < 0.5 / 255);
    }

    function _child(item, typeName, nth = 0) {
        return Array.from(item.children).filter(child => child.toString().startsWith(typeName))[nth] ?? null;
    }

    // The parts of a DeleteButton: the button, its label, the border, the "×"
    function _parts(button) {
        const face = button.children[0];
        return { face: face, label: _child(face, "QQuickText"), outline: _child(face, "QQuickRectangle"),
            area: _child(face, "PointerArea"), cancel: button.children[1] };
    }

    // A row's buttons, without the Repeater that makes them
    function _buttons(row) {
        return Array.from(row.children).filter(child => !child.toString().startsWith("QQuickRepeater"));
    }

    // Whether a label is shown as written: plain text, and wider than it would be as markup
    function _asWritten(label) {
        if (label.textFormat !== Text.PlainText)
            return false;
        const writtenWidth = label.implicitWidth;
        label.textFormat = Text.StyledText;
        const narrowerAsMarkup = label.implicitWidth < writtenWidth;
        label.textFormat = Text.PlainText;
        return narrowerAsMarkup;
    }

    function _leave(lit) {
        driver.mouseMove(away, 5, 5);
        return _until(() => !lit());
    }

    function runAsync() {
        // The window takes input once it is shown: the pointer over the first button is seen
        const first = _buttons(plainButtons)[0];
        assert(_until(() => {
            driver.mouseMove(away, 5, 5);
            driver.mouseMove(first, 5, 5);
            return first.hovered;
        }, 5000), "the window is shown and the pointer is seen over a button");
        _leave(() => first.hovered);

        // --- SmallButton: each kind at rest and under the pointer ---
        for (let i = 0; i < kinds.length; i++) {
            const expected = kinds[i];
            const button = _buttons(plainButtons)[i];
            const label = _child(button, "QQuickText");
            const name = "\"" + expected.kind + "\"";
            assert(_until(() => _is(button.color, expected.fill)), name + " at rest: filled with " + expected.fill);
            assert(_is(label.color, expected.label), name + " at rest: its label in " + expected.label);
            if (expected.border === "") {
                assertEqual(button.border.width, 0, name + " at rest: no border");
            } else {
                assertEqual(button.border.width, Theme.border.width, name + " at rest: a border as wide as the theme's outlines");
                assert(_is(button.border.color, expected.border), name + " at rest: the border in " + expected.border);
            }
            assertEqual(button.opacity, 1, name + " at rest: fully shown");

            driver.mouseMove(button, 5, 5);
            assert(_until(() => _is(button.color, expected.hotFill)), name + " under the pointer: filled with " + expected.hotFill);
            assert(_is(label.color, expected.hotLabel), name + " under the pointer: its label in " + expected.hotLabel);
            assertEqual(button.border.width, expected.border === "" ? 0 : Theme.border.width, name + " under the pointer: the border as at rest");
            driver.mouseClick(button, 5, 5);
            assertEqual(button.clicks, 1, name + ": one click acts");
            assert(_leave(() => button.hovered) && _until(() => _is(button.color, expected.fill)),
                name + ": the pointer gone, as at rest again");
        }

        // --- DeleteButton: each kind at rest, under the pointer, asking ---
        for (let i = 0; i < kinds.length; i++) {
            const expected = kinds[i];
            const button = _buttons(askingButtons)[i];
            const parts = _parts(button);
            const name = "asking \"" + expected.kind + "\"";
            assert(_until(() => _is(parts.face.color, expected.fill)), name + " at rest: filled with " + expected.fill + ", as the kind");
            assert(_is(parts.label.color, expected.label), name + " at rest: its label in " + expected.label);
            assertEqual(parts.outline.visible, expected.border !== "", name + " at rest: " + (expected.border === "" ? "no border" : "a border"));
            if (expected.border !== "") {
                assert(_is(parts.outline.border.color, expected.border), name + " at rest: the border in " + expected.border);
                assertEqual(parts.outline.border.width, Theme.border.width, name + " at rest: as wide as the theme's outlines");
                assertEqual(parts.outline.width, parts.face.width, name + " at rest: around the button");
            }
            assert(!parts.cancel.visible, name + " at rest: no \"×\"");

            driver.mouseMove(parts.face, 5, 5);
            assert(_until(() => _is(parts.face.color, expected.hotFill)), name + " under the pointer: filled with " + expected.hotFill);
            assert(_is(parts.label.color, expected.hotLabel), name + " under the pointer: its label in " + expected.hotLabel);

            driver.mouseClick(parts.face, 5, 5);
            assert(button.asking && button.questions === 1 && button.confirmations === 0, name + ": the first click asks, nothing done");
            assertEqual(parts.label.text, "Really " + expected.kind + "?", name + ": the question is shown");
            assert(_is(parts.label.color, expected.asking), name + ": the question in " + expected.asking);
            assert(parts.outline.visible && _is(parts.outline.border.color, expected.askingBorder), name + ": a border in " + expected.askingBorder);
            assert(parts.cancel.visible, name + ": the \"×\" is attached");
            assertEqual(parts.outline.width, parts.face.width + parts.cancel.width, name + ": the border goes around the question and the \"×\"");
            assert(_until(() => _is(parts.face.color, "surfaceHover")), name + ": plain, under the pointer");
            assert(_leave(() => parts.area.lit) && _until(() => _is(parts.face.color, "surface")), name + ": plain, the pointer gone");

            driver.mouseClick(parts.cancel, 3, 3);
            assert(!button.asking && button.confirmations === 0, name + ": the \"×\" takes the question back");
            assertEqual(parts.label.text, "Ask " + expected.kind, name + ": the label is back");
            driver.mouseClick(parts.face, 5, 5);
            driver.mouseClick(parts.face, 5, 5);
            assert(!button.asking && button.confirmations === 1, name + ": a second click acts");
            // A move over the button first: after the two clicks the pointer's move away alone
            // is not seen as leaving it, and the wait ran out each time
            driver.mouseMove(parts.face, 6, 6);
            assert(_leave(() => parts.area.lit), name + ": the pointer gone");
        }

        // --- not available ---
        const unavailableLabel = _child(unavailable, "QQuickText");
        assertEqual(unavailable.opacity, 0.35, "not available: the whole button dimmed, its border with it");
        assertEqual(unavailable.border.width, Theme.border.width, "not available: the border stays");
        driver.mouseMove(unavailable, 5, 5);
        assert(_until(() => unavailable.hovered), "not available: the pointer is over it");
        assert(_is(unavailable.color, "surface") && _is(unavailableLabel.color, "textSecondary"), "not available: no fill under the pointer");
        driver.mouseClick(unavailable, 5, 5);
        assertEqual(unavailable.clicks, 0, "not available: a click does nothing");
        _leave(() => unavailable.hovered);

        const unavailableParts = _parts(unavailableAsking);
        assertEqual(unavailableParts.face.opacity, 0.35, "not available, one that asks: dimmed, its border with it");
        driver.mouseMove(unavailableParts.face, 5, 5);
        assert(_until(() => unavailableParts.area.containsMouse), "not available, one that asks: the pointer is over it");
        assert(_is(unavailableParts.face.color, "surface"), "not available, one that asks: no fill under the pointer");
        driver.mouseClick(unavailableParts.face, 5, 5);
        assert(!unavailableAsking.asking && unavailableAsking.questions === 0, "not available, one that asks: a click does not ask");
        _leave(() => unavailableParts.area.lit);

        // --- a narrow button; text as written ---
        const narrowLabel = _child(narrow, "QQuickText");
        assertEqual(narrow.width, 80, "a button made narrower than its label keeps that width");
        assert(narrowLabel.truncated && narrowLabel.width <= 80 - 2 * Theme.button.horizontalPadding, "and its label is cut short inside it");
        const wideLabel = _child(first, "QQuickText");
        assert(!wideLabel.truncated && wideLabel.width === wideLabel.implicitWidth, "a button of its own width shows its whole label");

        assert(_asWritten(_child(marked, "QQuickText")), "a button's label with markup in it is shown as written");
        const markedParts = _parts(markedAsking);
        assert(_asWritten(markedParts.label), "a button that asks shows its label as written");
        driver.mouseClick(markedParts.face, 5, 5);
        assert(markedAsking.asking && markedParts.label.text === "<b>z</b>?" && _asWritten(markedParts.label), "and its question too");
        markedAsking.asking = false;
        _leave(() => markedParts.area.lit);

        _window.visible = false;
        finish();
    }
}
