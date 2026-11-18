import QtQuick
import QtQuick.Layouts
import QtTest as QT
import Quickshell
import Quickshell.Wayland
import qs.api as Public
import qs.components
import qs.singletons

// The public elements (qs.api), pinned. For each: its public property and signal names —
// a change to a list written here is a module API version change —; each kind and size
// reaching the internal value it stands for, read from the item inside, so a wrong
// mapping fails; the element in a RowLayout and a ColumnLayout with the internal one's
// geometry, stretched and hidden; a label with markup in it shown as written. The words
// alone: ApiElementRules, checked here too.
//
// Opens a small window in a corner of the screen for a moment (a layer surface, so it
// moves no windows).
TestCase {
    id: root
    suiteName: "ApiElements"
    asynchronous: true

    // What a module can rely on, per element: properties and signals, sorted
    readonly property var pinned: ({
        "SmallButton": ["asked", "asking", "available", "cancelTip", "checked", "clicked", "confirm", "confirmLabel", "kind", "label", "size", "tooltip"]
    })

    // The public button's kinds and sizes, and what each is inside
    readonly property var kinds: [
        { kind: "primary", inside: "save" },
        { kind: "secondary", inside: "normal" },
        { kind: "danger", inside: "delete" },
        { kind: "warning", inside: "warning" },
        { kind: "success", inside: "success" }
    ]
    readonly property var sizes: [
        { size: "xs", inside: "fontSizeXSmall" },
        { size: "s", inside: "fontSizeSmall" },
        { size: "m", inside: "fontSizeBody" }
    ]

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 700
        implicitHeight: 320
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Item { id: bare }

        // Somewhere for the mouse to go that is no button
        Item {
            id: away
            x: 640; y: 280
            width: 40; height: 40
        }

        Row {
            x: 10; y: 10
            spacing: 20

            Public.SmallButton {
                id: plain
                property int clicks: 0
                property int questions: 0
                label: "Plain"
                onClicked: clicks++
                onAsked: questions++
            }
            Public.SmallButton {
                id: danger
                property int clicks: 0
                property int questions: 0
                label: "Stop"
                kind: "danger"
                onClicked: clicks++
                onAsked: questions++
            }
            Public.SmallButton {
                id: asks
                property int clicks: 0
                property int questions: 0
                label: "Remove"
                kind: "danger"
                confirm: true
                onClicked: clicks++
                onAsked: questions++
            }
            Public.SmallButton {
                id: asksInWords
                label: "Turn on"
                kind: "primary"
                confirm: true
                confirmLabel: "Really <b>on</b>?"
                cancelTip: "Leave it off"
            }
            Public.SmallButton {
                id: unavailable
                property int clicks: 0
                label: "Not now"
                available: false
                onClicked: clicks++
            }
            Public.SmallButton {
                id: marked
                label: "<b>x</b>"
            }
        }

        Row {
            x: 10; y: 60
            spacing: 20

            Public.SmallButton { id: checkedButton; label: "On"; checked: true; tooltip: "A tip" }
            Public.SmallButton { id: mistyped; label: "Typo"; kind: "primry"; size: "huge" }
            Public.SmallButton { id: mistypedAgain; label: "Typo"; kind: "primry"; size: "huge" }
            Public.SmallButton { id: reserved; label: "Typo"; kind: "toString"; size: "constructor" }
            Public.SmallButton { id: varied; label: "Varied" }
            Public.SmallButton { id: narrow; label: "A label much longer than its button"; width: 80 }
            Public.SmallButton { id: asksWithTip; label: "Tip"; confirm: true; tooltip: "Another tip" }
        }

        // The public button and the internal one, in the same layouts
        RowLayout {
            id: publicRow
            x: 10; y: 110
            width: 400
            spacing: 6
            Public.SmallButton { label: "First"; kind: "primary" }
            Public.SmallButton { label: "Hidden"; visible: false }
            Public.SmallButton { label: "Stretched"; Layout.fillWidth: true }
            Public.SmallButton { label: "Last"; size: "s" }
        }
        RowLayout {
            id: internalRow
            x: 10; y: 150
            width: 400
            spacing: 6
            SmallButton { label: "First"; kind: "save" }
            SmallButton { label: "Hidden"; visible: false }
            SmallButton { label: "Stretched"; Layout.fillWidth: true }
            SmallButton { label: "Last"; fontSize: Theme.fontSizeSmall }
        }
        ColumnLayout {
            id: publicColumn
            x: 430; y: 110
            width: 200
            spacing: 6
            Public.SmallButton { label: "First"; kind: "primary" }
            Public.SmallButton { label: "Hidden"; visible: false }
            Public.SmallButton { label: "Stretched"; Layout.fillWidth: true }
            Public.SmallButton { label: "Asks"; kind: "danger"; confirm: true }
        }
        ColumnLayout {
            id: internalColumn
            x: 430; y: 210
            width: 200
            spacing: 6
            SmallButton { label: "First"; kind: "save" }
            SmallButton { label: "Hidden"; visible: false }
            SmallButton { label: "Stretched"; Layout.fillWidth: true }
            DeleteButton { label: "Asks"; fontSize: Theme.fontSizeBody }
        }

        QT.TestCase {
            id: driver
            name: "ApiElementsDriver"
            when: false
        }
    }

    // Waits for `condition`, at most `limitMs`; whether it came true
    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    function _child(item, typeName, nth = 0) {
        return Array.from(item.children).filter(child => child.toString().startsWith(typeName))[nth] ?? null;
    }

    // The internal button inside a public one
    function _inside(element) {
        return _child(element, "QQuickLoader").item;
    }

    // The parts of an internal button that asks: the button, its label, the "×"
    function _parts(asking) {
        const face = asking.children[0];
        return { face: face, label: _child(face, "QQuickText"), cancel: asking.children[1] };
    }

    // What an element adds to a plain Item: its properties and signals, without the
    // "…Changed" signal every property has
    function _names(element) {
        const plain = [];
        for (const name in bare)
            plain.push(name);
        const added = [];
        for (const name in element) {
            if (!plain.includes(name) && !(name.endsWith("Changed") && (name.slice(0, -7) in element)))
                added.push(name);
        }
        return added.sort();
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

    function _geometry(item) {
        return [item.x, item.y, item.width, item.height].join(" ");
    }

    function _items(layout) {
        return Array.from(layout.children);
    }

    function runAsync() {
        // --- the words ---
        const rules = ApiElementRules;
        for (const entry of kinds)
            assertEqual(JSON.stringify(rules.buttonKind(entry.kind)), JSON.stringify({ value: entry.inside, known: true }), "the kind " + entry.kind + " is " + entry.inside + " inside");
        assertEqual(Object.keys(rules.buttonKinds).sort().join(" "), kinds.map(entry => entry.kind).sort().join(" "), "and those are all a button's kinds");
        for (const entry of sizes)
            assertEqual(JSON.stringify(rules.textSize(entry.size)), JSON.stringify({ value: entry.inside, known: true }), "the size " + entry.size + " is the theme's " + entry.inside);
        assertEqual(Object.keys(rules.textSizes).sort().join(" "), sizes.map(entry => entry.size).sort().join(" "), "and those are all a button's sizes");
        for (const word of ["primry", "", "save", "delete", "normal", "toString", "__proto__", undefined, null, 3]) {
            assertEqual(JSON.stringify(rules.buttonKind(word)), JSON.stringify({ value: "normal", known: false }), "a kind " + JSON.stringify(word) + " is not one: the default, secondary");
            assertEqual(JSON.stringify(rules.textSize(word)), JSON.stringify({ value: "fontSizeBody", known: false }), "a size " + JSON.stringify(word) + " is not one: the default, m");
        }
        assertEqual(JSON.stringify(rules.textSize("l")), JSON.stringify({ value: "fontSizeBody", known: false }), "a button has no size l");
        const warning = rules.unknownWord("SmallButton", "kind", "prim\nry" + "x".repeat(100), "secondary");
        assert(!warning.message.includes("\n") && warning.message.length < 140, "the warning for an unknown word is one short line: " + warning.message);
        assert(warning.message.includes("SmallButton") && warning.message.includes("kind") && warning.message.includes("secondary"), "… naming the element, the property and what is shown");

        // --- the names ---
        assertEqual(JSON.stringify(_names(marked)), JSON.stringify(pinned.SmallButton), "SmallButton's public properties and signals are the pinned ones");
        assert(_names(_inside(plain)).includes("fontSize") && _names(_inside(plain)).includes("hovered"), "… the internal button's own are not among them (it has fontSize, hovered)");

        // --- beside qs.components, which has a SmallButton too ---
        const publicLast = Qt.createQmlObject("import QtQuick\nimport qs.components\nimport qs.api\nSmallButton {}", bare, "PublicLast.qml");
        const internalLast = Qt.createQmlObject("import QtQuick\nimport qs.api\nimport qs.components\nSmallButton {}", bare, "InternalLast.qml");
        assert("confirm" in publicLast && !("fontSize" in publicLast), "a file that imports qs.api last gets the public button");
        assert("fontSize" in internalLast && !("confirm" in internalLast), "one that imports qs.components last gets the internal one");
        publicLast.destroy();
        internalLast.destroy();

        // --- defaults ---
        assertEqual([plain.kind, plain.size, plain.confirm, plain.available, plain.checked, plain.asking, plain.tooltip, plain.cancelTip].join(" "),
            "secondary m false true false false  Cancel", "a button's defaults: secondary, m, does not ask, available");
        assertEqual(plain.confirmLabel, "Plain?", "the question is the label and \"?\" unless given");
        assertEqual(asksInWords.confirmLabel, "Really <b>on</b>?", "… or the one given");

        // --- each kind and size, read from the button inside ---
        for (const entry of kinds) {
            varied.kind = entry.kind;
            assertEqual(_inside(varied).kind, entry.inside, "a " + entry.kind + " button is " + entry.inside + " inside");
        }
        for (const entry of sizes) {
            varied.size = entry.size;
            assertEqual(_inside(varied).fontSize, Theme[entry.inside], "a button of size " + entry.size + " has the theme's " + entry.inside);
        }
        assert(Theme.fontSizeXSmall < Theme.fontSizeSmall && Theme.fontSizeSmall < Theme.fontSizeBody, "the three sizes differ in the theme");
        varied.confirm = true;
        for (const entry of kinds) {
            varied.kind = entry.kind;
            assertEqual(_inside(varied).kind, entry.inside, "a " + entry.kind + " button that asks is " + entry.inside + " inside");
        }
        for (const entry of sizes) {
            varied.size = entry.size;
            assertEqual(_inside(varied).fontSize, Theme[entry.inside], "a button of size " + entry.size + " that asks has the theme's " + entry.inside);
        }
        assert(_inside(varied).toString().startsWith("DeleteButton") && _inside(plain).toString().startsWith("SmallButton"),
            "a button that asks is the shell's asking button inside, another its plain one");

        // --- what is passed on ---
        assert(_inside(checkedButton).checked && !_inside(plain).checked, "checked reaches the button inside");
        assertEqual(_inside(checkedButton).tooltip, "A tip", "and so does the tooltip");
        assertEqual(_inside(asksWithTip).tooltip, "Another tip", "… of a button that asks too");
        assert(!_inside(unavailable).available && !_inside(unavailable).hovered, "and not available");
        assertEqual(_inside(asksInWords).cancelTip, "Leave it off", "the \"×\"'s tooltip reaches the button inside");

        // --- words it does not know ---
        assertEqual(_inside(mistyped).kind + " " + _inside(mistyped).fontSize, "normal " + Theme.fontSizeBody, "a kind and a size that do not exist show as secondary, m");
        assertEqual(_inside(reserved).kind + " " + _inside(reserved).fontSize, "normal " + Theme.fontSizeBody, "… words every object knows included");
        assertEqual(mistyped.kind, "primry", "the element keeps the word it was given");
        assertEqual(ApiElements.warned.filter(key => key.startsWith("SmallButton.") && key.includes("primry")).length, 1, "the kind is warned about once, for two buttons with it");
        assertEqual(ApiElements.warned.filter(key => key.startsWith("SmallButton.") && key.includes("huge")).length, 1, "and the size once");
        assert(!ApiElements.warned.some(key => key.includes("secondary") || key.includes("=m") || key.includes("danger")), "a word it knows is not warned about");
        const warnedBefore = ApiElements.warned.length;
        varied.kind = "later";
        varied.kind = "primary";
        varied.kind = "later";
        assertEqual(ApiElements.warned.length, warnedBefore + 1, "a word set later is warned about too, once");

        // --- clicks ---
        const inner = _inside(plain);
        assert(_until(() => {
            driver.mouseMove(away, 5, 5);
            driver.mouseMove(plain, 5, 5);
            return inner.hovered;
        }, 5000), "the window is shown and the pointer is seen over a public button");
        driver.mouseClick(plain, 5, 5);
        assertEqual(plain.clicks + " " + plain.questions, "1 0", "a click on a button acts");
        driver.mouseClick(danger, 5, 5);
        assertEqual(danger.clicks + " " + danger.questions + " " + danger.asking, "1 0 false", "a danger button that does not ask acts on the first click");
        driver.mouseClick(unavailable, 5, 5);
        assertEqual(unavailable.clicks, 0, "a button that is not available does nothing");

        const parts = _parts(_inside(asks));
        assertEqual(parts.label.text, "Remove", "a button that asks shows its label");
        driver.mouseClick(asks, 5, 5);
        assertEqual(asks.clicks + " " + asks.questions + " " + asks.asking, "0 1 true", "its first click asks: asked(), asking, nothing done");
        assertEqual(parts.label.text, "Remove?", "and it shows the question");
        assert(_until(() => asks.width === parts.face.width + parts.cancel.width) && parts.cancel.visible, "the element is as wide as the question and its \"×\"");
        driver.mouseClick(parts.cancel, 3, 3);
        assertEqual(asks.clicks + " " + asks.questions + " " + asks.asking, "0 1 false", "the \"×\" takes the question back");
        driver.mouseClick(asks, 5, 5);
        driver.mouseClick(asks, 5, 5);
        assertEqual(asks.clicks + " " + asks.questions + " " + asks.asking, "1 2 false", "a second click acts: clicked()");
        driver.mouseClick(asks, 5, 5);
        asks.asking = false;
        assertEqual(parts.label.text + " " + asks.clicks, "Remove 1", "the owner takes the question back with asking = false");
        asks.asking = true;
        assertEqual(parts.label.text + " " + asks.questions, "Remove? 3", "and may put it, without asked()");
        asks.confirm = false;
        assertEqual(asks.asking, false, "a button that no longer asks is not asking");
        driver.mouseClick(asks, 5, 5);
        assertEqual(asks.clicks + " " + asks.questions, "2 3", "and acts on one click, the same handler");
        plain.asking = true;
        assertEqual(plain.asking, false, "a button that does not ask cannot be asking");
        driver.mouseMove(away, 5, 5);

        // --- a label as written ---
        assert(_asWritten(_child(_inside(marked), "QQuickText")), "a label with markup in it is shown as written");
        const wordParts = _parts(_inside(asksInWords));
        driver.mouseClick(asksInWords, 5, 5);
        assert(wordParts.label.text === "Really <b>on</b>?" && _asWritten(wordParts.label), "and a question too");
        asksInWords.asking = false;
        driver.mouseMove(away, 5, 5);

        // --- in layouts, as the internal one ---
        for (const pair of [{ name: "a RowLayout", mine: publicRow, theirs: internalRow }, { name: "a ColumnLayout", mine: publicColumn, theirs: internalColumn }]) {
            const mine = _items(pair.mine);
            const theirs = _items(pair.theirs);
            assert(_until(() => mine[3].width > 0 && theirs[3].width > 0 && _geometry(mine[3]) === _geometry(theirs[3])), "in " + pair.name + " the layout is done");
            for (const i of [0, 2, 3])
                assertEqual(_geometry(mine[i]), _geometry(theirs[i]), "in " + pair.name + ", \"" + mine[i].label + "\" stands where the internal one does, as large");
            assertEqual(pair.mine.implicitWidth + " " + pair.mine.implicitHeight, pair.theirs.implicitWidth + " " + pair.theirs.implicitHeight,
                "in " + pair.name + ", the hidden one takes no room: the layout wants the internal one's size");
            const stretched = _inside(mine[2]);
            assert(mine[2].width > mine[2].implicitWidth, "in " + pair.name + ", the stretched one is wider than its label needs");
            assertEqual(stretched.width + " " + stretched.height, mine[2].width + " " + mine[2].height, "… and the button inside fills it");
            assertEqual(mine[0].width + " " + mine[0].height, _inside(mine[0]).width + " " + _inside(mine[0]).height, "… one not stretched is as large as the button inside");
            assertEqual(mine[0].implicitWidth + " " + mine[0].implicitHeight, theirs[0].implicitWidth + " " + theirs[0].implicitHeight, "… and wants the internal one's size");
        }

        // --- narrower than its label ---
        const narrowLabel = _child(_inside(narrow), "QQuickText");
        assert(narrow.width === 80 && _inside(narrow).width === 80 && narrowLabel.truncated, "a button made narrower than its label keeps that width and cuts the label");

        _window.visible = false;
        finish();
    }
}
