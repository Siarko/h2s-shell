pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.io

// What the shell knows of the system it runs on — the user, the host, the base directories,
// the download folder, IP forwarding — read by the shell's one SystemFactsReader and decided
// by SystemFactsRules. Modules see it as Api.system (module API 1.13); the module host takes
// the data home from here for the modules' data directories. Made on first use.
Singleton {
    id: root

    // SystemFactsRules.facts, frozen: a new object only when something in it changed
    readonly property string _factsText: JSON.stringify(_reader.facts)
    readonly property var facts: Object.freeze(JSON.parse(_factsText))

    readonly property bool ready: facts.ready
    readonly property string home: facts.home
    readonly property string dataHome: facts.dataHome

    // → frozen { ipv4, ipv6 }: true, false, or null for one that could not be read
    function readIpForwarding() {
        return _reader.readIpForwarding();
    }

    function refresh() {
        _reader.refresh();
    }

    SystemFactsReader {
        id: _reader
    }
}
