import QtQuick
import Quickshell
import qs.singletons

// Pins the Quickshell behaviour the module system rests on (notes/plans/modules.md §2). None of
// it is a documented promise of Quickshell's; it was found in its source and tried. A module is
// a directory outside the scanned tree, with a qmldir of its own, whose files are loaded by
// file:// URL (singletons/ModuleHost.qml). The fixture tests/fixtures/qs-pin is such a
// directory (Quickshell never scans it: nothing imports it).
//
// IF THIS SUITE FAILS AFTER A QUICKSHELL UPGRADE, the module system is broken by the upgrade,
// not by a module: read the failing check's message, and see the plan's §2 before changing
// the host.
TestCase {
    id: suite
    suiteName: "QuickshellPin"

    readonly property string directory: Quickshell.shellDir + "/tests/fixtures/qs-pin"
    property var _held: []

    function _create(url) {
        const component = Qt.createComponent(url, Component.PreferSynchronous);
        if (component.status !== Component.Ready)
            return { component: component, object: null };
        const object = component.createObject(suite);
        _held.push(object);
        return { component: component, object: object };
    }

    function run() {
        const first = _create(ModuleFileRules.fileUrl(directory, "First.qml"));
        const second = _create(ModuleFileRules.fileUrl(directory, "Second.qml"));
        if (!first.object || !second.object) {
            fail("a file loaded by file:// URL from a directory outside the tree did not load: "
                 + (first.component.errorString() + second.component.errorString()).trim()
                 + " — modules cannot be loaded at all (plan §2)");
            return;
        }

        // (a) The directory's own singletons: real singletons, one instance for its files
        assert(first.object.pin !== null && first.object.pin !== undefined,
               "(a) a file loaded by URL sees its directory's qmldir singleton — if not, a module's qmldir is ignored and its singletons are not reachable");
        assert(first.object.pin === second.object.pin,
               "(a) two files of the directory share ONE instance of its singleton — if not, a module's state splits per file (its main and its widgets would not see each other)");
        assertEqual(second.object.pin.count, 2, "(a) … and both wrote to that one instance");

        // (b) The core's singletons: the SAME instances as the shell's
        assert(first.object.config === Config,
               "(b) the core singleton Config seen from a module file is the shell's own instance — if not, modules get a second copy of the core's state (settings, profiles), and nothing they do reaches the shell");
        assert(first.object.rules === ModuleRules && second.object.rules === ModuleRules,
               "(b) … ModuleRules too, from both files");

        // (c) A broken file is contained: an Error status, not a failed config
        const broken = Qt.createComponent(ModuleFileRules.fileUrl(directory, "Broken.qml"), Component.PreferSynchronous);
        assertEqual(broken.status, Component.Error,
                    "(c) a file with a syntax error loads as a Component in Error — if not, one broken module could take the shell (and its lock screen) down");
        assert(broken.errorString().includes("Broken.qml"), "(c) … whose error names the file: " + broken.errorString().trim());

        // (d) Two spellings of one directory give two sets of singletons ("a//b" does; "a/./b"
        // does not; a symlink does): the host's canonical paths avoid it
        const spelled = _create(ModuleFileRules.fileUrl(directory + "/./x/..//", "First.qml"));
        assert(spelled.object !== null && spelled.object.pin === first.object.pin,
               "(d) a directory given in another spelling still reaches the same singleton through the host's canonical paths (ModuleFileRules.fileUrl) — if not, a module given twice would run with two states");
        assertEqual(ModuleFileRules.fileUrl(directory + "//", "First.qml"), ModuleFileRules.fileUrl(directory, "First.qml"),
                    "(d) the host spells one file one way");
        // The trap itself, for the log only (whether Quickshell normalises a repeated "/"
        // changes nothing for the host)
        const raw = _create("file://" + directory + "//First.qml");
        console.log("  INFO: a raw \"//\" spelling " + (raw.object && raw.object.pin !== first.object.pin
            ? "gives a second set of singletons (the trap is there)" : "shares the singletons (the trap is gone)"));

        for (const object of _held)
            object.destroy();
        _held = [];
    }
}
