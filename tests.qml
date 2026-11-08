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
    property var _notificationMarkup: NotificationMarkupTest {}
    property var _roundedOutline: RoundedOutlineTest {}
    property var _coverColors: CoverColorsTest {}
    property var _playerRules: PlayerRulesTest {}
    property var _barGeometry: BarGeometryTest {}
    property var _pointerRules: PointerRulesTest {}
    property var _batteryRules: BatteryRulesTest {}
    property var _energyRules: EnergyRulesTest {}
    property var _pointerInput: PointerInputTest {}

    // The suites that run on the event loop (TestCase.asynchronous)
    readonly property var _asyncSuites: [_pointerInput]

    // Exit once the synchronous suites have run (all in Component.onCompleted) and the
    // asynchronous ones are done — or after a deadline, counting those as failed
    property var _quit: Timer {
        interval: 50
        running: true
        repeat: true
        property int _waited: 0
        onTriggered: {
            _waited += interval;
            const pending = _asyncSuites.filter(suite => !suite.done);
            if (pending.length > 0 && _waited < 20000)
                return;
            pending.forEach(suite => {
                suite.fail("timed out");
                suite.finish();
            });
            Qt.quit();
        }
    }
}
