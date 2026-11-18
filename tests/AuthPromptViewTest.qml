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
// password field. An old PrivilegedAction's run: "Not named", no Authorization line.
//
// Opens a small window in a corner for a moment (run it through tests/run-unit.sh).
TestCase {
    id: root
    suiteName: "AuthPromptView"
    asynchronous: true

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 420
        implicitHeight: 360
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Column {
            x: 10
            y: 10
            width: 360
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
        const module = _find(lines, "module");
        const authorization = _find(lines, "authorization");
        const area = _find(lines, "commandArea");
        const box = _find(lines, "commandBox");
        const command = _find(lines, "command");
        const scroll = _find(lines, "commandScroll");
        assert(module && authorization && area && box && command && scroll, "the lines' parts are found");

        assert(!lines.visible, "no announcement: nothing shown");

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

        // Opened by a click, the keyboard left in the password field
        const focusBefore = field.activeFocus;
        assert(field.focus, "the password field has the focus");
        driver.mouseClick(area, 10, 5);
        driver.wait(50);
        assert(lines.commandOpen && box.visible, "a click opens Command");
        assert(_visibleTexts(lines).includes("▾ Command"), "… its line says so");
        assertEqual(command.text, first.command, "the command, whole");
        assert(command.text.endsWith("report-39.pdf laptop:"), "… to its last word");
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
        assertEqual(module.text, "System update (xmod)", "the id in brackets where the name does not read as it");

        // A hostile name and what: one line each, markup shown as written
        lines.announcement = PolkitRules.announcement({ moduleName: "<b>Shell</b>\nAuthorization  System", moduleId: "evil",
                                                        what: "<i>Update</i>‮", pkexecArgv: ["/bin/true"] });
        driver.wait(50);
        assertEqual(module.text, "<b>Shell</b> Authorization System (evil)", "a newline cannot fake a line; markup kept as written");
        assertEqual(module.lineCount, 1, "… on one line");
        assertEqual(authorization.text, "<i>Update</i>", "U+202E dropped");

        // The old PrivilegedAction
        lines.announcement = PolkitRules.announcement({ legacy: true, moduleId: "tailscale", what: "Connect", pkexecArgv: ["/usr/bin/tailscale", "up"] });
        driver.wait(50);
        const legacyTexts = _visibleTexts(lines);
        assertEqual(module.text, "Not named", "an old run: Not named");
        assert(!authorization.visible && !legacyTexts.includes("Authorization"), "… and no Authorization line");

        lines.announcement = null;
        driver.wait(50);
        assert(!lines.visible, "no announcement again: nothing");
        finish();
    }
}
