pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: systemTray

    property var menuHandle: null
    property int lastItemIndex: 0
    property int slideDirection: 1

    function calculateDirection(index) {
        systemTray.slideDirection = lastItemIndex > index ? -1 : 1;
        systemTray.lastItemIndex = index;
    }
}
