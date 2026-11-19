import QtQuick
import qs.api

// The provider's main: its `exports` is what other modules get (module.uses.provider);
// everything else here is its own
QtObject {
    id: main

    property var module: null
    // Not exported: a dependent must never reach it
    readonly property string secret: "the provider's main"

    readonly property QtObject exports: QtObject {
        readonly property string greeting: "hello from the provider"

        function hello(who) {
            ProviderState.note("hello " + who);
            return "hello, " + who;
        }
    }

    Component.onCompleted: ProviderState.note("provider up")
    Component.onDestruction: ProviderState.note("provider gone")
}
