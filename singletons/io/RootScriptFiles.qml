import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// The shell's root scripts (scripts/root/, RootScriptRules.directory), read as text when a run
// is about to start: what is read is what goes to pkexec, never a copy kept from an earlier
// read. `names` in the order they are joined (a Rules' scriptFiles); read() → their texts, ""
// for a file missing or unreadable (RootScriptRules.script then refuses the run). The files are
// small and read on a click only, so the reads are synchronous.
QtObject {
    id: root

    property var names: []
    // The folder they are in; a suite points it elsewhere to see a missing file refused
    property string directory: Quickshell.shellDir + "/" + RootScriptRules.directory

    // A view of its own per read: nothing from an earlier read can stand in for a file gone
    function read() {
        return Array.from(names).map(name => {
            const view = _view.createObject(root, { path: root.directory + "/" + name });
            const text = String(view.text() ?? "");
            view.destroy();
            return text;
        });
    }

    property Component _view: Component {
        FileView {
            blockAllReads: true
            printErrors: false
        }
    }
}
