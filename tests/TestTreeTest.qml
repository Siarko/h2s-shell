import QtQuick
import Quickshell
import Quickshell.Io

// tests/test-tree.sh, which makes a test tree (the lock bed's copy of the checkout, or one
// for running the shell with stand-ins by hand): the copy has the test seam files in the
// production ones' place and the rest of the checkout, and the checkout is not touched. It
// refuses a destination that holds something or lies inside the checkout.
TestCase {
    id: suite
    suiteName: "TestTree"
    asynchronous: true

    function runAsync() {
        // Each fact a line "<name>=<0|1>" (1: holds), from one shell script
        _run.command = ["sh", "-c",
            "repo=$1\n"
            + "work=$(mktemp -d) || exit 1\n"
            + "fact() { name=$1; shift; if \"$@\"; then echo \"$name=1\"; else echo \"$name=0\"; fi; }\n"
            + "touch \"$work/stamp\"\n"
            + "sleep 0.01\n"
            + "before=$(cat \"$repo/singletons/TestSeams.qml\" \"$repo/scripts/seams.sh\" | cksum)\n"
            + "printed=$(\"$repo/tests/test-tree.sh\" \"$work/tree\"); status=$?\n"
            + "tree=$work/tree\n"
            + "fact made test \"$status\" = 0\n"
            + "fact printed test \"$printed\" = \"$(cd \"$tree\" && pwd -P)\"\n"
            + "fact qml cmp -s \"$repo/tests/lock/seams/TestSeams.qml\" \"$tree/singletons/TestSeams.qml\"\n"
            + "fact rules cmp -s \"$repo/tests/lock/seams/TestSeamRules.qml\" \"$tree/singletons/TestSeamRules.qml\"\n"
            + "fact script cmp -s \"$repo/tests/lock/seams/seams.sh\" \"$tree/scripts/seams.sh\"\n"
            + "fact rest cmp -s \"$repo/shell.qml\" \"$tree/shell.qml\"\n"
            + "fact stand-in test -f \"$tree/tests/FakeVpnProvider.qml\"\n"
            + "fact executable test -x \"$tree/scripts/launch.sh\"\n"
            + "fact no-git test ! -e \"$tree/.git\"\n"
            + "fact untouched test \"$before\" = \"$(cat \"$repo/singletons/TestSeams.qml\" \"$repo/scripts/seams.sh\" | cksum)\"\n"
            + "fact unwritten test -z \"$(find \"$repo\" -path \"$repo/.git\" -prune -o -newer \"$work/stamp\" -print | head -n 1)\"\n"
            + "\"$repo/tests/test-tree.sh\" \"$tree\" > /dev/null 2>&1; fact refuses-full test $? = 2\n"
            + "\"$repo/tests/test-tree.sh\" \"$repo/test-tree-probe/nested\" > /dev/null 2>&1; fact refuses-inside test $? = 2\n"
            + "fact inside-left-nothing test ! -e \"$repo/test-tree-probe\"\n"
            + "rm -rf \"$work\"",
            "sh", Quickshell.shellDir];
        _run.running = true;
    }

    property Process _run: Process {
        property string output: ""
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => suite._run.output += data
        }
        onExited: (code, status) => {
            const facts = {};
            for (const line of output.split("\n")) {
                const match = /^([a-z-]+)=([01])$/.exec(line);
                if (match !== null)
                    facts[match[1]] = match[2] === "1";
            }
            const expect = (name, message) => suite.assert(facts[name] === true, message);
            expect("made", "the tree is made (status 0)");
            expect("printed", "… and its path printed");
            expect("qml", "singletons/TestSeams.qml is the test seam file");
            expect("rules", "… TestSeamRules beside it");
            expect("script", "scripts/seams.sh is the test seam script");
            expect("rest", "the rest is the checkout's (shell.qml)");
            expect("stand-in", "tests/ is there (the stand-in VPN provider loads from it)");
            expect("executable", "scripts keep their mode");
            expect("no-git", "no .git");
            expect("untouched", "the checkout's own seam files are unchanged");
            expect("unwritten", "nothing in the checkout was written");
            expect("refuses-full", "a destination that holds something: refused (status 2)");
            expect("refuses-inside", "a destination inside the checkout: refused (status 2)");
            expect("inside-left-nothing", "… and nothing left there");
            suite.finish();
        }
    }
}
