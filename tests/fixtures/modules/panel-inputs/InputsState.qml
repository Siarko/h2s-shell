pragma Singleton

import QtQuick
import Quickshell

// The fixture's panel on screen now (null: none), and whether the one with a readonly
// `availableHeight` was told the popup animates, for the suite to find
Singleton {
    property var panel: null
    property bool sawAnimating: false
}
