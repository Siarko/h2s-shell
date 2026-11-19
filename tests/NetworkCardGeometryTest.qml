import QtQuick
import QtQuick.Layouts
import QtTest as QT
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.panels.settings
import qs.singletons

// panels/settings/NetworkProfileCard.qml laid out in a window as each of its four uses —
// a Wi-Fi network, a wired profile, a hotspot, a VPN provider's entry —, closed and open:
// where its named parts stand. The positions follow from the card's layout (margins 8, 6
// between lines, the buttons in one row on the name's line, closed and open, 6 apart and
// centred on it, the lock 10 left of the primary button, the arrow at the right) and from
// the sizes of the parts themselves, so they hold whatever the fonts; each card's numbers
// are also printed ("geometry: …"), for comparing two versions of the card on one machine.
// The card's wiring: the name is the profile's, one in use bold with the accent's border, the
// notice's button waiting while busy; the shared card's buttons centred on the row, one that
// names a vertical alignment of its own keeping it. Then the header: a click asks to toggle, the
// pointer over it tints the card.
TestCase {
    id: suite
    suiteName: "NetworkCardGeometry"
    asynchronous: true

    readonly property int cardWidth: 380

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 2 * suite.cardWidth + 30
        implicitHeight: 900
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Grid {
            x: 10
            y: 10
            columns: 2
            spacing: 10

            // A saved Wi-Fi network in range, not connected, with a row of the page's
            NetworkProfileCard {
                id: wifiCard
                width: suite.cardWidth
                busy: false
                profile: ({ uuid: "w", name: "Home", active: false, autoconnect: true, priority: 2, device: "" })
                title: "Home"
                subtitle: "In range · 70 % · WPA2 Personal · Last used 2 h ago"
                useDevice: "wlan0"
                autoconnectHint: "When in range"
                priorityHint: "Higher wins when several are in range"
                Rectangle {
                    objectName: "pageRow"
                    Layout.fillWidth: true
                    implicitHeight: 30
                    color: "transparent"
                }
            }

            // A wired profile in use
            NetworkProfileCard {
                id: wiredCard
                width: suite.cardWidth
                busy: false
                profile: ({ uuid: "e", name: "Wired", active: true, autoconnect: true, priority: 0, device: "eth0" })
                subtitle: "In use on eth0"
                useDevice: "eth0"
                useLabel: "Use"
                autoconnectHint: "When a cable is plugged in"
            }

            // A hotspot that asks before it turns on
            NetworkProfileCard {
                id: hotspotCard
                width: suite.cardWidth
                busy: false
                profile: ({ uuid: "h", name: "Spot", active: false, autoconnect: false, priority: 0, device: "" })
                title: "Spot"
                subtitle: "Off · WPA2 Personal · 5 GHz"
                useDevice: "wlan0"
                useLabel: "Turn on"
                stopLabel: "Turn off"
                stopsProfile: true
                useQuestion: "Turn on? The Wi-Fi drops"
                autoconnectLabel: "Start automatically"
                autoconnectHint: "When the computer starts"
                showPriority: false
                editTooltip: "Name, password, band, and the addresses handed out"
                // A row of the page's that is hidden (an open hotspot's password): no room
                Rectangle {
                    objectName: "hiddenPageRow"
                    visible: false
                    Layout.fillWidth: true
                    implicitHeight: 30
                }
            }

            // A VPN provider's entry, connected: its page's "Settings…", a notice with its
            // action, the lock beside the primary button, a row of the page's
            NetworkProfileCard {
                id: providerCard
                width: suite.cardWidth
                busy: false
                profile: ({ uuid: "p", name: "Provider", active: true, autoconnect: false, priority: 0, device: "" })
                subtitle: "Provider · Connected · Via exit-1"
                usable: true
                stopsProfile: true
                showAutoconnect: false
                showPriority: false
                external: true
                hasSettings: true
                need: "auth"
                notice: "Log in to continue"
                noticeAction: "Log in"
                Rectangle {
                    objectName: "pageRow"
                    Layout.fillWidth: true
                    implicitHeight: 30
                    color: "transparent"
                }
            }

            // The shared card with buttons, one naming a vertical alignment of its own
            SettingsCard {
                id: alignedCard
                width: suite.cardWidth
                title: "Aligned"
                primary: SmallButton { objectName: "alignedPrimary"; label: "Go" }
                buttons: [
                    SmallButton { objectName: "alignedTop"; label: "Top"; Layout.alignment: Qt.AlignTop },
                    SmallButton { objectName: "alignedPlain"; label: "Plain" }
                ]
            }
        }
    }

    property var _driver: QT.TestCase {
        name: "NetworkCardGeometryDriver"
        when: false
    }

    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            _driver.wait(10);
        return condition();
    }

    // The first shown item under `item` (itself included) that `test` accepts, depth first
    function _find(item, test) {
        if (!item || !item.visible)
            return null;
        if (test(item))
            return item;
        for (const child of item.children ?? []) {
            const found = _find(child, test);
            if (found)
                return found;
        }
        return null;
    }

    function _round(value) {
        return Math.round(value * 100) / 100;
    }

    // Where `item` stands in `card`, or null for no item
    function _rect(card, item) {
        if (!item)
            return null;
        const corner = item.mapToItem(card, 0, 0);
        return { x: _round(corner.x), y: _round(corner.y), width: _round(item.width), height: _round(item.height),
                 right: _round(corner.x + item.width), bottom: _round(corner.y + item.height) };
    }

    // The named parts of `card` that show: { name: rect }
    function _parts(card) {
        const text = value => item => item.text === value && item.label === undefined;
        const button = value => item => item.label === value && typeof item.clicked === "function";
        const confirm = value => item => item.label === value && typeof item.confirmed === "function";
        const parts = {
            title: _find(card, text(card.title)),
            subtitle: _find(card, text(card.subtitle)),
            arrow: _find(card, item => item.text === "▸" || item.text === "▾"),
            mark: _find(card, item => item !== card && item.need === card.need && item.font !== undefined),
            primary: card.useQuestion !== "" && !card.profile.active ? _find(card, confirm(card.useLabel))
                : _find(card, item => item.objectName === "profilePrimary"),
            settings: _find(card, item => item.objectName === "profileSettings"),
            edit: _find(card, item => item.objectName === "profileEdit"),
            forget: _find(card, item => item.objectName === "profileForget"),
            notice: card.notice !== "" ? _find(card, text(card.notice)) : null,
            noticeButton: card.noticeAction !== "" ? _find(card, button(card.noticeAction)) : null,
            autoconnect: _find(card, item => item.label === card.autoconnectLabel && typeof item.toggled === "function"),
            priority: _find(card, text("Priority")),
            priorityHint: _find(card, text(card.priorityHint)),
            priorityPlus: _find(card, button("+")),
            pageRow: _find(card, item => item.objectName === "pageRow")
        };
        const shown = { card: _rect(card, card) };
        for (const name in parts) {
            if (parts[name])
                shown[name] = _rect(card, parts[name]);
        }
        return shown;
    }

    function _describe(parts) {
        return Object.keys(parts).map(name => {
            const part = parts[name];
            return name + " " + part.x + "," + part.y + " " + part.width + "x" + part.height;
        }).join("; ");
    }

    // Every card and every part where it stood at the last look (a layout places its
    // children in its polish pass, after they are built)
    property string _last: ""
    function _steady(cards) {
        const described = cards.map(card => _describe(_parts(card))).join(" | ");
        const steady = described === _last;
        _last = described;
        return steady;
    }

    function _settle(cards) {
        _last = "";
        return _until(() => {
            _driver.wait(30);
            return _steady(cards);
        });
    }

    // The layout's rules, on the parts of one card (`kind`, open or closed)
    function _check(card, kind, open) {
        const parts = _parts(card);
        const where = kind + (open ? " open" : " closed");
        console.log("  geometry: " + where + ": " + _describe(parts));
        const width = suite.cardWidth;
        const near = (actual, expected) => Math.abs(actual - expected) < 0.6;
        const expectNear = (actual, expected, message) => assert(near(actual, expected), where + ": " + message
                                                                 + (near(actual, expected) ? "" : " — expected " + _round(expected) + ", got " + actual));

        // The header: the name and its line on the left, at the margin
        const title = parts.title, subtitle = parts.subtitle, arrow = parts.arrow, primary = parts.primary;
        assert(title && subtitle && arrow, where + ": the name, its line and the arrow show");
        if (!title || !subtitle || !arrow)
            return;
        expectNear(title.x, 8, "the name at the left margin");
        expectNear(title.y, 8, "the name at the top margin");
        expectNear(subtitle.x, 8, "its line under it, aligned");
        expectNear(subtitle.y, title.bottom + 1, "its line 1 under the name");
        expectNear(subtitle.width, title.width, "the name and its line as wide");

        // The buttons in one row on the name's line, closed and open: the lock, the primary
        // button, "Settings…", "Edit", "Forget" — those that show
        const row = ["mark", "primary", "settings", "edit", "forget"].filter(name => parts[name]);
        // The arrow at the right margin, as tall as the header's line: the name and its line,
        // or the buttons if taller
        const rowHeight = Math.max(0, ...row.map(name => parts[name].height));
        const slot = Math.max(rowHeight, subtitle.bottom - title.y);
        expectNear(arrow.right, width - 8, "the arrow at the right margin");
        expectNear(arrow.y, 8, "the arrow at the top margin");
        expectNear(arrow.height, slot, "the arrow as tall as the header's line");

        // Right to left from 10 left of the arrow: the buttons 6 apart, the lock 10 left of the
        // primary button, each centred on the line
        let rowLeft = arrow.x - 10;
        for (const name of row.slice().reverse()) {
            const gap = rowLeft === arrow.x - 10 ? 0 : name === "mark" ? 10 : 6;
            expectNear(parts[name].right, rowLeft - gap, name + (gap === 0 ? " 10 left of the arrow" : " " + gap + " left of the next"));
            expectNear(parts[name].y, 8 + (slot - parts[name].height) / 2, name + " centred on the name's line");
            rowLeft = parts[name].x;
        }
        if (parts.mark)
            assert(primary !== undefined, where + ": the lock beside a primary button");
        // The name stops 10 short of the row (a layout gives it a whole width: up to 1 more)
        const nameEnd = rowLeft - 10;
        assert(title.right <= nameEnd + 0.01 && title.right > nameEnd - 1, where + ": the name 10 short of the buttons ("
               + title.right + ", " + _round(nameEnd) + ")");
        let bottom = Math.max(subtitle.bottom, 8 + slot);

        // The notice line, 6 under the header: its text at the margin, its button on the right,
        // both centred on the line
        if (card.notice !== "") {
            const notice = parts.notice, noticeButton = parts.noticeButton;
            assert(notice && noticeButton, where + ": the notice and its button show");
            if (notice && noticeButton) {
                const lineHeight = Math.max(notice.height, noticeButton.height);
                expectNear(notice.x, 8, "the notice at the margin");
                expectNear(notice.y, bottom + 6 + (lineHeight - notice.height) / 2, "the notice 6 under the header");
                expectNear(noticeButton.right, width - 8, "the notice's button at the right margin");
                expectNear(noticeButton.y, bottom + 6 + (lineHeight - noticeButton.height) / 2, "the notice's button on its line");
                expectNear(notice.right, noticeButton.x - 8, "the notice 8 short of its button");
                bottom += 6 + lineHeight;
            }
        }

        // Opened, the rows: each across the card, 6 under the one above (12 under the
        // switch, which keeps 6 under itself while a row follows); with no row of the page's,
        // nothing more under the card's own: the card ends 8 under its last line
        const rows = ["autoconnect", "priority", "pageRow"].filter(name => parts[name]);
        if (!open)
            assertEqual(rows.length, 0, where + ": no rows");
        for (const name of rows) {
            if (name === "priority") {
                const label = parts.priority, hint = parts.priorityHint, plus = parts.priorityPlus;
                assert(hint && plus, where + ": priority's hint and its + button show");
                if (!hint || !plus)
                    continue;
                const rowHeight = Math.max(hint.bottom - label.y, plus.height);
                expectNear(label.x, 8, "priority at the margin");
                expectNear(label.y, bottom + 6 + (rowHeight - (hint.bottom - label.y)) / 2, "priority 6 under the row above");
                expectNear(hint.y, label.bottom, "priority's hint under it");
                expectNear(plus.right, width - 8, "priority's + at the right margin");
                expectNear(plus.y, bottom + 6 + (rowHeight - plus.height) / 2, "priority's + on its line");
                bottom += 6 + rowHeight;
            } else {
                expectNear(parts[name].x, 8, name + " at the margin");
                expectNear(parts[name].width, width - 16, name + " across the card");
                expectNear(parts[name].y, bottom + 6, name + " 6 under what is above it");
                bottom = parts[name].bottom + (name === "autoconnect" && name !== rows[rows.length - 1] ? 6 : 0);
            }
        }
        expectNear(parts.card.width, width, "the card as wide as given");
        expectNear(parts.card.height, bottom + 8, "the card 8 under its last part");
    }

    function runAsync() {
        const cards = [wifiCard, wiredCard, hotspotCard, providerCard];
        const kinds = ["Wi-Fi", "wired", "hotspot", "provider"];
        assert(_until(() => _window.visible && cards.every(card => card.height > 0)), "the window is shown and the cards laid out");
        assert(_settle(cards), "closed: the cards stand still");
        cards.forEach((card, index) => _check(card, kinds[index], false));
        // Closed, every button on the name's line: nothing waits for the card to open
        const closed = cards.map(card => _parts(card));
        assert(closed[0].primary && closed[0].edit && closed[0].forget && closed[1].primary && closed[1].edit && closed[1].forget
               && closed[2].primary && closed[2].edit && closed[2].forget && closed[3].primary && closed[3].settings && closed[3].mark,
               "closed: each card's buttons on its name's line");

        // The card's wiring (NetworkProfileCard on SettingsCard): the name is the profile's, a
        // profile in use has its name bold and the border in the accent's colour
        const wiredTitle = _find(wiredCard, item => item.text === "Wired" && item.label === undefined);
        assert(wiredCard.title === "Wired" && wiredTitle !== null, "wiring: the wired card's name is its profile's (" + wiredCard.title + ")");
        assert(wiredTitle !== null && wiredTitle.font.bold && Qt.colorEqual(wiredCard.frame.border.color, Theme.accent),
               "wiring: a profile in use — its name bold, the border in the accent's colour");
        const wifiTitle = _find(wifiCard, item => item.text === "Home" && item.label === undefined);
        assert(wifiTitle !== null && !wifiTitle.font.bold && Qt.colorEqual(wifiCard.frame.border.color, Theme.outline),
               "wiring: a profile not in use — its name plain, the border the outline's");

        // What each kind shows: the Wi-Fi network Connect, Edit and Forget; the
        // wired profile in use Disconnect; the hotspot its asking Turn on; the provider
        // Disconnect, Settings…, the lock and the notice, no Edit or Forget —
        // opened, the buttons where they stood closed
        cards.forEach(card => card.open = true);
        assert(_settle(cards), "open: the cards stand still");
        cards.forEach((card, index) => _check(card, kinds[index], true));
        cards.forEach((card, index) => {
            const opened = _parts(card);
            const moved = ["mark", "primary", "settings", "edit", "forget"].filter(name => JSON.stringify(opened[name] ?? null) !== JSON.stringify(closed[index][name] ?? null));
            assertEqual(moved.join(","), "", kinds[index] + ": opened, its buttons where they stood closed");
        });
        const wifi = _parts(wifiCard), wired = _parts(wiredCard), hotspot = _parts(hotspotCard), provider = _parts(providerCard);
        assert(wifi.primary && wifi.edit && wifi.forget && !wifi.settings && wifi.autoconnect && wifi.priority && wifi.pageRow,
               "Wi-Fi open: Connect, Edit, Forget, both rows and the page's");
        assert(wired.primary && wired.edit && wired.forget && wired.autoconnect && wired.priority && !wired.mark,
               "wired open: Disconnect, Edit, Forget, both rows");
        assert(hotspot.primary && hotspot.edit && hotspot.forget && hotspot.autoconnect && !hotspot.priority,
               "hotspot open: its asking Turn on, Edit, Forget, no priority");
        assert(provider.primary && provider.settings && !provider.edit && !provider.forget && provider.mark && provider.notice
               && !provider.autoconnect && provider.pageRow, "provider open: Disconnect, Settings…, the lock, the notice, the page's row");

        // The notice's button waits while the card is busy, as its primary button does
        const noticeButton = _find(providerCard, item => item.label === providerCard.noticeAction && typeof item.clicked === "function");
        assert(noticeButton !== null && noticeButton.available, "wiring: the notice's button available while the card is not busy");
        providerCard.busy = true;
        assert(!noticeButton.available, "wiring: … unavailable while it is busy");
        providerCard.busy = false;

        // A long question asked by the primary button: cut to the room the other buttons
        // leave, the name cut to nothing first, the arrow still at the right margin
        hotspotCard.useQuestion = "Leaves a network with a long name: no internet to share. Turn on?";
        const asking = _find(hotspotCard, item => item.label === hotspotCard.useLabel && typeof item.confirmed === "function");
        asking.asking = true;
        assert(_settle(cards), "the hotspot asking: the cards stand still");
        const asked = _parts(hotspotCard);
        const askedButton = _rect(hotspotCard, asking);
        assert(asking.fullWidth > asking.maximumWidth && Math.abs(askedButton.width - asking.maximumWidth) < 0.6,
               "the hotspot asking: its question cut to the room left (" + askedButton.width + ", " + _round(asking.maximumWidth) + ", " + asking.fullWidth + ")");
        assert(Math.abs(asked.arrow.right - (suite.cardWidth - 8)) < 0.6 && Math.abs(asked.edit.right - (asked.forget.x - 6)) < 0.6
               && Math.abs(askedButton.right - (asked.edit.x - 6)) < 0.6 && askedButton.x >= asked.title.x + 10 - 0.6,
               "… the row in the card: the question, Edit and Forget 6 apart, the arrow at the margin ("
               + [askedButton.x, askedButton.right, asked.edit.x, asked.forget.x, asked.arrow.right].join(", ") + ")");
        asking.asking = false;
        hotspotCard.useQuestion = "Turn on? The Wi-Fi drops";

        // The shared card's buttons: one naming no vertical alignment centred on the row, one
        // naming its own (top) keeping it
        alignedCard.open = true;
        let alignedLast = "";
        const alignedSteady = () => {
            _driver.wait(30);
            const named = ["alignedPrimary", "alignedTop", "alignedPlain"].map(name => _rect(alignedCard, _find(alignedCard, item => item.objectName === name)));
            const described = JSON.stringify(named);
            const steady = named.every(rect => rect !== null) && described === alignedLast;
            alignedLast = described;
            return steady;
        };
        assert(_until(alignedSteady), "the shared card open, standing still");
        const alignedPrimary = _rect(alignedCard, _find(alignedCard, item => item.objectName === "alignedPrimary"));
        const alignedTop = _rect(alignedCard, _find(alignedCard, item => item.objectName === "alignedTop"));
        const alignedPlain = _rect(alignedCard, _find(alignedCard, item => item.objectName === "alignedPlain"));
        const alignedSlot = alignedCard.buttonRow.height;
        assert(alignedSlot > alignedPlain.height + 1, "the shared card's line taller than its buttons (" + alignedSlot + ", " + alignedPlain.height + ")");
        assert(Math.abs(alignedPlain.y - (8 + (alignedSlot - alignedPlain.height) / 2)) < 0.6 && Math.abs(alignedPlain.y - alignedPrimary.y) < 0.6,
               "a button naming no alignment: centred on the row, as the primary (" + alignedPlain.y + ", " + alignedPrimary.y + ")");
        assert(Math.abs(alignedTop.y - 8) < 0.6, "a button naming a vertical alignment: kept (" + alignedTop.y + ")");
        assert(Math.abs(alignedTop.right - (alignedPlain.x - 6)) < 0.6 && Math.abs(alignedPrimary.right - (alignedTop.x - 6)) < 0.6,
               "… in the row's order, 6 apart (" + [alignedPrimary.right, alignedTop.x, alignedTop.right, alignedPlain.x].join(", ") + ")");
        alignedCard.open = false;

        // The header: a click on the name asks to toggle; the pointer over it tints the card
        cards.forEach(card => card.open = false);
        assert(_settle(cards), "closed again: the cards stand still");
        let toggles = 0;
        const onToggle = () => toggles++;
        wiredCard.toggleRequested.connect(onToggle);
        const titleText = _find(wiredCard, item => item.text === wiredCard.title && item.label === undefined);
        const tinted = () => {
            const frame = wiredCard.frame ?? wiredCard;
            return Qt.colorEqual(frame.color, Theme.fillSubtle);
        };
        _driver.mouseMove(_window.contentItem, 2, 2);
        assert(_until(() => !tinted()), "the pointer away: the card untinted");
        _driver.mouseMove(titleText, 5, 5);
        assert(_until(tinted), "the pointer over the header tints the card");
        _driver.mouseClick(titleText, 5, 5);
        assertEqual(toggles, 1, "a click on the header asks to toggle");
        wiredCard.toggleRequested.disconnect(onToggle);
        _driver.mouseMove(_window.contentItem, 2, 2);
        finish();
    }
}
