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
        if (warned.includes(warning.key))
            return;
        warned = warned.concat([warning.key]);
        console.warn(warning.message);
    }
}
