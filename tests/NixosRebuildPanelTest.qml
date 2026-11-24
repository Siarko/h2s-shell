import QtQuick
import Quickshell
import qs.components
import qs.singletons
import qs.panels.settings

// The rebuild of NixOS as the Settings window shows it, under clicks and keys, on a stand-in
// NixosRebuild (NixosRebuildRules.step without any process: it records the clicks it is
// given and the actions the rules ask for): the announcing modal "Rebuild NixOS" and Undo's
// "Undo the last Apply" through a SettingsModalHost, the side panel
// (panels/settings/NixosRebuildPanel.qml in a SideDrawer, wired by NixosRebuildFlow as the
// window wires it) in each phase — building, cancelled, built with Apply now, waiting for the
// password, switching, applied, applied with errors, failed — and the run's line on the NixOS
// page with Show and Undo. Apply now is the only control that starts the root run (the
// password prompt follows only that click); closing the panel (Close, a click beside it,
// Escape) never stops the run; a configuration only root can build has the privileged mark
// on Build; Tab and Space reach Apply now.
//
// Stand-ins only: no nix, no pkexec, no notification. Opens a window for a moment in the
// runner's headless compositor.
TestCase {
    id: suite
    suiteName: "NixosRebuildPanel"
    asynchronous: true
    // Its window takes the keyboard
    ownProcess: true

    readonly property string folder: "/srv/nixos-config"
    readonly property string candidate: "{\"version\":1,\"settings\":{\"sleep.hibernateDelay\":\"3h\"}}"
    property string _copied: ""

    // The stand-in run: the rules' own steps, no process
    property QtObject _rebuild: QtObject {
        signal opened()
        property var state: NixosRebuildRules.initial()
        readonly property string phase: state.phase
        property var progress: null
        property var lines: []
        property var times: ({ started: 0, built: 0, ended: 0 })
        property real nowMs: 1000000
        property var clock: () => nowMs
        property var calls: []
        property var actions: []

        function step(event) {
            const result = NixosRebuildRules.step(state, event);
            state = result.state;
            actions = actions.concat(result.actions.map(action => action.type));
            return { taken: result.refused === "", refusal: result.refused === "" ? null : NixosRebuildRules.refusal(result.refused) };
        }
        function _call(name, event) {
            calls = calls.concat([name]);
            return step(event);
        }
        function announce(request) { return _call("announce", { type: "announce", request }); }
        function undo(reading) { return _call("undo", { type: "undo", reading }); }
        function build() { return _call("build", { type: "build" }); }
        function cancel() { return _call("cancel", { type: "cancel" }); }
        function applyNow(drvPath) { return _call("applyNow:" + drvPath, { type: "applyNow", drvPath }); }
        function close() { return _call("close", { type: "close" }); }
    }

    // The stand-in reading: the configuration as read now (Undo keys to it)
    property QtObject _configuration: QtObject {
        property int revision: 0
        property bool busy: false
        property var value: null
        function current() {
            return value === null ? null : JSON.parse(JSON.stringify(value));
        }
        function read() {}
        function choose(folder, host) {}
        function acknowledgeHome(real) {}
    }

    property var _window: FloatingWindow {
        title: "h2s-tests nixos rebuild panel"
        visible: false
        implicitWidth: 1100
        implicitHeight: 1000
        color: Theme.popupBackground

        Item {
            id: area
            anchors.fill: parent
        }

        WindowDriver {
            id: driver
            name: "NixosRebuildPanelDriver"
        }
    }

    // As panels/SettingsWindow.qml wires it
    property Component _harnessComponent: Component {
        Item {
            id: harness
            anchors.fill: parent
            readonly property alias flow: _flow
            readonly property alias drawer: _drawer
            readonly property alias host: _host
            readonly property alias page: _page
            NixosRebuildFlow {
                id: _flow
                rebuild: suite._rebuild
                configuration: suite._configuration
                modalHost: _host
                copyText: text => suite._copied = text
            }
            NixosSettings {
                id: _page
                objectName: "page"
                configuration: suite._configuration
                creator: null
                flow: _flow
            }
            SideDrawer {
                id: _drawer
                anchors.fill: parent
                open: _flow.panelOpen && _flow.rebuild !== null
                title: NixosRebuildViewRules.title(_flow.state)
                panelWidth: ApiElementRules.sidePanelWidth("l", width, Theme.sidePanelWidths)
                content: Component { NixosRebuildPanel { flow: _flow } }
                onRequested: event => _flow.panelRequested(event)
            }
            SettingsModalHost {
                id: _host
                anchors.fill: parent
            }
        }
    }
    property var _harness: null

    // ── Readings and requests ──

    function _reading(sha256) {
        const result = {
            configuration: { found: true, folder, entry: "flake.nix", type: "flake" },
            real: folder, owner: "root", rootWrites: true, git: "present", gitKnowsFile: "tracked", host: "nixos",
            file: { path: folder + "/h2s-shell.json", state: "present", sha256 },
            fileStatus: "inForce", module: "present", published: "present",
            generations: { count: 14, current: 14 }, state: "connected", homeWarning: false
        };
        result.facts = NixosConfigRules.facts(result);
        return result;
    }

    function _request() {
        return { key: "sleep.hibernateDelay", value: "3h", text: candidate, reading: _reading("before"), previous: { value: "1h", text: "{\"version\":1}" } };
    }

    // ── Helpers ──

    function _until(condition, limitMs = 8000) {
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

    function _all(item, name, into) {
        if (!item)
            return into;
        if (item.objectName === name)
            into.push(item);
        for (const child of item.children)
            _all(child, name, into);
        return into;
    }

    function _visible(item) {
        for (let at = item; at; at = at.parent) {
            if (!at.visible)
                return false;
        }
        return item !== null;
    }

    function _item(name) {
        return _find(area, name);
    }

    function _shown(name) {
        return _visible(_item(name));
    }

    function _text(name) {
        const item = _item(name);
        return _visible(item) ? item.text : "(hidden)";
    }

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

    function _click(name) {
        const item = _item(name);
        if (!item || !_visible(item))
            return false;
        _settle(item);
        driver.mouseClick(item, item.width / 2, item.height / 2);
        return true;
    }

    function _panelOpen() {
        return _until(() => _harness.drawer.contentItem !== null && _harness.drawer.panel.x <= _harness.drawer.width - _harness.drawer.panelWidth + 0.5);
    }

    function _panelClosed() {
        return _until(() => _harness.drawer.contentItem === null);
    }

    function _modalOpen() {
        return _until(() => _harness.host.open && _shown("modalTitle"));
    }

    function _applies() {
        return _rebuild.actions.filter(action => action === "apply").length;
    }

    function _marks() {
        return ["build", "password", "switch"].map(id => _item("rebuild:step:" + id)?.mark ?? "?").join(" ");
    }

    function _modalBody() {
        return _all(_harness.host, "modalLine", []).map(line => line.text).join(" / ");
    }

    // ── The run ──

    function runAsync() {
        try {
            _run();
        } finally {
            _harness?.destroy();
            _window.visible = false;
        }
        finish();
    }

    function _run() {
        _configuration.value = _reading("before");
        _window.visible = true;
        assert(_until(() => _window.visible && driver.waitShown()), "the window shows");
        _harness = _harnessComponent.createObject(area);
        assert(_harness !== null, "the harness built");
        assert(_until(() => _harness.page.reading !== null), "the page read");
        assert(!_shown("nixos:rebuild"), "nothing ran, nothing to undo: no rebuild line on the page");

        // --- the announcing modal: Escape lets it go ---
        assert(_harness.flow.apply(_request()).taken && _modalOpen(), "Apply: the announcing modal");
        assertEqual(_text("modalTitle") + " | " + _modalBody(), "Rebuild NixOS | A new NixOS system is built first, as you. No password yet. / "
                    + "This may take minutes and load the machine. You can cancel while it builds. / When it is built, your password applies it.",
                    "… its title and body");
        assertEqual(_item("modalButton:0").label + " " + _shown("modalMark:0") + " " + _item("modalButton:1").label,
                    "Build false Cancel", "… Build, without the privileged mark, and Cancel");
        driver.keyClick(Qt.Key_Escape);
        assert(_until(() => !_harness.host.open), "Escape closes the modal");
        assertEqual(_rebuild.phase + " " + _rebuild.calls.join(",") + " " + _harness.flow.panelOpen, "idle announce,close false", "… the announcement let go, no panel");

        // --- Build: the panel ---
        assert(_harness.flow.apply(_request()).taken && _modalOpen(), "Apply again: the modal");
        assert(_click("modalButton:0") && _until(() => _rebuild.phase === "building"), "Build: building");
        _rebuild.times = { started: _rebuild.nowMs - 41000, built: 0, ended: 0 };
        _rebuild.progress = { label: "Building 2 of 7", fraction: 0.3, lines: ["these 7 derivations will be built:", "building '/nix/store/k2mv-unit.drv'..."] };
        assert(_panelOpen(), "… the side panel opens");
        assertEqual(_harness.drawer.title, "Applying: rebuilding NixOS", "… titled for the Apply");
        assertEqual(["build", "password", "switch"].map(id => _text("rebuild:stepLabel:" + id)).join(" / "), "Build, as you / Your password / Switch", "… the three steps");
        assertEqual(_marks(), "current todo todo", "… the build is the step now");
        assert(_until(() => _text("rebuild:elapsed") === "41 s"), "… the elapsed time");
        assertEqual(_text("rebuild:phase") + " | " + _shown("rebuild:progress") + " " + _item("rebuild:progress").value.toFixed(1), "Building 2 of 7 | true 0.3",
                    "… nix's phase and the progress bar");
        assertEqual(_all(area, "rebuild:line", []).map(line => line.text).join(" / "), "these 7 derivations will be built: / building '/nix/store/k2mv-unit.drv'...",
                    "… nix's last lines under Output");
        assertEqual(_text("rebuild:outputCaption") + " | " + _text("rebuild:closing"), "Output | Closing this panel does not stop the build.", "… the closing line");
        assertEqual([_shown("rebuild:cancel"), _shown("rebuild:applyNow"), _shown("rebuild:applyAgain"), _shown("rebuild:undo"), _shown("rebuild:outcome")].join(" "),
                    "true false false false false", "… Cancel build only");
        _rebuild.nowMs += 2000;
        assert(_until(() => _text("rebuild:elapsed") === "43 s"), "… the time counts on");

        // --- closing the panel keeps the run ---
        const callsBuilding = _rebuild.calls.length;
        assert(_clickClose(), "Close");
        assert(_panelClosed(), "… the panel closes");
        assertEqual(_rebuild.phase + " " + (_rebuild.calls.length === callsBuilding), "building true", "… the build goes on, nothing asked of the run");
        assertEqual(_text("nixos:rebuildLine") + " | " + _shown("nixos:rebuildShow"), "Building… 43 s | true", "… the page says it builds, with Show");
        assert(_click("nixos:rebuildShow") && _panelOpen(), "Show opens the panel again");
        assert(!_shown("nixos:rebuildShow"), "… Show hidden while it is open");
        driver.mouseClick(area, 20, 500);
        assert(_panelClosed(), "a click beside the panel closes it");
        assert(_click("nixos:rebuildShow") && _panelOpen(), "… shown again");
        driver.keyClick(Qt.Key_Escape);
        assert(_panelClosed(), "Escape closes it");
        assertEqual(_rebuild.phase + " " + (_rebuild.calls.length === callsBuilding) + " " + _applies(), "building true 0", "… still building, nothing stopped, no root run");

        // --- Cancel build, then Apply again ---
        assert(_click("nixos:rebuildShow") && _panelOpen(), "shown again");
        assert(_click("rebuild:cancel") && _until(() => _rebuild.phase === "cancelled"), "Cancel build: cancelled");
        _rebuild.times = Object.assign({}, _rebuild.times, { ended: _rebuild.times.started + 45000 });
        assertEqual(_text("rebuild:outcomeText") + " | " + _marks() + " | " + _text("rebuild:phase"), "Cancelled. Nothing changed. | stopped todo todo | Cancelled",
                    "… said, the build stopped");
        assertEqual([_shown("rebuild:cancel"), _shown("rebuild:applyAgain"), _shown("rebuild:closing"), _shown("rebuild:progress")].join(" "), "false true false false",
                    "… Apply again offered, nothing running");
        assert(_click("rebuild:applyAgain") && _modalOpen(), "Apply again: the announcing modal again");
        assertEqual(_rebuild.state.subject.value + " " + _rebuild.state.subject.text, "3h " + candidate, "… for the same candidate");
        assert(_click("modalButton:0") && _until(() => _rebuild.phase === "building"), "… Build: building again");
        _rebuild.times = { started: _rebuild.nowMs, built: 0, ended: 0 };

        // --- built: Apply now ---
        _rebuild.nowMs += 72000;
        _rebuild.step({ type: "built", run: _rebuild.state.run, outcome: { ok: true, drvPath: "/nix/store/a1hd-system.drv", outPath: "/nix/store/a1hd-system" } });
        _rebuild.times = Object.assign({}, _rebuild.times, { built: _rebuild.nowMs });
        assert(_until(() => _text("rebuild:outcomeText") === "Built in 1 min 12 s."), "built: Built in …");
        assertEqual(_text("rebuild:outcomeCaption") + " | " + _marks() + " | " + _text("rebuild:phase"),
                    "Apply now asks for your password. Cancelling it changes nothing. | done current todo | Built", "… what Apply now does, the password next");
        assertEqual([_shown("rebuild:applyNow"), _shown("rebuild:applyNowMark"), _shown("rebuild:cancel"), _shown("rebuild:closing")].join(" "), "true true false false",
                    "… Apply now with the privileged mark");
        assertEqual(_rebuild.actions.join(",") + " | " + _applies(), "build,cancelBuild,build,notify | 0", "… the notification, no root run: no password yet");
        // Every other control leaves the root run alone
        assert(_click("rebuild:copyAll") && _until(() => _copied !== ""), "Copy all");
        assertEqual(_copied, "these 7 derivations will be built:\nbuilding '/nix/store/k2mv-unit.drv'...", "… gives every line");
        assert(_clickClose() && _panelClosed(), "Close while built");
        assertEqual(_rebuild.phase + " " + _rebuild.actions.includes("release") + " " + _applies(), "built false 0", "… the built system kept, still no root run");
        assertEqual(_text("nixos:rebuildLine"), "Built. Waiting for Apply now.", "… the page says it waits");
        assert(_click("nixos:rebuildShow") && _panelOpen(), "Show");

        // Tab reaches Apply now, Space presses it: the root run, once
        let reached = false;
        for (let presses = 0; presses < 12 && !reached; presses++) {
            driver.keyClick(Qt.Key_Tab);
            reached = _until(() => _window.contentItem.Window.activeFocusItem?.objectName === "rebuild:applyNow", 200);
        }
        assert(reached, "Tab reaches Apply now");
        assertEqual(_applies(), 0, "… moving the keyboard asks nothing");
        driver.keyClick(Qt.Key_Space);
        assert(_until(() => _rebuild.phase === "authorizing"), "Space on Apply now: the root run asked");
        assertEqual(_applies() + " " + _rebuild.calls[_rebuild.calls.length - 1], "1 applyNow:/nix/store/a1hd-system.drv", "… once, naming the system built");
        assertEqual(_marks() + " | " + _text("rebuild:phase") + " | " + _shown("rebuild:applyNow"), "done current todo | Waiting for the password | false", "… waiting for the password");

        // --- switching ---
        _rebuild.lines = ["activating the configuration...", "setting up /etc..."];
        _rebuild.step({ type: "line", run: _rebuild.state.run });
        assert(_until(() => _shown("rebuild:switching")), "switching");
        assertEqual(_text("rebuild:switching") + " | " + _marks() + " | " + _shown("rebuild:cancel"), "Switching. This cannot be cancelled now. | done done current | false",
                    "… cannot be cancelled now");
        assertEqual(_all(area, "rebuild:line", []).map(line => line.text).join(" / "), "activating the configuration... / setting up /etc...", "… the root run's lines");

        // --- applied: Undo ---
        _rebuild.nowMs += 9000;
        _rebuild.step({ type: "applied", run: _rebuild.state.run, outcome: { ok: true, kind: "applied", generation: 15 } });
        _rebuild.times = Object.assign({}, _rebuild.times, { ended: _rebuild.nowMs });
        assert(_until(() => _text("rebuild:outcomeText") === "Applied in 1 min 21 s. Generation 15 is in use."), "applied: said with the generation");
        assertEqual(_marks() + " | " + _shown("rebuild:undo") + " " + _shown("rebuild:applyAgain"), "done done done | true false", "… every step done, Undo offered");
        assert(_clickClose() && _panelClosed(), "Close");
        assertEqual(_text("nixos:rebuildLine") + " | " + _shown("nixos:undo"), "Applied. Generation 15. | true", "… the page: applied, Undo");

        // Undo refused: the file changed since that Apply
        _configuration.value = _reading("someone-else");
        assert(_click("nixos:undo") && _until(() => _text("nixos:rebuildNote") === NixosRebuildRules.texts.fileChanged), "Undo with the file changed: said why not");
        assert(!_harness.host.open, "… no modal");
        // Undo: its modal, cancelled
        _configuration.value = _reading(PamEditRules.sha256(candidate));
        assert(_click("nixos:undo") && _modalOpen(), "Undo: its modal");
        assertEqual(_text("modalTitle") + " | " + _modalBody() + " | " + _item("modalButton:0").label, "Undo the last Apply | The shell's previous settings are put back and NixOS is rebuilt. | Undo and build",
                    "… its title, its one sentence, Undo and build");
        assertEqual(_rebuild.state.subject.text + " " + _rebuild.state.subject.undo, "{\"version\":1} true", "… the file before as the candidate");
        assert(_click("modalButton:1") && _until(() => !_harness.host.open && _rebuild.phase === "idle"), "… Cancel: nothing runs");
        assertEqual(_text("nixos:rebuildNote") + " " + _shown("nixos:undo"), "(hidden) true", "… Undo still offered");
        assert(_click("nixos:undo") && _modalOpen(), "Undo again");
        assert(_click("modalButton:0") && _until(() => _rebuild.phase === "building") && _panelOpen(), "… Undo and build: building, the panel");
        assertEqual(_harness.drawer.title, "Undo: rebuilding NixOS", "… titled for Undo");

        // --- a build only root can do: the mark on Build ---
        _rebuild.step({ type: "built", run: _rebuild.state.run, outcome: { ok: false, quiet: false, kind: "failed", reason: "needsRoot",
                                                                            error: NixBuildRules.texts.needsRoot, lines: ["error: opening file: Permission denied"] } });
        assert(_until(() => _text("rebuild:outcomeText") === "The build failed. Nothing changed."), "a build that needs root failed: said");
        assertEqual(_text("rebuild:outcomeCaption") + " | " + _text("rebuild:outputCaption") + " | " + _all(area, "rebuild:line", []).map(line => line.text).join(" / "),
                    NixBuildRules.texts.needsRoot + " Fix the error, then Apply again. | nix's last lines | error: opening file: Permission denied", "… why, nix's last lines");
        assert(!_shown("rebuild:applyAgain") && _shown("rebuild:undo"), "… an Undo's build: Undo again, not Apply again");
        assert(_click("rebuild:undo") && _modalOpen(), "Undo: the modal");
        assertEqual(_shown("modalMark:0") + " " + _item("modalButton:0").label, "true Undo and build", "… its button carries the privileged mark now");
        driver.keyClick(Qt.Key_Escape);
        assert(_until(() => !_harness.host.open && _rebuild.phase === "idle"), "… Escape lets it go");
        assert(_harness.flow.apply(_request()).taken && _modalOpen(), "Apply: the modal");
        assertEqual(_shown("modalMark:0") + " | " + _modalBody(), "true | A new NixOS system is built first. The configuration can be built only with your password. / "
                    + "This may take minutes and load the machine. / When it is built, your password applies it.", "… Build marked, no 'as you', no Cancel promised");
        const appliesBefore = _applies();
        assert(_click("modalButton:0") && _until(() => _rebuild.phase === "building"), "… Build: building as root");
        assertEqual(_text("rebuild:stepLabel:build") + " " + _shown("rebuild:cancel") + " " + _rebuild.state.asRoot + " " + _applies(), "Build false true " + appliesBefore,
                    "… not 'as you', no Cancel, the switch's root run not started");

        // --- applied with errors ---
        _rebuild.step({ type: "built", run: _rebuild.state.run, outcome: { ok: true, drvPath: "/nix/store/b-system.drv", outPath: "/nix/store/b-system" } });
        assert(_until(() => _shown("rebuild:applyNow")), "built as root: Apply now");
        assert(_click("rebuild:applyNow") && _until(() => _rebuild.phase === "authorizing"), "Apply now clicked: the root run");
        assertEqual(_applies(), appliesBefore + 1, "… one more root run, from that click");
        _rebuild.step({ type: "applied", run: _rebuild.state.run, outcome: { ok: true, kind: "appliedWithErrors", generation: 16, error: NixosApplyRules.texts.appliedWithErrors } });
        assert(_until(() => _text("rebuild:outcomeText") === "Applied, with errors: some services did not start again."), "applied with errors: said");
        assertEqual(_text("rebuild:outcomeCaption") + " | " + _marks() + " | " + _shown("rebuild:undo"), "The new values are in force. | done done warning | true",
                    "… the switch warned, Undo offered");
        assertEqual(_rebuild.calls.filter(call => call.startsWith("applyNow:")).length, _applies(), "every root run came from an Apply now click");
    }

    // The panel's own Close button
    function _clickClose() {
        const buttons = [];
        const walk = item => {
            if (!item)
                return;
            if (item.label === "Close" && item.clicked !== undefined)
                buttons.push(item);
            for (const child of item.children)
                walk(child);
        };
        walk(_harness.drawer.panel);
        const button = buttons.find(item => _visible(item)) ?? null;
        if (!button)
            return false;
        _settle(button);
        driver.mouseClick(button, button.width / 2, button.height / 2);
        return true;
    }
}
