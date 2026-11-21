import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.tests.lock.seams as TestBed

// The test seam files, each in two versions: the production one (constants, what the shell
// runs with) and the test bed's, which a test tree has in its place (tests/lock/README.md,
// "The test tree") — singletons/TestSeams.qml and tests/lock/seams/TestSeams.qml for QML,
// scripts/seams.sh and tests/lock/seams/seams.sh for the scripts. A consumer reads the same
// name in either, so each pair must have the same names — one in one file only is
// `undefined` (an empty variable) in the other tree. The production files read nothing
// from the environment, and TestSeams' values are what the reader says when no seam is
// set. And no other file of the shell reads a seam itself: that would bring the seam back
// into the installed shell.
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
    property var _productionScript: FileView {
        path: Quickshell.shellDir + "/scripts/seams.sh"
        blockLoading: true
    }
    property var _bar: FileView {
        path: Quickshell.shellDir + "/Bar.qml"
        blockLoading: true
    }
    property var _testTreeScript: FileView {
        path: Quickshell.shellDir + "/tests/lock/seams/seams.sh"
        blockLoading: true
    }

    // "type name" of each public property a QML file declares
    function _properties(text) {
        const found = [];
        const pattern = /^\s*(?:readonly\s+)?property\s+(\w+)\s+([A-Za-z]\w*)\s*:/gm;
        let match;
        while ((match = pattern.exec(text)) !== null)
            found.push(match[1] + " " + match[2]);
        return found.sort();
    }

    // The seam_* variables a script sets, each once
    function _variables(text) {
        const found = new Set();
        const pattern = /^(seam_\w+)=/gm;
        let match;
        while ((match = pattern.exec(text)) !== null)
            found.add(match[1]);
        return Array.from(found).sort();
    }

    // A script's lines without its comments and blank lines
    function _code(text) {
        return text.split("\n").filter(line => line.trim() !== "" && !line.trim().startsWith("#"));
    }

    function runAsync() {
        const production = _production.text();
        const testTree = _testTree.text();
        assert(production.length > 0 && testTree.length > 0, "both TestSeams files read");
        const productionProperties = _properties(production);
        assert(productionProperties.length >= 10, "the production file's properties found (" + productionProperties.length + ")");
        assertEqual(_properties(testTree).join(", "), productionProperties.join(", "), "the same properties, of the same types, in both TestSeams files");
        assert(!production.includes("Quickshell.env"), "the production TestSeams reads nothing from the environment");
        assert(!production.includes("TestSeamRules"), "… and does not use the reader's rules");
        // The held notifications' summaries and bodies are told only in a test tree: the
        // shell's own IPC (Bar.qml's shelltest) has no notificationState
        const bar = _bar.text();
        assert(bar.includes("target: \"shelltest\""), "Bar.qml read, its shelltest IPC found");
        assert(!bar.includes("notificationState"), "… without notificationState");
        assert(!production.includes("notificationState") && testTree.includes("function notificationState()"),
               "notificationState is the test tree's (locktest.notifications), not the production TestSeams'");

        // The values: what the reader says for an environment without any seam — and off for
        // the two that are not read from a variable (module test mode is on in every test
        // tree, tests/lock/seams/TestSeams.qml)
        const none = TestBed.TestSeamRules.read({});
        const notRead = { active: false, moduleTestMode: false };
        for (const property of productionProperties) {
            const name = property.split(" ")[1];
            const expected = name in notRead ? notRead[name] : none[name];
            assert(expected !== undefined, name + ": the reader has it");
            assertEqual(JSON.stringify(TestSeams[name]), JSON.stringify(expected), name + ": the production value is the reader's with no seam set");
        }

        // The scripts' pair
        const productionScript = _productionScript.text();
        const testTreeScript = _testTreeScript.text();
        assert(productionScript.length > 0 && testTreeScript.length > 0, "both seams.sh read");
        const productionVariables = _variables(productionScript);
        assert(productionVariables.length >= 5, "the production seams.sh's variables found (" + productionVariables.length + ")");
        assertEqual(_variables(testTreeScript).join(", "), productionVariables.join(", "), "the same variables in both seams.sh");
        const productionCode = _code(productionScript);
        assertEqual(productionCode.filter(line => !/^seam_\w+=[^$`"'();|&<>]*$/.test(line)).join(" | "), "",
                    "the production seams.sh only sets constants: no expansion, no command");

        // No file of the shell (outside tests/ and the test entry files) reads a seam from
        // the environment: an H2S_LOCK_*, H2S_*TEST* or H2S_FAKE_* variable, by
        // Quickshell.env in QML or as $NAME in a script. Named in a comment or a log line is
        // fine; read is not. The search is also run on a tree made for it, holding one read of
        // each kind and one in a comment, so that it is seen to find them.
        const qmlRead = "Quickshell\\.env\\([[:space:]]*\"H2S_(LOCK_|FAKE_|[A-Z_]*TEST)";
        const scriptRead = "\\$\\{?H2S_(LOCK_|FAKE_|[A-Z_]*TEST)";
        _search.command = ["sh", "-c",
            "qml=$2; script=$3\n"
            + "search() {\n"
            + "    cd \"$1\" || return\n"
            + "    {\n"
            + "        grep -rnE --include='*.qml' --exclude-dir=tests --exclude-dir=.git -e \"$qml\" -e TestSeamRules . | grep -vE '^\\./tests(-modules)?\\.qml:'\n"
            + "        grep -rnE --include='*.sh' --exclude-dir=tests --exclude-dir=.git -e \"$script\" .\n"
            + "        [ ! -d scripts ] || grep -rnE --exclude='*.sh' -e \"$script\" scripts | sed 's|^|./|'\n"
            + "    } | grep -vE '^[^:]*:[0-9]+:[[:space:]]*(//|#)'\n"
            + "    true\n"
            + "}\n"
            + "(search \"$1\")\n"
            + "probe=$(mktemp -d) || exit 1\n"
            + "mkdir -p \"$probe/widgets\" \"$probe/scripts\"\n"
            + "printf '%s\\n' 'import Quickshell' 'QtObject { property string x: Quickshell.env(\"H2S_LOCK_NEW\") ?? \"\" }' > \"$probe/widgets/A.qml\"\n"
            + "printf '%s\\n' '// Quickshell.env(\"H2S_LOCK_NEW\") in a comment' > \"$probe/widgets/B.qml\"\n"
            + "printf '%s\\n' 'x=${H2S_SHELL_TEST_NEW:-}' '    # $H2S_LOCK_NEW in a comment' > \"$probe/scripts/c.sh\"\n"
            + "printf '%s\\n' 'exec \"$H2S_FAKE_NEW\"' > \"$probe/scripts/helper\"\n"
            + "(search \"$probe\") | sed 's/^/PROBE:/'\n"
            + "rm -rf \"$probe\"",
            "sh", Quickshell.shellDir, qmlRead, scriptRead];
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
            suite.assertEqual(probe.map(line => line.replace(/^PROBE:\.\/([^:]*):.*/, "$1")).sort().join(","),
                              "scripts/c.sh,scripts/helper,widgets/A.qml",
                              "… the search finds a read of each kind in a tree made for it, and no comment");
            suite.assertEqual(code, 0, "… the search ran");
            suite.finish();
        }
    }
}
