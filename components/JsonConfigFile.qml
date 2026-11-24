import QtQuick
import Quickshell.Io
import qs.singletons

// A JSON file read and written through a JsonAdapter, whose save() keeps the keys the file
// held that the adapter does not declare: top-level keys, and keys inside a declared
// JsonObject (MigrationRules.keepUndeclaredKeys decides what is kept). JsonAdapter writes
// only what it declares, so without this an older shell saving the config drops every key a
// newer one added.
//
// A file with no such keys is written by the adapter itself, as JsonAdapter alone writes it.
// One with such keys is written once, atomically, as the adapter's content (serialized here
// the way JsonAdapter does: Quickshell has no way to serialize an adapter without writing
// the file) with the kept keys added.
FileView {
    id: root

    // The file as last read or written: where the undeclared keys come from at each save.
    // Something else that writes the file without reloading it hands its text to written()
    property string loadedText: ""

    onLoaded: loadedText = text()
    onLoadFailed: loadedText = ""

    // The file now holds `text`, written by something other than save() (a migration, a
    // restore): the keys this adapter does not declare are kept from it from now on, so a
    // key it removed does not come back
    function written(text) {
        loadedText = typeof text === "string" ? text : "";
    }

    function save() {
        if (!adapter)
            return;
        const kept = MigrationRules.keepUndeclaredKeys(JSON.stringify(serialized()), loadedText);
        if (kept === "") {
            writeAdapter();
            return;
        }
        setText(kept);
        loadedText = kept;
    }

    // The content as it stands (the adapter's, with the kept keys), as a save would write it
    function currentText() {
        const written = JSON.stringify(serialized());
        const kept = MigrationRules.keepUndeclaredKeys(written, loadedText);
        return kept !== "" ? kept : written;
    }

    // Sets the adapter's declared properties to `content`'s values (a plain object as the file
    // would hold it; a declared JsonObject from an object, key by key): what another writer put
    // in the file reaches the adapter without reading it again
    function apply(content) {
        if (adapter)
            _apply(adapter, content);
    }

    function _apply(target, content) {
        if (content === null || typeof content !== "object" || Array.isArray(content))
            return;
        const declared = _plain(target, true);
        for (const key of Object.keys(content)) {
            if (!Object.prototype.hasOwnProperty.call(declared, key))
                continue;
            if (_isQObject(target[key])) {
                _apply(target[key], content[key]);
                continue;
            }
            if (JSON.stringify(declared[key]) !== JSON.stringify(content[key]))
                target[key] = content[key];
        }
    }

    // The adapter's content as JsonAdapter writes it: every property it declares (a QML
    // object's own properties, not objectName, no functions or signals), a JsonObject as an
    // object, a list as a list
    function serialized() {
        return _plain(adapter, true);
    }

    function _isQObject(value) {
        return value !== null && typeof value === "object" && typeof value.objectName === "string" && typeof value.destroy === "function";
    }

    function _plain(value, isObject) {
        if (value === undefined || value === null)
            return null;
        if (isObject || _isQObject(value)) {
            const object = {};
            for (const key of Object.keys(value).sort()) {
                if (key === "objectName" || typeof value[key] === "function")
                    continue;
                object[key] = _plain(value[key], false);
            }
            return object;
        }
        if (typeof value === "object" && typeof value.length === "number")
            return Array.from(value, item => _plain(item, false));
        if (typeof value === "object")
            return JSON.parse(JSON.stringify(value));
        return value;
    }
}
