import QtQuick
import Quickshell
import qs.components
import qs.singletons

// The Settings modal (components/SettingsModal.qml) in its host (SettingsModalHost.qml):
// the rules behind it (modalButtons, modalBody, modalChecks, modalWidth, modalRefusal,
// sameSubject); opened, it shows its title, lines, checkboxes, content and buttons; a click
// on a control behind it does nothing; a button answers with its id and the checkboxes'
// states; "×", Escape, the session locking, the window hiding and the subject going answer
// cancel; one button informs and closes it; a second question while one is open is
// refused; the keyboard taken and given back.
//
// Opens a small window for a moment, an ordinary one that takes the keyboard (Escape is
// sent to it), in the runner's headless compositor.
TestCase {
    id: suite
    suiteName: "SettingsModal"
    asynchronous: true
    // Its window takes the keyboard, as other suites' do
    ownProcess: true

    property int behindClicks: 0
    property var answers: []
    property var drawerEvents: []

    property var _window: FloatingWindow {
        title: "h2s-tests settings modal"
        visible: false
        implicitWidth: 640
        implicitHeight: 420
        color: Theme.popupBackground

        Item {
            id: area
            anchors.fill: parent

            TextInput {
                id: field
                x: 10; y: 10
                width: 200
                height: 24
                text: "behind"
                activeFocusOnTab: true
            }
            Checkbox {
                id: behindBox
                x: 10; y: 250
                label: "Behind"
            }
            SmallButton {
                id: behind
                x: 10; y: 200
                label: "Behind"
                onClicked: suite.behindClicks++
            }

            // A side panel open behind a modal (a modal asked from a side panel)
            SideDrawer {
                id: drawer
                anchors.fill: parent
                title: "Backups"
                onRequested: event => suite.drawerEvents = suite.drawerEvents.concat([event])
            }

            SettingsModalHost {
                id: host
                anchors.fill: parent
            }

            // Over the window's content, as in the Settings window: it leaves the focus alone
            // while a question is open
            TouchTextFocus {
                id: touchText
                watching: !host.open
            }
        }

        WindowDriver {
            id: driver
            name: "SettingsModalDriver"
        }
    }

    // Content under the checkboxes, with values of its own
    property Component _contentComp: Component {
        Text {
            objectName: "modalContent"
            property var values: ({ picked: "b" })
            text: "Exit map"
            color: Theme.textSecondary
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

    function _click(name) {
        const item = _find(host.modal, name);
        if (!item)
            return false;
        driver.mouseClick(item, item.width / 2, item.height / 2);
        return true;
    }

    function _last() {
        return answers[answers.length - 1] ?? null;
    }

    function _remember(answer) {
        suite.answers = suite.answers.concat([answer]);
    }

    function _askRemove() {
        return host.ask({
            kind: "danger",
            title: "Remove Player?",
            body: [{ text: "Not installed by the shell.", strong: true }, "Deletes the folder ~/.local/share/h2s-shell/modules/player."],
            checks: [{ key: "data", label: "Also delete its data and settings" }],
            content: _contentComp,
            buttons: [{ id: "remove", label: "Remove", kind: "delete" }],
            cancelLabel: "Keep",
            subject: { id: "player", directory: "/modules/player" }
        }, _remember);
    }

    function _focusInside() {
        const focused = host.Window.activeFocusItem;
        return focused !== null && host.modal._isInside(focused);
    }

    function runAsync() {
        try {
            _rules();
            _run();
        } finally {
            if (host.open)
                host.cancel("window");
            Profiles.screenLocked = false;
            // The window gone, whatever happened: the file chooser's suite takes the keyboard next
            _window.visible = false;
        }
        finish();
    }

    function _rules() {
        const rules = ApiElementRules;
        const shape = list => list.buttons.map(button => button.id + "/" + button.label + "/" + button.kind + (button.cancel ? "/cancel" : "")).join(" ");
        const remove = rules.modalButtons([{ id: "remove", label: "Remove", kind: "delete" }], "Keep");
        assertEqual(shape(remove), "remove/Remove/delete cancel/Keep/cancel/cancel", "modalButtons: no cancel given: one added, labelled as asked, last");
        assertEqual(remove.informing, false, "… a question, not information");
        assertEqual(shape(rules.modalButtons([{ label: "Disable", kind: "warning" }])), "Disable/Disable/warning cancel/Cancel/cancel/cancel",
            "… no cancel label: Cancel; no id: the label is the id");
        assertEqual(shape(rules.modalButtons([{ label: "No", cancel: true }, { label: "Yes", kind: "save" }])), "Yes/Yes/save cancel/No/cancel/cancel",
            "… the cancel given goes last, its label kept");
        assertEqual(shape(rules.modalButtons([{ label: "Back", kind: "cancel" }, { label: "Go" }, { label: "Never", cancel: true }])),
            "Go/Go/normal cancel/Back/cancel/cancel", "… two cancels: the first kept, one cancel only");
        const info = rules.modalButtons([], "OK");
        assertEqual(shape(info) + " " + info.informing, "cancel/OK/normal/cancel true", "… none of its own: one button, informing");
        assertEqual(shape(rules.modalButtons(undefined)), "cancel/OK/normal/cancel", "… not a list, no label: OK");
        const close = rules.modalButtons([{ label: "Close", kind: "success", cancel: true }]);
        assertEqual(shape(close) + " " + close.informing, "cancel/Close/success/cancel true", "… a cancel alone: informing, as given");
        assertEqual(shape(rules.modalButtons([null, 3, { label: "" }, { kind: "delete" }, { id: "cancel", label: "Drop", kind: "delete" }])),
            "Drop/Drop/delete cancel/Cancel/cancel/cancel", "… no object or no label: left out; an action may not take the cancel's id");
        assertEqual(rules.modalButtons([{ label: "Go\nnow" }]).buttons[0].label, "Go now", "… labels on one line");

        assertEqual(JSON.stringify(rules.modalBody(["One", { text: "Two", strong: true }, "", null, { text: "a\nb" }])),
            JSON.stringify([{ text: "One", strong: false }, { text: "Two", strong: true }, { text: "a b", strong: false }]),
            "modalBody: strings and lines, the empty left out, each on one line");
        assertEqual(JSON.stringify(rules.modalBody("Just this")), JSON.stringify([{ text: "Just this", strong: false }]), "… a string: one line");
        assertEqual(rules.modalBody({ text: "x" }).length + rules.modalBody(undefined).length, 0, "… anything else: none");
        assertEqual(PrivilegedRules.characters(rules.modalBody(["x".repeat(1000)])[0].text).length, rules.modalLineCap, "… a long line cut at the cap");
        assertEqual(rules.modalBody(["<b>bold</b>"])[0].text, "<b>bold</b>", "… markup kept as text (drawn as plain text)");

        assertEqual(JSON.stringify(rules.modalChecks([{ key: "data", label: "Data" }, { key: "data", label: "Again" }, { key: "", label: "No key" },
                                                      { key: "x" }, null, { key: "y", label: "Y\nZ" }])),
            JSON.stringify([{ key: "data", label: "Data" }, { key: "y", label: "Y Z" }]), "modalChecks: keyed, labelled, each key once");
        assertEqual(rules.modalChecks("data").length, 0, "… not a list: none");

        const modal = { widthSmall: 380, widthMedium: 520, padding: 18 };
        assertEqual(rules.modalWidth("s", 1000, modal) + " " + rules.modalWidth("m", 1000, modal) + " " + rules.modalWidth("xl", 1000, modal),
            "380 520 520", "modalWidth: each size's width; one it does not have: m");
        assertEqual(rules.modalWidth("m", 400, modal), 364, "… never wider than the area less its padding");
        assertEqual(rules.modalWidth("m", 0, modal) + " " + rules.modalWidth("m", 1000, null), "0 0", "… no area, no sizes: 0");

        assertEqual(rules.modalRefusal(false, false), "", "modalRefusal: none open, unlocked: opens");
        assert(rules.modalRefusal(true, false) !== "" && rules.modalRefusal(false, true) !== "", "… one open, or locked: refused");
        assert(rules.sameSubject({ id: "a" }, { id: "a" }) && !rules.sameSubject({ id: "a" }, { id: "b" }), "sameSubject: by value");
        assert(!rules.sameSubject(undefined, undefined) && !rules.sameSubject(null, null), "… no subject is never the same");
    }

    function _run() {
        _window.visible = true;
        assert(_until(() => _window.visible && area.width > 0 && host.Window.active), "the window shows and has the keyboard");
        assertEqual(host.open + " " + host.modal.visible, "false false", "closed at first: nothing drawn");
        field.forceActiveFocus();
        assert(field.activeFocus, "a field behind has the keyboard");

        // --- a danger question ---
        assertEqual(_askRemove(), "", "ask: opens");
        assert(_until(() => host.modal.visible && host.modal.panel.width > 0), "… drawn");
        assertEqual(_find(host.modal, "modalTitle").text, "Remove Player?", "… its title");
        const lines = _all(host.modal, "modalLine");
        assertEqual(lines.map(line => line.text + (line.font.bold ? "*" : "")).join("|"),
            "Not installed by the shell.*|Deletes the folder ~/.local/share/h2s-shell/modules/player.", "… its lines, the first bold");
        assert(lines.every(line => line.textFormat === Text.PlainText), "… as plain text");
        assert(_find(host.modal, "modalCheck:data") !== null, "… its checkbox");
        assert(_find(host.modal, "modalContent") !== null, "… its content");
        assertEqual(_find(host.modal, "modalButton:0").label + " " + _find(host.modal, "modalButton:1").label, "Remove Keep", "… Remove, then Keep");
        assert(Qt.colorEqual(host.modal.panel.children[0].border.color, Theme.error), "… a border in the error colour");
        assertEqual(host.modal.panel.width, Math.min(Theme.modal.widthMedium, area.width - 2 * Theme.modal.padding), "… its width the theme's");
        assert(_until(_focusInside), "… holds the keyboard");

        assert(host.ask({ title: "Another" }, _remember) !== "", "a second question while one is open: refused");
        assertEqual(_find(host.modal, "modalTitle").text, "Remove Player?", "… the first stays");

        driver.mouseClick(behind, behind.width / 2, behind.height / 2);
        driver.mouseClick(field, 5, 5);
        assertEqual(behindClicks, 0, "a click on a control behind: nothing");
        assert(_focusInside(), "… the keyboard stays in the modal");

        assert(_click("modalCheck:data"), "the checkbox clicked");
        assert(_until(() => host.modal.values.data === true), "… checked");
        assert(_until(() => _find(host.modal, "modalButton:0").x + _find(host.modal, "modalButton:0").width < _find(host.modal, "modalButton:1").x),
            "the buttons laid out, Remove before Keep");
        assert(_click("modalButton:0"), "Remove clicked");
        assert(_until(() => answers.length === 1), "… answered once");
        assertEqual(JSON.stringify(_last()), JSON.stringify({ button: "remove", cancelled: false, reason: "button",
            values: { data: true, picked: "b" }, subject: { id: "player", directory: "/modules/player" } }),
            "… with its id, the checkbox's and the content's values, and the subject");
        assertEqual(host.open + " " + host.modal.visible, "false false", "… closed");
        assert(_until(() => field.activeFocus), "… the keyboard back to the field");
        assertEqual(host.ask({ title: "Now" }, () => {}) === "" && host.open, true, "closed, a question opens again");
        host.cancel("window");

        // --- ×, Escape ---
        _askRemove();
        assert(_until(() => host.modal.visible), "opened again");
        assertEqual(host.modal.values.data === true, false, "… its checkbox unchecked again");
        assert(_click("modalClose"), "× clicked");
        assertEqual(_last()?.reason + " " + _last()?.button + " " + _last()?.cancelled, "close cancel true", "… answers cancel");
        assertEqual(host.open, false, "… closed");
        _askRemove();
        assert(_until(_focusInside), "opened again, with the keyboard");
        driver.keyClick(Qt.Key_Escape);
        assert(_until(() => !host.open), "Escape closes it");
        assertEqual(_last()?.reason + " " + _last()?.button, "escape cancel", "… as cancel");
        _askRemove();
        assert(_click("modalButton:1"), "Keep clicked");
        assertEqual(_last()?.reason + " " + _last()?.button + " " + _last()?.cancelled, "button cancel true", "… the cancel button answers cancel");

        // --- over a side panel: Escape is the modal's ---
        drawer.open = true;
        _askRemove();
        assert(_until(_focusInside), "a modal over an open side panel, with the keyboard");
        driver.keyClick(Qt.Key_Escape);
        assert(_until(() => !host.open), "Escape closes the modal");
        assertEqual(drawerEvents.length + " " + drawer.open, "0 true", "… not the side panel behind it");
        drawer.open = false;

        // --- Tab stays inside ---
        host.ask({ title: "Two boxes", checks: [{ key: "one", label: "One" }, { key: "two", label: "Two" }],
                   buttons: [{ label: "Go" }] }, _remember);
        assert(_until(_focusInside), "a modal with two checkboxes, with the keyboard");
        const reached = [];
        let stayed = true;
        for (let i = 0; i < 5; i++) {
            driver.keyClick(Qt.Key_Tab);
            driver.wait(20);
            stayed = stayed && _focusInside();
            reached.push(host.Window.activeFocusItem?.objectName ?? "");
        }
        assert(stayed && !field.activeFocus && !behindBox.activeFocus, "Tab five times: the keyboard never reaches a control behind");
        assertEqual(reached.join(" "), "modalCheck:one modalCheck:two modalButton:0 modalButton:1 modalCheck:one", "… it cycles through the checkboxes and the buttons, wrapping");
        driver.keyClick(Qt.Key_Tab, Qt.ShiftModifier);
        driver.wait(20);
        assert(_focusInside() && host.Window.activeFocusItem?.objectName === "modalButton:1", "… Shift+Tab too, back round to the last button");
        host.cancel("window");

        // --- a touch tap: the focus stays ---
        _askRemove();
        assert(_until(_focusInside), "opened, with the keyboard");
        const title = _find(host.modal, "modalTitle");
        const touch = driver.touchEvent(title);
        touch.press(0, title, 5, 5).commit();
        driver.wait(60);
        touch.release(0, title, 5, 5).commit();
        driver.wait(120);
        assert(_focusInside(), "a tap on the modal: the keyboard stays in it");
        driver.keyClick(Qt.Key_Escape);
        assert(_until(() => !host.open), "… and Escape still cancels");
        assertEqual(_last()?.reason, "escape", "… as Escape");

        // --- the window turning to another page ---
        host.page = "general";
        _askRemove();
        host.page = "general";
        assertEqual(host.open, true, "the same page set again: stays");
        host.page = "modules";
        assertEqual(host.open + " " + _last()?.reason + " " + _last()?.button, "false page cancel", "another page: closed as cancelled");

        // --- one button: informs ---
        const before = answers.length;
        host.ask({ kind: "success", title: "Settings restored", body: "Tailscale's settings are back.", cancelLabel: "OK" }, _remember);
        assert(_until(() => host.modal.visible), "an informing modal opens");
        assertEqual(_all(host.modal, "modalButton:0").length + _all(host.modal, "modalButton:1").length, 1, "… with one button");
        assertEqual(_find(host.modal, "modalButton:0").label, "OK", "… OK");
        assert(Qt.colorEqual(host.modal.panel.children[0].border.color, Theme.success), "… in the success colour");
        assert(_click("modalButton:0"), "OK clicked");
        assertEqual(answers.length - before, 1, "… answered once");
        assertEqual(_last()?.button + " " + host.open, "cancel false", "… closed, as the × does");

        // --- the subject going ---
        _askRemove();
        host.withdraw({ id: "weather" });
        assertEqual(host.open, true, "another subject went: stays");
        host.withdraw({ id: "player", directory: "/modules/player" });
        assertEqual(host.open + " " + _last()?.reason + " " + _last()?.button, "false subject cancel", "its subject went: closed as cancelled");

        // --- a lock ---
        _askRemove();
        Profiles.screenLocked = true;
        assertEqual(host.open + " " + _last()?.reason + " " + _last()?.button, "false lock cancel", "the session locked: closed as cancelled");
        assert(_askRemove() !== "" && !host.open, "… while locked no question opens");
        Profiles.screenLocked = false;

        // --- the window hiding ---
        _askRemove();
        _window.visible = false;
        assert(_until(() => !host.open), "the window hid: closed");
        assertEqual(_last()?.reason + " " + _last()?.button, "window cancel", "… as cancelled");
    }
}
