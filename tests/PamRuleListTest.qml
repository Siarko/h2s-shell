import QtQuick
import Quickshell
import qs.components
import qs.singletons
import qs.panels.settings

// The sign-in rule list (panels/settings/PamRuleList.qml) and its rules (PamRuleViewRules):
// chips, control words per method, "No limit", the add list, drop slots and drops, the
// fixed row's question; then the element under clicks: a row opened, a word picked, a field
// edited, "No limit", a row added (opened, sufficient), one deleted after its question, the
// fixed row's removal asked in the Settings modal, rows dragged by their handle while the
// page does not scroll, and nothing below the fixed row.
//
// Opens a small window for a moment, an ordinary one that takes the keyboard (a field is
// typed into), in the runner's headless compositor.
TestCase {
    id: suite
    suiteName: "PamRuleList"
    asynchronous: true
    // Its window takes the keyboard, as other suites' do
    ownProcess: true

    readonly property var facts: ({ service: "sudo", fingerprint: "ready", securityKey: "absent",
                                    faillockPresent: true, faillock: { deny: 3, failInterval: 900, unlockTime: 600 } })
    property var rows: []
    property int edits: 0

    property var _window: FloatingWindow {
        title: "h2s-tests pam rule list"
        visible: false
        implicitWidth: 760
        implicitHeight: 520
        color: Theme.popupBackground

        Item {
            id: area
            anchors.fill: parent

            Flickable {
                id: page
                anchors.fill: parent
                contentWidth: width
                // Taller than the window: the page scrolls, and could take a drag
                contentHeight: 2000
                boundsBehavior: Flickable.StopAtBounds

                PamRuleList {
                    id: list
                    x: 20
                    // Low enough in the page that it can scroll either way under a drag
                    y: 200
                    width: 700
                    title: "sudo and administrator prompts"
                    rows: suite.rows
                    facts: suite.facts
                    modalHost: host
                    systemLines: ["auth required pam_faillock.so preauth"]
                    onEdited: next => {
                        suite.edits++;
                        suite.rows = next;
                    }
                }
            }

            SettingsModalHost {
                id: host
                anchors.fill: parent
            }
        }

        WindowDriver {
            id: driver
            name: "PamRuleListDriver"
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

    function _item(name) {
        // From the window's own root: the add list floats there, above the window's content
        return _find(area.Window.window?.contentItem ?? _window.contentItem, name);
    }

    // Waits until `item` stays where it is for a few frames: an opened row lays out what it
    // shows a frame or two after it shows, moving what is below
    function _settle(item) {
        let last = "", same = 0;
        for (let waited = 0; waited < 3000 && same < 3; waited += 16) {
            const place = item.mapToItem(area, 0, 0);
            const now = place.x + "," + place.y + "," + item.width + "," + item.height;
            same = now === last ? same + 1 : 0;
            last = now;
            driver.wait(16);
        }
    }

    function _click(name, x) {
        const item = _item(name);
        if (!item || !item.visible)
            return false;
        _settle(item);
        driver.mouseClick(item, x ?? item.width / 2, item.height / 2);
        return true;
    }

    function _ids() {
        return rows.map(row => row.id).join(",");
    }

    function _chips(id) {
        return _all(_item("row:" + id), "chip").filter(chip => chip.visible).map(chip => chip.text).join(",");
    }

    // Drags the row `id` by its handle to the scene height `toY`, in steps, the button held;
    // `during` runs before the release
    function _drag(id, toY, during) {
        const handle = _item("handle:" + id);
        const start = handle.mapToItem(area, handle.width / 2, handle.height / 2);
        driver.mousePress(area, start.x, start.y);
        const steps = 8;
        for (let i = 1; i <= steps; i++) {
            driver.wait(16);
            driver.mouseMove(area, start.x, start.y + (toY - start.y) * i / steps);
        }
        driver.wait(16);
        if (during)
            during();
        driver.mouseRelease(area, start.x, toY);
        driver.wait(30);
    }

    function runAsync() {
        try {
            _rules();
            _run();
        } finally {
            if (host.open)
                host.cancel("window");
            _window.visible = false;
        }
        finish();
    }

    function _rules() {
        const rules = PamRuleViewRules;
        const fingerprint = (id, details) => ({ id, method: "fingerprint", control: "sufficient", details: Object.assign({ timeout: 10, tries: 3 }, details ?? {}) });
        const password = (id, counted) => ({ id, method: "password", control: "sufficient", details: { counted: counted === true } });
        const raw = (id, text) => ({ id, method: "raw", control: "", details: { text } });
        const fixed = PamRuleRules.fixedRow();
        const ids = list => list === null ? "null" : list.map(row => row.id).join(",");

        // --- control words per method ---
        assertEqual(rules.controlsFor("fingerprint").join(" "), "sufficient required requisite", "controlsFor: no optional for the editor's own methods");
        assertEqual(rules.controlsFor("password").join(" ") + " | " + rules.controlsFor("securityKey").join(" "),
                    "sufficient required requisite | sufficient required requisite", "… nor for the password or the key");
        assertEqual(rules.controlsFor("raw").join(" "), "sufficient required requisite optional", "… a raw line: all four");

        // --- unlimited details ---
        assert(rules.unlimited(-1) && !rules.unlimited(0) && !rules.unlimited(10) && !rules.unlimited("-1"), "unlimited: a negative number only");
        const timeout = rules.range("fingerprint", "timeout");
        assertEqual(JSON.stringify(rules.typedChange("fingerprint", "timeout", " 25 ")), JSON.stringify({ timeout: 25 }), "typedChange: a number in range");
        assertEqual(rules.typedChange("fingerprint", "timeout", String(timeout.max + 1)), null, "… above the range: none");
        assertEqual(rules.typedChange("fingerprint", "timeout", String(timeout.min - 1)), null, "… below it: none");
        assertEqual(JSON.stringify([rules.typedChange("fingerprint", "timeout", String(timeout.min)), rules.typedChange("fingerprint", "timeout", String(timeout.max))]),
                    JSON.stringify([{ timeout: timeout.min }, { timeout: timeout.max }]), "… the range's ends included");
        assertEqual(rules.typedChange("fingerprint", "tries", "2.5") ?? rules.typedChange("fingerprint", "tries", "x") ?? rules.typedChange("fingerprint", "pin", "1"),
                    null, "… not a whole number, or not a number detail: none");
        assertEqual(JSON.stringify(rules.limitChange("fingerprint", "tries", true, "4")), JSON.stringify({ tries: -1 }), "limitChange: on is -1");
        assertEqual(JSON.stringify(rules.limitChange("fingerprint", "tries", false, "4")), JSON.stringify({ tries: 4 }), "… off takes the field's number");
        assertEqual(JSON.stringify(rules.limitChange("fingerprint", "timeout", false, "")), JSON.stringify({ timeout: timeout.initial }),
                    "… off with no number in the field: the initial value");
        assertEqual(rules.limitChange("password", "counted", true, ""), null, "… not a number detail: none");

        // --- chips ---
        assertEqual(rules.chips(fingerprint("r1"), facts).join(","), "10 s,3 tries,Not counted", "chips: a fingerprint's numbers and counting");
        assertEqual(rules.chips(fingerprint("r1", { timeout: -1, tries: -1 }), facts).join(","), "no time limit,unlimited tries,Not counted", "… no limits");
        assertEqual(rules.chips(fingerprint("r1", { tries: 1 }), facts)[1], "1 try", "… one try");
        assertEqual(rules.chips({ id: "k", method: "securityKey", details: { pin: true } }, facts).join(",") + " | "
                    + rules.chips({ id: "k", method: "securityKey", details: { pin: false } }, facts).join(","),
                    "PIN,Not counted | Touch,Not counted", "… a key: PIN or touch");
        assertEqual(rules.chips(password("p", true), facts).join(",") + " | " + rules.chips(password("p", false), facts).join(","),
                    "Counted | Not counted", "… a password: counted or not");
        assertEqual(rules.chips(password("p", true), { faillockPresent: false }).length, 0, "… where the system does not count: no chip");
        assertEqual(rules.chips(fixed, facts).join(","), "Counts: 3 wrong in 15 min lock 10 min", "… the fixed row: faillock's numbers");
        assertEqual(rules.chips(fixed, { texts: { systemRow: "NixOS's rules" }, faillockPresent: false }).join(","), "NixOS's rules",
                    "… without faillock: whose rules, where the integration names them");
        assertEqual(rules.chips(fixed, { texts: {}, faillockPresent: false }).length, 0, "… elsewhere without faillock: none");
        assertEqual(rules.chips(raw("x", "auth sufficient pam_ldap.so"), facts).join(","), "Not checked", "… a raw line: not checked");
        assertEqual(rules.chips(null, facts).length, 0, "… no row: none");

        // --- what opens ---
        assertEqual([rules.opened(fixed), rules.opened(raw("x", "")), rules.opened(password("p"))].join(" "), "fixed raw rule", "opened: by kind of row");
        const reading = rules.rawReading("auth sufficient pam_ldap.so use_first_pass", facts);
        assert(!reading.problem && reading.text.startsWith("Reads as: auth · sufficient · pam_ldap.so"), "rawReading: how a line reads");
        assert(rules.rawReading("hello", facts).problem, "… not a line: a problem");

        const result = { refusals: [{ id: "r1" }, { id: "" }], warnings: [{ id: "r1" }, { id: "r2" }] };
        assertEqual([rules.rowState(result, "r1"), rules.rowState(result, "r2"), rules.rowState(result, "r3"), rules.rowState(result, "")].join("/"),
                    "refused/warned//", "rowState: a refusal first, then a warning; the list's own items name no row");

        // --- adding ---
        const options = rules.addOptions(facts);
        assertEqual(options.map(option => option.method + ":" + option.available).join(" "),
                    "fingerprint:true securityKey:false password:true raw:true", "addOptions: every method, a missing key off");
        assertEqual(options[1].note + " | " + options[0].note,
                    "No key registered — it needs pam_u2f and a registered key. From this system's packages: pam_u2f, for security keys. | A finger is enrolled",
                    "… with its reason and what it needs: the system not known, the neutral hint");
        const archFacts = { label: "Arch Linux", packages: { fprintd: { package: "fprintd" }, pamU2f: { package: "pam-u2f" } } };
        assertEqual(rules.addOptions({ fingerprint: "absent", securityKey: "absent" }, archFacts).slice(0, 2).map(option => option.note).join(" | "),
                    "No finger enrolled — it needs fprintd and an enrolled finger. On Arch Linux: the package fprintd. | "
                    + "No key registered — it needs pam_u2f and a registered key. On Arch Linux: the package pam-u2f.",
                    "… on Arch: the package names, as the lock's switches say them");
        assertEqual(options[2].note + " | " + options[3].note, "Only the password, without the system's other rules | Any PAM line, as written — not checked",
                    "… the password and a raw line explained");
        assertEqual(rules.addOptions({}).find(option => option.method === "fingerprint").note, "Not known whether a finger is enrolled",
                    "… a reader not known: off, said so");
        const start = [fingerprint("r1"), fixed];
        const outcome = rules.added(start, "password", facts);
        assertEqual(ids(outcome.rows) + " " + outcome.id, "r1,r2,system r2", "added: above the fixed row, its id");
        assertEqual(outcome.rows[1].control, "sufficient", "… sufficient");
        assertEqual(ids(rules.added([fingerprint("r1")], "raw", facts).rows), "r1,r2", "… last in a list without the fixed row");
        assertEqual(rules.added(start, "securityKey", facts), null, "… a method the machine lacks: none");
        assertEqual(rules.added(start, "system", facts), null, "… the fixed row: none");

        // --- dragging ---
        const three = [fingerprint("r1"), password("r2"), fixed];
        const middles = [10, 50, 90];
        assertEqual([5, 30, 70, 200].map(y => rules.dropSlot(three, middles, y)).join(" "), "0 1 2 2", "dropSlot: before the row below the pointer, never below the fixed row");
        assertEqual(rules.dropSlot([fingerprint("r1"), password("r2")], [10, 50], 200), 2, "… a list without it: after the last");
        assertEqual(rules.dropSlot(three, [], 5), 2, "… no rows measured: above the fixed row");
        assertEqual(rules.dropSlot(three, middles, 50), 2, "… on a row's middle: after it");
        assertEqual(rules.dropSlot([fixed], [10], 200), 0, "… the fixed row first: before it");
        assert(rules.dropLineAt(0, 2, 2), "dropLineAt: the first row dragged down");
        assertEqual([rules.dropLineAt(1, 0, 0), rules.dropLineAt(1, 1, 1), rules.dropLineAt(1, 2, 2), rules.dropLineAt(-1, 0, 0), rules.dropLineAt(1, 0, 1)].join(" "),
                    "true false false false false", "dropLineAt: only where the row would move to");
        assertEqual(ids(rules.dropped(three, 1, 0)), "r2,r1,system", "dropped: moved up");
        assertEqual(ids(rules.dropped(three, 0, 2)), "r2,r1,system", "… moved down, before the fixed row");
        assertEqual(ids(rules.dropped(three, 0, 3)), "r2,r1,system", "… a slot below the fixed row: kept above it");
        assertEqual(ids(rules.dropped(three, 0, 0)) + " " + ids(rules.dropped(three, 0, 1)), "null null", "… its own place: nothing");
        assertEqual(ids(rules.dropped(three, 2, 0)), "null", "… the fixed row: nothing");
        assertEqual(ids(rules.dropped([fingerprint("r1"), fixed], 0, 2)), "null", "… a slot that comes back to its place: nothing");
        assertEqual(ids(rules.dropped(three, -1, 0)) + " " + ids(rules.dropped(three, 1, -1)), "null null", "… no row or no slot: nothing");

        // --- the fixed row's question ---
        const question = rules.removeFixedQuestion("sudo", three, facts);
        assertEqual(question.kind + " " + question.buttons.map(button => button.id + "/" + button.kind).join(",") + " " + JSON.stringify(question.subject),
                    "danger remove/delete {\"list\":\"sudo\",\"id\":\"system\"}", "removeFixedQuestion: danger, Remove, keyed to the fixed row");
        assertEqual(question.body.length, 2, "… a password row left: what goes with it");
        assert(question.body[0].startsWith("sudo will no longer"), "… names the list");
        assertEqual(rules.removeFixedQuestion("sudo", [fingerprint("r1"), fixed], facts).body.length, 3, "… none left: says it closes");
        assertEqual(rules.removeFixedQuestion("sudo", [raw("x", "auth sufficient pam_unix.so"), fixed], facts).body.length, 2,
                    "… a raw pam_unix line asks the password too");
    }

    function _run() {
        rows = [{ id: "r1", method: "fingerprint", control: "sufficient", details: { timeout: 10, tries: 3 } },
                { id: "r2", method: "password", control: "sufficient", details: { counted: false } },
                PamRuleRules.fixedRow()];
        _window.visible = true;
        assert(_until(() => _window.visible && area.width > 0 && host.Window.active && driver.waitShown()), "the window shows and has the keyboard");
        assert(_until(() => _item("row:system") !== null && _item("row:system").height > 0), "the rows drawn");
        assertEqual(_chips("r1"), "10 s,3 tries,Not counted", "a row's chips");
        assertEqual(_chips("system"), "Counts: 3 wrong in 15 min lock 10 min", "… the fixed row's");
        assert(!_item("handle:system").enabled && _item("handle:r1").enabled, "the fixed row's handle does not move it");

        // --- a row opened, a word picked ---
        assert(!_item("word:r1/sufficient")?.visible, "closed: no control words");
        assert(_click("arrow:r1"), "the arrow clicked");
        assert(_until(() => _item("word:r1/sufficient")?.visible === true), "… the row opens: its words");
        assert(_item("word:r1/optional") === null, "… no optional for a fingerprint");
        assertEqual(_item("explanation:r1").text, PamRuleRules.explanation("sufficient"), "… the picked word explained");
        assert(_click("word:r1/requisite"), "requisite clicked");
        assert(_until(() => rows[0].control === "requisite"), "… the row's word changes");
        assertEqual(_item("explanation:r1").text, PamRuleRules.explanation("requisite"), "… its explanation shown");
        assert(_item("word:r1/requisite").picked && !_item("word:r1/sufficient").picked, "… picked");

        // --- a field edited ---
        const timeout = _item("field:r1/timeout");
        assert(timeout?.visible === true, "the timeout field");
        _settle(timeout);
        driver.mouseClick(timeout, timeout.width / 2, timeout.height / 2);
        assert(_until(() => timeout.editing), "… focused");
        driver.keyClick(Qt.Key_A, Qt.ControlModifier);
        driver.keyClick(Qt.Key_2);
        driver.keyClick(Qt.Key_5);
        driver.keyClick(Qt.Key_Return);
        assert(_until(() => rows[0].details.timeout === 25), "… a number typed: the row's timeout");
        assert(_until(() => _chips("r1") === "25 s,3 tries,Not counted"), "… its chip");

        // --- no limit ---
        assert(_click("noLimit:r1/tries", 5), "No limit clicked");
        assert(_until(() => rows[0].details.tries === -1), "… unlimited tries");
        assert(_until(() => _chips("r1") === "25 s,unlimited tries,Not counted"), "… the chip says so");
        assert(!_item("field:r1/tries").enabled, "… the field off");
        assert(_click("noLimit:r1/tries", 5), "No limit clicked again");
        assert(_until(() => rows[0].details.tries === 3), "… the number back");
        assert(_item("field:r1/tries").enabled, "… the field on");

        // --- a row added ---
        assert(_click("addRow"), "Add a row clicked");
        assert(_until(() => list.addOpen && _item("add:password")?.visible === true), "… the methods listed");
        const icons = ["fingerprint", "securityKey", "password", "raw"].map(method => _find(_item("add:" + method), "addTexts"));
        assert(icons.every(texts => texts && Math.abs(texts.mapToItem(area, 0, 0).x - icons[0].mapToItem(area, 0, 0).x) < 0.5),
               "… their texts aligned, past one icon column");
        assert(_item("add:securityKey").opacity < 1, "… the key off");
        const before = edits;
        assert(_click("add:securityKey"), "the key clicked");
        driver.wait(50);
        assertEqual(edits + " " + list.addOpen, before + " true", "… nothing added, the list stays");
        assert(_click("add:password"), "Password clicked");
        assert(_until(() => _ids() === "r1,r2,r3,system"), "… added above the fixed row");
        assert(_until(() => _item("word:r3/sufficient")?.visible === true && _item("word:r3/sufficient").picked), "… opened, sufficient picked");
        assert(!list.addOpen, "… the methods closed");

        // --- a row deleted, after its question ---
        assert(_click("remove:r3", 4), "its × clicked");
        assert(_until(() => _item("remove:r3").asking), "… it asks");
        assertEqual(_ids(), "r1,r2,r3,system", "… nothing deleted yet");
        assert(_click("remove:r3", 4), "… clicked again");
        assert(_until(() => _ids() === "r1,r2,system"), "… deleted");

        // --- the fixed row: asked in the modal ---
        assert(_click("remove:system"), "the fixed row's × clicked");
        assert(_until(() => host.open && host.modal.visible), "… the Settings modal asks");
        assertEqual(_find(host.modal, "modalTitle").text, "Remove the system's password?", "… its question");
        assert(_click("modalButton:1"), "… cancelled");
        assert(_until(() => !host.open), "… closed");
        assertEqual(_ids(), "r1,r2,system", "… kept");
        assert(_click("remove:system"), "asked again");
        assert(_until(() => host.open && host.modal.visible && _find(host.modal, "modalButton:0")?.width > 0), "… open");
        // The owner reorders the rows while the question is open: the answer acts on the fixed
        // row by its id, on the list as it is now
        const moved = rows.slice();
        rows = [moved[1], moved[0], moved[2]];
        assert(_until(() => _ids() === "r2,r1,system"), "(the rows reordered meanwhile)");
        assert(_click("modalButton:0"), "… Remove");
        assert(_until(() => _ids() === "r2,r1"), "… the fixed row gone, the new order kept");
        rows = [rows[1], rows[0], PamRuleRules.fixedRow()];
        assert(_until(() => _item("row:system") !== null && _ids() === "r1,r2,system"), "(put back)");

        // --- dragging ---
        // The page scrolled part way: a drag that the page took would move it either way
        page.contentY = 100;
        _settle(_item("row:r1"));
        const firstTop = _item("row:r1").mapToItem(area, 0, 0).y;
        let heldInteractive = null, heldDragging = null, heldLine = null;
        _drag("r2", firstTop + 4, () => {
            heldInteractive = page.interactive;
            heldDragging = list.dragging;
            heldLine = _item("dropLine:0").visible;
        });
        assertEqual(heldInteractive + " " + heldDragging + " " + heldLine, "false true true", "held: the page does not scroll, the line shows where it drops");
        assert(_until(() => _ids() === "r2,r1,system"), "the password dragged above the fingerprint");
        assertEqual(page.contentY + " " + page.interactive + " " + list.dragging, "100 true false", "… the page did not scroll and scrolls again");
        _settle(_item("row:system"));
        const fixedBottom = _item("row:system").mapToItem(area, 0, _item("row:system").height).y;
        _drag("r2", fixedBottom + 40);
        assert(_until(() => _ids() === "r1,r2,system"), "dragged below the fixed row: it stays above it");
        assertEqual(page.contentY, 100, "… the page did not scroll");
        _drag("system", firstTop - 10);
        driver.wait(30);
        assertEqual(_ids(), "r1,r2,system", "the fixed row's lock does not drag it");

        // A row removed while its handle is held: the drag ends, the page scrolls again, the
        // release drops nothing
        page.contentY = 100;
        const handle = _item("handle:r2");
        _settle(handle);
        const at = handle.mapToItem(area, handle.width / 2, handle.height / 2);
        driver.mousePress(area, at.x, at.y);
        driver.mouseMove(area, at.x, at.y - 20);
        assert(_until(() => list.dragging && !page.interactive), "(held)");
        const editsHeld = edits;
        rows = [rows[0], rows[2]];
        assert(_until(() => !list.dragging && page.interactive), "the held row removed: the drag ends, the page scrolls again");
        driver.mouseRelease(area, at.x, at.y - 40);
        driver.wait(30);
        assertEqual(_ids() + " " + edits, "r1,system " + editsHeld, "… the release changes nothing");

        // --- the key's PIN, the counted password, a raw line ---
        const long = "auth sufficient pam_ldap.so " + "x".repeat(600);
        rows = [{ id: "k1", method: "securityKey", control: "sufficient", details: { pin: false, cue: true } },
                { id: "p1", method: "password", control: "sufficient", details: { counted: false } },
                { id: "x1", method: "raw", control: "", details: { text: long } },
                PamRuleRules.fixedRow()];
        assert(_until(() => _item("row:x1") !== null), "(rows with a key, a password and a raw line)");
        assert(list.openIds.r1 === undefined && list.openIds.r3 === undefined, "rows gone from the list: no longer remembered open");
        assert(_click("arrow:k1") && _until(() => _item("pin:k1")?.visible === true), "the key opened: its PIN box");
        assert(_click("pin:k1", 5), "… clicked");
        assert(_until(() => rows[0].details.pin === true && _chips("k1") === "PIN,Not counted"), "… the PIN asked, its chip");
        assert(_click("arrow:p1") && _until(() => _item("counted:p1")?.visible === true), "the password opened: its switch");
        assert(_click("counted:p1"), "… clicked");
        assert(_until(() => rows[1].details.counted === true && _chips("p1") === "Counted"), "… failures count, its chip");
        assert(_click("arrow:x1") && _until(() => _item("line:x1")?.visible === true), "the raw line opened: its field");
        const line = _item("line:x1");
        assertEqual(line.text.length, long.length, "… the whole line, not cut");
        assert(_item("reading:x1").text.length > 0 && Qt.colorEqual(_item("reading:x1").color, Theme.error), "… read as a problem (too long)");
        const editsBefore = edits;
        _settle(line);
        driver.mouseClick(line, line.width / 2, line.height / 2);
        assert(_until(() => line.editing), "… focused");
        driver.keyClick(Qt.Key_Tab);
        assert(_until(() => !line.editing), "… left");
        driver.wait(30);
        assertEqual(edits + " " + rows[2].details.text.length, editsBefore + " " + long.length, "… focus in and out: nothing written");
        driver.mouseClick(line, line.width / 2, line.height / 2);
        assert(_until(() => line.editing), "… focused again");
        driver.keyClick(Qt.Key_A, Qt.ControlModifier);
        driver.keyClick(Qt.Key_X);
        driver.keyClick(Qt.Key_Return);
        assert(_until(() => rows[2].details.text === "x"), "… a line typed: the row's text");
    }
}
