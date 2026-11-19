import QtQuick
import qs.singletons

// The file chooser's decisions (singletons/FileChooserRules.qml)
TestCase {
    suiteName: "FileChooserRules"

    function run() {
        const options = (given, home) => FileChooserRules.options(given, home ?? "/home/tester");
        const shown = parsed => [parsed.mode, parsed.title, parsed.startDirectory, parsed.problem].join("|");

        // --- what was asked ---
        assertEqual(shown(options(undefined)), "open||/home/tester|", "no options: open one file, no title, from the home directory");
        assertEqual(shown(options({})), "open||/home/tester|", "… an empty object the same");
        assertEqual(shown(options({ mode: "openMany", title: "Send files", startDirectory: "/srv/share/" })),
                    "openMany|Send files|/srv/share|", "openMany, a title, a directory without its trailing /");
        assertEqual(shown(options({ mode: "folder", startDirectory: "/" })), "folder||/|", "a folder, from /");
        assertEqual(shown(options({ startDirectory: "" })), "open||/home/tester|", "startDirectory \"\": the home directory");
        assertEqual(shown(options({}, "")), "open|||", "home not known: the dialog's own start");
        assertEqual(shown(options({}, "relative")), "open|||", "… a home that is not absolute is not known");
        assertEqual(options({ mode: "save" }).problem, "mode must be one of open, openMany, folder", "an unknown mode");
        assertEqual(options({ mode: 1 }).problem, "mode must be one of open, openMany, folder", "a mode that is not text");
        assertEqual(options({ title: 5 }).problem, "title must be text", "a title that is not text");
        assertEqual(options({ startDirectory: "Downloads" }).problem, "startDirectory must be an absolute path", "a relative directory");
        assertEqual(options({ startDirectory: "file:///tmp" }).problem, "startDirectory must be an absolute path", "… a URL is not a path");
        assertEqual(options({ startDirectory: "/tmp/a\nb" }).problem, "startDirectory: it holds a control character", "… a line break in it");
        assertEqual(options({ startDirectory: "/" + "a".repeat(4096) }).problem, "startDirectory: longer than 4096 characters", "… too long");
        assertEqual(options("open").problem, "the options are not an object", "options that are not an object");
        assertEqual(options(["open"]).problem, "the options are not an object", "… an array neither");
        const throwing = {};
        Object.defineProperty(throwing, "mode", { get() { throw new Error("no"); }, enumerable: true });
        assert(options(throwing).problem.startsWith("the options could not be read"), "a getter that throws: a problem, not an exception");

        // --- the title: plain text, one line, at most 60 characters ---
        assertEqual(FileChooserRules.cleanTitle("  Send\n\tfiles  "), "Send files", "white space folded, trimmed");
        assertEqual(FileChooserRules.cleanTitle("Evil‮elif"), "Evilelif", "a right-to-left override dropped");
        assertEqual(FileChooserRules.cleanTitle("<b>bold</b>"), "<b>bold</b>", "markup kept as written (shown as plain text)");
        assertEqual(FileChooserRules.cleanTitle("x".repeat(80)).length, 60, "cut at 60");
        assertEqual(PrivilegedRules.characters(FileChooserRules.cleanTitle("x".repeat(59) + "😀😀")).join("|"), "x|".repeat(59) + "😀", "… by code point: an emoji is never cut in half");
        assertEqual(FileChooserRules.cleanTitle(null), "", "not text: none");

        // --- whether it may open ---
        const refusal = request => FileChooserRules.refusal(request);
        assertEqual(refusal({ active: true, locked: false, busy: false }), "", "on, unlocked, nothing open: it opens");
        assertEqual(refusal({ active: false, locked: true, busy: true }), "off", "the module off: no answer, whatever else");
        assertEqual(refusal({ active: true, locked: true, busy: true }), "locked", "the session locked, before busy");
        assertEqual(refusal({ active: true, locked: false, busy: true }), "busy", "another chooser open: busy");
        assertEqual(refusal(null), "off", "nothing known: off");

        // --- the answer ---
        const result = FileChooserRules.result({ paths: ["/a"], cancelled: true, blocked: "nonsense", error: 3 });
        assertEqual(JSON.stringify(result), "{\"paths\":[\"/a\"],\"cancelled\":true,\"blocked\":\"\",\"error\":\"\"}",
                    "result: the four fields; an unknown blocked word and an error that is not text dropped");
        assert(Object.isFrozen(result) && Object.isFrozen(result.paths), "… frozen, its paths too");
        assertEqual(FileChooserRules.result({ blocked: "busy" }).blocked, "busy", "… busy kept");

        assertEqual(FileChooserRules.folderUrl("/home/a b/#1?x"), "file:///home/a%20b/%231%3Fx", "a directory as a URL: each part encoded");
        assertEqual(FileChooserRules.folderUrl("/"), "file:///", "… the root");
        assertEqual(FileChooserRules.folderUrl(""), "", "… none: \"\"");
        assertEqual(FileChooserRules.pathOf("file:///home/a%20b/%231%3Fx"), "/home/a b/#1?x", "a file: URL as a path, decoded");
        assertEqual(FileChooserRules.pathOf("file:///tmp/%E2%82%AC.txt"), "/tmp/€.txt", "… UTF-8 decoded");
        assertEqual(FileChooserRules.pathOf("https://example.org/a"), "", "… another scheme: not a local file");
        assertEqual(FileChooserRules.pathOf("file://host/tmp/a"), "", "… a file on another host: not local");
        assertEqual(FileChooserRules.pathOf("file:///tmp/%E2%82"), "", "… broken encoding: none");
        assertEqual(FileChooserRules.pathOf("file:///tmp/a%0Ab"), "", "… a line break in the name: not taken");

        const accepted = (urls, mode) => JSON.stringify(FileChooserRules.accepted(urls, mode));
        assertEqual(accepted(["file:///tmp/a", "file:///tmp/b", "file:///tmp/a"], "openMany"),
                    "{\"paths\":[\"/tmp/a\",\"/tmp/b\"],\"cancelled\":false,\"blocked\":\"\",\"error\":\"\"}", "openMany: every path, once");
        assertEqual(accepted(["file:///tmp/a", "file:///tmp/b"], "open"),
                    "{\"paths\":[\"/tmp/a\"],\"cancelled\":false,\"blocked\":\"\",\"error\":\"\"}", "open: the first only");
        assertEqual(accepted(["file:///srv"], "folder"),
                    "{\"paths\":[\"/srv\"],\"cancelled\":false,\"blocked\":\"\",\"error\":\"\"}", "folder: its path");
        assertEqual(FileChooserRules.accepted(["file:///tmp/a", "sftp://host/b"], "openMany").error,
                    "the dialog returned something that is not a local file", "a URL that is not a local file: an error…");
        assertEqual(FileChooserRules.accepted(["file:///tmp/a", "sftp://host/b"], "openMany").paths.length, 0, "… and no paths: never half a choice");
        assertEqual(FileChooserRules.accepted([], "open").error, "the dialog returned nothing", "nothing chosen: an error");
        assertEqual(FileChooserRules.accepted([""], "folder").error, "the dialog returned something that is not a local file", "… an empty URL too");

        // --- the test kit's answer ---
        const answer = (paths, mode) => FileChooserRules.testAnswer(paths, mode);
        assertEqual(JSON.stringify(answer(["/tmp/a b", "/tmp/c"], "openMany").result?.paths), "[\"/tmp/a b\",\"/tmp/c\"]", "a test answer: the paths as given");
        assertEqual(answer(["/tmp/a", "/tmp/b"], "open").problem, "mode \"open\" chooses one path, not 2", "… two for open: the suite's mistake");
        assertEqual(answer([], "open").problem, "the answer must be a list of at least one path", "… none");
        assertEqual(answer("/tmp/a", "open").problem, "the answer must be a list of at least one path", "… not a list");
        assertEqual(answer(["tmp/a"], "folder").problem, "not an absolute path: \"tmp/a\"", "… a relative path");
        assertEqual(answer([5], "open").problem, "not an absolute path: 5", "… not text");
    }
}
