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

        // (e) A child written inside an element whose default property is a Component —
        // here through the alias of a public wrapper (api/ExpandingRow.qml) — is held as a
        // Component, not built
        const row = Qt.createQmlObject("import QtQuick\nimport qs.api\nExpandingRow {\n    id: row\n    property int built: 0\n"
            + "    Item { Component.onCompleted: row.built++ }\n}", suite, "ExpandingRowPin.qml");
        _held.push(row);
        assertEqual(row.built, 0,
                    "(e) a child given to a Component property through a wrapper's default alias is wrapped, not built — if not, what a closed ExpandingRow holds exists (and runs) while it is closed");
        assert(row.content instanceof Component, "(e) … it is a Component");
        row.open = true;
        assertEqual(row.built, 1, "(e) … built when the row opens");
        row.open = false;
        row.open = true;
        assertEqual(row.built, 2, "(e) … and anew each time");

        // (f) An item finds an enclosing one by walking up `parent` in a binding — at its
        // completion, also as a Loader's item and a Repeater's delegate — and the binding
        // follows a move under another parent (components/AnchorBlock.qml finds its
        // enclosing block, and the base a window or popup gives, this way)
        const tree = Qt.createQmlObject("import QtQuick\nimport Quickshell\nItem {\n"
            + "    id: top\n    property string anchorBase: \"settings.pin\"\n"
            + "    property alias direct: direct\n    property alias loader: loader\n    property alias repeater: repeater\n"
            + "    property alias other: other\n"
            + "    component Probe: Item {\n"
            + "        readonly property var enclosing: { for (let p = parent; p; p = p.parent) { if (typeof p.anchorBase === \"string\") return p; } return null; }\n"
            + "        property var atCompletion: null\n"
            + "        Component.onCompleted: atCompletion = enclosing\n"
            + "    }\n"
            + "    Column { Item { Probe { id: direct } } }\n"
            + "    Loader { id: loader; sourceComponent: Probe {} }\n"
            + "    Column { Repeater { id: repeater; model: ScriptModel { values: [{ k: 1 }, { k: 2 }]; objectProp: \"k\" } Probe {} } }\n"
            + "    Item { id: other; property string anchorBase: \"popup.pin\" }\n"
            + "}", suite, "AnchorWalkPin.qml");
        _held.push(tree);
        assert(tree.direct.atCompletion === tree, "(f) an item finds the enclosing one by walking up parent, already at its Component.onCompleted — if not, an anchor block has no path while it is built");
        assert(tree.loader.item?.atCompletion === tree && tree.loader.item.enclosing === tree, "(f) … as a Loader's item");
        const delegate = tree.repeater.itemAt(1);
        assert(delegate?.atCompletion === tree && delegate.enclosing === tree, "(f) … as a Repeater's delegate (on a ScriptModel)");
        tree.direct.parent = tree.other;
        assert(tree.direct.enclosing === tree.other, "(f) the walk is a binding: an item moved under another parent finds the new enclosing one — if not, a moved block keeps a stale path");

        // (g) ScriptModel given objects built anew at each step (a refetch) and an objectProp
        // replaces rows BY POSITION after the first key-equal one: a removal in the middle
        // destroys the LAST delegate and shifts the later items into the earlier delegates.
        // Views give it string keys instead (components/KeyedModel.qml); strings compare
        // strictly and go to the right rows. notes/upstream/quickshell-scriptmodel-replace.md
        const rows = values => Qt.createQmlObject("import QtQuick\nimport Quickshell\nItem {\n"
            + "    property alias model: model\n    property alias repeater: repeater\n"
            + "    Column { Repeater { id: repeater; model: ScriptModel { id: model" + values + " }\n"
            + "        Item { required property var modelData } } }\n"
            + "}", suite, "ScriptModelPin.qml");
        const objects = rows("; objectProp: \"id\"");
        _held.push(objects);
        objects.model.values = ["A", "B", "C", "D"].map(id => ({ id: id }));
        const objectRows = [0, 1, 2, 3].map(i => objects.repeater.itemAt(i));
        objects.model.values = ["A", "C", "D"].map(id => ({ id: id }));
        const wrongDelegate = objects.repeater.itemAt(1) === objectRows[1] && objects.repeater.itemAt(2) === objectRows[2];
        console.log("  INFO: ScriptModel with rebuilt objects, B removed from A,B,C,D: "
            + (wrongDelegate ? "B's delegate shows C and D's delegate went (the bug is there)" : "C and D keep their delegates (the bug is fixed)"));
        assert(wrongDelegate && objects.repeater.itemAt(1).modelData.id === "C",
               "(g) ScriptModel still overwrites rows by position for rebuilt objects — if this fails after an upgrade, Quickshell fixed it: KeyedModel is no longer needed for correctness, and the Repeater rule in CLAUDE.md can be relaxed");
        const keys = rows("");
        _held.push(keys);
        keys.model.values = ["A", "B", "C", "D"];
        const keyRows = [0, 1, 2, 3].map(i => keys.repeater.itemAt(i));
        keys.model.values = ["A", "C", "D"];
        assert(keys.repeater.itemAt(1) === keyRows[2] && keys.repeater.itemAt(2) === keyRows[3],
               "(g) … string values go to the right rows: B's delegate went, C and D kept theirs — if not, KeyedModel's keys are no fix");
        keys.model.values = ["D", "A", "X", "C"];
        assert(keys.repeater.itemAt(0) === keyRows[3] && keys.repeater.itemAt(1) === keyRows[0]
               && keys.repeater.itemAt(3) === keyRows[2] && keys.repeater.itemAt(2).modelData === "X",
               "(g) … and through a move and an insert");

        for (const object of _held)
            object.destroy();
        _held = [];
    }
}
