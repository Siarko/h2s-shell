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
// changes. Opened, a card shows its dependencies and the copies it replaces. In safe mode,
// the safe-mode banner at the top (why, Load modules; no Open Modules, no ×).
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
        // Safe mode, for the page's banner (SafeModeBanner)
        property bool safeMode: false
        property string safeModeCause: "relaunch"
        property var guard: ({ count: 2 })
        property int guardClearMs: 30000
        property var previousModulesOn: ["tailscale"]
        property var sourceRecords: null
        property bool discovering: false

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
        function loadWithoutSafeMode() {
            calls = calls.concat(["loadWithoutSafeMode"]);
            return "";
        }
    }

    // The stand-in installer: Remove's preview and remove, recorded
    property var _installer: QtObject {
        signal finished(var result)
        property int jobNumber: 0
        property var previews: ({})
        property var calls: []
        function removalPreview(id, directory, done) {
            calls = calls.concat(["preview " + id + " " + directory]);
            const preview = previews[id] ?? { ok: false, reason: "not in your modules folder" };
            Qt.callLater(() => done(Object.assign({ id: id, directory: directory, title: "", lines: [], orphans: [] }, preview)));
        }
        function remove(id, directory, options) {
            calls = calls.concat(["remove " + id + " " + directory + " " + JSON.stringify(options)]);
            jobNumber++;
            return "";
        }
        // Installing: the suite sets the job's state as the installer would
        property bool busy: false
        property string phase: ""
        property var steps: []
        property var preview: null
        property string installRefusal: ""
        function install(source, options) {
            calls = calls.concat(["install " + source + " " + JSON.stringify(options)]);
            if (installRefusal !== "")
                return installRefusal;
            jobNumber++;
            busy = true;
            phase = "downloading";
            steps = [];
            preview = null;
            return "";
        }
        function proceed(job, options) {
            calls = calls.concat(["proceed " + job + " " + JSON.stringify(options)]);
            phase = "installing";
            preview = null;
            return "";
        }
        function cancelPreview(job) {
            calls = calls.concat(["cancelPreview " + job]);
            return true;
        }
        function cancelDownload(job) {
            calls = calls.concat(["cancelDownload " + job]);
            return true;
        }
        // The job ends as the installer ends it
        function end(ok, message, cancelled) {
            busy = false;
            phase = "";
            preview = null;
            finished({ ok: ok, job: jobNumber, message: message, ids: [], details: { cancelled: cancelled === true } });
        }
    }

    // The stand-in file chooser: records the call, answers with `answer`
    property var _chooser: QtObject {
        property var calls: []
        property var answer: ({ paths: ["/home/you/src/h2s-notes"], cancelled: false, blocked: "", error: "" })
        function choose(handle, options, done, home) {
            calls = calls.concat([options.mode + " " + home]);
            Qt.callLater(() => done(answer));
            return { open: true, cancel: () => {} };
        }
    }

    // The stand-in updater: its state set by the suite, its calls recorded
    property var _updater: QtObject {
        property var checks: ({})
        property bool checking: false
        property string checkingId: ""
        property int checkingIndex: 0
        property int checkingTotal: 0
        property var approvals: ({})
        property var queue: ({ rows: [] })
        property bool automatic: false
        property var calls: []
        property string checkRefusal: ""
        function check(id) {
            calls = calls.concat(["check " + id]);
            return checkRefusal;
        }
        function update(id, version) {
            calls = calls.concat(["update " + id + " " + version]);
            return "";
        }
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
                    installer: suite._installer
                    updater: suite._updater
                    chooser: suite._chooser
                    home: "/home/you"
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
        _installer.previews = {};
        _installer.calls = [];
        _updater.checks = {};
        _updater.checking = false;
        _updater.checkingId = "";
        _updater.approvals = {};
        _updater.calls = [];
        _updater.checkRefusal = "";
        _host.statuses = [
            _status({ id: "tailscale", name: "Tailscale", version: "0.6.0", directory: "/mods/tailscale", entry: "/mods/tailscale", source: "repository",
                      sourceLabel: "From github.com/x/h2s-tailscale @ v0.6.0", deprecations: ["Uses Api.module()"] }),
            _status({ id: "weather", name: "Weather", version: "1.2.0", directory: "/mods/weather", source: "repository",
                      sourceLabel: "From codeberg.org/anna/weather @ main", warnings: ["imports not checked in 2 files"],
                      replaces: [{ directory: "/builtin/weather", source: "builtin", version: "1.0.0" }] }),
            _status({ id: "weather", name: "Weather", version: "1.0.0", directory: "/builtin/weather", source: "builtin", state: "duplicate",
                      shadowedBy: "/mods/weather" }),
            _status({ id: "exitmap", name: "Exit map", version: "0.2.1", directory: "/mods/exitmap", entry: "/mods/exitmap", source: "folder", sourceLabel: "Copied from /src/exitmap" }),
            _status({ id: "backup", name: "Backup", directory: "/mods/backup", state: "failed", sourceLabel: "Your link → /src/backup",
                      errors: ["main.qml:12: <b>Type</b> SnapshotList unavailable"] }),
            _status({ id: "dictation", name: "Dictation", directory: "/builtin/dictation", source: "builtin", sourceLabel: "Built-in",
                      state: "disabled", enabled: false }),
            _status({ id: "player", name: "Player", version: "0.1.0", directory: "/mods/player", entry: "/mods/player", state: "unconfirmed", confirmation: ["new"] }),
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

        _remove();
        _checks();
        _installing();
        _safeModeBanner();
    }

    function _modalChecked(key) {
        return _named(modal.modal, "modalCheck:" + key)[0] ?? null;
    }

    // --- Remove: through the danger modal, keyed to the module ---
    function _remove() {
        _fixture();
        assert(_until(() => _cards().length === 7 && _in(_card("player"), "removeButton") !== null), "the list again");
        assertEqual(["dictation", "evil", "player", "tailscale", "exitmap"].map(id => _in(_card(id), "removeButton") !== null).join(","),
                    "false,false,true,true,true", "Remove: for what the modules folder holds, never for a built-in module or a copy outside it");
        _installer.previews = { player: { ok: true, title: "Remove Player?", key: "plan-1",
                                          lines: ["Not installed by the shell.", "Deletes the folder ~/.local/share/h2s-shell/modules/player."] } };
        const player = _card("player");
        _show(player);
        _click(_in(player, "removeButton"));
        assert(_until(_modalReady), "a click on Remove asks in the modal");
        assertEqual(_installer.calls[0], "preview player /mods/player", "… what it deletes read first, for the module asked about");
        assertEqual(_named(modal.modal, "modalTitle")[0].text, "Remove Player?", "… its title");
        assertEqual(_named(modal.modal, "modalLine").map(line => line.text + (line.font.bold ? "*" : "")).join("|"),
                    "Not installed by the shell.*|Deletes the folder ~/.local/share/h2s-shell/modules/player.", "… not installed by the shell, bold; the folder deleted");
        assert(Qt.colorEqual(modal.modal.panel.children[0].border.color, Theme.error), "… a danger question");
        assert(_modalChecked("data") !== null && !_modalChecked("data").checked, "… \"Also delete its data and settings\", unchecked");
        _click(_modalButton("Keep"));
        assert(_until(() => !modal.open), "Keep closes it");
        assertEqual(_installer.calls.filter(call => call.startsWith("remove")).length, 0, "… nothing removed");

        _click(_in(player, "removeButton"));
        assert(_until(_modalReady), "asked again");
        assert(!_modalChecked("data").checked, "… the box unchecked again");
        _click(_modalChecked("data"));
        assert(_until(() => _modalChecked("data").checked), "… ticked");
        _click(_modalButton("Remove"));
        assert(_until(() => _installer.calls.some(call => call.startsWith("remove"))), "Remove answers it");
        assertEqual(_installer.calls.filter(call => call.startsWith("remove")).join(""), "remove player /mods/player {\"withData\":true,\"alsoRemove\":[],\"planKey\":\"plan-1\"}",
                    "… the module asked about, with its data, keyed to the plan shown");
        assert(!_in(player, "removeButton").available, "… no second Remove while it runs");
        _installer.finished({ ok: false, job: _installer.jobNumber, message: "the folder could not be deleted" });
        assert(_until(() => _card("player").notice === "Could not be removed: the folder could not be deleted"), "a failed remove: its reason on the card");

        // Others need it, a dependency installed for it alone
        _installer.calls = [];
        _installer.previews = { tailscale: { ok: true, title: "Remove Tailscale?", lines: ["Deletes Tailscale 0.6.0.", "These stop working: Exit map."],
                                             orphans: [{ id: "clip", label: "Also remove Clipboard (installed for Tailscale, nothing else uses it) — and a few more words so it cannot fit on one line" }] } };
        _show(_card("tailscale"));
        _click(_in(_card("tailscale"), "removeButton"));
        assert(_until(_modalReady), "Remove Tailscale asks");
        assertEqual(_modalLines().join("|"), "Deletes Tailscale 0.6.0.|These stop working: Exit map.", "… who stops working");
        assert(_modalChecked("also:clip") !== null && !_modalChecked("also:clip").checked, "… the dependency left alone offered, unchecked");
        const longLabel = _named(_modalChecked("also:clip"), "checkboxLabel")[0];
        const labelEnd = longLabel.mapToItem(modal.modal.panel, longLabel.width, 0).x;
        assert(labelEnd <= modal.modal.panel.width && longLabel.lineCount > 1, "… its long label wraps inside the modal (" + labelEnd + " ≤ " + modal.modal.panel.width + ", " + longLabel.lineCount + " lines)");
        assert(_modalChecked("also:clip").height >= longLabel.implicitHeight, "… the box as tall as its lines");
        _click(_modalChecked("also:clip"));
        assert(_until(() => _modalChecked("also:clip").checked));
        _click(_modalButton("Remove"));
        assert(_until(() => _installer.calls.some(call => call.startsWith("remove"))), "… answered");
        assertEqual(_installer.calls.filter(call => call.startsWith("remove")).join(""),
                    "remove tailscale /mods/tailscale {\"withData\":false,\"alsoRemove\":[\"clip\"],\"planKey\":\"\"}", "… with the dependency ticked, without the data");
        _installer.finished({ ok: true, job: _installer.jobNumber, message: "removed" });

        // A preview that refuses asks nothing
        _installer.previews = {};
        _show(_card("exitmap"));
        _click(_in(_card("exitmap"), "removeButton"));
        assert(_until(() => _card("exitmap").notice === "Cannot be removed: not in your modules folder"), "a refused preview: its reason, no question");
        assert(!modal.open, "… no modal");
    }

    // --- Checking for updates ---
    function _checks() {
        _fixture();
        assert(_until(() => _cards().length === 7));
        const checkAll = _all(page, child => child.objectName === "checkAll")[0];
        _show(_card("evil"));
        _all(page, child => child.toString().startsWith("QQuickFlickable"))[0].contentY = 0;
        driver.wait(20);
        assertEqual(checkAll.label + " " + checkAll.available, "Check all true", "\"Check all\" at the top");
        const line = _all(page, child => child.objectName === "checkAllLine")[0];
        _updater.checkRefusal = "Refused while the session is locked";
        _click(checkAll);
        assert(_until(() => line.visible && line.text === "Refused while the session is locked"), "a refused check: why, under the title");
        assert(Qt.colorEqual(line.color, Theme.error), "… in the error colour");
        _updater.checkRefusal = "";
        _updater.calls = [];
        const at = new Date(2026, 10, 21, 14, 32).getTime();
        // An old result: not this run's
        _updater.checks = { printers: { outcome: "current", checkedAt: at }, tailscale: { outcome: "current", checkedAt: at } };
        _click(checkAll);
        assertEqual(_updater.calls.join(","), "check ", "… checks every module");
        _updater.checking = true;
        _updater.checkingTotal = 3;
        _updater.checkingIndex = 2;
        _updater.checkingId = "weather";
        assert(_until(() => line.visible && line.text === "Checking 2 of 3…"), "… says how far it is");
        assertEqual(checkAll.label + " " + checkAll.available, "Checking… false", "… and takes no second click");
        assertEqual(_card("weather").detail + "|" + _card("tailscale").detail, "Checking…|Up to date · checked 14:32", "the card being checked says so; the others keep their last result");

        _updater.checks = { printers: _updater.checks.printers, weather: { outcome: "available", version: "1.3.0", downloading: false, downloadedDir: "1.3.0-abcdef1", checkedAt: at },
                            tailscale: { outcome: "failed", reason: "github.com did not answer", checkedAt: at } };
        _updater.checking = false;
        _updater.checkingId = "";
        assert(_until(() => line.text === "1 update · 1 failed"), "done: its summary, this run's results only");
        assertEqual(_card("weather").detail, "1.3.0 available", "a card's result under its name");
        assert(Qt.colorEqual(_card("weather").detailColor, Theme.accent), "… a version found in the accent");
        assertEqual(_card("tailscale").detail, "Check failed: github.com did not answer", "… a failed check, why");
        assert(Qt.colorEqual(_card("tailscale").detailColor, Theme.error), "… in the error colour");

        const update = _in(_card("weather"), "updateButton");
        assertEqual(update?.label, "Update to 1.3.0", "a downloaded update: its button");
        _show(_card("weather"));
        _click(update);
        assertEqual(_updater.calls[_updater.calls.length - 1], "update weather 1.3.0", "… queues it, the version shown");
        _updater.checks = Object.assign({}, _updater.checks, { weather: Object.assign({}, _updater.checks.weather, { downloading: true, downloadedDir: "" }) });
        assert(_until(() => _in(_card("weather"), "updateButton") === null), "still downloading: no button");
        _updater.checks = Object.assign({}, _updater.checks, { weather: Object.assign({}, _updater.checks.weather, { downloading: false, downloadedDir: "1.3.0-abcdef1" }) });
        _updater.approvals = { weather: { dir: "1.3.0-abcdef1", reasons: [] } };
        assert(_until(() => _in(_card("weather"), "updatePill")?.label === "Approval required"), "waiting for consent: its pill");
        assertEqual(_in(_card("weather"), "updateButton"), null, "… and no button");

        page.openId = "tailscale";
        assert(_until(() => _in(_card("tailscale"), "checkButton") !== null), "an opened card from a repository: Check for updates");
        const checkOne = _in(_card("tailscale"), "checkButton");
        assertEqual(checkOne.label, "Check for updates", "… its label");
        _show(checkOne);
        _click(checkOne);
        assertEqual(_updater.calls[_updater.calls.length - 1], "check tailscale", "… checks that module");
        page.openId = "exitmap";
        assert(_until(() => _card("exitmap").open));
        assertEqual(_in(_card("exitmap"), "checkButton"), null, "a copied folder: no check");
        page.openId = "";
    }

    // In safe mode, the banner at the top of the page: why, with Load modules — no Open
    // Modules (this is the page) and no × (it stays while safe mode does)
    function _safeModeBanner() {
        _fixture();
        assert(_until(() => _cards().length === 7));
        assertEqual(_named(page, "safeModeBanner").length, 0, "out of safe mode: no banner on the page");
        _host.safeMode = true;
        assert(_until(() => (_named(page, "safeModeBanner")[0]?.height ?? 0) > 0), "in safe mode: the banner on the page");
        const banner = _named(page, "safeModeBanner")[0];
        assert(banner.mapToItem(page, 0, 0).y < _cards()[0].mapToItem(page, 0, 0).y, "… above the cards");
        assertEqual(_named(banner, "warningTitle")[0].text, "Started without modules", "… its title");
        assertEqual(_named(banner, "warningBody")[0].text, "The shell crashed twice within 30 seconds of starting. Modules on when it crashed: Tailscale.",
                    "… why, and the modules on when it crashed by name");
        assert(!_named(banner, "openModules")[0].visible && !_named(banner, "warningClose")[0].visible, "… no Open Modules, no ×");
        _host.calls = [];
        _click(_named(banner, "loadModules")[0]);
        assert(_until(() => _host.calls.length === 1), "Load modules calls the host");
        assertEqual(_host.calls[0], "loadWithoutSafeMode", "… to load without safe mode");
        _host.safeMode = false;
        assert(_until(() => _named(page, "safeModeBanner").length === 0), "out of safe mode: the banner gone");
    }

    function _top() {
        _all(page, child => child.toString().startsWith("QQuickFlickable"))[0].contentY = 0;
        driver.wait(20);
    }

    // --- Add a module: the field, the steps, the preview, the outcome ---
    function _installing() {
        _fixture();
        _installer.busy = false;
        _installer.phase = "";
        _installer.installRefusal = "";
        assert(_until(() => _cards().length === 7));
        _all(page, child => child.toString().startsWith("QQuickFlickable"))[0].contentY = 0;
        driver.wait(20);
        const field = _named(page, "installField")[0];
        const install = _named(page, "installButton")[0];
        const error = _named(page, "installError")[0];
        assert(field !== undefined && !install.available, "\"Add a module\": the field; Install waits for an address");

        _click(_named(page, "chooseFolder")[0]);
        assert(_until(() => field.text === "/home/you/src/h2s-notes"), "Choose folder…: the folder chosen lands in the field");
        assertEqual(_chooser.calls.join(","), "folder /home/you", "… the shell's chooser, for a folder, starting at home");

        field.text = "ext::sh -c touch% /tmp/x";
        _installer.installRefusal = "ext:: addresses run commands";
        assert(_until(() => install.available));
        _click(install);
        assert(_until(() => error.visible && error.text === "ext:: addresses run commands"), "a refused address: why, on one line");
        assert(Qt.colorEqual(error.color, Theme.error), "… in the error colour");
        _installer.installRefusal = "";

        field.text = "https://codeberg.org/anna/h2s-notes#v0.4.0";
        assert(_until(() => !error.visible), "a new address: the error goes");
        _click(install);
        assertEqual(_installer.calls[_installer.calls.length - 1], "install https://codeberg.org/anna/h2s-notes#v0.4.0 {\"preview\":true}", "Install: with a preview");
        const job = _installer.jobNumber;
        _installer.steps = [{ key: "1", label: "Notes 0.4.0", state: "verified", percent: 100, rate: null },
                            { key: "2", label: "clipboard", state: "downloading", percent: 45, rate: 2516582 }];
        assert(_until(() => _named(page, "installStep").filter(row => row.visible).length === 2), "downloading: a row per module");
        assertEqual(_named(page, "installPhase")[0].text, "Downloading", "… the step");
        assertEqual(_named(page, "stepText").map(text => text.text).join("|"), "Verified|45% · " + Format.rate(2516582), "… each row's words, the speed");
        const bars = _named(page, "stepBar");
        assert(bars[1].wave && !bars[0].wave && Math.abs(bars[1].value - 0.45) < 0.001, "… the bar of the download waves, at its percent");
        _click(_named(page, "cancelDownload")[0]);
        assertEqual(_installer.calls[_installer.calls.length - 1], "cancelDownload " + job, "… Cancel stops this job's download");

        // The preview
        const plan = { complete: true, refused: "", blocking: [], offers: [],
                       entries: [{ id: "clipboard", name: "Clipboard", kind: "download", neededBy: ["notes"], address: "https://github.com/anna/h2s-clipboard" }] };
        const given = { root: { manifest: { id: "notes", name: "Notes", version: "0.4.0", api: "1.30", description: "Sticky notes in a popup.", programs: ["xclip"] },
                                commit: "4f2a9c1", source: { kind: "repository", address: "https://codeberg.org/anna/h2s-notes#v0.4.0", ref: "v0.4.0" } },
                        fetched: { clipboard: { manifest: { id: "clipboard", name: "Clipboard", version: "0.2.0" } } }, plan: plan, rootTarget: { kind: "new" },
                        replaced: [], shellApi: "1.36", programs: { xclip: true }, goesTo: "~/.local/share/h2s-shell/modules/notes", previous: {} };
        _installer.phase = "preview";
        _installer.preview = Object.assign(ModuleInstallRules.installPreview(given), { job: job,
            changelogs: [{ key: "notes", title: "Notes 0.4.0", text: "## 0.4.0\n- Copy a note.", none: false },
                         { key: "clipboard", title: "Clipboard 0.2.0", text: "No changelog", none: true }] });
        assert(_until(() => _named(page, "installPreview")[0].visible), "the preview");
        assertEqual(_named(page, "previewName")[0].text, "Notes", "… its name");
        assertEqual(_named(page, "installStep").filter(row => row.visible).length, 0, "… the rows give way to it");
        assertEqual(_named(page, "trustTitle")[0].text, "Notes and Clipboard are not part of h2s-shell.", "… the statement for both");
        const rows = label => _all(_named(page, "installPreview")[0], child => child.label === label && child.visible)[0]?.value ?? "";
        assertEqual(rows("Also installs") + " | " + rows("Programs") + " | " + rows("Source"),
                    "Clipboard 0.2.0 — from github.com/anna/h2s-clipboard (Notes needs it) | xclip — found | From codeberg.org/anna/h2s-notes @ v0.4.0\ncommit 4f2a9c1",
                    "… the chain, the programs, the source");
        assert(_named(page, "installEnable")[0].visible && _named(page, "installKeepOff")[0].visible && !_named(page, "installAnyway")[0].visible,
               "… Install and enable, Install keep off; no Install anyway");
        _show(_named(page, "whatsNew")[0]);
        _click(_named(page, "whatsNew")[0]);
        const drawer = _named(page, "changelogPanel")[0];
        assert(_until(() => drawer.open && _named(drawer, "changelogSection").length === 2), "What's new: the side panel, a section per module");
        assertEqual(_named(drawer, "changelogText").map(text => text.text).join("|"), "## 0.4.0\n- Copy a note.|No changelog", "… their text, plain");
        drawer.requested("closeButton");
        assert(_until(() => !drawer.open), "… closed");
        _show(_named(page, "installKeepOff")[0]);
        _click(_named(page, "installKeepOff")[0]);
        assertEqual(_installer.calls[_installer.calls.length - 1], "proceed " + job + " {\"enable\":false,\"anyway\":false}", "Install, keep off: goes on, off");
        assert(_until(() => _named(page, "installPhase")[0].visible && _named(page, "installPhase")[0].text === "Installing"), "… installing");
        _installer.end(true, "installed notes, clipboard (kept off)");
        assert(_until(() => field.text === "" && !error.visible), "installed: the field emptied, no error");

        // A dependency that cannot be had; Cancel
        field.text = "https://github.com/olek/h2s-todo";
        _top();
        _click(install);
        const second = _installer.jobNumber;
        _installer.phase = "preview";
        _installer.preview = Object.assign(ModuleInstallRules.installPreview(Object.assign({}, given, {
            plan: Object.assign({}, plan, { blocking: ["Needs Sync 1.0 — not installed, no address given"] }) })), { job: second, changelogs: [] });
        assert(_until(() => _named(page, "installAnyway")[0].visible), "a dependency that cannot be had: Install anyway");
        assert(!_named(page, "installEnable")[0].visible && !_named(page, "installKeepOff")[0].visible, "… instead of the two");
        assertEqual(_named(page, "previewBlocking").map(row => row.modelData).join(""), "Needs Sync 1.0 — not installed, no address given", "… which, and why");
        _show(_named(page, "installCancel")[0]);
        _click(_named(page, "installCancel")[0]);
        assertEqual(_installer.calls[_installer.calls.length - 1], "cancelPreview " + second, "Cancel: the downloads deleted");
        _installer.end(false, "cancelled", true);
        assert(_until(() => !_named(page, "installPreview")[0].visible), "… the preview gone");
        assertEqual(error.text, "", "… no error for a cancel");

        // A failure: what and why, nothing more
        _top();
        _click(install);
        _installer.end(false, "clipboard: download failed — the server did not answer; nothing installed");
        assert(_until(() => error.visible), "a failure: said");
        assertEqual(error.text, "Clipboard: download failed — the server did not answer", "… what happened and why, nothing more");
        assertEqual(field.text, "https://github.com/olek/h2s-todo", "… the address kept to try again");
        // Another job's answer is not this section's
        _installer.jobNumber += 5;
        _installer.finished({ ok: false, job: 1, message: "old" });
        driver.wait(20);
        assertEqual(error.text, "Clipboard: download failed — the server did not answer", "a late answer of another job: ignored");

        // The window hidden while a preview waits: dropped
        _top();
        _click(install);
        const third = _installer.jobNumber;
        _installer.phase = "preview";
        _installer.preview = Object.assign(ModuleInstallRules.installPreview(given), { job: third, changelogs: [] });
        assert(_until(() => _named(page, "installPreview")[0].visible), "a preview once more");
        _window.visible = false;
        assert(_until(() => _installer.calls[_installer.calls.length - 1] === "cancelPreview " + third), "the window hidden: the preview dropped");
    }
}
