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
        progressCard.notification = withHints({});
        assert(!progressBar.visible, "no value: no bar");
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

    // Toasts through the shared queue (Notifications.hudQueue), each in a slot as Hud makes
    // them, with stand-in notifications: how long each shows (ToastRules.timing), which one
    // counts down, and the room for those that stay (ToastRules.slots)
    function _toastTimes() {
        const savedGlobals = Config.globals;
        const made = [];
        let nextId = 9001;
        const standIn = (expire, critical) => {
            const standing = _standIn.createObject(suite, { id: nextId++, expireTimeout: expire, summary: "Toast",
                urgency: critical ? NotificationUrgency.Critical : NotificationUrgency.Normal });
            made.push(standing);
            return standing;
        };
        // Queued, then a new slot takes the next one that has room
        const show = notification => {
            Notifications.enqueueHudNotification(notification);
            const slot = _slot.createObject(suite);
            made.push(slot);
            slot.showNext();
            return slot;
        };
        const countdownOf = slot => slot.resources.find(resource => resource.property === "remaining") ?? null;
        const cardOf = slot => _find(slot, item => item.bodyMaxLines !== undefined);
        const counting = slot => slot._counting && countdownOf(slot).running;
        const settings = change => {
            Config.globals = JSON.stringify(Object.assign(JSON.parse(savedGlobals || "{}"), change));
        };
        const clear = () => Notifications.clearHudQueue();

        // --- the default layout (one at a time): one that stays takes none of its slot ---
        settings({});
        const stays = show(standIn(0));
        assert(stays.currentNotif?.id === 9001 && !counting(stays) && !cardOf(stays).timerVisible,
               "expire 0: shown, no countdown, no timer bar");
        assert(Notifications.stayingToasts.includes(9001) && Notifications.toastDurations[9001] === 0, "expire 0: listed as staying, its time 0");
        const ordinary = show(standIn(-1));
        assert(ordinary.currentNotif?.id === 9002 && counting(ordinary) && countdownOf(ordinary).duration === 5000 && cardOf(ordinary).timerVisible,
               "beside it, an ordinary toast shows in the layout's one slot and counts the user's 5 s");
        const critical = show(standIn(-1, true));
        assert(critical.currentNotif?.id === 9003 && !counting(critical) && !cardOf(critical).timerVisible && cardOf(critical)._critical,
               "a critical one stays above too, outlined");
        cardOf(stays).dismissRequested();
        assert(!Notifications.shownToasts.includes(9001) && made[0].dismissCalls === 0 && made[0].tracked,
               "its \"×\": the toast goes, the entry stays");
        clear();

        // --- the limit of those that stay: more wait, counted ---
        settings({ "notifications.maxStayingToasts": 1 });
        const first = show(standIn(0));
        Notifications.enqueueHudNotification(standIn(0));
        const ordinaryAfter = standIn(-1);
        const taker = show(ordinaryAfter);
        assert(first.currentNotif !== null && taker.currentNotif === ordinaryAfter && Notifications.hudQueue.length === 1
               && Notifications.hudQueue[0].expireTimeout === 0,
               "at most 1 that stays: the second waits in the queue, the ordinary one after it shows");
        clear();

        // --- a column: the sender's time counts by itself, the user's time one at a time ---
        settings({ "notifications.toastLayout": "column", "notifications.toastColumnSize": 3 });
        const oldest = show(standIn(-1));
        const waiting = show(standIn(-1));
        const ownTime = show(standIn(3000));
        assert(counting(oldest) && !counting(waiting) && waiting.remaining === 1, "the user's time: the oldest counts, the next waits its turn");
        assert(counting(ownTime) && countdownOf(ownTime).duration === 3000 && Notifications.toastDurations[ownTime.currentNotif.id] === 3000,
               "3000 ms: counts 3 s at once, by itself");
        oldest.dismiss();
        assert(counting(waiting), "the oldest leaving while it counts: the next counts at once");
        waiting.currentNotif.expireTimeout = 0;
        assert(!counting(waiting) && waiting.remaining === 1 && !cardOf(waiting).timerVisible && Notifications.stayingToasts.includes(waiting.currentNotif.id),
               "replaced with 0 while counting: it stops, stays, no timer bar");
        clear();

        settings({});
        const replaced = show(standIn(0));
        replaced.currentNotif.expireTimeout = -1;
        assert(counting(replaced) && countdownOf(replaced).duration === 5000 && cardOf(replaced).timerVisible && !Notifications.stayingToasts.includes(replaced.currentNotif.id),
               "replaced 0 → -1 while shown: counts the user's time, its bar shows");
        replaced.currentNotif.expireTimeout = 4000;
        assert(counting(replaced) && countdownOf(replaced).duration === 4000 && Notifications.toastDurations[replaced.currentNotif.id] === 4000,
               "replaced with 4000: counts 4 s from full");
        clear();

        // --- "Apps choose how long" off: every toast the user's time, as before ---
        settings({ "notifications.followSenderTime": false, "notifications.toastLayout": "column" });
        const zero = show(standIn(0));
        const thirty = show(standIn(30000));
        assert(counting(zero) && countdownOf(zero).duration === 5000 && cardOf(zero).timerVisible && !counting(thirty),
               "setting off: expire 0 counts the user's time; 30 s waits its turn like any other");
        clear();

        // --- a notification closed while its toast waits its turn: the next still counts ---
        settings({ "notifications.toastLayout": "column", "notifications.toastColumnSize": 3 });
        const counter = show(standIn(-1));
        const closedOne = show(standIn(-1));
        const behind = show(standIn(-1));
        const closedId = closedOne.currentNotif.id;
        closedOne.currentNotif.closed(1);
        assert(!Notifications.shownToasts.includes(closedId), "closed by its sender: off the list of shown toasts");
        counter.dismiss();
        assert(counting(behind), "the counting one leaving: the one behind the closed one counts");
        clear();

        // --- a backlog draining at once (each take makes every free slot take): never past the room ---
        const drain = (change, queue, check, message) => {
            settings(change);
            const drainSlots = [];
            for (let i = 0; i < 15; i++) {
                // On the toasts' screen (none here, ""), so a change of the queue reaches them
                const slot = _slot.createObject(suite, { screenModelData: { name: Notifications.toastScreen } });
                slot.slotEnabled = Qt.binding(() => i < Notifications.toastRoom.total);
                made.push(slot);
                drainSlots.push(slot);
            }
            Notifications.hudQueue = queue.map(expire => standIn(expire));
            const onScreen = drainSlots.filter(slot => slot.currentNotif !== null && slot._shownId >= 0).length;
            const staying = Notifications.stayingToasts.length;
            const others = Notifications.shownToasts.length - staying;
            assert(check(others, staying) && onScreen === Notifications.shownToasts.length,
                   message + " (" + others + " counting, " + staying + " staying, " + onScreen + " slots showing, "
                   + Notifications.hudQueue.length + " waiting)");
            clear();
            // This round's free slots take nothing in the next
            for (const slot of drainSlots)
                slot.slotEnabled = false;
        };
        drain({}, [-1, -1, -1], (others, staying) => others === 1 && staying === 0, "one at a time: three at once, one shows");
        drain({ "notifications.toastLayout": "column", "notifications.toastColumnSize": 3 }, [-1, -1, -1, -1, -1],
              (others, staying) => others === 3, "a column of 3: five at once, three show");
        drain({ "notifications.maxStayingToasts": 1 }, [0, 0, 0, -1], (others, staying) => others === 1 && staying === 1,
              "at most 1 that stays: three that stay and one more, one of each shows");
        drain({ "notifications.followSenderTime": false }, [0, 3000, -1], (others, staying) => others === 1 && staying === 0,
              "\"Apps choose how long\" off: one at a time, one shows");

        // --- one closed while it waits: never shown, the next shows after the first leaves ---
        const closedWaiting = (makeQueue, message) => {
            settings({});
            const waitSlots = [];
            for (let i = 0; i < 4; i++) {
                const slot = _slot.createObject(suite, { screenModelData: { name: Notifications.toastScreen } });
                made.push(slot);
                waitSlots.push(slot);
            }
            const queue = makeQueue();
            Notifications.hudQueue = queue.list;
            const firstSlot = waitSlots.find(slot => slot.currentNotif === queue.first);
            queue.close();
            firstSlot.dismiss();
            const free = waitSlots.filter(slot => slot !== firstSlot && slot.currentNotif === null);
            let threw = "";
            try {
                free.forEach(slot => slot._retry());
            } catch (error) {
                threw = String(error);
            }
            const showing = waitSlots.filter(slot => slot.currentNotif !== null && slot._shownId >= 0);
            assert(firstSlot !== undefined && threw === "" && showing.length === 1 && showing[0].currentNotif === queue.last
                   && Notifications.hudQueue.length === 0 && waitSlots.every(slot => !slot._taking),
                   message + " (" + showing.length + " showing, " + Notifications.hudQueue.length + " waiting" + (threw ? ", threw " + threw : "") + ")");
            clear();
            for (const slot of waitSlots)
                slot.slotEnabled = false;
        };
        closedWaiting(() => {
            const list = [standIn(-1), standIn(-1), standIn(-1)];
            return { list: list, first: list[0], last: list[2], close: () => list[1].dismiss() };
        }, "one at a time, the 2nd dismissed while it waits: the 3rd shows after the 1st, nothing left waiting");
        closedWaiting(() => {
            const list = [standIn(-1), null, standIn(-1)];
            return { list: list, first: list[0], last: list[2], close: () => {} };
        }, "one at a time, the 2nd freed while it waits (reads null): the 3rd shows after the 1st");

        Config.globals = savedGlobals;
        for (const object of made)
            object.destroy();
    }

    // The shell's own sender announcing a notification again (x-qs-announce raised,
    // Notifications.watchAnnounces): its toast comes back once through the queue, or on
    // screen counts its time again; stand-in notifications, a slot on a stand-in toast screen
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
        // Its own screen's name: slots of the suite's earlier parts, not freed yet, are on "test-screen"
        const slot = _slot.createObject(suite, { screenModelData: { name: "announce-screen" } });
        made.push(slot);
        const countdown = slot.resources.find(resource => resource.property === "remaining");
        // The toast leaves now, its slide out finished
        const away = () => {
            slot.dismiss();
            slot.resources.find(resource => resource.property === "x" && resource.to === slot.screenWidth).complete();
        };
        const timesShown = id => Notifications.shownToasts.filter(shown => shown === id).length;
        const quiet = message => assert(slot.currentNotif === null && Notifications.hudQueue.length === 0 && Notifications.shownToasts.length === 0,
                                       message + " (" + Notifications.hudQueue.length + " waiting, " + Notifications.shownToasts.length + " shown)");

        const job = standIn(Notifier.progressRun);
        Notifications.enqueueHudNotification(job);
        assert(slot.currentNotif === job && timesShown(job.id) === 1, "the job's toast shows");
        away();
        quiet("taken away: gone");

        replace(job, { "x-qs-announce": "1" });
        assert(slot.currentNotif === job && timesShown(job.id) === 1 && Notifications.hudQueue.length === 0 && countdown.running,
               "announced with its toast gone: it comes back, counting");
        replace(job, { value: 50 });
        assert(slot.currentNotif === job && timesShown(job.id) === 1 && Notifications.hudQueue.length === 0,
               "a plain update while shown: nothing more");
        away();
        replace(job, { value: 60 });
        quiet("a plain update after it went: it does not come back (once)");

        // On screen: its time starts again, no second toast
        replace(job, { "x-qs-announce": "2" });
        // As if it had counted half its time
        countdown.pause();
        slot.remaining = 0.5;
        const before = slot.remaining;
        replace(job, { "x-qs-announce": "3" });
        assert(before === 0.5 && countdown.running && !countdown.paused && slot.remaining > 0.9
               && timesShown(job.id) === 1 && Notifications.hudQueue.length === 0,
               "announced on screen: its time starts again, no second toast (" + before + " → " + slot.remaining + ")");

        // Waiting its turn already: not queued twice
        const other = standIn(Notifier.progressRun);
        away();
        Notifications.enqueueHudNotification(other);
        Notifications.enqueueHudNotification(job);
        assert(slot.currentNotif === other && Notifications.hudQueue.length === 1, "the job waits behind another toast");
        replace(job, { "x-qs-announce": "4" });
        assert(Notifications.hudQueue.length === 1 && timesShown(job.id) === 0, "announced while waiting: still once in the queue");
        Notifications.clearHudQueue();
        slot.resources.find(resource => resource.property === "x" && resource.to === slot.screenWidth).complete();
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
            slotEnabled: false
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
    // A slot of the toast stack, on a screen that is not the toasts' screen: it takes a
    // toast only when told (showNext), not on its own
    property Component _slot: Component {
        NotificationHudItem {
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
            function dismiss() {
                dismissCalls++;
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
