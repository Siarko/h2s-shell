import QtQuick
import QtTest as QT
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.hud
import qs.singletons

// The HUD's startup warnings (hud/StartupWarnings.qml, placed and masked as Hud.qml does) on a
// stand-in module host in safe mode: the safe-mode banner under the bar with its words (why, the modules on when it crashed, the one updated in the last day) and
// buttons; "Open Modules" opens Settings → Modules, "Load modules" calls the host and says
// "Loading…" while it searches, a refusal shows in the banner; the banner goes when safe mode
// ends, while the session is locked and after × (for the run); the HUD's input mask is the
// banner's rectangle while it shows and nothing when it does not (maskItem, Hud.qml's Region).
// That clicks beside it reach the window beneath needs the compositor; the mask's item is what
// this checks. The whole Hud is not built here: its toasts and OSDs need the session's services.
//
// Opens an overlay like the HUD's (a full-screen layer surface without keyboard) for a moment.
TestCase {
    id: suite
    suiteName: "Hud"
    asynchronous: true

    // A suite whose window takes the pointer: this one's overlay shows once it is done
    property var after: null

    property var _host: QtObject {
        property bool safeMode: true
        property string safeModeCause: "launcher"
        property var guard: null
        property int guardClearMs: 30000
        property var previousModulesOn: ["tailscale", "weather"]
        property var statuses: [{ id: "tailscale", name: "Tailscale", state: "safe-mode" }, { id: "weather", name: "Weather", state: "safe-mode" }]
        property var sourceRecords: ({ ok: true, modules: {}, dropped: [] })
        property bool discovering: false
        property bool locked: false
        property string refusal: ""
        property var calls: []

        function loadWithoutSafeMode() {
            calls = calls.concat(["loadWithoutSafeMode"]);
            if (refusal !== "")
                return refusal;
            discovering = true;
            return "";
        }
    }

    // What the HUD reads of Modules
    property var _modules: QtObject {
        property var host: suite._host
        property bool safeModeBannerDismissed: false
    }

    // As Hud.qml: the whole screen, over the bar's reserved space, the warnings under the bar
    property var _window: PanelWindow {
        id: hud
        screen: Quickshell.screens[0]
        visible: false
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; left: true }
        implicitWidth: screen.width
        implicitHeight: screen.height
        color: "transparent"
        readonly property var _barInsets: BarGeometry.reservedInsets(BarLayout.edge, Theme.bar.reservedSpace)
        readonly property alias warnings: startupWarnings
        mask: Region {
            Region { item: startupWarnings.maskItem }
        }

        StartupWarnings {
            id: startupWarnings
            x: (hud.implicitWidth - width) / 2
            y: hud._barInsets.top + Theme.osdToast.screenGap
            width: Math.min(640, hud.implicitWidth - 2 * Theme.osdToast.screenGap)
            modules: suite._modules
            openSettings: pageId => { suite._opened = suite._opened.concat([pageId]); }
        }

        QT.TestCase {
            id: driver
            name: "HudDriver"
            when: false
        }
    }
    readonly property var _driver: driver

    // Hud.qml, for its mask's line
    property var _hudFile: FileView {
        path: Quickshell.shellDir + "/Hud.qml"
        blockLoading: true
    }

    property var _opened: []

    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            _driver.wait(10);
        return condition();
    }

    function _all(item, test, found = []) {
        if (!item)
            return found;
        if (test(item))
            found.push(item);
        for (const child of item.children)
            _all(child, test, found);
        return found;
    }

    function _named(item, name) {
        return _all(item, child => child.objectName === name)[0] ?? null;
    }

    // A click on its own: two closer together than the double-click interval are a double
    // click, which a button does not take as a second click
    function _click(item) {
        _driver.wait(Qt.styleHints.mouseDoubleClickInterval + 20);
        _driver.mouseClick(item, item.width / 2, item.height / 2);
    }

    function _rect(item) {
        const topLeft = item.mapToItem(null, 0, 0);
        return [Math.round(topLeft.x), Math.round(topLeft.y), Math.round(item.width), Math.round(item.height)].join(",");
    }

    function runAsync() {
        const saved = { launch: IconThemes.launchWarningDismissed, font: Theme.nerdFontWarningDismissed };
        try {
            assert(_until(() => after === null || after.done, 60000), "the suite before, whose window takes the pointer, is done");
            // Only the banner under test: the other startup warnings closed
            IconThemes.launchWarningDismissed = true;
            Theme.nerdFontWarningDismissed = true;
            _host.sourceRecords = { ok: true, dropped: [], modules: {
                weather: { versions: [{ dir: "1.2.0-a", fetchedAt: new Date(Date.now() - 10 * 60000 - 5000).toISOString() },
                                      { dir: "1.1.0-b", fetchedAt: "2026-01-01T00:00:00Z" }], active: "1.2.0-a" } } };
            _window.visible = true;
            _run(_window);
        } finally {
            _window.visible = false;
            IconThemes.launchWarningDismissed = saved.launch;
            Theme.nerdFontWarningDismissed = saved.font;
            finish();
        }
    }

    function _run(hud) {
        const banner = hud.warnings.safeModeBanner;
        assert(_until(() => hud.visible && banner.visible && banner.width > 0 && banner.height > 0), "in safe mode the banner shows");
        assertEqual(_named(banner, "warningTitle").text, "Started without modules", "… its title");
        assertEqual(_named(banner, "warningBody").text, "The shell crashed twice within 30 seconds of starting. Modules on when it crashed: Tailscale, Weather. "
                    + "Weather was updated 10 min ago.", "… why, the modules on when it crashed, the one updated in the last day");
        assertEqual(_named(banner, "warningBody").textFormat, Text.PlainText, "… as plain text");
        const open = _named(banner, "openModules");
        const load = _named(banner, "loadModules");
        const close = _named(banner, "warningClose");
        assert(open.visible && open.label === "Open Modules", "… Open Modules");
        assert(load.visible && load.label === "Load modules" && load.available, "… Load modules");
        assert(close.visible, "… ×");
        const insets = BarGeometry.reservedInsets(BarLayout.edge, Theme.bar.reservedSpace);
        assert(banner.mapToItem(null, 0, 0).y >= insets.top, "… under the bar, clear of its reserved space");
        assert(hud.warnings.maskItem !== null && _rect(hud.warnings.maskItem) === _rect(banner),
               "the input mask covers the banner's rectangle and nothing more: " + (hud.warnings.maskItem ? _rect(hud.warnings.maskItem) : "none") + " vs " + _rect(banner));
        assert(hud.mask.regions[0].item === hud.warnings, "… the window's mask takes it");
        assert(/Region \{ item: startupWarnings\.maskItem \}/.test(_hudFile.text()), "… as Hud.qml's mask does (" + _hudFile.text().length + " characters read)");

        _click(open);
        assert(_until(() => _opened.length > 0), "Open Modules opens the settings");
        assertEqual(_opened.join(","), "modules", "… on the Modules page");

        // A refusal stays in the banner
        _host.refusal = "No module search here";
        _click(load);
        assert(_until(() => _named(banner, "warningBody").text.endsWith("\nNo module search here")), "a refused load says why in the banner");
        _host.refusal = "";

        _click(load);
        assert(_until(() => _host.calls.length === 2), "Load modules calls the host");
        assertEqual(_host.calls.join(","), "loadWithoutSafeMode,loadWithoutSafeMode", "… to load without safe mode");
        assert(_until(() => load.label === "Loading…" && !load.available), "… Loading… while it searches, not offered again");
        _click(load);
        _driver.wait(50);
        assertEqual(_host.calls.length, 2, "… a click then does nothing");

        _host.safeMode = false;
        _host.discovering = false;
        assert(_until(() => !banner.visible && hud.warnings.maskItem === null), "out of safe mode: no banner, nothing in the input mask");

        _host.safeMode = true;
        assert(_until(() => banner.visible && hud.warnings.maskItem !== null), "in safe mode again: the banner");
        _host.locked = true;
        assert(_until(() => !banner.visible && hud.warnings.maskItem === null), "while the session is locked: no banner, nothing in the input mask");
        _host.locked = false;
        assert(_until(() => banner.visible), "… unlocked: back");

        _click(close);
        assert(_until(() => !banner.visible && hud.warnings.maskItem === null), "× hides it, and the input mask with it");
        assert(_modules.safeModeBannerDismissed, "… remembered for the run");
        _host.safeMode = false;
        _host.safeMode = true;
        _driver.wait(50);
        assert(!banner.visible, "… it stays closed for the run");
    }
}
