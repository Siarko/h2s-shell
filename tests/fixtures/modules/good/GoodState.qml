pragma Singleton

import QtQuick
import Quickshell

// The fixture module's own singleton: one instance for all its files (its qmldir)
Singleton {
    // Mains alive now, and ever created
    property int mains: 0
    property int started: 0

    function greet(name) {
        return "hello, " + name;
    }
}
