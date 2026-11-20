import QtQuick
import Quickshell.Services.Notifications
import qs.singletons
import qs.hud
import qs.components
import qs.singletons.io

// Notifier's pure parts: format "plain" (what it makes of a summary and a body) and the words
// notify-send gets for it. Nothing is sent: send() is checked in module test mode, where it
// records (tests/fixtures/modules/good, GoodApiTest).
TestCase {
    id: suite
    suiteName: "Notifier"

    property Component _shellToast: Component {
        ShellNotificationHudItem {
            screenWidth: 800
            screenHeight: 600
            screenModelData: ({ name: "test-screen" })
        }
    }

    function run() {
        // --- plainText: one line, no control characters, capped ---
        assertEqual(Notifier.plainText("a\nb\r\nc\td", 100), "a b c d", "plainText: line breaks and tabs become spaces");
        assertEqual(Notifier.plainText("a b c\u0085d", 100), "a b c d", "plainText: Unicode line and paragraph separators too");
        assertEqual(Notifier.plainText("be\u0007ll\u001b[31m\u007f\u009bx", 100), "bell[31mx", "plainText: other control characters dropped");
        assertEqual(Notifier.plainText("evil\u202etxt.exe a\u200db\u2066c\u2069 \ufeffd", 100), "eviltxt.exe abc d", "plainText: format characters dropped (an override, a joiner, isolates, a BOM)");
        assertEqual(Notifier.plainText("a\u2028b\u2029c", 100), "a b c", "plainText: line and paragraph separators become spaces");
        assertEqual(Notifier.plainText("x\ud800y😀", 100), "xy😀", "plainText: a lone surrogate dropped, a pair kept");
        assertEqual(Notifier.plainText("😀".repeat(3) + "\u202e", 3), "😀😀😀", "plainText: a dropped character does not count toward the cap");
        assertEqual(Notifier.plainText("x".repeat(10), 5), "xxxx…", "plainText: cut with …");
        assertEqual(Notifier.plainText("x".repeat(5), 5), "xxxxx", "plainText: at the cap, kept");
        assertEqual(Notifier.plainText("😀".repeat(6), 5), "😀😀😀😀…", "plainText: counted in characters, a pair never split");
        assertEqual(Notifier.plainText(42, 10) + "|" + Notifier.plainText(null, 10) + "|" + Notifier.plainText({ toString: () => "x" }, 10), "42||",
                    "plainText: a number as text, anything else nothing");

        // --- plainText with lines: the body's line breaks kept ---
        assertEqual(JSON.stringify(Notifier.plainText("a\nb\r\nc\rd\te", 100, 20)), JSON.stringify("a\nb\nc\nd e"),
                    "plainText (lines): LF kept, CRLF and CR as LF, a tab a space");
        assertEqual(JSON.stringify(Notifier.plainText("a\u2028b\u2029c\u0085d", 100, 20)), JSON.stringify("a\nb\nc\nd"),
                    "plainText (lines): the Unicode line and paragraph separators as LF");
        assertEqual(JSON.stringify(Notifier.plainText("a\n\u0007b\u202e\nc", 100, 20)), JSON.stringify("a\nb\nc"),
                    "plainText (lines): other control and format characters still dropped");
        const twentyFive = Array.from({ length: 25 }, (unused, i) => "line" + (i + 1)).join("\n");
        const cutLines = Notifier.plainText(twentyFive, 1000, 20);
        assertEqual(cutLines.split("\n").length + " " + cutLines.split("\n")[19], "20 line20…", "plainText (lines): cut after 20 lines, the last kept one ending in …");
        assertEqual(Notifier.plainText(Array(20).fill("x").join("\n"), 1000, 20).split("\n").length + " " + Notifier.plainText(Array(20).fill("x").join("\n"), 1000, 20).endsWith("…"),
                    "20 false", "plainText (lines): 20 lines, kept whole");
        assertEqual(Notifier.plainText("ab\nc", 2, 1), "a…", "plainText (lines): a line cut that meets the character cap stays within it");
        assertEqual(JSON.stringify(Notifier.plainText("error: x\n", 1000, 20)), JSON.stringify("error: x"), "plainText (lines): a closing line break makes no empty line");
        assertEqual(JSON.stringify(Notifier.plainText(" \n\t\r\n  a\n  b  \n \n\n", 1000, 20)), JSON.stringify("a\n  b"),
                    "plainText (lines): white space and line breaks at the start and end dropped, an inner line's indent kept, its trailing spaces dropped");
        assertEqual(JSON.stringify(Notifier.plainText("a\n\n\n \n\t\nb\n\nc", 1000, 20)), JSON.stringify("a\n\nb\n\nc"),
                    "plainText (lines): a run of blank lines (white space only too) kept as one");
        assertEqual(JSON.stringify(Notifier.plainText("a\n\u0007\nb", 1000, 20)), JSON.stringify("a\n\nb"),
                    "plainText (lines): a line of only a control character is blank once it is dropped");
        const twentyAndBreak = Array.from({ length: 20 }, (_, i) => "line" + (i + 1)).join("\n") + "\n";
        assertEqual(Notifier.plainText(twentyAndBreak, 1000, 20).split("\n").length + " " + Notifier.plainText(twentyAndBreak, 1000, 20).endsWith("…"), "20 false",
                    "plainText (lines): exactly 20 lines and a closing \"\\n\": kept whole, no …");
        const blanksBetween = Array.from({ length: 20 }, (_, i) => "line" + (i + 1)).join("\n\n\n");
        assertEqual(JSON.stringify(Notifier.plainText(blanksBetween, 1000, 20).split("\n").slice(-2)), JSON.stringify(["", "line10…"]),
                    "plainText (lines): folded blank lines still count, one each; a cut on a blank line puts the … on the line before");
        assertEqual(Notifier.plainText("a\nb", 100, 0) + "|" + Notifier.plainText("a\nb", 100), "a b|a b", "plainText: no lines given, one line");

        // --- prepared: format "plain" ---
        const plain = Notifier.prepared("Module: <b>Tail\nscale</b> & co", { body: "Authorization: <i>Send</i> a file & more\n-x", format: "plain", urgency: "low" });
        assertEqual(plain.summary, "Module: <b>Tail scale</b> & co", "plain: the summary on one line, not escaped (no markup there)");
        assertEqual(JSON.stringify(plain.options.body), JSON.stringify("Authorization: &lt;i&gt;Send&lt;/i&gt; a file &amp; more\n-x"), "plain: the body keeps its line break, &, < and > as entities");
        const longBody = Notifier.prepared("Two\r\nlines", { body: Array(30).fill("<x>").join("\r\n"), format: "plain" });
        assert(longBody.summary === "Two lines" && longBody.options.body.split("\n").length === 20 && longBody.options.body.endsWith("&lt;x&gt;…"),
               "plain: the summary one line; the body at most 20 lines, escaped after the cut");
        assertEqual(plain.options.urgency + " " + plain.options.format, "low plain", "plain: the other options kept");
        assertEqual(Notifier.prepared("s", { body: "&lt;", format: "plain" }).options.body, "&amp;lt;", "plain: an entity in the text is shown as written");
        assertEqual(Notifier.prepared("x".repeat(300), { body: "y".repeat(1200), format: "plain" }).summary.length, 200, "plain: the summary cut at 200");
        assertEqual(Notifier.prepared("s", { body: "y".repeat(1200), format: "plain" }).options.body.length, 1000, "plain: the body cut at 1000");
        const ampersands = Notifier.prepared("s", { body: "&".repeat(1200), format: "plain" }).options.body;
        assert(ampersands.startsWith("&amp;&amp;") && ampersands.endsWith("…") && ampersands.length === 999 * 5 + 1,
               "plain: cut before escaping, so an entity is never cut in half");
        assertEqual(JSON.stringify(Notifier.prepared(null, { format: "plain" })), "{\"summary\":\"\",\"options\":{\"format\":\"plain\",\"body\":\"\"}}",
                    "plain: no summary, no body");
        const given = { body: "<b>bold</b>" };
        const markup = Notifier.prepared("s\nt", given);
        assert(markup.summary === "s\nt" && markup.options === given, "without format: untouched, the same objects (the body is markup)");
        assert(Notifier.prepared("s", { body: "<b>", format: "html" }).options.body === "<b>", "another format word: untouched");

        // --- the words notify-send gets ---
        const argv = Notifier.command(plain.summary, plain.options);
        assertEqual(JSON.stringify(argv.slice(-3)), JSON.stringify(["--", plain.summary, plain.options.body]), "command: the plain texts after \"--\"");
        assert(!argv.some(word => word.startsWith("--format")), "command: format is not a notify-send option");
        const dash = Notifier.prepared("-a evil", { body: "--action=x=y", format: "plain" });
        const dashArgv = Notifier.command(dash.summary, dash.options);
        assertEqual(JSON.stringify(dashArgv.slice(-3)), "[\"--\",\"-a evil\",\"--action=x=y\"]", "command: a text starting with \"-\" stays after \"--\"");

        // --- the shell's own toast shows its summary as plain text ---
        const toast = _shellToast.createObject(null);
        const crafted = "<b>Copied</b><img src=\"http://example.invalid/\">";
        toast.currentNotif = { summary: crafted };
        const texts = [];
        const collect = item => {
            for (const child of item.children) {
                if (child instanceof Text)
                    texts.push(child);
                collect(child);
            }
        };
        collect(toast);
        assert(texts.length > 0 && texts.every(text => text.textFormat === Text.PlainText), "shell toast: every text plain (" + texts.length + ")");
        assert(texts.some(text => text.text === crafted), "shell toast: the summary as written");
        toast.destroy();

        // --- a toast cuts a long body; the notification centre's card shows it whole ---
        const longText = Array.from({ length: 20 }, (_, i) => "line " + (i + 1)).join("\n");
        const notification = { id: 7, appName: "Test", appIcon: "", summary: "Long", body: longText, image: "", actions: [], hasInlineReply: false };
        const hudItem = _toast.createObject(null);
        hudItem.currentNotif = notification;
        const toastCard = _find(hudItem, item => item.bodyMaxLines !== undefined);
        assert(toastCard !== null, "the toast has its card");
        assertEqual(toastCard?.bodyMaxLines, 6, "the toast: at most 6 lines of the body");
        const centreCard = _card.createObject(null, { notification: notification });
        assertEqual(centreCard.bodyMaxLines, 0, "the centre's card: the whole body");
        const isBody = item => item instanceof TextEdit && String(item.text).includes("line ");
        // Laid out at a toast's width: without a window the layouts here are not run, so the
        // body's box is given its width (the text wraps and counts its lines at it)
        const toastBody = _layOut(toastCard, isBody);
        const centreBody = _layOut(centreCard, isBody);
        const lineHeight = toastBody.implicitHeight / toastBody.lineCount;
        assert(toastBody.width === 300 && toastBody.lineCount === 20 && lineHeight >= toastBody.font.pixelSize, "the toast's body laid out at 300, one line each ("
               + toastBody.lineCount + " lines of " + lineHeight + ")");
        assert(toastCard.bodyCut && Math.abs(toastCard.bodyShownHeight - 6 * lineHeight) < 0.5,
               "the toast: 20 lines cut to 6 lines' height (" + toastCard.bodyShownHeight + " of " + toastBody.implicitHeight + ")");
        assert(toastBody.parent.clip, "… clipped");
        assert(!centreCard.bodyCut && Math.abs(centreCard.bodyShownHeight - centreBody.implicitHeight) < 0.5 && !centreBody.parent.clip,
               "the centre's card: the whole body, not clipped (" + centreCard.bodyShownHeight + " of " + centreBody.implicitHeight + ")");
        const lines = count => Array.from({ length: count }, (_, i) => "line " + (i + 1)).join("\n");
        hudItem.currentNotif = Object.assign({}, notification, { body: lines(6) });
        assert(toastBody.lineCount === 6 && !toastCard.bodyCut && Math.abs(toastCard.bodyShownHeight - toastBody.implicitHeight) < 0.5,
               "the toast: a body of exactly 6 lines whole, not cut (" + toastCard.bodyShownHeight + " of " + toastBody.implicitHeight + ")");
        hudItem.currentNotif = Object.assign({}, notification, { body: lines(7) });
        assert(toastBody.lineCount === 7 && toastCard.bodyCut && Math.abs(toastCard.bodyShownHeight - 6 * toastBody.implicitHeight / 7) < 0.5,
               "the toast: 7 lines cut to 6 (" + toastCard.bodyShownHeight + " of " + toastBody.implicitHeight + ")");
        hudItem.currentNotif = Object.assign({}, notification, { body: "one line" });
        assert(!toastCard.bodyCut, "the toast: a short body not cut");
        // A word longer than the line breaks onto the next lines rather than running off the side
        const longWord = "line" + "x".repeat(200);
        hudItem.currentNotif = Object.assign({}, notification, { body: longWord });
        assert(toastBody.lineCount > 1 && toastBody.contentWidth <= toastBody.width + 0.5,
               "the toast: a long word wrapped within the width (" + toastBody.lineCount + " lines, " + toastBody.contentWidth + " of " + toastBody.width + ")");
        centreCard.notification = Object.assign({}, notification, { body: longWord });
        assert(centreBody.lineCount > 1 && centreBody.contentWidth <= centreBody.width + 0.5,
               "the centre's card: a long word wrapped within the width (" + centreBody.lineCount + " lines, " + centreBody.contentWidth + " of " + centreBody.width + ")");
        centreCard.destroy();
        hudItem.destroy();

        // --- the sender's progress, under the text (NotificationRules.progress) ---
        const withHints = hints => Object.assign({}, notification, { body: "photo.jpg", hints: hints });
        const progressCard = _card.createObject(null, { notification: withHints({ value: 40 }) });
        const progressBar = _find(progressCard, item => item.objectName === "progress");
        assert(progressBar !== null, "the card has a progress bar");
        assert(progressBar.visible && Math.abs(progressBar.value - 0.4) < 1e-9 && progressBar.tone === "accent",
               "value 40: the bar at 0.4, the accent (" + progressBar.visible + ", " + progressBar.value + ", " + progressBar.tone + ")");
        progressCard.notification = withHints({ value: 40, "x-qs-progress-state": "failed" });
        assert(progressBar.visible && progressBar.value === 1 && progressBar.tone === "error", "failed: full, the error colour");
        // A finished job: its mark beside the summary; on a card counting down (a toast) no
        // bar of its own, the countdown the only bar (NotificationRules.progressView)
        const progressMark = _find(progressCard, item => item.objectName === "progressMark");
        assert(progressMark !== null && progressMark.visible && progressMark.text === "\uf00d", "failed, not counting (the centre): its ✗ beside the summary");
        progressCard.notification = withHints({ value: 40, "x-qs-progress-state": "running" });
        progressCard.timerVisible = true;
        assert(progressBar.visible && !progressMark.visible, "running, counting down: the bar, no mark");
        progressCard.notification = withHints({ value: 40, "x-qs-progress-state": "done" });
        assert(!progressBar.visible && progressMark.visible && progressMark.text === "\uf00c" && Qt.colorEqual(progressMark.color, Theme.success),
               "done, counting down: no progress bar, a ✓ in the success colour (" + progressBar.visible + ", " + progressMark.visible + ")");
        progressCard.notification = withHints({ value: 40, "x-qs-progress-state": "failed" });
        assert(!progressBar.visible && progressMark.visible && progressMark.text === "\uf00d" && Qt.colorEqual(progressMark.color, Theme.error),
               "failed, counting down: no progress bar, a ✗ in the error colour");
        progressCard.timerVisible = false;
        assert(progressBar.visible && progressBar.tone === "error" && progressMark.visible, "failed, not counting (the centre): the toned bar and the ✗");
        progressCard.notification = withHints({});
        assert(!progressBar.visible && !progressMark.visible, "no value: no bar, no mark");
        progressCard.notification = Object.assign({}, notification, { body: "photo.jpg" });
        assert(!progressBar.visible, "no hints at all: no bar");
        progressCard.destroy();

        // --- an action: the entry goes, unless the notification is resident ---
        // The card and its action are given the suite as parent: made without one, the
        // garbage collector may take them apart before their deferred destroy, and the
        // card's buttons then read a theme already gone (TypeErrors in the log)
        const pressAction = resident => {
            const action = _action.createObject(suite, { identifier: "skip", text: "Skip" });
            const card = _card.createObject(suite, { notification: Object.assign({}, notification, { resident: resident, actions: [action] }) });
            const result = { invoked: 0, dismissals: 0, actionsInvoked: 0 };
            card.dismissRequested.connect(() => result.dismissals++);
            card.actionInvoked.connect(() => result.actionsInvoked++);
            const button = _find(card, item => item instanceof MouseArea && item.parent?.modelData === action);
            if (button)
                button.clicked(null);
            result.found = button !== null;
            result.invoked = action.invoked;
            card.destroy();
            action.destroy();
            return result;
        };
        const notResident = pressAction(false);
        assert(notResident.found, "the action's button is on the card");
        assert(notResident.invoked === 1 && notResident.dismissals === 1 && notResident.actionsInvoked === 0,
               "not resident: the action runs and the entry is asked to go (" + JSON.stringify(notResident) + ")");
        const resident = pressAction(true);
        assert(resident.invoked === 1 && resident.dismissals === 0 && resident.actionsInvoked === 1,
               "resident: the action runs, no dismissal asked, the toast told to leave (" + JSON.stringify(resident) + ")");

        _toastTimes();
        _modals();
        _announces();
        _progress();
    }

    // The progress handle: gdbus's argv (show, update, close), test mode's records, and the
    // handle's I/O against a stand-in runner and a stand-in server — one call at a time,
    // coalescing, late and foreign answers, a click and a dismissal by id
    function _progress() {
        // --- the words gdbus gets ---
        const content = Notifier.progressContent("Sending photo.jpg", { body: "to laptop", format: "plain", progress: 0, toast: "whileRunning",
            urgency: "low", appName: "Transfers", expireTime: 3000,
            hints: { "x-qs-announce": "9", "x-qs-progress-run": "forged", "value": 99, "custom": "it's", "count": 3 },
            actions: [{ id: "cancel", label: "Cancel", onTriggered: () => {} }] }, "run1");
        const show = Notifier.progressCommand(content, 0);
        const head = ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path", "/org/freedesktop/Notifications",
                      "--method", "org.freedesktop.Notifications.Notify", "--"];
        assertEqual(JSON.stringify(show.slice(0, 10)), JSON.stringify(head), "show: gdbus calls Notify on the session bus, the arguments after \"--\"");
        assertEqual(show.length, 18, "show: the eight arguments of Notify, one word each");
        assertEqual(JSON.stringify(show.slice(10, 15)), JSON.stringify(["'Transfers'", "uint32 0", "''", "'Sending photo.jpg'", "'to laptop'"]),
                    "show: app name, no id to replace, no icon, the summary and the body as literals");
        assertEqual(show[15], "@as ['cancel', 'Cancel']", "show: the actions, id then label");
        assertEqual(show[16], "@a{sv} {'custom': <'it\\'s'>, 'count': <int32 3>, 'urgency': <byte 0>, 'resident': <true>, 'value': <int32 0>, "
                    + "'x-qs-progress-state': <'running'>, 'x-qs-progress-run': <'run1'>}",
                    "show: the caller's hints without x-qs- keys, then the shell's — resident, the value (the caller's own replaced), state, run; no announce yet");
        assertEqual(show[17], "int32 0", "show, whileRunning: stays (the caller's expireTime is not used)");
        assert(show.slice(10).every(word => !word.startsWith("-")), "show: no argument starts with \"-\"");
        const updated = Notifier.updatedContent(content, { progress: 40.6, summary: "Sending <b>", announce: true });
        const update = Notifier.progressCommand(updated, 7);
        assertEqual(update[11] + " " + update[13], "uint32 7 'Sending <b>'", "update: replaces id 7; the summary made plain again (format plain: no markup there)");
        assert(update[16].includes("'value': <int32 40>") && update[16].includes("'x-qs-announce': <'1'>"), "update: the value a whole percent, the announce count 1");
        assertEqual(update[17], "int32 0", "update, whileRunning, still running: stays");
        const done = Notifier.updatedContent(updated, { state: "done", body: "a & b" });
        const end = Notifier.progressCommand(done, 7);
        assert(end[16].includes("'x-qs-progress-state': <'done'>") && end[17] === "int32 -1" && end[14] === "'a &amp; b'",
               "done, whileRunning: the state done, the user's time (-1), the new body made plain");
        assert(end[13] === "'Sending <b>'" && end[16].includes("'x-qs-announce': <'1'>"), "done: the summary and the announce count kept");
        assertEqual(Notifier.updatedContent(done, { state: "paused", progress: "50" }).state, "done", "update: an unknown state and a progress that is no number ignored");
        const brief = Notifier.progressCommand(Notifier.progressContent("s", { progress: 10 }, "run1"), 0);
        assertEqual(brief[17] + " " + brief[10] + " " + brief[15], "int32 -1 'H2S Shell' @as []", "brief (the default): the user's time; the app name as notify-send's; no actions");
        const crafted = Notifier.progressCommand(Notifier.progressContent("x', 'evil", { progress: -1, body: "\\'\n😀" }, "r"), 0);
        assertEqual(crafted[13] + " " + crafted[14], "'x\\', \\'evil' '\\\\\\'\\u000a\\U0001f600'", "crafted texts stay inside their literals");
        assert(crafted[16].includes("'value': <int32 -1>"), "-1: a run of unknown length");
        const forged = Notifier.progressCommand(Notifier.progressContent("s", { progress: 1,
            hints: { "\ud800x-qs-announce": "9", "\u0000x-qs-progress-state": "done", "\u0000value": 77 } }, "run1", "3"), 0);
        assert(forged[16] === "@a{sv} {'urgency': <byte 1>, 'resident': <true>, 'value': <int32 1>, 'x-qs-progress-state': <'running'>, 'x-qs-progress-run': <'run1'>, "
               + "'x-qs-progress-handle': <'3'>}", "x-qs- keys judged as the server receives them: a NUL or a lone surrogate in front does not pass; "
               + "a caller's value is replaced; the handle's mark sent (" + forged[16] + ")");
        const urgent = Notifier.progressCommand(Notifier.progressContent("s", { progress: 1, hints: { urgency: 2 } }, "run1"), 0);
        assert(urgent[16].includes("'urgency': <byte 1>") && !urgent[16].includes("int32 2"),
               "a caller's urgency hint is replaced by the content's urgency, normal when none (" + urgent[16] + ")");
        assertEqual(JSON.stringify(Notifier.closeCommand(7).slice(8)), JSON.stringify(["org.freedesktop.Notifications.CloseNotification", "--", "uint32 7"]),
                    "close: CloseNotification with the id after \"--\"");
        assertEqual(JSON.stringify(Notifier.command("Hi")), "[\"notify-send\",\"--app-name=H2S Shell\",\"--\",\"Hi\"]", "plain send: notify-send's argv as before");

        // --- test mode: show, update, close recorded; nothing runs ---
        const savedRecordOnly = Notifier.recordOnly;
        Notifier.recordOnly = true;
        Notifier.clearRecorded();
        const recorded = Notifier.send("Copying", { progress: 0, toast: "whileRunning", actions: [{ id: "stop", label: "Stop" }] });
        assert(recorded !== null && recorded !== undefined && recorded.open && recorded.state === "running" && recorded.id > 0,
               "test mode: send with progress returns an open handle, as if the server answered");
        assert(recorded.update({ progress: 50 }) && recorded.update({ state: "done", announce: true }), "test mode: updates taken");
        assert(!recorded.update({ progress: 60 }), "after an end state, no update is taken");
        recorded.close();
        assert(!recorded.open && recorded.state === "closed", "closed");
        const kinds = Notifier.recorded.map(entry => [entry.kind, entry.handle, entry.progress, entry.state, entry.expireTime, entry.announce].join(" "));
        const number = recorded.number;
        assertEqual(JSON.stringify(kinds), JSON.stringify(["show " + number + " 0 running 0 0", "update " + number + " 50 running 0 0",
                                                           "update " + number + " 50 done -1 1", "close " + number + " 50 done -1 1"]),
                    "test mode: one record per show, update and close, with the handle's number");
        assertEqual(Notifier.recorded[0].actions.join(","), "Stop", "test mode: the actions' labels recorded");
        assertEqual(Notifier.send("Plain", {}), undefined, "test mode: a plain send still returns nothing");
        assert(!Notifier._liveHandles.includes(recorded), "an ended handle is no longer kept by Notifier");
        const kept = Notifier.send("Kept", { progress: 0 });
        assert(Notifier._liveHandles.includes(kept), "an open one is");
        kept.close();
        assert(!Notifier._liveHandles.includes(kept), "… until it ends");
        // Handles kept for an owner (a module's handle), out of its reach
        const owner = {};
        const other = {};
        const ownedFirst = Notifier.send("First", { progress: 0 });
        const second = Notifier.send("Second", { progress: 0 });
        const third = Notifier.send("Third", { progress: 0 });
        Notifier.own(owner, ownedFirst);
        Notifier.own(owner, second);
        Notifier.own(owner, second);
        Notifier.own(other, third);
        assertEqual(Notifier.ownedCount(owner) + " " + Notifier.ownedCount(other), "2 1", "own(): kept per owner, once each");
        second.close();
        assertEqual(Notifier.ownedCount(owner), 1, "… one that ends by itself is let go");
        Notifier.closeOwned(owner);
        assert(!ownedFirst.open && ownedFirst.state === "closed" && third.open, "closeOwned(): the owner's closed, another owner's left");
        assertEqual(Notifier.ownedCount(owner), 0, "… and let go");
        Notifier.forgetOwned(other);
        assert(third.open && Notifier.ownedCount(other) === 0, "forgetOwned(): let go, left open");
        third.close();
        Notifier.own(owner, third);
        assertEqual(Notifier.ownedCount(owner), 0, "own(): an ended handle is not kept");
        Notifier.clearRecorded();
        Notifier.recordOnly = savedRecordOnly;

        // --- the handle against stand-ins ---
        const runner = _standInRunner.createObject(suite);
        const server = _standInServer.createObject(suite);
        const events = [];
        const handleOf = options => _handle.createObject(suite, {
            number: 1, runner: runner, server: server,
            wanted: Notifier.progressContent("Sending", Object.assign({ progress: 0 }, options), "run1"),
            callbacks: { actions: [{ id: "cancel", onTriggered: () => events.push("cancel") }], onDismissed: () => events.push("dismissed") }
        });
        const answer = (index, id) => runner.answer(index, id);
        const handle = handleOf({});
        assertEqual(runner.calls.length + " " + handle.state, "1 starting", "the show starts at once; starting until it answers");
        assert(handle.update({ progress: 30 }) && handle.update({ summary: "Sending 2" }), "updates before the id: taken");
        assertEqual(runner.calls.length, 1, "… but nothing sent before the id is known");
        server.tracked = [41];
        answer(0, 41);
        assertEqual(handle.id + " " + handle.state, "41 running", "the answer: the id known, running");
        assertEqual(runner.calls.length, 2, "the newest content goes as one update after the show's answer");
        assert(runner.calls[1].argv[11] === "uint32 41" && runner.calls[1].argv[13] === "'Sending 2'" && runner.calls[1].argv[16].includes("<int32 30>"),
               "… replacing id 41, with everything wanted meanwhile");
        for (let i = 1; i <= 10; i++)
            handle.update({ progress: 30 + i * 5 });
        assertEqual(runner.calls.length, 2, "ten progress updates while a call runs: none started");
        answer(1, 41);
        assertEqual(runner.calls.length + " " + handle._later.running, "2 true", "answered within the minimum time: the progress waits (coalesced)");
        handle._later.stop();
        handle._lastSentAt = 0;
        handle._pump();
        assertEqual(runner.calls.length, 3, "after the minimum time: one update");
        assert(runner.calls[2].argv[16].includes("<int32 80>"), "… with the last value, 80");
        answer(2, 41);
        server.actionInvoked(41, "cancel");
        server.actionInvoked(99, "cancel");
        server.actionInvoked(41, "other");
        assertEqual(events.join(","), "cancel", "a click on its card: its callback once; another id or an unknown action: nothing");
        assert(handle.open, "after a click: still open (resident)");
        server.notificationClosed(41, NotificationCloseReason.Dismissed);
        assertEqual(events.join(",") + " " + handle.state, "cancel,dismissed closed", "dismissed by the user: onDismissed once, closed");
        assert(!handle.update({ progress: 90 }), "after a dismissal: no update taken");
        server.notificationClosed(41, NotificationCloseReason.Dismissed);
        assertEqual(events.length + " " + runner.calls.length, "2 3", "a second closed signal: nothing; nothing sent");
        handle.destroy();

        // An update in flight when the user dismisses: its answer made a new notification, closed at once
        events.length = 0;
        const raced = handleOf({});
        const first = runner.calls.length;
        server.tracked = [50];
        answer(first - 1, 50);
        raced.update({ summary: "B" });
        server.notificationClosed(50, NotificationCloseReason.Dismissed);
        answer(first, 51);
        assertEqual(events.join(",") + " " + raced.state, "dismissed closed", "dismissed while an update runs: onDismissed, closed");
        assertEqual(JSON.stringify(runner.calls[first + 1]?.argv.slice(-1)), JSON.stringify(["uint32 51"]), "… and what the late answer made is closed (late answers lose)");
        raced.destroy();

        // A foreign id: the old one was closed elsewhere; the new one is closed, no callback
        events.length = 0;
        const foreign = handleOf({});
        let base = runner.calls.length;
        server.tracked = [60];
        answer(base - 1, 60);
        foreign.update({ summary: "B" });
        answer(base, 61);
        assertEqual(foreign.state + " " + events.length + " " + runner.calls[base + 1]?.argv.slice(-1)[0], "closed 0 uint32 61",
                    "a foreign id: closed at once, the handle closed, no callback");
        foreign.destroy();

        // close(): before the id, it goes when the id comes; no onDismissed
        events.length = 0;
        const closing = handleOf({});
        base = runner.calls.length;
        closing.close();
        assertEqual(closing.state + " " + runner.calls.length, "closed " + base, "close() before the id: closed, the close waits for the id");
        server.tracked = [70];
        answer(base - 1, 70);
        assertEqual(runner.calls[base]?.argv.slice(-3).join(" "), "org.freedesktop.Notifications.CloseNotification -- uint32 70", "… sent when the id comes");
        server.notificationClosed(70, NotificationCloseReason.CloseRequested);
        assertEqual(events.length + " " + closing.calls, "0 2", "close(): no onDismissed; a show and a close, nothing more");
        closing.destroy();

        // The shell's own server does not hold the id (another daemon owns the name): unknown
        const elsewhere = handleOf({});
        base = runner.calls.length;
        server.tracked = [];
        answer(base - 1, 80);
        assertEqual(elsewhere.state + " " + elsewhere.open, "unknown false", "an id the shell's server does not hold: unknown, not open");
        assertEqual(runner.calls[base]?.argv.slice(-1)[0] + " " + runner.calls[base]?.argv[8], "uint32 80 org.freedesktop.Notifications.CloseNotification",
                    "… and what it made there is closed (nothing left running)");
        server.actionInvoked(80, "cancel");
        server.notificationClosed(80, NotificationCloseReason.Dismissed);
        assertEqual(events.length + " " + elsewhere.update({ progress: 5 }), "0 false", "unknown: no callbacks, no updates");
        elsewhere.destroy();

        // Dismissed before the show's answer came: still a dismissal
        const quick = handleOf({});
        base = runner.calls.length;
        server.notificationClosed(90, NotificationCloseReason.Dismissed);
        server.tracked = [];
        answer(base - 1, 90);
        assertEqual(quick.state + " " + events.join(","), "closed dismissed", "dismissed before the id came: closed, onDismissed");
        quick.destroy();
        events.length = 0;

        // A failed show: unknown, no callbacks; what the server made under its mark is closed
        const failed = handleOf({});
        base = runner.calls.length;
        server.marked = [95];
        runner.fail(base - 1);
        server.marked = [];
        assertEqual(failed.state, "unknown", "the show failed: unknown");
        assertEqual(runner.calls[base]?.argv.slice(-1)[0], "uint32 95", "… and a notification the server made under its mark before the call failed is closed");
        failed.destroy();

        // A failed update: tried again after a pause with the newest content; done is never lost
        const retried = handleOf({ toast: "whileRunning" });
        base = runner.calls.length;
        server.tracked = [100];
        answer(base - 1, 100);
        retried.update({ state: "done" });
        runner.fail(base);
        assertEqual(runner.calls.length + " " + retried._later.running + " " + retried.state, (base + 1) + " true done",
                    "the done update failed: nothing sent at once, a retry waits");
        retried._retryAt = 0;
        retried._pump();
        assertEqual(runner.calls.length, base + 2, "the retry goes");
        assert(runner.calls[base + 1].argv[16].includes("'x-qs-progress-state': <'done'>") && runner.calls[base + 1].argv[17] === "int32 -1",
               "… with done and the user's time (the toast does not stay for ever)");
        answer(base + 1, 100);
        assertEqual(retried._failures + " " + retried._later.running, "0 false", "answered: no more retries");
        retried.destroy();
        const givingUp = handleOf({});
        base = runner.calls.length;
        server.tracked = [110];
        answer(base - 1, 110);
        givingUp.update({ summary: "B" });
        for (let i = 0; i <= NotificationRules.maxRetries; i++) {
            runner.fail(runner.calls.length - 1);
            if (givingUp.state === "unknown")
                break;
            givingUp._retryAt = 0;
            givingUp._pump();
        }
        assertEqual(givingUp.state + " " + runner.calls.length + " " + runner.calls[runner.calls.length - 1].argv.slice(-1)[0],
                    "unknown " + (base + 2 + NotificationRules.maxRetries) + " uint32 110",
                    "every retry failed: given up after the last, unknown, and its notification closed");
        givingUp.destroy();

        // A click before the show's id came: delivered once the id is known
        events.length = 0;
        const early = handleOf({});
        base = runner.calls.length;
        server.actionInvoked(120, "cancel");
        server.actionInvoked(121, "cancel");
        server.tracked = [120];
        answer(base - 1, 120);
        assertEqual(events.join(","), "cancel", "an early click on its own card: its callback, once; one on another: nothing");

        // Ended: it lets go of the server's signals and says so
        let finishedCount = 0;
        early.finished.connect(() => finishedCount++);
        early.close();
        server.notificationClosed(120, NotificationCloseReason.CloseRequested);
        server.actionInvoked(120, "cancel");
        assertEqual(finishedCount + " " + early._connected + " " + events.length, "1 false 1", "closed: finished once, disconnected, no more callbacks");
        early.destroy();
        runner.destroy();
        server.destroy();
    }

    // Runs nothing: keeps each start's argv and done, for the test to answer
    property Component _standInRunner: Component {
        QtObject {
            property var calls: []
            function start(argv, options) {
                calls = calls.concat([{ argv: argv, done: options?.done ?? null }]);
                return { running: true, cancel: () => {} };
            }
            function answer(index, id) {
                calls[index].done?.({ ok: true, code: 0, stdout: "(uint32 " + id + ",)", stderr: "", error: "" });
            }
            function fail(index) {
                calls[index].done?.({ ok: false, code: 1, stdout: "", stderr: "Error: no server", error: "" });
            }
        }
    }
    // Notifications as a handle reads it
    property Component _standInServer: Component {
        QtObject {
            property var tracked: []
            property var marked: []
            signal notificationClosed(int id, int reason)
            signal actionInvoked(int id, string actionId)
            function tracks(id) {
                return tracked.includes(id);
            }
            function progressIds(run, handle) {
                return marked;
            }
        }
    }
    property Component _handle: Component {
        NotificationHandle {}
    }

    // Toasts through the three queues (Notifications.toastState, ToastRules), shown by a
    // ToastStack as Hud makes it, on a stand-in toasts' screen, with stand-in notifications:
    // which queue each goes to, the stacks' order, the limits and badges, how long each
    // shows (ToastRules.timing) and which one counts down
    function _toastTimes() {
        const savedGlobals = Config.globals;
        Notifications.screensOverride = [{ name: "queue-screen", focused: true, fullscreen: false, workspace: 1 }];
        const made = [];
        let nextId = 9001;
        const standIn = (expire, change) => {
            const standing = _standIn.createObject(suite, Object.assign({ id: nextId++, expireTimeout: expire, summary: "Toast" }, change ?? {}));
            made.push(standing);
            return standing;
        };
        const critical = { urgency: NotificationUrgency.Critical };
        const stack = _stack.createObject(suite, { screenModelData: { name: "queue-screen" } });
        made.push(stack);
        // Queued: the stack on the toasts' screen shows it at once while its queue has room
        const show = notification => {
            Notifications.enqueueHudNotification(notification);
            return stack.toastFor(notification.id);
        };
        const place = notification => {
            const at = Notifications.toastPlace(notification.id);
            return at.place + (at.queue ? " " + at.queue : "");
        };
        const countdownOf = toast => toast.resources.find(resource => resource.property === "remaining") ?? null;
        const cardOf = toast => _find(toast, item => item.bodyMaxLines !== undefined);
        const closeButtonOf = toast => _find(toast, item => item instanceof MouseArea && item.parent?.text === "×");
        const counting = toast => toast !== null && toast._counting && countdownOf(toast).running;
        const badge = queue => _find(stack, item => item.objectName === queue + "Badge");
        const settings = change => {
            Config.globals = JSON.stringify(Object.assign(JSON.parse(savedGlobals || "{}"), change));
        };
        // Every toast that is leaving slides out to the end
        const settle = () => {
            for (let i = 0; i < 40; i++) {
                const leaving = _findAll(stack, item => item.toastId !== undefined && item.toastId >= 0 && !item.present && item.visible);
                if (leaving.length === 0)
                    return;
                for (const toast of leaving)
                    toast.resources.find(resource => resource.property === "x" && resource.to === toast.screenWidth)?.complete();
            }
        };
        const clear = () => {
            Notifications.clearHudQueue();
            settle();
        };
        const shownCount = queue => Notifications.toastState.shown[queue].length;
        const presentToasts = () => _findAll(stack, item => item.toastId !== undefined && item.toastId >= 0 && item.present).length;

        // --- one of each queue: three stacks, critical on top, then staying, then ordinary ---
        settings({});
        const stays = standIn(0);
        const ordinary = standIn(-1);
        const urgent = standIn(-1, critical);
        const staysToast = show(stays);
        const ordinaryToast = show(ordinary);
        const urgentToast = show(urgent);
        assert(place(stays) === "shown staying" && place(ordinary) === "shown ordinary" && place(urgent) === "shown critical",
               "expire 0 → staying, -1 → ordinary, urgency critical → critical: all shown (" + [place(stays), place(ordinary), place(urgent)] + ")");
        assertEqual(JSON.stringify(stack.stack.map(entry => entry.id)), JSON.stringify([urgent.id, stays.id, ordinary.id]),
                    "the stacks top to bottom: critical, staying, ordinary");
        const spacing = Theme.osdToast.spacing;
        const placeOf = notification => stack.layout.places[notification.id];
        assert(placeOf(urgent) === 0 && placeOf(stays) === urgentToast.height + 2 * spacing
               && placeOf(ordinary) === placeOf(stays) + staysToast.height + 2 * spacing && ordinaryToast.y === placeOf(ordinary),
               "a wider gap between two queues (" + [placeOf(urgent), placeOf(stays), placeOf(ordinary)] + ")");
        assert(staysToast !== null && !counting(staysToast) && !cardOf(staysToast).timerVisible && Notifications.toastDurations[stays.id] === 0,
               "expire 0: no countdown, no timer bar, its time 0");
        assert(counting(ordinaryToast) && countdownOf(ordinaryToast).duration === 5000 && cardOf(ordinaryToast).timerVisible,
               "the ordinary one counts the user's 5 s");
        assert(!counting(urgentToast) && !cardOf(urgentToast).timerVisible && cardOf(urgentToast)._critical, "the critical one stays, outlined");
        assert(!badge("critical").look.shown && !badge("staying").look.shown && !badge("ordinary").look.shown && stack.restX === 800 - Theme.osdToast.width - Theme.osdToast.screenGap,
               "nothing waits: no badge, the toasts at the edge");
        closeButtonOf(staysToast).clicked(null);
        assert(place(stays) === "none" && !staysToast.present && stays.dismissCalls === 1 && !stays.tracked,
               "its \"×\": the notification dismissed — the toast goes, the entry too");
        assert(Notifications._toastWatched[stays.id] === undefined && Notifications._toastWatched[ordinary.id] === ordinary,
               "a notification gone: no longer followed; one still there is");
        clear();
        assert(presentToasts() === 0 && stack.stack.length === 0 && Notifications.hudQueue.length === 0
               && stack._leaving.length === 0, "cleared: nothing shown, waiting or sliding out");

        // --- each queue its own limit; what waits is counted on its badge, beside its lowest toast ---
        const criticals = [standIn(-1, critical), standIn(-1, critical)];
        const stayings = [standIn(0), standIn(0), standIn(0)];
        const ordinaries = [standIn(-1), standIn(-1)];
        criticals.concat(stayings, ordinaries).forEach(show);
        assert(shownCount("critical") === 1 && shownCount("staying") === 1 && shownCount("ordinary") === 1
               && place(criticals[1]) === "waiting critical" && place(stayings[2]) === "waiting staying" && place(ordinaries[1]) === "waiting ordinary",
               "the defaults: 1 critical, 1 staying, 1 ordinary shown; the others wait in their queues");
        assertEqual(JSON.stringify(Notifications.toastBadges), JSON.stringify({ critical: 1, staying: 2, ordinary: 1 }), "the badges count what waits");
        const criticalBadge = badge("critical");
        const stayingBadge = badge("staying");
        assert(criticalBadge.look.shown && criticalBadge.look.label === "+1" && criticalBadge.border.color === Theme.error
               && criticalBadge.border.width >= Theme.border.selectedWidth,
               "the critical badge: \"+1\", the critical outline");
        assert(stayingBadge.look.label === "+2" && stayingBadge.border.color === Theme.osdToastBorder && stayingBadge.border.width === Theme.osdToast.borderWidth,
               "the staying badge: \"+2\", the toasts' own outline");
        assert(criticalBadge.y === placeOf(criticals[0]) && stayingBadge.y === placeOf(stayings[0]) && badge("ordinary").y === placeOf(ordinaries[0]),
               "each badge beside its queue's lowest toast");
        assertEqual(stack.restX, 800 - Theme.osdToast.width - Theme.osdToast.badgeWidth - 8, "a badge showing: the toasts rest beside the badges");
        assertEqual(Notifications.hudQueue.map(notification => notification.id).join(","), [criticals[1].id, stayings[1].id, stayings[2].id, ordinaries[1].id].join(","),
                    "hudQueue: every queue's waiting, oldest first");
        settings({ "notifications.criticalToastLimit": 2, "notifications.stayingToastLimit": 3 });
        assert(shownCount("critical") === 2 && shownCount("staying") === 3 && shownCount("ordinary") === 1 && !criticalBadge.look.shown && !stayingBadge.look.shown,
               "the limits raised (2 critical, 3 staying): the waiting ones show, their badges go");
        assertEqual(presentToasts(), 6, "a toast on screen for each shown");
        clear();

        // --- a queue that waits with nothing of it shown here: its badge below the stack ---
        settings({});
        const elsewhere = standIn(0);
        Notifications.screensOverride = [{ name: "other-screen", focused: true, fullscreen: false, workspace: 1 }];
        Notifications.enqueueHudNotification(elsewhere);
        const otherStack = _stack.createObject(suite, { screenModelData: { name: "other-screen" } });
        made.push(otherStack);
        const waitingHere = show(standIn(0));
        assert(place(elsewhere) === "shown staying" && Notifications.toastScreens[elsewhere.id] === "other-screen" && stack.stack.length === 0,
               "shown on the toasts' screen of then; not in another screen's stack");
        Notifications.screensOverride = [{ name: "queue-screen", focused: true, fullscreen: false, workspace: 1 }];
        assert(otherStack.stack.length === 1 && _find(stack, item => item.objectName === "stayingBadge").look.shown && stack.layout.badges.staying?.y === 0,
               "the toasts' screen moved: the other one keeps its toast, the badge here stands alone");
        clear();
        Notifications.screensOverride = [{ name: "queue-screen", focused: true, fullscreen: false, workspace: 1 }];

        // --- resident ones stay (staying); with "Resident notification hide" they count down ---
        const resident = standIn(-1, { resident: true });
        const residentToast = show(resident);
        assert(place(resident) === "shown staying" && !counting(residentToast), "resident, expire -1: staying, no countdown");
        settings({ "notifications.residentHide": true });
        assert(place(resident) === "shown staying" && counting(residentToast) && countdownOf(residentToast).duration === 5000,
               "hide turned on while shown: it counts the user's time where it is");
        const residentLater = standIn(-1, { resident: true });
        show(residentLater);
        assert(place(residentLater) === "shown ordinary", "a resident one with hide on: the ordinary queue");
        clear();
        settings({});
        const job = standIn(-1, { resident: true, hints: { "x-qs-progress-run": Notifier.progressRun } });
        show(job);
        assert(place(job) === "shown ordinary", "the shell's own job (resident), brief: ordinary, not staying");
        clear();

        // --- a job ending while it waits in staying shows its result in ordinary ---
        const holding = standIn(0);
        const runningJob = standIn(0, { resident: true, hints: { "x-qs-progress-run": Notifier.progressRun } });
        show(holding);
        show(runningJob);
        assert(place(holding) === "shown staying" && place(runningJob) === "waiting staying", "a job set to stay waits behind the staying one");
        runningJob.expireTimeout = -1;
        const endedToast = stack.toastFor(runningJob.id);
        assert(place(runningJob) === "shown ordinary" && counting(endedToast) && Notifications.toastBadges.staying === 0,
               "it ends while waiting: into the ordinary queue, shown there, counting");
        holding.expireTimeout = -1;
        assert(place(holding) === "shown staying" && counting(stack.toastFor(holding.id)), "one ending while shown in staying: counts where it is");
        clear();

        // --- a column: the sender's time counts by itself, the user's time one at a time ---
        settings({ "notifications.toastLayout": "column", "notifications.toastColumnSize": 3 });
        const oldest = show(standIn(-1));
        const waiting = show(standIn(-1));
        const ownTime = show(standIn(3000));
        assert(counting(oldest) && !counting(waiting) && waiting.remaining === 1, "the user's time: the oldest counts, the next waits its turn");
        assert(counting(ownTime) && countdownOf(ownTime).duration === 3000 && Notifications.toastDurations[ownTime.toastId] === 3000,
               "3000 ms: counts 3 s at once, by itself");
        countdownOf(oldest).complete();
        assert(!oldest.present && counting(waiting), "the oldest's time running out: the next counts at once");
        waiting.currentNotif.expireTimeout = 0;
        assert(!counting(waiting) && waiting.present && waiting.remaining === 1 && !cardOf(waiting).timerVisible
               && Notifications.toastPlace(waiting.toastId).queue === "staying",
               "replaced with 0 while counting: it goes up to the staying queue, stops, no timer bar");
        clear();

        settings({});
        const replaced = show(standIn(0));
        replaced.currentNotif.expireTimeout = -1;
        assert(counting(replaced) && countdownOf(replaced).duration === 5000 && cardOf(replaced).timerVisible,
               "replaced 0 → -1 while shown: counts the user's time where it is, its bar shows");
        replaced.currentNotif.expireTimeout = 4000;
        assert(counting(replaced) && countdownOf(replaced).duration === 4000 && Notifications.toastDurations[replaced.toastId] === 4000,
               "replaced with 4000: counts 4 s from full");
        clear();

        // --- "Apps choose how long" off: an app's stay counts the user's time too ---
        settings({ "notifications.followSenderTime": false, "notifications.toastLayout": "column" });
        const zero = show(standIn(0));
        const thirty = show(standIn(30000));
        assert(counting(zero) && countdownOf(zero).duration === 5000 && cardOf(zero).timerVisible && !counting(thirty)
               && Notifications.toastPlace(zero.toastId).queue === "ordinary",
               "setting off: expire 0 counts the user's time in the ordinary queue; 30 s waits its turn like any other");
        clear();

        // --- nothing strands the countdown: a toast leaving, closed, or changing queue hands it on ---
        settings({ "notifications.toastLayout": "column", "notifications.toastColumnSize": 3 });
        const counter = show(standIn(-1));
        const closedOne = show(standIn(-1));
        const behind = show(standIn(-1));
        const closedId = closedOne.toastId;
        closedOne.currentNotif.closed(1);
        assert(Notifications.toastPlace(closedId).place === "none" && !closedOne.present, "closed by its sender: out of its queue, the toast leaves");
        counter.dismiss();
        assert(counting(behind), "the counting one leaving: the one behind the closed one counts");
        behind.currentNotif.expireTimeout = 0;
        const last = show(standIn(-1));
        assert(counting(last) && Notifications.countingToasts.length === 1, "the counting one changing queue: the next ordinary one counts");
        clear();

        // --- a backlog arriving at once: never past any queue's limit, a toast for each shown ---
        const drain = (change, list, message) => {
            settings(change);
            const limits = Notifications.toastLimits;
            let past = "";
            for (const notification of list) {
                show(notification);
                for (const queue of ToastRules.queues) {
                    if (shownCount(queue) > limits[queue])
                        past = queue;
                }
            }
            const shown = shownCount("critical") + shownCount("staying") + shownCount("ordinary");
            const waitingTotal = Notifications.hudQueue.length;
            assert(past === "" && presentToasts() === shown && shown + waitingTotal === list.length
                   && ToastRules.queues.every(queue => shownCount(queue) === Math.min(limits[queue], list.filter(n => Notifications.toastQueue(n) === queue).length)),
                   message + " (" + ToastRules.queues.map(queue => queue + " " + shownCount(queue)).join(", ") + ", " + waitingTotal + " waiting)");
            // Drained: each shown one ends, the next takes its place, never past the limit
            for (let round = 0; round < list.length && past === ""; round++) {
                const shownIds = _allShown();
                if (shownIds.length === 0)
                    break;
                Notifications.toastGone(shownIds[0]);
                for (const queue of ToastRules.queues) {
                    if (shownCount(queue) > limits[queue])
                        past = queue;
                }
            }
            assert(past === "" && Notifications.hudQueue.length === 0, message + ": drained one by one, never past a limit");
            clear();
        };
        drain({}, [standIn(-1), standIn(-1), standIn(-1)], "one at a time: three at once, one shows");
        drain({ "notifications.toastLayout": "column", "notifications.toastColumnSize": 3 }, Array.from({ length: 5 }, () => standIn(-1)),
              "a column of 3: five at once, three show");
        drain({}, [standIn(0), standIn(0), standIn(-1, critical), standIn(-1), standIn(-1, critical), standIn(0), standIn(-1)],
              "all three queues at once: one of each shows");
        drain({ "notifications.followSenderTime": false }, [standIn(0), standIn(3000), standIn(-1)], "\"Apps choose how long\" off: one at a time, one shows");

        // --- one dismissed while it waits: never shown, the next shows after the first leaves ---
        settings({});
        const queued = [standIn(-1), standIn(-1), standIn(-1)];
        queued.forEach(show);
        queued[1].dismiss();
        stack.toastFor(queued[0].id).dismiss();
        assert(place(queued[1]) === "none" && place(queued[2]) === "shown ordinary" && Notifications.hudQueue.length === 0,
               "the 2nd dismissed while it waits: the 3rd shows after the 1st, nothing left waiting");
        clear();

        // --- "×" on a job's toast: dismissed, its handle told as from the centre; the job goes on ---
        const runner = _standInRunner.createObject(suite);
        const server = _standInServer.createObject(suite);
        made.push(runner, server);
        const events = [];
        const runningOn = standIn(0, { resident: true, hints: { "x-qs-progress-run": Notifier.progressRun } });
        // As Notifications.onNotification says a tracked notification's closing, by id
        runningOn.closed.connect(reason => server.notificationClosed(runningOn.id, reason));
        const handle = _handle.createObject(suite, {
            number: 1, runner: runner, server: server,
            wanted: Notifier.progressContent("Sending", { progress: 0 }, "run1"),
            callbacks: { actions: [], onDismissed: () => events.push("dismissed") }
        });
        made.push(handle);
        server.tracked = [runningOn.id];
        runner.answer(0, runningOn.id);
        const jobToast = show(runningOn);
        assert(handle.state === "running" && place(runningOn) === "shown staying", "the job runs, its toast stays");
        closeButtonOf(jobToast).clicked(null);
        assert(events.join(",") === "dismissed" && handle.state === "closed" && place(runningOn) === "none" && !runningOn.tracked,
               "its \"×\": the notification dismissed, the handle's onDismissed once (" + events.join(",") + ", " + handle.state + ")");
        clear();

        // --- an action: a resident toast stays on screen, any other leaves as before ---
        const pressOn = (notification, toast) => {
            const action = _action.createObject(suite, { identifier: "next", text: "Next" });
            made.push(action);
            notification.actions = [action];
            const button = _find(toast, item => item instanceof MouseArea && item.parent?.modelData === action);
            button?.clicked(null);
            return button !== null && action.invoked === 1;
        };
        const player = standIn(-1, { resident: true });
        const playerToast = show(player);
        assert(pressOn(player, playerToast) && place(player) === "shown staying" && playerToast.present && player.tracked && player.dismissCalls === 0,
               "resident: the action runs, its toast stays on screen, the entry stays");
        const mail = standIn(-1);
        const mailToast = show(mail);
        assert(pressOn(mail, mailToast) && place(mail) === "none" && !mailToast.present && mail.dismissCalls === 0,
               "not resident: the action runs, the toast leaves, as before (the server ends the entry)");
        clear();

        // --- the centre opened: only the ordinary toasts go; critical and staying stay, and new ones show ---
        settings({});
        const openCritical = [standIn(-1, critical), standIn(-1, critical)];
        const openStaying = standIn(0);
        const openOrdinary = [standIn(-1), standIn(-1)];
        openCritical.concat([openStaying], openOrdinary).forEach(show);
        Notifications.setHudPanelOpen(true);
        assert(place(openCritical[0]) === "shown critical" && place(openCritical[1]) === "waiting critical" && place(openStaying) === "shown staying"
               && place(openOrdinary[0]) === "none" && place(openOrdinary[1]) === "none" && !stack.toastFor(openOrdinary[0].id).present,
               "centre open: critical and staying stay (and wait), the ordinary ones go, shown and waiting");
        const lateCritical = standIn(0, critical);
        const lateOrdinary = standIn(-1);
        show(lateOrdinary);
        assert(place(lateOrdinary) === "none", "centre open: a new ordinary one is not queued (seen in the centre)");
        Notifications.toastGone(openCritical[0].id);
        assert(place(openCritical[1]) === "shown critical", "centre open: the next critical one shows in its turn");
        const newStaying = standIn(0);
        show(newStaying);
        Notifications.toastGone(openStaying.id);
        assert(place(newStaying) === "shown staying" && stack.toastFor(newStaying.id)?.present, "centre open: a new staying one shows");
        show(lateCritical);
        assert(place(lateCritical) === "waiting critical" && Notifications.toastBadges.critical === 1, "centre open: a new critical one queues, counted");
        Notifications.toastGone(openCritical[1].id);
        const newCritical = standIn(-1, critical);
        show(newCritical);
        assert(place(lateCritical) === "shown critical" && place(newCritical) === "waiting critical", "centre open: … and shows in its turn");
        Notifications.toastGone(lateCritical.id);
        assert(place(newCritical) === "shown critical" && stack.toastFor(newCritical.id)?.present, "centre open: a critical one arriving shows");
        const endsWaiting = standIn(0, { resident: true, hints: { "x-qs-progress-run": Notifier.progressRun } });
        show(endsWaiting);
        endsWaiting.expireTimeout = -1;
        assert(place(endsWaiting) === "none" && Notifications.toastKinds[endsWaiting.id] === undefined
               && Notifications.toastDurations[endsWaiting.id] === undefined && Notifications.toastObject(endsWaiting.id) === null,
               "centre open: a job ending while it waits in staying is no ordinary toast now: dropped, its maps pruned");
        Notifications.setHudPanelOpen(false);
        clear();

        // --- "Show toasts" off: what waits goes, in every queue ---
        [standIn(-1, critical), standIn(-1, critical), standIn(0), standIn(0), standIn(-1), standIn(-1)].forEach(show);
        assertEqual(JSON.stringify(Notifications.toastBadges), JSON.stringify({ critical: 1, staying: 1, ordinary: 1 }), "one waits in each queue");
        settings({ "notifications.toasts": false });
        assert(Notifications.hudQueue.length === 0 && JSON.stringify(Notifications.toastBadges) === JSON.stringify({ critical: 0, staying: 0, ordinary: 0 })
               && Object.keys(Notifications.toastKinds).length === 3,
               "toasts off: nothing waits in any queue, the maps keep only the shown ones");
        const whileOff = standIn(-1, critical);
        show(whileOff);
        assert(place(whileOff) === "none", "toasts off: a new one is not queued");
        settings({});
        clear();

        // --- a fullscreen window there, "Don't show": only the critical toasts stay ---
        settings({ "notifications.toastFullscreen": "hide" });
        const fullCritical = [standIn(-1, critical), standIn(-1, critical)];
        const fullStaying = standIn(0);
        const fullOrdinary = [standIn(-1), standIn(-1)];
        fullCritical.concat([fullStaying], fullOrdinary).forEach(show);
        Notifications.screensOverride = [{ name: "queue-screen", focused: true, fullscreen: true, workspace: 1 }];
        assert(Notifications.toastScreen === "" && Notifications.criticalToastScreen === "queue-screen"
               && place(fullCritical[0]) === "shown critical" && place(fullCritical[1]) === "waiting critical"
               && place(fullStaying) === "none" && place(fullOrdinary[0]) === "none" && place(fullOrdinary[1]) === "none"
               && stack.toastFor(fullCritical[0].id)?.present && !stack.toastFor(fullStaying.id).present,
               "fullscreen: the critical toasts stay (and wait); staying and ordinary go, shown and waiting");
        const fullNew = [standIn(0), standIn(-1), standIn(-1, critical)];
        fullNew.forEach(show);
        Notifications.toastGone(fullCritical[0].id);
        assert(place(fullNew[0]) === "none" && place(fullNew[1]) === "none" && place(fullCritical[1]) === "shown critical"
               && place(fullNew[2]) === "waiting critical",
               "fullscreen: a new staying or ordinary one is not queued; critical ones still show in turn");
        // A staying toast still in the state while hidden (as a modal will be): not in the stack
        Notifications.toastState = { waiting: { critical: [], staying: [], ordinary: [] },
                                     shown: { critical: Notifications.toastState.shown.critical, staying: [fullStaying.id], ordinary: [] },
                                     moved: [] };
        assertEqual(JSON.stringify(stack.stack.map(entry => entry.queue)), JSON.stringify(["critical"]),
                    "fullscreen: the stack shows the critical toasts only");
        Notifications.toastGone(fullStaying.id);
        // "Another screen" with none free: no screen for critical toasts either — they go too
        show(fullNew[2]);
        settings({ "notifications.toastFullscreen": "elsewhere" });
        assert(Notifications.criticalToastScreen === "" && place(fullCritical[1]) === "none" && place(fullNew[2]) === "none"
               && Notifications.hudQueue.length === 0 && !stack.toastFor(fullCritical[1].id).present,
               "fullscreen, then \"Another screen\" with none free: the critical toasts go, shown and waiting");
        // Both screens gone at once (the only output went): everything goes, not only the
        // ones that are not critical
        settings({ "notifications.toastFullscreen": "hide" });
        Notifications.screensOverride = [{ name: "queue-screen", focused: true, fullscreen: false, workspace: 1 }];
        const goneCritical = [standIn(-1, critical), standIn(-1, critical)];
        goneCritical.forEach(show);
        Notifications.screensOverride = [];
        assert(place(goneCritical[0]) === "none" && place(goneCritical[1]) === "none" && Notifications.hudQueue.length === 0,
               "no screen at all: the critical toasts go too, shown and waiting");
        Notifications.screensOverride = [{ name: "queue-screen", focused: true, fullscreen: false, workspace: 1 }];
        settings({});
        clear();

        // --- a toast swiped away just as its time ran out: still the notification dismissed ---
        const lateSwipe = standIn(-1);
        const lateSwipeToast = show(lateSwipe);
        Notifications.toastGone(lateSwipe.id);
        cardOf(lateSwipeToast).closeClicked();
        assert(lateSwipe.dismissCalls === 1 && !lateSwipe.tracked, "its time ran out during the swipe: the notification is dismissed all the same");
        clear();

        Notifications.screensOverride = null;
        Config.globals = savedGlobals;
        for (const object of made)
            object.destroy();
    }

    // Modals in the queues' state (Notifications): pinned from the centre, kept through the
    // centre opening, toasts off and a fullscreen window ("Don't show": hidden, then back), a
    // pinned toast that counted down kept until its job stays and ends, a modal whose screen
    // went back in its queue — or gone when that queue takes nothing now. Dragging under real
    // input events: ToastDragTest.
    function _modals() {
        const savedGlobals = Config.globals;
        const settings = change => {
            Config.globals = JSON.stringify(Object.assign(JSON.parse(savedGlobals || "{}"), change));
        };
        settings({});
        Notifications.clearHudQueue();
        Notifications.screensOverride = [{ name: "modal-screen", focused: true, fullscreen: false, workspace: 1 }];
        const made = [];
        let nextId = 9301;
        const standIn = (expire, change) => {
            const standing = _standIn.createObject(suite, Object.assign({ id: nextId++, expireTimeout: expire, summary: "Toast" }, change ?? {}));
            made.push(standing);
            return standing;
        };
        const place = notification => {
            const at = Notifications.toastPlace(notification.id);
            return at.place + (at.queue ? " " + at.queue : "");
        };

        // --- pinned from the centre: no toast before, a modal on the toasts' screen ---
        const mail = standIn(-1);
        assert(Notifications.pinToast(mail) && place(mail) === "moved ordinary" && Notifications.toastScreens[mail.id] === "modal-screen",
               "pinned with no toast: a modal on the toasts' screen");
        assert(!Notifications.countingToasts.includes(mail.id) && Notifications.toastDurations[mail.id] === 5000,
               "pinned while it would count down: it stays (its time kept for later)");
        assert(Notifications.pinToast(mail) && place(mail) === "moved ordinary", "pinned again: it stays as it is");
        Notifications.unpinToast(mail.id);
        assert(place(mail) === "none" && mail.tracked && mail.dismissCalls === 0, "unpinned: the modal ends, the entry stays");
        const gone = standIn(-1);
        gone.tracked = false;
        assert(!Notifications.pinToast(gone) && place(gone) === "none", "an entry gone: not pinned");
        // From a centre open on another screen: on that one
        const fromCentre = standIn(-1);
        assert(Notifications.pinToast(fromCentre, "centre-screen") && Notifications.toastScreens[fromCentre.id] === "centre-screen",
               "pinned from a centre on another screen: a modal on the centre's screen");
        Notifications.unpinToast(fromCentre.id);
        const shownThere = standIn(0);
        Notifications.enqueueHudNotification(shownThere);
        Notifications.fillToasts("modal-screen");
        assert(place(shownThere) === "shown staying" && Notifications.toastScreens[shownThere.id] === "modal-screen", "a toast shown on the toasts' screen");
        assert(Notifications.pinToast(shownThere, "centre-screen") && place(shownThere) === "moved staying"
               && Notifications.toastScreens[shownThere.id] === "centre-screen", "… pinned from the other screen's centre: it goes there");
        Notifications.toastGone(shownThere.id);
        Notifications.screensOverride = [];
        assert(!Notifications.pinToast(mail) && place(mail) === "none", "no screen for toasts: not pinned");
        Notifications.screensOverride = [{ name: "modal-screen", focused: true, fullscreen: false, workspace: 1 }];

        // --- a pinned job: kept while it would count, by its kind once it stays, then counts when it ends ---
        const job = standIn(5000);
        Notifications.pinToast(job);
        assert(!Notifications.countingToasts.includes(job.id), "a job pinned while it counted: it stays");
        job.expireTimeout = 0;
        Notifications._retime(job.id, job);
        assert(place(job) === "moved staying" && !Notifications.countingToasts.includes(job.id), "it runs again (stays): still a modal (its queue now staying), no countdown");
        job.expireTimeout = 3000;
        Notifications._retime(job.id, job);
        assert(Notifications.countingToasts.includes(job.id), "it ends: the modal counts down where it is");
        Notifications.toastGone(job.id);

        // --- the centre, toasts off and a fullscreen window leave modals in the state ---
        const pinned = standIn(0);
        Notifications.pinToast(pinned);
        Notifications.setHudPanelOpen(true);
        assert(place(pinned) === "moved staying", "the centre opened: the modal stays");
        const whileOpen = standIn(-1);
        assert(Notifications.pinToast(whileOpen) && place(whileOpen) === "moved ordinary", "pinned while the centre is open: a modal at once");
        Notifications.setHudPanelOpen(false);
        settings({ "notifications.toasts": false });
        assert(place(pinned) === "moved staying", "toasts off: the modal stays");
        settings({ "notifications.toastFullscreen": "hide" });
        Notifications.screensOverride = [{ name: "modal-screen", focused: true, fullscreen: true, workspace: 1 }];
        const hidden = ToastRules.onScreen(Notifications.toastState, Notifications.fullscreenHidden);
        assert(place(pinned) === "moved staying" && hidden.modals.length === 0, "a fullscreen window, \"Don't show\": kept, not shown");
        Notifications.screensOverride = [{ name: "modal-screen", focused: true, fullscreen: false, workspace: 1 }];
        assert(ToastRules.onScreen(Notifications.toastState, Notifications.fullscreenHidden).modals.some(entry => entry.id === pinned.id),
               "… back when the fullscreen window goes");
        settings({});

        // --- its screen gone: back in its queue, or gone when that queue takes nothing now ---
        Notifications.modalScreenGone(pinned.id);
        assert(place(pinned) === "waiting staying", "its screen gone: it waits in its queue again");
        Notifications.pinToast(pinned);
        Notifications.setHudPanelOpen(true);
        Notifications.modalScreenGone(whileOpen.id);
        assert(place(whileOpen) === "none", "its screen gone while the centre is open: an ordinary one goes (the centre shows it)");
        Notifications.setHudPanelOpen(false);
        Notifications.modalScreenGone(mail.id);
        assert(place(mail) === "none", "not a modal: nothing");

        // --- the movable option and the rules' answer ---
        assert(Notifications.movableToasts && Notifications.canMoveToast(pinned.id), "movable by default: a modal can be dragged");
        settings({ "notifications.movableToasts": false });
        assert(!Notifications.canMoveToast(pinned.id), "the option off: no drag");
        Notifications.moveToast(pinned.id, 10, 10);
        assert(Notifications.toastState.moved.find(entry => entry.id === pinned.id).x !== 10, "… and a move asked for is refused");
        settings({});
        Notifications.placeModal(pinned.id, 30, 40);
        const placed = Notifications.toastState.moved.find(entry => entry.id === pinned.id);
        assert(placed.x === 30 && placed.y === 40, "a pinned modal given its place");

        Notifications.clearHudQueue();
        Notifications.screensOverride = null;
        Config.globals = savedGlobals;
        for (const object of made)
            object.destroy();
    }

    // The shell's own sender announcing a notification again (x-qs-announce raised,
    // Notifications.watchAnnounces): its toast comes back once through the queue, or on
    // screen counts its time again; stand-in notifications, a stack on a stand-in toasts' screen
    function _announces() {
        const savedGlobals = Config.globals;
        Config.globals = JSON.stringify(Object.assign(JSON.parse(savedGlobals || "{}"), { "notifications.toastDuration": 5 }));
        Notifications.screensOverride = [{ name: "announce-screen", focused: true, fullscreen: false, workspace: 1 }];
        const made = [];
        let nextId = 9101;
        const standIn = run => {
            const hints = { value: 40 };
            if (run !== undefined)
                hints["x-qs-progress-run"] = run;
            const standing = _standIn.createObject(suite, { id: nextId++, summary: "Job", hints: hints });
            made.push(standing);
            Notifications.watchAnnounces(standing);
            return standing;
        };
        const replace = (notification, change) => {
            notification.hints = Object.assign({}, notification.hints, change);
        };
        const stack = _stack.createObject(suite, { screenModelData: { name: "announce-screen" } });
        made.push(stack);
        const toastOf = notification => stack.toastFor(notification.id);
        const countdownOf = toast => toast.resources.find(resource => resource.property === "remaining");
        // The toast leaves now, its slide out finished
        const away = notification => {
            const toast = toastOf(notification);
            toast.dismiss();
            toast.resources.find(resource => resource.property === "x" && resource.to === toast.screenWidth).complete();
        };
        const timesShown = id => _allShown().filter(shown => shown === id).length;
        const shownTotal = () => _allShown().length;
        const quiet = message => assert(stack.stack.length === 0 && Notifications.hudQueue.length === 0 && shownTotal() === 0,
                                       message + " (" + Notifications.hudQueue.length + " waiting, " + shownTotal() + " shown)");

        const job = standIn(Notifier.progressRun);
        Notifications.enqueueHudNotification(job);
        assert(toastOf(job)?.present && timesShown(job.id) === 1, "the job's toast shows");
        away(job);
        quiet("taken away: gone");

        replace(job, { "x-qs-announce": "1" });
        assert(toastOf(job)?.present && timesShown(job.id) === 1 && Notifications.hudQueue.length === 0 && countdownOf(toastOf(job)).running,
               "announced with its toast gone: it comes back, counting");
        replace(job, { value: 50 });
        assert(toastOf(job)?.present && timesShown(job.id) === 1 && Notifications.hudQueue.length === 0,
               "a plain update while shown: nothing more");
        away(job);
        replace(job, { value: 60 });
        quiet("a plain update after it went: it does not come back (once)");

        // On screen: its time starts again, no second toast
        replace(job, { "x-qs-announce": "2" });
        const toast = toastOf(job);
        const countdown = countdownOf(toast);
        // As if it had counted half its time
        countdown.pause();
        toast.remaining = 0.5;
        const before = toast.remaining;
        replace(job, { "x-qs-announce": "3" });
        assert(before === 0.5 && countdown.running && !countdown.paused && toast.remaining > 0.9
               && timesShown(job.id) === 1 && Notifications.hudQueue.length === 0,
               "announced on screen: its time starts again, no second toast (" + before + " → " + toast.remaining + ")");

        // Waiting its turn already: not queued twice
        const other = standIn(Notifier.progressRun);
        away(job);
        Notifications.enqueueHudNotification(other);
        Notifications.enqueueHudNotification(job);
        assert(toastOf(other)?.present && Notifications.hudQueue.length === 1, "the job waits behind another toast");
        replace(job, { "x-qs-announce": "4" });
        assert(Notifications.hudQueue.length === 1 && timesShown(job.id) === 0, "announced while waiting: still once in the queue");
        Notifications.clearHudQueue();
        toastOf(other).resources.find(resource => resource.property === "x" && resource.to === toastOf(other).screenWidth).complete();
        quiet("cleared");

        // Toasts off, no toast screen, the centre open: nothing slides in
        Config.globals = JSON.stringify(Object.assign(JSON.parse(savedGlobals || "{}"), { "notifications.toasts": false }));
        replace(job, { "x-qs-announce": "5" });
        quiet("toasts off: an announce brings nothing");
        Config.globals = JSON.stringify(Object.assign(JSON.parse(savedGlobals || "{}"), { "notifications.toastDuration": 5 }));
        Notifications.screensOverride = [];
        replace(job, { "x-qs-announce": "6" });
        Notifications.screensOverride = [{ name: "announce-screen", focused: true, fullscreen: false, workspace: 1 }];
        quiet("no toast screen: an announce brings nothing");
        Notifications.setHudPanelOpen(true);
        replace(job, { "x-qs-announce": "7" });
        Notifications.setHudPanelOpen(false);
        quiet("the centre open: an announce brings nothing");

        // An outside app's replacement — plain, or even with the hint but not this run's token
        const outside = standIn();
        const otherRun = standIn("an-earlier-run");
        replace(outside, { value: 70 });
        outside.summary = "Replaced";
        replace(outside, { "x-qs-announce": "1" });
        replace(otherRun, { "x-qs-announce": "1" });
        quiet("an outside app's replacement, or another run's announce: nothing, as before");

        Notifications.screensOverride = null;
        Config.globals = savedGlobals;
        for (const object of made)
            object.destroy();
    }

    // The body under `card` (found by `test`), its box given a toast's width
    function _layOut(card, test) {
        const body = _find(card, test);
        body.parent.width = 300;
        return body;
    }

    // The ids of every shown toast, critical first
    function _allShown() {
        const shown = Notifications.toastState.shown;
        return shown.critical.concat(shown.staying, shown.ordinary);
    }

    // Every item under `item` (itself not included) for which `test` holds
    function _findAll(item, test) {
        const found = [];
        for (const child of item?.children ?? []) {
            if (test(child))
                found.push(child);
            found.push(..._findAll(child, test));
        }
        return found;
    }

    // The first item under `item` (itself not included) for which `test` holds, or null
    function _find(item, test) {
        for (const child of item?.children ?? []) {
            if (test(child))
                return child;
            const found = _find(child, test);
            if (found)
                return found;
        }
        return null;
    }

    property Component _toast: Component {
        NotificationHudItem {
            screenWidth: 800
            screenModelData: ({ name: "test-screen" })
        }
    }
    // A notification's action as Quickshell hands it: an object with an identifier, a text
    // and invoke()
    property Component _action: Component {
        QtObject {
            property string identifier
            property string text
            property int invoked: 0
            function invoke() {
                invoked++;
            }
        }
    }
    // The toasts of a screen, as Hud makes them; the suite gives it its screen
    property Component _stack: Component {
        ToastStack {
            screenWidth: 800
            screenModelData: ({ name: "test-screen" })
        }
    }
    // A notification as the server hands it, as far as a toast reads it
    property Component _standIn: Component {
        QtObject {
            property int id
            property real expireTimeout: -1
            property int urgency: NotificationUrgency.Normal
            property string appName: "Test"
            property string appIcon: ""
            property string summary
            property string body: ""
            property string image: ""
            property var actions: []
            property bool hasInlineReply: false
            property var hints: ({})
            property bool resident: false
            property bool tracked: true
            property int dismissCalls: 0
            signal closed(int reason)
            // As Quickshell dismisses one: closed (Dismissed), no longer tracked
            function dismiss() {
                dismissCalls++;
                closed(NotificationCloseReason.Dismissed);
                tracked = false;
            }
        }
    }
    property Component _card: Component {
        NotificationCard {
            width: 360
        }
    }
}
