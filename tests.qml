//@ pragma UseQApplication
import QtQuick
import qs.singletons
import qs.tests

// Run with: quickshell -p tests.qml
// Add new test suite components here as suites are created.
QtObject {
    // First, before any suite runs: the suites use the real Config singleton, whose
    // file is the user's
    readonly property bool _configReadOnly: { Config.readOnly = true; return true; }

    property var _promises: PromisesTest {}
    property var _fetch: FetchTest {}
    property var _network: NetworkTest {}
    property var _calendarDates: CalendarDatesTest {}
    property var _widgetRegistry: WidgetRegistryTest {}
    property var _hardware: HardwareTest {}
    property var _profiles: ProfilesTest {}
    property var _polling: PollingTest {}
    property var _settingsPages: SettingsPagesTest {}
    property var _workspaces: WorkspacesTest {}
    property var _version: VersionTest {}
    property var _theme: ThemeTest {}
    property var _format: FormatTest {}
    property var _scrollNotches: ScrollNotchesTest {}
    property var _curvePoints: CurvePointsTest {}

    // Exit after all Component.onCompleted handlers finish.
    // interval:0 fires on the next event loop tick, after all suites have run.
    property var _quit: Timer {
        interval: 0
        running: true
        onTriggered: Qt.quit()
    }
}
