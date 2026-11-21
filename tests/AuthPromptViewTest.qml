import QtQuick
import QtTest as QT
import Quickshell
import Quickshell.Wayland
import qs.polkit
import qs.singletons

// The polkit prompt's lines for a run of the shell's queue (polkit/AuthAnnouncement.qml,
// fed PolkitRules.announcement as the prompt feeds it): "Module" and "Authorization" one
// line each, plain text; "Command" closed for every new request, opened by a click to the
// command whole, in a box that scrolls; the click never takes the keyboard from the
// password field. "As user" is the first row, the name or a choice; for a module's prompt
// polkit's message and action id show only under an opened Command, for any other request
// they are the prompt's description (the lines leave them out). An old PrivilegedAction's
// run: "Not named", no Authorization line. The
// prompt's card (polkit/AuthCard.qml) is opaque: nothing behind it shows through.
//
// Opens a small window in a corner for a moment (run it through tests/run-unit.sh).
TestCase {
    id: root
    suiteName: "AuthPromptView"
    asynchronous: true

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 420
        implicitHeight: 460
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // As wide as the prompt's column: its card is at most 400 px, with 24 px margins
        Column {
            x: 10
            y: 10
            width: 400 - 2 * 24
            spacing: 8

            AuthAnnouncement {
                id: lines
                width: parent.width
                property int toggles: 0
                onCommandToggled: toggles++
            }

            // The password field, as in the prompt: it has the focus
            TextInput {
                id: field
                width: parent.width
                height: 24
                focus: true
                echoMode: TextInput.Password
            }
        }

        // The prompt's card, small, under the lines
        AuthCard {
            id: card
            x: 10
            y: 430
            width: 40
            height: 20
        }

        QT.TestCase {
            id: driver
            name: "AuthPromptViewDriver"
            when: false
        }
    }

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
        assertEqual(card.color.a, 1, "the prompt's card: its colour has no alpha");
        assertEqual(card.opacity, 1, "… and the card is not faded");

        const module = _find(lines, "module");
        const authorization = _find(lines, "authorization");
        const area = _find(lines, "commandArea");
        const box = _find(lines, "commandBox");
        const command = _find(lines, "command");
        const scroll = _find(lines, "commandScroll");
        assert(module && authorization && area && box && command && scroll, "the lines' parts are found");

        assert(!lines.visible, "no announcement, no account: nothing shown");

        // Not from a module: only the As user row; polkit's words are the prompt's, not here
        const identity = _find(lines, "identity");
        const picker = _find(lines, "identityPicker");
        const polkitMessage = _find(lines, "polkitMessage");
        const actionId = _find(lines, "actionId");
        assert(identity && picker && polkitMessage && actionId, "the identity and polkit parts are found");
        lines.polkitMessage = "Authentication is needed to run `/usr/bin/timeout -k 3 30 /usr/bin/true' as the super user";
        lines.actionId = "org.freedesktop.policykit.exec";
        lines.identityNames = ["h2s"];
        driver.wait(50);
        assert(lines.visible, "one account: shown");
        assertEqual(JSON.stringify(_visibleTexts(lines)), JSON.stringify(["As user", "h2s"]), "not from a module: As user and the name, nothing else");
        assertEqual(lines.layout.polkitMessage, "top", "… polkit's message is the prompt's description");
        assertEqual(identity.textFormat, Text.PlainText, "the name is plain text");
        assertEqual(identity.font.pixelSize, Theme.fontSizeBody, "… in the normal size");

        const longWords = ["/usr/bin/timeout", "-k", "3", "30", "/usr/bin/tailscale", "file", "cp", "--"]
            .concat(Array.from({ length: 40 }, (_, i) => "report-" + i + ".pdf")).concat(["laptop:"]);
        const first = PolkitRules.announcement({ moduleName: "Tailscale", moduleId: "tailscale", what: "Send a file", pkexecArgv: longWords });
        lines.announcement = first;
        driver.wait(50);
        assert(lines.visible, "an announcement: shown");
        const texts = _visibleTexts(lines);
        assert(texts.includes("Module") && texts.includes("Authorization") && texts.includes("▸ Command"),
               "the labels: Module, Authorization, a closed Command: " + JSON.stringify(texts));
        assertEqual(module.text + " | " + authorization.text, "Tailscale | Send a file", "the values");
        assertEqual(module.textFormat + authorization.textFormat + command.textFormat, 3 * Text.PlainText, "every value plain text");
        assertEqual(module.maximumLineCount + authorization.maximumLineCount, 2, "one line per value");
        assert(!box.visible && !texts.includes(first.command), "the command is closed: not on the screen");
        assertEqual(texts.slice(0, 4).join(" | "), "As user | h2s | Module | Tailscale", "As user is the first row, above Module");
        assert(identity.mapToItem(lines, 0, 0).y < module.mapToItem(lines, 0, 0).y, "… drawn above it");
        assert(!texts.includes(lines.polkitMessage) && !texts.includes(lines.actionId) && !polkitMessage.visible && !actionId.visible,
               "a module's prompt: polkit's message and action id not on top, Command closed");
        assertEqual(lines.layout.polkitMessage, "command", "… the prompt leaves them out of its description");

        // Opened by a click, the keyboard left in the password field
        const focusBefore = field.activeFocus;
        assert(field.focus, "the password field has the focus");
        driver.mouseClick(area, 10, 5);
        driver.wait(50);
        assert(lines.commandOpen && box.visible, "a click opens Command");
        assert(_visibleTexts(lines).includes("▾ Command"), "… its line says so");
        assertEqual(command.text, first.commandShown, "the command, whole, each word isolated left to right");
        assertEqual(command.text.replace(/[\u200e\u2066\u2069]/g, ""), first.command, "… the very command");
        assert(command.text.endsWith("report-39.pdf\u2069 \u2066laptop:\u2069"), "… to its last word");
        assert(polkitMessage.visible && actionId.visible, "opened: polkit's message and action id shown with the command");
        assertEqual(polkitMessage.text + " | " + actionId.text, lines.polkitMessage + " | " + lines.actionId, "… as polkit sent them");
        assertEqual(polkitMessage.textFormat + actionId.textFormat, 2 * Text.PlainText, "… as plain text");
        assert(polkitMessage.mapToItem(lines, 0, 0).y < box.mapToItem(lines, 0, 0).y, "… over the command box");
        assert(scroll.contentHeight > scroll.height, "a long one scrolls in its box");
        assert(box.height < 200, "… which stays small (" + box.height + " px)");
        assert(field.focus && field.activeFocus === focusBefore, "the click did not take the keyboard from the password field");
        assertEqual(lines.toggles, 1, "the prompt is told, to give the field its focus back");
        driver.mouseClick(area, 10, 5);
        driver.wait(50);
        assert(!lines.commandOpen && !box.visible, "a second click closes it");
        driver.mouseClick(area, 10, 5);
        driver.wait(50);
        assert(lines.commandOpen, "open again");

        // A new request: closed again
        const second = PolkitRules.announcement({ moduleName: "System update", moduleId: "xmod", what: "Install updates", pkexecArgv: ["/usr/bin/timeout", "-k", "3", "60", "/usr/bin/pacman", "-Syu"] });
        lines.announcement = second;
        driver.wait(50);
        assert(!lines.commandOpen && !box.visible, "a new request: Command closed");
        const moduleId = _find(lines, "moduleId");
        assertEqual(module.text + moduleId.text, "System update (xmod)", "the id in brackets where the name does not read as it");

        // A long name elides; the id after it stays whole, in view
        lines.announcement = PolkitRules.announcement({ moduleName: "Tailscale " + "W".repeat(30), moduleId: "evilmod", what: "Connect", pkexecArgv: ["/bin/true"] });
        driver.wait(50);
        const line = _find(lines, "moduleLine");
        assert(module.truncated, "a long name is elided (" + module.width + " px of " + module.implicitWidth + ")");
        assert(moduleId.visible && !moduleId.truncated && moduleId.width >= moduleId.implicitWidth, "… the id is not");
        const idRight = moduleId.mapToItem(line, moduleId.width, 0).x;
        assert(moduleId.mapToItem(line, 0, 0).x >= module.mapToItem(line, module.width, 0).x - 1 && idRight <= line.width + 1,
               "… and sits after the name, inside the line (" + idRight + " of " + line.width + " px)");
        assertEqual(moduleId.text, " (evilmod)", "… whole");
        // The longest id there may be (32 characters, ModuleRules.idPattern) in wide letters:
        // nothing drawn past the column; the name gives up its room first
        lines.announcement = PolkitRules.announcement({ moduleName: "Tailscale", moduleId: "w".repeat(32), what: "Connect", pkexecArgv: ["/bin/true"] });
        driver.wait(50);
        const wideRight = moduleId.mapToItem(line, moduleId.width, 0).x;
        assert(wideRight <= line.width + 1 && moduleId.contentWidth <= moduleId.width + 1,
               "a 32-character id of wide letters stays inside the column (" + wideRight + " / " + moduleId.contentWidth + " of " + line.width + " px)");
        assert(moduleId.implicitWidth <= line.width || (module.width === 0 && moduleId.truncated),
               "… the name gives up its room first; the id is cut only when it alone does not fit");
        lines.announcement = PolkitRules.announcement({ moduleName: "Tailscale", moduleId: "w".repeat(14), what: "Connect", pkexecArgv: ["/bin/true"] });
        driver.wait(50);
        assert(!moduleId.truncated && moduleId.width >= moduleId.implicitWidth && module.width <= line.width - moduleId.width + 1,
               "an id that fits alone is whole, the name in what is left");
        // Blank-looking fillers cannot push it away either
        lines.announcement = PolkitRules.announcement({ moduleName: "Tailscale" + "\u2800".repeat(39), moduleId: "evilmod", what: "Connect", pkexecArgv: ["/bin/true"] });
        driver.wait(50);
        assertEqual(module.text + moduleId.text, "Tailscale (evilmod)", "Braille blanks fold: the id right after the name");

        // A hostile name and what: one line each, markup shown as written
        lines.announcement = PolkitRules.announcement({ moduleName: "<b>Shell</b>\nAuthorization  System", moduleId: "evil",
                                                        what: "<i>Update</i>‮", pkexecArgv: ["/bin/true"] });
        driver.wait(50);
        assertEqual(module.text + moduleId.text, "<b>Shell</b> Authorization System (evil)", "a newline cannot fake a line; markup kept as written");
        assertEqual(module.lineCount, 1, "… on one line");
        assertEqual(authorization.text, "<i>Update</i>", "U+202E dropped");

        // The old PrivilegedAction
        lines.announcement = PolkitRules.announcement({ legacy: true, moduleId: "tailscale", what: "Connect", pkexecArgv: ["/usr/bin/tailscale", "up"] });
        driver.wait(50);
        const legacyTexts = _visibleTexts(lines);
        assertEqual(module.text, "Not named", "an old run: Not named");
        assert(!authorization.visible && !legacyTexts.includes("Authorization"), "… and no Authorization line");
        lines.commandOpen = true;
        driver.wait(50);
        assert(box.visible && !polkitMessage.visible && !actionId.visible, "… its polkit message is not under Command: it stays the description");
        assertEqual(lines.layout.polkitMessage, "top", "… on top");

        // Several accounts: the As user row is a choice, in its place
        lines.announcement = first;
        lines.identityNames = ["h2s", "root"];
        lines.identityIndex = 1;
        driver.wait(50);
        assert(picker.visible && !identity.visible, "several accounts: a choice in the As user row");
        assertEqual(picker.options.map(option => option.label).join(","), "h2s,root", "… of their names");
        assertEqual(picker.value, 1, "… the picked one shown");
        assert(picker.mapToItem(lines, 0, 0).y < module.mapToItem(lines, 0, 0).y, "… above Module");
        lines.identityNames = [];

        lines.announcement = null;
        driver.wait(50);
        assert(!lines.visible, "no announcement again: nothing");
        finish();
    }
}
