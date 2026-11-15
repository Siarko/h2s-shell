import QtQuick
import QtTest as QT
import Quickshell
import Quickshell.Wayland
import qs.screensaver
import qs.singletons
import qs.singletons.lock

// The lock screen's views as components, fed a view the way Lockscreen feeds them
// (LockRules.view's shape): what the prompt shows for each state — the answer hidden or
// shown, the question in full when the field's placeholder cannot hold it, the error, the
// notice, "Unlocking…", the passive methods' lines, Caps Lock — and what a notification
// card shows at each detail, every line plain text. The states that the lock test bed
// cannot reach (a compositor that confirms late; a PAM question longer than any test
// stack asks) are covered here; the rest is covered there too, end to end.
//
// Opens a small window in a corner for a moment (run it through tests/run-unit.sh).
TestCase {
    id: root
    suiteName: "LockView"
    asynchronous: true

    readonly property var _baseView: ({
        locked: true, unlocking: false, promptSurface: 1, promptScreen: "A", busy: false,
        buttonText: "Unlock", placeholder: "Password", answerVisible: false, error: "", notice: "",
        refusal: "", fieldEpoch: 0, methods: []
    })

    function _view(changes) {
        return Object.assign({}, _baseView, changes);
    }

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 760
        implicitHeight: 560
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        LockPrompt {
            id: prompt
            x: 10
            y: 10
            width: implicitWidth
            awake: true
            view: root._baseView
            property var submittedTexts: []
            onSubmitted: text => submittedTexts.push(text)
        }

        // A narrow one: a small output, a large scale (LockSurface clamps the width)
        LockPrompt {
            id: narrowPrompt
            x: 350
            y: 10
            width: 180
            awake: true
            view: root._baseView
        }

        NotificationPreview {
            id: card
            x: 350
            y: 380
            detail: "app"
            modelData: QtObject {
                property string appName: "Messages"
                property string summary: "<b>Alice</b> <a href=\"https://example.com\">link</a><img src=\"https://example.com/x.png\">"
                property string body: "Your code is 123456"
            }
        }

        IdleWatch {
            id: idleWatch
            enabled: false
            timeout: 300
        }

        QT.TestCase {
            id: driver
            name: "LockViewDriver"
            when: false
        }
    }

    // The first item under `item` with this objectName (depth first), or null
    function _find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        const children = item.children ?? [];
        for (let i = 0; i < children.length; i++) {
            const found = _find(children[i], name);
            if (found)
                return found;
        }
        return null;
    }

    // Every visible Text under `item`, as its text
    function _visibleTexts(item, into) {
        const list = into ?? [];
        if (!item || item.visible === false)
            return list;
        if (item instanceof Text)
            list.push(item.text);
        const children = item.children ?? [];
        for (let i = 0; i < children.length; i++)
            _visibleTexts(children[i], list);
        return list;
    }

    function runAsync() {
        driver.wait(300); // the window shown
        const field = _find(prompt, "field");
        const error = _find(prompt, "error");
        const notice = _find(prompt, "notice");
        const question = _find(prompt, "question");
        const button = _find(prompt, "button");
        const caps = _find(prompt, "capsLock");
        assert(field && error && notice && question && button && caps, "the prompt's parts are found");

        // --- the password: hidden, forwarded keys edit it, Enter submits ---
        assertEqual(field.echoMode, TextInput.Password, "a password is never shown");
        prompt.applyKey("", "pa");
        prompt.applyKey("", "sé");
        prompt.applyKey("Backspace", "");
        prompt.applyKey("", "s");
        assertEqual(field.text, "pass", "forwarded characters and Backspace edit the field (é composed, then deleted)");
        assert(field.displayText !== "pass" && field.displayText.length === 4, "and it shows as masks");
        assert(!_visibleTexts(prompt).some(text => text.indexOf("pass") >= 0), "the typed text is in no visible label");
        prompt.applyKey("Enter", "");
        assertEqual(JSON.stringify(prompt.submittedTexts), JSON.stringify(["pass"]), "Enter submits what is in the field");
        assertEqual(field.text, "pass", "and does not empty it by itself");
        prompt.view = _view({ fieldEpoch: 1 });
        assertEqual(field.text, "", "a new fieldEpoch empties it");

        // --- a question whose answer may show ---
        prompt.view = _view({ fieldEpoch: 1, placeholder: "Token:", answerVisible: true });
        prompt.applyKey("", "lt-7");
        assertEqual(field.echoMode, TextInput.Normal, "an answer allowed to show is in plain sight");
        assertEqual(field.displayText, "lt-7", "as typed");
        prompt.view = _view({ fieldEpoch: 1, placeholder: "STRESS Password:", answerVisible: false });
        assertEqual(field.echoMode, TextInput.Password, "a hidden one is masked");
        assert(field.displayText !== "lt-7", "never shown");
        prompt.view = _view({ fieldEpoch: 2 });
        driver.wait(50);
        assert(!question.visible, "a short placeholder needs no question line");

        // --- a question too long for the placeholder: shown in full above the field ---
        const longQuestion = "Please enter the one-time code that was just sent to the phone number ending in 4242:";
        prompt.view = _view({ fieldEpoch: 2, placeholder: longQuestion });
        driver.wait(50);
        assert(question.visible, "a long question is shown in full");
        assertEqual(question.text, longQuestion, "all of it");
        assert(question.lineCount > 1, "wrapped, not cut");
        assert(question.width <= prompt.width, "inside the card");

        // --- errors, notices, busy ---
        prompt.view = _view({ fieldEpoch: 3, error: "Authentication failed" });
        driver.wait(50);
        assert(error.visible && error.text === "Authentication failed", "the error is shown");
        const longError = "Password check is not available: the PAM configuration named by the methods script could not be started, and there is no fallback";
        narrowPrompt.view = _view({ error: longError, notice: "Waiting for the compositor to confirm the lock" });
        driver.wait(50);
        const narrowError = _find(narrowPrompt, "error");
        assert(narrowError.lineCount > 2 && narrowError.width <= narrowPrompt.width, "a long error wraps inside a narrow card");
        assert(narrowPrompt.implicitHeight > prompt.implicitHeight, "and the card grows to hold it");
        assert(_find(narrowPrompt, "notice").visible, "the compositor's late confirmation is said");
        prompt.view = _view({ fieldEpoch: 3 });
        driver.wait(50);
        assert(!error.visible && !notice.visible, "no error, no notice: neither line");
        prompt.view = _view({ fieldEpoch: 3, busy: true, buttonText: "Verifying…" });
        assertEqual(button.text, "Verifying…", "busy: Verifying…");
        prompt.view = _view({ fieldEpoch: 3, busy: true, unlocking: true, buttonText: "Unlocking…" });
        assertEqual(button.text, "Unlocking…", "an unlock waiting for the compositor: Unlocking…");

        // --- the passive methods' lines (a fresh array every view, through a ScriptModel) ---
        prompt.view = _view({ fieldEpoch: 3, methods: [
            { name: "fingerprint", visible: true, waiting: true, text: "Touch the fingerprint reader", isError: false },
            { name: "u2f", visible: false, waiting: false, text: "", isError: false }] });
        driver.wait(50);
        assert(_visibleTexts(prompt).includes("Touch the fingerprint reader"), "a waiting method's line shows");
        prompt.view = _view({ fieldEpoch: 3, methods: [
            { name: "fingerprint", visible: true, waiting: false, text: "Fingerprint not available, trying again later", isError: true },
            { name: "u2f", visible: false, waiting: false, text: "", isError: false }] });
        driver.wait(50);
        const texts = _visibleTexts(prompt);
        assert(texts.includes("Fingerprint not available, trying again later") && !texts.includes("Touch the fingerprint reader"),
            "and is replaced by its next state");

        // --- Caps Lock ---
        assert(!caps.visible, "Caps Lock not known on: nothing said");
        prompt.capsLock = true;
        assert(caps.visible && caps.text === "Caps Lock is on", "Caps Lock on is said");
        prompt.capsLock = false;

        // --- a notification card at each detail ---
        const cardApp = _find(card, "app");
        const cardTitle = _find(card, "title");
        const cardBody = _find(card, "body");
        assert(cardApp.visible && cardApp.text === "Messages", "app only: the app's name");
        assert(!cardTitle.visible && cardTitle.text === "", "no title, not even laid out");
        assert(!cardBody.visible && cardBody.text === "", "no body, not even laid out");
        assert(!_visibleTexts(card).some(text => text.indexOf("123456") >= 0), "the code is not on the screen");
        card.detail = "title";
        assert(cardTitle.visible && !cardBody.visible, "title: the title, no body");
        card.detail = "full";
        assert(cardBody.visible && cardBody.text === "Your code is 123456", "full: the body too");
        assertEqual(cardTitle.textFormat, Text.PlainText, "the title is plain text: no link, no image fetched");
        assert(cardTitle.text.indexOf("<img") >= 0, "markup in it is kept as written, never interpreted");
        assertEqual(cardBody.textFormat, Text.PlainText, "so is the body");
        card.detail = "something else";
        assert(!cardTitle.visible && !cardBody.visible, "an unknown detail shows the least");

        // --- IdleWatch: a new IdleMonitor for every change (Quickshell's own re-creation
        // can leave isIdle false for good) ---
        assertEqual(idleWatch.monitor, null, "IdleWatch disabled: no monitor");
        idleWatch.enabled = true;
        driver.wait(50);
        const first = idleWatch.monitor;
        assert(first !== null && first.timeout === 300 && first.enabled, "enabled: a monitor with the timeout");
        idleWatch.timeout = 5;
        driver.wait(50);
        assert(idleWatch.monitor !== null && idleWatch.monitor !== first, "a new timeout: a new monitor, not the old one changed");
        assertEqual(idleWatch.monitor.timeout, 5, "with the new timeout");
        const second = idleWatch.monitor;
        idleWatch.timeout = 7;
        idleWatch.timeout = 5;
        driver.wait(50);
        assertEqual(idleWatch.monitor, second, "changed and changed back in one pass: kept");
        assert(!idleWatch.isIdle, "not idle meanwhile");
        idleWatch.enabled = false;
        driver.wait(50);
        assertEqual(idleWatch.monitor, null, "disabled again: none");

        finish();
    }
}
