import QtQuick
import QtTest
import Quickshell
import qs.singletons
import qs.components
import qs.panels.settings
import qs.distributions.nixos

import qs.mockups.kit

// Settings → System → NixOS as implemented: the real page (NixosSettings), the real rebuild
// run (NixosRebuild, the rules' own steps and times), the window's real wiring of it
// (NixosRebuildFlow, the SideDrawer with NixosRebuildPanel, the SettingsModalHost) on stand-in
// readings. The I/O under the run is stood in for: the build (NixosBuild's place) folds
// stand-in lines of nix's internal-json through NixBuildRules.step and ends with
// NixBuildRules.outcome on nix's stand-in answer; the root step (NixosApply's place) passes
// the stand-in lines of pkexec's run and ends with NixosApplyRules.reply on its stand-in
// last line. The configuration's readings are NixosConfigRules' shape with its facts, what
// is in force NixosDeclareRules.inForce of a stand-in published setting, the Apply's request
// NixosDeclareRules.request. Nothing runs, nothing is read from the system, no notification.
//
// Each state is set up whole in a cell of its own when the cell is made, by the clicks'
// own paths: flow.apply (the page's Apply, the announcing modal), the modal's Build
// (modal.answered), flow.cancel, flow.applyNow (Apply now), flow.undo. The run's clock is the
// cell's: a fixed time, moved on between the steps, so every elapsed time is a fixed value.
// The cells are a settings window's page area each, too large for all of them to fit the
// shooter's output side by side: the kit's StateGrid stacks them (on one another while
// shooting, only the state's cell shown; one under another on screen). No pointer is ever simulated over a cell: it rests on a strip below them from the
// first state on, so nothing shown or hidden is ever under it.
//
//   not-connected        no configuration found: Choose folder…, Look again
//   found-not-in-force   a classic configuration.nix at /etc/nixos, not in git, root's: the
//                        one-time setup, Create with the privileged mark, the line, Copy
//   home-folder          a flake in the home folder: the one-time warning, Use it
//   ready                connected (a flake at /srv/nixos-config, in git): the facts, the
//                        hibernation delay picked 3 h, in force 1 h, Apply
//   apply-announcement   the Apply's modal "Rebuild NixOS"
//   building             the build as the user, 41 s, "Building 4 of 7", Cancel build
//   built-apply-now      "Built in 1 min 12 s." with Apply now (no prompt before that click)
//   waiting-password     after Apply now: the root run waits for the password
//   switching            the root run's lines, no Cancel
//   applied              generation 15, Undo offered
//   build-failed         an error in the configuration (a classic one at /etc/nixos)
//   applied-with-errors  a unit did not start again
//   cancelled            Cancel build pressed
//   set-in-configuration the configuration sets the delay itself: its line wins, no Apply
//   undo-announcement    Undo's modal "Undo the last Apply"
//   undo-building        Undo's build in the same panel
MockupWindow {
    id: root

    onCurrentChanged: pointer.mouseMove(_area.parking, _area.parking.width / 2, _area.parking.height / 2)

    TestCase {
        id: pointer
        when: false
    }

    // ---- Stand-in data ----

    readonly property string store: NixosApplyRules.livePaths.store
    readonly property string drvPath: store + "/86f4485i1vmk8whfp8wbmbqa6vlsmbv8-nixos-system-nixos-26.05.20261101.9bb5222.drv"
    readonly property string outPath: store + "/aayigsnwrdbys1xrj2c6fsxg78nvj3n4-nixos-system-nixos-26.05.20261101.9bb5222"
    // When each run's build starts (ms), as the cell's clock reads it
    readonly property real startMs: root.now.getTime()
    readonly property string fileBefore: JSON.stringify({ version: 1, idle: { hibernateDelay: 3600 } }, null, 2) + "\n"
    readonly property var capability: ({ mode: "declare", trial: false, undo: true, inForce: true, anyway: false, reason: "", known: true })
    readonly property var notConnectedCapability: ({ mode: "copy", trial: false, undo: false, inForce: true, anyway: false, reason: "", known: true })

    // A configuration's reading → NixosConfigRules.reading's shape, with its facts
    function reading(more) {
        const kind = more?.kind ?? "flake";
        const folder = more?.folder ?? "/srv/nixos-config";
        const state = more?.state ?? "connected";
        const fileText = more?.fileText ?? (state === "connected" ? fileBefore : "");
        const result = {
            configuration: { found: true, folder, entry: kind === "flake" ? "flake.nix" : "configuration.nix", type: kind },
            real: folder, owner: more?.owner ?? "root", rootWrites: more?.owner === undefined, git: kind === "flake" ? "present" : "absent",
            gitKnowsFile: kind === "flake" && state === "connected" ? "tracked" : "", host: more?.host ?? "nixos",
            file: fileText === "" ? { path: folder + "/h2s-shell.json", state: "absent", sha256: "" }
                                  : { path: folder + "/h2s-shell.json", state: "present", sha256: PamEditRules.sha256(fileText), text: fileText },
            fileStatus: state === "connected" ? "inForce" : fileText === "" ? "notCreated" : "created",
            module: "present", published: state === "connected" ? "present" : "absent",
            publishedSettings: { system: { idle: { hibernateDelay: more?.inForce ?? "1h" } }, own: { idle: { hibernateDelay: more?.own === true } } },
            generations: { count: more?.generations ?? 14, current: more?.generations ?? 14 }, state,
            homeWarning: more?.homeWarning === true
        };
        result.facts = NixosConfigRules.facts(result);
        return result;
    }

    // nix's stand-in lines (internal-json, on stderr) up to "Building <done> of 7"
    function buildLines(done) {
        const json = event => "@nix " + JSON.stringify(event);
        const derivations = ["h2s-shell-settings.json", "unit-systemd-sleep.conf", "system-units", "etc", "boot.json", "activate",
                             "nixos-system-nixos-26.05.20261101.9bb5222"];
        let lines = [
            json({ action: "msg", level: 4, msg: "evaluating file '/srv/nixos-config/flake.nix'" }),
            json({ action: "start", id: 1, level: 0, parent: 0, text: "", type: 104 }),
            json({ action: "start", id: 2, level: 0, parent: 0, text: "", type: 103 }),
            json({ action: "msg", level: 3, msg: "these 7 derivations will be built:" })
        ].concat(derivations.map(name => json({ action: "msg", level: 3, msg: "  " + store + "/9xq4mbd2l1yzw8hvc0n6k5fkrq7sajgp-" + name + ".drv" })));
        for (let index = 0; index < done; index++) {
            lines.push(json({ action: "start", id: 10 + index, level: 3, parent: 1, text: "building '" + store + "/9xq4mbd2l1yzw8hvc0n6k5fkrq7sajgp-"
                              + derivations[index] + ".drv'", type: 105 }));
            lines.push(json({ action: "result", id: 1, type: 105, fields: [index + 1, 7, index + 1 < 7 ? 1 : 0, 0] }));
        }
        return lines;
    }
    readonly property var failLines: [
        "@nix " + JSON.stringify({ action: "msg", level: 4, msg: "evaluating file '/etc/nixos/configuration.nix'" }),
        "@nix " + JSON.stringify({ action: "msg", level: 0, msg: "error: attribute 'firefox-esr-115' missing\n       at /etc/nixos/configuration.nix:88:7:\n           87|   environment.systemPackages = [\n           88|     pkgs.firefox-esr-115\n             |     ^\n           89|     htop" })
    ]
    readonly property var switchLines: ["activating the configuration...", "setting up /etc...", "reloading user units for alex...",
                                        "restarting the following units: systemd-logind.service"]
    readonly property var errorLines: ["activating the configuration...", "setting up /etc...",
                                       "restarting the following units: bluetooth.service, systemd-logind.service",
                                       "Job for bluetooth.service failed because the control process exited with error code.",
                                       "warning: the following units failed: bluetooth.service"]

    // ---- A state set up in its cell, by the clicks' own paths ----

    function setUp(cell, name) {
        const connected = reading({});
        const flake = !["found-not-in-force", "home-folder", "build-failed"].includes(name);
        cell.value = name === "not-connected" ? { configuration: { found: false }, state: "notConnected", facts: [] }
            : name === "found-not-in-force" ? reading({ kind: "classic", folder: "/etc/nixos", state: "found" })
            : name === "home-folder" ? reading({ folder: "/home/alex/nixos-config", owner: "alex", host: "laptop", state: "found", homeWarning: true })
            : name === "build-failed" ? reading({ kind: "classic", folder: "/etc/nixos" })
            : name === "set-in-configuration" ? reading({ inForce: "10min", own: true })
            : connected;
        cell.delayCapability = ["not-connected", "found-not-in-force", "home-folder"].includes(name) ? notConnectedCapability : capability;
        if (["not-connected", "found-not-in-force", "home-folder", "ready", "set-in-configuration"].includes(name))
            return;
        // An Apply: the page's request, its modal, the Build click
        const made = NixosDeclareRules.request(cell.value, "sleep.hibernateDelay", 10800);
        cell.flow.apply(made.request);
        if (name === "apply-announcement")
            return;
        cell.busy = "apply";
        cell.nowMs = startMs;
        cell.host.modal.answered(0);
        if (name === "build-failed") {
            cell.builder.feed(failLines);
            cell.nowMs = startMs + 23000;
            cell.builder.finish({ code: 1, stdout: "" });
            cell.busy = "";
            return;
        }
        if (name === "building" || name === "cancelled") {
            cell.builder.feed(buildLines(name === "building" ? 4 : 2));
            cell.nowMs = startMs + (name === "building" ? 41000 : 29000);
            if (name === "cancelled") {
                cell.flow.cancel();
                cell.busy = "";
            }
            return;
        }
        cell.builder.feed(buildLines(7));
        cell.nowMs = startMs + 72000;
        cell.builder.finish({ code: 0, stdout: JSON.stringify([{ drvPath, outputs: { out: outPath } }]) });
        if (name === "built-apply-now")
            return;
        // Apply now, minutes later: the root run from that click
        const applying = startMs + 300000;
        cell.nowMs = applying;
        cell.flow.applyNow();
        if (name === "waiting-password") {
            cell.nowMs = applying + 3000;
            return;
        }
        const errors = name === "applied-with-errors";
        for (const line of (errors ? errorLines : switchLines).slice(0, name === "switching" ? 2 : undefined))
            cell.writer.line(line);
        if (name === "switching") {
            cell.nowMs = applying + 6000;
            return;
        }
        cell.nowMs = applying + 9000;
        const expected = { op: "apply", folder: connected.configuration.folder, sha256: PamEditRules.sha256(made.request.text),
                           current: connected.file.sha256 };
        cell.writer.finish(NixosApplyRules.reply(errors ? { code: 4, stdout: "applied-with-errors 15 h2s-shell.json.20260115T103000Z\n", stderr: "" }
                                                        : { code: 0, stdout: "applied 15 h2s-shell.json.20260115T103000Z\n", stderr: "" }, expected));
        // What the page reads after it: the shell's file with 3 h, in force, generation 15
        cell.busy = "";
        cell.undoable = true;
        cell.value = reading({ fileText: made.request.text, inForce: "3h", generations: 15 });
        if (name === "applied" || name === "applied-with-errors")
            return;
        // Undo of that Apply: its modal, then its Build
        cell.flow.panelRequested("close");
        cell.flow.undo();
        if (name === "undo-announcement")
            return;
        cell.busy = "undo";
        const undoStart = startMs + 600000;
        cell.nowMs = undoStart;
        cell.host.modal.answered(0);
        cell.builder.feed(buildLines(4));
        cell.nowMs = undoStart + 41000;
    }

    // The panel's progress bar of a run of unknown length (the switch) slides to and fro
    // without end: held still in the middle through its own reduceMotion
    function stillBars(item) {
        if (!item)
            return;
        if (item.objectName === "rebuild:progress")
            item.reduceMotion = true;
        for (const child of item.children)
            stillBars(child);
    }

    // ---- The cells ----

    // A settings window's page area each: the page, the side panel over its right part, the
    // modal
    StateGrid {
        id: _area
        cellWidth: 890
        cellHeight: 960
        stacked: true
        parkingHeight: 8

        Repeater {
            id: _cells
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]
                readonly property string stateName: name
                clip: true

                // The stand-ins the cell's run and page read
                property var value: null
                property int revision: 0
                property real nowMs: root.startMs
                property var delayCapability: root.capability
                property string busy: ""
                property bool undoable: false
                readonly property var delayInForce: NixosDeclareRules.inForce(value, "sleep.hibernateDelay")
                property alias flow: _flow
                property alias host: _host
                property alias builder: _builder
                property alias writer: _writer

                Component.onCompleted: {
                    root.setUp(cell, stateName);
                    root.stillBars(_drawer.contentItem);
                }

                // The configuration's reading: what current() gives; read() reads nothing
                QtObject {
                    id: _configuration
                    readonly property int revision: cell.revision
                    readonly property bool busy: false
                    function current() {
                        return cell.value === null ? null : JSON.parse(JSON.stringify(cell.value));
                    }
                    function read() {}
                    function choose(folder, host) {}
                    function acknowledgeHome(real) {}
                }

                // The build: nix's stand-in lines through NixBuildRules, its answer at finish()
                QtObject {
                    id: _builder
                    property var _state: NixBuildRules.fresh()
                    property var _done: null
                    readonly property var progress: NixBuildRules.progress(_state)
                    function build(request, handlers) {
                        _state = NixBuildRules.fresh();
                        _done = handlers?.done ?? null;
                        return { started: true, refusal: null };
                    }
                    function feed(lines) {
                        for (const line of lines)
                            _state = NixBuildRules.step(_state, line, "stderr");
                    }
                    function finish(result) {
                        const done = _done;
                        _done = null;
                        done?.(NixBuildRules.outcome(result, _state, root.store));
                    }
                    function cancel() {
                        _done = null;
                        return true;
                    }
                    function release(done) {
                        done?.(true);
                        return true;
                    }
                }

                // The root step: pkexec's stand-in run, its lines and its reply
                QtObject {
                    id: _writer
                    property var _handlers: null
                    readonly property bool busy: _handlers !== null
                    function apply(value, handlers) {
                        _handlers = handlers;
                        return { started: true, refusal: null };
                    }
                    function line(text) {
                        _handlers?.onLine?.(text, "stdout");
                    }
                    function finish(outcome) {
                        const handlers = _handlers;
                        _handlers = null;
                        handlers?.done?.(outcome);
                    }
                }

                NixosRebuild {
                    id: _rebuild
                    builder: _builder
                    writer: _writer
                    notifier: null
                    clock: () => cell.nowMs
                }

                NixosRebuildFlow {
                    id: _flow
                    rebuild: _rebuild
                    configuration: _configuration
                    modalHost: _host
                    copyText: text => {}
                }

                NixosSettings {
                    configuration: _configuration
                    creator: null
                    flow: _flow
                    copyText: text => {}
                    chooseFolder: (start, done) => {}
                    delayCapability: cell.delayCapability
                    delayInForce: cell.delayInForce
                    delayBusy: cell.busy
                    delayUndoable: cell.undoable
                    delayPicked: 10800
                    applyDelay: (request, flow) => {}
                    undoDelay: flow => {}
                    readDelay: () => {}
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
    }
}
