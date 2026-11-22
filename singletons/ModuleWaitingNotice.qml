import QtQuick
import Quickshell

// The one notification that says modules are held for the user's confirmation or approval
// (ModuleWaitingRules decides what it says and when): raised once the host has settled, a new
// one in its place when the set of waiting modules changes, closed when none waits. Its action
// "Open Modules" asks for Settings → Modules (openRequested); it confirms nothing itself. It is
// resident (it stays after its action), sent through the shell's own sender with a handle that
// closes it. Dismissed by the user, it stays gone: only a change of the set raises one.
//
// Its state is kept for the process (PersistentProperties): a reload that finds the same set
// raises nothing, and the notification the last run left still works — its action is
// recognised on the notification server by its hint (`hintKey`), and it is closed when the set
// changes.
Scope {
    id: root

    // The module host: statuses, settled, discovering, confirmations, safeMode
    property var host: null
    // Notifier, or a stand-in: send(summary, options) → a handle (open, close())
    property var notifier: Notifier
    // Notifications, or a stand-in: notifications.values, the signal actionInvoked(id,
    // actionId); null in the suites
    property var server: Notifications
    // Lines go to the log (the suites turn it off)
    property bool logging: true

    // "Open Modules" was pressed
    signal openRequested()

    readonly property string hintKey: "x-h2s-modules-waiting"

    readonly property var waiting: ModuleWaitingRules.waiting(host?.statuses ?? [])
    readonly property string waitingKey: ModuleWaitingRules.key(waiting)
    readonly property bool _settled: host?.settled === true && host?.discovering !== true
    readonly property bool _active: host?.confirmations === true && host?.safeMode !== true
    readonly property var noticeState: ModuleWaitingRules.restore(_parse(_memory.stateText))

    // The notification shown by this process, or null
    property var _handle: null

    onWaitingKeyChanged: Qt.callLater(_evaluate)
    on_SettledChanged: Qt.callLater(_evaluate)
    on_ActiveChanged: Qt.callLater(_evaluate)
    Component.onCompleted: Qt.callLater(_evaluate)

    function _parse(text) {
        try {
            return text === "" ? null : JSON.parse(text);
        } catch (error) {
            return null;
        }
    }

    function _log(line) {
        if (logging && line !== "")
            console.info("[Modules] " + line);
    }

    function _evaluate() {
        _apply(ModuleWaitingRules.step(noticeState, { key: waitingKey, settled: _settled, active: _active }));
    }

    function _apply(result) {
        _memory.stateText = JSON.stringify(result.state);
        if (result.action === "close" || result.action === "replace")
            _withdraw();
        if (result.action === "raise" || result.action === "replace")
            _raise();
        _log(ModuleWaitingRules.logLine(result.action, waiting.length));
    }

    function _raise() {
        const text = ModuleWaitingRules.noticeText(waiting);
        _handle = notifier?.send(text.title, {
            body: text.body, format: "plain", handle: true,
            hints: { resident: true, [hintKey]: "1" },
            actions: [{ id: "default", label: "Open Modules", onTriggered: () => root.openRequested() }]
        }) ?? null;
    }

    // The notification shown is taken away, and any an earlier run of the shell left
    function _withdraw() {
        const handle = _handle;
        _handle = null;
        if (handle?.open)
            handle.close();
        for (const notification of (server?.notifications?.values ?? []).slice()) {
            if (typeof notification?.hints?.[hintKey] === "string" && notification.id !== handle?.id)
                notification.dismiss();
        }
    }

    // Whether `id` is a notification of this notice that this process's handle does not
    // follow (one the last run left)
    function _leftBehind(id) {
        if (_handle?.open && (_handle.id === id || _handle.id === 0))
            return false;
        const notification = (server?.notifications?.values ?? []).find(each => each?.id === id);
        return typeof notification?.hints?.[hintKey] === "string";
    }

    Connections {
        target: root.server
        ignoreUnknownSignals: true
        function onActionInvoked(id, actionId) {
            if (actionId === "default" && root._leftBehind(id))
                root.openRequested();
        }
    }

    // The notice's state for this process (ModuleWaitingRules' as JSON): over a reload
    PersistentProperties {
        id: _memory
        reloadableId: "moduleWaitingNotice"
        property string stateText: ""
    }
}
