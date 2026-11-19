pragma Singleton

import QtQuick
import Quickshell

// The provider fixture's own singleton: what was asked of its exports, and when its main
// came and went, in order — so the suite can see that a dependent's main goes before it
Singleton {
    property var log: []

    function note(line) {
        log = log.concat([String(line)]);
    }
}
