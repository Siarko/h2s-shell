pragma Singleton

import Quickshell
import QtQuick

// The public elements' (qs.api) one voice: a word an element does not know — a kind or a
// size from a newer shell, or a typing mistake — is logged once per element type and
// word, however many elements carry it. An element cannot know which module built it, so
// the warning is in the log, not in a module's status.
Singleton {
    // What was said, by ApiElementRules.unknownWord's key, in order
    property var warned: []

    function unknown(element, property, word, fallback) {
        const warning = ApiElementRules.unknownWord(element, property, word, fallback);
        once(warning.key, warning.message);
    }

    // `message` logged the first time `key` is said
    function once(key, message) {
        if (warned.includes(key))
            return;
        warned = warned.concat([key]);
        console.warn(message);
    }

    // (1.34) The session locked, for side panels: the lock screen's word, or in module test
    // mode the test kit's (ModuleTestKit.setSessionLocked)
    property bool testLocked: false
    readonly property bool sessionLocked: Modules.host.testMode ? testLocked : Profiles.screenLocked

    // (1.34) The page frames that host side panels (components/ModulePageFrame.qml), each with
    // its host: a public SidePanel finds its own by walking up its parents to one of these.
    // Kept by identity, so no name a module could give its own item makes it a frame
    property var _frames: []

    function addFrame(frame, host) {
        _frames = _frames.filter(entry => entry.frame !== frame && entry.frame !== null).concat([{ frame: frame, host: host }]);
        // Panels open from the start that were made before their frame was known
        for (const panel of _waiting.slice()) {
            if (sidePanelHostAbove(panel) === host) {
                _waiting = _waiting.filter(other => other !== panel);
                if (panel.open)
                    sidePanelOpened(panel);
            }
        }
    }

    function removeFrame(frame) {
        _frames = _frames.filter(entry => entry.frame !== frame && entry.frame !== null);
    }

    // (1.34) Each public SidePanel's side a module does not see, by the element: { host (the
    // SidePanelHost it is open in, null while closed), shownIn (the host that showed it
    // last, its content perhaps still sliding out), completed (made: an `open` given at
    // creation is looked at only then, when the panel has its parents) }
    property var _panels: new Map()

    function _panelOf(panel) {
        let entry = _panels.get(panel);
        if (!entry) {
            entry = { host: null, shownIn: null, completed: false };
            _panels.set(panel, entry);
        }
        return entry;
    }

    function sidePanelCheckSize(panel) {
        if (!ApiElementRules.sidePanelSize(panel.size).known)
            unknown("SidePanel", "size", panel.size, ApiElementRules.sizeDefault);
    }

    // The panel's owner set `open`: shown in the frame above it, else refused — `open` back
    // to false, logged once
    function sidePanelOpened(panel) {
        const entry = _panelOf(panel);
        if (entry.host || !entry.completed)
            return;
        const found = sidePanelHostAbove(panel);
        const closer = reason => {
            if (!entry.host)
                return;
            entry.host = null;
            panel.open = false;
            panel.closed(reason);
        };
        const refusal = found ? found.show(panel, closer) : ApiElementRules.sidePanelRefusal(false, false);
        if (refusal !== "") {
            once("SidePanel.open:" + refusal, "[Api] SidePanel: not opened, " + refusal);
            panel.open = false;
            return;
        }
        entry.host = found;
        entry.shownIn = found;
    }

    // Panels open from the start whose frame was not known when they were made
    property var _waiting: []

    // A panel made: with `open` true, shown in the frame above it, or once that frame is known
    // (a page built in the same pass as its frame); none by the end of the pass, refused
    function sidePanelCompleted(panel) {
        _panelOf(panel).completed = true;
        if (!panel.open)
            return;
        if (sidePanelHostAbove(panel) !== null) {
            sidePanelOpened(panel);
            return;
        }
        _waiting = _waiting.concat([panel]);
        Qt.callLater(() => {
            if (!_waiting.includes(panel))
                return;
            _waiting = _waiting.filter(other => other !== panel);
            if (panel.open)
                sidePanelOpened(panel);
        });
    }

    // The owner set `open` false: closed without a reason
    function sidePanelShut(panel) {
        const entry = _panels.get(panel);
        if (!entry?.host)
            return;
        const host = entry.host;
        entry.host = null;
        host.hide(panel);
    }

    // The panel is being destroyed (its page or module going): open, it closes with "page";
    // its content, still shown or sliding out, goes at once — it belongs to the page
    function sidePanelGone(panel) {
        _waiting = _waiting.filter(other => other !== panel);
        const entry = _panels.get(panel);
        _panels.delete(panel);
        if (!entry)
            return;
        const host = entry.host;
        entry.host = null;
        // A host destroyed before the panel has taken the panel's content with it
        if (typeof entry.shownIn?.release === "function")
            entry.shownIn.release(panel);
        if (host && panel.open) {
            panel.open = false;
            panel.closed(ApiElementRules.sidePanelReasons.pageGone);
        }
    }

    // The side panel host of the nearest page frame above `item`, or null
    function sidePanelHostAbove(item) {
        for (let step = item?.parent ?? null; step; step = step.parent) {
            const entry = _frames.find(candidate => candidate.frame === step);
            if (entry)
                return entry.host;
        }
        return null;
    }
}
