import QtQuick
import QtQuick.Layouts
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
        _row("settings.fixture.vpn", "row", ["append"], "{ vpnId }", "own-provider")
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

    function _row(path, kind, placements, context, scope, view) {
        return { path: path, kind: kind, placements: placements, takes: "", marks: false, context: context, scope: scope ?? "", since: "1.20",
                 where: "AnchorsTest's fixture view", view: view ?? "tests/AnchorsTest.qml" };
    }

    property Connections _liveWatch: Connections {
        target: Anchors
        function onLiveChanged() {
            suite._liveChanges++;
        }
    }

    // The files outside the tests that still name a slot read as an anchor: a quoted slot
    // name on a line that is not a comment, beside the rules that list them
    property Process _slotGrep: Process {
        command: ["sh", "-c", "cd \"$1\" && shift && for slot; do grep -rnF --include=*.qml \"\\\"$slot\\\"\" . | grep -v '^\\./tests/' "
                  + "| grep -v '^\\./singletons/ModuleRules\\.qml:' | grep -vE '^[^:]*:[0-9]+:[[:space:]]*//' | cut -d: -f1 | sort -u "
                  + "| sed \"s|^\\./|$slot\\t|\"; done; echo END",
                  "sh", Quickshell.shellDir].concat(ModuleRules.slotAliases.map(alias => alias.slot))
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
        _fakeVpn?.destroy();
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
    readonly property var _namedNotPublished: ["popup.network", "popup.network.connections.vpn", "popup.network.connections.vpn.row"]
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
            assertEqual(JSON.stringify(_slotUses["network.popup.sections"] ?? null) + " " + JSON.stringify(_slotUses["network.vpn.row"]),
                        "null [\"singletons/network/VpnManager.qml\"]",
                        "the slot guard finds what still builds a slot (not comments, not the rules, not the tests): the VPN row's, not the popup's any more");
            assertEqual(ModuleRules.slotAliasProblems(ModuleRules.anchorTable, ModuleRules.slotAliases, _slotUses, _viewTextsOf(ModuleRules.anchorTable)).join("; "), "",
                        "every slot read as its anchor in this shell's table: no longer built as a slot, its view builds the block and gives what the slot gave");
            const published = [_row("popup.network.connections.vpn.row", "row", ["after"], "{ vpnId }", "own-provider", "panels/network/VpnSection.qml")];
            const problems = ModuleRules.slotAliasProblems(published, ModuleRules.slotAliases, _slotUses, _viewTextsOf(published));
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
            assert(model !== null && !Array.isArray(model) && model.objectProp === "key",
                   "the elements are made from a ScriptModel keyed by module and file, never a live array on Repeater.model");
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
        _then("a module at the General page's end", () => _generalSettled() && _ready(_generalView.loader.item.appendHost, 2), () => {
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
            assertEqual(live.join(","), ModuleRules.anchorTable.map(row => row.path).filter(path => path.startsWith("settings.")).sort().join(","),
                        "every settings place in the table is live with the settings window built, and nothing else is (none named, not published)");
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
              && _popupParts(_popupView.loader.item).length === _networkExpected(false).length, () => {
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
              && _popupParts(_popupView.loader.item).length === _networkExpected(true).length, () => {
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
            _closePopupView();
            _openPopupView("notifications", "../panels/NotificationPanel.qml", 600);
        });
        _then("the notifications popup is laid out, with the module's elements",
              () => _popupView.loader.item && _ready(_blockAt(_popupView.loader.item, "popup.notifications")?.prependHost ?? { items: [] }, 2)
              && _popupParts(_popupView.loader.item).length === _notificationsExpected(true).length, () => {
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
              && _popupParts(_popupView.loader.item).length === _notificationsExpected(false).length, () => {
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
        _clock.start();
    }
}
