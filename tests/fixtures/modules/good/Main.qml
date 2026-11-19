import QtQuick
import Quickshell.Io
import qs.api

// Created by the module host while the module is enabled; everything of the module that acts
// lives here (its IPC handler, its registration) or follows module.active (GoodState's timer)
QtObject {
    id: main

    // Its handle, set by the host before Component.onCompleted
    property var module: null
    property var goodState: GoodState
    // What module.active was while it was being built
    property bool activeAtStart: false
    // Its progress notification (`progress` over IPC), null before
    property var job: null

    // Its IPC target is its id (a module's targets are <id> or <id>.<name>)
    property IpcHandler ipc: IpcHandler {
        target: "good"

        function ping(): string {
            return "pong " + GoodState.mains;
        }

        function greeting(): string {
            return String(main.module?.value("greeting"));
        }

        function widgetHandle(): string {
            return String(GoodState.widgetSawHandle);
        }

        // (API 1.33) A progress notification, kept by the main: its state
        function progress(): string {
            main.job = main.module.notify("Good job", {
                body: "the fixture's progress", format: "plain", progress: 30, toast: "whileRunning",
                actions: [{ id: "stop", label: "Stop", onTriggered: () => main.job?.update({ state: "cancelled" }) }]
            });
            return main.job ? main.job.state : "none";
        }

        function progressState(): string {
            return main.job ? main.job.state : "none";
        }
    }

    // A stand-in for a provider registered somewhere: it goes with the main
    property QtObject registration: QtObject {
        Component.onCompleted: GoodState.register(this)
        Component.onDestruction: GoodState.unregister(this)
    }

    Component.onCompleted: {
        GoodState.mains += 1;
        GoodState.started += 1;
        activeAtStart = module?.active ?? false;
        GoodState.mainSawHandle = module !== null && activeAtStart;
        module.setFact("ready", true);
        // Its store: how often it was started (not a preference)
        module.store.set("starts", (module.store.get("starts", 0) ?? 0) + 1);
    }
    Component.onDestruction: GoodState.mains -= 1
}
