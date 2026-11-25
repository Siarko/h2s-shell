import QtQuick
import qs.api

// What the module's store held when its main was made: the host runs its migrations before
// (the settings first, then the store), so it sees it migrated
QtObject {
    property var module: null
    property var seen: null

    Component.onCompleted: seen = { folders: module.store.get("folders"), hostile: module.store.get("hostile", null) }
}
