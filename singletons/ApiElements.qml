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
    }

    function removeFrame(frame) {
        _frames = _frames.filter(entry => entry.frame !== frame && entry.frame !== null);
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
