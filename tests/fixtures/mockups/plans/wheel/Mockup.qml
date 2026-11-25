import QtQuick
import qs.singletons
import qs.singletons.googlecalendar
import qs.panels.calendar
import qs.mockups.kit

// A fixture plan for tests/run-mockups-selftest.sh's real wheel: the event form's colour row
// (EventColorRow), narrower than its swatches, put under the pointer wherever it enters.
// Prints "WHEEL-ROW <contentX>" as the row scrolls.
MockupWindow {
    id: root
    contentWidth: 400
    contentHeight: 200

    Component.onCompleted: {
        const colors = {};
        for (let i = 1; i <= 11; i++)
            colors[String(i)] = Qt.hsla(i / 11, 0.6, 0.5, 1).toString();
        GoogleCalendar.eventColors = colors;
    }

    Rectangle {
        width: root.contentWidth
        height: root.contentHeight
        color: Theme.surface

        // Where the pointer is: the row is put under it (the window's place on the screen,
        // its title bar among it, is the compositor's)
        HoverHandler {
            id: pointer
        }
    }

    EventColorRow {
        id: row
        width: 120
        x: Math.max(0, Math.min(root.contentWidth - width, pointer.point.position.x - width / 2))
        y: Math.max(0, Math.min(root.contentHeight - height, pointer.point.position.y - 12))

        readonly property real scrolled: children[0].contentX
        onScrolledChanged: console.info("WHEEL-ROW " + Math.round(scrolled))
    }
}
