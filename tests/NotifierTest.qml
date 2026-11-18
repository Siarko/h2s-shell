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

        // --- prepared: format "plain" ---
        const plain = Notifier.prepared("Module: <b>Tail\nscale</b> & co", { body: "Authorization: <i>Send</i> a file & more\n-x", format: "plain", urgency: "low" });
        assertEqual(plain.summary, "Module: <b>Tail scale</b> & co", "plain: the summary on one line, not escaped (no markup there)");
        assertEqual(plain.options.body, "Authorization: &lt;i&gt;Send&lt;/i&gt; a file &amp; more -x", "plain: the body on one line, &, < and > as entities");
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
