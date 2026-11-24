pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons.io as Io

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
//   progress:    number                           — 0–100, or -1 for a run of unknown length:
//                                                   send() returns a handle (below)
//   toast:       "brief" | "whileRunning"         — with progress: how long its toast shows
//   handle:      true                             — without progress: send() returns a handle
//                                                   all the same, for a plain notification
//                                                   (no bar, not resident) whose actions and
//                                                   dismissal the shell's own server reports
//                                                   in-process and that close() takes away
// }
// No inline reply: notify-send has no option to ask for one (libnotify 0.8.8).
//
// Without `progress` send() returns nothing and runs one notify-send. With it, send()
// returns a handle (io/NotificationHandle.qml: open, state, update(), close()) whose
// notification is sent with `gdbus call … Notify` (progressCommand) and replaced in place
// by its id; the shell is the notification server, so the handle learns a click and a
// dismissal from it in-process (Notifications), never from a waiting process. Such a
// notification is resident (its actions stay after a click), carries the progress in the
// spec's "value" hint and the shell's own hints (x-qs-progress-state, x-qs-progress-run,
// x-qs-announce), and asks for the toast's time by `toast` (NotificationRules.expireTime);
// a caller's own expireTime and x-qs-… hints are not used there.
//
// In module test mode (Modules binds `recordOnly` to ModuleHost.testMode) nothing is sent: each
// call is recorded in `recorded` instead — a suite must not reach a real notification
// daemon. A plain notification's callbacks never run then; a progress notification's run
// only when a suite dismisses it or presses an action (ModuleTestKit, testHandle).
Singleton {
    id: root

    // Record, never send (module test mode)
    property bool recordOnly: false
    // Recording in an isolated process too (Isolation), whatever recordOnly says
    readonly property bool _recording: recordOnly || Isolation.active
    // What send() was asked while recordOnly, oldest first, at most maxRecorded: frozen
    // { summary, body, appName, urgency, actions (the labels), format ("plain" or ""),
    // command (notify-send's argv) } — summary and body as sent (plain: made plain); a
    // progress notification's show, update and close: { kind "show" | "update" | "close",
    // handle (its number), appName, summary, body, progress, state, toast, expireTime, announce,
    // actions (the labels), format }
    property var recorded: []
    readonly property int maxRecorded: 200

    function clearRecorded() {
        recorded = [];
    }

    function _record(entry) {
        recorded = recorded.concat([Object.freeze(entry)]).slice(-maxRecorded);
    }

    // This Notifier's run token, sent with each of its progress notifications: a reload
    // makes a new Notifier, and Notifications dismisses a running notification of another
    // run as an orphan (NotificationRules.orphaned)
    readonly property string progressRun: Date.now().toString(36) + "-" + Math.floor(Math.random() * 2147483647).toString(36)

    // ---- Plain text (format: "plain") ----
    // A notification daemon reads the body as markup (the spec's <b>, <i>, <a>, <img>; the
    // shell's own server too, NotificationMarkup) and the summary as plain text. Text from
    // outside the shell — a module's, a command's output, a file's name — is sent with
    // format "plain": the summary on one line (line breaks and tabs become spaces), the body
    // keeping its line breaks (CR and CRLF as "\n", at most plainBodyLines lines), other
    // control and format characters dropped, cut with "…" at its cap; in the body "&", "<" and ">"
    // become entities, so the daemon shows them as written (a daemon shows the body's "\n"
    // as a line break; the shell's own server turns it into <br>). The summary is not
    // escaped: the spec has no markup there, and a daemon would show "&amp;".
    readonly property int plainSummaryCap: 200
    readonly property int plainBodyCap: 1000
    // A body of more lines is cut after this many, the last kept line ending in "…": enough
    // for a command's short output or a list of a few files, not a log a popup cannot hold
    readonly property int plainBodyLines: 20

    // One text as plain sends it, before the body's escaping: no control or format characters
    // (PrivilegedRules.unprintableCode: C0, DEL, C1, a right-to-left override, a zero-width
    // joiner), at most `cap` characters, counted by code point. With `lines` 0 or absent one
    // line (line breaks, tabs, U+2028/2029 as spaces); with `lines` > 0 line breaks kept as
    // "\n" (CR, CRLF, NEL, U+2028/2029), tabs as spaces, at most `lines` lines (cut with "…"),
    // counted after the text is tidied: white space at its start and end dropped (so a
    // command's closing "\n" makes no empty line), each line's trailing spaces dropped, and a
    // run of blank lines kept as one. Not a string or a number: ""
    function plainText(value, cap, lines) {
        if (typeof value !== "string" && typeof value !== "number")
            return "";
        const maxLines = typeof lines === "number" && lines > 0 ? Math.floor(lines) : 0;
        const folded = maxLines === 0
            ? String(value).replace(/[\r\n\t\v\f\u0085\u2028\u2029]+/g, " ")
            : String(value).replace(/\r\n?|[\u0085\u2028\u2029]/g, "\n").replace(/[\t\v\f]+/g, " ");
        let characters = PrivilegedRules.characters(folded).filter(character => character === "\n" || !PrivilegedRules.unprintableCode(character.codePointAt(0)));
        let cut = false;
        if (maxLines > 0) {
            const tidied = characters.join("").split("\n").map(line => line.replace(/\s+$/, ""))
                .filter((line, index, all) => line !== "" || (index > 0 && all[index - 1] !== ""))
                .join("\n").trim();
            characters = PrivilegedRules.characters(tidied);
            let breaks = 0;
            const end = characters.findIndex(character => character === "\n" && ++breaks === maxLines);
            if (end >= 0) {
                characters = characters.slice(0, end);
                // The "…" goes on the last line with text, not alone on a blank one
                while (characters.length > 0 && characters[characters.length - 1] === "\n")
                    characters.pop();
                cut = true;
            }
        }
        if (characters.length > cap || (cut && characters.length === cap))
            return characters.slice(0, cap - 1).join("") + "…";
        return characters.join("") + (cut ? "…" : "");
    }

    // The summary and options as send() hands them on (pure): with format "plain" the
    // summary and body made plain (above), every other option as given; otherwise the same
    // objects, untouched → { summary, options }
    function prepared(summary, opts) {
        const options = opts ?? {};
        if (options.format !== "plain")
            return { summary: summary, options: options };
        const plain = Object.assign({}, options);
        const body = plainText(options.body ?? "", plainBodyCap, plainBodyLines);
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

    // ---- A progress notification's content and the words gdbus gets (pure) ----

    // The content a handle shows first, from send()'s summary and options → { appName,
    // icon, urgency, category, transient, hints, format, summary, body, actions [{ id,
    // label }], actionsKey, progress, state "running", toast, announce 0, run, handle }
    // — `handle` the handle's mark ("" for none), sent as x-qs-progress-handle, by which a
    // notification made by a show whose answer was lost is found again
    function progressContent(givenSummary, opts, run, handle) {
        const ready = prepared(givenSummary, opts);
        const options = ready.options;
        const actions = (Array.isArray(options.actions) ? options.actions : [])
            .map(action => ({ id: String(action?.id ?? ""), label: String(action?.label ?? "") }));
        return Object.freeze({
            appName: String(options.appName ?? "H2S Shell"), icon: String(options.icon ?? ""),
            urgency: String(options.urgency ?? ""), category: String(options.category ?? ""), transient: options.transient === true,
            hints: options.hints !== null && typeof options.hints === "object" ? Object.assign({}, options.hints) : {},
            format: options.format === "plain" ? "plain" : "",
            summary: String(ready.summary ?? ""), body: String(options.body ?? ""),
            actions: Object.freeze(actions), actionsKey: JSON.stringify(actions),
            progress: typeof options.progress === "number" && !isNaN(options.progress) ? options.progress : 0,
            state: "running", toast: options.toast === "whileRunning" ? "whileRunning" : "brief",
            announce: 0, run: String(run ?? ""), handle: String(handle ?? ""),
            // "plain": a notification with no progress (send's `handle` without `progress`)
            kind: typeof options.progress === "number" && !isNaN(options.progress) ? "progress" : "plain"
        });
    }

    // A content after update(changes) (pure): { summary?, body?, progress?, actions?,
    // state?, announce? } — the texts made plain again with the content's format; a state
    // other than "running" or an end state, or a progress that is not a number, is ignored;
    // announce: true raises the announce count by one
    function updatedContent(content, changes) {
        const given = changes ?? {};
        const next = Object.assign({}, content);
        if (given.summary !== undefined || given.body !== undefined) {
            const ready = prepared(given.summary !== undefined ? given.summary : content.summary,
                { body: given.body !== undefined ? given.body : content.body, format: content.format });
            // A text left unchanged is not made plain twice (its entities would be escaped again)
            if (given.summary !== undefined)
                next.summary = String(ready.summary ?? "");
            if (given.body !== undefined)
                next.body = String(ready.options.body ?? "");
        }
        if (typeof given.progress === "number" && !isNaN(given.progress))
            next.progress = given.progress;
        if (Array.isArray(given.actions)) {
            next.actions = Object.freeze(given.actions.map(action => ({ id: String(action?.id ?? ""), label: String(action?.label ?? "") })));
            next.actionsKey = JSON.stringify(next.actions);
        }
        if (given.state === "running" || NotificationRules.endStates.includes(given.state))
            next.state = given.state;
        if (given.announce === true)
            next.announce = content.announce + 1;
        return Object.freeze(next);
    }

    readonly property var _notificationsCall: ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
        "--object-path", "/org/freedesktop/Notifications", "--method"]

    // gdbus's argv for a content, replacing `replaceId` (0: a new notification). Every
    // argument after "--" is one word of GVariant text (NotificationRules.gvariant*): the
    // spec's Notify(app_name, replaces_id, app_icon, summary, body, actions, hints,
    // expire_timeout). The caller's hints first, without "x-qs-…" keys; the shell's own
    // after them, so they win: urgency as given (normal when not), category, transient as given, resident true, the
    // value, the state, the run, the handle's mark, the announce count (from 1)
    function progressCommand(content, replaceId) {
        const urgencies = { low: 0, normal: 1, critical: 2 };
        const entries = [];
        for (const key in content.hints) {
            // Judged as the server receives the key: a NUL or a lone surrogate in front
            // does not get an "x-qs-" key past this
            if (NotificationRules.gvariantText(key).startsWith("x-qs-"))
                continue;
            const value = content.hints[key];
            entries.push({ key: key, type: NotificationRules.hintType(value), value: value });
        }
        // Always its own urgency (normal unless given), so a caller's "urgency" hint, which
        // the same key replaces, never makes it critical behind the option's back
        entries.push({ key: "urgency", type: "byte", value: urgencies[content.urgency] ?? 1 });
        if (content.category !== "")
            entries.push({ key: "category", type: "string", value: content.category });
        if (content.transient)
            entries.push({ key: "transient", type: "boolean", value: true });
        // A plain one carries no progress, is not resident, and has no run token (nothing of
        // it is left running for a reload to dismiss as an orphan)
        if (content.kind !== "plain") {
            entries.push({ key: "resident", type: "boolean", value: true });
            entries.push({ key: "value", type: "int32", value: NotificationRules.progressValue(content.progress) });
            entries.push({ key: "x-qs-progress-state", type: "string", value: content.state });
            entries.push({ key: "x-qs-progress-run", type: "string", value: content.run });
        }
        if (content.handle !== "")
            entries.push({ key: "x-qs-progress-handle", type: "string", value: content.handle });
        if (content.announce > 0)
            entries.push({ key: "x-qs-announce", type: "string", value: String(content.announce) });
        const actionWords = [];
        for (const action of content.actions)
            actionWords.push(action.id, action.label);
        const id = Number.isInteger(replaceId) && replaceId > 0 && replaceId <= 4294967295 ? replaceId : 0;
        return _notificationsCall.concat(["org.freedesktop.Notifications.Notify", "--",
            NotificationRules.gvariantString(content.appName), "uint32 " + id, NotificationRules.gvariantString(content.icon),
            NotificationRules.gvariantString(content.summary), NotificationRules.gvariantString(content.body),
            NotificationRules.gvariantStringArray(actionWords), NotificationRules.gvariantHints(entries),
            "int32 " + NotificationRules.expireTime(content.toast, content.state)]);
    }

    // gdbus's argv closing notification `id`
    function closeCommand(id) {
        const known = Number.isInteger(id) && id > 0 && id <= 4294967295 ? id : 0;
        return _notificationsCall.concat(["org.freedesktop.Notifications.CloseNotification", "--", "uint32 " + known]);
    }

    // Handles made so far (their numbers), and the ids test mode makes up for them
    property int _handles: 0

    // Handles not yet ended, kept here; an ended one is kept only by its caller, so it is
    // freed when the caller lets it go (made without a parent: JavaScript owns it)
    property var _liveHandles: []

    function _sendProgress(givenSummary, options) {
        _handles++;
        const handle = _handleComponent.createObject(null, {
            number: _handles, recordOnly: _recording, runner: _runner, server: Notifications,
            wanted: progressContent(givenSummary, options, progressRun, String(_handles)),
            callbacks: { actions: Array.isArray(options.actions) ? options.actions : [], onDismissed: options.onDismissed ?? null }
        });
        if (handle.open) {
            _liveHandles = _liveHandles.concat([handle]);
            handle.finished.connect(() => root._liveHandles = root._liveHandles.filter(live => live !== handle));
        }
        return handle;
    }

    // Test mode: the open handle of that number (the `handle` of its records), or null
    function testHandle(number) {
        return _recording ? (_liveHandles.find(live => live.number === number && live.recordOnly) ?? null) : null;
    }

    // Progress handles kept for an owner (a module's handle) until they end: closed together
    // when the owner goes (closeOwned: the module turned off), let go without a word when it
    // is destroyed (forgetOwned). Kept here, out of the owner's reach: what a module can
    // read of its handle (or of another module's) leads to none of them
    property var _owned: new Map()      // owner → Map(handle → its `finished` connection)

    function own(owner, handle) {
        if (!owner || !handle?.open)
            return;
        let handles = _owned.get(owner);
        if (!handles) {
            handles = new Map();
            _owned.set(owner, handles);
        }
        if (handles.has(handle))
            return;
        const connection = () => root._disown(owner, handle);
        handles.set(handle, connection);
        handle.finished.connect(connection);
    }

    function _disown(owner, handle) {
        const handles = _owned.get(owner);
        const connection = handles?.get(handle);
        if (connection === undefined)
            return;
        handles.delete(handle);
        if (handles.size === 0)
            _owned.delete(owner);
        handle.finished.disconnect(connection);
    }

    function closeOwned(owner) {
        for (const handle of Array.from(_owned.get(owner)?.keys() ?? [])) {
            _disown(owner, handle);
            handle.close();
        }
    }

    function forgetOwned(owner) {
        for (const handle of Array.from(_owned.get(owner)?.keys() ?? []))
            _disown(owner, handle);
    }

    // How many open handles an owner has (tests)
    function ownedCount(owner) {
        return _owned.get(owner)?.size ?? 0;
    }

    // A handle's show, update or close in test mode, as recorded
    function _recordHandle(kind, number, content) {
        _record({
            kind: kind, handle: number, appName: content.appName, summary: content.summary, body: content.body, progress: content.progress,
            state: content.state, toast: content.toast, expireTime: NotificationRules.expireTime(content.toast, content.state),
            announce: content.announce, actions: Object.freeze(content.actions.map(action => action.label)), format: content.format
        });
    }

    property Io.CommandRunner _runner: Io.CommandRunner {}

    Component {
        id: _handleComponent
        Io.NotificationHandle {}
    }

    function send(givenSummary, opts) {
        if ((typeof opts?.progress === "number" && !isNaN(opts.progress)) || opts?.handle === true)
            return _sendProgress(givenSummary, opts);
        const ready = prepared(givenSummary, opts);
        const summary = ready.summary;
        const options = ready.options;
        const cmd = command(summary, options);
        if (_recording) {
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
