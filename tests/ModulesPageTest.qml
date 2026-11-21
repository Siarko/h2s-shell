import QtQuick
import QtTest as QT
import Quickshell
import qs.components
import qs.panels.settings
import qs.singletons

// Settings → Modules → Installed (panels/settings/ModulesSettings.qml) on a stand-in host:
// the cards in the list's order (enabled first, each group by name; a shadowed copy inside
// its winner's card), the name's colour and weight by state and "· Off" under a module that is
// off; a pill only for a state worth attention, which takes no click (the card stays closed);
// the marks' tips on hover; a module's name and errors shown as written, never as markup;
// Enable straight away, or through the confirmation in the Settings modal (and nothing on its
// Cancel); Disable through the button's own question, or through the modal listing the
// running modules that need it (those disabled too); a question withdrawn when its module
// changes. Opened, a card shows its dependencies and the copies it replaces.
//
// Opens a window for a moment, an ordinary one (the modal takes the keyboard in it), in the
// runner's headless compositor.
TestCase {
    id: suite
    suiteName: "ModulesPage"
    asynchronous: true

    // A suite whose window takes the keyboard too: this one's window shows once it is done
    property var after: null

    // The stand-in host: what the page reads of ModuleHost, and its calls recorded
    property var _host: QtObject {
        property var statuses: []
        property var icons: ({ tailscale: { kind: "glyph", glyph: "", url: "", colors: "theme" } })
        property string apiVersion: "1.36"
        property var dataDirectories: ({ tailscale: "/data/module-data/tailscale" })
        property var manifests: ({})
        property var calls: []
        property string confirmRefusal: ""
        // Ids setEnabled refuses to turn off
        property var refuseOff: []

        function manifestOf(directory) {
            return manifests[directory] ?? null;
        }
        function status(id) {
            return statuses.find(status => status.id === id && status.state !== "duplicate") ?? null;
        }
        function setEnabled(id, on) {
            calls = calls.concat(["setEnabled " + id + " " + on]);
            if (!on && refuseOff.includes(id))
                return false;
            statuses = statuses.map(status => status.id === id && status.state !== "duplicate"
                ? Object.assign({}, status, { enabled: on, state: on ? "loaded" : "disabled", confirmation: [] }) : status);
            return true;
        }
        function confirm(id, directory) {
            calls = calls.concat(["confirm " + id + " " + directory]);
            if (confirmRefusal !== "")
                return confirmRefusal;
            setEnabled(id, true);
            return "";
        }
        function iconFailed(id, why) {}
    }

    property var _window: FloatingWindow {
        title: "h2s-tests modules page"
        visible: false
        implicitWidth: 900
        implicitHeight: 1000
        color: Theme.popupBackground

        Item {
            id: area
            // No place: the suite runs beside AnchorsTest, which reads the settings window's
            // places in Anchors.live
            property string anchorBase: ""
            anchors.fill: parent

            // Built for the run only
            Loader {
                id: pageLoader
                anchors.fill: parent
                active: false
                sourceComponent: ModulesSettings {
                    host: suite._host
                    modalHost: modal
                }
            }

            SettingsModalHost {
                id: modal
                anchors.fill: parent
            }
        }

        QT.TestCase {
            id: driver
            name: "ModulesPageDriver"
            when: false
        }
    }

    readonly property Item page: pageLoader.item
    readonly property string _evilName: "<b>Evil</b><img src=x>"

    function _status(fields) {
        return Object.assign({ id: "", name: "", version: "1.0.0", api: "1.36", description: "", directory: "", state: "loaded", enabled: true,
                               errors: [], warnings: [], deprecations: [], missingPrograms: [], setupHints: [], shadowedBy: "",
                               source: "user", sourceLabel: "Your copy", replaces: [], installedFor: "", confirmation: [] }, fields);
    }

    function _fixture() {
        _host.manifests = {
            "/mods/tailscale": { uses: [], programs: ["tailscale"], optionalPrograms: [], privileged: { why: "Connect", programs: ["tailscale"] } },
            "/mods/exitmap": { uses: [{ id: "tailscale", version: "1.0", optional: false }, { id: "weather", version: "1.x", optional: true }],
                               programs: [], optionalPrograms: [], privileged: null },
            "/mods/weather": { uses: [], programs: [], optionalPrograms: [], privileged: null },
            "/mods/backup": { uses: [], programs: [], optionalPrograms: [], privileged: null },
            "/builtin/dictation": { uses: [], programs: [], optionalPrograms: [], privileged: null },
            "/mods/player": { uses: [], programs: [], optionalPrograms: [], privileged: null },
            "/mods/evil": { uses: [], programs: [], optionalPrograms: [], privileged: null }
        };
        _host.calls = [];
        _host.confirmRefusal = "";
        _host.refuseOff = [];
        _host.statuses = [
            _status({ id: "tailscale", name: "Tailscale", version: "0.6.0", directory: "/mods/tailscale", source: "repository",
                      sourceLabel: "From github.com/x/h2s-tailscale @ v0.6.0", deprecations: ["Uses Api.module()"] }),
            _status({ id: "weather", name: "Weather", version: "1.2.0", directory: "/mods/weather", source: "repository",
                      sourceLabel: "From codeberg.org/anna/weather @ main", warnings: ["imports not checked in 2 files"],
                      replaces: [{ directory: "/builtin/weather", source: "builtin", version: "1.0.0" }] }),
            _status({ id: "weather", name: "Weather", version: "1.0.0", directory: "/builtin/weather", source: "builtin", state: "duplicate",
                      shadowedBy: "/mods/weather" }),
            _status({ id: "exitmap", name: "Exit map", version: "0.2.1", directory: "/mods/exitmap", source: "folder", sourceLabel: "Copied from /src/exitmap" }),
            _status({ id: "backup", name: "Backup", directory: "/mods/backup", state: "failed", sourceLabel: "Your link → /src/backup",
                      errors: ["main.qml:12: <b>Type</b> SnapshotList unavailable"] }),
            _status({ id: "dictation", name: "Dictation", directory: "/builtin/dictation", source: "builtin", sourceLabel: "Built-in",
                      state: "disabled", enabled: false }),
            _status({ id: "player", name: "Player", version: "0.1.0", directory: "/mods/player", state: "unconfirmed", confirmation: ["new"] }),
            _status({ id: "evil", name: _evilName, directory: "/mods/evil", description: "<i>not</i> markup" })
        ];
    }

    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
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
        return _all(item, child => child.objectName === name);
    }

    // The cards shown, top to bottom
    function _cards() {
        return _all(page, child => child.kind === "card" && typeof child.modelData === "string" && child.visible)
            .sort((first, second) => first.mapToItem(page, 0, 0).y - second.mapToItem(page, 0, 0).y);
    }

    function _card(id) {
        return _cards().find(card => card.modelData === id) ?? null;
    }

    function _in(card, name) {
        return _named(card, name).find(item => item.visible) ?? null;
    }

    function _click(item) {
        driver.mouseClick(item, item.width / 2, item.height / 2);
    }

    function _modalButton(label) {
        return _all(modal.modal, child => child.objectName.startsWith("modalButton:") && child.label === label && child.visible && child.width > 0)[0] ?? null;
    }

    // The modal open and laid out: its buttons side by side (the row is placed a frame after
    // it opens; a click before would land on a button not yet moved)
    function _modalReady() {
        if (!modal.open || modal.modal.panel.width <= 0)
            return false;
        const buttons = _all(modal.modal, child => child.objectName.startsWith("modalButton:") && child.visible)
            .map(button => button.mapToItem(area, 0, 0).x);
        return buttons.length > 1 && new Set(buttons).size === buttons.length;
    }

    function _modalLines() {
        return _named(modal.modal, "modalLine").map(line => line.text);
    }

    // The tooltip over `target`, if one shows
    function _tipOver(target) {
        const top = target.Window.window?.contentItem;
        return top ? Array.from(top.children).find(child => child.toString().startsWith("HoverTip") && child.target === target) ?? null : null;
    }

    // Scrolls the page so `item` is in view
    function _show(item) {
        const flickable = _all(page, child => child.toString().startsWith("QQuickFlickable"))[0];
        const y = item.mapToItem(flickable.contentItem, 0, 0).y;
        flickable.contentY = Math.max(0, Math.min(y - 40, flickable.contentHeight - flickable.height));
        driver.wait(20);
    }

    function runAsync() {
        try {
            _run();
        } finally {
            if (modal.open)
                modal.cancel("window");
            pageLoader.active = false;
            _window.visible = false;
        }
        finish();
    }

    function _run() {
        assert(_until(() => after === null || after.done, 60000), "the suite before, whose window takes the keyboard, is done");
        _fixture();
        pageLoader.active = true;
        _window.visible = true;
        assert(_until(() => _window.visible && area.width > 0 && _cards().length === 7), "the window shows the cards");

        // --- the list ---
        assertEqual(_cards().map(card => card.modelData).join(","), "evil,backup,exitmap,tailscale,weather,dictation,player",
                    "enabled first, then the ones off, each by name; the shadowed copy is no card");
        const tailscale = _card("tailscale");
        const dictation = _card("dictation");
        assert(Qt.colorEqual(tailscale.titleText.color, Theme.accent) && tailscale.titleText.font.bold, "an enabled module's name: accent, bold");
        assert(Qt.colorEqual(dictation.titleText.color, Theme.textMuted) && !dictation.titleText.font.bold, "a module off: muted");
        assertEqual(tailscale.subtitle + " | " + dictation.subtitle, "0.6.0 · Repository | 1.0.0 · Built-in · Off", "… its line: version · source, Off when off");
        assert(tailscale.leadingItem.children.length === 1 && tailscale.leadingItem.children[0].shownAs === "glyph", "the icon before the name");
        assert(tailscale.titleText.mapToItem(tailscale, 0, 0).x > tailscale.leadingItem.mapToItem(tailscale, 0, 0).x + tailscale.leadingItem.width,
               "… the name after it");

        // --- the pill ---
        assertEqual(_in(tailscale, "statePill"), null, "loaded: no pill");
        const backupPill = _in(_card("backup"), "statePill");
        assertEqual(backupPill?.label, "Failed", "failed: its pill");
        assertEqual(_in(_card("player"), "statePill")?.label, "New — off", "new: its pill");
        _click(backupPill);
        driver.wait(50);
        assert(!backupPill.expanded && page.openId === "" && !_card("backup").open, "a click on the pill opens nothing");

        // --- the marks and their tips ---
        const mark = _in(tailscale, "mark");
        assert(mark !== null && _in(_card("weather"), "mark") !== null && _in(dictation, "mark") === null, "marks beside the names that have some");
        driver.mouseMove(mark, mark.width / 2, mark.height / 2);
        assert(_until(() => _tipOver(mark)?.visible ?? false), "hovering a mark shows its tip");
        assertEqual(_tipOver(mark).text, "1 deprecated API use", "… saying what it counts");
        driver.mouseMove(area, 5, area.height - 5);
        assert(_until(() => !(_tipOver(mark)?.visible ?? false)), "… gone with the pointer");
        _click(mark);
        driver.wait(50);
        assertEqual(page.openId + " " + tailscale.open, " false", "a click on a mark opens nothing");

        // --- text from outside: as written ---
        const evil = _card("evil");
        assert(evil.titleText.textFormat === Text.PlainText && evil.titleText.text === _evilName, "a module's name as written, never markup");
        _click(evil.titleText);
        assert(_until(() => evil.open), "a click on the header opens the card");
        const evilDescription = _all(evil, child => child.visible && child.text === "<i>not</i> markup")[0];
        assert(evilDescription?.textFormat === Text.PlainText, "… its description as written");
        _click(evil.titleText);
        assert(_until(() => !evil.open), "… a second click closes it");
        const backup = _card("backup");
        page.openId = "backup";
        assert(_until(() => _in(backup, "statusLineText") !== null), "a failed module opened: its errors");
        const errorLine = _in(backup, "statusLineText");
        assert(errorLine.textFormat === Text.PlainText && errorLine.text === "main.qml:12: <b>Type</b> SnapshotList unavailable"
               && Qt.colorEqual(errorLine.color, Theme.error), "… as written, in the error colour");

        // --- opened: dependencies, replaced copies ---
        page.openId = "exitmap";
        const exitmap = _card("exitmap");
        assert(_until(() => exitmap.open), "Exit map opened");
        const rows = label => _all(exitmap, child => child.label === label && child.visible)[0]?.value ?? "";
        assertEqual(rows("Needs") + " | " + rows("Can use"), "Tailscale 1.0 — on | Weather 1.x — on", "its dependencies with their state");
        page.openId = "tailscale";
        assert(_until(() => tailscale.open), "Tailscale opened");
        const tailscaleRow = label => _all(tailscale, child => child.label === label && child.visible)[0]?.value ?? "";
        assertEqual(tailscaleRow("Used by") + " | " + tailscaleRow("Administrator") + " | " + tailscaleRow("Data"),
                    "Exit map | asks for your password to: Connect | /data/module-data/tailscale", "… used by, administrator, data");
        page.openId = "weather";
        const weather = _card("weather");
        assert(_until(() => weather.open), "Weather opened");
        assertEqual(_all(weather, child => child.label === "Replaces" && child.visible)[0]?.value, "Replaces the built-in copy (1.0.0)\n/builtin/weather",
                    "… the copy it replaces, inside its card");
        page.openId = "";

        // --- Enable: straight away, and through the confirmation ---
        _show(dictation);
        const dictationButton = _in(dictation, "mainButton");
        assertEqual(dictationButton?.label + " " + dictationButton?.kind, "Enable normal", "a built-in module off: Enable");
        _click(dictationButton);
        assert(_until(() => _host.calls.length === 1), "… a click enables it");
        assertEqual(_host.calls[0], "setEnabled dictation true", "… without a question");
        assert(!modal.open, "… no modal");
        assert(_until(() => _cards().findIndex(card => card.modelData === "dictation") === 5), "enabled, it moves among the enabled");

        _host.calls = [];
        const player = _card("player");
        _show(player);
        const playerButton = _in(player, "mainButton");
        assertEqual(playerButton?.label + " " + playerButton?.kind, "Enable save", "a new module: Enable, which asks");
        _click(playerButton);
        assert(_until(_modalReady), "… the confirmation opens in the modal");
        assertEqual(_named(modal.modal, "modalTitle")[0].text, "Enable Player?", "… its title");
        assertEqual(_modalLines().join("|"), "Player is not part of h2s-shell.|" + ModuleInstallRules.trustText, "… the statement");
        assertEqual(_host.calls.length, 0, "… nothing done yet");
        _click(_modalButton("Cancel"));
        assert(_until(() => !modal.open), "Cancel closes it");
        assertEqual(_host.calls.length, 0, "… and nothing is done");
        _click(playerButton);
        assert(_until(_modalReady), "asked again");
        _click(_modalButton("Enable"));
        assert(_until(() => _host.calls.length > 0), "Enable confirms it");
        assertEqual(_host.calls[0], "confirm player /mods/player", "… the module asked about, by id and directory");

        // A refusal shows on the card
        _fixture();
        assert(_until(() => _cards().length === 7));
        _host.confirmRefusal = "Refused while the session is locked";
        _show(_card("player"));
        _click(_in(_card("player"), "mainButton"));
        assert(_until(_modalReady), "the confirmation once more");
        _click(_modalButton("Enable"));
        assert(_until(() => _card("player").notice === "Refused while the session is locked"), "a refused confirmation: its reason on the card");

        // --- Disable: the button's own question ---
        _fixture();
        assert(_until(() => _cards().length === 7));
        const weatherCard = _card("weather");
        _show(weatherCard);
        assertEqual(_in(weatherCard, "mainButton"), null, "nothing needs Weather: no plain button");
        const disableButton = _in(weatherCard, "disableButton");
        assertEqual(disableButton?.label, "Disable", "… the button that asks");
        _click(disableButton);
        assert(_until(() => disableButton.asking), "a click asks on the button");
        assertEqual(_host.calls.length + " " + modal.open, "0 false", "… nothing done, no modal");
        _click(disableButton);
        assert(_until(() => _host.calls.length === 1), "the second click disables it");
        assertEqual(_host.calls[0], "setEnabled weather false", "… Weather");

        // --- Disable with running dependents: the modal ---
        _fixture();
        assert(_until(() => _cards().length === 7));
        const tailscaleCard = _card("tailscale");
        _show(tailscaleCard);
        assertEqual(_in(tailscaleCard, "disableButton"), null, "Exit map needs Tailscale: no question on the button");
        const tailscaleButton = _in(tailscaleCard, "mainButton");
        assertEqual(tailscaleButton?.label + " " + tailscaleButton?.kind, "Disable warning", "… Disable, a warning");
        _click(tailscaleButton);
        assert(_until(_modalReady), "… it asks in the modal");
        assertEqual(_named(modal.modal, "modalTitle")[0].text, "Disable Tailscale?", "… its title");
        assertEqual(_modalLines().join("|"), "These modules need it and are disabled too:|Exit map", "… the modules disabled with it");
        assert(Qt.colorEqual(modal.modal.panel.children[0].border.color, Theme.warning), "… a warning");
        _click(_modalButton("Disable"));
        assert(_until(() => _host.calls.length === 2), "Disable answers it");
        assertEqual(_host.calls.join(","), "setEnabled exitmap false,setEnabled tailscale false", "… those that need it, then the module");

        // The module changes while asked about: the question goes, nothing done
        _fixture();
        assert(_until(() => _cards().length === 7));
        _show(_card("tailscale"));
        _click(_in(_card("tailscale"), "mainButton"));
        assert(_until(_modalReady), "asked again");
        _host.statuses = _host.statuses.map(status => status.id === "tailscale" && status.state !== "duplicate"
                                                ? Object.assign({}, status, { directory: "/mods/tailscale-0.7.0" }) : status);
        assert(_until(() => !modal.open), "its module changed: the question withdrawn");
        assertEqual(_host.calls.length, 0, "… and nothing done");

        // --- Disable through a chain: each before what it needs, whatever the names ---
        const chainStatuses = [
            _status({ id: "c", name: "C", directory: "/mods/c" }),
            _status({ id: "b", name: "B", directory: "/mods/b" }),
            _status({ id: "z", name: "Z", directory: "/mods/z" })];
        _host.manifests = { "/mods/c": { uses: [] }, "/mods/b": { uses: [{ id: "c", version: "1.0", optional: false }] },
                            "/mods/z": { uses: [{ id: "b", version: "1.0", optional: false }] } };
        _host.calls = [];
        _host.statuses = chainStatuses;
        assert(_until(() => _cards().length === 3 && _in(_card("c"), "mainButton") !== null), "a chain: Z needs B, B needs C");
        driver.wait(100);
        _show(_card("c"));
        _click(_in(_card("c"), "mainButton"));
        assert(_until(_modalReady), "disabling C asks");
        assertEqual(_modalLines()[1], "B, Z", "… both named");
        _click(_modalButton("Disable"));
        assert(_until(() => _host.calls.length === 3), "… answered");
        assertEqual(_host.calls.join(","), "setEnabled z false,setEnabled b false,setEnabled c false", "… Z first, then B, then C");

        // One that cannot be turned off: the others go back on, the card says so
        _host.calls = [];
        _host.statuses = chainStatuses;
        _host.refuseOff = ["b"];
        assert(_until(() => _in(_card("c"), "mainButton") !== null));
        driver.wait(100);
        _show(_card("c"));
        _click(_in(_card("c"), "mainButton"));
        assert(_until(_modalReady), "asked again");
        _click(_modalButton("Disable"));
        assert(_until(() => _host.calls.length === 3), "… answered");
        assertEqual(_host.calls.join(","), "setEnabled z false,setEnabled b false,setEnabled z true", "B refused: stopped there, Z back on, C left on");
        assert(_until(() => _card("c").notice === "Could not be disabled: B could not be turned off"), "… the reason on the card");

        // A name with a line break stands on one line
        _host.refuseOff = [];
        _host.statuses = [_status({ id: "two", name: "Two\nlines", directory: "/mods/two" }),
                          _status({ id: "dep", name: "Dep", directory: "/mods/dep", installedFor: "two" })];
        assert(_until(() => _card("two") !== null && _card("dep") !== null));
        assertEqual(_card("two").titleText.text, "Two lines", "a name with a line break: on one line");
        page.openId = "dep";
        assert(_until(() => _card("dep").open));
        assertEqual(_all(_card("dep"), child => child.label === "Installed for" && child.visible)[0]?.value, "Two lines", "… in Installed for too");
        page.openId = "";
    }
}
