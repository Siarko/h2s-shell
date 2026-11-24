pragma Singleton

import Quickshell
import QtQuick

// How many command runners were destroyed after Qt had dropped their properties
// (CommandRunner's Component.onDestruction): what the runner's suite checks that it reached
// that case. Counted here, as such a runner cannot write a property of its own.
Singleton {
    property int cleared: 0
}
