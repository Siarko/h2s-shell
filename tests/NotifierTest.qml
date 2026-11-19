import QtQuick
import Quickshell.Services.Notifications
import qs.singletons
import qs.hud
import qs.components

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
