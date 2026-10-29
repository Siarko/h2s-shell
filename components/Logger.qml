import Quickshell
import QtQuick
import qs.singletons

Item {
    id: root

    property string prefix: ""
    property bool enabled: Profiles.value("general.debug") ?? false
    property int level: 3

    function log() {
        if (root.enabled && level > 2) {
            console.log(root.prefix, ...arguments);
        }
    }

    function warn() {
        if (root.enabled && level > 1) {
            console.warn(root.prefix, ...arguments);
        }
    }

    function error() {
        console.error(root.prefix, ...arguments);
    }
}
