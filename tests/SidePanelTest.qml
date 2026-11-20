import QtQuick
import QtQuick.Layouts
import QtTest as QT
import Quickshell
import qs.api as Public
import qs.components
import qs.singletons

// The public SidePanel (module API 1.34) in the module page frame (components/
// ModulePageFrame.qml, the settings window's): its content built when it opens and
// destroyed once it has closed; each way it closes and the reason it gives — Close, a click
// beside it, Escape (a dropdown's list inside it first), another one opening, the session
// locking, the window hiding, the frame going —; the keyboard taken and given back; its
// width by size within the page; the title fixed over scrolled content; outside a frame it
// does not open. And the public headings with controls at the right end of their line.
//
// Opens a small window for a moment, an ordinary one that takes the keyboard (Escape is
// sent to it), in the runner's headless compositor.
TestCase {
    id: suite
    suiteName: "SidePanel"
    asynchronous: true

    // What the content built and destroyed, and the reasons given, in order
    property int built: 0
    property int destroyed: 0
    property var reasons: []
    property int toggles: 0

    // A window of its own that takes the keyboard, as the settings window does
    property var _window: FloatingWindow {
        title: "h2s-tests side panel"
        implicitWidth: 600
        implicitHeight: 400
        color: Theme.popupBackground

        Item {
            id: area
            anchors.fill: parent
        }

        // Not in a page frame: does not open
        Public.SidePanel {
            id: stray
            title: "Stray"
            Text { text: "never" }
        }

        // Headings with and without controls
        ColumnLayout {
            id: headings
            x: 0; y: 0
            width: 300
            visible: false
            Public.Heading {
                id: switchedHeading
                text: "Taildrop"
                Public.ToggleSwitch {
                    id: headingSwitch
                    onToggled: suite.toggles++
                }
            }
            Public.SectionTitle {
                id: switchedTitle
                text: "Files"
                Public.SmallButton { label: "Add" }
            }
            Public.Heading { id: plainHeading; text: "Plain" }
            Public.SectionTitle { id: plainTitle; text: "Plain" }
        }

        QT.TestCase {
            id: driver
            name: "SidePanelDriver"
            when: false
        }
    }

    // A module's page as it would be written: a field, a button, two panels
    property Component _pageComp: Component {
        ColumnLayout {
            property alias first: _first
            property alias second: _second
            property alias field: _field
            property alias opener: _opener
            spacing: 4

            Public.InputField { id: _field; Layout.fillWidth: true }
            Public.SmallButton { id: _opener; label: "Files…"; onClicked: _first.open = true }

            Public.SidePanel {
                id: _first
                title: "First\npanel"
                size: "l"
                onClosed: reason => suite.reasons = suite.reasons.concat(["first:" + reason])
                ColumnLayout {
                    objectName: "firstContent"
                    spacing: 4
                    Component.onCompleted: suite.built++
                    Component.onDestruction: suite.destroyed++
                    Public.Dropdown {
                        objectName: "choice"
                        options: [{ value: "a", label: "A" }, { value: "b", label: "B" }]
                        value: "a"
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 2000
                        color: Theme.surface
                    }
                }
            }
            Public.SidePanel {
                id: _second
                title: "Second"
                size: "s"
                onClosed: reason => suite.reasons = suite.reasons.concat(["second:" + reason])
                Text { objectName: "secondContent"; text: "Second" }
            }
        }
    }

    property var _frame: null
    property var _page: null

    // Waits for `condition`, at most `limitMs`; whether it came true
    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    function _makeFrame() {
        _frame = _frameComp.createObject(area, { width: 600, height: 400 });
        _page = _pageComp.createObject(_frame.body);
    }

    readonly property Component _frameComp: Component { ModulePageFrame {} }

    function _drawer() {
        return _frame.sidePanelHost.drawer;
    }

    function _settled() {
        const drawer = _drawer();
        const panel = drawer.panel;
        return drawer.open ? Math.abs(panel.x - (drawer.width - panel.width)) < 0.5 : !panel.visible;
    }

    function _lastReason() {
        return reasons[reasons.length - 1] ?? "";
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

    function _count(item, prefix) {
        if (!item)
            return 0;
        let total = item.toString().startsWith(prefix) ? 1 : 0;
        for (const child of item.children)
            total += _count(child, prefix);
        return total;
    }

    function _openFirst() {
        _page.first.open = true;
        return _until(() => _drawer().contentItem !== null && _settled());
    }

    function runAsync() {
        try {
            _run();
        } finally {
            // The window gone, whatever happened: the file chooser's suite takes the keyboard next
            _window.visible = false;
        }
        finish();
    }

    function _run() {
        assert(_until(() => _window.visible && area.width > 0), "the window shows");
        _makeFrame();

        // --- the rules ---
        const rules = ApiElementRules;
        const widths = { s: 320, m: 420, l: 520 };
        assertEqual(rules.sidePanelWidth("s", 1000, widths) + " " + rules.sidePanelWidth("m", 1000, widths) + " " + rules.sidePanelWidth("l", 1000, widths),
                    "320 420 520", "sidePanelWidth: each size's width on a wide page");
        assertEqual(rules.sidePanelWidth("l", 500, widths), 450, "… never wider than 90 % of the page");
        assertEqual(rules.sidePanelWidth("xl", 1000, widths) + " " + rules.sidePanelWidth(undefined, 1000, widths), "420 420", "… a size it does not have: m");
        assertEqual(rules.sidePanelWidth("m", 0, widths) + " " + rules.sidePanelWidth("m", NaN, null), "0 0", "… no page, no widths: 0");
        assertEqual(JSON.stringify(rules.sidePanelSize("l")), JSON.stringify({ value: "l", known: true }), "sidePanelSize: l known");
        assertEqual(JSON.stringify(rules.sidePanelSize("xs")), JSON.stringify({ value: "m", known: false }), "… xs not one: m");
        const events = { closeButton: "close", outsideClick: "outside", escape: "escape", otherOpened: "replaced", pageGone: "page", locked: "lock" };
        for (const event of Object.keys(events))
            assertEqual(JSON.stringify(rules.sidePanelEvent(true, event, false)), JSON.stringify({ close: true, reason: events[event], closeList: false }),
                        "sidePanelEvent: " + event + " closes it, \"" + events[event] + "\"");
        assertEqual(Object.keys(rules.sidePanelReasons).sort().join(" "), Object.keys(events).sort().join(" "), "… and those are all its events");
        assertEqual(JSON.stringify(rules.sidePanelEvent(true, "escape", true)), JSON.stringify({ close: false, reason: "", closeList: true }), "… Escape with a list open: the list first");
        assertEqual(rules.sidePanelEvent(true, "closeButton", true).reason, "close", "… Close with a list open: closes all the same");
        for (const [open, event] of [[false, "escape"], [true, "toString"], [true, "__proto__"], [true, undefined]])
            assertEqual(rules.sidePanelEvent(open, event, false).close, false, "… " + JSON.stringify(event) + (open ? "" : " while closed") + ": nothing");
        assertEqual(rules.sidePanelRefusal(true, false), "", "sidePanelRefusal: in a frame, unlocked: opens");
        assert(rules.sidePanelRefusal(false, false) !== "" && rules.sidePanelRefusal(true, true) !== "", "… no frame, or locked: refused");
        const oddSizes = [0, 1].map(() => Qt.createQmlObject("import qs.api\nSidePanel { size: \"xl\" }", area, "OddSize.qml"));
        assertEqual(ApiElements.warned.filter(key => key === "SidePanel.size=xl").length, 1, "a size it does not have: logged once, however many panels carry it");
        assert(!ApiElements.warned.some(key => /^SidePanel\.size=(s|m|l)$/.test(key)), "… a size it has is not logged");
        oddSizes.forEach(panel => panel.destroy());
        assertEqual(JSON.stringify(Theme.sidePanelWidths), JSON.stringify({ s: Theme.scaled(320), m: Theme.scaled(420), l: Theme.scaled(520) }), "the theme's widths, grown with the text");

        // --- outside a page frame ---
        stray.open = true;
        assertEqual(stray.open, false, "a SidePanel outside a page frame: open goes back to false");
        assert(ApiElements.warned.includes("SidePanel.open:not on a module's settings page"), "… logged");
        stray.open = true;
        assertEqual(ApiElements.warned.filter(key => key.startsWith("SidePanel.open:")).length, 1, "… once");

        // --- opening: content built, the keyboard taken ---
        assert(_until(() => _frame.Window.active), "the window has the keyboard");
        _page.field.forceActiveFocus();
        const fieldFocused = () => _frame.Window.activeFocusItem !== null && _frame.Window.activeFocusItem !== _drawer().panel
            && !_drawer()._isInside(_frame.Window.activeFocusItem);
        assert(fieldFocused(), "a field on the page has the keyboard");
        assertEqual(built, 0, "nothing of the content exists while closed");
        assert(_openFirst(), "open: the panel slides in, its content built");
        assertEqual(built, 1, "… built once");
        const drawer = _drawer();
        assertEqual(drawer.panel.width, Math.min(Theme.sidePanelWidths.l, Math.floor(600 * 0.9)), "size l: the theme's width, within the page");
        assertEqual(drawer.contentItem.width, drawer.panel.width - 2 * Theme.settings.pageMargin, "the content laid out at the panel's inner width");
        assert(_find(drawer.panel, "firstContent") !== null, "the content is in the panel");
        assert(drawer._isInside(_frame.Window.activeFocusItem), "the panel took the keyboard");
        const titleText = Array.from(drawer.panel.children).find(child => child.toString().startsWith("QQuickRowLayout"));
        assertEqual(titleText.children[0].text, "First panel", "the title on one line, as written");
        assertEqual(_count(drawer, "QQuickRepeater"), 0, "no Repeater in the panel and its frame");

        // --- tall content scrolls below the fixed title ---
        const scroller = Array.from(drawer.panel.children).find(child => child.toString().startsWith("QQuickFlickable"));
        assert(scroller.contentHeight > scroller.height, "content taller than the panel: it scrolls");
        const titleY = titleText.mapToItem(drawer, 0, 0).y;
        scroller.contentY = 600;
        assert(_until(() => drawer.contentItem.mapToItem(drawer, 0, 0).y < 0), "scrolled: the content moved up");
        assertEqual(titleText.mapToItem(drawer, 0, 0).y, titleY, "… the title stayed");
        scroller.contentY = 0;

        // --- Close ---
        const closeButton = titleText.children[1];
        driver.mouseClick(closeButton, 5, 5);
        assertEqual(_lastReason(), "first:close", "Close: closed(\"close\")");
        assertEqual(_page.first.open, false, "… open set false by the panel");
        assert(_until(() => _settled() && drawer.contentItem === null && destroyed === 1), "… slid out, its content destroyed");
        assert(_until(fieldFocused), "… the keyboard given back to the field");

        // --- a click beside it ---
        assert(_openFirst(), "opened again");
        assertEqual(built, 2, "… the content built anew");
        driver.mouseClick(area, 20, 200);
        assertEqual(_lastReason(), "first:outside", "a click on the dimmed page: closed(\"outside\")");
        assert(_until(() => _settled() && destroyed === 2), "… content destroyed");

        // --- the page under the dim takes no click ---
        let pageClicks = 0;
        const counter = () => pageClicks++;
        _page.opener.clicked.connect(counter);
        assert(_openFirst(), "opened again");
        // The opener sits under the dim: its click closes the panel, the button gets nothing
        driver.mouseClick(_page.opener, 5, 5);
        assertEqual(pageClicks, 0, "a click on a button under the dim does not reach it");
        assertEqual(_lastReason(), "first:outside", "… it closes the panel");
        _page.opener.clicked.disconnect(counter);
        assert(_until(_settled), "… slid out");

        // --- Escape, a dropdown's list first ---
        assert(_openFirst(), "opened again");
        driver.keyClick(Qt.Key_Escape);
        assertEqual(_lastReason(), "first:escape", "Escape: closed(\"escape\")");
        assert(_until(_settled), "… slid out");
        assert(_openFirst(), "opened again");
        const choice = _find(drawer.contentItem, "choice");
        driver.mouseClick(choice, 10, 5);
        const inner = Array.from(choice.children).find(child => "open" in child);
        assert(_until(() => inner.open), "a dropdown in the panel opens its list");
        const list = Array.from(_frame.Window.contentItem.children).find(child => child.floatingList === true && child.anchorItem === inner);
        assert(list && list.visible && list.z > 0, "… its list over the panel");
        driver.keyClick(Qt.Key_Escape);
        assert(_until(() => !inner.open), "Escape: the list closes first");
        assertEqual(_page.first.open, true, "… the panel stays");
        driver.keyClick(Qt.Key_Escape);
        assertEqual(_lastReason(), "first:escape", "Escape again: the panel closes");
        assert(_until(_settled), "… slid out");

        // --- another panel opening ---
        assert(_openFirst(), "the first open");
        _page.second.open = true;
        assertEqual(_lastReason(), "first:replaced", "the second opened: the first closed(\"replaced\")");
        assertEqual(_page.first.open + " " + _page.second.open, "false true", "… the second open");
        assert(_until(() => _find(drawer.contentItem, "secondContent") === drawer.contentItem && _settled()), "… the panel shows the second's content");
        assert(_until(() => destroyed === built && built === 6), "… the first's content destroyed (" + built + " built, " + destroyed + " destroyed)");
        assertEqual(drawer.panel.width, Math.min(Theme.sidePanelWidths.s, 540), "… at size s");

        // --- a lock ---
        Profiles.screenLocked = true;
        assertEqual(_lastReason(), "second:lock", "the session locked: closed(\"lock\")");
        _page.first.open = true;
        assertEqual(_page.first.open, false, "while locked a panel does not open");
        Profiles.screenLocked = false;
        assert(_until(_settled), "… slid out");

        // --- the owner closing it ---
        const before = reasons.length;
        assert(_openFirst(), "opened again");
        _page.first.open = false;
        assert(_until(() => _settled() && drawer.contentItem === null), "the owner sets open false: it closes");
        assertEqual(reasons.length, before, "… without a reason");

        // --- the window hiding ---
        assert(_openFirst(), "opened again");
        _window.visible = false;
        assertEqual(_lastReason(), "first:page", "the window hidden: closed(\"page\")");
        _window.visible = true;
        assert(_until(() => _window.visible && _settled()), "the window again, the panel closed");

        // --- the frame going ---
        assert(_until(() => _frame.Window.active) && _openFirst(), "opened again");
        const builtBefore = built;
        _frame.destroy();
        assert(_until(() => _lastReason() === "first:page"), "the frame destroyed: closed(\"page\")");
        assert(_until(() => destroyed === builtBefore), "… its content gone with it");
        _makeFrame();

        // --- a panel destroyed while open (its page or module going) ---
        assert(_openFirst(), "a new frame: opened");
        const builtThen = built;
        _page.destroy();
        assert(_until(() => _lastReason() === "first:page"), "its page destroyed: closed(\"page\")");
        assert(_until(() => !_drawer().open && _drawer().contentItem === null && destroyed === builtThen), "… the panel closed, its content gone at once");
        _frame.destroy();

        // --- headings with controls ---
        headings.visible = true;
        assert(_until(() => headingSwitch.width > 0 && switchedHeading.width === 300), "a heading with a switch fills the width");
        const switchRight = headingSwitch.mapToItem(switchedHeading, headingSwitch.width, 0).x;
        assertEqual(switchRight, switchedHeading.width, "… the switch at the right end of its line");
        const switchMiddle = headingSwitch.mapToItem(switchedHeading, 0, headingSwitch.height / 2).y;
        assert(Math.abs(switchMiddle - switchedHeading.height / 2) < 1, "… centred on it");
        assert(switchedHeading.height >= headingSwitch.height, "… the line as tall as the switch");
        driver.mouseClick(headingSwitch, headingSwitch.width / 2, headingSwitch.height / 2);
        assertEqual(toggles, 1, "… and takes its click");
        assertEqual(switchedTitle.width, 300, "a section title with a button fills the width too");
        assertEqual((Math.abs(plainHeading.width - plainHeading.contentWidth) < 1) + " " + plainHeading.rightPadding + " " + plainHeading.topPadding, "true 0 0",
                    "a heading without children: as it was (its text's width, no padding)");
        assertEqual((Math.abs(plainTitle.width - plainTitle.contentWidth) < 1) + " " + plainTitle.rightPadding + " " + plainTitle.Layout.fillWidth, "true 0 false",
                    "a section title without children: as it was");
        headings.visible = false;
    }
}
