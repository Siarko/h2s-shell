import QtQuick
import QtQuick.Layouts
import QtTest as QT
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.api
import qs.components
import qs.singletons
import qs.singletons.network

// The anchor blocks and their hosts (components/AnchorBlock.qml, AnchorContent.qml,
// SettingsPage.qml) on a fixture view, with a host of the suite's own (ModuleHost) and a
// table of its own: a page (settings.fixture) holding a block with a host at each of the four
// placements (AnchorFixtureBlock, "box") and one with no anchor. Two fixture modules
// (tests/fixtures/modules/anchors-a, anchors-b) put elements there: each placement in
// the one order, top to bottom; several modules by module id; the documented context and the
// module's handle; a place not offered and a placement not taken in the module's status; a
// module turned off takes its elements, on brings them back, the other module's element
// stays the same object; a reload builds them anew; a slot read as its anchor; Anchors.live
// following the blocks; the view opened and closed over and over. Asynchronous; after
// ModuleRegistriesTest, since both turn modules off through Config.disabledModules.
//
// A second fixture view whose root is no page (a plain item at the base holding blocks):
// sections with no anchor are not addressable (only a page is the view's root), a block of
// another kind than its row's or without the placement shows nothing, and an own-provider
// row shows each block only its scope's module. The table set anew is merged anew; a slot
// read as its anchor is no longer built as a slot (ModuleRules.slotAliasProblems, on the
// shell's files).
//
// The General page as the settings window's page loader holds it: where its rows stand — the
// headings, the hint and each setting at the page's margin, as far apart as they always were.
// Then the shell's own host with a fixture module (tests/fixtures/modules/anchors-general)
// at settings.general, append, and through the old slot read as it: the elements 16 under
// the last setting, their context; the settings window's General page with them, every place
// in the table live and nothing else; another page and back, the window closed and opened,
// over and over.
//
// The network and notifications popups as the popup's content loader holds them: where
// their parts stand, with no module and with a fixture module's elements
// (tests/fixtures/modules/anchors-popups) at popup.network.connections, append, and
// popup.notifications, prepend, and through the old slots read as them — the network popup
// in a network state the suite holds (an Ethernet link up, Wi-Fi on and joined to nothing, a
// stand-in provider's two VPNs); their blocks live against the table (the panel's root and
// the VPN part named, not published), the elements' context, a change of it passed once.
// Then the popups as the bar opens them (panels/Popup.qml): opened, moved to the other panel,
// closed, five times; opened and closed at once, closed while the content is being made,
// moved twice before it is made, a hover close called off — nothing left live, no element
// failed.
//
// Sections and cards on a fixture view (settings.cards, components/SettingsSection.qml,
// SettingsCard.qml) with two fixture modules (tests/fixtures/modules/anchors-cards-a,
// anchors-cards-b) whose elements tell a tracker in their context when they are made, run and
// go: a section's four placements and its cards' before and after in the one order; a card's
// region `settings` built only while the card is open, its elements above and under the
// card's own rows inside the frame, gone when it closes, opened and closed ten times; an
// own-provider region showing each provider's card only its module's element; cards made
// from a ScriptModel reordered (the same cards and elements), added, and taken out while open
// (their elements gone with them); the view closed with a card open — nothing left, no
// element running after its card went.
//
// The VPN page and the network popup's VPN rows (own-provider places), with two provider
// modules (tests/fixtures/modules/anchors-vpn-a through `anchors`, anchors-vpn-b through the
// old slots read as them), a provider that is no module's and a NetworkManager VPN held in
// NetworkProfiles: under each row and in each opened card only the VPN's provider module's
// element, with the VPN in its context (through the old slots every key they gave); none for
// the others; VPNs reordered, added and taken out with new objects at each read — the
// elements follow their VPN, a context handed again only when it changed, an element gone
// with its VPN.
//
// The Wi-Fi and Ethernet pages in a network state the suite holds (saved networks, a hotspot,
// wired profiles, a wired device): where their parts stand, every card closed and one open on
// each page, as they always stood; then a fixture module (tests/fixtures/modules/anchors-
// networks) at the saved networks' and wired profiles' opened cards (append): its element
// only in the open card, under the page's rows, 6 apart, with the network in its context as
// Api.networks names it; the page otherwise unmoved; none in a closed card or a hotspot's;
// networks read anew with new objects (reordered, one up, added, taken out) — the element
// follows its network, its context handed once, and goes with it.
TestCase {
    id: suite
    suiteName: "Anchors"
    asynchronous: true
    timeLimitMs: 90000

    // A suite that must be done first
    property var after: null

    readonly property string fixtures: Quickshell.shellDir + "/tests/fixtures/modules"
    readonly property var table: [
        _row("settings.fixture", "page", ["prepend", "append"], "{ editIndex }"),
        _row("settings.fixture.box", "section", ["before", "after", "prepend", "append"], "{ boxed }"),
        _row("settings.general", "page", ["append"], "{ editIndex }"),
        _row("settings.fixture.vpn", "row", ["append"], "{ vpnId }", "own-provider"),
        _row("settings.cards.saved", "section", ["before", "after", "prepend", "append"], "{ tracker }"),
        _row("settings.cards.saved.card", "card", ["before", "after"], "{ itemId, tracker }"),
        _row("settings.cards.saved.card.settings", "region", ["prepend", "append"], "{ itemId, tracker }"),
        _row("settings.cards.vpns.card.settings", "region", ["prepend"], "{ itemId, tracker }", "own-provider"),
        _row("settings.cards.saved.card.actions", "region", ["append"], "{ itemId, tracker }", "", undefined, "SmallButton"),
        _row("settings.cards.vpns.card.actions", "region", ["append"], "{ itemId, tracker }", "own-provider", undefined, "SmallButton")
    ]

    property ModuleHost host: ModuleHost {
        logStates: false
    }
    property var _steps: []
    property var _savedDisabled: []
    property var _views: []
    property var _view: null
    property var _betaItem: null
    property var _betaElement: null
    property int _betaContexts: 0
    property var _alphaElement: null
    property int _cycles: 0
    property real _waitUntil: 0
    property var _plain: null
    property int _liveChanges: 0
    // What the slot guard read: { slot: [files] }, { file: text }
    property var _slotUses: null
    property var _viewTexts: ({})

    function _row(path, kind, placements, context, scope, view, takes) {
        return { path: path, kind: kind, placements: placements, takes: takes ?? "", context: context, scope: scope ?? "", since: "1.20",
                 where: "AnchorsTest's fixture view", view: view ?? "tests/AnchorsTest.qml" };
    }

    property Connections _liveWatch: Connections {
        target: Anchors
        function onLiveChanged() {
            suite._liveChanges++;
        }
    }

    // The files outside the tests that still name a slot read as an anchor: a quoted slot
    // name on a line that is not a comment, beside the rules that list them — and the page's
    // slot, still a slot, so that the guard is seen finding one
    property Process _slotGrep: Process {
        command: ["sh", "-c", "cd \"$1\" && shift && for slot; do grep -rnF --include=*.qml \"\\\"$slot\\\"\" . | grep -v '^\\./tests/' "
                  + "| grep -v '^\\./singletons/ModuleRules\\.qml:' | grep -vE '^[^:]*:[0-9]+:[[:space:]]*//' | cut -d: -f1 | sort -u "
                  + "| sed \"s|^\\./|$slot\\t|\"; done; echo END",
                  "sh", Quickshell.shellDir].concat(ModuleRules.slotAliases.map(alias => alias.slot), ["network.vpn.page"])
        stdout: StdioCollector {
            onStreamFinished: {
                const uses = {};
                for (const line of text.split("\n")) {
                    const [slot, file] = line.split("\t");
                    if (file)
                        (uses[slot] = uses[slot] ?? []).push(file);
                }
                suite._slotUses = text.includes("END") ? uses : {};
            }
        }
    }

    function _viewText(file) {
        if (!Object.prototype.hasOwnProperty.call(_viewTexts, file)) {
            const reader = Qt.createQmlObject("import Quickshell.Io; FileView { blockLoading: true; path: " + JSON.stringify(Quickshell.shellDir + "/" + file) + " }", suite);
            const text = reader.text();
            reader.destroy();
            _viewTexts[file] = text === "" ? undefined : text;
        }
        return _viewTexts[file];
    }

    function _viewTextsOf(table) {
        const texts = {};
        for (const row of table)
            texts[row.view] = _viewText(row.view);
        return texts;
    }

    function _then(description, condition, action, timeoutMs) {
        _steps.push({ description: description, condition: condition, action: action, deadline: timeoutMs ?? 10000 });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite._end();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {
                ready = false;
            }
            if (!ready && waited < step.deadline)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    function _end() {
        _pinNetwork(false);
        _holdProfiles(null);
        _holdWifiDetails(null);
        _holdDevices(null);
        if (_heldNetworks !== null)
            _holdNetworks(null);
        _fakeVpn?.destroy();
        _ownVpn?.destroy();
        _dropPopup();
        for (const view of _views)
            view?.destroy();
        _views = [];
        host.unload();
        Modules.host.unload();
        Config.disabledModules = _savedDisabled;
        finish();
    }

    // ---- The fixture view: a layer surface in a corner, its root given a base ----

    property Component _viewComponent: Component {
        PanelWindow {
            id: window

            property string base: "settings.fixture"
            property alias page: page
            property alias inside: inside
            property alias box: box
            property alias boxContent: boxContent
            property alias plain: plain

            anchors {
                top: true
                left: true
            }
            implicitWidth: 400
            implicitHeight: 700
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "h2s-tests"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // What the settings window's page loader will be: the base of the view's root
            Item {
                property string anchorBase: window.base
                anchors.fill: parent

                SettingsPage {
                    id: page
                    anchors.fill: parent
                    title: "Fixture"
                    host: suite.host
                    context: ({ editIndex: 2 })

                    Text {
                        id: inside
                        text: "the page's own content"
                    }

                    AnchorFixtureBlock {
                        id: box
                        anchor: "box"
                        context: ({ boxed: true })
                        Layout.fillWidth: true

                        Text {
                            id: boxContent
                            text: "the box's own content"
                        }
                    }

                    // No anchor: not addressable, adds no level
                    AnchorFixtureBlock {
                        id: plain
                        title: "Plain"
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    // The view whose root is no page: blocks straight under a plain item at the base
    property Component _plainViewComponent: Component {
        PanelWindow {
            id: plainWindow

            property alias sections: sections
            property alias wrongKind: wrongKind
            property alias fewer: fewer
            property alias vpnA: vpnA
            property alias vpnB: vpnB
            property alias vpnNone: vpnNone

            anchors {
                top: true
                right: true
            }
            implicitWidth: 400
            implicitHeight: 700
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "h2s-tests"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Item {
                property string anchorBase: "settings.fixture"
                anchors.fill: parent

                Column {
                    width: parent.width

                    // Three sections with no anchor: none is the page
                    Repeater {
                        id: sections
                        model: 3
                        AnchorFixtureBlock {
                            host: suite.host
                            width: 400
                        }
                    }

                    // At the box's path, but a card: its row is a section's
                    AnchorFixtureBlock {
                        id: wrongKind
                        anchor: "box"
                        kind: "card"
                        host: suite.host
                        width: 400
                    }

                    // At the box's path, with only a prepend host of its own
                    AnchorFixtureBlock {
                        id: fewer
                        anchor: "box"
                        placements: ["prepend"]
                        host: suite.host
                        width: 400
                    }

                    // Items of two providers, and one of none, on the own-provider row
                    AnchorFixtureBlock {
                        id: vpnA
                        anchor: "vpn"
                        kind: "row"
                        scopeId: "anchors-a"
                        host: suite.host
                        width: 400
                    }

                    AnchorFixtureBlock {
                        id: vpnB
                        anchor: "vpn"
                        kind: "row"
                        scopeId: "anchors-b"
                        host: suite.host
                        width: 400
                    }

                    AnchorFixtureBlock {
                        id: vpnNone
                        anchor: "vpn"
                        kind: "row"
                        host: suite.host
                        width: 400
                    }
                }
            }
        }
    }

    // The view of sections and cards: a page (settings.cards) holding a section of cards made
    // from a list (saved: settings.cards.saved, its cards …saved.card, their opened part
    // …saved.card.settings) and a section of providers' cards (vpns: …vpns.card.settings,
    // own-provider), one card of each open at most
    property Component _cardsViewComponent: Component {
        PanelWindow {
            id: cardsWindow

            property var items: []
            property string openId: ""
            property var vpns: []
            property string vpnOpenId: ""
            property alias page: cardsPage
            property alias saved: savedSection
            property alias intro: savedIntro
            property alias savedCards: savedRepeater
            property alias vpnCards: vpnRepeater

            anchors {
                top: true
                left: true
            }
            implicitWidth: 400
            implicitHeight: 1000
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "h2s-tests"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Item {
                property string anchorBase: "settings.cards"
                anchors.fill: parent

                SettingsPage {
                    id: cardsPage
                    anchors.fill: parent
                    host: suite.host

                    SettingsSection {
                        id: savedSection
                        anchor: "saved"
                        title: "Saved"
                        spacing: 6
                        context: ({ tracker: suite._tracker })
                        Layout.fillWidth: true
                        buttons: SmallButton { label: "Find" }

                        Text {
                            id: savedIntro
                            text: "the section's own content"
                        }

                        // Keyed as the real pages are (KeyedModel): the suite gives new
                        // objects for the items at every step, as a read of the system does
                        KeyedModel { id: savedItems; values: cardsWindow.items; keyProp: "id" }

                        Repeater {
                            id: savedRepeater
                            model: savedItems.model

                            SettingsCard {
                                required property string modelData
                                readonly property var cardItem: savedItems.byKey[modelData] ?? ({})
                                readonly property alias ownRow: ownRow
                                anchor: "card"
                                title: cardItem.id
                                subtitle: "a fixture card"
                                open: cardsWindow.openId === cardItem.id
                                context: ({ itemId: cardItem.id, tracker: suite._tracker })
                                Layout.fillWidth: true
                                onToggleRequested: cardsWindow.openId = open ? "" : cardItem.id
                                // Its own buttons, as a network's card has them: one above the
                                // modules' and the one that removes it, last
                                buttons: SmallButton { objectName: "ownEdit"; label: "Edit" }
                                lastButtons: DeleteButton { objectName: "ownForget"; label: "Forget"; fontSize: Theme.fontSizeBody }

                                Text {
                                    id: ownRow
                                    text: "the card's own row"
                                }
                            }
                        }
                    }

                    SettingsSection {
                        anchor: "vpns"
                        title: "VPNs"
                        Layout.fillWidth: true

                        KeyedModel { id: vpnItems; values: cardsWindow.vpns; keyProp: "id" }

                        Repeater {
                            id: vpnRepeater
                            model: vpnItems.model

                            SettingsCard {
                                required property string modelData
                                readonly property var cardItem: vpnItems.byKey[modelData] ?? ({})
                                anchor: "card"
                                title: cardItem.id
                                scopeId: cardItem.provider
                                open: cardsWindow.vpnOpenId === cardItem.id
                                context: ({ itemId: cardItem.id, tracker: suite._tracker })
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
    }
    property var _cards: null
    // The saved cards' items, a new object at every call: what a page gets from a read
    function _cardItems(ids) {
        return ids.map(id => ({ id: id }));
    }
    property int _cardCycles: 0
    // The cards of a list, in the list's order: the identity of each, by item
    property var _cardObjects: ({})
    property var _regionElements: []

    // What the fixture cards' elements tell: made, a beat while they run, gone. A beat from an
    // element counted gone is late (it ran after its card took it)
    property QtObject _tracker: QtObject {
        property var live: ({})
        property int madeCount: 0
        property int goneCount: 0
        property int beats: 0
        property int late: 0

        function key(name, context) {
            return [name, context?.anchor, context?.placement, context?.itemId ?? ""].join("|");
        }
        function made(name, context) {
            const at = key(name, context);
            live[at] = (live[at] ?? 0) + 1;
            madeCount++;
        }
        function gone(name, context) {
            const at = key(name, context);
            live[at] = (live[at] ?? 0) - 1;
            if (live[at] <= 0)
                delete live[at];
            goneCount++;
        }
        function beat(name, context) {
            beats++;
            if (!(live[key(name, context)] > 0))
                late++;
        }
        function count(prefix) {
            return Object.keys(live).filter(at => prefix === undefined || at.includes(prefix)).reduce((sum, at) => sum + live[at], 0);
        }
        function reset() {
            live = {};
            madeCount = goneCount = beats = late = 0;
        }
    }

    function _savedCard(index) {
        return _cards?.savedCards.itemAt(index) ?? null;
    }

    function _savedCardList() {
        const cards = [];
        for (let i = 0; _cards && i < _cards.savedCards.count; i++)
            cards.push(_cards.savedCards.itemAt(i));
        return cards;
    }

    function _vpnCard(index) {
        return _cards?.vpnCards.itemAt(index) ?? null;
    }

    function _yIn(item) {
        return item.mapToItem(_cards.page, 0, 0).y;
    }

    // Whether the cards view stands still: every card and every element where it stood at the
    // last look (a layout places its children in its polish pass, after they are built)
    property string _lastCards: ""
    function _cardsSteady() {
        const parts = [];
        const add = item => parts.push(Math.round(_yIn(item) * 100) / 100 + ":" + Math.round(item.height * 100) / 100);
        const section = _cards.saved;
        for (const host of [section.beforeHost, section.prependHost, section.appendHost, section.afterHost])
            host.items.forEach(add);
        for (const card of _savedCardList().concat([_vpnCard(0), _vpnCard(1), _vpnCard(2)]).filter(card => card)) {
            add(card.frame);
            for (const host of [card.beforeHost, card.afterHost, card.settingsRegion.prependHost, card.settingsRegion.appendHost, card.actionsRegion.appendHost])
                host.items.forEach(add);
            add(card.actionsRegion);
        }
        const described = parts.join(" ");
        const steady = described === _lastCards;
        _lastCards = described;
        return steady;
    }

    // The section's elements and every saved card's beside it built
    function _cardsBuilt() {
        const section = _cards.saved;
        return _ready(section.beforeHost, 1) && _ready(section.prependHost, 1) && _ready(section.appendHost, 1) && _ready(section.afterHost, 1)
            && _savedCardList().length === _cards.items.length
            && _savedCardList().every(card => _ready(card.beforeHost, 1) && _ready(card.afterHost, 1));
    }

    // The opened saved card's region built, every closed card's empty
    function _regionBuilt(openIndex) {
        return _savedCardList().every((card, index) => index === openIndex
            ? _ready(card.settingsRegion.prependHost, 1) && _ready(card.settingsRegion.appendHost, 2)
            : !card.settingsRegion.prependHost.built && !card.settingsRegion.appendHost.built);
    }

    // What is wrong with where an opened card's parts stand: its before element above its
    // frame, the region's prepend element under the header and above its own row, the append
    // elements under it, all inside the frame, its after element under the frame
    function _openCardProblems(card) {
        const problems = [];
        const frameTop = _yIn(card.frame);
        const frameBottom = frameTop + card.frame.height;
        const prepend = card.settingsRegion.prependHost.items[0];
        const appended = card.settingsRegion.appendHost.items;
        const ownRow = card.ownRow;
        if (_yIn(card.beforeHost.items[0]) + card.beforeHost.items[0].height > frameTop + 0.01)
            problems.push("the before element is not above the frame");
        if (_yIn(card.afterHost.items[0]) < frameBottom - 0.01)
            problems.push("the after element is not under the frame");
        if (_yIn(card.settingsRegion) < frameTop + 8 || _yIn(prepend) < _yIn(card.settingsRegion) - 0.01)
            problems.push("the region does not start under the header");
        if (_yIn(prepend) + prepend.height > _yIn(ownRow) + 0.01)
            problems.push("the prepend element is not above the card's own row");
        if (_yIn(appended[0]) < _yIn(ownRow) + ownRow.height - 0.01 || _yIn(appended[1]) < _yIn(appended[0]) + appended[0].height - 0.01)
            problems.push("the append elements are not under the own row, in order");
        if (_yIn(appended[1]) + appended[1].height > frameBottom - 8 + 0.01)
            problems.push("the append elements are not inside the frame");
        if (prepend.width <= 0 || Math.abs(prepend.width - card.settingsRegion.width) > 0.01
                || Math.abs(card.settingsRegion.width - (card.frame.width - 16)) > 0.01)
            problems.push("the region's elements are not as wide as the frame inside its margins (" + prepend.width + ", " + card.frame.width + ")");
        return problems;
    }

    function _openCards(items, vpns) {
        _cards = _cardsViewComponent.createObject(suite);
        _views.push(_cards);
        // Assigned, not given to createObject: that would hand the view copies of the items
        _cards.items = items;
        _cards.vpns = vpns ?? [];
    }

    // The General page as the settings window's page loader holds it, in a layer surface in a
    // corner, for where its rows stand
    property Component _generalViewComponent: Component {
        PanelWindow {
            id: generalWindow

            property alias loader: generalLoader

            anchors {
                top: true
                left: true
            }
            implicitWidth: 420
            implicitHeight: 1000
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "h2s-tests"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Loader {
                id: generalLoader
                property string anchorBase: "settings.general"
                anchors.fill: parent
                source: Qt.resolvedUrl("../panels/settings/GeneralSettings.qml")
            }
        }
    }
    property var _generalView: null
    property var _settingsWindow: null
    property int _windowCycles: 0

    // The anchor block at `path` under `item` (the first found), or null
    function _blockAt(item, path) {
        for (const child of item?.children ?? []) {
            if (child.isAnchorBlock === true && child.path === path)
                return child;
            const found = _blockAt(child, path);
            if (found)
                return found;
        }
        return null;
    }

    function _windowPage() {
        return _settingsWindow ? _blockAt(_settingsWindow.contentItem, "settings.general") : null;
    }

    function _openSettingsWindow() {
        const component = Qt.createComponent(Qt.resolvedUrl("../panels/SettingsWindow.qml"), Component.PreferSynchronous);
        _settingsWindow = component.status === Component.Ready ? component.createObject(suite, { visible: false }) : null;
        if (_settingsWindow)
            _views.push(_settingsWindow);
        else
            fail("the settings window can be made (" + component.errorString() + ")");
    }

    function _closeSettingsWindow() {
        _close(_settingsWindow);
        _settingsWindow = null;
    }

    function _generalSettled() {
        const statuses = Modules.host.statuses;
        return statuses.length > 0 && !statuses.some(status => status.state === "pending") && !Modules.host.checkingFiles;
    }

    // The General page's rows top to bottom, as { name, x, y, width, height } in the loader's
    // coordinates: its headings and hint (the texts outside a setting's editor) and each
    // setting's editor (named by its key)
    function _generalRows(loader) {
        const rows = [];
        const walk = item => {
            for (const child of item.children ?? []) {
                if (!child.visible)
                    continue;
                const point = child.mapToItem(loader, 0, 0);
                const row = { x: point.x, y: point.y, width: child.width, height: child.height };
                if (typeof child.key === "string" && child.editIndex !== undefined)
                    rows.push(Object.assign(row, { name: "setting " + child.key }));
                else if (typeof child.text === "string" && child.font !== undefined && child.text !== "")
                    rows.push(Object.assign(row, { name: "text " + child.text.slice(0, 16) }));
                else
                    walk(child);
            }
        };
        walk(loader.item);
        return rows.sort((a, b) => a.y - b.y);
    }

    // Whether the General page's column has placed the elements at its end: under the last
    // setting, given the page's width, and where they stood at the last look (a column places
    // its children in its polish pass, after they are built)
    property string _lastGeneralEnd: ""
    function _generalEndLaidOut(loader) {
        const host = loader.item.appendHost;
        const rows = _generalRows(loader).filter(row => row.name.startsWith("setting "));
        const last = rows[rows.length - 1];
        const element = host.items[0].mapToItem(loader, 0, 0);
        const described = [element.x, element.y, host.width, last.y, last.height].join(" ");
        const steady = described === _lastGeneralEnd;
        _lastGeneralEnd = described;
        return steady && host.width > 0 && element.y >= last.y + last.height;
    }

    // What the rows must be: the heading at the page's margin; under it, 8 apart, the general
    // settings one after another; 16 lower the second heading, 2 under it the hint, 8 under
    // that the appearance settings; every row at the margin, the settings as wide as the page
    // inside its margins — measured from each row's own height, so no font changes it
    function _generalLayoutProblems(rows, width) {
        const margin = Theme.settings.pageMargin;
        const general = SettingsSchema.keysInGroup("general");
        const appearance = SettingsSchema.keysInGroup("appearance");
        const expected = [["text General", 0]].concat(general.map((key, index) => ["setting " + key, index === 0 ? 8 : 0]),
                                                      [["text Theme and motion", 16], ["text Which theme this", 2]],
                                                      appearance.map((key, index) => ["setting " + key, index === 0 ? 8 : 0]));
        const problems = [];
        if (rows.map(row => row.name).join("|") !== expected.map(entry => entry[0]).join("|"))
            return ["the rows: " + rows.map(row => row.name).join("|")];
        rows.forEach((row, index) => {
            const top = index === 0 ? margin : rows[index - 1].y + rows[index - 1].height + expected[index][1];
            if (Math.abs(row.y - top) > 0.01)
                problems.push(row.name + " at y " + row.y + ", not " + top);
            if (Math.abs(row.x - margin) > 0.01)
                problems.push(row.name + " at x " + row.x + ", not " + margin);
            if (row.name.startsWith("setting ") && Math.abs(row.width - (width - 2 * margin)) > 0.01)
                problems.push(row.name + " " + row.width + " wide, not " + (width - 2 * margin));
            if (row.height <= 0)
                problems.push(row.name + " has no height");
        });
        return problems;
    }

    // ---- The popups: where their parts stand ----

    // A popup's panel as the popup's content loader holds it (panels/Popup.qml: the panel's
    // width its own, the base of its place given), in a layer surface in a corner
    property Component _popupViewComponent: Component {
        PanelWindow {
            id: popupWindow

            property string key: "network"
            property url source
            property real panelHeight: 0
            property alias loader: popupContent

            anchors {
                top: true
                right: true
            }
            implicitWidth: 420
            implicitHeight: 1000
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "h2s-tests"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Loader {
                id: popupContent
                property string anchorBase: "popup." + popupWindow.key
                width: item ? item.implicitWidth : 0
                height: popupWindow.panelHeight > 0 ? popupWindow.panelHeight : (item ? item.implicitHeight : 0)
                source: popupWindow.source
                onLoaded: {
                    if (popupWindow.panelHeight > 0 && typeof item.availableHeight !== "undefined")
                        item.availableHeight = popupWindow.panelHeight;
                }
            }
        }
    }
    property var _popupView: null
    property real _cutHeight: 0
    // The network list's list view, in a network panel
    function _findListView(item) {
        for (const child of item.children ?? []) {
            if (String(child).startsWith("WifiNetworkList"))
                return child.children.find(inner => inner.contentY !== undefined && inner.count !== undefined) ?? null;
            const found = _findListView(child);
            if (found !== null)
                return found;
        }
        return null;
    }
    property var _fakeVpn: null
    // The network state the popup is measured in, held while _pinned: an Ethernet link up,
    // Wi-Fi on but joined to nothing — what the panel would show with no NetworkManager
    // gives way (its polls, with no bus here, keep resetting it)
    property bool _pinned: false
    property var _unpinned: null
    readonly property var _pinnedState: ({ wifiAvailable: true, ethernetDevice: "eth-anchors", ethernetState: "connected",
                                           ethernetConnection: "Wired test", wifiEnabled: true })

    function _pin() {
        if (!_pinned)
            return;
        for (const key of ["wifiAvailable", "ethernetDevice", "ethernetState", "ethernetConnection"]) {
            if (NetworkManager[key] !== _pinnedState[key])
                NetworkManager[key] = _pinnedState[key];
        }
        if (WifiManager.wifiEnabled !== _pinnedState.wifiEnabled)
            WifiManager.wifiEnabled = _pinnedState.wifiEnabled;
    }

    function _pinNetwork(on) {
        if (on && !_pinned) {
            _unpinned = { wifiAvailable: NetworkManager.wifiAvailable, ethernetDevice: NetworkManager.ethernetDevice,
                          ethernetState: NetworkManager.ethernetState, ethernetConnection: NetworkManager.ethernetConnection,
                          wifiEnabled: WifiManager.wifiEnabled };
            _pinned = true;
            _pin();
        } else if (!on && _pinned) {
            _pinned = false;
            for (const key of ["wifiAvailable", "ethernetDevice", "ethernetState", "ethernetConnection"])
                NetworkManager[key] = _unpinned[key];
            WifiManager.wifiEnabled = _unpinned.wifiEnabled;
        }
    }

    function _networkPinned() {
        return Object.keys(_pinnedState).every(key => (key === "wifiEnabled" ? WifiManager[key] : NetworkManager[key]) === _pinnedState[key]);
    }

    property Connections _pinNetworkManager: Connections {
        target: NetworkManager
        enabled: suite._pinned
        function onWifiAvailableChanged() { suite._pin(); }
        function onEthernetDeviceChanged() { suite._pin(); }
        function onEthernetStateChanged() { suite._pin(); }
        function onEthernetConnectionChanged() { suite._pin(); }
    }
    property Connections _pinWifiManager: Connections {
        target: WifiManager
        enabled: suite._pinned
        function onWifiEnabledChanged() { suite._pin(); }
    }

    function _openPopupView(key, file, panelHeight) {
        _popupView = _popupViewComponent.createObject(suite, { key: key, source: Qt.resolvedUrl(file), panelHeight: panelHeight ?? 0 });
        _views.push(_popupView);
    }

    function _closePopupView() {
        _close(_popupView);
        _popupView = null;
    }

    // A popup panel's parts top to bottom, as { name, x, y, width, height } in the panel's
    // coordinates: what stands in its columns, looked into through the columns, plain items,
    // loaders and blocks that hold them (and the VPN part, a file of its own), never into a
    // part. A part is named by its objectName, "modules" for a place modules fill, "list" for
    // a list view, its file's
    // type for a part in a file of its own, "divider" for a line, else its first text with a
    // letter
    function _popupParts(panel) {
        const parts = [];
        const typeOf = item => String(item).replace(/\(.*$/, "").replace(/_QML(TYPE)?_\d+$/, "");
        const opens = item => item.isAnchorBlock === true || typeOf(item) === "VpnSection"
            || /^QQuick(Column|ColumnLayout|Item|Loader)(_QML_\d+)?\(/.test(String(item));
        const firstText = item => {
            if (!item.visible)
                return "";
            if (typeof item.text === "string" && item.font !== undefined && /[A-Za-z]/.test(item.text))
                return item.text;
            for (const child of item.children ?? []) {
                const text = firstText(child);
                if (text !== "")
                    return text;
            }
            return "";
        };
        const nameOf = item => {
            if (item.contributions !== undefined)
                return "modules";
            if (item.objectName !== "")
                return item.objectName;
            if (item.model !== undefined && item.contentY !== undefined)
                return "list";
            if (/_QMLTYPE_\d+\(/.test(String(item)))
                return typeOf(item);
            if (item.border !== undefined && item.radius !== undefined && item.height === 1)
                return "divider";
            return "text " + firstText(item).slice(0, 18);
        };
        const walk = item => {
            for (const child of item.children ?? []) {
                if (!child.visible || child.width <= 0 || child.height <= 0)
                    continue;
                if (opens(child) && child.contributions === undefined) {
                    walk(child);
                    continue;
                }
                const point = child.mapToItem(panel, 0, 0);
                parts.push({ name: nameOf(child), x: point.x, y: point.y, width: child.width, height: child.height });
            }
        };
        walk(panel);
        return parts.sort((a, b) => a.y - b.y || a.x - b.x);
    }

    // What is wrong with where the parts stand: `expected` [[name, the gap above it (from
    // the top for the first), its inset from the sides]], each part as wide as the panel less
    // its insets, the last reaching `bottom` when given — measured from each part's own
    // height, so no font changes it
    function _partsProblems(parts, expected, width, bottom) {
        if (parts.map(part => part.name).join("|") !== expected.map(entry => entry[0]).join("|"))
            return ["the parts: " + parts.map(part => part.name).join("|")];
        const problems = [];
        parts.forEach((part, index) => {
            const [name, gap, inset] = expected[index];
            const top = index === 0 ? gap : parts[index - 1].y + parts[index - 1].height + gap;
            if (Math.abs(part.y - top) > 0.01)
                problems.push(name + " at y " + part.y + ", not " + top);
            if (Math.abs(part.x - inset) > 0.01)
                problems.push(name + " at x " + part.x + ", not " + inset);
            if (Math.abs(part.width - (width - 2 * inset)) > 0.01)
                problems.push(name + " " + part.width + " wide, not " + (width - 2 * inset));
        });
        const last = parts[parts.length - 1];
        if (bottom !== undefined && last && Math.abs(last.y + last.height - bottom) > 0.01)
            problems.push(last.name + " ends at " + (last.y + last.height) + ", not " + bottom);
        return problems;
    }

    function _describeParts(parts) {
        return parts.map(part => part.name + " " + [part.x, part.y, part.width, part.height].map(Math.round).join(" ")).join(" · ");
    }

    // Whether a popup's columns have placed its parts: the parts `expected` names, each under
    // the one before it, and where they stood at the last look — a Column places its children
    // in its polish pass, after they are built, so a count alone may meet them all at the top
    property string _lastParts: ""
    function _partsLaidOut(panel, expected) {
        const parts = _popupParts(panel);
        const placed = parts.map(part => part.name).join("|") === expected.map(entry => entry[0]).join("|")
            && parts.every((part, index) => index === 0 || part.y >= parts[index - 1].y + parts[index - 1].height - 0.01);
        const described = _describeParts(parts) + " " + parts.map(part => part.y + part.height).join(" ");
        const steady = described === _lastParts;
        _lastParts = described;
        return placed && steady;
    }

    // Stand-in networks in range, held in WifiManager while set: no scan replaces them
    property var _heldNetworks: null
    property var _unheldNetworks: null
    function _holdNetworks(networks) {
        if (networks !== null && _heldNetworks === null)
            _unheldNetworks = WifiManager.wifiNetworks;
        _heldNetworks = networks;
        WifiManager.wifiNetworks = networks ?? _unheldNetworks ?? [];
    }
    property Connections _holdWifiNetworks: Connections {
        target: WifiManager
        enabled: suite._heldNetworks !== null
        function onWifiNetworksChanged() {
            if (WifiManager.wifiNetworks !== suite._heldNetworks)
                WifiManager.wifiNetworks = suite._heldNetworks;
        }
    }
    function _standInNetworks(count) {
        const networks = [];
        for (let i = 0; i < count; i++)
            networks.push({ ssid: "Stand-in " + (i + 1), signal: 90 - i * 5, security: "WPA2", inUse: false, bands: ["5G"], band: "5G" });
        return networks;
    }

    // The network popup in the pinned state: the VPN part (its header, two VPNs — the first
    // with its status line — each with the provider's extras under it, and its divider), the
    // Ethernet link (its line, its details, a divider), the Wi-Fi line, modules' elements
    // when there are some, the divider over the network list, and the list's header and rows
    function _networkExpected(withModules) {
        return [["text VPN", 0, 0], ["vpnRow", 4, 0], ["VpnExtras", 2, 0], ["vpnRow", 4, 0], ["VpnExtras", 2, 0], ["divider", 4, 0],
                ["text Wired test", 6, 0], ["LinkInfo", 6, 0], ["divider", 6, 0], ["text WiFi", 6, 0]]
            .concat(withModules ? [["modules", 6, 0]] : [])
            .concat([["divider", 6, 0], ["text Available Networks", 6, 0], ["WifiNetworkList", 4, 0], ["HiddenNetworkRow", 4, 0]]);
    }

    // The notifications popup: its header 8 in from the sides, modules' elements under it as
    // far in, the list under them to the panel's end
    function _notificationsExpected(withModules) {
        return [["text Notifications", 0, 8]].concat(withModules ? [["modules", 8, 8]] : [], [["list", 8, 0]]);
    }

    // The popup places live under `prefix` against the table: each of its rows live, and
    // every live path not in it among those named, not published
    readonly property var _namedNotPublished: ["popup.network", "popup.network.connections.vpn", "settings.network_vpn.vpns", "settings.network_vpn.vpns.card",
                                               "settings.network_vpn.vpns.card.title",
                                               "settings.network_wifi.saved", "settings.network_wifi.saved.card", "settings.network_wifi.hotspots",
                                               "settings.network_wifi.hotspots.card", "settings.network_wifi.hotspots.card.settings",
                                               "settings.network_wifi.hotspots.card.actions", "settings.network_wifi.hotspots.card.title",
                                               "settings.network_ethernet.profiles", "settings.network_ethernet.profiles.card"]
    function _popupLiveProblems(prefix) {
        const problems = [];
        const live = Object.keys(Anchors.live).filter(path => path === prefix || path.startsWith(prefix + "."));
        for (const row of ModuleRules.anchorTable.filter(row => row.path === prefix || row.path.startsWith(prefix + "."))) {
            if (!live.includes(row.path))
                problems.push(row.path + " is in the table but not live");
        }
        for (const path of live) {
            if (!ModuleRules.anchorRow(ModuleRules.anchorTable, path) && !_namedNotPublished.includes(path))
                problems.push(path + " is live but neither in the table nor named, not published");
        }
        return problems;
    }

    // ---- The VPN page and the popup's VPN rows (own-provider places) ----

    // The VPN page as the settings window's page loader holds it, in a layer surface in a
    // corner
    property Component _vpnPageViewComponent: Component {
        PanelWindow {
            property alias loader: vpnPageLoader

            anchors {
                top: true
                left: true
            }
            implicitWidth: 520
            implicitHeight: 1000
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "h2s-tests"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Loader {
                id: vpnPageLoader
                property string anchorBase: "settings.network_vpn"
                anchors.fill: parent
                source: Qt.resolvedUrl("../panels/settings/NetworkVpnSettings.qml")
            }
        }
    }
    property var _vpnPage: null
    // A provider that is no module's (its own extras, no module's elements)
    property var _ownVpn: null
    // Elements kept to see that they stay the same objects
    property var _keptRow: null
    property var _keptCard: null
    property int _keptChanges: 0

    // Stand-in NetworkManager profiles, held in NetworkProfiles while set: no read replaces
    // them (with no NetworkManager here, its reads keep resetting the list)
    property var _heldProfiles: null
    property var _unheldProfiles: null
    function _holdProfiles(profiles) {
        if (profiles !== null && _heldProfiles === null)
            _unheldProfiles = NetworkProfiles.profiles;
        if (profiles === null && _heldProfiles === null)
            return;
        _heldProfiles = profiles;
        NetworkProfiles.profiles = profiles ?? _unheldProfiles ?? [];
    }
    property Connections _holdNetworkProfiles: Connections {
        target: NetworkProfiles
        enabled: suite._heldProfiles !== null
        function onProfilesChanged() {
            if (NetworkProfiles.profiles !== suite._heldProfiles)
                NetworkProfiles.profiles = suite._heldProfiles;
        }
    }
    readonly property var _nmVpnProfile: ({ uuid: "nm-anchors", name: "Office", type: "wireguard", kind: "vpn", autoconnect: false,
                                           priority: 0, lastUsed: 5, active: false, port: "", device: "" })

    // Every anchor block at `path` under `item`, top to bottom in the tree
    function _blocksAt(item, path, found) {
        const blocks = found ?? [];
        for (const child of item?.children ?? []) {
            if (child.isAnchorBlock === true && child.path === path)
                blocks.push(child);
            _blocksAt(child, path, blocks);
        }
        return blocks;
    }

    // The popup's VPN rows, by VPN id
    function _vpnRows() {
        const rows = {};
        for (const row of _blocksAt(_popupView?.loader.item, "popup.network.connections.vpn.row"))
            rows[row.vpn?.uuid ?? ""] = row;
        return rows;
    }

    // The VPN page's cards, by VPN id, and in the page's order
    function _vpnCards() {
        const cards = {};
        for (const card of _blocksAt(_vpnPage?.loader.item, "settings.network_vpn.vpns.card"))
            cards[card.vpn?.uuid ?? ""] = card;
        return cards;
    }

    function _vpnCardOrder() {
        return _blocksAt(_vpnPage?.loader.item, "settings.network_vpn.vpns.card").filter(card => card.visible)
            .sort((a, b) => a.mapToItem(null, 0, 0).y - b.mapToItem(null, 0, 0).y).map(card => card.vpn?.uuid ?? "");
    }

    function _setEntries(moduleId, entries) {
        Modules.host.mainObject(moduleId).provider.entries = entries.map(entry => ({ id: entry[0], name: entry[1], state: entry[2] ?? "",
                                                                                     attention: null, detail: {} }));
    }

    function _vpnLive(moduleId) {
        const main = Modules.host.mainObject(moduleId);
        return main ? Object.keys(main.live).sort().map(key => key + ":" + main.live[key]).join(",") : "?";
    }

    // The texts shown under `item`
    function _texts(item, found) {
        const texts = found ?? [];
        for (const child of item?.children ?? []) {
            if (!child.visible)
                continue;
            if (typeof child.text === "string" && child.font !== undefined)
                texts.push(child.text);
            _texts(child, texts);
        }
        return texts;
    }

    // The first shown text item under `item` reading `text`, or null
    function _textItem(item, text) {
        for (const child of item?.children ?? []) {
            if (!child.visible)
                continue;
            if (child.text === text && child.font !== undefined)
                return child;
            const found = _textItem(child, text);
            if (found)
                return found;
        }
        return null;
    }

    // The first item under `item` with that objectName, or null
    function _blockChild(item, name) {
        for (const child of item?.children ?? []) {
            if (child.objectName === name)
                return child;
            const found = _blockChild(child, name);
            if (found)
                return found;
        }
        return null;
    }

    // The keys of an element's context, sorted, with what each holds for the checks
    function _contextKeys(element) {
        return Object.keys(element?.context ?? {}).sort().join(",");
    }

    // Where the popup's rows and the page's cards stand still (a layout places its children in
    // its polish pass, after they are built)
    property string _lastVpnViews: ""
    function _vpnViewsSteady() {
        const parts = [];
        const add = item => parts.push(Math.round(item.mapToItem(null, 0, 0).y * 100) / 100 + ":" + Math.round(item.height * 100) / 100);
        const rows = _vpnRows();
        for (const id of Object.keys(rows).sort()) {
            add(rows[id]);
            rows[id].afterHost.items.forEach(add);
        }
        const cards = _vpnCards();
        for (const id of Object.keys(cards).sort()) {
            add(cards[id]);
            cards[id].settingsRegion.prependHost.items.forEach(add);
        }
        const described = parts.join(" ");
        const steady = described === _lastVpnViews;
        _lastVpnViews = described;
        return steady;
    }

    // ---- A card's buttons (its region `actions`) ----

    property var _driver: QT.TestCase {
        name: "AnchorsDriver"
        when: false
    }
    // Buttons kept to see that they stay the same objects
    property var _keptButtons: []
    // Where the button under a hidden one stood before
    property real _nextButtonY: 0

    // The first child of `item` of a type (its name as the engine prints it), or null
    function _child(item, typeName) {
        return Array.from(item?.children ?? []).find(child => String(child).startsWith(typeName)) ?? null;
    }

    // The buttons of the anchors-buttons fixture standing now: "<name>|<anchor>|<itemId>:<count>"
    function _buttonsLive() {
        const main = host.mainObject("anchors-buttons");
        return main ? Object.keys(main.live).sort().map(key => key + ":" + main.live[key]).join(",") : "?";
    }

    // What is wrong with where a card's buttons stand: `items` top to bottom, the first 4 under
    // the primary controls' slot (the region's top), each 4 under the one above, each ending
    // on the stack's right edge (the region's), each a whole number of pixels wide, the region
    // ending with the last
    function _stackProblems(card, items) {
        const problems = [];
        const region = card.actionsRegion;
        const at = item => {
            const corner = item.mapToItem(card, 0, 0);
            return { y: corner.y, right: corner.x + item.width, bottom: corner.y + item.height, width: item.width };
        };
        const edge = at(region).right;
        let bottom = at(region).y;
        for (const item of items) {
            const name = item.objectName !== "" ? item.objectName : item.label;
            const where = at(item);
            if (Math.abs(where.y - (bottom + 4)) > 0.01)
                problems.push(name + " at " + where.y + ", not 4 under " + bottom);
            if (Math.abs(where.right - edge) > 0.01)
                problems.push(name + " ends at " + where.right + ", not on the stack's right edge (" + edge + ")");
            if (Math.abs(where.width - Math.round(where.width)) > 0.001)
                problems.push(name + " " + where.width + " wide: not on whole pixels");
            bottom = where.bottom;
        }
        if (Math.abs(at(region).bottom - bottom) > 0.01)
            problems.push("the stack ends at " + at(region).bottom + ", not with its last button (" + bottom + ")");
        return problems;
    }

    // ---- The Wi-Fi and Ethernet pages: the saved networks' and the wired profiles' cards ----

    // The first shown item under `item` that `test` accepts, depth first, or null
    function _shownItem(item, test) {
        for (const child of item?.children ?? []) {
            if (!child.visible)
                continue;
            if (test(child))
                return child;
            const found = _shownItem(child, test);
            if (found)
                return found;
        }
        return null;
    }

    // What is wrong with a page's section titles: each section with buttons on its title's line
    // has its last one ending at the line's right edge, each centred on the line; `count` the
    // buttons looked at
    function _titleButtonProblems(page, count) {
        const problems = [];
        let seen = 0;
        for (const section of Object.values(_sectionsOf(page))) {
            const frame = section.frame;
            const row = frame.children[frame.children.length - 1];
            const buttons = Array.from(row.children).filter(child => child.visible && child.width > 0);
            if (buttons.length === 0)
                continue;
            for (const button of buttons) {
                seen++;
                const corner = button.mapToItem(frame, 0, 0);
                if (Math.abs(corner.y - (frame.height - button.height) / 2) > 0.01)
                    problems.push(section.path + ": [" + button.label + "] at " + corner.y + ", not centred on the title's line");
            }
            const last = buttons[buttons.length - 1];
            const right = last.mapToItem(frame, 0, 0).x + last.width;
            if (Math.abs(right - frame.width) > 0.01)
                problems.push(section.path + ": [" + last.label + "] ends at " + right + ", not at the title line's right edge (" + frame.width + ")");
            if (Math.abs(frame.mapToItem(section, 0, 0).x + frame.width - section.width) > 0.01)
                problems.push(section.path + ": the title's line is not as wide as the section");
        }
        if (seen !== count)
            problems.push(seen + " title buttons, not " + count);
        return problems;
    }

    // The sections of a page, by path
    function _sectionsOf(page) {
        const sections = {};
        const walk = item => {
            for (const child of item?.children ?? []) {
                if (child.isAnchorBlock === true && child.kind === "section")
                    sections[child.path] = child;
                walk(child);
            }
        };
        walk(page?.loader.item);
        return sections;
    }

    // What is wrong with where an open network card's parts stand, in its frame: the primary
    // button on the stack's right edge; the stack (Edit connection…, `buttons` a module added,
    // Forget) 4 apart; the rows 8 in and across the card — "Connect automatically" 6 under the
    // header (the name's line or the stack, whichever ends lower), priority 12 under it (the
    // switch keeps 6 under itself), then the page's: the Wi-Fi password's title 6 under
    // priority and its field's line 4 under that, the field 6 short of Save at the right
    // margin; the frame 8 under the last (`element`, a module's element under the rows, if
    // any), or 14 with no row of the page's (their place keeps 6)
    function _openCardRowsProblems(card, password, buttons, element) {
        const problems = [];
        const frame = card.frame;
        const at = item => {
            const corner = item.mapToItem(frame, 0, 0);
            return { x: corner.x, y: corner.y, right: corner.x + item.width, bottom: corner.y + item.height, width: item.width };
        };
        const expect = (name, actual, expected) => {
            if (Math.abs(actual - expected) > 0.01)
                problems.push(name + " " + Math.round(actual * 100) / 100 + ", not " + Math.round(expected * 100) / 100);
        };
        const stack = [_blockChild(card, "profileEdit")].concat(buttons ?? [], [_blockChild(card, "profileForget")]);
        problems.push(..._stackProblems(card, stack));
        expect("the primary button's right", at(_blockChild(card, "profilePrimary")).right, at(card.actionsRegion).right);
        const subtitle = _textItem(card, card.subtitle);
        const autoconnect = _shownItem(card, item => item.label === card.autoconnectLabel && typeof item.toggled === "function");
        const priorityText = _textItem(card, "Priority");
        if (!subtitle || !autoconnect || !priorityText)
            return problems.concat(["the name's line, Connect automatically and Priority show"]);
        const headerBottom = Math.max(at(subtitle).bottom, at(card.actionsRegion).bottom);
        const width = frame.width;
        const row = (name, item, top) => {
            expect(name + " at y", at(item).y, top);
            expect(name + " at x", at(item).x, 8);
            expect(name + " wide", at(item).width, width - 16);
            return at(item).bottom;
        };
        let bottom = row("Connect automatically", autoconnect, headerBottom + 6);
        bottom = row("priority", priorityText.parent.parent, bottom + 12);
        if (password) {
            const title = _textItem(card, "Password");
            const field = _blockChild(card, "wifiPassword");
            if (!title || !field)
                return problems.concat(["the password's title and field show"]);
            expect("the password's title at y", at(title).y, bottom + 6);
            expect("the password's title at x", at(title).x, 8);
            const line = field.parent;
            bottom = row("the password's line", line, at(title).bottom + 4);
            const save = Array.from(line.children).filter(child => child.visible).pop();
            expect("Save's right", at(save).right, width - 8);
            expect("the field's right", at(field).right, at(save).x - 6);
            expect("the field at x", at(field).x, 8);
        }
        // No row of the page's: nothing left under the card's own (an opened card ends 8
        // under its last line)
        if (element) {
            expect("the module's element at y", at(element).y, bottom + 6);
            bottom = at(element).bottom;
        }
        expect("the frame's height", frame.height, bottom + 8);
        return problems;
    }

    // A network page as the settings window's page loader holds it, in a layer surface in a
    // corner
    property Component _networkPageViewComponent: Component {
        PanelWindow {
            id: networkPageWindow

            property string page: ""
            property url source
            property alias loader: networkPageLoader

            anchors {
                top: true
                left: true
            }
            implicitWidth: 520
            implicitHeight: 1000
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "h2s-tests"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Loader {
                id: networkPageLoader
                property string anchorBase: "settings." + networkPageWindow.page
                anchors.fill: parent
                source: networkPageWindow.source
            }
        }
    }
    property var _wifiPage: null
    property var _ethernetPage: null
    // An element kept to see that it stays the same object
    property var _keptNetwork: null
    property int _keptNetworkChanges: 0
    property var _keptWired: null
    // The name's line of the network cards (1.28): where the names stood before any module, a
    // title element kept across reads, the card whose name is made long
    property var _titleLinesBefore: null
    property var _keptTitle: null
    property int _keptTitleChanges: 0
    property var _longNameCard: null

    // The elements shown on a card's name line, left to right
    function _titleElements(card) {
        const items = card?.titleRegion?.appendHost.items ?? [];
        return items.filter(item => item.ready && item.elementShown).sort((a, b) => a.x - b.x);
    }

    // The objectNames of those elements, left to right
    function _titleNames(card) {
        return _titleElements(card).map(item => item.item.objectName).join(",");
    }

    // Where a card's name stands in the card, rounded
    function _titleLine(card) {
        const title = card.titleText;
        const point = title.mapToItem(card, 0, 0);
        return [point.x, point.y, title.width, title.height].map(value => Math.round(value * 100) / 100);
    }

    // What is wrong with where a card's name-line elements stand: on the name's line, each as
    // tall as it, after the name as drawn, at most a quarter of the card all together, inside
    // the name's column, clear of the card's own parts (the buttons, the lock, the arrow, the
    // line under the name)
    function _titleProblems(card) {
        const problems = [];
        const region = card.titleRegion;
        const title = card.titleText;
        const elements = _titleElements(card);
        if (elements.length === 0)
            return ["no element on the name's line"];
        const rect = item => {
            const point = item.mapToItem(card, 0, 0);
            return { left: point.x, top: point.y, right: point.x + item.width, bottom: point.y + item.height };
        };
        const place = rect(region);
        const line = rect(title);
        if (Math.abs(place.top - line.top) > 0.5 || Math.abs(place.bottom - line.bottom) > 0.5)
            problems.push("not the name's line (" + place.top + "–" + place.bottom + " against " + line.top + "–" + line.bottom + ")");
        for (const element of elements) {
            const shown = rect(element);
            if (Math.abs(element.height - title.height) > 0.5 || Math.abs(element.item.height - title.height) > 0.5)
                problems.push(element.item.objectName + " not as tall as the name's line (" + element.item.height + ", " + title.height + ")");
            if (shown.top < line.top - 0.5 || shown.bottom > line.bottom + 0.5)
                problems.push(element.item.objectName + " off the name's line");
        }
        if (region.width > Math.floor(card.width / 4) + 0.5)
            problems.push("wider than a quarter of the card (" + region.width + ", " + card.width + ")");
        if (!region.clip)
            problems.push("its elements not cut at its width");
        // Where the name is drawn in its line: on the side its effective alignment says (a
        // right-to-left name, unless aligned explicitly, is drawn on the right)
        const room = title.width - title.leftPadding - title.rightPadding;
        const drawnWidth = Math.min(title.contentWidth, room);
        const drawnLeft = title.effectiveHorizontalAlignment === Text.AlignRight ? title.width - title.rightPadding - drawnWidth
            : title.effectiveHorizontalAlignment === Text.AlignHCenter ? title.leftPadding + (room - drawnWidth) / 2 : title.leftPadding;
        if (region.x < drawnLeft + drawnWidth - 0.5)
            problems.push("over the name (at " + region.x + ", the name drawn from " + drawnLeft + ", " + drawnWidth + " wide)");
        if (place.right > line.right + 0.5)
            problems.push("past the name's column (" + place.right + " > " + line.right + ")");
        const own = [];
        const walk = item => {
            for (const child of item?.children ?? []) {
                if (!child.visible || child === region)
                    continue;
                if (/^profile|^alignedTop|^alignedPlain/.test(String(child.objectName)) || String(child).startsWith("PrivilegedMark")
                        || (typeof child.text === "string" && (child.text === "▸" || child.text === "▾")))
                    own.push(child);
                walk(child);
            }
        };
        walk(card);
        for (const part of own) {
            const other = rect(part);
            if (other.right > other.left && other.left < place.right - 0.5 && other.right > place.left + 0.5
                    && other.top < place.bottom - 0.5 && other.bottom > place.top + 0.5)
                problems.push("over " + (part.objectName || part.text || String(part)));
        }
        if (own.length === 0)
            problems.push("none of the card's own parts found");
        return problems;
    }
    // The parts of the two pages with no module, to compare with them under one
    property var _wifiPartsBefore: []
    property var _ethernetPartsBefore: []

    // Stand-in Wi-Fi details and devices, held in their singletons while set, as the profiles
    // are (_holdProfiles)
    property var _heldWifi: null
    property var _unheldWifi: null
    function _holdWifiDetails(details) {
        if (details !== null && _heldWifi === null)
            _unheldWifi = NetworkProfiles.wifi;
        if (details === null && _heldWifi === null)
            return;
        _heldWifi = details;
        NetworkProfiles.wifi = details ?? _unheldWifi ?? {};
    }
    property Connections _holdNetworkWifi: Connections {
        target: NetworkProfiles
        enabled: suite._heldWifi !== null
        function onWifiChanged() {
            if (NetworkProfiles.wifi !== suite._heldWifi)
                NetworkProfiles.wifi = suite._heldWifi;
        }
    }
    property var _heldDevices: null
    property var _unheldDevices: null
    function _holdDevices(devices) {
        if (devices !== null && _heldDevices === null)
            _unheldDevices = NetworkOverview.devices;
        if (devices === null && _heldDevices === null)
            return;
        _heldDevices = devices;
        NetworkOverview.devices = devices ?? _unheldDevices ?? [];
    }
    property Connections _holdOverviewDevices: Connections {
        target: NetworkOverview
        enabled: suite._heldDevices !== null
        function onDevicesChanged() {
            if (NetworkOverview.devices !== suite._heldDevices)
                NetworkOverview.devices = suite._heldDevices;
        }
    }

    // NetworkManager's profiles as a read gives them, new objects at each call: [uuid, name,
    // kind, last used, the device it is up on ("" not up)]
    function _networkProfiles(entries) {
        return entries.map(entry => ({ uuid: entry[0], name: entry[1], type: entry[2] === "wifi" ? "802-11-wireless" : "802-3-ethernet",
                                       kind: entry[2], autoconnect: true, priority: 0, lastUsed: entry[3], active: entry[4] !== "",
                                       port: "", device: entry[4], state: entry[4] !== "" ? "activated" : "" }));
    }
    readonly property var _wifiDetailsHeld: ({
        "anchors-home": { ssid: "Home", security: "wpa-psk", hidden: false, mode: "infrastructure", band: "" },
        "anchors-office": { ssid: "Office", security: "sae", hidden: false, mode: "infrastructure", band: "" },
        "anchors-cafe": { ssid: "Cafe", security: "", hidden: false, mode: "infrastructure", band: "" },
        "anchors-airport": { ssid: "Airport", security: "wpa-psk", hidden: false, mode: "infrastructure", band: "" },
        "anchors-spot": { ssid: "Spot", security: "wpa-psk", hidden: false, mode: "ap", band: "a" }
    })
    readonly property var _wiredDevice: ({ device: "eth-anchors", ipIface: "", type: "ethernet", kind: "ethernet", mac: "00:11:22:33:44:55", mtu: 1500,
                                          state: 100, stateText: "connected", connection: "Wired", vendor: "", product: "", driver: "", speed: 1000,
                                          carrier: "on", ipv4: [], gateway4: "", dns: [], domains: [], ipv6: [], gateway6: "" })

    // The cards of a page (every card block under it, whatever its path), by profile UUID
    function _profileCards(page) {
        const cards = {};
        const walk = item => {
            for (const child of item?.children ?? []) {
                if (child.isAnchorBlock === true && child.kind === "card")
                    cards[child.profile?.uuid ?? ""] = child;
                walk(child);
            }
        };
        walk(page?.loader.item);
        return cards;
    }

    // The cards at `path` on a page, by profile UUID
    function _cardsAt(page, path) {
        const cards = {};
        for (const card of _blocksAt(page?.loader.item, path))
            cards[card.profile?.uuid ?? ""] = card;
        return cards;
    }

    // A page's column: what its Flickable scrolls
    function _pageColumn(page) {
        for (const child of page?.loader.item?.children ?? []) {
            if (child.contentHeight !== undefined && child.contentItem)
                return child.contentItem.children[0] ?? null;
        }
        return null;
    }

    // A network page's parts top to bottom, as { name, x, y, width, height } in its column:
    // what stands in its columns, looked into through the columns, plain items and blocks
    // other than cards, never into a part. A card is named by its title, a line of a title and
    // buttons by its first text, a text by itself, a part in a file of its own by its type
    function _pageParts(page) {
        const column = _pageColumn(page);
        const parts = [];
        if (!column)
            return parts;
        const typeOf = item => String(item).replace(/\(.*$/, "").replace(/_QML(TYPE)?_\d+$/, "");
        const isCard = item => item.isAnchorBlock === true && item.kind === "card";
        const opens = item => (item.isAnchorBlock === true && !isCard(item) && item.contributions === undefined)
            || /^QQuick(Column|ColumnLayout|Item|Loader)(_QML_\d+)?\(/.test(String(item));
        const firstText = item => {
            if (!item.visible)
                return "";
            if (typeof item.text === "string" && item.font !== undefined && /[A-Za-z]/.test(item.text))
                return item.text;
            for (const child of item.children ?? []) {
                const text = firstText(child);
                if (text !== "")
                    return text;
            }
            return "";
        };
        const nameOf = item => {
            if (isCard(item))
                return "card " + item.title;
            if (item.contributions !== undefined)
                return "modules";
            if (typeof item.text === "string" && item.font !== undefined)
                return "text " + item.text.slice(0, 18);
            if (/^QQuickRowLayout/.test(String(item)))
                return "text " + firstText(item).slice(0, 18);
            return typeOf(item);
        };
        const walk = item => {
            for (const child of item.children ?? []) {
                if (!child.visible || child.width <= 0 || child.height <= 0)
                    continue;
                if (opens(child)) {
                    walk(child);
                    continue;
                }
                const point = child.mapToItem(column, 0, 0);
                parts.push({ name: nameOf(child), x: point.x, y: point.y, width: child.width, height: child.height });
            }
        };
        walk(column);
        return parts.sort((a, b) => a.y - b.y || a.x - b.x);
    }

    // What is wrong with where a page's parts stand: `expected` [[name, the gap above it,
    // whether it is as wide as the column]], each at the column's left edge — measured from
    // each part's own height, so no font changes it
    function _pagePartsProblems(page, expected) {
        const parts = _pageParts(page);
        const width = _pageColumn(page)?.width ?? -1;
        if (parts.map(part => part.name).join("|") !== expected.map(entry => entry[0]).join("|"))
            return ["the parts: " + parts.map(part => part.name).join("|")];
        const problems = [];
        parts.forEach((part, index) => {
            const [name, gap, full] = expected[index];
            const top = index === 0 ? gap : parts[index - 1].y + parts[index - 1].height + gap;
            if (Math.abs(part.y - top) > 0.01)
                problems.push(name + " at y " + part.y + ", not " + top);
            if (Math.abs(part.x) > 0.01)
                problems.push(name + " at x " + part.x + ", not 0");
            if (full && Math.abs(part.width - width) > 0.01)
                problems.push(name + " " + part.width + " wide, not " + width);
        });
        return problems;
    }

    // Everything a page shows, for comparing two versions of it on one machine: each text
    // (where it is drawn: its position, the width of its letters, its height), each button,
    // each card's frame and each named item, in the page loader's coordinates
    function _pageFingerprint(page) {
        const loader = page.loader;
        const entries = [];
        const round = value => Math.round(value * 100) / 100;
        const walk = item => {
            for (const child of item.children ?? []) {
                if (!child.visible)
                    continue;
                const point = child.mapToItem(loader, 0, 0);
                const at = [round(point.x), round(point.y)];
                if (typeof child.text === "string" && child.font !== undefined) {
                    if (child.text !== "")
                        entries.push("'" + child.text.slice(0, 24) + "' " + at.concat([round(child.contentWidth), round(child.height)]).join(" "));
                    continue;
                }
                if (typeof child.label === "string" && child.clicked !== undefined) {
                    entries.push("[" + child.label + "] " + at.concat([round(child.width), round(child.height)]).join(" "));
                    continue;
                }
                if (child.isAnchorBlock === true && child.kind === "card")
                    entries.push("card " + child.title + " " + at.concat([round(child.width), round(child.height)]).join(" "));
                else if (child.objectName !== "")
                    entries.push(child.objectName + " " + at.concat([round(child.width), round(child.height)]).join(" "));
                walk(child);
            }
        };
        walk(loader.item);
        return entries.join(" · ");
    }

    // What is wrong with the Wi-Fi page's heading: the Wi-Fi switch on the heading's line, at
    // its right edge (the column's), centred on it, showing whether Wi-Fi is on; no "Wi-Fi"
    // switch row under it
    function _wifiHeadingProblems(page) {
        const column = _pageColumn(page);
        const toggle = _shownItem(column, item => item.objectName === "wifiSwitch");
        if (!toggle)
            return ["no Wi-Fi switch"];
        const line = toggle.parent;
        const problems = [];
        const point = toggle.mapToItem(column, 0, 0);
        const linePoint = line.mapToItem(column, 0, 0);
        if (Math.abs(point.x + toggle.width - column.width) > 0.01)
            problems.push("the switch ends at " + (point.x + toggle.width) + ", not at the column's right edge (" + column.width + ")");
        if (Math.abs(point.y - (linePoint.y + (line.height - toggle.height) / 2)) > 0.01)
            problems.push("the switch at " + point.y + ", not centred on the heading's line");
        if (!_textItem(line, "Wi-Fi"))
            problems.push("the switch not on the heading's line");
        if (toggle.checked !== WifiManager.wifiEnabled)
            problems.push("the switch shows " + toggle.checked + ", Wi-Fi is " + WifiManager.wifiEnabled);
        if (_shownItem(column, item => item.label === "Wi-Fi" && typeof item.toggled === "function"))
            problems.push("a Wi-Fi switch row still shown");
        return problems;
    }

    // The Wi-Fi page with every card closed: the heading's line across the page (the Wi-Fi
    // switch on its right), the saved networks' title 22 lower (the heading's 8 and the
    // title's 14), each saved network's card 6 apart (the one in use, the one in range, the one
    // out of range), the hotspots' title 20 under the last, the hotspot's card, the form for a
    // hidden network 20 lower
    readonly property var _wifiPageExpected: [["text Wi-Fi", 0, true], ["text Saved networks", 22, true],
        ["card Home", 6, true], ["card Office", 6, true], ["card Cafe", 6, true], ["text Hotspots", 20, true], ["card Spot", 6, true],
        ["HiddenNetworkRow", 20, true]]
    // The Ethernet page: the heading, the wired device's card 8 under it, the wired profiles'
    // title 26 lower, each profile's card 6 apart (the one in use first)
    readonly property var _ethernetPageExpected: [["text Ethernet", 0, false], ["NetworkDeviceCard", 8, true], ["text Wired profiles", 26, false],
        ["card Wired", 6, true], ["card Lab", 6, true]]

    // Where both pages' parts stand still (a layout places its children in its polish pass,
    // after they are built)
    property string _lastNetworkPages: ""
    function _networkPagesSteady() {
        const described = [_wifiPage, _ethernetPage].map(page => page ? _describeParts(_pageParts(page)) : "-").join(" / ")
            + [_wifiPage, _ethernetPage].map(page => page ? _pageFingerprint(page) : "-").join(" / ");
        const steady = described === _lastNetworkPages;
        _lastNetworkPages = described;
        return steady;
    }

    // The parts of `after` against `before`: the same, those under `card` lower by `shift`,
    // `card` itself taller by it
    function _shiftedProblems(before, after, card, shift) {
        if (before.map(part => part.name).join("|") !== after.map(part => part.name).join("|"))
            return ["the parts: " + after.map(part => part.name).join("|")];
        const problems = [];
        const index = before.findIndex(part => part.name === card);
        before.forEach((part, i) => {
            const moved = after[i];
            const y = part.y + (i > index ? shift : 0);
            const height = part.height + (i === index ? shift : 0);
            if (Math.abs(moved.y - y) > 0.01 || Math.abs(moved.height - height) > 0.01 || Math.abs(moved.x - part.x) > 0.01 || Math.abs(moved.width - part.width) > 0.01)
                problems.push(part.name + " at " + [moved.x, moved.y, moved.width, moved.height].join(" ") + ", not " + [part.x, y, part.width, height].join(" "));
        });
        return problems;
    }

    // The elements of the network fixture standing now: "<anchor>|<networkId>:<count>"
    function _networkLive() {
        const main = Modules.host.mainObject("anchors-networks");
        return main ? Object.keys(main.live).sort().map(key => key + ":" + main.live[key]).join(",") : "?";
    }

    // What is wrong with where a card's element stands: in its opened part, under the page's
    // own rows (the card's rows' column) `spacing` apart, last, as wide as the part
    function _regionElementProblems(card) {
        const region = card.settingsRegion;
        const element = region.appendHost.items[0];
        if (!element)
            return ["no element"];
        const siblings = region.appendHost.parent.children;
        let rows = null;
        for (let i = 0; i < siblings.length; i++) {
            if (siblings[i] === region.appendHost)
                rows = siblings[i - 1];
        }
        const problems = [];
        const top = element.mapToItem(card, 0, 0).y;
        const rowsBottom = rows.mapToItem(card, 0, 0).y + rows.height;
        if (Math.abs(top - (rowsBottom + card.spacing)) > 0.01)
            problems.push("the element at " + top + ", not " + card.spacing + " under the rows (" + rowsBottom + ")");
        if (Math.abs(element.mapToItem(region, 0, 0).y + element.height - region.height) > 0.01)
            problems.push("the element is not last in the opened part");
        if (Math.abs(element.width - region.width) > 0.01 || Math.abs(element.mapToItem(region, 0, 0).x) > 0.01)
            problems.push("the element " + element.width + " wide, not " + region.width);
        return problems;
    }

    // The suite's bar (two cells) and a popup on its screen, as the bar opens it
    property var _popupBar: null
    property var _realPopup: null
    property var _popupCellA: null
    property var _popupCellB: null
    property int _popupCycles: 0

    function _makePopup() {
        _popupBar = Qt.createQmlObject("import QtQuick; import Quickshell; import Quickshell.Wayland; PanelWindow {"
            + " anchors { top: true; left: true } implicitWidth: 300; implicitHeight: 40; color: \"transparent\";"
            + " exclusionMode: ExclusionMode.Ignore; WlrLayershell.layer: WlrLayer.Overlay; WlrLayershell.namespace: \"h2s-tests\";"
            + " WlrLayershell.keyboardFocus: WlrKeyboardFocus.None; property alias cellA: cellA; property alias cellB: cellB;"
            + " Row { Item { id: cellA; width: 100; height: 40 } Item { id: cellB; width: 100; height: 40 } } }", suite);
        _popupCellA = _popupBar.cellA;
        _popupCellB = _popupBar.cellB;
        const component = Qt.createComponent(Qt.resolvedUrl("../panels/Popup.qml"), Component.PreferSynchronous);
        _realPopup = component.createObject(suite, { popupPosition: 0, popupLength: 0, barScreen: _popupBar.screen ?? Quickshell.screens[0], barEdge: "top" });
        if (!_realPopup)
            fail("the popup can be made (" + component.errorString() + ")");
    }

    function _dropPopup() {
        _realPopup?.destroy();
        _popupBar?.destroy();
        _realPopup = _popupBar = _popupCellA = _popupCellB = null;
    }

    function _popupShown() {
        return _realPopup?.active === true && _realPopup.item?.showPopup === true && !_realPopup.closing;
    }

    // The block at `path` in the suite's popup, or null
    function _inPopup(path) {
        return _realPopup?.item ? _blockAt(_realPopup.item.contentItem, path) : null;
    }

    function _open(base) {
        const view = _viewComponent.createObject(suite, { base: base ?? "settings.fixture" });
        _views.push(view);
        return view;
    }

    function _close(view) {
        _views = _views.filter(each => each !== view);
        view.destroy();
    }

    // ---- Helpers ----

    function _settled() {
        return host.statuses.length > 0 && !host.statuses.some(status => status.state === "pending") && !host.checkingFiles;
    }

    function _has(list, fragment) {
        return (list ?? []).some(entry => String(entry).includes(fragment));
    }

    function _ready(hostItem, count) {
        return hostItem.items.length === count && hostItem.items.every(item => item.ready);
    }

    // The elements of view `view` all built (on the page's end, anchors-b's too while it is on)
    function _allBuilt(view) {
        const appended = host.status("anchors-b")?.state === "loaded" ? 3 : 2;
        return _ready(view.page.prependHost, 1) && _ready(view.page.appendHost, appended) && _ready(view.box.beforeHost, 1)
            && _ready(view.box.prependHost, 1) && _ready(view.box.appendHost, 1) && _ready(view.box.afterHost, 1);
    }

    // Top to bottom, what a view shows, as [name, y in the page]
    function _sequence(view) {
        const y = item => item.mapToItem(view.page, 0, 0).y;
        const page = view.page;
        const box = view.box;
        return [["page.prepend", y(page.prependHost.items[0])], ["page content", y(view.inside)], ["box.before", y(box.beforeHost.items[0])],
                ["box frame", y(box.frame)], ["box.prepend", y(box.prependHost.items[0])], ["box content", y(view.boxContent)],
                ["box.append", y(box.appendHost.items[0])], ["box.after", y(box.afterHost.items[0])],
                ["page.append 1", y(page.appendHost.items[0])], ["page.append 2", y(page.appendHost.items[1])],
                ["page.append 3", y(page.appendHost.items[2])]];
    }

    function _inOrder(view) {
        if (!_allBuilt(view))
            return false;
        const sequence = _sequence(view);
        return sequence.every((entry, index) => index === 0 || entry[1] > sequence[index - 1][1]);
    }

    function _names(hostItem) {
        return hostItem.items.map(item => item.item?.objectName ?? "?").join(",");
    }

    function _live(prefix) {
        return Object.keys(Anchors.live).filter(path => path === prefix || path.startsWith(prefix + ".")).sort()
            .map(path => path + ":" + Anchors.live[path]).join(",");
    }

    function runAsync() {
        _then("the suite before is done, the config read", () => (after === null || after.done) && Config.ready, () => {
            _savedDisabled = host._plainList(Config.disabledModules);
            Config.disabledModules = [];
            // This shell's table, as the API hands it out
            assertEqual(ModuleRules.anchorTableProblems(ModuleRules.anchorTable).join("; "), "", "this shell's anchor table is well formed");
            assert(!ModuleRules.anchorTable.some(row => /lock|screensaver/.test(row.path)), "… nothing on the lock screen or the screensaver");
            assertEqual(JSON.stringify(Api.anchors), JSON.stringify(ModuleRules.anchorTable), "Api.anchors: the anchor table");
            assert(Object.isFrozen(Api.anchors) && Api.anchors.every(row => Object.isFrozen(row) && Object.isFrozen(row.placements)), "… frozen, each row and its placements");
            assertEqual(ModuleRules.anchorTableProblems(table).join("; "), "", "the suite's table is well formed");

            // A block reports itself once, when it is complete
            _liveChanges = 0;
            const early = Qt.createQmlObject("import QtQuick; import qs.components; Item { property string anchorBase: \"settings.fixture\"; "
                                             + "SettingsPage { anchor: \"early\"; AnchorFixtureBlock { anchor: \"inner\" } } }", suite);
            assertEqual(_live("settings.fixture.early"), "settings.fixture.early:1,settings.fixture.early.inner:1", "blocks built: each reported once");
            assertEqual(_liveChanges, 2, "… one change each, nothing reported while they were being built");
            early.destroy();

            host.anchorTable = table;
            _view = _open();
            _slotGrep.running = true;
        }, 80000);
        _then("the slot guard has read the shell's files", () => _slotUses !== null, () => {
            assertEqual(["network.popup.sections", "network.vpn.row", "network.vpn.card", "network.vpn.page"].map(slot => JSON.stringify(_slotUses[slot] ?? null)).join(" "),
                        "null null null [\"singletons/network/VpnManager.qml\"]",
                        "the slot guard finds what still builds a slot (not comments, not the rules, not the tests): the page's, still a slot; not the popup's, the VPN row's or card's any more");
            assertEqual(ModuleRules.slotAliasProblems(ModuleRules.anchorTable, ModuleRules.slotAliases, _slotUses, _viewTextsOf(ModuleRules.anchorTable)).join("; "), "",
                        "every slot read as its anchor in this shell's table: no longer built as a slot, its view builds the block and gives what the slot gave");
            const published = [_row("popup.network.connections.vpn.row", "row", ["after"], "{ vpnId }", "own-provider", "panels/network/VpnSection.qml")];
            // A view as the VPN part was before it gave the row its context, the slot still built
            // in VpnManager
            const problems = ModuleRules.slotAliasProblems(published, ModuleRules.slotAliases, { "network.vpn.row": ["singletons/network/VpnManager.qml"] },
                                                           { "panels/network/VpnSection.qml": "delegate: PopupRow {\n    readonly property var vpn: ({})\n    anchor: \"row\"\n}" });
            assert(_has(problems, "network.vpn.row → popup.network.connections.vpn.row: the slot is still built in singletons/network/VpnManager.qml"),
                   "a table publishing a place whose slot is still built: caught — " + problems.join("; "));
            assert(_has(problems, "gives no vpnId") && _has(problems, "gives no otherVpns") && !_has(problems, "gives no vpn "),
                   "… and what the slot gave and the block does not give (the VPN row names only `vpn`)");
            assert(!_has(problems, "builds no") && !_has(problems, "names no block"), "… the block is there: a row named \"row\"");
            const elsewhere = [_row("popup.network.connections", "popupSection", ["append"], "{}", "", "panels/network/LinkInfo.qml")];
            const elsewhereProblems = ModuleRules.slotAliasProblems(elsewhere, ModuleRules.slotAliases, _slotUses, _viewTextsOf(elsewhere));
            assert(_has(elsewhereProblems, "builds no PopupSection") && _has(elsewhereProblems, "names no block \"connections\"")
                   && _has(elsewhereProblems, "gives no wifiEnabled"), "a row naming a view that builds no such block: caught — " + elsewhereProblems.join("; "));
            const missing = [_row("popup.network.connections", "popupSection", ["append"], "{}", "", "panels/NoSuchView.qml")];
            assert(_has(ModuleRules.slotAliasProblems(missing, ModuleRules.slotAliases, {}, _viewTextsOf(missing)), "panels/NoSuchView.qml cannot be read"),
                   "… a view that is not there: caught");
        });
        _then("the view is up with no module", () => _view.page.flickable.contentHeight > 100, () => {
            assertEqual(_view.page.path + " " + _view.box.path + " " + _view.plain.path, "settings.fixture settings.fixture.box ",
                        "paths: the page takes the base, the box adds its name, a block with no anchor has none");
            assertEqual(_view.box.host, host, "a block's module host: the enclosing block's");
            assertEqual(_live("settings.fixture"), "settings.fixture:1,settings.fixture.box:1", "Anchors.live: the page and the box, once each; not the block with no anchor");
            assert(table.filter(row => row.path.startsWith("settings.fixture") && row.path !== "settings.fixture.vpn").every(row => Anchors.live[row.path] > 0),
                   "every fixture table path the view builds is live (the own-provider row is the view with no page's)");
            const hosts = [_view.page.prependHost, _view.page.appendHost, _view.box.beforeHost, _view.box.afterHost, _view.box.prependHost,
                           _view.box.appendHost, _view.plain.appendHost];
            assertEqual(hosts.map(each => each.count + (each.built ? "b" : "") + each.implicitHeight).join(","), "00,00,00,00,00,00,00",
                        "with no module: no host has a size or builds anything, not even its list");
            host.load([fixtures + "/anchors-b", fixtures + "/anchors-a"], {});
        });
        _then("the fixture modules settle", _settled, () => {
            const alpha = host.status("anchors-a");
            const beta = host.status("anchors-b");
            assertEqual(alpha?.state + " " + beta?.state, "loaded loaded", "both modules loaded");
            assert(_has(alpha?.errors, "anchors: \"settings.nowhere\" is not a place this shell offers (module API " + ModuleRules.apiVersion + ")"),
                   "a place this shell does not offer: an error in the module's status — " + alpha?.errors.join("; "));
            assert(_has(alpha?.errors, "anchors: \"settings.fixture\" does not take \"before\" (it takes: prepend, append)"),
                   "… a placement the place does not take, too");
            assertEqual(alpha?.errors.length + "," + alpha?.warnings.length, "2,0", "… nothing else, no warning: the rest of the module loads");
            assertEqual(alpha?.deprecations.join("|"),
                        "slots (\"settings.general.bottom\"): use `anchors`: \"settings.general\", \"append\" (goes with the shell's next tightening)",
                        "a slot whose place is offered is read as the anchor, listed among the deprecations");
            assertEqual(beta?.errors.length + "," + beta?.warnings.length + "," + beta?.deprecations.length, "0,0,0", "the other module: clean");
            assertEqual(host.slotContributions("settings.general.bottom").length, 0, "the slot read as an anchor is not a slot contribution any more");
            assertEqual(host.anchorContent("settings.nowhere", "append").length + host.anchorContent("settings.fixture", "before").length, 0,
                        "the host lists nothing for a place not offered or a placement not taken");
            // The table set anew: the modules' anchors and their errors follow
            host.anchorTable = table.concat([_row("settings.nowhere", "page", ["append"], "{}")]);
            assertEqual(host.status("anchors-a")?.errors.length + "," + host.anchorContent("settings.nowhere", "append").length, "1,1",
                        "a place added to the table: no longer an error, its element listed");
            host.anchorTable = table;
            assertEqual(host.status("anchors-a")?.errors.length + "," + host.anchorContent("settings.nowhere", "append").length, "2,0",
                        "… taken out again: the error back, nothing listed");
            assertEqual(host.anchorContent("settings.fixture.vpn", "append").length, 0, "an own-provider place with no scope: nothing");
            assertEqual(host.anchorContent("settings.fixture.vpn", "append", "anchors-b").map(entry => entry.module).join(","), "anchors-b",
                        "… with one: that module's only");
        });
        _then("every element is built and laid out", () => _inOrder(_view), () => {
            const sequence = _sequence(_view);
            console.log("  INFO: top to bottom: " + sequence.map(entry => entry[0] + " " + Math.round(entry[1])).join(" · "));
            assertEqual(_names(_view.page.appendHost), "anchors-a:Element,anchors-a:Second,anchors-b:Element",
                        "several modules at one place: by module id (loaded beta first), a module's together in its manifest's order");
            assertEqual(_names(_view.page.prependHost) + " " + _names(_view.box.beforeHost) + " " + _names(_view.box.afterHost),
                        "anchors-a:Element anchors-a:Element anchors-a:Element", "each placement its element");
            const appended = _view.page.appendHost.items[0].item;
            assertEqual(JSON.stringify(appended.context), JSON.stringify({ editIndex: 2, anchor: "settings.fixture", placement: "append" }),
                        "an element's context: the block's, with anchor and placement");
            assertEqual(JSON.stringify(_view.box.beforeHost.items[0].item.context), JSON.stringify({ boxed: true, anchor: "settings.fixture.box", placement: "before" }),
                        "… the box's own context at its places");
            assertEqual(appended.module, host.handle("anchors-a"), "each element gets its own module's handle");
            assertEqual(_view.page.appendHost.items[2].item.module, host.handle("anchors-b"), "… the other module's its own");
            assert(appended.shown, "… and `shown`: on screen");
            assertEqual(appended.text, "alpha settings.fixture append", "the element shows (plain text)");
            const model = _view.page.appendHost.repeaterModel;
            assert(model !== null && !Array.isArray(model) && model.values.length === 3 && model.values.every(value => typeof value === "string"),
                   "the elements are made from a ScriptModel of keys (module and file), never a live array on Repeater.model, never the entries themselves");
            assertEqual(_view.plain.appendHost.count + "," + _view.plain.appendHost.built, "0,false", "a block with no anchor hosts nothing");
            _betaItem = _view.page.appendHost.items[2];
            _betaElement = _betaItem.item;
            _betaContexts = _betaElement.contextChanges;
            _alphaElement = appended;
            assert(host.setEnabled("anchors-a", false), "anchors-a turned off");
        });
        _then("anchors-a is off", () => host.status("anchors-a")?.state === "disabled" && _view.page.appendHost.items.length === 1, () => {
            assertEqual(_names(_view.page.appendHost), "anchors-b:Element", "its elements are gone; the other module's stays");
            assert(_view.page.appendHost.items[0] === _betaItem && _betaItem.item === _betaElement, "… the same object: not rebuilt");
            assertEqual(_betaElement.contextChanges, _betaContexts, "… its context not handed over again");
            const emptied = [_view.page.prependHost, _view.box.beforeHost, _view.box.afterHost, _view.box.prependHost, _view.box.appendHost];
            assertEqual(emptied.map(each => each.count + (each.built ? "b" : "") + each.implicitHeight).join(","), "00,00,00,00,00",
                        "the hosts it alone filled: empty, no size, their lists gone");
            assert(host.setEnabled("anchors-a", true), "anchors-a turned on");
        });
        _then("anchors-a is on again", () => host.status("anchors-a")?.state === "loaded" && _inOrder(_view), () => {
            assertEqual(_names(_view.page.appendHost), "anchors-a:Element,anchors-a:Second,anchors-b:Element", "its elements are back, in the one order");
            assert(_view.page.appendHost.items[2].item === _betaElement, "… the other module's element still the same object");
            _alphaElement = _view.page.appendHost.items[0].item;
            host.load([fixtures + "/anchors-a", fixtures + "/anchors-b"], {});
        });
        _then("reloaded", () => _settled() && host.status("anchors-a")?.state === "loaded" && _inOrder(_view)
                                && _view.page.appendHost.items[0].item !== _alphaElement, () => {
            assertEqual(_names(_view.page.appendHost), "anchors-a:Element,anchors-a:Second,anchors-b:Element", "a reload: the same elements, in the same order");
            assert(_view.page.appendHost.items[0].item !== _alphaElement, "… built anew");
            assert(_view.page.appendHost.items[0].item.module === host.handle("anchors-a"), "… with the module's handle");
            // A block renamed (or moved) has its new path at once
            _view.box.anchor = "renamed";
            assertEqual(_view.box.path, "settings.fixture.renamed", "a block renamed: its path follows");
            assertEqual(_live("settings.fixture"), "settings.fixture:1,settings.fixture.renamed:1", "… Anchors.live too");
            assertEqual(_view.box.beforeHost.count, 0, "… and a path not in the table takes nothing");
            _view.box.anchor = "box";
            _view.plain.parent = _view.box.frame.parent;
            _view.plain.anchor = "inner";
            assertEqual(_view.plain.path, "settings.fixture.box.inner", "a block moved into another: the enclosing block's path and its name");
            _view.plain.anchor = "";
            // A second view of the same page, and the General page with a slot read as its anchor
            _open("settings.fixture");
            _open("settings.general");
        });
        _then("the box has its elements back, the other views are up", () => _allBuilt(_view) && _allBuilt(_views[1])
                                                                            && _ready(_views[2].page.appendHost, 1), () => {
            assertEqual(_live("settings.fixture"), "settings.fixture:2,settings.fixture.box:2", "two views of one page: each path live twice");
            assertEqual(_live("settings.general"), "settings.general:1,settings.general.box:1",
                        "the General fixture: the page, and its box live but named, not published");
            const slotElement = _views[2].page.appendHost.items[0].item;
            assertEqual(slotElement?.objectName, "anchors-a:Element", "a slot read as its anchor: the module's slot file at the place");
            assertEqual(JSON.stringify(slotElement?.context), JSON.stringify({ editIndex: 2, slot: "settings.general.bottom", anchor: "settings.general", placement: "append" }),
                        "… its context carrying the slot's name, as the old name promised");
            assertEqual(_views[2].box.beforeHost.count, 0, "… a block whose path is not in the table takes nothing");
            _close(_views[2]);
            _close(_views[1]);
        });
        _then("two views closed", () => _live("settings.general") === "", () => {
            assertEqual(_live("settings.fixture"), "settings.fixture:1,settings.fixture.box:1", "a view closed: its blocks leave Anchors.live; the view still open stays");
            _close(_view);
            _view = null;
        });
        _then("the last view closed", () => _live("settings.fixture") === "", () => {
            _plain = _plainViewComponent.createObject(suite);
            _views.push(_plain);
        });
        _then("the view with no page is built", () => _ready(_plain.vpnA.appendHost, 1) && _ready(_plain.vpnB.appendHost, 1)
                                                       && _ready(_plain.fewer.prependHost, 1), () => {
            assertEqual(_live("settings.fixture"), "settings.fixture.box:2,settings.fixture.vpn:3",
                        "sections with no anchor straight under a plain item: not addressable, not the page");
            const empty = hostItem => hostItem.count + (hostItem.built ? "b" : "");
            const sections = [0, 1, 2].map(index => _plain.sections.itemAt(index));
            assertEqual(sections.map(section => [section.path, empty(section.prependHost), empty(section.appendHost)].join("/")).join(" "),
                        "/0/0 /0/0 /0/0", "… none builds the page's elements");
            const wrong = _plain.wrongKind;
            assertEqual([wrong.beforeHost, wrong.prependHost, wrong.appendHost, wrong.afterHost].map(empty).join(","), "0,0,0,0",
                        "a block of another kind than its row's: shows nothing");
            const fewer = _plain.fewer;
            assertEqual([fewer.beforeHost, fewer.prependHost, fewer.appendHost, fewer.afterHost].map(empty).join(","), "0,1b,0,0",
                        "a block shows only the placements it has");
            assertEqual(_names(_plain.vpnA.appendHost) + " " + _names(_plain.vpnB.appendHost) + " " + empty(_plain.vpnNone.appendHost),
                        "anchors-a:Element anchors-b:Element 0", "an own-provider row: each item only its provider module's element, none with no provider");
            assertEqual(_plain.vpnA.appendHost.items[0].item.context.anchor, "settings.fixture.vpn", "… at the row's path");
            _close(_plain);
            _plain = null;
        });
        _then("the view with no page closed", () => _live("settings.fixture") === "", () => {
            _view = _open();
        });

        // Opened and closed over and over, each time built to the end, with a module turned
        // off and on between; then opened and closed in one go, before anything is built
        const cycle = number => {
            _then("the view built (cycle " + number + ")", () => _view !== null && _allBuilt(_view), () => {
                _cycles++;
                _close(_view);
                _view = null;
                if (_cycles === 5)
                    host.setEnabled("anchors-b", false);
                if (_cycles === 7)
                    host.setEnabled("anchors-b", true);
            });
            _then("… opened again", () => host.status("anchors-b")?.state === (number >= 5 && number < 7 ? "disabled" : "loaded"), () => {
                _view = _open();
            });
        };
        for (let i = 1; i <= 10; i++)
            cycle(i);
        _then("ten times opened and closed", () => _view !== null && _allBuilt(_view) && _live("settings.fixture") === "settings.fixture:1,settings.fixture.box:1", () => {
            assertEqual(_cycles, 10, "the view opened and closed ten times, built each time");
            assertEqual(_live("settings.fixture"), "settings.fixture:1,settings.fixture.box:1", "… one view live now (the closed ones gone)");
            _close(_view);
            _view = null;
            for (let i = 0; i < 10; i++)
                _close(_open());
            _waitUntil = Date.now() + 300;
        });
        _then("views closed before they were built leave nothing live", () => Date.now() >= _waitUntil && _live("settings.fixture") === "", () => {
            assertEqual(host.status("anchors-a")?.errors.length, 2, "no element failed meanwhile (the module's errors are its two anchors)");
        });

        // Sections and cards: the section's placements, the cards' before and after, the
        // opened part (the region `settings`) only while the card is open, the scope, the
        // cards following their list
        _then("the fixture views are closed", () => _live("settings.fixture") === "", () => {
            _tracker.reset();
            host.load([fixtures + "/anchors-cards-b", fixtures + "/anchors-cards-a"], {});
            _openCards(_cardItems(["one", "two", "three"]),
                       [{ id: "v1", provider: "anchors-cards-a" }, { id: "v2", provider: "anchors-cards-b" }, { id: "v3", provider: "" }]);
        });
        _then("the section and the closed cards are built and laid out", () => _settled() && host.status("anchors-cards-a")?.state === "loaded"
              && _cardsBuilt() && _cardsSteady(), () => {
            assertEqual(host.status("anchors-cards-a")?.errors.length + "," + host.status("anchors-cards-b")?.errors.length, "0,0",
                        "the cards' fixture modules: clean (a region's places are places)");
            const section = _cards.saved;
            const cards = _savedCardList();
            assertEqual([section.path, cards[0].path, cards[0].settingsRegion.path, _vpnCard(0).settingsRegion.path].join(" "),
                        "settings.cards.saved settings.cards.saved.card settings.cards.saved.card.settings settings.cards.vpns.card.settings",
                        "paths: the section, its cards by their kind, a card's region under it");
            assertEqual(_live("settings.cards"), ["settings.cards:1", "settings.cards.saved:1", "settings.cards.saved.card:3", "settings.cards.saved.card.actions:3",
                                                   "settings.cards.saved.card.settings:3", "settings.cards.saved.card.title:3", "settings.cards.vpns:1", "settings.cards.vpns.card:3",
                                                   "settings.cards.vpns.card.actions:3", "settings.cards.vpns.card.settings:3", "settings.cards.vpns.card.title:3"].join(","),
                        "Anchors.live: each card and its three regions, once per card, open or closed");
            // Top to bottom: section.before · the title's line · section.prepend · its own
            // content · each card (before · frame · after) · section.append · section.after
            const sequence = [["section.before", _yIn(section.beforeHost.items[0])], ["title", _yIn(section.frame)],
                              ["section.prepend", _yIn(section.prependHost.items[0])], ["section content", _yIn(_cards.intro)]];
            cards.forEach((card, index) => sequence.push(["card " + index + ".before", _yIn(card.beforeHost.items[0])], ["card " + index, _yIn(card.frame)],
                                                         ["card " + index + ".after", _yIn(card.afterHost.items[0])]));
            sequence.push(["section.append", _yIn(section.appendHost.items[0])], ["section.after", _yIn(section.afterHost.items[0])]);
            console.log("  INFO: the section top to bottom: " + sequence.map(entry => entry[0] + " " + Math.round(entry[1])).join(" · "));
            assert(sequence.every((entry, index) => index === 0 || entry[1] > sequence[index - 1][1]),
                   "the section's placements and its cards' in the one order: " + sequence.map(entry => entry[0]).join(" < "));
            const titleBottom = _yIn(section.frame) + section.frame.height;
            assert(_yIn(section.prependHost.items[0]) >= titleBottom, "… a prepended element under the title's line, not beside it");
            assertEqual(JSON.stringify(Object.assign({}, section.beforeHost.items[0].item.context, { tracker: null })),
                        JSON.stringify({ tracker: null, anchor: "settings.cards.saved", placement: "before" }), "the section's element: the section's context");
            assertEqual(cards[1].beforeHost.items[0].item.context.itemId + " " + cards[1].beforeHost.items[0].item.context.anchor, "two settings.cards.saved.card",
                        "a card's element: its card's item in the context");
            assertEqual(cards.concat([_vpnCard(0), _vpnCard(1), _vpnCard(2)]).map(card => card.settingsRegion.prependHost.built || card.settingsRegion.appendHost.built
                                                                                   || card.settingsRegion.visible).join(","),
                        "false,false,false,false,false,false", "closed cards: their region hidden, its hosts build nothing");
            assertEqual(_tracker.count() + " " + _tracker.count("card.settings"), "10 0", "… ten elements made: the section's four, each card's two beside it");
            _cards.openId = "two";
        });
        _then("the second card open, its region built and laid out", () => _regionBuilt(1) && _cardsSteady()
              && _openCardProblems(_savedCard(1)).length === 0, () => {
            const card = _savedCard(1);
            assertEqual(_names(card.settingsRegion.prependHost) + " " + _names(card.settingsRegion.appendHost),
                        "anchors-cards-a:Element anchors-cards-a:Element,anchors-cards-b:Element",
                        "the opened card's region: each placement its elements, by module id");
            assertEqual(JSON.stringify(Object.assign({}, card.settingsRegion.appendHost.items[1].item.context, { tracker: null })),
                        JSON.stringify({ itemId: "two", tracker: null, anchor: "settings.cards.saved.card.settings", placement: "append" }),
                        "… the card's context at the region's path");
            assertEqual(card.settingsRegion.prependHost.items[0].item.module, host.handle("anchors-cards-a"), "… the module's handle");
            assert(card.settingsRegion.prependHost.items[0].item.shown, "… on screen");
            assertEqual(_tracker.count("card.settings") + " " + _tracker.count("|two"), "3 5", "three made in the open card, none in the closed ones");
            const model = card.settingsRegion.appendHost.repeaterModel;
            assert(model !== null && !Array.isArray(model) && model.values.length === 2 && model.values.every(value => typeof value === "string"), "… from a ScriptModel of keys (module and file)");
            _cards.openId = "";
        });
        _then("the card closed: its region's elements gone", () => _regionBuilt(-1) && _tracker.count("card.settings") === 0, () => {
            assertEqual(_tracker.count(), 10, "only the elements beside the cards and in the section are left");
            assert(!_savedCard(1).settingsRegion.visible && _savedCard(1).settingsRegion.appendHost.count === 0, "… the region hidden, empty");
            assertEqual(_tracker.count("|two") + " " + _tracker.goneCount, "2 3", "… the three it held destroyed, its two beside it left");
        });
        // Opened and closed over and over, each card in turn, and one card to the next directly
        const openClose = number => {
            const index = number % 3;
            _then("card " + index + " open (cycle " + number + ")", () => _cards.openId === _cards.items[index].id && _regionBuilt(index)
                  && _cardsSteady() && _openCardProblems(_savedCard(index)).length === 0, () => {
                _cardCycles++;
                if (number % 2 === 0)
                    _cards.openId = "";
                else
                    _cards.openId = _cards.items[(index + 1) % 3].id;
            });
            if (number % 2 === 0) {
                _then("… closed (cycle " + number + ")", () => _regionBuilt(-1) && _tracker.count("card.settings") === 0, () => {
                    _cards.openId = _cards.items[(index + 1) % 3].id;
                });
            }
        };
        _then("cycles start", () => true, () => {
            _cards.openId = _cards.items[0].id;
        });
        for (let i = 0; i < 10; i++)
            openClose(i);
        _then("ten times opened and closed", () => _regionBuilt(1) && _cardsSteady(), () => {
            assertEqual(_cardCycles, 10, "the cards opened and closed ten times, laid out each time");
            assertEqual(_tracker.count("card.settings") + " " + _tracker.count(), "3 13", "… one card's region built now, nothing left of the others");
            assertEqual(_tracker.late, 0, "… no element ran after its card took it");
            // The providers' cards: each shows only its own provider module's element
            _cards.openId = "";
            _cards.vpnOpenId = "v1";
        });
        const vpnOpen = (index, expected) => {
            _then("the provider's card " + index + " open", () => _regionBuilt(-1) && _vpnCard(index).settingsRegion.visible
                  && (expected === "" ? true : _ready(_vpnCard(index).settingsRegion.prependHost, 1)) && _cardsSteady(), () => {
                const region = _vpnCard(index).settingsRegion;
                assertEqual(expected === "" ? String(region.prependHost.count) + region.prependHost.built : _names(region.prependHost),
                            expected === "" ? "0false" : expected,
                            "an own-provider region: " + (expected === "" ? "a card of no provider shows nothing" : "only the card's provider module's element"));
                if (index < 2)
                    _cards.vpnOpenId = ["v2", "v3"][index];
                else
                    _cards.vpnOpenId = "";
            });
        };
        vpnOpen(0, "anchors-cards-a:Element");
        vpnOpen(1, "anchors-cards-b:Element");
        vpnOpen(2, "");
        _then("the providers' cards closed", () => _tracker.count("vpns") === 0, () => {
            // The cards in a list: reordered, the same cards and elements follow
            _cards.openId = "two";
        });
        _then("the second card open again", () => _regionBuilt(1) && _cardsSteady(), () => {
            const objects = {};
            for (const card of _savedCardList())
                objects[card.cardItem.id] = card;
            _cardObjects = objects;
            _regionElements = _savedCard(1).settingsRegion.appendHost.items.map(item => item.item);
            _tracker.madeCount = 0;
            _cards.items = _cardItems(["three", "two", "one"]);
        });
        _then("the list reordered", () => _savedCard(0)?.cardItem.id === "three" && _cardsSteady()
              && _yIn(_savedCard(0).frame) < _yIn(_savedCard(1).frame) && _yIn(_savedCard(1).frame) < _yIn(_savedCard(2).frame), () => {
            const cards = _savedCardList();
            assertEqual(cards.map(card => card.cardItem.id).join(","), "three,two,one", "the cards in the list's new order");
            assert(cards.every(card => card === _cardObjects[card.cardItem.id]), "… each the same card as before: not rebuilt");
            const elements = _savedCard(1).settingsRegion.appendHost.items.map(item => item.item);
            assert(elements.length === 2 && elements.every((element, index) => element === _regionElements[index]),
                   "… the open card's elements the same objects");
            assertEqual(_tracker.madeCount, 0, "… nothing made anew");
            assertEqual(_openCardProblems(_savedCard(1)).join("; "), "", "… its parts where they stood in the card");
            assert(_yIn(_savedCard(2).afterHost.items[0]) < _yIn(_cards.saved.appendHost.items[0]), "… the section's end still under its last card");
            // One added at the front, the open one taken out
            _cards.items = _cardItems(["four", "three", "one"]);
        });
        _then("a card added, the open one taken out", () => _savedCardList().length === 3 && _savedCard(0)?.cardItem.id === "four"
              && _cardsBuilt() && _cardsSteady() && _tracker.count("|two") === 0, () => {
            assertEqual(_savedCardList().map(card => card.cardItem.id).join(","), "four,three,one", "the cards as the list is");
            assert(_savedCard(1) === _cardObjects["three"] && _savedCard(2) === _cardObjects["one"], "… the cards left the same objects, each still its own item");
            assertEqual(_tracker.count("card.settings"), 0, "the open card taken out: its region's elements destroyed with it, nothing left in a region");
            assertEqual(_tracker.count("saved.card|") + " " + _tracker.count("|four"), "6 2", "… beside the cards: two each, the new one's made");
            assertEqual(_live("settings.cards.saved.card"), "settings.cards.saved.card:3,settings.cards.saved.card.actions:3,settings.cards.saved.card.settings:3,settings.cards.saved.card.title:3",
                        "… Anchors.live: three cards, their regions");
            _cards.openId = "four";
            _waitUntil = Date.now() + 300;
        });
        _then("the new card open, a while later", () => Date.now() >= _waitUntil && _regionBuilt(0) && _cardsSteady()
              && _openCardProblems(_savedCard(0)).length === 0, () => {
            assertEqual(_names(_savedCard(0).settingsRegion.appendHost), "anchors-cards-a:Element,anchors-cards-b:Element", "the new card's region, opened");
            assertEqual(_tracker.late, 0, "no element ran after its card was taken out");
            // The view closed with a card open
            _close(_cards);
            _cards = null;
        });
        _then("the cards view closed", () => _live("settings.cards") === "" && _tracker.count() === 0, () => {
            _waitUntil = Date.now() + 300;
        });
        _then("a while after the cards view closed", () => Date.now() >= _waitUntil, () => {
            assertEqual(_tracker.late + " " + _tracker.count(), "0 0", "the view closed with a card open: every element gone, none ran after");
            assert(_tracker.beats > 0, "… the elements did run while they stood (the check can fail)");
            host.unload();
        });

        // The General page: where its rows stand (the same before and after it became a
        // SettingsPage)
        _then("the fixture views are gone", () => true, () => {
            _generalView = _generalViewComponent.createObject(suite);
            _views.push(_generalView);
        });
        _then("the General page is laid out", () => {
            const rows = _generalRows(_generalView.loader);
            return rows.length > 3 && rows[rows.length - 1].y > rows[0].y && rows.every(row => row.height > 0);
        }, () => {
            const rows = _generalRows(_generalView.loader);
            console.log("  INFO: the General page's rows (x y width height): "
                        + rows.map(row => row.name + " " + [row.x, row.y, row.width, row.height].map(Math.round).join(" ")).join(" · "));
            assertEqual(_generalLayoutProblems(rows, _generalView.loader.width).join("; "), "",
                        "the General page's rows: headings, hint and settings at the page's margin, 8, 16 and 2 apart as before");
            const page = _generalView.loader.item;
            assertEqual(page.path + " " + page.appendHost.count + " " + page.appendHost.built, "settings.general 0 false",
                        "the page is the place settings.general, its base the page loader's; no module: its end builds nothing");
            assertEqual(_live("settings.general"), "settings.general:1", "… live once");
            Modules.host.load([fixtures + "/anchors-general"], {});
        });
        _then("a module at the General page's end", () => _generalSettled() && _ready(_generalView.loader.item.appendHost, 2)
              && _generalEndLaidOut(_generalView.loader), () => {
            const status = Modules.status("anchors-general");
            assertEqual(status?.state + " " + status?.errors.length + " " + status?.warnings.length, "loaded 0 0", "the fixture module: loaded in the shell's host, clean");
            assertEqual(status?.deprecations.join("|"),
                        "slots (\"settings.general.bottom\"): use `anchors`: \"settings.general\", \"append\" (goes with the shell's next tightening)",
                        "its General slot: read as the place, listed among the deprecations");
            assertEqual(Modules.host.slotContributions("settings.general.bottom").length, 0, "… no longer a slot contribution");
            const page = _generalView.loader.item;
            assertEqual(_names(page.appendHost), "anchors-general:Element,anchors-general:Slot",
                        "its element at the page's end, then the one through the old slot (manifest order: anchors, then slots read as anchors)");
            assertEqual(JSON.stringify(page.appendHost.items[0].item.context), JSON.stringify({ editIndex: -1, anchor: "settings.general", placement: "append" }),
                        "the element's context: the profile being edited, anchor and placement");
            assertEqual(JSON.stringify(page.appendHost.items[1].item.context),
                        JSON.stringify({ editIndex: -1, slot: "settings.general.bottom", anchor: "settings.general", placement: "append" }),
                        "… through the old slot: also the slot's name, editIndex as the slot gave it");
            const rows = _generalRows(_generalView.loader).filter(row => row.name.startsWith("setting "));
            const last = rows[rows.length - 1];
            const element = page.appendHost.items[0].mapToItem(_generalView.loader, 0, 0);
            const margin = Theme.settings.pageMargin;
            assertEqual([element.x, element.y, page.appendHost.width].join(" "), [margin, last.y + last.height + 16, _generalView.loader.width - 2 * margin].join(" "),
                        "… 16 under the last setting, at the margin, as wide as the page inside it (as the slot stood)");
            _close(_generalView);
            _generalView = null;
            _openSettingsWindow();
        });

        // The General page in the settings window: built with the place, the modules' elements
        // at its end; another page and back, the window closed and opened, over and over
        _then("the settings window shows the General page with the module's elements", () => _ready(_windowPage()?.appendHost ?? { items: [] }, 2), () => {
            const page = _windowPage();
            assertEqual(_names(page.appendHost), "anchors-general:Element,anchors-general:Slot", "the settings window's General page: the module's elements at its end");
            assertEqual(page.appendHost.items[0].item.context.editIndex, _settingsWindow.editIndex, "… given the profile the window edits");
            const live = Object.keys(Anchors.live).filter(path => path.startsWith("settings.")).sort();
            assertEqual(live.join(","), ModuleRules.anchorTable.map(row => row.path).filter(path => path.startsWith("settings.general")).sort().join(","),
                        "the settings window on the General page: its places in the table live, and nothing else (no other page is built)");
            _settingsWindow.selectedPage = "calendar";
        });
        const pageCycle = number => {
            _then("another page (" + number + ")", () => _live("settings.general") === "" && _windowPage() === null, () => {
                _settingsWindow.selectedPage = "general";
            });
            _then("the General page again (" + number + ")", () => _ready(_windowPage()?.appendHost ?? { items: [] }, 2), () => {
                _windowCycles++;
                assertEqual(_live("settings.general"), "settings.general:1", "the General page shown again: live once (" + number + ")");
                if (number < 5)
                    _settingsWindow.selectedPage = "calendar";
                else
                    _closeSettingsWindow();
            });
        };
        for (let i = 1; i <= 5; i++)
            pageCycle(i);
        const windowCycle = number => {
            _then("the settings window closed (" + number + ")", () => _live("settings.general") === "", () => {
                _openSettingsWindow();
            });
            _then("the settings window open again (" + number + ")", () => _ready(_windowPage()?.appendHost ?? { items: [] }, 2), () => {
                _windowCycles++;
                _closeSettingsWindow();
            });
        };
        for (let i = 1; i <= 5; i++)
            windowCycle(i);
        _then("the settings window closed after the cycles", () => _live("settings.general") === "", () => {
            assertEqual(_windowCycles, 10, "the General page shown and left five times, the window opened and closed five times, built each time");
            for (let i = 0; i < 5; i++) {
                _openSettingsWindow();
                _closeSettingsWindow();
            }
            _waitUntil = Date.now() + 300;
        });
        _then("windows closed at once leave nothing live", () => Date.now() >= _waitUntil && _live("settings.general") === "", () => {
            const status = Modules.status("anchors-general");
            assertEqual(status?.state + " " + status?.errors.length, "loaded 0", "no element failed meanwhile");
            Modules.host.unload();
        });

        // The popups: where their parts stand, with no module and with a module's elements
        // (the same before and after they were built on the popup blocks)
        _then("the shell's host is empty", () => Modules.host.statuses.length === 0, () => {
            const component = Qt.createComponent("FakeVpnProvider.qml");
            _fakeVpn = component.createObject(suite, { providerId: "anchors-vpn", withExtras: true });
            _fakeVpn.add("one", "One");
            _fakeVpn.add("two", "Two");
            _fakeVpn.setStatus("one", "Via exit-1");
            _pinNetwork(true);
            _openPopupView("network", "../panels/NetworkPanel.qml");
        });
        _then("the network popup is laid out", () => _networkPinned() && _popupView.loader.item
              && _partsLaidOut(_popupView.loader.item, _networkExpected(false)), () => {
            const panel = _popupView.loader.item;
            const parts = _popupParts(panel);
            console.log("  INFO: the network popup's parts (x y width height): " + _describeParts(parts));
            assertEqual(_partsProblems(parts, _networkExpected(false), panel.width).join("; "), "",
                        "the network popup's parts: the VPN part 4 apart, the rest 6, all as wide as the panel");
            assertEqual(_live("popup.network"), "popup.network:1,popup.network.connections:1,popup.network.connections.vpn:1,popup.network.connections.vpn.row:2",
                        "the network popup's blocks: the panel, its connections, the VPN part and a row per VPN");
            assertEqual(_popupLiveProblems("popup.network").join("; "), "", "… every place of the network popup in the table live, the rest named, not published");
            const connections = _blockAt(panel, "popup.network.connections");
            assertEqual(connections.appendHost.count + " " + connections.appendHost.built, "0 false", "… with no module: its end builds nothing");
            Modules.host.load([fixtures + "/anchors-popups"], {});
        });
        _then("a module's elements in the network popup", () => _generalSettled() && _networkPinned()
              && _ready(_blockAt(_popupView.loader.item, "popup.network.connections")?.appendHost ?? { items: [] }, 2)
              && _partsLaidOut(_popupView.loader.item, _networkExpected(true)), () => {
            const status = Modules.status("anchors-popups");
            assertEqual(status?.state + " " + status?.errors.length + " " + status?.warnings.length, "loaded 0 0", "the popups fixture: loaded in the shell's host, clean");
            assertEqual(status?.deprecations.join("|"),
                        "slots (\"network.popup.sections\"): use `anchors`: \"popup.network.connections\", \"append\" (goes with the shell's next tightening)|"
                        + "slots (\"notifications.popup.top\"): use `anchors`: \"popup.notifications\", \"prepend\" (goes with the shell's next tightening)",
                        "its popup slots: read as the places, listed among the deprecations");
            assertEqual(Modules.host.slotContributions("network.popup.sections").length + Modules.host.slotContributions("notifications.popup.top").length, 0,
                        "… no longer slot contributions");
            const panel = _popupView.loader.item;
            const host = _blockAt(panel, "popup.network.connections").appendHost;
            assertEqual(_names(host), "anchors-popups:Element,anchors-popups:Slot", "its element at the connections' end, then the one through the old slot");
            const facts = { wifiEnabled: true, wifiConnected: false, ethernetConnected: true };
            assertEqual(JSON.stringify(host.items[0].item.context), JSON.stringify(Object.assign({}, facts, { anchor: "popup.network.connections", placement: "append" })),
                        "the element's context: whether Wi-Fi is on and joined and the cable is, anchor and placement");
            assertEqual(JSON.stringify(host.items[1].item.context),
                        JSON.stringify(Object.assign({}, facts, { slot: "network.popup.sections", anchor: "popup.network.connections", placement: "append" })),
                        "… through the old slot: the same, with the slot's name");
            const parts = _popupParts(panel);
            console.log("  INFO: … with a module's elements: " + _describeParts(parts));
            assertEqual(_partsProblems(parts, _networkExpected(true), panel.width).join("; "), "",
                        "… with a module's elements: under the Wi-Fi line, above the divider over the list, 6 apart (as the slot stood)");
            // The cable out: the context follows, handed over once
            const element = host.items[1].item;
            const changes = element.contextChanges;
            _pinned = false;
            NetworkManager.ethernetState = "disconnected";
            assertEqual(element.context.ethernetConnected + " " + (element.contextChanges - changes), "false 1", "the cable out: the context follows, passed once");
            _pinned = true;
            _pin();
            assertEqual(element.context.ethernetConnected, true, "… back in: so is the context");
            // The same popup at a height that cuts the list: room for 150 of it
            const listPart = parts.find(part => part.name === "WifiNetworkList");
            const hiddenPart = parts.find(part => part.name === "HiddenNetworkRow");
            _cutHeight = Math.round(listPart.y + 150 + 4 + hiddenPart.height);
            _closePopupView();
            _holdNetworks(_standInNetworks(12));
            _openPopupView("network", "../panels/NetworkPanel.qml", _cutHeight);
        });
        _then("the network popup at a height that cuts its list", () => _networkPinned() && _popupView.loader.item
              && _ready(_blockAt(_popupView.loader.item, "popup.network.connections")?.appendHost ?? { items: [] }, 2)
              && _partsLaidOut(_popupView.loader.item, _networkExpected(true)), () => {
            const panel = _popupView.loader.item;
            const parts = _popupParts(panel);
            console.log("  INFO: … " + _cutHeight + " high, twelve networks: " + _describeParts(parts));
            assertEqual(panel.height + " " + panel.availableHeight, _cutHeight + " " + _cutHeight, "the panel: as high as the popup lets it be");
            assertEqual(_partsProblems(parts, _networkExpected(true), panel.width, _cutHeight).join("; "), "",
                        "… its parts as before, the row under the list ending where the popup does");
            const list = parts.find(part => part.name === "WifiNetworkList");
            assertEqual(Math.round(list.height), 150, "… the list cut to the room left, not shorter");
            const listView = _findListView(panel);
            assert(listView !== null && listView.count === 12 && listView.contentHeight > listView.height + 1,
                   "… holding all twelve networks, taller than it shows: it scrolls (" + listView?.count + ", " + listView?.contentHeight + " in " + listView?.height + ")");
            _closePopupView();
            _holdNetworks(null);
            _openPopupView("notifications", "../panels/NotificationPanel.qml", 600);
        });
        _then("the notifications popup is laid out, with the module's elements",
              () => _popupView.loader.item && _ready(_blockAt(_popupView.loader.item, "popup.notifications")?.prependHost ?? { items: [] }, 2)
              && _partsLaidOut(_popupView.loader.item, _notificationsExpected(true)), () => {
            const panel = _popupView.loader.item;
            const host = _blockAt(panel, "popup.notifications").prependHost;
            assertEqual(_names(host), "anchors-popups:Element,anchors-popups:Slot", "the notifications popup: the module's element under the header, then the one through the old slot");
            assertEqual(JSON.stringify(host.items[0].item.context), JSON.stringify({ count: 0, anchor: "popup.notifications", placement: "prepend" }),
                        "… its context: how many notifications the list holds, anchor and placement");
            assertEqual(JSON.stringify(host.items[1].item.context), JSON.stringify({ count: 0, slot: "notifications.popup.top", anchor: "popup.notifications", placement: "prepend" }),
                        "… through the old slot: the same, with the slot's name");
            assertEqual(_live("popup"), "popup.notifications:1", "… the panel's root is the place popup.notifications, live once; the network popup's gone");
            const parts = _popupParts(panel);
            console.log("  INFO: the notifications popup's parts: " + _describeParts(parts));
            assertEqual(_partsProblems(parts, _notificationsExpected(true), panel.width, 600).join("; "), "",
                        "the notifications popup's parts: the header and the module's elements 8 in from the sides, 8 apart, the list to the end");
            Modules.host.unload();
        });
        _then("the notifications popup with no module", () => Modules.host.statuses.length === 0 && _popupView.loader.item
              && _partsLaidOut(_popupView.loader.item, _notificationsExpected(false)), () => {
            const panel = _popupView.loader.item;
            assertEqual(_partsProblems(_popupParts(panel), _notificationsExpected(false), panel.width, 600).join("; "), "",
                        "… with no module: the list 8 under the header");
            _closePopupView();
            _makePopup();
            Modules.host.load([fixtures + "/anchors-popups"], {});
        });

        // The popups as the bar opens them (panels/Popup.qml, its content made from
        // Qt.callLater): opened, moved to the other panel by another cell, closed; over and over;
        // opened and closed at once, before the content is made; moved before it is made; a
        // hover close called off by opening again
        _then("the module is back, the suite's popup made", () => _generalSettled() && Modules.status("anchors-popups")?.state === "loaded", () => {
            _realPopup.open(_popupCellA, false, "network");
        });
        const popupCycle = number => {
            _then("the network popup open (" + number + ")", () => _popupShown() && _ready(_inPopup("popup.network.connections")?.appendHost ?? { items: [] }, 2), () => {
                assertEqual(_names(_inPopup("popup.network.connections").appendHost), "anchors-popups:Element,anchors-popups:Slot",
                            "the network popup on screen: the module's elements at the connections' end (" + number + ")");
                assertEqual(_popupLiveProblems("popup.network").join("; "), "", "… its places live (" + number + ")");
                // Another cell's panel while it is open: the popup moves to it
                _realPopup.open(_popupCellB, false, "notifications", null, number % 2 === 0);
            });
            _then("moved to the notifications popup (" + number + ")", () => _popupShown() && _live("popup.network") === ""
                  && _ready(_inPopup("popup.notifications")?.prependHost ?? { items: [] }, 2), () => {
                assertEqual(_names(_inPopup("popup.notifications").prependHost), "anchors-popups:Element,anchors-popups:Slot",
                            "… moved to the notifications popup: its elements under the header, the network popup's blocks gone (" + number + ")");
                _realPopup.close();
            });
            _then("the popup closed (" + number + ")", () => !_realPopup.active && _live("popup") === "", () => {
                _popupCycles++;
                _realPopup.open(number % 2 === 0 ? _popupCellA : _popupCellB, false, "network", null, number % 3 === 0);
            });
        };
        for (let i = 1; i <= 5; i++)
            popupCycle(i);
        _then("five times opened, moved and closed", () => _popupShown() && _ready(_inPopup("popup.network.connections")?.appendHost ?? { items: [] }, 2), () => {
            assertEqual(_popupCycles, 5, "the popup opened, moved to the other panel and closed five times, built each time");
            _realPopup.close();
        });
        _then("closed after the cycles", () => !_realPopup.active && _live("popup") === "", () => {
            // Opened and closed at once, before the content is made (it is made from Qt.callLater)
            for (let i = 0; i < 5; i++) {
                _realPopup.open(_popupCellA, false, i % 2 === 0 ? "network" : "notifications");
                _realPopup.close();
            }
            _waitUntil = Date.now() + 400;
        });
        _then("popups closed before their content was made leave nothing", () => Date.now() >= _waitUntil && !_realPopup.active && _live("popup") === "", () => {
            // Opened, then closed on the next turn, while the content may still be being made
            _realPopup.open(_popupCellA, false, "network");
            Qt.callLater(() => _realPopup.close());
            _waitUntil = Date.now() + 400;
        });
        _then("a popup closed while its content was being made leaves nothing", () => Date.now() >= _waitUntil && !_realPopup.active && _live("popup") === "", () => {
            // Moved to another panel and back before either is made
            _realPopup.open(_popupCellA, false, "network");
            _realPopup.open(_popupCellB, false, "notifications");
            _realPopup.open(_popupCellA, false, "network");
        });
        _then("the popup moved twice before it was made shows the last panel", () => _popupShown()
              && _ready(_inPopup("popup.network.connections")?.appendHost ?? { items: [] }, 2), () => {
            assertEqual(_live("popup.notifications"), "", "… and nothing of the panel it passed through");
            // A hover close, called off by the pointer coming back: it stays open
            _realPopup._hoverClose.restart();
            _realPopup.open(_popupCellA, false, "network");
            _waitUntil = Date.now() + 300;
        });
        _then("a hover close called off", () => Date.now() >= _waitUntil, () => {
            assert(_realPopup.active && !_realPopup.closing, "a hover close called off by opening again: the popup stays");
            assertEqual(_inPopup("popup.network.connections")?.appendHost.items.length, 2, "… its elements with it");
            _realPopup._hoverClose.restart();
        });
        _then("a hover close", () => !_realPopup.active && _live("popup") === "", () => {
            const status = Modules.status("anchors-popups");
            assertEqual(status?.state + " " + status?.errors.length, "loaded 0", "no element failed meanwhile");
            _dropPopup();
            Modules.host.unload();
            _pinNetwork(false);
            _fakeVpn.destroy();
            _fakeVpn = null;
        });

        // The popup's VPN rows and the VPN page's cards: own-provider places. Two provider
        // modules — anchors-vpn-a through `anchors`, anchors-vpn-b through the old slots — each
        // row and opened card shows only its own provider module's element; a provider that is
        // no module's and a NetworkManager VPN none; VPNs added, removed and reordered with new
        // objects each read: the elements follow their VPN and go with it
        _then("the popups are gone", () => Modules.host.statuses.length === 0 && _live("popup") === "", () => {
            _holdProfiles([_nmVpnProfile]);
            const component = Qt.createComponent("FakeVpnProvider.qml");
            _ownVpn = component.createObject(suite, { providerId: "anchors-own", withExtras: true });
            _ownVpn.add("x", "Own");
            Modules.host.load([fixtures + "/anchors-vpn-b", fixtures + "/anchors-vpn-a"], {});
        });
        _then("the VPN fixtures loaded, their providers registered", () => _generalSettled() && Modules.host.mainObject("anchors-vpn-a") !== null
              && Modules.host.mainObject("anchors-vpn-b") !== null, () => {
            for (const id of ["anchors-vpn-a", "anchors-vpn-b"]) {
                const status = Modules.status(id);
                assertEqual(status?.state + " " + status?.errors.length + " " + status?.warnings.length, "loaded 0 0", id + ": loaded, clean");
            }
            assertEqual(Modules.status("anchors-vpn-a").deprecations.length, 0, "anchors-vpn-a, through anchors: nothing deprecated");
            assertEqual(Modules.status("anchors-vpn-b").deprecations.join("|"),
                        "slots (\"network.vpn.row\"): use `anchors`: \"popup.network.connections.vpn.row\", \"after\" (goes with the shell's next tightening)|"
                        + "slots (\"network.vpn.card\"): use `anchors`: \"settings.network_vpn.vpns.card.settings\", \"prepend\" (goes with the shell's next tightening)",
                        "anchors-vpn-b: its row's and card's slots read as the places, listed among the deprecations");
            assertEqual(Modules.host.slotContributions("network.vpn.row").length + Modules.host.slotContributions("network.vpn.card").length, 0,
                        "… no longer slot contributions");
            _setEntries("anchors-vpn-a", [["a1", "A one"], ["a2", "A two"]]);
            _setEntries("anchors-vpn-b", [["b1", "B one"]]);
            _openPopupView("network", "../panels/NetworkPanel.qml");
            _vpnPage = _vpnPageViewComponent.createObject(suite);
            _views.push(_vpnPage);
        });
        const vpnIds = ["nm-anchors", "anchors-own:x", "anchors-vpn-a:a1", "anchors-vpn-a:a2", "anchors-vpn-b:b1"];
        _then("the popup's VPN rows built, each provider module's under its own", () => {
            const rows = _vpnRows();
            return vpnIds.every(id => rows[id]) && _ready(rows["anchors-vpn-a:a1"].afterHost, 1) && _ready(rows["anchors-vpn-a:a2"].afterHost, 1)
                && _ready(rows["anchors-vpn-b:b1"].afterHost, 1) && Object.keys(_vpnCards()).length === 5 && _vpnViewsSteady();
        }, () => {
            const rows = _vpnRows();
            assertEqual(vpnIds.map(id => _names(rows[id].afterHost) || "-").join(" "),
                        "- - anchors-vpn-a:Row anchors-vpn-a:Row anchors-vpn-b:Row",
                        "under each row its provider module's element only: none under NetworkManager's or a provider's that is no module's");
            assertEqual(rows["nm-anchors"].afterHost.built + " " + rows["anchors-own:x"].afterHost.built, "false false", "… those build nothing at all");
            assert(_texts(rows["anchors-own:x"]).includes("Fake row extras for x"), "… the provider that is no module's shows its own extras");
            assertEqual(vpnIds.map(id => rows[id].scopeId).join(","), ",anchors-own,anchors-vpn-a,anchors-vpn-a,anchors-vpn-b",
                        "each row's scope: its provider's id (none for NetworkManager's)");
            const a1 = rows["anchors-vpn-a:a1"].afterHost.items[0].item;
            const b1 = rows["anchors-vpn-b:b1"].afterHost.items[0].item;
            assertEqual(_contextKeys(a1), "anchor,entryId,otherVpns,otherVpnsUp,placement,provider,vpn,vpnId",
                        "the element's context: the VPN as the old slot gave it, with anchor and placement");
            assertEqual([a1.context.anchor, a1.context.placement, a1.context.vpnId, a1.context.entryId, a1.context.vpn.name].join(" "),
                        "popup.network.connections.vpn.row after anchors-vpn-a:a1 a1 A one", "… its VPN, at the row's path");
            assert(a1.context.provider === VpnManager.providerOf("anchors-vpn-a:a1").object && a1.context.provider === Modules.host.mainObject("anchors-vpn-a").provider,
                   "… the provider object itself");
            assertEqual(JSON.stringify(a1.context.otherVpnsUp) + " " + JSON.stringify(a1.context.otherVpns), "[] []", "… no other VPN up");
            assertEqual(a1.module, Modules.handle("anchors-vpn-a"), "… its module's handle");
            assertEqual(_contextKeys(b1), "anchor,entryId,otherVpns,otherVpnsUp,placement,provider,slot,vpn,vpnId",
                        "through the old slot: every key the slot gave, and its name");
            assertEqual(b1.context.slot + " " + b1.context.vpnId + " " + (b1.context.provider === Modules.host.mainObject("anchors-vpn-b").provider),
                        "network.vpn.row anchors-vpn-b:b1 true", "… the slot's name, its VPN, its provider");
            const row = rows["anchors-vpn-a:a1"];
            const body = row.afterHost.items[0].mapToItem(row, 0, 0);
            const vpnRow = _blockChild(row, "vpnRow");
            assertEqual([body.x, body.y, row.afterHost.items[0].width].join(" "),
                        [0, vpnRow.mapToItem(row, 0, 0).y + vpnRow.height + 2, row.width].join(" "),
                        "… right under its row, 2 apart, as wide as the row (where the slot stood)");
            assertEqual(_popupLiveProblems("popup.network").join("; "), "", "the network popup's places: every one in the table live, the rest named, not published");
            assertEqual(_live("settings.network_vpn"), "settings.network_vpn.vpns:1,settings.network_vpn.vpns.card:5,settings.network_vpn.vpns.card.actions:5,settings.network_vpn.vpns.card.settings:5,settings.network_vpn.vpns.card.title:5",
                        "the VPN page: its section, a card and its opened part per VPN");
            assertEqual(_popupLiveProblems("settings.network_vpn").join("; "), "", "… its place in the table live, the rest named, not published");
            const cards = _vpnCards();
            assert(vpnIds.every(id => !cards[id].settingsRegion.prependHost.built), "closed cards: no element built in them");
            assertEqual(vpnIds.map(id => cards[id].scopeId).join(","), ",anchors-own,anchors-vpn-a,anchors-vpn-a,anchors-vpn-b", "each card's scope: its provider's id");
            assertEqual(_vpnLive("anchors-vpn-a") + " " + _vpnLive("anchors-vpn-b"),
                        "Row|popup.network.connections.vpn.row|anchors-vpn-a:a1:1,Row|popup.network.connections.vpn.row|anchors-vpn-a:a2:1 "
                        + "Row|popup.network.connections.vpn.row|anchors-vpn-b:b1:1", "the elements standing: one under each of their provider's rows");
            _vpnPage.loader.item._open = "anchors-vpn-a:a1";
        });
        // Each card opened in turn: its provider module's element only, first in its opened
        // part; none in the others
        const vpnCardOpen = (id, expected, next) => {
            // anchors-vpn-a also puts a button among its own cards' buttons (…card.actions)
            const button = id.startsWith("anchors-vpn-a:");
            _then("the card of " + id + " open", () => _vpnCards()[id]?.settingsRegion.visible
                  && (expected === "-" ? true : _ready(_vpnCards()[id].settingsRegion.prependHost, 1))
                  && (!button || _ready(_vpnCards()[id].actionsRegion.appendHost, 1)) && _vpnViewsSteady(), () => {
                const cards = _vpnCards();
                const region = cards[id].settingsRegion;
                assertEqual(_names(region.prependHost) || "-", expected, "the opened card of " + id + ": " + (expected === "-" ? "no module's element" : "its provider module's element"));
                assert(vpnIds.filter(other => other !== id).every(other => !cards[other].settingsRegion.prependHost.built), "… none built in the closed cards");
                const actions = cards[id].actionsRegion;
                assertEqual(_names(actions.appendHost) || "-", button ? "anchors-vpn-a:Button" : "-",
                            "… its buttons: " + (button ? "its provider module's button" : "no module's (own-provider)"));
                assert(vpnIds.filter(other => other !== id).every(other => !cards[other].actionsRegion.appendHost.built), "… no button built in the closed cards");
                if (button) {
                    const own = ["profileSettings", "profileEdit"].map(name => _blockChild(cards[id], name)).filter(item => item?.visible);
                    assertEqual(_stackProblems(cards[id], own.concat([actions.appendHost.items[0].item])).join("; "), "",
                                "… under the card's own buttons, 4 apart, on their right edge");
                    assertEqual(actions.appendHost.items[0].item.context.vpnId + " " + actions.appendHost.items[0].item.context.anchor,
                                id + " settings.network_vpn.vpns.card.actions", "… the VPN in its context, at the region's path");
                }
                if (expected !== "-") {
                    const element = region.prependHost.items[0];
                    const comesUpWith = _textItem(cards[id], "Comes up with");
                    assert(comesUpWith !== null && element.mapToItem(cards[id], 0, 0).y + element.height <= comesUpWith.mapToItem(cards[id], 0, 0).y,
                           "… above the card's own rows");
                    assertEqual(Math.round(element.mapToItem(region, 0, 0).y) + " " + element.width, "0 " + region.width, "… first in its opened part, as wide");
                }
                if (id === "anchors-vpn-a:a1") {
                    const card = region.prependHost.items[0].item;
                    assertEqual(_contextKeys(card), "anchor,entryId,otherVpns,otherVpnsUp,placement,provider,vpn,vpnId", "the card's element: the VPN in its context");
                    assertEqual(card.context.anchor + " " + card.context.placement + " " + card.context.vpnId, "settings.network_vpn.vpns.card.settings prepend anchors-vpn-a:a1",
                                "… at the region's path");
                }
                if (id === "anchors-vpn-b:b1") {
                    const card = region.prependHost.items[0].item;
                    assertEqual(_contextKeys(card), "anchor,entryId,open,otherVpns,otherVpnsUp,placement,provider,slot,vpn,vpnId",
                                "through the old slot: every key the slot gave");
                    assertEqual(card.context.slot + " " + card.context.open + " " + (card.context.provider === Modules.host.mainObject("anchors-vpn-b").provider),
                                "network.vpn.card true true", "… its name, open: true (it stands only while the card is open), its provider");
                }
                if (id === "anchors-own:x")
                    assert(_texts(cards[id]).includes("Fake card extras for x (open)"), "… the provider that is no module's shows its own extras");
                _vpnPage.loader.item._open = next;
            });
        };
        vpnCardOpen("anchors-vpn-a:a1", "anchors-vpn-a:Card", "anchors-vpn-b:b1");
        vpnCardOpen("anchors-vpn-b:b1", "anchors-vpn-b:Card", "anchors-own:x");
        vpnCardOpen("anchors-own:x", "-", "nm-anchors");
        vpnCardOpen("nm-anchors", "-", "anchors-vpn-a:a1");
        _then("the card of anchors-vpn-a:a1 open again", () => _ready(_vpnCards()["anchors-vpn-a:a1"].settingsRegion.prependHost, 1)
              && !_vpnCards()["nm-anchors"].settingsRegion.visible && _vpnViewsSteady(), () => {
            assertEqual(_vpnLive("anchors-vpn-b").includes("Card|"), false, "the cards closed: their elements gone");
            _keptRow = _vpnRows()["anchors-vpn-a:a2"].afterHost.items[0].item;
            _keptCard = _vpnCards()["anchors-vpn-a:a1"].settingsRegion.prependHost.items[0].item;
            _keptChanges = _keptRow.contextChanges;
            // A new read: new objects, a2 before a1, a3 added
            _setEntries("anchors-vpn-a", [["a2", "A two"], ["a3", "A three"], ["a1", "A one"]]);
        });
        _then("the VPNs reordered, one added", () => VpnManager.vpns.findIndex(vpn => vpn.uuid === "anchors-vpn-a:a2") < VpnManager.vpns.findIndex(vpn => vpn.uuid === "anchors-vpn-a:a1")
              && _vpnRows()["anchors-vpn-a:a3"] && _ready(_vpnRows()["anchors-vpn-a:a3"].afterHost, 1) && _vpnViewsSteady(), () => {
            const rows = _vpnRows();
            assertEqual(rows["anchors-vpn-a:a2"].afterHost.items[0].item, _keptRow, "the rows reordered: a VPN's element the same object");
            assertEqual(_keptRow.context.vpnId + " " + (_keptRow.contextChanges - _keptChanges), "anchors-vpn-a:a2 0",
                        "… still its own VPN's, its context not handed again (nothing in it changed)");
            assertEqual(_vpnCards()["anchors-vpn-a:a1"].settingsRegion.prependHost.items[0]?.item, _keptCard, "the open card's element the same object");
            assertEqual(rows["anchors-vpn-a:a3"].afterHost.items[0].item.context.vpnId, "anchors-vpn-a:a3", "the VPN added: its own element, its own VPN");
            const order = _vpnCardOrder();
            assert(order.indexOf("anchors-vpn-a:a2") < order.indexOf("anchors-vpn-a:a1"), "the cards in the new order: " + order.join(","));
            // a2 comes up: the others' otherVpnsUp follows, handed once
            _keptChanges = _keptCard.contextChanges;
            _setEntries("anchors-vpn-a", [["a2", "A two", "activated"], ["a3", "A three"], ["a1", "A one"]]);
        });
        _then("a VPN up", () => (_keptCard.context?.otherVpnsUp ?? []).length === 1, () => {
            assertEqual(JSON.stringify(_keptCard.context.otherVpnsUp) + " " + _keptCard.context.otherVpns.map(vpn => vpn.name).join(","), "[\"A two\"] A two",
                        "another VPN up: the element's otherVpnsUp and otherVpns say so");
            assertEqual(_keptCard.contextChanges - _keptChanges, 1, "… handed once");
            // The open card's VPN taken out
            _setEntries("anchors-vpn-a", [["a2", "A two", "activated"], ["a3", "A three"]]);
        });
        _then("the open card's VPN gone", () => !_vpnCards()["anchors-vpn-a:a1"] && !_vpnRows()["anchors-vpn-a:a1"]
              && !_vpnLive("anchors-vpn-a").includes("anchors-vpn-a:a1"), () => {
            assertEqual(_vpnLive("anchors-vpn-a"),
                        "Row|popup.network.connections.vpn.row|anchors-vpn-a:a2:1,Row|popup.network.connections.vpn.row|anchors-vpn-a:a3:1",
                        "a VPN gone: its card's and its row's elements gone with it, the others' left");
            assertEqual(_vpnRows()["anchors-vpn-a:a2"].afterHost.items[0].item, _keptRow, "… the others the same objects");
            assertEqual(_live("settings.network_vpn.vpns.card"), "settings.network_vpn.vpns.card:5,settings.network_vpn.vpns.card.actions:5,settings.network_vpn.vpns.card.settings:5,settings.network_vpn.vpns.card.title:5",
                        "… Anchors.live: its card gone, the added one's in (five)");
            _keptRow = null;
            _keptCard = null;
            _close(_vpnPage);
            _vpnPage = null;
            _closePopupView();
        });
        _then("the VPN views closed", () => _live("settings.network_vpn") === "" && _live("popup") === "" && _vpnLive("anchors-vpn-a") === ""
              && _vpnLive("anchors-vpn-b") === "", () => {
            assertEqual(Modules.status("anchors-vpn-a")?.errors.length + " " + Modules.status("anchors-vpn-b")?.errors.length, "0 0", "no element failed meanwhile");
            Modules.host.unload();
            _ownVpn.destroy();
            _ownVpn = null;
            _holdProfiles(null);
        });

        // The Wi-Fi and Ethernet pages: where their parts stand, with a card open and with a
        // module's element in it; the saved networks' and the wired profiles' opened cards
        // (settings.network_wifi.saved.card.settings, settings.network_ethernet.profiles.card.
        // settings, append) — each opened card shows the element of the fixture module
        // (tests/fixtures/modules/anchors-networks) under the page's own rows, with the
        // network in its context; a closed card builds none, a hotspot's card none; networks
        // read anew (new objects, reordered, added, taken out): the element follows its network
        // and goes with it
        _then("the VPN fixtures gone", () => Modules.host.statuses.length === 0 && _live("settings") === "", () => {
            _pinNetwork(true);
            _holdWifiDetails(_wifiDetailsHeld);
            _holdDevices([_wiredDevice]);
            _holdNetworks([{ ssid: "Home", signal: 80, security: "WPA2", inUse: true, bands: ["2.4G"], band: "2.4G" },
                           { ssid: "Office", signal: 60, security: "WPA3", inUse: false, bands: ["5G"], band: "5G" }]);
            _holdProfiles(_networkProfiles([["anchors-home", "Home", "wifi", 30, "wlan0"], ["anchors-office", "Office", "wifi", 20, ""],
                                            ["anchors-cafe", "Cafe", "wifi", 10, ""], ["anchors-spot", "Spot", "wifi", 5, ""],
                                            ["anchors-wired", "Wired", "ethernet", 30, "eth-anchors"], ["anchors-lab", "Lab", "ethernet", 20, ""]]));
            _wifiPage = _networkPageViewComponent.createObject(suite, { page: "network_wifi", source: Qt.resolvedUrl("../panels/settings/NetworkWifiSettings.qml") });
            _ethernetPage = _networkPageViewComponent.createObject(suite, { page: "network_ethernet", source: Qt.resolvedUrl("../panels/settings/NetworkEthernetSettings.qml") });
            _views.push(_wifiPage, _ethernetPage);
        });
        _then("the network pages laid out, every card closed", () => Object.keys(_profileCards(_wifiPage)).length === 4
              && Object.keys(_profileCards(_ethernetPage)).length === 2 && _networkPagesSteady(), () => {
            console.log("  geometry: the Wi-Fi page, closed: " + _pageFingerprint(_wifiPage));
            console.log("  geometry: the Ethernet page, closed: " + _pageFingerprint(_ethernetPage));
            assertEqual(_pagePartsProblems(_wifiPage, _wifiPageExpected).join("; "), "", "the Wi-Fi page: its parts where they always stood");
            assertEqual(_pagePartsProblems(_ethernetPage, _ethernetPageExpected).join("; "), "", "the Ethernet page: its parts where they always stood");
            assertEqual(_titleButtonProblems(_wifiPage, 2).join("; "), "", "the Wi-Fi page: Find networks and New hotspot at their title line's right edge, centred on it");
            assertEqual(_titleButtonProblems(_ethernetPage, 0).join("; "), "", "the Ethernet page: no title buttons");
            assertEqual(_wifiHeadingProblems(_wifiPage).join("; "), "", "the Wi-Fi page: the switch at the heading's right edge, centred on it, no row under the heading");
            _wifiPage.loader.item._open = "anchors-home";
            _ethernetPage.loader.item._open = "anchors-wired";
        });
        _then("a card open on each page", () => _profileCards(_wifiPage)["anchors-home"]?.settingsRegion.visible
              && _profileCards(_ethernetPage)["anchors-wired"]?.settingsRegion.visible && _networkPagesSteady(), () => {
            console.log("  geometry: the Wi-Fi page, Home open: " + _pageFingerprint(_wifiPage));
            console.log("  geometry: the Ethernet page, Wired open: " + _pageFingerprint(_ethernetPage));
            assertEqual(_pagePartsProblems(_wifiPage, _wifiPageExpected).join("; "), "", "… and with a card open");
            assertEqual(_pagePartsProblems(_ethernetPage, _ethernetPageExpected).join("; "), "", "… on both pages");
            assertEqual(_openCardRowsProblems(_profileCards(_wifiPage)["anchors-home"], true).join("; "), "",
                        "Home open: its buttons stacked on the primary's edge, its rows and the password where the rules put them");
            assertEqual(_openCardRowsProblems(_profileCards(_ethernetPage)["anchors-wired"], false).join("; "), "", "Wired open: the same, with no row of the page's");
            assertEqual(_titleButtonProblems(_wifiPage, 2).join("; "), "", "… the title buttons still at their line's right edge");
            _wifiPartsBefore = _pageParts(_wifiPage);
            _ethernetPartsBefore = _pageParts(_ethernetPage);
            assertEqual(_live("settings.network_wifi"), "settings.network_wifi.hotspots:1,settings.network_wifi.hotspots.card:1,settings.network_wifi.hotspots.card.actions:1,"
                        + "settings.network_wifi.hotspots.card.settings:1,settings.network_wifi.hotspots.card.title:1,settings.network_wifi.saved:1,settings.network_wifi.saved.card:3,"
                        + "settings.network_wifi.saved.card.actions:3,settings.network_wifi.saved.card.settings:3,settings.network_wifi.saved.card.title:3",
                        "the Wi-Fi page: its two sections, a card, its name's line and its opened part per saved network and per hotspot");
            assertEqual(_live("settings.network_ethernet"), "settings.network_ethernet.profiles:1,settings.network_ethernet.profiles.card:2,settings.network_ethernet.profiles.card.actions:2,"
                        + "settings.network_ethernet.profiles.card.settings:2,settings.network_ethernet.profiles.card.title:2",
                        "the Ethernet page: its section, a card, its name's line and its opened part per wired profile");
            assertEqual(_popupLiveProblems("settings.network_wifi").concat(_popupLiveProblems("settings.network_ethernet")).join("; "), "",
                        "… their places in the table live, the rest named, not published");
            const cards = Object.values(_profileCards(_wifiPage)).concat(Object.values(_profileCards(_ethernetPage)));
            assert(cards.every(card => !card.settingsRegion.appendHost.built && !card.settingsRegion.prependHost.built), "no module: nothing built in any card");
            assert(cards.every(card => !card.titleRegion.appendHost.built && card.titleRegion.width === 0 && card.titleText.rightPadding === 0),
                   "… nor on any name's line: the name has the whole line");
            _titleLinesBefore = { office: _titleLine(_profileCards(_wifiPage)["anchors-office"]), lab: _titleLine(_profileCards(_ethernetPage)["anchors-lab"]) };
            Modules.host.load([fixtures + "/anchors-networks", fixtures + "/anchors-title"], {});
        });
        _then("the network fixture loaded, its element in each open card", () => _generalSettled() && Modules.status("anchors-networks")?.state === "loaded"
              && Modules.status("anchors-title")?.state === "loaded"
              && _ready(_cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-home"].settingsRegion.appendHost, 1)
              && _ready(_cardsAt(_ethernetPage, "settings.network_ethernet.profiles.card")["anchors-wired"].settingsRegion.appendHost, 1)
              && _ready(_cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-home"].actionsRegion.appendHost, 1)
              && _ready(_cardsAt(_ethernetPage, "settings.network_ethernet.profiles.card")["anchors-wired"].actionsRegion.appendHost, 1)
              && _networkPagesSteady(), () => {
            const status = Modules.status("anchors-networks");
            assertEqual(status.errors.length + " " + status.warnings.length + " " + status.deprecations.length, "0 0 0", "the network fixture: loaded, clean");
            const wifiCards = _cardsAt(_wifiPage, "settings.network_wifi.saved.card");
            const ethernetCards = _cardsAt(_ethernetPage, "settings.network_ethernet.profiles.card");
            assertEqual(["anchors-home", "anchors-office", "anchors-cafe"].map(id => _names(wifiCards[id].settingsRegion.appendHost) || "-").join(" "),
                        "anchors-networks:Element - -", "the Wi-Fi page: the element in the open card only");
            assert(!wifiCards["anchors-office"].settingsRegion.appendHost.built && !wifiCards["anchors-cafe"].settingsRegion.appendHost.built,
                   "… nothing built in the closed cards");
            assertEqual(["anchors-wired", "anchors-lab"].map(id => _names(ethernetCards[id].settingsRegion.appendHost) || "-").join(" "),
                        "anchors-networks:Element -", "the Ethernet page: the same");
            const home = wifiCards["anchors-home"];
            const wired = ethernetCards["anchors-wired"];
            assertEqual(_regionElementProblems(home).join("; "), "", "Home's element: under the page's rows (the password), 6 apart, last, as wide as the opened part");
            assertEqual(_regionElementProblems(wired).join("; "), "", "Wired's element: under the card's rows, 6 apart, last, as wide");
            const homeElement = home.settingsRegion.appendHost.items[0];
            const wiredElement = wired.settingsRegion.appendHost.items[0];
            assertEqual(_contextKeys(homeElement.item), "active,anchor,kind,name,networkId,placement", "the element's context: the network, with anchor and placement");
            assertEqual([homeElement.item.context.anchor, homeElement.item.context.placement, homeElement.item.context.networkId, homeElement.item.context.name,
                         homeElement.item.context.kind, homeElement.item.context.active].join(" "),
                        "settings.network_wifi.saved.card.settings append anchors-home Home wifi true", "… Home, as Api.networks names it");
            assertEqual([wiredElement.item.context.anchor, wiredElement.item.context.networkId, wiredElement.item.context.name, wiredElement.item.context.kind,
                         wiredElement.item.context.active].join(" "),
                        "settings.network_ethernet.profiles.card.settings anchors-wired Wired ethernet true", "… Wired, on its page's path");
            assertEqual(homeElement.item.module, Modules.handle("anchors-networks"), "… its module's handle");
            // Its button among the card's: under "Edit connection…", above "Forget", 4 apart on
            // one right edge
            const homeButton = home.actionsRegion.appendHost.items[0];
            const wiredButton = wired.actionsRegion.appendHost.items[0];
            assertEqual(_names(home.actionsRegion.appendHost) + " " + _names(wired.actionsRegion.appendHost), "anchors-networks:Button anchors-networks:Button",
                        "the module's button among each open card's buttons");
            for (const card of [home, wired]) {
                const stack = [_blockChild(card, "profileEdit"), card.actionsRegion.appendHost.items[0].item, _blockChild(card, "profileForget")];
                assertEqual(_stackProblems(card, stack).join("; "), "", card.title + ": Edit connection…, the module's button, Forget — 4 apart, on one right edge");
            }
            assertEqual([homeButton.item.context.anchor, homeButton.item.context.networkId, wiredButton.item.context.anchor, wiredButton.item.context.networkId].join(" "),
                        "settings.network_wifi.saved.card.actions anchors-home settings.network_ethernet.profiles.card.actions anchors-wired",
                        "… the network in its context, at the region's path");
            assert(!wifiCards["anchors-office"].actionsRegion.appendHost.built && !ethernetCards["anchors-lab"].actionsRegion.appendHost.built,
                   "… no button built in a closed card");
            // The card taller by the element and its gap, and by the button and its gap (the
            // stack is taller than the name and its line)
            assertEqual(_shiftedProblems(_wifiPartsBefore, _pageParts(_wifiPage), "card Home", homeElement.height + home.spacing + homeButton.height + 4).join("; "), "",
                        "the Wi-Fi page otherwise as it was: only the open card taller, by the element, the button and their gaps");
            assertEqual(_shiftedProblems(_ethernetPartsBefore, _pageParts(_ethernetPage), "card Wired", wiredElement.height + wired.spacing + wiredButton.height + 4).join("; "), "",
                        "… the Ethernet page too");
            assertEqual(_openCardRowsProblems(home, true, [homeButton.item], homeElement).join("; "), "",
                        "Home: its rows where the rules put them, the module's element 6 under the password, the frame 8 under it");
            assertEqual(_openCardRowsProblems(wired, false, [wiredButton.item], wiredElement).join("; "), "", "Wired: the same");
            homeButton.item.clicked();
            assertEqual(homeButton.item.clicks + " " + wiredButton.item.clicks, "1 0", "a click on the button reaches the module's own handler");
            const spot = _cardsAt(_wifiPage, "settings.network_wifi.hotspots.card")["anchors-spot"];
            assert(spot && !spot.settingsRegion.appendHost.built, "the hotspot's card: none");
            assertEqual(_networkLive(), "settings.network_ethernet.profiles.card.settings|anchors-wired:1,settings.network_wifi.saved.card.settings|anchors-home:1",
                        "the elements standing: one per open card");
            // The name's line (1.28): both modules' elements on every saved network's and
            // wired profile's card, closed and open
        });
        _then("the name-line elements shown", () => _titleElements(_cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-office"]).length === 2
              && _titleElements(_cardsAt(_ethernetPage, "settings.network_ethernet.profiles.card")["anchors-lab"]).length === 2
              && _titleElements(_cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-home"]).length === 2 && _networkPagesSteady(), () => {
            const wifiCards = _cardsAt(_wifiPage, "settings.network_wifi.saved.card");
            const ethernetCards = _cardsAt(_ethernetPage, "settings.network_ethernet.profiles.card");
            const office = wifiCards["anchors-office"];
            const lab = ethernetCards["anchors-lab"];
            assertEqual(Modules.status("anchors-title").errors.length + Modules.status("anchors-title").warnings.length, 0, "the title fixture: loaded, clean");
            assertEqual(_titleNames(office), "anchors-networks:Title,anchors-title:Title", "Office's card, closed: both modules' elements, in module id order");
            assertEqual(_titleNames(lab) + " | " + _titleNames(wifiCards["anchors-home"]) + " | " + _titleNames(ethernetCards["anchors-wired"]),
                        "anchors-networks:Title,anchors-title:Title | anchors-networks:Title,anchors-title:Title | anchors-networks:Title,anchors-title:Title",
                        "Lab's card, closed, and Home's and Wired's, open: the same");
            const cafe = wifiCards["anchors-cafe"];
            assertEqual(_titleNames(cafe), "anchors-title:Title", "Cafe's card: the element its module hides takes no room");
            assertEqual(Math.round(_titleElements(cafe)[0].x), 0, "… the other starts the line's place, no gap before it");
            const spot = _cardsAt(_wifiPage, "settings.network_wifi.hotspots.card")["anchors-spot"];
            assert(spot && spot.titleRegion.appendHost.count === 0 && spot.titleRegion.width === 0 && spot.titleText.rightPadding === 0,
                   "a hotspot's card: no place on its name's line, the name has the whole line");
            const [ownTitle, wideTitle] = _titleElements(office);
            assertEqual(_contextKeys(ownTitle.item), "active,anchor,kind,name,networkId,placement", "an element's context: the card's, with anchor and placement");
            assertEqual([ownTitle.item.context.anchor, ownTitle.item.context.placement, ownTitle.item.context.networkId, ownTitle.item.context.name,
                         ownTitle.item.context.kind, ownTitle.item.context.active].join(" "),
                        "settings.network_wifi.saved.card.title append anchors-office Office wifi false", "… Office's, at the place's path");
            assertEqual(_titleElements(lab)[0].item.context.anchor + " " + _titleElements(lab)[0].item.context.networkId,
                        "settings.network_ethernet.profiles.card.title anchors-lab", "… Lab's on its page's path");
            assertEqual(ownTitle.item.module, Modules.handle("anchors-networks"), "… its module's handle");
            assertEqual(Math.round(ownTitle.width) + " " + Math.round(wideTitle.x - ownTitle.width), "24 4", "the first at its own width, the next 4 after it");
            assert(wideTitle.item.implicitWidth > Math.floor(office.width / 4) && Math.abs(office.titleRegion.width - Math.floor(office.width / 4)) < 0.01,
                   "a wide element: the place a quarter of the card wide (" + office.titleRegion.width + ", the card " + office.width + "), the element cut on the right");
            for (const [name, card] of [["Office", office], ["Lab", lab], ["Home", wifiCards["anchors-home"]], ["Wired", ethernetCards["anchors-wired"]], ["Cafe", cafe]])
                assertEqual(_titleProblems(card).join("; "), "", name + ": the elements on the name's line, as tall as it, after the name, clear of the card's own parts");
            assertEqual(JSON.stringify(_titleLine(office)), JSON.stringify(_titleLinesBefore.office), "Office: the name's line where it stood, as wide");
            assertEqual(JSON.stringify(_titleLine(lab)), JSON.stringify(_titleLinesBefore.lab), "Lab: the same");
            _keptTitle = ownTitle.item;
            _keptTitleChanges = _keptTitle.contextChanges;
            // A long name: cut first, the elements keep their place
            _longNameCard = office;
            office.title = "A very long network name that cannot fit on the line beside the card's buttons and its elements";
        });
        _then("a long name cut, the elements kept", () => _longNameCard.titleText.truncated && _networkPagesSteady(), () => {
            assertEqual(_titleProblems(_longNameCard).join("; "), "", "a long name: cut, the elements at the line's end, clear of the buttons");
            assertEqual(Math.round(_longNameCard.titleRegion.x + _longNameCard.titleRegion.width), Math.round(_longNameCard.titleText.width),
                        "… the elements end where the name's line ends");
            assert(Math.abs(_longNameCard.titleRegion.width - Math.floor(_longNameCard.width / 4)) < 0.01, "… at their whole width still");
            assertEqual(_titleElements(_longNameCard)[0].item, _keptTitle, "… the same element");
            // A right-to-left name: drawn on the left all the same, the elements after it
            _longNameCard.title = "רשת המשרד";
        });
        _then("a right-to-left name", () => _longNameCard.titleText.text === "רשת המשרד" && !_longNameCard.titleText.truncated && _networkPagesSteady(), () => {
            const title = _longNameCard.titleText;
            assertEqual(_titleProblems(_longNameCard).join("; "), "", "a Hebrew name: the elements after it, clear of it");
            assertEqual(title.effectiveHorizontalAlignment, Text.AlignLeft, "… the name drawn on the left, as the card is laid out");
            assert(Math.abs(_longNameCard.titleRegion.x - (title.leftPadding + title.contentWidth + _longNameCard.titleRegion.gap)) < 1,
                   "… the elements right after the name's drawn end (" + _longNameCard.titleRegion.x + ", the name " + title.contentWidth + " wide)");
            const card = _longNameCard;
            card.title = Qt.binding(() => card.network.ssid + (card.network.name !== card.network.ssid ? "  (" + card.network.name + ")" : ""));
            _longNameCard = null;
            _wifiPage.loader.item._open = "anchors-office";
            _ethernetPage.loader.item._open = "anchors-lab";
        });
        _then("other cards opened", () => _networkLive() === "settings.network_ethernet.profiles.card.settings|anchors-lab:1,settings.network_wifi.saved.card.settings|anchors-office:1"
              && _ready(_cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-office"].settingsRegion.appendHost, 1)
              && _ready(_cardsAt(_ethernetPage, "settings.network_ethernet.profiles.card")["anchors-lab"].settingsRegion.appendHost, 1)
              && _networkPagesSteady(), () => {
            const wifiCards = _cardsAt(_wifiPage, "settings.network_wifi.saved.card");
            const ethernetCards = _cardsAt(_ethernetPage, "settings.network_ethernet.profiles.card");
            assert(!wifiCards["anchors-home"].settingsRegion.appendHost.built && !ethernetCards["anchors-wired"].settingsRegion.appendHost.built,
                   "the cards closed: their elements gone");
            const office = wifiCards["anchors-office"];
            const lab = ethernetCards["anchors-lab"];
            assertEqual(_regionElementProblems(office).join("; ") + _regionElementProblems(lab).join("; "), "", "the cards opened: each its element, under its rows");
            _keptNetwork = office.settingsRegion.appendHost.items[0].item;
            _keptWired = lab.settingsRegion.appendHost.items[0].item;
            assertEqual(_keptNetwork.context.networkId + " " + _keptNetwork.context.active + " " + _keptWired.context.networkId,
                        "anchors-office false anchors-lab", "… with its own network: Office, not up; Lab");
            assertEqual(_titleNames(office) + " " + _titleNames(lab), "anchors-networks:Title,anchors-title:Title anchors-networks:Title,anchors-title:Title",
                        "the name-line elements on the opened cards too");
            assertEqual(_titleElements(office)[0].item, _keptTitle, "… the same element: opening the card made no new one");
            assertEqual(_titleProblems(office).join("; ") + _titleProblems(lab).join("; "), "", "… still clear of the card's parts, the stacked buttons included");
            _keptNetworkChanges = _keptNetwork.contextChanges;
            // A new read: new objects; Office comes up, Cafe forgotten, Airport saved; Lab used
            // last, Wired no longer up
            _holdProfiles(_networkProfiles([["anchors-airport", "Airport", "wifi", 40, ""], ["anchors-home", "Home", "wifi", 30, ""],
                                            ["anchors-office", "Office", "wifi", 20, "wlan0"], ["anchors-spot", "Spot", "wifi", 5, ""],
                                            ["anchors-wired", "Wired", "ethernet", 30, ""], ["anchors-lab", "Lab", "ethernet", 40, ""]]));
        });
        const cardOrder = (page, path) => _blocksAt(page?.loader.item, path).filter(card => card.visible)
            .sort((a, b) => a.mapToItem(null, 0, 0).y - b.mapToItem(null, 0, 0).y).map(card => card.profile?.name ?? "");
        _then("the networks read anew", () => cardOrder(_wifiPage, "settings.network_wifi.saved.card").join(",") === "Office,Home,Airport"
              && cardOrder(_ethernetPage, "settings.network_ethernet.profiles.card").join(",") === "Lab,Wired" && _networkPagesSteady(), () => {
            const wifiCards = _cardsAt(_wifiPage, "settings.network_wifi.saved.card");
            const ethernetCards = _cardsAt(_ethernetPage, "settings.network_ethernet.profiles.card");
            assertEqual(wifiCards["anchors-office"].settingsRegion.appendHost.items[0]?.item, _keptNetwork,
                        "Office up, moved to the top, Cafe gone, Airport added: its element the same object");
            assertEqual(_keptNetwork.context.networkId + " " + _keptNetwork.context.active + " " + (_keptNetwork.contextChanges - _keptNetworkChanges),
                        "anchors-office true 1", "… still Office's, up now, its context handed once");
            assertEqual(ethernetCards["anchors-lab"].settingsRegion.appendHost.items[0]?.item, _keptWired, "the wired profiles reordered: Lab's element the same object");
            assertEqual(_titleElements(wifiCards["anchors-office"])[0]?.item, _keptTitle,
                        "Office's name-line element: the same object, following its network read anew with new objects and reordered");
            assertEqual(_keptTitle.context.networkId + " " + _keptTitle.context.active + " " + (_keptTitle.contextChanges - _keptTitleChanges),
                        "anchors-office true 1", "… still Office's, up now, its context handed once");
            assertEqual(["anchors-office", "anchors-home", "anchors-airport"].map(id => _titleNames(wifiCards[id]) || "-").join(" "),
                        "anchors-networks:Title,anchors-title:Title anchors-networks:Title,anchors-title:Title anchors-networks:Title,anchors-title:Title",
                        "… each card's elements its own, Airport's (a network added) too");
            assertEqual(_titleElements(wifiCards["anchors-home"]).map(item => item.item.context.networkId).join(","), "anchors-home,anchors-home",
                        "… Home's with Home's context");
            assertEqual(_titleNames(ethernetCards["anchors-lab"]) + " " + _titleElements(ethernetCards["anchors-wired"]).map(item => item.item.context.networkId).join(","),
                        "anchors-networks:Title,anchors-title:Title anchors-wired,anchors-wired", "… the wired profiles reordered: the same");
            assertEqual(_live("settings.network_wifi.saved.card") + " " + _live("settings.network_ethernet.profiles.card"),
                        "settings.network_wifi.saved.card:3,settings.network_wifi.saved.card.actions:3,settings.network_wifi.saved.card.settings:3,settings.network_wifi.saved.card.title:3 "
                        + "settings.network_ethernet.profiles.card:2,settings.network_ethernet.profiles.card.actions:2,settings.network_ethernet.profiles.card.settings:2,"
                        + "settings.network_ethernet.profiles.card.title:2", "… a card per network, Cafe's gone");
            assertEqual(_networkLive(), "settings.network_ethernet.profiles.card.settings|anchors-lab:1,settings.network_wifi.saved.card.settings|anchors-office:1",
                        "… no other element made");
            // The open cards' networks taken out
            _holdProfiles(_networkProfiles([["anchors-airport", "Airport", "wifi", 40, ""], ["anchors-home", "Home", "wifi", 30, ""],
                                            ["anchors-spot", "Spot", "wifi", 5, ""], ["anchors-wired", "Wired", "ethernet", 30, ""]]));
        });
        _then("the open cards' networks gone", () => !_cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-office"]
              && !_cardsAt(_ethernetPage, "settings.network_ethernet.profiles.card")["anchors-lab"] && _networkLive() === "", () => {
            assertEqual(_live("settings.network_wifi.saved.card") + " " + _live("settings.network_ethernet.profiles.card"),
                        "settings.network_wifi.saved.card:2,settings.network_wifi.saved.card.actions:2,settings.network_wifi.saved.card.settings:2,settings.network_wifi.saved.card.title:2 "
                        + "settings.network_ethernet.profiles.card:1,settings.network_ethernet.profiles.card.actions:1,settings.network_ethernet.profiles.card.settings:1,"
                        + "settings.network_ethernet.profiles.card.title:1",
                        "a network gone: its card, and the elements in it, gone with it");
            assertEqual(_titleNames(_cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-home"]), "anchors-networks:Title,anchors-title:Title",
                        "… Home's name-line elements still there");
            _keptNetwork = null;
            _keptWired = null;
            _keptTitle = null;
            // A module turned off: its elements on the name's line go; on again, back
            assert(Modules.host.setEnabled("anchors-networks", false), "anchors-networks turned off");
        });
        _then("the module off: its name-line elements gone", () => Modules.status("anchors-networks")?.state === "disabled"
              && _titleNames(_cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-home"]) === "anchors-title:Title" && _networkPagesSteady(), () => {
            const home = _cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-home"];
            assertEqual(Math.round(_titleElements(home)[0].x), 0, "the other module's element alone, from the place's start");
            assertEqual(_titleProblems(home).join("; "), "", "… on the name's line as before");
            assert(Modules.host.setEnabled("anchors-networks", true), "… turned on again");
        });
        _then("the module on again", () => Modules.status("anchors-networks")?.state === "loaded"
              && _titleElements(_cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-home"]).length === 2 && _networkPagesSteady(), () => {
            assertEqual(_titleNames(_cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-home"]), "anchors-networks:Title,anchors-title:Title",
                        "… its elements back on the name's line, in module id order");
            _wifiPage.loader.item._open = "anchors-airport";
            // Airport's details not read yet (it could be a hotspot): its card no place
            const unread = Object.assign({}, _wifiDetailsHeld);
            delete unread["anchors-airport"];
            _holdWifiDetails(unread);
        });
        _then("a network whose details are unread, open", () => _profileCards(_wifiPage)["anchors-airport"]?.settingsRegion.visible
              && _profileCards(_wifiPage)["anchors-airport"].path === "" && _networkPagesSteady(), () => {
            const airport = _profileCards(_wifiPage)["anchors-airport"];
            assertEqual(airport.path + "|" + airport.settingsRegion.path + "|" + airport.actionsRegion.path + "|" + airport.titleRegion.path, "|||",
                        "a Wi-Fi network whose details are unread: its card and its regions no place (Api.networks leaves it out)");
            assert(!airport.settingsRegion.appendHost.built && !airport.actionsRegion.appendHost.built && !airport.titleRegion.appendHost.built
                   && airport.titleText.rightPadding === 0 && _networkLive() === "",
                   "… opened, no module's element or button built for it, none on its name's line");
            assertEqual(_live("settings.network_wifi.saved.card"), "settings.network_wifi.saved.card:1,settings.network_wifi.saved.card.actions:1,settings.network_wifi.saved.card.settings:1,"
                        + "settings.network_wifi.saved.card.title:1",
                        "… Anchors.live: only Home's card a place");
            _holdWifiDetails(_wifiDetailsHeld);
        });
        _then("its details read", () => _ready(_cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-airport"]?.settingsRegion.appendHost ?? { items: [] }, 1)
              && _ready(_cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-airport"].actionsRegion.appendHost, 1) && _networkPagesSteady(), () => {
            const airport = _cardsAt(_wifiPage, "settings.network_wifi.saved.card")["anchors-airport"];
            assertEqual(airport.settingsRegion.appendHost.items[0].item.context.networkId + " " + _networkLive(),
                        "anchors-airport settings.network_wifi.saved.card.settings|anchors-airport:1", "the details read: the card a place, the element built for it");
            _wifiPage.loader.item._open = "anchors-spot";
        });
        _then("the hotspot's card open", () => _cardsAt(_wifiPage, "settings.network_wifi.hotspots.card")["anchors-spot"]?.settingsRegion.visible
              && _networkPagesSteady(), () => {
            const region = _cardsAt(_wifiPage, "settings.network_wifi.hotspots.card")["anchors-spot"].settingsRegion;
            assert(!region.appendHost.built && !region.prependHost.built && _networkLive() === "", "the hotspot's opened card: no module's element (not a place)");
            assert(!_cardsAt(_wifiPage, "settings.network_wifi.hotspots.card")["anchors-spot"].actionsRegion.appendHost.built, "… and no module's button");
            assertEqual(Modules.status("anchors-networks")?.errors.length, 0, "no element failed meanwhile");
            _close(_wifiPage);
            _close(_ethernetPage);
            _wifiPage = null;
            _ethernetPage = null;
        });
        _then("the network pages closed", () => _live("settings.network_wifi") === "" && _live("settings.network_ethernet") === "", () => {
            Modules.host.unload();
            _holdProfiles(null);
            _holdWifiDetails(null);
            _holdDevices(null);
            _holdNetworks(null);
            _pinNetwork(false);
        });

        // A card's buttons (settings.cards.saved.card.actions, append; the fixture view's cards
        // have "Edit" and, last, "Forget") with a fixture module (tests/fixtures/modules/
        // anchors-buttons): a button of each kind under the card's own, in its manifest's
        // order, above "Forget", 4 apart on one right edge, at most a third of the card, in its
        // own size or the stack's; one element that is no button refused; built only while the card is
        // open; a click reaching the module; the cards reordered, the open one taken out; an
        // own-provider card's buttons only its provider module's
        const cardButtons = card => card?.actionsRegion.appendHost.items.filter(item => item.ready) ?? [];
        _then("the network pages gone", () => _live("settings.network") === "", () => {
            _tracker.reset();
            host.load([fixtures + "/anchors-buttons"], {});
            _openCards(_cardItems(["one", "two", "three"]), [{ id: "v1", provider: "anchors-buttons" }, { id: "v2", provider: "anchors-cards-a" }]);
        });
        _then("the buttons' fixture loaded, the cards closed", () => _settled() && host.status("anchors-buttons")?.state === "loaded"
              && _savedCardList().length === 3 && _cardsSteady(), () => {
            assertEqual(host.status("anchors-buttons").errors.length, 0, "the buttons' fixture: loaded, clean (nothing refused before it is built)");
            assertEqual(_savedCard(0).actionsRegion.path, "settings.cards.saved.card.actions", "a card's buttons: the region …card.actions");
            assert(_savedCardList().every(card => !card.actionsRegion.visible && !card.actionsRegion.appendHost.built), "closed cards: no button built");
            assertEqual(_buttonsLive(), "", "… none standing");
            _cards.openId = "two";
        });
        _then("the second card open, its buttons built", () => cardButtons(_savedCard(1)).length === 6 && _cardsSteady()
              && _has(host.status("anchors-buttons")?.errors, "takes a SmallButton"), () => {
            const card = _savedCard(1);
            const appended = card.actionsRegion.appendHost;
            const buttons = cardButtons(card).map(item => item.item);
            assertEqual(buttons.map(button => button.objectName.replace("anchors-buttons:", "")).join(","), "Primary,Secondary,Danger,Warning,Success,Long",
                        "the open card: the module's buttons in its manifest's order");
            assertEqual(appended.items.length + " " + appended.items.filter(item => !item.ready && !item.visible && item.height === 0).length, "7 1",
                        "… the element that is no button refused: nothing shown, no room taken");
            assert(_has(host.status("anchors-buttons").errors, "anchors: \"settings.cards.saved.card.actions\" takes a SmallButton"),
                   "… and said in the module's status: " + JSON.stringify(host.status("anchors-buttons").errors));
            assertEqual(host.status("anchors-buttons").errors.length, 1, "… once");
            assertEqual(_buttonsLive().split(",").filter(entry => entry.endsWith("|two:1")).length, 6, "… the buttons made, in the open card only");
            const edit = _blockChild(card, "ownEdit");
            const forget = _blockChild(card, "ownForget");
            assertEqual(_stackProblems(card, [edit].concat(buttons, [forget])).join("; "), "",
                        "the card's Edit, the module's buttons, then Forget last: 4 apart, on one right edge, on whole pixels");
            assertEqual(buttons.map(button => button.kind).join(","), "primary,secondary,danger,warning,success,secondary", "… a button of each kind");
            assertEqual(buttons.map(button => _child(button, "QQuickLoader").item.kind).join(","),
                        ["primary", "secondary", "danger", "warning", "success", "secondary"].map(kind => ApiElementRules.buttonKind(kind).value).join(","),
                        "… each drawn as its kind");
            assertEqual(buttons.map(button => button.size).join(","), "s,m,m,m,m,m", "… the one that sets its size: s; the others, setting none: the stack's m");
            assertEqual(buttons.map(button => _child(button, "QQuickLoader").item.fontSize).join(","),
                        [Theme[ApiElementRules.textSize("s").value]].concat(Array(5).fill(Theme[ApiElementRules.textSize("m").value])).join(","),
                        "… and drawn so");
            const long = buttons[5];
            const most = Math.floor(card.width / 3);
            assert(long.implicitWidth > most && Math.abs(long.width - most) < 0.01 && _child(_child(long, "QQuickLoader").item, "QQuickText").truncated,
                   "a long label: the button a third of the card wide (" + long.width + ", " + most + "), its label cut");
            assert(buttons.slice(0, 5).every(button => Math.abs(button.width - Math.round(button.implicitWidth)) <= 1),
                   "… the others at their own width");
            assertEqual(JSON.stringify(Object.assign({}, buttons[0].context, { tracker: null })),
                        JSON.stringify({ itemId: "two", tracker: null, anchor: "settings.cards.saved.card.actions", placement: "append" }),
                        "a button's context: the card's, at the region's path");
            assertEqual(buttons[0].module, host.handle("anchors-buttons"), "… its module's handle");
            // Clicks, as the user makes them
            _driver.mouseClick(buttons[0], buttons[0].width / 2, buttons[0].height / 2);
            _driver.mouseClick(buttons[2], buttons[2].width / 2, buttons[2].height / 2);
            assertEqual(host.mainObject("anchors-buttons").clicks.join(","), "Primary|settings.cards.saved.card.actions|two",
                        "a click reaches the module, with the card's item; a button that asks only asks");
            _driver.mouseClick(buttons[2], 5, 5);
            assertEqual(host.mainObject("anchors-buttons").clicks.length, 2, "… and acts on the second click");
            _keptButtons = buttons;
            // A button the module hides takes no room and no gap
            _nextButtonY = _yIn(buttons[2]);
            buttons[1].visible = false;
        });
        _then("a button hidden, the next one moved", () => Math.abs(_yIn(_keptButtons[2]) - _nextButtonY) > 0.01 && _cardsSteady(), () => {
            const card = _savedCard(1);
            const shown = _keptButtons.filter((button, index) => index !== 1);
            assertEqual(_stackProblems(card, [_blockChild(card, "ownEdit")].concat(shown, [_blockChild(card, "ownForget")])).join("; "), "",
                        "a hidden button takes no room: the next one up in its place, 4 under the one above");
            _keptButtons[1].visible = true;
        });
        _then("the button shown again, the next one back", () => Math.abs(_yIn(_keptButtons[2]) - _nextButtonY) < 0.01 && _cardsSteady(), () => {
            const card = _savedCard(1);
            assertEqual(_stackProblems(card, [_blockChild(card, "ownEdit")].concat(_keptButtons, [_blockChild(card, "ownForget")])).join("; "), "",
                        "… shown again, back in its place");
            _cards.openId = "";
        });
        _then("the card closed: its buttons gone", () => !_savedCard(1).actionsRegion.appendHost.built && _buttonsLive() === "", () => {
            assert(!_savedCard(1).actionsRegion.visible, "the region hidden with the card closed");
            _cards.openId = "two";
        });
        _then("open again", () => cardButtons(_savedCard(1)).length === 6 && _cardsSteady(), () => {
            assert(cardButtons(_savedCard(1)).every(item => !_keptButtons.includes(item.item)), "opened again: its buttons made anew");
            assertEqual(host.status("anchors-buttons").errors.length, 1, "… the refusal not said again");
            _keptButtons = cardButtons(_savedCard(1)).map(item => item.item);
            _cardObjects = { one: _savedCard(0), two: _savedCard(1), three: _savedCard(2) };
            _cards.items = _cardItems(["three", "two", "one"]);
        });
        _then("the cards reordered", () => _savedCard(0)?.cardItem.id === "three" && _cardsSteady()
              && _yIn(_savedCard(0).frame) < _yIn(_savedCard(1).frame), () => {
            const card = _savedCard(1);
            assert(card === _cardObjects.two, "the open card the same card");
            const buttons = cardButtons(card).map(item => item.item);
            assert(buttons.length === 6 && buttons.every((button, index) => button === _keptButtons[index]) && buttons.every(button => button.context.itemId === "two"),
                   "… its buttons the same objects, still its item's");
            assertEqual(_stackProblems(card, [_blockChild(card, "ownEdit")].concat(buttons, [_blockChild(card, "ownForget")])).join("; "), "",
                        "… where they stood in the card");
            _cards.items = _cardItems(["three", "one"]);
        });
        _then("the open card taken out", () => _savedCardList().length === 2 && _buttonsLive() === "", () => {
            assert(_savedCardList().every(card => !card.actionsRegion.appendHost.built), "its buttons gone with it, none built elsewhere");
            _keptButtons = [];
            _cards.openId = "";
            _cards.vpnOpenId = "v1";
        });
        _then("the module's own provider card open", () => _vpnCard(0)?.actionsRegion.visible && cardButtons(_vpnCard(0)).length === 1 && _cardsSteady(), () => {
            assertEqual(_names(_vpnCard(0).actionsRegion.appendHost), "anchors-buttons:Primary", "an own-provider card: its provider module's button");
            assertEqual(_stackProblems(_vpnCard(0), [cardButtons(_vpnCard(0))[0].item]).join("; "), "", "… alone in the stack, 4 under the primary slot");
            _cards.vpnOpenId = "v2";
        });
        _then("another provider's card open", () => _vpnCard(1)?.actionsRegion.visible && !_vpnCard(0).actionsRegion.appendHost.built && _cardsSteady(), () => {
            assert(!_vpnCard(1).actionsRegion.appendHost.built, "another provider's card: none of the module's buttons");
            assertEqual(_vpnCard(1).actionsRegion.height, 0, "… and its stack takes no room");
            _close(_cards);
            _cards = null;
        });
        _then("the buttons' view closed", () => _live("settings.cards") === "" && _buttonsLive() === "", () => {
            host.unload();
        });

        // A card whose only module element is refused (tests/fixtures/modules/anchors-refused:
        // no button, in a saved card's and in its own provider card's buttons) measures as
        // without it: no room, no gap; one that fails to build before and after a saved card
        // adds no gap either
        _then("the buttons' fixture unloaded", () => host.statuses.length === 0, () => {
            host.load([fixtures + "/anchors-refused"], {});
            _openCards(_cardItems(["one"]), [{ id: "v1", provider: "anchors-refused" }]);
        });
        _then("the refused fixture loaded", () => _settled() && host.status("anchors-refused")?.state === "loaded"
              && _savedCardList().length === 1 && _cardsSteady(), () => {
            _cards.openId = "one";
            _cards.vpnOpenId = "v1";
        });
        _then("both cards open, their element refused", () => _savedCard(0).actionsRegion.visible && _vpnCard(0).actionsRegion.visible
              && _savedCard(0).actionsRegion.appendHost.items.length === 1 && _vpnCard(0).actionsRegion.appendHost.items.length === 1
              && host.status("anchors-refused")?.errors.length === 4 && _cardsSteady(), () => {
            const card = _savedCard(0);
            assertEqual(card.beforeHost.count + " " + card.afterHost.count + " " + card.beforeHost.implicitHeight + " " + card.afterHost.implicitHeight, "1 1 0 0",
                        "an element that fails to build before and after the card: listed, no size");
            assert(_has(host.status("anchors-refused").errors, "anchors: settings.cards.saved.card, before: ")
                   && _has(host.status("anchors-refused").errors, "anchors: settings.cards.saved.card, after: "), "… each failure in the module's status");
            assertEqual(Math.round(card.frame.mapToItem(card, 0, 0).y * 100) / 100 + " " + Math.round((card.height - card.frame.height) * 100) / 100, "0 0",
                        "… no gap above or under the frame: the card as tall as its frame");
            assertEqual(_stackProblems(card, [_blockChild(card, "ownEdit"), _blockChild(card, "ownForget")]).join("; "), "",
                        "a saved card whose only module element is refused: Edit, then Forget 4 under it, no gap added");
            assertEqual(_vpnCard(0).actionsRegion.height, 0, "… a card with no button of its own: the stack takes no room");
            _close(_cards);
            _cards = null;
        });
        _then("the refused fixture's view closed", () => _live("settings.cards") === "", () => {
            host.unload();
        });
        _clock.start();
    }
}
