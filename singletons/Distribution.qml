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

    property DistributionReader _reader: DistributionReader {
        override: TestSeams.distribution
        holdWhile: TestSeams.distributionHold
    }
}
