import QtQuick
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
    // Its overlay takes the pointer other suites' windows would get
    ownProcess: true

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
        property string discoveryOutcome: ""
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

        WindowDriver {
            id: driver
            name: "HudDriver"
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
        assertEqual(_named(banner, "warningBody").text, "The shell crashed repeatedly within 30 seconds of starting. Modules on when it crashed: Tailscale, Weather. "
                    + "Weather was updated 10 min ago.", "… why, the modules on when it crashed, the one updated in the last day");
        assertEqual(_named(banner, "warningBody").textFormat, Text.PlainText, "… as plain text");
        const open = _named(banner, "openModules");
        const load = _named(banner, "loadModules");
        const close = _named(banner, "warningClose");
        assert(open.visible && open.label === "Open Modules", "… Open Modules");
        assert(load.visible && load.label === "Load modules" && load.available, "… Load modules");
        assert(close.visible, "… ×");
        assert(!open.activeFocusOnTab && !load.activeFocusOnTab, "… neither reached by Tab (a toast's reply field is not left for them)");
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

        // The search fails: said in the banner, Load modules offered again
        _host.discoveryOutcome = "the module search failed (status 1): the modules stay as they are";
        _host.discovering = false;
        assert(_until(() => _named(banner, "warningBody").text.endsWith("\nThe module search failed (status 1): the modules stay as they are")),
               "a search that failed says why in the banner");
        assert(load.label === "Load modules" && load.available, "… Load modules offered again");
        _host.discoveryOutcome = "";
        _click(load);
        assert(_until(() => _host.calls.length === 3 && !_named(banner, "warningBody").text.includes("\n")), "… clicked again: the old reason gone");

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

        // Out of safe mode, another warning shown: the mask is that warning alone
        _host.safeMode = false;
        Theme.nerdFontWarningDismissed = false;
        if (Theme.nerdFontInstalled) {
            // Fonts present here: the warning cannot show; the launch warning stands in
            Theme.nerdFontWarningDismissed = true;
            IconThemes.launchWarningDismissed = false;
        }
        const other = () => hud.warnings.children.find(child => child !== banner && child.visible && child.height > 0) ?? null;
        assert(_until(() => other() !== null && hud.warnings.maskItem !== null), "another warning shown: in the mask");
        assertEqual(_rect(hud.warnings.maskItem), _rect(other()), "… the mask is that warning's rectangle, not the banner's");

        // Settings outside their range: a banner naming them; × closes it, another stored value
        // brings it back
        const range = hud.warnings.rangeWarning;
        const savedDismissed = Profiles.rangeNoticeDismissed;
        try {
            assert(!range.visible, "nothing corrected: no range banner");
            hud.warnings.rangeCorrections = [{ key: "system.rememberAdminMinutes", stored: 120, used: 60, note: "" }];
            assert(_until(() => range.visible && range.height > 0), "a setting corrected: the range banner");
            assert(range.body.startsWith("system.rememberAdminMinutes: the nearest allowed value is used"), "… naming it");
            range.dismissed();
            assert(_until(() => !range.visible), "× closes it");
            hud.warnings.rangeCorrections = [{ key: "system.rememberAdminMinutes", stored: 0, used: 1, note: "" }];
            assert(_until(() => range.visible), "… another stored value: shown again");
        } finally {
            hud.warnings.rangeCorrections = Qt.binding(() => Profiles.rangeCorrections);
            Profiles.rangeNoticeDismissed = savedDismissed;
        }

        // The font warning names the package as this system gets it, never as a command
        const font = hud.warnings.fontWarning;
        const saidFacts = hud.warnings.distributionFacts;
        const lastLine = () => font.body.split("\n").slice(-1)[0];
        try {
            hud.warnings.distributionFacts = { label: "Arch Linux", packages: { nerdFont: { package: "ttf-jetbrains-mono-nerd" } } };
            assertEqual(lastLine(), "On Arch Linux: the package ttf-jetbrains-mono-nerd.", "the font warning on Arch: the package's name");
            hud.warnings.distributionFacts = { label: "NixOS", packages: { nerdFont: { option: "programs.h2s-shell.enable", package: "nerd-fonts.jetbrains-mono", in: "fonts.packages" } } };
            assertEqual(lastLine(), "On NixOS: the option programs.h2s-shell.enable, or the package nerd-fonts.jetbrains-mono in fonts.packages.",
                        "… on NixOS: the option, or the package and where it goes");
            hud.warnings.distributionFacts = null;
            assertEqual(lastLine(), "From this system's packages: JetBrainsMono Nerd Font, for the shell's icons.", "… the system not known: the neutral hint");
            assert(font.body.startsWith("The shell's icons are Nerd Font glyphs"), "… after what is missing and why");
        } finally {
            hud.warnings.distributionFacts = saidFacts;
        }
    }
}
