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
//   format:      "plain"                          — the texts are plain text (plainOptions)
// }
// No inline reply: notify-send has no option to ask for one (libnotify 0.8.8).
//
// In module test mode (Modules binds `recordOnly` to ModuleHost.testMode) nothing is sent: each
// call is recorded in `recorded` instead, and no callback ever runs — a suite must not reach
// a real notification daemon.
Singleton {
    id: root

    // Record, never send (module test mode)
    property bool recordOnly: false
    // What send() was asked while recordOnly, oldest first, at most maxRecorded: frozen
    // { summary, body, appName, urgency, actions (the labels), format ("plain" or ""),
    // command (notify-send's argv) } — summary and body as sent (plain: made plain)
    property var recorded: []
    readonly property int maxRecorded: 200

    function clearRecorded() {
        recorded = [];
    }

    // ---- Plain text (format: "plain") ----
    // A notification daemon reads the body as markup (the spec's <b>, <i>, <a>, <img>; the
    // shell's own server too, NotificationMarkup) and the summary as plain text. Text from
    // outside the shell — a module's, a command's output, a file's name — is sent with
    // format "plain": each text on one line (line breaks and tabs become spaces), other
    // control characters dropped, cut with "…" at its cap; in the body "&", "<" and ">"
    // become entities, so the daemon shows them as written. The summary is not escaped: the
    // spec has no markup there, and a daemon would show "&amp;".
    readonly property int plainSummaryCap: 200
    readonly property int plainBodyCap: 1000

    // One text as plain sends it, before the body's escaping: one line, no control
    // characters (C0, DEL, C1, U+2028/2029), at most `cap` characters. Not a string or a
    // number: ""
    function plainText(value, cap) {
        if (typeof value !== "string" && typeof value !== "number")
            return "";
        const folded = String(value).replace(/[\r\n\t\v\f\u0085\u2028\u2029]+/g, " ")
            .replace(/[\u0000-\u001f\u007f-\u009f]/g, "");
        const characters = _characters(folded);
        return characters.length > cap ? characters.slice(0, cap - 1).join("") + "…" : folded;
    }

    // A text's characters, a surrogate pair kept whole (Array.from splits it here)
    function _characters(text) {
        const characters = [];
        for (let i = 0; i < text.length; i++) {
            const code = text.charCodeAt(i);
            if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
                const next = text.charCodeAt(i + 1);
                if (next >= 0xdc00 && next <= 0xdfff) {
                    characters.push(text.substr(i, 2));
                    i++;
                    continue;
                }
            }
            characters.push(text[i]);
        }
        return characters;
    }

    // The summary and options as send() hands them on (pure): with format "plain" the
    // summary and body made plain (above), every other option as given; otherwise the same
    // objects, untouched → { summary, options }
    function prepared(summary, opts) {
        const options = opts ?? {};
        if (options.format !== "plain")
            return { summary: summary, options: options };
        const plain = Object.assign({}, options);
        const body = plainText(options.body ?? "", plainBodyCap);
        plain.body = body.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return { summary: plainText(summary ?? "", plainSummaryCap), options: plain };
    }

    // notify-send's argv for a notification (pure; tests/NotifierTest.qml). Every option
    // comes first, then "--", then the summary and the body: text from anywhere (a module, a
    // command's stderr, a peer's name) that starts with "-" is never parsed as an option.
    function command(summary, opts) {
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

        if (hasActions || !!options.onDismissed)
            cmd.push("--wait");

        cmd.push("--", String(summary ?? ""));
        if (options.body)
            cmd.push(String(options.body));
        return cmd;
    }

    function send(givenSummary, opts) {
        const ready = prepared(givenSummary, opts);
        const summary = ready.summary;
        const options = ready.options;
        const cmd = command(summary, options);
        if (recordOnly) {
            recorded = recorded.concat([Object.freeze({
                summary: String(summary ?? ""), body: String(options.body ?? ""), appName: String(options.appName ?? "H2S Shell"),
                urgency: String(options.urgency ?? ""), actions: Object.freeze((Array.isArray(options.actions) ? options.actions : []).map(action => String(action?.label ?? ""))),
                format: options.format === "plain" ? "plain" : "",
                command: Object.freeze(cmd)
            })]).slice(-maxRecorded);
            return;
        }
        let needWait = (options.actions && options.actions.length > 0) || !!options.onDismissed;

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
