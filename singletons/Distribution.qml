pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.io

// Which distribution the shell runs on, and its static facts (distributions/<id>/
// distribution.json): read by the shell's one DistributionReader, decided by
// DistributionRules. Until the reading has answered — or when it could not be read — `id`
// is "" and `facts` null: unknown, never a default system. Made on first use.
Singleton {
    id: root

    // DistributionRules.detect's answer, frozen
    readonly property var detection: _reader.detection
    readonly property bool ready: detection.ready
    // "nixos" | "arch" | "generic", or "" while unknown
    readonly property string id: detection.id
    // The distribution's facts (DistributionRules.manifest), or null while unknown
    readonly property var facts: detection.facts
    // Every shipped distribution's facts ({ <id>: facts }), for a reading that looks in every
    // system's places; null until the manifests are read, or when one cannot be used
    readonly property var shipped: detection.shipped

    // Calls `callback` once Distribution has answered (`ready`): at once when it has, else
    // just after it does (once every property here has taken the answer). For what needs
    // the facts before it may start — never a guess meanwhile
    function whenReady(callback) {
        if (typeof callback !== "function")
            return;
        if (ready) {
            callback();
            return;
        }
        _waiting = _waiting.concat([callback]);
    }

    property var _waiting: []

    onReadyChanged: {
        if (ready)
            Qt.callLater(root._flush);
    }

    function _flush() {
        if (!ready)
            return;
        const waiting = _waiting;
        _waiting = [];
        for (const callback of waiting)
            callback();
    }

    property DistributionReader _reader: DistributionReader {
        override: TestSeams.distribution
        holdWhile: TestSeams.distributionHold
    }
}
