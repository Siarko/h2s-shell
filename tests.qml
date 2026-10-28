//@ pragma UseQApplication
import QtQuick
import qs.tests

// Run with: quickshell -p tests.qml
// Add new test suite components here as suites are created.
QtObject {
    property var _promises: PromisesTest {}
    property var _fetch: FetchTest {}
    property var _network: NetworkTest {}
    property var _calendarDates: CalendarDatesTest {}
    property var _widgetRegistry: WidgetRegistryTest {}
    property var _hardware: HardwareTest {}

    // Exit after all Component.onCompleted handlers finish.
    // interval:0 fires on the next event loop tick, after all suites have run.
    property var _quit: Timer {
        interval: 0
        running: true
        onTriggered: Qt.quit()
    }
}
