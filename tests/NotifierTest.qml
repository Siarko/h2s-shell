import QtQuick
import qs.singletons
import qs.hud

// Notifier's pure parts: format "plain" (what it makes of a summary and a body) and the words
// notify-send gets for it. Nothing is sent: send() is checked in module test mode, where it
// records (tests/fixtures/modules/good, GoodApiTest).
TestCase {
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
    }
}
