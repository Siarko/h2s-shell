import QtQuick
import qs.components
import qs.singletons

// The shell started without modules: why, in plain
// words, the modules on when it crashed and one installed or updated in the last day
// (ModuleInstallRules.safeModeBanner), with "Open Modules" (Settings → Modules, to turn
// suspects off) and "Load modules" (the host loads its list again, out of safe mode). Under
// the bar (Hud.qml, with × for this run) and at the top of Settings → Modules (`onPage`,
// without "Open Modules" and ×). Whoever shows it decides when; never on the lock screen
// (tests/lock-closure.sh names this type).
StartupWarning {
    id: root

    // The module host: safeMode, safeModeCause, guard, guardClearMs, previousModulesOn,
    // statuses, sourceRecords, discovering, loadWithoutSafeMode()
    property var host: null
    // "Open Modules": whoever shows the banner opens the page (StartupWarnings)
    signal openRequested
    // Why "Load modules" was refused, until the next click
    property string problem: ""
    // The moment the "updated … ago" is told from: taken when the banner shows, so it does not
    // need a timer
    property real nowMs: Date.now()
    onVisibleChanged: {
        problem = "";
        if (visible)
            nowMs = Date.now();
    }
    // A refusal or a failed search is about the safe mode it was asked in
    readonly property bool _safeMode: host?.safeMode ?? false
    on_SafeModeChanged: problem = ""
    // A search that ended without loading: why (the host's discoveryOutcome)
    readonly property bool _discovering: host?.discovering === true
    on_DiscoveringChanged: {
        const outcome = host?.discoveryOutcome ?? "";
        if (!_discovering && outcome !== "")
            problem = outcome.charAt(0).toUpperCase() + outcome.slice(1);
    }
    // … and when the record changes (read again at a load)
    readonly property var _record: host?.sourceRecords ?? null
    on_RecordChanged: nowMs = Date.now()

    readonly property var words: ModuleInstallRules.safeModeBanner({
        cause: host?.safeModeCause ?? "",
        count: host?.guard?.count ?? 0,
        windowSeconds: (host?.guardClearMs ?? 30000) / 1000,
        previousModulesOn: host?.previousModulesOn ?? [],
        statuses: host?.statuses ?? [],
        record: host?.sourceRecords ?? null,
        nowMs: nowMs,
        discovering: host?.discovering === true
    })

    icon: "󰀦"
    title: words.title
    body: words.body + (problem !== "" ? "\n" + ApiElementRules.oneLine(problem, 200) : "")

    actions: [
        SmallButton {
            objectName: "openModules"
            visible: !root.onPage
            label: "Open Modules"
            onClicked: root.openRequested()
        },
        SmallButton {
            objectName: "loadModules"
            label: root.words.load.label
            available: root.words.load.available
            kind: "warning"
            onClicked: {
                if (!root.words.load.available || !root.host)
                    return;
                root.problem = root.host.loadWithoutSafeMode() ?? "";
            }
        }
    ]
}
