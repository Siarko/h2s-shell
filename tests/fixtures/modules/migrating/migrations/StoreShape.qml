import QtQuick

// The store's folders, once a ":"-separated text, become a list
QtObject {
    readonly property string summary: "Folders are a list"

    function migrate(part, context) {
        if (typeof part.store.folders === "string")
            part.store.folders = part.store.folders.split(":").filter(folder => folder !== "");
        return part;
    }
}
