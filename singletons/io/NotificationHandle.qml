import QtQuick
import Quickshell.Services.Notifications
import qs.singletons

// One progress notification of the shell's own sender (Notifier.send with `progress`):
//
//   open       shown or being shown, not closed
//   state      "starting" | "running" | "done" | "failed" | "cancelled" | "closed" | "unknown"
//              ("unknown": the shell's own server does not hold it — another daemon owns
//              the name, or the call failed — so nothing about it is known: no callbacks)
//   update({ summary?, body?, progress?, actions?, state?, announce? }) → bool, taken
//   close()    takes it away; no onDismissed
//
// I/O only; what to send and when is NotificationRules' (nextSend, answered). One gdbus
// call at a time: while one runs, only the newest wanted content is kept, and sent when it
// answers (a progress-only change at most once per NotificationRules.minUpdateMs). Clicks
// and the dismissal come from the shell's own server (Notifications: actionInvoked,
// notificationClosed, tracks), so no process waits for them. In test mode (recordOnly)
// nothing runs: each show, update and close is recorded (Notifier.recorded) and the
// server answers at once with a made-up id.
QtObject {
    id: root

    // Set by Notifier when it makes the handle
    property int number: 0
    property bool recordOnly: false
    property var runner: null
    // Notifications, or a stand-in: tracks(id), signals actionInvoked(id, actionId) and
    // notificationClosed(id, reason)
    property var server: null
    // The content it wants shown (Notifier.progressContent / updatedContent)
    property var wanted: null
    // { actions: [{ id, onTriggered }], onDismissed }
    property var callbacks: ({ actions: [], onDismissed: null })

    property string state: "starting"
    readonly property bool open: state !== "closed" && state !== "unknown"
    // The server's id, 0 while not known
    property int id: 0
    // gdbus calls started (show, updates and closes): what coalescing saves shows here
    property int calls: 0

    property bool _ended: false
    property bool _inFlight: false
    property var _sent: null
    property real _lastSentAt: 0
    property bool _closeWanted: false
    // Notifications closed while the first show's answer was on its way, by id → reason:
    // a user quick enough to dismiss it before the answer is still a dismissal
    property var _closedEarly: ({})

    property Timer _later: Timer {
        onTriggered: root._pump()
    }

    function update(changes) {
        if (!open || _closeWanted || NotificationRules.endStates.includes(wanted.state))
            return false;
        wanted = Notifier.updatedContent(wanted, changes);
        if (Array.isArray(changes?.actions))
            callbacks = { actions: changes.actions, onDismissed: callbacks.onDismissed };
        if (state !== "starting")
            state = wanted.state;
        if (recordOnly)
            Notifier._recordHandle("update", number, wanted);
        else
            _pump();
        return true;
    }

    function close() {
        if (!open)
            return;
        _closeWanted = true;
        state = "closed";
        if (recordOnly) {
            _ended = true;
            Notifier._recordHandle("close", number, wanted);
            return;
        }
        _pump();
    }

    function _pump() {
        const next = NotificationRules.nextSend({
            ended: _ended, inFlight: _inFlight, id: id, closeWanted: _closeWanted,
            sent: _sent, wanted: wanted, lastSentAt: _lastSentAt
        }, Date.now());
        switch (next.action) {
        case "show":
        case "update":
            _later.stop();
            _send();
            break;
        case "close":
            _later.stop();
            _ended = true;
            _sendClose(id);
            break;
        case "later":
            _later.interval = Math.max(1, next.delayMs);
            _later.restart();
            break;
        }
    }

    function _send() {
        const content = wanted;
        _inFlight = true;
        _lastSentAt = Date.now();
        calls++;
        runner.start(Notifier.progressCommand(content, id), {
            timeoutMs: 5000,
            done: result => root._answered(content, result)
        });
    }

    function _sendClose(closeId) {
        if (!(closeId > 0))
            return;
        calls++;
        runner.start(Notifier.closeCommand(closeId), { timeoutMs: 5000, keepOutput: false });
    }

    function _answered(content, result) {
        _inFlight = false;
        const answerId = result.ok ? NotificationRules.notifyAnswerId(result.stdout) : 0;
        const step = NotificationRules.answered({ ended: _ended, id: id }, answerId);
        switch (step.outcome) {
        case "late":
            _sendClose(step.closeId);
            return;
        case "failed":
            if (id === 0) {
                console.warn("[Notifier] a progress notification could not be shown: "
                             + (result.error || result.stderr || ("exit " + result.code)).slice(0, 200));
                _end("unknown");
                return;
            }
            // Not sent again: the next change sends the whole content anyway
            _sent = content;
            break;
        case "shown":
            id = step.id;
            if (server?.tracks(id) !== true) {
                const early = _closedEarly[id];
                _closedEarly = ({});
                if (early !== undefined)
                    _closedBy(early);
                else
                    _end("unknown");
                return;
            }
            _closedEarly = ({});
            _sent = content;
            if (state === "starting")
                state = wanted.state;
            break;
        case "foreign":
            _sendClose(step.closeId);
            _end("closed");
            return;
        case "updated":
            _sent = content;
            break;
        }
        _pump();
    }

    function _end(endState) {
        _ended = true;
        _later.stop();
        state = endState;
    }

    function _closedBy(reason) {
        const dismissed = reason === NotificationCloseReason.Dismissed && !_closeWanted;
        _end("closed");
        if (dismissed && typeof callbacks.onDismissed === "function")
            _call(callbacks.onDismissed);
    }

    function _call(callback) {
        try {
            callback();
        } catch (error) {
            console.warn("[Notifier] a progress notification's callback threw: " + String(error).slice(0, 300));
        }
    }

    function _onClosed(closedId, reason) {
        if (_ended && !_closeWanted)
            return;
        if (id === 0) {
            if (_inFlight) {
                const early = Object.assign({}, _closedEarly);
                early[closedId] = reason;
                _closedEarly = early;
            }
            return;
        }
        if (closedId !== id || state === "unknown")
            return;
        if (_closeWanted) {
            _end("closed");
            return;
        }
        _closedBy(reason);
    }

    function _onAction(actionId, identifier) {
        if (_ended || _closeWanted || id === 0 || actionId !== id)
            return;
        const action = (callbacks.actions ?? []).find(candidate => String(candidate?.id ?? "") === identifier);
        if (action && typeof action.onTriggered === "function")
            _call(action.onTriggered);
    }

    Component.onCompleted: {
        if (recordOnly) {
            id = 1000000 + number;
            _sent = wanted;
            state = wanted.state;
            Notifier._recordHandle("show", number, wanted);
            return;
        }
        server?.notificationClosed.connect(_onClosed);
        server?.actionInvoked.connect(_onAction);
        _pump();
    }

    Component.onDestruction: {
        if (recordOnly)
            return;
        server?.notificationClosed.disconnect(_onClosed);
        server?.actionInvoked.disconnect(_onAction);
    }
}
