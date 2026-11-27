import QtQuick
import Quickshell
import qs.components
import qs.singletons

// A module's question (module API 1.44: module.ask → ModalQuestions.ask): the rules behind
// it (modalQuestion, modalItems, modalLongLabels, modalAskRefusal, modalAnswer, modalRefused),
// and the asking through a stand-in module handle — the place found from the asking item,
// the places that refuse (no place above it, a host that takes none, the module off), one
// question in the whole shell, the user's answer, a lock, a page change, the module turned
// off, its own cancel(), the host going while open, and the long label logged once.
//
// Opens a small window for a moment in the runner's headless compositor.
TestCase {
    id: suite
    suiteName: "ModalQuestions"
    asynchronous: true
    // ModalQuestions' one open question, and its window takes the keyboard
    ownProcess: true

    property var answers: []

    // A module's handle as ModalQuestions reads it
    property QtObject standIn: QtObject {
        property string moduleId: "fake"
        property bool active: true
    }

    property var _window: FloatingWindow {
        title: "h2s-tests modal questions"
        visible: false
        implicitWidth: 640
        implicitHeight: 420
        color: Theme.popupBackground

        Item {
            id: area
            anchors.fill: parent
            Item {
                id: asker
                width: 10
                height: 10
            }
            SettingsModalHost {
                id: host
                anchors.fill: parent
                placeRoot: area
            }
        }
        // Another place, which takes no question
        Item {
            id: refusing
            Item { id: refusedAsker }
            SettingsModalHost {
                placeRoot: refusing
                placeRefusal: "takes none"
            }
        }
        // Another host, the shell's own: one question in the whole shell
        SettingsModalHost {
            id: otherHost
            anchors.fill: parent
        }
        Item { id: nowhere }

        WindowDriver {
            id: driver
            name: "ModalQuestionsDriver"
        }
    }

    // A place that goes while its question is open
    property Component _goingPlace: Component {
        Item {
            id: going
            property alias asker: _goingAsker
            Item { id: _goingAsker }
            SettingsModalHost { placeRoot: going }
        }
    }

    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    function _find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (const child of item.children) {
            const found = _find(child, name);
            if (found)
                return found;
        }
        return null;
    }

    function _all(item, name, found = []) {
        if (!item)
            return found;
        if (item.objectName === name)
            found.push(item);
        for (const child of item.children)
            _all(child, name, found);
        return found;
    }

    function _remember(answer) {
        suite.answers = suite.answers.concat([answer]);
    }

    function _last() {
        return answers[answers.length - 1] ?? null;
    }

    function _shape(answer) {
        return answer ? [answer.button, answer.cancelled, answer.blocked].join(" ") : "none";
    }

    readonly property var _question: ({
        kind: "danger", title: "Stop all Serve shares?", body: ["These stop at once:"],
        items: ["https://laptop.example.ts.net → localhost:3000", "Funnel :8443"],
        checks: [{ key: "funnel", label: "Also Funnel" }],
        buttons: [{ id: "stopAll", label: "Stop all", kind: "delete" }], cancelLabel: "Cancel",
        subject: { shares: ["a", "b"] }
    })

    function runAsync() {
        try {
            _rules();
            _run();
        } finally {
            if (host.open)
                host.cancel("window");
            if (otherHost.open)
                otherHost.cancel("window");
            Profiles.screenLocked = false;
            _window.visible = false;
        }
        finish();
    }

    function _rules() {
        const rules = ApiElementRules;
        const spec = rules.modalQuestion({ kind: "warning", title: "Two\nlines", body: ["One", { text: "Two", strong: true }],
            items: ["a", "", "b\nc", 3, null], content: _goingPlace, size: "xl", subject: { ids: [1, 2] }, cancelLabel: "Keep",
            buttons: [{ id: "go", label: "Go", kind: "save", privileged: true, extra: () => 1 }, null] });
        assertEqual(JSON.stringify(spec), JSON.stringify({ kind: "warning", title: "Two lines", body: [{ text: "One", strong: false }, { text: "Two", strong: true }],
            items: ["a", "b c", "3"], checks: [], buttons: [{ id: "go", label: "Go", kind: "save", privileged: true, cancel: false }],
            cancelLabel: "Keep", size: "s", subject: { ids: [1, 2] } }),
            "modalQuestion: plain copies of what the modal draws, no content, an unknown size the question's default (s)");
        assertEqual(rules.modalQuestion({ size: "m" }).size, "m", "… a size it has kept");
        const subject = { ids: [1] };
        const copied = rules.modalQuestion({ subject: subject });
        subject.ids.push(2);
        assertEqual(JSON.stringify(copied.subject), "{\"ids\":[1]}", "… the subject a copy: the module's later change does not reach it");
        assertEqual(JSON.stringify(rules.modalQuestion("Ask")), JSON.stringify(rules.modalQuestion({})), "… not an object: an empty question");
        assertEqual(rules.modalItems(Array(80).fill("x")).length, rules.modalItemsCap, "modalItems: at most the cap");
        assertEqual(rules.modalItems("one").length, 0, "… not a list: none");

        assertEqual(JSON.stringify(rules.modalLongLabels({ buttons: [{ label: "Save all four files" }, { label: "Save all five files now" }],
                                                         cancelLabel: "Do not save these files" })),
                    JSON.stringify(["Save all five files now", "Do not save these files"]),
                    "modalLongLabels: more than four words, the cancel's too");

        assertEqual(["module", "locked", "place", "place", "busy", ""].join(" "),
            [rules.modalAskRefusal(false, true, false, false, true), rules.modalAskRefusal(true, true, false, false, true),
             rules.modalAskRefusal(true, false, false, false, true), rules.modalAskRefusal(true, false, true, true, true),
             rules.modalAskRefusal(true, false, true, false, true), rules.modalAskRefusal(true, false, true, false, false)].join(" "),
            "modalAskRefusal: the module off, then the lock, then the place, then busy");

        const answer = (reason, active, button, cancelled) => _shape(rules.modalAnswer({ button: button ?? "cancel", cancelled: cancelled ?? true, reason: reason, values: {} }, active ?? true));
        assertEqual(answer("button", true, "stopAll", false), "stopAll false ", "modalAnswer: a button, as clicked");
        assertEqual([answer("close"), answer("escape"), answer("asker")].join("|"), "cancel true |cancel true |cancel true ",
                    "… ×, Escape and the module's own cancel(): cancelled");
        assertEqual([answer("lock"), answer("window"), answer("page"), answer("subject"), answer("module"), answer("window", false)].join("|"),
                    "cancel false locked|cancel false closed|cancel false closed|cancel false closed|cancel false module|cancel false module",
                    "… the lock: locked; the window, page or subject gone: closed; the module off: module, also when its view went first");
        const full = rules.modalAnswer({ button: "go", cancelled: false, reason: "button", values: { a: true, b: "x", c: false }, subject: { id: 1 } }, true);
        assertEqual(JSON.stringify(full.values) + " " + JSON.stringify(full.subject), "{\"a\":true,\"c\":false} {\"id\":1}", "… the checkboxes' states only, and the subject");
        assert(Object.isFrozen(full) && Object.isFrozen(full.values), "… frozen");
        const refused = rules.modalRefused("busy", { id: 2 });
        assertEqual(_shape(refused) + " " + refused.subject.id, "cancel false busy 2", "modalRefused: blocked, with the subject");
    }

    function _run() {
        _window.visible = true;
        assert(_until(() => _window.visible && area.width > 0), "the window shows");

        // --- refused places, answered after the call ---
        answers = [];
        const nowhereCall = ModalQuestions.ask(standIn, nowhere, _question, _remember);
        assertEqual(answers.length + " " + nowhereCall.open, "0 false", "an item in no place: not open, not answered inside the call");
        assert(_until(() => answers.length === 1), "… answered after it");
        assertEqual(_shape(_last()) + " " + _last().subject.shares.length, "cancel false place 2", "… blocked \"place\", with its subject");
        ModalQuestions.ask(standIn, refusedAsker, _question, _remember);
        assert(_until(() => answers.length === 2), "a place that takes no question: answered");
        assertEqual(_last().blocked, "place", "… blocked \"place\"");
        ModalQuestions.ask(standIn, null, _question, _remember);
        assert(_until(() => answers.length === 3) && _last().blocked === "place", "no item: blocked \"place\"");
        standIn.active = false;
        const offCall = ModalQuestions.ask(standIn, asker, _question, _remember);
        driver.wait(30);
        assertEqual(answers.length + " " + offCall.open + " " + host.open, "3 false false", "the module off: nothing opens, never answered");
        standIn.active = true;

        // --- asked: drawn in the place's host ---
        answers = [];
        const call = ModalQuestions.ask(standIn, asker, _question, _remember);
        assert(call.open && host.open && ModalQuestions.busy, "an item in the place: the question opens in its host");
        assert(Object.isFrozen(call), "… the handle frozen");
        assertEqual(_find(host.modal, "modalTitle").text, "Stop all Serve shares?", "… its title");
        assertEqual(_all(host.modal, "modalItem").map(item => item.text).join("|"), "• https://laptop.example.ts.net → localhost:3000|• Funnel :8443",
                    "… its items, a line each");
        assert(_all(host.modal, "modalItem").every(item => item.textFormat === Text.PlainText), "… as plain text");
        assert(_until(() => host.modal.panel.width === Math.min(Theme.modal.widthSmall, area.width - 2 * Theme.modal.padding)),
               "… at the small width");

        // --- one at a time in the whole shell ---
        ModalQuestions.ask(standIn, asker, { title: "Another" }, _remember);
        assert(_until(() => answers.length === 1), "a second question: answered");
        assertEqual(_shape(_last()), "cancel false busy", "… blocked \"busy\"");
        assert(otherHost.ask({ title: "The shell's own" }, () => {}) !== "" && !otherHost.open, "… the shell's own host elsewhere refused too");
        assertEqual(_find(host.modal, "modalTitle").text, "Stop all Serve shares?", "… the first stays");

        // --- the user's answer ---
        host.modal.values = { funnel: true };
        const button = _find(host.modal, "modalButton:0");
        driver.mouseClick(button, button.width / 2, button.height / 2);
        assert(_until(() => answers.length === 2), "Stop all clicked: answered");
        assertEqual(_shape(_last()) + " " + JSON.stringify(_last().values) + " " + JSON.stringify(_last().subject),
                    "stopAll false  {\"funnel\":true} {\"shares\":[\"a\",\"b\"]}", "… with its id, the checkbox and the subject");
        assert(!call.open && !host.open && !ModalQuestions.busy, "… closed, the shell free again");
        assert(otherHost.ask({ title: "Now" }, () => {}) === "", "… the shell's own host may ask again");
        otherHost.cancel("window");

        // --- withdrawn: a lock, a page change, the module off; its own cancel() ---
        ModalQuestions.ask(standIn, asker, _question, _remember);
        Profiles.screenLocked = true;
        assertEqual(_shape(_last()), "cancel false locked", "the session locked: blocked \"locked\"");
        ModalQuestions.ask(standIn, asker, _question, _remember);
        assert(_until(() => answers.length === 4) && _last().blocked === "locked" && !host.open, "… asked while locked: blocked \"locked\"");
        Profiles.screenLocked = false;
        ModalQuestions.ask(standIn, asker, _question, _remember);
        host.page = "other";
        assertEqual(_shape(_last()), "cancel false closed", "the page changed: blocked \"closed\"");
        ModalQuestions.ask(standIn, asker, _question, _remember);
        ModalQuestions.ownerGone(standIn);
        assertEqual(_shape(_last()), "cancel false module", "the module turned off: blocked \"module\"");
        const own = ModalQuestions.ask(standIn, asker, _question, _remember);
        own.cancel();
        assertEqual(_shape(_last()) + " " + own.open, "cancel true  false", "its own cancel(): cancelled");
        const counted = answers.length;
        own.cancel();
        ModalQuestions.ownerGone(standIn);
        assertEqual(answers.length, counted, "… once: nothing more after it");

        // --- the place going while open ---
        const placesBefore = ModalQuestions._places.length;
        const going = _goingPlace.createObject(area);
        assertEqual(ModalQuestions._places.length - placesBefore, 1, "a host with a place: known");
        ModalQuestions.ask(standIn, going.asker, _question, _remember);
        assert(ModalQuestions.busy, "… asked there");
        going.destroy();
        assert(_until(() => answers.length === counted + 1), "its host destroyed: answered");
        assertEqual(_shape(_last()) + " " + ModalQuestions.busy + " " + (ModalQuestions._places.length - placesBefore),
                    "cancel false closed false 0", "… blocked \"closed\", the question and the place forgotten");
        const goingOff = _goingPlace.createObject(area);
        ModalQuestions.ask(standIn, goingOff.asker, _question, _remember);
        standIn.active = false;
        goingOff.destroy();
        assert(_until(() => answers.length === counted + 2), "destroyed while the module is off: answered");
        assertEqual(_last().blocked, "module", "… blocked \"module\"");
        standIn.active = true;

        // --- a handler that throws, a long label ---
        ModalQuestions.ask(standIn, asker, _question, () => { throw new Error("boom"); });
        host.cancel("escape");
        assert(!host.open && !ModalQuestions.busy, "a handler that throws: closed all the same");
        const warnedBefore = ApiElements.warned.length;
        ModalQuestions.ask(standIn, asker, { title: "Long", buttons: [{ label: "Save all of these five" }] }, _remember);
        host.cancel("escape");
        ModalQuestions.ask(standIn, asker, { title: "Long", buttons: [{ label: "Save all of these five" }] }, _remember);
        host.cancel("escape");
        assertEqual(ApiElements.warned.length - warnedBefore, 1, "a label over four words: logged once");
        assert(ApiElements.warned.includes("ask.label:fake:Save all of these five"), "… under the module and the label");
    }
}
