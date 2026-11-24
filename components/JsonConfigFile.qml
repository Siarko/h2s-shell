import QtQuick
import Quickshell.Io
import qs.singletons

// A JSON file read and written through a JsonAdapter, whose save() keeps the top-level keys
// the file held when it was loaded that the adapter does not declare. JsonAdapter writes only
// what it declares, so without this an older shell saving the config drops every key a newer
// one added (MigrationRules.keepUndeclaredKeys decides what is put back).
//
// Writes are synchronous: save() reads back what the adapter wrote to find the keys it lacks.
// The adapter's text is written first and the kept keys right after, each write atomic; when
// nothing is to be kept, the adapter's write is the only one.
FileView {
    id: root

    // The file as it was last loaded: where the undeclared keys come from at each save
    property string loadedText: ""

    blockWrites: true

    onLoaded: loadedText = text()
    onLoadFailed: loadedText = ""

    function save() {
        writeAdapter();
        const kept = MigrationRules.keepUndeclaredKeys(text(), loadedText);
        if (kept !== "")
            setText(kept);
    }
}
