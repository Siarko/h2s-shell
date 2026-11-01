pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// send(summary, opts?)
//
// opts: {
//   body:        string                           — notification body text
//   appName:     string                           — app name (default "H2S Shell")
//   urgency:     "low" | "normal" | "critical"   — urgency level
//   icon:        string                           — icon name or file path
//   expireTime:  number                           — timeout in milliseconds (0 = never)
//   category:    string                           — notification category (e.g. "im.received")
//   transient:   bool                             — don't persist after action
//   replaceId:   number                           — replace existing notification by ID
//   hints:       object                           — extra hints { key: value }
//                                                   value type is inferred (bool/int/double/string)
//   actions:     [{ id, label, onTriggered }]     — action buttons
//   onDismissed: function                         — called when dismissed without action
// }
// No inline reply: notify-send has no option to ask for one (libnotify 0.8.8).
Singleton {
    id: root

    function send(summary, opts) {
        let options = opts ?? {};
        let cmd = ["notify-send"];

        cmd.push("--app-name=" + (options.appName ?? "H2S Shell"));

        if (options.urgency)
            cmd.push("--urgency=" + options.urgency);

        if (options.icon)
            cmd.push("--icon=" + options.icon);

        if (options.expireTime !== undefined)
            cmd.push("--expire-time=" + options.expireTime);

        if (options.category)
            cmd.push("--category=" + options.category);

        if (options.transient)
            cmd.push("--transient");

        if (options.replaceId)
            cmd.push("--replace-id=" + options.replaceId);

        if (options.hints) {
            for (let key in options.hints) {
                let value = options.hints[key];
                let hintType;
                if (typeof value === "boolean")
                    hintType = "boolean";
                else if (Number.isInteger(value))
                    hintType = "int";
                else if (typeof value === "number")
                    hintType = "double";
                else
                    hintType = "string";
                cmd.push("--hint=" + hintType + ":" + key + ":" + value);
            }
        }

        let hasActions = options.actions && options.actions.length > 0;

        if (hasActions) {
            // notify-send's syntax is NAME=Text. With any other separator the whole string
            // becomes the label and the reply is the button's index, so no action matched.
            for (let action of options.actions)
                cmd.push("--action=" + action.id + "=" + action.label);
        }

        let needWait = hasActions || !!options.onDismissed;

        cmd.push(summary);
        if (options.body)
            cmd.push(options.body);
        if (needWait)
            cmd.push("--wait");

        // A process of its own per notification: one shared process meant a second
        // interactive notification killed the first's `notify-send --wait` and took over
        // its callbacks, so the first's buttons did nothing
        const process = _processComponent.createObject(root, {
            command: cmd,
            callbacks: needWait ? {
                actions: options.actions ?? [],
                onDismissed: options.onDismissed ?? null
            } : null
        });
        process.running = true;
    }

    // Calls the callback that matches what notify-send printed when the notification
    // closed: an action id, or nothing for a dismissal
    function _dispatch(callbacks, lines) {
        if (lines.length === 0) {
            if (callbacks.onDismissed)
                callbacks.onDismissed();
            return;
        }

        let firstLine = lines[0];

        let action = callbacks.actions.find(a => a.id === firstLine);
        if (action && action.onTriggered) {
            action.onTriggered();
            return;
        }

        // No match — treated as dismissed
        if (callbacks.onDismissed)
            callbacks.onDismissed();
    }

    // One notify-send run; gone once it exits
    Component {
        id: _processComponent

        Process {
            id: _process
            // null for a notification that needs no reply
            property var callbacks: null
            property var lines: []

            stdout: SplitParser {
                onRead: line => _process.lines = _process.lines.concat([line])
            }

            onExited: (exitCode, exitStatus) => {
                if (_process.callbacks)
                    root._dispatch(_process.callbacks, _process.lines);
                _process.destroy();
            }
        }
    }
}
