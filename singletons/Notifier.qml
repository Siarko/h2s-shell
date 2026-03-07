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
//   inlineReply: { placeholder?, onReply(text) }  — inline reply input
//   onDismissed: function                         — called when dismissed without action
// }
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
        let hasInlineReply = !!options.inlineReply;

        if (hasActions) {
            for (let action of options.actions)
                cmd.push("--action=" + action.id + ":" + action.label);
        }

        if (hasInlineReply) {
            cmd.push("--inline-reply");
            if (options.inlineReply.placeholder)
                cmd.push("--inline-reply-placeholder=" + options.inlineReply.placeholder);
        }

        let needWait = hasActions || hasInlineReply || !!options.onDismissed;

        cmd.push(summary);
        if (options.body)
            cmd.push(options.body);

        if (needWait) {
            cmd.push("--wait");
            _pendingCallbacks = {
                actions: options.actions ?? [],
                inlineReply: options.inlineReply ?? null,
                onDismissed: options.onDismissed ?? null
            };
            _outputLines = [];
            _waitProcess.running = false;
            _waitProcess.command = cmd;
            _waitProcess.running = true;
        } else {
            _simpleProcess.running = false;
            _simpleProcess.command = cmd;
            _simpleProcess.running = true;
        }
    }

    property var _pendingCallbacks: null
    property var _outputLines: []

    // Fire-and-forget notifications
    Process {
        id: _simpleProcess
        running: false
    }

    // Notifications requiring a response (actions, inline reply, dismiss callback)
    Process {
        id: _waitProcess
        running: false

        stdout: SplitParser {
            onRead: line => {
                root._outputLines = root._outputLines.concat([line]);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (!root._pendingCallbacks)
                return;

            let lines = root._outputLines;
            let callbacks = root._pendingCallbacks;
            root._pendingCallbacks = null;
            root._outputLines = [];

            if (lines.length === 0) {
                if (callbacks.onDismissed)
                    callbacks.onDismissed();
                return;
            }

            let firstLine = lines[0];

            // Inline reply: notify-send outputs "inline-reply" followed by the reply text
            if (callbacks.inlineReply && firstLine === "inline-reply" && lines.length > 1) {
                let replyText = lines.slice(1).join("\n");
                callbacks.inlineReply.onReply(replyText);
                return;
            }

            // Action button: output is the action id
            let action = callbacks.actions.find(a => a.id === firstLine);
            if (action && action.onTriggered) {
                action.onTriggered();
                return;
            }

            // No match — treated as dismissed
            if (callbacks.onDismissed)
                callbacks.onDismissed();
        }
    }
}
