import QtQuick
import Quickshell.Io

// Created by the module host while the module is enabled
QtObject {
    property var goodState: GoodState

    property IpcHandler ipc: IpcHandler {
        target: "good-fixture"

        function ping(): string {
            return "pong " + GoodState.mains;
        }
    }

    Component.onCompleted: {
        GoodState.mains += 1;
        GoodState.started += 1;
    }
    Component.onDestruction: GoodState.mains -= 1
}
