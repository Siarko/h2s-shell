import QtQuick
import Quickshell
import qs.singletons

// The Settings window's way to the rebuild of NixOS (NixosRebuild, held by the Nixos
// singleton): a page that applies through NixOS calls apply(request) or undo(); this opens the
// announcing modal (or Undo's) through the window's modalHost and, on its Build, starts the
// build and opens the window's one side panel (NixosRebuildPanel in a SideDrawer). The panel
// is only a view: closing it — Close, a click beside it, Escape — never stops the run, which
// lives in NixosRebuild. What the modal and panel say is NixosRebuildViewRules'.
//
// The root run (the password prompt) starts only from applyNow(), the panel's Apply now click,
// naming the system the panel showed; the notification's action only opens the page and
// this panel (NixosRebuild.opened).
Item {
    id: root

    visible: false

    // NixosRebuild (null off NixOS), the configuration's reading (for Undo: the file as it is
    // now), the window's SettingsModalHost
    property var rebuild: null
    property var configuration: null
    property var modalHost: null
    property var copyText: text => {
        Quickshell.clipboardText = text;
    }

    // The side panel is open (the window's SideDrawer follows it)
    property bool panelOpen: false
    // Why the last click did nothing ("" none)
    property string note: ""

    readonly property var state: rebuild?.state ?? NixosRebuildRules.initial()

    Connections {
        target: root.rebuild
        ignoreUnknownSignals: true
        function onOpened() {
            root.panelOpen = true;
        }
    }

    function _took(answer) {
        note = answer?.taken === true ? "" : String(answer?.refusal?.text ?? NixosRebuildRules.texts.notNow);
        return answer?.taken === true;
    }

    // A page's Apply: `request` { key, value, text, reading, previous } (NixosRebuild.announce)
    // → { taken, refusal }
    function apply(request) {
        if (!rebuild)
            return { taken: false, refusal: NixosRebuildRules.refusal("notNow") };
        const answer = rebuild.announce(request);
        if (_took(answer))
            _ask();
        return answer;
    }

    // Undo of the last Apply, keyed to the configuration as read now
    function undo() {
        if (!rebuild)
            return { taken: false, refusal: NixosRebuildRules.refusal("notNow") };
        const answer = rebuild.undo(configuration?.current() ?? null);
        if (_took(answer))
            _ask();
        return answer;
    }

    // The panel's Apply again: the run's own candidate announced once more
    function applyAgain() {
        const subject = state.subject;
        if (!subject)
            return { taken: false, refusal: NixosRebuildRules.refusal("notNow") };
        return apply({ key: subject.key, value: subject.value, text: subject.text, reading: subject.reading, previous: subject.previous });
    }

    // The modal for the announced run; its Build starts the build and shows the panel, anything
    // else lets the announcement go
    function _ask() {
        const run = state.run;
        const refusal = modalHost ? modalHost.ask(NixosRebuildViewRules.question(state), answer => {
            if (!root.rebuild || root.state.phase !== "announced" || answer.subject?.nixosRebuild !== run)
                return;
            if (answer.button === "build") {
                if (root._took(root.rebuild.build()))
                    root.panelOpen = true;
            } else {
                root.rebuild.close();
            }
        }) : "noHost";
        if (refusal !== "") {
            rebuild.close();
            note = NixosRebuildRules.texts.notNow;
        }
    }

    // The panel's Apply now: the one control that starts the root run
    function applyNow() {
        return rebuild ? _took(rebuild.applyNow(state.subject?.drvPath ?? "")) : false;
    }

    function cancel() {
        return rebuild ? _took(rebuild.cancel()) : false;
    }

    function showPanel() {
        panelOpen = true;
    }

    // The panel's Close, a click beside it or Escape: the panel closes, the run goes on
    function panelRequested(event) {
        panelOpen = false;
    }

    function copyLines(lines) {
        copyText((lines ?? []).join("\n"));
    }
}
