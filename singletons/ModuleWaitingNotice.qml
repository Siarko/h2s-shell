import QtQuick
import Quickshell

// The one notification that says modules are held for the user's confirmation or approval
// (ModuleWaitingRules decides what it says and when): raised once the host has settled, a new
// one in its place when the set of waiting modules changes, closed when none waits. Its action
// "Open Modules" asks for Settings → Modules (openRequested); it confirms nothing itself. It is
// resident (it stays after its action), sent through the shell's own sender with a handle that
// closes it; with another notification daemon in its place it is sent plainly, and stays
// until the user closes it. Dismissed by the user, it stays gone: only a change of the set raises one.
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
    // Where the state is kept: an object with a string `stateText` (this process's
    // PersistentProperties; a suite hands one notice's to another, as a reload would)
    property QtObject store: _memory
    readonly property var noticeState: ModuleWaitingRules.restore(_parse(store?.stateText ?? ""))
    // Who shows the notification raised last: "" (none, or not known yet), "shell" (the shell's
    // own server, through the handle), "other" (another notification daemon owns the name: sent
    // plainly, and the shell cannot take it back)
    readonly property string shownBy: _shownBy

    // The notification shown by this process, or null
    property var _handle: null
    property string _shownBy: ""

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
        if (store)
            store.stateText = JSON.stringify(result.state);
        if (result.action === "close") {
            _log(ModuleWaitingRules.logLine(_shownBy === "other" ? "close-other" : "close", waiting.length));
            _withdraw();
        } else if (result.action === "replace" || result.action === "raise") {
            _withdraw();
            _raise(result.action);
        }
    }

    function _options() {
        const text = ModuleWaitingRules.noticeText(waiting);
        return { title: text.title, body: text.body, format: "plain",
                 hints: { resident: true, [hintKey]: "1" },
                 actions: [{ id: "default", label: "Open Modules", onTriggered: () => root.openRequested() }] };
    }

    // Sent with a handle (the shell's own server follows it: it can be closed); logged by the
    // handle's outcome — once the server holds it, or, when another daemon owns the name (the
    // handle gives up: "unknown"), sent again plainly, as notify-send, its action still waiting
    function _raise(action) {
        const options = _options();
        const count = waiting.length;
        _shownBy = "";
        const handle = notifier?.send(options.title, Object.assign({ handle: true }, options)) ?? null;
        _handle = handle;
        if (!handle)
            return;
        let done = false;
        const settle = () => {
            if (done || handle.state === "starting")
                return;
            done = true;
            handle.stateChanged?.disconnect(settle);
            if (handle !== root._handle)
                return;
            if (handle.state === "unknown") {
                root._handle = null;
                root._shownBy = "other";
                root.notifier?.send(options.title, options);
                root._log(ModuleWaitingRules.logLine(action + "-other", count));
                return;
            }
            root._shownBy = "shell";
            root._log(ModuleWaitingRules.logLine(action, count));
        };
        handle.stateChanged?.connect(settle);
        settle();
    }

    // The notification shown is taken away, and any an earlier run of the shell left
    function _withdraw() {
        const handle = _handle;
        _handle = null;
        _shownBy = "";
        if (handle?.open)
            handle.close();
        for (const notification of (server?.notifications?.values ?? []).slice()) {
            if (typeof notification?.hints?.[hintKey] === "string" && !(handle && notification.id === handle.id))
                notification.dismiss();
        }
    }

    // Whether `id` is a notification of this notice that this process's handle does not
    // follow (one the last run left). A click on one opens the page whatever else shows: it
    // confirms nothing
    function _leftBehind(id) {
        if (_handle?.open && id !== 0 && _handle.id === id)
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
