import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.tests.lock.seams as TestBed

// The two TestSeams files: singletons/TestSeams.qml (constants, what the shell runs with)
// and tests/lock/seams/TestSeams.qml (the reader a test tree has in its place,
// tests/lock/README.md "The test tree"). A consumer reads the same property in either, so
// they must have the same properties — a property in one only is `undefined` in the other
// tree. The production file reads nothing from the environment, and its values are what
// the reader says when no seam is set. And no other file of the shell reads a seam itself:
// that would bring the seam back into the installed shell.
TestCase {
    id: suite
    suiteName: "TestSeamsShape"
    asynchronous: true

    property var _production: FileView {
        path: Quickshell.shellDir + "/singletons/TestSeams.qml"
        blockLoading: true
    }
    property var _testTree: FileView {
        path: Quickshell.shellDir + "/tests/lock/seams/TestSeams.qml"
        blockLoading: true
    }

    // "type name" of each public property a file declares
    function _properties(text) {
        const found = [];
        const pattern = /^\s*(?:readonly\s+)?property\s+(\w+)\s+([A-Za-z]\w*)\s*:/gm;
        let match;
        while ((match = pattern.exec(text)) !== null)
            found.push(match[1] + " " + match[2]);
        return found.sort();
    }

    function runAsync() {
        const production = _production.text();
        const testTree = _testTree.text();
        assert(production.length > 0 && testTree.length > 0, "both files read");
        const productionProperties = _properties(production);
        assert(productionProperties.length >= 10, "the production file's properties found (" + productionProperties.length + ")");
        assertEqual(_properties(testTree).join(", "), productionProperties.join(", "), "the same properties, of the same types, in both files");
        assert(!production.includes("Quickshell.env"), "the production file reads nothing from the environment");
        assert(!production.includes("TestSeamRules"), "… and does not use the reader's rules");

        // The values: what the reader says for an environment without any seam
        const none = TestBed.TestSeamRules.read({});
        for (const property of productionProperties) {
            const name = property.split(" ")[1];
            const expected = name === "active" ? false : none[name];
            assert(expected !== undefined, name + ": the reader has it");
            assertEqual(JSON.stringify(TestSeams[name]), JSON.stringify(expected), name + ": the production value is the reader's with no seam set");
        }

        // No file of the shell (outside tests/ and the test entry files) reads a seam from
        // the environment: an H2S_LOCK_*, H2S_*TEST* or H2S_FAKE_* variable. Named in a
        // comment or a log line is fine; read is not. The search is also run on a tree made
        // for it, holding one such read, so that it is seen to find one.
        _search.command = ["sh", "-c",
            "search() { cd \"$1\" && grep -rnE --include='*.qml' --exclude-dir=tests --exclude-dir=.git "
            + "-e 'Quickshell\\.env\\([[:space:]]*\"H2S_(LOCK_|FAKE_|[A-Z_]*TEST)' -e 'TestSeamRules' . "
            + "| grep -vE '^\\./tests(-modules)?\\.qml:' | grep -vE '^[^:]*:[0-9]+:[[:space:]]*//'; true; }\n"
            + "(search \"$1\")\n"
            + "probe=$(mktemp -d) && mkdir -p \"$probe/widgets\" && "
            + "printf '%s\\n' 'import Quickshell' 'QtObject { property string x: Quickshell.env(\"H2S_LOCK_NEW\") ?? \"\" }' > \"$probe/widgets/A.qml\" && "
            + "printf '%s\\n' '// Quickshell.env(\"H2S_LOCK_NEW\") in a comment' > \"$probe/widgets/B.qml\" && "
            + "(search \"$probe\") | sed 's/^/PROBE:/'; rm -rf \"$probe\"",
            "sh", Quickshell.shellDir];
        _search.running = true;
    }

    property Process _search: Process {
        property string output: ""
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => suite._search.output += data
        }
        onExited: (code, status) => {
            const lines = output.split("\n").filter(line => line !== "");
            const found = lines.filter(line => !line.startsWith("PROBE:"));
            const probe = lines.filter(line => line.startsWith("PROBE:"));
            suite.assertEqual(found.join(" | "), "", "no file of the shell reads a seam itself");
            suite.assertEqual(probe.map(line => line.replace(/^PROBE:\.\/([^:]*):.*/, "$1")).join(","), "widgets/A.qml",
                              "… the search finds a read in a tree made for it, and not a comment");
            suite.assertEqual(code, 0, "… the search ran");
            suite.finish();
        }
    }
}
