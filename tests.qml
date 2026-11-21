//@ pragma UseQApplication
import QtQuick
import qs.singletons
import qs.tests

// Run with: tests/run-unit.sh (in a private headless compositor: three suites open a window)
// Add new test suite components here as suites are created, one `property var _name:
// SomethingTest {…}` each: tests/run-unit.sh reads the suites, and which suites a suite is
// given, from these lines (tests/count-suites.sh). With suites named to the runner, the
// others are built and do not run (TestCase.selected).
QtObject {
    id: root

    // First, before any suite runs: the suites use the real Config singleton, whose
    // file is the user's
    readonly property bool _configReadOnly: { Config.readOnly = true; return true; }

    property var _promises: PromisesTest {}
    property var _fetch: FetchTest {}
    property var _network: NetworkTest {}
    property var _deviceAddressReading: DeviceAddressReadingTest {}
    property var _sleepLockersReading: SleepLockersReadingTest {}
    property var _vpnProviders: VpnProvidersTest {}
    property var _calendarDates: CalendarDatesTest {}
    property var _calendarEvents: CalendarEventsTest {}
    property var _widgetRegistry: WidgetRegistryTest {}
    property var _hardware: HardwareTest {}
    property var _profiles: ProfilesTest {}
    property var _polling: PollingTest {}
    property var _settingsPages: SettingsPagesTest {}
    property var _workspaces: WorkspacesTest {}
    property var _version: VersionTest {}
    property var _theme: ThemeTest {}
    property var _apiThemeTokens: ApiThemeTokensTest {}
    property var _format: FormatTest {}
    property var _addressRules: AddressRulesTest {}
    property var _systemFacts: SystemFactsTest {}
    property var _notifier: NotifierTest {}
    property var _scrollNotches: ScrollNotchesTest {}
    property var _curvePoints: CurvePointsTest {}
    property var _notificationMarkup: NotificationMarkupTest {}
    property var _roundedOutline: RoundedOutlineTest {}
    property var _coverColors: CoverColorsTest {}
    property var _playerRules: PlayerRulesTest {}
    property var _barText: BarTextTest {}
    property var _barGeometry: BarGeometryTest {}
    property var _pointerRules: PointerRulesTest {}
    property var _batteryRules: BatteryRulesTest {}
    property var _toastRules: ToastRulesTest {}
    property var _notificationRules: NotificationRulesTest {}
    property var _wallpaperRules: WallpaperRulesTest {}
    property var _polkitRules: PolkitRulesTest {}
    property var _privilegedRules: PrivilegedRulesTest {}
    property var _energyRules: EnergyRulesTest {}
    property var _lockRules: LockRulesTest {}
    property var _lockParseRules: LockParseRulesTest {}
    property var _lockViewRules: LockViewRulesTest {}
    property var _lockRecoveryRules: LockRecoveryRulesTest {}
    property var _lockIoRules: LockIoRulesTest {}
    property var _testSeamRules: TestSeamRulesTest {}
    property var _testSeamsShape: TestSeamsShapeTest {}
    property var _lockscreenShape: LockscreenShapeTest {}
    property var _testTree: TestTreeTest {}
    property var _pointerInput: PointerInputTest {}
    property var _buttonKinds: ButtonKindsTest {}
    property var _toastDrag: ToastDragTest {}
    property var _pillSizes: PillSizesTest {}
    property var _apiElements: ApiElementsTest {}
    property var _sidePanel: SidePanelTest {}
    property var _settingsModal: SettingsModalTest { after: _sidePanel }
    property var _statusPill: StatusPillTest {}
    property var _lockView: LockViewTest {}
    property var _authPromptView: AuthPromptViewTest {}
    property var _moduleRules: ModuleRulesTest {}
    property var _moduleInstallRules: ModuleInstallRulesTest {}
    property var _fileChooserRules: FileChooserRulesTest {}
    property var _fileChooser: FileChooserTest {}
    property var _commandRules: CommandRulesTest {}
    property var _commandRunner: CommandRunnerTest {}
    property var _listKeyRules: ListKeyRulesTest {}
    property var _moduleDependencyRules: ModuleDependencyRulesTest {}
    property var _moduleUpdateRules: ModuleUpdateRulesTest {}
    property var _keyedViews: KeyedViewsTest {}
    property var _settingsCard: SettingsCardTest {}
    property var _moduleContribution: ModuleContributionTest {}
    property var _networkCardGeometry: NetworkCardGeometryTest {}
    property var _quickshellPin: QuickshellPinTest {}
    property var _modules: ModulesTest {}
    property var _moduleIcon: ModuleIconTest {}
    property var _moduleRegistries: ModuleRegistriesTest { after: _modules; vpnSuite: _vpnProviders }
    property var _anchors: AnchorsTest { after: _moduleRegistries }
    property var _moduleInstaller: ModuleInstallerTest { after: _anchors }

    // The suites that run on the event loop (TestCase.asynchronous)
    readonly property var _asyncSuites: [_pointerInput, _toastDrag, _settingsCard, _moduleContribution, _networkCardGeometry, _buttonKinds, _pillSizes, _apiElements, _sidePanel, _settingsModal, _statusPill, _lockView, _authPromptView, _commandRunner, _systemFacts, _modules, _moduleIcon, _moduleRegistries, _anchors, _moduleInstaller, _vpnProviders, _testSeamsShape, _testTree, _deviceAddressReading, _sleepLockersReading, _network, _fileChooser]
    // How long an asynchronous suite may take, counted from the start of the suites, unless
    // it sets its own (TestCase.timeLimitMs); then it fails as timed out
    readonly property int _asyncLimitMs: 90000
    function timeLimitOf(suite) {
        return suite.timeLimitMs > 0 ? suite.timeLimitMs : _asyncLimitMs;
    }
    // FileChooserTest opens a real dialog, which takes the keyboard: it starts once the other
    // asynchronous suites are done, so that no key they send reaches it, nor its keys them.
    // It waits for them until the time it needs itself is all that is left of the limit, then
    // fails without opening a dialog. ModuleInstallerTest is not waited for: it opens no window
    // and sends no key, and runs long after the module suites it waits for itself.
    readonly property bool _chooserLast: {
        _fileChooser.waitFor = _asyncSuites.filter(suite => suite !== _fileChooser && suite !== _moduleInstaller);
        _fileChooser.waitLimitMs = timeLimitOf(_fileChooser) - _fileChooser.ownTimeMs;
        return true;
    }

    // Exit once the synchronous suites have run (all in Component.onCompleted) and the
    // asynchronous ones are done — each failed as timed out once past its own limit. A suite
    // that was not selected is done from the start.
    property var _quit: Timer {
        interval: 50
        running: true
        repeat: true
        property int _waited: 0
        onTriggered: {
            _waited += interval;
            const pending = _asyncSuites.filter(suite => !suite.done);
            for (const suite of pending) {
                if (_waited >= root.timeLimitOf(suite)) {
                    suite.fail("timed out (" + Math.round(root.timeLimitOf(suite) / 1000) + " s)");
                    suite.finish();
                }
            }
            if (pending.some(suite => !suite.done))
                return;
            Qt.quit();
        }
    }
}
